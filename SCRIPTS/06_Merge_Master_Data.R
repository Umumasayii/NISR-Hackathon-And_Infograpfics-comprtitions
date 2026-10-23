# ============================================================================
# 06_Merge_Master_Data.R
# SmartIrrigate Rwanda - NISR 2026 Hackathon
#
# PURPOSE
#   Merge the irr_* tables from 05_Select_Irrigation_Data.R into ONE set of
#   harmonised "master" tables that share common features (same column names,
#   same codes, same units for every year and season 2019A-2025C), so you can
#   see overall production and measures and then simply filter.
#
# INPUT  : DATA/processed/selection/irr_*.rds   (written by 05_...R)
# OUTPUT : DATA/processed/master/
#   master_crop_plot.rds         1 row = crop x plot x season (the analysis table)
#   master_plot.rds              1 row = plot x season (irrigation rates, inputs)
#   master_national_season.*     overall measures, 21 seasons
#   master_district_season.*     30 districts x 21 seasons + rainfall
#   master_crop_season.*         crop x season (national production, yields)
#   master_crop_district_season.* crop x district x season
#   master_rain_district_season.* CHIRPS 1981-2025 by district and SAS season
#   master_dictionary.csv        every master column: meaning, unit, source
#   master_coverage.csv          % non-missing per column per season
#   master_join_log.csv          which keys joined which module, match rates
#
# RUN    : from the Hackathon project root, after 05_Select_Irrigation_Data.R
#          source("SCRIPTS/06_Merge_Master_Data.R")
#
# DATA TRAPS THIS SCRIPT FIXES (found while profiling the irr_* tables)
#   1. Skip patterns. From 2020, "Was this plot irrigated?" is mostly asked only
#      when the farmer said yes to "irrigated ANY plot this season". Blanks are
#      set to "No" ONLY in seasons where the data confirm the skip (see
#      skip_pattern_audit.csv); otherwise they stay missing. Same check for
#      fertiliser, pesticide, micronutrients, machines and anti-erosion.
#   2. Wrong value labels. In 2022A-C and 2025A-B the irrigation TOOL codes
#      carry the WATER SOURCE labels (e.g. tool = "Lake/stream water").
#      Codes are re-labelled by position (code 1 = Irrigation machine ...).
#   3. Multi-answer codes. In 2021 and 2025A-B, water source / tool are stored
#      as digit strings ("13" = answers 1 and 3). They are decoded.
#   4. 2019 crop production has no weight; 2021C has half. Weights are taken
#      from the same plot in agricultural practices.
#   5. District spelling "Nyarugenege" is fixed to "Nyarugenge".
#   6. Crop area has 7 different names across years; 2024 has none in crop
#      production, so it is taken from crop screening (same plot and crop).
#
# Packages: dplyr, tidyr, purrr, stringr, readr (all tidyverse). No others.
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(purrr); library(stringr); library(readr)
})

# ---- 0. SETTINGS -----------------------------------------------------------
dir_root   <- Sys.getenv("HACKATHON_ROOT", ".")          # project root
dir_sel    <- file.path(dir_root, "DATA", "processed", "selection")
dir_master <- file.path(dir_root, "DATA", "processed", "master")
write_csv_copies <- TRUE    # small aggregate tables also as .csv (for Excel/Python)
yield_trim_pct   <- c(0.01, 0.99)  # per crop x season, yields outside these quantiles are flagged
rain_baseline    <- 1991:2020

# SAS season calendar (confirmed by the team, 13 Oct 2026)
#   A = Sep-Feb (long rains, main season), B = Mar-Jun, C = Jul-Sep (dry season,
#   marshlands / irrigated). September is counted in both A (next year) and C.
season_months <- list(A = c(9:12, 1:2), B = 3:6, C = 7:9)

dir.create(dir_master, showWarnings = FALSE, recursive = TRUE)
rd <- function(x) readRDS(file.path(dir_sel, paste0("irr_", x, ".rds")))

# ---- 1. HELPERS ------------------------------------------------------------
# first non-missing value across candidate columns (only those that exist)
take <- function(df, cands, as = c("num", "chr")) {
  as <- match.arg(as)
  cands <- intersect(cands, names(df))
  if (!length(cands)) return(if (as == "num") rep(NA_real_, nrow(df)) else rep(NA_character_, nrow(df)))
  vals <- map(cands, \(v) if (as == "num") suppressWarnings(as.numeric(df[[v]])) else
    na_if(str_squish(as.character(df[[v]])), ""))
  reduce(vals, coalesce)
}
yes   <- function(x) case_when(str_detect(str_to_lower(x), "^yes") ~ 1L,
                               str_detect(str_to_lower(x), "^no")  ~ 0L,
                               TRUE ~ NA_integer_)
wmean <- function(x, w) { ok <- !is.na(x) & !is.na(w); if (!any(ok)) NA_real_ else sum(x[ok] * w[ok]) / sum(w[ok]) }
wsum  <- function(x, w) { ok <- !is.na(x) & !is.na(w); if (!any(ok)) NA_real_ else sum(x[ok] * w[ok]) }
fix_district <- function(x) recode(x, "Nyarugenege" = "Nyarugenge")
# Skip patterns, checked season by season (not a blanket "missing = No" rule).
# A plot question left blank is set to "No" ONLY in seasons where the data
# prove the skip: the farmer-level gate question exists for (almost) every row,
# and plots whose gate is "No" were (almost) never asked the plot question.
# Every decision is written to skip_pattern_audit.csv.
skip_audit <- list()
gate_fill <- function(plot, gate, ys, var) {
  aud <- tibble(plot, gate, ys) |>
    group_by(ys) |>
    summarise(rows = n(), gate_present_pct = round(100 * mean(!is.na(gate)), 1),
              gate_no = sum(gate == 0L, na.rm = TRUE),
              answered_when_gate_no = sum(gate == 0L & !is.na(plot), na.rm = TRUE),
              gate_yes = sum(gate == 1L, na.rm = TRUE),
              blank_when_gate_yes = sum(gate == 1L & is.na(plot), na.rm = TRUE),
              plot_blank = sum(is.na(plot)), .groups = "drop") |>
    mutate(variable = var, .before = 1,
           skip_confirmed = gate_present_pct >= 95 & gate_no > 0 &
             answered_when_gate_no / pmax(gate_no, 1) < 0.02,
           blanks_set_to_no = if_else(skip_confirmed, gate_no - answered_when_gate_no, 0L))
  skip_audit[[var]] <<- aud
  ok <- ys %in% aud$ys[aud$skip_confirmed]
  case_when(plot == 1L ~ 1L, plot == 0L ~ 0L, ok & gate == 0L ~ 0L, TRUE ~ NA_integer_)
}
any_yes <- function(x) if (all(is.na(x))) NA_integer_ else as.integer(any(x == 1L, na.rm = TRUE))

# Harmonised categories --------------------------------------------------------
src_labels  <- c("1" = "Rainwater harvesting", "2" = "Water treatment plant",
                 "3" = "Underground water", "4" = "Lake / stream", "5" = "Dam / water catchment",
                 "6" = "Other")
tool_labels <- c("1" = "Irrigation machine", "2" = "Motor pump", "3" = "Tube well",
                 "4" = "Watering can", "5" = "Water channels", "6" = "Jerrycan / basin",
                 "7" = "Other")

