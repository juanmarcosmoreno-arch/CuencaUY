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
      wide[[sprintf("%s_%d", k, y)]] <- if (is_climate(k)) round(vy[[k]][i], 1) else vy[[k]][i]
      if (!is_climate(k)) {
        wide[[sprintf("%s_%d_c", k, y)]] <- round(vy[[paste0(k, "_chg")]][i], 2)
        wide[[sprintf("%s_%d_s", k, y)]] <- unname(STATUS_CODE[vy[[paste0(k, "_cmp")]][i]])
      }
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
# La extrusión se reduce al acercar la cámara (multiplicador por zoom) para que
# las zonas altas no tapen el entorno cuando se inspecciona un área de cerca.
ZOOM_FACTOR <- list(c(6.5, 1), c(8, 0.42), c(10, 0.13), c(12, 0.045))

height_expr <- function(ind, year, max, transform = "linear", dim = "3d") {
  if (dim == "2d") return(0)
  v <- list("to-number", list("get", prop_name(ind, year)), 0)
  base <- if (transform == "sqrt") {
    list("*", list("sqrt", v), H_MAX / sqrt(max))
  } else {
    list("*", v, H_MAX / max)
  }
  e <- list("interpolate", list("linear"), list("zoom"))
  for (zf in ZOOM_FACTOR) e <- c(e, list(zf[1], list("*", base, zf[2])))
  e
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
  if (ind == "lluvia") {
    # Divergente: terracota = más seco que lo normal, verde azulado = más húmedo.
    d <- seq(-chg_lim, chg_lim, length.out = length(PAL_DIV))
    e <- list("interpolate", list("linear"),
              list("to-number", list("get", prop_name(ind, year)), 0))
    for (i in seq_along(d)) e <- c(e, list(d[i], PAL_DIV[i]))
  } else if (ind == "thi") {
    s <- seq(0, max, length.out = length(PAL_THI))
    e <- list("interpolate", list("linear"),
              list("to-number", list("get", prop_name(ind, year)), 0))
    for (i in seq_along(s)) e <- c(e, list(s[i], PAL_THI[i]))
  } else if (mode == "value") {
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

# Clima (opcional): si existe data/clima.rds se agregan dos indicadores. El color
# muestra el clima del ejercicio; la altura sigue siendo la producción de leche.
PAL_THI <- c("#FBEFE3", "#F4D2B4", "#E9AD82", "#D98657", "#C0613A", "#963F24")
CLIMATE_IND <- c("lluvia", "thi")

add_climate <- function(atlas, path = file.path("data", "clima.rds")) {
  if (is.null(atlas) || !file.exists(path)) return(atlas)
  cl <- readRDS(path)
  for (lv in c("ae", "dep")) {
    e <- cl$ejercicios[[lv]] |>
      dplyr::transmute(id, ejercicio, lluvia_mm = lluvia, lluvia = lluvia_anom, thi = thi_dias)
    atlas$values[[lv]] <- atlas$values[[lv]] |> dplyr::left_join(e, by = c("id", "ejercicio"))
    v <- atlas$values[[lv]]
    atlas$scales[[lv]]$lluvia <- list(max = 50, max_raw = max(abs(v$lluvia), na.rm = TRUE), chg_lim = 50)
    atlas$scales[[lv]]$thi <- list(max = ceiling(max(v$thi, na.rm = TRUE) / 10) * 10,
                                   max_raw = max(v$thi, na.rm = TRUE), chg_lim = NA)
  }
  atlas$indicators$lluvia <- list(
    id = "lluvia", label = "Lluvia del ejercicio", short = "Lluvia", group = "clima",
    unit = "% respecto a la normal 1991–2020", unit_short = "%", big = 1, big_unit = "% vs. normal 1991–2020",
    desc = "Precipitación acumulada de julio a junio (CHIRPS v2.0, ~5 km), promediada en cada área, frente a su promedio 1991–2020. El color muestra la lluvia; la altura, la producción de leche.")
  atlas$indicators$thi <- list(
    id = "thi", label = "Estrés térmico", short = "Días THI ≥ 72", group = "clima",
    unit = "días con THI medio ≥ 72", unit_short = "días", big = 1, big_unit = "días en el ejercicio",
    desc = sprintf("Días del ejercicio con índice de temperatura y humedad medio ≥ %d, umbral habitual de estrés en vacas lecheras (NASA POWER, celdas de ~55 km). El color muestra el estrés; la altura, la producción.", cl$thi_umbral))
  atlas$clima <- cl
  atlas
}

is_climate <- function(ind) ind %in% CLIMATE_IND
