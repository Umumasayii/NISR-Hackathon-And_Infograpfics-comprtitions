<img src="SCRIPTS/web/public/logo.svg" width="96" alt="SmartIrrigate Rwanda logo">

# SmartIrrigate Rwanda

- Web app: https://niyoishimwe.vercel.app/
- Shiny app: https://niyobyosebranchal.shinyapps.io/NiyoIshimweAPP/

---

## Problem

Most Rwandan farmers depend on rain, and the rain is becoming less reliable. Farmers who
irrigate get bigger harvests, yet only a small share irrigate. Planners have no single place
that shows **where rain fails most, who already irrigates, and where support would pay off
first.**

##  Solution

A dashboard that brings together **7 years of NISR farm surveys** and **45 years of satellite
rainfall data** to answer four questions:

| | |
|---|---|
| **The gap** | How many farmers and how much land are irrigated, by district, since 2019? |
| **The need** | Where is rain short or unreliable, and is irrigation happening there? |
| **The payoff** | How do harvests on irrigated plots compare with rain-fed plots? |
| **The action** | A **ranked district shortlist** for field checks, with weights you can adjust and a CSV download |

Every number shows its reliability. NISR's published figures come first, and our own
estimates sit beside them, clearly labelled. It works on a phone, offline, in three languages.

##  Relevance to the hackathon

| Track 1 asks for | SmartIrrigate |
|---|---|
| A real challenge such as small-scale irrigation | Irrigation is the core topic |
| Informed by NISR data | Seasonal Agricultural Survey 2019–2025, Agricultural Household Survey 2017–2024, NISR published tables |
| Open climate data | CHIRPS rainfall 1981–2025, GADM district maps |
| Innovation | Satellite rainfall combined with survey data, a district priority index, an offline web app |
| Practical impact | A shortlist that district planners, MINAGRI, RAB and extension officers can act on |

##  Tech stack

```
NISR surveys + NISR tables + CHIRPS + GADM
        │
        ▼
R data pipeline (SCRIPTS/05–15)
        │
        ├─► SCRIPTS/app/data/*.rds ─► Shiny app ─► shinyapps.io
        │
        └─► SCRIPTS/web/public/data/*.json ─► React web app ─► Vercel
```

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
| `jsonlite` | Export the final aggregates as JSON for the web app |

The scripts are numbered in run order, and `SCRIPTS/09_Run_All.R` runs them all. Only
aggregated estimates leave the pipeline: survey microdata and weights are never published.
Tests are in `SCRIPTS/tests/`.

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
| React 18 + TypeScript | The 12 dashboard pages, with type-checked data |
| Vite | Development server and production build |
| React Router | Navigation between pages |
| Plotly.js | The same interactive charts and maps as the Shiny app, loaded only when needed |
| vite-plugin-pwa | Makes the site installable on a phone and usable offline |
| Lucide | Icons |
| Vercel | Hosting. Every push to `master` publishes a new version |

The web app is a static site with no backend or database. It loads the JSON files once, then
does all filtering and survey maths (combining districts, reliability labels) in the browser,
in `src/lib/stats.ts`.

### 4. Languages and quality checks

- **Three languages:** English, Kinyarwanda and French, shared by both apps through one
  translation file.
- **GitHub Actions:** `.github/workflows/web-build.yml` builds the web app on every change, so
  a broken build is caught before it goes live.

##  Run it

```bash
# Web app (Node 20+)
cd SCRIPTS/web && npm install && npm run dev
```

```r
# Shiny app (R, from the project root)
shiny::runApp("SCRIPTS/app")

# Rebuild all data (needs the NISR microdata)
source("SCRIPTS/09_Run_All.R")
```

## Team NiyoIshimwe

| Member | Role | GitHub |
|---|---|---|
| **NIYOBYOSE Branchal** | Data Scientist | [@Umumasayii](https://github.com/Umumasayii) |
| **ISHIMWE Ami Paradis** | Software Engineer | [@amiparadis250](https://github.com/amiparadis250) |

---

<div align="center">

<sub>Independent project, not affiliated with NISR. AI assistance (Claude) was used for code and drafting, as the rules require us to disclose; every figure comes from code run on the data.</sub>

</div>
