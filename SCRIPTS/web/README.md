# SmartIrrigate Rwanda: web app

The same dashboard as the Shiny app (`SCRIPTS/app`), rebuilt as a fast, installable web app in
React + TypeScript with Plotly charts. It runs in any browser, works on phones, can be installed
like an app (PWA) and keeps working offline once opened. English, Kinyarwanda and French.

Powered by Team NiyoIshimwe.

## How the pieces fit

```
SAS / AHS / NISR tables ──> R pipeline (SCRIPTS/03 … 11) ──> SCRIPTS/app/data/*.rds
                                                                │
                              SCRIPTS/12_Export_Web_Data.R  <───┘
                                                                │
                            SCRIPTS/web/public/data/*.json  <───┘  (aggregates only, no microdata)
                                                                │
                                   React app (SCRIPTS/web/src) ─┘ ──> website (Vercel)
```

R stays the data engine. The web app only reads the weighted estimates the R scripts produce;
survey weights and microdata never leave your computer.

## Refresh the data

After `SCRIPTS/09_Run_All.R` (and `11_NISR_Published_Tables.R` when the NISR tables change), run
from the project root:

```r
source("SCRIPTS/12_Export_Web_Data.R")
```

It writes `app_data.json`, `districts.json`, `i18n.json` (the Shiny translations) and
`data_source.md` (the general Data Source) into `SCRIPTS/web/public/data/`. It also adds the cited
NISR headline figures from `DATA/NISR_published/nisr_report_headlines.csv`.

**By default it then commits and pushes every project change to GitHub** with
`SCRIPTS/13_Push_To_GitHub.R` (needs the `gert` package), and Vercel rebuilds the website from
`master`. To export without committing or pushing, run `Sys.setenv(SI_AUTO_PUSH = "FALSE")` first.
The push script never commits microdata-type files or secrets, even if `.gitignore` changes.

## Run it on your computer

Needs [Node.js](https://nodejs.org) 20 or newer.

```bash
cd SCRIPTS/web
npm install        # first time only
npm run dev        # opens http://localhost:5173
```

`npm run build` makes the production site in `SCRIPTS/web/dist/`; `npm run preview` serves it.

## The website (Vercel)

Vercel is linked to this repository with **Root Directory `SCRIPTS/web`** and **production branch
`master`**; `SCRIPTS/web/vercel.json` holds the build settings. Every push to `master` publishes a
new version of the site, and every pull request gets its own preview link. The GitHub check
`.github/workflows/web-build.yml` builds the app on each change so a broken build shows up early.

## Code map

| Path | What it does |
|---|---|
| `src/data/store.tsx` | Loads the JSON, holds language and the filter selection shared by every page |
| `src/lib/stats.ts` | Survey maths ported from the Shiny app: combining districts with stratum variances, reliability labels, weighted means |
| `src/lib/i18n.ts`, `src/lib/webI18n.ts` | Translations (reuses `SCRIPTS/app/translations.json`) |
| `src/components/Plot.tsx` | Plotly wrapper (lazy loaded) and shared chart styles: plain lines with markers, clustered bars, district map |
| `src/lib/sources.ts` | The source list and the provenance fields shown under each chart and added to each CSV |
| `src/components/ui.tsx` | Number cards, chart cards (takeaway, source line, "Show the numbers" table), filters, sortable tables with CSV download |
| `src/pages/*.tsx` | The 12 pages: Overview, Map, District, Need, Explorer, Evidence, How, Who, Households, Model, Priority, Methods |

Rules the app keeps: NISR published figures are shown as published and labelled, never replaced
by or joined to project estimates; every chart and number card names its measure, period, kind
of number and source next to it (`src/lib/sources.ts`), with a table alternative and a CSV that
repeats those fields; "Other" answers are never shown; associations, not causes.
