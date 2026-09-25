# Gráficas para difusión (PNG 1080 × 1080, formato cuadrado para redes).
#
#   1. Remisión mensual a planta, una línea por año calendario (INALE).
#   2. Remisión mensual por ejercicio julio–junio, alineada con DICOSE (INALE).
#   3. Variación de la producción declarada 2021 → 2025 por departamento (DICOSE).
#
# DICOSE es anual: no hay producción mensual oficial. La remisión a planta de
# INALE es la serie mensual oficial más cercana (≈ 91–95 % de lo producido).
#
# Uso: Rscript scripts/05_graficas.R   → docs/graficas/*.png

source("scripts/_common.R")
suppressPackageStartupMessages({
  library(ggplot2)
  library(tidyr)
  library(systemfonts)
})

out_dir <- file.path(PROJECT_ROOT, "docs", "graficas")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Tipografía Inter (instancias estáticas generadas desde la fuente variable del atlas).
fdir <- file.path(PROJECT_ROOT, "tools", "fonts")
register_font("Inter Atlas",
              plain = file.path(fdir, "InterAtlas-Regular.ttf"),
              bold = file.path(fdir, "InterAtlas-SemiBold.ttf"))

INK <- "#172B2A"; INK2 <- "#667773"; LINE <- "#E3E8E4"; BG <- "#FCFCFB"
# Rampa ordinal de un solo tono (validada: monótona, ΔL ≥ 0,06, extremo claro ≥ 2:1).
RAMP <- c("#82BA9C", "#5AA088", "#398674", "#216D62", "#12564F", "#083D38")
NEG <- "#B8663F"; POS <- "#2A7F80"

wrap <- function(x, width) paste(vapply(strsplit(x, "\n", fixed = TRUE)[[1]],
                                          function(l) paste(strwrap(l, width), collapse = "\n"), ""),
                                   collapse = "\n")
signed <- function(v, d = 0) paste0(ifelse(v > 0, "+", ifelse(v < 0, "−", "")), fmt_es(abs(v), d))
fmt_es <- function(x, d = 0) formatC(x, format = "f", digits = d, big.mark = ".", decimal.mark = ",")

theme_atlas <- function() {
  theme_minimal(base_family = "Inter Atlas", base_size = 15) +
    theme(
      plot.background = element_rect(fill = BG, colour = NA),
      panel.background = element_rect(fill = BG, colour = NA),
      panel.grid.major.x = element_blank(),
      panel.grid.minor = element_blank(),
      panel.grid.major.y = element_line(colour = LINE, linewidth = 0.35),
      axis.text = element_text(colour = INK2, size = 12.5),
      axis.title = element_blank(),
      plot.title = element_text(colour = INK, face = "bold", size = 23, margin = margin(b = 6)),
      plot.subtitle = element_text(colour = INK2, size = 14.5, lineheight = 1.15, margin = margin(b = 18)),
      plot.caption = element_text(colour = INK2, size = 11, hjust = 0, lineheight = 1.2, margin = margin(t = 18)),
      plot.title.position = "plot", plot.caption.position = "plot",
      legend.position = "top", legend.justification = "left",
      legend.title = element_blank(), legend.text = element_text(colour = INK, size = 12.5),
      legend.key.width = unit(22, "pt"), legend.margin = margin(0, 0, 6, 0),
      plot.margin = margin(40, 44, 30, 40)
    )
}

save_png <- function(p, name) {
  path <- file.path(out_dir, name)
  ggsave(path, p, device = ragg::agg_png, width = 1080, height = 1080, units = "px",
         dpi = 144, bg = BG)
  msg("  ", sub(paste0(PROJECT_ROOT, "/"), "", path))
}

# Datos INALE -------------------------------------------------------------------
x <- readxl::read_excel(file.path(DIR_RAW, "oficial", "inale_remision_a_planta.xls"),
                        sheet = 1, col_names = FALSE, .name_repair = "minimal")
hdr <- which(trimws(as.character(x[[1]])) %in% c("Año/ Mes", "Año/Mes"))[1]
yrs <- suppressWarnings(as.integer(unlist(x[hdr, -1])))
MESES <- c("Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto",
           "Setiembre", "Octubre", "Noviembre", "Diciembre")
MES_CORTO <- c("Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Set", "Oct", "Nov", "Dic")
rows <- match(MESES, trimws(as.character(x[[1]])))
inale <- expand_grid(mes = 1:12, j = seq_along(yrs)) |>
  mutate(anio = yrs[j],
         ml = mapply(function(m, j) suppressWarnings(as.numeric(x[[j + 1]][rows[m]])), mes, j)) |>
  filter(!is.na(anio), !is.na(ml)) |> select(anio, mes, ml)
