# ============================================================================
# 16_Build_Manifest.R  -  record what a build was made from
# SmartIrrigate Rwanda - Team NiyoIshimwe - NISR 2026 Big Data Hackathon
#
# Writes docs/build_manifest.json: build time, git commit, R and package
# versions, and SHA-256 checksums of every input (SAS microdata, NISR workbooks,
# CHIRPS, GADM) and every web output. Only file names, sizes and checksums are
# written: no microdata leaves the computer. Also refreshes
# docs/Reconciliation_Register_2019_2025.csv from SCRIPTS/app/data/official.rds.
# Run from the project root after 09_Run_All.R:  source("SCRIPTS/16_Build_Manifest.R")
# ============================================================================

suppressPackageStartupMessages({ library(dplyr); library(jsonlite) })
source("SCRIPTS/00_Config.R")

# openssl comes with gert (used by 13_Push_To_GitHub.R); sha256sum on Linux/macOS otherwise
sha256 <- function(f) if (requireNamespace("openssl", quietly = TRUE)) {
  con <- file(f, "rb"); on.exit(close(con)); paste(unclass(as.character(openssl::sha256(con))), collapse = "")
} else sub(" .*", "", system2("sha256sum", shQuote(f), stdout = TRUE))
files_of <- function(dir, pattern = NULL) {
  f <- sort(list.files(file.path(dir_root, dir), pattern, recursive = TRUE, full.names = TRUE))
  if (!length(f)) return(list())
  lapply(f, \(x) list(file = sub("^\\./", "", x),
                      bytes = file.size(x), sha256 = sha256(x)))
}
git <- function(...) tryCatch(system2("git", c("-C", dir_root, ...), stdout = TRUE, stderr = FALSE), error = \(e) NA_character_)
meta <- if (file.exists(file.path(dir_app_data, "meta.rds"))) readRDS(file.path(dir_app_data, "meta.rds")) else list()

manifest <- list(
  built = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  data_built = meta$built,
  git_commit = git("rev-parse", "HEAD"), git_branch = git("rev-parse", "--abbrev-ref", "HEAD"),
  git_dirty = length(git("status", "--porcelain", "--untracked-files=no")) > 0,
  r_version = R.version.string, platform = R.version$platform,
  packages = lapply(c("dplyr", "survey", "haven", "ranger", "readxl", "sf", "jsonlite"),
                    \(p) list(package = p, version = tryCatch(as.character(packageVersion(p)), error = \(e) NA))),
  inputs = list(
    sas_microdata = files_of(file.path("DATA", "SAS"), "\\.(sav|dta)$"),
    nisr_published = files_of(file.path("DATA", "NISR_published")),
    chirps = files_of(file.path("DATA", "CHIRPS")),
    gadm = files_of(file.path("DATA", "GADM"))),
  outputs = files_of(file.path("SCRIPTS", "web", "public", "data"), "\\.json$"))
dir.create(file.path(dir_root, "docs"), showWarnings = FALSE)
write_json(manifest, file.path(dir_root, "docs", "build_manifest.json"), auto_unbox = TRUE, pretty = TRUE, na = "null")

# aggregated reconciliation register (published cell vs our estimate); no microdata
off_f <- file.path(dir_app_data, "official.rds")
if (file.exists(off_f)) {
  # national cells with a project value beside them (district cells: DATA/processed/official)
  off <- readRDS(off_f) |> filter(sas_year <= 2025, farmer_type == "All", level == "national", !is.na(project_value))
  keep <- intersect(c("indicator", "sas_year", "sas_season", "level", "area", "crop_name", "is_group", "unit",
                      "nisr_value", "value", "project_value", "gap", "gap_pct", "comparable", "decision", "population",
                      "definition", "measure_label", "project_indicator", "source_title", "source_file", "sheet",
                      "cell", "copies", "revised_from", "rule_note"), names(off))
  reg <- off[keep]
  if (!"nisr_value" %in% names(reg) && "value" %in% names(reg)) reg <- rename(reg, nisr_value = value)
  write.csv(reg, file.path(dir_root, "docs", "Reconciliation_Register_2019_2025.csv"), row.names = FALSE, na = "")
}
message("16 Build manifest: ", length(manifest$inputs$sas_microdata), " SAS files, ",
        length(manifest$outputs), " web outputs, commit ", manifest$git_commit)
