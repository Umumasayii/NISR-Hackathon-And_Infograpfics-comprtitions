# ============================================================================
# 08_Models.R  -  irrigation adoption model + adjusted yield associations
# SmartIrrigate Rwanda - Team NiyoIshimwe
#
# A. Adoption model: which plot and farmer characteristics are associated with
#    a plot being irrigated (Seasons A+B, 2020-2025)?
#    - weighted logistic regression (explainable, used by the app simulator)
#    - random forest (ranger) as a benchmark
#    - OUT-OF-TIME validation: train 2020-2023, test 2024-2025
#    - calibration by decile, fairness checks by gender and province
# B. Adjusted yield association per crop: survey-weighted regression of
#    log(yield) on irrigation + inputs + plot + district + season.
#    These are ADJUSTED ASSOCIATIONS, not causal effects (Section 13).
#
# OUTPUT: SCRIPTS/app/data/model_adoption.rds, model_yield.rds
# ============================================================================

source(file.path(Sys.getenv("HACKATHON_ROOT", "."), "SCRIPTS", "00_Config.R"))
set.seed(2026)

plot_df <- read_master("master_plot") |> add_design_vars()
rain    <- read_master("master_rain_district_season") |>
  select(district_std, sas_year, sas_season, rain_std_anomaly)

# ---- A. ADOPTION MODEL ---------------------------------------------------------
message("A. Adoption model")
fct_na <- function(x, lv = NULL) { x <- as.character(x); x[is.na(x)] <- "Unknown"; if (is.null(lv)) factor(x) else factor(x, levels = lv) }
md <- plot_df |>
  filter(sas_year >= 2020, sas_season %in% main_seasons, !is.na(irrigated), plot_area_ha > 0) |>
  left_join(rain, by = c("district_std", "sas_year", "sas_season")) |>
  transmute(
    irrigated, weight, sas_year, district_std, province = fct_na(province),
    gender = fct_na(gender), season = factor(sas_season),
    log_plot_area = log(pmin(plot_area_ha, 20)),
    rain_anomaly_z = coalesce(rain_std_anomaly, 0),
    erosion = fct_na(str_remove(erosion_degree, "^[0-9] ")),
    consolidated = fct_na(if_else(land_consolidated == 1L, "Yes", "No")),
    inorganic_fert = fct_na(if_else(inorganic_fert == 1L, "Yes", "No")),
    organic_fert = fct_na(if_else(organic_fert == 1L, "Yes", "No")),
    age_band = fct_na(cut(age_years, c(-Inf, 34, 54, Inf), labels = c("Under 35", "35-54", "55+"))),
    # missing farmer type stays "Unknown" (it was counted as small-scale before)
    large_farm = factor(case_when(is.na(farmer_type) ~ "Unknown",
                                  str_detect(str_to_lower(farmer_type), "large") ~ "Large-scale",
                                  TRUE ~ "Small-scale")),
    district = factor(district_std))

train <- md |> filter(sas_year <= 2023)
test  <- md |> filter(sas_year >= 2024)
features <- c("district", "season", "log_plot_area", "rain_anomaly_z", "erosion", "consolidated",
              "inorganic_fert", "organic_fert", "gender", "age_band", "large_farm")
fml <- as.formula(paste("irrigated ~", paste(features, collapse = " + ")))

# weights normalised to mean 1 so the logistic fit is not dominated by scale
train$w <- train$weight / mean(train$weight)
glm_fit <- suppressWarnings(glm(fml, family = binomial(), data = train, weights = w))
rf_fit  <- ranger::ranger(fml, data = train |> mutate(irrigated = factor(irrigated)),
                          probability = TRUE, num.trees = 300, min.node.size = 50,
                          case.weights = train$w, importance = "permutation", seed = 2026)

auc <- function(y, p, w = rep(1, length(y))) {     # weighted Mann-Whitney AUC
  o <- order(p); y <- y[o]; w <- w[o]
  pos <- w * (y == 1); neg <- w * (y == 0)
  sum(pos * (cumsum(neg) - neg / 2)) / (sum(pos) * sum(neg))
}
test$p_glm <- predict(glm_fit, newdata = test, type = "response")
test$p_rf  <- predict(rf_fit, data = test)$predictions[, "1"]
metrics <- function(d, p) tibble(
  auc = auc(d$irrigated, d[[p]], d$weight),
  brier = sum(d$weight * (d[[p]] - d$irrigated)^2) / sum(d$weight),
  observed_pct = 100 * sum(d$weight * d$irrigated) / sum(d$weight),
  predicted_pct = 100 * sum(d$weight * d[[p]]) / sum(d$weight),
  n = nrow(d))
perf <- bind_rows(metrics(test, "p_glm") |> mutate(model = "Logistic regression"),
                  metrics(test, "p_rf")  |> mutate(model = "Random forest")) |>
  mutate(validation = "Out-of-time: trained 2020-2023, tested 2024-2025")

calibration <- test |>
  mutate(bin = ntile(p_glm, 10)) |>
  group_by(bin) |>
  summarise(predicted_pct = 100 * weighted.mean(p_glm, weight),
            observed_pct  = 100 * weighted.mean(irrigated, weight), n = n(), .groups = "drop")

fairness <- bind_rows(
  test |> filter(gender != "Unknown") |> group_by(group = as.character(gender)) |>
    group_modify(\(g, k) metrics(g, "p_glm")) |> mutate(dimension = "Gender"),
  test |> group_by(group = as.character(province)) |>
    group_modify(\(g, k) metrics(g, "p_glm")) |> mutate(dimension = "Province")) |>
  ungroup() |>
  mutate(calibration_gap_pts = predicted_pct - observed_pct)

