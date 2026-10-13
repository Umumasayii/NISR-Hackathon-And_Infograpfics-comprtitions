# ============================================================================
# 07_Build_App_Data.R  -  small, survey-weighted tables for the Shiny app
# SmartIrrigate Rwanda - Team NiyoIshimwe
#
# INPUT : DATA/processed/master/*.rds  (from SCRIPTS/06_Merge_Master_Data.R)
#         DATA/processed/selection/irr_districts.rds (GADM level 2)
# OUTPUT: SCRIPTS/app/data/*.rds   (aggregates only - no microdata leave R)
#
# Every estimate carries: estimate, 95% CI, unweighted n, CV and a reliability
# label (Good / Use with caution / Unreliable), so each chart can state its
# sample and quality (Section 13).
# ============================================================================

source(file.path(Sys.getenv("HACKATHON_ROOT", "."), "SCRIPTS", "00_Config.R"))
t0 <- Sys.time()

plot_df <- read_master("master_plot")      |> add_design_vars()
crop_df <- read_master("master_crop_plot") |> add_design_vars()
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
plot_indicators <- c("irrigated", "irrig_any_farmer", "inorganic_fert", "organic_fert", "pesticide",
                     "mechanised", "anti_erosion", "land_consolidated", "agroforestry")
modern_df <- plot_df |> filter(irrigated == 1L)

est_level <- function(by_extra, level_name, area_col) {
  base <- c("sas_year", "sas_season", by_extra)
  bind_rows(
    map_dfr(plot_indicators, \(v) survey_mean_by(plot_df, v, base)),
    survey_mean_by(modern_df, "irrig_modern", base)) |>
    mutate(level = level_name, area = if (is.null(area_col)) "Rwanda" else .data[[area_col]])
}
est_plot <- bind_rows(
  est_level(character(), "national", NULL),
  est_level("province", "province", "province"),
  est_level("district_std", "district", "district_std")) |>
  mutate(across(c(estimate, se, ci_low, ci_high), \(x) 100 * x)) |>
  select(level, area, sas_year, sas_season, indicator, estimate, se, ci_low, ci_high, n, cv, reliability)
save_app(est_plot, "est_plot")

# ---- 3. TOTALS (hectares, tonnes) --------------------------------------------
message("3/9 Totals")
totals_cols <- c("cultivated_area_ha", "irrigated_area_ha", "irrigated_area_pct", "production_t",
                 "crop_area_ha", "sold_t", "sold_share_pct", "sales_value_mrwf", "n_plots")
save_app(bind_rows(
  nat_season |> mutate(level = "national", area = "Rwanda", province = NA_character_),
  dist_season |> mutate(level = "district", area = district_std)) |>
  select(level, area, province, sas_year, sas_season, any_of(totals_cols)), "totals")

# ---- 4. YIELD EVIDENCE (observed association, irrigated vs rain-fed) -----------
message("4/9 Yield evidence")
yd <- crop_df |> filter(yield_ok, !is.na(irrigated))
crops_enough <- yd |> filter(irrigated == 1L) |> count(crop_name) |> filter(n >= 100) |> pull(crop_name)
yd <- yd |> filter(crop_name %in% crops_enough) |>
  mutate(season_type = if_else(sas_season == "C", "Season C (dry)", "Seasons A+B (main)"),
         irrigation = if_else(irrigated == 1L, "Irrigated", "Rain-fed"))
yield_pooled <- survey_ratio_by(yd, "harvest_kg", "crop_area_ha", c("crop_group", "crop_name", "season_type", "irrigation"))
yield_year   <- survey_ratio_by(yd |> filter(season_type == "Seasons A+B (main)"),
                                "harvest_kg", "crop_area_ha", c("crop_name", "sas_year", "irrigation"))
ladder <- crop_df |> filter(yield_ok, sas_season %in% main_seasons, crop_name %in% crops_enough) |>
  survey_ratio_by("harvest_kg", "crop_area_ha", c("crop_name", "modern_inputs_n"))
save_app(list(pooled = yield_pooled, by_year = yield_year, ladder = ladder, crops = sort(crops_enough)), "yield_evidence")

# ---- 5. HOW FARMERS IRRIGATE (shares among irrigated plots) ---------------------
message("5/9 Irrigation technology mix")
share_of <- function(d, var, by) d |>
  filter(irrigated == 1L, !is.na(.data[[var]])) |>
  group_by(across(all_of(c(by, var)))) |>
  summarise(w = sum(weight), n = n(), .groups = "drop_last") |>
  mutate(share = 100 * w / sum(w), n_group = sum(n)) |> ungroup() |>
  rename(category = all_of(var)) |> mutate(dimension = var)
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
cost <- plot_df |> filter(irrigated == 1L, irrig_cost_rwf > 0, plot_area_ha > 0, !is.na(irrig_tool_level)) |>
  mutate(cost_rwf_ha = irrig_cost_rwf / plot_area_ha) |>
  group_by(irrig_tool_level) |>
  summarise(p25 = quantile(cost_rwf_ha, .25), median = median(cost_rwf_ha), p75 = quantile(cost_rwf_ha, .75),
            n = n(), .groups = "drop")
