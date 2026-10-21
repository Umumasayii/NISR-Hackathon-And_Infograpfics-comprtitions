# ---- Load the pre-built aggregate tables (from SCRIPTS/07 and 08) -------------
# Only aggregates are deployed; no unit-level microdata (Section 13).
ld <- function(x) readRDS(file.path("data", paste0(x, ".rds")))
D <- list(
  geo        = ld("districts_geojson"),
  lookup     = ld("district_lookup"),
  est        = ld("est_plot"),
  totals     = ld("totals"),
  yield      = ld("yield_evidence"),
  tech       = ld("irrigation_tech"),
  rain       = ld("rain_need"),
  equity     = ld("equity"),
  screen     = ld("priority_screening"),
  crop       = ld("crop_season"),
  crop_dist  = ld("crop_district_season"),
  meta       = ld("meta"),
  model      = ld("model_adoption"),
  model_yield = ld("model_yield"),
  ahs        = if (file.exists("data/ahs.rds")) ld("ahs"))

# Residual "Other (specify)" crops and categories are never shown (user decision
# 2026-10-14); SCRIPTS/07 already drops them, this guards older data files.
is_other <- function(x) grepl("^other|specify|unclassified", x, ignore.case = TRUE)
D$crop      <- dplyr::filter(D$crop, !is_other(crop_name), !is_other(crop_group))
D$crop_dist <- dplyr::filter(D$crop_dist, !is_other(crop_name), !is_other(crop_group))
D$tech$mix  <- D$tech$mix |> dplyr::filter(!is_other(category)) |>
  dplyr::group_by(sas_year, sas_season, dimension, district_std, period) |>
  dplyr::mutate(share = 100 * w / sum(w)) |> dplyr::ungroup()
D$tech$cost <- dplyr::filter(D$tech$cost, !is_other(irrig_tool_level))
YEARS     <- sort(unique(D$est$sas_year))
CROP_GRPS <- sort(unique(na.omit(D$crop$crop_group)))

# Plotly (d3-geo) draws a polygon as "the whole globe minus the shape" when the
# outer ring runs counter-clockwise (the GeoJSON RFC order). Force outer rings
# clockwise and holes counter-clockwise so each district is drawn as itself.
ring_area <- function(r) { x <- vapply(r, `[[`, 0, 1); y <- vapply(r, `[[`, 0, 2)
  sum(x * c(y[-1], y[1]) - c(x[-1], x[1]) * y) / 2 }
orient <- function(rings) lapply(seq_along(rings), \(i) {
  r <- rings[[i]]; cw <- ring_area(r) < 0
  if ((i == 1 && !cw) || (i > 1 && cw)) rev(r) else r })
D$geo$features <- lapply(D$geo$features, \(ft) {
  g <- ft$geometry
  g$coordinates <- if (g$type == "Polygon") orient(g$coordinates) else lapply(g$coordinates, orient)
  ft$geometry <- g; ft })

recent_years_app <- 2023:2025
D$est <- D$est |> dplyr::filter(!is.na(area))
# "survey" = our estimate from the SAS microdata, "nisr" = NISR published figure
# (published figures now travel separately in official.rds / official.json, SCRIPTS/07 section 10)
if (!"source" %in% names(D$est)) D$est$source <- "survey"
if (!"totals_source" %in% names(D$totals)) D$totals$totals_source <- "survey"
PUB_YEARS <- sort(unique(D$est$sas_year[D$est$source == "nisr"]))
