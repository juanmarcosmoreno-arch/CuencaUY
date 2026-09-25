# Contenido dinámico: ficha del ejercicio, indicadores nacionales, leyenda,
# nota de la métrica, panel de detalle y ventana de fuentes y método.

year_card_ui <- function(atlas, year) {
  m <- atlas$years_meta[[as.character(year)]]
  estado <- m$estado %||% ""
  tagList(
    div(class = "year-kicker", "Ejercicio"),
    div(class = "year-value num", year),
    div(class = "year-status",
        span(class = "num", m$periodo %||% ""), " · ",
        span(class = paste("badge", if (estado == "preliminar") "prelim"),
             if (nzchar(estado)) tools::toTitleCase(estado) else "—"))
  )
}

kpi <- function(label, value, unit = NULL, delta = NULL, delta_class = "") {
  div(class = "kpi",
      div(class = "kpi-label", label),
      div(class = "kpi-value num", value, if (!is.null(unit)) tags$small(unit)),
      if (!is.null(delta)) div(class = paste("kpi-delta num", delta_class), delta))
}

delta_text <- function(cur, prev, prev_year) {
  if (is.null(prev) || length(prev) == 0 || is.na(prev) || prev == 0) {
    return(list(txt = "sin ejercicio anterior", cls = ""))
  }
  p <- 100 * (cur - prev) / prev
  list(txt = paste(fmt_pct(p), "vs.", prev_year), cls = if (p > 0.05) "up" else if (p < -0.05) "down" else "")
}

kpis_ui <- function(atlas, year) {
  n <- atlas$national
  cur <- n[n$ejercicio == year, ]
  prv <- n[n$ejercicio == year - 1, ]
  d1 <- delta_text(cur$prod, prv$prod, year - 1)
  d3 <- delta_text(cur$rem, prv$rem, year - 1)
  tagList(
    kpi("Producción nacional", fmt_num(cur$prod / 1e6, 0), "M L", d1$txt, d1$cls),
    kpi("Vendida", fmt_num(100 * cur$share_venta, 0), "%", "de la leche producida"),
    kpi("Remitentes a industria", fmt_int(cur$rem), NULL, d3$txt, d3$cls)
  )
}

metric_note_ui <- function(atlas, ind_id, level) {
  ind <- atlas$indicators[[ind_id]]
  lvl <- if (level == "ae") {
    "Las áreas de enumeración (DIEA) ubican cada establecimiento en el área de su mayor padrón declarado. Los establecimientos sin padrón en el catastro rural quedan sin área y solo cuentan en los departamentos."
  } else {
    "Los departamentos agregan a cada tenedor según su departamento de registro, incluidos los establecimientos sin área de enumeración asignada."
  }
  tagList(
    p(strong(ind$label), " — ", ind$desc),
    p(lvl),
    p("Ejercicios ganaderos del 1 de julio al 30 de junio, declarados por los productores (DICOSE–SNIG, MGAP). No hay datos mensuales.")
  )
}

legend_ui <- function(atlas, ind_id, level, year, mode, transform, dim) {
  ind <- atlas$indicators[[ind_id]]
  sc <- atlas$scales[[level]][[ind_id]]
  if (mode == "value") {
    stops <- seq(0, 1, length.out = length(PAL_SEQ))
    grad <- paste(sprintf("%s %.0f%%", PAL_SEQ, 100 * stops), collapse = ", ")
    mid <- if (transform == "sqrt") sc$max * 0.25 else sc$max * 0.5
    ramp <- div(class = "legend-ramp", style = sprintf("background: linear-gradient(90deg, %s)", grad))
    ticks <- div(class = "legend-ticks num",
                 span(fmt_axis(0, ind)), span(fmt_axis(mid, ind)), span(fmt_axis(sc$max, ind)))
    zero_lab <- switch(ind_id, venta = "Sin ventas declaradas", rem = "Sin tenedores",
                       "Sin producción declarada")
    extra <- div(class = "legend-extra",
                 span(span(class = "legend-swatch", style = paste0("background:", COL_ZERO)),
                      zero_lab))
    title <- ind$label
    unit <- ind$big_unit
  } else {
    stops <- seq(0, 1, length.out = length(PAL_DIV))
    grad <- paste(sprintf("%s %.0f%%", PAL_DIV, 100 * stops), collapse = ", ")
    ramp <- div(class = "legend-ramp", style = sprintf("background: linear-gradient(90deg, %s)", grad))
    ticks <- div(class = "legend-ticks num",
                 span(paste0("≤ −", sc$chg_lim, " %")), span("0"), span(paste0("≥ +", sc$chg_lim, " %")))
    first <- year == min(atlas$years) || !((year - 1) %in% atlas$years)
    extra <- div(class = "legend-extra",
                 span(span(class = "legend-swatch", style = paste0("background:", COL_NOBASE)),
                      "Sin base de comparación"),
                 span(span(class = "legend-swatch", style = paste0("background:", COL_ZERO)),
                      "Sin producción"),
                 if (first) span(span(class = "legend-swatch", style = paste0("background:", COL_NOPREV)),
                                 "Sin ejercicio anterior"))
    title <- paste(ind$label, "— variación")
    unit <- sprintf("%% respecto a %d", year - 1)
  }
  scale_txt <- if (transform == "sqrt") "Escala de raíz cuadrada (resalta valores bajos)." else "Escala lineal."
  un <- atlas$unassigned
  note_ae <- if (level == "ae" && ind_id %in% c("prod", "venta")) {
    s <- sum(un$litros[un$ejercicio == year])
    tot <- atlas$national$prod[atlas$national$ejercicio == year]
    sprintf(" %s M L (%s %%) sin área asignada.", fmt_num(s / 1e6, 1), fmt_num(100 * s / tot, 2))
  } else ""
  tagList(
    div(class = "legend-title", title, " ", span(class = "legend-unit", paste0("(", unit, ")"))),
    ramp, ticks, extra,
    div(class = "legend-note",
        if (dim == "3d") "La altura representa la magnitud del indicador; no es relieve. " else "Vista 2D: sin extrusión. ",
        scale_txt, " Escala fija 2021–2025.", note_ae)
  )
}

