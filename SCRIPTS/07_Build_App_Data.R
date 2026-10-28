# ============================================================================
# 07_Build_App_Data.R  -  small, survey-weighted tables for the Shiny app
# SmartIrrigate Rwanda - Team NiyoIshimwe
#
# INPUT : DATA/processed/master/*.rds  (from SCRIPTS/06_Merge_Master_Data.R)
#         DATA/processed/selection/irr_districts.rds (GADM level 2)
#         DATA/processed/official/official_reference.csv (from SCRIPTS/14, optional):
#         published NISR figures, kept as a SEPARATE layer next to our estimates
#         (section 10). They never overwrite a survey estimate.
#
# Scope (user decision 2026-10-20): statistics for 2019-2025 only. No 2026 survey
# figure is read, used to fill gaps or used in a comparison.
# OUTPUT: SCRIPTS/app/data/*.rds   (aggregates only - no microdata leave R)
#
# Every estimate carries: estimate, 95% CI, unweighted n, number of segments
# (n_psu), CV and a reliability label (Good / Use with caution / Unreliable), so
# each chart can state its sample and quality (Section 13). Districts and other
# groups are estimated as domains of the full season design (see 00_Config.R).
# ============================================================================

source(file.path(Sys.getenv("HACKATHON_ROOT", "."), "SCRIPTS", "00_Config.R"))
t0 <- Sys.time()
# residual "Other (specify)" crops and categories are not shown in the app
is_other <- function(x) grepl("^other|specify", x, ignore.case = TRUE)

plot_df <- read_master("master_plot")      |> add_design_vars()
crop_df <- read_master("master_crop_plot") |> add_design_vars()
farmer_df <- read_master("master_farmer") |> add_design_vars()
season_quality <- read_csv(file.path(dir_master, "season_quality.csv"), show_col_types = FALSE)
rain    <- read_master("master_rain_district_season")
dist_season <- read_master("master_district_season")
nat_season  <- read_master("master_national_season")

# ---- 1. MAP GEOMETRY ---------------------------------------------------------
message("1/9 District map")
geo <- readRDS(file.path(dir_sel, "irr_districts.rds"))
geo <- sf::st_make_valid(geo) |>
  sf::st_transform(32735) |>                               # UTM 35S for simplification in metres
  sf::st_simplify(preserveTopology = TRUE, dTolerance = 150) |>
  sf::st_transform(4326) |>
  mutate(district = recode(district, "Nyarugenege" = "Nyarugenge"))
miss <- setdiff(unique(plot_df$district_std), geo$district)
if (length(miss)) warning("Districts not on the map: ", paste(miss, collapse = ", "))
tmp <- tempfile(fileext = ".geojson")
sf::st_write(geo |> select(district, province), tmp, quiet = TRUE)
save_app(jsonlite::fromJSON(tmp, simplifyVector = FALSE), "districts_geojson")
district_lookup <- plot_df |> count(province, district_std) |>
  group_by(district_std) |> slice_max(n, n = 1, with_ties = FALSE) |> ungroup() |>
  select(province, district = district_std) |> arrange(province, district)
save_app(district_lookup, "district_lookup")

# ---- 2. PLOT INDICATORS WITH CIs (national, province, district) ----------------
message("2/9 Plot indicators with survey CIs (takes a minute)")
plot_indicators <- c("irrigated", "inorganic_fert", "organic_fert", "pesticide",
                     "mechanised", "anti_erosion", "land_consolidated", "agroforestry")
input_vars <- c("inorganic_fert", "organic_fert", "pesticide")
# land share: area of plots with the input over area of plots answering (same plots)
land_df <- plot_df |>
  mutate(across(all_of(input_vars), \(x) if_else(is.na(x) | is.na(plot_area_ha), NA_real_, x * plot_area_ha),
                .names = "{.col}_area"))
