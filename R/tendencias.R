# Sección «Tendencias»: gráficas interactivas con series oficiales.
#
#   Leche por mes   INALE, remisión mensual a planta (una línea por año)
#   Año lechero     INALE, la misma serie ordenada de julio a junio
#   Rodeo y tambos  MGAP, DICOSE–SNIG (producción, vacas, litros por vaca, tambos)
#   Departamentos   MGAP, DICOSE–SNIG (variación entre el primer y el último ejercicio)
#   Precio          INALE, precio real en tambo y remisión por ejercicio
#   Clima           CHIRPS v2.0 (lluvia en la cuenca) y remisión INALE
#
# Cada vista devuelve la gráfica, los datos con coordenadas numéricas (para el
# tooltip al pasar el mouse) y la tabla que se descarga como CSV.

TV_INK <- "#172B2A"; TV_INK2 <- "#667773"; TV_LINE <- "#E7ECE8"
# Un color propio por año (paleta categórica validada para daltonismo sobre el
# fondo #F5F3EE). El color sigue al año, no a su posición: 2024 es siempre violeta.
TV_YEAR_COLS <- c(`2021` = "#2a78d6", `2022` = "#eb6834", `2023` = "#1baf7a", `2024` = "#eda100",
                  `2025` = "#e87ba4", `2026` = "#008300", `2027` = "#4a3aa7")
TV_DESDE <- 2021L    # primer ejercicio DICOSE: las series mensuales se muestran desde ahí
TV_NEG <- "#B8663F"; TV_POS <- "#2A7F80"
MES_LARGO <- c("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
               "setiembre", "octubre", "noviembre", "diciembre")
MES_CORTO <- c("Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Set", "Oct", "Nov", "Dic")

# Tipografía del atlas para las gráficas (si falta, la del sistema).
TV_FONT <- tryCatch({
  f <- file.path("tools", "fonts", c("InterAtlas-Regular.ttf", "InterAtlas-SemiBold.ttf"))
  stopifnot(all(file.exists(f)))
  systemfonts::register_font("Inter Atlas", plain = f[1], bold = f[2])
  "Inter Atlas"
}, error = function(e) "")

load_tendencias <- function(atlas, path = file.path("data", "tendencias.rds")) {
  if (is.null(atlas)) return(NULL)
  t <- if (file.exists(path)) readRDS(path) else NULL
  rem <- t$remision
  if (!is.null(rem)) {
    rem <- rem |> dplyr::mutate(ejercicio = ifelse(mes >= 7, anio + 1L, anio),
                                pos = ifelse(mes >= 7, mes - 6L, mes + 6L))
  }
  views <- c("Leche por mes" = "mes", "Año lechero" = "ejercicio", "Rodeo y tambos" = "rodeo",
             "Departamentos" = "deps", "Precio" = "precio", "Clima" = "clima")
  if (is.null(rem)) views <- views[!views %in% c("mes", "ejercicio")]
  if (is.null(atlas$clima)) views <- views[!views %in% c("precio", "clima")]
  list(remision = rem, ultimo = t$ultimo, atlas = atlas, clima = atlas$clima, views = views,
       anios = if (!is.null(rem)) sort(unique(rem$anio[rem$anio >= TV_DESDE])),
       ejercicios = if (!is.null(rem)) sort(unique(rem$ejercicio[rem$ejercicio >= TV_DESDE])))
}

# Años marcados al abrir: desde el primer ejercicio DICOSE hasta hoy.
tv_default_years <- function(yrs, desde = TV_DESDE) as.character(yrs[yrs >= desde])

year_colour <- function(y) {
  y <- as.character(y)
  out <- unname(TV_YEAR_COLS[y])
  out[is.na(out)] <- "#667773"
  out
}