# Panel de detalle ------------------------------------------------------------

zone_series <- function(atlas, level, id, ind_id) {
  v <- atlas$values[[level]]
  v <- v[v$id == id, ]
  data.frame(ejercicio = atlas$years_all) |>
    dplyr::left_join(data.frame(ejercicio = v$ejercicio, value = v[[ind_id]],
                                chg = v[[paste0(ind_id, "_chg")]],
                                cmp = v[[paste0(ind_id, "_cmp")]]), by = "ejercicio")
}

detail_plot <- function(s, year, ind) {
  s$cur <- s$ejercicio == year
  div <- if (ind$id %in% c("prod", "venta")) 1e6 else 1
  s$y <- s$value / div
  ylab <- if (div == 1e6) "M L" else ind$unit_short
  ggplot2::ggplot(s, ggplot2::aes(x = factor(ejercicio), y = y)) +
    ggplot2::geom_col(ggplot2::aes(fill = cur), width = 0.62, na.rm = TRUE) +
    ggplot2::geom_text(data = s[is.na(s$y), , drop = FALSE],
                       ggplot2::aes(y = 0, label = "s/d"), vjust = -0.6, size = 3.2,
                       colour = "#8A9894") +
    ggplot2::scale_fill_manual(values = c(`TRUE` = "#176B60", `FALSE` = "#B9D6CB"), guide = "none") +
    ggplot2::scale_y_continuous(labels = function(x) fmt_num(x, if (max(s$y, na.rm = TRUE) < 10) 1 else 0),
                                expand = ggplot2::expansion(mult = c(0, 0.08)), n.breaks = 4) +
    ggplot2::labs(x = NULL, y = NULL, subtitle = ylab) +
    ggplot2::theme_minimal(base_size = 11, base_family = "") +
    ggplot2::theme(
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(colour = "#E7ECE8", linewidth = 0.4),
      axis.text = ggplot2::element_text(colour = "#667773"),
      plot.subtitle = ggplot2::element_text(colour = "#667773", size = 9, margin = ggplot2::margin(b = 4)),
      plot.margin = ggplot2::margin(4, 6, 0, 0),
      plot.background = ggplot2::element_rect(fill = "transparent", colour = NA),
      panel.background = ggplot2::element_rect(fill = "transparent", colour = NA)
    )
}

cmp_text <- function(chg, cmp, prev_year) {
  switch(cmp %||% "sin_anterior",
         ok = paste("respecto a", prev_year),
         sin_base = "Sin base de comparación (anterior = 0)",
         sin_produccion = "Sin producción en ambos ejercicios",
         sin_anterior = "Sin ejercicio anterior publicado",
         "—")
}

