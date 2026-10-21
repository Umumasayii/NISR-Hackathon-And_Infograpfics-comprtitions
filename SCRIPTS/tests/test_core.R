# Run from the project root:  Rscript SCRIPTS/tests/test_core.R
repo <- normalizePath(".")
suppressPackageStartupMessages({library(dplyr); library(survey)})
Sys.setenv(HACKATHON_ROOT = tempdir())
source(file.path(repo, "SCRIPTS/00_Config.R"))
# pull the three model helpers out of 08 without running the models
src <- readLines(file.path(repo, "SCRIPTS/08_Models.R"))
a <- grep("^auc <- function", src); b <- grep("^test\\$p_glm", src) - 1
eval(parse(text = src[a:b]))
ok <- function(cond, msg) cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n")
# 1. ties: one positive, one negative, same score -> 0.5 in either order
ok(auc(c(1,0), c(.5,.5)) == 0.5 && auc(c(0,1), c(.5,.5)) == 0.5, "AUC tied pair = 0.5 whatever the order")
old_auc <- function(y, p, w = rep(1, length(y))) { o <- order(p); y <- y[o]; w <- w[o]; pos <- w*(y==1); neg <- w*(y==0); sum(pos*(cumsum(neg)-neg/2))/(sum(pos)*sum(neg)) }
cat("  old implementation on the same pairs:", old_auc(c(1,0), c(.5,.5)), old_auc(c(0,1), c(.5,.5)), "\n")
set.seed(1); y <- rbinom(5000, 1, .1); p <- round(plogis(-2 + 1.5*y + rnorm(5000)), 1); w <- runif(5000, .5, 2)
# brute-force weighted pair count
P <- which(y==1); N <- which(y==0)
bf <- sum(outer(w[P], w[N]) * (outer(p[P], p[N], ">") + 0.5*outer(p[P], p[N], "=="))) / (sum(w[P])*sum(w[N]))
ok(abs(auc(y, p, w) - bf) < 1e-12, sprintf("weighted AUC with many ties = brute force (%.6f)", bf))
cat("  old implementation on heavily tied data:", round(old_auc(y, p, w), 6), "vs correct", round(bf, 6), "\n")
ok(abs(avg_precision(y, runif(5000), w) - sum(w*y)/sum(w)) < 0.03, "average precision of a random score is close to prevalence")
tk <- top_k(y, p, w); ok(tk[["share"]] >= 0.10, "top-10% selection holds at least 10% of the weight")
# 2. survey_mean_by: SAS seasons and AHS rounds against survey::svyby
mk <- function(id) { set.seed(id); n <- 2000
  d <- tibble(strat = sample(1:20, n, TRUE), psu0 = sample(1:6, n, TRUE), weight = runif(n, 10, 100), y = rbinom(n, 1, .3), g = sample(c("a","b"), n, TRUE))
  d |> mutate(psu = as.integer(factor(paste(strat, psu0)))) }
s1 <- mk(1) |> mutate(sas_year = 2024L, sas_season = "A"); s2 <- mk(2) |> mutate(sas_year = 2024L, sas_season = "B", strat = strat + 100L, psu = psu + 10000L)
ours <- survey_mean_by(bind_rows(s1, s2), "y", c("sas_year", "sas_season", "g"))
ref <- bind_rows(lapply(list(s1, s2), \(d) { des <- svydesign(ids = ~psu, strata = ~strat, weights = ~weight, data = d, nest = TRUE)
  r <- svyby(~y, ~g, des, svymean); tibble(sas_season = d$sas_season[1], g = r$g, est = r$y, se = SE(r)) }))
cmp <- inner_join(ours, ref, by = c("sas_season", "g"))
ok(max(abs(cmp$estimate - cmp$est)) < 1e-10 && max(abs(cmp$se.x - cmp$se.y)) < 1e-8, "SAS seasons: estimate and SE equal svyby")
a1 <- mk(3) |> mutate(year = 2020L); a2 <- mk(4) |> mutate(year = 2024L, strat = strat + 100L, psu = psu + 10000L)
oa <- tryCatch(survey_mean_by(bind_rows(a1, a2), "y", c("year", "g")), error = \(e) { cat("  error:", conditionMessage(e), "\n"); NULL })
refa <- bind_rows(lapply(list(a1, a2), \(d) { des <- svydesign(ids = ~psu, strata = ~strat, weights = ~weight, data = d, nest = TRUE)
  r <- svyby(~y, ~g, des, svymean); tibble(year = d$year[1], g = r$g, est = r$y, se = SE(r)) }))
ok(!is.null(oa) && { c2 <- inner_join(oa, refa, by = c("year", "g")); nrow(c2) == 4 && max(abs(c2$estimate - c2$est)) < 1e-10 && max(abs(c2$se.x - c2$se.y)) < 1e-8 },
   "AHS rounds (year, no sas_year): runs, estimate and SE equal svyby")
