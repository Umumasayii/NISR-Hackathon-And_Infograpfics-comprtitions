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

# Reliability label used on every KPI and chart (Section 13: "sample/quality indication").
# Uses the unweighted sample (n), the number of segments it comes from (n_psu,
# the survey's clusters) and the coefficient of variation (cv).
reliability <- function(n, cv, n_psu = Inf) case_when(
  is.na(n) | n < min_n | n_psu < min_psu         ~ "Unreliable",
  !is.na(cv) & cv <= 0.20 & n >= 50 & n_psu >= 12 ~ "Good",
  !is.na(cv) & cv <= 0.35                         ~ "Use with caution",
  TRUE                                            ~ "Unreliable")
min_psu <- 5                           # fewer segments than this: not reliable

# ---- survey design -----------------------------------------------------------
# Each season is its own sample: strata = season x district x land-use stratum,
# PSU = segment within the season (2022C has no segment_id: district + stratum +
# segment number). Pooling several seasons then keeps them as separate strata.
add_design_vars <- function(d) d |>
  mutate(.ys = paste0(sas_year, sas_season),
         psu = paste(.ys, coalesce(as.character(segment_id),
                                   paste(district_std, stratum, segment_number, sep = "_"))),
         strat = paste(.ys, district_std, coalesce(as.character(stratum), "unknown")),
         # integer codes: newer 'survey' versions coerce character strata with
         # as.numeric() for lonely-PSU handling, giving NA and SE = Inf
         psu = as.integer(factor(psu)), strat = as.integer(factor(strat))) |>
  select(-.ys) |>
  filter(!is.na(weight), weight > 0)

# Design variables for models that pool seasons or years: the PHYSICAL segment is the
# cluster (it is revisited across seasons and years) and district x land-use stratum
# the stratum. Integer codes, as above.
add_pooled_design_vars <- function(d) d |>
  mutate(ppsu = as.integer(factor(coalesce(as.character(segment_id),
                                           paste(sas_year, sas_season, district_std, stratum, segment_number)))),
         pstr = as.integer(factor(paste(district_std, coalesce(as.character(stratum), "unknown")))))

# Domain estimation that keeps the FULL design. Each season is a separate sample,
# so a design is built per season on EVERY row of that season, and districts,
# gender, crops etc. are domains inside it (never cut out before the design).
# Per season and domain we take survey totals of y and x with their covariance;
# pooled results (several seasons) add these up, as independent samples do. The
# estimate is the ratio R = Y / X (a mean when x = 1) with the usual linearised
# variance (VarY - 2R CovXY + R^2 VarX) / X^2, and a t-based 95% CI using the
# design's degrees of freedom.
.dom_key <- function(d, dom) if (length(dom)) do.call(paste, c(lapply(d[dom], \(x) coalesce(as.character(x), "(missing)")), sep = "\r")) else rep("all", nrow(d))