std_source <- function(x) {
  x <- str_to_lower(x)
  case_when(
    is.na(x) | x %in% c(".", "") ~ NA_character_,
    str_detect(x, "^[0-9]+$") ~ unname(src_labels[str_sub(x, 1, 1)]),   # first answer
    str_detect(x, "rain")      ~ "Rainwater harvesting",
    str_detect(x, "treatment") ~ "Water treatment plant",
    str_detect(x, "underground") ~ "Underground water",
    str_detect(x, "lake|stream") ~ "Lake / stream",
    str_detect(x, "dam|catchment") ~ "Dam / water catchment",
    TRUE ~ "Other")
}
# trap 2: in these seasons the tool codes wear the water-source labels
tool_mislabelled <- c("2022A", "2022B", "2022C", "2025A", "2025B")
src_to_tool <- c("rain" = "Irrigation machine", "treatment" = "Motor pump",
                 "underground" = "Tube well", "lake|stream" = "Watering can",
                 "dam|catchment" = "Water channels", "other source" = "Jerrycan / basin")
std_tool <- function(x, ys) {
  lx <- str_to_lower(x)
  out <- case_when(
    is.na(lx) | lx %in% c(".", "") ~ NA_character_,
    str_detect(lx, "^[0-9]+$") ~ unname(tool_labels[str_sub(lx, 1, 1)]),
    str_detect(lx, "pivot") ~ "Pivot",
    str_detect(lx, "irrigation machine") ~ "Irrigation machine",
    str_detect(lx, "generator|moto|^pump|pumps") ~ "Motor pump",
    str_detect(lx, "tube") ~ "Tube well",
    str_detect(lx, "water can") ~ "Watering can",
    str_detect(lx, "channel") ~ "Water channels",
    str_detect(lx, "jer[r]?ycan|basin") ~ "Jerrycan / basin",
    TRUE ~ "Other")
  bad <- ys %in% tool_mislabelled & !is.na(lx) & !str_detect(lx, "^[0-9]+$")
  if (any(bad)) {
    fixed <- rep(NA_character_, sum(bad))
    for (p in names(src_to_tool)) fixed[is.na(fixed) & str_detect(lx[bad], p)] <- src_to_tool[[p]]
    fixed[is.na(fixed) & lx[bad] == "7"] <- "Other"
    out[bad] <- coalesce(fixed, "Other")
  }
  out
}
tool_level <- function(t) case_when(   # technology ladder used on the dashboard
  t %in% c("Jerrycan / basin", "Watering can") ~ "1 Manual (can / jerrycan)",
  t %in% c("Water channels")                   ~ "2 Gravity channels",
  t %in% c("Tube well", "Motor pump")          ~ "3 Motorised pumping",
  t %in% c("Irrigation machine", "Pivot")      ~ "4 Irrigation machine / pivot",
  is.na(t) ~ NA_character_, TRUE ~ "Other")
std_technique <- function(x) {
  x <- str_to_lower(x)
  case_when(is.na(x) ~ NA_character_,
            str_detect(x, "drip") ~ "Drip",
            str_detect(x, "sprinkler") ~ "Sprinkler",
            str_detect(x, "pivot") ~ "Pivot",
            str_detect(x, "flood") ~ "Flood (rice)",
            str_detect(x, "surface") ~ "Surface",
            str_detect(x, "traditional") ~ "Traditional",
            TRUE ~ "Other")
}
std_erosion <- function(x) {
  x <- str_to_lower(x)
  case_when(is.na(x) ~ NA_character_,
            str_detect(x, "severe") ~ "3 Severe",
            str_detect(x, "moderate") ~ "2 Moderate",
            str_detect(x, "low|weak|splash|wind") ~ "1 Low",
            TRUE ~ NA_character_)
}
crop_group <- function(crop) {
  c <- str_to_lower(crop)
  case_when(
    is.na(c) ~ NA_character_,
    str_detect(c, "fodder|napi|tripsacum|desmodium|setaria|mucuna|leucena") ~ "Fodder",
    str_detect(c, "maize|rice|sorghum|wheat|millet|cereal") ~ "Cereals",
    str_detect(c, "bean|pea$|^pea|soybean|groundnut|pulse") ~ "Legumes & pulses",
    str_detect(c, "banana") ~ "Bananas",
    str_detect(c, "cassava|potato|taro|yam|tuber") ~ "Roots & tubers",
    str_detect(c, "coffee|tea|pyrethrum|sugar|tobacco|sun ?flower|macadamia|palm|chia|stevia|patchouli|geranium|rosemary|lemongrass|artemesia|jatropha|vetiver|mint|levendine|mulberry") ~ "Cash & industrial",
    str_detect(c, "avocado|mango|pineapple|passion|papaya|orange|lemon|guava|apple|tree tomato|fruit|strawberry|goose|mandol|mandal|olive|melon") ~ "Fruits",
    TRUE ~ "Vegetables")
}

# ---- 2. LOAD -----------------------------------------------------------------
message("Loading irr_* tables from ", dir_sel)
ap <- rd("agri_prac");  cp <- rd("crop_prod");  fp <- rd("fert_pest")
cs <- rd("crop_screen"); er <- if (file.exists(file.path(dir_sel, "irr_erosion.rds"))) rd("erosion") else NULL
af <- if (file.exists(file.path(dir_sel, "irr_agrofor.rds"))) rd("agrofor") else NULL
rain <- rd("rainfall")

add_ys <- function(d) d |> mutate(ys = paste0(sas_year, sas_season),
                                   district_std = fix_district(as.character(district_std)))
ap <- add_ys(ap); cp <- add_ys(cp); fp <- add_ys(fp); cs <- add_ys(cs)
if (!is.null(er)) er <- add_ys(er)
if (!is.null(af)) af <- add_ys(af)

# ---- 3. PLOT KEYS ------------------------------------------------------------
# Not every season has every ID (2022C has no segment_id, 2024C no plot_number,
# 2025 no segment_number). For each season we use the first key set that
# exists in BOTH tables and is unique on the plot side.
key_sets <- list(c("segment_id", "plot_number"),
                 c("district_std", "stratum", "segment_number", "plot_number"),   # 2022C
                 c("district_std", "segment_number", "plot_number"),
                 c("segment_id", "farmer_id"),
                 c("district_std", "segment_number", "farmer_id"))
max_dup_share <- 0.25   # a key with more duplicate rows than this is not used (no join = unknown)
join_log <- list()

