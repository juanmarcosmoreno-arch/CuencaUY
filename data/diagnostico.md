# Diagnóstico de datos — Atlas Lechero Uruguay

Generado: 2026-09-25 06:39 · atlas.rds: 2026-09-25

## Años disponibles

| Ejercicio | Período | Estado | Filas | Producción (M L) | AE con leche | Sin AE (M L) |
|---|---|---|---:|---:|---:|---:|
| 2021 | 1 jul 2020 – 30 jun 2021 | preliminar | 5.621 | 2.283,1 | 350 de 637 | 4,2 |
| 2022 | 1 jul 2021 – 30 jun 2022 | preliminar | 5.501 | 2.200,7 | 344 de 637 | 4,7 |
| 2023 | 1 jul 2022 – 30 jun 2023 | actualizado | 5.367 | 2.275,0 | 342 de 637 | 4,4 |
| 2024 | 1 jul 2023 – 30 jun 2024 | actualizado | 5.178 | 2.259,8 | 335 de 637 | 4,7 |
| 2025 | 1 jul 2024 – 30 jun 2025 | actualizado | 4.946 | 2.298,1 | 331 de 637 | 5,0 |

## Cobertura geográfica

- 637 áreas de enumeración (DIEA/MGAP) y 19 departamentos. El 100 % de los códigos de área de las tablas tiene polígono en todos los ejercicios.
- Las AE no cubren el área urbana de Montevideo ni los grandes embalses del río Negro. Salvo eso, coinciden con los límites departamentales oficiales (diferencia de superficie ≤ 6 %).
- Entre 4,2 y 5,0 M L por ejercicio (≈ 0,2 %) corresponden a establecimientos sin área asignada: cuentan en su departamento de registro, no en el mapa de áreas.

## Indicadores válidos

- **Producción de leche** (litros): Litros producidos en el ejercicio por bovinos de leche, sumando todos los destinos declarados (venta a industria, cuota o reparto, industrialización y consumo en el predio, otros).
- **Leche vendida** (litros): Litros declarados como venta: a la industria, como cuota o reparto propio y otras ventas de leche. Se agregan porque la frontera entre venta a industria y cuota o reparto cambia entre ejercicios.
- **Densidad territorial** (litros por km² de territorio): Producción dividida por la superficie total del área (km²). Permite comparar áreas de distinto tamaño. No es un rendimiento por hectárea lechera: el denominador incluye todo el territorio, no la superficie de los tambos.
- **Tenedores con venta a industria** (tenedores (números DICOSE)): Números DICOSE que declaran venta de leche a la industria. Se cuentan solo en ese destino: un mismo productor puede declarar varios destinos y no se suman entre sí.

## Contraste con INALE (remisión a planta, julio–junio)

| Ejercicio | Remisión INALE | Producción DICOSE | Vendida DICOSE | A industria DICOSE |
|---|---:|---:|---:|---:|
| 2021 | 2.110 | 2.283 (1,08×) | 1.939 (0,92×) | 1.663 (0,79×) |
| 2022 | 2.105 | 2.201 (1,05×) | 1.857 (0,88×) | 1.734 (0,82×) |
| 2023 | 2.089 | 2.275 (1,09×) | 1.932 (0,92×) | 1.807 (0,86×) |
| 2024 | 2.078 | 2.260 (1,09×) | 1.899 (0,91×) | 1.676 (0,81×) |
| 2025 | 2.096 | 2.298 (1,10×) | 1.935 (0,92×) | 1.842 (0,88×) |

## Limitaciones

- Datos anuales declarados por ejercicio ganadero; no existen datos mensuales en la fuente.
- Ejercicios preliminares: 2021, 2022.
- La venta a industria sola (destino 2) no es comparable entre años: su frontera con «cuota o reparto» cambia. Por eso se usa la leche vendida agregada.
- Tenedores: se cuentan dentro de un único destino (venta a industria). No existe en la fuente un total de productores únicos por área.
- Asignación por padrón de mayor superficie: algunas áreas concentran producción de pocos declarantes (p. ej. 0601004, Durazno, ≈ 9 % del total).
- Cartografía de AE vigente: los códigos son estables en 2021–2025, pero no hay capas históricas para verificar cambios de límite.
- Caprinos (especie 4) excluidos: sin control de calidad según los metadatos.

Controles: 48 de preparación y 23 independientes; fallidos: 0.
