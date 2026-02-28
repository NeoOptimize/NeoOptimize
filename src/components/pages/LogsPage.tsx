import React, { useMemo, useState } from 'react';
import { FileText, Download, Search } from 'lucide-react';
import { apiFetch } from '../../lib/api';

type Log = { time?: string; level?: string; message?: string; engine?: string };

const FILTERS = ['ALL', 'OK', 'WARN', 'ERR', 'INFO'];

function normalize(level?: string) {
  const v = String(level || '').toLowerCase();
  if (v === 'error' || v === 'err') return 'ERR';
  if (v === 'warn' || v === 'warning') return 'WARN';
  if (v === 'ok' || v === 'success') return 'OK';
  return 'INFO';
}

function color(level: string) {
  if (level === 'ERR') return 'var(--ansi-red)';
  if (level === 'WARN') return 'var(--ansi-yellow)';
  if (level === 'OK') return 'var(--ansi-green)';
  return 'var(--ansi-blue)';
}

export function LogsPage() {
  const [logs, setLogs] = useState<Log[]>([]);
  const [activeFilter, setActiveFilter] = useState('ALL');
  const [search, setSearch] = useState('');
  const [generating, setGenerating] = useState(false);
  const [reportPath, setReportPath] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [lastUpdated, setLastUpdated] = useState('');

  React.useEffect(() => {
    let mounted = true;
    const refresh = async () => {
      try {
        const r = await apiFetch('/api/logs?limit=400');
        const j = await r.json();
        if (mounted && j?.ok) setLogs(j.logs || []);
        setLastUpdated(new Date().toLocaleTimeString());
        setError('');
      } catch (err: any) {
        setError(String(err?.message || err));
      } finally {
        setLoading(false);
      }
    };
    refresh();
    const iv = setInterval(refresh, 2000);
    return () => { mounted = false; clearInterval(iv); };
  }, []);

  const generateReport = async () => {
    setGenerating(true);
    try {
      const r = await apiFetch('/api/report/generate', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ engine: 'advance' }) });
      const j = await r.json();
      if (j?.ok) {
        setReportPath(j.path);
        setError('');
      } else {
        setError(String(j?.error || 'report generation failed'));
      }
    } catch (err: any) {
      setError(String(err?.message || err));
    }
    setGenerating(false);
  };

  const filtered = useMemo(() => logs.filter((l) => {
    const lvl = normalize(l.level);
    if (activeFilter !== 'ALL' && lvl !== activeFilter) return false;
    const blob = `${l.time || ''} ${l.engine || ''} ${l.message || ''}`.toLowerCase();
    return blob.includes(search.toLowerCase());
  }), [logs, activeFilter, search]);

  return (
    <div className="space-y-4">
      <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>$</span>
        <span>tail -f neooptimize.log</span>
        <span style={{ color: 'var(--ansi-cyan)' }}>{lastUpdated ? `updated ${lastUpdated}` : ''}</span>
      </div>

      {(loading || error) && (
        <div className="px-3 py-2 text-xs font-mono border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: error ? 'var(--ansi-red)' : 'var(--text-primary)' }}>
          {loading ? 'Loading logs...' : error}
        </div>
      )}

      <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="flex items-center gap-2 mb-3 text-xs font-bold" style={{ color: 'var(--ansi-blue)' }}><FileText size={14} /> HTML REPORT EXPORT</div>
        <div className="text-xs font-mono mb-3 p-2 border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--terminal-output-bg)', color: 'var(--text-muted)' }}>$ neooptimize --export-report --format=html</div>
        <button onClick={generateReport} disabled={generating} className="w-full py-2 text-xs font-bold border transition-colors flex items-center justify-center gap-2" style={{ borderColor: 'var(--ansi-blue)', color: generating ? 'var(--bg-primary)' : 'var(--ansi-blue)', backgroundColor: generating ? 'var(--ansi-blue)' : 'transparent' }}>
          {generating ? 'GENERATING REPORT...' : '[GENERATE REPORT]'}
        </button>
        {reportPath && (
          <div className="mt-2 flex items-center justify-between p-2 border text-xs font-mono" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-primary)' }}>
            <span className="truncate mr-2" style={{ color: 'var(--text-primary)' }}>{reportPath}</span>
            <button onClick={() => navigator?.clipboard?.writeText?.(reportPath)} className="px-2 py-1 text-[10px] font-bold border flex items-center gap-1" style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}><Download size={10} /> COPY PATH</button>
          </div>
        )}
      </div>

      <div className="border flex flex-col h-[500px]" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="p-2 border-b flex items-center justify-between" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)' }}>
          <div className="flex gap-2">
            {FILTERS.map((f) => (
              <button key={f} onClick={() => setActiveFilter(f)} className="px-2 py-0.5 text-[10px] border" style={{ borderColor: activeFilter === f ? 'var(--ansi-green)' : 'var(--border-color)', color: activeFilter === f ? 'var(--ansi-green)' : 'var(--text-muted)' }}>{f}</button>
            ))}
          </div>
          <div className="flex items-center gap-2 px-2 py-0.5 border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-primary)' }}>
            <Search size={10} style={{ color: 'var(--text-muted)' }} />
            <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="grep..." className="bg-transparent outline-none text-[10px] w-24" style={{ color: 'var(--text-primary)' }} />
          </div>
        </div>

        <div className="flex-1 overflow-y-auto p-2 font-mono text-xs space-y-1" style={{ backgroundColor: 'var(--terminal-output-bg)' }}>
          {filtered.map((log, i) => {
            const lvl = normalize(log.level);
            return (
              <div key={`${log.time}-${i}`} className="flex gap-2">
                <span style={{ color: 'var(--text-muted)' }}>{log.time ? new Date(log.time).toLocaleTimeString() : '--:--:--'}</span>
                <span style={{ color: color(lvl) }}>[{lvl}]</span>
                <span style={{ color: 'var(--ansi-cyan)' }}>{String(log.engine || 'system').toUpperCase()}</span>
                <span style={{ color: 'var(--text-primary)' }}>{log.message}</span>
              </div>
            );
          })}
          {filtered.length === 0 && <div style={{ color: 'var(--text-muted)' }}>No logs match filter/search</div>}
        </div>
      </div>
    </div>
  );
}