choose_key <- function(left, right, season, what) {
  for (k in key_sets) {
    if (!all(k %in% names(left)) || !all(k %in% names(right))) next
    if (mean(complete.cases(left[k])) < 0.95 || mean(complete.cases(right[k])) < 0.95) next
    dup <- mean(duplicated(right[k]))
    if (dup > max_dup_share) next
    m <- mean(do.call(paste, left[k]) %in% do.call(paste, right[k]))
    if (m < 0.5) next
    join_log[[length(join_log) + 1]] <<- tibble(join = what, season = season,
                                                key = paste(k, collapse = "+"), match_rate = round(m, 3),
                                                dup_rows_pct = round(100 * dup, 1))
    return(k)
  }
  join_log[[length(join_log) + 1]] <<- tibble(join = what, season = season, key = "none", match_rate = 0,
                                              dup_rows_pct = NA_real_)
  NULL
}
# Duplicate rows on the join key are COMBINED, not dropped. For each field:
#   all non-missing values agree -> that value;
#   0/1 flags that disagree      -> 1 if any row says yes (any_yes);
#   other values that disagree   -> missing (unknown), and counted as a conflict.
# The number of keys and fields in conflict goes to the join log.
collapse_dups <- function(r, k) {
  r <- group_by(r, across(all_of(c(k, "ys"))))
  if (!any(duplicated(select(ungroup(r), all_of(c(k, "ys")))))) return(list(d = ungroup(r), keys = 0L, conflicts = 0L))
  r <- mutate(r, .n_dup = n())
  single <- filter(r, .n_dup == 1) |> ungroup() |> select(-.n_dup)
  multi  <- filter(r, .n_dup > 1) |> select(-.n_dup)
  vars <- setdiff(names(multi), c(k, "ys"))
  agree <- function(x) { u <- unique(x[!is.na(x)]); length(u) <= 1 }
  conflicts <- multi |> summarise(across(all_of(vars), \(x) !agree(x)), .groups = "drop")
  n_conf <- sum(as.matrix(conflicts[vars]))
  merged <- multi |> summarise(across(all_of(vars), \(x) {
      u <- unique(x[!is.na(x)])
      if (length(u) == 0) x[1] else if (length(u) == 1) u[1] else
        if (is.integer(x) && all(u %in% 0:1)) 1L else x[NA_integer_][1]
    }), .groups = "drop")
  list(d = bind_rows(single, merged), keys = nrow(merged), conflicts = as.integer(n_conf))
}
season_join <- function(left, right, what) {
  map_dfr(unique(left$ys), \(s) {
    l <- filter(left, ys == s); r <- filter(right, ys == s) |> select(-any_of(c("sas_year", "sas_season")))
    if (!nrow(r)) return(l)
    k <- choose_key(l, r, s, what)
    if (is.null(k)) return(l)          # no usable key: the added fields stay missing (unknown), never "No"
    r <- select(r, all_of(k), ys, setdiff(names(r), c(names(l), "ys")))
    cd <- collapse_dups(r, k)
    i <- length(join_log)
    join_log[[i]] <<- mutate(join_log[[i]], dup_keys_combined = cd$keys, field_conflicts = cd$conflicts)
    out <- left_join(l, cd$d, by = c(k, "ys"))
    # expected cardinality: many-to-one. A join must never add rows.
    if (nrow(out) != nrow(l)) stop("Join '", what, "' in ", s, " added rows (", nrow(l), " -> ", nrow(out), ")")
    out
  })
}

# ---- 4. PLOT-LEVEL PRACTICES (agricultural practices) -------------------------
message("Building plot-level practices")
ap_std <- ap |>
  transmute(
    sas_year, sas_season, ys, province = as.character(province), district_std, stratum,
    segment_id, segment_number = if ("segment_number" %in% names(ap)) segment_number else NA_real_,
    plot_number, farmer_id = if ("farmer_id" %in% names(ap)) farmer_id else NA_real_,
    weight = weight_std, plot_area_ha = plot_area_ha_std,
    farmer_type = take(ap, "farmer_type", "chr"),
    gender = take(ap, "gender", "chr"), age_years = take(ap, "age_years"),
    # irrigation (trap 1: skip pattern)
    irrig_any_farmer = yes(take(ap, "irrigation_any_plot_this_season", "chr")),
    irrig_plot_raw   = yes(take(ap, "plot_irrigated_this_season", "chr")),
    irrigated = gate_fill(irrig_plot_raw, irrig_any_farmer, ys, "irrigated"),
    irrig_technique = std_technique(take(ap, "irrigation_technique", "chr")),
    irrig_source    = std_source(take(ap, "irrigation_water_source", "chr")),
    irrig_tool      = std_tool(take(ap, "irrigation_tool", "chr"), ys),
    irrig_tool_level = tool_level(irrig_tool),
    irrig_modern = case_when(is.na(irrig_tool) ~ NA_integer_,
                             str_detect(irrig_tool_level, "^[34]") |
                               irrig_technique %in% c("Drip", "Sprinkler", "Pivot") ~ 1L, TRUE ~ 0L),
    irrig_cost_rwf = take(ap, "irrigation_cost_rwf"),
    # mechanisation (2019: asked to all; 2020+: only if "used any machine on this plot" = yes)
    mech_gate = coalesce(yes(take(ap, "use_any_mechanical_equipment_for_agriculture_activities_on_this", "chr")),
                         if_else(yes(take(ap, "use_any_mechanical_equipment_for_agriculture_activities_in_any", "chr")) == 0L, 0L, NA_integer_)),
    oxen    = gate_fill(yes(take(ap, c("used_ploughing_animals_oxen_in_this_plot_during_this_season",
                                       "used_ploughing_animals_oxen_during_this_season"), "chr")), mech_gate, ys, "oxen"),
    tractor = gate_fill(yes(take(ap, c("used_a_ploughing_tractor_in_this_plot_during_this_season",
                                       "used_a_ploughing_tractor_during_this_season"), "chr")), mech_gate, ys, "tractor"),
    other_machine = gate_fill(yes(take(ap, c("used_any_other_mechanical_equipment_not_mentioned_in_this_plot_d",
                                             "used_any_other_mechanical_equipment_during_this_season"), "chr")), mech_gate, ys, "other_machine"),
    mechanised = coalesce(mech_gate, pmax(oxen, tractor, other_machine, na.rm = TRUE)),
    tractor_cost_rwf = take(ap, c("amount_paid_on_ploughing_tractor_rwf_in_this_season",
                                  "amount_paid_on_rent_of_ploughing_tractor_rwf")),
    hired_labour_rwf = take(ap, c("amount_spent_on_hired_labor_used_to_prepare_land_sowing_and_any",
                                  "amount_spent_on_manpower_to_prepare_land_sowing_and_any_other")),
    # land and soil
    erosion_degree = std_erosion(take(ap, "degree_of_erosion_on_this_plot", "chr")),
    anti_erosion   = gate_fill(yes(take(ap, "anti_erosion_activity_on_this_plot", "chr")),
                               yes(take(ap, "anti_erosion_activity_in_any_of_your_plots", "chr")), ys, "anti_erosion"),
    land_consolidated = yes(take(ap, "is_this_plot_located_in_land_consolidated_site_in_this_season", "chr"))
  ) |>
  select(-irrig_plot_raw, -mech_gate)

# trap 3: multi-answer flags for water source (any mention, all columns)
src_cols <- grep("^irrigation_water_source", names(ap), value = TRUE)
for (code in names(src_labels)[1:5]) {
  nm <- paste0("src_", str_replace_all(str_to_lower(src_labels[[code]]), "[^a-z]+", "_"))
  hit <- map(src_cols, \(v) { x <- str_to_lower(as.character(ap[[v]]))
    pat <- c("1" = "rain", "2" = "treatment", "3" = "underground", "4" = "lake|stream", "5" = "dam|catchment")[[code]]
    coalesce(str_detect(x, pat) | (str_detect(x, "^[0-9]+$") & str_detect(x, code)), FALSE) }) |> reduce(`|`)
  ap_std[[nm]] <- if_else(ap_std$irrigated == 1L, as.integer(hit), NA_integer_)
}

