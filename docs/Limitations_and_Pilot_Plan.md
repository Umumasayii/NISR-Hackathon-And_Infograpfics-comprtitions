# Limitations and pilot plan

## Limitations

**What the survey can and cannot say**
- SAS measures plots, crops and farmers in a season. It does not measure water availability, distance
  to a source, land suitability, energy, costs, markets or environmental limits. The Assess page keeps
  these as *unknown* until the officer records evidence.
- "% of plots irrigated" (ours) and "% of farmers who irrigated" (NISR) are different indicators.
  NISR farmer percentages are unweighted shares of sampled farmers; ours are survey-weighted.
- NISR's input-use "% of plots" covers only plots of farmers who used the input once the
  questionnaire added an "any of your plots" filter (pesticide and organic fertiliser from 2022C,
  chemical fertiliser from 2025A). Those NISR values are shown under their own label, not compared.
- 2019 (SAS) and 2020 onwards (USAS) differ in design: no trend is drawn across 2019/2020.
- 2024B crop areas are incomplete in the microdata (44% of harvested crop rows match a screened crop,
  against 99.9% in other seasons). 2024B and 2024C are left out of yield analysis. The cause could not
  be determined from the files.
- 2022C area estimates are unreliable (see `DOCS/Data_Check_v0.2.md`).
- Season C samples are small; many district estimates are labelled "Use with care" or "Not reliable".

**Methods**
- Yields are weighted harvest ÷ weighted eligible area. The main rule drops zero harvests and trims
  the 1st/99th percentiles; the Evidence page shows the result under three other rules.
- Pooled seasons share segments (about 97% of segments are revisited between A and B), so pooled
  variances cluster on the physical segment. Single-season estimates use the season's own design.
- The priority score is a transparent weighted sum of four relative criteria. The weight sensitivity
  describes preference uncertainty only, not sampling error.
- The rain-shortfall history index is relative between districts and uses past rainfall. It is not a
  forecast or a water-requirement estimate. The CHIRPS district aggregation method is undocumented.
- The adoption model classifies plots using answers from the same season (fertiliser, erosion,
  rain anomaly). It is not a pre-season forecast and not causal. The 2024–2025 check shares
  segments with the training years.
- Yield differences between irrigated and rain-fed plots are associations, not effects of irrigation.

**Product**
- Assessment notes are stored only in the officer's browser (no server, no sharing).
- French and Kinyarwanda text needs native-speaker review.
- Accessibility was checked for keyboard focus, reduced motion and phone width; no screen-reader
  user test has been done.

## Pilot plan (proposed, not yet run)

**Who:** planning officers in 3 districts (one high, one middle, one low on the shortlist), with their
irrigation/agriculture officer, over one season.

**What they do:** use the shortlist and Assess page to prepare a brief for one candidate site, then
compare with their usual process.

| Measure | How | Target |
|---|---|---|
| Time to a first assessment brief | Self-timed, compared with current practice | Shorter than current practice |
| Checks moved from *unknown* to *documented* or *measured* | Count in exported CSV | ≥ 5 of 8 checks per site |
| Officer understands what the score is and is not | 5-question check after first use | ≥ 4 of 5 correct |
| Disagreement with the shortlist | Officer marks districts they would order differently, with reason | All reasons recorded; used to revise criteria |
| Usability | SUS questionnaire | ≥ 70 |
| Language | Officer flags unclear Kinyarwanda/French strings | All flagged strings fixed |

**Not measured in a pilot:** whether investments chosen this way perform better. That needs years of
follow-up and is outside this entry.
