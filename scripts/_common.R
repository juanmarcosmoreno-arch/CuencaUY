# Utilidades compartidas por los scripts de descarga, preparación y validación.
# Se cargan con source("scripts/_common.R") desde la raíz del proyecto.

suppressPackageStartupMessages({
  library(httr2)
  library(dplyr)
  library(readr)
  library(jsonlite)
})

PROJECT_ROOT <- normalizePath(".", mustWork = TRUE)
if (!file.exists(file.path(PROJECT_ROOT, "app.R"))) {
  stop("Ejecute los scripts desde la raíz del proyecto (donde está app.R).")
}

DIR_RAW       <- file.path(PROJECT_ROOT, "data-raw")
DIR_DATA      <- file.path(PROJECT_ROOT, "data")
MANIFEST_PATH <- file.path(DIR_RAW, "manifest.csv")

USER_AGENT <- "CuencaUY/1.0 (+https://github.com/juanmarcosmoreno-arch/CuencaUY)"

# Conjuntos DICOSE–SNIG publicados en el Catálogo Nacional de Datos Abiertos.
# `estado` se deriva del título oficial y se vuelve a comprobar tras la descarga.
DICOSE_DATASETS <- tibble::tribble(
  ~ejercicio, ~slug,
  2021L, "mgap-datos-preliminares-basados-en-la-declaracion-jurada-de-existencias-dicose-snig-2021",
  2022L, "datos-preliminares-declaracion-jurada-de-existencias-dicose-snig-2022",
  2023L, "mgap-datos-actualizados-de-la-declaracion-jurada-de-existencias-dicose-snig-2023",
  2024L, "mgap-datos-preliminares-basados-en-la-declaracion-jurada-de-existencias-dicose-snig-2024",
  2025L, "mgap-datos-preliminares-basados-en-la-declaracion-jurada-de-existencias-dicose-snig-2025"
)

CKAN_API <- "https://catalogodatos.gub.uy/api/3/action"

if (!exists("%||%", baseenv())) `%||%` <- function(a, b) if (is.null(a)) b else a

msg <- function(...) cat(format(Sys.time(), "[%H:%M:%S] "), ..., "\n", sep = "")

# Petición base: tiempo máximo, reintentos con espera exponencial y agente propio.
base_request <- function(url, timeout = 120) {
  # HTTP/1.1 explícito: el servidor ArcGIS del SNIG corta las conexiones HTTP/2.
  request(url) |>
    req_options(http_version = 2L) |>
    req_user_agent(USER_AGENT) |>
    req_timeout(timeout) |>
    req_retry(max_tries = 4, backoff = function(i) 2^i)
}

get_json <- function(url, timeout = 60) {
  # Algunos servicios (ArcGIS) devuelven JSON como text/plain.
  resp <- base_request(url, timeout) |> req_perform()
  fromJSON(resp_body_string(resp), simplifyVector = FALSE)
}

# Descarga con caché: si el archivo ya existe y no se pide `refresh`, no se vuelve
# a descargar. Devuelve una fila para el manifiesto.
download_cached <- function(url, dest, refresh = FALSE, timeout = 600) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(dest) && !refresh && file.size(dest) > 0) {
    return(list(path = dest, cached = TRUE, status = NA_integer_,
                error = NA_character_))
  }
  tmp <- paste0(dest, ".part")
  out <- tryCatch({
    resp <- base_request(url, timeout) |>
      req_error(is_error = function(resp) FALSE) |>
      req_perform(path = tmp)
    status <- resp_status(resp)
    if (status >= 400) {
      unlink(tmp)
      list(path = NA_character_, cached = FALSE, status = status,
           error = paste("HTTP", status))
    } else {
      file.rename(tmp, dest)
      list(path = dest, cached = FALSE, status = status, error = NA_character_)
    }
  }, error = function(e) {
    unlink(tmp)
    list(path = NA_character_, cached = FALSE, status = NA_integer_,
         error = conditionMessage(e))
  })
  out
}