# fertiliser & pesticide flags (plot level; fert_pest can have >1 row per plot)
message("Building plot-level inputs")
fp_std <- fp |>
  transmute(ys, district_std, stratum, segment_id, plot_number,
            segment_number = if ("segment_number" %in% names(fp)) segment_number else NA_real_,
            farmer_id = if ("farmer_id" %in% names(fp)) farmer_id else NA_real_,
            # each plot question is gated by "...in ANY of your plots" from 2020 (skip pattern)
            organic_fert   = gate_fill(yes(take(fp, "used_organic_fertilizer_in_this_plot_during_this_season", "chr")),
                                       yes(take(fp, "use_organic_fertilizer_in_any_of_your_plots_during_this_season", "chr")), ys, "organic_fert"),
            inorganic_fert = gate_fill(yes(take(fp, "used_inorganic_fertilizer_in_this_plot_during_this_season", "chr")),
                                       yes(take(fp, "use_inorganic_fertilizer_in_any_of_your_plots_during_this_season", "chr")), ys, "inorganic_fert"),
            pesticide      = gate_fill(yes(take(fp, c("used_pesticide_fungicide_in_this_plot_during_this_current_season",
                                                      "used_pesticides_in_this_plot_during_this_season"), "chr")),
                                       yes(take(fp, "use_pesticide_fungicide_in_any_of_your_plots_during_this_season", "chr")), ys, "pesticide"),
            micronutrient  = gate_fill(yes(take(fp, "use_any_type_of_micro_nutrients_in_this_plot_during_this_season", "chr")),
                                       yes(take(fp, "use_any_type_of_micro_nutrients_in_any_of_your_plots_in_this", "chr")), ys, "micronutrient")) |>
  # the farmer-level "in ANY of your plots" answers. They cover ALL the farmer's plots,
  # also plots outside the sampled segment, so "% of farmers who used X" must come from
  # them, not from the listed plots (2025A: 2,940 farmers said yes to chemical fertiliser
  # on some plot but on none of their listed plots; plot-derived farmer share 37% vs 62%)
  mutate(inorganic_fert_any = yes(take(fp, "use_inorganic_fertilizer_in_any_of_your_plots_during_this_season", "chr")),
         organic_fert_any   = yes(take(fp, "use_organic_fertilizer_in_any_of_your_plots_during_this_season", "chr")),
         pesticide_any      = yes(take(fp, "use_pesticide_fungicide_in_any_of_your_plots_during_this_season", "chr"))) |>
  # the plot's own answer before the skip fill, kept for the reconciliation (15)
  mutate(inorganic_fert_raw = yes(take(fp, "used_inorganic_fertilizer_in_this_plot_during_this_season", "chr")),
         organic_fert_raw   = yes(take(fp, "used_organic_fertilizer_in_this_plot_during_this_season", "chr")),
         pesticide_raw      = yes(take(fp, c("used_pesticide_fungicide_in_this_plot_during_this_current_season",
                                             "used_pesticides_in_this_plot_during_this_season"), "chr"))) |>
  group_by(ys, district_std, stratum, segment_id, segment_number, plot_number, farmer_id) |>
  summarise(across(c(organic_fert, inorganic_fert, pesticide, micronutrient,
                     inorganic_fert_any, organic_fert_any, pesticide_any,
                     inorganic_fert_raw, organic_fert_raw, pesticide_raw), any_yes), .groups = "drop")

# agroforestry (2020-2023 module, 2024-2025 crop screening question)
agro_std <- bind_rows(
  if (!is.null(af)) af |> transmute(ys, district_std, stratum, segment_id, plot_number,
    segment_number = if ("segment_number" %in% names(af)) segment_number else NA_real_,
    agroforestry = yes(take(af, "agroforestry_practices_on_this_plot", "chr"))),
  cs |> transmute(ys, district_std, stratum, segment_id, plot_number,
    segment_number = if ("segment_number" %in% names(cs)) segment_number else NA_real_,
    agroforestry = yes(take(cs, "agroforestry_practice_on_this_plot", "chr")))) |>
  filter(!is.na(agroforestry)) |>
  group_by(ys, district_std, stratum, segment_id, segment_number, plot_number) |>
  summarise(agroforestry = any_yes(agroforestry), .groups = "drop")

# plot area fallback (agri_prac has no plot area in 2022A): crop screening, same plot
cs_plot <- cs |>
  transmute(ys, district_std, stratum, segment_id, plot_number,
            segment_number = if ("segment_number" %in% names(cs)) segment_number else NA_real_,
            plot_area_ha_cs = plot_area_ha_std) |>
  filter(!is.na(plot_area_ha_cs)) |>
  group_by(ys, district_std, stratum, segment_id, segment_number, plot_number) |>
  summarise(plot_area_ha_cs = first(plot_area_ha_cs), .groups = "drop")

master_plot <- ap_std |>
  season_join(fp_std, "agri_prac <- fert_pest") |>
  season_join(agro_std, "agri_prac <- agroforestry") |>
  season_join(cs_plot, "agri_prac <- crop_screen plot area") |>
  mutate(plot_area_ha = coalesce(plot_area_ha, plot_area_ha_cs)) |>
  select(-plot_area_ha_cs)

# One province per district, taken from the seasons where it is filled in.
# (2021B has province missing on 13% of rows and 2021C on all rows; grouping by
# a half-missing province split each district in two and doubled 2021B totals.)
district_province <- master_plot |> filter(!is.na(province), !is.na(district_std)) |>
  count(district_std, province) |>
  group_by(district_std) |> slice_max(n, n = 1, with_ties = FALSE) |> ungroup() |>
  select(district_std, province)
if (anyDuplicated(district_province$district_std)) stop("District -> province lookup is not unique")
master_plot <- master_plot |> select(-province) |>
  left_join(district_province, by = "district_std") |> relocate(province, .after = ys)

