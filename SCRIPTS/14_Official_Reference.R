# ============================================================================
# 14_Official_Reference.R  -  the published NISR figures the app shows first
# SmartIrrigate Rwanda - Team NiyoIshimwe
#
# Takes the long table of every published cell (SCRIPTS/11) and keeps the figures
# that answer the app's questions, using DATA/NISR_published/indicator_rules.csv
# (table title + column text -> app indicator, unit, population, definition,
# and whether our survey estimate measures the same thing).
#
# User decision 2026-10-21: where NISR publishes a figure with the same
# definition, the app shows the NISR figure (headline, chart, map, table, CSV all
# from that one value) and keeps our estimate only as a cross-check. Where the
# definition differs, the NISR figure is shown under its own label and never
# compared directly. Where NISR publishes no breakdown, the app says so.
#
# Scope: statistics 2019-2025 only (11 already drops later releases and seasons).
#
# Inputs : DATA/processed/official/nisr_published_all_tables.csv  (from 11)
#          DATA/NISR_published/indicator_rules.csv
# Output : DATA/processed/official/official_reference.csv   one row per published
#          figure, with survey, file, sheet, cell, table number and title
# ============================================================================

suppressPackageStartupMessages({ library(dplyr); library(readr); library(stringr); library(purrr) })

dir_root <- Sys.getenv("HACKATHON_ROOT", ".")
dir_pub  <- file.path(dir_root, "DATA", "NISR_published")
dir_out  <- file.path(dir_root, "DATA", "processed", "official")
last_stat_year <- 2025

cells_file <- file.path(dir_out, "nisr_published_all_tables.csv")
if (!file.exists(cells_file)) stop("Run SCRIPTS/11_NISR_Published_Tables.R first (no ", cells_file, ")")
cells <- read_csv(cells_file, show_col_types = FALSE, guess_max = 1e5,
                  col_types = cols(value = col_double(), sas_year = col_integer(), .default = col_character())) |>
  filter(sas_year <= last_stat_year)
rules <- read_csv(file.path(dir_pub, "indicator_rules.csv"), show_col_types = FALSE,
                  col_types = cols(scale = col_double(), comparable = col_logical(), .default = col_character()))

# NISR crop names -> the app's crop names. Groups ("Cereals", "Vegetables") and
# all-type totals ("Bananas" when cooking/dessert/beer bananas are also listed,
# "Beans" when bush and climbing beans are) are subtotals: they are flagged and
# renamed "... (all)" so they are never added to the crops they contain.
crop_fix <- c("Cooking Banana" = "Cooking banana", "Irish potatoes" = "Irish potato",
              "Sweet potatoes" = "Sweet potato", "Soya beans" = "Soybean", "Ground nuts" = "Groundnut",
              "Groundnuts" = "Groundnut", "Peas" = "Pea", "Yarms & Taro" = "Yams & Taro",
              "Taro & Yams" = "Yams & Taro", "Paddy Rice" = "Paddy rice", "Bean" = "Beans",
              "Banana" = "Bananas", "Other Cereals" = "Other cereals")
group_children <- list(
  "Cereals" = c("Maize", "Sorghum", "Paddy rice", "Wheat"),
  "Tubers and Roots" = c("Cassava", "Sweet potato", "Irish potato", "Yams & Taro"),
  "Legumes and Pulses" = c("Beans", "Bush bean", "Climbing bean", "Pea", "Groundnut", "Soybean"),
  "Vegetables and Fruits" = c("Vegetables", "Fruits"),
  "Bananas" = c("Cooking banana", "Dessert banana", "Banana for beer"),
  "Beans" = c("Bush bean", "Climbing bean", "Small red bean"))
always_group <- c("Cereals", "Tubers and Roots", "Legumes and Pulses", "Vegetables and Fruits",
                  "Vegetables", "Fruits", "Fodder crops", "Total", "National")
fix_crop <- \(x) { x <- str_squish(x); coalesce(unname(crop_fix[x]), x) }

apply_rule <- function(r) {
  d <- cells |>
    filter(survey == r$survey,
           str_detect(table_title, regex(r$title_rx, ignore_case = TRUE)),
           if (is.na(r$column_rx)) TRUE
           else str_detect(coalesce(column, ""), regex(r$column_rx, ignore_case = TRUE)))
  d <- switch(r$geo,
    geo      = d |> filter(is.na(row_item)),                         # national + district rows
    national = d |> filter(level == "national", !is.na(row_item)),   # crop rows of the national table
    district = d |> filter(level == "district"))
  if (!nrow(d)) return(NULL)
  d |> mutate(
    indicator = r$indicator,
    crop_name = case_when(r$crop_from %in% "row" ~ fix_crop(row_item),
                          r$crop_from %in% "column" ~ fix_crop(column), TRUE ~ NA_character_),
    # per-unit scale: thousand ha tables, and yield tables in t/ha
    value = value * r$scale * if_else(r$unit == "kg/ha" & unit %in% "t/ha", 1000, 1),
    unit_out = r$unit, population = r$population, definition = r$definition,
    project_indicator = r$project_indicator, project_table = r$project_table,
    comparable = r$comparable, rule_note = r$note)
}

