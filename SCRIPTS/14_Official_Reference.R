# ============================================================================
# 14_Official_Reference.R  -  published NISR figures, read cell by cell
# SmartIrrigate Rwanda - Team NiyoIshimwe
#
# Reads the official workbooks named in DATA/NISR_published/official_cell_map.csv
# and records, for every mapped figure, the workbook, sheet, cell, population and
# definition. Nothing here is written into our survey estimates: the published
# figures form a separate layer that the app shows beside ours only when the
# definition is the same.
#
# Scope: statistics for 2019-2025 only. Workbooks released after 2025 (for
# example the SAS 2026 tables) are not read unless allow_later_releases = TRUE,
# and even then their rows stay "cross-check only" and never reach the app.
#
# Inputs : DATA/NISR_published/official_cell_map.csv   (the register of cells)
#          DATA/NISR_published/*.xlsx                  (official workbooks, downloaded by hand)
# Outputs: DATA/processed/official/official_cells.csv     every mapped cell + status
#          DATA/processed/official/official_reference.csv rows the app may show
# Statuses: "read from workbook" | "workbook missing" | "sheet missing" |
#           "empty cell" | "later release, not read" | "no cell mapped"
# ============================================================================

suppressPackageStartupMessages({ library(dplyr); library(readr); library(readxl); library(stringr) })

dir_root <- Sys.getenv("HACKATHON_ROOT", ".")
dir_pub  <- file.path(dir_root, "DATA", "NISR_published")
dir_out  <- file.path(dir_root, "DATA", "processed", "official")
dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

last_stat_year       <- 2025
allow_later_releases <- FALSE

map <- read_csv(file.path(dir_pub, "official_cell_map.csv"), show_col_types = FALSE,
                col_types = cols(.default = col_character()))

# the release year is the first 20xx in the workbook name
release_year <- function(pattern) suppressWarnings(as.integer(str_extract(pattern, "20[0-9]{2}")))

find_workbook <- function(pattern) {
  hits <- list.files(dir_pub, pattern = utils::glob2rx(pattern), ignore.case = TRUE, full.names = TRUE)
  hits <- hits[!startsWith(basename(hits), "~$")]          # Excel lock files
  if (length(hits)) sort(hits)[1] else NA_character_
}

read_cell <- function(path, sheet_re, cell) {
  sheets <- excel_sheets(path)
  sh <- sheets[str_detect(str_squish(sheets), regex(sheet_re, ignore_case = TRUE))]
  if (!length(sh)) return(list(value = NA_character_, sheet = NA_character_, status = "sheet missing"))
  v <- read_excel(path, sheet = sh[1], range = cell, col_names = FALSE, col_types = "text", .name_repair = "minimal")
  v <- if (nrow(v) && ncol(v)) str_squish(as.character(v[[1]][1])) else NA_character_
  list(value = v, sheet = sh[1], status = if (is.na(v) || !nzchar(v)) "empty cell" else "read from workbook")
}

cells <- map |>
  mutate(release_year = release_year(workbook_pattern),
         workbook = vapply(workbook_pattern, find_workbook, character(1)))

res <- lapply(seq_len(nrow(cells)), function(i) {
  r <- cells[i, ]
  if (is.na(r$cell) || !nzchar(r$cell)) return(list(value = NA_character_, sheet = NA_character_, status = "no cell mapped"))
  if (!is.na(r$release_year) && r$release_year > last_stat_year && !allow_later_releases)
    return(list(value = NA_character_, sheet = NA_character_, status = "later release, not read"))
  if (is.na(r$workbook)) return(list(value = NA_character_, sheet = NA_character_, status = "workbook missing"))
  tryCatch(read_cell(r$workbook, r$sheet_pattern, r$cell),
           error = \(e) list(value = NA_character_, sheet = NA_character_, status = paste("read error:", conditionMessage(e))))
})

cells <- cells |>
  mutate(value_text = vapply(res, `[[`, character(1), "value"),
         sheet      = vapply(res, `[[`, character(1), "sheet"),
         status     = vapply(res, `[[`, character(1), "status"),
         value      = suppressWarnings(as.numeric(str_remove_all(value_text, "[,%\\s]"))),
         audit_value = suppressWarnings(as.numeric(audit_value)),
         # does the cell hold what the audit reported? (a check on the cell map itself)
         matches_audit = ifelse(is.na(value) | is.na(audit_value), NA,
                                abs(value - audit_value) <= 0.051 * pmax(1, abs(audit_value) / 100)),
         workbook = basename(workbook), sas_year = as.integer(sas_year))

write_csv(cells, file.path(dir_out, "official_cells.csv"), na = "")

# what the app may show: read from a 2019-2025 release, same definition as ours
reference <- cells |>
  filter(status == "read from workbook", !is.na(value), sas_year <= last_stat_year,
         is.na(release_year) | release_year <= last_stat_year,
         same_definition == "TRUE") |>
  transmute(indicator = app_indicator, sas_year, sas_season, level, area, crop_name, value, unit,
            population, definition = definition_official, same_definition = TRUE,
            source_title, source_url, table = str_extract(source_title, "Table ?[0-9]+"),
            sheet, cell, status, register_id)
write_csv(reference, file.path(dir_out, "official_reference.csv"), na = "")

message("14 Official reference: ", sum(cells$status == "read from workbook"), " of ", nrow(cells),
        " mapped cells read; ", nrow(reference), " rows the app may show")
print(count(cells, family, status), n = 50)
if (any(cells$matches_audit %in% FALSE))
  warning("Some cells do not hold the value the audit reported; check the cell map: ",
          paste(cells$register_id[cells$matches_audit %in% FALSE], collapse = ", "))