# modern tools: a domain of irrigated plots (other plots set to missing, design kept)
modern_df <- plot_df |> mutate(irrig_modern = if_else(irrigated %in% 1L, irrig_modern, NA_integer_))

est_level <- function(by_extra, level_name, area_col) {
  base <- c("sas_year", "sas_season", by_extra)
  bind_rows(
    map_dfr(plot_indicators, \(v) survey_mean_by(plot_df, v, base)),
    survey_mean_by(modern_df, "irrig_modern", base),
    # farmers irrigating any plot: ONE record per farmer (master_farmer), 2020+
    survey_mean_by(farmer_df, "irrig_farmer", base) |> mutate(indicator = "irrig_any_farmer"),
    # NISR publishes inputs three ways (SAS tables "Use of ... by farmer type per
    # district"): % of farmers, % of plots, % of land. Plots = the indicators above;
    # farmers and land added here so each can be set beside the matching NISR column.
    map_dfr(input_vars, \(v) survey_mean_by(farmer_df, paste0(v, "_farmer"), base)),
    map_dfr(input_vars, \(v) survey_ratio_by(land_df, paste0(v, "_area"), "plot_area_ha", base) |>
              mutate(indicator = paste0(v, "_land")))) |>
    mutate(level = level_name, area = if (is.null(area_col)) "Rwanda" else .data[[area_col]])
}
est_plot <- bind_rows(
  est_level(character(), "national", NULL),
  est_level("province", "province", "province"),
  est_level("district_std", "district", "district_std")) |>
  mutate(across(c(estimate, se, ci_low, ci_high), \(x) 100 * x)) |>
  # df (design degrees of freedom) is kept so the website can combine districts with
  # the same t-based intervals and reliability rule as R
  select(level, area, sas_year, sas_season, indicator, estimate, se, ci_low, ci_high, n, n_psu, df, wsum, cv, reliability)
save_app(est_plot, "est_plot")

# ---- 3. TOTALS (hectares, tonnes) --------------------------------------------
message("3/9 Totals")
# irrigated_area_ha = area of plots REPORTING irrigation (not hectares watered);
# area_coverage_pct says how complete crop areas are (2024B/C are not).
totals_cols <- c("cultivated_area_ha", "irrigated_area_ha", "irrigated_area_pct", "production_t",
                 "crop_area_ha", "area_coverage_pct", "sold_t", "sold_share_pct", "sales_value_mrwf",
                 "sales_value_imputed_pct", "n_plots", "n_farmers")
save_app(bind_rows(
  nat_season |> mutate(level = "national", area = "Rwanda", province = NA_character_),
  dist_season |> mutate(level = "district", area = district_std)) |>
  select(level, area, province, sas_year, sas_season, any_of(totals_cols)), "totals")

# ---- 4. YIELD EVIDENCE (observed association, irrigated vs rain-fed) -----------
message("4/9 Yield evidence")
# Only seasons where crop areas are complete enough (season_quality.csv: 2024B and
# 2024C are left out). Ineligible rows are set to missing, not dropped, so each
# crop is a domain of the full design.
usable <- season_quality |> filter(yield_usable) |> transmute(ys = paste0(sas_year, sas_season)) |> pull(ys)
crop_df <- crop_df |> mutate(ys = paste0(sas_year, sas_season),
                             yield_eligible = yield_ok & ys %in% usable & !is.na(irrigated))
crops_enough <- crop_df |> filter(yield_eligible, irrigated == 1L) |> count(crop_name) |>
  filter(n >= 100, !is_other(crop_name)) |> pull(crop_name)
yd <- crop_df |>
  mutate(harvest_y = if_else(yield_eligible & crop_name %in% crops_enough, harvest_kg, NA_real_),
         season_type = if_else(sas_season == "C", "Season C (dry)", "Seasons A+B (main)"),
         irrigation = if_else(irrigated == 1L, "Irrigated", "Rain-fed"))
