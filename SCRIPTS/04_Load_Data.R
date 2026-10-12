# ============================================================================
# SMARTIRRIGATE RWANDA | LOAD PREPARED DATA INTO R
#
# Run after 03_Data_Preparation.R. Reads DATA/processed/ and creates one
# object per dataset in your environment, named <module><year><season>:
#
#   crop_prod2019A    crop production
#   crop_screen2019A  crop / land-use screening
#   agri_prac2019A    agricultural practices (irrigation lives here)
#   fert_pest2019A    fertilizers & pesticides
#   land_ten2019A     land tenure            (2019 only)
#   agrofor2020A      agroforestry screening (2020-2023)
#   erosion2020A      anti-erosion & land consolidation (2020-2023)
#
#   chirps            CHIRPS district-month rainfall 1981-2025
#   districts_sf      GADM district boundaries (sf)
#
# Columns are renamed, coded values are labelled factors, and each column
# keeps its question text as a label (see labelled::look_for()).
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(stringr)
  library(tibble)
  library(labelled)
})

dir_processed <- file.path("DATA", "processed")
if (!dir.exists(file.path(dir_processed, "SAS"))) {
  stop("DATA/processed/SAS not found in ", getwd(),
       ". Run 03_Data_Preparation.R first, from the Hackathon folder.")
}

# Optional filters: load only what you need to save memory (NULL = all)
years_to_load   <- NULL          # e.g. 2023:2025
seasons_to_load <- NULL          # e.g. c("A", "B")
modules_to_load <- NULL          # e.g. c("agri_prac", "crop_prod")

module_abbrev <- c(
  crop_production            = "crop_prod",
  crop_screening             = "crop_screen",
  agricultural_practices     = "agri_prac",
  fertilizers_pesticides     = "fert_pest",
  land_tenure                = "land_ten",
  agroforestry_screening     = "agrofor",
  erosion_land_consolidation = "erosion"
)


# 1. INDEX OF PREPARED FILES --------------------------------------------------

data_index <- tibble(
  path = list.files(file.path(dir_processed, "SAS"), pattern = "\\.rds$",
                    recursive = TRUE, full.names = TRUE)
) |>
  mutate(
    year   = as.integer(str_extract(path, "(?<=SAS_)\\d{4}")),
    season = str_extract(path, "(?<=Season_)[ABC]"),
    module = str_remove(basename(path), "\\.rds$"),
    abbrev = coalesce(unname(module_abbrev[module]), module),
    object = paste0(abbrev, year, season)
  ) |>
  filter(is.null(years_to_load)   | year   %in% years_to_load,
         is.null(seasons_to_load) | season %in% seasons_to_load,
         is.null(modules_to_load) | abbrev %in% modules_to_load) |>
  arrange(abbrev, year, season)


# 2. LOAD INTO THE ENVIRONMENT + A NAMED LIST ---------------------------------

sas <- map(set_names(data_index$path, data_index$object), readRDS)
list2env(sas, envir = globalenv())

data_index <- data_index |>
  mutate(rows = map_int(sas, nrow), cols = map_int(sas, ncol),
         size_mb = round(map_dbl(sas, \(d) as.numeric(object.size(d))) / 1e6, 1))

if (file.exists(file.path(dir_processed, "chirps_district_month.rds"))) {
  chirps <- readRDS(file.path(dir_processed, "chirps_district_month.rds"))
}
if (file.exists(file.path(dir_processed, "gadm_districts.rds")) &&
    requireNamespace("sf", quietly = TRUE)) {
  library(sf)
  districts_sf <- readRDS(file.path(dir_processed, "gadm_districts.rds"))
}


# 3. HELPERS FOR ANALYSIS -----------------------------------------------------

# Stack one module across years/seasons, e.g. stack_module("agri_prac").
# Columns whose type differs between files are converted to character so
# they can be combined. Columns missing in a year are filled with NA.
stack_module <- function(abbrev, years = NULL, seasons = NULL) {
  idx <- data_index |>
    filter(.data$abbrev == !!abbrev,
           is.null(years)   | year   %in% years,
           is.null(seasons) | season %in% seasons)
  if (!nrow(idx)) stop("No loaded datasets for module '", abbrev, "'")
  dfs <- sas[idx$object]

  types <- dfs |>
    map(\(d) map_chr(d, \(x) class(x)[1])) |>
    map(\(x) enframe(x, "col", "type")) |>
    bind_rows() |>
    distinct()
  mixed <- unique(types$col[duplicated(types$col)])

  dfs |>
    map(\(d) mutate(d, across(any_of(mixed), as.character))) |>
    bind_rows()
}

# Find variables by keyword in names or question labels, across all datasets,
# e.g. find_var("irrigat")
find_var <- function(pattern) {
  imap(sas, \(d, obj) tibble(
    object   = obj,
    variable = names(d),
    label    = map_chr(d, \(x) attr(x, "label", exact = TRUE) %||% NA_character_)
  )) |>
    bind_rows() |>
    filter(str_detect(variable, regex(pattern, ignore_case = TRUE)) |
             str_detect(coalesce(label, ""), regex(pattern, ignore_case = TRUE)))
}


# 4. INDEX --------------------------------------------------------------------

cat("\nLoaded", nrow(data_index), "SAS datasets (",
    round(sum(data_index$size_mb)), "MB in memory)\n\n")
print(select(data_index, object, rows, cols, size_mb), n = Inf)
if (exists("chirps")) cat("\nchirps       :", nrow(chirps), "rows\n")
if (exists("districts_sf")) cat("districts_sf :", nrow(districts_sf), "districts\n")

# EXAMPLES --------------------------------------------------------------------
# glimpse(agri_prac2025B)
# look_for(agri_prac2025B, "irrig")
# count(agri_prac2025B, district_name_code, plot_irrigated_this_season)
# find_var("irrigation_technique") |> count(variable)
# irrig_all <- stack_module("agri_prac")
# count(irrig_all, sas_year, sas_season, irrigation_any_plot_this_season)
