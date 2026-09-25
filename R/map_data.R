# Carga del atlas procesado y construcción de las capas y expresiones del mapa.
# Todo lo costoso (lectura, pivotado, cajas envolventes) se hace una sola vez al
# iniciar la app; las reacciones solo generan expresiones de estilo.

PAL_SEQ  <- c("#EAF3E3", "#C9E4C3", "#9CCCA8", "#6DB096", "#3F9185", "#1F7470", "#0E5553")
PAL_DIV  <- c("#9A4B2A", "#C8845D", "#E8C7AC", "#F2EFE8", "#A8D2CE", "#57A3A1", "#1B6A70")
COL_ZERO <- "#E4E1D8"   # sin producción declarada
COL_NOBASE <- "#B9B3C9" # anterior = 0: sin base de comparación
COL_NOPREV <- "#D5DAD6" # sin ejercicio anterior publicado
COL_SEL  <- "#0B2F2C"   # zona seleccionada
H_MAX    <- 65000       # altura máxima (m) de la extrusión estadística

STATUS_CODE <- c(ok = 0L, sin_base = 1L, sin_produccion = 2L, sin_anterior = 3L)

load_atlas <- function(path = file.path("data", "atlas.rds")) {
  if (!file.exists(path)) return(NULL)
  readRDS(path)
}

# sf con una columna por indicador × ejercicio: valor, cambio y estado.
build_layer_data <- function(atlas, level) {
  g <- atlas$geo[[level]]
  v <- atlas$values[[level]]
  wide <- list()
  for (k in names(atlas$indicators)) {
    for (y in atlas$years) {
      vy <- v[v$ejercicio == y, ]
      i <- match(g$id, vy$id)
      wide[[sprintf("%s_%d", k, y)]]   <- vy[[k]][i]
      wide[[sprintf("%s_%d_c", k, y)]] <- round(vy[[paste0(k, "_chg")]][i], 2)
      wide[[sprintf("%s_%d_s", k, y)]] <- unname(STATUS_CODE[vy[[paste0(k, "_cmp")]][i]])
    }
  }
  out <- cbind(g[, c("id", "name", "dep_name")], as.data.frame(wide))
  sf::st_as_sf(out)
}

# Índice para el buscador y para encuadrar la zona elegida (sin cálculos
# espaciales durante la sesión).
build_search_index <- function(atlas) {
  one <- function(level) {
    g <- atlas$geo[[level]]
    bb <- lapply(sf::st_geometry(g), function(x) round(as.numeric(sf::st_bbox(x)), 4))
    data.frame(level = level, id = g$id, name = g$name, dep = g$dep_name,
               bbox = I(bb), stringsAsFactors = FALSE)
  }
  rbind(one("dep"), one("ae"))
}

prop_name <- function(ind, year, suffix = "") sprintf("%s_%d%s", ind, year, suffix)

# Altura: magnitud del indicador (escala fija por indicador y nivel). En 2D, 0.
height_expr <- function(ind, year, max, transform = "linear", dim = "3d") {
  if (dim == "2d") return(0)
  v <- list("to-number", list("get", prop_name(ind, year)), 0)
  if (transform == "sqrt") {
    list("*", list("sqrt", v), H_MAX / sqrt(max))
  } else {
    list("*", v, H_MAX / max)
  }
}

# Paradas de color fijas (lineal o raíz cuadrada) sobre [0, max].
seq_stops <- function(max, transform = "linear") {
  t <- seq(0, 1, length.out = length(PAL_SEQ))
  if (transform == "sqrt") t <- t^2
  s <- t * max
  s[1] <- max * 1e-9 # cualquier valor > 0 recibe color de la escala
  s
}

color_expr <- function(ind, year, max, mode = "value", transform = "linear",
                       chg_lim = 50, selected = NULL) {
  if (mode == "value") {
    stops <- seq_stops(max, transform)
    e <- list("interpolate", list("linear"),
              list("to-number", list("get", prop_name(ind, year)), 0),
              0, COL_ZERO)
    for (i in seq_along(stops)) e <- c(e, list(stops[i], PAL_SEQ[i]))
  } else {
    d <- seq(-chg_lim, chg_lim, length.out = length(PAL_DIV))
    ramp <- list("interpolate", list("linear"),
                 list("to-number", list("get", prop_name(ind, year, "_c")), 0))
    for (i in seq_along(d)) ramp <- c(ramp, list(d[i], PAL_DIV[i]))
    e <- list("match", list("to-number", list("get", prop_name(ind, year, "_s")), 3),
              0, ramp, 1, COL_NOBASE, 2, COL_ZERO, COL_NOPREV)
  }
  # La selección usa `match` en el nivel superior: mapgl reinterpreta un `case`
  # de primer nivel como estado de hover al actualizar por proxy.
  if (!is.null(selected) && nzchar(selected)) {
    e <- list("match", list("get", "id"), selected, COL_SEL, e)
  }
  e
}

sel_filter <- function(selected) {
  list("==", list("get", "id"), if (is.null(selected)) "" else selected)
}

# Estilo del mapa base: JSON local con teselas vectoriales de OpenFreeMap. Si las
# teselas no cargan, el fondo y las capas del atlas siguen visibles.
load_basemap_style <- function(path = file.path("data", "basemap_style.json")) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

# Estilo mínimo sin dependencias de red (solo fondo).
offline_style <- function() {
  list(version = 8, name = "Atlas — sin mapa base",
       sources = setNames(list(), character(0)),
       layers = list(list(id = "background", type = "background",
                          paint = list(`background-color` = "#EEEEE8"))))
}