# Per season: survey totals of y and x for every domain, with their variances and
# covariance, for a stratified one-stage cluster design (PSUs with replacement, as
# survey::svydesign(ids = ~psu, strata = ~strat) computes them; single-PSU strata
# centred on the design average like options(survey.lonely.psu = "adjust")).
# Written out with dplyr because it is ~8x faster than svyby(); it was checked to
# give the same estimates and standard errors as survey::svyby(..., svytotal).
.season_totals <- function(g, dom) {
  keep <- g$.ok & (if (length(dom)) stats::complete.cases(g[dom]) else TRUE)
  if (!any(keep)) return(tibble())
  g$.dom <- .dom_key(g, dom)
  ps <- distinct(g, strat, psu) |> count(strat, name = "nh")
  N <- sum(ps$nh); H <- nrow(ps)
  z <- g[keep, ] |> group_by(.dom, strat, psu) |>
    summarise(zy = sum(weight * .y), zx = sum(weight * .x), .groups = "drop") |>
    left_join(ps, by = "strat")
  tot <- z |> group_by(.dom) |> summarise(Y = sum(zy), X = sum(zx), .groups = "drop")
  reg <- z |> filter(nh > 1) |> group_by(.dom, strat, nh) |>
    summarise(sy = sum(zy), sx = sum(zx), syy = sum(zy^2), sxx = sum(zx^2), sxy = sum(zy * zx), .groups = "drop") |>
    mutate(f = nh / (nh - 1), vY = f * (syy - sy^2 / nh), vX = f * (sxx - sx^2 / nh), cXY = f * (sxy - sy * sx / nh)) |>
    group_by(.dom) |> summarise(across(c(vY, vX, cXY), sum), .groups = "drop")
  # lonely PSUs: centred on the average PSU total of the whole design ("adjust")
  lone <- ps |> filter(nh == 1)
  lv <- if (nrow(lone)) {
    tot |> mutate(my = Y / N, mx = X / N) |>
      tidyr::crossing(strat = lone$strat) |>
      left_join(z |> filter(nh == 1) |> select(.dom, strat, zy, zx), by = c(".dom", "strat")) |>
      mutate(zy = coalesce(zy, 0), zx = coalesce(zx, 0)) |>
      group_by(.dom) |> summarise(vY = sum((zy - my)^2), vX = sum((zx - mx)^2), cXY = sum((zy - my) * (zx - mx)), .groups = "drop")
  } else tibble(.dom = character(), vY = numeric(), vX = numeric(), cXY = numeric())
  key <- g[keep, ] |> group_by(.dom, across(all_of(dom))) |>
    summarise(n = n(), n_psu = n_distinct(psu), wsum = sum(weight), .groups = "drop")
  tot |> left_join(bind_rows(reg, lv) |> group_by(.dom) |> summarise(across(everything(), sum)), by = ".dom") |>
    mutate(across(c(vY, vX, cXY), \(v) coalesce(v, 0)), df = N - H) |>
    left_join(key, by = ".dom")
}

# The independent samples: SAS seasons (sas_year + sas_season) or, for the AHS,
# survey rounds (year). Each sample gets its own design; pooled results add them.
.sample_cols <- function(d) {
  if (all(c("sas_year", "sas_season") %in% names(d))) c("sas_year", "sas_season")
  else if ("year" %in% names(d)) "year"
  else stop("survey_mean_by / survey_ratio_by: no sample identity (sas_year + sas_season, or year)")
}

.ratio_est <- function(d, by) {
  if (!nrow(d) || !any(d$.ok)) return(tibble())
  smp <- .sample_cols(d)
  seas <- intersect(by, smp); dom <- setdiff(by, seas)
  d$.season <- do.call(paste, unname(as.list(d[smp])))
  per <- d |> group_by(.season) |> group_modify(\(g, k) .season_totals(g, dom)) |> ungroup()
  if (!nrow(per)) return(tibble())
  per <- per |> left_join(distinct(d, across(all_of(c(".season", smp)))), by = ".season")
  out <- per |> group_by(across(all_of(c(seas, dom)))) |>
    summarise(across(c(Y, X, vY, vX, cXY, df, n, n_psu, wsum), sum), .groups = "drop") |>
    mutate(estimate = Y / X,
           se = sqrt(pmax(vY - 2 * estimate * cXY + estimate^2 * vX, 0)) / X) |>
    select(-Y, -X, -vY, -vX, -cXY)
  # Several seasons pooled into one estimate: the seasons are NOT independent samples.
  # SAS revisits the same segments (2020-2025: ~97% of Season A segments are surveyed
  # again in Season B and ~98% again next year), so adding season variances would
  # understate the error. Pooled results are re-estimated with the PHYSICAL segment as
  # the cluster across all pooled seasons (see .pooled_var). n_psu then counts
  # distinct segments, not segment-seasons.
  if (length(setdiff(smp, by)) && pooled_cluster_segments && "segment_id" %in% names(d)) {
    g <- c(seas, dom)
    if (!length(g)) { d$.all <- "all"; out$.all <- "all"; g <- ".all" }
    pv <- .pooled_var(d, g, out)
    out <- out |> select(-se, -df, -n_psu) |> left_join(pv, by = g) |> select(-any_of(".all"))
  }
  out
}

