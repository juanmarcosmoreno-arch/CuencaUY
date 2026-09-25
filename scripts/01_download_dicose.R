# Descarga los recursos DICOSE–SNIG (datos y metadatos) de cada ejercicio desde
# el Catálogo Nacional de Datos Abiertos (CKAN) y registra cada archivo en
# data-raw/manifest.csv con URL, fecha de descarga, ejercicio y estado.
#
# Uso:
#   Rscript scripts/01_download_dicose.R            # usa la caché
#   Rscript scripts/01_download_dicose.R --refresh  # fuerza nueva descarga

source("scripts/_common.R")

args    <- commandArgs(trailingOnly = TRUE)
refresh <- "--refresh" %in% args

estado_from_title <- function(title) {
  t <- tolower(title)
  dplyr::case_when(
    grepl("actualizad", t) ~ "actualizado",
    grepl("preliminar", t) ~ "preliminar",
    TRUE ~ "sin especificar"
  )
}

fetch_package <- function(slug, ejercicio) {
  url <- paste0(CKAN_API, "/package_show?id=", slug)
  pkg <- tryCatch(get_json(url)$result, error = function(e) NULL)
  if (is.null(pkg)) {
    # Si el identificador cambió, se busca por texto.
    q <- utils::URLencode(sprintf("DICOSE SNIG %d", ejercicio), reserved = TRUE)
    res <- tryCatch(get_json(paste0(CKAN_API, "/package_search?rows=50&q=", q))$result$results,
                    error = function(e) list())
    hit <- Filter(function(p) grepl(as.character(ejercicio), p$title) &&
                    grepl("DICOSE", p$title, ignore.case = TRUE), res)
    if (length(hit)) pkg <- hit[[1]]
  }
  pkg
}

rows <- list()
for (i in seq_len(nrow(DICOSE_DATASETS))) {
  ej   <- DICOSE_DATASETS$ejercicio[i]
  slug <- DICOSE_DATASETS$slug[i]
  msg("Ejercicio ", ej, ": consultando catálogo…")
  pkg <- fetch_package(slug, ej)
  if (is.null(pkg)) {
    msg("  ✗ No se pudo consultar el conjunto ", slug)
    rows[[length(rows) + 1]] <- tibble::tibble(
      fuente = "dicose", ejercicio = ej, estado = NA, dataset_id = slug,
      dataset_titulo = NA, recurso_id = paste0(slug, "#no-disponible"),
      recurso_nombre = NA, recurso_descripcion = NA, formato = NA,
      url = paste0(CKAN_API, "/package_show?id=", slug), archivo = NA,
      descargado = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), bytes = NA,
      md5 = NA, http = NA, error = "catálogo inaccesible",
      recurso_modificado = NA, dataset_modificado = NA)
    next
  }
  # Metadatos del conjunto, para referencia.
  pkg_dir <- file.path(DIR_RAW, "dicose", ej)
  dir.create(pkg_dir, recursive = TRUE, showWarnings = FALSE)
  write_json(pkg, file.path(pkg_dir, "_ckan_package.json"), auto_unbox = TRUE,
             pretty = TRUE)
  estado <- estado_from_title(pkg$title)
  msg("  ", pkg$title, " [", estado, "] — ", length(pkg$resources), " recursos")

  for (r in pkg$resources) {
    fmt  <- toupper(r$format %||% "")
    ext  <- tolower(tools::file_ext(sub("\\?.*$", "", r$url)))
    if (!nzchar(ext)) ext <- tolower(fmt)
    if (!nzchar(ext)) ext <- "bin"
    dest <- file.path(pkg_dir, paste0(slugify(r$name %||% r$id), "__",
                                      substr(r$id, 1, 8), ".", ext))
    dl <- download_cached(r$url, dest, refresh = refresh)
    status_txt <- if (isTRUE(dl$cached)) "caché" else if (is.na(dl$error)) "ok" else dl$error
    msg(sprintf("    %-8s %s", status_txt, r$name))
    rows[[length(rows) + 1]] <- tibble::tibble(
      fuente = "dicose", ejercicio = ej, estado = estado,
      dataset_id = pkg$name, dataset_titulo = pkg$title,
      recurso_id = r$id, recurso_nombre = r$name %||% NA,
      recurso_descripcion = gsub("[\r\n]+", " ", r$description %||% ""),
      formato = fmt, url = r$url,
      archivo = if (is.na(dl$path)) NA else sub(paste0(PROJECT_ROOT, "/"), "", dl$path),
      descargado = if (isTRUE(dl$cached)) {
        format(file.mtime(dest), "%Y-%m-%dT%H:%M:%S%z")
      } else format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      bytes = if (is.na(dl$path)) NA else file.size(dl$path),
      md5 = file_md5(dl$path), http = dl$status, error = dl$error,
      recurso_modificado = r$last_modified %||% r$metadata_modified %||% NA,
      dataset_modificado = pkg$metadata_modified %||% NA)
  }
}

man <- write_manifest(bind_rows(rows))
ok  <- sum(man$fuente == "dicose" & !is.na(man$archivo) & man$archivo != "")
msg("Manifiesto actualizado: ", ok, " archivos DICOSE disponibles localmente.")
