# ============================================================================
# 10_AHS_Preparation.R  -  Agricultural Household Survey (AHS) 2017, 2020, 2024
# SmartIrrigate Rwanda - Team NiyoIshimwe - NISR 2026 Big Data Hackathon
#
# INPUT : DATA/Agriculture Household Survey/{2017,2020,2024}/*.dta  (NISR microdata)
# OUTPUT: DATA/processed/ahs/
#   clean/ahs<year>_<module>.rds   one clean table per survey module (renamed,
#                                  labelled factors, hidden missing codes removed,
#                                  multi-response slots reshaped, flags added)
#   ahs_household.rds              ONE harmonised household table, all years
#   ahs_members.rds                harmonised household members, all years
#   ahs_extension.rds              extension services received (long), all years
#   ahs_irrigation_detail.rds      technique / water source / tool among irrigators
#   ahs_indicators.rds             survey-weighted % with 95% CI, n, CV, reliability
#                                  (national, province, district, by year) - same
#                                  columns as SCRIPTS/app/data/est_plot.rds
#   ahs_variable_dictionary.csv    every source variable: year, file, name, new name,
#                                  label, value labels (documentation + AI disclosure)
#   logs/ahs_cleaning_log.csv      every recode, with the number of values touched
#   logs/ahs_checks.csv            consistency checks (pass / flagged counts)
#
# Run from the Hackathon project root:  source("SCRIPTS/10_AHS_Preparation.R")
#
# Design notes (decisions to review are marked DECISION):
#   * The three rounds use different samples: 2017 = SAS 2017 segments (PSU =
#     segment), 2020 = stand-alone sample (no PSU in the file), 2024 = EICV7
#     sub-sample (PSU = cluster). None link to the SAS 2019-2025 plots at
#     household level, so AHS joins the dashboard by district and year.
#   * Codes are harmonised by LABEL, never by number (e.g. "Drip irrigation" is
#     code 3 in 2017 and code 4 in 2020).
#   * Household indicators use ALL farm (agricultural) households as the denominator
#     (user decision 2026-10-14); farm households that grew no crops count as "no".
#   * 2024 is a series break (plot-level questions, EICV7 sample): every 2024
#     estimate carries series_break = TRUE (user decision 2026-10-14).
# ============================================================================

source(file.path(Sys.getenv("HACKATHON_ROOT", "."), "SCRIPTS", "00_Config.R"))
suppressPackageStartupMessages({ library(haven); library(lubridate) })
t0 <- Sys.time()

dir_ahs_raw <- file.path(dir_root, "DATA", "Agriculture Household Survey")
dir_ahs     <- file.path(dir_root, "DATA", "processed", "ahs")
dir_ahs_cl  <- file.path(dir_ahs, "clean")
dir_ahs_log <- file.path(dir_ahs, "logs")
for (d in c(dir_ahs, dir_ahs_cl, dir_ahs_log)) dir.create(d, showWarnings = FALSE, recursive = TRUE)

ahs_files <- list(
  `2017` = c(s0 = "S0_General Information.dta",
             s1 = "S1_Household members characteristics.dta",
             s3 = "S3_Extension services and agricultural programmes.dta",
             s5 = "S5_Agricultural Inputs.dta",
             s6 = "S6_Agricultural Practices.dta",
             s8a = "S8_A_Production Use,storage and Expenses.dta",
             s8b = "S8_B_Production Use,Storage and Expenses.dta"),
  `2020` = c(s0 = "Rwa_AHS_2020_Section_0.dta", s1 = "Rwa_AHS_2020_Section_1.dta",
             s21 = "Rwa_AHS_2020_Section_2.1.dta", s22 = "Rwa_AHS_2020_Section_2.2.dta",
             s23 = "Rwa_AHS_2020_Section_2.3.dta", s31 = "Rwa_AHS_2020_Section_3.1.dta",
             s32 = "Rwa_AHS_2020_Section_3.2.dta", s4 = "Rwa_AHS_2020_Section_4.dta"),
  `2024` = c(s0 = "AHS2024_Section0.dta",
             s1 = "AHS2024_Section1_HOUSEHOLD MEMBERS CHARACTERISTICS.dta",
             s34 = "AHS2024_Section3_4_CROP GROWN, SEEDS AND PRODUCTION & AGRICULTURAL INPUTS AND PRACTICES.dta",
             s6 = "AHS2024_Section6_EXTENSION SERVICES AND AGRICULTURAL PROGRAMMES.dta",
             s8 = "AHS2024_Section8_SUSTAINABLE AGRICULTURE.dta"))

# ---- 0. HELPERS ----------------------------------------------------------------
# Cleaning log: every recode is recorded with the number of values it touched.
.log <- new.env(); .log$rows <- list(); .log$ctx <- ""
set_ctx <- function(x) .log$ctx <- x
log_fix <- function(variable, rule, n, detail = "") {
  if (n > 0) .log$rows[[length(.log$rows) + 1]] <- tibble(
    table = .log$ctx, variable = variable, rule = rule, detail = detail, n_values = as.integer(n))
}
.chk <- new.env(); .chk$rows <- list()
check <- function(name, n_flagged, n_total, action) {
  .chk$rows[[length(.chk$rows) + 1]] <- tibble(
    table = .log$ctx, check = name, n_flagged = as.integer(n_flagged), n_total = as.integer(n_total), action = action)
  invisible(n_flagged)
}

# Dictionary of every raw variable (written to CSV at the end)
.dict <- new.env(); .dict$rows <- list()
read_ahs <- function(year, module) {
  f <- file.path(dir_ahs_raw, year, ahs_files[[year]][[module]])
  if (!file.exists(f)) { warning("Missing AHS file: ", f); return(NULL) }
  d <- tryCatch(read_dta(f), error = \(e) read_dta(f, encoding = "latin1"))  # 2024 S6 has CP1252 labels
  .dict$rows[[length(.dict$rows) + 1]] <- tibble(
    year = as.integer(year), module = module, file = basename(f), variable = names(d),
    label = map_chr(d, \(x) str_squish(coalesce(attr(x, "label", exact = TRUE), ""))),
    value_labels = map_chr(d, \(x) { l <- attr(x, "labels"); if (is.null(l)) "" else
      paste(paste0(l, "=", str_squish(names(l))), collapse = "; ") }))
  set_ctx(paste0("ahs", year, "_", module))
  d
}

na_label_rx <- "^(NA|N/A|Not applicable)$"
dk_label_rx <- "^(Don.?t know|Do not know|Don\\?t know|Unkown.*|Unknown.*)$"
fix_text <- function(x) x |> str_replace_all("Â | ", " ") |> str_replace_all("Â½", "1/2") |>
  str_replace_all("\u0085", "...") |> str_squish()

# Labelled categorical -> factor. Codes labelled "NA" and codes with no label are set
# to missing (logged). "Don't know" stays a level unless dk_to_na = TRUE.
# `labels` lets one variable borrow another's value labels (2017 Season A slots).
as_cat <- function(x, var = deparse(substitute(x)), dk_to_na = FALSE, labels = NULL) {
  lab <- labels %||% attr(x, "labels")
  v <- as.numeric(zap_labels(x))
  if (is.null(lab)) return(v)
  names(lab) <- fix_text(names(lab))
  bad_na <- v %in% lab[str_detect(names(lab), regex(na_label_rx, ignore_case = TRUE))]
  log_fix(var, "code labelled NA -> missing", sum(bad_na))
  v[bad_na] <- NA
  if (dk_to_na) {
    dk <- v %in% lab[str_detect(names(lab), regex(dk_label_rx, ignore_case = TRUE))]
    log_fix(var, "Don't know -> missing", sum(dk)); v[dk] <- NA
  }
  unl <- !is.na(v) & !(v %in% lab)
  log_fix(var, "unlabelled code -> missing", sum(unl), paste(sort(unique(v[unl])), collapse = ","))
  v[unl] <- NA
  lab <- lab[!duplicated(lab)]
  lab <- lab[!str_detect(names(lab), regex(na_label_rx, ignore_case = TRUE))]
  factor(v, levels = unname(lab), labels = names(lab))
}

# Yes/No (1/2) -> 1/0 integer
as_yn <- function(x, var = deparse(substitute(x))) {
  v <- as.numeric(zap_labels(x))
  odd <- !is.na(v) & !(v %in% c(1, 2))
  log_fix(var, "non Yes/No code -> missing", sum(odd), paste(sort(unique(v[odd])), collapse = ","))
  case_when(v == 1 ~ 1L, v == 2 ~ 0L, TRUE ~ NA_integer_)
}

# Numeric with listed missing codes. Also turns negative values into missing.
as_num <- function(x, var = deparse(substitute(x)), na_codes = numeric(), max_ok = Inf) {
  v <- suppressWarnings(as.numeric(zap_labels(x)))
  hit <- v %in% na_codes; log_fix(var, "missing-value code -> missing", sum(hit), paste(na_codes, collapse = ",")); v[hit] <- NA
  neg <- !is.na(v) & v < 0; log_fix(var, "negative -> missing", sum(neg)); v[neg] <- NA
  big <- !is.na(v) & v > max_ok; log_fix(var, "implausible (> max) -> missing", sum(big), paste0("max=", max_ok)); v[big] <- NA
  v
}

blank_to_na <- function(x) { x <- str_squish(as.character(x)); x[x %in% c("", ".", "_", "0")] <- NA; x }

# Multi-response slot columns (var_1, var_2, ...) -> long table of chosen labels
slots_long <- function(d, id, cols, value_name, labels = NULL, drop_codes = c(0), raw = FALSE) {
  cols <- intersect(cols, names(d))
  if (!length(cols)) return(tibble())
  lab <- if (raw) NULL else labels %||% (attr(d[[cols[1]]], "labels"))
  d |> select(all_of(c(id, cols))) |>
    mutate(across(all_of(cols), \(x) as.numeric(zap_labels(x)))) |>
    pivot_longer(all_of(cols), names_to = "slot", values_to = "code") |>
    filter(!is.na(code), !code %in% drop_codes) |>
    mutate(!!value_name := if (is.null(lab)) as.character(code) else
      fix_text(names(lab)[match(code, lab)]),
      slot = as.integer(str_extract(slot, "[0-9]+$"))) |>
    filter(!is.na(.data[[value_name]]), !str_detect(.data[[value_name]], regex(na_label_rx, ignore_case = TRUE)))
}