file_md5 <- function(path) {
  ifelse(!is.na(path) & file.exists(path), unname(tools::md5sum(path)), NA_character_)
}

read_manifest <- function() {
  if (!file.exists(MANIFEST_PATH)) return(NULL)
  read_csv(MANIFEST_PATH, col_types = cols(.default = col_character()),
           progress = FALSE)
}

# Sustituye las filas del manifiesto con la misma clave (fuente + recurso).
write_manifest <- function(rows) {
  rows <- mutate(rows, across(everything(), as.character))
  old <- read_manifest()
  if (!is.null(old)) {
    old <- anti_join(old, rows, by = c("fuente", "recurso_id"))
    rows <- bind_rows(old, rows)
  }
  rows <- arrange(rows, fuente, ejercicio, recurso_nombre)
  write_csv(rows, MANIFEST_PATH, na = "")
  invisible(rows)
}

# Nombre de archivo seguro y estable a partir del nombre del recurso.
slugify <- function(x) {
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
  x <- gsub("['`^~\"]", "", x)
  x <- tolower(gsub("[^A-Za-z0-9]+", "-", x))
  gsub("(^-|-$)", "", x)
}

# Quita prefijos de espacio de nombres XML (p. ej. "ns1:Litros" -> "Litros").
clean_names_ns <- function(x) {
  x <- sub("^[A-Za-z0-9]+:", "", trimws(x))
  sub("^﻿", "", x)
}

# Lectura robusta de los CSV del MGAP: detecta separador, conserva todo como
# texto (para no perder ceros iniciales) y normaliza nombres.
read_mgap_csv <- function(path) {
  first <- readLines(path, n = 1, warn = FALSE, encoding = "UTF-8")
  delim <- if (lengths(regmatches(first, gregexpr(";", first))) >
               lengths(regmatches(first, gregexpr(",", first)))) ";" else ","
  enc <- if (validUTF8(paste(readLines(path, n = 200, warn = FALSE), collapse = ""))) {
    "UTF-8"
  } else {
    "latin1"
  }
  df <- read_delim(path, delim = delim, col_types = cols(.default = col_character()),
                   locale = locale(encoding = enc), trim_ws = TRUE,
                   progress = FALSE, show_col_types = FALSE)
  names(df) <- clean_names_ns(names(df))
  attr(df, "delim") <- delim
  attr(df, "encoding") <- enc
  df
}

# Convierte texto numérico con posibles separadores locales a double.
parse_num <- function(x) {
  x <- trimws(x)
  x[x %in% c("", "NA", "N/A", "-", "s/d", "S/D")] <- NA
  # "1.234.567,8" -> "1234567.8"; "1234567.8" se mantiene.
  has_comma_dec <- grepl(",\\d{1,3}$", x) & grepl("\\.", x)
  x[has_comma_dec] <- gsub("\\.", "", x[has_comma_dec])
  x <- sub(",", ".", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

# Planillas de INALE: bloques con una fila de encabezado «Año/Mes» (o «Año»),
# luego una fila por año con los 12 meses en las columnas 2–13. Devuelve una
# lista de tablas largas (anio, mes, valor), una por bloque, en orden de aparición.
read_inale_blocks <- function(path, sheet = 1) {
  x <- readxl::read_excel(path, sheet = sheet, col_names = FALSE, .name_repair = "minimal")
  c1 <- trimws(as.character(x[[1]]))
  hdr <- which(grepl("^Año\\s*(/\\s*Mes)?$", c1))
  lapply(hdr, function(h) {
    r <- h + 1
    out <- list()
    while (r <= nrow(x) && grepl("^(19|20)\\d{2}$", c1[r])) {
      v <- suppressWarnings(as.numeric(unlist(x[r, 2:13])))
      out[[length(out) + 1]] <- tibble::tibble(anio = as.integer(c1[r]), mes = 1:12, valor = v)
      r <- r + 1
    }
    if (!length(out)) return(tibble::tibble(anio = integer(), mes = integer(), valor = numeric()))
    dplyr::bind_rows(out) |> dplyr::filter(!is.na(valor))
  })
}
