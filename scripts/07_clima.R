# Clima y lechería: agrega el clima a áreas de enumeración y departamentos,
# construye series de la «cuenca lechera» ponderadas por producción y estima la
# asociación entre anomalías climáticas y la remisión mensual de INALE.
#
# Entradas: data-raw/clima/ (06_download_clima.R), data/atlas.rds (03_prepare.R),
#           data-raw/oficial/inale_remision_a_planta.xls
# Salidas:  data/clima.rds, data/clima_mensual_cuenca.csv, data/clima_ejercicios_*.csv
#
# Uso: Rscript scripts/07_clima.R

source("scripts/_common.R")
suppressPackageStartupMessages({ library(sf); library(terra); library(tidyr) })
sf_use_s2(FALSE)

checks <- list()
check <- function(id, ok, detalle, nivel = "control") {
  checks[[length(checks) + 1]] <<- list(id = id, ok = isTRUE(ok), detalle = detalle, nivel = nivel)
  msg(if (nivel == "aviso") "  ⚠ " else if (isTRUE(ok)) "  ✓ " else "  ✗ ", id, " — ", detalle)
}

atlas <- readRDS(file.path(DIR_DATA, "atlas.rds"))
dir_cl <- file.path(DIR_RAW, "clima")
THI_UMBRAL <- 72   # umbral habitual de estrés térmico leve en vacas lecheras
NORMAL <- 1991:2020

# Geometrías originales (sin simplificar) ------------------------------------
ae <- st_read(file.path(DIR_RAW, "geo", "ae_mgap.geojson"), quiet = TRUE) |>
  transmute(id = sprintf("%07d", as.integer(CCOMPAE))) |> st_make_valid() |>
  group_by(id) |> summarise(.groups = "drop")
dep <- st_read(file.path(DIR_RAW, "geo", "departamentos.geojson"), quiet = TRUE)
dep <- dep[toupper(dep$NOMBRE) != "LIMITE CONTESTADO", ] |> st_make_valid()
dep$id <- sprintf("%02d", as.integer(dep$DEPTO))   # la capa usa la nomenclatura INE
dep <- dep |> group_by(id) |> summarise(.groups = "drop")
stopifnot(!anyNA(dep$id), nrow(dep) == 19)

# 1. CHIRPS: lluvia mensual por área -------------------------------------------
msg("CHIRPS")
r <- rast(file.path(dir_cl, "chirps_v2_mensual_uruguay.nc"))
# La consulta pide desde enero de 1991; cada capa es un mes consecutivo.
meses <- seq(as.Date("1991-01-01"), by = "month", length.out = nlyr(r))
ultimo <- max(meses)
check("chirps_periodo", ultimo <= Sys.Date() && ultimo >= seq(Sys.Date(), by = "-4 months", length.out = 2)[2],
      sprintf("%d meses, enero 1991 – %s (último mes publicado)", nlyr(r), format(ultimo, "%m/%Y")))
check("chirps_valores", all(global(r, "min", na.rm = TRUE)$min >= 0),
      "Precipitación no negativa (mm/mes)")

extract_monthly <- function(polys) {
  v <- terra::extract(r, vect(polys), fun = mean, exact = TRUE, na.rm = TRUE, ID = FALSE)
  m <- as.matrix(v)
  tibble(id = rep(polys$id, times = ncol(m)),
         fecha = rep(meses, each = nrow(m)),
         lluvia = as.vector(m))
}
ll_ae  <- extract_monthly(ae)
ll_dep <- extract_monthly(dep)
check("chirps_cobertura_ae", mean(!is.na(ll_ae$lluvia)) > 0.999,
      sprintf("%.2f %% de valores área-mes con dato", 100 * mean(!is.na(ll_ae$lluvia))))

