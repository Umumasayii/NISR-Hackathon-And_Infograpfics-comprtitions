# ============================================================================
# 00_Config.R  -  shared settings for the SmartIrrigate Rwanda build
# Team NiyoIshimwe - NISR 2026 Big Data Hackathon
#
# Sourced by 07_Build_App_Data.R and 08_Models.R. Run everything from the
# Hackathon project root with:  source("SCRIPTS/09_Run_All.R")
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(purrr); library(stringr); library(readr)
})

# ---- paths -------------------------------------------------------------------
dir_root     <- Sys.getenv("HACKATHON_ROOT", ".")
dir_master   <- file.path(dir_root, "DATA", "processed", "master")
dir_sel      <- file.path(dir_root, "DATA", "processed", "selection")
dir_scripts  <- file.path(dir_root, "SCRIPTS")
dir_app_data <- file.path(dir_scripts, "app", "data")
dir.create(dir_app_data, showWarnings = FALSE, recursive = TRUE)

read_master <- function(name) readRDS(file.path(dir_master, paste0(name, ".rds")))
save_app    <- function(x, name) saveRDS(x, file.path(dir_app_data, paste0(name, ".rds")), compress = "xz")

# ---- analysis settings ---------------------------------------------------------
main_seasons   <- c("A", "B")          # main rain-fed seasons
recent_years   <- 2023:2025            # "current situation" window
rain_baseline  <- 1991:2020
min_n          <- 30                   # suppress estimates below this unweighted n
options(survey.lonely.psu = "adjust")  # single-PSU strata (e.g. large-scale farms)

# Reliability label used on every KPI and chart (Section 13: "sample/quality indication")
reliability <- function(n, cv) case_when(
  is.na(n) | n < min_n            ~ "Unreliable",
  !is.na(cv) & cv <= 0.20 & n >= 50 ~ "Good",
  !is.na(cv) & cv <= 0.35         ~ "Use with caution",
  TRUE                             ~ "Unreliable")

# ---- survey design -----------------------------------------------------------
# PSU = segment (2022C has no segment_id: district + stratum + segment number)
add_design_vars <- function(d) d |>
  mutate(psu = coalesce(as.character(segment_id),
                        paste(district_std, stratum, segment_number, sep = "_")),
         strat = coalesce(as.character(stratum), "unknown"),
         # integer codes: newer 'survey' versions coerce character strata with
         # as.numeric() for lonely-PSU handling, giving NA and SE = Inf
         psu = as.integer(factor(psu)), strat = as.integer(factor(strat))) |>
  filter(!is.na(weight), weight > 0)

# Weighted mean of a 0/1 (or numeric) variable with design-based SE, by groups.
# Returns estimate, se, 95% CI, unweighted n, cv and reliability.
survey_mean_by <- function(d, var, by) {
  d <- d |> filter(!is.na(.data[[var]]))
  if (!nrow(d)) return(tibble())
  d |>
    group_by(across(all_of(by))) |>
    group_modify(\(g, k) {
      if (nrow(g) < 2) return(tibble(estimate = mean(g[[var]]), se = NA_real_, n = nrow(g), wsum = sum(g$weight)))
      des <- survey::svydesign(ids = ~psu, strata = ~strat, weights = ~weight, data = g, nest = TRUE)
      m <- survey::svymean(as.formula(paste0("~", var)), des)
      # wsum (weighted count) lets the app combine several districts or provinces
      tibble(estimate = as.numeric(coef(m)), se = as.numeric(survey::SE(m)), n = nrow(g), wsum = sum(g$weight))
    }) |>
    ungroup() |>
    mutate(indicator = var,
           ci_low  = pmax(estimate - 1.96 * se, 0),
           ci_high = estimate + 1.96 * se,
           cv = if_else(estimate > 0, se / estimate, NA_real_),
           reliability = reliability(n, cv))
}

# Ratio estimator (e.g. yield = sum harvest / sum area) with design-based SE
survey_ratio_by <- function(d, num, den, by) {
  d <- d |> filter(!is.na(.data[[num]]), !is.na(.data[[den]]), .data[[den]] > 0)
  if (!nrow(d)) return(tibble())
  d |>
    group_by(across(all_of(by))) |>
    group_modify(\(g, k) {
      if (nrow(g) < 2) return(tibble(estimate = sum(g[[num]]) / sum(g[[den]]), se = NA_real_, n = nrow(g)))
      des <- survey::svydesign(ids = ~psu, strata = ~strat, weights = ~weight, data = g, nest = TRUE)
      r <- survey::svyratio(as.formula(paste0("~", num)), as.formula(paste0("~", den)), des)
      tibble(estimate = as.numeric(coef(r)), se = as.numeric(survey::SE(r)), n = nrow(g))
    }) |>
    ungroup() |>
    mutate(ci_low = pmax(estimate - 1.96 * se, 0), ci_high = estimate + 1.96 * se,
           cv = if_else(estimate > 0, se / estimate, NA_real_), reliability = reliability(n, cv))
}

minmax <- function(x) { r <- range(x, na.rm = TRUE); if (diff(r) == 0) x * 0 else (x - r[1]) / diff(r) }
