# ============================================================================
# SMARTIRRIGATE RWANDA | STEP 2: RENAME VARIABLES + DECODE CATEGORICAL VALUES
# Sources: Original NISR SAS, 2019-2025; Seasons A, B, C
#
# Run after 01_Load_SAS_2019_2025.R (or this script will source Step 1).
# Dictionaries are required in Hackathon/Dictionaries/.
#
# WHAT CHANGES:
#   (1) Rename all source variables using verified source-question labels
#       and the reviewable VARIABLE_RENAME_MAP.csv.
#   (2) Replace categorical numeric codes ONLY where an exact value-label
#       lookup exists for that year, season, source file AND variable.
#   (3) Keep original code columns beside recoded fields.
#   (4) Save a separate RDS per source module, plus audit logs.
#
# WHAT DOES NOT CHANGE:
#   - sas_data (original imported data in memory)
#   - original .sav / .dta files, rows, continuous quantities, survey weights
#   - any code without a verified dictionary definition
#   - no cleaning, harmonizing, selecting, or merging yet
# ============================================================================

# STEP 1. FIND YOUR HACKATHON FOLDER -----------------------------------------
# You can edit this line if your folder is in a different location.

hackathon_folder <- "C:\\Users\\branc\\OneDrive\\Documenti\\Hackathon"


# STEP 2. LOAD ORIGINAL DATA IF STEP 1 HAS NOT ALREADY RUN ---------------------

if (!exists("sas_data", inherits = FALSE) ||
    !exists("sas_file_log", inherits = FALSE)) {
  import_script <- file.path(hackathon_folder, "01_Load_SAS_2019_2025.R")
  if (!file.exists(import_script)) {
    stop("First run 01_Load_SAS_2019_2025.R (Step 1), ",
         "or put that script in Documents/Hackathon.")
  }
  source(import_script, local = FALSE)
}

if (!requireNamespace("haven", quietly = TRUE)) {
  stop("The 'haven' package is required. Run install.packages('haven').")
}

# STEP 3. FIND AND READ BOTH SOURCE-BASED LOOKUP TABLES -----------------------
# Keep the two supplied CSVs in Documents/Hackathon/Dictionaries/.

dictionary_folder <- file.path(hackathon_folder, "Dictionaries")
rename_file <- file.path(dictionary_folder, "VARIABLE_RENAME_MAP.csv")
labels_file <- file.path(dictionary_folder,
                         "VALUE_LABELS_LOOKUP_ALL_ORIGINAL.csv")

if (!file.exists(rename_file) || !file.exists(labels_file)) {
  stop("Dictionaries missing. Extract the ZIP's Dictionaries folder to:\n",
       dictionary_folder)
}

read_dictionary <- function(path) {
  read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
           colClasses = "character", fileEncoding = "UTF-8-BOM",
           na.strings = character(0))
}

rename_lookup <- read_dictionary(rename_file)
value_lookup  <- read_dictionary(labels_file)

# Match dictionaries by *exact source file* + year + season + original field.
# This is crucial: codes and question numbers change across SAS years.
rename_lookup$source_filename <- tolower(rename_lookup$source_filename)
value_lookup$source_filename <- tolower(basename(
  gsub("\\\\", "/", value_lookup$source_file)))

# Blank labels are NOT reliable categorical definitions.
value_lookup <- value_lookup[
  nzchar(trimws(value_lookup$value_label)), , drop = FALSE
]

rename_id <- paste(rename_lookup$year, rename_lookup$season,
                   rename_lookup$source_filename,
                   rename_lookup$original_variable, sep = "|")
label_id <- paste(value_lookup$year, value_lookup$season,
                  value_lookup$source_filename, value_lookup$variable_name,
                  value_lookup$coded_value, sep = "|")
