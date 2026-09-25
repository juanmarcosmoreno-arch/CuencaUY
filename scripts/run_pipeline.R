# Pipeline completo: descarga (con caché), cartografía, preparación y validación;
# luego, clima y gráficas de difusión (opcionales).
# Uso: Rscript scripts/run_pipeline.R [--refresh]
#   --refresh fuerza la nueva descarga de todas las fuentes.
# Debe ejecutarse desde la raíz del proyecto.

args <- commandArgs(trailingOnly = TRUE)
steps <- c("scripts/01_download_dicose.R", "scripts/02_download_geometry.R",
           "scripts/03_prepare.R", "scripts/04_validate.R")
# Clima y gráficas: opcionales. Si fallan, el atlas sigue funcionando sin la capa.
optional <- c("scripts/06_download_clima.R", "scripts/07_clima.R", "scripts/05_graficas.R")
rscript <- file.path(R.home("bin"), "Rscript")
for (s in steps) {
  cat("\n══", s, "══\n")
  status <- system2(rscript, c(s, args))
  if (!identical(status, 0L)) stop("Falló ", s, " (código ", status, ")")
}
for (s in optional) {
  cat("\n══", s, "(opcional) ══\n")
  status <- system2(rscript, c(s, args))
  if (!identical(status, 0L)) { warning("Falló ", s, ": se omite la capa climática o las gráficas."); break }
}
cat("\nListo. Inicie la app con: Rscript -e \"shiny::runApp('.', launch.browser = TRUE)\"\n")