# ---- 5. CROP x PLOT TABLE (crop production) ----------------------------------
message("Building crop x plot table")
cp_std <- cp |>
  transmute(
    sas_year, sas_season, ys, district_std, stratum, segment_id,
    segment_number = if ("segment_number" %in% names(cp)) segment_number else NA_real_,
    plot_number, farmer_id = if ("farmer_id" %in% names(cp)) farmer_id else NA_real_,
    weight_cp = weight_std,
    crop_name = str_squish(as.character(crop_name)),
    crop_group = crop_group(crop_name),
    harvest_kg = take(cp, "harvested_quantity_kg_s2q21"),           # total harvest, all 21 seasons
    crop_area_ha_cp = take(cp, c("harvested_crop_area_ha", "crop_area_ha", "crop_area_in_ha",
                                 "ii_harvested_crop_area", "harvested_crop_area_in_ha",
                                 "crop_area", "developped_crop_area_in_ha")),
    sold_kg = take(cp, c("quantity_sold", "total_qty_of_harvest_that_has_been_sold_to_be_sold_kg",
                         "crop_quantity_sold_kg", "qty_of_production_that_has_been_sold_to_be_sold_kg",
                         "on_the_total_production_of_this_crop_what_is_the_quantity_that")),   # 2025A-B
    price_rwf_kg = na_if(take(cp, c("selling_price_per_kilogram_rwf_kg", "market_price")), 9999),
    own_consumption_kg = take(cp, c("quantity_used_for_own_consumption",
                                    "quantity_that_has_been_used_by_the_household_auto_consumption",
                                    "qty_of_production_used_as_hh_consumption")),
    stored_kg = take(cp, c("quantity_stored", "quantity_that_has_been_stored_to_be_stored_kg",
                           "qty_of_production_stored_to_be_stored_kg",
                           "qty_of_production_to_be_stored_for_future_uses")),
    seed_type = take(cp, c("type_of_seeds_sown_in_this_plot", "type_of_seeds_sown"), "chr"),
    improved_seed = case_when(str_detect(str_to_lower(seed_type), "improved|1&2") ~ 1L,
                              str_detect(str_to_lower(seed_type), "traditional") ~ 0L,
                              TRUE ~ yes(take(cp, "use_improved_seed_for_this_crop_in_any_of_your_plots_in_this", "chr"))),
    production_vs_last = take(cp, c("how_do_you_compare_the_production_of_this_crop_in_this_season",
                                    "how_can_you_compare_the_production_of_the_current_season_with",
                                    "compare_the_production_of_this_crop_with_its_production_in_the"), "chr"),
    gender_cp = take(cp, "gender", "chr"), age_cp = take(cp, "age_years")
  ) |>
  mutate(sold_kg = if_else(sold_kg < 0, NA_real_, sold_kg),
         own_consumption_kg = if_else(own_consumption_kg < 0, NA_real_, own_consumption_kg),
         # Price codes 999 / 9999 / 99999 mean "don't know" (999 alone is 68k rows),
         # and 0 means nothing was sold (2025A-B), so neither is a price.
         price_rwf_kg = if_else(price_rwf_kg <= 0 | price_rwf_kg %in% c(99, 999, 9999, 99999, 999999),
                                NA_real_, price_rwf_kg)) |>
  # drop extreme prices: above 10x the crop's median price that season
  group_by(ys, crop_name) |>
  mutate(price_rwf_kg = if_else(price_rwf_kg > 10 * median(price_rwf_kg, na.rm = TRUE), NA_real_, price_rwf_kg)) |>
  ungroup()

# crop area fallback from crop screening (same plot, same crop) - fills 2024
cs_area <- cs |>
  transmute(ys, segment_id, plot_number,
            crop_name = str_squish(as.character(crop_name)),
            crop_area_ha_cs = suppressWarnings(as.numeric(crop_area))) |>
  filter(!is.na(crop_name), !is.na(crop_area_ha_cs)) |>
  group_by(ys, segment_id, plot_number, crop_name) |>
  summarise(crop_area_ha_cs = sum(crop_area_ha_cs), .groups = "drop")

plot_vars <- c("province", "weight", "plot_area_ha", "farmer_type", "gender", "age_years",
               "irrig_any_farmer", "irrigated", "irrig_technique", "irrig_source", "irrig_tool",
               "irrig_tool_level", "irrig_modern", "irrig_cost_rwf", "oxen", "tractor", "other_machine",
               "mechanised", "erosion_degree", "anti_erosion", "land_consolidated",
               "organic_fert", "inorganic_fert", "pesticide", "micronutrient", "agroforestry")

master_crop_plot <- cp_std |>
  season_join(master_plot |> select(ys, district_std, stratum, segment_id, segment_number, plot_number, farmer_id,
                                    any_of(plot_vars)), "crop_prod <- plot practices") |>
  left_join(cs_area, by = c("ys", "segment_id", "plot_number", "crop_name")) |>
  # in some seasons (2021) the "crop area" in crop production is the whole plot
  # area repeated for every crop of a mixed plot; crop screening is then used
  group_by(ys) |>
  mutate(cp_area_is_plot = median(crop_area_ha_cp / plot_area_ha, na.rm = TRUE) > 0.98,
         crop_area_ha_cp = if_else(cp_area_is_plot & !is.na(crop_area_ha_cs), NA_real_, crop_area_ha_cp)) |>
  ungroup() |>
  add_count(ys, segment_id, plot_number, name = "n_crops_on_plot") |>
  mutate(
    weight = coalesce(weight_cp, weight),                       # trap 4
    gender = coalesce(gender_cp, gender), age_years = coalesce(age_cp, age_years),
    crop_area_single = if_else(n_crops_on_plot == 1L, plot_area_ha, NA_real_),   # pure stand
    crop_area_ha = coalesce(crop_area_ha_cp, crop_area_ha_cs, crop_area_single),
    crop_area_source = case_when(!is.na(crop_area_ha_cp) ~ "crop_production",
                                 !is.na(crop_area_ha_cs) ~ "crop_screening",
                                 !is.na(crop_area_single) ~ "plot area (single crop)", TRUE ~ NA_character_),
    # a crop cannot cover more than its plot: cap obvious unit / typing errors
    crop_area_capped = !is.na(crop_area_ha) & !is.na(plot_area_ha) & crop_area_ha > 1.05 * plot_area_ha,
    crop_area_ha = if_else(crop_area_capped, plot_area_ha, crop_area_ha),
    yield_kg_ha = if_else(crop_area_ha > 0, harvest_kg / crop_area_ha, NA_real_),
    # sold quantity is asked per crop (all plots) in some years: cap at this plot's harvest
    sold_share = if_else(harvest_kg > 0, pmin(sold_kg / harvest_kg, 1), NA_real_),
    sold_kg_plot = harvest_kg * sold_share,
    # complementary inputs (irrigation is NOT counted: it is what we compare).
    # Missing when any of the three is unknown, so unknown never counts as "not used".
    modern_inputs_n = if_else(is.na(improved_seed) | is.na(inorganic_fert) | is.na(mechanised), NA_integer_,
                              as.integer((improved_seed == 1L) + (inorganic_fert == 1L) + (mechanised == 1L))),
    age_band = cut(age_years, c(-Inf, 34, 54, Inf), labels = c("<35", "35-54", "55+"))
  ) |>
  # Sales value: reported price, else the median reported price for the same crop,
  # season and district, else for the crop and season. Half of the sellers give no
  # usable price, so without this the value of sales is badly undercounted.
  group_by(crop_name, ys, district_std) |>
  mutate(price_med_dist = median(price_rwf_kg, na.rm = TRUE)) |>
  group_by(crop_name, ys) |>
  mutate(price_med_nat = median(price_rwf_kg, na.rm = TRUE),
         price_used = coalesce(price_rwf_kg, price_med_dist, price_med_nat),
         price_imputed = is.na(price_rwf_kg) & !is.na(price_used),
         sales_value_rwf = sold_kg_plot * price_used) |>
  select(-price_med_dist, -price_med_nat) |>
  mutate(yield_ok = !is.na(yield_kg_ha) & harvest_kg > 0 &
           between(yield_kg_ha, quantile(yield_kg_ha, yield_trim_pct[1], na.rm = TRUE),
                                quantile(yield_kg_ha, yield_trim_pct[2], na.rm = TRUE))) |>
  ungroup() |>
  select(-weight_cp, -gender_cp, -age_cp, -crop_area_ha_cp, -crop_area_ha_cs, -cp_area_is_plot, -crop_area_single)

