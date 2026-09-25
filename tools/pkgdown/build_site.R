# Construye la página del proyecto con pkgdown en _site/.
#
# Uso (desde la raíz): Rscript tools/pkgdown/build_site.R
#
# No es un paquete instalable (es una app Shiny): no hay referencia de funciones.
# pkgdown no copia las imágenes que el README y los artículos toman de docs/ y
# www/: se copian después, con las mismas rutas relativas.

unlink("_site", recursive = TRUE)
pkgdown::init_site(".")
pkgdown::build_home(".", preview = FALSE)
pkgdown::build_articles(".", preview = FALSE)
pkgdown::build_search(".")

dest <- "_site"
for (d in c("docs/capturas", "docs/graficas", "docs/marca", "docs/video", "www/brand")) {
  files <- list.files(d, recursive = TRUE, full.names = TRUE)
  files <- files[!grepl("propuesta-anterior|README\\.md$", files)]
  for (f in files) {
    to <- file.path(dest, f)
    dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
    file.copy(f, to, overwrite = TRUE)
  }
}
invisible(file.create(file.path(dest, ".nojekyll")))
message("Página lista en ", normalizePath(dest))