detail_ui <- function(atlas, level, id, ind_id, year) {
  g <- atlas$geo[[level]]
  z <- g[g$id == id, ]
  ind <- atlas$indicators[[ind_id]]
  s <- zone_series(atlas, level, id, ind_id)
  cur <- s[s$ejercicio == year, ]
  nat <- atlas$national[atlas$national$ejercicio == year, ]
  share <- if (ind_id %in% c("prod", "venta", "rem")) {
    tot <- nat[[ind_id]]
    if (!is.na(cur$value) && tot > 0) paste0(fmt_num(100 * cur$value / tot, 1), " % del total nacional") else NULL
  }
  kicker <- if (level == "ae") "Área de enumeración" else "Departamento"
  title <- if (level == "ae") z$name else z$dep_name
  sub <- if (level == "ae") {
    sprintf("%s · código %s · %s km²", z$dep_name, z$id, fmt_int(z$area_km2))
  } else sprintf("%s km²", fmt_int(z$area_km2))
  un <- atlas$unassigned
  dep_note <- if (level == "dep") {
    u <- un[un$dep == id & un$ejercicio == year, ]
    if (nrow(u) && u$litros > 0) {
      p(sprintf("Incluye %s L de establecimientos sin área de enumeración asignada.", fmt_int(u$litros)))
    }
  }
  estado <- atlas$years_meta[[as.character(year)]]$estado
  tagList(
    div(class = "detail-head",
        div(div(class = "detail-kicker", kicker),
            h2(class = "detail-title", title),
            div(class = "detail-sub num", sub)),
        tags$button(type = "button", class = "btn-icon", id = "btn-close-detail",
                    `aria-label` = "Cerrar detalle", icon("x"))),
    div(class = "detail-body",
      div(class = "detail-stats",
          div(class = "detail-stat",
              div(class = "kpi-label", paste(ind$short, year)),
              div(class = "kpi-value num", fmt_value(cur$value, ind)),
              if (!is.null(share)) div(class = "kpi-delta num", share)),
          div(class = "detail-stat",
              div(class = "kpi-label", "Cambio anual"),
              div(class = paste("kpi-value num"),
                  if (identical(cur$cmp, "ok")) fmt_pct(cur$chg) else "—"),
              div(class = "kpi-delta", cmp_text(cur$chg, cur$cmp, year - 1)))),
      div(class = "detail-section",
          h3(paste("Serie", min(atlas$years_all), "–", max(atlas$years_all))),
          div(class = "detail-plot", plotOutput("detail_plot", height = "150px"))),
      div(class = "detail-section",
          tags$table(class = "detail-table",
            tags$thead(tags$tr(tags$th("Ejercicio"), tags$th(ind$short), tags$th("Variación"))),
            tags$tbody(lapply(seq_len(nrow(s)), function(i) {
              r <- s[i, ]
              tags$tr(class = if (r$ejercicio == year) "is-current",
                      tags$td(class = "num", r$ejercicio),
                      tags$td(class = "num", if (is.na(r$value)) "sin datos" else fmt_value(r$value, ind)),
                      tags$td(class = "num",
                              if (is.na(r$value)) "—"
                              else if (identical(r$cmp, "ok")) fmt_pct(r$chg)
                              else if (identical(r$cmp, "sin_base")) "sin base"
                              else "—"))
            })))),
      div(class = "detail-section detail-source",
          h3("Fuente y observaciones"),
          p(paste0("MGAP · DICOSE–SNIG, declaración jurada de existencias, ejercicio ", year,
                   if (!is.null(estado)) paste0(" (", estado, ")"), ".")),
          dep_note,
          if (level == "ae") p("Cada declaración se asigna completa al área de su padrón de mayor superficie: una empresa con varios predios puede concentrar su producción en una sola área. No se localizan tambos individuales."),
          if (ind_id == "dens") p("Densidad sobre la superficie total del área; no equivale a rendimiento por hectárea lechera."),
          if (ind_id == "rem") p("Cuenta números DICOSE con venta a industria; no se suman con otros destinos."))
    )
  )
}

