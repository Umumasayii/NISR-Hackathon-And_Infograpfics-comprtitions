<div align="center">

<img src="SCRIPTS/web/public/logo.svg" width="96" alt="SmartIrrigate Rwanda logo">

# SmartIrrigate Rwanda

**Which districts should be checked first for small-scale irrigation?**

[![Web app](https://img.shields.io/badge/Open-Web%20app-2E7D32?style=for-the-badge)](https://niyoishimwe.vercel.app/)
[![Shiny app](https://img.shields.io/badge/Open-Shiny%20app-1565C0?style=for-the-badge)](https://niyobyosebranchal.shinyapps.io/NiyoIshimweAPP/)

NISR 2026 Big Data Hackathon · Track 1: Agricultural Productivity · Team NiyoIshimwe
English · Kinyarwanda · Français

</div>

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

| Layer | Tools |
|---|---|
| Data pipeline | **R**: `survey`, `tidyverse`, `haven`, `readxl`, `sf`, `ranger` |
| Shiny app | `shiny`, `bslib`, `plotly`, `DT` on shinyapps.io |
| Web app | **React 18**, **TypeScript**, **Vite**, **Plotly**, installable offline web app (PWA), on Vercel |

```
NISR surveys + CHIRPS + GADM ─► R pipeline ─► .rds ─► Shiny app
                                           └─► .json ─► React web app
```

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