tv_theme <- function() {
  ggplot2::theme_minimal(base_size = 12.5, base_family = TV_FONT) +
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = "transparent", colour = NA),
      panel.background = ggplot2::element_rect(fill = "transparent", colour = NA),
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(colour = TV_LINE, linewidth = 0.4),
      axis.text = ggplot2::element_text(colour = TV_INK2, size = 10.5),
      axis.title = ggplot2::element_blank(),
      strip.text = ggplot2::element_text(colour = TV_INK, face = "bold", size = 11, hjust = 0),
      legend.position = "top", legend.justification = "left", legend.title = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(colour = TV_INK, size = 10.5),
      legend.key.width = ggplot2::unit(18, "pt"), legend.margin = ggplot2::margin(0, 0, 2, 0),
      panel.spacing = ggplot2::unit(16, "pt"),
      plot.margin = ggplot2::margin(6, 12, 4, 4)
    )
}

pct <- function(v, d = 0) paste0(signed(v, d), "\u00a0%")
# Etiquetas del eje con los decimales justos para distinguir los cortes.
lab_num <- function(v) {
  w <- v[!is.na(v)]
  fmt_num(v, if (all(abs(w - round(w)) < 1e-9)) 0 else if (all(abs(w * 10 - round(w * 10)) < 1e-9)) 1 else 2)
}
signed <- function(v, d = 0) {
  paste0(ifelse(v > 0, "+", ifelse(v < 0, "−", "")), fmt_num(abs(v), d))
}

# Vistas ------------------------------------------------------------------------

tv_mes <- function(T, years, narrow = FALSE) {
  yrs <- sort(as.integer(years))
  d <- T$remision |> dplyr::filter(anio %in% yrs)
  if (!nrow(d)) return(NULL)
  pal <- stats::setNames(year_colour(yrs), yrs)
  last <- max(yrs)
  d <- d |> dplyr::arrange(anio, mes) |>
    dplyr::mutate(x = mes, y = ml, grupo = factor(anio, levels = yrs),
                  prev = T$remision$ml[match(paste(anio - 1, mes), paste(T$remision$anio, T$remision$mes))])
  d$tip_title <- paste(tools::toTitleCase(MES_LARGO[d$mes]), d$anio)
  d$tip_value <- paste(fmt_num(d$ml, 1), "millones de litros")
  d$tip_note <- ifelse(is.na(d$prev), "",
                       paste(pct(100 * (d$ml / d$prev - 1), 1), "vs.", MES_LARGO[d$mes], d$anio - 1))
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = grupo, group = grupo)) +
    ggplot2::geom_line(ggplot2::aes(linewidth = anio == last), lineend = "round", linejoin = "round") +
    ggplot2::geom_point(data = d[d$anio == last, ], size = 1.6, show.legend = FALSE) +
    ggplot2::scale_linewidth_manual(values = c(`TRUE` = 1.25, `FALSE` = 0.7), guide = "none") +
    ggplot2::scale_colour_manual(values = pal) +
    ggplot2::scale_x_continuous(breaks = 1:12, labels = if (narrow) substr(MES_CORTO, 1, 1) else MES_CORTO,
                                expand = ggplot2::expansion(add = 0.25)) +
    ggplot2::scale_y_continuous(labels = lab_num, n.breaks = 6) +
    ggplot2::guides(colour = ggplot2::guide_legend(nrow = if (length(yrs) > 13) 2 else 1,
                                                   override.aes = list(linewidth = 1.2))) +
    tv_theme() +
    ggplot2::theme(legend.position = "none")   # la leyenda son los botones de año
  u <- T$ultimo
  list(plot = p, data = d, type = "point",
       title = "La leche que llega a planta, mes a mes",
       sub = sprintf("Remisión mensual a la industria, en millones de litros, desde 2021 (el primer ejercicio del atlas). Una línea por año; %d resaltado. Pase el cursor por una línea para ver el valor.", last),
       source = sprintf("Fuente: INALE, remisión a planta (datos hasta %s de %d). DICOSE (MGAP) solo publica producción anual; la remisión mensual equivale a ≈ 91–95\u00a0%% de lo producido.",
                        MES_LARGO[u$mes], u$anio),
       csv = d |> dplyr::transmute(anio, mes, remision_millones_litros = ml),
       file = "cuencauy-remision-mensual.csv")
}

