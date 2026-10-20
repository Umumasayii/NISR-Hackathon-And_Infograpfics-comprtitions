# ============================================================================
# 12_Export_Web_Data.R  -  export the dashboard tables to JSON for the web app
# SmartIrrigate Rwanda - Team NiyoIshimwe - NISR 2026 Big Data Hackathon
#
# The R pipeline stays the data engine. This script reads the aggregate tables
# that 07_Build_App_Data.R and 08_Models.R write to SCRIPTS/app/data/ and saves
# them as JSON for the React app in SCRIPTS/web/ (same numbers as the Shiny app).
#
# Run from the Hackathon project root, after 09_Run_All.R:
#   source("SCRIPTS/12_Export_Web_Data.R")
# Then pushes every project change to GitHub (13_Push_To_GitHub.R), so the
# website on Vercel updates; Sys.setenv(SI_AUTO_PUSH = "FALSE") skips that.
# Writes:
#   SCRIPTS/web/public/data/app_data.json      every table the pages use
#   SCRIPTS/web/public/data/districts.json     30 district shapes (GeoJSON)
#   SCRIPTS/web/public/data/i18n.json          EN / RW / FR wording
#   SCRIPTS/web/public/data/data_source.md     the one general Data Source text
# Only aggregates are exported; no unit-level microdata (Section 13).
# ============================================================================

suppressPackageStartupMessages({ library(dplyr); library(jsonlite) })

dir_root <- Sys.getenv("HACKATHON_ROOT", ".")
dir_app  <- file.path(dir_root, "SCRIPTS", "app")
dir_out  <- file.path(dir_root, "SCRIPTS", "web", "public", "data")
dir.create(dir_out, showWarnings = FALSE, recursive = TRUE)

ld <- function(x) readRDS(file.path(dir_app, "data", paste0(x, ".rds")))
as_df <- function(d) as.data.frame(d, stringsAsFactors = FALSE)

# ---- same guards as SCRIPTS/app/R/00_data.R --------------------------------------
# "Other (specify)" crops and categories are never shown (user decision 2026-10-14)
is_other <- function(x) grepl("^other|specify|unclassified", x, ignore.case = TRUE)

est    <- ld("est_plot") |> filter(!is.na(area))
totals <- ld("totals")
if (!"source" %in% names(est)) est$source <- "survey"
if (!"totals_source" %in% names(totals)) totals$totals_source <- "survey"

crop      <- ld("crop_season") |> filter(!is_other(crop_name), !is_other(crop_group))
crop_dist <- ld("crop_district_season") |> filter(!is_other(crop_name), !is_other(crop_group))

tech <- ld("irrigation_tech")
tech$mix <- tech$mix |> filter(!is_other(category)) |>
  group_by(sas_year, sas_season, dimension, district_std, period) |>
  mutate(share = 100 * w / sum(w)) |> ungroup()
tech$cost <- tech$cost |> filter(!is_other(irrig_tool_level))

# Plotly (d3-geo) needs clockwise outer rings and counter-clockwise holes
geo <- ld("districts_geojson")
ring_area <- function(r) { x <- vapply(r, `[[`, 0, 1); y <- vapply(r, `[[`, 0, 2)
  sum(x * c(y[-1], y[1]) - c(x[-1], x[1]) * y) / 2 }
orient <- function(rings) lapply(seq_along(rings), \(i) {
  r <- rings[[i]]; cw <- ring_area(r) < 0
  r <- if ((i == 1 && !cw) || (i > 1 && cw)) rev(r) else r
  lapply(r, \(p) round(unlist(p)[1:2], 5)) })
geo$features <- lapply(geo$features, \(ft) {
  g <- ft$geometry
  g$coordinates <- if (g$type == "Polygon") orient(g$coordinates) else lapply(g$coordinates, orient)
  ft$geometry <- g; ft })

# ---- adoption model: keep what the simulator needs to predict in the browser ----
model <- ld("model_adoption")
coefs <- model$glm$coefficients; coefs[is.na(coefs)] <- 0
model_web <- list(
  performance = as_df(model$performance), calibration = as_df(model$calibration),
  fairness = as_df(model$fairness), coefficients = as_df(model$coefficients),
  importance = as_df(model$importance), potential = as_df(model$potential),
  # logistic model: p = plogis(intercept + sum of the level effects + slopes * x);
  # a factor's effect is the coefficient named <variable><level> (0 for the base level)
  coef = as.list(coefs), levels = model$levels,
  n_train = model$n_train, n_test = model$n_test)

