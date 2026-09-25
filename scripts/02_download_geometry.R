# Descarga la cartografía oficial:
#   1. Áreas de enumeración (MGAP, SNIA — Unidades Estadísticas, capa 5).
#   2. Áreas de enumeración, servicio alternativo del SNIG (se usa si 1 falla).
#   3. Límites departamentales (Catálogo Nacional de Datos Abiertos).
#
# Los servicios ArcGIS REST devuelven como máximo `maxRecordCount` entidades
# por consulta, así que se pagina con resultOffset. Los originales se guardan
# sin simplificar en data-raw/geo/.
#
# Uso: Rscript scripts/02_download_geometry.R [--refresh]

source("scripts/_common.R")
suppressPackageStartupMessages(library(sf))

args    <- commandArgs(trailingOnly = TRUE)
refresh <- "--refresh" %in% args
geo_dir <- file.path(DIR_RAW, "geo")
dir.create(geo_dir, recursive = TRUE, showWarnings = FALSE)

AE_MGAP   <- "https://mapas.mgap.gub.uy/arcgis/rest/services/SNIA_Temas/Unidades_Estad%C3%ADsticas/MapServer/5"
AE_SNIG   <- "https://web.snig.gub.uy/arcgisserver/rest/services/MapasBase/AAEE/MapServer"
DEPTO_RES <- "3c1b430a-c010-4db1-880d-bdc0f11e4ce9"

now_iso <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# Descarga completa de una capa ArcGIS REST como GeoJSON en EPSG:4326.
arcgis_layer_to_geojson <- function(layer_url, dest, refresh = FALSE) {
  if (file.exists(dest) && !refresh) {
    msg("  caché: ", basename(dest))
    return(list(ok = TRUE, info = read_json(sub("\\.geojson$", "_info.json", dest))))
  }
  info <- get_json(paste0(layer_url, "?f=pjson"))
  write_json(info, sub("\\.geojson$", "_info.json", dest), auto_unbox = TRUE,
             pretty = TRUE)
  page <- min(info$maxRecordCount %||% 1000, 1000)
  cnt  <- get_json(paste0(layer_url, "/query?where=1%3D1&returnCountOnly=true&f=json"))$count
  msg("  ", info$name, ": ", cnt, " entidades (páginas de ", page, ")")
  parts <- list()
  offset <- 0
  while (offset < cnt) {
    q <- paste0(layer_url, "/query?where=1%3D1&outFields=*&returnGeometry=true",
                "&outSR=4326&f=geojson&orderByFields=OBJECTID",
                "&resultOffset=", offset, "&resultRecordCount=", page)
    tmp <- tempfile(fileext = ".geojson")
    base_request(q, timeout = 300) |> req_perform(path = tmp)
    part <- st_read(tmp, quiet = TRUE)
    if (!nrow(part)) break
    parts[[length(parts) + 1]] <- part
    offset <- offset + nrow(part)
  }
  all <- do.call(rbind, parts)
  stopifnot(nrow(all) == cnt)
  if (file.exists(dest)) unlink(dest)
  st_write(all, dest, quiet = TRUE, driver = "GeoJSON")
  list(ok = TRUE, info = info)
}

rows <- list()
add_row <- function(...) rows[[length(rows) + 1]] <<- tibble::tibble(...)

# 1 y 2. Áreas de enumeración ------------------------------------------------
msg("Áreas de enumeración (MGAP)…")
ae_dest <- file.path(geo_dir, "areas_enumeracion_mgap.geojson")
res <- tryCatch(arcgis_layer_to_geojson(AE_MGAP, ae_dest, refresh),
                error = function(e) { msg("  ✗ ", conditionMessage(e)); NULL })
add_row(fuente = "geo", ejercicio = NA, estado = NA, dataset_id = "mgap-snia-unidades-estadisticas",
        dataset_titulo = "SNIA Temas — Unidades Estadísticas (capa 5)",
        recurso_id = "ae_mgap", recurso_nombre = res$info$name %||% "Áreas de enumeración",
        recurso_descripcion = res$info$description %||% NA, formato = "GeoJSON",
        url = AE_MGAP, archivo = if (!is.null(res)) sub(paste0(PROJECT_ROOT, "/"), "", ae_dest) else NA,
        descargado = now_iso(), bytes = if (!is.null(res)) file.size(ae_dest) else NA,
        md5 = if (!is.null(res)) file_md5(ae_dest) else NA, http = NA,
        error = if (is.null(res)) "servicio inaccesible" else NA,
        recurso_modificado = as.character(res$info$editingInfo$lastEditDate %||% NA),
        dataset_modificado = NA)

msg("Áreas de enumeración (SNIG, alternativa)…")
snig_ok <- tryCatch({
  svc <- get_json(paste0(AE_SNIG, "?f=pjson"))
  write_json(svc, file.path(geo_dir, "snig_aaee_service.json"), auto_unbox = TRUE, pretty = TRUE)
  lyr <- Filter(function(l) grepl("enumer|aaee|area", l$name, ignore.case = TRUE), svc$layers)
  if (!length(lyr)) lyr <- svc$layers
  dest <- file.path(geo_dir, "areas_enumeracion_snig.geojson")
  r <- arcgis_layer_to_geojson(paste0(AE_SNIG, "/", lyr[[1]]$id), dest, refresh)
  add_row(fuente = "geo", ejercicio = NA, estado = NA, dataset_id = "snig-mapasbase-aaee",
          dataset_titulo = "SNIG MapasBase — AAEE", recurso_id = "ae_snig",
          recurso_nombre = r$info$name, recurso_descripcion = r$info$description %||% NA,
          formato = "GeoJSON", url = paste0(AE_SNIG, "/", lyr[[1]]$id),
          archivo = sub(paste0(PROJECT_ROOT, "/"), "", dest), descargado = now_iso(),
          bytes = file.size(dest), md5 = file_md5(dest), http = NA, error = NA,
          recurso_modificado = NA, dataset_modificado = NA)
  TRUE
}, error = function(e) { msg("  ✗ ", conditionMessage(e)); FALSE })

# 3. Departamentos ------------------------------------------------------------
msg("Límites departamentales…")
dep <- tryCatch(get_json(paste0(CKAN_API, "/resource_show?id=", DEPTO_RES))$result,
                error = function(e) { msg("  ✗ ", conditionMessage(e)); NULL })
if (!is.null(dep)) {
  ext  <- tolower(tools::file_ext(sub("\\?.*$", "", dep$url)))
  dest <- file.path(geo_dir, paste0("departamentos.", if (nzchar(ext)) ext else "zip"))
  dl   <- download_cached(dep$url, dest, refresh)
  if (!is.na(dl$path) && ext == "zip") {
    unzip(dest, exdir = file.path(geo_dir, "departamentos"))
  }
  add_row(fuente = "geo", ejercicio = NA, estado = NA, dataset_id = dep$package_id,
          dataset_titulo = "Límites departamentales", recurso_id = DEPTO_RES,
          recurso_nombre = dep$name, recurso_descripcion = gsub("[\r\n]+", " ", dep$description %||% ""),
          formato = dep$format, url = dep$url,
          archivo = if (is.na(dl$path)) NA else sub(paste0(PROJECT_ROOT, "/"), "", dest),
          descargado = now_iso(), bytes = if (is.na(dl$path)) NA else file.size(dest),
          md5 = file_md5(dl$path), http = dl$status, error = dl$error,
          recurso_modificado = dep$last_modified %||% NA, dataset_modificado = NA)
}

write_manifest(bind_rows(rows))
msg("Listo.")