# 2. NASA POWER: THI diario y humedad del suelo por celda ----------------------
msg("NASA POWER")
read_power <- function(param) {
  fs <- Sys.glob(file.path(dir_cl, "power", paste0(param, "_*.json")))
  bind_rows(lapply(fs, function(f) {
    j <- fromJSON(f, simplifyVector = FALSE)
    bind_rows(lapply(j$features, function(ft) {
      vals <- unlist(ft$properties$parameter[[param]])
      tibble(lon = ft$geometry$coordinates[[1]], lat = ft$geometry$coordinates[[2]],
             fecha = as.Date(names(vals), "%Y%m%d"), valor = as.numeric(vals))
    }))
  })) |> mutate(valor = ifelse(valor <= -999, NA, valor))
}
t2m <- read_power("T2M"); rh <- read_power("RH2M"); gw <- read_power("GWETROOT")
pw <- t2m |> rename(t = valor) |>
  inner_join(rh |> rename(rh = valor), by = c("lon", "lat", "fecha")) |>
  inner_join(gw |> rename(gw = valor), by = c("lon", "lat", "fecha")) |>
  mutate(thi = (1.8 * t + 32) - (0.55 - 0.0055 * rh) * (1.8 * t - 26))
check("power_valores", all(pw$rh >= 0 & pw$rh <= 100, na.rm = TRUE) && all(pw$gw >= 0 & pw$gw <= 1, na.rm = TRUE),
      sprintf("%s registros celda-día, %s – %s; humedad relativa 0–100 %%, humedad del suelo 0–1",
              format(nrow(pw), big.mark = "."), min(pw$fecha), max(pw$fecha)))
pw_m <- pw |> mutate(mes = as.Date(format(fecha, "%Y-%m-01"))) |>
  group_by(lon, lat, mes) |>
  summarise(dias = sum(!is.na(thi)), thi_dias = sum(thi >= THI_UMBRAL, na.rm = TRUE),
            gw = mean(gw, na.rm = TRUE), t = mean(t, na.rm = TRUE), .groups = "drop") |>
  filter(dias >= 25)                           # solo meses completos
cells <- pw_m |> distinct(lon, lat) |> mutate(cell = row_number())
pw_m <- pw_m |> left_join(cells, by = c("lon", "lat"))
cells_sf <- st_as_sf(cells, coords = c("lon", "lat"), crs = 4326)

# Cada área toma la celda POWER más cercana a un punto interior (resolución ~55 km).
cell_of <- function(polys) {
  pts <- suppressWarnings(st_point_on_surface(polys))
  tibble(id = polys$id, cell = cells$cell[st_nearest_feature(pts, cells_sf)])
}
pw_ae  <- cell_of(ae)  |> inner_join(pw_m, by = "cell", relationship = "many-to-many")
pw_dep <- cell_of(dep) |> inner_join(pw_m, by = "cell", relationship = "many-to-many")

# 3. Indicadores por ejercicio (1 jul – 30 jun) --------------------------------
ejercicio_de <- function(f) as.integer(format(f, "%Y")) + (as.integer(format(f, "%m")) >= 7)
by_ejercicio <- function(ll, pwx) {
  a <- ll |> mutate(ejercicio = ejercicio_de(fecha)) |>
    group_by(id, ejercicio) |> summarise(n = sum(!is.na(lluvia)), lluvia = sum(lluvia), .groups = "drop") |>
    filter(n == 12)
  normal <- a |> filter(ejercicio %in% (NORMAL + 1)) |> group_by(id) |>
    summarise(lluvia_normal = mean(lluvia))
  b <- pwx |> mutate(ejercicio = ejercicio_de(mes)) |>
    group_by(id, ejercicio) |> summarise(n_pw = n(), thi_dias = sum(thi_dias), gw = mean(gw), .groups = "drop") |>
    filter(n_pw == 12)
  gnorm <- b |> filter(ejercicio <= 2025) |> group_by(id) |> summarise(gw_m = mean(gw), gw_s = sd(gw))
  a |> left_join(normal, by = "id") |>
    mutate(lluvia_anom = 100 * (lluvia - lluvia_normal) / lluvia_normal) |>
    left_join(b, by = c("id", "ejercicio")) |> left_join(gnorm, by = "id") |>
    mutate(gw_z = (gw - gw_m) / gw_s) |>
    select(id, ejercicio, lluvia, lluvia_normal, lluvia_anom, thi_dias, gw, gw_z)
}
ej_ae  <- by_ejercicio(ll_ae, pw_ae)
ej_dep <- by_ejercicio(ll_dep, pw_dep)
check("clima_ejercicios_atlas", all(atlas$years %in% ej_ae$ejercicio[!is.na(ej_ae$thi_dias)]),
      sprintf("Lluvia y estrés térmico disponibles para los ejercicios %s", paste(atlas$years, collapse = ", ")))