yield_pooled <- survey_ratio_by(yd, "harvest_y", "crop_area_ha", c("crop_group", "crop_name", "season_type", "irrigation")) |>
  filter(crop_name %in% crops_enough)
# by year (A+B together): a year missing one of its main seasons is left out,
# otherwise 2024 would quietly be "Season A only" next to full years
years_ab_ok <- season_quality |> filter(sas_season %in% main_seasons) |> group_by(sas_year) |>
  summarise(ok = all(yield_usable) & n() == 2, .groups = "drop") |> filter(ok) |> pull(sas_year)
yield_year   <- survey_ratio_by(yd |> filter(season_type == "Seasons A+B (main)", sas_year %in% years_ab_ok),
                                "harvest_y", "crop_area_ha", c("sas_year", "crop_name", "irrigation")) |>
  filter(crop_name %in% crops_enough)
# complementary inputs ladder (seed, fertiliser, machines; irrigation not counted);
# plots with any of the three unknown are left out
ladder <- yd |> filter(sas_season %in% main_seasons) |>
  survey_ratio_by("harvest_y", "crop_area_ha", c("crop_name", "modern_inputs_n")) |>
  filter(crop_name %in% crops_enough)
ladder_observed <- yd |> filter(!is.na(harvest_y), sas_season %in% main_seasons) |>
  group_by(crop_name) |> summarise(observed_pct = round(100 * mean(!is.na(modern_inputs_n)), 1), .groups = "drop")
# Sensitivity of the irrigated / rain-fed yield ratio-of-totals to the eligibility
# mask (main seasons pooled, usable seasons only). 'main' is the mask used everywhere:
# positive harvest, yield inside the crop x season 1st-99th percentiles. Zero harvests
# on a measured crop area are real crop failures, so 'with_zero_harvests' keeps them.
q_by <- crop_df |> filter(harvest_kg > 0, !is.na(yield_kg_ha)) |> group_by(crop_name, ys) |>
  summarise(q05 = quantile(yield_kg_ha, .05), q95 = quantile(yield_kg_ha, .95), .groups = "drop")
ys_d <- crop_df |> filter(sas_season %in% main_seasons, ys %in% usable, !is.na(irrigated), crop_name %in% crops_enough) |>
  left_join(q_by, by = c("crop_name", "ys")) |>
  mutate(irrigation = if_else(irrigated == 1L, "Irrigated", "Rain-fed"),
         area_ok = !is.na(crop_area_ha) & crop_area_ha > 0 & !is.na(harvest_kg),
         m_main = yield_ok,
         m_with_zero_harvests = yield_ok | (area_ok & harvest_kg == 0),
         m_no_trimming = area_ok & harvest_kg > 0,
         m_trim_5_95 = area_ok & harvest_kg > 0 & between(yield_kg_ha, q05, q95))
yield_sensitivity <- map_dfr(c("main", "with_zero_harvests", "no_trimming", "trim_5_95"), \(m) {
  dd <- ys_d |> mutate(h = if_else(.data[[paste0("m_", m)]] %in% TRUE, harvest_kg, NA_real_))
  survey_ratio_by(dd, "h", "crop_area_ha", c("crop_name", "irrigation")) |>
    left_join(dd |> group_by(crop_name, irrigation) |>
                summarise(n_area_ok = sum(area_ok), n_zero_harvest = sum(area_ok & harvest_kg == 0, na.rm = TRUE),
                          .groups = "drop"), by = c("crop_name", "irrigation")) |>
    mutate(mask = m, n_excluded = n_area_ok - n)
}) |> select(mask, crop_name, irrigation, estimate, se, ci_low, ci_high, n, n_psu, df, n_excluded, n_zero_harvest, reliability)
save_app(list(pooled = yield_pooled, by_year = yield_year, ladder = ladder, ladder_observed = ladder_observed,
              sensitivity = yield_sensitivity,
              crops = sort(crops_enough), season_quality = season_quality,
              excluded = season_quality |> filter(!yield_usable)), "yield_evidence")

