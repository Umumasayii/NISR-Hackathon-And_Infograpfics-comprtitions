# ============================================================================
# SMARTIRRIGATE RWANDA | OFFICIAL NISR FIGURES FROM THE PUBLISHED TABLES
#
# RETIRED (audit 2026-10-20): not run by 09_Run_All.R and not read by 07. The app's
# statistics cover 2019-2025 only, and published figures are now read cell by cell,
# with their table, sheet and cell, by SCRIPTS/14_Official_Reference.R. Kept for the
# record; its output is not used anywhere.
#
# Reads the "Tables_<year> Season <A|B>.xlsx" workbooks NISR publishes with
# each Seasonal Agricultural Survey report and turns every table into one
# long, tidy table. The dashboard uses these official numbers as published.
#
#   Input : DATA/NISR_published/Tables_2026 Season A.xlsx (and Season B ...)
#           Download from statistics.gov.rw > Statistical publications >
#           Agriculture > Seasonal Agricultural Survey. Any later season
#           saved here with the same file name pattern is picked up too.
#   Output: DATA/processed/official/
#           nisr_published.csv          app indicators (see section 5)
#           nisr_published_all_tables.csv   every cell of every table
#
# Table numbers differ between seasons (Season A has two extra GVA tables),
# so tables are matched by their title, never by number. The real number is
# kept in nisr_table.
# ============================================================================

suppressPackageStartupMessages({
  library(readxl); library(dplyr); library(tidyr); library(purrr)
  library(stringr); library(readr); library(tibble)
})

dir_in  <- file.path("DATA", "NISR_published")
dir_out <- file.path("DATA", "processed", "official")
dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

files <- list.files(dir_in, pattern = "^Tables_\\d{4} Season [ABC]\\.xlsx$",
                    full.names = TRUE)
if (!length(files)) stop("No NISR tables found in ", dir_in,
                         " (expected e.g. 'Tables_2026 Season A.xlsx').")


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
  ref  <- str_match(lab, "^(\\d{4})\\s*([ABC])$")
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

read_table <- function(path, sheet, year, season) {
  raw <- suppressMessages(read_excel(path, sheet = sheet, col_names = FALSE,
                                     col_types = "text", .name_repair = "minimal"))
  m <- as.matrix(raw)
  m[!is.na(m)] <- str_squish(m[!is.na(m)])
  m[m == ""] <- NA
  if (!nrow(m)) return(NULL)

  # title row: first cell starting with "Table"
  title_row <- which(apply(m, 1, \(r) any(str_detect(r, "^Table\\s*\\d"), na.rm = TRUE)))[1]
  if (is.na(title_row)) return(NULL)
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

  vals <- data[, value_cols, drop = FALSE]
  keep <- !is.na(col_label) | colSums(!is.na(vals)) > 0
  out <- expand_grid(r = seq_len(nrow(data)), k = which(keep)) |>
    mutate(row_label = data[cbind(r, label_col)],
           column = col_label[k], measure = col_measure[k], category = col_category[k],
           value_text = vals[cbind(r, k)]) |>
    filter(!is.na(value_text) | !is.na(column))

  out |>
    bind_cols(classify_row(out$row_label, year, season)) |>
    filter(!drop, !is.na(value_text)) |>
    mutate(
      source_file = basename(path), workbook = paste0(year, season),
      nisr_table = nisr_table, table_title = title,
      # reference season: from the row (e.g. "2025A"), else from the column
      # (e.g. "2026 B | 2025 B"), else the workbook's season
      col_ref = str_match(coalesce(column, ""), "(\\d{4})\\s*([ABC])\\b"),
      sas_year = coalesce(row_year, as.integer(col_ref[, 2]), as.integer(year)),
      sas_season = coalesce(row_season, col_ref[, 3], season),
      farmer_type = coalesce(row_farmer_type,
                             str_match(coalesce(category, ""), "^(Overall|SSF|LSF)$")[, 2],
                             "All") |> recode(Overall = "All"),
      value = suppressWarnings(as.numeric(value_text)),
      value_note = case_when(value_text == "-" ~ "dash in table (none reported)",
                             value_text == "(NA)" ~ "not applicable in table",
                             TRUE ~ NA_character_),
      unit = coalesce(unit_from(coalesce(measure, "")), unit_from(title)),
      province = unname(district_province[area])
    ) |>
    select(workbook, source_file, nisr_table, table_title, sas_year, sas_season,
           level, province, area, row_item, measure, category, column,
           farmer_type, value, unit, value_note)
}


# 3. ALL TABLES OF ALL WORKBOOKS ---------------------------------------------

all_tables <- map(files, \(f) {
  year   <- str_extract(basename(f), "\\d{4}")
  season <- str_match(basename(f), "Season ([ABC])")[, 2]
  sheets <- excel_sheets(f)
  map(sheets, \(s) read_table(f, s, year, season)) |> bind_rows()
}) |> bind_rows()

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
if (any(n_dist$n != 30)) {
  warning("Tables without all 30 districts: ",
          paste(n_dist$workbook[n_dist$n != 30], n_dist$nisr_table[n_dist$n != 30], collapse = ", "))
}


# 5. APP INDICATORS -------------------------------------------------------------
# Matched by table title and column text, so Season A and B (different table
# numbers) map to the same indicator. Only the "All" farmer type is kept here;
# SSF / LSF splits stay in nisr_published_all_tables.csv.

