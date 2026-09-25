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
  # Nivel superior: `match` por tipo (número vs. dato ausente); dentro, la rampa.
  expect_equal(e[[1]], "match")
  expect_equal(e[[2]][[1]], "typeof")
  expect_equal(e[[5]], COL_MISSING)
  e <- e[[4]]
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
  expect_equal(h[[1]], "interpolate")
  expect_equal(h[[3]], list("zoom"))
  expect_equal(h[[5]][[2]][[2]][[1]], "sqrt")
  expect_equal(h[[5]][[2]][[2]][[2]][[1]], "min")   # acotada al máximo de la escala
  # misma escala para todos los años: solo cambia la propiedad leída
  h21 <- height_expr("prod", 2021, 8e8); h25 <- height_expr("prod", 2025, 8e8)
  expect_identical(h21[[5]][[2]][[3]], h25[[5]][[2]][[3]])
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


test_that("rodeo y tambos: sin dato ≠ cero, y umbral de vacas", {
  v <- atlas$values$ae
  expect_true(all(is.na(v$tambos[v$ejercicio == 2021])))
  expect_true(all(!is.na(v$tambos[v$ejercicio >= 2022])))
  expect_true(all(is.na(v$lpv[v$vacas < 50])))
  expect_equal(unname(STATUS_CODE["sin_dato"]), 4L)
  L <- build_layer_data(atlas, "ae")
  expect_true(all(is.na(L$tambos_2021)))
  expect_true(all(L$tambos_2022_s != 4))
  n <- atlas$national
  expect_true(all(n$lpv > 5000 & n$lpv < 7000))
  expect_true(is.na(n$tambos[n$ejercicio == 2021]))
  html <- as.character(kpis_ui(atlas, 2021))
  expect_match(html, "sin dato publicado")
})

test_that("la capa climática se integra sin alterar la producción", {
  a2 <- add_climate(atlas)
  skip_if(is.null(a2$clima), "sin data/clima.rds")
  v <- a2$values$ae
  expect_equal(sum(v$prod), sum(atlas$values$ae$prod))          # el join no duplica filas
  expect_true(all(c("lluvia", "lluvia_mm", "thi") %in% names(v)))
  expect_true(all(v$lluvia_mm >= 0, na.rm = TRUE))               # mm, no anomalía
  expect_false(isTRUE(all.equal(v$lluvia, v$lluvia_mm)))
  L <- build_layer_data(a2, "ae")
  expect_true(all(c("lluvia_2023", "thi_2023") %in% names(L)))
  expect_equal(color_expr("lluvia", 2023, 50, chg_lim = 50)[[4]][[1]], "interpolate")
  # Paneles con clima: se renderizan y no quedan cifras escritas a mano.
  html <- as.character(about_modal(a2))
  expect_match(html, "Clima")
  expect_match(as.character(legend_ui(a2, "lluvia", "ae", 2023, "value", "linear", "3d")), "más seco")
  expect_match(as.character(detail_ui(a2, "ae", "0804006", "lluvia", 2023)), "mm de lluvia")
})

withr_defer()
