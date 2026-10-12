# ============================================================================
# SMARTIRRIGATE RWANDA | DATA PREPARATION (NISR 2026 HACKATHON)
#
#   1. Load all datasets   : NISR SAS 2019-2025 (Seasons A, B, C; .sav/.dta),
#                            CHIRPS district-month rainfall, GADM districts
#   2. Rename variables    : Dictionaries/VARIABLE_RENAME_MAP.csv
#   3. Label values        : value labels stored inside the .sav/.dta files
#                            first, then Dictionaries/VALUE_LABELS_LOOKUP_ALL_ORIGINAL.csv
#
# Raw files in DATA/ are only read, never modified.
# Outputs go to DATA/processed/ (one .rds per dataset + review logs).
#
# Run from the project root (the "Hackathon" folder), e.g. open the RStudio
# project there or setwd("C:/Users/branc/OneDrive/Documenti/Hackathon").
# ============================================================================


# 0. PACKAGES & PATHS ---------------------------------------------------------

pkgs <- c("haven", "labelled", "dplyr", "purrr", "stringr", "readr",
          "tibble", "sf")
missing_pkgs <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs)) install.packages(missing_pkgs)

suppressPackageStartupMessages({
  library(haven)
  library(labelled)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(readr)
  library(tibble)
})

if (!dir.exists(file.path("DATA", "SAS"))) {
  stop("Run this script from the Hackathon project folder (DATA/SAS not found ",
       "in ", getwd(), "). Use setwd() or open the RStudio project.")
}

dir_sas       <- file.path("DATA", "SAS")
dir_chirps    <- file.path("DATA", "CHIRPS")
dir_gadm      <- file.path("DATA", "GADM")
dir_dict      <- "Dictionaries"
dir_processed <- file.path("DATA", "processed")
dir_logs      <- file.path(dir_processed, "logs")
dir.create(dir_logs, recursive = TRUE, showWarnings = FALSE)

# Settings
keep_code_columns <- TRUE   # keep <var>_code next to each labelled factor
                            # (useful for joins, e.g. district codes)
max_levels_flag   <- 15     # unlabelled integer vars with <= this many distinct
                            # values are flagged as "probably categorical"


# 1. DICTIONARIES -------------------------------------------------------------

read_dict <- function(path) {
  read_csv(path, col_types = cols(.default = col_character()),
           na = character(), progress = FALSE)
}

rename_map <- read_dict(file.path(dir_dict, "VARIABLE_RENAME_MAP.csv")) |>
  mutate(file_key = str_to_lower(source_filename)) |>
  select(year, season, file_key, original_variable, readable_variable,
         source_question_label, labeling_policy)

value_dict <- read_dict(file.path(dir_dict, "VALUE_LABELS_LOOKUP_ALL_ORIGINAL.csv")) |>
  filter(str_trim(value_label) != "") |>
  mutate(file_key = str_to_lower(basename(source_file))) |>
  distinct(year, season, file_key, variable_name, coded_value, .keep_all = TRUE) |>
  select(year, season, file_key, variable_name, coded_value, value_label)


# 2. HELPERS ------------------------------------------------------------------

# Readable module name from the original file name (names differ by year).
name_module <- function(path) {
  x <- str_to_lower(tools::file_path_sans_ext(basename(path))) |>
    str_replace_all("[^a-z0-9]+", "_")
  case_when(
    str_detect(x, "antierosion|anti_erosion|land_consolidation") ~ "erosion_land_consolidation",
    str_detect(x, "agroforestry")             ~ "agroforestry_screening",
    str_detect(x, "agricultural_practice")    ~ "agricultural_practices",
    str_detect(x, "fertilizer|pesticide")     ~ "fertilizers_pesticides",
    str_detect(x, "land_tenure")              ~ "land_tenure",
    str_detect(x, "crop_production|_production$") ~ "crop_production",
    str_detect(x, "screening")                ~ "crop_screening",
    TRUE                                      ~ x
  )
}

