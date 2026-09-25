# Revalida data/atlas.rds de forma independiente y escribe un diagnóstico breve
# en data/diagnostico.md (años, cobertura, indicadores, contraste, limitaciones).
#
# Uso: Rscript scripts/04_validate.R   (termina con error si algún control falla)

source("scripts/_common.R")
suppressPackageStartupMessages(library(sf))

a <- readRDS(file.path(DIR_DATA, "atlas.rds"))
fails <- character(0)
n_assert <- 0
assert <- function(ok, what) {
  n_assert <<- n_assert + 1
  msg(if (ok) "  ✓ " else "  ✗ ", what)
  if (!ok) fails <<- c(fails, what)
}

msg("Controles de preparación")
for (c in a$checks) if (!c$ok) fails <- c(fails, c$id)
assert(all(vapply(a$checks, `[[`, logical(1), "ok")),
       sprintf("%d controles de 03_prepare.R superados", length(a$checks)))

msg("Controles independientes")
v_ae <- a$values$ae; v_dep <- a$values$dep; n <- a$national
assert(all(nchar(a$geo$ae$id) == 7) && is.character(a$geo$ae$id),
       "Códigos de AE como texto de 7 dígitos")
assert(all(nchar(a$geo$dep$id) == 2) && is.character(a$geo$dep$id),
       "Códigos de departamento como texto de 2 dígitos")
assert(!anyDuplicated(v_ae[c("id", "ejercicio")]) && !anyDuplicated(v_dep[c("id", "ejercicio")]),
       "Una sola fila por zona y ejercicio (sin duplicaciones)")
assert(nrow(v_ae) == nrow(a$geo$ae) * length(a$years), "Todas las AE tienen valor en cada ejercicio (cero explícito)")
for (k in c("prod", "venta", "rem", "vacas")) {
  s_dep <- tapply(v_dep[[k]], v_dep$ejercicio, sum)
  assert(isTRUE(all.equal(as.numeric(s_dep), n[[k]])), sprintf("Σ departamentos = nacional (%s)", k))
  s_ae <- tapply(v_ae[[k]], v_ae$ejercicio, sum)
  assert(all(as.numeric(s_ae) <= n[[k]] + 1e-6), sprintf("Σ AE ≤ nacional (%s); la diferencia es lo no asignado", k))
}
assert(all(v_ae$venta <= v_ae$prod + 1e-6), "Leche vendida ≤ producción en cada AE")
assert(all(is.na(v_ae$lpv[v_ae$vacas < 50])), "Litros por vaca sin calcular donde hay menos de 50 vacas")
assert(all(is.na(v_ae$tambos[v_ae$ejercicio == 2021])) && all(v_ae$tambos_cmp[v_ae$ejercicio == 2021] == "sin_dato"),
       "Tambos 2021: sin dato (no cero) y estado «sin_dato»")
cmp_ok <- with(v_ae, all(prod_cmp[!is.na(prod_prev) & prod_prev == 0 & prod > 0] == "sin_base") &&
                     all(is.na(prod_chg[prod_cmp != "ok"])))
assert(cmp_ok, "Base cero → «sin base de comparación», nunca infinito")
assert(all(v_ae$prod_cmp[v_ae$ejercicio == min(a$years)] == "sin_anterior"),
       "Primer ejercicio sin variación")
for (lv in c("ae", "dep")) for (k in names(a$indicators)) {
  s <- a$scales[[lv]][[k]]
  x <- a$values[[lv]][[k]]
  if (isTRUE(s$capped)) {
    assert(s$max >= stats::quantile(x, 0.98, na.rm = TRUE), sprintf("Escala fija %s/%s cubre el 98 %% de los valores (acotada, «≥» en la leyenda)", lv, k))
  } else {
    assert(s$max >= max(x, na.rm = TRUE), sprintf("Escala fija %s/%s cubre todos los ejercicios", lv, k))
  }
}
assert(all(a$national$prod > 0), "Producción nacional positiva en todos los ejercicios")

