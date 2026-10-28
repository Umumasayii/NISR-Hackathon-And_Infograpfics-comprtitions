# ============================================================================
# 15_Reconcile_With_NISR.R  -  why do our estimates differ from NISR's tables?
# SmartIrrigate Rwanda - Team NiyoIshimwe
#
# For fertiliser, pesticide and crop production, NISR's published figures and our
# survey estimates differ (audit 2026-10-20: inputs 20-30 points, maize production
# -35% to +37%). This script recomputes our figure several ways and sets each next
# to the published cell, nationally and for every district, so the cause can be
# read from the data instead of guessed.
#
# Inputs : DATA/processed/master/master_plot.rds, master_farmer.rds,
#          master_crop_plot.rds (from 06)
#          DATA/processed/official/official_reference.csv (from 11 + 14)
# Outputs: DATA/processed/official/reconcile_inputs.csv      one row per published
#          cell x way of computing; reconcile_inputs_best.csv (closest way per
#          indicator and season); reconcile_production.csv (production split into
#          harvested area and yield, so a gap can be traced to one or the other)
#
# Ways of computing inputs (all weighted unless said):
#   plot_project   % of plots, as in the app (blank plot answers set to "No" only
#                  where the "any of your plots" question confirms the skip)
#   plot_answered  % of plots, only plots with their own answer (no skip fill)
#   plot_ssf       % of plots of small-scale farmers only
#   plot_crop      % of plots that also appear in the crop-production module
#   plot_unweighted
#   farmer_mean_w  % of farmers (any plot), farmer weight = mean of plot weights
#   farmer_sum_w   % of farmers, farmer weight = sum of plot weights
#   land           % of cultivated area
# Nothing here changes the app; it explains the gaps for the register and Methods.
# ============================================================================

source(file.path(Sys.getenv("HACKATHON_ROOT", "."), "SCRIPTS", "00_Config.R"))
dir_off <- file.path(dir_root, "DATA", "processed", "official")
off_file <- file.path(dir_off, "official_reference.csv")
if (!file.exists(off_file)) stop("Run SCRIPTS/11 and 14 first: ", off_file, " is missing")

official <- read_csv(off_file, show_col_types = FALSE, guess_max = 1e5) |>
  filter(sas_year <= 2025, farmer_type == "All")
plot   <- read_master("master_plot")
farmer <- read_master("master_farmer")
cropp  <- read_master("master_crop_plot")

inputs <- c("inorganic_fert", "organic_fert", "pesticide")
wm <- \(x, w) { k <- !is.na(x) & !is.na(w); if (!any(k)) NA_real_ else 100 * sum(x[k] * w[k]) / sum(w[k]) }
geo <- \(d) bind_rows(d |> mutate(level = "national", area = "Rwanda"),
                      d |> filter(!is.na(district_std)) |> mutate(level = "district", area = district_std))

in_crop <- cropp |> distinct(ys, segment_id, plot_number) |> mutate(in_crop = TRUE)
plot <- plot |> left_join(in_crop, by = c("ys", "segment_id", "plot_number")) |>
  mutate(in_crop = coalesce(in_crop, FALSE),
         ssf = !str_detect(str_to_lower(coalesce(as.character(farmer_type), "")), "large|lsf"))

plot_ways <- geo(plot) |>
  group_by(level, area, sas_year, sas_season) |>
  summarise(across(all_of(inputs), list(
    plot_project    = \(x) wm(x, weight),
    plot_answered   = \(x) wm(x, weight),    # replaced below when raw answers exist
    plot_ssf        = \(x) wm(x[ssf], weight[ssf]),
    plot_crop       = \(x) wm(x[in_crop], weight[in_crop]),
    plot_unweighted = \(x) wm(x, rep(1, length(x))),
    land            = \(x) wm(x, weight * plot_area_ha)), .names = "{.col}__{.fn}"), .groups = "drop")
# raw plot answers (before the skip fill), when 06 kept them
for (v in inputs) if (paste0(v, "_raw") %in% names(plot)) {
  raw <- geo(plot) |> group_by(level, area, sas_year, sas_season) |>
    summarise(x = wm(.data[[paste0(v, "_raw")]], weight), .groups = "drop")
  plot_ways[[paste0(v, "__plot_answered")]] <- raw$x[match(do.call(paste, plot_ways[1:4]), do.call(paste, raw[1:4]))]
} else plot_ways[[paste0(v, "__plot_answered")]] <- NA_real_

farmer_w <- plot |> group_by(ys, segment_id, farmer_id) |>
  summarise(w_sum = sum(weight, na.rm = TRUE), .groups = "drop")
farmer <- farmer |> left_join(farmer_w, by = c("ys", "segment_id", "farmer_id"))
farmer_ways <- geo(farmer) |>
  group_by(level, area, sas_year, sas_season) |>
  summarise(across(all_of(paste0(inputs, "_farmer")), list(
    farmer_mean_w = \(x) wm(x, weight),
    farmer_sum_w  = \(x) wm(x, w_sum),
    farmer_unweighted = \(x) wm(x, rep(1, length(x)))), .names = "{.col}__{.fn}"), .groups = "drop") |>
  rename_with(\(n) str_replace(n, "_farmer__", "__"))

ways <- full_join(plot_ways, farmer_ways, by = c("level", "area", "sas_year", "sas_season")) |>
  pivot_longer(contains("__"), names_to = c("input", "way"), names_sep = "__", values_to = "project_value")