# 4. Cuenca lechera: series mensuales ponderadas por producción --------------
w <- atlas$values$ae |> group_by(id) |> summarise(w = mean(prod)) |> filter(w > 0)
check("pesos_cuenca", nrow(w) > 300, sprintf("%d áreas con producción ponderan el clima de la cuenca", nrow(w)))
cuenca <- ll_ae |> inner_join(w, by = "id") |> group_by(fecha) |>
  summarise(lluvia = weighted.mean(lluvia, w, na.rm = TRUE)) |>
  left_join(pw_ae |> inner_join(w, by = "id") |> group_by(fecha = mes) |>
              summarise(thi_dias = weighted.mean(thi_dias, w), gw = weighted.mean(gw, w),
                        t = weighted.mean(t, w)), by = "fecha") |>
  mutate(mes = as.integer(format(fecha, "%m")), anio = as.integer(format(fecha, "%Y"))) |>
  arrange(fecha)
nm <- cuenca |> filter(anio %in% NORMAL) |> group_by(mes) |> summarise(lluvia_n = mean(lluvia))
gm <- cuenca |> filter(anio %in% 2001:2025) |> group_by(mes) |>
  summarise(gw_m = mean(gw, na.rm = TRUE), gw_s = sd(gw, na.rm = TRUE), thi_m = mean(thi_dias, na.rm = TRUE))
roll <- function(x, k) as.numeric(stats::filter(x, rep(1, k), sides = 1))
cuenca <- cuenca |> left_join(nm, by = "mes") |> left_join(gm, by = "mes") |>
  mutate(gw_z = (gw - gw_m) / gw_s,
         lluvia3_anom = 100 * (roll(lluvia, 3) / roll(lluvia_n, 3) - 1),
         lluvia6_anom = 100 * (roll(lluvia, 6) / roll(lluvia_n, 6) - 1),
         thi_anom = thi_dias - thi_m)

# 5. Remisión INALE y análisis -------------------------------------------------
msg("Análisis con la remisión de INALE")
x <- readxl::read_excel(file.path(DIR_RAW, "oficial", "inale_remision_a_planta.xls"),
                        sheet = 1, col_names = FALSE, .name_repair = "minimal")
hdr <- which(trimws(as.character(x[[1]])) %in% c("Año/ Mes", "Año/Mes"))[1]
yrs <- suppressWarnings(as.integer(unlist(x[hdr, -1])))
MESES <- c("Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto",
           "Setiembre", "Octubre", "Noviembre", "Diciembre")
rws <- match(MESES, trimws(as.character(x[[1]])))
rem <- expand_grid(mes = 1:12, j = seq_along(yrs)) |>
  mutate(anio = yrs[j], remision = mapply(function(m, j) suppressWarnings(as.numeric(x[[j + 1]][rws[m]])), mes, j)) |>
  filter(!is.na(anio), !is.na(remision)) |>
  transmute(fecha = as.Date(sprintf("%d-%02d-01", anio, mes)), remision) |> arrange(fecha)

ma12 <- function(x) as.numeric(stats::filter(x, rep(1 / 12, 12), sides = 1))
sum12 <- function(x) as.numeric(stats::filter(x, rep(1, 12), sides = 1))
d <- rem |> inner_join(cuenca, by = "fecha") |> arrange(fecha) |>
  mutate(d_rem = 100 * (log(remision) - lag(log(remision), 12)),
         # Condiciones de los últimos 12 meses frente a los 12 anteriores.
         gw12 = ma12(gw_z), d_gw12 = gw12 - lag(gw12, 12),
         ll12 = 100 * (sum12(lluvia) / sum12(lluvia_n) - 1), d_ll12 = ll12 - lag(ll12, 12),
         thi12 = sum12(thi_dias), d_thi12 = thi12 - lag(thi12, 12))
