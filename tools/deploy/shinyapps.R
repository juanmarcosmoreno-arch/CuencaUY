# Publica CuencaUY en shinyapps.io.
#
# Una sola vez, conectar la cuenta:
#   1. En https://www.shinyapps.io → menú de tu usuario → «Tokens» → «Show» →
#      «Show secret» → «Copy to clipboard».
#   2. Pegar ese comando rsconnect::setAccountInfo(name = ..., token = ...,
#      secret = ...) en la consola de R y ejecutarlo. El secreto queda guardado
#      en tu computadora; no lo subas a GitHub.
#
# Cada vez que quieras publicar o actualizar (desde la carpeta del proyecto):
#   Rscript tools/deploy/shinyapps.R
#   (o en RStudio: abrir este archivo y «Source»)
#
# Se sube solo lo que la app necesita (unos 3 MB): app.R, R/, www/, los datos
# ya procesados de data/ y la tipografía de las gráficas. Los paquetes se
# instalan en el servidor con las mismas versiones que tenés en tu computadora.

APP_NAME <- Sys.getenv("CUENCAUY_APP", "cuencauy")    # dirección: https://<cuenta>.shinyapps.io/cuencauy/

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  install.packages("rsconnect", type = if (.Platform$pkgType == "source") "source" else "binary",
                   repos = "https://cloud.r-project.org")
}
if (!nrow(rsconnect::accounts(server = "shinyapps.io"))) {
  stop("Falta conectar la cuenta: ejecutá primero rsconnect::setAccountInfo(...) (ver arriba).", call. = FALSE)
}

datos <- file.path("data", c("atlas.rds", "clima.rds", "tendencias.rds", "basemap_style.json"))
faltan <- datos[!file.exists(datos)]
if (length(faltan)) stop("Faltan datos procesados: ", paste(faltan, collapse = ", "),
                         ". Generarlos con Rscript scripts/run_pipeline.R", call. = FALSE)

archivos <- c(
  "app.R",
  list.files("R", pattern = "\\.R$", full.names = TRUE),
  list.files("www", recursive = TRUE, full.names = TRUE),
  datos,
  list.files(file.path("tools", "fonts"), pattern = "\\.ttf$", full.names = TRUE)
)
message(sprintf("Subiendo %d archivos (%.1f MB) como «%s»…", length(archivos),
                sum(file.size(archivos)) / 1e6, APP_NAME))

rsconnect::deployApp(
  appDir = ".", appFiles = archivos, appName = APP_NAME, appTitle = "CuencaUY",
  server = "shinyapps.io", forceUpdate = TRUE, launch.browser = interactive()
)
