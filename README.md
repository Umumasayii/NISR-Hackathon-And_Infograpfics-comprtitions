# SmartIrrigate Rwanda

**Which districts should agricultural planners assess first for small-scale irrigation, why, and what
evidence must they collect before recommending investment?**

SmartIrrigate Rwanda is a decision-support website for a district planning officer. It turns the NISR
Seasonal Agricultural Survey (SAS) 2019–2025, NISR's published tables and CHIRPS rainfall into a short,
evidence-backed shortlist, and then helps the officer record the feasibility checks that the survey
cannot answer (water source, land, energy, cost, markets, environment) and export a district
assessment brief.

- Live site: https://niyoishimwe.vercel.app/ (English, Kinyarwanda, French; installable, works offline)
- Entry: NISR 2026 Big Data Hackathon. Powered by Team NiyoIshimwe.
- It is a screening aid. It does not decide who gets investment, and it makes no causal claims.

## Planner journey

1. **Understand**: Overview, irrigation today, with NISR published figures first.
2. **Compare**: Priority shortlist. Adjustable weights; a criterion set to zero stays exactly zero;
   rank ranges show how much the order depends on the weights.
3. **Inspect evidence**: District page, Evidence (yields), Methods (definitions, reconciliation with NISR).
4. **Record feasibility checks**: Assess page. Each check is marked *measured*, *documented*,
   *assumed* or *unknown* (the default). Notes stay in the browser.
5. **Export**: a one-page district assessment brief (HTML) and a CSV of the checks.

Advanced (models, households, data explorer) sits under its own menu.

## Team

> To be completed by the team: member names, roles, institution, contact, and the eligibility and
> originality declarations. These are not filled in on purpose: they must come from the team.

## Run it

Requirements: R ≥ 4.3 with `dplyr`, `tidyr`, `purrr`, `stringr`, `readr`, `forcats`, `survey`, `haven`,
`ranger`, `readxl`, `sf`, `jsonlite`, `openssl`; Node ≥ 20 for the website.

```r
# from the project root (the folder that holds DATA/ and SCRIPTS/)
source("SCRIPTS/03_Data_Preparation.R")   # once: reads the 111 SAS files, CHIRPS and GADM
source("SCRIPTS/09_Run_All.R")            # 05, 06, (10), 11, 14, 15, 07, 08, 12, 16
shiny::runApp("SCRIPTS/app")              # optional Shiny version
```

```bash
cd SCRIPTS/web
npm ci
npm test          # unit tests for the ranking (weights, zero criteria, Dirichlet sensitivity)
npm run dev       # local site;  npm run build  for production files
```

R tests: `Rscript SCRIPTS/tests/test_core.R` (synthetic checks of the helpers) and
`Rscript SCRIPTS/tests/test_pooled_variance.R` (needs the microdata; checks the pooled-season
variance against `survey::svymean`).

Every build writes `docs/build_manifest.json`: build time, git commit, R and package versions and
SHA-256 checksums of every input and web output.

## Inputs (not in this repository)

| Input | Where it goes | Note |
|---|---|---|
| NISR SAS 2019–2025 microdata (111 .sav/.dta) | `DATA/SAS/` | Licensed by NISR; never published here |
| NISR AHS 2017/2020/2024 (optional) | `DATA/Agriculture Household Survey/` | Licensed by NISR |
| NISR SAS annual tables 2019–2025 (.xlsx) | `DATA/NISR_published/` | Public NISR releases, committed |
| CHIRPS district-month rainfall 1981–2025 | `DATA/CHIRPS/` | See source register |
| GADM 4.1 Rwanda boundaries | `DATA/GADM/` | Licence to be confirmed by the team |

2026 survey data are excluded on purpose. No microdata, survey weights or record-level files are ever
exported; the website reads aggregates only.

## Scripts

| Script | Role |
|---|---|
| `00_Config.R` | Shared helpers: survey ratio estimates, reliability rules, pooled-season variance |
| `03_Data_Preparation.R` | Reads, renames and labels all SAS files, CHIRPS and GADM |
| `04_Load_Data.R`, `05_Select_Irrigation_Data.R` | Load prepared files; select irrigation columns |
| `06_Merge_Master_Data.R` | Plot, crop and farmer master tables |
| `07_Build_App_Data.R` | Survey-weighted estimates, yields, rain index, priority screening |
| `08_Models.R` | Adoption classifier and adjusted yield associations (Advanced) |
| `10_AHS_Preparation.R` | AHS household indicators (optional) |
| `11_NISR_Published_Tables.R`, `14_Official_Reference.R` | Every cell of the NISR workbooks; published figures shown first |
| `15_Reconcile_With_NISR.R` | Our estimates recomputed several ways beside NISR's cells |
| `12_Export_Web_Data.R` | JSON for the website (aggregates only) |
| `16_Build_Manifest.R` | Build manifest and reconciliation register |
| `09_Run_All.R` | Runs the above in order |
| `13_Push_To_GitHub.R` | Optional helper; never run by 09 |

Not part of the pipeline (kept for the record): `001_chrips.R` (early exploration),
`01_Load_SAS_2019_2025.R` and `02_Rename_and_Label_SAS_2019_2025.R` (replaced by 03),
`Crop Production 2019.Rmd`, `github push.R`, `Gathering Data/`, `Analysis_d.Rmd` and
`Mugemangango_Analysis_Corrections/` (unrelated analyses).

## Documentation

- [Methods and reconciliation](docs/Methods_and_Reconciliation.md): definitions, estimators, every gap with NISR and its cause
- [Data dictionary](docs/Data_Dictionary.md) · [Source register](docs/Source_Register.md)
- [Reconciliation register (CSV)](docs/Reconciliation_Register_2019_2025.csv): each NISR cell beside our value
- [Limitations and pilot plan](docs/Limitations_and_Pilot_Plan.md)
- [AI-use disclosure](docs/AI_Use_Disclosure.md)
- Earlier notes: `docs/Audit_Fixes_2019_2025.md`, `docs/NISR_Primary_2019_2025.md`, `DOCS/Data_Check_v0.2.md`

## Licence

To be chosen by the team (code licence, and terms for GADM and CHIRPS reuse).
