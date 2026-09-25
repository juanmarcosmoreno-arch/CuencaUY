# Descarga datos climáticos abiertos para Uruguay (con caché) y los registra en
# data-raw/manifest.csv:
#
#   • CHIRPS v2.0 mensual (lluvia, 0,05°), 1991 → último mes disponible, recortado
#     a Uruguay con la biblioteca de datos del IRI (Columbia University).
#   • NASA POWER diario (0,5° × 0,625°, comunidad AG): temperatura media del aire
#     a 2 m (T2M), humedad relativa (RH2M) y humedad del suelo en la zona de
#     raíces (GWETROOT), 2001 → hoy. Un parámetro y un año por solicitud (límite
#     de la API regional).
#
# Uso: Rscript scripts/06_download_clima.R [--refresh]

source("scripts/_common.R")

args    <- commandArgs(trailingOnly = TRUE)
refresh <- "--refresh" %in% args
dir_cl  <- file.path(DIR_RAW, "clima")
dir.create(file.path(dir_cl, "power"), recursive = TRUE, showWarnings = FALSE)

BBOX <- c(xmin = -58.6, xmax = -53.0, ymin = -35.2, ymax = -29.9)
now_iso <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
rel <- function(p) sub(paste0(PROJECT_ROOT, "/"), "", p, fixed = TRUE)
rows <- list()

# CHIRPS ----------------------------------------------------------------------
# «last» devuelve hasta el último mes publicado; se vuelve a descargar si el
# archivo tiene más de 20 días, para incorporar meses nuevos.
chirps_url <- sprintf(paste0(
  "https://iridl.ldeo.columbia.edu/SOURCES/.UCSB/.CHIRPS/.v2p0/.monthly/.global/.precipitation/",
  "X/%.2f/%.2f/RANGEEDGES/Y/%.2f/%.2f/RANGEEDGES/T/(Jan%%201991)/last/RANGE/data.nc"),
  BBOX["xmin"], BBOX["xmax"], BBOX["ymin"], BBOX["ymax"])
chirps_dest <- file.path(dir_cl, "chirps_v2_mensual_uruguay.nc")
stale <- file.exists(chirps_dest) && difftime(Sys.time(), file.mtime(chirps_dest), units = "days") > 20
msg("CHIRPS mensual…")
dl <- download_cached(chirps_url, chirps_dest, refresh = refresh || stale, timeout = 900)
msg("  ", if (isTRUE(dl$cached)) "caché" else if (is.na(dl$error)) "ok" else dl$error)
rows[[length(rows) + 1]] <- tibble::tibble(
  fuente = "clima", ejercicio = NA, estado = NA, dataset_id = "chirps-v2.0-monthly",
  dataset_titulo = "CHIRPS v2.0, precipitación mensual (UCSB/CHC vía IRI Data Library)",
  recurso_id = "chirps_mensual_uy", recurso_nombre = "Precipitación mensual, Uruguay",
  recurso_descripcion = "mm/mes, 0,05°, enero 1991 – último mes publicado",
  formato = "NetCDF", url = chirps_url, archivo = if (is.na(dl$path)) NA else rel(chirps_dest),
  descargado = now_iso(), bytes = if (is.na(dl$path)) NA else file.size(chirps_dest),
  md5 = file_md5(dl$path), http = dl$status, error = dl$error,
  recurso_modificado = NA, dataset_modificado = NA)

# NASA POWER ------------------------------------------------------------------
power_url <- function(param, year) {
  end <- if (year == as.integer(format(Sys.Date(), "%Y"))) format(Sys.Date() - 5, "%Y%m%d") else sprintf("%d1231", year)
  sprintf(paste0("https://power.larc.nasa.gov/api/temporal/daily/regional?parameters=%s",
                 "&community=AG&latitude-min=-35&latitude-max=-30&longitude-min=-58.5&longitude-max=-53",
                 "&start=%d0101&end=%s&format=JSON"), param, year, end)
}
this_year <- as.integer(format(Sys.Date(), "%Y"))
for (param in c("T2M", "RH2M", "GWETROOT")) {
  msg("NASA POWER ", param, "…")
  n_ok <- 0
  for (y in 2001:this_year) {
    dest <- file.path(dir_cl, "power", sprintf("%s_%d.json", param, y))
    # El año en curso se actualiza siempre (datos provisorios recientes).
    dl <- download_cached(power_url(param, y), dest, refresh = refresh || y == this_year, timeout = 300)
    if (!is.na(dl$error)) msg("  ✗ ", y, ": ", dl$error) else n_ok <- n_ok + 1
  }
  msg("  ", n_ok, " años disponibles")
  rows[[length(rows) + 1]] <- tibble::tibble(
    fuente = "clima", ejercicio = NA, estado = NA, dataset_id = "nasa-power-daily-ag",
    dataset_titulo = "NASA POWER, datos diarios regionales (comunidad AG, MERRA-2)",
    recurso_id = paste0("power_", param), recurso_nombre = param,
    recurso_descripcion = sprintf("Diario, 0,5° × 0,625°, 2001–%d, un archivo por año", this_year),
    formato = "JSON", url = power_url(param, 2001), archivo = rel(file.path(dir_cl, "power")),
    descargado = now_iso(), bytes = NA, md5 = NA, http = NA,
    error = if (n_ok == 0) "sin datos" else NA, recurso_modificado = NA, dataset_modificado = NA)
}

write_manifest(bind_rows(rows))
msg("Listo.")