# Diagnóstico -----------------------------------------------------------------
ym <- a$years_meta
fmt <- function(x, d = 0) formatC(x, format = "f", digits = d, big.mark = ".", decimal.mark = ",")
ae_con_leche <- v_ae |> filter(prod > 0) |> count(ejercicio)
lines <- c(
  "# Diagnóstico de datos — Atlas Lechero Uruguay",
  "",
  sprintf("Generado: %s · atlas.rds: %s", format(Sys.time(), "%Y-%m-%d %H:%M"), a$version),
  "",
  "## Años disponibles",
  "",
  "| Ejercicio | Período | Estado | Filas | Producción (M L) | AE con leche | Sin AE (M L) |",
  "|---|---|---|---:|---:|---:|---:|",
  vapply(a$years, function(y) {
    m <- ym[[as.character(y)]]; r <- n[n$ejercicio == y, ]
    sprintf("| %d | %s | %s | %s | %s | %d de %d | %s |", y, m$periodo, m$estado, fmt(m$filas),
            fmt(r$prod / 1e6, 1), ae_con_leche$n[ae_con_leche$ejercicio == y], nrow(a$geo$ae),
            fmt(r$sin_ae_litros / 1e6, 1))
  }, ""),
  "",
  "## Cobertura geográfica",
  "",
  sprintf("- %d áreas de enumeración (DIEA/MGAP) y 19 departamentos. El 100 %% de los códigos de área de las tablas tiene polígono en todos los ejercicios.", nrow(a$geo$ae)),
  "- Las AE no cubren el área urbana de Montevideo ni los grandes embalses del río Negro. Salvo eso, coinciden con los límites departamentales oficiales (diferencia de superficie ≤ 6 %).",
  sprintf("- Entre %s y %s M L por ejercicio (≈ 0,2 %%) corresponden a establecimientos sin área asignada: cuentan en su departamento de registro, no en el mapa de áreas.",
          fmt(min(n$sin_ae_litros) / 1e6, 1), fmt(max(n$sin_ae_litros) / 1e6, 1)),
  "",
  "## Indicadores válidos",
  "",
  vapply(a$indicators, function(i) paste0("- **", i$label, "** (", i$unit, "): ", i$desc), ""),
  "",
  "## Contraste con INALE (remisión a planta, julio–junio)",
  "",
  "| Ejercicio | Remisión INALE | Producción DICOSE | Vendida DICOSE | A industria DICOSE |",
  "|---|---:|---:|---:|---:|",
  if (!is.null(a$inale)) vapply(seq_len(nrow(a$inale)), function(i) {
    r <- a$inale[i, ]
    sprintf("| %d | %s | %s (%s×) | %s (%s×) | %s (%s×) |", r$ejercicio, fmt(r$remision_ML),
            fmt(r$prod_ML), fmt(r$ratio_prod, 2), fmt(r$venta_ML), fmt(r$ratio_venta, 2),
            fmt(r$ind_ML), fmt(r$ratio_ind, 2))
  }, ""),
  "",
  "## Limitaciones",
  "",
  "- Datos anuales declarados por ejercicio ganadero; no existen datos mensuales en la fuente.",
  sprintf("- Ejercicios preliminares: %s.", paste(names(Filter(function(m) identical(m$estado, "preliminar"), ym)), collapse = ", ")),
  "- La venta a industria sola (destino 2) no es comparable entre años: su frontera con «cuota o reparto» cambia. Por eso se usa la leche vendida agregada.",
  "- Tenedores: se cuentan dentro de un único destino (venta a industria). No existe en la fuente un total de productores únicos por área.",
  "- Asignación por padrón de mayor superficie: algunas áreas concentran producción de pocos declarantes (p. ej. 0601004, Durazno, ≈ 9 % del total).",
  "- Cartografía de AE vigente: los códigos son estables en 2021–2025, pero no hay capas históricas para verificar cambios de límite.",
  {
    sc <- a$snig_cmp
    if (!is.null(sc) && "iou" %in% names(sc)) sprintf(
      "- Dos versiones oficiales de los límites de AE (MGAP y SNIG) comparten códigos pero difieren en geometría: IoU mediana %s, %d de %d áreas con IoU < 0,8. Los valores no cambian (enlace por código); la densidad varía con la superficie (mediana |Δ| %s %%). Capa usada: %s.",
      fmt(median(sc$iou, na.rm = TRUE), 2), sum(sc$iou < 0.8, na.rm = TRUE), sum(!is.na(sc$iou)),
      fmt(median(abs(sc$dif_pct), na.rm = TRUE), 1), toupper(a$ae_source %||% "mgap")) else character(0)
  },
  "- Caprinos (especie 4) excluidos: sin control de calidad según los metadatos.",
  sprintf("- Vacas: en ordeñe + secas presentes en los establecimientos (propias y ajenas dentro), para ubicarlas donde se ordeñan; el total difiere < 1,5 %% del criterio «propias dentro y fuera». Litros por vaca solo con ≥ 50 vacas. Nacional: %s L/vaca (%d) → %s (%d).",
          fmt(n$lpv[1]), n$ejercicio[1], fmt(n$lpv[nrow(n)]), n$ejercicio[nrow(n)]),
  sprintf("- Tambos («Lecheros» según DIEA): sin dato en %s porque la clasificación no se publica; se muestra como faltante, no como cero.",
          paste(n$ejercicio[is.na(n$tambos)], collapse = ", ")),
  "",
  sprintf("Controles: %d de preparación y %d independientes; fallidos: %d.",
          length(a$checks), n_assert, length(fails))
)
writeLines(lines, file.path(DIR_DATA, "diagnostico.md"))
msg("Diagnóstico escrito en data/diagnostico.md")
if (length(fails)) stop("Controles fallidos: ", paste(fails, collapse = "; "))
