# Descarga la cartografía oficial y guarda los originales sin simplificar en
# data-raw/geo/:
#   1. Áreas de enumeración (AE) — MGAP/DIEA, SNIA Temas › Unidades Estadísticas, capa 5.
#   2. AE — servicio alternativo del SNIG (MapasBase/AAEE), para contraste de
#      códigos y límites en 03_prepare.R.
#   3. Límites departamentales — MGAP, SNIA Temas › UnidadesAdministrativas, capa 1.
#   4. Límites departamentales del Catálogo Nacional de Datos Abiertos (recurso
#      3c1b430a…). En septiembre de 2026 el recurso responde 404; se intenta
#      igualmente y el resultado queda registrado en el manifiesto.
#
# Los servicios ArcGIS REST devuelven como máximo `maxRecordCount` entidades
# por consulta, así que se pagina con resultOffset.
#
# Uso: Rscript scripts/02_download_geometry.R [--refresh]

source("scripts/_common.R")
suppressPackageStartupMessages(library(sf))

args    <- commandArgs(trailingOnly = TRUE)
refresh <- "--refresh" %in% args
geo_dir <- file.path(DIR_RAW, "geo")
dir.create(geo_dir, recursive = TRUE, showWarnings = FALSE)

MGAP_SNIA <- "https://mapas.mgap.gub.uy/arcgis/rest/services/SNIA_Temas"
LAYERS <- tibble::tribble(
  ~id,             ~url,                                                             ~titulo,
  "ae_mgap",       paste0(MGAP_SNIA, "/Unidades_Estad%C3%ADsticas/MapServer/5"),     "MGAP SNIA — Unidades Estadísticas: Áreas de Enumeración (AE)",
  "departamentos", paste0(MGAP_SNIA, "/UnidadesAdministrativas/MapServer/1"),        "MGAP SNIA — Unidades Administrativas: Límites Departamentales"
)
AE_SNIG   <- "https://web.snig.gub.uy/arcgisserver/rest/services/MapasBase/AAEE/MapServer"
DEPTO_PKG <- "9bfa6e97-f40f-437e-aa13-a3406c50f762"
DEPTO_RES <- "3c1b430a-c010-4db1-880d-bdc0f11e4ce9"

now_iso <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
rel     <- function(p) sub(paste0(PROJECT_ROOT, "/"), "", p, fixed = TRUE)

# Descarga completa de una capa ArcGIS REST como GeoJSON en EPSG:4326.
arcgis_layer_to_geojson <- function(layer_url, dest, refresh = FALSE) {
  info_path <- sub("\\.geojson$", "_info.json", dest)
  if (file.exists(dest) && file.exists(info_path) && !refresh) {
    msg("  caché: ", basename(dest))
    return(read_json(info_path))
  }
  info <- get_json(paste0(layer_url, "?f=pjson"))
  write_json(info, info_path, auto_unbox = TRUE, pretty = TRUE)
  oid  <- info$objectIdField %||% "OBJECTID"
  page <- min(info$maxRecordCount %||% 1000, 1000)
  cnt  <- get_json(paste0(layer_url, "/query?where=1%3D1&returnCountOnly=true&f=json"))$count
  msg("  ", info$name, ": ", cnt, " entidades")
  parts  <- list()
  offset <- 0
  while (offset < cnt) {
    q <- paste0(layer_url, "/query?where=1%3D1&outFields=*&returnGeometry=true",
                "&outSR=4326&f=geojson&orderByFields=", oid,
                "&resultOffset=", offset, "&resultRecordCount=", page)
    tmp <- tempfile(fileext = ".geojson")
    base_request(q, timeout = 300) |> req_perform(path = tmp)
    part <- st_read(tmp, quiet = TRUE)
    if (!nrow(part)) break
    parts[[length(parts) + 1]] <- part
    offset <- offset + nrow(part)
  }
  all <- do.call(rbind, parts)
  if (nrow(all) != cnt) stop("Se esperaban ", cnt, " entidades y se obtuvieron ", nrow(all))
  if (file.exists(dest)) unlink(dest)
  st_write(all, dest, quiet = TRUE, driver = "GeoJSON")
  info
}

