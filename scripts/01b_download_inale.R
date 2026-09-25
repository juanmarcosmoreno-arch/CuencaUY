# Descarga series oficiales de INALE (Instituto Nacional de la Leche):
#   • Remisión a planta y composición (mensual, millones de litros)
#   • Precio al productor en tambo ($/L y US$/L, mensual)
#   • Índice de precios al consumo (IPC, mensual) para deflactar
#
# Las URL de las planillas cambian con cada actualización (/uploads/AAAA/MM/),
# así que se buscan en la página de estadísticas. Si la página no responde, se
# conservan los archivos ya descargados.
#
# Uso: Rscript scripts/01b_download_inale.R [--refresh]

source("scripts/_common.R")

args    <- commandArgs(trailingOnly = TRUE)
refresh <- "--refresh" %in% args
dir_of  <- file.path(DIR_RAW, "oficial")
dir.create(dir_of, recursive = TRUE, showWarnings = FALSE)
PAGE <- "https://www.inale.org/estadisticas/"

SERIES <- tibble::tribble(
  ~id,                    ~patron,                                   ~archivo,                          ~titulo,
  "inale_remision",       "Remision-a-planta-y-composicion",         "inale_remision_a_planta.xls",     "INALE — Remisión a planta y composición",
  "inale_precio",         "Precio-leche-en-tambo-y-composicion",     "inale_precio_leche_tambo.xlsx",   "INALE — Precio de la leche en tambo",
  "inale_ipc",            "Indice-de-Precios-al-Consumo",            "inale_ipc_mensual.xlsx",          "INALE — Índice de precios al consumo (INE), mensual"
)

html <- tryCatch(resp_body_string(base_request(PAGE, 60) |> req_perform()),
                 error = function(e) { msg("✗ Página de INALE inaccesible: ", conditionMessage(e)); "" })
links <- unique(regmatches(html, gregexpr('https://www\\.inale\\.org/wp-content/uploads/[^"\']+\\.xlsx?', html))[[1]])

rows <- list()
for (i in seq_len(nrow(SERIES))) {
  s <- SERIES[i, ]
  url <- links[grepl(s$patron, links, ignore.case = TRUE)][1]
  dest <- file.path(dir_of, s$archivo)
  if (is.na(url)) {
    msg("✗ ", s$titulo, ": enlace no encontrado", if (file.exists(dest)) " (se usa la copia local)")
    next
  }
  # Si la URL cambió (nueva publicación mensual), se vuelve a descargar.
  old <- read_manifest()
  prev_url <- if (!is.null(old)) old$url[old$recurso_id == s$id][1] else NA
  dl <- download_cached(url, dest, refresh = refresh || !identical(prev_url, url))
  msg(if (isTRUE(dl$cached)) "  caché  " else if (is.na(dl$error)) "  ok     " else paste("  ✗", dl$error), s$titulo)
  rows[[length(rows) + 1]] <- tibble::tibble(
    fuente = "oficial", ejercicio = NA, estado = NA, dataset_id = "inale-estadisticas",
    dataset_titulo = "INALE — Estadísticas", recurso_id = s$id, recurso_nombre = s$titulo,
    recurso_descripcion = NA, formato = toupper(tools::file_ext(url)), url = url,
    archivo = if (is.na(dl$path)) NA else sub(paste0(PROJECT_ROOT, "/"), "", dest, fixed = TRUE),
    descargado = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    bytes = if (is.na(dl$path)) NA else file.size(dest), md5 = file_md5(dl$path),
    http = dl$status, error = dl$error, recurso_modificado = NA, dataset_modificado = NA)
}
if (length(rows)) write_manifest(bind_rows(rows))
msg("Listo.")
