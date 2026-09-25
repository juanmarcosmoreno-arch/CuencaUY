# Ejecutar desde la raíz del proyecto: Rscript tests/run_tests.R
testthat::test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