rows <- list()
add_row <- function(...) rows[[length(rows) + 1]] <<- tibble::tibble(...)

layer_row <- function(id, url, titulo, dest, info, error = NA) {
  ok <- is.na(error)
  add_row(fuente = "geo", ejercicio = NA, estado = NA, dataset_id = id,
          dataset_titulo = titulo, recurso_id = id,
          recurso_nombre = info$name %||% NA,
          recurso_descripcion = info$description %||% NA, formato = "GeoJSON (EPSG:4326)",
          url = url, archivo = if (ok) rel(dest) else NA, descargado = now_iso(),
          bytes = if (ok) file.size(dest) else NA, md5 = if (ok) file_md5(dest) else NA,
          http = NA, error = error, recurso_modificado = NA, dataset_modificado = NA)
}

# 1 y 3. Capas del MGAP --------------------------------------------------------
for (i in seq_len(nrow(LAYERS))) {
  L <- LAYERS[i, ]
  msg(L$titulo, "…")
  dest <- file.path(geo_dir, paste0(L$id, ".geojson"))
  info <- tryCatch(arcgis_layer_to_geojson(L$url, dest, refresh),
                   error = function(e) { msg("  ✗ ", conditionMessage(e)); e })
  if (inherits(info, "error")) layer_row(L$id, L$url, L$titulo, dest, list(), conditionMessage(info))
  else layer_row(L$id, L$url, L$titulo, dest, info)
}

# 2. Servicio alternativo del SNIG -------------------------------------------
msg("Áreas de enumeración (SNIG, alternativa)…")
tryCatch({
  svc <- get_json(paste0(AE_SNIG, "?f=pjson"))
  write_json(svc, file.path(geo_dir, "ae_snig_service.json"), auto_unbox = TRUE, pretty = TRUE)
  lyr <- Filter(function(l) grepl("enumer|aaee|area", l$name, ignore.case = TRUE), svc$layers)
  if (!length(lyr)) lyr <- svc$layers
  url  <- paste0(AE_SNIG, "/", lyr[[1]]$id)
  dest <- file.path(geo_dir, "ae_snig.geojson")
  info <- arcgis_layer_to_geojson(url, dest, refresh)
  layer_row("ae_snig", url, "SNIG MapasBase — AAEE", dest, info)
}, error = function(e) {
  msg("  ✗ ", conditionMessage(e))
  layer_row("ae_snig", AE_SNIG, "SNIG MapasBase — AAEE", NA, list(), conditionMessage(e))
})

# 4. Recurso del catálogo (referencia) ----------------------------------------
msg("Límites departamentales (Catálogo de Datos Abiertos)…")
cat_url <- sprintf("https://catalogodatos.gub.uy/dataset/%s/resource/%s", DEPTO_PKG, DEPTO_RES)
st <- tryCatch(resp_status(base_request(cat_url, 30) |>
                             req_error(is_error = function(r) FALSE) |> req_perform()),
               error = function(e) NA_integer_)
msg("  HTTP ", st, if (!identical(st, 200L)) " — no disponible; se usan los límites del MGAP.")
add_row(fuente = "geo", ejercicio = NA, estado = NA, dataset_id = DEPTO_PKG,
        dataset_titulo = "Límites departamentales (Catálogo Nacional de Datos Abiertos)",
        recurso_id = DEPTO_RES, recurso_nombre = "Límites departamentales",
        recurso_descripcion = "Recurso indicado en el encargo; sustituido por la capa del MGAP.",
        formato = NA, url = cat_url, archivo = NA, descargado = now_iso(), bytes = NA,
        md5 = NA, http = st, error = if (identical(st, 200L)) NA else paste("HTTP", st),
        recurso_modificado = NA, dataset_modificado = NA)

write_manifest(bind_rows(rows))
msg("Listo.")