pick <- function(d, indicator, title_rx, column_rx = NULL, farmer = "All") {
  d |>
    filter(str_detect(table_title, regex(title_rx, ignore_case = TRUE)),
           if (is.null(column_rx)) TRUE
           else str_detect(coalesce(column, ""), regex(column_rx, ignore_case = TRUE)),
           farmer_type %in% farmer) |>
    mutate(indicator = indicator)
}

base <- filter(all_tables, is.na(row_item))   # geography rows only

app <- bind_rows(
  pick(base, "irrig_any_farmer",     "farmers who practiced agricultural practices", "practiced irrigation"),
  pick(base, "anti_erosion_farmers", "farmers who practiced agricultural practices", "against erosion"),
  pick(base, "mechanised_farmers",   "farmers who practiced agricultural practices", "mechanical equipment"),
  pick(base, "agroforestry_farmers", "farmers who practiced agricultural practices", "agroforestry"),
  pick(base, "inorganic_fert",       "use of inorganic fertilizer", "plots in which"),
  pick(base, "organic_fert",         "use of organic fertilizer",   "plots in which"),
  pick(base, "pesticide",            "use of pesticides",           "plots in which"),
  pick(base, "improved_seed_farmers", "use of seeds by farmer type", "farmers who used improved seeds"),
  pick(base, "modern_irrig_area_ha", "area under agricultural practices", "modern irrigated"),
  # land use table is in thousand ha: physical cultivated land -> ha
  pick(base, "cultivated_area_ha",   "agricultural land use per district", "^Physical cultivated land$") |>
    mutate(value = value * 1000, unit = "ha"),
  # share of irrigated plots using a modern technique = 100 - traditional;
  # a row of zeros (no irrigated plot in the sample) stays unknown
  pick(base, "modern_irrig_share",   "types of irrigation used") |>
    group_by(workbook, sas_year, sas_season, area) |>
    mutate(row_total = sum(value, na.rm = TRUE)) |>
    filter(str_detect(column, "^Traditional")) |>
    ungroup() |>
    mutate(value_note = if_else(row_total == 0, "no irrigated plot in the sample", value_note),
           value = if_else(row_total == 0, NA_real_, 100 - value),
           column = "100 - Traditional techniques") |>
    select(-row_total)
)

# Districts left blank in a published table get an explicit NA row
app <- app |>
  group_by(indicator, workbook, nisr_table, table_title, sas_year, sas_season, unit) |>
  complete(level = "district", area = names(district_province)) |>
  ungroup() |>
  mutate(value_note = if_else(is.na(value) & is.na(value_note),
                              "blank in published table", value_note))

# One spelling per crop across tables and seasons
crop_fix <- c("Bananas" = "Banana", "Cooking Banana" = "Cooking banana",
              "Groundnuts" = "Groundnut", "Ground nuts" = "Groundnut",
              "Taro &Yams" = "Yams & Taro", "Taro & Yams" = "Yams & Taro",
              "vegetables" = "Vegetables", "Other Cereals" = "Other cereals")
crop_groups <- c("Cereals", "Tubers and Roots", "Banana", "Legumes and Pulses",
                 "Vegetables and Fruits")
fix_crop <- \(x) { x <- str_squish(x); coalesce(unname(crop_fix[x]), x) }

# Production by crop: national (crop table, with the earlier seasons it
# compares against) and district (crop x district table)
prod_nat <- all_tables |>
  filter(str_detect(table_title, regex("cultivated area, harvested area, production and yield by crop", ignore_case = TRUE)),
         str_detect(coalesce(measure, ""), regex("^Production", ignore_case = TRUE)),
         !is.na(row_item)) |>
  mutate(indicator = "production_t", crop_name = fix_crop(row_item))
prod_dist <- all_tables |>
  filter(str_detect(table_title, regex("crop production by crop type and district", ignore_case = TRUE)),
         level == "district") |>
  mutate(indicator = "production_t", crop_name = fix_crop(column))
# (the national rows of the district table repeat the crop table: not used)

nisr_published <- bind_rows(app, prod_nat, prod_dist) |>
  mutate(crop_name = coalesce(crop_name, NA_character_),
         province = unname(district_province[area]),
         farmer_type = coalesce(farmer_type, "All")) |>
  transmute(indicator, sas_year, sas_season, level, area, value, unit,
            nisr_table = paste0(workbook, " ", nisr_table, ": ", table_title),
            crop_name, crop_group = crop_name %in% crop_groups,
            province, farmer_type, value_note,
            source = paste0("NISR, Seasonal Agricultural Survey ", workbook,
                            ", published tables")) |>
  arrange(indicator, sas_year, sas_season, level != "national", area, crop_name)

dups <- count(nisr_published, indicator, sas_year, sas_season, level, area, crop_name) |> filter(n > 1)
if (nrow(dups)) warning(nrow(dups), " duplicate indicator rows, see `dups`")

write_csv(all_tables,     file.path(dir_out, "nisr_published_all_tables.csv"), na = "")
write_csv(nisr_published, file.path(dir_out, "nisr_published.csv"), na = "")

cat("\nNISR published tables:", n_distinct(paste(all_tables$workbook, all_tables$nisr_table)),
    "tables,", nrow(all_tables), "cells\n")
print(count(nisr_published, indicator, sas_year, sas_season, level), n = Inf)
cat("Saved in", dir_out, "\n")