save_app(list(mix = tech, sources_any = src_any, cost = cost), "irrigation_tech")

# ---- 6. RAINFALL AND NEED -----------------------------------------------------
message("6/9 Rainfall and need")
rain_stats <- rain |>
  filter(sas_season %in% main_seasons) |>
  group_by(district_std) |>
  summarise(rain_normal_ab_mm = mean(rain_mm[sas_year %in% rain_baseline]),
            rain_cv_pct = 100 * sd(rain_mm[sas_year %in% rain_baseline]) / rain_normal_ab_mm,
            dry_seasons_2016_2025 = sum(rain_std_anomaly[sas_year %in% 2016:2025] < -1, na.rm = TRUE),
            mean_anomaly_2019_2025 = mean(rain_anomaly_pct[sas_year %in% 2019:2025]),
            .groups = "drop")
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
    eq_df |> filter(sas_year %in% recent_years, !is.na(.data[[g]])) |>
      mutate(group = as.character(.data[[g]])) |>
      survey_mean_by("irrigated", "group") |> mutate(dimension = g, period = "2023-2025")),
  eq_df |> filter(!is.na(gender)) |> mutate(group = gender) |>
    survey_mean_by("irrigated", c("sas_year", "group")) |> mutate(dimension = "gender_trend")) |>
  mutate(across(c(estimate, se, ci_low, ci_high), \(x) 100 * x))
gender_district <- eq_df |> filter(sas_year %in% recent_years, !is.na(gender)) |>
  survey_mean_by("irrigated", c("district_std", "gender")) |>
  mutate(across(c(estimate, ci_low, ci_high), \(x) 100 * x))
save_app(list(equity = equity, gender_district = gender_district), "equity")

# ---- 8. PRIORITY SCREENING (preliminary, adjustable weights) ------------------
message("8/9 Priority screening + weight sensitivity")
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
         c_readiness = minmax(inorganic_fert_pct))
default_weights <- c(c_need = 0.30, c_gap = 0.30, c_scale = 0.20, c_equity = 0.10, c_readiness = 0.10)
score_with <- function(s, w) as.numeric(as.matrix(s[names(w)]) %*% (w / sum(w))) * 100
screen$score <- score_with(screen, default_weights)
screen$rank  <- rank(-screen$score, ties.method = "min")
# Sensitivity: 2,000 random weight sets (Dirichlet around equal weights)
set.seed(2026)
draws <- matrix(rgamma(2000 * 5, shape = 2), ncol = 5, dimnames = list(NULL, names(default_weights)))
rank_draws <- apply(draws, 1, \(w) rank(-score_with(screen, w), ties.method = "min"))
screen <- screen |>
  mutate(rank_median = apply(rank_draws, 1, median),
         rank_p10 = apply(rank_draws, 1, quantile, 0.10),
         rank_p90 = apply(rank_draws, 1, quantile, 0.90),
         prob_top5_pct = 100 * rowMeans(rank_draws <= 5),
         stability = case_when(rank_p90 - rank_p10 <= 4 ~ "Stable",
                               rank_p90 - rank_p10 <= 10 ~ "Moderately sensitive",
                               TRUE ~ "Sensitive to weights"))
save_app(list(table = screen, default_weights = default_weights), "priority_screening")

# ---- 9. EXPLORER, DOWNLOADS, METADATA -----------------------------------------
message("9/9 Explorer tables and metadata")
save_app(read_master("master_crop_season") |> filter(n_crop_plots >= 10), "crop_season")
save_app(read_master("master_crop_district_season") |> filter(n_crop_plots >= 10), "crop_district_season")
skip <- if (file.exists(file.path(dir_master, "skip_pattern_audit.csv")))
  read_csv(file.path(dir_master, "skip_pattern_audit.csv"), show_col_types = FALSE) else tibble()
joins <- if (file.exists(file.path(dir_master, "master_join_log.csv")))
  read_csv(file.path(dir_master, "master_join_log.csv"), show_col_types = FALSE) else tibble()
save_app(list(
  built = format(Sys.time(), "%Y-%m-%d %H:%M"),
  team = "NiyoIshimwe",
  sources = tibble(
    source = c("NISR Seasonal Agricultural Survey (SAS) 2019-2025, Seasons A/B/C",
               "CHIRPS v2 monthly rainfall by district, 1981-2025",
               "GADM 4.1 district boundaries (level 2)"),
    use = c("Irrigation, inputs, production, yields, farmer characteristics",
            "Season rainfall, anomalies vs 1991-2020, dry-season frequency",
            "District maps")),
  n_plots = nrow(plot_df), n_crop_plots = nrow(crop_df),
  skip_audit = skip, join_log = joins), "meta")

message(sprintf("Done in %.1f min. Files in %s:", as.numeric(difftime(Sys.time(), t0, units = "mins")), dir_app_data))
print(tibble(file = list.files(dir_app_data), kb = round(file.size(list.files(dir_app_data, full.names = TRUE)) / 1024)))
