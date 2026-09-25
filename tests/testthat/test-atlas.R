# Pruebas de datos procesados, expresiones de estilo y lógica del servidor.
# Ejecutar desde la raíz: Rscript tests/run_tests.R

root <- normalizePath(file.path(testthat::test_path(), "..", ".."))
old <- setwd(root)
withr_defer <- function() setwd(old)
suppressPackageStartupMessages({ library(shiny); library(mapgl); library(sf); library(dplyr); library(ggplot2); library(bslib) })
for (f in list.files("R", full.names = TRUE)) source(f, local = TRUE)
atlas <- load_atlas()

test_that("el atlas procesado existe y cubre 2021–2025", {
  expect_false(is.null(atlas))
  expect_equal(atlas$years, 2021:2025)
  expect_true(all(vapply(atlas$checks, `[[`, logical(1), "ok")))
})

test_that("los códigos territoriales son texto con ceros iniciales", {
  expect_type(atlas$geo$ae$id, "character")
  expect_true(all(grepl("^[0-9]{7}$", atlas$geo$ae$id)))
  expect_true("0204001" %in% atlas$geo$ae$id)   # «204001» en las tablas DICOSE
  expect_true(all(grepl("^[0-9]{2}$", atlas$geo$dep$id)))
})

test_that("cero, base cero y ausencia de ejercicio previo se distinguen", {
  v <- atlas$values$ae
  z <- v[v$prod == 0 & v$ejercicio > 2021, ]
  expect_true(all(z$prod_cmp %in% c("sin_produccion", "ok")))
  nb <- v[v$prod_cmp == "sin_base", ]
  expect_true(nrow(nb) > 0)
  expect_true(all(is.na(nb$prod_chg)))
  expect_true(all(is.finite(v$prod_chg[!is.na(v$prod_chg)])))
  expect_true(all(v$prod_cmp[v$ejercicio == 2021] == "sin_anterior"))
})

test_that("las geometrías conservan la superficie original", {
  expect_true(all(atlas$geo$ae$area_km2 > 0))
  expect_equal(round(sum(atlas$geo$dep$area_km2)), 175000, tolerance = 0.02)
})

test_that("las capas del mapa tienen una columna por indicador y ejercicio", {
  L <- build_layer_data(atlas, "dep")
  expect_equal(nrow(L), 19)
  expect_true(all(c("prod_2025", "prod_2025_c", "prod_2025_s", "rem_2021") %in% names(L)))
  expect_equal(sum(L$prod_2025), atlas$national$prod[atlas$national$ejercicio == 2025])
})

test_that("las expresiones de estilo son válidas y usan escala fija", {
  e <- color_expr("prod", 2024, 8e8)
  expect_equal(e[[1]], "interpolate")
  stops <- unlist(e[seq(4, length(e), 2)])
  expect_true(all(diff(stops) > 0))
  # La selección se envuelve con `match`, nunca con `case` (ver map_data.R).
  es <- color_expr("prod", 2024, 8e8, selected = "0601004")
  expect_equal(es[[1]], "match")
  ec <- color_expr("prod", 2024, 8e8, mode = "change", chg_lim = 20)
  expect_equal(ec[[1]], "match")
  expect_equal(height_expr("prod", 2024, 8e8, dim = "2d"), 0)
  h <- height_expr("prod", 2024, 8e8, "sqrt")
  expect_equal(h[[2]][[1]], "sqrt")
  # misma escala para todos los años
  expect_identical(height_expr("prod", 2021, 8e8)[[3]], height_expr("prod", 2025, 8e8)[[3]])
})

test_that("el servidor responde a año, indicador y selección", {
  app <- shiny::shinyAppDir(root)
  testServer(app, {
    session$setInputs(year = 2023, indicator = "venta", level = "dep", mode = "value",
                      transform = "linear", map_zoom = 6)
    expect_equal(year(), 2023L)
    expect_match(as.character(output$year_card$html), "2023")
    expect_match(as.character(output$kpis$html), "Producción nacional")
    session$setInputs(atlas_select = list(id = "16", level = "dep"))
    expect_equal(sel_id(), "16")
    expect_match(as.character(output$detail$html), "San José")
    session$setInputs(year = 2021)
    expect_equal(sel_id(), "16")      # la selección se conserva al cambiar de año
    session$setInputs(year = 2019)    # año no publicado: se ignora
    expect_equal(year(), 2025L)
    session$setInputs(level = "ae")
    expect_null(sel_id())
    session$setInputs(atlas_select = list(id = "0601004", level = "ae"))
    session$setInputs(level = "dep")
    expect_equal(sel_id(), "06")      # el área pasa a su departamento
  })
})

withr_defer()
