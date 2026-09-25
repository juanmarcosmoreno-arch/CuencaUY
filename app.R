# Atlas Lechero Uruguay — aplicación Shiny
#
# Ejecutar desde la raíz del proyecto:
#   RStudio:  abrir app.R y pulsar «Run App»
#   Consola:  Rscript -e "shiny::runApp('.', launch.browser = TRUE)"
#
# La app solo lee datos locales ya procesados (data/atlas.rds). Para generarlos
# o actualizarlos: Rscript scripts/run_pipeline.R

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(mapgl)
  library(sf)
  library(dplyr)
  library(ggplot2)
})

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f, local = TRUE)

# Carga única al iniciar el proceso (compartida por todas las sesiones) --------
ATLAS <- order_indicators(add_climate(load_atlas()))
if (!is.null(ATLAS)) {
  LAYERS <- list(dep = build_layer_data(ATLAS, "dep"), ae = build_layer_data(ATLAS, "ae"))
  SEARCH <- build_search_index(ATLAS)
  STYLE  <- tryCatch(load_basemap_style(), error = function(e) offline_style())
  if (identical(Sys.getenv("ATLAS_OFFLINE"), "1")) STYLE <- offline_style()
}

ui <- atlas_ui(ATLAS)

server <- function(input, output, session) {
  if (is.null(ATLAS)) return(invisible())

  init <- list(year = max(ATLAS$years), ind = "prod", level = "dep",
               mode = "value", transform = "linear", dim = "3d")

  # Estado de la vista -------------------------------------------------------
  year <- reactive({
    y <- suppressWarnings(as.integer(input$year))
    if (length(y) != 1 || is.na(y) || !(y %in% ATLAS$years)) init$year else y
  })
  ind       <- reactive(input$indicator %||% init$ind)
  level     <- reactive(input$level %||% init$level)
  # Los indicadores climáticos no tienen modo de variación: color = clima.
  mode      <- reactive(if (is_climate(ind())) "value" else input$mode %||% init$mode)
  transform <- reactive(input$transform %||% init$transform)
  dim       <- reactive(if (identical(input$dim, "2d")) "2d" else "3d")
  selected  <- reactiveVal(NULL)   # list(level, id)

  sel_id <- reactive({
    s <- selected()
    if (!is.null(s) && identical(s$level, level())) s$id else NULL
  })

  # Mapa: se construye una única vez ------------------------------------------
  output$map <- renderMaplibre({
    build_map(ATLAS, LAYERS, STYLE, init)
  })
  proxy <- maplibre_proxy("map", session)

  # El widget informa el zoom al terminar de cargar: a partir de ahí se aceptan
  # actualizaciones por proxy.
  map_ready <- reactiveVal(FALSE)
  observeEvent(input$map_zoom, map_ready(TRUE), once = TRUE, ignoreInit = FALSE)

  session$sendCustomMessage("atlas-init", list(
    years = ATLAS$years, years_all = ATLAS$years_all, year = init$year,
    search = lapply(seq_len(nrow(SEARCH)), function(i) list(
      level = SEARCH$level[i], id = SEARCH$id[i], name = SEARCH$name[i],
      dep = SEARCH$dep[i], bbox = SEARCH$bbox[[i]])),
    layers = DATA_LAYERS
  ))

  # Estilo del nivel activo: color y altura (escala fija por indicador y nivel).
  observe({
    req(map_ready())
    lv <- level(); k <- ind(); y <- year()
    s <- ATLAS$scales[[lv]][[k]]
    # Con clima, la altura sigue mostrando la producción (su propia escala fija).
    hk <- if (is_climate(k)) "prod" else k
    hs <- ATLAS$scales[[lv]][[hk]]
    L <- LEVEL_LAYERS[[lv]]
    proxy |>
      set_paint_property(L$fill, "fill-extrusion-color",
                         color_expr(k, y, s$max, mode(), transform(), s$chg_lim, sel_id())) |>
      set_paint_property(L$fill, "fill-extrusion-height",
                         height_expr(hk, y, hs$max, transform(), dim()))
    session$sendCustomMessage("atlas-state", list(
      year = y, ind = k, level = lv, mode = mode(), dim = dim(), climate = is_climate(k),
      label = ATLAS$indicators[[k]]$short, unit = ATLAS$indicators[[k]]$unit_short
    ))
  })

  # Cambio de nivel: visibilidad de capas.
  observe({
    req(map_ready())
    lv <- level()
    for (l in names(LEVEL_LAYERS)) {
      vis <- if (l == lv) "visible" else "none"
      for (id in unlist(LEVEL_LAYERS[[l]][c("fill", "line", "sel")])) {
        proxy |> set_layout_property(id, "visibility", vis)
      }
    }
    proxy |> set_layout_property("dep-context", "visibility", if (lv == "ae") "visible" else "none")
  })

  # Contorno de la zona seleccionada.
  observe({
    req(map_ready())
    id <- sel_id()
    for (l in names(LEVEL_LAYERS)) {
      proxy |> set_filter(LEVEL_LAYERS[[l]]$sel, sel_filter(if (l == level()) id else NULL))
    }
  })

  # Selección (clic en el mapa o buscador) -------------------------------------
  observeEvent(input$atlas_select, {
    s <- input$atlas_select
    if (is.null(s$id) || !nzchar(s$id)) { selected(NULL); return() }
    lv <- s$level %||% level()
    if (!(s$id %in% ATLAS$geo[[lv]]$id)) return()
    if (lv != level()) updateRadioButtons(session, "level", selected = lv)
    selected(list(level = lv, id = s$id))
  }, ignoreNULL = FALSE)

  observeEvent(input$close_detail, selected(NULL))

  # Al cambiar de nivel, un área seleccionada pasa a su departamento.
  observeEvent(level(), {
    s <- selected()
    if (is.null(s) || identical(s$level, level())) return()
    if (s$level == "ae" && level() == "dep") {
      selected(list(level = "dep", id = substr(s$id, 1, 2)))
    } else {
      selected(NULL)
    }
  }, ignoreInit = TRUE)

  observe({
    session$sendCustomMessage("atlas-detail", list(open = !is.null(sel_id())))
  })

  # Paneles ----------------------------------------------------------------
  output$year_card   <- renderUI(year_card_ui(ATLAS, year()))
  output$kpis        <- renderUI(kpis_ui(ATLAS, year()))
  output$metric_note <- renderUI(metric_note_ui(ATLAS, ind(), level()))
  output$legend      <- renderUI(legend_ui(ATLAS, ind(), level(), year(), mode(), transform(), dim()))

  output$detail <- renderUI({
    id <- sel_id()
    if (is.null(id)) return(NULL)
    detail_ui(ATLAS, level(), id, ind(), year())
  })
  output$detail_plot <- renderPlot({
    id <- sel_id(); req(id)
    detail_plot(zone_series(ATLAS, level(), id, ind()), year(), ATLAS$indicators[[ind()]])
  }, bg = "transparent", res = 110)

  observeEvent(input$about, showModal(about_modal(ATLAS)))
}

shinyApp(ui, server)