tv_ejercicio <- function(T, years, narrow = FALSE) {
  yrs <- sort(as.integer(years))
  d <- T$remision |> dplyr::filter(ejercicio %in% yrs)
  if (!nrow(d)) return(NULL)
  pal <- stats::setNames(year_colour(yrs), yrs)
  last <- max(yrs)
  tot <- d |> dplyr::group_by(ejercicio) |> dplyr::summarise(total = sum(ml), n = dplyr::n(), .groups = "drop")
  d <- d |> dplyr::arrange(ejercicio, pos) |>
    dplyr::left_join(tot, by = "ejercicio") |>
    dplyr::mutate(x = pos, y = ml, grupo = factor(ejercicio, levels = yrs),
                  acum = stats::ave(ml, ejercicio, FUN = cumsum))
  d$tip_title <- paste0(tools::toTitleCase(MES_LARGO[d$mes]), " ", d$anio, " · ejercicio ", d$ejercicio)
  d$tip_value <- paste(fmt_num(d$ml, 1), "millones de litros")
  d$tip_note <- ifelse(d$n == 12, paste("Total del ejercicio:", fmt_num(d$total, 0), "M L"),
                       paste0("Acumulado (", d$n, " de 12 meses): ", fmt_num(d$acum, 0), " M L"))
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, colour = grupo, group = grupo)) +
    ggplot2::geom_line(ggplot2::aes(linewidth = ejercicio == last), lineend = "round", linejoin = "round") +
    ggplot2::geom_point(data = d[d$ejercicio == last, ], size = 1.6, show.legend = FALSE) +
    ggplot2::scale_linewidth_manual(values = c(`TRUE` = 1.25, `FALSE` = 0.7), guide = "none") +
    ggplot2::scale_colour_manual(values = pal) +
    ggplot2::scale_x_continuous(breaks = 1:12, labels = (if (narrow) substr(MES_CORTO, 1, 1) else MES_CORTO)[c(7:12, 1:6)],
                                expand = ggplot2::expansion(add = 0.25)) +
    ggplot2::scale_y_continuous(labels = lab_num, n.breaks = 6) +
    ggplot2::guides(colour = ggplot2::guide_legend(nrow = if (length(yrs) > 13) 2 else 1,
                                                   override.aes = list(linewidth = 1.2))) +
    tv_theme() +
    ggplot2::theme(legend.position = "none")   # la leyenda son los botones de año
  list(plot = p, data = d, type = "point",
       title = "El año lechero, de julio a junio",
       sub = "Remisión mensual por ejercicio ganadero (1 de julio – 30 de junio), el mismo período que declaran los productores a DICOSE. Millones de litros.",
       source = "Fuente: INALE, remisión a planta. Ejercicio 2026 = julio 2025 – junio 2026. Un ejercicio incompleto muestra solo los meses publicados.",
       csv = d |> dplyr::transmute(ejercicio, anio, mes, mes_del_ejercicio = pos, remision_millones_litros = ml),
       file = "cuencauy-remision-por-ejercicio.csv")
}

