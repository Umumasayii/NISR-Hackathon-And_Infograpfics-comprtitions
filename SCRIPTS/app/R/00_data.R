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
  model_yield = ld("model_yield"))
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