# Pooled-season variance with segments as clusters across seasons. Physical stratum =
# district x land-use stratum; physical PSU = segment_id (2022C, which has no
# segment_id, keeps its season-specific segment). Linearised ratio scores
# u = w * (y - R x) are summed per segment over every pooled season, and the variance
# is the usual with-replacement between-segment variance within strata, / X^2.
pooled_cluster_segments <- TRUE
.pooled_var <- function(d, grp, est) {
  d <- d |> mutate(.pstr = paste(district_std, coalesce(as.character(stratum), "u")),
                   .ppsu = coalesce(as.character(segment_id),
                                    paste(sas_year, sas_season, district_std, stratum, segment_number)))
  ps <- distinct(d, .pstr, .ppsu) |> count(.pstr, name = "nh")
  N <- nrow(distinct(d, .ppsu)); H <- nrow(ps)
  keep <- d$.ok & (if (length(grp)) stats::complete.cases(d[grp]) else TRUE)
  z <- d[keep, ] |>
    left_join(est |> select(all_of(grp), .R = estimate), by = grp) |>
    group_by(across(all_of(grp)), .pstr, .ppsu) |>
    summarise(u = sum(weight * (.y - .R * .x)), X = sum(weight * .x), .groups = "drop") |>
    left_join(ps, by = ".pstr")
  # all segments of a stratum count, also those with no row in the domain (u = 0)
  v <- z |> group_by(across(all_of(grp)), .pstr, nh) |>
    summarise(su = sum(u), suu = sum(u^2), .groups = "drop") |>
    mutate(vh = if_else(nh > 1, nh / (nh - 1) * (suu - su^2 / nh), su^2)) |>
    group_by(across(all_of(grp))) |> summarise(V = sum(vh), .groups = "drop")
  z |> group_by(across(all_of(grp))) |>
    summarise(X = sum(X), n_psu = n_distinct(.ppsu), .groups = "drop") |>
    left_join(v, by = grp) |>
    transmute(across(all_of(grp)), se = sqrt(pmax(V, 0)) / X, df = N - H, n_psu)
}

.finish <- function(out) out |>
  mutate(se = if_else(n < 2, NA_real_, se),
         tq = qt(0.975, pmax(df, 1)),
         ci_low  = pmax(estimate - tq * se, 0),
         ci_high = estimate + tq * se,
         cv = if_else(estimate > 0, se / estimate, NA_real_),
         reliability = reliability(n, cv, n_psu)) |>
  select(-tq)

# Weighted mean of a 0/1 (or numeric) variable with design-based SE, by groups.
# Returns estimate, se, 95% CI, unweighted n, number of segments (n_psu), cv,
# design degrees of freedom and reliability.
survey_mean_by <- function(d, var, by) {
  if (!nrow(d)) return(tibble())
  d$.y <- as.numeric(d[[var]]); d$.x <- 1; d$.ok <- !is.na(d$.y)
  .ratio_est(d, by) |> mutate(indicator = var) |> .finish()
}

# Ratio estimator (e.g. yield = sum harvest / sum area) with design-based SE
survey_ratio_by <- function(d, num, den, by) {
  if (!nrow(d)) return(tibble())
  d$.y <- as.numeric(d[[num]]); d$.x <- as.numeric(d[[den]])
  d$.ok <- !is.na(d$.y) & !is.na(d$.x) & d$.x > 0
  .ratio_est(d, by) |> .finish()
}

minmax <- function(x) { r <- range(x, na.rm = TRUE); if (diff(r) == 0) x * 0 else (x - r[1]) / diff(r) }