if (!"labeling_policy" %in% names(rename_lookup)) {
  stop("Please use the complete VARIABLE_RENAME_MAP.csv provided with Step 2")
}
if (anyDuplicated(rename_id)) stop("Duplicate rows in VARIABLE_RENAME_MAP.csv")
if (anyDuplicated(label_id)) stop("Conflicting coded values in value-label lookup")

# STEP 4. USER SETTINGS -------------------------------------------------------

keep_original_code_columns <- TRUE   # Recommended for future dataset joining
keep_all_labeled_data_in_memory <- FALSE  # FALSE uses less laptop memory
save_individual_rds <- TRUE

output_folder <- file.path(hackathon_folder, "02_LABELLED_SAS")
dir.create(output_folder, recursive = TRUE, showWarnings = FALSE)

# STEP 5. FUNCTION TO TRANSLATE A CATEGORY WITHOUT GUESSING ------------------

replace_codes_with_labels <- function(values, dictionary_rows) {
  # Dictionary codes are supplied as character strings; original numeric codes
  # are compared numerically to handle 1 versus 1.0 safely.
  numeric_values <- is.numeric(values)
  original_codes <- as.character(values)

  if (numeric_values) {
    dictionary_numbers <- suppressWarnings(
      as.numeric(dictionary_rows$coded_value))
    if (anyNA(dictionary_numbers)) {
      stop("Dictionary has a nonnumeric code for a numeric source field")
    }
    found <- match(as.numeric(values), dictionary_numbers)
  } else {
    found <- match(trimws(original_codes),
                   trimws(dictionary_rows$coded_value))
  }

  missing <- is.na(values)
  known <- !missing & !is.na(found)
  unknown <- !missing & is.na(found)

  human_values <- rep(NA_character_, length(values))
  human_values[known] <- dictionary_rows$value_label[found[known]]
  # Unknown categories remain explicitly identifiable, not silently dropped.
  human_values[unknown] <- paste0("[UNLABELLED CODE: ",
                                  original_codes[unknown], "]")

  if (sum(is.na(human_values)) != sum(missing)) {
    stop("Unexpected change in missingness during value labeling")
  }

  list(values = human_values,
       number_labeled = sum(known),
       number_unlabelled = sum(unknown),
       unknown_codes = if (any(unknown)) {
         as.data.frame(table(original_codes[unknown]),
                       stringsAsFactors = FALSE)
       } else NULL)
}

# STEP 6. TRANSFORM ALL LOADED DATASETS, ONE ORIGINAL MODULE AT A TIME --------

sas_data_readable <- if (keep_all_labeled_data_in_memory) list() else NULL
file_audit <- list()
variable_audit <- list()
unknown_audit <- list()