# ---- 5. HOW FARMERS IRRIGATE (shares among irrigated plots) ---------------------
message("5/9 Irrigation technology mix")
# residual "Other" answers are left out; shares are of the named categories
share_of <- function(d, var, by) d |>
  filter(irrigated == 1L, !is.na(.data[[var]]), !is_other(.data[[var]])) |>
  group_by(across(all_of(c(by, var)))) |>
  summarise(w = sum(weight), n = n(), .groups = "drop_last") |>
  mutate(share = 100 * w / sum(w), n_group = sum(n)) |> ungroup() |>
  rename(category = all_of(var)) |> mutate(dimension = var)
# how many answers were "other / unspecified" (not shown; the chart notes it)
other_share <- map_dfr(c("irrig_tool_level", "irrig_technique", "irrig_source"), \(v) plot_df |>
  filter(irrigated == 1L, !is.na(.data[[v]])) |>
  group_by(sas_year) |>
  summarise(other_pct = 100 * sum(weight[is_other(.data[[v]])]) / sum(weight), .groups = "drop") |>
  mutate(dimension = v))
tech <- bind_rows(
  map_dfr(c("irrig_tool_level", "irrig_technique", "irrig_source"), \(v) share_of(plot_df, v, c("sas_year", "sas_season"))),
  map_dfr(c("irrig_tool_level", "irrig_technique", "irrig_source"), \(v)
    share_of(plot_df |> filter(sas_year %in% recent_years), v, "district_std") |> mutate(period = "2023-2025")))
src_any <- plot_df |> filter(irrigated == 1L) |>
  select(sas_year, sas_season, weight, starts_with("src_")) |>
  pivot_longer(starts_with("src_"), names_to = "source", values_to = "used") |>
  filter(!is.na(used)) |>
  group_by(sas_year, sas_season, source) |>
  summarise(share = 100 * sum(weight * used) / sum(weight), n = n(), .groups = "drop") |>
  mutate(source = str_remove(source, "^src_") |> str_replace_all("_", " ") |> str_squish() |> str_to_sentence())
cost <- plot_df |> filter(irrigated == 1L, irrig_cost_rwf > 0, plot_area_ha > 0, !is.na(irrig_tool_level),
                   !is_other(irrig_tool_level)) |>
  mutate(cost_rwf_ha = irrig_cost_rwf / plot_area_ha) |>
  group_by(irrig_tool_level) |>
  summarise(p25 = quantile(cost_rwf_ha, .25), median = median(cost_rwf_ha), p75 = quantile(cost_rwf_ha, .75),
            n = n(), .groups = "drop")
save_app(list(mix = tech, sources_any = src_any, cost = cost, other_share = other_share), "irrigation_tech")

# ---- 6. RAINFALL AND NEED -----------------------------------------------------
message("6/9 Rainfall and need")
# Variability is measured WITHIN each season, then averaged over A and B with equal
# weight. Pooling A and B totals into one CV (the old method) counted the normal,
# predictable difference between a long Season A and a shorter Season B as "risk"
# (audit 2026-10-20: Rusizi pooled CV 31% vs 12% in A and 18% in B). Dry seasons are
# counted on the season-specific standardised anomaly (< -1 SD of that season's normal).
rain_season <- rain |>
  filter(sas_season %in% main_seasons, sas_year %in% rain_baseline) |>
  group_by(district_std, sas_season) |>
  summarise(normal_mm = mean(rain_mm), cv_pct = 100 * sd(rain_mm) / mean(rain_mm), .groups = "drop")