# which published measure each way answers: farmers, plots or land
pub <- official |>
  filter(str_detect(indicator, paste0("^(", paste(inputs, collapse = "|"), ")"))) |>
  mutate(input = str_remove(indicator, "_(farmer|land)$"),
         measure = case_when(str_ends(indicator, "_farmer") ~ "farmers", str_ends(indicator, "_land") ~ "land",
                             TRUE ~ "plots")) |>
  select(input, measure, sas_year, sas_season, level, area, published = value, source_file, sheet, cell)
way_measure <- c(plot_project = "plots", plot_answered = "plots", plot_ssf = "plots", plot_crop = "plots",
                 plot_unweighted = "plots", farmer_mean_w = "farmers", farmer_sum_w = "farmers",
                 farmer_unweighted = "farmers", land = "land")
rec <- ways |> mutate(measure = unname(way_measure[way])) |>
  inner_join(pub, by = c("input", "measure", "sas_year", "sas_season", "level", "area")) |>
  mutate(gap_pts = project_value - published)
write_csv(rec, file.path(dir_off, "reconcile_inputs.csv"), na = "")

best <- rec |> filter(!is.na(gap_pts)) |>
  group_by(input, measure, sas_year, sas_season, way) |>
  summarise(national_gap = gap_pts[level == "national"][1],
            district_mae = mean(abs(gap_pts[level == "district"])),
            district_cor = suppressWarnings(cor(project_value[level == "district"], published[level == "district"])),
            .groups = "drop") |>
  group_by(input, measure, sas_year, sas_season) |>
  arrange(abs(national_gap), .by_group = TRUE) |> mutate(rank = row_number()) |> ungroup()
write_csv(best, file.path(dir_off, "reconcile_inputs_best.csv"), na = "")

# Farmers who practised irrigation (NISR "Percentage of farmers who practiced agricultural
# practices"): the project's weighted share beside the unweighted share of sampled farmers.
if ("irrig_farmer" %in% names(farmer)) {
irr <- geo(farmer) |> filter(!is.na(irrig_farmer)) |>
  group_by(level, area, sas_year, sas_season) |>
  summarise(farmer_mean_w = wm(irrig_farmer, weight), farmer_sum_w = wm(irrig_farmer, w_sum),
            farmer_unweighted = wm(irrig_farmer, rep(1, n())), n_farmers = n(), .groups = "drop") |>
  pivot_longer(starts_with("farmer_"), names_to = "way", values_to = "project_value") |>
  inner_join(official |> filter(indicator == "irrig_any_farmer") |>
               select(sas_year, sas_season, level, area, published = value, source_file, sheet, cell),
             by = c("sas_year", "sas_season", "level", "area")) |>
  mutate(input = "irrigation", measure = "farmers", gap_pts = project_value - published)
write_csv(irr, file.path(dir_off, "reconcile_irrigation_farmers.csv"), na = "")
}

# Production = harvested area x yield. Splitting the gap shows whether it comes
# from how much land is counted or from harvest per hectare.
crop_geo <- geo(cropp) |> filter(!is.na(crop_name)) |>
  group_by(level, area, sas_year, sas_season, crop_name) |>
  summarise(prod_t = sum(harvest_kg * weight, na.rm = TRUE) / 1000,
            prod_t_cropweight = if ("weight_cp" %in% names(cropp)) sum(harvest_kg * weight_cp, na.rm = TRUE) / 1000 else NA_real_,
            area_ha = sum((crop_area_ha * weight)[!is.na(harvest_kg)], na.rm = TRUE),
            n_plots = n(), .groups = "drop") |>
  mutate(yield_kg_ha = 1000 * prod_t / area_ha)
pubc <- official |> filter(indicator %in% c("production_t", "harvested_crop_ha", "yield_kg_ha"), !is_group) |>
  select(indicator, sas_year, sas_season, level, area, crop_name, value) |>
  mutate(indicator = paste0("pub_", indicator)) |>
  pivot_wider(names_from = indicator, values_from = value)
for (v in c("pub_production_t", "pub_harvested_crop_ha", "pub_yield_kg_ha"))
  if (!v %in% names(pubc)) pubc[[v]] <- NA_real_
recp <- crop_geo |> inner_join(pubc, by = c("level", "area", "sas_year", "sas_season", "crop_name")) |>
  mutate(prod_ratio  = prod_t / pub_production_t,
         area_ratio  = area_ha / pub_harvested_crop_ha,
         yield_ratio = yield_kg_ha / pub_yield_kg_ha,
         main_cause = case_when(
           is.na(prod_ratio) ~ NA_character_,
           abs(log(prod_ratio)) < log(1.1) ~ "within 10%",
           is.na(area_ratio) | is.na(yield_ratio) ~ "not split (area or yield not published)",
           abs(log(area_ratio)) >= abs(log(yield_ratio)) ~ "area counted",
           TRUE ~ "harvest per hectare"))
write_csv(recp, file.path(dir_off, "reconcile_production.csv"), na = "")

message("15 Reconciliation: ", nrow(rec), " input comparisons, ", nrow(recp), " crop comparisons")
print(best |> filter(rank == 1) |> select(input, measure, sas_year, sas_season, way, national_gap, district_mae), n = 100)
print(count(recp |> filter(level == "national"), main_cause))
