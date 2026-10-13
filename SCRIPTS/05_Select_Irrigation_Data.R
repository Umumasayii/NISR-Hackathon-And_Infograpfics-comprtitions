rm(list = ls())
# ============================================================================
# SMARTIRRIGATE RWANDA | SELECT DATASETS + COLUMNS FOR IRRIGATION ANALYSIS
#
# STATUS: CONFIRMED 2026-10-12 (answers to [Q1]..[Q8]: 1 yes, 2 yes, 3 no,
# 4 yes, 5 yes, 6 no, 7 yes, 8 yes). Each dataset and column group says WHY
# it is in or out. Switch a group on/off with its `include` flag.
#
# Run after 04_Load_Data.R (needs `sas` and `data_index` in memory).
# Output: one stacked table per module (all years + seasons), plus a report
# of exactly which columns were picked from each file.
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr); library(purrr); library(stringr); library(tibble); library(readr)
})
if (!exists("sas") || !exists("data_index")) source(file.path("SCRIPTS", "04_Load_Data.R"))

save_outputs <- TRUE    # writes DATA/processed/selection/


# ----------------------------------------------------------------------------
# A. DATASETS: what each one brings to irrigation + modern agriculture
# ----------------------------------------------------------------------------
# agri_prac   IN   Core. Irrigation (any plot / this plot, technique, water
#                  source, tool, cost), mechanisation (oxen, tractor, other
#                  machines + costs), hired labour, erosion and land
#                  consolidation. All 21 seasons.
# crop_prod   IN   Outcome side. Crop, area, harvest (kg) -> yield (kg/ha),
#                  seed type (improved vs traditional), sales and price
#                  -> gross sales value. All 21 seasons.
# fert_pest   IN   Input intensity. Organic / inorganic fertiliser,
#                  micronutrients, pesticides, quantities and costs. Modern
#                  inputs usually go together with irrigation. All 21 seasons.
# crop_screen IN   Land use and cropped area per plot (cropland, cropping
#                  system, crop area), the base for "candidate cropland".
#                  2024-25 also hold anti-erosion + agroforestry. All seasons.
# erosion     IN   [Q1] 2020-2023 only. Anti-erosion works and land
#                  consolidation sites: soil conservation, a feasibility
#                  factor (terraced / consolidated land is easier to irrigate).
# agrofor     IN   [Q2] 2020-2023 only. Agroforestry trees on plot: part of a
#                  "climate-smart practices" picture next to irrigation.
# land_ten    OUT  [Q3] 2019 only (owned / rented / payment). Tenure security
#                  matters for irrigation investment, but one year cannot
#                  support trends or the 2020-25 dashboard.
# chirps      IN   Rainfall 1981-2025 -> seasonal totals, anomalies, deficit
#                  months = irrigation NEED.
# districts   IN   GADM boundaries for the 30-district maps.
#
# SOIL TYPE: no SAS file has a soil variable. Closest proxies are
# "degree of erosion" and anti-erosion activity. Real soil data must come
# from outside (e.g. iSDAsoil / SoilGrids) [Q4: yes]. See section C2: put a
# district-level soil CSV in DATA/SOIL/ and it is joined automatically.

datasets_in <- c("agri_prac", "crop_prod", "fert_pest", "crop_screen",
                 "erosion", "agrofor")   # [Q1] yes, [Q2] yes; land_ten out [Q3]


# ----------------------------------------------------------------------------
# B. COLUMNS. Names were made readable per year, so groups use regex patterns
# on those names. Every group lists its patterns and its reason.
# ----------------------------------------------------------------------------

# Always kept: survey keys, geography, design weights (needed for weighted
# national / district estimates and for joining modules on the same plot).
key_cols <- paste0("^(", paste(c(
  "sas_year", "sas_season", "sas_module",
  "segment_id", "segment_number", "plot_number", "farmer_id", "stratum",
  "province", "district", "district_name_code",
  "names_and_codes_of_the_(province|district|stratum).*",
  "plot_weight", "plot_weight_plot_weight", "final_weight", "weight_plot",
  "segment_weight", "aweight", "farmer_type"
), collapse = "|"), ")$")