about_modal <- function(atlas) {
  chk <- atlas$checks
  ok <- sum(vapply(chk, `[[`, logical(1), "ok"))
  ym <- atlas$years_meta
  inale <- atlas$inale
  modalDialog(
    title = "Fuentes, método y limitaciones",
    size = "l", easyClose = TRUE, footer = modalButton("Cerrar"),
    h3("Fuente principal"),
    p("Declaraciones juradas de existencias DICOSE–SNIG del Ministerio de Ganadería, Agricultura y Pesca (MGAP), publicadas en el Catálogo Nacional de Datos Abiertos. Recurso «Producción de leche»: litros producidos en el ejercicio, desagregados por destino, especie y área de enumeración."),
    tags$table(class = "table table-sm",
      tags$thead(tags$tr(tags$th("Ejercicio"), tags$th("Período"), tags$th("Estado"), tags$th("Filas"), tags$th("Descarga"))),
      tags$tbody(lapply(ym, function(m) tags$tr(
        tags$td(tags$a(href = m$url_dataset, target = "_blank", rel = "noopener", m$ejercicio)),
        tags$td(m$periodo), tags$td(m$estado), tags$td(class = "num", fmt_int(m$filas)),
        tags$td(substr(m$descargado, 1, 10)))))),
    h3("Definiciones"),
    tags$ul(lapply(atlas$indicators, function(i) tags$li(strong(i$label, .noWS = "after"), ": ", i$desc))),
    p("Solo bovinos de leche (especie 11). La leche de caprinos (especie 4, ",
      fmt_num(sum(atlas$especies$litros[atlas$especies$especie == "4"]) / 1e6 / length(atlas$years), 1),
      " M L por ejercicio en promedio) se excluye: según los metadatos, esa especie no tiene control de calidad."),
    p("No se usa el recurso «Producción de leche en establecimiento»: sus litros son los industrializados en el predio (queso, manteca…). Coinciden con el destino 3 ya incluido en la producción."),
    h3("Territorio"),
    p("Áreas de enumeración de DIEA (MGAP, SNIA — Unidades Estadísticas), 637 polígonos con código CCOMPAE de 7 dígitos: departamento (INE), área de supervisión y área. Los códigos de las tablas pierden el cero inicial y se normalizan como texto de 7 dígitos. El 100 % de las áreas con leche tiene polígono en los cinco ejercicios. Los códigos de departamento DICOSE (Montevideo = 10) se traducen a la nomenclatura INE por nombre."),
    p("Límites departamentales: MGAP, SNIA — Unidades Administrativas. El recurso del catálogo indicado inicialmente responde 404. Se excluye el polígono «Límite contestado»."),
    if (!is.null(inale)) tagList(
      h3("Contraste con INALE"),
      p("Remisión mensual a planta (INALE) sumada de julio a junio para cada ejercicio."),
      tags$table(class = "table table-sm",
        tags$thead(tags$tr(tags$th("Ejercicio"), tags$th("Remisión INALE"), tags$th("Producción DICOSE"), tags$th("Vendida DICOSE"), tags$th("A industria DICOSE"))),
        tags$tbody(lapply(seq_len(nrow(inale)), function(i) { r <- inale[i, ]; tags$tr(
          tags$td(r$ejercicio), tags$td(class = "num", paste(fmt_num(r$remision_ML, 0), "M L")),
          tags$td(class = "num", sprintf("%s (%s×)", fmt_num(r$prod_ML, 0), fmt_num(r$ratio_prod, 2))),
          tags$td(class = "num", sprintf("%s (%s×)", fmt_num(r$venta_ML, 0), fmt_num(r$ratio_venta, 2))),
          tags$td(class = "num", sprintf("%s (%s×)", fmt_num(r$ind_ML, 0), fmt_num(r$ratio_ind, 2))))}))),
      p("La producción declarada supera a la remisión (entre 1,05 y 1,10 veces), como corresponde al consumo en el predio y a la industrialización propia. La venta a industria declarada queda debajo de la remisión y oscila frente a «cuota o reparto»: por eso el atlas muestra la leche vendida agregada.")
    ),
    h3("Limitaciones"),
    tags$ul(
      tags$li("Datos declarados por ejercicio (1 de julio – 30 de junio): no hay estacionalidad ni datos mensuales."),
      {
        pre <- names(Filter(function(m) identical(m$estado, "preliminar"), ym))
        if (length(pre)) tags$li(sprintf("Ejercicios publicados como preliminares: %s. Pueden cambiar si el MGAP publica datos actualizados.", paste(pre, collapse = ", ")))
      },
      tags$li("No se localizan tambos individuales ni se generan coordenadas: cada valor corresponde a un polígono oficial."),
      tags$li("No hay supresión estadística en la fuente: las áreas sin filas corresponden a cero litros declarados."),
      tags$li("Cada declaración se asigna completa al área de su padrón de mayor superficie. Algunas áreas concentran grandes volúmenes de pocos declarantes. Por ejemplo, el área 0601004 (Durazno) reúne cerca del 9 % de la producción nacional, en su mayoría industrializada en el predio. La escala de raíz cuadrada ayuda a leer el resto del territorio."),
      tags$li("La cartografía de áreas es la vigente; los códigos son estables en 2021–2025, pero no hay capas históricas publicadas para verificar cambios de límite."),
      tags$li("La altura de las extrusiones es una representación estadística, no el relieve.")
    ),
    h3("Controles de validación"),
    p(sprintf("%d de %d controles superados al preparar los datos (%s).", ok, length(chk), atlas$version)),
    tags$details(tags$summary("Ver controles"),
                 tags$ul(lapply(chk, function(c) tags$li(if (c$ok) "✓ " else "✗ ", c$detalle)))),
    h3("Mapa base"),
    p("Teselas vectoriales de OpenFreeMap (sin clave), © OpenMapTiles, datos © colaboradores de OpenStreetMap. Requieren conexión a internet; sin ella, el atlas se muestra sobre un fondo liso con sus geometrías locales. Tipografía Inter (SIL OFL) e iconos Lucide (ISC), servidos localmente.")
  )
}
