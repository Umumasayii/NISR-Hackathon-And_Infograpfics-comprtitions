import { Fragment, isValidElement, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import {
  CalendarDays, Check, CheckCheck, ChevronDown, CloudSunRain, Download, Info, MapPin, Maximize2, Minimize2, Search, SlidersHorizontal, Sprout, X,
  type LucideIcon,
} from 'lucide-react';
import { useApp } from '../data/store';
import { relCols } from '../lib/theme';
import { downloadCsv } from '../lib/stats';

// ---- short text ------------------------------------------------------------------------------
/** plain text of a string or a fragment of strings; null when it holds other elements */
function toText(n: ReactNode): string | null {
  if (n == null || typeof n === 'boolean') return '';
  if (typeof n === 'string' || typeof n === 'number') return String(n);
  if (Array.isArray(n)) { const p = n.map(toText); return p.some((x) => x === null) ? null : p.join(''); }
  if (isValidElement(n) && n.type === Fragment) return toText((n.props as { children?: ReactNode }).children);
  return null;
}
/** first sentence and the rest ("2.5%" and "e.g." stay whole: a sentence ends at . ! ? before a space) */
function splitFirst(s: string): [string, string] {
  const m = s.trim().match(/^(.+?[.!?])\s+(\S[\s\S]*)$/);
  return m ? [m[1], m[2]] : [s.trim(), ''];
}

/** One line to read, the rest one tap away: the first sentence, or two lines of richer content */
export function Brief({ children, className = '' }: { children: ReactNode; className?: string }) {
  const { tr } = useApp();
  const [open, setOpen] = useState(false);
  const text = toText(children);
  const [lead, rest] = text !== null ? splitFirst(text) : ['', ''];
  const box = useRef<HTMLDivElement>(null);
  const [over, setOver] = useState(false);
  useLayoutEffect(() => {
    if (text !== null || !box.current) return;
    const el = box.current;
    const check = () => setOver(el.scrollHeight > el.clientHeight + 2);
    check();
    const ro = new ResizeObserver(check); ro.observe(el);
    return () => ro.disconnect();
  }, [text, children]);
  const more = (text !== null ? !!rest : over || open) && (
    <button type="button" className="more-btn" onClick={() => setOpen(!open)} aria-expanded={open}>{tr(open ? 'less' : 'more')}</button>
  );
  if (text !== null) {
    if (!lead) return null;
    return (
      <div className={`brief ${className}`}>
        <span>{lead}</span>{' '}{more}
        {open && rest && <div className="brief-rest">{rest}</div>}
      </div>
    );
  }
  return (
    <div className={`brief ${className}`}>
      <div ref={box} className={open ? '' : 'brief-clamp'}>{children}</div>{more}
    </div>
  );
}

// ---- cards -------------------------------------------------------------------------------
/** Every chart card: title, the one-line message the chart shows, optional tools, the chart */
export function ChartCard({ title, icon: Icon, tools, means, children, className = '' }: {
  title: string; icon?: LucideIcon; tools?: ReactNode; means?: ReactNode; children: ReactNode; className?: string;
}) {
  const [full, setFull] = useState(false);
  const { tr } = useApp();
  useEffect(() => {
    if (!full) return;
    const k = (e: KeyboardEvent) => e.key === 'Escape' && setFull(false);
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, [full]);
  return (
    <section className={`card chart-card ${full ? 'is-full' : ''} ${className}`}>
      <header className="card-head">
        {Icon && <span className="ch-icon"><Icon size={15} strokeWidth={2} /></span>}
        <h3>{title}</h3>
        <button className="icon-btn ghost" onClick={() => setFull(!full)} aria-label={tr(full ? 'close' : 'expand')} title={full ? 'Esc' : tr('expand')}>
          {full ? <Minimize2 size={15} /> : <Maximize2 size={15} />}
        </button>
      </header>
      {means ? <Brief className="takeaway">{means}</Brief> : null}
      {tools && <div className="card-tools">{tools}</div>}
      <div className="card-body">{children}</div>
    </section>
  );
}

/** a missing table cell (null or NaN) shows as a dash */
const cell = (v: unknown) => (v == null || (typeof v === 'number' && !Number.isFinite(v)) ? '–' : (v as ReactNode));

/** Number card: circled line icon, title, one big value, period below; the definition in a hover hint */
export function Kpi({ label, value, icon: Icon, color, foot, delta, deltaGood = true, hint }: {
  label: string; value: string; icon: LucideIcon; color: string; foot?: ReactNode; delta?: number | null; deltaGood?: boolean; hint?: string;
}) {
  const shown = useCountUp(value);
  // a long plain-text note keeps its first part on the card; the rest moves to the hint
  if (typeof foot === 'string' && !hint) {
    const m = foot.match(/^(.+?)(?:\s\(|\.\s)/);
    if (m && m[1].length >= 8) { hint = foot; foot = m[1]; }
  }
  return (
    <div className="card kpi" style={{ ['--accent' as string]: color }}>
      <span className="kpi-icon"><Icon size={22} strokeWidth={1.8} /></span>
      {hint && <span className="kpi-hint" tabIndex={0} title={hint} aria-label={hint}><Info size={14} /></span>}
      <div className="kpi-label">{label}</div>
      <div className="kpi-value">{shown}
        {delta != null && Number.isFinite(delta) && (
          <span className={`delta ${(delta >= 0) === deltaGood ? 'good' : 'bad'}`}>{delta >= 0 ? '+' : ''}{delta.toFixed(1)}</span>)}
      </div>
      {foot && <div className="kpi-foot">{foot}</div>}
    </div>
  );
}
export const KpiRow = ({ children }: { children: ReactNode }) => <div className="kpi-row">{children}</div>;

/** count-up animation of the number inside a value such as "27.1%" or "+14%" */
function useCountUp(value: string) {
  const [out, setOut] = useState(value);
  useEffect(() => {
    const m = value.match(/^([^\d-]*)(-?[\d,]*\.?\d+)(.*)$/);
    // ranges such as "2024–2025" or "13% / 14%" are shown as they are
    if (!m || (value.match(/\d+/g) || []).length > 2 || /\d\D+\d/.test(m[3]) || window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) { setOut(value); return; }
    const target = parseFloat(m[2].replace(/,/g, '')); const dec = (m[2].split('.')[1] || '').length, grp = m[2].includes(',');
    let raf = 0; const t0 = performance.now();
    const step = (t: number) => {
      const k = Math.min((t - t0) / 800, 1), e = 1 - (1 - k) ** 3;
      setOut(m[1] + (target * e).toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec, useGrouping: grp }) + m[3]);
      if (k < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [value]);
  return out;
}

/** A finding told by its number: the number large, the short claim beside it, the detail one tap away */
export function Insight({ icon: Icon, title, text, color }: { icon: LucideIcon; title: string; text: string; color: string }) {
  const [open, setOpen] = useState(false);
  const m = title.match(/^([+\-−]?\d[\d.,]*\s?%?)\s+(.+)$/);
  return (
    <button type="button" className={`card insight ${open ? 'open' : ''}`} style={{ ['--accent' as string]: color }} onClick={() => setOpen(!open)} aria-expanded={open}>
      {m ? <span className="in-num">{m[1]}</span> : <span className="in-icon"><Icon size={20} /></span>}
      <span className="in-body">
        <span className="in-title">{m ? m[2] : title}</span>
        {open && <span className="in-text">{text}</span>}
      </span>
      <ChevronDown size={16} className="in-chev" />
    </button>
  );
}
export const InsightGrid = ({ children }: { children: ReactNode }) => <div className="insight-grid">{children}</div>;

/** Section heading; the old subtitles are dropped so the numbers below do the talking */
export const SectionTitle = ({ title }: { title: string; sub?: string }) => (
  <div className="section-title"><h2>{title}</h2></div>
);

export function Callout({ icon: Icon, kind = '', children }: { icon: LucideIcon; kind?: '' | 'soft' | 'warn'; children: ReactNode }) {
  return <div className={`callout ${kind}`}><Icon size={17} className="callout-ic" /><Brief>{children}</Brief></div>;
}

/** The current choice for the filters this page follows; a tap opens the filters */
export const openFilters = () => window.dispatchEvent(new Event('si-open-filters'));
export function FiltersUsed({ used }: { used: ('years' | 'seasons' | 'area' | 'crop')[] }) {
  const { tr, f, YEARS } = useApp();
  const ys = [...f.years].sort((a, b) => a - b);
  const run = ys.length > 1 && ys[ys.length - 1] - ys[0] === ys.length - 1;
  const years = !ys.length ? '–' : ys.length === 1 ? String(ys[0]) : run || ys.length === YEARS.length ? `${ys[0]}–${ys[ys.length - 1]}` : ys.join(', ');
  const crop = f.crops.length ? (f.crops.length === 1 ? f.crops[0] : tr('n_crops', f.crops.length)) : f.cropGroups.length ? f.cropGroups.join(', ') : tr('all_crops');
  const area = f.areaLevel === 'district' && f.districts.length > 2 ? tr('n_districts', f.districts.length) : f.area;
  const chips: { k: (typeof used)[number]; icon: LucideIcon; v: string }[] = [
    { k: 'years', icon: CalendarDays, v: years }, { k: 'seasons', icon: CloudSunRain, v: f.seasons.join(' + ') },
    { k: 'area', icon: MapPin, v: area }, { k: 'crop', icon: Sprout, v: crop },
  ];
  return (
    <div className="filters-used">
      {chips.filter((c) => used.includes(c.k)).map((c) => (
        <button type="button" key={c.k} className="fu" onClick={openFilters} title={tr('edit_filters')}><c.icon size={13} /> {c.v}</button>
      ))}
      <button type="button" className="fu edit" onClick={openFilters} aria-label={tr('edit_filters')} title={tr('edit_filters')}><SlidersHorizontal size={13} /></button>
    </div>
  );
}

const REL_KEY: Record<string, string> = { Good: 'rb_good', 'Use with caution': 'rb_caution', Unreliable: 'rb_unreliable', Published: 'rb_published' };
export function RelBadge({ r }: { r: string | null | undefined }) {
  const { tr } = useApp();
  if (!r || !REL_KEY[r]) return null;
  return <span className="rel-badge" style={{ color: relCols[r], borderColor: relCols[r] }}>{tr(REL_KEY[r])}</span>;
}
export const relLabel = (tr: (k: string) => string, r: string | null | undefined) => (r && REL_KEY[r] ? tr(REL_KEY[r]) : '–');

export const Grid = ({ cols, children }: { cols: string; children: ReactNode }) => (
  <div className="grid" style={{ ['--cols' as string]: cols }}>{children}</div>
);

// ---- inputs ------------------------------------------------------------------------------
export function Select<T extends string | number>({ value, onChange, options, label, width }: {
  value: T; onChange: (v: T) => void; options: { value: T; label: string }[]; label?: string; width?: number | string;
}) {
  return (
    <label className="select" style={{ width }}>
      {label && <span className="select-label">{label}</span>}
      <span className="select-box">
        <select value={String(value)} onChange={(e) => {
          const o = options.find((x) => String(x.value) === e.target.value); if (o) onChange(o.value);
        }}>
          {options.map((o) => <option key={String(o.value)} value={String(o.value)}>{o.label}</option>)}
        </select>
        <ChevronDown size={16} className="select-chev" />
      </span>
    </label>
  );
}

/** Multi-select dropdown with Select all / Clear (and a search box for long lists). Empty = all. */
export function MultiSelect<T extends string | number>({ label, icon: Icon, options, value, onChange, search = false, allText }: {
  label: string; icon: LucideIcon; options: { value: T; label: string }[]; value: T[]; onChange: (v: T[]) => void;
  search?: boolean; allText?: string;
}) {
  const { tr } = useApp();
  const [open, setOpen] = useState(false);
  const [q, setQ] = useState('');
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const h = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false); };
    const k = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false);
    document.addEventListener('mousedown', h); document.addEventListener('keydown', k);
    return () => { document.removeEventListener('mousedown', h); document.removeEventListener('keydown', k); };
  }, [open]);
  const on = options.filter((o) => value.includes(o.value));
  const narrowed = on.length > 0 && on.length < options.length;
  const text = !narrowed ? (allText ?? tr('all')) : on.length <= 2 ? on.map((o) => o.label).join(', ') : tr('n_selected', on.length);
  const shown = q ? options.filter((o) => o.label.toLowerCase().includes(q.toLowerCase())) : options;
  const toggle = (v: T) => onChange(value.includes(v) ? value.filter((x) => x !== v) : options.map((o) => o.value).filter((x) => x === v || value.includes(x)));
  return (
    <div className={`mp ${open ? 'open' : ''} ${narrowed ? 'narrowed' : ''}`} ref={ref}>
      <div className="mp-label"><Icon size={14} /> {label}</div>
      <button type="button" className="mp-btn" aria-expanded={open} onClick={() => setOpen(!open)}>
        <span className="mp-text">{text}</span>
        <span className="mp-count">{narrowed ? `${on.length}/${options.length}` : options.length}</span>
        <ChevronDown size={16} className="mp-chev" />
      </button>
      {open && (
        <div className="mp-menu" role="listbox" aria-multiselectable>
          <div className="mp-actions">
            <button type="button" onClick={() => onChange(options.map((o) => o.value))}><CheckCheck size={14} /> {tr('select_all')}</button>
            <button type="button" onClick={() => onChange([])}><X size={14} /> {tr('clear')}</button>
          </div>
          {search && (
            <div className="mp-search"><Search size={14} />
              <input type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder={tr('search_ph')} autoFocus />
            </div>
          )}
          <div className="mp-list">
            {shown.map((o) => (
              <label key={String(o.value)} className="mp-opt">
                <input type="checkbox" checked={value.includes(o.value)} onChange={() => toggle(o.value)} />
                <span className="mp-box"><Check size={12} strokeWidth={3} /></span>
                <span>{o.label}</span>
              </label>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

export function Tabs({ tabs, active, onChange }: { tabs: { id: string; label: string; icon?: LucideIcon }[]; active: string; onChange: (id: string) => void }) {
  return (
    <div className="tabs" role="tablist">
      {tabs.map(({ id, label, icon: I }) => (
        <button key={id} role="tab" aria-selected={active === id} className={active === id ? 'active' : ''} onClick={() => onChange(id)}>
          {I && <I size={15} />} {label}
        </button>
      ))}
    </div>
  );
}

// ---- table -------------------------------------------------------------------------------
export interface Col<T> { key: string; label: string; get: (r: T) => string | number | null; render?: (r: T) => ReactNode; num?: boolean }
/** Sortable, searchable table with pages and a CSV download */
export function DataTable<T>({ rows, cols, pageSize = 12, csvName, csvRows, searchable = true }: {
  rows: T[]; cols: Col<T>[]; pageSize?: number; csvName?: string; csvRows?: () => Record<string, unknown>[]; searchable?: boolean;
}) {
  const { tr } = useApp();
  const [q, setQ] = useState('');
  const [sort, setSort] = useState<{ k: string; dir: 1 | -1 } | null>(null);
  const [page, setPage] = useState(0);
  useEffect(() => setPage(0), [rows, q]);
  const shown = useMemo(() => {
    let r = rows;
    if (q) { const s = q.toLowerCase(); r = r.filter((x) => cols.some((c) => String(c.get(x) ?? '').toLowerCase().includes(s))); }
    if (sort) {
      const c = cols.find((x) => x.key === sort.k)!;
      r = [...r].sort((a, b) => {
        const va = c.get(a), vb = c.get(b);
        if (va == null) return 1; if (vb == null) return -1;
        return (typeof va === 'number' && typeof vb === 'number' ? va - vb : String(va).localeCompare(String(vb))) * sort.dir;
      });
    }
    return r;
  }, [rows, cols, q, sort]);
  const pages = Math.max(1, Math.ceil(shown.length / pageSize));
  const slice = shown.slice(page * pageSize, (page + 1) * pageSize);
  return (
    <div className="dt">
      <div className="dt-bar">
        {searchable && <label className="dt-search"><Search size={14} /><input type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder={tr('search_ph')} /></label>}
        <span className="dt-count">{shown.length.toLocaleString('en-US')} {tr('rows')}</span>
        {csvName && (
          <button className="btn outline sm" onClick={() => downloadCsv(csvRows ? csvRows() : shown.map((r) => Object.fromEntries(cols.map((c) => [c.label, c.get(r)]))), csvName)}>
            <Download size={14} /> {tr('download_csv')}
          </button>
        )}
      </div>
      <div className="dt-scroll">
        <table>
          <thead><tr>{cols.map((c) => (
            <th key={c.key} className={c.num ? 'num' : ''} onClick={() => setSort(sort?.k === c.key ? { k: c.key, dir: sort.dir === 1 ? -1 : 1 } : { k: c.key, dir: c.num ? -1 : 1 })}>
              {c.label}{sort?.k === c.key ? (sort.dir === 1 ? ' ▲' : ' ▼') : ''}
            </th>))}</tr></thead>
          <tbody>{slice.map((r, i) => (
            <tr key={i}>{cols.map((c) => <td key={c.key} className={c.num ? 'num' : ''}>{c.render ? c.render(r) : cell(c.get(r))}</td>)}</tr>
          ))}</tbody>
        </table>
      </div>
      {pages > 1 && (
        <div className="dt-pages">
          <button className="btn ghost sm" disabled={page === 0} onClick={() => setPage(page - 1)}>{'‹'}</button>
          <span>{page + 1} / {pages}</span>
          <button className="btn ghost sm" disabled={page >= pages - 1} onClick={() => setPage(page + 1)}>{'›'}</button>
        </div>
      )}
    </div>
  );
}

export const Muted = ({ children }: { children: ReactNode }) => <p className="muted">{children}</p>;