# Packed multi-select strings: "1235" (single digits) or "ADF" (letters) -> codes
split_codes <- function(x, letters_to_num = FALSE) {
  x <- blank_to_na(x)
  map(x, \(s) {
    if (is.na(s)) return(integer())
    ch <- str_split(str_remove_all(s, "[^0-9A-Za-z]"), "")[[1]]
    if (letters_to_num) match(toupper(ch), LETTERS) else as.integer(ch)
  })
}
# Packed household-member codes ("0102" = members 1 and 2; "102" = 1 and 2)
split_members <- function(x) {
  x <- blank_to_na(x)
  map(x, \(s) {
    if (is.na(s)) return(integer())
    s <- str_remove_all(s, "[^0-9]")
    if (nchar(s) %% 2 == 1) s <- paste0("0", s)
    as.integer(substring(s, seq(1, nchar(s), 2), seq(2, nchar(s), 2)))
  })
}

district_names <- c(`11` = "Nyarugenge", `12` = "Gasabo", `13` = "Kicukiro", `21` = "Nyanza", `22` = "Gisagara",
  `23` = "Nyaruguru", `24` = "Huye", `25` = "Nyamagabe", `26` = "Ruhango", `27` = "Muhanga", `28` = "Kamonyi",
  `31` = "Karongi", `32` = "Rutsiro", `33` = "Rubavu", `34` = "Nyabihu", `35` = "Ngororero", `36` = "Rusizi",
  `37` = "Nyamasheke", `41` = "Rulindo", `42` = "Gakenke", `43` = "Musanze", `44` = "Burera", `45` = "Gicumbi",
  `51` = "Rwamagana", `52` = "Nyagatare", `53` = "Gatsibo", `54` = "Kayonza", `55` = "Kirehe", `56` = "Ngoma",
  `57` = "Bugesera")
province_names <- c(`1` = "Kigali", `2` = "South", `3` = "West", `4` = "North", `5` = "East")
# Province and district from the NISR district code (same names as the SAS master tables)
add_geo <- function(d, district_code) {
  code <- as.character(as.integer(zap_labels(district_code)))
  d |> mutate(district_code = as.integer(code),
              province = unname(province_names[substr(code, 1, 1)]),
              district = unname(district_names[code]), .after = 1)
}

# Harmonised categories (matched on lower-case label text)
harm_technique <- function(x) {
  x <- str_to_lower(as.character(x))
  case_when(str_detect(x, "tradition") ~ "Traditional", str_detect(x, "surface") ~ "Surface",
            str_detect(x, "flood")     ~ "Flood (rice)", str_detect(x, "drip") ~ "Drip",
            str_detect(x, "sprinkl")   ~ "Sprinkler",   str_detect(x, "pivot") ~ "Pivot",
            is.na(x) ~ NA_character_, TRUE ~ "Other")
}
harm_water <- function(x) {
  x <- str_to_lower(as.character(x))
  case_when(str_detect(x, "rain")                  ~ "Rainwater harvesting",
            str_detect(x, "treatment|tap")          ~ "Treatment plant / tap",
            str_detect(x, "underground|well|bore")  ~ "Groundwater",
            str_detect(x, "lake|stream|river")      ~ "Lake / river / stream",
            str_detect(x, "dam")                    ~ "Dam",
            is.na(x) ~ NA_character_, TRUE ~ "Other")
}
harm_tool <- function(x) {
  x <- str_to_lower(as.character(x))
  case_when(str_detect(x, "cane|basin|bucket|arosoir|arrosoir|watering") ~ "Bucket / watering can",
            str_detect(x, "channel|canal")                            ~ "Water channels",
            str_detect(x, "tube well")                                ~ "Tube well",
            str_detect(x, "ssit|pump|pivot|machine|motor")            ~ "Pump / machine",
            is.na(x) ~ NA_character_, TRUE ~ "Other")
}
modern_techniques <- c("Drip", "Sprinkler", "Pivot")
harm_education <- function(x) factor(x, levels = c("No formal education", "Primary", "Secondary / vocational", "Tertiary"))
any1 <- function(x) if (all(is.na(x))) NA_integer_ else as.integer(any(x == 1, na.rm = TRUE))

save_clean <- function(x, name) {
  saveRDS(x, file.path(dir_ahs_cl, paste0(name, ".rds")), compress = "xz")
  message(sprintf("   %-28s %7d rows x %3d cols", name, nrow(x), ncol(x)))
  invisible(x)
}

# ============================================================================
# 1. AHS 2017  (agricultural year 2016/17, Seasons A and B; SAS 2017 sample)
# ============================================================================
message("1/5 AHS 2017")

# ---- 1.1 S0 listing: every household in the sampled segments --------------------
s0 <- read_ahs("2017", "s0")
n_empty <- sum(is.na(s0$idquest))
check("segments with no household (dropped)", n_empty, nrow(s0), "dropped")
listing17 <- s0 |> filter(!is.na(idquest)) |>
  add_geo(s0$s0q2[!is.na(s0$idquest)]) |>
  transmute(year = 2017L, hh_id = sprintf("%.0f", idquest), province, district, district_code,
            segment_id = as.character(Segment_ID),
            stratum = as_cat(s0q3, "s0q3"), segment_no = as.integer(s0q4),
            agri_activity = as_cat(s0q13, "s0q13"),
            is_agri_hh = as.integer(as.numeric(s0q13) != 11),
            respondent_is_head = as_yn(s0q9, "s0q9"), respondent_relation = as_cat(s0q12, "s0q12"),
            coop_member = as_yn(s0q14, "s0q14"), coop_type = as_cat(s0q15, "s0q15"),
            hh_size = as_num(s0q16, "s0q16", max_ok = 30),
            interview_date = dmy(sprintf("%08d", as.integer(zap_labels(s0q17))), quiet = TRUE),
            weight = as.numeric(weight))
log_fix("s0q17", "unparseable interview date -> missing", sum(!is.na(s0$s0q17)) - sum(!is.na(listing17$interview_date)))
# s0q7, s0q8, s0q10, s0q11 (names, phone numbers), s0q18-s0q20 (staff) are "." placeholders: not kept.
check("non-agricultural households in listing (kept, flagged is_agri_hh = 0)", sum(listing17$is_agri_hh == 0), nrow(listing17), "flag")
save_clean(listing17, "ahs2017_listing")

# ---- 1.2 S1 members -------------------------------------------------------------
s1 <- read_ahs("2017", "s1")
months_A <- c(s1q11 = "sep16", s1q12 = "oct16", s1q13 = "nov16", s1q14 = "dec16", s1q15 = "jan17")
months_B <- c(s1q17 = "feb17", s1q18 = "mar17", s1q19 = "apr17", s1q20 = "may17", s1q21 = "jun17")
mem17 <- s1 |>
  transmute(year = 2017L, hh_id = sprintf("%.0f", idquest), member_no = as.integer(s1q1),
            relation = as_cat(s1q3, "s1q3"), sex = as_cat(s1q4, "s1q4"),
            age = as_num(s1q5, "s1q5", max_ok = 110),
            child_schooled = as_yn(s1q6, "s1q6"), education_raw = as_cat(s1q7, "s1q7"),
            main_activity = as_cat(s1q8, "s1q8"), farm_location = as_cat(s1q9, "s1q9"),
            hours_day_seasonA = as_num(s1q10, "s1q10", max_ok = 16),
            hours_day_seasonB = as_num(s1q16, "s1q16", max_ok = 16),
            across(all_of(names(months_A)), \(x) as_num(x, max_ok = 31), .names = "days_{months_A[.col]}"),
            across(all_of(names(months_B)), \(x) as_num(x, max_ok = 31), .names = "days_{months_B[.col]}")) |>
  mutate(days_worked_seasonA = rowSums(across(starts_with("days_") & ends_with(c("16", "jan17"))), na.rm = TRUE),
         days_worked_seasonB = rowSums(across(c(days_feb17, days_mar17, days_apr17, days_may17, days_jun17)), na.rm = TRUE),
         labour_hours_seasonA = hours_day_seasonA * days_worked_seasonA,
         labour_hours_seasonB = hours_day_seasonB * days_worked_seasonB,
         education = harm_education(case_when(
           education_raw == "Primary" ~ "Primary", education_raw == "Secondary" ~ "Secondary / vocational",
           education_raw == "Tertiary" ~ "Tertiary", education_raw == "No education level" ~ "No formal education")))
check("members with missing age", sum(is.na(mem17$age)), nrow(mem17), "kept as missing")
save_clean(mem17, "ahs2017_members")

# ---- 1.3 S3 extension and programmes (file has 4 rows per household) -------------
s3 <- read_ahs("2017", "s3")
hh_const <- s3 |> group_by(idquest) |> summarise(across(c(s3q1, s3q2, s3q5:s3q16), n_distinct)) |>
  select(-idquest) |> as.matrix()
check("household-level answers that differ across the 4 rows", sum(hh_const > 1), length(hh_const), "first row kept")
prog17 <- s3 |> group_by(idquest) |> slice(1) |> ungroup() |>
  transmute(year = 2017L, hh_id = sprintf("%.0f", idquest),
            extension_any = as_yn(s3q1, "s3q1"), extension_domain = as_cat(s3q2, "s3q2"),
            twigire_muhinzi = as_yn(s3q5, "s3q5"), contract_farming = as_yn(s3q6, "s3q6"),
            reared_cow = as_yn(s3q7, "s3q7"), girinka_cow = as_yn(s3q8, "s3q8"),
            cow_from_ngo = as_yn(s3q9, "s3q9"), cow_from_friends = as_yn(s3q10, "s3q10"),
            cow_bought = as_yn(s3q11, "s3q11"), cow_own_raised = as_yn(s3q12, "s3q12"),
            girinka_cow_still = as_yn(s3q13, "s3q13"), girinka_cow_lost_reason = as_cat(s3q14, "s3q14"),
            school_milk = as_yn(s3q15, "s3q15"), kitchen_garden = as_yn(s3q16, "s3q16"))