# farmer gender/age onto the plot table from crop production when practices lack it
ga <- master_crop_plot |> filter(!is.na(gender)) |>
  distinct(ys, segment_id, plot_number, .keep_all = TRUE) |>
  select(ys, segment_id, plot_number, gender_c = gender, age_c = age_years)
master_plot <- master_plot |>
  left_join(ga, by = c("ys", "segment_id", "plot_number")) |>
  mutate(gender = coalesce(gender, gender_c), age_years = coalesce(age_years, age_c)) |>
  select(-gender_c, -age_c)

# ---- 5b. FARMER TABLE (one row per farmer x season, 2020+) ---------------------
# The farmer question "did you irrigate ANY plot this season?" is repeated on every
# plot row, so a plot-weighted average counts farmers with many plots several times.
# Here each farmer counts once. The SAS file has no separate farmer weight, so the
# farmer weight is the average of the farmer's plot weights (documented choice).
master_farmer <- master_plot |>
  filter(!is.na(farmer_id)) |>
  group_by(sas_year, sas_season, ys, province, district_std, stratum, segment_id, segment_number, farmer_id) |>
  summarise(weight = mean(weight, na.rm = TRUE), n_plots = n(),
            irrig_gate = any_yes(irrig_any_farmer), irrig_plot_any = any_yes(irrigated),
            # inputs on ANY plot: NISR's "percentage of farmers who applied ..." (SAS tables)
            # the farmer's own "any of your plots" answer first; the listed plots only
            # when that question was not asked (2019)
            inorganic_fert_farmer = coalesce(any_yes(inorganic_fert_any), any_yes(inorganic_fert)),
            organic_fert_farmer   = coalesce(any_yes(organic_fert_any), any_yes(organic_fert)),
            pesticide_farmer      = coalesce(any_yes(pesticide_any), any_yes(pesticide)),
            gender = first(na.omit(gender)), farmer_type = first(na.omit(farmer_type)), .groups = "drop") |>
  mutate(weight = if_else(is.finite(weight), weight, NA_real_),
         irrig_farmer = case_when(irrig_gate == 1L | irrig_plot_any == 1L ~ 1L,
                                  irrig_gate == 0L ~ 0L, TRUE ~ NA_integer_)) |>
  select(-irrig_gate, -irrig_plot_any)

# ---- 6. RAINFALL BY DISTRICT AND SAS SEASON ----------------------------------
message("Building rainfall by district and season")
rain_m <- rain |> transmute(district = fix_district(district), year, month, rainfall_mm)
master_rain <- imap_dfr(season_months, \(m, s) rain_m |>
  filter(month %in% m) |>
  mutate(sas_season = s,
         sas_year = if (s == "A") if_else(month >= 9, year + 1L, as.integer(year)) else as.integer(year))) |>
  group_by(district_std = district, sas_year, sas_season) |>
  summarise(rain_mm = sum(rainfall_mm), n_months = n(), .groups = "drop") |>
  filter(n_months == lengths(season_months)[sas_season]) |>          # complete seasons only
  group_by(district_std, sas_season) |>
  mutate(rain_normal_mm = mean(rain_mm[sas_year %in% rain_baseline]),
         rain_sd_mm     = sd(rain_mm[sas_year %in% rain_baseline]),
         rain_anomaly_pct = 100 * (rain_mm - rain_normal_mm) / rain_normal_mm,
         rain_std_anomaly = (rain_mm - rain_normal_mm) / rain_sd_mm,     # SPI-like z-score
         dry_season_flag = as.integer(rain_std_anomaly < -1)) |>
  ungroup() |> select(-n_months)

# ---- 7. AGGREGATE MEASURES (survey-weighted) ---------------------------------
message("Aggregating measures")
plot_measures <- function(d) summarise(d,
  n_plots = n(),
  cultivated_area_ha   = wsum(plot_area_ha, weight),
  irrigated_plot_pct   = 100 * wmean(irrigated, weight),
  # area of plots REPORTING irrigation (whole plot area, not hectares actually watered)
  irrigated_area_ha    = wsum(plot_area_ha * irrigated, weight),
  irrigated_area_pct   = 100 * irrigated_area_ha / cultivated_area_ha,
  modern_irrig_pct     = 100 * wmean(irrig_modern[irrigated %in% 1L], weight[irrigated %in% 1L]),
  irrig_cost_rwf_ha    = wmean((irrig_cost_rwf / plot_area_ha)[irrigated %in% 1L & plot_area_ha > 0],
                               weight[irrigated %in% 1L & plot_area_ha > 0]),
  mechanised_pct = 100 * wmean(mechanised, weight),
  tractor_pct    = 100 * wmean(tractor, weight),
  oxen_pct       = 100 * wmean(oxen, weight),
  organic_fert_pct   = 100 * wmean(organic_fert, weight),
  inorganic_fert_pct = 100 * wmean(inorganic_fert, weight),
  pesticide_pct      = 100 * wmean(pesticide, weight),
  anti_erosion_pct   = 100 * wmean(anti_erosion, weight),
  severe_erosion_pct = 100 * wmean(as.integer(erosion_degree == "3 Severe"), weight),
  land_consolidated_pct = 100 * wmean(land_consolidated, weight),
  agroforestry_pct   = 100 * wmean(agroforestry, weight),
  female_plot_pct    = 100 * wmean(as.integer(gender == "Female"), weight),
  irrig_female_pct   = 100 * wmean(irrigated[gender %in% "Female"], weight[gender %in% "Female"]),
  irrig_male_pct     = 100 * wmean(irrigated[gender %in% "Male"], weight[gender %in% "Male"]),
  .groups = "drop")

farmer_measures <- function(d) summarise(d,
  n_farmers = n(),
  farmers_irrig_pct = 100 * wmean(irrig_farmer, weight),        # one record per farmer
  .groups = "drop")

