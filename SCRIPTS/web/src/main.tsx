import { StrictMode, useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { registerSW } from 'virtual:pwa-register';
import App from './App';
import { AppProvider, loadAll, type Loaded } from './data/store';
import { WEB_I18N, WEB_OVERRIDE } from './lib/webI18n';
import { initialLang } from './lib/i18n';
// Poppins ships with the app (not from a font server), so it also works offline
import '@fontsource/poppins/latin-400.css';
import '@fontsource/poppins/latin-500.css';
import '@fontsource/poppins/latin-600.css';
import '@fontsource/poppins/latin-700.css';
import './styles.css';

registerSW({ immediate: true });

function Boot() {
  const [data, setData] = useState<Loaded | null>(null);
  const [err, setErr] = useState(false);
  useEffect(() => {
    loadAll().then((d) => {
      for (const [k, v] of Object.entries(WEB_I18N)) if (!d.dict[k]) d.dict[k] = v;
      Object.assign(d.dict, WEB_OVERRIDE);
      setData(d);
    }).catch((e) => { console.error(e); setErr(true); });
  }, []);
  const l = initialLang();
  if (err) return <div className="boot"><p>{WEB_I18N.load_error[l]}</p></div>;
  if (!data) return (
    <div className="boot">
      <img src={`${import.meta.env.BASE_URL}logo.svg`} alt="" width={64} height={64} />
      <div className="boot-name">SmartIrrigate Rwanda</div>
      <div className="boot-bar"><span /></div>
      <p>{WEB_I18N.loading[l]}</p>
    </div>
  );
  return <AppProvider data={data}><App /></AppProvider>;
}

createRoot(document.getElementById('root')!).render(<StrictMode><Boot /></StrictMode>);
