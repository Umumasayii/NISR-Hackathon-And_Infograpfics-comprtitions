# SmartIrrigate Rwanda

**Which districts should be checked first for small-scale irrigation?**

SmartIrrigate Rwanda is a dashboard that combines NISR farm surveys with 45 years of satellite
rainfall data. It shows where rain fails most often, how many farmers water their crops, and how
harvests compare on irrigated and rain-fed plots. The result is a ranked shortlist of districts
for field checks, with the uncertainty behind each figure shown.

NISR 2026 Big Data Hackathon, **Track 1: Agricultural Productivity**. Powered by Team NiyoIshimwe.

| | |
|---|---|
| **Web app** (React, works on phones and offline) | `<VERCEL-URL>` |
| **Shiny app** (R) | https://niyobyosebranchal.shinyapps.io/NiyoIshimweAPP/ |
| **Languages** | English, Kinyarwanda, French |

> Independent project. Not affiliated with or endorsed by NISR.

---

## How this answers the Track 1 brief

| The brief asks for | What SmartIrrigate does |
|---|---|
| A real agricultural challenge, e.g. **small-scale irrigation** | Who irrigates, where, with which technology (pump, drip, sprinkler, pivot and others) and how the harvest compares with rain-fed plots, for 2019–2025 |
| Solutions **informed by NISR data** | Built on the NISR Seasonal Agricultural Survey (21 seasons, 2019–2025) and the Agricultural Household Survey (2017, 2020, 2024). NISR's published tables are shown first wherever they exist |
| Other open data on **agriculture, food security or climate** | CHIRPS satellite rainfall 1981–2025, district by district, against a 1991–2020 baseline. GADM district boundaries |
| **Innovative** use of data | Combines satellite rainfall with survey data, maps the rainfall need of each district against its irrigation use, offers adjustable priority weights with rank stability, and runs as an installable offline web app |
| **Tangible impact** for farmers, planners and policymakers | A downloadable, ranked district shortlist with the reasons behind each rank, for district planners, MINAGRI, RAB and partners. Extension officers can use the district profiles in Kinyarwanda, on a phone and without a connection |

## What is in the dashboard

12 pages, with filters shared by every page (year, season, province, district, crop):

| Page | Question it answers |
|---|---|
| Overview | How much land and how many farmers are irrigated, and how has that moved since 2019? |
| Map | How does each district compare? |
| District | What does one district look like: rainfall, irrigation, crops and harvests? |
| Need | Where is rain short or unreliable, and is irrigation happening there? |
| Explorer | Any indicator by crop, season and district |
| Evidence | How do yields on irrigated plots compare with rain-fed plots? |
| How | Which irrigation technologies do farmers use? |
| Who | Who irrigates and who is left out (gender, plot size, land conditions)? |
| Households | Household-level support: cooperatives, water user groups, insurance, inputs |
| Model | Which plot and farm features go with irrigation (adoption model, with its evaluation) |
| Priority | The ranked district shortlist, with weights the user can change, and a CSV download |
| Methods | Sources, definitions, reliability rules, the reconciliation register with NISR's tables, and the AI-use disclosure |

## Methods in brief

- **Survey-weighted estimates** with standard errors computed from the survey design (strata and
  clusters). Every figure carries a reliability label: *Good*, *Use with caution* or
  *Unreliable*. The label depends on the sample size (minimum 30), the number of clusters and the
  coefficient of variation.
- **NISR published figures come first.** Where NISR publishes a figure, the app shows it and
  cites the workbook, sheet and cell. Our own estimates sit beside it, labelled as estimates.
  A reconciliation register lists where the two differ, by how much, and the likely reason.
- **Rainfall need**: seasonal totals, anomalies and variability within each season, measured
  against 1991–2020.
- **Associations, not causes.** The yield comparisons are adjusted for crop, season, district,
  inputs and plot size, and they are described as associations, not proof of an effect.
- **Privacy**: only aggregated estimates are published. Survey microdata and weights never leave
  the team's computer.

