# ============================================================================
# SMARTIRRIGATE RWANDA | NISR PUBLISHED TABLES -> ONE LONG TABLE
#
# Reads every NISR Seasonal Agricultural Survey (SAS) and Agricultural Household
# Survey (AHS) table workbook saved under DATA/NISR_published/ and turns every
# table into one long table, keeping for each number its workbook, sheet, cell,
# table number and title, season, geography, measure and farmer type.
# SCRIPTS/14_Official_Reference.R then picks the figures the app uses.
#
#   Input : DATA/NISR_published/**/*.xlsx (or .xls), downloaded by hand from
#           statistics.gov.rw > Statistical publications > Agriculture. File names
#           only need the survey year (e.g. "SAS 2025_Annual Tables.xlsx",
#           "Tables_2024 Season A.xlsx", "AHS 2024 Tables.xlsx").
#   Output: DATA/processed/official/nisr_published_all_tables.csv
#
# Scope (user rule 2026-10-20/21): statistics 2019-2025 only. Workbooks released
# after 2025 are skipped, and any row whose reference season is after 2025 is
# dropped, so no 2026 figure can enter the app.
# Table numbers differ between releases, so 14 matches tables by title, never by
# number. The real number is kept in nisr_table.
# ============================================================================

suppressPackageStartupMessages({
  library(readxl); library(dplyr); library(tidyr); library(purrr)
  library(stringr); library(readr); library(tibble)
})

dir_root <- Sys.getenv("HACKATHON_ROOT", ".")
dir_in   <- file.path(dir_root, "DATA", "NISR_published")
dir_out  <- file.path(dir_root, "DATA", "processed", "official")
dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)
last_stat_year <- 2025