col_groups <- list(

  irrigation = list(include = TRUE, modules = c("agri_prac", "crop_prod"),
    why = "The outcome of the project: who irrigates, how, from which water source, with which tool, at what cost.",
    pattern = "irrigat"),

  mechanisation = list(include = TRUE, modules = "agri_prac",
    why = "Modern agriculture: oxen, tractors, other machines and what was paid. Mechanised farms adopt irrigation more.",
    pattern = "plough|tractor|mechanical_equipment|hired_labor|manpower"),

  soil_conservation = list(include = TRUE,
    modules = c("agri_prac", "crop_prod", "crop_screen", "erosion"),
    why = "Soil proxy (no soil type in SAS). Erosion degree, anti-erosion works, land consolidation affect irrigation feasibility.",
    pattern = "erosion|land_consolidat"),

  plot_area = list(include = TRUE, modules = datasets_in,
    why = "Denominator for yield (kg/ha) and irrigated area shares.",
    pattern = "^plot_area|ptot_area|^crop_area|harvested_crop_area|developped_crop_area|ii_harvested_crop_area"),

  crop = list(include = TRUE, modules = c("crop_prod", "crop_screen", "fert_pest"),
    why = "Crop-specific yields; which crops are irrigated or fertilised.",
    pattern = "^crop_name$|^crop_category$|^cropgroup$|cropping_system|main_crops_to_be_fertilized|plot_land_use"),

  production_yield = list(include = TRUE, modules = "crop_prod",
    why = "Productivity: harvested / produced kg and reported yield -> kg/ha for irrigated vs non-irrigated plots.",
    pattern = "harvested_quantity|quantity_produced|already_harvested|remaining_quantity|unit_of_measurement|yield|compare_the_production|how_do_you_compare"),

  sales_value = list(include = TRUE, modules = "crop_prod",
    why = "Economics: quantity sold x price = gross sales value (not net income).",
    pattern = "selling_price|quantity_sold|sold_to_be_sold|on_which_market|market_price|what_is_the_quantity_that"),  # 2025A-B names added 13 Oct

  seeds = list(include = TRUE, modules = "crop_prod",
    why = "Improved seed is a modern input that is usually combined with irrigation and fertiliser.",
    pattern = "improved_seed|type_of_seeds|traditional_seeds|quantity_sown|sowing_date"),

  fertiliser_pesticide = list(include = TRUE, modules = c("fert_pest", "crop_prod"),
    why = "Input intensity: organic / inorganic fertiliser, micronutrients, pesticides, quantities, costs, sufficiency.",
    pattern = "fertili|micro_nutrient|pesticid|pesticde|fungicide|unit_price|measurement_unit|total_quantity_used|quantity_purchased|total_amount_spent"),

  demographics = list(include = TRUE, modules = c("agri_prac", "crop_prod", "fert_pest"),
    why = "[Q5] Gender and age of farmer: equity of irrigation access (who is left behind).",
    pattern = "^gender$|^age_years$"),

  post_harvest_losses = list(include = FALSE, modules = "crop_prod",
    why = "[Q6] Losses (pests, storage, transport). Indirect link; many columns, 2020+ only.",
    pattern = "lost|damaged|stolen|stollen|stalks"),

  storage_use = list(include = TRUE, modules = "crop_prod",
    why = "[Q7] Storage, own consumption, gifts, seeds kept: how much of the harvest reaches the market.",
    pattern = "storage|stored|own_consumption|auto_consum|hh_consumption|gift|wage|farm_rent|fodder|feed_animals|exchanged|transformed|processed"),

  agroforestry = list(include = TRUE, modules = c("crop_screen", "agrofor"),
    why = "[Q2] Agroforestry trees on plot: climate-smart practice, weak irrigation link.",
    pattern = "agroforestry")
)

# Columns never kept: *_code duplicates (the factor already has the label),
# free-text "other / specify" answers, interviewer bookkeeping.
drop_pattern <- "(?<!district_name)_code(_\\d+)?$|_specify|^other_|relationship_of_respondent|date_of_interview|which_grids|grids_fallling|number_of_grid"
# [Q8] district_name_code_code (numeric district code) is kept for joins.


# ----------------------------------------------------------------------------
# C. APPLY THE SELECTION
# ----------------------------------------------------------------------------

