# Source register

Every figure on the website comes from one of these sources. NISR published values are shown first
where the definition matches ours; our estimates are a labelled cross-check.

| Source | Publisher | Years used | Files | Used for | Status |
|---|---|---|---|---|---|
| Seasonal Agricultural Survey (SAS) microdata | NISR | 2019–2025, seasons A, B, C | 111 .sav/.dta in `DATA/SAS/` (checksums in `build_manifest.json`) | All project estimates, yields, models | Licensed; not redistributed. 2020 is USAS (questionnaire upgrade): no trend drawn across 2019/2020 |
| SAS annual tables | NISR | 2019, 2020 (USAS), 2021, 2022, 2023, 2024, 2025 | `DATA/NISR_published/*.xlsx` | Published figures shown first; reconciliation | Public. Each figure keeps its file, sheet and cell. A season printed twice keeps the later release |
| Agricultural Household Survey (AHS) | NISR | 2017, 2020, 2024 | `DATA/Agriculture Household Survey/` | Households page | Optional input. 2024 is a series break |
| CHIRPS v2.0 rainfall | Climate Hazards Center, UC Santa Barbara (Funk et al., 2015, *Scientific Data* 2:150066) | 1981–2025 monthly | `DATA/CHIRPS/CHRIPS District-Month 1981-2025 data.csv` | Rain-shortfall history index | **Provenance gap:** how the 0.05° grid was aggregated to districts (mean of cells, area-weighted, boundary version) is not documented in the file. Needs confirming from whoever exported it |
| GADM 4.1 administrative boundaries | GADM | — | `DATA/GADM/gadm41_RWA_*.shp` | Maps, district names | Licence allows non-commercial use; team to confirm terms for the entry |

## What is not used

- No 2026 survey data or 2026 statistics (scope decision, 2026-10-20).
- No household identifiers, coordinates or record-level data leave the build computer.
- The competition rules page (statistics.gov.rw) could not be fetched from the build environment;
  the team should confirm the rules directly, including keeping the hackathon entry separate from
  any infographics entry.
