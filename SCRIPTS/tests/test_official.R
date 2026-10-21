# Tests for the published-figures chain: 11 (read tables) -> 14 (pick figures) -> 15 (reconcile)
# Run from the project root:  Rscript SCRIPTS/tests/test_official.R
# Builds small synthetic NISR-style workbooks and master tables in a temporary
# folder; no real data is needed or touched.
suppressPackageStartupMessages({ library(dplyr); library(readr); library(openxlsx) })
repo <- normalizePath(".")
ok <- function(cond, msg) { cat(if (isTRUE(cond)) "PASS" else "FAIL", msg, "\n"); if (!isTRUE(cond)) fails <<- fails + 1 }
fails <- 0

root <- file.path(tempdir(), "official_test"); unlink(root, recursive = TRUE)
dir.create(file.path(root, "DATA", "NISR_published"), recursive = TRUE)
dir.create(file.path(root, "DATA", "processed", "master"), recursive = TRUE)
file.copy(file.path(repo, "DATA", "NISR_published", "indicator_rules.csv"), file.path(root, "DATA", "NISR_published"))
dir.create(file.path(root, "SCRIPTS")); file.copy(file.path(repo, "SCRIPTS", "00_Config.R"), file.path(root, "SCRIPTS"))
districts <- c("Nyarugenge", "Gasabo", "Kicukiro")

# a workbook laid out like the NISR SAS tables: title row, two header rows, data rows
sheet_inputs <- function(wb, name, title, vals) {
  addWorksheet(wb, name)
  writeData(wb, name, data.frame(x = title), colNames = FALSE, startRow = 1)
  hdr <- rbind(c("District", "Percentage of farmers who applied inorganic fertilizer", NA,
                 "Percentage of plots in which inorganic fertilizer was applied", NA),
               c(NA, "Overall", "SSF", "Overall", "SSF"))
  writeData(wb, name, as.data.frame(hdr), colNames = FALSE, startRow = 2)
  body <- data.frame(d = c(districts, "Rwanda"), vals)
  writeData(wb, name, body, colNames = FALSE, startRow = 4)
}
# NISR's district crop tables: one column per crop, one row per district and Rwanda
sheet_crop <- function(wb, name, title, crops, vals) {
  addWorksheet(wb, name)
  writeData(wb, name, data.frame(x = title), colNames = FALSE, startRow = 1)
  writeData(wb, name, as.data.frame(t(c("District", crops))), colNames = FALSE, startRow = 2)
  writeData(wb, name, data.frame(d = c(districts, "Rwanda"), vals), colNames = FALSE, startRow = 3)
}
vals_in <- data.frame(a = c(60, 50, 40, 55), b = c(59, 49, 39, 54), c = c(45, 35, 25, 40), d = c(44, 34, 24, 39))
wb <- createWorkbook()
sheet_inputs(wb, "Table 25", "Table 25: Use of Inorganic fertilizer by farmer type per district (Percentage)", vals_in)
sheet_crop(wb, "Table 6", "Table 6: Crop production by crop type and district (MT)", c("Cereals", "Maize", "Sorghum"),
           data.frame(g = c(200, 150, 250, 600), m = c(150, 120, 230, 500), s = c(50, 30, 20, 100)))
sheet_crop(wb, "Table 7", "Table 7: Average yield by crop type and district (MT/Ha)", c("Maize", "Sorghum"),
           data.frame(m = c(2, 2, 2, 2), s = c(1, 1, 1, 1)))
# a parent in one table and its parts in another (as SAS 2019 prints Beans and Bush/Climbing bean)
sheet_crop(wb, "Table 8", "Table 8: Crop production by crop type per district (MT)", c("Beans"),
           data.frame(b = c(30, 30, 40, 100)))
sheet_crop(wb, "Table 9", "Table 9: Crop production by crop type and district (MT)", c("Bush bean", "Climbing bean"),
           data.frame(b = c(10, 10, 20, 40), c = c(20, 20, 20, 60)))
saveWorkbook(wb, file.path(root, "DATA", "NISR_published", "Tables_2025 Season A.xlsx"))
# a later release, which must be skipped entirely
saveWorkbook(wb, file.path(root, "DATA", "NISR_published", "Tables_2026 Season A.xlsx"))

Sys.setenv(HACKATHON_ROOT = root)
owd <- setwd(root)
source(file.path(repo, "SCRIPTS", "11_NISR_Published_Tables.R"), local = new.env())
cells <- read_csv(file.path(root, "DATA", "processed", "official", "nisr_published_all_tables.csv"), show_col_types = FALSE)
ok(all(cells$sas_year <= 2025), "11: no figure after 2025 (2026 workbook skipped)")
ok(!any(grepl("2026", cells$source_file)), "11: the 2026 workbook is not read")
r <- cells |> filter(area == "Gasabo", grepl("farmers", column), farmer_type == "All")
ok(nrow(r) == 1 && r$value == 50 && r$cell == "B5" && r$sheet == "Table 25", "11: value, sheet and cell kept (Gasabo farmers = 50 in B5)")
ok(all(cells$sas_season == "A"), "11: season taken from the file name")