tv_rodeo <- function(T) {
  n <- T$atlas$national
  panels <- c("Producción · millones de litros", "Vacas lecheras · miles de vacas masa",
              "Litros por vaca por año", "Tambos · números DICOSE «Lecheros»")
  d <- dplyr::bind_rows(
    data.frame(ejercicio = n$ejercicio, panel = panels[1], y = n$prod / 1e6, lab = fmt_num(n$prod / 1e6, 0),
               tip_value = paste(fmt_int(n$prod), "litros")),
    data.frame(ejercicio = n$ejercicio, panel = panels[2], y = n$vacas / 1e3, lab = fmt_num(n$vacas / 1e3, 0),
               tip_value = paste(fmt_int(n$vacas), "vacas masa")),
    data.frame(ejercicio = n$ejercicio, panel = panels[3], y = n$lpv, lab = fmt_int(n$lpv),
               tip_value = paste(fmt_int(n$lpv), "litros por vaca")),
    data.frame(ejercicio = n$ejercicio, panel = panels[4], y = n$tambos,
               lab = ifelse(is.na(n$tambos), "s/d", fmt_int(n$tambos)),
               tip_value = ifelse(is.na(n$tambos), "Sin dato publicado para este ejercicio",
                                  paste(fmt_int(n$tambos), "tambos"))))
  d$panel <- factor(d$panel, levels = panels)
  d$x <- d$ejercicio
  d <- d |> dplyr::group_by(panel) |> dplyr::arrange(ejercicio, .by_group = TRUE) |>
    dplyr::mutate(prev = dplyr::lag(y)) |> dplyr::ungroup()
  d$tip_title <- paste("Ejercicio", d$ejercicio)
  d$tip_note <- ifelse(is.na(d$prev) | is.na(d$y), "", paste(pct(100 * (d$y / d$prev - 1), 1), "vs. ejercicio anterior"))
  chg <- function(x) { x <- x[!is.na(x)]; 100 * (x[length(x)] / x[1] - 1) }
  last <- max(n$ejercicio)
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) +
    ggplot2::geom_col(ggplot2::aes(fill = ejercicio == last), width = 0.62, na.rm = TRUE) +
    ggplot2::geom_text(ggplot2::aes(y = ifelse(is.na(y), 0, y), label = lab), vjust = -0.5,
                       family = TV_FONT, size = 3.3, colour = TV_INK) +
    ggplot2::facet_wrap(~panel, ncol = 2, scales = "free_y") +
    ggplot2::scale_fill_manual(values = c(`TRUE` = "#176B60", `FALSE` = "#A9CFC0"), guide = "none") +
    ggplot2::scale_x_continuous(breaks = n$ejercicio) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.2)), labels = NULL) +
    tv_theme() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank(), axis.text.y = ggplot2::element_blank())
  list(plot = p, data = d, type = "bar",
       title = "Menos vacas y tambos, más leche por vaca",
       sub = sprintf("Uruguay, ejercicios %d–%d. La producción varía %s\u00a0%% con %s\u00a0%% de vacas; cada vaca rinde %s\u00a0%% más. Tambos: %s\u00a0%% desde %d.",
                     min(n$ejercicio), last, signed(chg(n$prod), 1), signed(chg(n$vacas), 1), signed(chg(n$lpv), 1),
                     signed(chg(n$tambos), 1), min(n$ejercicio[!is.na(n$tambos)])),
       source = "Fuente: MGAP, declaraciones juradas DICOSE–SNIG (Catálogo de Datos Abiertos). Vaca masa = en ordeñe + secas. La clasificación «Lecheros» no se publica para 2021 (s/d).",
       csv = n |> dplyr::transmute(ejercicio, produccion_litros = prod, vacas_masa = vacas,
                                   litros_por_vaca = round(lpv, 1), tambos),
       file = "cuencauy-rodeo-y-tambos.csv")
}

