# ============================================================================
# SMARTIRRIGATE RWANDA | STEP 1: IMPORT THE ORIGINAL NISR SAS DATA
# Years: 2019-2025 | Seasons: A, B, C
# Author: SmartIrrigate Rwanda project
#
# This script ONLY loads the original datasets into R.
# It does NOT select columns, change variable labels, remove rows, or merge files.
#
# Your expected folder structure is:
# Documents/
#   Hackathon/
#     01_Load_SAS_2019_2025.R
#     SAS/
#       SAS 2019/
#         Season A/   (original .sav files)
#         Season B/
#         Season C/
#       SAS 2020/
#         Season A/   (original .dta files)
#         Season B/
#         Season C/
#       ...
#       SAS 2025/
#         Season A/
#         Season B/
#         Season C/
# ============================================================================

# STEP 1. SET THE WORKING DIRECTORY TO DOCUMENTS/HACKATHON --------------------
# First try the standard Windows Documents folder, then OneDrive Documents.
# If neither works, edit the 'hackathon_folder' line below to your actual path.

hackathon_folder <- file.path(Sys.getenv("USERPROFILE"), "Documents", "Hackathon")

if (!dir.exists(file.path(hackathon_folder, "SAS"))) {
  onedrive_folder <- Sys.getenv("OneDrive")

  if (nzchar(onedrive_folder) &&
      dir.exists(file.path(onedrive_folder, "Documents", "Hackathon", "SAS"))) {
    hackathon_folder <- file.path(onedrive_folder, "Documents", "Hackathon")
  }
}

# If you use another location, uncomment and edit this example:
hackathon_folder <- "C:\\Users\\branc\\OneDrive\\Documenti\\Hackathon"

if (!dir.exists(file.path(hackathon_folder, "SAS"))) {
  stop(
    "Cannot find the SAS folder in Documents/Hackathon.\n",
    "Check the folder location and edit 'hackathon_folder' in STEP 1.\n",
    "Path checked: ", hackathon_folder
  )
}

setwd(hackathon_folder)
sas_folder <- file.path(getwd(), "SAS")
cat("Working directory:", getwd(), "\n")


# STEP 2. INSTALL AND LOAD THE PACKAGE WE NEED -------------------------------
# The haven package reads SPSS (.sav) and Stata (.dta) files.
# It retains the variable labels and categorical value labels in the data.

if (!requireNamespace("haven", quietly = TRUE)) {
  install.packages("haven")
}
library(haven)


# STEP 3. DEFINE YEARS, SEASONS, AND A SIMPLE MODULE NAMING FUNCTION ----------

years   <- 2019:2025
seasons <- c("A", "B", "C")

# Different years use slightly different file names for the same survey module.
# Assign readable list names without changing the ORIGINAL filenames or data.
name_module <- function(file_path) {
  name <- tolower(tools::file_path_sans_ext(basename(file_path)))
  name <- gsub("[^a-z0-9]+", "_", name)

  if (grepl("antierosion|anti_erosion|land_consolidation", name)) {
    return("erosion_land_consolidation")
  }
  if (grepl("agroforestry", name)) {
    return("agroforestry_screening")
  }
  if (grepl("agricultural_practice", name)) {
    return("agricultural_practices")
  }
  if (grepl("fertilizer|pesticide", name)) {
    return("fertilizers_pesticides")
  }
  if (grepl("land_tenure", name)) {
    return("land_tenure")
  }
  if (grepl("crop_production|_production$", name)) {
    return("crop_production")
  }
  if (grepl("screening", name)) {
    return("crop_screening")
  }

  # Unknown future modules still load; the name will come from the source file.
  name
}


# STEP 4. LOAD EVERY ORIGINAL SAS FILE ---------------------------------------
# Result: sas_data[["year"]][["season"]][["module"]]
# Example: sas_data[["2025"]][["B"]][["crop_production"]]
#
# Every column and observation is retained. Missing codes/labels are preserved
# where supported by haven (including SPSS user-defined missing values).

