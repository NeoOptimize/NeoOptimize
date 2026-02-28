import React, { useEffect, useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import { HardDrive, Trash2, Folder, Database } from 'lucide-react';
import { useEngineApi } from '../../hooks/useEngineApi';
import { apiFetch } from '../../lib/api';

type Results = {
  files: Array<{ path: string; sizeKB?: number; category?: string }>;
  registry: Array<{ key: string; reason: string }>;
  backups: Array<{ id: string; time: string; meta?: any }>;
};

export function StoragePage() {
  const engine = useEngineApi('advance');
  const [results, setResults] = useState<Results>({ files: [], registry: [], backups: [] });
  const [profiles, setProfiles] = useState<Array<{ id: string; label: string; description: string }>>([]);
  const [selectedProfile, setSelectedProfile] = useState('quick-clean');
  const [applyChanges, setApplyChanges] = useState(false);
  const [backupNote, setBackupNote] = useState('');
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [lastUpdated, setLastUpdated] = useState('');

  const refreshResults = React.useCallback(async (silent = true) => {
    if (!silent) setLoading(true);
    try {
      const [resR, bkR] = await Promise.all([apiFetch('/api/clean/advance/results'), apiFetch('/api/clean/advance/backups')]);
      const j1 = await resR.json();
      const j2 = await bkR.json();
      const payload = j1?.results || {};
      setResults({
        files: payload.files || [],
        registry: payload.registry || [],
        backups: j2?.backups || payload.backups || []
      });
      setLastUpdated(new Date().toLocaleTimeString());
      setError('');
    } catch (err: any) {
      setError(String(err?.message || err));
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  useEffect(() => {
    let mounted = true;
    const init = async () => {
      try {
        const r = await apiFetch('/api/clean/advance/profiles');
        const j = await r.json();
        if (mounted && j?.ok && Array.isArray(j.profiles) && j.profiles.length > 0) setProfiles(j.profiles);
      } catch (err: any) {
        if (mounted) setError(String(err?.message || err));
      }
      await refreshResults(false);
    };
    init();
    return () => { mounted = false; };
  }, [refreshResults]);

  useEffect(() => {
    const iv = setInterval(() => refreshResults(true), engine.status.running ? 1200 : 3000);
    return () => clearInterval(iv);
  }, [engine.status.running, refreshResults]);

  const startCleaner = async () => {
    setBusy(true);
    try {
      const mode = selectedProfile === 'quick-clean' ? 'dump' : 'full';
      const dryRunMode = !applyChanges;
      if (!dryRunMode && !window.confirm(`APPLY mode will modify/delete files for profile ${selectedProfile}. Continue?`)) {
        setBusy(false);
        return;
      }
      await engine.start({ mode, total: selectedProfile === 'aggressive-clean' ? 180 : 120, profile: selectedProfile, dryRun: dryRunMode });
      setMessage(`Cleaner started with profile ${selectedProfile} (${dryRunMode ? 'safe dry-run' : 'APPLY changes'})`);
      setError('');
    } catch (err: any) {
      setMessage(`Failed to start cleaner: ${String(err?.message || err)}`);
      setError(String(err?.message || err));
    } finally {
      setBusy(false);
    }
  };

  const runSpecialScan = async (type: 'registry') => {
    setBusy(true);
    try {
      const dryRunMode = !applyChanges;
      if (!dryRunMode && !window.confirm(`APPLY mode will execute ${type} cleanup actions. Continue?`)) {
        setBusy(false);
        return;
      }
      const r = await apiFetch(`/api/clean/advance/${type}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ total: 90, dryRun: dryRunMode }) });
      const j = await r.json();
      if (!r.ok || j?.ok === false) {
        setMessage(`${type} scan failed: ${j?.error || 'unknown error'}`);
        setError(`${type} scan failed: ${j?.error || 'unknown error'}`);
      } else {
        setMessage(`${type} scan started (${dryRunMode ? 'safe dry-run' : 'APPLY changes'})`);
        setError('');
      }
    } catch (err: any) {
      setMessage(`${type} scan failed: ${String(err?.message || err)}`);
      setError(String(err?.message || err));
    } finally {
      setBusy(false);
    }
  };

  const createBackup = async () => {
    setBusy(true);
    try {
      const r = await apiFetch('/api/clean/advance/backup', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ note: backupNote || 'manual' }) });
      const j = await r.json();
      if (!r.ok || !j?.ok) {
        setMessage(`Create backup failed: ${j?.error || 'unknown error'}`);
        setError(`Create backup failed: ${j?.error || 'unknown error'}`);
      } else {
        setMessage(`Backup created: ${j.entry.id}`);
        setError('');
      }
      setBackupNote('');
      await refreshResults(true);
    } catch (err: any) {
      setMessage(`Create backup failed: ${String(err?.message || err)}`);
      setError(String(err?.message || err));
    } finally {
      setBusy(false);
    }
  };

  const restoreBackup = async (id: string) => {
    if (!window.confirm(`Restore backup ${id}?`)) return;
    setBusy(true);
    try {
      const r = await apiFetch('/api/clean/advance/backup/restore', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id }) });
      const j = await r.json();
      if (!r.ok || !j?.ok) {
        setMessage(`Restore failed: ${j?.error || 'unknown error'}`);
        setError(`Restore failed: ${j?.error || 'unknown error'}`);
      } else {
        setMessage(`Backup restored: ${id}`);
        setError('');
      }
      await refreshResults(true);
    } catch (err: any) {
      setMessage(`Restore failed: ${String(err?.message || err)}`);
      setError(String(err?.message || err));
    } finally {
      setBusy(false);
    }
  };

  const reclaimedMB = useMemo(() => Math.round((results.files || []).reduce((s, f) => s + (f.sizeKB || 0), 0) / 1024), [results.files]);
  const progressPct = Math.round((engine.status.progress / Math.max(1, engine.status.total || 100)) * 100);
  const dryRun = engine.status?.dryRun !== false;

  return (
    <div className="space-y-4">
      <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>$</span>
        <span>neooptimize cleaner --profile {selectedProfile}</span>
        <span style={{ color: 'var(--ansi-cyan)' }}>{lastUpdated ? `updated ${lastUpdated}` : ''}</span>
      </div>

      {(loading || error || message) && (
        <div className="px-3 py-2 text-xs font-mono border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: error ? 'var(--ansi-red)' : 'var(--text-primary)' }}>
          {loading ? 'Loading storage cleaner data...' : error || message}
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {[
          { mount: 'Cleaner Progress', value: `${progressPct}%`, used: progressPct, type: 'RUN' },
          { mount: 'Recovered', value: `${reclaimedMB} MB`, used: Math.min(100, reclaimedMB / 20), type: 'SPACE' },
          { mount: 'Registry', value: `${results.registry.length}`, used: Math.min(100, results.registry.length * 8), type: 'ISSUES' },
          { mount: 'Backups', value: `${results.backups.length}`, used: Math.min(100, results.backups.length * 10), type: 'SNAPSHOT' }
        ].map((card, i) => (
          <motion.div key={card.mount} initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} transition={{ delay: i * 0.04 }} className="p-3 border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
            <div className="flex justify-between items-start mb-2">
              <div className="flex items-center gap-2 font-bold" style={{ color: 'var(--text-primary)' }}><HardDrive size={14} /> {card.mount}</div>
              <span className="text-[10px]" style={{ color: 'var(--text-muted)' }}>{card.type}</span>
            </div>
            <div className="text-xs mb-2" style={{ color: 'var(--ansi-cyan)' }}>{card.value}</div>
            <div className="h-2 w-full bg-[var(--bg-tertiary)] mb-1 overflow-hidden"><div className="h-full transition-all duration-500" style={{ width: `${card.used}%`, backgroundColor: 'var(--ansi-green)' }} /></div>
          </motion.div>
        ))}
      </div>

      <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="flex items-center justify-between mb-3">
          <div className="text-xs font-bold" style={{ color: 'var(--ansi-yellow)' }}><Trash2 size={14} className="inline mr-2" />ADVANCE CLEANER ENGINE</div>
          <div className="flex gap-2">
            <button onClick={startCleaner} disabled={busy || engine.status.running} className="px-3 py-1 text-[10px] font-bold border" style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}>START</button>
            <button onClick={() => engine.stop()} disabled={!engine.status.running} className="px-3 py-1 text-[10px] font-bold border" style={{ borderColor: 'var(--ansi-red)', color: 'var(--ansi-red)' }}>STOP</button>
          </div>
        </div>
        <div className="mb-2 text-[10px]" style={{ color: dryRun ? 'var(--ansi-cyan)' : 'var(--ansi-red)' }}>
          Mode: {dryRun ? 'SAFE DRY-RUN (default)' : 'APPLY CHANGES'}
        </div>
        <div className="mb-2 text-[10px]" style={{ color: 'var(--text-muted)' }}>
          Engine status: <span style={{ color: engine.status.running ? 'var(--ansi-yellow)' : 'var(--ansi-green)' }}>{engine.status.running ? 'RUNNING' : 'IDLE'}</span> | Mode: <span style={{ color: 'var(--text-primary)' }}>{engine.status.mode || '-'}</span>
        </div>
        <div className="flex gap-2 mb-2">
          <button
            onClick={() => setApplyChanges(false)}
            disabled={engine.status.running}
            className="px-2 py-1 text-[10px] font-bold border disabled:opacity-50"
            style={{ borderColor: !applyChanges ? 'var(--ansi-cyan)' : 'var(--border-color)', color: !applyChanges ? 'var(--ansi-cyan)' : 'var(--text-muted)' }}
          >
            SAFE (dryRun=true)
          </button>
          <button
            onClick={() => setApplyChanges(true)}
            disabled={engine.status.running}
            className="px-2 py-1 text-[10px] font-bold border disabled:opacity-50"
            style={{ borderColor: applyChanges ? 'var(--ansi-red)' : 'var(--border-color)', color: applyChanges ? 'var(--ansi-red)' : 'var(--text-muted)' }}
          >
            APPLY (dryRun=false)
          </button>
        </div>
        <div className="text-[10px] mb-3" style={{ color: applyChanges ? 'var(--ansi-red)' : 'var(--ansi-cyan)' }}>
          Request mode: {applyChanges ? 'APPLY CHANGES' : 'SAFE DRY-RUN'}
        </div>
        <div className="flex gap-2 mb-3">
          <select value={selectedProfile} onChange={(e) => setSelectedProfile(e.target.value)} className="flex-1 p-2 border font-mono text-xs" style={{ borderColor: 'var(--border-color)', color: 'var(--text-primary)', backgroundColor: 'var(--bg-primary)' }}>
            {(profiles.length > 0 ? profiles : [{ id: 'quick-clean', label: 'QUICK CLEAN' }, { id: 'standard-clean', label: 'STANDARD CLEAN' }, { id: 'deep-clean', label: 'DEEP CLEAN' }]).map((p) => <option key={p.id} value={p.id}>{p.label}</option>)}
          </select>
        </div>
        <div className="h-2 w-full bg-[var(--bg-tertiary)] mb-2 overflow-hidden"><div className="h-full" style={{ width: `${progressPct}%`, backgroundColor: 'var(--ansi-yellow)' }} /></div>
        <div className="text-xs font-mono max-h-32 overflow-y-auto">
          {engine.logs.slice(-20).map((l, i) => <div key={`${l.time}-${i}`} style={{ color: l.level === 'error' ? 'var(--ansi-red)' : 'var(--text-primary)' }}>[{l.time}] {l.level}: {l.message}</div>)}
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4">
        <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="flex items-center justify-between mb-3 text-xs font-bold" style={{ color: 'var(--ansi-yellow)' }}>
            <span>REGISTRY SCAN</span>
            <button onClick={() => runSpecialScan('registry')} disabled={busy || engine.status.running} className="px-2 py-1 border text-[10px]" style={{ borderColor: 'var(--ansi-yellow)', color: 'var(--ansi-yellow)' }}>RUN</button>
          </div>
          <div className="space-y-2 max-h-44 overflow-auto font-mono text-xs">
            {results.registry.slice(-10).map((r) => (
              <div key={`${r.key}-${r.reason}`} className="p-2 border" style={{ borderColor: 'var(--border-color)' }}>
                <div style={{ color: 'var(--text-primary)' }}>{r.key}</div>
                <div style={{ color: 'var(--text-muted)' }}>{r.reason}</div>
              </div>
            ))}
            {results.registry.length === 0 && <div style={{ color: 'var(--text-muted)' }}>No registry issues yet</div>}
          </div>
        </div>
      </div>

      <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="flex items-center gap-2 mb-3 text-xs font-bold" style={{ color: 'var(--ansi-green)' }}><Database size={14} /> BACKUP MANAGER</div>
        <div className="flex gap-2 mb-3">
          <input value={backupNote} onChange={(e) => setBackupNote(e.target.value)} placeholder="backup note" className="flex-1 px-2 py-1 text-xs border bg-transparent outline-none font-mono" style={{ borderColor: 'var(--border-color)', color: 'var(--text-primary)' }} />
          <button onClick={createBackup} disabled={busy} className="px-3 py-1 text-[10px] font-bold border" style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}>CREATE</button>
        </div>
        <div className="space-y-2 max-h-44 overflow-auto">
          {results.backups.slice().reverse().map((b) => (
            <div key={b.id} className="p-2 border flex items-center justify-between text-xs font-mono" style={{ borderColor: 'var(--border-color)' }}>
              <div>
                <div style={{ color: 'var(--text-primary)' }}>{b.id}</div>
                <div style={{ color: 'var(--text-muted)' }}>{new Date(b.time).toLocaleString()} {b.meta?.note ? `- ${b.meta.note}` : ''}</div>
              </div>
              <button onClick={() => restoreBackup(b.id)} disabled={busy} className="px-2 py-1 border text-[10px]" style={{ borderColor: 'var(--ansi-blue)', color: 'var(--ansi-blue)' }}>RESTORE</button>
            </div>
          ))}
          {results.backups.length === 0 && <div className="text-xs" style={{ color: 'var(--text-muted)' }}>No backups available</div>}
        </div>
      </div>

      <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="flex items-center gap-2 mb-3 text-xs font-bold" style={{ color: 'var(--ansi-blue)' }}><Folder size={14} /> RECENT CLEAN TARGETS</div>
        <div className="space-y-2">
          {results.files.slice(-8).map((f) => (
            <div key={f.path} className="text-xs">
              <div className="flex justify-between mb-1">
                <span className="truncate mr-2" style={{ color: 'var(--text-primary)' }}>{f.path}</span>
                <span style={{ color: 'var(--text-muted)' }}>{Math.round((f.sizeKB || 0) / 1024)} MB</span>
              </div>
              <div className="h-1.5 w-full bg-[var(--bg-tertiary)]"><div className="h-full bg-[var(--ansi-blue)]" style={{ width: `${Math.min(100, Math.max(8, ((f.sizeKB || 1) / 2048) * 100))}%` }} /></div>
            </div>
          ))}
          {results.files.length === 0 && <div className="text-xs" style={{ color: 'var(--text-muted)' }}>No cleaned files yet</div>}
        </div>
      </div>
    </div>
  );
}
