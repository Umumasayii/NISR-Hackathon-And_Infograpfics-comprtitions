# Run from the project root:  Rscript SCRIPTS/tests/test_crop.R
repo <- normalizePath(".")
suppressPackageStartupMessages(library(dplyr))
src <- readLines(file.path(repo, "SCRIPTS/06_Merge_Master_Data.R"))
for (f in c("wsum", "wmean")) { i <- grep(paste0("^", f, " +<- function"), src); if (length(i)) eval(parse(text = src[i])) }
a <- grep("^crop_measures <- function", src); b <- a + grep("\\.groups = \"drop\"\\)", src[a:length(src)])[1] - 1
eval(parse(text = src[a:b]))
ok <- function(cond, msg) cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n")
set.seed(3)
d <- tibble(harvest_kg = rexp(400, 1/500), crop_area_ha = runif(400, .02, .5), weight = runif(400, 10, 90),
            irrigated = rbinom(400, 1, .2), yield_ok = runif(400) > .1, sas_year = 2025L,
            sas_season = rep(c("A", "B"), 200), season_yield_usable = sas_season == "A",
            sold_kg_plot = ifelse(runif(400) > .2, harvest_kg * runif(400), NA), price_rwf_kg = 300, sold_kg = sold_kg_plot,
            sales_value_rwf = sold_kg_plot * 300, price_imputed = FALSE, improved_seed = rbinom(400, 1, .4))
d$harvest_kg[sample(400, 20)] <- NA
d$yield_ok <- d$yield_ok & !is.na(d$harvest_kg)   # as in 06: a yield needs a harvest
by_s <- d |> group_by(sas_season) |> crop_measures()
all  <- d |> crop_measures()
k <- d$yield_ok & d$season_yield_usable
ok(isTRUE(all.equal(all$yield_kg_ha, sum((d$harvest_kg * d$weight)[k], na.rm = TRUE) / sum((d$crop_area_ha * d$weight)[k & !is.na(d$harvest_kg)]))), "yield = summed harvest / summed area (eligible plots)")
ok(is.na(by_s$yield_kg_ha[by_s$sas_season == "B"]) || by_s$yield_area_ha[by_s$sas_season == "B"] == 0, "season not usable gives no yield")
ok(isTRUE(all.equal(all$yield_kg_ha, sum(by_s$yield_harvest_kg, na.rm = TRUE) / sum(by_s$yield_area_ha, na.rm = TRUE))), "season sums recombine to the pooled yield")
ok(all$sold_share_pct <= 100, "sold share on matched plots stays within 0-100")
ok(isTRUE(all.equal(all$n_yield, all$n_irrigated_yield + all$n_rainfed_yield)), "irrigated + rain-fed yield plots = all yield plots")