rain_stats <- rain_season |>
  group_by(district_std) |>
  summarise(rain_normal_ab_mm = mean(normal_mm),           # average main-season total
            rain_cv_pct = mean(cv_pct),                    # mean of the A and B season CVs
            rain_cv_a_pct = cv_pct[sas_season == "A"], rain_cv_b_pct = cv_pct[sas_season == "B"],
            .groups = "drop") |>
  left_join(rain |> filter(sas_season %in% main_seasons) |> group_by(district_std) |>
              summarise(dry_seasons_2016_2025 = sum(rain_std_anomaly[sas_year %in% 2016:2025] < -1, na.rm = TRUE),
                        mean_anomaly_2019_2025 = mean(rain_anomaly_pct[sas_year %in% 2019:2025]), .groups = "drop"),
            by = "district_std")
adoption_recent <- plot_df |> filter(sas_year %in% recent_years, sas_season %in% main_seasons) |>
  survey_mean_by("irrigated", "district_std") |>
  transmute(district_std, adoption_pct = 100 * estimate, adoption_low = 100 * ci_low,
            adoption_high = 100 * ci_high, adoption_n = n, adoption_reliability = reliability)
need <- rain_stats |>
  mutate(need_score = 100 * (minmax(rain_cv_pct) + minmax(dry_seasons_2016_2025) + minmax(-rain_normal_ab_mm)) / 3) |>
  left_join(adoption_recent, by = "district_std") |>
  mutate(quadrant = case_when(
    need_score >= median(need_score) & adoption_pct <  median(adoption_pct, na.rm = TRUE) ~ "High need, low adoption",
    need_score >= median(need_score)                                                    ~ "High need, higher adoption",
    adoption_pct < median(adoption_pct, na.rm = TRUE)                                  ~ "Lower need, low adoption",
    TRUE                                                                               ~ "Lower need, higher adoption"))
save_app(list(rain = rain, district = need), "rain_need")

# ---- 7. WHO IS LEFT BEHIND ------------------------------------------------------
message("7/9 Equity")
eq_df <- plot_df |>
  filter(sas_season %in% main_seasons) |>
  mutate(plot_size = cut(plot_area_ha, c(-Inf, 0.05, 0.1, 0.25, 0.5, Inf),
                         labels = c("< 0.05 ha", "0.05-0.1 ha", "0.1-0.25 ha", "0.25-0.5 ha", "> 0.5 ha")),
         age_band = cut(age_years, c(-Inf, 34, 54, Inf), labels = c("Under 35", "35-54", "55+")),
         erosion = str_remove(erosion_degree, "^[0-9] "),
         consolidated = if_else(land_consolidated == 1L, "In consolidated site", "Not consolidated"))
equity <- bind_rows(
  map_dfr(c("gender", "age_band", "plot_size", "erosion", "consolidated"), \(g)
    eq_df |> filter(sas_year %in% recent_years) |>
      mutate(group = as.character(.data[[g]])) |>
      survey_mean_by("irrigated", "group") |> mutate(dimension = g, period = "2023-2025")),
  eq_df |> mutate(group = gender) |>
    survey_mean_by("irrigated", c("sas_year", "group")) |> mutate(dimension = "gender_trend")) |>
  mutate(across(c(estimate, se, ci_low, ci_high), \(x) 100 * x))
gender_district <- eq_df |> filter(sas_year %in% recent_years) |>
  survey_mean_by("irrigated", c("district_std", "gender")) |>
  mutate(across(c(estimate, ci_low, ci_high), \(x) 100 * x))
save_app(list(equity = equity, gender_district = gender_district), "equity")

# ---- 8. PRIORITY SCREENING (preliminary, adjustable weights) ------------------
message("8/9 Priority screening + weight sensitivity")
# A SHORTLIST for field feasibility checks, not an investment ranking: water
# availability, scheme status, distance to infrastructure and costs are not in
# the data yet (listed in feasibility_missing). "c_readiness" is only a proxy for
# current input use (inorganic fertiliser), not irrigation feasibility.
recent_tot <- dist_season |> filter(sas_year %in% recent_years, sas_season %in% main_seasons) |>
  group_by(district_std) |>
  summarise(cultivated_area_ha = mean(cultivated_area_ha, na.rm = TRUE),
            inorganic_fert_pct = mean(inorganic_fert_pct, na.rm = TRUE), .groups = "drop")