coefs <- {
  s <- summary(glm_fit)$coefficients
  tibble(term = rownames(s), estimate = s[, 1], se = s[, 2]) |>
    mutate(odds_ratio = exp(estimate), or_low = exp(estimate - 1.96 * se), or_high = exp(estimate + 1.96 * se))
}
importance <- tibble(feature = names(rf_fit$variable.importance),
                     importance = as.numeric(rf_fit$variable.importance)) |>
  arrange(desc(importance)) |> mutate(importance = 100 * importance / max(importance))

# Prediction gap: districts where the model predicts more irrigated plots than were
# observed in the test years. A screening signal for follow-up, not a measure of
# what a programme would achieve.
potential <- test |>
  group_by(district_std) |>
  summarise(observed_pct = 100 * weighted.mean(irrigated, weight),
            predicted_pct = 100 * weighted.mean(p_rf, weight), n = n(), .groups = "drop") |>
  mutate(gap_pts = predicted_pct - observed_pct)

# A light copy of the logistic model for the app simulator (no data inside)
tt_light <- delete.response(terms(glm_fit))
attr(tt_light, ".Environment") <- baseenv()   # otherwise the training data is saved with the formula
glm_light <- list(terms = tt_light, xlevels = glm_fit$xlevels,
                  contrasts = glm_fit$contrasts, coefficients = coef(glm_fit))

save_app(list(performance = perf, calibration = calibration, fairness = fairness,
              coefficients = coefs, importance = importance, potential = potential,
              glm = glm_light, levels = lapply(md[features], \(x) if (is.factor(x)) levels(x) else range(x)),
              n_train = nrow(train), n_test = nrow(test)), "model_adoption")
print(perf)

# ---- B. ADJUSTED YIELD ASSOCIATION --------------------------------------------
# Observational, adjusted associations, NOT the effect of irrigation.
# Seasons with incomplete crop areas (season_quality.csv: 2024B, 2024C) are left out.
# Unknown fertiliser / seed answers stay "Unknown" (a separate category), and a
# complete-case fit (only plots where all three are known) is kept as a sensitivity check.
message("B. Adjusted yield association by crop")
crop_df <- read_master("master_crop_plot") |> add_design_vars() |>
  mutate(eligible = yield_ok & season_yield_usable %in% TRUE & sas_season %in% main_seasons & !is.na(irrigated))
crops <- crop_df |> filter(eligible, irrigated == 1L) |> count(crop_name) |> filter(n >= 150) |> pull(crop_name)
yn_unknown <- function(x) factor(case_when(x == 1L ~ "Yes", x == 0L ~ "No", TRUE ~ "Unknown"), levels = c("No", "Yes", "Unknown"))

fit_crop <- function(cn) {
  d <- crop_df |>
    mutate(in_crop = eligible & crop_name == cn,
           log_yield = if_else(in_crop, log(yield_kg_ha), NA_real_), log_area = log(crop_area_ha),
           inorganic = yn_unknown(inorganic_fert), organic = yn_unknown(organic_fert),
           seed = yn_unknown(improved_seed), ys = paste0(sas_year, sas_season),
           complete = in_crop & !is.na(inorganic_fert) & !is.na(organic_fert) & !is.na(improved_seed))
  # the crop is a domain of the full design (subset() keeps every segment)
  des_all <- survey::svydesign(ids = ~psu, strata = ~strat, weights = ~weight,
                               data = d |> filter(sas_season %in% main_seasons, season_yield_usable %in% TRUE), nest = TRUE)
  des <- subset(des_all, in_crop)
  f <- survey::svyglm(log_yield ~ irrigated + inorganic + organic + seed + log_area + district_std + ys, design = des)
  b <- coef(f)["irrigated"]; se <- survey::SE(f)["irrigated"]; dfr <- survey::degf(des); tq <- qt(0.975, dfr)
  fc <- tryCatch(survey::svyglm(log_yield ~ irrigated + inorganic + organic + seed + log_area + district_std + ys,
                                design = subset(des_all, complete)), error = \(e) NULL)
  bc <- if (is.null(fc)) NA_real_ else coef(fc)["irrigated"]
  dd <- filter(d, in_crop)
  raw <- dd |> group_by(irrigated) |> summarise(y = sum(weight * harvest_kg) / sum(weight * crop_area_ha))
  tibble(crop_name = cn,
         raw_pct = 100 * (raw$y[raw$irrigated == 1] / raw$y[raw$irrigated == 0] - 1),
         adjusted_pct = 100 * (exp(b) - 1),
         adjusted_low = 100 * (exp(b - tq * se) - 1),
         adjusted_high = 100 * (exp(b + tq * se) - 1),
         complete_case_pct = 100 * (exp(bc) - 1),           # sensitivity: only plots with all inputs known
         inputs_known_pct = round(100 * mean(dd$complete), 1),
         n = nrow(dd), n_irrigated = sum(dd$irrigated == 1L), n_psu = n_distinct(dd$psu))
}
yield_adj <- map_dfr(crops, \(cn) tryCatch(fit_crop(cn), error = \(e) { message("  skipped ", cn, ": ", conditionMessage(e)); NULL })) |>
  mutate(direction = case_when(adjusted_low > 0 ~ "Higher on irrigated plots",
                               adjusted_high < 0 ~ "Lower on irrigated plots",
                               TRUE ~ "No clear difference"))
save_app(list(table = yield_adj,
              controls = "inorganic & organic fertiliser, improved seed (unknown kept as its own group), crop area, district, year-season",
              excluded_seasons = read_csv(file.path(dir_master, "season_quality.csv"), show_col_types = FALSE) |>
                filter(!yield_usable) |> transmute(season = paste0(sas_year, sas_season), area_coverage_pct)),
         "model_yield")
print(yield_adj |> mutate(across(where(is.numeric), \(x) round(x, 1))), n = 30)