# snake_case name built from a question label, used only when the rename map
# has no entry for a variable.
label_to_name <- function(label, fallback) {
  x <- label |>
    str_remove("^[0-9.]+\\s*") |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9]+", "_") |>
    str_remove_all("^_+|_+$") |>
    str_trunc(60, ellipsis = "")
  ifelse(is.na(x) | x == "", str_to_lower(fallback), x)
}

# Rename, label and decode one SAS data frame. Returns the prepared data plus
# a variable-level log and a table of codes that have no label.
prepare_sas <- function(df, yr, ss, file_key) {
  map_f  <- filter(rename_map, year == yr, season == ss, file_key == !!file_key)
  dict_f <- filter(value_dict, year == yr, season == ss, file_key == !!file_key)

  orig_names <- names(df)
  idx        <- match(orig_names, map_f$original_variable)
  file_lab   <- map_chr(df, \(x) attr(x, "label", exact = TRUE) %||% NA_character_)
  dict_lab   <- map_f$source_question_label[idx]
  var_lab    <- coalesce(na_if(file_lab, ""), na_if(dict_lab, ""))
  policy     <- coalesce(map_f$labeling_policy[idx], "decode_if_value_labels_present")

  new_names <- coalesce(map_f$readable_variable[idx],
                        label_to_name(var_lab, orig_names)) |>
    make.unique(sep = "_")

  out      <- vector("list", length(orig_names))
  log_rows <- vector("list", length(orig_names))
  unl_rows <- list()
  extras   <- list()

  for (i in seq_along(orig_names)) {
    x <- df[[i]]
    if (is.character(x)) x <- na_if(str_trim(x), "")

    # Value labels: file first, dictionary second
    labs <- val_labels(x)
    lab_source <- if (length(labs)) "file" else "none"
    if (!length(labs)) {
      d <- filter(dict_f, variable_name == orig_names[i])
      if (nrow(d)) {
        codes <- if (is.numeric(x)) suppressWarnings(as.numeric(d$coded_value)) else d$coded_value
        ok <- !is.na(codes)
        if (any(ok)) {
          labs <- setNames(codes[ok], d$value_label[ok])
          lab_source <- "dictionary"
        }
      }
    }

    status <- "kept as is"
    unl_codes <- character()

    # Labels that only mark special codes (e.g. 999 = "NA") on a numeric
    # variable: fewer than half of the observed values carry a label.
    obs_vals <- unique(x[!is.na(x)])
    special_codes_only <- length(labs) && is.numeric(x) &&
      length(obs_vals) > 2 && mean(obs_vals %in% labs) < 0.5

    if (policy[i] == "protect_quantitative_or_id" || special_codes_only) {
      # Quantities, weights and IDs stay numeric. Codes labelled as missing
      # ("NA", "Missing") become NA; other special codes are kept and logged.
      na_codes <- labs[str_detect(names(labs), regex("^\\s*(NA|N/A|missing)\\s*$", ignore_case = TRUE))]
      x <- zap_labels(x)
      if (length(na_codes)) x[x %in% na_codes] <- NA
      if (length(labs)) {
        status <- paste0("numeric kept (special-code labels: ",
                         paste0(unname(labs), "=", names(labs), collapse = "; "), ")")
      }
    } else if (length(labs)) {
      unl_codes <- as.character(sort(setdiff(obs_vals, unname(labs))))
      if (length(unl_codes)) {
        tab <- table(as.character(x[!is.na(x) & !(x %in% labs)]))
        unl_rows[[length(unl_rows) + 1]] <- tibble(
          original_variable = orig_names[i], new_variable = new_names[i],
          code = names(tab), n = as.integer(tab))
      }
      if (keep_code_columns) {
        extras[[paste0(new_names[i], "_code")]] <- zap_labels(x)
      }
      # Labelled codes -> factor levels; unlabelled codes keep their code as level
      x <- as_factor(labelled(zap_labels(x), labels = labs), levels = "default")
      status <- paste0("factor (labels from ", lab_source, ")")
    } else if (is.numeric(x) &&
               all(x == round(x), na.rm = TRUE) &&
               n_distinct(x, na.rm = TRUE) <= max_levels_flag &&
               n_distinct(x, na.rm = TRUE) > 1) {
      status <- "no value labels found: looks categorical, review"
    }

    x <- zap_formats(x)
    # NULL (not NA) when there is no label: newer labelled versions reject NA
    var_label(x) <- if (is.na(var_lab[i])) NULL else var_lab[i]
    out[[i]] <- x

    log_rows[[i]] <- tibble(
      original_variable = orig_names[i], new_variable = new_names[i],
      question_label = var_lab[i],
      name_source = if (is.na(idx[i])) "derived from label" else "rename map",
      value_label_source = lab_source, status = status,
      n_unlabelled_codes = length(unl_codes))
  }

  names(out) <- new_names
  prepared <- as_tibble(out)
  if (length(extras)) {
    extras <- extras[setdiff(names(extras), names(prepared))]
    prepared <- bind_cols(prepared, as_tibble(extras))
  }

  list(data = prepared,
       log = bind_rows(log_rows),
       unlabelled = bind_rows(unl_rows))
}