ext17 <- bind_rows(
  s3 |> filter(!is.na(s3q3_a)) |> transmute(hh_id = sprintf("%.0f", idquest), domain = "Cropping",
    service = as_cat(s3q3_a, "s3q3_a"), provider = as_cat(s3q3_b, "s3q3_b")),
  s3 |> filter(!is.na(s3q4_a)) |> transmute(hh_id = sprintf("%.0f", idquest), domain = "Livestock",
    service = as_cat(s3q4_a, "s3q4_a"), provider = as_cat(s3q4_b, "s3q4_b"))) |>
  mutate(year = 2017L, .before = 1) |> filter(!is.na(service)) |> distinct()
save_clean(prog17, "ahs2017_programmes"); save_clean(ext17, "ahs2017_extension_services")

# ---- 1.4 S5 inputs: organic, inorganic, pesticide, seeds (wide -> long) ---------
s5 <- read_ahs("2017", "s5")
org_src_lab <- attr(s5$s5q1_11, "labels")       # Season A source has no labels: same question as B
unit_to_std <- function(q, unit) case_when(unit %in% c("Kg", "l") ~ q, unit %in% c("g", "cc") ~ q / 1000)
inputs17 <- s5 |>
  transmute(year = 2017L, hh_id = sprintf("%.0f", idquest),
            organic_A = as_yn(s5q1_1, "s5q1_1"), organic_A_kg = as_num(s5q1_2, "s5q1_2"),
            organic_A_source = as_cat(s5q1_3, "s5q1_3", labels = org_src_lab),
            organic_A_bought_kg = as_num(s5q1_4, "s5q1_4"), organic_A_paid_rwf = as_num(s5q1_5, "s5q1_5"),
            organic_q517_kg = as_num(s5q1_7, "s5q1_7"),
            lime_A = as_yn(s5q1_8, "s5q1_8"),
            organic_B = as_yn(s5q1_9, "s5q1_9"), organic_B_kg = as_num(s5q1_10, "s5q1_10"),
            organic_B_source = as_cat(s5q1_11, "s5q1_11"),
            organic_B_bought_kg = as_num(s5q1_12, "s5q1_12"), organic_B_paid_rwf = as_num(s5q1_13, "s5q1_13"),
            lime_B = as_yn(s5q1_16, "s5q1_16"),
            inorganic_A = as_yn(s5q2_1, "s5q2_1"), inorganic_B = as_yn(s5q2_20, "s5q2_20"),
            pesticide_A = as_yn(s5q3_1, "s5q3_1"), pesticide_B = as_yn(s5q3_23, "s5q3_23"))
manure17 <- bind_rows(
  slots_long(s5, "idquest", c("s5q1_6_1", "s5q1_6_2", "s5q1_6_3"), "manure_method", drop_codes = c(0, 9)) |> mutate(season = "A"),
  slots_long(s5, "idquest", c("s5q1_14_1", "s5q1_14_2", "s5q1_14_3"), "manure_method", drop_codes = c(0, 9)) |> mutate(season = "B")) |>
  transmute(year = 2017L, hh_id = sprintf("%.0f", idquest), season, slot, manure_method)
# Inorganic fertiliser: 3 type slots per season, 6 questions per slot
fert_slot <- function(season, vars) s5 |>
  transmute(hh_id = sprintf("%.0f", idquest), season = season,
            fert_type = as_cat(.data[[vars[1]]], vars[1], labels = attr(s5$s5q2_2, "labels")),
            unit = as_cat(.data[[vars[2]]], vars[2], labels = attr(s5$s5q2_3, "labels")),
            qty_used = as_num(.data[[vars[3]]], vars[3]), qty_bought = as_num(.data[[vars[4]]], vars[4]),
            price_rwf_per_kg = as_num(.data[[vars[5]]], vars[5]),
            source = as_cat(.data[[vars[6]]], vars[6], labels = attr(s5$s5q2_7, "labels")))
fs <- \(i) paste0("s5q2_", i)
fert17 <- bind_rows(fert_slot("A", fs(2:7)), fert_slot("A", fs(8:13)), fert_slot("A", fs(14:19)),
                    fert_slot("B", fs(21:26)), fert_slot("B", fs(27:32)), fert_slot("B", fs(33:38))) |>
  filter(!is.na(fert_type)) |>
  mutate(year = 2017L, .before = 1,
         qty_used_std = unit_to_std(qty_used, unit), qty_bought_std = unit_to_std(qty_bought, unit),
         flag_bought_gt_used = qty_bought > qty_used)
check("fertiliser bought > used", sum(fert17$flag_bought_gt_used, na.rm = TRUE), nrow(fert17), "flag")
pest_slot <- function(season, vars) s5 |>
  transmute(hh_id = sprintf("%.0f", idquest), season = season,
            pesticide = as_cat(.data[[vars[1]]], vars[1], labels = attr(s5$s5q3_2, "labels")),
            unit = as_cat(.data[[vars[2]]], vars[2], labels = attr(s5$s5q3_3, "labels")),
            qty_used = as_num(.data[[vars[3]]], vars[3]), qty_bought = as_num(.data[[vars[4]]], vars[4]),
            price_rwf_per_unit = as_num(.data[[vars[5]]], vars[5]),
            source = as_cat(.data[[vars[6]]], vars[6], labels = attr(s5$s5q3_7, "labels")),
            purpose = as_cat(.data[[vars[7]]], vars[7], labels = attr(s5$s5q3_8, "labels")))
ps <- \(i) paste0("s5q3_", i)
pest17 <- bind_rows(pest_slot("A", ps(2:8)), pest_slot("A", ps(9:15)), pest_slot("A", ps(16:22)),
                    pest_slot("B", ps(24:30)), pest_slot("B", ps(31:37)), pest_slot("B", ps(38:44))) |>
  filter(!is.na(pesticide)) |>
  mutate(year = 2017L, .before = 1, qty_used_std = unit_to_std(qty_used, unit))
# DECISION: 99 in seed quantities is a "don't know" code. Evidence (crop rows only):
# traditional seed sown = 99 kg for 1,147 / 3,350 / 4,935 first / second / third crops
# vs 69 / 44 / 31 rows at 100 kg. Seed QUANTITIES for 2017 are therefore weak; seed TYPE
# (traditional / improved) is complete and is what the indicators use.
seed_slot <- function(season, crop, type, trad_sown, trad_bought, trad_spent, impr_sown, impr_bought, impr_spent, impr_src) s5 |>
  transmute(hh_id = sprintf("%.0f", idquest), season = season,
            crop_code = as.integer(zap_labels(.data[[crop]])),
            crop = as_cat(.data[[crop]], crop),
            seed_type = as_cat(.data[[type]], type),
            trad_sown_kg = as_num(.data[[trad_sown]], trad_sown, na_codes = 99),
            trad_bought_kg = as_num(.data[[trad_bought]], trad_bought, na_codes = 99),
            trad_spent_rwf = as_num(.data[[trad_spent]], trad_spent),
            impr_sown_kg = as_num(.data[[impr_sown]], impr_sown, na_codes = 99),
            impr_bought_kg = as_num(.data[[impr_bought]], impr_bought, na_codes = 99),
            impr_spent_rwf = as_num(.data[[impr_spent]], impr_spent),
            impr_source = as_cat(.data[[impr_src]], impr_src))
seeds17 <- bind_rows(
  map_dfr(c("a", "b", "c"), \(k) seed_slot("A", paste0("s5q4_1_", k), paste0("s5q4_2_", k), paste0("s5q4_3_", k),
    paste0("s5q4_4_", k), paste0("s5q4_5_", k), paste0("s5q4_6_", k), paste0("s5q4_7_", k), paste0("s5q4_8_", k), paste0("s5q4_9_", k))),
  map_dfr(c("a", "b", "c"), \(k) seed_slot("B", paste0("s5q4_10_", k), paste0("s5q4_11_", k), paste0("s5q4_12_", k),
    paste0("s5q4_13_", k), paste0("s5q4_14_", k), paste0("s5q4_16_", k), paste0("s5q4_17_", k), paste0("s5q4_18_", k), paste0("s5q4_15_", k)))) |>
  filter(!is.na(crop_code)) |>
  mutate(year = 2017L, .before = 1, improved_seed = as.integer(seed_type %in% c("Improved seeds", "Both")))
save_clean(inputs17, "ahs2017_inputs"); save_clean(manure17, "ahs2017_manure_methods")
save_clean(fert17, "ahs2017_fertiliser"); save_clean(pest17, "ahs2017_pesticide"); save_clean(seeds17, "ahs2017_seeds")

# ---- 1.5 S6 practices: erosion, IRRIGATION, mechanisation --------------------------
s6 <- read_ahs("2017", "s6")
prac17 <- s6 |>
  transmute(year = 2017L, hh_id = sprintf("%.0f", idquest),
            grows_crops = as_yn(cropping, "cropping"), grows_crops_seasonB = as_yn(dummy_cropping_B, "dummy_cropping_B"),
            erosion_control = as_yn(s6q1_1, "s6q1_1"),
            erosion_increasing = as_cat(s6q1_3, "s6q1_3"),
            erosion_limitations = as_yn(s6q1_5_0, "s6q1_5_0"),
            irrigates = as_yn(s6q2_1, "s6q2_1"),
            mechanised = as_yn(s6q2_4, "s6q2_4"),
            limitation_other_text = coalesce(blank_to_na(s6q1_5_1_a), blank_to_na(s6q1_5_1_b), blank_to_na(s6q1_5_1_c)))
irr17_tech  <- slots_long(s6, "idquest", paste0("s6q2_2_", 1:3), "technique_raw", drop_codes = c(0, 9))
irr17_water <- slots_long(s6, "idquest", paste0("s6q2_3_", 1:3), "water_source_raw", drop_codes = c(0, 9))
check("irrigation technique given but irrigates = No",
      sum(irr17_tech$idquest %in% s6$idquest[s6$s6q2_1 == 2]), nrow(irr17_tech), "kept")
