# Formato numérico en español de Uruguay y utilidades de interfaz.

fmt_int <- function(x) {
  ifelse(is.na(x), "—", formatC(round(x), format = "d", big.mark = ".", decimal.mark = ","))
}

fmt_num <- function(x, digits = 1) {
  ifelse(is.na(x), "—",
         formatC(x, format = "f", digits = digits, big.mark = ".", decimal.mark = ","))
}

fmt_pct <- function(x, digits = 1, sign = TRUE) {
  ifelse(is.na(x), "—",
         paste0(ifelse(sign & x > 0, "+", ifelse(x < 0, "−", "")),
                fmt_num(abs(x), digits), " %"))
}

# Valor del indicador con su unidad compacta ("12,4 M L", "38 tenedores").
fmt_value <- function(x, ind, compact = TRUE) {
  if (is.na(x)) return("—")
  if (ind$id %in% c("prod", "venta")) {
    if (compact && x >= 1e6) return(paste(fmt_num(x / 1e6, if (x >= 1e8) 0 else 1), "M L"))
    if (compact && x >= 1e3) return(paste(fmt_num(x / 1e3, 0), "mil L"))
    return(paste(fmt_int(x), "L"))
  }
  if (ind$id == "dens") return(paste(fmt_int(x), "L/km²"))
  paste(fmt_int(x), if (x == 1) "tenedor" else "tenedores")
}

# Etiqueta corta para los extremos de la leyenda.
fmt_axis <- function(x, ind) {
  if (ind$id %in% c("prod", "venta")) {
    if (x >= 1e6) return(paste0(fmt_num(x / 1e6, 0), " M"))
    if (x >= 1e3) return(paste0(fmt_num(x / 1e3, 0), " mil"))
    return(fmt_int(x))
  }
  if (ind$id == "dens" && x >= 1e3) return(paste0(fmt_num(x / 1e3, 0), " mil"))
  fmt_int(x)
}

# Iconos Lucide (ISC) incrustados como SVG en línea: una sola familia, sin CDN.
.icon_cache <- new.env()
icon <- function(name, class = NULL) {
  if (is.null(.icon_cache[[name]])) {
    path <- file.path("www", "icons", paste0(name, ".svg"))
    svg <- paste(readLines(path, warn = FALSE), collapse = " ")
    svg <- sub("<!--.*?-->", "", svg)
    svg <- sub("<svg", '<svg aria-hidden="true" focusable="false"', svg)
    .icon_cache[[name]] <- svg
  }
  htmltools::span(class = paste(c("icon", class), collapse = " "),
                  htmltools::HTML(.icon_cache[[name]]))
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
