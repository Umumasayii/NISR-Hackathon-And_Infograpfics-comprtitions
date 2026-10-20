# Audit response, SmartIrrigate Rwanda v0.8 (2026-10-16)

This note answers the external audit item by item: what changed, where, and what is still open. The full pipeline (06 → 07 → 08) was rerun on the current selection files, and the app was tested on all 12 pages in English, Kinyarwanda and French with no errors.

## Fix these first

| # | Audit item | What we did | Where |
|---|---|---|---|
| 1 | **Critical:** 2021B district totals counted twice | Every measure is now built at the same district × year × season grain. The province is added afterwards from a single district → province lookup, which also fills the 2021B/C rows where it was missing. The build **stops** if a district-season appears twice, or if district totals differ from national totals by more than 0.5%. Result: 2021B district production now equals the national figure exactly (ratio 1.000 in every season). | `06_Merge_Master_Data.R` §4, §7; `DATA/processed/master/district_national_reconciliation.csv` |
| 2 | Irrigation KPI definitions | **Farmers irrigating** is now computed from a new farmer table: one row per farmer and season, from 2020. The farmer weight is the average of the farmer's plot weights, because SAS has no separate farmer weight. 2025A: 13.5% (95% CI 12.4–14.7). The NISR official figure for 2026A is 14.4%, and it is shown beside ours as a separate benchmark. **Irrigated area** is relabelled everywhere as "area of plots that report irrigation" (whole plot area, not hectares watered). The Overview now shows the average per main season, not A + B added together, because both seasons farm the same land. Policy targets appear only on Methods, with sources and a note that the definitions differ. | `06` §5b (`master_farmer`); `07` §2; `mod_overview.R`; Methods → KPI definitions |
| 3 | 2024B/C yields gated on coverage | Seasons where fewer than 80% of harvested crop plots have a crop area are excluded from every yield result: 2024B (46%) and 2024C (7%). This covers the yield comparisons, the input ladder and the adjusted yield model. The yearly A+B chart also leaves out 2024, so that one year is not silently Season A only. Coverage is shown by season on Methods → Data quality. | `06` (`season_quality.csv`, `season_yield_usable`); `07` §4; `08` part B |
| 4 | Duplicate join rows kept silently | Duplicate rows on a join key are now **combined**, not dropped. A 0/1 field is yes if any row says yes. Values that disagree become unknown. The number of combined keys and field conflicts is written to the join log (15 joins have duplicates, mostly 2022C and 2024C, where the keys are weak). The build stops if a join ever adds rows. When no key is usable, the join stays unknown and never becomes "No". | `06` §3 (`collapse_dups`, `season_join`); `master_join_log.csv` |
| 5 | Screening, not impact | Wording is reviewed in EN, FR and RW. The hero now asks "Which districts should be checked first for small-scale irrigation?" Findings say "goes with" or "a link, not proof". "Hidden potential" is now a "prediction gap". The simulator caveat says that changing inputs there does not mean farmers would irrigate. "Readiness" is now "current input use (proxy)". The priority page is a **shortlist for field checks**. It has a "Still unknown" card listing water, schemes, irrigable land, infrastructure, water user associations, permits, costs and markets; a "Why listed" column; and a CSV shortlist download. | `i18n/build_translations.py`; `mod_priority.R`; `07` §8 |

## Other corrections

- **Unknown stays unknown.** In the yield model, missing fertiliser and seed values are now an "Unknown" category instead of being set to 0. A complete-case fit is stored as a sensitivity check. It gives the same results, because those inputs are recorded for 100% of the eligible plots. Missing farmer type is now "Unknown" in the adoption model; before, it was counted as small-scale. Files: `08_Models.R`.
- **Inputs ladder.** It now counts improved seed, chemical fertiliser and machines (0–3). Irrigation is no longer counted. A plot is left out when any of the three inputs is unknown. The share of plots with all three recorded is saved (`ladder_observed`). The plot-level version, which had a different definition, was removed. Files: `06` §5, `07` §4.
- **Gross sales value.** The share of value that uses an imputed price is now reported (`sales_value_imputed_pct`), and the definition says "not income or profit". Files: `06` §7, Methods → KPI definitions.
- **"Other" categories.** The team rule stays: these categories are not shown. Each technology chart now says it shows the share of named answers, and how many answers were "other" or not stated. Files: `07` §5, `mod_how.R`.
- **Survey uncertainty.**
  - Strata are now season × district × land-use stratum, and PSUs are segments within a season.
  - Districts, gender, crops and other groups are estimated as domains of the full season design, never by cutting the data first.
  - Pooled periods add up the independent season samples.
  - CIs use the t distribution with the design's degrees of freedom.
  - Every estimate carries `n_psu` (the number of segments). The reliability label now also needs at least 12 segments for "Good"; fewer than 5 segments means "Not reliable".
  - The variance code reproduces `survey::svyby(…, svytotal)` exactly and runs about 8× faster.
  - Files: `00_Config.R`.
- **Code-label review** for the 195 priority entries. **Not done in this round.** It needs the questionnaires for each year. Focus: irrigation source and tool, farmer type, crop codes.

## Data still to add

| Item | Status |
|---|---|
| NISR SAS 2026A official benchmark (14.4% of farmers) | Added as a benchmark on the Overview farmers card (national view) and on Methods. |
| NST2 / MINAGRI irrigation-area targets | Added on Methods only, with sources, periods and a note that the definitions differ from survey plot area. |
| SAS 2026 Season A and B microdata | Being prepared in a separate thread; it will flow into 06–08 when ready. |
| Water, scheme and feasibility data | Not available yet. The app lists these items as "still unknown" on the shortlist page. |
| Unit costs and market viability | Not available yet. Listed the same way; no return on investment is computed. |

## What to rerun

Run `source("SCRIPTS/09_Run_All.R")` with `run_select = FALSE`. The selection files did not change. The `SCRIPTS/app/data/*.rds` files delivered with v0.8 were already rebuilt this way, so the app also works without the rerun. The whole build now takes about 7 minutes.