irrdet17 <- bind_rows(
  irr17_tech |> transmute(hh_id = sprintf("%.0f", idquest), slot, dimension = "technique",
                          category_raw = technique_raw, category = harm_technique(technique_raw)),
  irr17_water |> transmute(hh_id = sprintf("%.0f", idquest), slot, dimension = "water_source",
                           category_raw = water_source_raw, category = harm_water(water_source_raw))) |>
  mutate(year = 2017L, .before = 1)
erosion17 <- slots_long(s6, "idquest", paste0("s6q1_2_", 1:3), "measure", drop_codes = c(0, 99)) |>
  transmute(year = 2017L, hh_id = sprintf("%.0f", idquest), slot, measure)
mech17 <- slots_long(s6, "idquest", paste0("s6q2_5_", 1:3), "equipment", drop_codes = c(0, 9)) |>
  transmute(year = 2017L, hh_id = sprintf("%.0f", idquest), slot, equipment)
crop_lab17 <- attr(s5$s5q4_1_a, "labels")
major17 <- bind_rows(
  slots_long(s6, "idquest", paste0("s2q7_", 1:3), "crop", labels = crop_lab17) |> mutate(season = "A"),
  slots_long(s6, "idquest", paste0("s2q15_", 1:3), "crop", labels = crop_lab17) |> mutate(season = "B")) |>
  transmute(year = 2017L, hh_id = sprintf("%.0f", idquest), season, rank = slot, crop_code = code, crop)
save_clean(prac17, "ahs2017_practices"); save_clean(irrdet17, "ahs2017_irrigation_detail")
save_clean(erosion17, "ahs2017_erosion_measures"); save_clean(mech17, "ahs2017_mechanisation")
save_clean(major17, "ahs2017_major_crops")

# ---- 1.6 S8 production use, Season A and B stacked --------------------------------
prod_season <- function(module, season, first) {
  d <- read_ahs("2017", module); v <- \(i) paste0("s8q1_1_", first + i - 1)
  if (module == "s8a") { mkt_lab <<- attr(d$s8q1_1_6, "labels"); sto_lab <<- attr(d$s8q1_1_18, "labels") }
  d |> transmute(year = 2017L, hh_id = sprintf("%.0f", idquest), season = season,
    crop_name_rw = blank_to_na(.data[[v(1)]]), crop_code = as.integer(zap_labels(.data[[v(2)]])),
    crop = as_cat(.data[[v(2)]], v(2)),
    produced_kg = as_num(.data[[v(3)]], v(3)), processed_kg = as_num(.data[[v(4)]], v(4)),
    sold_kg = as_num(.data[[v(5)]], v(5)), market = as_cat(.data[[v(6)]], v(6), labels = attr(d[[v(6)]], "labels") %||% mkt_lab),
    price_rwf_kg = as_num(.data[[v(7)]], v(7)),
    own_consumption_kg = as_num(.data[[v(8)]], v(8)), wages_kg = as_num(.data[[v(9)]], v(9)),
    rent_kg = as_num(.data[[v(10)]], v(10)), gift_kg = as_num(.data[[v(11)]], v(11)),
    exchanged_kg = as_num(.data[[v(12)]], v(12)), seed_kg = as_num(.data[[v(13)]], v(13)),
    animal_feed_kg = as_num(.data[[v(14)]], v(14)), stored_kg = as_num(.data[[v(15)]], v(15)),
    lost_kg = as_num(.data[[v(16)]], v(16)), other_use_kg = as_num(.data[[v(17)]], v(17)),
    storage_type = as_cat(.data[[v(18)]], v(18), labels = attr(d[[v(18)]], "labels") %||% sto_lab),
    applies_postharvest_training = as_yn(.data[[v(19)]], v(19)),
    cost_harvest_labour_rwf = as_num(.data[[v(20)]], v(20)), cost_equipment_rwf = as_num(.data[[v(21)]], v(21)),
    cost_buildings_1_rwf = as_num(.data[[v(22)]], v(22)), cost_buildings_2_rwf = as_num(.data[[v(23)]], v(23)),
    cost_storage_insecticide_rwf = as_num(.data[[v(24)]], v(24)), cost_other_rwf = as_num(.data[[v(25)]], v(25)))
}
prod17 <- bind_rows(prod_season("s8a", "A", 1), prod_season("s8b", "B", 26)) |>
  filter(!is.na(crop_code) | !is.na(crop_name_rw)) |>
  mutate(uses_total_kg = rowSums(across(c(sold_kg, own_consumption_kg, wages_kg, rent_kg, gift_kg, exchanged_kg,
                                          seed_kg, animal_feed_kg, stored_kg, lost_kg, other_use_kg)), na.rm = TRUE),
         flag_uses_gt_production = uses_total_kg > 1.05 * produced_kg & produced_kg > 0,
         flag_sold_gt_production = sold_kg > produced_kg,
         sold_share = if_else(produced_kg > 0, pmin(sold_kg / produced_kg, 1), NA_real_),
         sales_value_rwf = sold_kg * price_rwf_kg)
check("crop uses add up to more than 105% of production", sum(prod17$flag_uses_gt_production, na.rm = TRUE), nrow(prod17), "flag")
check("quantity sold > quantity produced", sum(prod17$flag_sold_gt_production, na.rm = TRUE), nrow(prod17), "flag; sold_share capped at 1")
save_clean(prod17, "ahs2017_production_use")

# ============================================================================
# 2. AHS 2020  (agricultural year 2019/20)
# ============================================================================
message("2/5 AHS 2020")
s0 <- read_ahs("2020", "s0")
w20 <- read_ahs("2020", "s22") |> distinct(HHUID, weight)   # Section 0 has no weight column
s0 <- s0 |> left_join(w20, by = "HHUID")
hh20 <- s0 |> add_geo(s0$s0q2) |>
  transmute(year = 2020L, hh_id = as.character(HHUID), province, district, district_code,
            head_marital = as_cat(s0q9, "s0q9"), ubudehe = as_cat(s0q10, "s0q10"),
            respondent_is_head = as_yn(s0q12, "s0q12"), respondent_relation = as_cat(s0q15, "s0q15"),
            agri_main_livelihood = as_yn(s0q17, "s0q17"), other_activity = as_cat(s0q18, "s0q18"),
            weight = as.numeric(weight))
# s0q11 (head's phone number) is not kept.
act20 <- slots_long(s0, "HHUID", paste0("s0q16_", 1:4), "activity", drop_codes = c(0, 7)) |>
  mutate(activity = str_to_lower(word(activity, 1)) |> str_remove("[^a-z]+$")) |> distinct(HHUID, activity) |>
  mutate(v = 1L) |> pivot_wider(names_from = activity, values_from = v, names_prefix = "activity_", values_fill = 0L) |>
  mutate(hh_id = as.character(HHUID), .keep = "unused")
hh20 <- hh20 |> left_join(act20, by = "hh_id")
save_clean(hh20, "ahs2020_household")

s1 <- read_ahs("2020", "s1")
mem20 <- s1 |>
  transmute(year = 2020L, hh_id = as.character(HHUID), hh_size_reported = as.integer(s1q1), member_no = as.integer(s1q2),
            relation = as_cat(s1q4, "s1q4"), sex = as_cat(s1q5, "s1q5"), age = as_num(s1q6, "s1q6", max_ok = 110),
            education_raw = as_cat(s1q7, "s1q7", dk_to_na = TRUE), main_activity = as_cat(s1q8, "s1q8"),
            engaged_agriculture = as_yn(s1q9, "s1q9")) |>
  mutate(education = harm_education(case_when(
    education_raw %in% c("Some/Still Primary", "Completed Primary") ~ "Primary",
    education_raw %in% c("Vocational School", "some/still secondary", "Completed Secondary") ~ "Secondary / vocational",
    education_raw %in% c("Some / still University", "Completed university") ~ "Tertiary",
    education_raw == "Not schooled" ~ "No formal education")))
agribus20 <- slots_long(s1, c("HHUID", "s1q2"), c("s1q10_1", "s1q10_2"), "agribusiness", drop_codes = c(0, 6)) |>
  transmute(year = 2020L, hh_id = as.character(HHUID), member_no = as.integer(s1q2), agribusiness)
size_chk <- mem20 |> group_by(hh_id) |> summarise(a = first(hh_size_reported), b = n())
check("reported household size differs from members listed", sum(size_chk$a != size_chk$b), nrow(size_chk), "listed members used")
save_clean(mem20, "ahs2020_members"); save_clean(agribus20, "ahs2020_agribusiness")

# ---- 2.1 plots -------------------------------------------------------------------
s21 <- read_ahs("2020", "s21")
# DECISION: plot area 9999 = "Don't know" (labelled) -> missing; plots above 50 ha
# (500,000 sqm) are implausible for a household plot -> missing area, row kept.
plots20 <- s21 |>
  transmute(year = 2020L, hh_id = as.character(HHUID),
            has_crop_land = as_yn(s2q1, "s2q1"), has_pasture_land = as_yn(s2q2, "s2q2"), owns_land = as_yn(s2q3, "s2q3"),
            n_plots_reported = as.integer(s2q4), plot_no = as.integer(s2q5),
            plot_area_sqm = as_num(s2q6, "s2q6", na_codes = 9999, max_ok = 500000),
            tenure = as_cat(s2q8, "s2q8"),
            n_members_access = as.integer(HH_access), n_members_collateral = as.integer(HH_loan),
            cultivated = as_cat(s2q10, "s2q10"),
            no_mech_reason = as_cat(s2q12, "s2q12"),
            land_consolidated = as_cat(s2q13, "s2q13"))
eq20 <- slots_long(s21, c("HHUID", "s2q5"), paste0("s2q11_", 1:5), "equipment", drop_codes = 0)
plots20 <- plots20 |>
  left_join(eq20 |> group_by(hh_id = as.character(HHUID), plot_no = as.integer(s2q5)) |>
              summarise(equipment = paste(sort(unique(equipment)), collapse = "; "),
                        mechanised = as.integer(any(!equipment %in% c("Hoe"))), .groups = "drop"),
            by = c("hh_id", "plot_no")) |>
  filter(!is.na(plot_no)) |>
  mutate(plot_area_ha = plot_area_sqm / 1e4,
         mechanised = if_else(is.na(mechanised) & !is.na(equipment), 0L, mechanised),
         in_consolidation = case_when(land_consolidated == "Yes" ~ 1L, land_consolidated == "No" ~ 0L))