ultimo <- inale |> arrange(anio, mes) |> tail(1)
msg("INALE: remisión mensual hasta ", MESES[ultimo$mes], " ", ultimo$anio)

# 1. Año calendario ------------------------------------------------------------
y1 <- 2021:max(inale$anio)
d1 <- inale |> filter(anio %in% y1) |> mutate(anio = factor(anio, levels = y1))
pal1 <- setNames(tail(RAMP, length(y1)), y1)
ends1 <- d1 |> group_by(anio) |> filter(mes == max(mes)) |> ungroup() |>
  filter(anio %in% tail(y1, 2))
# ¿El último año supera a todos los anteriores en cada mes con dato?
ult <- d1 |> filter(anio == max(y1))
maxprev <- d1 |> filter(anio != max(y1)) |> group_by(mes) |> summarise(m = max(ml))
supera <- all(ult$ml > maxprev$m[match(ult$mes, maxprev$mes)])
frase1 <- if (supera) {
  sprintf("\nEl pico de primavera se repite cada año; en %d cada mes supera a los de años anteriores.", max(y1))
} else "\nEl pico de primavera, de agosto a octubre, se repite cada año."
p1 <- ggplot(d1, aes(mes, ml, colour = anio)) +
  geom_line(linewidth = 0.85, lineend = "round", linejoin = "round") +
  geom_point(data = ends1, size = 2.8, stroke = 1.2, fill = BG, shape = 21, show.legend = FALSE) +
  geom_text(data = ends1, aes(label = paste0(anio, " · ", fmt_es(ml))), colour = INK,
            family = "Inter Atlas", fontface = "bold", size = 4.1, show.legend = FALSE,
            hjust = ifelse(ends1$mes == 12, 0, 0.5), nudge_x = ifelse(ends1$mes == 12, 0.22, 0),
            nudge_y = ifelse(ends1$mes == 12, 0, 7)) +
  scale_colour_manual(values = pal1) +
  scale_x_continuous(breaks = 1:12, labels = MES_CORTO, expand = expansion(add = c(0.3, 2.3))) +
  scale_y_continuous(labels = function(v) fmt_es(v), n.breaks = 6,
                     expand = expansion(mult = c(0.04, 0.06))) +
  guides(colour = guide_legend(nrow = 1, override.aes = list(linewidth = 1.4))) +
  labs(title = "La leche que llega a planta, mes a mes",
       subtitle = wrap(paste0(sprintf("Remisión mensual a la industria, en millones de litros. Una línea por año, 2021–%d.", max(y1)), frase1), 66),
       caption = wrap(sprintf("Fuente: INALE, remisión a planta (datos hasta %s de %d). No es la producción total: DICOSE (MGAP) solo publica producción anual; la remisión equivale a ≈ 91–95\u00a0%% de lo producido. Atlas Lechero Uruguay.",
                         tolower(MESES[ultimo$mes]), ultimo$anio), 84)) +
  theme_atlas()
save_png(p1, "remision-mensual-por-anio.png")

# 2. Ejercicio julio–junio (como DICOSE) --------------------------------------
d2 <- inale |> mutate(ejercicio = ifelse(mes >= 7, anio + 1L, anio),
                      pos = ifelse(mes >= 7, mes - 6L, mes + 6L))
completos <- d2 |> count(ejercicio) |> filter(n == 12) |> pull(ejercicio)
y2 <- intersect(2021:max(d2$ejercicio), completos)
d2 <- d2 |> filter(ejercicio %in% y2) |> mutate(ejercicio = factor(ejercicio, levels = y2))
tot2 <- d2 |> group_by(ejercicio) |> summarise(total = sum(ml))
pal2 <- setNames(tail(RAMP, length(y2)), y2)
ends2 <- d2 |> filter(pos == 12, ejercicio %in% tail(y2, 2)) |>
  left_join(tot2, by = "ejercicio")
