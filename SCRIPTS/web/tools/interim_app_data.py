"""Interim correction of public/data/app_data.json without the survey microdata.

The proper fix is to re-run SCRIPTS/09_Run_All.R on the machine that holds the SAS
and AHS files. Until then this script applies, to the committed app_data.json, the
corrections that need no microdata:

  * drops every 2026 statistic (sas_year > 2025) and the published-figure overlay
  * restores our survey values where the overlay had replaced them (2024B, 2025A,
    2025B national production) and removes the parent crop rows it had added
  * recomputes rainfall variability within each main season (CHIRPS, 1991-2020),
    the need score, quadrants and the shortlist with the new default weights
  * adds layers, scope, the reconciliation register and a list of pending rebuilds

Run from SCRIPTS/web:  python3 -I tools/interim_app_data.py
"""
import csv
import json
import math
import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(WEB))
DATA = os.path.join(WEB, "public", "data", "app_data.json")
CELL_MAP = os.path.join(ROOT, "DATA", "NISR_published", "official_cell_map.csv")
REGISTER_OUT = os.path.join(ROOT, "docs", "Reconciliation_Register_2019_2025.csv")
LAST_YEAR = 2025


def to_df(x):
    return pd.DataFrame(x["__df"])


def from_df(df):
    cols = {}
    for c in df.columns:
        v = df[c]
        if pd.api.types.is_bool_dtype(v):
            cols[c] = [bool(b) for b in v]
        elif pd.api.types.is_integer_dtype(v):
            cols[c] = [int(i) for i in v]
        elif pd.api.types.is_float_dtype(v):
            cols[c] = [None if not math.isfinite(f) else int(f) if f.is_integer() else sig(f) for f in v]
        else:
            cols[c] = [None if (isinstance(s, float) and math.isnan(s)) or s is None else s for s in v]
    return {"__df": cols}


def sig(f, n=5):
    if f == 0:
        return 0.0
    return round(f, -int(math.floor(math.log10(abs(f)))) + (n - 1))


def minmax(x):
    x = np.asarray(x, dtype=float)
    lo, hi = np.nanmin(x), np.nanmax(x)
    return x * 0 if hi == lo else (x - lo) / (hi - lo)


def in_scope(df, col="sas_year"):
    return df[df[col].isna() | (df[col] <= LAST_YEAR)].reset_index(drop=True) if col in df else df


d = json.load(open(DATA, encoding="utf-8"))
removed = []

# ---- 1. no 2026 statistics, no overlay ---------------------------------------
est = to_df(d["est"])
removed.append(("est", "rows from 2026 (published SAS 2026 tables)", int((est.sas_year > LAST_YEAR).sum())))
est = in_scope(est)
est["source"] = "survey"
d["est"] = from_df(est)

tot = to_df(d["totals"])
removed.append(("totals", "rows from 2026", int((tot.sas_year > LAST_YEAR).sum())))
tot = in_scope(tot)
over = tot.totals_source.ne("survey")
removed.append(("totals", "national production replaced by a published figure (2024B, 2025A, 2025B): survey value restored", int(over.sum())))
tot.loc[over, "production_t"] = tot.loc[over, "production_survey_t"]
tot.loc[over, "cultivated_area_ha"] = tot.loc[over, "cultivated_survey_ha"]
tot = tot.drop(columns=["production_survey_t", "cultivated_survey_ha"])
tot["totals_source"] = "survey"
d["totals"] = from_df(tot)

crop = to_df(d["crop"])
removed.append(("crop", "rows from 2026", int((crop.sas_year > LAST_YEAR).sum())))
crop = in_scope(crop)
parent = crop.production_source.ne("survey") & crop.production_survey_t.isna()
removed.append(("crop", "parent rows added beside their own crops (Vegetables (all), Fruits (all), Fodder crops, Yams & taro): double counting", int(parent.sum())))
crop = crop[~parent].copy()
over = crop.production_source.ne("survey")
removed.append(("crop", "crop production replaced by a published figure (2024B, 2025A, 2025B): survey value restored", int(over.sum())))
crop.loc[over, "production_t"] = crop.loc[over, "production_survey_t"]
crop = crop.drop(columns=["production_survey_t", "production_source"])
d["crop"] = from_df(crop.reset_index(drop=True))

