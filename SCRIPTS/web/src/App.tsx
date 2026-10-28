import { useEffect, useRef, useState, type ReactNode } from 'react';
import { HashRouter, NavLink, Route, Routes, useLocation, Link } from 'react-router-dom';
import {
  BookOpen, LayoutDashboard, ChartColumn, Compass, House, MapPinned, IdCard, CloudSunRain, Table, Sprout, Droplets, Users, Brain, Trophy,
  Info, ChevronRight, Menu, X, SlidersHorizontal, CalendarDays, Map, MapPin, Layers, RotateCcw, Smartphone, type LucideIcon,
} from 'lucide-react';
import { useApp } from './data/store';
import { LANGS, type Lang } from './lib/i18n';
import { MultiSelect } from './components/ui';
import type { Season } from './data/types';
import Overview from './pages/Overview';
import MapPage from './pages/MapPage';
import District from './pages/District';
import Need from './pages/Need';
import Explorer from './pages/Explorer';
import Evidence from './pages/Evidence';
import How from './pages/How';
import Who from './pages/Who';
import Households from './pages/Households';
import Model from './pages/Model';
import Priority from './pages/Priority';
import Methods from './pages/Methods';

interface PageDef { path: string; key: string; icon: LucideIcon; el: ReactNode }
const PAGES: Record<string, PageDef> = {
  overview: { path: '/', key: 'p_overview', icon: LayoutDashboard, el: <Overview /> },
  map: { path: '/map', key: 'p_map', icon: MapPinned, el: <MapPage /> },
  district: { path: '/district', key: 'p_district', icon: IdCard, el: <District /> },
  need: { path: '/need', key: 'p_need', icon: CloudSunRain, el: <Need /> },
  explorer: { path: '/explorer', key: 'p_explorer', icon: Table, el: <Explorer /> },
  evidence: { path: '/evidence', key: 'p_evidence', icon: Sprout, el: <Evidence /> },
  how: { path: '/how', key: 'p_how', icon: Droplets, el: <How /> },
  who: { path: '/who', key: 'p_who', icon: Users, el: <Who /> },
  households: { path: '/households', key: 'p_households', icon: House, el: <Households /> },
  model: { path: '/model', key: 'p_model', icon: Brain, el: <Model /> },
  priority: { path: '/priority', key: 'p_priority', icon: Trophy, el: <Priority /> },
  methods: { path: '/methods', key: 'p_methods', icon: Info, el: <Methods /> },
};
const MENUS: { key: string; icon: LucideIcon; pages: string[] }[] = [
  { key: 'menu_story', icon: BookOpen, pages: ['overview', 'map', 'district', 'need'] },
  { key: 'menu_analyse', icon: ChartColumn, pages: ['explorer', 'evidence', 'how', 'who', 'households'] },
  { key: 'menu_act', icon: Compass, pages: ['model', 'priority'] },
];
// pages that use no global filter at all hide the filter panel
const NO_FILTERS = new Set(['/methods']);

export default function App() {
  return (
    <HashRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
      <Shell />
    </HashRouter>
  );
}

const PIN_KEY = 'si-pin-filters';
// closed unless the viewer opened them before
const readPin = () => { try { return localStorage.getItem(PIN_KEY) === '1'; } catch { return false; } };
// the width at which the filters fit beside the page (same as the CSS)
const WIDE = '(min-width: 961px)';
const isWide = () => typeof window !== 'undefined' && window.matchMedia(WIDE).matches;