check("serie_analisis", sum(!is.na(d$d_rem) & !is.na(d$d_gw12)) > 200,
      sprintf("%d meses con remisión y clima (%s – %s)", sum(!is.na(d$d_rem) & !is.na(d$d_gw12)),
              format(min(d$fecha[!is.na(d$d_rem) & !is.na(d$d_gw12)]), "%m/%Y"), format(max(d$fecha[!is.na(d$d_gw12)]), "%m/%Y")))

# Errores estándar de Newey–West (núcleo de Bartlett) para series autocorrelacionadas.
nw_se <- function(fit, L = 18) {
  X <- model.matrix(fit); e <- residuals(fit); n <- nrow(X)
  S <- crossprod(X * e)
  for (l in seq_len(L)) {
    wl <- 1 - l / (L + 1)
    G <- crossprod(X[(l + 1):n, , drop = FALSE] * e[(l + 1):n], X[1:(n - l), , drop = FALSE] * e[1:(n - l)])
    S <- S + wl * (G + t(G))
  }
  B <- solve(crossprod(X))
  sqrt(diag(B %*% S %*% B))
}
# Intervalo de la correlación por bootstrap de bloques móviles de 24 meses.
set.seed(20260925)
block_ci <- function(a, b, B = 1000, L = 24) {
  ok <- !is.na(a) & !is.na(b); a <- a[ok]; b <- b[ok]; n <- length(a)
  starts <- seq_len(n - L + 1)
  rs <- replicate(B, { idx <- unlist(lapply(sample(starts, ceiling(n / L), TRUE), function(s) s:(s + L - 1)))[1:n]; cor(a[idx], b[idx]) })
  unname(quantile(rs, c(0.025, 0.975)))
}
# Rezago positivo: el clima precede a la remisión. Negativo: placebo (clima posterior).
shiftv <- function(v, k) if (k == 0) v else if (k > 0) c(rep(NA, k), head(v, -k)) else c(tail(v, k), rep(NA, -k))

VARS <- c(d_gw12 = "Humedad del suelo (12 meses)", d_ll12 = "Lluvia (12 meses)", d_thi12 = "Días de estrés térmico (12 meses)")
rezagos <- bind_rows(lapply(names(VARS), function(v) bind_rows(lapply(seq(-12, 24, 3), function(k) {
  xv <- shiftv(d[[v]], k); ci <- block_ci(d$d_rem, xv)
  tibble(variable = v, etiqueta = VARS[[v]], rezago = k, r = cor(d$d_rem, xv, use = "complete.obs"),
         lo = ci[1], hi = ci[2], n = sum(!is.na(d$d_rem) & !is.na(xv)))
}))))
best <- rezagos |> filter(variable == "d_gw12", rezago >= 0, rezago <= 18) |> slice_max(r, n = 1)
placebo <- rezagos |> filter(variable == "d_gw12", rezago < 0)
msg(sprintf("  Humedad del suelo 12 m: mayor correlación a %d meses (r = %.2f; IC 95 %% %.2f a %.2f)",
            best$rezago, best$r, best$lo, best$hi))
# Las ventanas de 12 meses se solapan entre rezagos: el perfil mensual es solo
# descriptivo. La inferencia se hace con ejercicios anuales y con el panel de áreas.
check("perfil_mensual_placebo", TRUE, nivel = "aviso",
      sprintf("Perfil mensual solo descriptivo: con clima posterior (placebo) |r| llega a %.2f, frente a %.2f con clima anterior (ventanas solapadas)",
              max(abs(placebo$r)), best$r))
ll_best <- rezagos |> filter(variable == "d_ll12", rezago >= 0, rezago <= 18) |> slice_max(r, n = 1)
check("robustez_lluvia_chirps", ll_best$r > 0.2,
      sprintf("Con lluvia CHIRPS (fuente independiente) el máximo es r = %.2f a %d meses", ll_best$r, ll_best$rezago),
      nivel = if (ll_best$r > 0.2) "control" else "aviso")