gap_gender <- gender_district |> select(district_std, gender, estimate, n) |>
  pivot_wider(names_from = gender, values_from = c(estimate, n)) |>
  transmute(district_std, gender_gap_pts = estimate_Male - estimate_Female,
            gender_gap_ok = pmin(n_Male, n_Female) >= min_n)
screen <- need |>
  select(district_std, need_score, adoption_pct, adoption_reliability, quadrant) |>
  left_join(recent_tot, by = "district_std") |>
  left_join(gap_gender, by = "district_std") |>
  left_join(district_lookup, by = c("district_std" = "district")) |>
  mutate(c_need     = minmax(need_score),
         c_gap      = 1 - minmax(adoption_pct),
         c_scale    = minmax(cultivated_area_ha),
         c_equity   = minmax(pmax(coalesce(if_else(gender_gap_ok, gender_gap_pts, 0), 0), 0)),
         c_readiness = minmax(inorganic_fert_pct))   # current input use (proxy)
# Current input use starts at weight 0: our plot-level chemical fertiliser share is
# about 20 points below the published SAS 2025 tables (audit 2026-10-20), so it is
# not used by default until the fertiliser variable is reconciled. Users can raise it.
default_weights <- c(c_need = 0.30, c_gap = 0.30, c_scale = 0.20, c_equity = 0.10, c_readiness = 0)
score_with <- function(s, w) as.numeric(as.matrix(s[names(default_weights)]) %*% (w[names(default_weights)] / sum(w))) * 100
screen$score <- score_with(screen, default_weights)
screen$rank  <- rank(-screen$score, ties.method = "min")
# Sensitivity: 1,000 weight sets drawn from Dirichlet(20 x default weights) over the
# criteria with a positive weight; a criterion weighted 0 stays exactly 0 (same as
# the website, SCRIPTS/web/src/lib/ranking.ts). Weight uncertainty only, not sampling error.
set.seed(2026)
w_def <- default_weights / sum(default_weights)
draws <- t(replicate(1000, { g <- ifelse(w_def > 0, rgamma(length(w_def), shape = 20 * pmax(w_def, 1e-12)), 0); g / sum(g) }))
colnames(draws) <- names(default_weights)
rank_draws <- apply(draws, 1, \(w) rank(-score_with(screen, w), ties.method = "min"))
screen <- screen |>
  mutate(rank_median = apply(rank_draws, 1, median),
         rank_p10 = apply(rank_draws, 1, quantile, 0.10),
         rank_p90 = apply(rank_draws, 1, quantile, 0.90),
         # share of the 1,000 weight scenarios with the district in the top 5 (a
         # frequency over scenarios, not a probability that it deserves investment)
         prob_top5_pct = 100 * rowMeans(rank_draws <= 5),
         stability = case_when(rank_p90 - rank_p10 <= 4 ~ "Stable",
                               rank_p90 - rank_p10 <= 10 ~ "Moderately sensitive",
                               TRUE ~ "Sensitive to weights"))
comp_cols <- names(default_weights)
contrib <- sweep(as.matrix(screen[comp_cols]), 2, default_weights / sum(default_weights), `*`)
screen$reasons <- apply(contrib, 1, \(r) paste(comp_cols[order(-r)][1:2], collapse = ","))
# what the shortlist is computed from (exported with every shortlist CSV)
screen_meta <- list(
  weights = default_weights, sensitivity = "1,000 weight sets, Dirichlet(20 x default weights) over criteria with weight > 0 (zero stays zero), seed 2026",
  periods = c(c_need = "CHIRPS rainfall, baseline 1991-2020; dry seasons 2016-2025",
              c_gap = "plots irrigated, Seasons A+B 2023-2025", c_scale = "cultivated area, mean per main season 2023-2025",
              c_equity = "men - women plot irrigation gap, 2023-2025", c_readiness = "chemical fertiliser plots, 2023-2025"))
