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

climate_finding <- function(atlas) {
  cl <- atlas$clima
  if (is.null(cl) || is.null(cl$panel_areas)) return(NULL)
  pa <- cl$panel_areas$coefs[cl$panel_areas$coefs$termino == "lluvia_anom", ]
  na <- cl$nacional_anual$datos
  p(strong("¿Explica el clima la producción?"), paste0(
    " No de forma detectable en 2021–2025. Comparando áreas dentro de cada ejercicio, +10 puntos de lluvia se asocian con ",
    fmt_pct(10 * pa$estimado, 1), " de producción (IC 95 %: ", fmt_pct(10 * pa$lo, 1), " a ", fmt_pct(10 * pa$hi, 1),
    "). A escala nacional, ", min(na$ejercicio[!is.na(na$d_rem)]), "–", max(na$ejercicio),
    ", tampoco hay asociación significativa. Ver «Fuentes y método»."))
}

metric_note_ui <- function(atlas, ind_id, level) {
  ind <- atlas$indicators[[ind_id]]
  if (is_climate(ind_id)) {
    return(tagList(p(strong(ind$label), " — ", ind$desc), climate_finding(atlas),
                   p("Asociación no es causalidad: precios, costos y decisiones de manejo pesan en la producción.")))
  }
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
  if (is_climate(ind_id)) {
    pal <- if (ind_id == "lluvia") PAL_DIV else PAL_THI
    stops <- seq(0, 1, length.out = length(pal))
    grad <- paste(sprintf("%s %.0f%%", pal, 100 * stops), collapse = ", ")
    ticks <- if (ind_id == "lluvia") {
      div(class = "legend-ticks num", span("≤ −50 %"), span("normal"), span("≥ +50 %"))
    } else {
      div(class = "legend-ticks num", span("0"), span(fmt_int(sc$max / 2)), span(paste(fmt_int(sc$max), "días")))
    }
    hs <- atlas$scales[[level]]$prod
    return(tagList(
      div(class = "legend-title", ind$label, " ", span(class = "legend-unit", paste0("(", ind$big_unit, ")"))),
      div(class = "legend-ramp", style = sprintf("background: linear-gradient(90deg, %s)", grad)),
      ticks,
      if (ind_id == "lluvia") div(class = "legend-extra", span("Terracota: más seco"), span("Verde azulado: más húmedo")),
      div(class = "legend-note",
          if (dim == "3d") sprintf("Altura: producción de leche (escala fija, máx. %s M L). ", fmt_num(hs$max / 1e6, 0)) else "Vista 2D: sin extrusión. ",
          if (ind_id == "lluvia") "Fuente: CHIRPS v2.0." else "Fuente: NASA POWER (celdas de ~55 km).")
    ))
  }
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
  chg <- v[[paste0(ind_id, "_chg")]] %||% rep(NA_real_, nrow(v))
  cmp <- v[[paste0(ind_id, "_cmp")]] %||% rep(NA_character_, nrow(v))
  data.frame(ejercicio = atlas$years_all) |>
    dplyr::left_join(data.frame(ejercicio = v$ejercicio, value = v[[ind_id]], chg = chg, cmp = cmp,
                                prod = v$prod, lluvia_mm = v$lluvia_mm %||% NA), by = "ejercicio")
}