The full design is in [Dashboard_Architecture_FINAL.md](DOCS/Dashboard_Architecture_FINAL.md),
the audit and its fixes in [Audit_Fixes_2019_2025.md](DOCS/Audit_Fixes_2019_2025.md), and the
role of NISR's published tables in [NISR_Primary_2019_2025.md](DOCS/NISR_Primary_2019_2025.md).

## Data sources

| Source | Use |
|---|---|
| NISR Seasonal Agricultural Survey (SAS) 2019–2025 | Plots, crops, irrigation, inputs, harvests, sales |
| NISR Agricultural Household Survey (AHS) 2017, 2020, 2024 | Household support and practices |
| NISR published SAS tables 2019–2025 (`DATA/NISR_published/`) | Official figures shown first, and reconciliation |
| CHIRPS rainfall, district × month, 1981–2025 (`DATA/CHIRPS/`) | Rainfall need and variability |
| GADM 4.1 boundaries (`DATA/GADM/`) | District maps |

The survey microdata are not in this repository. Request them from the
[NISR microdata portal](https://microdata.statistics.gov.rw/).

## Tech stack

```
SAS / AHS microdata + NISR tables + CHIRPS + GADM
      │
      ▼  R pipeline (SCRIPTS/05–15): survey, tidyverse, haven, readxl, sf, ranger
SCRIPTS/app/data/*.rds ──► Shiny app (shiny, bslib, plotly, DT) ──► shinyapps.io
      │
      ▼  SCRIPTS/12_Export_Web_Data.R
SCRIPTS/web/public/data/*.json ──► React 18 + TypeScript + Vite + Plotly (PWA) ──► Vercel
```

There is no separate backend or database. The Shiny server works on precomputed `.rds` files,
and the web app is a static site that reads precomputed JSON. GitHub Actions
([web-build.yml](.github/workflows/web-build.yml)) builds the web app on every change.

## Run it

Both apps run from the data already in this repository. The rebuild step is only needed when
the inputs change.

**Web app** (needs Node.js 20 or newer):

```bash
cd SCRIPTS/web
npm install
npm run dev          # http://localhost:5173
```

**Shiny app** (from the project root in R):

```r
install.packages(c("shiny", "bslib", "plotly", "dplyr", "tidyr", "DT", "fontawesome", "sf"))
shiny::runApp("SCRIPTS/app")
```

**Rebuild all data** (needs the SAS and AHS microdata in `DATA/`):

```r
source("SCRIPTS/09_Run_All.R")
```

This runs selection (05), merging (06), AHS preparation (10), NISR tables (11, 14, 15), app
tables (07), models (08) and the web export (12). It never commits or pushes anything. Tests are
in [SCRIPTS/tests/](SCRIPTS/tests/).

## Repository map

| Path | Contents |
|---|---|
| `SCRIPTS/` | R pipeline, numbered in run order (`09_Run_All.R` runs everything) |
| `SCRIPTS/app/` | Shiny app |
| `SCRIPTS/web/` | React web app ([README](SCRIPTS/web/README.md)) |
| `DATA/` | Open inputs: NISR published tables, CHIRPS, GADM |
| `Dictionaries/`, `02_LABELLED_SAS/` | Variable dictionary, renaming map and labelling audit for the SAS files |
| `DOCS/` | Design, audit and methods documents |

## Limitations

- Estimates for small districts or rare crops can be unreliable. They are labelled, never hidden.
- Some of our input-use figures (fertiliser, pesticides) differ from NISR's published figures
  from 2022 on. The difference is listed in the reconciliation register, and NISR's figure is
  shown first.
- Yield comparisons are associations. A field check is needed before any investment decision,
  which is why the output is a shortlist for field checks and not a final ranking.
- The Kinyarwanda and French translations are drafts and still need review by native speakers.

## AI-use disclosure

As the hackathon rules require, we disclose that this project used AI assistance (Claude by
Anthropic) for:

1. Drafting code for data preparation, the apps and the models. The team reviewed and ran all
   of it.
2. Draft French and Kinyarwanda translations, pending review by native speakers.
3. Drafting documentation, including this README.

Every figure comes from code run on NISR and open data. No number was written by AI without
computation. Any AI-generated image is labelled as such. The same disclosure appears on the
Methods page of both apps.

## Team

Team NiyoIshimwe: `<NAMES AND ROLES>`
