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
# Se sube solo lo que la app necesita (unos 2 MB): app.R, R/, www/, los datos
# ya procesados de data/ y la tipografía de las gráficas. Los paquetes se
# instalan en el servidor con las mismas versiones que tenés en tu computadora.

APP_NAME <- Sys.getenv("CUENCAUY_APP", "cuencauy")    # dirección: https://<cuenta>.shinyapps.io/cuencauy/
# Con más de una cuenta conectada, se usa esta (por ejemplo, Sys.setenv(CUENCAUY_CUENTA = "cuencauy")).
CUENTA <- Sys.getenv("CUENCAUY_CUENTA", "")

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  install.packages("rsconnect", type = if (.Platform$pkgType == "source") "source" else "binary",
                   repos = "https://cloud.r-project.org")
}
cuentas <- rsconnect::accounts(server = "shinyapps.io")$name
if (!length(cuentas)) {
  stop("Falta conectar la cuenta: ejecutá primero rsconnect::setAccountInfo(...) (ver arriba).", call. = FALSE)
}
if (!nzchar(CUENTA)) {
  if (length(cuentas) > 1) stop("Hay varias cuentas conectadas (", paste(cuentas, collapse = ", "),
                                "). Elegí una con Sys.setenv(CUENCAUY_CUENTA = \"...\").", call. = FALSE)
  CUENTA <- cuentas
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
message(sprintf("Subiendo %d archivos (%.1f MB) a https://%s.shinyapps.io/%s/ …", length(archivos),
                sum(file.size(archivos)) / 1e6, CUENTA, APP_NAME))

# Se publica desde una copia en una carpeta temporal: si rsconnect ve el
# renv.lock del proyecto, lo usa completo (con los paquetes del pipeline, que
# la app no necesita y quizá no estén instalados). Desde la copia, detecta solo
# los paquetes que la app usa, con las versiones instaladas en tu computadora.
bundle <- file.path(tempdir(), "cuencauy-app")
unlink(bundle, recursive = TRUE)
for (f in archivos) {
  dir.create(file.path(bundle, dirname(f)), recursive = TRUE, showWarnings = FALSE)
  file.copy(f, file.path(bundle, f))
}

# Detección de paquetes «clásica» (packrat): sigue solo Depends/Imports de lo que
# la app usa. La de renv también exige paquetes sugeridos que no hacen falta.
options(rsconnect.packrat = TRUE)

rsconnect::deployApp(
  appDir = bundle, appName = APP_NAME, appTitle = "CuencaUY",
  account = CUENTA, server = "shinyapps.io", forceUpdate = TRUE, launch.browser = interactive()
)