detail_plot <- function(s, year, ind) {
  s$cur <- s$ejercicio == year
  if (ind$id == "lluvia") {
    s$sign <- ifelse(is.na(s$value), NA, ifelse(s$value < 0, "seco", "humedo"))
    return(ggplot2::ggplot(s, ggplot2::aes(x = factor(ejercicio), y = value)) +
      ggplot2::geom_hline(yintercept = 0, colour = "#B9C4BE", linewidth = 0.4) +
      ggplot2::geom_col(ggplot2::aes(fill = sign, alpha = cur), width = 0.62, na.rm = TRUE) +
      ggplot2::scale_fill_manual(values = c(seco = "#C8845D", humedo = "#57A3A1"), guide = "none") +
      ggplot2::scale_alpha_manual(values = c(`TRUE` = 1, `FALSE` = 0.5), guide = "none") +
      ggplot2::scale_y_continuous(labels = function(x) paste0(fmt_num(x, 0), " %"), n.breaks = 4) +
      ggplot2::labs(x = NULL, y = NULL, subtitle = "% respecto a 1991–2020") +
      ggplot2::theme_minimal(base_size = 11) +
      ggplot2::theme(panel.grid.major.x = ggplot2::element_blank(), panel.grid.minor = ggplot2::element_blank(),
                     panel.grid.major.y = ggplot2::element_line(colour = "#E7ECE8", linewidth = 0.4),
                     axis.text = ggplot2::element_text(colour = "#667773"),
                     plot.subtitle = ggplot2::element_text(colour = "#667773", size = 9),
                     plot.margin = ggplot2::margin(4, 6, 0, 0),
                     plot.background = ggplot2::element_rect(fill = "transparent", colour = NA),
                     panel.background = ggplot2::element_rect(fill = "transparent", colour = NA)))
  }
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
  climate <- is_climate(ind_id)
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
              div(class = "kpi-label", if (ind_id == "lluvia") paste("Lluvia", year, "vs. normal") else paste(ind$short, year)),
              div(class = "kpi-value num", fmt_value(cur$value, ind)),
              if (!is.null(share)) div(class = "kpi-delta num", share)),
          if (climate) div(class = "detail-stat",
              div(class = "kpi-label", paste("Producción", year)),
              div(class = "kpi-value num", fmt_value(cur$prod, atlas$indicators$prod)),
              if (ind_id == "lluvia" && !is.na(cur$lluvia_mm)) div(class = "kpi-delta num", paste(fmt_int(cur$lluvia_mm), "mm de lluvia")))
          else div(class = "detail-stat",
              div(class = "kpi-label", "Cambio anual"),
              div(class = paste("kpi-value num"),
                  if (identical(cur$cmp, "ok")) fmt_pct(cur$chg) else "—"),
              div(class = "kpi-delta", cmp_text(cur$chg, cur$cmp, year - 1)))),
      div(class = "detail-section",
          h3(paste("Serie", min(atlas$years_all), "–", max(atlas$years_all))),
          div(class = "detail-plot", plotOutput("detail_plot", height = "150px"))),
      div(class = "detail-section",
          tags$table(class = "detail-table",
            tags$thead(tags$tr(tags$th("Ejercicio"), tags$th(ind$short),
                               tags$th(if (climate) "Producción" else "Variación"))),
            tags$tbody(lapply(seq_len(nrow(s)), function(i) {
              r <- s[i, ]
              if (climate) return(tags$tr(class = if (r$ejercicio == year) "is-current",
                tags$td(class = "num", r$ejercicio),
                tags$td(class = "num", if (is.na(r$value)) "—" else if (ind_id == "lluvia") fmt_pct(r$value, 0) else fmt_int(r$value)),
                tags$td(class = "num", fmt_value(r$prod, atlas$indicators$prod))))
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
          if (ind_id == "rem") p("Cuenta números DICOSE con venta a industria; no se suman con otros destinos."),
          if (climate) p(if (ind_id == "lluvia") "Lluvia: CHIRPS v2.0 (UCSB), promedio del área, julio a junio." else "Estrés térmico: NASA POWER, celda de ~55 km más cercana al área.",
                         " Asociación no es causalidad."))
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
    p("El SNIG publica otra versión de la misma cartografía (MapasBase/AAEE), con los mismos códigos pero límites digitalizados de forma distinta: la intersección sobre la unión mediana por área es 0,91 y las superficies difieren un 3 % en la mediana. Los valores no cambian, porque se enlazan por código. Sí cambian el dibujo y el denominador de la densidad. El atlas usa la capa del MGAP; el pipeline puede regenerarse con la del SNIG (ATLAS_AE_SOURCE=snig)."),
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
    if (!is.null(atlas$clima)) {
      cl <- atlas$clima; pa <- cl$panel_areas; na <- cl$nacional_anual
      lb <- function(t) { r <- pa$coefs[pa$coefs$termino == t, ]; sprintf("%s (IC 95 %%: %s a %s)", fmt_pct(10 * r$estimado, 1), fmt_pct(10 * r$lo, 1), fmt_pct(10 * r$hi, 1)) }
      pl <- pa$placebo[1, ]
      tagList(
        h3("Clima"),
        p(paste0("Lluvia mensual CHIRPS v2.0 (UCSB/CHC, ~5 km, recorte vía IRI Data Library), promediada en cada polígono y comparada con la normal 1991–2020. Temperatura y humedad diarias de NASA POWER (MERRA-2, ~55 km): índice de temperatura y humedad (THI) y días con THI medio ≥ ", cl$thi_umbral, ". Todo por ejercicio de julio a junio.")),
        p(strong("Resultado: "), sprintf("en el panel de %d áreas (%d observaciones, efectos fijos por ejercicio) +10 puntos de lluvia del mismo ejercicio se asocian con %s de producción; los del ejercicio anterior, con %s. El placebo con la lluvia del ejercicio siguiente da %s (IC %s a %s). A escala nacional (INALE, %d ejercicios) ninguna correlación supera el umbral de significación (|r| < %s).",
          pa$areas, pa$n, lb("lluvia_anom"), lb("lluvia_prev"), fmt_pct(10 * pl$estimado, 1), fmt_pct(10 * pl$lo, 1), fmt_pct(10 * pl$hi, 1),
          na$n, fmt_num(na$r_crit, 2))),
        {
          s23 <- na$datos[na$datos$ejercicio == 2023, ]
          p(sprintf("Con los datos disponibles, el clima no explica de forma detectable los cambios de producción. La sequía de 2022–23 (%s de lluvia en la cuenca lechera) movió la remisión anual apenas un %s. Precios, costos y manejo (suplementación, reservas) dominan la variación. Pocas observaciones y resoluciones gruesas limitan la potencia del análisis; asociación no implica causalidad.",
                    fmt_pct(s23$lluvia_anom, 0), fmt_pct(s23$d_rem, 1)))
        }
      )
    },
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
                 tags$ul(lapply(chk, function(c) tags$li(
                   if (identical(c$nivel, "aviso")) "⚠ " else if (c$ok) "✓ " else "✗ ", c$detalle)))),
    h3("Mapa base"),
    p("Teselas vectoriales de OpenFreeMap (sin clave), © OpenMapTiles, datos © colaboradores de OpenStreetMap. Requieren conexión a internet; sin ella, el atlas se muestra sobre un fondo liso con sus geometrías locales. Tipografía Inter (SIL OFL) e iconos Lucide (ISC), servidos localmente.")
  )
}