active <- keep(col_groups, \(g) g$include)

pick_columns <- function(d, abbrev) {
  pats <- active |> keep(\(g) abbrev %in% g$modules) |> map_chr("pattern")
  nm <- names(d)
  keep_nm <- str_detect(nm, key_cols) |
    (if (length(pats)) str_detect(nm, paste(pats, collapse = "|")) else FALSE)
  keep_nm <- keep_nm & !str_detect(nm, regex(drop_pattern)) |
    nm %in% c("district_name_code_code", "district_code")
  d[, keep_nm, drop = FALSE]
}

# One harmonised district / weight / plot-area column across years
harmonise <- function(d) {
  chr <- \(col) if (col %in% names(d)) as.character(d[[col]]) else NA_character_
  num <- \(col) if (col %in% names(d)) as.numeric(d[[col]]) else NA_real_
  d |>
    mutate(
      district_std = coalesce(chr("district"), chr("district_name_code"),
                              chr("names_and_codes_of_the_district_the_segment_lsf_is_loca")),
      weight_std   = coalesce(num("plot_weight"), num("plot_weight_plot_weight"),
                              num("weight_plot"), num("final_weight"),
                              num("segment_weight")),
      plot_area_ha_std = coalesce(num("plot_area_ha"), num("plot_area_m2") / 1e4,
                                  num("ptot_area_in_sqm") / 1e4),
      .after = sas_module
    )
}

selection_report <- list()
selected <- list()

for (m in intersect(datasets_in, unique(data_index$abbrev))) {
  objs <- data_index$object[data_index$abbrev == m]
  parts <- map(set_names(objs), \(o) harmonise(pick_columns(sas[[o]], m)))

  selection_report[[m]] <- imap(parts, \(d, o) tibble(
    module = m, object = o, column = names(d),
    label = map_chr(d, \(x) attr(x, "label", exact = TRUE) %||% NA_character_)
  )) |> bind_rows()

  # Columns that change type between years -> character, then stack
  mixed <- parts |>
    map(\(d) map_chr(d, \(x) class(x)[1])) |>
    map(\(x) enframe(x, "col", "type")) |> bind_rows() |> distinct() |>
    count(col) |> filter(n > 1) |> pull(col)
  selected[[m]] <- parts |>
    map(\(d) mutate(d, across(any_of(mixed), as.character))) |>
    bind_rows()
}

selection_report <- bind_rows(selection_report)

# Rainfall + map (already analysis-ready)
if (exists("chirps"))       selected$rainfall  <- chirps
if (exists("districts_sf")) selected$districts <- districts_sf

# C2. SOIL [Q4] ---------------------------------------------------------------
# No soil variable exists in SAS. When you download district soil summaries
# (e.g. iSDAsoil / SoilGrids: texture, pH, organic carbon, depth), save them as
# DATA/SOIL/*.csv with a `district` column; they are loaded as irr_soil and can
# be joined on district_std.
soil_files <- list.files(file.path("DATA", "SOIL"), pattern = "\\.csv$", full.names = TRUE)
if (length(soil_files)) {
  selected$soil <- map(soil_files, \(f) read_csv(f, show_col_types = FALSE)) |>
    reduce(full_join, by = "district")
} else {
  message("No soil data yet (DATA/SOIL/*.csv): add it at the geospatial stage.")
}

list2env(set_names(selected, paste0("irr_", names(selected))), globalenv())


# ----------------------------------------------------------------------------
# D. REVIEW
# ----------------------------------------------------------------------------

cat("\nSelected tables:\n")
walk(names(selected), \(n) cat(sprintf("  irr_%-12s %8d rows  %4d cols\n", n,
                                        nrow(selected[[n]]), ncol(selected[[n]]))))
cat("\nColumns kept per module (unique names):\n")
print(count(distinct(selection_report, module, column), module))

# Inspect the choice before confirming:
# View(selection_report)
# selection_report |> filter(module == "agri_prac") |> distinct(column, label)

if (save_outputs) {
  out <- file.path("DATA", "processed", "selection")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  iwalk(selected, \(d, n) saveRDS(d, file.path(out, paste0("irr_", n, ".rds"))))
  write_csv(selection_report, file.path(out, "column_selection_report.csv"))
}