tv_deps <- function(T, narrow = FALSE) {
  a <- T$atlas
  y0 <- min(a$years); y9 <- max(a$years)
  g <- a$geo$dep
  v <- a$values$dep
  d <- data.frame(id = g$id, dep = g$dep_name)
  d$ini <- v$prod[match(paste(d$id, y0), paste(v$id, v$ejercicio))]
  d$fin <- v$prod[match(paste(d$id, y9), paste(v$id, v$ejercicio))]
  omit <- d$dep[is.na(d$ini) | d$ini < 5e6]
  d <- d[!is.na(d$ini) & d$ini >= 5e6, ]          # < 5 M L: variaciones inestables
  d$chg <- 100 * (d$fin / d$ini - 1)
  d <- d[order(d$chg), ]
  d$y <- seq_len(nrow(d)); d$x <- d$chg
  d$tip_title <- d$dep
  d$tip_value <- paste(pct(d$chg, 1), "entre", y0, "y", y9)
  d$tip_note <- sprintf("%s → %s millones de litros", fmt_num(d$ini / 1e6, 1), fmt_num(d$fin / 1e6, 1))
  lim <- max(abs(d$chg)) * if (narrow) 1.8 else 1.45
  nat <- a$national
  tot <- 100 * (nat$prod[nat$ejercicio == y9] / nat$prod[nat$ejercicio == y0] - 1)
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) +
    ggplot2::geom_vline(xintercept = 0, colour = "#B9C4BE", linewidth = 0.5) +
    ggplot2::geom_col(ggplot2::aes(fill = chg > 0), width = 0.62, orientation = "y") +
    ggplot2::geom_text(ggplot2::aes(label = paste0(signed(chg, 1), "\u00a0%"), hjust = ifelse(chg > 0, -0.12, 1.12)),
                       family = TV_FONT, size = 3.4, colour = TV_INK) +
    ggplot2::scale_fill_manual(values = c(`TRUE` = TV_POS, `FALSE` = TV_NEG), guide = "none") +
    ggplot2::scale_x_continuous(limits = c(-lim, lim), labels = function(v) paste0(signed(v), "\u00a0%")) +
    ggplot2::scale_y_continuous(breaks = d$y, labels = d$dep, expand = ggplot2::expansion(add = 0.6)) +
    tv_theme() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank(),
                   panel.grid.major.x = ggplot2::element_line(colour = TV_LINE, linewidth = 0.4),
                   axis.text.y = ggplot2::element_text(colour = TV_INK, size = 11))
  list(plot = p, data = d, type = "hbar",
       title = "Dónde creció y dónde cayó la leche",
       sub = sprintf("Variación de la producción declarada por departamento entre los ejercicios %d y %d. Total nacional: %s\u00a0%%.",
                     y0, y9, signed(tot, 1)),
       source = sprintf("Fuente: MGAP, declaraciones juradas DICOSE–SNIG (bovinos de leche, todos los destinos). Se omiten departamentos con menos de 5 M L en %d: %s.",
                        y0, paste(sort(omit), collapse = ", ")),
       csv = d |> dplyr::transmute(departamento = dep, litros_inicio = ini, litros_fin = fin, variacion_pct = round(chg, 2)),
       file = "cuencauy-variacion-departamentos.csv")
}

tv_precio <- function(T, narrow = FALSE) {
  na <- T$clima$nacional_anual
  x <- na$datos |> dplyr::filter(!is.na(precio_real))
  panels <- c("Precio real al productor · $ de 2025 por litro", "Remisión a planta · millones de litros")
  d <- dplyr::bind_rows(
    data.frame(ejercicio = x$ejercicio, panel = panels[1], y = x$precio_real,
               tip_value = paste("$", fmt_num(x$precio_real, 2), "por litro (pesos de 2025)"),
               tip_note = ifelse(is.na(x$d_precio), "", paste(pct(x$d_precio, 1), "vs. ejercicio anterior"))),
    data.frame(ejercicio = x$ejercicio, panel = panels[2], y = x$remision,
               tip_value = paste(fmt_num(x$remision, 0), "millones de litros"),
               tip_note = ifelse(is.na(x$d_rem), "", paste(pct(x$d_rem, 1), "vs. ejercicio anterior"))))
  d$panel <- factor(d$panel, levels = panels)
  d$x <- d$ejercicio
  d$tip_title <- paste("Ejercicio", d$ejercicio)
  cn <- na$cor
  r_prev <- cn$r[cn$predictor == "Precio real del ejercicio anterior"]
  r_sig <- cn$r[cn$predictor == "Precio real del ejercicio siguiente (placebo)"]
  b <- na$modelo_precio[2, ]
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y)) +
    ggplot2::geom_line(colour = "#176B60", linewidth = 0.9) +
    ggplot2::geom_point(colour = "#176B60", size = 1.7) +
    ggplot2::facet_wrap(~panel, ncol = 1, scales = "free_y") +
    ggplot2::scale_x_continuous(breaks = seq(2004, max(d$x), if (narrow) 4 else 2)) +
    ggplot2::scale_y_continuous(labels = lab_num, n.breaks = 5) +
    tv_theme()
  list(plot = p, data = d, type = "point",
       title = "La leche responde al precio, un año después",
       sub = sprintf("Por ejercicio (julio–junio). La variación de la remisión acompaña a la del precio real del ejercicio anterior (r\u00a0=\u00a0%s; placebo con el precio siguiente: %s). +10\u00a0%% de precio se asocia con %s\u00a0%% de remisión al año siguiente.",
                     fmt_num(r_prev, 2), fmt_num(r_sig, 2), signed(10 * b$estimado, 1)),
       source = "Fuentes: INALE (precio en tambo con reliquidaciones y remisión a planta) e IPC del INE para deflactar a pesos de 2025. Asociación no es causalidad.",
       csv = x |> dplyr::transmute(ejercicio, precio_real_pesos_2025 = round(precio_real, 3),
                                   remision_millones_litros = round(remision, 3),
                                   var_precio_pct = round(d_precio, 2), var_remision_pct = round(d_rem, 2)),
       file = "cuencauy-precio-y-remision.csv")
}

