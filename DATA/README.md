# Data

This folder holds the public inputs: NISR's published tables, CHIRPS rainfall and GADM
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
on purpose.

## Contents

| Path | What it is |
|---|---|
| `NISR_published/` | The seven SAS annual table workbooks (2019, USAS 2020, 2021–2025) and `indicator_rules.csv`, which maps NISR table columns to our indicators |
| `CHIRPS/CHIRPS_District_Month_1981_2025.csv` | Monthly rainfall per district, aggregated from the 0.05° CHIRPS grid |
| `GADM/` | GADM 4.1 Rwanda shapefiles (levels 0–5: country, province, district, sector, cell, village) |
| `irrigation_columns_by_dataset.csv` | Which irrigation variables exist in each SAS file |
