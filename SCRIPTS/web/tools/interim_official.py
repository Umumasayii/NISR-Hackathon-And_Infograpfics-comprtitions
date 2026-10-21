"""Interim public/data/official.json (published NISR figures) without the microdata.

The proper path is SCRIPTS/09_Run_All.R on the machine that holds the SAS files:
11 reads every NISR table, 14 picks the figures the app uses, 07 sets our estimate
beside each one and 12 writes official.json. This script does the last two steps
from the committed app_data.json instead, so the website can show the published
figures now. Our values for the new per-farmer and per-land input measures only
exist after the rebuild; until then they are empty, never guessed.

Inputs : official_reference.csv from SCRIPTS/14 (path as first argument)
Outputs: SCRIPTS/web/public/data/official.json
         docs/Reconciliation_Register_2019_2025.csv  (national figures, every season)
         <outdir>/Reconciliation_Register_full.csv     (every published figure; optional 2nd argument)

Run from SCRIPTS/web:  python3 -I tools/interim_official.py <official_reference.csv> [outdir]
"""
import csv
import json
import math
import os
import sys

import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(WEB))
APP = os.path.join(WEB, "public", "data", "app_data.json")
OUT = os.path.join(WEB, "public", "data", "official.json")
REGISTER = os.path.join(ROOT, "docs", "Reconciliation_Register_2019_2025.csv")
LAST_YEAR = 2025

ref = pd.read_csv(sys.argv[1], dtype={"sas_season": str, "cell": str, "value_note": str, "revised_from": str}, low_memory=False)
ref = ref[(ref.sas_year <= LAST_YEAR) & (ref.farmer_type == "All")].copy()
ref["crop_name"] = ref["crop_name"].fillna("")
ref["is_group"] = ref["is_group"].fillna(False).astype(bool)
d = json.load(open(APP, encoding="utf-8"))
df = lambda x: pd.DataFrame(x["__df"])

# ---- our value for the same question, place, season and crop -----------------------
est = df(d["est"])
est = est[est.level.isin(["national", "district"])]
p_est = est.assign(project_table="est", crop_name="").rename(columns={"indicator": "project_indicator", "estimate": "project_value"})[
    ["project_table", "project_indicator", "sas_year", "sas_season", "level", "area", "crop_name", "project_value"]]
tot = df(d["totals"])
tot = tot[tot.level.isin(["national", "district"])]
p_tot = tot.melt(id_vars=["level", "area", "sas_year", "sas_season"], value_vars=["cultivated_area_ha", "irrigated_area_ha"],
                 var_name="project_indicator", value_name="project_value").assign(project_table="totals", crop_name="")
crop = df(d["crop"]).assign(level="national", area="Rwanda", project_table="crop")
cd = df(d["crop_dist"]).rename(columns={"district_std": "area"}).assign(level="district", project_table="crop_dist")
p_crop = pd.concat([crop, cd]).melt(id_vars=["project_table", "level", "area", "sas_year", "sas_season", "crop_name"],
                                    value_vars=["production_t", "crop_area_ha", "yield_kg_ha"],
                                    var_name="project_indicator", value_name="project_value")
proj = pd.concat([p_est, p_tot, p_crop])[["project_table", "project_indicator", "sas_year", "sas_season", "level", "area", "crop_name", "project_value"]]
proj = proj.drop_duplicates(["project_table", "project_indicator", "sas_year", "sas_season", "level", "area", "crop_name"])

off = ref.merge(proj, how="left", on=["project_table", "project_indicator", "sas_year", "sas_season", "level", "area", "crop_name"])
off["comparable"] = off["comparable"].fillna(False).astype(bool)
off["gap"] = off["value"] - off["project_value"]


def decision(r):
    if pd.isna(r.value):
        return "Published cell blank: shown as unavailable"
    if not r.comparable:
        return "NISR value shown under its own label; not compared (different definition)"
    if pd.isna(r.project_value):
        return "NISR value shown; no project estimate"
    return "NISR value shown; project estimate kept as cross-check"


off["decision"] = off.apply(decision, axis=1)
# short codes in the web file (the register keeps the sentences)
DECISION_CODE = {"Published cell blank: shown as unavailable": "blank",
                 "NISR value shown under its own label; not compared (different definition)": "own_label",
                 "NISR value shown; no project estimate": "no_project",
                 "NISR value shown; project estimate kept as cross-check": "cross_check"}


# ---- official.json, the same shape 12_Export_Web_Data.R writes ------------------------
def num(v, n=6):
    if v is None or (isinstance(v, float) and not math.isfinite(v)):
        return None
    v = float(v)
    if v == 0:
        return 0
    r = round(v, max(0, -int(math.floor(math.log10(abs(v)))) + (n - 1)))
    return int(r) if float(r).is_integer() else r


def col(s):
    out = []
    for v in s:
        if isinstance(v, float) and math.isnan(v):
            out.append(None)
        elif isinstance(v, (bool,)) or type(v).__name__ == "bool_":
            out.append(bool(v))
        elif isinstance(v, (int, float)) or type(v).__name__ in ("int64", "float64"):
            out.append(num(v))
        else:
            out.append(v if v != "" else None)
    return out


# one row per source table and printed column label: rows point to it by number
off["src"] = off["source_file"] + " | " + off["sheet"] + " | " + off["measure_label"].fillna("")
src = off.drop_duplicates("src")[["src", "survey", "source_title", "source_file", "sheet", "nisr_table", "table_title",
                                  "measure_label"]].reset_index(drop=True)
src["src_id"] = src.index + 1
off = off.merge(src[["src", "src_id"]], on="src")
off["d"] = off["decision"].map(DECISION_CODE)
defs = off.drop_duplicates("indicator")[["indicator", "unit", "population", "definition", "comparable", "project_indicator", "project_table"]]
rows = off[["indicator", "sas_year", "sas_season", "level", "area", "crop_name", "is_group", "value",
            "src_id", "cell", "project_value", "d"]].sort_values(["indicator", "sas_year", "sas_season", "level", "area", "crop_name"])
pack = lambda t: {"__df": {c: col(t[c]) for c in t.columns}}
json.dump({"rows": pack(rows), "sources": pack(src.drop(columns="src")), "definitions": pack(defs),
           "built": "published NISR tables, interim join with app_data.json"},
          open(OUT, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print(f"official.json: {len(rows)} figures, {len(src)} source tables, {os.path.getsize(OUT) / 1e6:.1f} MB")

# ---- reconciliation register ----------------------------------------------------------
reg = off.assign(gap_pct=lambda x: (100 * x.gap / x.value).where(x.unit != "%")).rename(columns={"value": "nisr_value"})
cols = ["indicator", "sas_year", "sas_season", "level", "area", "crop_name", "is_group", "unit", "nisr_value", "project_value",
        "gap", "gap_pct", "comparable", "decision", "population", "definition", "measure_label", "project_indicator",
        "source_title", "source_file", "sheet", "cell", "copies", "revised_from"]
reg = reg[cols].sort_values(["indicator", "level", "area", "crop_name", "sas_year", "sas_season"])
reg[reg.level == "national"].to_csv(REGISTER, index=False, quoting=csv.QUOTE_MINIMAL)
if len(sys.argv) > 2:
    reg.to_csv(os.path.join(sys.argv[2], "Reconciliation_Register_full.csv"), index=False)
print(reg.decision.value_counts().to_string())