source(file.path(repo, "SCRIPTS", "14_Official_Reference.R"), local = new.env())
ref <- read_csv(file.path(root, "DATA", "processed", "official", "official_reference.csv"), show_col_types = FALSE)
f <- ref |> filter(indicator == "inorganic_fert_farmer", area == "Rwanda", farmer_type == "All")
ok(nrow(f) == 1 && f$value == 55, "14: farmers measure mapped to inorganic_fert_farmer")
p <- ref |> filter(indicator == "inorganic_fert", area == "Rwanda", farmer_type == "All")
ok(nrow(p) == 1 && p$value == 40, "14: plots measure mapped to inorganic_fert")
pr <- ref |> filter(indicator == "production_t", area == "Rwanda")
ok(isTRUE(pr$is_group[pr$crop_name == "Cereals (all)"]) && !any(pr$is_group[pr$crop_name %in% c("Maize", "Sorghum")]),
   "14: crop group column flagged as a subtotal and renamed")
ok(sum(pr$value[pr$crop_name %in% c("Maize", "Sorghum")]) == pr$value[pr$crop_name == "Cereals (all)"],
   "14: crops without the group add up to the group total")
ok(isTRUE(pr$is_group[pr$crop_name == "Beans (all)"]) && !"Beans" %in% pr$crop_name,
   "14: a parent printed in another table than its parts is a subtotal too (never added)")
ok(sum(pr$value[!pr$is_group]) == 500 + 100 + 40 + 60, "14: national crops add up without double counting")
y <- ref |> filter(indicator == "yield_kg_ha", crop_name == "Maize", area == "Rwanda")
ok(nrow(y) == 1 && y$value == 2000, "14: yield in t/ha converted to kg/ha")

# 15: synthetic master tables where the published farmer share is reproduced exactly
set.seed(3)
n_f <- 300
farm <- tibble(ys = "2025A", sas_year = 2025L, sas_season = "A", segment_id = rep(1:30, each = 10),
               farmer_id = 1:n_f, district_std = rep(districts, each = 100), weight = 1)
plots <- farm |> slice(rep(1:n_f, each = 3)) |> mutate(plot_number = rep(1:3, n_f),
  inorganic_fert = rbinom(n(), 1, .4), organic_fert = rbinom(n(), 1, .6), pesticide = rbinom(n(), 1, .3),
  inorganic_fert_raw = inorganic_fert, plot_area_ha = runif(n(), .05, .5), farmer_type = "Small scale farmer")
farm <- farm |> left_join(plots |> group_by(farmer_id) |>
  summarise(across(c(inorganic_fert, organic_fert, pesticide), max, .names = "{.col}_farmer")), by = "farmer_id")
crop <- plots |> transmute(ys, sas_year, sas_season, segment_id, plot_number, district_std, weight,
                           crop_name = "Maize", harvest_kg = 100, crop_area_ha = .05)
saveRDS(plots, file.path(root, "DATA", "processed", "master", "master_plot.rds"))
saveRDS(farm,  file.path(root, "DATA", "processed", "master", "master_farmer.rds"))
saveRDS(crop,  file.path(root, "DATA", "processed", "master", "master_crop_plot.rds"))
# replace the published national farmer share with the synthetic truth
truth <- 100 * mean(farm$inorganic_fert_farmer)
ref2 <- ref |> mutate(value = if_else(indicator == "inorganic_fert_farmer" & area == "Rwanda" & farmer_type == "All", truth, value))
write_csv(ref2, file.path(root, "DATA", "processed", "official", "official_reference.csv"), na = "")
source(file.path(repo, "SCRIPTS", "15_Reconcile_With_NISR.R"), local = new.env())
best <- read_csv(file.path(root, "DATA", "processed", "official", "reconcile_inputs_best.csv"), show_col_types = FALSE)
b <- best |> filter(input == "inorganic_fert", measure == "farmers", rank == 1)
ok(nrow(b) == 1 && abs(b$national_gap) < 1e-9, "15: the farmer-level way reproduces a farmer-level published share")
rp <- read_csv(file.path(root, "DATA", "processed", "official", "reconcile_production.csv"), show_col_types = FALSE)
m <- rp |> filter(level == "national", crop_name == "Maize")
ok(nrow(m) == 1 && abs(m$prod_t - 90) < 1e-9 && abs(m$prod_ratio - 90 / 500) < 1e-9,
   "15: production compared crop by crop (group rows never matched)")
setwd(owd)
cat(if (fails) paste(fails, "test(s) FAILED\n") else "All official-chain tests passed\n")
quit(status = as.integer(fails > 0))
