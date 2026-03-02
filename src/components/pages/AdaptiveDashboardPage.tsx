import { useEffect, useMemo, useState } from 'react';
import { Activity, Sparkles, Stethoscope, Wrench } from 'lucide-react';
import { apiFetch } from '../../lib/api';
import { useSystemStats } from '../../hooks/SystemStatsContext';
import { asRecord, toErrorMessage } from '../../lib/safe';

type SecurityStatus = {
  antivirus: string;
  firewall: string;
  issues: string[];
  scan?: { running: boolean; progress: number };
};

type Overview = {
  hostname?: string;
  platform?: string;
  kernel?: string;
  memPercent?: number;
};

type Health = 'good' | 'attention' | 'critical';

function healthColor(health: Health): string {
  if (health === 'good') return 'var(--ansi-green)';
  if (health === 'attention') return 'var(--ansi-yellow)';
  return 'var(--ansi-red)';
}

export function AdaptiveDashboardPage() {
  const { metrics, tasks, uptime } = useSystemStats();
  const [overview, setOverview] = useState<Overview>({});
  const [security, setSecurity] = useState<SecurityStatus>({
    antivirus: 'unknown',
    firewall: 'unknown',
    issues: []
  });
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [message, setMessage] = useState('');
  const [lastUpdated, setLastUpdated] = useState('');

  useEffect(() => {
    let mounted = true;
    let timer: ReturnType<typeof setTimeout> | null = null;

    const refresh = async () => {
      try {
        const [oRes, sRes] = await Promise.all([
          apiFetch('/api/system/overview'),
          apiFetch('/api/security/status')
        ]);
        const overviewBody = asRecord(await oRes.json().catch(() => ({})));
        const securityBody = asRecord(await sRes.json().catch(() => ({})));
        if (!mounted) return;
        if (overviewBody.ok && overviewBody.system) setOverview(asRecord(overviewBody.system));
        if (securityBody.ok && securityBody.status) setSecurity(asRecord(securityBody.status) as unknown as SecurityStatus);
        setLastUpdated(new Date().toLocaleTimeString());
      } catch (err: unknown) {
        if (!mounted) return;
        setMessage(toErrorMessage(err));
      }
      if (!mounted) return;
      const hidden = typeof document !== 'undefined' && document.visibilityState === 'hidden';
      timer = setTimeout(refresh, hidden ? 18000 : 7000);
    };

    void refresh();
    return () => {
      mounted = false;
      if (timer) clearTimeout(timer);
    };
  }, []);

  const health = useMemo<Health>(() => {
    const cpuHigh = metrics.cpu >= 85;
    const memHigh = Number(overview.memPercent ?? metrics.mem) >= 85;
    const hasSecurityIssue = (security.issues || []).length > 0;
    if (cpuHigh || memHigh || hasSecurityIssue) return 'critical';
    if (metrics.cpu >= 65 || Number(overview.memPercent ?? metrics.mem) >= 65) return 'attention';
    return 'good';
  }, [metrics, overview.memPercent, security.issues]);

  const runQuickAction = async (action: 'clean' | 'optimize' | 'fix') => {
    setBusyAction(action);
    setMessage('');
    try {
      if (action === 'clean') {
        const r = await apiFetch('/api/clean/advance/start', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ mode: 'dump', dryRun: true, total: 90 })
        });
        const body = asRecord(await r.json().catch(() => ({})));
        if (!r.ok || body.ok === false) throw new Error(String(body.error || `request failed (${r.status})`));
        setMessage('Smart Clean started (safe dry-run).');
      } else if (action === 'optimize') {
        const r = await apiFetch('/api/actions/execute', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'quick-safe-clean' })
        });
        const body = asRecord(await r.json().catch(() => ({})));
        if (!r.ok || body.ok === false) throw new Error(String(body.error || `request failed (${r.status})`));
        setMessage('Smart Optimize profile executed.');
      } else {
        const r = await apiFetch('/api/clean/advance/registry', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ dryRun: true, total: 90 })
        });
        const body = asRecord(await r.json().catch(() => ({})));
        if (!r.ok || body.ok === false) throw new Error(String(body.error || `request failed (${r.status})`));
        setMessage('Smart Fix pre-check started (registry + integrity preparation).');
      }
    } catch (err: unknown) {
      setMessage(toErrorMessage(err));
    } finally {
      setBusyAction(null);
    }
  };

  return (
    <div className="space-y-4">
      <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>$</span>
        <span>neooptimize dashboard --adaptive --realtime</span>
        <span style={{ color: 'var(--ansi-cyan)' }}>{lastUpdated ? `updated ${lastUpdated}` : ''}</span>
      </div>

      {message && (
        <div
          className="px-3 py-2 text-xs border"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-tertiary)',
            color: message.toLowerCase().includes('fail') || message.toLowerCase().includes('error') ? 'var(--ansi-red)' : 'var(--text-primary)'
          }}
        >
          {message}
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-4">
        <div className="border p-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="text-[10px]" style={{ color: 'var(--text-muted)' }}>CPU Usage</div>
          <div className="text-xl font-bold" style={{ color: 'var(--text-primary)' }}>{metrics.cpu.toFixed(1)}%</div>
        </div>
        <div className="border p-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="text-[10px]" style={{ color: 'var(--text-muted)' }}>Memory Usage</div>
          <div className="text-xl font-bold" style={{ color: 'var(--text-primary)' }}>{Number(overview.memPercent ?? metrics.mem).toFixed(1)}%</div>
        </div>
        <div className="border p-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="text-[10px]" style={{ color: 'var(--text-muted)' }}>Network Latency</div>
          <div className="text-xl font-bold" style={{ color: 'var(--text-primary)' }}>{metrics.net.toFixed(0)} ms</div>
        </div>
        <div className="border p-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="text-[10px]" style={{ color: 'var(--text-muted)' }}>Health Status</div>
          <div className="text-xl font-bold" style={{ color: healthColor(health) }}>{health.toUpperCase()}</div>
        </div>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <div className="border p-4 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-cyan)' }}>
            <Activity size={14} /> Quick Actions
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
            <button
              onClick={() => runQuickAction('clean')}
              disabled={busyAction != null}
              className="px-3 py-2 text-xs border font-bold disabled:opacity-50"
              style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}
            >
              {busyAction === 'clean' ? 'RUNNING...' : 'Smart Clean'}
            </button>
            <button
              onClick={() => runQuickAction('optimize')}
              disabled={busyAction != null}
              className="px-3 py-2 text-xs border font-bold disabled:opacity-50"
              style={{ borderColor: 'var(--ansi-blue)', color: 'var(--ansi-blue)' }}
            >
              {busyAction === 'optimize' ? 'RUNNING...' : 'Smart Optimize'}
            </button>
            <button
              onClick={() => runQuickAction('fix')}
              disabled={busyAction != null}
              className="px-3 py-2 text-xs border font-bold disabled:opacity-50"
              style={{ borderColor: 'var(--ansi-yellow)', color: 'var(--ansi-yellow)' }}
            >
              {busyAction === 'fix' ? 'RUNNING...' : 'Smart Fix'}
            </button>
          </div>
          <div className="text-[11px]" style={{ color: 'var(--text-muted)' }}>
            Progressive disclosure: advanced controls tersedia di module Cleaner/Optimizer/System Tools.
          </div>
        </div>

        <div className="border p-4 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-yellow)' }}>
            <Stethoscope size={14} /> Device Summary
          </div>
          <div className="space-y-2 text-xs">
            <div className="flex justify-between">
              <span style={{ color: 'var(--text-muted)' }}>Host</span>
              <span style={{ color: 'var(--text-primary)' }}>{overview.hostname || '-'}</span>
            </div>
            <div className="flex justify-between">
              <span style={{ color: 'var(--text-muted)' }}>Platform</span>
              <span style={{ color: 'var(--text-primary)' }}>{overview.platform || '-'}</span>
            </div>
            <div className="flex justify-between">
              <span style={{ color: 'var(--text-muted)' }}>Kernel</span>
              <span style={{ color: 'var(--text-primary)' }}>{overview.kernel || '-'}</span>
            </div>
            <div className="flex justify-between">
              <span style={{ color: 'var(--text-muted)' }}>Uptime</span>
              <span style={{ color: 'var(--text-primary)' }}>{uptime}</span>
            </div>
            <div className="flex justify-between">
              <span style={{ color: 'var(--text-muted)' }}>Tasks</span>
              <span style={{ color: 'var(--text-primary)' }}>{tasks}</span>
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <div className="border p-4 text-xs" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="font-bold mb-2 flex items-center gap-2" style={{ color: 'var(--ansi-green)' }}>
            <Sparkles size={14} /> Security Snapshot
          </div>
          <div className="flex justify-between mb-1">
            <span style={{ color: 'var(--text-muted)' }}>Antivirus</span>
            <span style={{ color: 'var(--text-primary)' }}>{security.antivirus || '-'}</span>
          </div>
          <div className="flex justify-between mb-1">
            <span style={{ color: 'var(--text-muted)' }}>Firewall</span>
            <span style={{ color: 'var(--text-primary)' }}>{security.firewall || '-'}</span>
          </div>
          <div className="flex justify-between mb-1">
            <span style={{ color: 'var(--text-muted)' }}>Scan</span>
            <span style={{ color: 'var(--text-primary)' }}>
              {security.scan?.running ? `running ${security.scan.progress}%` : 'idle'}
            </span>
          </div>
          <div style={{ color: (security.issues || []).length > 0 ? 'var(--ansi-yellow)' : 'var(--text-muted)' }}>
            {(security.issues || []).length > 0 ? security.issues.join(' | ') : 'No security issue reported'}
          </div>
        </div>

        <div className="border p-4 text-xs" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="font-bold mb-2 flex items-center gap-2" style={{ color: 'var(--ansi-blue)' }}>
            <Wrench size={14} /> Blueprint Notes
          </div>
          <div style={{ color: 'var(--text-primary)' }}>Core Hub: dashboard + cleaner + optimizer + smart fix + unified logs.</div>
          <div style={{ color: 'var(--text-muted)', marginTop: 6 }}>
            Advanced module membuka controls tambahan: registry cleaner, backup restore, security engine, scheduler profile.
          </div>
        </div>
      </div>
    </div>
  );
}
