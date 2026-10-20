// Where every number comes from. Each chart card and number card names its unit,
// period, kind of estimate and source next to it (not only on Methods), and CSV
// downloads repeat the same fields. Links go to the NISR page or file itself.

export type SrcId =
  | 'sas_micro' | 'sas2024' | 'sas2025a' | 'sas2026a' | 'sas2026b'
  | 'ahs' | 'chirps' | 'gadm' | 'model' | 'screen';

export interface Source { short: string; title: string; url: string }

export const SOURCES: Record<SrcId, Source> = {
  sas_micro: {
    short: 'NISR SAS 2019–2025 microdata',
    title: 'NISR, Seasonal Agricultural Survey 2019–2025 microdata (Seasons A, B, C); estimates computed by the team',
    url: 'https://microdata.statistics.gov.rw/index.php/catalog',
  },
  sas2024: {
    short: 'NISR SAS 2024 Annual Report',
    title: 'NISR, Seasonal Agricultural Survey 2024 Annual Report, Executive summary (Table 0)',
    url: 'http://www.statistics.gov.rw/sites/default/files/documents/2025-02/SAS%202024%20Annual.pdf',
  },
  sas2025a: {
    short: 'NISR SAS 2025 Season A report',
    title: 'NISR, Seasonal Agricultural Survey Season A 2025, Final report (Section 4.1)',
    url: 'https://statistics.gov.rw/sites/default/files/documents/2025-05/SAS%202025A_Final%20%20report.pdf',
  },
  sas2026a: {
    short: 'NISR SAS 2026 Season A tables',
    title: 'NISR, Seasonal Agricultural Survey Season A 2026, published tables (released 28 April 2026)',
    url: 'https://statistics.gov.rw/sites/default/files/documents/2026-04/Tables_2026%20Season%20A.xlsx',
  },
  sas2026b: {
    short: 'NISR SAS 2026 Season B tables',
    title: 'NISR, Seasonal Agricultural Survey Season B 2026, published tables (released 22 September 2026)',
    url: 'https://statistics.gov.rw/sites/default/files/documents/2026-09/Tables_2026%20Season%20B.xlsx',
  },
  ahs: {
    short: 'NISR AHS 2017, 2020, 2024 microdata',
    title: 'NISR, Agricultural Household Survey 2017, 2020 and 2024 microdata; estimates computed by the team',
    url: 'https://microdata.statistics.gov.rw/index.php/catalog',
  },
  chirps: {
    short: 'CHIRPS v2 rainfall',
    title: 'Climate Hazards Center, CHIRPS v2.0 monthly rainfall 1981–2025, averaged by district by the team',
    url: 'https://www.chc.ucsb.edu/data/chirps',
  },
  gadm: { short: 'GADM 4.1 boundaries', title: 'GADM 4.1 district boundaries (level 2)', url: 'https://gadm.org/' },
  model: {
    short: 'Team model on SAS microdata',
    title: 'Team NiyoIshimwe model fitted to NISR SAS microdata (SCRIPTS/08_Models.R)',
    url: 'https://github.com/Umumasayii/NISR-Hackathon-And_Infograpfics-comprtitions/blob/master/SCRIPTS/08_Models.R',
  },
  screen: {
    short: 'Team screening index',
    title: 'Team NiyoIshimwe screening index (SCRIPTS/07_Build_App_Data.R, section 8)',
    url: 'https://github.com/Umumasayii/NISR-Hackathon-And_Infograpfics-comprtitions/blob/master/SCRIPTS/07_Build_App_Data.R',
  },
};

/** the kind of number: a survey estimate made by the team, a NISR published figure, both, a model output or an index */
export type Kind = 'survey' | 'official' | 'mixed' | 'model' | 'derived';

/** What a chart or number shows. Unit and note are already translated text. */
export interface Prov {
  unit: string;          // what is measured and over whom, e.g. "% of plots (Seasons A+B)"
  period?: string;       // e.g. "2019–2025" or "2026 Season B"
  kind: Kind;
  src: SrcId[];
  tables?: string[];     // NISR table names when official figures are shown
  note?: string;         // the caveat that matters most for this chart
}

/** NISR published-table source for a season, e.g. "2026A Table31: ..." -> sas2026a */
export const pubSrc = (season: string): SrcId[] => (/2026\s?A/.test(season) ? ['sas2026a'] : /2026\s?B/.test(season) ? ['sas2026b'] : /2025/.test(season) ? ['sas2025a'] : /2024/.test(season) ? ['sas2024'] : []);

/** Same provenance as columns, for CSV downloads */
export function provColumns(p: Prov, kindLabel: string): Record<string, string> {
  return {
    measure: p.unit,
    period: p.period ?? '',
    estimate_type: kindLabel,
    source: p.src.map((s) => SOURCES[s].title).join('; '),
    source_url: p.src.map((s) => SOURCES[s].url).join(' '),
    nisr_tables: (p.tables ?? []).join('; '),
    caveat: p.note ?? '',
  };
}