cd = to_df(d["crop_dist"])
removed.append(("crop_dist", "rows from 2026", int((cd.sas_year > LAST_YEAR).sum())))
cd = in_scope(cd)
cd = cd[cd.production_source.eq("survey")].drop(columns=["production_source"])
d["crop_dist"] = from_df(cd.reset_index(drop=True))

for k in ("mix", "sources_any", "other_share"):
    d["tech"][k] = from_df(in_scope(to_df(d["tech"][k])))
d["equity"]["equity"] = from_df(in_scope(to_df(d["equity"]["equity"])))
d["yield"]["by_year"] = from_df(in_scope(to_df(d["yield"]["by_year"])))
d["meta"]["season_quality"] = from_df(in_scope(to_df(d["meta"]["season_quality"])))

# ---- 2. rainfall variability within each season --------------------------------
rain = to_df(d["rain"]["rain"])
rain = rain[rain.sas_year <= LAST_YEAR]
base = rain[rain.sas_season.isin(["A", "B"]) & rain.sas_year.between(1991, 2020)]
season = (base.groupby(["district_std", "sas_season"]).rain_mm
          .agg(normal_mm="mean", sd_mm=lambda v: v.std(ddof=1)).reset_index())
season["cv_pct"] = 100 * season.sd_mm / season.normal_mm
wide = season.pivot(index="district_std", columns="sas_season", values=["normal_mm", "cv_pct"])
stats = pd.DataFrame({
    "rain_normal_ab_mm": wide["normal_mm"].mean(axis=1),
    "rain_cv_pct": wide["cv_pct"].mean(axis=1),
    "rain_cv_a_pct": wide["cv_pct"]["A"], "rain_cv_b_pct": wide["cv_pct"]["B"]}).reset_index()
main = rain[rain.sas_season.isin(["A", "B"])]
dry = (main[main.sas_year.between(2016, 2025)].assign(dry=lambda x: x.rain_std_anomaly < -1)
       .groupby("district_std").dry.sum().rename("dry_seasons_2016_2025").reset_index())
anom = (main[main.sas_year.between(2019, 2025)].groupby("district_std").rain_anomaly_pct.mean()
        .rename("mean_anomaly_2019_2025").reset_index())
old = to_df(d["rain"]["district"])
adopt = old[["district_std", "adoption_pct", "adoption_low", "adoption_high", "adoption_n", "adoption_reliability"]]
need = stats.merge(dry, on="district_std", how="left").merge(anom, on="district_std", how="left")
need["need_score"] = 100 * (minmax(need.rain_cv_pct) + minmax(need.dry_seasons_2016_2025) + minmax(-need.rain_normal_ab_mm)) / 3
need = need.merge(adopt, on="district_std", how="left")
hn = need.need_score >= need.need_score.median()
la = need.adoption_pct < need.adoption_pct.median()
need["quadrant"] = np.select([hn & la, hn, la], ["High need, low adoption", "High need, higher adoption",
                                                 "Lower need, low adoption"], "Lower need, higher adoption")
d["rain"]["district"] = from_df(need)
d["rain"]["rain"] = from_df(rain.reset_index(drop=True))

# ---- 3. shortlist with the new default weights ---------------------------------
W = {"c_need": 0.30, "c_gap": 0.30, "c_scale": 0.20, "c_equity": 0.10, "c_readiness": 0.0}
comp = list(W)
scr = to_df(d["screen"]["table"]).drop(columns=["need_score", "quadrant"])
scr = scr.merge(need[["district_std", "need_score", "quadrant"]], on="district_std", how="left")
scr["c_need"] = minmax(scr.need_score)
M = scr[comp].to_numpy(dtype=float)


def score(w):
    w = np.asarray(w, dtype=float)
    return 100 * M @ (w / w.sum())


def rank(s):
    return pd.Series(-s).rank(method="min").to_numpy()