# Nivel nacional anual (ejercicios julio–junio, sin solapamiento) ------------
ej_nac <- rem |> mutate(ejercicio = ejercicio_de(fecha)) |> group_by(ejercicio) |>
  summarise(remision = sum(remision), n = n()) |> filter(n == 12) |>
  inner_join(cuenca |> mutate(ejercicio = ejercicio_de(fecha)) |> group_by(ejercicio) |>
               summarise(lluvia_anom = 100 * (sum(lluvia) / sum(lluvia_n) - 1), gw_z = mean(gw_z),
                         thi_dias = sum(thi_dias), n2 = n()) |> filter(n2 == 12), by = "ejercicio") |>
  arrange(ejercicio) |>
  mutate(d_rem = 100 * log(remision / lag(remision)),
         lluvia_prev = lag(lluvia_anom), lluvia_sig = lead(lluvia_anom))
cor_nac <- tibble(
  predictor = c("Lluvia del mismo ejercicio", "Lluvia del ejercicio anterior", "Lluvia del ejercicio siguiente (placebo)",
                "Humedad del suelo del mismo ejercicio", "Días de estrés térmico del mismo ejercicio"),
  r = c(cor(ej_nac$d_rem, ej_nac$lluvia_anom, use = "c"), cor(ej_nac$d_rem, ej_nac$lluvia_prev, use = "c"),
        cor(ej_nac$d_rem, ej_nac$lluvia_sig, use = "c"), cor(ej_nac$d_rem, ej_nac$gw_z, use = "c"),
        cor(ej_nac$d_rem, ej_nac$thi_dias, use = "c")))
n_nac <- sum(!is.na(ej_nac$d_rem))
# Con n ≈ 23, |r| < 0,41 no es distinguible de cero al 5 %.
r_crit <- { tq <- qt(0.975, n_nac - 2); tq / sqrt(n_nac - 2 + tq^2) }
check("nacional_anual", TRUE, nivel = "aviso",
      sprintf("Nacional, %d ejercicios: ninguna asociación supera |r| = %.2f (umbral 5 %%): %s",
              n_nac, r_crit, paste(sprintf("%.2f", cor_nac$r), collapse = ", ")))
print(cor_nac)

# Episodios secos: humedad del suelo de 12 meses por debajo de −1 desvío.
rl <- rle(!is.na(d$gw12) & d$gw12 < -1)
ends <- cumsum(rl$lengths); starts <- ends - rl$lengths + 1
ep <- tibble(ini = d$fecha[starts], fin = d$fecha[ends], meses = rl$lengths, seco = rl$values) |>
  filter(seco, meses >= 3) |> select(-seco)
ep$rem_durante <- mapply(function(a, b) mean(d$d_rem[d$fecha >= a & d$fecha <= b], na.rm = TRUE), ep$ini, ep$fin)
ep$rem_despues <- mapply(function(b) { w <- d$d_rem[d$fecha > b & d$fecha <= seq(b, by = "12 months", length.out = 2)[2]]
  if (sum(!is.na(w)) >= 6) mean(w, na.rm = TRUE) else NA_real_ }, ep$fin)
msg("  Episodios secos en la cuenca: ", nrow(ep)); print(ep)

# 5b. Panel por área (DICOSE 2022–2025) ------------------------------------------
# Cambio de producción de cada área frente a la lluvia de su territorio, con
# efectos fijos por ejercicio: se compara dentro de cada año (precios, costos y
# shocks nacionales quedan absorbidos). Ponderado por la producción previa.
va <- atlas$values$ae |> select(id, ejercicio, prod, prod_prev, prod_chg) |>
  filter(!is.na(prod_prev), prod_prev >= 1e6) |>
  mutate(chg = 100 * (prod - prod_prev) / prod_prev) |>
  left_join(ej_ae |> select(id, ejercicio, lluvia_anom, thi_dias), by = c("id", "ejercicio")) |>
  left_join(ej_ae |> transmute(id, ejercicio = ejercicio + 1L, lluvia_prev = lluvia_anom), by = c("id", "ejercicio")) |>
  left_join(ej_ae |> transmute(id, ejercicio = ejercicio - 1L, lluvia_sig = lluvia_anom), by = c("id", "ejercicio")) |>
  filter(!is.na(lluvia_anom), !is.na(lluvia_prev), !is.na(lluvia_sig))
