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
  mutate(.row = row_number()) |>
  transmute(
    .row, segment_id, irrigated, weight, sas_year, district_std, province = fct_na(province),
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

md_design <- plot_df |>
  filter(sas_year >= 2020, sas_season %in% main_seasons, !is.na(irrigated), plot_area_ha > 0) |>
  add_pooled_design_vars() |> transmute(.row = row_number(), ppsu, pstr)
train <- md |> filter(sas_year <= 2023)
test  <- md |> filter(sas_year >= 2024)
features <- c("district", "season", "log_plot_area", "rain_anomaly_z", "erosion", "consolidated",
              "inorganic_fert", "organic_fert", "gender", "age_band", "large_farm")
fml <- as.formula(paste("irrigated ~", paste(features, collapse = " + ")))

# weights normalised to mean 1 so the logistic fit is not dominated by scale
train$w <- train$weight / mean(train$weight)
fit_warnings <- character()
glm_fit <- withCallingHandlers(glm(fml, family = binomial(), data = train, weights = w),
  warning = \(w) { fit_warnings <<- c(fit_warnings, conditionMessage(w)); invokeRestart("muffleWarning") })
rf_fit  <- ranger::ranger(fml, data = train |> mutate(irrigated = factor(irrigated)),
                          probability = TRUE, num.trees = 300, min.node.size = 50,
                          case.weights = train$w, importance = "permutation", seed = 2026)

# Weighted Mann-Whitney AUC with ties counted as 1/2. Rows are grouped by predicted
# value first: within a tie group every positive-negative pair scores 0.5 whatever
# the row order (the earlier version scored a tied pair 0 or 1 depending on order).
auc <- function(y, p, w = rep(1, length(y))) {
  g <- tibble(p, pos = w * (y == 1), neg = w * (y == 0)) |>
    group_by(p) |> summarise(pos = sum(pos), neg = sum(neg), .groups = "drop") |> arrange(p)
  neg_below <- cumsum(g$neg) - g$neg
  sum(g$pos * (neg_below + g$neg / 2)) / (sum(g$pos) * sum(g$neg))
}
# Weighted average precision (area under the precision-recall curve, step version);
# tied predictions enter together. Its no-skill value is the positive share.
avg_precision <- function(y, p, w = rep(1, length(y))) {
  g <- tibble(p, pos = w * (y == 1), all = w) |>
    group_by(p) |> summarise(pos = sum(pos), all = sum(all), .groups = "drop") |> arrange(desc(p))
  tp <- cumsum(g$pos); pp <- cumsum(g$all)
  sum((tp / pp) * g$pos) / sum(g$pos)
}
# The plots with the top 10% of predicted values (by weight): what share of them is
# irrigated, and what share of all irrigated plots they hold (ties enter together)
top_k <- function(y, p, w, k = 0.10) {
  o <- order(-p); cw <- cumsum(w[o]) / sum(w); cut <- p[o][which(cw >= k)[1]]
  sel <- p >= cut
  c(precision = sum(w[sel] * y[sel]) / sum(w[sel]), recall = sum(w[sel] * y[sel]) / sum(w * y), share = sum(w[sel]) / sum(w))
}
test$p_glm <- predict(glm_fit, newdata = test, type = "response")
test$p_rf  <- predict(rf_fit, data = test)$predictions[, "1"]
# Baselines: the training-period share of irrigated plots used as a constant
# prediction (a prospective baseline) and the test share (descriptive baseline).
prev_train <- sum(train$weight * train$irrigated) / sum(train$weight)
metrics <- function(d, p) {
  q_test <- sum(d$weight * d$irrigated) / sum(d$weight)
  tk <- top_k(d$irrigated, d[[p]], d$weight)
  tibble(
    auc = auc(d$irrigated, d[[p]], d$weight),
    avg_precision = avg_precision(d$irrigated, d[[p]], d$weight),
    avg_precision_baseline = q_test,
    brier = sum(d$weight * (d[[p]] - d$irrigated)^2) / sum(d$weight),
    brier_baseline_train = sum(d$weight * (prev_train - d$irrigated)^2) / sum(d$weight),
    brier_baseline_test = q_test * (1 - q_test),
    top10_precision_pct = 100 * tk[["precision"]], top10_recall_pct = 100 * tk[["recall"]],
    top10_lift = tk[["precision"]] / q_test,
    observed_pct = 100 * q_test,
    predicted_pct = 100 * sum(d$weight * d[[p]]) / sum(d$weight),
    n = nrow(d))
}
perf <- bind_rows(metrics(test, "p_glm") |> mutate(model = "Logistic regression"),
                  metrics(test, "p_rf")  |> mutate(model = "Random forest")) |>
  mutate(validation = "Out-of-time: trained 2020-2023, tested 2024-2025",
         auc_method = "weighted Mann-Whitney, ties = 1/2 (fixed 2026-10-20)")

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

# Odds ratios with DESIGN-BASED intervals: same weighted point estimates as glm(), but
# standard errors from survey::svyglm with the physical segment as cluster (segments
# are revisited across seasons and years) and t quantiles on the design df. The plain
# glm() intervals treated every plot as independent and were too narrow.
# Fit problems are recorded, not hidden: warnings, convergence and near-0/1 fitted
# values (a sign of separation).
train_des <- survey::svydesign(ids = ~ppsu, strata = ~pstr, weights = ~weight,
                               data = train |> left_join(md_design, by = ".row"), nest = TRUE)
svy_fit <- withCallingHandlers(survey::svyglm(fml, design = train_des, family = quasibinomial()),
  warning = \(w) { fit_warnings <<- c(fit_warnings, paste("svyglm:", conditionMessage(w))); invokeRestart("muffleWarning") })
coefs <- {
  b <- coef(svy_fit); se <- survey::SE(svy_fit); tq <- qt(0.975, survey::degf(train_des))
  tibble(term = names(b), estimate = b, se = se) |>
    mutate(odds_ratio = exp(estimate), or_low = exp(estimate - tq * se), or_high = exp(estimate + tq * se),
           se_naive_glm = summary(glm_fit)$coefficients[term, 2])
}
fitted_p <- fitted(glm_fit)
diagnostics <- list(
  converged = glm_fit$converged, iterations = glm_fit$iter, warnings = unique(fit_warnings),
  fitted_near_0_or_1 = sum(fitted_p < 1e-3 | fitted_p > 1 - 1e-3),
  terms_with_se_over_10 = names(which(survey::SE(svy_fit) > 10)),
  design_df = survey::degf(train_des), n_segments_train = n_distinct(train_des$cluster[[1]]),
  # segments are revisited, so the 2024-2025 check shares units with training
  test_segments_in_train_pct = 100 * mean(unique(test$segment_id) %in% unique(train$segment_id)),
  decision_date = paste("Contemporaneous classification: fertiliser use, plot erosion and the season's rain anomaly",
                        "are only known during or after the season, so this is NOT a validated pre-season forecast."))
message("glm converged: ", glm_fit$converged, "; warnings: ", length(unique(fit_warnings)),
        "; near-0/1 fitted: ", diagnostics$fitted_near_0_or_1)
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
              coefficients = coefs, importance = importance, potential = potential, diagnostics = diagnostics,
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
  # seasons are pooled, so the physical segment is the cluster (revisited across seasons)
  des_all <- survey::svydesign(ids = ~ppsu, strata = ~pstr, weights = ~weight,
                               data = d |> filter(sas_season %in% main_seasons, season_yield_usable %in% TRUE) |>
                                 add_pooled_design_vars(), nest = TRUE)
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
         n = nrow(dd), n_irrigated = sum(dd$irrigated == 1L), n_psu = n_distinct(dd$segment_id))
}
yield_adj <- map_dfr(crops, \(cn) tryCatch(fit_crop(cn), error = \(e) { message("  skipped ", cn, ": ", conditionMessage(e)); NULL })) |>
  mutate(direction = case_when(adjusted_low > 0 ~ "Higher on irrigated plots",
                               adjusted_high < 0 ~ "Lower on irrigated plots",
                               TRUE ~ "No clear difference"))
save_app(list(table = yield_adj,
              controls = "inorganic & organic fertiliser, improved seed (unknown kept as its own group), crop area, district, year-season",
              # what the two numbers are (they are different estimands): raw_pct compares
              # weighted harvest / weighted area (ratio of sums); adjusted_pct is exp(b) - 1
              # from a survey-weighted regression of log(yield per plot)
              estimands = c(raw = "ratio of weighted sums: sum(harvest) / sum(area), irrigated vs rain-fed",
                            adjusted = "exp(coefficient) - 1 from a survey-weighted log(yield) regression"),
              eligibility = "harvest > 0, crop area known, yield inside the 1st-99th percentile of its crop-season; seasons with < 80% crop-area coverage left out; Seasons A+B",
              excluded_seasons = read_csv(file.path(dir_master, "season_quality.csv"), show_col_types = FALSE) |>
                filter(!yield_usable) |> transmute(season = paste0(sas_year, sas_season), area_coverage_pct)),
         "model_yield")
print(yield_adj |> mutate(across(where(is.numeric), \(x) round(x, 1))), n = 30)