feasibility_missing <- c("water_availability", "scheme_status", "net_irrigable_area", "distance_infrastructure",
                         "water_user_associations", "environment_permits", "unit_costs", "market_access")
save_app(list(table = screen, default_weights = default_weights, meta = screen_meta,
              feasibility_missing = feasibility_missing), "priority_screening")

# ---- 9. EXPLORER, DOWNLOADS, METADATA -----------------------------------------
message("9/9 Explorer tables and metadata")
save_app(read_master("master_crop_season") |> filter(n_crop_plots >= 10, !is_other(crop_name)), "crop_season")
save_app(read_master("master_crop_district_season") |> filter(n_crop_plots >= 10, !is_other(crop_name)),
         "crop_district_season")
# ---- AGRICULTURAL HOUSEHOLD SURVEY (AHS) AGGREGATES -------------------------
# Weighted indicators built by 10_AHS_Preparation.R. Only the aggregate tables are
# copied (never the household file). Residual "Other" / "Unclassified" categories
# are dropped and the remaining shares re-scaled to 100%.
ahs_file <- file.path(dir_root, "DATA", "processed", "ahs", "ahs_indicators.rds")
if (file.exists(ahs_file)) {
  message("AHS aggregates")
  ahs <- readRDS(ahs_file)
  drop_other <- function(x) !grepl("^other|unclassified|specify", x, ignore.case = TRUE)
  save_app(list(
    indicators = ahs$indicators |> filter(is.finite(estimate)),
    equity = ahs$equity |> filter(drop_other(group)),
    irrigation_mix = ahs$irrigation_mix |> filter(drop_other(category)) |>
      group_by(year, dimension) |> mutate(share = 100 * w / sum(w)) |> ungroup(),
    built = ahs$built), "ahs")
} else message("AHS aggregates skipped: run 10_AHS_Preparation.R first")

# ---- 10. PUBLISHED NISR FIGURES: SHOWN FIRST WHERE THE DEFINITION MATCHES ------
# User decision 2026-10-21: where NISR publishes a figure with the same definition
# as one of ours, the app shows the NISR figure and keeps ours as a cross-check;
# a figure with a different definition is shown under its own NISR label only.
# Figures come from SCRIPTS/11 (every published cell, with file, sheet and cell)
# and SCRIPTS/14 (which cells answer which app question). Our estimates are never
# overwritten here: both values travel together and the web picks the NISR one.
off_file <- file.path(dir_root, "DATA", "processed", "official", "official_reference.csv")
official <- if (file.exists(off_file)) {
  message("10 Published NISR figures")
  read_csv(off_file, show_col_types = FALSE, guess_max = 1e5) |> filter(sas_year <= 2025)
} else {
  message("10 No published NISR figures yet (save the workbooks in DATA/NISR_published, run 11 and 14)")
  tibble(indicator = character(), survey = character(), sas_year = integer(), sas_season = character(),
         level = character(), area = character(), crop_name = character(), is_group = logical(),
         farmer_type = character(), value = numeric(), unit = character(), measure_label = character(),
         population = character(), definition = character(), comparable = logical(),
         project_indicator = character(), project_table = character(), source_title = character(),
         source_file = character(), sheet = character(), cell = character())
}
# our value for the same question, place, season and crop (only for "All" farmers)
proj_est  <- est_plot |> transmute(project_indicator = indicator, project_table = "est", sas_year, sas_season,
                                   level, area, crop_name = NA_character_, project_value = estimate,
                                   project_reliability = reliability)