panel_fit <- function(f) {
  fit <- lm(f, data = va, weights = prod_prev)
  X <- model.matrix(fit); e <- residuals(fit); wv <- weights(fit)
  Bm <- solve(crossprod(X * sqrt(wv)))
  meat <- Reduce(`+`, lapply(split(seq_along(e), va$id), function(ix) {
    u <- crossprod(X[ix, , drop = FALSE] * wv[ix], e[ix]); u %*% t(u) }))
  G <- length(unique(va$id)); k <- ncol(X); n <- nrow(X)
  se <- sqrt(diag(Bm %*% meat %*% Bm) * G / (G - 1) * (n - 1) / (n - k))
  tibble(termino = names(coef(fit)), estimado = coef(fit), se = se,
         lo = coef(fit) - 1.96 * se, hi = coef(fit) + 1.96 * se) |> filter(!grepl("factor|Intercept", termino))
}
coef_ae <- panel_fit(chg ~ lluvia_anom + lluvia_prev + thi_dias + factor(ejercicio))
coef_placebo <- panel_fit(chg ~ lluvia_sig + factor(ejercicio))
print(coef_ae, digits = 3); print(coef_placebo, digits = 3)
sig <- function(cf, t) { r <- cf[cf$termino == t, ]; r$lo > 0 | r$hi < 0 }
check("panel_areas", TRUE, nivel = "aviso",
      sprintf("Áreas (%d obs., %d áreas, efectos fijos por ejercicio): +10 pp de lluvia del mismo ejercicio → %+.2f %% (IC %.2f a %.2f); del ejercicio anterior → %+.2f %% (IC %.2f a %.2f); placebo ejercicio siguiente → %+.2f %% (IC %.2f a %.2f)",
              nrow(va), n_distinct(va$id),
              10 * coef_ae$estimado[1], 10 * coef_ae$lo[1], 10 * coef_ae$hi[1],
              10 * coef_ae$estimado[2], 10 * coef_ae$lo[2], 10 * coef_ae$hi[2],
              10 * coef_placebo$estimado[1], 10 * coef_placebo$lo[1], 10 * coef_placebo$hi[1]))

# 6. Guardado ---------------------------------------------------------------
clima <- list(
  version = format(Sys.time(), "%Y-%m-%d"), thi_umbral = THI_UMBRAL, normal = range(NORMAL),
  chirps_ultimo = ultimo, power_ultimo = max(pw$fecha),
  ejercicios = list(ae = ej_ae, dep = ej_dep),
  cuenca = cuenca, analisis = d, rezagos = rezagos, mejor_rezago = best,
  nacional_anual = list(datos = ej_nac, cor = cor_nac, n = n_nac, r_crit = r_crit),
  panel_areas = list(coefs = coef_ae, placebo = coef_placebo, n = nrow(va), areas = n_distinct(va$id)),
  episodios = ep, checks = checks,
  fuentes = list(
    chirps = "Funk et al. (2015), CHIRPS v2.0 — Climate Hazards Center, UC Santa Barbara; recorte vía IRI Data Library.",
    power = "NASA Langley Research Center, POWER Project (MERRA-2), datos diarios, comunidad AG."
  )
)
saveRDS(clima, file.path(DIR_DATA, "clima.rds"), compress = "xz")
write_csv(cuenca |> select(fecha, lluvia, lluvia_n, lluvia3_anom, lluvia6_anom, gw, gw_z, thi_dias, t),
          file.path(DIR_DATA, "clima_mensual_cuenca.csv"), na = "")
write_csv(ej_ae |> filter(ejercicio >= 2021), file.path(DIR_DATA, "clima_ejercicios_areas.csv"), na = "")
write_csv(ej_dep |> filter(ejercicio >= 2021), file.path(DIR_DATA, "clima_ejercicios_departamentos.csv"), na = "")
msg(sprintf("clima.rds: %.1f MB — %d controles, %d fallidos", file.size(file.path(DIR_DATA, "clima.rds")) / 1e6,
            length(checks), sum(!vapply(checks, `[[`, logical(1), "ok"))))
