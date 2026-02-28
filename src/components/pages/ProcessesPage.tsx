import React, { useEffect, useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import { Pause, Play, XCircle, Info } from 'lucide-react';
import { apiFetch } from '../../lib/api';

type Proc = {
  pid: number;
  user?: string;
  cpu?: number | null;
  mem?: string;
  memKB?: number | null;
  status?: string;
  command?: string;
  name?: string;
};

function memLabel(p: Proc) {
  if (typeof p.memKB === 'number' && Number.isFinite(p.memKB)) {
    if (p.memKB >= 1024 * 1024) return `${(p.memKB / (1024 * 1024)).toFixed(2)} GB`;
    return `${(p.memKB / 1024).toFixed(1)} MB`;
  }
  return p.mem || '-';
}

export function ProcessesPage() {
  const [procs, setProcs] = useState<Proc[]>([]);
  const [search, setSearch] = useState('');
  const [pidInput, setPidInput] = useState('');
  const [busyPid, setBusyPid] = useState<number | null>(null);
  const [message, setMessage] = useState('');
  const [selected, setSelected] = useState<Proc | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [lastUpdated, setLastUpdated] = useState('');

  const load = React.useCallback(async () => {
    try {
      const r = await apiFetch('/api/processes');
      const j = await r.json();
      if (j?.ok && Array.isArray(j.processes)) setProcs(j.processes);
      setLastUpdated(new Date().toLocaleTimeString());
      setError('');
    } catch (err: any) {
      setError(String(err?.message || err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    let mounted = true;
    const refresh = async () => {
      if (!mounted) return;
      await load();
    };
    refresh();
    const iv = setInterval(refresh, 3000);
    return () => { mounted = false; clearInterval(iv); };
  }, [load]);

  const filtered = useMemo(() => {
    const q = search.toLowerCase();
    return procs.filter((p) => `${p.pid} ${p.user || ''} ${p.command || p.name || ''}`.toLowerCase().includes(q));
  }, [procs, search]);

  const totals = useMemo(() => ({
    total: procs.length,
    running: procs.filter((p) => (p.status || 'running').toLowerCase().includes('running')).length,
    sleeping: procs.filter((p) => (p.status || '').toLowerCase().includes('sleep')).length
  }), [procs]);

  const runAction = async (pid: number, action: 'kill' | 'pause' | 'resume', reason: string) => {
    if (!Number.isInteger(pid) || pid <= 0) return;
    if (!window.confirm(`Confirm ${action.toUpperCase()} PID ${pid}?`)) return;
    setBusyPid(pid);
    try {
      const cRes = await apiFetch(`/api/processes/${pid}/confirm`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, reason })
      });
      const c = await cRes.json();
      if (!cRes.ok || !c?.token) {
        setMessage(`Confirmation failed: ${c?.error || 'unknown error'}`);
        return;
      }
      const aRes = await apiFetch(`/api/processes/${pid}/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ confirmToken: c.token, reason })
      });
      const a = await aRes.json();
      if (!aRes.ok || !a?.ok) {
        setMessage(`${action.toUpperCase()} failed: ${a?.error || 'unknown error'}`);
        return;
      }
      setMessage(`${action.toUpperCase()} succeeded for PID ${pid}`);
      await load();
    } catch (err: any) {
      setMessage(`${action.toUpperCase()} error: ${String(err?.message || err)}`);
    } finally {
      setBusyPid(null);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between text-xs" style={{ color: 'var(--text-muted)' }}>
        <div className="flex items-center gap-2">
          <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>$</span>
          <span>ps aux --sort=-%cpu | head -20</span>
          <span style={{ color: 'var(--ansi-cyan)' }}>{lastUpdated ? `updated ${lastUpdated}` : ''}</span>
        </div>
        <div className="flex gap-4">
          <span>Total: <span style={{ color: 'var(--text-primary)' }}>{totals.total}</span></span>
          <span>Running: <span style={{ color: 'var(--ansi-green)' }}>{totals.running}</span></span>
          <span>Sleeping: <span style={{ color: 'var(--ansi-blue)' }}>{totals.sleeping}</span></span>
        </div>
      </div>

      {(loading || error) && (
        <div className="px-3 py-2 text-xs font-mono border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: error ? 'var(--ansi-red)' : 'var(--text-primary)' }}>
          {loading ? 'Loading process list...' : error}
        </div>
      )}

      <div className="flex items-center gap-2 px-3 py-2 text-xs border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <span style={{ color: 'var(--ansi-green)' }}>grep -i</span>
        <input value={search} onChange={(e) => setSearch(e.target.value)} className="bg-transparent outline-none flex-1 font-mono" style={{ color: 'var(--text-primary)' }} placeholder="[search process...]" />
      </div>

      {message && (
        <div className="px-3 py-2 text-xs font-mono border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: 'var(--text-primary)' }}>
          {message}
        </div>
      )}

      <div className="border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="grid grid-cols-12 gap-2 px-3 py-2 text-[10px] font-bold border-b" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: 'var(--text-muted)' }}>
          <div className="col-span-1">PID</div>
          <div className="col-span-2">USER</div>
          <div className="col-span-1">CPU%</div>
          <div className="col-span-2">MEM</div>
          <div className="col-span-2">STATUS</div>
          <div className="col-span-2">COMMAND</div>
          <div className="col-span-2 text-right">ACTIONS</div>
        </div>
        <div className="max-h-[60vh] overflow-y-auto">
          {filtered.map((p, i) => {
            const status = (p.status || 'running').toLowerCase();
            return (
              <motion.div
                key={`${p.pid}-${i}`}
                initial={{ opacity: 0, x: -8 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: i * 0.01 }}
                className="grid grid-cols-12 gap-2 px-3 py-2 text-xs font-mono items-center hover:bg-[var(--bg-tertiary)] transition-colors"
                style={{ borderBottom: '1px solid var(--border-color)', backgroundColor: i % 2 === 0 ? 'var(--bg-primary)' : 'transparent' }}
              >
                <div className="col-span-1" style={{ color: 'var(--ansi-yellow)' }}>{p.pid}</div>
                <div className="col-span-2 truncate" style={{ color: 'var(--text-muted)' }}>{p.user || '-'}</div>
                <div className="col-span-1" style={{ color: (Number(p.cpu) || 0) > 10 ? 'var(--ansi-red)' : 'var(--text-primary)' }}>{p.cpu == null ? '-' : Number(p.cpu).toFixed(1)}</div>
                <div className="col-span-2" style={{ color: 'var(--text-primary)' }}>{memLabel(p)}</div>
                <div className="col-span-2">
                  <span
                    className="px-1.5 py-0.5 text-[9px] font-bold rounded-sm"
                    style={{
                      backgroundColor: status.includes('running') ? 'rgba(0,255,65,0.1)' : status.includes('sleep') ? 'rgba(85,153,255,0.1)' : 'rgba(255,170,0,0.12)',
                      color: status.includes('running') ? 'var(--ansi-green)' : status.includes('sleep') ? 'var(--ansi-blue)' : 'var(--ansi-yellow)'
                    }}
                  >
                    {status.toUpperCase()}
                  </span>
                </div>
                <div className="col-span-2 truncate" style={{ color: 'var(--text-primary)' }}>{p.command || p.name || '-'}</div>
                <div className="col-span-2 flex justify-end gap-1">
                  <button disabled={busyPid === p.pid} onClick={() => runAction(p.pid, 'kill', 'table-kill')} className="p-1 border disabled:opacity-50" style={{ borderColor: 'var(--ansi-red)', color: 'var(--ansi-red)' }} title="Kill"><XCircle size={10} /></button>
                  <button disabled={busyPid === p.pid} onClick={() => runAction(p.pid, status.includes('sleep') ? 'resume' : 'pause', 'table-pause-resume')} className="p-1 border disabled:opacity-50" style={{ borderColor: 'var(--ansi-yellow)', color: 'var(--ansi-yellow)' }} title={status.includes('sleep') ? 'Resume' : 'Pause'}>{status.includes('sleep') ? <Play size={10} /> : <Pause size={10} />}</button>
                  <button onClick={() => setSelected(p)} className="p-1 border" style={{ borderColor: 'var(--ansi-blue)', color: 'var(--ansi-blue)' }} title="Info"><Info size={10} /></button>
                </div>
              </motion.div>
            );
          })}
        </div>
      </div>

      <div className="flex items-center gap-2 px-3 py-2 text-xs border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <span style={{ color: 'var(--ansi-red)' }}>$ kill</span>
        <input value={pidInput} onChange={(e) => setPidInput(e.target.value)} className="bg-transparent outline-none flex-1 font-mono" style={{ color: 'var(--text-primary)' }} placeholder="[PID]" />
        <button onClick={() => runAction(Number(pidInput), 'kill', 'cli-kill')} className="px-3 py-1 text-[10px] font-bold border" style={{ borderColor: 'var(--ansi-red)', color: 'var(--ansi-red)' }}>EXEC</button>
      </div>

      {selected && (
        <div className="border p-3 text-xs font-mono" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="flex justify-between mb-2">
            <span style={{ color: 'var(--ansi-blue)' }}>PROCESS INFO</span>
            <button onClick={() => setSelected(null)} style={{ color: 'var(--text-muted)' }}>close</button>
          </div>
          <div style={{ color: 'var(--text-primary)' }}>PID: {selected.pid}</div>
          <div style={{ color: 'var(--text-primary)' }}>User: {selected.user || '-'}</div>
          <div style={{ color: 'var(--text-primary)' }}>Command: {selected.command || selected.name || '-'}</div>
          <div style={{ color: 'var(--text-primary)' }}>Memory: {memLabel(selected)}</div>
          <div style={{ color: 'var(--text-primary)' }}>Status: {(selected.status || 'running').toUpperCase()}</div>
        </div>
      )}
    </div>
  );
}
