# Componentes de la interfaz. HTML propio, sin cajas de dashboard: los controles
# de radio usan el binding estándar de Shiny (clase shiny-input-radiogroup).

radio_group <- function(id, choices, selected, class = "segmented", label = NULL,
                        subtitles = NULL, disabled = character(0), separators = list()) {
  items <- lapply(seq_along(choices), function(i) {
    val <- unname(choices[i]); lab <- names(choices)[i]
    input <- tags$input(type = "radio", name = id, value = val,
                        checked = if (identical(val, selected)) NA,
                        disabled = if (val %in% disabled) NA)
    if (class == "choice-list") {
      tags$label(class = "choice", input,
                 span(class = "choice-box",
                      span(class = "choice-title", lab),
                      if (!is.null(subtitles)) span(class = "choice-sub", subtitles[i])))
    } else {
      tags$label(input, span(lab))
    }
  })
  # Separadores con título antes de ciertas opciones (p. ej. «Clima»).
  for (val in rev(names(separators))) {
    pos <- match(val, unname(choices))
    if (!is.na(pos)) items <- append(items, list(div(class = "choice-sep", separators[[val]])), after = pos - 1)
  }
  div(class = "field",
      if (!is.null(label)) span(class = "field-label", id = paste0(id, "-label"), label),
      div(id = id, class = paste("shiny-input-radiogroup", class), role = "radiogroup",
          `aria-labelledby` = if (!is.null(label)) paste0(id, "-label"), items))
}

