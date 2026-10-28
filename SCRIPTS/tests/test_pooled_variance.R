# Pooled-season standard errors: segments are clusters across seasons.
# Needs the survey microdata (DATA/processed/master). Run from the project root:
#   Rscript SCRIPTS/tests/test_pooled_variance.R
suppressMessages({library(dplyr); library(survey)})
source("SCRIPTS/00_Config.R")
p <- readRDS("DATA/processed/master/master_plot.rds") |> add_design_vars() |>
  filter(sas_year %in% 2023:2025, sas_season %in% c("A","B"), !is.na(irrigated))
r <- survey_mean_by(p, "irrigated", character())
print(as.data.frame(r))
pooled_cluster_segments <- FALSE
r0 <- survey_mean_by(p, "irrigated", character()); pooled_cluster_segments <- TRUE
cat("independent-seasons SE:", r0$se, " segment-cluster SE:", r$se, " ratio:", r$se / r0$se, "\n")
q <- p |> mutate(pstr = paste(district_std, stratum), ppsu = segment_id)
des <- svydesign(ids = ~ppsu, strata = ~pstr, weights = ~weight, data = q, nest = TRUE)
s <- svymean(~irrigated, des)
cat("survey package: est", coef(s), "se", SE(s), "\n")
stopifnot(abs(coef(s) - r$estimate) < 1e-10, abs(SE(s) - r$se) < 1e-8)
cat("PASS: pooled estimate and SE equal survey::svymean with segment clusters\n")