function Shell() {
  const { tr, D } = useApp();
  const loc = useLocation();
  // wide screens: the filters are a sidebar beside the page, open until closed.
  // narrow screens: they slide in on demand over the page.
  const [drawer, setDrawer] = useState(false);
  const [pinned, setPinnedState] = useState(readPin);
  const setPinned = (v: boolean) => { setPinnedState(v); setDrawer(false); try { localStorage.setItem(PIN_KEY, v ? '1' : '0'); } catch { /* ignore */ } };
  const [wide, setWide] = useState(isWide);
  useEffect(() => {
    const m = window.matchMedia(WIDE);
    const on = () => setWide(m.matches);
    m.addEventListener('change', on);
    return () => m.removeEventListener('change', on);
  }, []);
  const openFilters = () => (wide ? setPinned(true) : setDrawer(true));
  const [menu, setMenu] = useState(false);
  useEffect(() => { setMenu(false); window.scrollTo({ top: 0 }); }, [loc.pathname]);
  useEffect(() => {
    const open = () => openFilters();
    window.addEventListener('si-open-filters', open);
    return () => window.removeEventListener('si-open-filters', open);
  }, [wide]); // eslint-disable-line
  // the filter drawer takes the focus when it opens and gives it back when it closes
  const side = useRef<HTMLElement>(null);
  useEffect(() => {
    if (!drawer) return;
    const back = document.activeElement as HTMLElement | null;
    side.current?.querySelector<HTMLElement>('button, select, input')?.focus();
    const k = (e: KeyboardEvent) => e.key === 'Escape' && setDrawer(false);
    window.addEventListener('keydown', k);
    return () => { window.removeEventListener('keydown', k); back?.focus?.(); };
  }, [drawer]);
  const page = Object.values(PAGES).find((p) => p.path === loc.pathname);
  useEffect(() => { document.title = page && page.path !== '/' ? `${tr(page.key)} · SmartIrrigate Rwanda` : 'SmartIrrigate Rwanda'; }, [page, tr]);
  const showFilters = !NO_FILTERS.has(loc.pathname);
  const docked = showFilters && pinned && wide;

  return (
    <div className="app">
      <SideNav />
      <div className="app-body">
      <TopBar onMenu={() => setMenu(!menu)} menuOpen={menu} onFilters={showFilters && !docked ? openFilters : undefined} />
      {menu && <MobileNav onClose={() => setMenu(false)} />}
      <div className={`shell ${docked ? 'docked' : ''}`}>
        {showFilters && (
          <>
            <aside ref={side} className={`sidebar ${drawer ? 'open' : ''}`} aria-label={tr('filters')} aria-hidden={!docked && !drawer}
              {...(drawer && !docked ? { role: 'dialog', 'aria-modal': true } : {})}>
              <FilterPanel onDone={() => (docked ? setPinned(false) : setDrawer(false))} />
            </aside>
            {drawer && <div className="scrim" onClick={() => setDrawer(false)} />}
          </>
        )}
        <main className="main" id="main">
          {page && page.path !== '/' && (
            <div className="page-head"><page.icon size={22} strokeWidth={1.8} /><h1>{tr(page.key)}</h1></div>
          )}
          <Routes>
            {Object.values(PAGES).map((p) => <Route key={p.path} path={p.path} element={p.el} />)}
            <Route path="*" element={<div className="card pad"><p>{tr('not_found')}</p><Link to="/">{tr('go_home')}</Link></div>} />
          </Routes>
          <footer className="app-footer">
            <p className="disclaimer">{tr('disclaimer')}{D.meta.interim ? ` ${tr('interim_note')}` : ''}</p>
            <span>{tr('footer_by')}</span><span>{'·'}</span>
            <Link to="/methods">{tr('footer_see_sources')}</Link><span>{'·'}</span>
            <span>{tr('built')} {D.meta.built} {'·'} v {__SITE_VERSION__}</span>
          </footer>
        </main>
      </div>
      </div>
      {showFilters && !docked && (
        <button className="fab" onClick={openFilters}><SlidersHorizontal size={18} /> {tr('show_filters')}<FilterCount /></button>
      )}
    </div>
  );
}

const Brand = () => (
  <Link to="/" className="brand"><img src={`${import.meta.env.BASE_URL}logo.svg`} alt="" width={34} height={34} /><span>SmartIrrigate <b>Rwanda</b></span></Link>
);

/** every page in view at once on wide screens, grouped as the story reads */
function SideNav() {
  const { tr } = useApp();
  return (
    <aside className="sidenav">
      <Brand />
      <nav aria-label="main">
        {MENUS.map((m) => (
          <div key={m.key} className="sn-group">
            <div className="sn-title">{tr(m.key)}</div>
            {m.pages.map((p) => { const P = PAGES[p]; return (
              <NavLink key={p} to={P.path} end className={({ isActive }) => `sn-link ${isActive ? 'active' : ''}`}><P.icon size={18} strokeWidth={1.8} /> {tr(P.key)}</NavLink>
            ); })}
          </div>
        ))}
        <div className="sn-group">
          <NavLink to="/methods" className={({ isActive }) => `sn-link ${isActive ? 'active' : ''}`}><Info size={18} strokeWidth={1.8} /> {tr('p_methods')}</NavLink>
        </div>
      </nav>
      <div className="sn-foot">{tr('footer_by')}</div>
    </aside>
  );
}

function TopBar({ onMenu, menuOpen, onFilters }: { onMenu: () => void; menuOpen: boolean; onFilters?: () => void }) {
  const { tr, lang, setLang } = useApp();
  const install = useInstallPrompt();
  const loc = useLocation();
  const group = MENUS.find((m) => m.pages.some((p) => PAGES[p].path === loc.pathname));
  const page = Object.values(PAGES).find((p) => p.path === loc.pathname);
  return (
    <header className="topbar">
      <span className="top-brand"><Brand /></span>
      {page && (
        <div className="crumbs">
          {group && <><span>{tr(group.key)}</span><ChevronRight size={14} /></>}
          <b>{tr(page.key)}</b>
        </div>
      )}
      <div className="top-right">
        {onFilters && <button className="btn outline sm top-filters" onClick={onFilters}><SlidersHorizontal size={15} /> {tr('show_filters')}<FilterCount /></button>}
        {install && <button className="btn outline sm install" onClick={install}><Smartphone size={15} /> {tr('install')}</button>}
        <div className="lang-switch" role="group" aria-label="Language">
          {(Object.keys(LANGS) as Lang[]).map((l) => (
            <button key={l} className={l === lang ? 'active' : ''} title={LANGS[l]} onClick={() => setLang(l)}>{l.toUpperCase()}</button>
          ))}
        </div>
        <button className="icon-btn menu-btn" onClick={onMenu} aria-label={tr('menu')} aria-expanded={menuOpen}>{menuOpen ? <X size={20} /> : <Menu size={20} />}</button>
      </div>
    </header>
  );
}