for (file_number in seq_len(nrow(sas_file_log))) {
  info <- sas_file_log[file_number, , drop = FALSE]
  yr <- as.character(info$year)
  ss <- as.character(info$season)
  module <- as.character(info$module)
  filename <- tolower(as.character(info$source_file))

  original <- sas_data[[yr]][[ss]][[module]]
  if (is.null(original)) stop("Missing imported dataset: ", yr, "/", ss,
                              "/", module)

  # Load only the dictionary entries for this specific source file.
  matched_rename <- rename_lookup[
    rename_lookup$year == yr & rename_lookup$season == ss &
      rename_lookup$source_filename == filename, , drop = FALSE
  ]
  matched_value <- value_lookup[
    value_lookup$year == yr & value_lookup$season == ss &
      value_lookup$source_filename == filename, , drop = FALSE
  ]

  original_names <- names(original)
  mapping_rows <- match(original_names, matched_rename$original_variable)

  # Refuse to guess when a source field is absent from the dictionary.
  if (nrow(matched_rename) == 0L || anyNA(mapping_rows)) {
    stop("Source-to-dictionary mismatch in ", info$source_file, "\n",
         "Unmatched columns: ",
         paste(original_names[is.na(mapping_rows)], collapse = ", "))
  }

  field_map <- matched_rename[mapping_rows, , drop = FALSE]
  readable_names <- field_map$readable_variable

  if (anyDuplicated(readable_names)) {
    stop("Readable variable names collide in ", info$source_file)
  }

  readable <- original
  names(readable) <- readable_names
  decoded_count <- 0L
  unlabelled_observations <- 0L
  extra_code_columns <- 0L

  for (i in seq_along(original_names)) {
    original_name <- original_names[i]
    readable_name <- readable_names[i]
    source_column <- original[[i]]

    dictionary_for_field <- matched_value[
      matched_value$variable_name == original_name, , drop = FALSE
    ]

    status <- "No value labels in dictionary: codes kept unchanged"
    labeled_n <- 0L
    unknown_n <- 0L

    # Only explicitly coded numeric/character variables are decoded.
    # Dates, datetimes, continuous measures and unlabelled IDs stay intact.
    supported_type <- (is.numeric(source_column) ||
                       is.character(source_column) || is.factor(source_column)) &&
      !inherits(source_column, c("Date", "POSIXct", "POSIXlt"))

    if (nrow(dictionary_for_field) > 0L && supported_type &&
        field_map$labeling_policy[i] == "decode_if_value_labels_present") {
      result <- replace_codes_with_labels(source_column,
                                         dictionary_for_field)

      # Retain source numeric codes, especially important for future joins.
      if (keep_original_code_columns) {
        code_name <- paste0(readable_name, "_original_code")
        if (code_name %in% names(readable)) {
          suffix <- 2L
          while (paste0(code_name, "_", suffix) %in% names(readable)) {
            suffix <- suffix + 1L
          }
          code_name <- paste0(code_name, "_", suffix)
        }
        readable[[code_name]] <- source_column
        extra_code_columns <- extra_code_columns + 1L
      }

      # A readable character column replaces the coded column in the copy.
      readable[[readable_name]] <- result$values
      if (nzchar(field_map$source_question_label[i])) {
        attr(readable[[readable_name]], "label") <-
          field_map$source_question_label[i]
      }

      status <- "Decoded using exact original value-label dictionary"
      decoded_count <- decoded_count + 1L
      labeled_n <- result$number_labeled
      unknown_n <- result$number_unlabelled
      unlabelled_observations <- unlabelled_observations + unknown_n

      if (!is.null(result$unknown_codes)) {
        freqs <- result$unknown_codes
        unknown_audit[[length(unknown_audit) + 1L]] <- data.frame(
          year = yr, season = ss, module = module,
          source_file = info$source_file,
          original_variable = original_name,
          readable_variable = readable_name,
          unlabelled_code = as.character(freqs$Var1),
          frequency = as.integer(freqs$Freq),
          stringsAsFactors = FALSE)
      }
    } else if (nrow(dictionary_for_field) > 0L &&
               field_map$labeling_policy[i] == "protect_quantitative_or_id") {
      status <- "Protected numeric/identifier field: source labels need review"
    } else if (nrow(dictionary_for_field) > 0L) {
      status <- "Value labels exist, but field type requires manual review"
    }

    variable_audit[[length(variable_audit) + 1L]] <- data.frame(
      year = yr, season = ss, module = module,
      source_file = info$source_file,
      original_variable = original_name,
      readable_variable = readable_name,
      source_question_label = field_map$source_question_label[i],
      rename_rule = field_map$rename_rule[i],
      labeling_status = status,
      labeled_observations = labeled_n,
      unlabelled_observations = unknown_n,
      stringsAsFactors = FALSE)
  }

  if (nrow(readable) != nrow(original) || anyDuplicated(names(readable))) {
    stop("Unexpected row count or duplicate column names in ", info$source_file)
  }

  destination <- file.path(output_folder, paste0("SAS_", yr),
                           paste0("Season_", ss))
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  if (save_individual_rds) {
    saveRDS(readable, file.path(destination, paste0(module, ".rds")),
            compress = "gzip")
  }

  if (keep_all_labeled_data_in_memory) {
    if (is.null(sas_data_readable[[yr]])) sas_data_readable[[yr]] <- list()
    if (is.null(sas_data_readable[[yr]][[ss]])) {
      sas_data_readable[[yr]][[ss]] <- list()
    }
    sas_data_readable[[yr]][[ss]][[module]] <- readable
  }

  file_audit[[length(file_audit) + 1L]] <- data.frame(
    year = yr, season = ss, module = module,
    source_file = info$source_file,
    rows_before = nrow(original), rows_after = nrow(readable),
    columns_before = ncol(original), columns_after = ncol(readable),
    categorical_columns_decoded = decoded_count,
    extra_original_code_columns = extra_code_columns,
    observed_values_without_dictionary_label = unlabelled_observations,
    stringsAsFactors = FALSE)

  cat(sprintf("[%d/%d] %s / Season %s / %s: %d columns decoded, %d rows\n",
              file_number, nrow(sas_file_log), yr, ss, module,
              decoded_count, nrow(readable)))
  rm(readable)
}