brand_mark <- function() {
  # Marca: barras que crecen sobre una línea de horizonte (altura = magnitud).
  HTML('<svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
    <path d="M4 19.5h16" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
    <rect x="5.5" y="12" width="3" height="6" rx="0.8" fill="currentColor" opacity=".55"/>
    <rect x="10.5" y="6.5" width="3" height="11.5" rx="0.8" fill="currentColor"/>
    <rect x="15.5" y="9.5" width="3" height="8.5" rx="0.8" fill="currentColor" opacity=".8"/>
  </svg>')
}

atlas_header <- function() {
  tags$header(class = "atlas-header",
    div(class = "brand",
        div(class = "brand-mark", brand_mark()),
        div(class = "brand-text",
            h1(class = "brand-title", "Atlas Lechero Uruguay"),
            p(class = "brand-sub", "La producción de leche, territorio por territorio"))),
    div(class = "header-meta",
        tags$button(type = "button", class = "btn-ghost", id = "btn-about",
                    icon("info"), span(class = "label", "Fuentes y método")))
  )
}

controls_panel <- function(atlas) {
  inds <- atlas$indicators
  tags$aside(class = "panel-left surface", id = "panel-left", `aria-label` = "Controles del atlas",
    div(class = "panel-head",
        span(class = "panel-kicker", "Explorar"),
        tags$button(type = "button", class = "btn-icon", id = "btn-collapse",
                    `aria-label` = "Ocultar panel", `aria-controls` = "panel-left",
                    icon("panel-left-close", "only-desktop"), icon("x", "only-mobile"))),
    div(class = "panel-body",
      div(class = "field field-search",
          tags$label(class = "field-label", `for` = "search-input", "Buscar zona"),
          div(class = "search", role = "combobox", `aria-expanded` = "false",
              `aria-owns` = "search-results", `aria-haspopup` = "listbox",
              icon("search"),
              tags$input(id = "search-input", type = "search", autocomplete = "off",
                         placeholder = "Departamento o código de área",
                         `aria-autocomplete` = "list", `aria-controls` = "search-results")),
          tags$ul(id = "search-results", class = "search-results", role = "listbox")),
      radio_group("indicator",
                  setNames(names(inds), vapply(inds, `[[`, "", "label")),
                  selected = "prod", class = "choice-list", label = "Indicador",
                  subtitles = unname(c(prod = "Litros, todos los destinos", venta = "Litros vendidos",
                                       dens = "Litros por km² de territorio", rem = "Números DICOSE",
                                       lluvia = "% respecto a 1991–2020",
                                       thi = "Días con THI ≥ 72")[names(inds)]),
                  separators = list(lluvia = tagList(span("Clima"), span(class = "choice-sep-sub", "La altura sigue mostrando la producción")))),
      radio_group("level", c("Departamentos" = "dep", "Áreas de enumeración" = "ae"),
                  selected = "dep", label = "Nivel territorial"),
      radio_group("mode", c("Magnitud" = "value", "Variación anual" = "change"),
                  selected = "value", label = "Color"),
      radio_group("transform", c("Lineal" = "linear", "Raíz cuadrada" = "sqrt"),
                  selected = "linear", label = "Escala de altura y color"),
      div(class = "metric-note", uiOutput("metric_note"))
    )
  )
}

map_controls <- function() {
  div(class = "map-controls surface", role = "toolbar", `aria-label` = "Controles del mapa",
      tags$button(type = "button", class = "btn-icon", id = "btn-zoom-in",
                  `aria-label` = "Acercar", title = "Acercar", icon("plus")),
      tags$button(type = "button", class = "btn-icon", id = "btn-zoom-out",
                  `aria-label` = "Alejar", title = "Alejar", icon("minus")),
      tags$hr(),
      tags$button(type = "button", class = "btn-icon", id = "btn-home",
                  `aria-label` = "Volver a Uruguay", title = "Volver a Uruguay", icon("house")),
      tags$button(type = "button", class = "btn-dim", id = "btn-dim",
                  `aria-label` = "Cambiar a vista 2D", title = "Alternar 2D / 3D",
                  `aria-pressed` = "true", "3D"))
}

detail_panel <- function() {
  tags$aside(class = "panel-detail surface", id = "panel-detail", `aria-label` = "Detalle de la zona",
             `aria-live` = "polite",
             uiOutput("detail"))
}

timeline <- function(atlas) {
  yrs <- atlas$years_all
  avail <- atlas$years
  tags$footer(class = "timeline", role = "group", `aria-label` = "Línea temporal de ejercicios",
    div(class = "tl-transport",
        tags$button(type = "button", class = "btn-icon", id = "btn-prev",
                    `aria-label` = "Ejercicio anterior", title = "Ejercicio anterior",
                    icon("chevron-left")),
        tags$button(type = "button", class = "btn-primary", id = "btn-play",
                    `aria-label` = "Reproducir", title = "Reproducir (barra espaciadora)",
                    span(class = "ic-play", icon("play")),
                    span(class = "ic-pause", style = "display:none", icon("pause"))),
        tags$button(type = "button", class = "btn-icon", id = "btn-next",
                    `aria-label` = "Ejercicio siguiente", title = "Ejercicio siguiente",
                    icon("chevron-right"))),
    div(class = "tl-track-wrap",
        div(class = "tl-track", id = "tl-track",
            div(class = "tl-progress", id = "tl-progress"),
            lapply(yrs, function(y) {
              ok <- y %in% avail
              tags$button(type = "button",
                          class = paste("tl-year", if (!ok) "is-missing"),
                          `data-year` = y,
                          disabled = if (!ok) NA,
                          `aria-label` = if (ok) paste("Ejercicio", y) else paste("Ejercicio", y, "sin datos publicados"),
                          title = if (ok) sprintf("Ejercicio %d (1 jul %d – 30 jun %d)", y, y - 1, y)
                                  else paste(y, "— sin datos validados"),
                          span(class = "tl-dot"), span(class = "tl-label num", y))
            }))),
    div(class = "tl-speed",
        span("Velocidad"),
        div(class = "segmented", role = "radiogroup", `aria-label` = "Velocidad de reproducción",
            lapply(list(c("0.5×", "1800"), c("1×", "1200"), c("2×", "700")), function(s) {
              tags$label(tags$input(type = "radio", name = "speed", value = s[2],
                                    checked = if (s[2] == "1200") NA), span(s[1]))
            }))),
    if (length(setdiff(yrs, avail))) {
      div(class = "tl-legend", span(class = "tl-dot is-missing-dot"), "Sin datos")
    }
  )
}

empty_state <- function() {
  div(class = "empty-state",
      div(class = "empty-card surface",
          h2("Faltan los datos procesados"),
          p("La aplicación arranca con datos locales. Genérelos una vez con:"),
          p(tags$code("Rscript scripts/run_pipeline.R")),
          p("El proceso descarga las fuentes oficiales (con caché), valida y guarda ",
            tags$code("data/atlas.rds"), ".")))
}

atlas_ui <- function(atlas) {
  page_fillable(
    title = "Atlas Lechero Uruguay",
    padding = 0, gap = 0,
    theme = bs_theme(
      version = 5, bg = "#F5F3EE", fg = "#172B2A", primary = "#176B60",
      base_font = font_collection("Inter Atlas", "Inter", "Source Sans 3", "system-ui",
                                  "-apple-system", "Segoe UI", "Roboto", "sans-serif"),
      "border-color" = "#DEE5DF", "border-radius" = "10px"
    ),
    tags$head(
      tags$meta(name = "viewport", content = "width=device-width, initial-scale=1, viewport-fit=cover"),
      tags$meta(name = "description", content = "Atlas interactivo de la producción de leche en Uruguay por departamento y área de enumeración, a partir de las declaraciones juradas DICOSE–SNIG del MGAP."),
      tags$meta(name = "theme-color", content = "#FFFFFF"),
      tags$link(rel = "preload", href = "fonts/inter-latin-wght-normal.woff2", as = "font",
                type = "font/woff2", crossorigin = NA),
      tags$link(rel = "stylesheet", href = "css/atlas.css"),
      tags$script(src = "js/atlas.js")
    ),
    div(class = "atlas", id = "atlas",
      atlas_header(),
      tags$main(class = "stage", id = "stage",
        if (is.null(atlas)) empty_state() else tagList(
          # El mapa va primero en el apilado visual pero último en el orden de
          # tabulación: los controles se recorren antes que el lienzo.
          controls_panel(atlas),
          tags$button(type = "button", class = "btn-icon panel-toggle", id = "btn-expand",
                      `aria-label` = "Mostrar panel de controles", `aria-controls` = "panel-left",
                      icon("panel-left-open", "only-desktop"), icon("layers", "only-mobile"),
                      span(class = "only-mobile toggle-label", "Explorar")),
          div(class = "overlay-top",
              div(class = "year-card surface", uiOutput("year_card")),
              div(class = "kpis surface", uiOutput("kpis"))),
          map_controls(),
          div(class = "legend surface", uiOutput("legend")),
          div(class = "basemap-status surface", id = "basemap-status", role = "status",
              icon("triangle-alert"),
              span("Mapa base no disponible: se muestran las geometrías locales.")),
          detail_panel(),
          div(class = "map-wrap", maplibreOutput("map", height = "100%"))
        )),
      if (!is.null(atlas)) timeline(atlas)
    )
  )
}