tv_clima <- function(T, narrow = FALSE) {
  na <- T$clima$nacional_anual
  x <- na$datos |> dplyr::filter(!is.na(d_rem))
  panels <- c("Lluvia en la cuenca lechera · % respecto a la normal 1991–2020",
              "Remisión a planta · variación respecto al ejercicio anterior, %")
  d <- dplyr::bind_rows(
    data.frame(ejercicio = x$ejercicio, panel = panels[1], y = x$lluvia_anom,
               tono = ifelse(x$lluvia_anom < 0, "seco", "humedo"),
               tip_value = paste(pct(x$lluvia_anom, 0), "de lluvia frente a lo normal")),
    data.frame(ejercicio = x$ejercicio, panel = panels[2], y = x$d_rem,
               tono = ifelse(x$d_rem < 0, "baja", "sube"),
               tip_value = paste(pct(x$d_rem, 1), "de remisión"),
               tip_note = paste(fmt_num(x$remision, 0), "millones de litros")))
  d$tip_note[is.na(d$tip_note)] <- ""
  d$panel <- factor(d$panel, levels = panels)
  d$x <- d$ejercicio
  d$tip_title <- paste("Ejercicio", d$ejercicio)
  r_ll <- na$cor$r[1]
  p <- ggplot2::ggplot(d, ggplot2::aes(x, y, fill = tono)) +
    ggplot2::geom_hline(yintercept = 0, colour = "#B9C4BE", linewidth = 0.4) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::facet_wrap(~panel, ncol = 1, scales = "free_y") +
    ggplot2::scale_fill_manual(values = c(seco = TV_NEG, humedo = TV_POS, baja = "#9CB8B0", sube = "#176B60"), guide = "none") +
    ggplot2::scale_x_continuous(breaks = seq(2004, max(d$x), if (narrow) 4 else 2)) +
    ggplot2::scale_y_continuous(labels = function(v) paste0(signed(v), "\u00a0%"), n.breaks = 5) +
    tv_theme()
  list(plot = p, data = d, type = "bar",
       title = "Años secos, leche estable",
       sub = sprintf("Por ejercicio (julio–junio), %d–%d. La lluvia y la remisión no se mueven juntas: r\u00a0=\u00a0%s, no significativa con %d ejercicios. La sequía de 2022–23 apenas movió la remisión.",
                     min(x$ejercicio), max(x$ejercicio), signed(r_ll, 2), nrow(x)),
       source = "Fuentes: lluvia CHIRPS v2.0 (UCSB/CHC), ponderada por la producción DICOSE de cada área; remisión INALE. Asociación no es causalidad.",
       csv = x |> dplyr::transmute(ejercicio, lluvia_anomalia_pct = round(lluvia_anom, 2),
                                   remision_millones_litros = round(remision, 3), var_remision_pct = round(d_rem, 2),
                                   dias_thi_72 = thi_dias),
       file = "cuencauy-clima-y-remision.csv")
}

tv_view <- function(T, view, years_mes = NULL, years_ej = NULL, narrow = FALSE) {
  switch(view,
         mes = tv_mes(T, years_mes, narrow),
         ejercicio = tv_ejercicio(T, years_ej, narrow),
         rodeo = tv_rodeo(T),
         deps = tv_deps(T, narrow),
         precio = tv_precio(T, narrow),
         clima = tv_clima(T, narrow),
         NULL)
}