p2 <- ggplot(d2, aes(pos, ml, colour = ejercicio)) +
  geom_line(linewidth = 0.85, lineend = "round", linejoin = "round") +
  geom_point(data = ends2, size = 2.8, stroke = 1.2, fill = BG, shape = 21, show.legend = FALSE) +
  geom_text(data = ends2, show.legend = FALSE, aes(label = sprintf("%s\n%s M L", ejercicio, fmt_es(total))), lineheight = 0.95,
            colour = INK, family = "Inter Atlas", fontface = "bold", size = 3.9,
            hjust = 0, nudge_x = 0.25) +
  scale_colour_manual(values = pal2, labels = function(l) paste("Ejercicio", l)) +
  scale_x_continuous(breaks = 1:12, labels = MES_CORTO[c(7:12, 1:6)],
                     expand = expansion(add = c(0.3, 2.2))) +
  scale_y_continuous(labels = function(v) fmt_es(v), n.breaks = 6,
                     expand = expansion(mult = c(0.04, 0.06))) +
  guides(colour = guide_legend(nrow = 2, override.aes = list(linewidth = 1.4))) +
  labs(title = "El año lechero, de julio a junio",
       subtitle = wrap("Remisión mensual a la industria por ejercicio ganadero, en millones de litros. Es el mismo período que declaran los productores a DICOSE.", 66),
       caption = wrap("Fuente: INALE, remisión a planta. En la etiqueta, total del ejercicio. Ejercicio 2026 = julio 2025 – junio 2026. Atlas Lechero Uruguay.", 84)) +
  theme_atlas()
save_png(p2, "remision-por-ejercicio.png")

# 3. Departamentos, DICOSE 2021 → 2025 ------------------------------------------
a <- readRDS(file.path(DIR_DATA, "atlas.rds"))
dep_name <- setNames(a$geo$dep$dep_name, a$geo$dep$id)
y0 <- min(a$years); y9 <- max(a$years)
d3 <- a$values$dep |> filter(ejercicio %in% c(y0, y9)) |>
  select(id, ejercicio, prod) |>
  pivot_wider(names_from = ejercicio, values_from = prod, names_prefix = "p") |>
  mutate(dep = dep_name[id], ini = .data[[paste0("p", y0)]], fin = .data[[paste0("p", y9)]],
         chg = 100 * (fin - ini) / ini) |>
  filter(ini >= 5e6) |>               # se omiten departamentos con < 5 M L (variaciones inestables)
  arrange(chg) |> mutate(dep = factor(dep, levels = dep))
omit <- setdiff(dep_name, as.character(d3$dep))
lim <- max(abs(d3$chg)) * 1.32
p3 <- ggplot(d3, aes(chg, dep)) +
  geom_vline(xintercept = 0, colour = "#B9C4BE", linewidth = 0.5) +
  geom_col(aes(fill = chg > 0), width = 0.62) +
  geom_text(aes(label = paste0(signed(chg, 1), " %"),
                hjust = ifelse(chg > 0, -0.12, 1.12)),
            family = "Inter Atlas", size = 3.9, colour = INK) +
  scale_fill_manual(values = c(`TRUE` = POS, `FALSE` = NEG), guide = "none") +
  scale_x_continuous(limits = c(-lim, lim), labels = function(v) paste0(signed(v), " %")) +
  labs(title = "Dónde creció y dónde cayó la leche",
       subtitle = wrap(sprintf("Variación de la producción declarada por departamento entre los ejercicios %d y %d. Total nacional: %s %%.",
                          y0, y9, signed(100 * (a$national$prod[a$national$ejercicio == y9] /
                                                 a$national$prod[a$national$ejercicio == y0] - 1), 1)), 66),
       caption = wrap(sprintf("Fuente: MGAP, declaraciones juradas DICOSE–SNIG (bovinos de leche, todos los destinos). Se omiten departamentos con menos de 5 M L en %d: %s. Atlas Lechero Uruguay.",
                         y0, paste(sort(omit), collapse = ", ")), 84)) +
  theme_atlas() +
  theme(panel.grid.major.y = element_blank(),
        panel.grid.major.x = element_line(colour = LINE, linewidth = 0.35),
        axis.text.y = element_text(colour = INK, size = 13))
save_png(p3, "variacion-departamentos.png")

# Tablas de respaldo (la vista de datos de cada gráfica)
write_csv(d1 |> transmute(anio, mes, remision_millones_litros = ml), file.path(out_dir, "remision-mensual-por-anio.csv"))
write_csv(d2 |> transmute(ejercicio, mes_del_ejercicio = pos, remision_millones_litros = ml), file.path(out_dir, "remision-por-ejercicio.csv"))
write_csv(d3 |> transmute(departamento = dep, litros_inicio = ini, litros_fin = fin, variacion_pct = round(chg, 2)),
          file.path(out_dir, "variacion-departamentos.csv"))
msg("Listo.")
