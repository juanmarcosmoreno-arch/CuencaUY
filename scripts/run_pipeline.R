# Pipeline completo: descarga (con caché), cartografía, preparación y validación.
# Uso: Rscript scripts/run_pipeline.R [--refresh]
#   --refresh fuerza la nueva descarga de todas las fuentes.
# Debe ejecutarse desde la raíz del proyecto.

args <- commandArgs(trailingOnly = TRUE)
steps <- c("scripts/01_download_dicose.R", "scripts/02_download_geometry.R",
           "scripts/03_prepare.R", "scripts/04_validate.R")
rscript <- file.path(R.home("bin"), "Rscript")
for (s in steps) {
  cat("\n══", s, "══\n")
  status <- system2(rscript, c(s, args))
  if (!identical(status, 0L)) stop("Falló ", s, " (código ", status, ")")
}
cat("\nListo. Inicie la app con: Rscript -e \"shiny::runApp('.', launch.browser = TRUE)\"\n")