check("households with no plot row (no land)", sum(is.na(s21$s2q5)), n_distinct(s21$HHUID), "kept in household table only")
save_clean(plots20, "ahs2020_plots")

# ---- 2.2 crops, inputs, practices, IRRIGATION -------------------------------------
s22 <- read_ahs("2020", "s22")
prac20 <- s22 |>
  transmute(year = 2020L, hh_id = as.character(HHUID),
            grows_crops = as_yn(s2q14, "s2q14"), n_crops = as.integer(crops_grown), n_vegetables = as.integer(Nmber_vegs),
            stored_crops = as_cat(s2q16, "s2q16"), storage_place = as_cat(s2q18, "s2q18"),
            improved_seed = as_yn(s2q19, "s2q19"), n_members_improved_seed = as.integer(HH_members),
            organic_fert = as_yn(s2q22, "s2q22"), inorganic_fert = as_yn(s2q23, "s2q23"),
            n_members_inorganic = as.integer(HH_members2), inorganic_source = as_cat(s2q25, "s2q25"),
            pesticide = as_yn(s2q26, "s2q26"), erosion_control = as_yn(s2q27, "s2q27"),
            agroforestry = as_yn(s2q29, "s2q29"),
            irrigates = as_yn(s2q30, "s2q30"),          # label says "2017 agric." - question is about 2019/20
            irrig_technique_raw = as_cat(s2q31, "s2q31"), irrig_tool_raw = as_cat(s2q32, "s2q32"),
            irrig_water_raw = as_cat(s2q33, "s2q33")) |>
  mutate(irrig_technique = harm_technique(irrig_technique_raw), irrig_tool = harm_tool(irrig_tool_raw),
         irrig_water_source = harm_water(irrig_water_raw),
         stored = as.integer(!is.na(stored_crops) & stored_crops != "No"))
check("irrigation answered by households that grew no crops", sum(prac20$grows_crops == 0 & !is.na(prac20$irrigates), na.rm = TRUE),
      nrow(prac20), "kept; indicators use crop growers only")
check("irrigation details missing for irrigating households", sum(prac20$irrigates == 1 & is.na(prac20$irrig_technique_raw), na.rm = TRUE),
      sum(prac20$irrigates == 1, na.rm = TRUE), "kept")
crops20 <- bind_rows(
  slots_long(s22, "HHUID", paste0("s2q15_", 1:10), "crop", drop_codes = c(0, 19)) |> mutate(list = "grown"),
  slots_long(s22, "HHUID", paste0("s2q15_v_", 1:10), "crop", drop_codes = 0) |> mutate(list = "vegetable grown"),
  slots_long(s22, "HHUID", paste0("s2q17_", 1:7), "crop", drop_codes = c(0, 19)) |> mutate(list = "stored"),
  slots_long(s22, "HHUID", paste0("s2q20_", 1:4), "crop", drop_codes = c(0, 19)) |> mutate(list = "improved seed")) |>
  transmute(year = 2020L, hh_id = as.character(HHUID), list, crop = str_to_sentence(crop)) |> distinct()
erosion20 <- slots_long(s22, "HHUID", paste0("s2q28_", 1:3), "measure", drop_codes = 0) |>
  transmute(year = 2020L, hh_id = as.character(HHUID), slot, measure)
log_fix("s2q28_2/3", "code 0 (no measure) -> dropped", sum(s22$s2q28_2 == 0, s22$s2q28_3 == 0, na.rm = TRUE))
users20 <- bind_rows(
  slots_long(s22, "HHUID", paste0("s2q21_", 1:6), "member_no", raw = TRUE) |> mutate(input = "improved seed"),
  slots_long(s22, "HHUID", paste0("s2q24_", 1:6), "member_no", raw = TRUE) |> mutate(input = "inorganic fertiliser")) |>
  transmute(year = 2020L, hh_id = as.character(HHUID), input, member_no = as.integer(member_no))
irrdet20 <- prac20 |> filter(irrigates == 1) |>
  select(year, hh_id, technique = irrig_technique_raw, tool = irrig_tool_raw, water_source = irrig_water_raw) |>
  mutate(across(c(technique, tool, water_source), as.character)) |>
  pivot_longer(c(technique, tool, water_source), names_to = "dimension", values_to = "category_raw") |>
  filter(!is.na(category_raw)) |>
  mutate(slot = 1L, category = case_when(dimension == "technique" ~ harm_technique(category_raw),
                                         dimension == "tool" ~ harm_tool(category_raw),
                                         TRUE ~ harm_water(category_raw)))
save_clean(prac20, "ahs2020_practices"); save_clean(crops20, "ahs2020_crops")
save_clean(erosion20, "ahs2020_erosion_measures"); save_clean(users20, "ahs2020_input_users")
save_clean(irrdet20, "ahs2020_irrigation_detail")

# ---- 2.3 fruit trees --------------------------------------------------------------
s23 <- read_ahs("2020", "s23")
fruit20 <- s23 |>
  transmute(year = 2020L, hh_id = as.character(HHUID), grows_fruit = as_yn(s2q34, "s2q34"),
            fruit = as_cat(s2q35, "s2q35"), trees_owned = as_num(s2q36, "s2q36"),
            trees_harvested = as_num(s2q37, "s2q37"), production_kg = as_num(s2q38, "s2q38"),
            share_sold = as_cat(s2q39, "s2q39"), share_consumed = as_cat(s2q40, "s2q40")) |>
  mutate(flag_harvested_gt_owned = trees_harvested > trees_owned)
check("fruit trees harvested > trees owned", sum(fruit20$flag_harvested_gt_owned, na.rm = TRUE), nrow(fruit20), "flag")
save_clean(fruit20, "ahs2020_fruit")

# ---- 2.4 assets and extension (long by service) -------------------------------------
s31 <- read_ahs("2020", "s31")
assets20 <- slots_long(s31 |> distinct(HHUID, .keep_all = TRUE), "HHUID", paste0("s3q1_", 1:4), "asset") |>
  distinct(HHUID, asset) |> mutate(v = 1L, asset = paste0("has_", str_to_lower(word(asset, 1, sep = " |/")))) |>
  pivot_wider(names_from = asset, values_from = v, values_fill = 0L) |>
  rename(hh_id = HHUID) |> mutate(hh_id = as.character(hh_id))
ext20 <- s31 |> transmute(year = 2020L, hh_id = as.character(HHUID), service = as_cat(s3q2, "s3q2"),
                          n_male = as_num(s3q3_3_1, "s3q3_3_1"), n_female = as_num(s3q3_3_2, "s3q3_3_2"),
                          provider = as_cat(s3q4, "s3q4")) |>
  filter(!is.na(service), service != "None")
save_clean(assets20, "ahs2020_assets"); save_clean(ext20, "ahs2020_extension_services")

# ---- 2.5 groups, cooperatives, insurance, Girinka, grants ----------------------------
s32 <- read_ahs("2020", "s32")
prog20 <- s32 |>
  transmute(year = 2020L, hh_id = as.character(HHUID),
            twigire_muhinzi = as_yn(s3q5, "s3q5"), twigire_n_male = as.integer(s3q5_1), twigire_n_female = as.integer(s3q5_2),
            farmer_field_school = as_yn(s3q6, "s3q6"), ffs_n_male = as.integer(s3q6_1), ffs_n_female = as.integer(s3q6_2),
            contract_farming = as_yn(s3q7, "s3q7"), crop_insurance = as_yn(s3q8, "s3q8"),
            coop_member = as_yn(s3q9, "s3q9"), coop_n_male = as.integer(s3q9_1), coop_n_female = as.integer(s3q9_2),
            kitchen_garden = as_yn(s3q12, "s3q12"), girinka_cow = as_yn(s3q13, "s3q13"),
            girinka_source = as_cat(s3q14, "s3q14"), girinka_cow_still = as_yn(s3q15, "s3q15"),
            girinka_cow_lost_reason = as_cat(s3q16, "s3q16"), small_livestock_program = as_yn(s3q17, "s3q17"),
            small_livestock_type = as_cat(s3q18, "s3q18"), small_livestock_source = as_cat(s3q19, "s3q19"),
            grant_received = as_yn(s3q20, "s3q20"), grant_type = as_cat(s3q21, "s3q21"), grant_origin = as_cat(s3q22, "s3q22"))
coop20 <- bind_rows(
  slots_long(s32, "HHUID", paste0("s3q10_", 1:3), "category") |> mutate(dimension = "coop_type"),
  slots_long(s32, "HHUID", paste0("s3q11_", 1:4), "category", drop_codes = c(0, 7)) |> mutate(dimension = "coop_service")) |>
  transmute(year = 2020L, hh_id = as.character(HHUID), dimension, category) |> distinct()
prog20 <- prog20 |> left_join(coop20 |> filter(dimension == "coop_type") |> group_by(hh_id) |>
  summarise(water_user_coop = as.integer(any(str_detect(category, "Water")))), by = "hh_id") |>
  mutate(water_user_coop = if_else(coop_member == 0L, 0L, coalesce(water_user_coop, 0L)))
save_clean(prog20, "ahs2020_programmes"); save_clean(coop20, "ahs2020_cooperatives")

# ---- 2.6 finance ---------------------------------------------------------------------
s4 <- read_ahs("2020", "s4")
fin20 <- s4 |>
  transmute(year = 2020L, hh_id = as.character(HHUID),
            bank_account = as_yn(s4q1, "s4q1"), tontine = as_yn(s4q4, "s4q4"), savings = as_yn(s4q5, "s4q5"),
            loan_requested = as_yn(s4q8, "s4q8"), loan_rejected = as_cat(s4q11, "s4q11"),
            loan_rejected_reason = as_cat(s4q12, "s4q12"), loan_rejected_use = as_cat(s4q13, "s4q13")) |>
  mutate(loan_any_rejected = case_when(loan_requested == 0L ~ NA_integer_,
                                       loan_rejected %in% c("Yes all", "Yes some") ~ 1L, loan_rejected == "No" ~ 0L))