files <- list.files(dir_in, pattern = "\\.xlsx?$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
files <- files[!startsWith(basename(files), "~$")]                 # Excel lock files
release <- suppressWarnings(as.integer(str_extract(basename(files), "20[0-9]{2}")))
if (any(release > last_stat_year, na.rm = TRUE))
  message("Skipped (released after ", last_stat_year, "): ",
          paste(basename(files[release > last_stat_year & !is.na(release)]), collapse = ", "))
files <- files[!is.na(release) & release <= last_stat_year]
if (!length(files)) stop("No NISR table workbooks for 2019-", last_stat_year, " in ", dir_in)

# Excel column letters for the cell reference of every value
col_letter <- function(j) vapply(j, \(k) { s <- ""; while (k > 0) { r <- (k - 1) %% 26
  s <- paste0(LETTERS[r + 1], s); k <- (k - 1) %/% 26 }; s }, character(1))


# 1. GEOGRAPHY ----------------------------------------------------------------

district_province <- c(
  Nyarugenge = "Kigali", Gasabo = "Kigali", Kicukiro = "Kigali",
  Nyanza = "South", Gisagara = "South", Nyaruguru = "South", Huye = "South",
  Nyamagabe = "South", Ruhango = "South", Muhanga = "South", Kamonyi = "South",
  Karongi = "West", Rutsiro = "West", Rubavu = "West", Nyabihu = "West",
  Ngororero = "West", Rusizi = "West", Nyamasheke = "West",
  Rulindo = "North", Gakenke = "North", Musanze = "North", Burera = "North",
  Gicumbi = "North",
  Rwamagana = "East", Nyagatare = "East", Gatsibo = "East", Kayonza = "East",
  Kirehe = "East", Ngoma = "East", Bugesera = "East")

# Row label -> geography / farmer type / reference season
classify_row <- function(label, year, season) {
  lab <- str_squish(label)
  low <- str_to_lower(lab)
  # exact name first, then a spelling slip of up to 2 letters ("Nyarugenege")
  dn   <- str_to_lower(names(district_province))
  dist <- map_chr(low, \(x) {
    if (is.na(x)) return(NA_character_)
    if (x %in% dn) return(names(district_province)[match(x, dn)])
    if (nchar(x) < 5) return(NA_character_)
    d <- adist(x, dn)[1, ]
    if (min(d) <= 2 && sum(d == min(d)) == 1) names(district_province)[which.min(d)] else NA_character_
  })
  # "2025A", or "National 2021 A" (national row with the season it refers to)
  ref  <- str_match(lab, "^(?:(?:National|Rwanda|Total)\\s*)?(\\d{4})\\s*([ABC])$")
  tibble(
    level = case_when(!is.na(dist) ~ "district",
                      TRUE ~ "national"),
    area = coalesce(dist, "Rwanda"),
    row_item = case_when(
      !is.na(dist) ~ NA_character_,
      low %in% c("national", "total", "s/total", "rwanda", "ssf", "lsf") ~ NA_character_,
      !is.na(ref[, 1]) ~ NA_character_,
      TRUE ~ lab),
    row_farmer_type = case_when(low == "ssf" ~ "SSF", low == "lsf" ~ "LSF",
                                TRUE ~ NA_character_),
    row_year = if_else(!is.na(ref[, 1]), as.integer(ref[, 2]), NA_integer_),
    row_season = if_else(!is.na(ref[, 1]), ref[, 3], NA_character_),
    drop = low %in% c("change") | str_detect(low, "^source"))
}


# 2. READ ONE TABLE -------------------------------------------------------------

clean_title <- function(x) {
  x |>
    str_remove("^\\s*Table\\s*\\d+\\s*:?\\s*") |>
    str_remove("^\\d{4}\\s*Season\\s*[ABC]\\s*_\\s*") |>
    str_remove("^Season\\s*[ABC]\\s*\\d{4}\\s*_\\s*") |>
    str_squish()
}

unit_from <- function(txt) {
  t <- str_to_lower(txt)
  case_when(
    str_detect(t, "\\(,000\\s*ha\\)") ~ "thousand ha",
    str_detect(t, "\\(mt/ha\\)")      ~ "t/ha",
    str_detect(t, "\\(kg/ha\\)")      ~ "kg/ha",
    str_detect(t, "\\(mt\\)")         ~ "t",
    str_detect(t, "\\(ha\\)")         ~ "ha",
    str_detect(t, "frw\\s*/ha")       ~ "Frw/ha",
    str_detect(t, "percentage|\\(%\\)|%\\)|%") ~ "%",
    TRUE ~ NA_character_)
}

read_table <- function(path, sheet, year, season, survey) {
  # range from A1 so that leading blank rows and columns are kept: cell references
  # then match what a reader sees in Excel
  raw <- suppressMessages(read_excel(path, sheet = sheet, col_names = FALSE, col_types = "text",
                                     range = cellranger::cell_limits(c(1, 1), c(NA, NA)),
                                     .name_repair = "minimal"))
  m <- as.matrix(raw)
  m[!is.na(m)] <- str_squish(m[!is.na(m)])
  m[m == ""] <- NA
  if (!nrow(m)) return(NULL)

  # title row: first cell starting with "Table"
  title_row <- which(apply(m, 1, \(r) any(str_detect(r, "^Table\\s*\\d"), na.rm = TRUE)))[1]
  if (is.na(title_row)) return(NULL)
  # a season named in the title or sheet ("Season A") applies to the whole table
  ttl_season <- str_match(paste(sheet, paste(na.omit(m[title_row, ]), collapse = " ")),
                          "[Ss]eason\\s*([ABC])(?![A-Za-z])")[, 2]
  if (is.na(season)) season <- ttl_season
  title <- clean_title(paste(na.omit(m[title_row, ]), collapse = " "))
  nisr_table <- str_extract(paste(na.omit(m[title_row, ]), collapse = " "), "Table\\s*\\d+") |>
    str_remove_all("\\s")

  # label column = first column with any text after the title
  body <- m[(title_row + 1):nrow(m), , drop = FALSE]
  label_col <- which(colSums(!is.na(body)) > 0)[1]
  is_num <- \(x) !is.na(suppressWarnings(as.numeric(x))) | x %in% c("-", "(NA)")
  is_data <- apply(body, 1, \(r) {
    lab <- r[label_col]
    vals <- r[-seq_len(label_col)]
    !is.na(lab) && !str_detect(lab, "^Source") &&
      is.na(suppressWarnings(as.numeric(lab))) && any(is_num(vals[!is.na(vals)]))
  })
  first_data <- which(is_data)[1]
  if (is.na(first_data)) return(NULL)
  header <- body[seq_len(first_data - 1), , drop = FALSE]
  data   <- body[is_data, , drop = FALSE]

  # header: fill merged group cells to the right on every row but the last
  value_cols <- (label_col + 1):ncol(m)
  if (nrow(header) > 1) {
    for (i in seq_len(nrow(header) - 1)) {
      cur <- NA
      for (j in value_cols) {
        if (!is.na(header[i, j])) cur <- header[i, j] else header[i, j] <- cur
      }
    }
  }
  col_label <- map_chr(value_cols, \(j) {
    parts <- unique(na.omit(header[, j]))
    parts <- parts[!str_detect(parts, "^(District|Crops?|Crop/Groups|District/Crop|Stratum|Year)$")]
    if (!length(parts)) NA_character_ else paste(parts, collapse = " | ")
  })
  # measure = top header part, category = bottom part (when two levels)
  col_measure  <- map_chr(value_cols, \(j) {
    p <- na.omit(header[, j]); p <- p[!str_detect(p, "^(District|Crops?|Crop/Groups|District/Crop|Year)$")]
    if (length(p)) p[1] else NA_character_ })
  col_category <- map_chr(value_cols, \(j) {
    p <- na.omit(header[, j]); p <- p[!str_detect(p, "^(District|Crops?|Crop/Groups|District/Crop|Year)$")]
    if (length(p) > 1) p[length(p)] else NA_character_ })

  data_rows <- title_row + which(is_data)                     # row numbers in the sheet
  # a label row without numbers below the header is a section ("Cultivated area for
  # major crops (Ha)"): it is kept with each data row under it
  sec_lab <- ifelse(!is_data & seq_len(nrow(body)) > first_data & !is.na(body[, label_col]),
                    body[, label_col], NA_character_)
  section <- vapply(which(is_data), \(i) { s <- sec_lab[seq_len(i)]; s <- s[!is.na(s)]
    if (length(s)) s[length(s)] else NA_character_ }, character(1))
  vals <- data[, value_cols, drop = FALSE]
  keep <- !is.na(col_label) | colSums(!is.na(vals)) > 0
  out <- expand_grid(r = seq_len(nrow(data)), k = which(keep)) |>
    mutate(row_label = data[cbind(r, label_col)],
           column = col_label[k], measure = col_measure[k], category = col_category[k],
           value_text = vals[cbind(r, k)],
           cell = paste0(col_letter(value_cols[k]), data_rows[r]),
           section = section[r]) |>
    filter(!is.na(value_text) | !is.na(column))

  out |>
    bind_cols(classify_row(out$row_label, year, season)) |>
    filter(!drop, !is.na(value_text)) |>
    mutate(
      survey = survey, source_file = basename(path), sheet = sheet, workbook = paste0(year, coalesce(season, "")),
      nisr_table = nisr_table, table_title = title,
      # reference season: from the row (e.g. "2025A"), else from the column
      # (e.g. "2025 B" or "Season B"), else the workbook's season
      col_ref = str_match(coalesce(column, ""), "(20\\d{2})\\s*([ABC])(?![A-Za-z])"),
      # summary tables: "SAS 2023 | Season | A"
      col_year = as.integer(str_match(coalesce(column, ""), "\\b(20\\d{2})\\b")[, 2]),
      col_season = coalesce(str_match(coalesce(column, ""), "[Ss]eason\\s*([ABC])(?![A-Za-z])")[, 2],
                            str_match(coalesce(column, ""), "(?:^|\\|)\\s*([ABC])\\s*$")[, 2]),
      sas_year = coalesce(row_year, as.integer(col_ref[, 2]), col_year, as.integer(year)),
      sas_season = coalesce(row_season, col_ref[, 3], col_season, season),
      farmer_type = coalesce(row_farmer_type,
                             str_match(coalesce(category, ""), "^(Overall|SSF|LSF)$")[, 2],
                             str_match(coalesce(column, ""), "\\b(SSF|LSF)\\b")[, 2],
                             "All") |> recode(Overall = "All"),
      value = suppressWarnings(as.numeric(str_remove_all(value_text, "[,%\\s]"))),
      value_note = case_when(value_text == "-" ~ "dash in table (none reported)",
                             value_text == "(NA)" ~ "not applicable in table",
                             TRUE ~ NA_character_),
      unit = coalesce(unit_from(coalesce(measure, "")), unit_from(title)),
      province = unname(district_province[area])
    ) |>
    select(survey, workbook, source_file, sheet, cell, nisr_table, table_title, sas_year, sas_season,
           level, province, area, section, row_item, measure, category, column,
           farmer_type, value, unit, value_note)
}


# 3. ALL TABLES OF ALL WORKBOOKS ---------------------------------------------

all_tables <- map(files, \(f) {
  nm     <- basename(f)
  year   <- str_extract(nm, "20[0-9]{2}")
  season <- str_match(nm, "[Ss]eason\\s*([ABC])(?![A-Za-z])")[, 2]
  survey <- if (str_detect(str_to_upper(nm), "AHS|HOUSEHOLD")) "AHS" else "SAS"
  map(excel_sheets(f), \(s) tryCatch(read_table(f, s, year, season, survey), error = \(e) {
    warning(nm, " / ", s, ": ", conditionMessage(e)); NULL })) |> bind_rows()
}) |> bind_rows() |>
  # earlier seasons printed beside the current one are kept (same scope), later never
  filter(sas_year <= last_stat_year)

# Table 5 (sampling errors) mixes units by column
all_tables <- all_tables |>
  mutate(unit = case_when(
    str_detect(table_title, "^Sampling [Ee]rrors") & str_detect(coalesce(column, ""), "CV|DEFF") ~ "ratio",
    str_detect(table_title, "^Sampling [Ee]rrors") & str_detect(coalesce(column, ""), "observations") ~ "plots",
    str_detect(table_title, "^Sampling [Ee]rrors") ~ "ha",
    str_detect(table_title, "^Number of segments|^Allocation of") ~ "segments",
    TRUE ~ unit))


# 4. CHECKS -------------------------------------------------------------------

n_dist <- all_tables |> filter(level == "district") |>
  group_by(workbook, nisr_table) |> summarise(n = n_distinct(area), .groups = "drop")
if (any(n_dist$n != 30))
  message("Tables without all 30 districts (check the layout): ",
          paste(n_dist$workbook[n_dist$n != 30], n_dist$nisr_table[n_dist$n != 30], collapse = ", "))
no_season <- all_tables |> filter(survey == "SAS", is.na(sas_season)) |> distinct(source_file, nisr_table)
if (nrow(no_season))
  warning("SAS tables with no season found (named neither in file, sheet, title, row nor column): ",
          paste(no_season$source_file, no_season$nisr_table, collapse = "; "))

write_csv(all_tables, file.path(dir_out, "nisr_published_all_tables.csv"), na = "")
cat("\nNISR published tables:", n_distinct(paste(all_tables$source_file, all_tables$sheet)),
    "sheets,", nrow(all_tables), "cells, seasons",
    paste(sort(unique(paste0(all_tables$sas_year, coalesce(all_tables$sas_season, "")))), collapse = " "), "\n")
cat("Saved in", dir_out, "\n")
