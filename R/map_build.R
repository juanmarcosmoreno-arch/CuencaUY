# Widget inicial del mapa. Se construye una sola vez por sesión; después solo se
# actualiza con maplibre_proxy() (propiedades de pintura, filtros y visibilidad),
# así la cámara, el zoom y la selección se conservan al cambiar de ejercicio.

LEVEL_LAYERS <- list(
  ae  = list(fill = "ae-3d",  line = "ae-line",  sel = "ae-sel",  src = "ae-src"),
  dep = list(fill = "dep-3d", line = "dep-line", sel = "dep-sel", src = "dep-src")
)
DATA_LAYERS <- c("dep-3d", "ae-3d")

# Las capas del atlas se insertan debajo de la primera etiqueta del mapa base
# para que los topónimos queden legibles sobre las extrusiones.
first_label_layer <- function(style) {
  for (l in style$layers) if (identical(l$type, "symbol")) return(l$id)
  NULL
}

build_map <- function(atlas, layers, style, state) {
  before <- first_label_layer(style)
  sc <- function(level) atlas$scales[[level]][[state$ind]]
  vis <- function(level) if (state$level == level) "visible" else "none"

  m <- maplibre(
    style = style,
    center = c(-56.0, -32.75),
    zoom = 5.6,
    pitch = 45,
    bearing = -8,
    projection = "mercator",
    minZoom = 4.5,
    maxZoom = 12,
    maxPitch = 70,
    maxBounds = list(c(-62.5, -38.5), c(-49.5, -27.5)),
    attributionControl = list(compact = TRUE),
    dragRotate = TRUE,
    fadeDuration = 150
  )

  for (level in c("dep", "ae")) {
    L <- LEVEL_LAYERS[[level]]
    s <- sc(level)
    m <- m |>
      add_source(id = L$src, data = layers[[level]]) |>
      add_fill_extrusion_layer(
        id = L$fill, source = L$src,
        fill_extrusion_color = color_expr(state$ind, state$year, s$max, state$mode,
                                          state$transform, s$chg_lim),
        fill_extrusion_height = height_expr(state$ind, state$year, s$max,
                                            state$transform, state$dim),
        fill_extrusion_opacity = 0.93,
        fill_extrusion_vertical_gradient = TRUE,
        visibility = vis(level),
        before_id = before
      ) |>
      add_line_layer(
        id = L$line, source = L$src,
        line_color = if (level == "dep") "#7F8E89" else "#FFFFFF",
        line_width = if (level == "dep") 0.9 else 0.5,
        line_opacity = if (level == "dep") 0.75 else 0.7,
        visibility = vis(level),
        before_id = before
      ) |>
      add_line_layer(
        id = L$sel, source = L$src,
        line_color = COL_SEL, line_width = 2.4,
        filter = sel_filter(NULL),
        visibility = vis(level),
        before_id = before
      )
  }
  # Límites departamentales como contexto también en el nivel de áreas.
  m |>
    add_line_layer(
      id = "dep-context", source = "dep-src",
      line_color = "#55655F", line_width = 1.1, line_opacity = 0.55,
      visibility = if (state$level == "ae") "visible" else "none",
      before_id = before
    )
}