function MobileNav({ onClose }: { onClose: () => void }) {
  const { tr } = useApp();
  return (
    <nav className="mobile-nav">
      {MENUS.map((m) => (
        <div key={m.key} className="mn-group">
          <div className="mn-title">{tr(m.key)}</div>
          {m.pages.map((p) => { const P = PAGES[p]; return <NavLink key={p} to={P.path} end onClick={onClose}><P.icon size={18} /> {tr(P.key)}</NavLink>; })}
        </div>
      ))}
      <div className="mn-group"><NavLink to="/methods" onClick={onClose}><Info size={18} /> {tr('p_methods')}</NavLink></div>
    </nav>
  );
}

function FilterCount() {
  const { f, YEARS } = useApp();
  const n = (f.years.length < YEARS.length ? 1 : 0) + (f.seasons.join() !== 'A,B' ? 1 : 0) + (f.areaLevel !== 'national' ? 1 : 0) + (f.cropGroups.length || f.crops.length ? 1 : 0);
  return n ? <span className="f-count">{n}</span> : null;
}

function FilterPanel({ onDone }: { onDone: () => void }) {
  const { tr, sel, setSel, resetSel, YEARS, ALL_P, CROP_GRPS, D } = useApp();
  const scope = D.lookup.filter((r) => (sel.provinces.length ? sel.provinces : ALL_P).includes(r.province)).map((r) => r.district);
  const G = sel.cropGroups.length ? sel.cropGroups : CROP_GRPS;
  const crops = Array.from(new Set(D.crop.filter((r) => G.includes(r.crop_group)).map((r) => r.crop_name))).sort();
  const o = <T extends string | number>(x: T[]) => x.map((v) => ({ value: v, label: String(v) }));
  return (
    <div className="filters">
      <div className="sidebar-head">
        <span className="sh-icon"><SlidersHorizontal size={17} /></span>
        <div className="sidebar-title">{tr('filters')}</div>
        <button className="icon-btn drawer-close" onClick={onDone} aria-label={tr('unpin')} title={tr('unpin')}><X size={18} /></button>
      </div>
      <div className="filter-group">
        <div className="fg-title">{tr('fg_when')}</div>
        <MultiSelect label={tr('years')} icon={CalendarDays} options={o(YEARS)} value={sel.years} onChange={(v) => setSel({ years: v })} />
        <MultiSelect<Season> label={tr('seasons')} icon={CloudSunRain}
          options={[{ value: 'A', label: tr('season_a') }, { value: 'B', label: tr('season_b') }, { value: 'C', label: tr('season_c') }]}
          value={sel.seasons} onChange={(v) => setSel({ seasons: v })} />
      </div>
      <div className="filter-group">
        <div className="fg-title">{tr('fg_where')}</div>
        <MultiSelect label={tr('province')} icon={Map} options={o(ALL_P)} value={sel.provinces} onChange={(v) => setSel({ provinces: v })} allText={tr('all_rwanda')} />
        <MultiSelect label={tr('district')} icon={MapPin} options={o(scope)} value={sel.districts.filter((d) => scope.includes(d))} onChange={(v) => setSel({ districts: v })} search />
      </div>
      <div className="filter-group">
        <div className="fg-title">{tr('fg_what')}</div>
        <MultiSelect label={tr('crop_group')} icon={Layers} options={o(CROP_GRPS)} value={sel.cropGroups} onChange={(v) => setSel({ cropGroups: v })} />
        <MultiSelect label={tr('crop')} icon={Sprout} options={o(crops)} value={sel.crops.filter((c) => crops.includes(c))} onChange={(v) => setSel({ crops: v })} search />
      </div>
      <div className="filter-actions">
        <button className="btn outline" onClick={resetSel}><RotateCcw size={15} /> {tr('reset')}</button>
        <button className="btn primary drawer-apply" onClick={onDone}>{tr('apply')}</button>
      </div>
    </div>
  );
}

// "Install app" button where the browser offers it (Android / Chrome / Edge)
function useInstallPrompt() {
  const [ev, setEv] = useState<(Event & { prompt: () => Promise<void> }) | null>(null);
  useEffect(() => {
    const h = (e: Event) => { e.preventDefault(); setEv(e as Event & { prompt: () => Promise<void> }); };
    window.addEventListener('beforeinstallprompt', h);
    return () => window.removeEventListener('beforeinstallprompt', h);
  }, []);
  return ev ? () => { ev.prompt(); setEv(null); } : null;
}