screen <- ld("priority_screening")
my     <- ld("model_yield")
meta   <- ld("meta")
ahs    <- if (file.exists(file.path(dir_app, "data", "ahs.rds"))) ld("ahs")

drop_cols <- function(d, cols) d[, setdiff(names(d), cols), drop = FALSE]

app_data <- list(
  built     = meta$built,
  lookup    = as_df(ld("district_lookup")),
  est       = as_df(drop_cols(est, c("n_psu", "survey_estimate", "nisr_table"))),
  totals    = as_df(totals),
  crop      = as_df(crop),
  crop_dist = as_df(drop_cols(crop_dist, c("production_survey_t"))),
  yield     = lapply(ld("yield_evidence")[c("pooled", "by_year", "ladder", "crops")], \(x) if (is.data.frame(x)) as_df(x) else x),
  tech      = lapply(tech, as_df),
  rain      = lapply(ld("rain_need"), as_df),
  equity    = lapply(ld("equity"), as_df),
  screen    = list(table = as_df(screen$table), default_weights = as.list(screen$default_weights),
                   feasibility_missing = screen$feasibility_missing),
  model     = model_web,
  model_yield = list(table = as_df(my$table), controls = my$controls, excluded_seasons = as_df(my$excluded_seasons)),
  meta      = list(built = meta$built, team = meta$team, n_plots = meta$n_plots, n_crop_plots = meta$n_crop_plots,
                   n_farmers = meta$n_farmers, sources = as_df(meta$sources),
                   season_quality = as_df(meta$season_quality), benchmarks = as_df(meta$benchmarks),
                   published = list(seasons = meta$published$seasons,
                                    headline = as_df(meta$published$headline),
                                    production_alignment = as_df(meta$published$production_alignment),
                                    totals_alignment = as_df(meta$published$totals_alignment)),
                   skip_audit = as_df(meta$skip_audit), join_log = as_df(meta$join_log)),
  ahs       = if (!is.null(ahs)) list(indicators = as_df(ahs$indicators), equity = as_df(ahs$equity),
                                      irrigation_mix = as_df(ahs$irrigation_mix), built = ahs$built))

# NaN / Inf are not valid JSON: write them as null
fix_num <- function(x) {
  if (is.data.frame(x)) { x[] <- lapply(x, \(v) if (is.numeric(v)) replace(v, !is.finite(v), NA) else v); x }
  else if (is.list(x)) lapply(x, fix_num)
  else if (is.numeric(x)) replace(x, !is.finite(x), NA) else x
}
app_data <- fix_num(app_data)

# Tables are written column by column (much smaller than one object per row) and
# marked {"__df": {column: [values]}} so the app can turn them back into rows
mark_df <- function(x) {
  if (is.data.frame(x)) list(`__df` = lapply(as.list(x), \(v) if (is.factor(v)) as.character(v) else v))
  else if (is.list(x)) lapply(x, mark_df) else x
}
app_data <- mark_df(app_data)

write_json(app_data, file.path(dir_out, "app_data.json"), auto_unbox = TRUE,
           na = "null", digits = I(5), null = "null")
write_json(geo, file.path(dir_out, "districts.json"), auto_unbox = TRUE, digits = NA)
file.copy(file.path(dir_app, "i18n", "translations.json"), file.path(dir_out, "i18n.json"), overwrite = TRUE)
if (file.exists(file.path(dir_app, "DATA_SOURCE.md")))
  file.copy(file.path(dir_app, "DATA_SOURCE.md"), file.path(dir_out, "data_source.md"), overwrite = TRUE)

sz <- file.info(list.files(dir_out, full.names = TRUE))$size
message("Web data written to ", normalizePath(dir_out), " (", round(sum(sz) / 1e6, 1), " MB, built ", meta$built, ")")

# ---- send the new data to GitHub; Vercel then rebuilds the website ----------------
if (!identical(toupper(Sys.getenv("SI_AUTO_PUSH", "TRUE")), "FALSE")) {
  source(file.path(dir_root, "SCRIPTS", "13_Push_To_GitHub.R"))
  push_project(paste("Update web data (built", meta$built, ")"), root = dir_root)
}