fin_inst20 <- bind_rows(
  slots_long(s4, "HHUID", paste0("s4q3_", 1:4), "institution") |> mutate(purpose = "bank account"),
  slots_long(s4, "HHUID", paste0("s4q7_", 1:4), "institution") |> mutate(purpose = "savings"),
  slots_long(s4, "HHUID", paste0("s4q10_", 1:4), "institution") |> mutate(purpose = "loan request")) |>
  transmute(year = 2020L, hh_id = as.character(HHUID), purpose, institution) |> distinct()
save_clean(fin20, "ahs2020_finance"); save_clean(fin_inst20, "ahs2020_finance_institutions")

# ============================================================================
# 3. AHS 2024  (Season A and B 2024; EICV7 sub-sample)
# ============================================================================
message("3/5 AHS 2024")
s0 <- read_ahs("2024", "s0")
hh24 <- s0 |> add_geo(s0$district) |>
  transmute(year = 2024L, hh_id = sprintf("%.0f", hhid), cluster = sprintf("%.0f", clust), province, district, district_code,
            respondent_relation = as_cat(s0q13, "s0q13"),
            is_agri_hh = as_yn(s0q14, "s0q14"),   # 1 Agriculture / 2 No agricultural activities
            agri_activity = as_cat(s0q15, "s0q15"), non_agri_activity = as_cat(s0q16, "s0q16"),
            weight = as.numeric(weight))
check("households with no agricultural activity (kept, is_agri_hh = 0)", sum(hh24$is_agri_hh == 0, na.rm = TRUE), nrow(hh24), "flag")
save_clean(hh24, "ahs2024_household")

s1 <- read_ahs("2024", "s1")
mem24 <- s1 |>
  transmute(year = 2024L, hh_id = sprintf("%.0f", hhid), member_no = as.integer(pid),
            sex = as_cat(s1q1, "s1q1"), relation = as_cat(s1q2, "s1q2"),
            age = as_num(s1q3y, "s1q3y", na_codes = 998, max_ok = 110), marital = as_cat(s1q4, "s1q4"),
            health_insurance = as_cat(s3q2, "s3q2", dk_to_na = TRUE),
            ever_school = as_yn(s4aq1, "s4aq1"), education_level = as_cat(s4aq2, "s4aq2"),
            can_read = as_yn(s4bq4, "s4bq4"), can_calculate = as_yn(s4bq7, "s4bq7"),
            has_mobile = as_yn(s4bq8, "s4bq8"), phone_type = as_cat(s4bq10, "s4bq10"),
            used_internet_3m = as_yn(s4bq15, "s4bq15"), uses_mobile_money = as_yn(s4bq23c, "s4bq23c"),
            works_own_farm = as_yn(s6aq2, "s6aq2"), farm_output_use = as_cat(s6aq3, "s6aq3"),
            any_agri_activity = as_yn(s6aq4, "s6aq4"),
            hours_fetching_water_7d = as_num(s6cq2, "s6cq2", max_ok = 84),
            hours_work_week = as_num(s6bq1, "s6bq1", max_ok = 112),
            difficulty_max = pmax(as.numeric(s3q7), as.numeric(s3q8), as.numeric(s3q9), as.numeric(s3q10),
                                  as.numeric(s3q11), as.numeric(s3q12), na.rm = TRUE)) |>
  mutate(disability = case_when(difficulty_max >= 3 ~ 1L, difficulty_max %in% 1:2 ~ 0L),  # Washington Group cut-off
         education = harm_education(case_when(
           ever_school == 0L ~ "No formal education",
           education_level %in% c("ECD", "Nursery") ~ "No formal education",
           education_level == "Primary" ~ "Primary",
           education_level %in% c("INGOBOKA /Vocational training", "Lower secondary", "Upper secondary") ~ "Secondary / vocational",
           education_level == "Tertiary" ~ "Tertiary")), .keep = "all") |>
  select(-difficulty_max)
# The full EICV7 roster (migration, schooling costs, ICT, labour) stays in the raw file;
# only farm-relevant member variables are carried forward.
save_clean(mem24, "ahs2024_members")

# ---- 3.1 extension, groups, cooperatives (long by service) --------------------------
s6 <- read_ahs("2024", "s6")
ext24 <- s6 |>
  transmute(year = 2024L, hh_id = sprintf("%.0f", hhid), service = as_cat(s6q1, "s6q1"),
            members_ever = split_members(s6q2), members_season = split_members(s6q3),
            providers = split_codes(s6q4, letters_to_num = TRUE)) |>
  mutate(n_members_ever = lengths(members_ever), n_members_season = lengths(members_season)) |>
  filter(!is.na(service), service != "None")
prov_lab <- attr(s6$s6q4_1, "labels"); names(prov_lab) <- fix_text(names(prov_lab))
ext24_prov <- ext24 |> select(year, hh_id, service, providers) |> unnest(providers) |>
  mutate(provider = names(prov_lab)[match(providers, prov_lab)]) |> select(-providers)
ext24_mem <- ext24 |> select(year, hh_id, service, members_season) |> unnest(members_season) |>
  rename(member_no = members_season)
grp <- s6 |> group_by(hhid) |> slice(1) |> ungroup()
# DECISION: 2024 codes for cooperative type, cooperative services, grant type and grant
# origin have no value labels in the file. They are mapped with the 2020 questionnaire
# lists (same questions, same order) and marked "_assumed".
coop_type_lab   <- c("Crop producers", "Livestock producers", "Water users", "Apiculture", "Fishery", "Other")
coop_serv_lab   <- c("Farming advice", "Markets our products", "Access to farm inputs", "Storage facilities",
                     "Access to loan", "Share in the profit", "None", "Other")
grant_type_lab  <- c("Money", "Agricultural material/tools", "Post-harvest tools", "Other")
grant_orig_lab  <- c("Government", "NGOs", "Friends and relatives", "Company/Association", "Other")
multi_dummies <- function(codes, labs, prefix) {
  m <- map(seq_along(labs), \(k) map_int(codes, \(cc) as.integer(k %in% cc)))
  names(m) <- paste0(prefix, "_", str_to_lower(str_replace_all(labs, "[^A-Za-z]+", "_")) |> str_remove("_$"))
  as_tibble(m)
}
prog24 <- grp |>
  transmute(year = 2024L, hh_id = sprintf("%.0f", hhid),
            twigire_muhinzi = as_yn(s6q5, "s6q5"), farmer_field_school = as_yn(s6q6, "s6q6"),
            contract_farming = as_yn(s6q7, "s6q7"), crop_insurance = as_yn(s6q8, "s6q8"),
            livestock_insurance = as_yn(s6q9, "s6q9"), coop_member = as_yn(s6q10, "s6q10"),
            kitchen_garden = as_yn(s6q13, "s6q13"), grant_received = as_yn(s6q14, "s6q14"),
            n_members_coop = lengths(split_members(s6q10_a)), n_members_twigire = lengths(split_members(s6q5_a)))
prog24 <- bind_cols(prog24,
  multi_dummies(split_codes(grp$s6q11), coop_type_lab, "coop_type_assumed"),
  multi_dummies(split_codes(grp$s6q12), coop_serv_lab, "coop_service_assumed"),
  multi_dummies(split_codes(grp$s6q15), grant_type_lab, "grant_type_assumed"),
  multi_dummies(split_codes(grp$s6q16), grant_orig_lab, "grant_origin_assumed")) |>
  mutate(across(starts_with("coop_type") | starts_with("coop_service"), \(x) if_else(coop_member == 1L, x, NA_integer_)),
         across(starts_with("grant_type") | starts_with("grant_origin"), \(x) if_else(grant_received == 1L, x, NA_integer_)),
         water_user_coop = if_else(coop_member == 0L, 0L, coop_type_assumed_water_users))
save_clean(ext24 |> select(-members_ever, -members_season, -providers), "ahs2024_extension_services")
save_clean(ext24_prov, "ahs2024_extension_providers"); save_clean(ext24_mem, "ahs2024_extension_members")
save_clean(prog24, "ahs2024_programmes")

# ---- 3.2 sustainable agriculture -----------------------------------------------------
s8 <- read_ahs("2024", "s8")
# s8q3, s8q5, s8q6 options have no labels in the file or the NISR catalog: kept as
# option_<code> dummies until the questionnaire is available.
opt_dummies <- function(x, prefix) {
  codes <- split_codes(x); k <- sort(unique(unlist(codes)))
  m <- map(k, \(j) map_int(codes, \(cc) as.integer(j %in% cc))); names(m) <- paste0(prefix, "_option_", k)
  as_tibble(m)
}
sust24 <- bind_cols(
  s8 |> transmute(year = 2024L, hh_id = sprintf("%.0f", hhid),
                  aware_fertiliser_risk = as_yn(s8q1, "s8q1"), took_fertiliser_measures = as_yn(s8q2, "s8q2"),
                  aware_pesticide_risk = as_yn(s8q4, "s8q4")),
  opt_dummies(s8$s8q3, "fert_measure"), opt_dummies(s8$s8q5, "pest_measure"), opt_dummies(s8$s8q6, "env_measure"))
save_clean(sust24, "ahs2024_sustainable_agriculture")