# 3. LOAD + PREPARE ALL SAS FILES ---------------------------------------------

sas_files <- tibble(path = list.files(dir_sas, pattern = "\\.(sav|dta)$",
                                      recursive = TRUE, full.names = TRUE,
                                      ignore.case = TRUE)) |>
  mutate(
    year     = str_extract(path, "(?<=SAS )\\d{4}"),
    season   = str_extract(path, "(?<=Season )[ABC]"),
    module   = name_module(path),
    file_key = str_to_lower(basename(path))
  ) |>
  arrange(year, season, module)

stopifnot(!anyNA(sas_files$year), !anyNA(sas_files$season))
message("SAS files found: ", nrow(sas_files))

file_log <- list(); var_log <- list(); unl_log <- list()

for (k in seq_len(nrow(sas_files))) {
  f <- sas_files[k, ]
  raw <- if (str_detect(f$path, regex("\\.sav$", ignore_case = TRUE))) {
    read_sav(f$path)            # SPSS user-missing codes become NA
  } else {
    read_dta(f$path)
  }

  res <- prepare_sas(raw, f$year, f$season, f$file_key)

  prepared <- res$data |>
    mutate(sas_year = as.integer(f$year), sas_season = f$season,
           sas_module = f$module, .before = 1)

  out_dir <- file.path(dir_processed, "SAS", paste0("SAS_", f$year),
                       paste0("Season_", f$season))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, paste0(f$module, ".rds"))
  saveRDS(prepared, out_file)

  tag <- tibble(year = f$year, season = f$season, module = f$module,
                source_file = basename(f$path))
  var_log[[k]] <- bind_cols(tag, res$log)
  if (nrow(res$unlabelled)) unl_log[[k]] <- bind_cols(tag, res$unlabelled)
  file_log[[k]] <- tag |>
    mutate(rows = nrow(raw), variables_in = ncol(raw),
           variables_out = ncol(prepared),
           renamed_from_map = sum(res$log$name_source == "rename map"),
           factors_file_labels = sum(res$log$value_label_source == "file" &
                                       str_starts(res$log$status, "factor")),
           factors_dict_labels = sum(res$log$value_label_source == "dictionary" &
                                       str_starts(res$log$status, "factor")),
           vars_with_unlabelled_codes = sum(res$log$n_unlabelled_codes > 0),
           categorical_without_labels = sum(str_detect(res$log$status, "looks categorical")),
           output = out_file)

  message(sprintf("[%3d/%d] %s %s %-28s %7d rows | %3d factors",
                  k, nrow(sas_files), f$year, f$season, f$module, nrow(raw),
                  file_log[[k]]$factors_file_labels + file_log[[k]]$factors_dict_labels))
  rm(raw, res, prepared); gc(verbose = FALSE)
}