scr["score"] = score(list(W.values()))
scr["rank"] = rank(scr.score.to_numpy()).astype(int)
rng = np.random.default_rng(2026)
draws = rng.gamma(2.0, size=(2000, 5))
R = np.column_stack([rank(score(w)) for w in draws])
scr["rank_median"] = np.median(R, axis=1)
scr["rank_p10"] = np.quantile(R, 0.10, axis=1)
scr["rank_p90"] = np.quantile(R, 0.90, axis=1)
scr["prob_top5_pct"] = 100 * (R <= 5).mean(axis=1)
spread = scr.rank_p90 - scr.rank_p10
scr["stability"] = np.select([spread <= 4, spread <= 10], ["Stable", "Moderately sensitive"], "Sensitive to weights")
contrib = M * (np.array(list(W.values())) / sum(W.values()))
scr["reasons"] = [",".join(np.array(comp)[np.argsort(-r, kind="stable")][:2]) for r in contrib]
d["screen"]["table"] = from_df(scr.sort_values("rank").reset_index(drop=True))
d["screen"]["default_weights"] = W
d["screen"]["meta"] = {
    "weights": W,
    "sensitivity": "2,000 random weight sets, Dirichlet(2, 2, 2, 2, 2), seed 2026",
    "periods": {"c_need": "CHIRPS rainfall, baseline 1991-2020; dry seasons 2016-2025",
                "c_gap": "plots irrigated, Seasons A+B 2023-2025",
                "c_scale": "cultivated area, mean per main season 2023-2025",
                "c_equity": "men - women plot irrigation gap, 2023-2025",
                "c_readiness": "chemical fertiliser plots, 2023-2025"}}

# ---- 4. meta: scope, layers, no published overlay ------------------------------
meta = d["meta"]
meta.pop("published", None)
meta.pop("benchmarks", None)
src = to_df(meta["sources"])
src.loc[0, "source"] = "NISR Seasonal Agricultural Survey (SAS) 2019-2025, Seasons A/B/C (microdata)"
meta["sources"] = from_df(src)
meta["scope"] = ("Statistics 2019-2025 only. Project estimates from survey microdata are not official NISR "
                 "statistics, and the project is not affiliated with or endorsed by NISR.")
tables = ["est", "totals", "crop", "crop_dist", "yield", "tech", "rain", "equity", "screen", "model", "model_yield", "ahs", "official"]
layers = ["project_estimate"] * 6 + ["project_analysis", "project_estimate", "project_analysis", "model_output", "model_output", "project_estimate", "published"]
meta["layers"] = from_df(pd.DataFrame({"table": tables, "layer": layers}))
meta["interim"] = {
    "note": "Interim data: corrected in the browser bundle without the survey microdata. Re-run SCRIPTS/09_Run_All.R to rebuild.",
    "pending": ["yield sufficient totals (one eligibility mask, ratio of summed harvest and area)",
                "model AUC with tie correction, average precision, Brier baselines",
                "published reference layer read cell by cell (needs the SAS 2019-2025 and AHS 2024 workbooks)",
                "fertiliser and pesticide reconciliation with the SAS 2025 tables"]}
d["official"] = from_df(pd.DataFrame(columns=["indicator", "sas_year", "sas_season", "level", "area", "crop_name",
                                              "value", "unit", "population", "definition", "same_definition",
                                              "source_title", "source_url", "table", "sheet", "cell", "status"]))
d["built"] = meta["built"] = meta["built"] + " (interim correction 2026-10-20)"

# ---- 5. reconciliation register ------------------------------------------------
cells = list(csv.DictReader(open(CELL_MAP, encoding="utf-8")))
ahs = to_df(d["ahs"]["indicators"])


