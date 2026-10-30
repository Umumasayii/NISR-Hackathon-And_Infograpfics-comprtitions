<img src="SCRIPTS/web/public/logo.svg" width="96" alt="SmartIrrigate Rwanda logo">

# SmartIrrigate Rwanda
- Live DEMO: https://youtu.be/CgHXCgNMi4c
- Web app: https://niyoishimwe.vercel.app
- Shiny app: https://niyobyosebranchal.shinyapps.io/NiyoIshimweAPP/
- Demo video (2:30): [`demo/NISR Submission.webm`](demo/NISR%20Submission.webm)
- Eligibility documents (student cards, both members): [`student_cards/`](student_cards/)

---

## Problem

Most Rwandan farmers depend on rain, and the rain is becoming less reliable. Farmers who
irrigate get bigger harvests, yet only a small share irrigate. Planners have no single place
that shows **where rain fails most, who already irrigates, and where support would pay off
first.**

##  Solution

A dashboard that brings together **7 years of NISR farm surveys** and **45 years of satellite
rainfall data** to answer one planning question: **which districts should planners assess
first for small-scale irrigation, why, and what evidence must they collect before recommending
investment?**

| | |
|---|---|
| **The gap** | How many farmers and how much land are irrigated, by district, since 2019? |
| **The need** | Where is rain short or unreliable, and is irrigation happening there? |
| **The payoff** | How do harvests on irrigated plots compare with rain-fed plots? |
| **The action** | A **ranked district shortlist** for field checks, with weights you can adjust and a CSV download |
| **The checks** | A district **assessment page**: record what is measured, documented, assumed or still unknown, and download a one-page brief |

Every number shows its reliability. NISR's published figures come first, and our own
estimates sit beside them, clearly labelled. It works on a phone, offline, in three languages.
It is a screening aid: it does not decide who gets investment, and it makes no causal claims.

### A planner's path through the app

1. **Understand**: Overview, irrigation today, with NISR's published figures first.
2. **Compare**: Priority shortlist. A criterion set to zero stays exactly zero; rank ranges show
   how much the order depends on the weights.
