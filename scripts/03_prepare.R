# Construye la base territorial comparable y los indicadores del atlas a partir
# de los originales en data-raw/. No descarga nada.
#
# Salidas:
#   data/atlas.rds          objeto único que carga la app (geometrías simplificadas,
#                           valores, escalas fijas, metadatos y diagnóstico)
#   data/indicadores_*.csv  tablas abiertas y legibles con los mismos valores
#   data/validacion.json    resultados de los controles (lo usa 04_validate.R)
#
# Uso: Rscript scripts/03_prepare.R

source("scripts/_common.R")
suppressPackageStartupMessages({
  library(sf)
  library(tidyr)
  library(rmapshaper)
})
sf_use_s2(FALSE)   # operaciones planas sobre coordenadas proyectadas

man <- read_manifest()
if (is.null(man)) stop("Falta data-raw/manifest.csv: ejecute primero 01 y 02.")

checks <- list()
check <- function(id, ok, detalle) {
  checks[[length(checks) + 1]] <<- list(id = id, ok = isTRUE(ok), detalle = detalle)
  msg(if (isTRUE(ok)) "  ✓ " else "  ✗ ", id, " — ", detalle)
}

# Utilidades ---------------------------------------------------------------

norm_name <- function(x) {
  x <- toupper(iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT"))
  x <- gsub("['`^~\"]", "", x)
  trimws(gsub("\\s+", " ", x))
}

# Los archivos de metadatos llegan en UTF-8, Latin-1 o CP850 según el año.
read_text_any <- function(path) {
  raw <- readBin(path, "raw", file.size(path))
  txt <- rawToChar(raw)
  if (validUTF8(txt)) return(txt)
  cands <- c("latin1", "CP850")
  score <- sapply(cands, function(enc) {
    t <- iconv(txt, from = enc, to = "UTF-8")
    lengths(regmatches(t, gregexpr("[áéíóúñÁÉÍÓÚÑ]", t))) -
      10 * lengths(regmatches(t, gregexpr("[¢µ¡£¤]", t)))
  })
  iconv(txt, from = cands[which.max(score)], to = "UTF-8")
}

read_meta <- function(path) {
  df <- read_delim(I(read_text_any(path)), delim = ";",
                   col_types = cols(.default = col_character()),
                   show_col_types = FALSE, progress = FALSE)
  names(df) <- trimws(names(df))
  df
}

resource_path <- function(year, name_exact) {
  r <- man |>
    filter(fuente == "dicose", ejercicio == as.character(year),
           norm_name(recurso_nombre) == norm_name(name_exact), !is.na(archivo), archivo != "")
  if (!nrow(r)) return(NA_character_)
  file.path(PROJECT_ROOT, r$archivo[1])
}

# 1. Cartografía -------------------------------------------------------------
msg("Cartografía")
ae_raw  <- st_read(file.path(DIR_RAW, "geo", "ae_mgap.geojson"), quiet = TRUE)
dep_raw <- st_read(file.path(DIR_RAW, "geo", "departamentos.geojson"), quiet = TRUE)

# Nomenclatura INE (la usa la cartografía y el prefijo de los códigos de AE).
INE_DEPS <- c("MONTEVIDEO", "ARTIGAS", "CANELONES", "CERRO LARGO", "COLONIA",
              "DURAZNO", "FLORES", "FLORIDA", "LAVALLEJA", "MALDONADO", "PAYSANDU",
              "RIO NEGRO", "RIVERA", "ROCHA", "SALTO", "SAN JOSE", "SORIANO",
              "TACUAREMBO", "TREINTA Y TRES")
DEP_LABEL <- c("Montevideo", "Artigas", "Canelones", "Cerro Largo", "Colonia",
               "Durazno", "Flores", "Florida", "Lavalleja", "Maldonado", "Paysandú",
               "Río Negro", "Rivera", "Rocha", "Salto", "San José", "Soriano",
               "Tacuarembó", "Treinta y Tres")
dep_code_ine <- function(name) sprintf("%02d", match(norm_name(name), INE_DEPS))

ae <- ae_raw |>
  transmute(
    id       = sprintf("%07d", as.integer(CCOMPAE)),
    dep      = sprintf("%02d", as.integer(DEPTO)),
    as_code  = sprintf("%04d", as.integer(CCOMPAS)),
    ae_num   = sprintf("%03d", as.integer(AREAENUM))
  )
check("ae_codigos_unicos", !anyDuplicated(ae$id),
      sprintf("%d polígonos, %d códigos CCOMPAE distintos", nrow(ae), n_distinct(ae$id)))
check("ae_prefijo_departamento", all(substr(ae$id, 1, 2) == ae$dep),
      "Los dos primeros dígitos del código de AE coinciden con el departamento (nomenclatura INE)")
check("ae_nombre_departamento",
      all(dep_code_ine(ae_raw$NOMDEPTO) == ae$dep),
      "El nombre de departamento de cada AE corresponde a su código INE")
n_invalid <- sum(!st_is_valid(ae))
ae <- st_make_valid(ae) |> st_collection_extract("POLYGON") |>
  group_by(id, dep, as_code, ae_num) |> summarise(.groups = "drop")
check("ae_geometrias_validas", all(st_is_valid(ae)),
      sprintf("%d geometrías inválidas en el original, reparadas con st_make_valid()", n_invalid))

ae_utm <- st_transform(ae, 32721)
ae$area_km2 <- as.numeric(st_area(ae_utm)) / 1e6

contested <- norm_name(dep_raw$NOMBRE) == "LIMITE CONTESTADO"
dep <- dep_raw[!contested, ] |>
  mutate(id = dep_code_ine(NOMBRE)) |>
  st_make_valid() |>
  group_by(id) |> summarise(.groups = "drop")
check("departamentos_19", nrow(dep) == 19 && !anyNA(dep$id),
      sprintf("%d departamentos; se excluye 1 polígono «LÍMITE CONTESTADO» de la capa oficial", nrow(dep)))
dep$area_km2 <- as.numeric(st_area(st_transform(dep, 32721))) / 1e6

# Coherencia AE ↔ departamentos: superficie de las AE agregadas vs. límites oficiales.
ae_dep_area <- st_drop_geometry(ae) |> group_by(dep) |> summarise(ae_km2 = sum(area_km2))
area_cmp <- st_drop_geometry(dep) |> left_join(ae_dep_area, by = c("id" = "dep")) |>
  mutate(dif_pct = 100 * (ae_km2 - area_km2) / area_km2)
# Las AE no cubren el área urbana de Montevideo ni los grandes embalses del
# río Negro; fuera de eso, deben coincidir con los límites oficiales.
rural <- area_cmp$id != "01"
check("ae_cubren_departamentos", all(abs(area_cmp$dif_pct[rural]) < 7),
      sprintf("Superficie AE agregadas vs. límites oficiales: máx. %.1f %% fuera de Montevideo (embalses); Montevideo %.0f %% (solo zona rural)",
              max(abs(area_cmp$dif_pct[rural])), area_cmp$dif_pct[!rural]))

# Simplificación con preservación de topología (mapshaper). Los originales
# quedan intactos en data-raw/geo/.
simplify <- function(x, keep) {
  s <- ms_simplify(x, keep = keep, keep_shapes = TRUE, method = "vis")
  st_make_valid(s) |> st_collection_extract("POLYGON") |>
    group_by(across(-any_of("geometry"))) |> summarise(.groups = "drop")
}
npts  <- function(x) sum(vapply(st_geometry(x), function(g) nrow(st_coordinates(g)), 1))
ae_s  <- simplify(ae, 0.06)
dep_s <- simplify(dep, 0.04)
check("simplificacion_conserva_entidades",
      nrow(ae_s) == nrow(ae) && nrow(dep_s) == nrow(dep),
      sprintf("AE: %d → %d vértices; departamentos: %d → %d vértices",
              npts(ae), npts(ae_s), npts(dep), npts(dep_s)))

# 2. Producción de leche DICOSE ---------------------------------------------
msg("Producción de leche (DICOSE)")
dic_deps <- read_mgap_csv(resource_path(max(DICOSE_DATASETS$ejercicio), "Códigos de departamentos"))
DIC2INE <- setNames(dep_code_ine(dic_deps$DepartamentoDescripcion),
                    as.character(as.integer(dic_deps$DepartamentoCodigo)))
check("diccionario_departamentos", !anyNA(DIC2INE) && length(DIC2INE) == 19,
      "Códigos DICOSE de departamento (orden alfabético, Montevideo = 10) traducidos a INE por nombre")

years_meta <- list()
rows <- list()
for (y in DICOSE_DATASETS$ejercicio) {
  p <- resource_path(y, "Producción de leche")
  if (is.na(p) || !file.exists(p)) {
    msg("  ", y, ": sin archivo de producción de leche")
    years_meta[[as.character(y)]] <- list(ejercicio = y, disponible = FALSE)
    next
  }
  d <- read_mgap_csv(p)
  need <- c("Ejercicio", "DepartamentoCodigo", "AreaEnumeracion", "EspecieCodigo",
            "TipoProduccionCodigo", "Litros", "CantidadTenedoresPorProduccionLeche")
  if (!all(need %in% names(d))) stop(y, ": faltan columnas ", paste(setdiff(need, names(d)), collapse = ", "))
  d <- d |> mutate(
    ejercicio = as.integer(Ejercicio),
    litros    = parse_num(Litros),
    tenedores = parse_num(CantidadTenedoresPorProduccionLeche),
    tipo      = as.character(as.integer(TipoProduccionCodigo)),
    especie   = as.character(as.integer(EspecieCodigo)),
    dep_ine   = unname(DIC2INE[as.character(as.integer(DepartamentoCodigo))]),
    ae_id     = ifelse(as.integer(AreaEnumeracion) == 0, NA_character_,
                       sprintf("%07d", as.integer(AreaEnumeracion)))
  )
  tipos <- read_mgap_csv(resource_path(y, "Códigos de producciones"))
  check(paste0(y, "_ejercicio"), all(d$ejercicio == y), "Todas las filas declaran el ejercicio del archivo")
  check(paste0(y, "_litros_validos"), !anyNA(d$litros) && all(d$litros >= 0),
        sprintf("%d filas; litros sin faltantes ni negativos (%d ceros)", nrow(d), sum(d$litros == 0)))
  check(paste0(y, "_tipos_en_diccionario"),
        all(d$tipo %in% as.character(as.integer(tipos$TipoProduccionCodigo))),
        paste("Tipos presentes:", paste(sort(unique(as.integer(d$tipo))), collapse = ", ")))
  check(paste0(y, "_sin_duplicados"), !anyDuplicated(select(d, -Litros, -litros,
                                                             -CantidadTenedoresPorProduccionLeche, -tenedores)),
        "Ninguna combinación de atributos se repite: no hay subtotales dentro del archivo")
  check(paste0(y, "_ae_con_poligono"), all(is.na(d$ae_id) | d$ae_id %in% ae$id),
        sprintf("%d áreas con leche; todas tienen polígono", n_distinct(na.omit(d$ae_id))))
  dep_ae <- substr(d$ae_id, 1, 2)
  mism <- !is.na(d$ae_id) & dep_ae != d$dep_ine
  check(paste0(y, "_departamento_coherente"), mean(mism) < 0.01,
        sprintf("%d filas con departamento registrado distinto al del AE (%.3f %% de los litros)",
                sum(mism), 100 * sum(d$litros[mism]) / sum(d$litros)))
  # El tipo 10 («Venta de LECHE») no es subtotal de 1 y 2: nunca coexiste con
  # ellos en la misma combinación de atributos.
  keycols <- setdiff(names(d), c("TipoProduccionCodigo", "tipo", "Litros", "litros",
                                 "CantidadTenedoresPorProduccionLeche", "tenedores",
                                 "ejercicio", "especie", "dep_ine", "ae_id"))
  co <- d |> group_by(across(all_of(keycols))) |>
    summarise(t10 = any(tipo == "10"), t12 = any(tipo %in% c("1", "2")), .groups = "drop")
  check(paste0(y, "_tipo10_no_es_subtotal"), !any(co$t10 & co$t12),
        sprintf("Tipo 10 en %d combinaciones, ninguna con tipos 1 o 2", sum(co$t10)))

  pkg <- man |> filter(fuente == "dicose", ejercicio == as.character(y)) |> slice(1)
  years_meta[[as.character(y)]] <- list(
    ejercicio = y, disponible = TRUE, estado = pkg$estado,
    titulo = pkg$dataset_titulo, url_dataset = paste0("https://catalogodatos.gub.uy/dataset/", pkg$dataset_id),
    url_recurso = man$url[man$archivo == sub(paste0(PROJECT_ROOT, "/"), "", p, fixed = TRUE)][1],
    descargado = pkg$descargado, filas = nrow(d),
    periodo = sprintf("1 jul %d – 30 jun %d", y - 1, y)
  )
  rows[[as.character(y)]] <- d
}
milk <- bind_rows(rows)
YEARS <- sort(unique(milk$ejercicio))
msg("  Ejercicios validados: ", paste(YEARS, collapse = ", "))

# Metadatos: definición de litros en ambos recursos (evita confundir los litros
# industrializados en el predio con la producción total).
meta_litros <- lapply(YEARS, function(y) {
  a <- read_meta(Sys.glob(file.path(DIR_RAW, "dicose", y, "metadatos-de-produccion-de-leche__*.csv")))
  b <- read_meta(Sys.glob(file.path(DIR_RAW, "dicose", y, "metadatos-de-produccion-de-leche-en-establecimiento__*.csv")))
  var <- names(a)[2]
  tibble(ejercicio = y,
         produccion = a$DESCRIPCION[a[[var]] == "Litros"],
         en_establecimiento = b$DESCRIPCION[b[[names(b)[2]]] == "Litros"])
}) |> bind_rows()
check("metadatos_litros",
      all(grepl("producidos", meta_litros$produccion)) &&
        all(grepl("industrializados", meta_litros$en_establecimiento)),
      "«Producción de leche»: litros producidos; «en establecimiento»: litros industrializados en el predio (no se usa como producción)")

# Contraste interno: tipo 3 (industrialización en el predio) vs. recurso
# «Producción de leche en establecimiento» (litros por producto).
est_cmp <- lapply(YEARS, function(y) {
  e <- read_mgap_csv(resource_path(y, "Producción de leche en establecimiento"))
  tibble(ejercicio = y,
         establecimiento_ML = sum(parse_num(e$Litros)) / 1e6,
         tipo3_ML = sum(milk$litros[milk$ejercicio == y & milk$tipo == "3"]) / 1e6)
}) |> bind_rows()

# Especies: 11 = BOVINOS DE LECHE; 4 = CAPRINOS (sin control de calidad según metadatos).
especies <- milk |> group_by(ejercicio, especie) |>
  summarise(litros = sum(litros), filas = n(), .groups = "drop")
bov <- filter(milk, especie == "11")

# 3. Indicadores -------------------------------------------------------------
# prod: litros producidos, bovinos de leche, todos los destinos (tipos 1–5, 10, 11).
# venta: litros vendidos (tipos 1 «cuota o reparto propio», 2 «industria» y 10
#       «venta de leche»). La frontera entre 1 y 2 cambia entre ejercicios, por lo
#       que solo el agregado es comparable en el tiempo.
# rem : tenedores (números DICOSE) que declaran venta a la industria (tipo 2).
#       Se cuentan dentro de un único destino: no se suman tenedores de destinos distintos.
# dens: prod / superficie territorial del área (km²). No es rendimiento por hectárea lechera.
msg("Indicadores")
agg <- function(d) summarise(d,
  prod = sum(litros),
  venta = sum(litros[tipo %in% c("1", "2", "10")]),
  rem  = sum(tenedores[tipo == "2"]),
  .groups = "drop")

grid_ae  <- expand_grid(id = ae$id, ejercicio = YEARS)
grid_dep <- expand_grid(id = dep$id, ejercicio = YEARS)

val_ae <- bov |> filter(!is.na(ae_id)) |> group_by(id = ae_id, ejercicio) |> agg()
val_ae <- grid_ae |> left_join(val_ae, by = c("id", "ejercicio")) |>
  mutate(across(c(prod, venta, rem), ~ coalesce(.x, 0))) |>
  left_join(st_drop_geometry(ae) |> select(id, area_km2), by = "id") |>
  mutate(dens = prod / area_km2)

# Departamentos: por departamento de registro del tenedor, lo que incluye los
# establecimientos sin área de enumeración asignada.
val_dep <- bov |> group_by(id = dep_ine, ejercicio) |> agg()
val_dep <- grid_dep |> left_join(val_dep, by = c("id", "ejercicio")) |>
  mutate(across(c(prod, venta, rem), ~ coalesce(.x, 0))) |>
  left_join(st_drop_geometry(dep) |> select(id, area_km2), by = "id") |>
  mutate(dens = prod / area_km2)

unassigned <- bov |> filter(is.na(ae_id)) |> group_by(dep = dep_ine, ejercicio) |>
  summarise(litros = sum(litros), filas = n(), .groups = "drop")

nacional <- bov |> group_by(ejercicio) |> agg() |>
  left_join(bov |> group_by(ejercicio) |>
              summarise(sin_ae_litros = sum(litros[is.na(ae_id)]),
                        sin_ae_filas = sum(is.na(ae_id)),
                        cuota_reparto = sum(litros[tipo == "1"]),
                        industria = sum(litros[tipo == "2"]),
                        predio = sum(litros[tipo == "3"]),
                        consumo = sum(litros[tipo %in% c("4", "5")]),
                        otros = sum(litros[tipo == "11"]), .groups = "drop"),
            by = "ejercicio") |>
  mutate(share_venta = venta / prod)

check("suma_ae_mas_sin_asignar_igual_nacional",
      isTRUE(all.equal(val_ae |> group_by(ejercicio) |> summarise(v = sum(prod)) |> pull(v) +
                         nacional$sin_ae_litros, nacional$prod)),
      "Σ AE + litros sin AE = total nacional (bovinos de leche), cada ejercicio")
check("suma_departamentos_igual_nacional",
      isTRUE(all.equal(val_dep |> group_by(ejercicio) |> summarise(v = sum(prod)) |> pull(v),
                       nacional$prod)),
      "Σ departamentos = total nacional, cada ejercicio")

# Variación interanual entre ejercicios consecutivos publicados.
add_change <- function(v) {
  v |> arrange(id, ejercicio) |> group_by(id) |>
    mutate(across(c(prod, venta, rem, dens), list(
      prev = ~ ifelse(ejercicio - lag(ejercicio) == 1, lag(.x), NA_real_)
    ), .names = "{.col}_prev")) |>
    ungroup() |>
    mutate(across(c(prod, venta, rem, dens), list(
      chg = ~ {
        prev <- get(paste0(cur_column(), "_prev"))
        ifelse(is.na(prev) | prev == 0, NA_real_, 100 * (.x - prev) / prev)
      }
    ), .names = "{.col}_chg"),
    across(c(prod, venta, rem, dens), list(
      # Estado de la comparación: ok | sin_base (anterior 0, actual > 0) |
      # sin_produccion (ambos 0) | sin_anterior (no hay ejercicio previo publicado)
      cmp = ~ {
        prev <- get(paste0(cur_column(), "_prev"))
        dplyr::case_when(is.na(prev) ~ "sin_anterior",
                         prev == 0 & .x == 0 ~ "sin_produccion",
                         prev == 0 ~ "sin_base",
                         TRUE ~ "ok")
      }
    ), .names = "{.col}_cmp"))
}
val_ae  <- add_change(val_ae)
val_dep <- add_change(val_dep)

# 4. Escalas fijas (una por indicador y nivel, comunes a todos los ejercicios)
INDICATORS <- list(
  prod = list(id = "prod", label = "Producción de leche", short = "Producción",
              unit = "litros", unit_short = "L", big = 1e6, big_unit = "millones de litros",
              desc = "Litros producidos en el ejercicio por bovinos de leche, sumando todos los destinos declarados (venta a industria, cuota o reparto, industrialización y consumo en el predio, otros)."),
  venta = list(id = "venta", label = "Leche vendida", short = "Vendida",
              unit = "litros", unit_short = "L", big = 1e6, big_unit = "millones de litros",
              desc = "Litros declarados como venta: a la industria, como cuota o reparto propio y otras ventas de leche. Se agregan porque la frontera entre venta a industria y cuota o reparto cambia entre ejercicios."),
  dens = list(id = "dens", label = "Densidad territorial", short = "Densidad",
              unit = "litros por km² de territorio", unit_short = "L/km²", big = 1, big_unit = "litros por km²",
              desc = "Producción dividida por la superficie total del área (km²). Permite comparar áreas de distinto tamaño. No es un rendimiento por hectárea lechera: el denominador incluye todo el territorio, no la superficie de los tambos."),
  rem  = list(id = "rem", label = "Tenedores con venta a industria", short = "Remitentes",
              unit = "tenedores (números DICOSE)", unit_short = "tenedores", big = 1, big_unit = "tenedores",
              desc = "Números DICOSE que declaran venta de leche a la industria. Se cuentan solo en ese destino: un mismo productor puede declarar varios destinos y no se suman entre sí.")
)

nice_ceiling <- function(x) {
  if (!is.finite(x) || x <= 0) return(1)
  p <- 10^floor(log10(x)); m <- x / p
  m2 <- c(1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10)[which(c(1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10) >= m)[1]]
  m2 * p
}
make_scales <- function(v) {
  out <- list()
  for (k in names(INDICATORS)) {
    x <- v[[k]]
    chg <- v[[paste0(k, "_chg")]]
    # El rango de variación se fija con el percentil 90 de |cambio| en áreas
    # con base > 0, redondeado, para no saturar por áreas muy pequeñas.
    q <- stats::quantile(abs(chg), 0.9, na.rm = TRUE)
    lim <- c(10, 20, 25, 40, 50, 75, 100)[which(c(10, 20, 25, 40, 50, 75, 100) >= q)[1]]
    if (is.na(lim)) lim <- 100
    out[[k]] <- list(max = nice_ceiling(max(x, na.rm = TRUE)), max_raw = max(x, na.rm = TRUE),
                     chg_lim = lim)
  }
  out
}
scales <- list(ae = make_scales(val_ae), dep = make_scales(val_dep))

# 5. Contraste con fuentes oficiales externas ----------------------------------
msg("Contraste con INALE")
inale <- NULL
inale_path <- file.path(DIR_RAW, "oficial", "inale_remision_a_planta.xls")
if (file.exists(inale_path) && requireNamespace("readxl", quietly = TRUE)) {
  x <- readxl::read_excel(inale_path, sheet = 1, col_names = FALSE, .name_repair = "minimal")
  hdr <- which(trimws(as.character(x[[1]])) %in% c("Año/ Mes", "Año/Mes"))[1]
  yrs <- suppressWarnings(as.integer(unlist(x[hdr, -1])))
  meses <- c("Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto",
             "Setiembre", "Octubre", "Noviembre", "Diciembre")
  mrows <- match(meses, trimws(as.character(x[[1]])))
  long <- expand_grid(m = 1:12, j = seq_along(yrs)) |>
    mutate(anio = yrs[j], ml = mapply(function(m, j) suppressWarnings(as.numeric(x[[j + 1]][mrows[m]])), m, j)) |>
    filter(!is.na(anio))
  inale <- lapply(YEARS, function(y) {
    s <- long |> filter((anio == y - 1 & m >= 7) | (anio == y & m <= 6))
    tibble(ejercicio = y, meses = sum(!is.na(s$ml)), remision_ML = sum(s$ml, na.rm = TRUE))
  }) |> bind_rows() |>
    left_join(nacional |> transmute(ejercicio, prod_ML = prod / 1e6, ind_ML = industria / 1e6,
                                    venta_ML = venta / 1e6), by = "ejercicio") |>
    mutate(ratio_ind = ind_ML / remision_ML, ratio_venta = venta_ML / remision_ML,
           ratio_prod = prod_ML / remision_ML)
  check("contraste_inale_produccion",
        all(inale$ratio_prod[inale$meses == 12] > 1),
        sprintf("Producción DICOSE / remisión INALE (jul–jun): %s",
                paste(sprintf("%d: %.2f", inale$ejercicio, inale$ratio_prod), collapse = "; ")))
  check("contraste_inale_venta",
        all(inale$ratio_venta > 0.85 & inale$ratio_venta < 1),
        sprintf("Leche vendida DICOSE / remisión INALE: %s (venta a industria sola: %s)",
                paste(sprintf("%.2f", inale$ratio_venta), collapse = ", "),
                paste(sprintf("%.2f", inale$ratio_ind), collapse = ", ")))
}

# 6. Guardado ---------------------------------------------------------------
msg("Guardando")
dir.create(DIR_DATA, showWarnings = FALSE)

geo_ae <- ae_s |> left_join(st_drop_geometry(ae) |> select(id, area_km2), by = "id") |>
  mutate(dep_name = DEP_LABEL[as.integer(dep)],
         name = sprintf("Área %s·%s", substr(as_code, 3, 4), ae_num),
         label = sprintf("%s — AE %s", dep_name, id))
geo_dep <- dep_s |> left_join(st_drop_geometry(dep) |> select(id, area_km2), by = "id") |>
  mutate(dep_name = DEP_LABEL[as.integer(id)], name = dep_name, label = dep_name)

sources <- man |> filter(!is.na(archivo) | fuente == "geo") |>
  select(fuente, ejercicio, estado, dataset_titulo, recurso_nombre, url, descargado, error)

atlas <- list(
  version = format(Sys.time(), "%Y-%m-%d"),
  years = YEARS,
  years_all = DICOSE_DATASETS$ejercicio,
  years_meta = years_meta,
  indicators = INDICATORS,
  geo = list(ae = geo_ae, dep = geo_dep),
  values = list(ae = val_ae, dep = val_dep),
  national = nacional,
  unassigned = unassigned,
  scales = scales,
  inale = inale,
  especies = especies,
  establecimiento = est_cmp,
  meta_litros = meta_litros,
  area_cmp = area_cmp,
  sources = sources,
  checks = checks
)
saveRDS(atlas, file.path(DIR_DATA, "atlas.rds"), compress = "xz")
write_csv(val_ae |> select(id, ejercicio, prod, venta, rem, dens, ends_with("_chg"), ends_with("_cmp")),
          file.path(DIR_DATA, "indicadores_areas_enumeracion.csv"), na = "")
write_csv(val_dep |> select(id, ejercicio, prod, venta, rem, dens, ends_with("_chg"), ends_with("_cmp")) |>
            mutate(departamento = DEP_LABEL[as.integer(id)], .after = id),
          file.path(DIR_DATA, "indicadores_departamentos.csv"), na = "")
write_csv(nacional, file.path(DIR_DATA, "indicadores_nacionales.csv"), na = "")
write_json(checks, file.path(DIR_DATA, "validacion.json"), auto_unbox = TRUE, pretty = TRUE)

n_fail <- sum(!vapply(checks, `[[`, logical(1), "ok"))
msg(sprintf("atlas.rds: %.1f MB — %d controles, %d fallidos",
            file.size(file.path(DIR_DATA, "atlas.rds")) / 1e6, length(checks), n_fail))
