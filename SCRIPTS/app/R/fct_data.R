# ---- Data access helpers used by several pages --------------------------------
# Every filter is multi-select. f() (built in app.R) carries:
#   years, seasons          selected years and seasons
#   area_level, areas       "national" / "province" / "district" and the selected names
#   districts               every district inside the selection (for maps and tables)
#   area                    a short label for text ("Rwanda", "Kirehe", "East + 1")
#   district                the district when exactly one is selected, else ""
#   crop_groups, crops      selected crop groups / crops (empty = all)

reliability_lab <- function(n, cv) dplyr::case_when(
  is.na(n) | n < 30 ~ "Unreliable",
  !is.na(cv) & cv <= 0.20 & n >= 50 ~ "Good",
  !is.na(cv) & cv <= 0.35 ~ "Use with caution",
  TRUE ~ "Unreliable")

# Several districts or provinces -> one estimate. Districts are survey strata, so
# the combined share is the weighted-count average and its variance is the sum of
# the stratum variances (sum of (W_d / W)^2 * se_d^2).
combine_est <- function(d, label) {
  if (!nrow(d)) return(d)
  if (!"source" %in% names(d)) d$source <- "survey"
  d |> group_by(sas_year, sas_season, indicator) |>
    summarise(W = sum(wsum, na.rm = TRUE),
              estimate = sum(wsum * estimate, na.rm = TRUE) / W,
              se = sqrt(sum((wsum / W)^2 * se^2, na.rm = TRUE)),
              n = sum(n), source = if (all(source == "nisr")) "nisr" else "survey", .groups = "drop") |>
    mutate(level = "combined", area = label, wsum = W,
           # NISR published figures have no margin of error here; several districts
           # are combined with the survey's weighted counts (see SCRIPTS/07 section 10)
           se = if_else(source == "nisr", NA_real_, se),
           ci_low = pmax(estimate - 1.96 * se, 0), ci_high = estimate + 1.96 * se,
           cv = if_else(estimate > 0, se / estimate, NA_real_),
           reliability = if_else(source == "nisr", "Published", reliability_lab(n, cv))) |>
    select(-W)
}

# Averages over several years use the survey seasons. A NISR published season
# (SAS 2026) is used on its own only when the selection has no survey season for
# that indicator, so two different sources are never averaged together.
survey_first <- function(d, by = "indicator") {
  if (!nrow(d) || !"source" %in% names(d)) return(d)
  d |> group_by(across(all_of(by))) |> filter(if (any(source == "survey")) source == "survey" else TRUE) |> ungroup()
}
is_pub <- function(d) "source" %in% names(d) && nrow(d) > 0 && all(d$source == "nisr")

# Survey estimates for the selected area(s), combined into one series
est_for <- function(f, indicators, years = f$years, seasons = f$seasons) {
  d <- D$est |> filter(level == f$area_level, area %in% f$areas, indicator %in% indicators,
                       sas_year %in% years, sas_season %in% seasons)
  if (length(f$areas) > 1) combine_est(d, f$area) else d
}

# Several seasons -> one value per year (weighted by the weighted plot count)
by_year <- function(d) {
  if (!nrow(d)) return(tibble(sas_year = integer(), estimate = numeric(), n = integer(), rel = character(), source = character()))
  if (!"source" %in% names(d)) d$source <- "survey"
  d |> group_by(sas_year) |>
    summarise(seasons = paste0(sas_season, " ", formatC(estimate, format = "f", digits = 1), "%", collapse = " \u00B7 "),
              estimate = weighted.mean(estimate, wsum), n = sum(n),
              rel = names(sort(table(reliability), decreasing = TRUE))[1],
              source = if (all(source == "nisr")) "nisr" else "survey",
              .groups = "drop") |>
    arrange(sas_year)
}

# The most recent season (within the filters) that has an estimate
latest <- function(d) d |> arrange(desc(sas_year), match(sas_season, c("C", "B", "A"))) |> slice(1)
season_label <- function(y, s) paste0(y, s)

# Totals (ha, t) for the selection: districts summed
totals_for <- function(f) {
  t <- D$totals |> filter(sas_year %in% f$years, sas_season %in% f$seasons)
  if (f$area_level == "national") return(filter(t, level == "national"))
  t |> filter(level == "district", area %in% f$districts) |>
    group_by(sas_year, sas_season) |>
    summarise(across(any_of(c("cultivated_area_ha", "irrigated_area_ha", "production_t", "crop_area_ha", "sold_t",
                              "sales_value_mrwf", "modern_irrig_area_ha")),
                     \(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)), .groups = "drop") |>
    mutate(irrigated_area_pct = 100 * irrigated_area_ha / cultivated_area_ha)
}

# Crop table for the selection (crop groups, crops, years, seasons). For a
# sub-national selection the district rows are kept; pages sum them.
crops_for <- function(f) {
  d <- if (f$area_level == "national") D$crop |> mutate(district_std = "Rwanda") else
    D$crop_dist |> filter(district_std %in% f$districts)
  d |> filter(sas_year %in% f$years, sas_season %in% f$seasons,
              !length(f$crop_groups) | crop_group %in% f$crop_groups,
              !length(f$crops) | crop_name %in% f$crops)
}

# Which global filters a page uses, shown as a small strip of chips
filters_used <- function(tr, used) {
  all <- c("years", "seasons", "area", "crop")
  div(class = "filters-used",
      span(class = "fu-lead", fontawesome::fa("filter"), " ", tr("fu_lead")),
      lapply(all, \(x) span(class = if (x %in% used) "fu on" else "fu off",
                            if (x %in% used) fontawesome::fa("check") else fontawesome::fa("minus"),
                            " ", tr(paste0("fu_", x)))))
}

# Short label for a set of names: "Kirehe", "Kirehe, Ngoma", "Kirehe + 3"
short_set <- function(x, max_show = 2) {
  if (length(x) <= max_show) paste(x, collapse = ", ") else paste0(x[1], " + ", length(x) - 1)
}

# ---- Agricultural Household Survey (AHS) -----------------------------------------
# AHS estimates for the selected area. Several provinces or districts are combined
# as in combine_est() (districts are AHS strata). Rounds: 2017, 2020, 2024.
ahs_for <- function(f, indicators) {
  d <- D$ahs$indicators |> filter(indicator %in% indicators, level == f$area_level, area %in% f$areas)
  if (length(f$areas) <= 1 || !nrow(d)) return(d)
  d |> group_by(year, indicator, population, series_break) |>
    summarise(W = sum(wsum, na.rm = TRUE),
              estimate = sum(wsum * estimate, na.rm = TRUE) / W,
              se = sqrt(sum((wsum / W)^2 * se^2, na.rm = TRUE)),
              n = sum(n), .groups = "drop") |>
    mutate(level = "combined", area = f$area, wsum = W,
           ci_low = pmax(estimate - 1.96 * se, 0), ci_high = estimate + 1.96 * se,
           cv = if_else(estimate > 0, se / estimate, NA_real_), reliability = reliability_lab(n, cv)) |>
    select(-W)
}
ahs_val <- function(d, ind, yr) { v <- d$estimate[d$indicator == ind & d$year == yr]; if (length(v)) v[1] else NA_real_ }