# NB: inside summarise() a new column masks the old one, so yields come first.
# Yields use ONE eligibility mask everywhere: yield_ok (positive harvest, crop area,
# inside the 1st-99th percentile of its crop-season) AND a season whose crop areas are
# complete enough (season_yield_usable; 2024B and 2024C are not). The weighted sums
# behind every ratio are kept (yield_*_kg, yield_*_ha), so the app can combine
# districts, seasons and crops as sum(harvest) / sum(area) instead of averaging ratios.
crop_measures <- function(d) summarise(d,
  n_crop_plots   = n(),
  # coverage: share of harvested crop plots with a usable crop area (and so a yield)
  area_coverage_pct = 100 * mean(!is.na(crop_area_ha[harvest_kg > 0 & !is.na(harvest_kg)])),
  yield_harvest_kg     = { k <- yield_ok & season_yield_usable %in% TRUE; wsum(harvest_kg[k], weight[k]) },
  yield_area_ha        = { k <- yield_ok & season_yield_usable %in% TRUE; wsum(crop_area_ha[k], weight[k]) },
  yield_harvest_irr_kg = { k <- yield_ok & season_yield_usable %in% TRUE & irrigated %in% 1L; wsum(harvest_kg[k], weight[k]) },
  yield_area_irr_ha    = { k <- yield_ok & season_yield_usable %in% TRUE & irrigated %in% 1L; wsum(crop_area_ha[k], weight[k]) },
  yield_harvest_rf_kg  = { k <- yield_ok & season_yield_usable %in% TRUE & irrigated %in% 0L; wsum(harvest_kg[k], weight[k]) },
  yield_area_rf_ha     = { k <- yield_ok & season_yield_usable %in% TRUE & irrigated %in% 0L; wsum(crop_area_ha[k], weight[k]) },
  yield_kg_ha           = yield_harvest_kg / yield_area_ha,
  yield_irrigated_kg_ha = yield_harvest_irr_kg / yield_area_irr_ha,
  yield_rainfed_kg_ha   = yield_harvest_rf_kg / yield_area_rf_ha,
  n_yield               = sum(yield_ok & season_yield_usable %in% TRUE),
  n_irrigated_yield     = sum(yield_ok & season_yield_usable %in% TRUE & irrigated %in% 1L),
  n_rainfed_yield       = sum(yield_ok & season_yield_usable %in% TRUE & irrigated %in% 0L),
  yield_premium_pct     = 100 * (yield_irrigated_kg_ha / yield_rainfed_kg_ha - 1),
  production_t   = wsum(harvest_kg, weight) / 1000,
  crop_area_ha   = wsum(crop_area_ha, weight),
  sold_t         = wsum(sold_kg_plot, weight) / 1000,
  # sold share uses only plots where both the harvest and the sold quantity are known
  sold_share_pct = { k <- !is.na(harvest_kg) & !is.na(sold_kg_plot)
                     100 * wsum(sold_kg_plot[k], weight[k]) / wsum(harvest_kg[k], weight[k]) },
  price_rwf_kg   = wmean(price_rwf_kg[sold_kg > 0], weight[sold_kg > 0]),
  sales_value_mrwf = wsum(sales_value_rwf, weight) / 1e6,          # GROSS sales value, not income
  sales_value_imputed_pct = 100 * wsum(sales_value_rwf[price_imputed %in% TRUE], weight[price_imputed %in% TRUE]) /
                            wsum(sales_value_rwf, weight),
  improved_seed_pct = 100 * wmean(improved_seed, weight),
  .groups = "drop")

# Seasons where crop areas are too incomplete for yields (2024B: 46%, 2024C: 7%).
# Computed here, before any aggregate, so national, district and crop tables, the
# yield charts and the yield model all leave out the same seasons.
min_area_coverage <- 80
season_quality <- master_crop_plot |>
  group_by(sas_year, sas_season) |>
  summarise(area_coverage_pct = round(100 * mean(!is.na(crop_area_ha[harvest_kg > 0 & !is.na(harvest_kg)])), 1),
            .groups = "drop") |>
  mutate(yield_usable = area_coverage_pct >= min_area_coverage)
master_crop_plot <- master_crop_plot |>
  left_join(season_quality |> select(sas_year, sas_season, season_yield_usable = yield_usable),
            by = c("sas_year", "sas_season"))

finite <- \(d) mutate(d, across(where(is.numeric), \(x) if_else(is.finite(x), x, NA_real_)))

agg_at <- function(by) master_plot |> group_by(across(all_of(by))) |> plot_measures() |>
  full_join(master_farmer |> group_by(across(all_of(by))) |> farmer_measures(), by = by) |>
  full_join(master_crop_plot |> group_by(across(all_of(by))) |> crop_measures(), by = by) |>
  finite()
master_national_season <- agg_at(c("sas_year", "sas_season"))
# every measure at the SAME grain (district x year x season); province added after
master_district_season <- agg_at(c("district_std", "sas_year", "sas_season")) |>
  filter(!is.na(district_std)) |>
  left_join(district_province, by = "district_std") |> relocate(province) |>
  left_join(master_rain, by = c("district_std", "sas_year", "sas_season"))

# Checks before saving: one row per district-season, and district totals add up
# to the national totals (within 0.5%).
dups <- count(master_district_season, district_std, sas_year, sas_season) |> filter(n > 1)
if (nrow(dups)) stop("master_district_season has duplicate district-season rows: ", nrow(dups))
add_cols <- c("cultivated_area_ha", "irrigated_area_ha", "production_t", "crop_area_ha", "sold_t", "sales_value_mrwf")
reconcile <- master_district_season |>
  group_by(sas_year, sas_season) |> summarise(across(all_of(add_cols), \(x) sum(x, na.rm = TRUE)), .groups = "drop") |>
  pivot_longer(all_of(add_cols), names_to = "measure", values_to = "districts_sum") |>
  left_join(master_national_season |> select(sas_year, sas_season, all_of(add_cols)) |>
              pivot_longer(all_of(add_cols), names_to = "measure", values_to = "national"),
            by = c("sas_year", "sas_season", "measure")) |>
  mutate(ratio = districts_sum / national, ok = is.na(national) | abs(ratio - 1) <= 0.005)
if (!all(reconcile$ok)) {
  print(filter(reconcile, !ok))
  stop("District totals do not add up to national totals (see above)")
}

master_crop_season <- master_crop_plot |>
  group_by(crop_group, crop_name, sas_year, sas_season) |> crop_measures() |> finite()
master_crop_district_season <- master_crop_plot |>
  group_by(district_std, crop_group, crop_name, sas_year, sas_season) |> crop_measures() |> finite()