sas_data <- list()
sas_file_log <- data.frame(
  year = integer(),
  season = character(),
  module = character(),
  source_file = character(),
  observations = integer(),
  variables = integer(),
  stringsAsFactors = FALSE
)

for (year in years) {
  year_key <- as.character(year)
  sas_data[[year_key]] <- list()

  for (season in seasons) {
    season_folder <- file.path(
      sas_folder,
      paste("SAS", year),
      paste("Season", season)
    )

    if (!dir.exists(season_folder)) {
      stop("Missing SAS season folder: ", season_folder)
    }

    # Load all original SPSS and Stata modules, not just selected ones.
    data_files <- sort(list.files(
      season_folder,
      pattern = "\\.(sav|dta)$",
      full.names = TRUE,
      ignore.case = TRUE
    ))

    if (length(data_files) == 0L) {
      stop("No .sav or .dta files found in: ", season_folder)
    }

    sas_data[[year_key]][[season]] <- list()

    for (data_file in data_files) {
      module <- name_module(data_file)

      # Avoid overwriting if two different original files share a module name.
      if (module %in% names(sas_data[[year_key]][[season]])) {
        stop("Two files have the same module name in ", season_folder,
             ". Please inspect: ", basename(data_file))
      }

      extension <- tolower(tools::file_ext(data_file))
      dataset <- tryCatch(
        {
          if (extension == "sav") {
            haven::read_sav(data_file, user_na = TRUE)
          } else {
            haven::read_dta(data_file)
          }
        },
        error = function(e) {
          stop("Could not load ", data_file, "\nReason: ", conditionMessage(e))
        }
      )

      sas_data[[year_key]][[season]][[module]] <- dataset

      sas_file_log <- rbind(
        sas_file_log,
        data.frame(
          year = year,
          season = season,
          module = module,
          source_file = basename(data_file),
          observations = nrow(dataset),
          variables = ncol(dataset),
          stringsAsFactors = FALSE
        )
      )

      cat("Loaded: ", year, " / Season ", season, " / ", module,
          " (", nrow(dataset), " rows; ", ncol(dataset), " columns)\n",
          sep = "")
    }
  }
}


# STEP 5. CONFIRM THAT ALL ORIGINAL MODULES LOADED ----------------------------

cat("\n==============================================================\n")
cat("IMPORT COMPLETED\n")
cat("Original SAS files loaded:", nrow(sas_file_log), "\n")
cat("Years:", paste(years, collapse = ", "), "\n")
cat("Seasons: A, B, C\n")
cat("==============================================================\n\n")

# Show the number of original datasets imported for each year and season.
print(as.data.frame(with(sas_file_log, table(year, season))), row.names = FALSE)

# The archive previously shared contained 111 SAS source files.
# Warn if this installation has a different count, but keep the loaded data.
if (nrow(sas_file_log) != 111L) {
  warning("Expected 111 original SAS files; found ", nrow(sas_file_log),
          ". Compare your SAS folders with the source archive.")
}


# STEP 6. HOW TO ACCESS YOUR IMPORTED DATA -----------------------------------

# Display modules available for SAS 2019, Season C:
print(names(sas_data[["2019"]][["C"]]))

# View crop production for SAS 2019, Season C (in RStudio):
# View(sas_data[["2019"]][["C"]][["crop_production"]])

# View irrigation/agricultural practices for SAS 2025, Season B:
# View(sas_data[["2025"]][["B"]][["agricultural_practices"]])

# Inspect original variable names and labels:
# names(sas_data[["2025"]][["B"]][["crop_production"]])
# str(sas_data[["2025"]][["B"]][["crop_production"]])

# Inspect what was loaded: one row per original file.
# View(sas_file_log)

# OPTIONAL: Save the complete imported list for quicker loading next time.
# This is NOT a cleaning or merging step; it stores the imported R objects.
# saveRDS(sas_data, "SAS_original_imported_2019_2025.rds")
# To reload later: sas_data <- readRDS("SAS_original_imported_2019_2025.rds")

# DONE. Next stage (in a separate script): select necessary variables in R.