proj_tot  <- bind_rows(nat_season |> mutate(level = "national", area = "Rwanda"),
                       dist_season |> mutate(level = "district", area = district_std)) |>
  select(level, area, sas_year, sas_season, cultivated_area_ha, irrigated_area_ha) |>
  tidyr::pivot_longer(c(cultivated_area_ha, irrigated_area_ha), names_to = "project_indicator", values_to = "project_value") |>
  mutate(project_table = "totals", crop_name = NA_character_, project_reliability = NA_character_)
crop_cols <- c("production_t", "crop_area_ha", "yield_kg_ha")
proj_crop <- bind_rows(
  read_master("master_crop_season") |> mutate(level = "national", area = "Rwanda", project_table = "crop"),
  read_master("master_crop_district_season") |> mutate(level = "district", area = district_std, project_table = "crop_dist")) |>
  select(project_table, level, area, sas_year, sas_season, crop_name, any_of(crop_cols)) |>
  tidyr::pivot_longer(any_of(crop_cols), names_to = "project_indicator", values_to = "project_value") |>
  mutate(project_reliability = NA_character_)
project_values <- bind_rows(proj_est, proj_tot, proj_crop)
official <- official |>
  left_join(project_values |> mutate(farmer_type = "All"),
            by = c("project_indicator", "project_table", "sas_year", "sas_season", "level", "area", "crop_name", "farmer_type")) |>
  mutate(gap = value - project_value,
         gap_pct = if_else(unit == "%", NA_real_, 100 * gap / value),
         decision = case_when(
           is.na(value) ~ "Published cell blank: shown as unavailable",
           comparable & !is.na(project_value) ~ "NISR value shown; project estimate kept as cross-check",
           comparable ~ "NISR value shown; no project estimate",
           TRUE ~ "NISR value shown under its own label; not compared (different definition)"))
save_app(official, "official")

skip <- if (file.exists(file.path(dir_master, "skip_pattern_audit.csv")))
  read_csv(file.path(dir_master, "skip_pattern_audit.csv"), show_col_types = FALSE) else tibble()
joins <- if (file.exists(file.path(dir_master, "master_join_log.csv")))
  read_csv(file.path(dir_master, "master_join_log.csv"), show_col_types = FALSE) else tibble()
save_app(list(
  built = format(Sys.time(), "%Y-%m-%d %H:%M"),
  team = "NiyoIshimwe",
  sources = tibble(
    source = c("NISR Seasonal Agricultural Survey (SAS) 2019-2025 microdata, Seasons A/B/C",
               "CHIRPS v2 monthly rainfall by district, 1981-2025",
               "GADM 4.1 district boundaries (level 2)",
               "NISR Agricultural Household Survey (AHS) 2017, 2020, 2024"),
    use = c("Irrigation, inputs, production, yields, farmer characteristics",
            "Season rainfall, anomalies vs 1991-2020, dry-season frequency",
            "District maps",
            "Household irrigation, inputs, services and equity (aggregates only)")),
  n_plots = nrow(plot_df), n_crop_plots = nrow(crop_df), n_farmers = nrow(farmer_df),
  season_quality = season_quality,
  # targets and other-source benchmarks are no longer shown: they measure developed
  # irrigated land, not the area of plots that report irrigation (kept empty for the
  # Shiny app, which reads this table)
  benchmarks = tibble(key = character(), value = numeric(), unit = character(), period = character(),
                      source = character(), url = character()),
  scope = "Statistics 2019-2025 only. Project estimates from survey microdata are not official NISR statistics.",
  published = NULL, official_rows = nrow(official),
  skip_audit = skip, join_log = joins), "meta")

message(sprintf("Done in %.1f min. Files in %s:", as.numeric(difftime(Sys.time(), t0, units = "mins")), dir_app_data))
print(tibble(file = list.files(dir_app_data), kb = round(file.size(list.files(dir_app_data, full.names = TRUE)) / 1024)))
