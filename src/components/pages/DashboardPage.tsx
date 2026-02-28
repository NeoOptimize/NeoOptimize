import React, { useEffect, useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import { Activity, FileText, Play, Shield, Square, Terminal, Zap } from 'lucide-react';
import { MetricsPanel } from '../MetricsPanel';
import { useSystemStats } from '../../hooks/SystemStatsContext';
import { useEngineApi } from '../../hooks/useEngineApi';
import { apiFetch } from '../../lib/api';

type Overview = {
  hostname: string;
  platform: string;
  kernel: string;
  uptimeSec: number;
  cpuPercent: number;
  memPercent: number;
  loadAvg: number[];
};

type SecurityStatus = {
  antivirus: string;
  firewall: string;
  issues: string[];
  scan?: { running: boolean; progress: number; threats?: number; suspicious?: number };
};

type Connection = {
  local: string;
  remote: string;
  state: string;
  pid: number;
  process: string;
};

type ActionLevel = 'ok' | 'warn' | 'error' | 'info';

const sectionVariants = {
  hidden: { opacity: 0, y: 14 },
  visible: (i: number) => ({
    opacity: 1,
    y: 0,
    transition: { delay: i * 0.06, duration: 0.22, ease: 'easeOut' }
  })
};

const ACTIONS: Array<{ id: string; label: string; level: ActionLevel }> = [
  { id: 'quick-safe-clean', label: 'Quick Safe Clean', level: 'ok' },
  { id: 'registry-safe-scan', label: 'Registry Safe Scan', level: 'warn' },
  { id: 'backup-now', label: 'Backup Snapshot', level: 'info' },
  { id: 'report-now', label: 'Generate Report', level: 'info' }
];

function levelColor(level: ActionLevel) {
  if (level === 'error') return 'var(--ansi-red)';
  if (level === 'warn') return 'var(--ansi-yellow)';
  if (level === 'ok') return 'var(--ansi-green)';
  return 'var(--ansi-blue)';
}

function statusColor(v: string) {
  const s = String(v || '').toLowerCase();
  if (s === 'enabled' || s === 'active' || s.startsWith('active')) return 'var(--ansi-green)';
  return 'var(--ansi-red)';
}

export function DashboardPage() {
  const { metrics, logs, uptime, tasks } = useSystemStats();
  const engine = useEngineApi('advance');

  const [overview, setOverview] = useState<Overview | null>(null);
  const [security, setSecurity] = useState<SecurityStatus>({
    antivirus: 'unknown',
    firewall: 'unknown',
    issues: []
  });
  const [connections, setConnections] = useState<Connection[]>([]);
  const [message, setMessage] = useState('');
  const [actionBusy, setActionBusy] = useState<string | null>(null);
  const [mode, setMode] = useState<'full' | 'dump' | 'registry'>('full');
  const [applyChanges, setApplyChanges] = useState(false);
  const [reportPath, setReportPath] = useState<string | null>(null);
  const [generatingReport, setGeneratingReport] = useState(false);
  const [loading, setLoading] = useState(true);
  const [refreshError, setRefreshError] = useState('');
  const [lastUpdated, setLastUpdated] = useState('');

  const progressPct = Math.round((Number(engine.status.progress || 0) / Math.max(1, Number(engine.status.total || 100))) * 100);

  const refresh = React.useCallback(async () => {
    try {
      const [oRes, sRes, cRes] = await Promise.all([
        apiFetch('/api/system/overview'),
        apiFetch('/api/security/status'),
        apiFetch('/api/network/connections')
      ]);
      const [o, s, c] = await Promise.all([oRes.json(), sRes.json(), cRes.json()]);
      if (o?.ok && o.system) setOverview(o.system as Overview);
      if (s?.ok && s.status) setSecurity(s.status as SecurityStatus);
      if (c?.ok && Array.isArray(c.connections)) setConnections(c.connections as Connection[]);
      setLastUpdated(new Date().toLocaleTimeString());
      setRefreshError('');
    } catch (err: any) {
      setRefreshError(String(err?.message || err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
    const iv = setInterval(refresh, 2500);
    return () => clearInterval(iv);
  }, [refresh]);

  const runCleaner = async () => {
    try {
      const dryRunMode = !applyChanges;
      if (!dryRunMode && !window.confirm(`APPLY mode will modify system state in ${mode} mode. Continue?`)) return;
      await engine.start({ mode, total: mode === 'full' ? 140 : 90, dryRun: dryRunMode });
      setMessage(`Cleaner started in ${mode} mode (${dryRunMode ? 'safe dry-run' : 'APPLY changes'})`);
      setRefreshError('');
    } catch (err: any) {
      setMessage(`Cleaner start failed: ${String(err?.message || err)}`);
      setRefreshError(String(err?.message || err));
    }
  };

  const executeAction = async (actionId: string) => {
    setActionBusy(actionId);
    try {
      if (actionId === 'quick-safe-clean') {
        const r = await apiFetch('/api/clean/advance/start', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ mode: 'dump', dryRun: true, total: 90 })
        });
        const j = await r.json();
        if (!r.ok || j?.ok === false) {
          setMessage(`Action failed: ${j?.error || 'unknown error'}`);
          return;
        }
        setMessage('Quick safe clean started');
        return;
      }
      if (actionId === 'registry-safe-scan') {
        const r = await apiFetch('/api/clean/advance/registry', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ dryRun: true, total: 90 })
        });
        const j = await r.json();
        if (!r.ok || j?.ok === false) {
          setMessage(`Action failed: ${j?.error || 'unknown error'}`);
          return;
        }
        setMessage('Registry safe scan started');
        return;
      }
      if (actionId === 'backup-now') {
        const r = await apiFetch('/api/clean/advance/backup', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ note: 'dashboard quick action' })
        });
        const j = await r.json();
        if (!r.ok || !j?.ok) {
          setMessage(`Action failed: ${j?.error || 'unknown error'}`);
          return;
        }
        setMessage(`Backup created: ${j?.entry?.id || 'ok'}`);
        return;
      }
      if (actionId === 'report-now') {
        await generateReport();
        setMessage('Report generated and opened in browser');
        return;
      }
      setMessage(`Unknown action: ${actionId}`);
    } catch (err: any) {
      setMessage(`Action failed: ${String(err?.message || err)}`);
    } finally {
      setActionBusy(null);
    }
  };

  const generateReport = async () => {
    setGeneratingReport(true);
    try {
      const r = await apiFetch('/api/report/generate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ engine: 'advance' })
      });
      const j = await r.json();
      if (!r.ok || !j?.ok) setMessage(`Report failed: ${j?.error || 'unknown error'}`);
      else setReportPath(j.path || null);
    } catch (err: any) {
      setMessage(`Report failed: ${String(err?.message || err)}`);
    } finally {
      setGeneratingReport(false);
    }
  };

  const activity = useMemo(() => logs.slice(-14).reverse(), [logs]);

  return (
    <div className="space-y-4 font-mono">
      <motion.div
        custom={0}
        variants={sectionVariants}
        initial="hidden"
        animate="visible"
        className="flex items-center gap-2 text-xs"
        style={{ color: 'var(--text-muted)' }}
      >
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>root@neooptimize</span>
        <span>:~#</span>
        <span style={{ color: 'var(--text-primary)' }}>dashboard --live --realtime</span>
        <span style={{ color: 'var(--ansi-cyan)' }}>{lastUpdated ? `updated ${lastUpdated}` : ''}</span>
      </motion.div>

      {(loading || refreshError || message) && (
        <div
          className="px-3 py-2 text-xs border"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-tertiary)',
            color: refreshError ? 'var(--ansi-red)' : 'var(--text-primary)'
          }}
        >
          {loading ? 'Loading dashboard data...' : refreshError || message}
        </div>
      )}

      <motion.div custom={1} variants={sectionVariants} initial="hidden" animate="visible">
        <MetricsPanel />
      </motion.div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <motion.div
          custom={2}
          variants={sectionVariants}
          initial="hidden"
          animate="visible"
          className="border"
          style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}
        >
          <div
            className="px-3 py-2 text-[10px] border-b flex items-center justify-between"
            style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: 'var(--text-muted)' }}
          >
            <span>$ cleaner_control --engine advance</span>
            <span style={{ color: engine.status.running ? 'var(--ansi-yellow)' : 'var(--ansi-green)' }}>
              {engine.status.running ? 'RUNNING' : 'IDLE'}
            </span>
          </div>
          <div className="p-3 space-y-3 text-xs">
            <div className="flex gap-2">
              {(['full', 'dump', 'registry'] as const).map((m) => (
                <button
                  key={m}
                  onClick={() => setMode(m)}
                  className="px-2 py-1 border text-[10px] font-bold"
                  style={{
                    borderColor: mode === m ? 'var(--ansi-green)' : 'var(--border-color)',
                    color: mode === m ? 'var(--ansi-green)' : 'var(--text-muted)'
                  }}
                >
                  {m.toUpperCase()}
                </button>
              ))}
            </div>
            <div className="flex gap-2">
              <button
                onClick={() => setApplyChanges(false)}
                disabled={engine.status.running}
                className="px-2 py-1 text-[10px] font-bold border disabled:opacity-50"
                style={{ borderColor: !applyChanges ? 'var(--ansi-cyan)' : 'var(--border-color)', color: !applyChanges ? 'var(--ansi-cyan)' : 'var(--text-muted)' }}
              >
                SAFE
              </button>
              <button
                onClick={() => setApplyChanges(true)}
                disabled={engine.status.running}
                className="px-2 py-1 text-[10px] font-bold border disabled:opacity-50"
                style={{ borderColor: applyChanges ? 'var(--ansi-red)' : 'var(--border-color)', color: applyChanges ? 'var(--ansi-red)' : 'var(--text-muted)' }}
              >
                APPLY
              </button>
            </div>
            <div className="flex gap-2">
              <button
                onClick={runCleaner}
                disabled={engine.status.running}
                className="px-3 py-1 text-[10px] font-bold border flex items-center gap-1 disabled:opacity-50"
                style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}
              >
                <Play size={10} />
                START
              </button>
              <button
                onClick={() => engine.stop()}
                disabled={!engine.status.running}
                className="px-3 py-1 text-[10px] font-bold border flex items-center gap-1 disabled:opacity-50"
                style={{ borderColor: 'var(--ansi-red)', color: 'var(--ansi-red)' }}
              >
                <Square size={10} />
                STOP
              </button>
              <button
                onClick={generateReport}
                disabled={generatingReport}
                className="px-3 py-1 text-[10px] font-bold border flex items-center gap-1 disabled:opacity-50"
                style={{ borderColor: 'var(--ansi-blue)', color: 'var(--ansi-blue)' }}
              >
                <FileText size={10} />
                {generatingReport ? 'REPORT...' : 'REPORT'}
              </button>
            </div>
            <div className="h-2 w-full bg-[var(--bg-tertiary)] overflow-hidden">
              <div className="h-full transition-all duration-300" style={{ width: `${progressPct}%`, backgroundColor: 'var(--ansi-yellow)' }} />
            </div>
            <div className="flex items-center justify-between text-[10px]">
              <span style={{ color: 'var(--text-muted)' }}>
                progress: {engine.status.progress}/{engine.status.total}
              </span>
              <span style={{ color: 'var(--ansi-cyan)' }}>{progressPct}%</span>
            </div>
            <div className="text-[10px]" style={{ color: engine.status?.dryRun !== false ? 'var(--ansi-cyan)' : 'var(--ansi-red)' }}>
              {engine.status?.dryRun !== false ? 'SAFE DRY-RUN (default)' : 'APPLY CHANGES'}
            </div>
            <div className="text-[10px]" style={{ color: applyChanges ? 'var(--ansi-red)' : 'var(--ansi-cyan)' }}>
              Request mode: {applyChanges ? 'APPLY CHANGES (dryRun=false)' : 'SAFE DRY-RUN (dryRun=true)'}
            </div>
            {reportPath && (
              <div className="p-2 border text-[10px] truncate" style={{ borderColor: 'var(--border-color)', color: 'var(--text-primary)' }}>
                {reportPath}
              </div>
            )}
            <div className="border p-2 max-h-36 overflow-y-auto text-[10px] space-y-1" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--terminal-output-bg)' }}>
              {engine.logs.slice(-15).map((l, i) => (
                <div key={`${l.time}-${i}`} style={{ color: l.level === 'error' ? 'var(--ansi-red)' : 'var(--text-primary)' }}>
                  [{l.time}] {String(l.level || 'info').toUpperCase()} {l.message}
                </div>
              ))}
              {engine.logs.length === 0 && <div style={{ color: 'var(--text-muted)' }}>No engine log yet</div>}
            </div>
          </div>
        </motion.div>

        <motion.div
          custom={3}
          variants={sectionVariants}
          initial="hidden"
          animate="visible"
          className="border"
          style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}
        >
          <div
            className="px-3 py-2 text-[10px] border-b flex items-center justify-between"
            style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: 'var(--text-muted)' }}
          >
            <span>$ health_check --all</span>
            <span style={{ color: 'var(--ansi-green)' }}>{overview?.hostname || '-'}</span>
          </div>
          <div className="p-3 space-y-2 text-xs">
            <div className="grid grid-cols-2 gap-2">
              <div className="p-2 border" style={{ borderColor: 'var(--border-color)' }}>
                <div style={{ color: 'var(--text-muted)' }}>CPU</div>
                <div style={{ color: 'var(--text-primary)' }}>{metrics.cpu.toFixed(1)}%</div>
              </div>
              <div className="p-2 border" style={{ borderColor: 'var(--border-color)' }}>
                <div style={{ color: 'var(--text-muted)' }}>MEM</div>
                <div style={{ color: 'var(--text-primary)' }}>{metrics.mem.toFixed(1)}%</div>
              </div>
              <div className="p-2 border" style={{ borderColor: 'var(--border-color)' }}>
                <div style={{ color: 'var(--text-muted)' }}>NET LATENCY</div>
                <div style={{ color: 'var(--text-primary)' }}>{metrics.net.toFixed(0)} ms</div>
              </div>
              <div className="p-2 border" style={{ borderColor: 'var(--border-color)' }}>
                <div style={{ color: 'var(--text-muted)' }}>TASKS</div>
                <div style={{ color: 'var(--text-primary)' }}>{tasks}</div>
              </div>
            </div>
            <div className="space-y-1 text-[11px] pt-1 border-t" style={{ borderColor: 'var(--border-color)' }}>
              <div className="flex justify-between">
                <span style={{ color: 'var(--text-muted)' }}>Platform</span>
                <span style={{ color: 'var(--text-primary)' }}>{overview?.platform || '-'}</span>
              </div>
              <div className="flex justify-between">
                <span style={{ color: 'var(--text-muted)' }}>Kernel</span>
                <span style={{ color: 'var(--text-primary)' }}>{overview?.kernel || '-'}</span>
              </div>
              <div className="flex justify-between">
                <span style={{ color: 'var(--text-muted)' }}>Uptime</span>
                <span style={{ color: 'var(--text-primary)' }}>{uptime}</span>
              </div>
              <div className="flex justify-between">
                <span style={{ color: 'var(--text-muted)' }}>Firewall</span>
                <span style={{ color: statusColor(security.firewall) }}>{security.firewall}</span>
              </div>
              <div className="flex justify-between">
                <span style={{ color: 'var(--text-muted)' }}>Antivirus</span>
                <span style={{ color: statusColor(security.antivirus) }}>{security.antivirus}</span>
              </div>
              <div className="flex justify-between">
                <span style={{ color: 'var(--text-muted)' }}>Security Scan</span>
                <span style={{ color: security.scan?.running ? 'var(--ansi-yellow)' : 'var(--ansi-green)' }}>
                  {security.scan?.running ? `${security.scan.progress}%` : 'idle'}
                </span>
              </div>
            </div>
            <div className="text-[10px]" style={{ color: security.issues.length ? 'var(--ansi-yellow)' : 'var(--text-muted)' }}>
              {security.issues.length ? security.issues.join(' | ') : 'No active security issue'}
            </div>
          </div>
        </motion.div>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <motion.div
          custom={4}
          variants={sectionVariants}
          initial="hidden"
          animate="visible"
          className="border"
          style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}
        >
          <div
            className="px-3 py-2 text-[10px] border-b"
            style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: 'var(--text-muted)' }}
          >
            $ pending_actions --execute
          </div>
          <div className="p-3 space-y-2">
            {ACTIONS.map((a) => (
              <div key={a.id} className="flex items-center justify-between p-2 border text-xs" style={{ borderColor: 'var(--border-color)' }}>
                <div className="flex items-center gap-2">
                  <span style={{ color: levelColor(a.level) }}>●</span>
                  <span style={{ color: 'var(--text-primary)' }}>{a.label}</span>
                </div>
                <button
                  onClick={() => executeAction(a.id)}
                  disabled={actionBusy === a.id}
                  className="px-2 py-0.5 border text-[10px] font-bold disabled:opacity-50"
                  style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}
                >
                  {actionBusy === a.id ? 'RUNNING' : 'EXEC'}
                </button>
              </div>
            ))}
          </div>
        </motion.div>

        <motion.div
          custom={5}
          variants={sectionVariants}
          initial="hidden"
          animate="visible"
          className="border"
          style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}
        >
          <div
            className="px-3 py-2 text-[10px] border-b flex items-center justify-between"
            style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: 'var(--text-muted)' }}
          >
            <span>$ activity_feed --tail 14</span>
            <span style={{ color: 'var(--ansi-green)' }}>LIVE</span>
          </div>
          <div className="p-3 max-h-56 overflow-y-auto space-y-1 text-xs">
            {activity.map((log) => (
              <div key={log.id} className="flex items-start gap-2">
                <span style={{ color: 'var(--text-muted)' }}>{log.time}</span>
                <span style={{ color: log.level === 'error' ? 'var(--ansi-red)' : log.level === 'warn' ? 'var(--ansi-yellow)' : log.level === 'ok' ? 'var(--ansi-green)' : 'var(--ansi-blue)' }}>
                  {String(log.level || 'info').toUpperCase()}
                </span>
                <span style={{ color: 'var(--text-primary)' }}>{log.message}</span>
              </div>
            ))}
            {activity.length === 0 && <div style={{ color: 'var(--text-muted)' }}>No activity yet</div>}
          </div>
        </motion.div>
      </div>

      <motion.div
        custom={6}
        variants={sectionVariants}
        initial="hidden"
        animate="visible"
        className="border"
        style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}
      >
        <div
          className="px-3 py-2 text-[10px] border-b flex items-center justify-between"
          style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: 'var(--text-muted)' }}
        >
          <span>$ network_connections --top 8</span>
          <span>{connections.length} total</span>
        </div>
        <div className="grid grid-cols-12 gap-2 px-3 py-2 text-[10px] font-bold border-b" style={{ borderColor: 'var(--border-color)', color: 'var(--text-muted)' }}>
          <div className="col-span-3">LOCAL</div>
          <div className="col-span-3">REMOTE</div>
          <div className="col-span-2">STATE</div>
          <div className="col-span-1">PID</div>
          <div className="col-span-3">PROCESS</div>
        </div>
        <div className="max-h-64 overflow-y-auto">
          {connections.slice(0, 8).map((c, i) => (
            <div key={`${c.local}-${c.remote}-${c.pid}-${i}`} className="grid grid-cols-12 gap-2 px-3 py-1.5 text-xs" style={{ backgroundColor: i % 2 === 0 ? 'var(--bg-primary)' : 'transparent' }}>
              <div className="col-span-3 truncate" style={{ color: 'var(--text-primary)' }}>{c.local}</div>
              <div className="col-span-3 truncate" style={{ color: 'var(--text-muted)' }}>{c.remote}</div>
              <div className="col-span-2" style={{ color: c.state === 'ESTABLISHED' ? 'var(--ansi-green)' : 'var(--ansi-yellow)' }}>{c.state}</div>
              <div className="col-span-1" style={{ color: 'var(--ansi-yellow)' }}>{c.pid}</div>
              <div className="col-span-3 truncate" style={{ color: 'var(--text-primary)' }}>{c.process}</div>
            </div>
          ))}
          {connections.length === 0 && <div className="px-3 py-2 text-xs" style={{ color: 'var(--text-muted)' }}>No connection data</div>}
        </div>
      </motion.div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="border p-3 text-xs" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="flex items-center gap-2 mb-1" style={{ color: 'var(--ansi-cyan)' }}><Activity size={12} /> CPU/MEM</div>
          <div style={{ color: 'var(--text-primary)' }}>CPU {metrics.cpu.toFixed(1)}%</div>
          <div style={{ color: 'var(--text-primary)' }}>MEM {metrics.mem.toFixed(1)}%</div>
        </div>
        <div className="border p-3 text-xs" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="flex items-center gap-2 mb-1" style={{ color: 'var(--ansi-green)' }}><Shield size={12} /> Security</div>
          <div style={{ color: 'var(--text-primary)' }}>Threats: {security.scan?.threats ?? 0}</div>
          <div style={{ color: 'var(--text-primary)' }}>Suspicious: {security.scan?.suspicious ?? 0}</div>
        </div>
        <div className="border p-3 text-xs" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="flex items-center gap-2 mb-1" style={{ color: 'var(--ansi-yellow)' }}><Terminal size={12} /> Runtime</div>
          <div style={{ color: 'var(--text-primary)' }}>Uptime: {uptime}</div>
          <div style={{ color: 'var(--text-primary)' }}>Load: {(overview?.loadAvg || []).map((n) => n.toFixed(2)).join(' ') || '-'}</div>
        </div>
      </div>

      <div className="text-[10px] flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <Zap size={10} />
        <span>Dashboard data sources: system, network, security, process, cleaner, actions, report.</span>
      </div>
    </div>
  );
}