# ---- 3.3 plots, crops, inputs, IRRIGATION (S3_4; 32,616 plot-season rows) ------------
s34 <- read_ahs("2024", "s34")
plots24 <- crops24 <- irrdet24 <- NULL
if (!is.null(s34)) {
  g <- \(v) if (v %in% names(s34)) s34[[v]] else rep(NA, nrow(s34))  # tolerate small name differences
  plots24 <- s34 |>
    transmute(year = 2024L, hh_id = sprintf("%.0f", hhid), season = as.character(as_factor(Season)),
              plot_no = as.integer(s2q1), plot_area_sqm = as_num(s2q2, "s2q2", na_codes = 9999, max_ok = 500000),
              n_crops = as.integer(s3_q3),
              organic_fert = as_yn(g("s4_q1"), "s4_q1"), organic_cost_rwf = as_num(g("s4_q3"), "s4_q3"),
              inorganic_fert = as_yn(g("s4_q4"), "s4_q4"), inorganic_source = as_cat(g("s4_q5"), "s4_q5"),
              pesticide = as_yn(g("s4_q12"), "s4_q12"),
              anti_erosion_this_season = as_yn(g("s4_q20"), "s4_q20"), anti_erosion_cost_rwf = as_num(g("s4_q21"), "s4_q21"),
              irrigated = as_yn(g("s4_q22"), "s4_q22"),
              irrig_technique_raw = as_cat(g("s4_q23"), "s4_q23"),
              irrig_cost_rwf = as_num(g("s4_q26"), "s4_q26"),
              mechanised = as_yn(g("s4_q27"), "s4_q27"), mech_type = as_cat(g("s4_q28"), "s4_q28"),
              mech_cost_rwf = as_num(g("s4_q29"), "s4_q29"), other_cost_rwf = as_num(g("s4_q30"), "s4_q30"),
              agroforestry = as_yn(g("s4_q31"), "s4_q31")) |>
    mutate(plot_area_ha = plot_area_sqm / 1e4, irrig_technique = harm_technique(irrig_technique_raw))
  ero_cols <- intersect(c("s4_q19_a1", "s4_q19_a2", "s4_q19_a3"), names(s34))
  plots24$erosion_measure_any <- if (length(ero_cols)) as.integer(rowSums(!is.na(s34[ero_cols]) & s34[ero_cols] != 0) > 0) else NA_integer_
  key <- c("hhid", "Season", "s2q1")
  irrdet24 <- bind_rows(
    slots_long(s34, key, intersect(paste0("s4_q24_", 1:3), names(s34)), "category_raw") |> mutate(dimension = "water_source"),
    slots_long(s34, key, intersect(paste0("s4_q25_", 1:2), names(s34)), "category_raw") |> mutate(dimension = "tool")) |>
    transmute(year = 2024L, hh_id = sprintf("%.0f", hhid), season = as.character(as_factor(Season)), plot_no = as.integer(s2q1),
              slot, dimension, category_raw,
              category = if_else(dimension == "tool", harm_tool(category_raw), harm_water(category_raw))) |>
    bind_rows(plots24 |> filter(!is.na(irrig_technique_raw)) |>
                transmute(year, hh_id, season, plot_no, slot = 1L, dimension = "technique",
                          category_raw = as.character(irrig_technique_raw), category = irrig_technique))
  # Crops: 7 slots per plot, ~24 questions each (names follow s3_q4_<k>, s3_q20_<k>, ...)
  crop_slot <- function(k) {
    v <- \(stem) { cands <- c(sprintf(stem, k)); cands[cands %in% names(s34)][1] }
    get <- \(stem) { nm <- v(stem); if (is.na(nm)) rep(NA_real_, nrow(s34)) else s34[[nm]] }
    tibble(year = 2024L, hh_id = sprintf("%.0f", s34$hhid), season = as.character(as_factor(s34$Season)),
           plot_no = as.integer(s34$s2q1), slot = k,
           crop_code = as.integer(zap_labels(get("s3_q4_%d"))), crop = as_cat(get("s3_q4_%d"), paste0("s3_q4_", k)),
           crop_share_pct = as_num(get("s3_q4_%da"), max_ok = 100), crop_density_pct = as_num(get("s3_q4_%db"), max_ok = 100),
           seed_type = as_cat(get("s3_q9_%d"), paste0("s3_q9_", k)),
           improved_seed_source = as_cat(get("s3q10_%d"), paste0("s3q10_", k)),
           trad_seed_qty = as_num(get("s3_q11b_%d")), trad_seed_spent_rwf = as_num(get("s3_q13_%d")),
           impr_seed_qty = as_num(get("s3_q14b_%d")), impr_seed_spent_rwf = as_num(get("s3_q16_%d")),
           harvest_kg = as_num(get("s3_q20_%d"), paste0("s3_q20_", k)),
           production_vs_normal = as_cat(get("s2q23_%d"), paste0("s2q23_", k))) |>
      mutate(across(c(crop, seed_type, improved_seed_source, production_vs_normal), as.character))  # slots differ in labels
  }
  crops24 <- map_dfr(1:7, crop_slot) |> filter(!is.na(crop_code)) |>
    mutate(improved_seed = as.integer(str_detect(str_to_lower(as.character(seed_type)), "improved|both")))
  check("plot rows with area missing or implausible", sum(is.na(plots24$plot_area_sqm)), nrow(plots24), "kept as missing")
  save_clean(plots24, "ahs2024_plots"); save_clean(crops24, "ahs2024_plot_crops"); save_clean(irrdet24, "ahs2024_irrigation_detail")
} else {
  message("   2024 S3_4 (crops, inputs, irrigation) not found - 2024 practice indicators left empty")
}

# ============================================================================
# 4. HARMONISED TABLES (all years)
# ============================================================================
message("4/5 Harmonised household, member, extension and irrigation tables")
set_ctx("harmonised")
heads <- function(m, head_level) m |> filter(relation == head_level) |> group_by(hh_id) |> slice(1) |> ungroup() |>
  transmute(hh_id, head_sex = as.character(sex), head_age = age, head_education = education)
size  <- function(m) m |> count(hh_id, name = "hh_size")

members <- bind_rows(
  mem17 |> transmute(year, hh_id, member_no, sex = as.character(sex), age, education, is_head = relation == "Head"),
  mem20 |> transmute(year, hh_id, member_no, sex = as.character(sex), age, education, is_head = relation == "Head"),
  mem24 |> transmute(year, hh_id, member_no, sex = as.character(sex), age, education, is_head = relation == "Household head (HH)")) |>
  mutate(hh_key = paste(year, hh_id, sep = "_"), .after = hh_id)

# 2017: practices and inputs (any season)
hh17 <- listing17 |> filter(is_agri_hh == 1) |>
  left_join(heads(mem17, "Head"), by = "hh_id") |> left_join(size(mem17), by = "hh_id") |>
  left_join(prac17 |> select(hh_id, grows_crops, irrigates, erosion_control, mechanised), by = "hh_id") |>
  left_join(inputs17 |> transmute(hh_id,
              organic_fert = pmax(organic_A, organic_B, na.rm = TRUE), inorganic_fert = pmax(inorganic_A, inorganic_B, na.rm = TRUE),
              pesticide = pmax(pesticide_A, pesticide_B, na.rm = TRUE)), by = "hh_id") |>
  left_join(seeds17 |> group_by(hh_id) |> summarise(improved_seed = any1(improved_seed)), by = "hh_id") |>
  left_join(prog17, by = c("hh_id", "year")) |>
  left_join(ext17 |> group_by(hh_id) |> summarise(extension_water = as.integer(any(service == "Water harvesting techniques"))), by = "hh_id") |>
  left_join(irrdet17 |> filter(dimension == "technique") |> group_by(hh_id) |>
              summarise(irrig_technique = first(category), irrig_modern = as.integer(any(category %in% modern_techniques))), by = "hh_id") |>
  left_join(irrdet17 |> filter(dimension == "water_source", slot == 1) |> select(hh_id, irrig_water_source = category), by = "hh_id") |>
  mutate(improved_seed = coalesce(improved_seed, if_else(grows_crops == 1L, 0L, NA_integer_)),
         extension_water = if_else(extension_any == 0L, 0L, coalesce(extension_water, 0L)),
         water_user_coop = as.integer(coalesce(str_detect(as.character(coop_type), "[Ww]ater"), FALSE)),
         psu = segment_id, strat = paste(district, stratum, sep = "_"))

hh20h <- hh20 |>
  left_join(heads(mem20, "Head"), by = "hh_id") |> left_join(size(mem20), by = "hh_id") |>
  left_join(prac20 |> select(-year), by = "hh_id") |>
  left_join(plots20 |> group_by(hh_id) |> summarise(
    n_plots = n(), farm_area_ha = sum(plot_area_ha, na.rm = TRUE),
    land_consolidated = any1(in_consolidation), mechanised = any1(mechanised)), by = "hh_id") |>
  left_join(prog20 |> select(-year), by = "hh_id") |> left_join(fin20 |> select(-year), by = "hh_id") |>
  left_join(assets20, by = "hh_id") |>
  left_join(ext20 |> group_by(hh_id) |> summarise(extension_any = 1L), by = "hh_id") |>
  mutate(extension_any = coalesce(extension_any, 0L),
         irrig_modern = if_else(irrigates == 1L, as.integer(irrig_technique %in% modern_techniques), NA_integer_),
         irrig_motorised = if_else(irrigates == 1L, as.integer(irrig_tool == "Pump / machine"), NA_integer_),
         psu = hh_id, strat = district)   # 2020 file has no PSU: households treated as PSUs within district

hh24h <- hh24 |>
  left_join(heads(mem24, "Household head (HH)"), by = "hh_id") |> left_join(size(mem24), by = "hh_id") |>
  left_join(prog24 |> select(-year), by = "hh_id") |> left_join(sust24 |> select(-year), by = "hh_id") |>
  left_join(ext24 |> group_by(hh_id) |> summarise(extension_any = 1L,
              extension_irrigation = as.integer(any(service == "Irrigation system"))), by = "hh_id") |>
  mutate(extension_any = coalesce(extension_any, 0L), extension_irrigation = coalesce(extension_irrigation, 0L),
         psu = cluster, strat = district)
if (!is.null(plots24)) {
  hh24h <- hh24h |> left_join(plots24 |> group_by(hh_id) |> summarise(
      grows_crops = 1L, n_plot_seasons = n(), farm_area_ha = sum(plot_area_ha[season == first(season)], na.rm = TRUE),
      irrigates = any1(irrigated), organic_fert = any1(organic_fert), inorganic_fert = any1(inorganic_fert),
      pesticide = any1(pesticide), mechanised = any1(mechanised), agroforestry = any1(agroforestry),
      erosion_control = any1(erosion_measure_any),
      irrig_modern = if (any(irrigated == 1, na.rm = TRUE)) as.integer(any(irrig_technique %in% modern_techniques)) else NA_integer_,
      .groups = "drop"), by = "hh_id") |>
    left_join(crops24 |> group_by(hh_id) |> summarise(improved_seed = any1(improved_seed)), by = "hh_id") |>
    left_join(irrdet24 |> filter(dimension == "tool") |> group_by(hh_id) |>
                summarise(irrig_motorised = as.integer(any(category == "Pump / machine"))), by = "hh_id") |>
    mutate(grows_crops = coalesce(grows_crops, 0L))
}

