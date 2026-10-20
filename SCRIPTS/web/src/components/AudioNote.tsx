import { useEffect, useState } from 'react';
import { Volume2 } from 'lucide-react';
import { useApp } from '../data/store';

// Optional spoken summaries, recorded by a person (no text-to-speech). A note appears only
// when public/audio/manifest.json lists a recording for it; nothing plays by itself, and the
// transcript is always one tap away. See docs/Audio_Recording_Script.md.
interface Entry { file: string; transcript: Record<string, string>; reviewed?: boolean }
let manifest: Promise<Record<string, Entry>> | null = null;
const load = () => (manifest ??= fetch(`${import.meta.env.BASE_URL}audio/manifest.json`).then((r) => (r.ok ? r.json() : {})).catch(() => ({})) as Promise<Record<string, Entry>>);

export function AudioNote({ id }: { id: string }) {
  const { tr, lang } = useApp();
  const [e, setE] = useState<Entry | null>(null);
  useEffect(() => { let alive = true; load().then((m) => alive && setE(m[id] ?? null)); return () => { alive = false; }; }, [id]);
  if (!e) return null;
  return (
    <div className="audio-note">
      <span className="an-label"><Volume2 size={16} /> {tr('audio_play')}</span>
      <audio controls preload="none" src={`${import.meta.env.BASE_URL}audio/${e.file}`} />
      <details><summary>{tr('audio_transcript')}</summary><p lang="rw">{e.transcript.rw}</p>{lang !== 'rw' && e.transcript[lang] && <p>{e.transcript[lang]}</p>}</details>
    </div>
  );
}