file_log <- bind_rows(file_log)
var_log  <- bind_rows(var_log)
unl_log  <- bind_rows(unl_log)

write_csv(file_log, file.path(dir_logs, "sas_file_log.csv"), na = "")
write_csv(var_log,  file.path(dir_logs, "sas_variable_log.csv"), na = "")
write_csv(unl_log,  file.path(dir_logs, "sas_unlabelled_codes.csv"), na = "")
write_csv(filter(var_log, str_detect(status, "review|special-code") |
                   n_unlabelled_codes > 0),
          file.path(dir_logs, "sas_variables_to_review.csv"), na = "")


# 4. CHIRPS RAINFALL (district x month, 1981-2025) ----------------------------

chirps_file <- list.files(dir_chirps, pattern = "\\.csv$", full.names = TRUE)[1]

chirps <- read_csv(chirps_file, show_col_types = FALSE) |>
  rename(rainfall_mm = rainfall_total_mm) |>
  mutate(
    # GEE exports Kinyarwanda province names; add the English names SAS uses
    province_en = recode(province,
                         "Umujyi wa Kigali" = "Kigali", "Amajyepfo" = "South",
                         "Iburengerazuba"   = "West",   "Amajyaruguru" = "North",
                         "Iburasirazuba"    = "East", .default = province),
    # SAS seasons: A = Sep-Feb, B = Mar-Jun, C = Jul-Aug
    season = case_when(month %in% c(9:12, 1:2) ~ "A",
                       month %in% 3:6          ~ "B",
                       month %in% 7:8          ~ "C"),
    season_year = if_else(month %in% 9:12, year + 1L, as.integer(year))
  ) |>
  set_variable_labels(
    province = "Province (Kinyarwanda, from GEE boundary layer)",
    province_en = "Province (English, as in SAS)",
    district = "District name",
    chirps_district_code = "District code in GEE boundary layer (not SAS code)",
    year = "Calendar year", month = "Calendar month (1-12)",
    rainfall_mm = "Total monthly rainfall (mm), CHIRPS",
    days_in_month = "Days in month",
    coverage_status = "Coverage status of the monthly total",
    season = "SAS agricultural season (A: Sep-Feb, B: Mar-Jun, C: Jul-Aug)",
    season_year = "Agricultural year the season belongs to"
  )

saveRDS(chirps, file.path(dir_processed, "chirps_district_month.rds"))
message("CHIRPS: ", nrow(chirps), " rows, ", n_distinct(chirps$district), " districts")


# 5. GADM DISTRICT BOUNDARIES (level 2 = 30 districts) ------------------------

if (requireNamespace("sf", quietly = TRUE)) {
  districts_sf <- sf::st_read(file.path(dir_gadm, "gadm41_RWA_2.shp"), quiet = TRUE) |>
    select(province = NAME_1, district = NAME_2, gadm_id = GID_2)
  saveRDS(districts_sf, file.path(dir_processed, "gadm_districts.rds"))
  message("GADM districts: ", nrow(districts_sf))
}


# 6. SUMMARY ------------------------------------------------------------------

cat("\n================ DATA PREPARATION DONE ================\n")
cat("SAS files prepared :", nrow(file_log), "\n")
cat("Variables renamed  :", sum(var_log$name_source == "rename map"), "of", nrow(var_log), "\n")
cat("Factors (file lab) :", sum(file_log$factors_file_labels), "\n")
cat("Factors (dict lab) :", sum(file_log$factors_dict_labels), "\n")
cat("Vars with unlabelled codes      :", sum(file_log$vars_with_unlabelled_codes), "\n")
cat("Categorical-looking, no labels  :", sum(file_log$categorical_without_labels), "\n")
cat("Outputs in", dir_processed, "| logs in", dir_logs, "\n")

# Example:
# ap25B <- readRDS("DATA/processed/SAS/SAS_2025/Season_B/agricultural_practices.rds")
# count(ap25B, district_name_code, plot_irrigated_this_season)
# labelled::look_for(ap25B, "irrig")