# Punto más cercano al cursor. Las coordenadas del hover vienen en unidades de
# los datos; para líneas se usa nearPoints (distancia en píxeles) y para barras
# la categoría bajo el cursor.
tv_hit <- function(v, hover) {
  if (is.null(v) || is.null(hover) || is.null(hover$x)) return(NULL)
  d <- v$data
  pv <- hover$panelvar1
  if (!is.null(pv) && "panel" %in% names(d)) d <- d[as.character(d$panel) == pv, , drop = FALSE]
  if (!nrow(d)) return(NULL)
  if (v$type == "point") {
    h <- shiny::nearPoints(d, hover, xvar = "x", yvar = "y", panelvar1 = NULL,
                           threshold = 18, maxpoints = 1)
    if (nrow(h)) h else NULL
  } else if (v$type == "bar") {
    i <- which.min(abs(d$x - hover$x))
    if (length(i) && abs(d$x[i] - hover$x) <= 0.5) d[i, ] else NULL
  } else {
    i <- which.min(abs(d$y - hover$y))
    if (length(i) && abs(d$y[i] - hover$y) <= 0.5) d[i, ] else NULL
  }
}

tv_tip_ui <- function(hit, hover, width) {
  if (is.null(hit)) return(NULL)
  cx <- hover$coords_css$x; cy <- hover$coords_css$y
  flip <- !is.null(width) && cx > width * 0.6
  style <- sprintf("top:%.0fpx;%s", cy, if (flip) sprintf("right:%.0fpx", width - cx + 14) else sprintf("left:%.0fpx", cx + 14))
  div(class = "tv-tip", style = style,
      div(class = "tv-tip-title", hit$tip_title),
      div(class = "tv-tip-value num", hit$tip_value),
      if (!is.null(hit$tip_note) && nzchar(hit$tip_note)) div(class = "tv-tip-note num", hit$tip_note))
}

year_chips <- function(id, years, selected) {
  div(class = "tv-years",
      div(id = id, class = "shiny-input-checkboxgroup tv-chips", role = "group",
          `aria-label` = "Años a mostrar",
          lapply(years, function(y) tags$label(class = "tv-chip",
            tags$input(type = "checkbox", name = id, value = y,
                       checked = if (as.character(y) %in% selected) NA),
            span(span(class = "tv-swatch", style = paste0("background:", year_colour(y))),
                 span(class = "num", y))))),
      span(class = "tv-years-hint", "Toque un año para mostrarlo u ocultarlo"))
}

tendencias_modal <- function(T) {
  modalDialog(
    title = tagList(icon("chart-line"), span("Tendencias")),
    size = "xl", easyClose = TRUE,
    footer = tagList(
      downloadButton("tv_csv", "Descargar datos (CSV)", class = "btn-ghost", icon = NULL),
      modalButton("Cerrar")),
    div(class = "tv",
      radio_group("tv_view", T$views, selected = unname(T$views[1]), class = "segmented tv-tabs"),
      div(class = "tv-head", uiOutput("tv_head")),
      if ("mes" %in% T$views) conditionalPanel("input.tv_view == 'mes'",
        year_chips("tv_years_mes", T$anios, tv_default_years(T$anios))),
      if ("ejercicio" %in% T$views) conditionalPanel("input.tv_view == 'ejercicio'",
        year_chips("tv_years_ej", T$ejercicios, tv_default_years(T$ejercicios))),
      div(class = "tv-plot",
          plotOutput("tv_plot", height = "auto",
                     hover = hoverOpts("tv_hover", delay = 60, delayType = "throttle", nullOutside = TRUE)),
          div(class = "tv-tip-wrap", uiOutput("tv_tip"))),
      div(class = "tv-source", uiOutput("tv_source")),
      p(class = "tv-public", icon("info"),
        "Todos los datos provienen de fuentes públicas: INALE (estadísticas lecheras), MGAP (DICOSE–SNIG, Catálogo Nacional de Datos Abiertos), CHIRPS (UCSB) y NASA POWER. Ninguna cifra es estimada ni simulada por la app."))
  )
}