# ---- 8. DICTIONARY, COVERAGE, JOIN LOG ---------------------------------------
dict <- tribble(
  ~column, ~meaning, ~unit, ~source,
  "sas_year / sas_season", "Agricultural year and season (A Sep-Feb, B Mar-Jun, C Jul-Sep)", "", "all",
  "district_std / province", "District (30) and province", "", "agri_prac / crop_prod",
  "weight", "Plot expansion weight (crop_prod; else agri_prac same plot)", "", "harmonised",
  "plot_area_ha", "Plot area", "ha", "agri_prac",
  "irrig_any_farmer", "Farmer irrigated any plot this season (2020+), repeated on each plot row", "0/1", "agri_prac",
  "irrig_farmer (master_farmer)", "Farmer irrigated any plot this season; ONE row per farmer; weight = mean of the farmer's plot weights", "0/1", "derived",
  "farmers_irrig_pct", "Share of farmers irrigating any plot, one record per farmer (not plot-weighted)", "%", "aggregate",
  "irrigated_area_ha / irrigated_area_pct", "Area of plots REPORTING irrigation (whole plot area x irrigated flag); not hectares actually watered and not comparable with programme irrigation-area targets", "ha, %", "aggregate",
  "irrigated", "Plot irrigated this season; NA->0 when farmer irrigated no plot (skip pattern)", "0/1", "agri_prac",
  "irrig_technique", "Drip, Sprinkler, Pivot, Flood (rice), Surface, Traditional", "", "agri_prac",
  "irrig_source", "Main water source (first answer)", "", "agri_prac",
  "src_*", "Water source mentioned (any answer), irrigated plots only", "0/1", "agri_prac",
  "irrig_tool / irrig_tool_level", "Main irrigation tool and technology ladder 1-4", "", "agri_prac",
  "irrig_modern", "Motorised / machine tool or drip / sprinkler / pivot", "0/1", "derived",
  "irrig_cost_rwf", "Irrigation cost this season", "RWF", "agri_prac",
  "oxen / tractor / other_machine / mechanised", "Mechanisation used (2019: any plot; 2020+: this plot)", "0/1", "agri_prac",
  "erosion_degree / anti_erosion / land_consolidated", "Land and soil condition", "", "agri_prac",
  "organic_fert / inorganic_fert / pesticide / micronutrient", "Inputs used on this plot", "0/1", "fert_pest",
  "agroforestry", "Agroforestry on plot (2020+)", "0/1", "agrofor / crop_screen",
  "crop_name / crop_group", "Crop and harmonised crop group", "", "crop_prod",
  "harvest_kg", "Total harvest of the crop on the plot this season", "kg", "crop_prod",
  "crop_area_ha / crop_area_source / crop_area_capped", "Crop area (crop_prod, else crop_screen); capped at plot area", "ha", "harmonised",
  "yield_kg_ha / yield_ok", "harvest_kg / crop_area_ha; yield_ok = FALSE outside the 1st-99th pct per crop-season", "kg/ha", "derived",
  "sold_kg / sold_kg_plot / price_rwf_kg / sales_value_rwf", "Quantity sold as reported, capped at plot harvest; price (codes 999/9999/99999 and 0 removed); gross sales value using the reported price or, if missing, the crop-season-district median price (price_imputed flag); not net income", "kg, RWF", "crop_prod",
  "improved_seed", "Improved seed used for this crop", "0/1", "crop_prod",
  "modern_inputs_n", "Count of complementary inputs: improved seed + inorganic fertiliser + mechanisation (irrigation NOT counted); missing when any of the three is unknown", "0-3", "derived",
  "area_coverage_pct / season_yield_usable", "Share of harvested crop plots with a crop area; seasons below 80% (2024B, 2024C) are left out of yields", "%", "aggregate",
  "sales_value_imputed_pct", "Share of gross sales value that uses an imputed (median) price", "%", "aggregate",
  "gender / age_years / age_band", "Farmer gender and age", "", "crop_prod / agri_prac",
  "rain_mm / rain_normal_mm / rain_anomaly_pct / rain_std_anomaly / dry_season_flag",
  "CHIRPS season total, 1991-2020 normal, anomaly, z-score, z < -1", "mm, %", "CHIRPS",
  "*_pct (aggregates)", "Survey-weighted share", "%", "aggregate",
  "production_t / sold_t / sales_value_mrwf", "Weighted totals (plot weights as expansion factors)", "t, million RWF", "aggregate",
  "yield_irrigated_kg_ha / yield_rainfed_kg_ha / yield_premium_pct", "Ratio-of-sums yield by irrigation status (raw, not causal); not usable in seasons with low area coverage", "kg/ha, %", "aggregate")

coverage <- function(d, name) d |>
  mutate(ys = paste0(sas_year, sas_season)) |>
  group_by(ys) |>
  summarise(across(-any_of(c("sas_year", "sas_season")), \(x) round(100 * mean(!is.na(x)))), .groups = "drop") |>
  pivot_longer(-ys, names_to = "column", values_to = "pct_non_missing") |>
  pivot_wider(names_from = ys, values_from = pct_non_missing) |>
  mutate(table = name, .before = 1)
cov <- bind_rows(coverage(master_plot, "master_plot"), coverage(master_crop_plot, "master_crop_plot"),
                 coverage(master_farmer, "master_farmer"))

# ---- 9. SAVE -----------------------------------------------------------------
out <- list(master_crop_plot = master_crop_plot, master_plot = master_plot, master_farmer = master_farmer,
            master_national_season = master_national_season,
            master_district_season = master_district_season,
            master_crop_season = master_crop_season,
            master_crop_district_season = master_crop_district_season,
            master_rain_district_season = master_rain)
iwalk(out, \(d, n) saveRDS(d, file.path(dir_master, paste0(n, ".rds"))))
if (write_csv_copies) iwalk(out[!names(out) %in% c("master_crop_plot", "master_plot", "master_farmer")],
                            \(d, n) write_csv(d, file.path(dir_master, paste0(n, ".csv")), na = ""))
write_csv(dict, file.path(dir_master, "master_dictionary.csv"))
write_csv(cov, file.path(dir_master, "master_coverage.csv"), na = "")
write_csv(season_quality, file.path(dir_master, "season_quality.csv"), na = "")
write_csv(reconcile, file.path(dir_master, "district_national_reconciliation.csv"), na = "")
skip_audit <- bind_rows(skip_audit)
write_csv(skip_audit, file.path(dir_master, "skip_pattern_audit.csv"), na = "")
join_log <- bind_rows(join_log)
write_csv(join_log, file.path(dir_master, "master_join_log.csv"))

# ---- 10. FILTER + SUMMARISE HELPERS (use these interactively) ----------------
# filter_master(master_crop_plot, years = 2023:2025, seasons = "A",
#               districts = c("Bugesera", "Nyagatare"), crops = "Maize")
filter_master <- function(d, years = NULL, seasons = NULL, provinces = NULL,
                          districts = NULL, crops = NULL, crop_groups = NULL, genders = NULL) {
  if (!is.null(years))       d <- filter(d, sas_year %in% years)
  if (!is.null(seasons))     d <- filter(d, sas_season %in% seasons)
  if (!is.null(provinces) && "province" %in% names(d)) d <- filter(d, province %in% provinces)
  if (!is.null(districts))   d <- filter(d, district_std %in% districts)
  if (!is.null(crops) && "crop_name" %in% names(d))       d <- filter(d, crop_name %in% crops)
  if (!is.null(crop_groups) && "crop_group" %in% names(d)) d <- filter(d, crop_group %in% crop_groups)
  if (!is.null(genders) && "gender" %in% names(d))         d <- filter(d, gender %in% genders)
  d
}
# summarise_measures(filter_master(master_crop_plot, crops = "Maize"), by = c("sas_year", "irrigated"))
summarise_measures <- function(d, by = character()) {
  d <- group_by(d, across(all_of(by)))
  if ("crop_name" %in% names(d)) crop_measures(d) |> finite() else plot_measures(d) |> finite()
}

# ---- 11. PRINT A SHORT REPORT ------------------------------------------------
cat("\n== MASTER TABLES (DATA/processed/master) ==\n")
iwalk(out, \(d, n) cat(sprintf("  %-30s %9d rows %4d cols\n", n, nrow(d), ncol(d))))
cat("\n== Skip patterns confirmed (blanks set to No) ==\n")
print(skip_audit |> group_by(variable) |>
        summarise(seasons_confirmed = sum(skip_confirmed), seasons = n(),
                  blanks_set_to_no = sum(blanks_set_to_no)), n = 20)
cat("\n== Join match rates (lowest 5) ==\n"); print(arrange(join_log, match_rate) |> head(5))
cat("\n== Seasons left out of yields (crop area coverage < ", min_area_coverage, "%) ==\n", sep = "")
print(filter(season_quality, !yield_usable))
cat("\n== National irrigation and production, by season ==\n")
print(master_national_season |>
        transmute(sas_year, sas_season, irrigated_plot_pct = round(irrigated_plot_pct, 1),
                  irrigated_area_ha = round(irrigated_area_ha), modern_irrig_pct = round(modern_irrig_pct, 1),
                  production_kt = round(production_t / 1000), yield_premium_pct = round(yield_premium_pct)),
      n = 21)