3. **Inspect the evidence**: District page, Evidence (yields), Methods (definitions and every
   gap with NISR's tables).
4. **Record feasibility checks**: Assess page. Water source, schemes, land, energy, cooperative
   interest, markets, costs and environment each start as *unknown*. Notes stay in the browser.
5. **Export**: a district assessment brief (HTML) and a CSV of the checks.

##  Relevance to the hackathon

| Track 1 asks for | SmartIrrigate |
|---|---|
| A real challenge such as small-scale irrigation | Irrigation is the core topic |
| Informed by NISR data | Seasonal Agricultural Survey 2019–2025, Agricultural Household Survey 2017–2024, NISR published tables |
| Open climate data | CHIRPS rainfall 1981–2025, GADM district maps |
| Innovation | Satellite rainfall combined with survey data, a district priority index, an offline web app |
| Practical impact | A shortlist and assessment brief that district planners, MINAGRI, RAB and extension officers can act on |

##  Tech stack

<p align="center">
  <img src="Data%20pipeline%20(technical)%401x.png" width="900" alt="SmartIrrigate data pipeline: NISR surveys, NISR tables, CHIRPS and GADM feed the R pipeline (read and label, clean and merge, estimate and model, verify and export); only aggregates pass the export gate, to the Shiny app on shinyapps.io and the React web app on Vercel">
</p>

### 1. Data pipeline (R)

The heavy work happens here, before any user opens the app.

| Package | What it does in this project |
|---|---|
| `haven`, `labelled` | Read the NISR survey files (SAS and Stata) and keep their variable and value labels |
| `readxl` | Read every cell of NISR's published Excel tables, so official figures can be shown with their file, sheet and cell |
| `dplyr`, `tidyr`, `purrr`, `stringr`, `readr` | Clean, rename and merge 7 years of surveys into one consistent dataset |
| `survey` | Survey-weighted estimates with standard errors from the survey design (strata and clusters) |
| `sf` | Read the GADM district boundaries and build the district maps |
| `ranger` | Random forest model of which plot and farm features go with irrigation |
| `jsonlite`, `openssl` | Export the final aggregates as JSON for the web app; checksums for the build manifest |

The scripts are numbered in run order, and `SCRIPTS/09_Run_All.R` runs them all. Only
aggregated estimates leave the pipeline: survey microdata and weights are never published.

| Script | Role |
|---|---|
| `00_Config.R` | Shared helpers: survey ratio estimates, reliability rules, pooled-season variance |
| `03_Data_Preparation.R` | Reads, renames and labels all SAS files, CHIRPS and GADM |
| `04_Load_Data.R`, `05_Select_Irrigation_Data.R` | Load prepared files; select irrigation columns |
| `06_Merge_Master_Data.R` | Plot, crop and farmer master tables |
| `07_Build_App_Data.R` | Survey-weighted estimates, yields, rain index, priority screening |
| `08_Models.R` | Adoption classifier and adjusted yield associations (Advanced pages) |
| `10_AHS_Preparation.R` | AHS household indicators (optional input) |
| `11_NISR_Published_Tables.R`, `14_Official_Reference.R` | Every cell of the NISR workbooks; published figures shown first |
| `15_Reconcile_With_NISR.R` | Our estimates recomputed several ways beside NISR's cells |
| `12_Export_Web_Data.R` | JSON for the web app (aggregates only) |
| `16_Build_Manifest.R` | Build manifest (checksums, commit, versions) and reconciliation register |
| `09_Run_All.R` | Runs the above in order |

Not part of the pipeline (kept for the record): `001_chirps.R` (early exploration),
`01_Load_SAS_2019_2025.R` and `02_Rename_and_Label_SAS_2019_2025.R` (replaced by 03),
`Crop_Production_2019.Rmd`.

### 2. Shiny app (R)

| Package | Role |
|---|---|
| `shiny` | Web framework. Its R server filters the precomputed `.rds` tables and draws the charts |
| `bslib` | Bootstrap 5 theme and layout, with a shared filter sidebar |
| `plotly` | Interactive charts and maps |
| `DT` | Sortable, searchable tables with downloads |
| `fontawesome` | Icons |
| `rsconnect` | Deployment to shinyapps.io |

Each page is its own module in `SCRIPTS/app/R/mod_*.R`.

### 3. Web app (React)

| Tool | Role |
|---|---|
| React 18 + TypeScript | The dashboard pages, with type-checked data |
| Vite | Development server and production build |
| React Router | Navigation between pages |
| Plotly.js | The same interactive charts and maps as the Shiny app, loaded only when needed |
| vite-plugin-pwa | Makes the site installable on a phone and usable offline |
| Lucide | Icons |
| Vercel | Hosting. Every push to `master` publishes a new version |

The web app is a static site with no backend or database. It loads the JSON files once, then
does all filtering and survey maths (combining districts, reliability labels) in the browser,
in `src/lib/stats.ts`; the shortlist ranking and its weight sensitivity are in `src/lib/ranking.ts`.

### 4. Languages and quality checks

- **Three languages:** English, Kinyarwanda and French, shared by both apps through one
  translation file. The Kinyarwanda and French text still needs a native-speaker review.
- **GitHub Actions:** `.github/workflows/web-build.yml` builds the web app on every change, so
  a broken build is caught before it goes live.
- **Tests:** `cd SCRIPTS/web && npm test` (ranking: zero weights, sensitivity draws);
  `Rscript SCRIPTS/tests/test_core.R`, `test_crop.R`, `test_official.R` (synthetic checks) and
  `test_pooled_variance.R` (needs the microdata; checks against `survey::svymean`).
- **Build manifest:** every rebuild writes `docs/build_manifest.json` with the build time, git
  commit, R and package versions and SHA-256 checksums of every input and web output.

##  Run it

```r
# R packages (R 4.3+), listed in requirements.txt
install.packages(grep("^[A-Za-z]", readLines("requirements.txt"), value = TRUE))
```

```bash
# Web app (Node 20+)
cd SCRIPTS/web && npm install && npm test && npm run dev
```

```r
# Shiny app (R, from the project root)
shiny::runApp("SCRIPTS/app")

# Rebuild all data (needs the NISR microdata)
source("SCRIPTS/03_Data_Preparation.R")   # once: reads the 111 SAS files, CHIRPS and GADM
source("SCRIPTS/09_Run_All.R")
```

### Data and where to get it

The `DATA/` folder holds the public inputs: NISR's published tables, CHIRPS rainfall and GADM
boundaries. The NISR survey microdata are **not** in this repository: they are licensed by NISR
and too large for GitHub (111 files). Download them from the link below and place them in the
folder shown before rebuilding.

| Data | Link | In this repository? | Where it goes |
|---|---|---|---|
| NISR Seasonal Agricultural Survey 2019–2025 microdata (111 .sav/.dta) | [NISR microdata catalogue](https://microdata.statistics.gov.rw/index.php/catalog) | No (licensed, large) | `DATA/SAS/` |
| NISR Agricultural Household Survey 2017/2020/2024 (optional) | [NISR microdata catalogue](https://microdata.statistics.gov.rw/index.php/catalog) | No (licensed) | `DATA/Agriculture Household Survey/` |
| NISR SAS annual tables 2019–2025 (.xlsx) | [NISR publications](https://www.statistics.gov.rw/) | Yes | `DATA/NISR_published/` |
| CHIRPS v2.0 rainfall, district × month 1981–2025 | [CHIRPS, Climate Hazards Center](https://www.chc.ucsb.edu/data/chirps) | Yes (district aggregate) | `DATA/CHIRPS/` |
| GADM 4.1 Rwanda boundaries | [GADM downloads](https://gadm.org/download_country.html) | Yes | `DATA/GADM/` |

The web and Shiny apps run without the microdata: they read the aggregated files already
committed in `SCRIPTS/web/public/data/` and `SCRIPTS/app/data/`. 2026 survey data are excluded
on purpose. The same table and a list of the folder's contents are in [DATA/README.md](DATA/README.md).

##  Documentation

- [Methods and reconciliation](docs/Methods_and_Reconciliation.md): estimators and every gap with NISR's tables, with its cause
- [Reconciliation register (CSV)](docs/Reconciliation_Register_2019_2025.csv): each national NISR cell beside our value
- [Data dictionary](docs/Data_Dictionary.md) · [Source register](docs/Source_Register.md)
- [Limitations and pilot plan](docs/Limitations_and_Pilot_Plan.md) · [AI-use disclosure](docs/AI_Use_Disclosure.md)

## Team NiyoIshimwe

| Member | Role | GitHub |
|---|---|---|
| **NIYOBYOSE Branchal** | Data Scientist | [@Umumasayii](https://github.com/Umumasayii) |
| **ISHIMWE Ami Paradis** | Software Engineer | [@amiparadis250](https://github.com/amiparadis250) |

---

<div align="center">

<sub>Independent project, not affiliated with NISR. AI assistance (Claude) was used for code and drafting, as the rules require us to disclose</sub>

</div>