keep_cols <- c("year", "hh_id", "province", "district", "district_code", "weight", "psu", "strat",
  "is_agri_hh", "grows_crops", "hh_size", "head_sex", "head_age", "head_education", "ubudehe",
  "irrigates", "irrig_technique", "irrig_modern", "irrig_water_source", "irrig_tool", "irrig_motorised",
  "improved_seed", "organic_fert", "inorganic_fert", "pesticide", "erosion_control", "agroforestry", "mechanised",
  "n_plots", "farm_area_ha", "land_consolidated",
  "extension_any", "extension_water", "extension_irrigation", "twigire_muhinzi", "farmer_field_school",
  "contract_farming", "crop_insurance", "coop_member", "water_user_coop", "kitchen_garden", "grant_received", "girinka_cow",
  "bank_account", "savings", "loan_requested", "loan_any_rejected", "has_radio", "has_telephone", "has_television", "has_access",
  "aware_fertiliser_risk", "aware_pesticide_risk")
household <- bind_rows(hh17 |> mutate(is_agri_hh = 1L), hh20h |> mutate(is_agri_hh = 1L), hh24h) |>
  mutate(ubudehe = as.character(ubudehe), irrig_tool = as.character(irrig_tool)) |>
  select(any_of(keep_cols)) |>
  rename(has_internet = any_of("has_access")) |>
  mutate(hh_key = paste(year, hh_id, sep = "_"), .after = hh_id,
         head_age_band = cut(head_age, c(-Inf, 34, 54, Inf), labels = c("Under 35", "35-54", "55+")),
         farm_size_band = cut(farm_area_ha, c(-Inf, 0.25, 0.5, 1, Inf), labels = c("< 0.25 ha", "0.25-0.5 ha", "0.5-1 ha", "> 1 ha")),
         crop_grower = as.integer(is_agri_hh == 1L & coalesce(grows_crops, 1L) == 1L)) |>
  relocate(head_age_band, .after = head_age) |> relocate(farm_size_band, .after = farm_area_ha) |>
  relocate(crop_grower, .after = grows_crops)
stopifnot(!any(duplicated(household$hh_key)))
check("households missing district", sum(is.na(household$district)), nrow(household), "none expected")
check("households missing head", sum(is.na(household$head_sex)), nrow(household), "kept")
saveRDS(household, file.path(dir_ahs, "ahs_household.rds"), compress = "xz")
saveRDS(members, file.path(dir_ahs, "ahs_members.rds"), compress = "xz")

extension <- bind_rows(
  ext17 |> transmute(year, hh_id, service = as.character(service), provider = as.character(provider)),
  ext20 |> transmute(year, hh_id, service = as.character(service), provider = as.character(provider)),
  ext24_prov |> transmute(year, hh_id, service = as.character(service), provider)) |>
  mutate(theme = case_when(
    str_detect(service, regex("irrigat|water harvest", TRUE)) ~ "Irrigation / water",
    str_detect(service, regex("fertili|cropping|crop protection|breeding|pest", TRUE)) ~ "Crop practices and inputs",
    str_detect(service, regex("soil|erosion", TRUE)) ~ "Soil and erosion",
    str_detect(service, regex("post.?harvest|storage", TRUE)) ~ "Post-harvest",
    str_detect(service, regex("animal|veterin|livestock|bee|fodder|sanitation", TRUE)) ~ "Livestock",
    str_detect(service, regex("weather|climate", TRUE)) ~ "Weather and climate",
    str_detect(service, regex("saving|financ|agribusiness|cooperative", TRUE)) ~ "Business and finance",
    TRUE ~ "Other"))
saveRDS(extension, file.path(dir_ahs, "ahs_extension.rds"), compress = "xz")
irrigation_detail <- bind_rows(irrdet17, irrdet20, irrdet24) |>
  left_join(household |> select(year, hh_id, district, province, weight), by = c("year", "hh_id"))
saveRDS(irrigation_detail, file.path(dir_ahs, "ahs_irrigation_detail.rds"), compress = "xz")

# ============================================================================
# 5. SURVEY-WEIGHTED INDICATORS (same columns as est_plot.rds; source = "AHS")
# ============================================================================
message("5/5 Weighted indicators with 95% CI (national, province, district)")
ind_crop <- c("irrigates", "improved_seed", "organic_fert", "inorganic_fert", "pesticide", "erosion_control",
              "agroforestry", "mechanised", "land_consolidated")
ind_all  <- c("extension_any", "extension_water", "extension_irrigation", "twigire_muhinzi", "farmer_field_school",
              "contract_farming", "crop_insurance", "coop_member", "water_user_coop", "kitchen_garden", "grant_received",
              "girinka_cow", "bank_account", "savings", "loan_requested", "has_radio", "has_telephone", "has_internet",
              "aware_fertiliser_risk", "aware_pesticide_risk")
# DECISION (user, 2026-10-14): denominator = all farm households. A farm household that
# grew no crops did not irrigate or use crop inputs, so its missing practice answers are 0.
# The 0-fill only applies in years where the question was asked (agroforestry and land
# consolidation do not exist in 2017; land consolidation does not exist in 2024).
fill_non_growers <- function(x, grows) {
  x <- as.integer(x)
  if (all(is.na(x[coalesce(grows, 1L) == 1L]))) return(rep(NA_integer_, length(x)))
  if_else(is.na(x) & coalesce(grows, 1L) == 0L, 0L, x)
}
# Strata are passed to survey as integer codes: newer versions of the survey package
# turn character strata into NA when a stratum has a single PSU (lonely.psu = "adjust"),
# which gave SE = Inf for every 2017 estimate on the first real run.
agri_hh <- household |> filter(is_agri_hh == 1L, !is.na(weight), weight > 0) |>
  mutate(land_consolidated = if_else(is.na(land_consolidated) & year == 2020L & is.na(n_plots), 0L, land_consolidated)) |>
  group_by(year) |> mutate(across(any_of(ind_crop), \(x) fill_non_growers(x, grows_crops))) |> ungroup() |>
  mutate(strat = as.integer(factor(paste(year, strat))), psu = as.character(psu))
irr_hh  <- agri_hh |> filter(irrigates == 1L)
est_ahs <- function(d, vars, by_extra, level, area_col) {
  vars <- vars[vars %in% names(d)]
  map_dfr(vars, \(v) survey_mean_by(d, v, c("year", by_extra))) |>
    mutate(level = level, area = if (is.null(area_col)) "Rwanda" else .data[[area_col]])
}
levels_def <- list(list(character(), "national", NULL), list("province", "province", "province"), list("district", "district", "district"))
indicators <- map_dfr(levels_def, \(L) bind_rows(
  est_ahs(agri_hh, c(ind_crop, ind_all), L[[1]], L[[2]], L[[3]]) |> mutate(population = "Farm households"),
  est_ahs(irr_hh, c("irrig_modern", "irrig_motorised"), L[[1]], L[[2]], L[[3]]) |> mutate(population = "Irrigating households"))) |>
  mutate(across(c(estimate, se, ci_low, ci_high), \(x) 100 * x), source = "AHS",
         series_break = year == 2024L,
         series_note = if_else(series_break, "2024: plot-level questions on the EICV7 sub-sample; not directly comparable with 2017-2020", NA_character_)) |>
  select(source, level, area, year, indicator, population, estimate, se, ci_low, ci_high, n, wsum, cv, reliability,
         series_break, series_note)
# Equity cuts for household irrigation (national, by year)
equity <- map_dfr(c("head_sex", "head_age_band", "head_education", "ubudehe", "farm_size_band"), \(g)
  agri_hh |> filter(!is.na(.data[[g]])) |> mutate(group = as.character(.data[[g]])) |>
    survey_mean_by("irrigates", c("year", "group")) |> mutate(dimension = g)) |>
  mutate(across(c(estimate, se, ci_low, ci_high), \(x) 100 * x), source = "AHS", series_break = year == 2024L)
# Technique / water source / tool mix among irrigating households (weighted shares)
irrigation_mix <- irrigation_detail |> filter(!is.na(weight)) |>
  group_by(year, dimension, hh_id) |> mutate(w = weight / n()) |>      # split weight across multiple answers
  group_by(year, dimension, category) |> summarise(w = sum(w), n = n_distinct(hh_id), .groups = "drop_last") |>
  mutate(share = 100 * w / sum(w)) |> ungroup() |> mutate(series_break = year == 2024L)
saveRDS(list(indicators = indicators, equity = equity, irrigation_mix = irrigation_mix,
             built = format(Sys.time(), "%Y-%m-%d %H:%M")),
        file.path(dir_ahs, "ahs_indicators.rds"), compress = "xz")

# ---- logs and dictionary -------------------------------------------------------------
dict <- bind_rows(.dict$rows)
write_csv(dict, file.path(dir_ahs, "ahs_variable_dictionary.csv"))
write_csv(bind_rows(.log$rows), file.path(dir_ahs_log, "ahs_cleaning_log.csv"))
write_csv(bind_rows(.chk$rows), file.path(dir_ahs_log, "ahs_checks.csv"))

message(sprintf("Done in %.1f min. Households: %s. Indicators: %d rows.",
                as.numeric(difftime(Sys.time(), t0, units = "mins")),
                paste(names(table(household$year)), table(household$year), sep = "=", collapse = ", "), nrow(indicators)))
print(indicators |> filter(level == "national") |> select(year, indicator, estimate, ci_low, ci_high, n, reliability) |>
        mutate(across(where(is.numeric), \(x) round(x, 1))) |> arrange(indicator, year), n = 100)
