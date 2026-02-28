import React, { useMemo, useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Plus, Trash2, Play, Pause } from 'lucide-react';
import { apiFetch } from '../../lib/api';

type CronJob = {
  id: string;
  cron: string;
  desc: string;
  user: string;
  status: 'active' | 'paused' | 'failed';
  lastRun: string | null;
  nextRun: string;
};

const statusColor: Record<string, string> = {
  active: 'var(--ansi-green)',
  paused: 'var(--ansi-yellow)',
  failed: 'var(--ansi-red)'
};

export function SchedulerPage() {
  const [jobs, setJobs] = useState<CronJob[]>([]);
  const [showAdd, setShowAdd] = useState(false);
  const [newSchedule, setNewSchedule] = useState('0 * * * *');
  const [newCommand, setNewCommand] = useState('');
  const [message, setMessage] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [lastUpdated, setLastUpdated] = useState('');
  const [busyKey, setBusyKey] = useState<string | null>(null);

  const load = React.useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const r = await apiFetch('/api/scheduler/tasks');
      const j = await r.json();
      if (j?.ok) setJobs((j.tasks || []) as CronJob[]);
      setLastUpdated(new Date().toLocaleTimeString());
      setError('');
    } catch (err: any) {
      setError(String(err?.message || err));
    } finally {
      if (!silent) setLoading(false);
    }
  }, []);

  React.useEffect(() => {
    let mounted = true;
    const refresh = async () => { if (!mounted) return; await load(true); };
    load(false);
    const iv = setInterval(refresh, 3000);
    return () => { mounted = false; clearInterval(iv); };
  }, [load]);

  const addJob = async () => {
    if (!newCommand.trim()) return;
    setBusyKey('add');
    try {
      const r = await apiFetch('/api/scheduler/tasks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ schedule: newSchedule, command: newCommand, user: 'root' })
      });
      const j = await r.json();
      if (!r.ok || !j?.ok) {
        setMessage(`Add failed: ${j?.error || 'unknown error'}`);
        setError(`Add failed: ${j?.error || 'unknown error'}`);
      }
      else {
        setMessage(`Task created: ${j.task.id}`);
        setNewCommand('');
        setShowAdd(false);
        await load(true);
      }
    } catch (err: any) {
      setMessage(`Add failed: ${String(err?.message || err)}`);
      setError(String(err?.message || err));
    } finally {
      setBusyKey(null);
    }
  };

  const toggleJob = async (job: CronJob) => {
    const next = job.status === 'active' ? 'paused' : 'active';
    setBusyKey(`toggle-${job.id}`);
    try {
      const r = await apiFetch(`/api/scheduler/tasks/${job.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: next })
      });
      const j = await r.json();
      if (!r.ok || !j?.ok) {
        setMessage(`Toggle failed: ${j?.error || 'unknown error'}`);
        setError(`Toggle failed: ${j?.error || 'unknown error'}`);
      } else await load(true);
    } catch (err: any) {
      setMessage(`Toggle failed: ${String(err?.message || err)}`);
      setError(String(err?.message || err));
    } finally {
      setBusyKey(null);
    }
  };

  const removeJob = async (id: string) => {
    if (!window.confirm(`Delete task ${id}?`)) return;
    setBusyKey(`remove-${id}`);
    try {
      const r = await apiFetch(`/api/scheduler/tasks/${id}`, { method: 'DELETE' });
      const j = await r.json();
      if (!r.ok || !j?.ok) {
        setMessage(`Delete failed: ${j?.error || 'unknown error'}`);
        setError(`Delete failed: ${j?.error || 'unknown error'}`);
      } else await load(true);
    } catch (err: any) {
      setMessage(`Delete failed: ${String(err?.message || err)}`);
      setError(String(err?.message || err));
    } finally {
      setBusyKey(null);
    }
  };

  const runTask = async (id: string) => {
    setBusyKey(`run-${id}`);
    try {
      const r = await apiFetch('/api/scheduler/run', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id }) });
      const j = await r.json();
      if (!r.ok || !j?.ok) {
        setMessage(`Run failed: ${j?.error || 'unknown error'}`);
        setError(`Run failed: ${j?.error || 'unknown error'}`);
      }
      else {
        setMessage(`Task executed: ${id}`);
        await load(true);
      }
    } catch (err: any) {
      setMessage(`Run failed: ${String(err?.message || err)}`);
      setError(String(err?.message || err));
    } finally {
      setBusyKey(null);
    }
  };

  const stats = useMemo(() => ({
    total: jobs.length,
    active: jobs.filter((j) => j.status === 'active').length,
    failed: jobs.filter((j) => j.status === 'failed').length
  }), [jobs]);

  return (
    <div className="space-y-4 font-mono text-xs">
      <div className="flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>root@neooptimize</span>
        <span>:~#</span>
        <span style={{ color: 'var(--text-primary)', marginLeft: 4 }}>scheduler list --watch</span>
        <span style={{ color: 'var(--ansi-cyan)' }}>{lastUpdated ? `updated ${lastUpdated}` : ''}</span>
        <span className="cursor-blink ml-1" style={{ color: 'var(--ansi-green)' }}>█</span>
      </div>

      {(loading || error || message) && (
        <div className="px-3 py-2 text-xs border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: error ? 'var(--ansi-red)' : 'var(--text-primary)' }}>
          {loading ? 'Loading scheduler tasks...' : error || message}
        </div>
      )}

      <div className="grid grid-cols-3 gap-3">
        {[{ label: 'TOTAL JOBS', value: stats.total, color: 'var(--text-primary)' }, { label: 'ACTIVE', value: stats.active, color: 'var(--ansi-green)' }, { label: 'FAILED', value: stats.failed, color: stats.failed > 0 ? 'var(--ansi-red)' : 'var(--text-muted)' }].map((s) => (
          <div key={s.label} className="p-3 border text-center" style={{ backgroundColor: 'var(--bg-secondary)', borderColor: 'var(--border-color)' }}>
            <div className="text-2xl font-bold mb-1" style={{ color: s.color }}>{s.value}</div>
            <div style={{ color: 'var(--text-muted)', fontSize: '10px' }}>{s.label}</div>
          </div>
        ))}
      </div>

      <motion.div style={{ backgroundColor: 'var(--bg-secondary)', border: '1px solid var(--border-color)' }}>
        <div className="px-3 py-1.5 text-[10px] font-bold border-b flex items-center justify-between" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: 'var(--text-muted)' }}>
          <span><span style={{ color: 'var(--ansi-green)' }}>$</span> scheduler tasks --verbose</span>
          <button onClick={() => setShowAdd((s) => !s)} disabled={loading || busyKey != null} className="flex items-center gap-1 px-2 py-0.5 border disabled:opacity-50" style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}><Plus size={10} /> ADD JOB</button>
        </div>

        <AnimatePresence>
          {showAdd && (
            <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: 'auto', opacity: 1 }} exit={{ height: 0, opacity: 0 }} transition={{ duration: 0.2 }} style={{ overflow: 'hidden', borderBottom: '1px solid var(--border-color)' }}>
              <div className="p-3 space-y-2" style={{ backgroundColor: 'var(--bg-tertiary)' }}>
                <div className="flex gap-2 items-center">
                  <span style={{ color: 'var(--text-muted)', width: 72, flexShrink: 0 }}>SCHEDULE</span>
                  <input value={newSchedule} onChange={(e) => setNewSchedule(e.target.value)} className="flex-1 px-2 py-1 border outline-none font-mono text-xs" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-primary)', color: 'var(--text-primary)' }} />
                </div>
                <div className="flex gap-2 items-center">
                  <span style={{ color: 'var(--text-muted)', width: 72, flexShrink: 0 }}>COMMAND</span>
                  <input value={newCommand} onChange={(e) => setNewCommand(e.target.value)} className="flex-1 px-2 py-1 border outline-none font-mono text-xs" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-primary)', color: 'var(--text-primary)' }} />
                </div>
                <div className="flex gap-2 justify-end">
                  <button onClick={() => setShowAdd(false)} disabled={busyKey === 'add'} className="px-3 py-1 border text-[10px] disabled:opacity-50" style={{ borderColor: 'var(--border-color)', color: 'var(--text-muted)' }}>CANCEL</button>
                  <button onClick={addJob} disabled={busyKey === 'add'} className="px-3 py-1 border text-[10px] font-bold disabled:opacity-50" style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}>{busyKey === 'add' ? 'ADDING...' : '+ ADD'}</button>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        <div className="grid gap-2 px-3 py-1.5 text-[10px] font-bold border-b" style={{ gridTemplateColumns: '140px 1fr 70px 110px 80px 120px', borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: 'var(--text-muted)' }}>
          <div>SCHEDULE</div>
          <div>COMMAND</div>
          <div>USER</div>
          <div>LAST RUN</div>
          <div>STATUS</div>
          <div className="text-right">ACTIONS</div>
        </div>

        <div className="max-h-[52vh] overflow-y-auto">
          {jobs.map((job, i) => (
            <motion.div key={job.id} initial={{ opacity: 0, x: -8 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: i * 0.02 }} className="grid gap-2 px-3 py-2 items-center border-b" style={{ gridTemplateColumns: '140px 1fr 70px 110px 80px 120px', borderColor: 'var(--border-color)', backgroundColor: i % 2 === 0 ? 'var(--bg-primary)' : 'transparent' }}>
              <div style={{ color: 'var(--ansi-cyan)' }}>{job.cron}</div>
              <div className="truncate" style={{ color: 'var(--text-primary)' }}>{job.desc}</div>
              <div style={{ color: 'var(--text-muted)' }}>{job.user || 'root'}</div>
              <div style={{ color: 'var(--text-muted)', fontSize: '10px' }}>{job.lastRun ? new Date(job.lastRun).toLocaleString() : 'never'}</div>
              <div><span className="px-1 py-0.5 text-[9px] font-bold" style={{ backgroundColor: statusColor[job.status] + '22', color: statusColor[job.status], border: `1px solid ${statusColor[job.status]}44` }}>{job.status.toUpperCase()}</span></div>
              <div className="flex justify-end gap-1">
                <button onClick={() => runTask(job.id)} disabled={busyKey != null} className="p-1 border disabled:opacity-50" style={{ borderColor: 'var(--ansi-blue)', color: 'var(--ansi-blue)' }} title="Run now"><Play size={9} /></button>
                <button onClick={() => toggleJob(job)} disabled={busyKey != null} className="p-1 border disabled:opacity-50" style={{ borderColor: 'var(--ansi-yellow)', color: 'var(--ansi-yellow)' }} title={job.status === 'active' ? 'Pause' : 'Resume'}>{job.status === 'active' ? <Pause size={9} /> : <Play size={9} />}</button>
                <button onClick={() => removeJob(job.id)} disabled={busyKey != null} className="p-1 border disabled:opacity-50" style={{ borderColor: 'var(--ansi-red)', color: 'var(--ansi-red)' }} title="Delete"><Trash2 size={9} /></button>
              </div>
            </motion.div>
          ))}
          {jobs.length === 0 && <div className="px-3 py-2 text-xs" style={{ color: 'var(--text-muted)' }}>No scheduler task found</div>}
        </div>
      </motion.div>
    </div>
  );
}