# STEP 7. SAVE REVIEW LOGS ----------------------------------------------------

file_labeling_audit <- do.call(rbind, file_audit)
variable_labeling_audit <- do.call(rbind, variable_audit)

if (length(unknown_audit)) {
  unlabelled_value_audit <- do.call(rbind, unknown_audit)
} else {
  unlabelled_value_audit <- data.frame(
    year = character(), season = character(), module = character(),
    source_file = character(), original_variable = character(),
    readable_variable = character(), unlabelled_code = character(),
    frequency = integer())
}

# These fields are essential for the irrigation dashboard. If any of them
# lack dictionary labels, they need a source-codebook review (not guessing).
priority_fields <- c(
  "province", "district", "farmer_type", "crop_name", "crop_category",
  "irrigation_any_plot_this_season", "plot_irrigated_this_season",
  "irrigation_technique", "irrigation_tool", "irrigation_water_source"
)
priority_review <- variable_labeling_audit[
  variable_labeling_audit$readable_variable %in% priority_fields &
    variable_labeling_audit$labeling_status !=
      "Decoded using exact original value-label dictionary", , drop = FALSE
]

write.csv(file_labeling_audit,
          file.path(output_folder, "FILE_LABELING_AUDIT.csv"), row.names = FALSE,
          na = "")
write.csv(variable_labeling_audit,
          file.path(output_folder, "VARIABLE_RENAMING_AND_LABELING_LOG.csv"),
          row.names = FALSE, na = "")
write.csv(unlabelled_value_audit,
          file.path(output_folder, "UNLABELLED_CODES_TO_REVIEW.csv"),
          row.names = FALSE, na = "")
write.csv(priority_review,
          file.path(output_folder, "PRIORITY_FIELDS_NEEDING_LABEL_REVIEW.csv"),
          row.names = FALSE, na = "")

cat("\nDONE: Original files not modified.\n")
cat("SAS datasets processed:", nrow(file_labeling_audit), "\n")
cat("Output folder:", output_folder, "\n")
cat("Values without verified labels:",
    sum(file_labeling_audit$observed_values_without_dictionary_label), "\n")
cat("Review file:",
    file.path(output_folder, "PRIORITY_FIELDS_NEEDING_LABEL_REVIEW.csv"), "\n")

# STEP 8. CHECK THE RESULT ----------------------------------------------------

# View(file_labeling_audit)
# View(variable_labeling_audit)
# View(priority_review)
#
# Example: open the readable 2025 Season B agricultural-practices module:
# irrigation_2025_B <- readRDS(file.path(
#   output_folder, "SAS_2025", "Season_B", "agricultural_practices.rds"))
# View(irrigation_2025_B)
#
# Example: check old vs new names:
# subset(variable_labeling_audit,
#        year == "2025" & season == "B" &
#          module == "agricultural_practices",
#        select = c(original_variable, readable_variable,
#                   labeling_status))
#
# STOP HERE. We have NOT selected fields, cleaned data, or merged any files.