ref <- map(seq_len(nrow(rules)), \(i) apply_rule(rules[i, ])) |> bind_rows()
if (!nrow(ref)) stop("No published cell matched indicator_rules.csv: check the table titles in ", cells_file)

ref <- ref |>
  filter(!str_detect(coalesce(crop_name, ""), regex("^other", ignore_case = TRUE)), !crop_name %in% "") |>
  # a group is a subtotal when the table also lists its parts (or it is always one)
  group_by(source_file, sheet) |>
  mutate(is_group = !is.na(crop_name) & (crop_name %in% always_group |
           vapply(crop_name, \(cn) cn %in% names(group_children) && any(group_children[[cn]] %in% crop_name), logical(1)))) |>
  ungroup() |>
  mutate(crop_name = if_else(is_group, paste0(crop_name, " (all)"), crop_name),
         # national rows of a district table compare with our national crop table
         project_table = if_else(project_table %in% "crop_dist" & level == "national", "crop", project_table),
         source_title = paste0("NISR, ", if_else(survey == "SAS", "Seasonal Agricultural Survey", "Agricultural Household Survey"),
                               " ", str_extract(source_file, "20[0-9]{2}"), ", ", nisr_table, ": ", table_title),
         # the exact column wording NISR prints, for the label shown in the app
         measure_label = coalesce(column, measure)) |>
  transmute(indicator, survey, sas_year, sas_season, level, area, province, crop_name, is_group, farmer_type,
            value, unit = unit_out, value_note, measure_label, population, definition, comparable,
            project_indicator, project_table, source_title, source_file, sheet, cell, nisr_table,
            table_title, rule_note)

# One figure per indicator x season x place x crop x farmer type. A season printed
# in two releases (e.g. 2024A in the 2024 and 2025 annual tables) keeps the later
# release, which carries NISR's revisions; the other copy is listed as a duplicate.
ref <- ref |>
  mutate(release = as.integer(str_extract(source_file, "20[0-9]{2}"))) |>
  arrange(desc(release)) |>
  group_by(indicator, sas_year, sas_season, level, area, crop_name, farmer_type) |>
  mutate(copies = n(), revised_from = if_else(n() > 1, paste(unique(value[-1]), collapse = "; "), NA_character_)) |>
  slice(1) |> ungroup() |> select(-release)

# A parent printed in one table and its parts in another (SAS 2019 lists "Beans" and
# "Bananas" beside bush/climbing beans and the banana types) is a subtotal there too.
ref <- ref |>
  group_by(indicator, sas_year, sas_season, level, area, farmer_type) |>
  mutate(parent = !is_group & vapply(crop_name, \(cn) !is.na(cn) && cn %in% names(group_children) &&
                                       any(group_children[[cn]] %in% crop_name), logical(1))) |>
  ungroup() |>
  mutate(is_group = is_group | parent, crop_name = if_else(parent, paste0(crop_name, " (all)"), crop_name)) |>
  select(-parent) |>
  distinct(indicator, sas_year, sas_season, level, area, crop_name, farmer_type, .keep_all = TRUE)

# Skip gate (verified on the 2019-2025 microdata by 15_Reconcile_With_NISR.R): once
# the questionnaire asks "did you use X on ANY of your plots?" first, the plot
# question is only answered on plots of farmers who said yes, and NISR's "% of
# plots" is the share among those plots. Ours is the share of ALL cultivated
# plots, so the two are different populations from the gate onwards and are not
# compared as the same indicator. Gate starts: pesticide and organic fertiliser
# 2022C, chemical fertiliser 2025A (in 2024A the question was asked on every plot).
gate_start <- c(pesticide = 2022.3, organic_fert = 2022.3, inorganic_fert = 2025.1)
# the % of land is built from the same gated plot question, so it follows the same gate
gate_start <- c(gate_start, setNames(gate_start, paste0(names(gate_start), "_land")))
season_key <- \(y, s) y + match(s, c("A", "B", "C")) / 10
ref <- ref |>
  mutate(gated = indicator %in% names(gate_start) &
           season_key(sas_year, sas_season) >= coalesce(gate_start[indicator], Inf),
         comparable = comparable & !gated,
         population = if_else(gated, paste0("plots of farmers who reported using it on any plot (", sas_year, sas_season, " questionnaire skip)"), population),
         rule_note = if_else(gated, str_squish(paste(coalesce(rule_note, ""),
           "Different population from ours: NISR counts only plots of farmers who used it on any plot; ours counts all cultivated plots.")), rule_note)) |>
  select(-gated)

write_csv(ref, file.path(dir_out, "official_reference.csv"), na = "")
message("14 Official reference: ", nrow(ref), " published figures (",
        sum(ref$comparable), " with the same definition as a project estimate)")
print(count(ref, indicator, level, sas_year), n = 200)