def app_value(r):
    y, s, ind = int(r["sas_year"]), r["sas_season"], r["app_indicator"]
    if r["app_table"] == "est":
        m = est[(est.level == "national") & (est.sas_year == y) & (est.sas_season == s) & (est.indicator == ind)]
        return m.estimate.iloc[0] if len(m) else None
    if r["app_table"] == "crop":
        m = crop[(crop.sas_year == y) & (crop.sas_season == s)]
        if r["same_definition"] == "GROUP":
            g = m[m.crop_group == r["crop_name"]]
            return g.production_t.sum() if len(g) else None
        m = m[m.crop_name == r["crop_name"]]
        return m.production_t.iloc[0] if len(m) else None
    if r["app_table"] == "crop_dist":
        m = cd[(cd.sas_year == y) & (cd.sas_season == s) & (cd.crop_name == r["crop_name"]) & (cd.district_std == r["area"])]
        return m.production_t.iloc[0] if len(m) else None
    if r["app_table"] == "ahs":
        m = ahs[(ahs.year == y) & (ahs.level == "national") & (ahs.indicator == ind)]
        return m.estimate.iloc[0] if len(m) else None
    return None


rows = []
for r in cells:
    later = "2026" in r["workbook_pattern"]
    v = None if later else app_value(r)
    a = float(r["audit_value"]) if r["audit_value"] else None
    gap = None if v is None or a is None else v - a
    rel = None if gap is None or not a else 100 * gap / a
    sd = r["same_definition"]
    if later:
        decision, status = "Unavailable here: cell is in a later (2026) release, out of scope; read it from the SAS 2024/2025 Annual Tables", "not read"
    elif sd == "CONFLICT":
        decision, status = "Flagged: inconsistency inside the official tables; shown as published, not corrected", "audit-reported, not verified"
    elif sd == "FALSE":
        decision, status = "Retained as derived: different population or definition, so not compared as like-for-like", "audit-reported, not verified"
    elif sd == "UNKNOWN":
        decision, status = "Flagged for clarification: definition not confirmed", "audit-reported, not verified"
    elif gap is None:
        decision, status = "Unavailable: no comparable project value", "audit-reported, not verified"
    elif (r["unit"] == "%" and abs(gap) <= 2) or (r["unit"] != "%" and rel is not None and abs(rel) <= 5):
        decision, status = "Retained as derived: consistent with the published figure", "audit-reported, not verified"
    else:
        decision, status = ("Flagged for clarification: project estimate differs from the published figure; "
                            "not replaced (definitions, denominators or skip rules to check)"), "audit-reported, not verified"
    rows.append({
        "register_id": r["register_id"], "family": r["family"], "indicator": r["indicator"],
        "sas_year": r["sas_year"], "sas_season": r["sas_season"], "level": r["level"], "area": r["area"],
        "crop_name": r["crop_name"], "unit": r["unit"], "published_population": r["population"],
        "published_definition": r["definition_official"], "project_population": r["app_population"],
        "same_definition": sd, "source_title": r["source_title"], "source_url": r["source_url"],
        "workbook": r["workbook_pattern"], "sheet": r["sheet_pattern"], "cell": r["cell"],
        "published_value_audit": a, "project_value": None if v is None else round(float(v), 3),
        "gap": None if gap is None else round(gap, 3), "gap_pct": None if rel is None else round(rel, 2),
        "status": status, "decision": decision, "note": r["note"]})
for table, what, n in removed:
    rows.append({"register_id": f"APP-{table}-{len(rows)}", "family": "Changed in the app data", "indicator": table,
                 "status": f"{n} rows", "decision": "Removed: " + what if "restored" not in what else "Replaced: " + what})
reg = pd.DataFrame(rows)
os.makedirs(os.path.dirname(REGISTER_OUT), exist_ok=True)
reg.to_csv(REGISTER_OUT, index=False)
# the web register lists only figures that can be compared; later-release cells stay in the CSV
d["register"] = from_df(reg[(reg.family != "Changed in the app data") & (reg.status != "not read")].reset_index(drop=True))

json.dump(d, open(DATA, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"), allow_nan=False)
print("removed/replaced:", *removed, sep="\n  ")
print("register rows:", len(reg), "->", REGISTER_OUT)
print(scr.sort_values("rank")[["district_std", "need_score", "score", "rank", "rank_p10", "rank_p90", "reasons"]].head(8).to_string())
