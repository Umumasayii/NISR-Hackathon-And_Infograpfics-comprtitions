# ---- Data access helpers used by several pages --------------------------------

# Survey estimates for the selected area (national / province / district)
est_for <- function(f, indicators, years = f$years, seasons = f$seasons) {
  D$est |> filter(level == f$area_level, area == f$area, indicator %in% indicators,
                  sas_year %in% years, sas_season %in% seasons)
}
# The most recent season (within the filters) that has an estimate
latest <- function(d) d |> arrange(desc(sas_year), match(sas_season, c("C", "B", "A"))) |> slice(1)
season_label <- function(y, s) paste0(y, s)

# Totals (ha, t) for the area: districts summed for a province
totals_for <- function(f) {
  t <- D$totals |> filter(sas_year %in% f$years, sas_season %in% f$seasons)
  if (f$area_level == "national") filter(t, level == "national")
  else if (f$area_level == "district") filter(t, level == "district", area == f$district)
  else t |> filter(level == "district", province == f$province) |>
    group_by(sas_year, sas_season) |>
    summarise(across(c(cultivated_area_ha, irrigated_area_ha, production_t, crop_area_ha, sold_t, sales_value_mrwf),
                     \(x) sum(x, na.rm = TRUE)), .groups = "drop") |>
    mutate(irrigated_area_pct = 100 * irrigated_area_ha / cultivated_area_ha)
}

# Crop table filtered by area, crop group, crop, years and seasons
crops_for <- function(f) {
  d <- if (f$area_level == "national") D$crop |> mutate(district_std = "Rwanda") else
    D$crop_dist |> left_join(D$lookup, by = c("district_std" = "district")) |>
      filter(if (f$area_level == "district") district_std == f$district else province == f$province)
  d |> filter(sas_year %in% f$years, sas_season %in% f$seasons,
              !nzchar(f$crop_group) | crop_group == f$crop_group,
              !nzchar(f$crop) | crop_name == f$crop)
}

# Which global filters a page uses, shown as a small note (Section 13: do not apply
# crop or gender filters to tables that lack those columns)
filters_used <- function(tr, used) {
  all <- c("years", "seasons", "area", "crop", "gender")
  div(class = "filters-used",
      lapply(all, \(x) span(class = if (x %in% used) "fu on" else "fu off",
                            if (x %in% used) fontawesome::fa("check") else fontawesome::fa("minus"),
                            " ", tr(paste0("fu_", x)))))
}
