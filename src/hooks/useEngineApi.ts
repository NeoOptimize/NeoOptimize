import { useEffect, useState } from 'react';
import { apiEventSource, apiFetch } from '../lib/api';

type EngineStatus = {
  running: boolean;
  progress: number;
  total: number;
  mode?: string;
  dryRun?: boolean;
  statusMessage?: string;
  [key: string]: any;
};

type EngineLog = {
  time: string;
  level: string;
  message: string;
  [key: string]: any;
};

export function useEngineApi(engine = 'advance') {
  const [status, setStatus] = useState<EngineStatus>({ running: false, progress: 0, total: 100, mode: 'full', dryRun: true });
  const [logs, setLogs] = useState<EngineLog[]>([]);

  useEffect(() => {
    apiFetch(`/api/clean/${engine}/status`).then((r) => r.json()).then((j) => setStatus((s) => ({ ...s, ...j }))).catch(() => {});
    const es = apiEventSource(`/api/events/${engine}`);
    es.addEventListener('progress', (ev: any) => {
      try {
        const d = JSON.parse(ev.data);
        setStatus((s) => ({ ...s, ...d, progress: d.progress ?? s.progress, total: d.total ?? s.total }));
      } catch {}
    });
    es.addEventListener('log', (ev: any) => {
      try { const d = JSON.parse(ev.data); setLogs((l) => [...l.slice(-200), { time: new Date().toLocaleTimeString(), ...d }]); } catch {}
    });
    es.addEventListener('done', (ev: any) => {
      try { const d = JSON.parse(ev.data); setLogs((l) => [...l, { time: new Date().toLocaleTimeString(), level: 'ok', message: `done: ${JSON.stringify(d)}` }]); } catch {}
    });
    es.onerror = () => {};
    return () => { es.close(); };
  }, [engine]);

  async function start(opts = {}) {
    await apiFetch(`/api/clean/${engine}/start`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(opts) });
    const s = await (await apiFetch(`/api/clean/${engine}/status`)).json();
    setStatus((prev) => ({ ...prev, ...s }));
  }

  async function stop() {
    await apiFetch(`/api/clean/${engine}/stop`, { method: 'POST' });
    const s = await (await apiFetch(`/api/clean/${engine}/status`)).json();
    setStatus((prev) => ({ ...prev, ...s }));
  }

  return { status, logs, start, stop };
}
