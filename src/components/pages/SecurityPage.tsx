import React, { useEffect, useMemo, useState } from 'react';
import { Shield, Lock, AlertTriangle, CheckCircle } from 'lucide-react';
import { apiFetch } from '../../lib/api';

type SecurityStatus = {
  antivirus: string;
  firewall: string;
  issues: string[];
  scan?: { running: boolean; progress: number; startedAt?: string; finishedAt?: string; threats?: number; suspicious?: number; scanned?: number; engine?: string; requestedEngine?: string };
  settings?: { preferredEngine?: 'auto' | 'kicomav' | 'clamav'; clamscanPath?: string };
  engines?: {
    recommended?: 'kicomav' | 'clamav' | null;
    kicomav?: { available?: boolean };
    clamav?: { available?: boolean; binary?: string | null; database?: { ready?: boolean; dir?: string | null; fileCount?: number } };
  };
};

export function SecurityPage() {
  const [status, setStatus] = useState<SecurityStatus>({ antivirus: 'unknown', firewall: 'unknown', issues: [] });
  const [logs, setLogs] = useState<string[]>([]);
  const [scanning, setScanning] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [settingsInitialized, setSettingsInitialized] = useState(false);
  const [engineChoice, setEngineChoice] = useState<'auto' | 'kicomav' | 'clamav'>('auto');
  const [preferredEngine, setPreferredEngine] = useState<'auto' | 'kicomav' | 'clamav'>('auto');
  const [clamscanPath, setClamscanPath] = useState('');
  const [setupBusy, setSetupBusy] = useState(false);
  const [setupInfo, setSetupInfo] = useState<{ binary?: string; version?: string; freshclam?: { path?: string; version?: string } } | null>(null);
  const [dbUpdateBusy, setDbUpdateBusy] = useState(false);
  const [dbUpdateInfo, setDbUpdateInfo] = useState<{ dbDir?: string; fileCount?: number; output?: string } | null>(null);

  const refresh = React.useCallback(async () => {
    try {
      const [sRes, lRes, eRes] = await Promise.all([apiFetch('/api/security/status'), apiFetch('/api/logs?search=security&limit=120'), apiFetch('/api/security/engines')]);
      const s = await sRes.json();
      const l = await lRes.json();
      const e = await eRes.json();
      if (s?.ok) {
        setStatus(s.status || { antivirus: 'unknown', firewall: 'unknown', issues: [] });
        setScanning(Boolean(s.status?.scan?.running));
        if (!settingsInitialized) {
          if (s.status?.settings?.preferredEngine) setPreferredEngine(s.status.settings.preferredEngine);
          if (s.status?.settings?.clamscanPath != null) setClamscanPath(String(s.status.settings.clamscanPath || ''));
          setSettingsInitialized(true);
        }
      }
      if (e?.ok) {
        setStatus((prev) => ({ ...prev, engines: e, settings: e.settings || prev.settings }));
      }
      if (l?.ok) {
        const lines = (l.logs || []).map((x: any) => `[${new Date(x.time).toLocaleTimeString()}] ${x.message}`);
        setLogs(lines.slice(-40));
      }
      setError('');
    } catch (err: any) {
      setError(String(err?.message || err));
    } finally {
      setLoading(false);
    }
  }, [settingsInitialized]);

  useEffect(() => {
    let mounted = true;
    let timer: ReturnType<typeof setTimeout> | null = null;
    const loop = async () => {
      if (!mounted) return;
      await refresh();
      if (!mounted) return;
      const hidden = typeof document !== 'undefined' && document.visibilityState === 'hidden';
      const ms = hidden ? 12000 : (scanning ? 2500 : 5000);
      timer = setTimeout(loop, ms);
    };
    loop();
    return () => {
      mounted = false;
      if (timer) clearTimeout(timer);
    };
  }, [refresh, scanning]);

  const runScan = async () => {
    try {
      setMessage('');
      const r = await apiFetch('/api/security/scan', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ detail: 'manual-ui-scan', engine: engineChoice }) });
      const j = await r.json();
      if (j?.ok) {
        setScanning(true);
        setError('');
        setMessage(`Security scan started (${engineChoice.toUpperCase()})`);
      }
      else setError(String(j?.error || 'scan failed'));
    } catch (err: any) {
      setError(String(err?.message || err));
    }
  };

  const stopScan = async () => {
    try {
      const r = await apiFetch('/api/security/scan/stop', { method: 'POST' });
      const j = await r.json();
      if (!r.ok || !j?.ok) setError(String(j?.error || 'stop scan failed'));
      else {
        setError('');
        setMessage('Security scan stop requested');
      }
      await refresh();
    } catch (err: any) {
      setError(String(err?.message || err));
    }
  };

  const saveSettings = async () => {
    setSaving(true);
    try {
      const r = await apiFetch('/api/security/settings', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ preferredEngine, clamscanPath })
      });
      const j = await r.json();
      if (!r.ok || !j?.ok) {
        setError(String(j?.error || 'save settings failed'));
      } else {
        setMessage('Security settings saved');
        setError('');
        if (j.settings?.preferredEngine) setPreferredEngine(j.settings.preferredEngine);
        if (j.settings?.clamscanPath != null) setClamscanPath(String(j.settings.clamscanPath || ''));
        setSettingsInitialized(true);
      }
      await refresh();
    } catch (err: any) {
      setError(String(err?.message || err));
    } finally {
      setSaving(false);
    }
  };

  const runClamavSetup = async () => {
    setSetupBusy(true);
    try {
      const r = await apiFetch('/api/security/clamav/setup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ preferredEngine, clamscanPath })
      });
      const j = await r.json();
      if (!r.ok || !j?.ok) {
        setSetupInfo(null);
        setError(String(j?.error || 'ClamAV setup failed'));
      } else {
        setSetupInfo({ binary: j.detected, version: j.version, freshclam: j.freshclam || null });
        setMessage(j.message || 'ClamAV configured');
        setError('');
        if (j.settings?.preferredEngine) setPreferredEngine(j.settings.preferredEngine);
        if (j.settings?.clamscanPath != null) setClamscanPath(String(j.settings.clamscanPath || ''));
      }
      await refresh();
    } catch (err: any) {
      setError(String(err?.message || err));
    } finally {
      setSetupBusy(false);
    }
  };

  const updateClamavDb = async () => {
    setDbUpdateBusy(true);
    try {
      const r = await apiFetch('/api/security/clamav/update-db', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
      });
      const j = await r.json();
      if (!r.ok || !j?.ok) {
        setDbUpdateInfo(null);
        setError(String(j?.error || 'ClamAV database update failed'));
      } else {
        setDbUpdateInfo({ dbDir: j.dbDir, fileCount: j.fileCount, output: j.output || '' });
        setMessage(`ClamAV database updated (${j.fileCount} file(s))`);
        setError('');
      }
      await refresh();
    } catch (err: any) {
      setError(String(err?.message || err));
    } finally {
      setDbUpdateBusy(false);
    }
  };

  const antivirusActive = String(status.antivirus || '').toLowerCase().startsWith('active');
  const score = useMemo(() => {
    let s = 100;
    if (status.firewall !== 'enabled') s -= 25;
    if (!antivirusActive) s -= 25;
    s -= Math.min(30, (status.issues || []).length * 10);
    return Math.max(0, s);
  }, [status, antivirusActive]);

  return (
    <div className="space-y-4">
      <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>$</span>
        <span>neooptimize security --scan --status</span>
      </div>

      {(loading || error || message) && (
        <div className="px-3 py-2 text-xs border" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: error ? 'var(--ansi-red)' : 'var(--text-primary)' }}>
          {loading ? 'Loading security status...' : error || message}
        </div>
      )}

      <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="flex items-center gap-2 mb-4 text-xs font-bold" style={{ color: 'var(--ansi-cyan)' }}><Shield size={14} /> SECURITY SCAN</div>
        <div className="mb-3 flex items-center gap-2">
          <select
            value={engineChoice}
            onChange={(e) => setEngineChoice(e.target.value as 'auto' | 'kicomav' | 'clamav')}
            disabled={scanning}
            className="px-2 py-1 text-[10px] border bg-transparent font-mono disabled:opacity-50"
            style={{ borderColor: 'var(--border-color)', color: 'var(--text-primary)' }}
          >
            <option value="auto">AUTO (recommended)</option>
            <option value="kicomav">KICOMAV</option>
            <option value="clamav">CLAMAV</option>
          </select>
          <div className="text-[10px]" style={{ color: 'var(--text-muted)' }}>
            Recommended: <span style={{ color: 'var(--ansi-cyan)' }}>{status.engines?.recommended || 'none'}</span>
            {' '}| Kico: <span style={{ color: status.engines?.kicomav?.available ? 'var(--ansi-green)' : 'var(--ansi-red)' }}>{status.engines?.kicomav?.available ? 'READY' : 'N/A'}</span>
            {' '}| Clam: <span style={{ color: status.engines?.clamav?.available ? 'var(--ansi-green)' : 'var(--ansi-red)' }}>{status.engines?.clamav?.available ? 'READY' : 'N/A'}</span>
          </div>
        </div>
        <div className="h-36 overflow-y-auto mb-4 p-2 border font-mono text-xs space-y-1" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--terminal-output-bg)' }}>
          {logs.length === 0 && <div style={{ color: 'var(--text-muted)' }}>No security log yet...</div>}
          {logs.map((line, i) => <div key={i} style={{ color: 'var(--text-primary)' }}>{line}</div>)}
          {scanning && <div className="cursor-blink" style={{ color: 'var(--ansi-green)' }}>_</div>}
        </div>
        <div className="mb-4 p-2 border flex justify-between text-xs" style={{ borderColor: 'var(--border-color)', backgroundColor: 'rgba(0,255,65,0.05)' }}>
          <span style={{ color: 'var(--ansi-green)' }}>Threats: {status.scan?.threats ?? 0}</span>
          <span style={{ color: 'var(--ansi-yellow)' }}>Suspicious: {status.scan?.suspicious ?? 0}</span>
          <span style={{ color: 'var(--text-primary)' }}>Scanned: {(status.scan?.scanned ?? 0).toLocaleString()} items</span>
        </div>
        <div className="mb-2 text-[10px] flex justify-between" style={{ color: 'var(--text-muted)' }}>
          <span>Active engine: <span style={{ color: 'var(--text-primary)' }}>{status.scan?.engine || '-'}</span></span>
          <span>Requested: <span style={{ color: 'var(--text-primary)' }}>{status.scan?.requestedEngine || engineChoice}</span></span>
        </div>
        <div className="h-2 w-full bg-[var(--bg-tertiary)] mb-2 overflow-hidden"><div className="h-full transition-all duration-500" style={{ width: `${status.scan?.progress || 0}%`, backgroundColor: 'var(--ansi-cyan)' }} /></div>
        <div className="grid grid-cols-2 gap-2">
          <button onClick={runScan} disabled={scanning} className="py-2 text-xs font-bold border transition-colors disabled:opacity-60" style={{ borderColor: 'var(--ansi-cyan)', color: scanning ? 'var(--bg-primary)' : 'var(--ansi-cyan)', backgroundColor: scanning ? 'var(--ansi-cyan)' : 'transparent' }}>
            {scanning ? `SCANNING... ${status.scan?.progress || 0}%` : '[RUN SECURITY SCAN]'}
          </button>
          <button onClick={stopScan} disabled={!scanning} className="py-2 text-xs font-bold border transition-colors disabled:opacity-60" style={{ borderColor: 'var(--ansi-red)', color: 'var(--ansi-red)' }}>
            [STOP SCAN]
          </button>
        </div>
      </div>

      <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="text-xs font-bold mb-3" style={{ color: 'var(--ansi-yellow)' }}>ENGINE SETTINGS</div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div className="space-y-1">
            <div className="text-[10px]" style={{ color: 'var(--text-muted)' }}>Preferred engine (auto follows recommendation)</div>
            <select
              value={preferredEngine}
              onChange={(e) => setPreferredEngine(e.target.value as 'auto' | 'kicomav' | 'clamav')}
              disabled={saving || scanning}
              className="w-full px-2 py-1 text-[10px] border bg-transparent font-mono"
              style={{ borderColor: 'var(--border-color)', color: 'var(--text-primary)' }}
            >
              <option value="auto">AUTO</option>
              <option value="kicomav">KICOMAV</option>
              <option value="clamav">CLAMAV</option>
            </select>
          </div>
          <div className="space-y-1">
            <div className="text-[10px]" style={{ color: 'var(--text-muted)' }}>ClamAV binary path (`clamscan.exe`)</div>
            <input
              value={clamscanPath}
              onChange={(e) => setClamscanPath(e.target.value)}
              placeholder="D:\\Apps\\ClamAV\\clamscan.exe"
              disabled={saving || scanning}
              className="w-full px-2 py-1 text-[10px] border bg-transparent font-mono outline-none"
              style={{ borderColor: 'var(--border-color)', color: 'var(--text-primary)' }}
            />
            <div className="text-[10px]" style={{ color: 'var(--text-muted)' }}>
              Detected: <span style={{ color: 'var(--text-primary)' }}>{status.engines?.clamav?.binary || '-'}</span>
            </div>
            <div className="text-[10px]" style={{ color: status.engines?.clamav?.database?.ready ? 'var(--ansi-green)' : 'var(--ansi-yellow)' }}>
              DB: {status.engines?.clamav?.database?.ready ? `READY (${status.engines?.clamav?.database?.fileCount || 0})` : 'MISSING'}
              {status.engines?.clamav?.database?.dir ? ` @ ${status.engines.clamav.database.dir}` : ''}
            </div>
          </div>
        </div>
        <div className="mt-3 flex items-center justify-between gap-2">
          <button
            onClick={runClamavSetup}
            disabled={setupBusy || saving || scanning}
            className="px-3 py-1 text-[10px] font-bold border disabled:opacity-50"
            style={{ borderColor: 'var(--ansi-blue)', color: 'var(--ansi-blue)' }}
          >
            {setupBusy ? 'SETTING UP...' : 'AUTO SETUP CLAMAV'}
          </button>
          <button
            onClick={updateClamavDb}
            disabled={dbUpdateBusy || setupBusy || saving || scanning || !status.engines?.clamav?.binary}
            className="px-3 py-1 text-[10px] font-bold border disabled:opacity-50"
            style={{ borderColor: 'var(--ansi-yellow)', color: 'var(--ansi-yellow)' }}
          >
            {dbUpdateBusy ? 'UPDATING DB...' : 'UPDATE CLAMAV DB'}
          </button>
          <button
            onClick={saveSettings}
            disabled={saving || scanning}
            className="px-3 py-1 text-[10px] font-bold border disabled:opacity-50"
            style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}
          >
            {saving ? 'SAVING...' : 'SAVE SETTINGS'}
          </button>
        </div>
        {setupInfo && (
          <div className="mt-3 p-2 border text-[10px] space-y-1 font-mono" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: 'var(--text-primary)' }}>
            <div>clamscan: {setupInfo.binary || '-'}</div>
            <div>version: {setupInfo.version || '-'}</div>
            <div>freshclam: {setupInfo.freshclam?.path || '-'}</div>
          </div>
        )}
        {dbUpdateInfo && (
          <div className="mt-2 p-2 border text-[10px] space-y-1 font-mono" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: 'var(--text-primary)' }}>
            <div>db dir: {dbUpdateInfo.dbDir || '-'}</div>
            <div>db files: {dbUpdateInfo.fileCount ?? 0}</div>
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="flex items-center justify-between mb-3">
            <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--text-primary)' }}><Lock size={14} /> FIREWALL STATUS</div>
            <span className="px-1.5 py-0.5 text-[9px]" style={{ backgroundColor: status.firewall === 'enabled' ? 'rgba(0,255,65,0.1)' : 'rgba(255,68,68,0.1)', color: status.firewall === 'enabled' ? 'var(--ansi-green)' : 'var(--ansi-red)' }}>
              {status.firewall.toUpperCase()}
            </span>
          </div>
          <div className="space-y-2 text-xs">
            <div className="flex justify-between"><span style={{ color: 'var(--text-muted)' }}>Antivirus</span><span style={{ color: 'var(--text-primary)' }}>{status.antivirus}</span></div>
            <div className="flex justify-between"><span style={{ color: 'var(--text-muted)' }}>Firewall</span><span style={{ color: 'var(--text-primary)' }}>{status.firewall}</span></div>
            <div className="flex justify-between"><span style={{ color: 'var(--text-muted)' }}>Scan Engine</span><span style={{ color: 'var(--text-primary)' }}>{status.scan?.engine || '-'}</span></div>
            <div className="mt-2 pt-2 border-t" style={{ borderColor: 'var(--border-color)' }}>
              <div className="text-[10px] mb-1" style={{ color: status.issues.length ? 'var(--ansi-yellow)' : 'var(--ansi-green)' }}>SECURITY ISSUES</div>
              {status.issues.length === 0 ? <div style={{ color: 'var(--ansi-green)' }}>No active issue detected</div> : status.issues.map((x, i) => <div key={i} style={{ color: 'var(--text-muted)' }}>{x}</div>)}
            </div>
          </div>
        </div>

        <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="flex items-center gap-2 mb-3 text-xs font-bold" style={{ color: 'var(--ansi-yellow)' }}><AlertTriangle size={14} /> VULNERABILITY CHECK</div>
          <div className="flex items-center gap-4 mb-4">
            <div className="text-3xl font-bold" style={{ color: score >= 80 ? 'var(--ansi-green)' : score >= 60 ? 'var(--ansi-yellow)' : 'var(--ansi-red)' }}>{score}</div>
            <div className="text-xs" style={{ color: 'var(--text-muted)' }}>Security Score<br /><span style={{ color: score >= 80 ? 'var(--ansi-green)' : score >= 60 ? 'var(--ansi-yellow)' : 'var(--ansi-red)' }}>{score >= 80 ? 'Good Standing' : score >= 60 ? 'Need Attention' : 'At Risk'}</span></div>
          </div>
          <div className="space-y-2 text-xs">
            <div className="flex items-center gap-2"><CheckCircle size={12} style={{ color: status.firewall === 'enabled' ? 'var(--ansi-green)' : 'var(--ansi-red)' }} /><span style={{ color: 'var(--text-primary)' }}>Firewall {status.firewall}</span></div>
            <div className="flex items-center gap-2"><CheckCircle size={12} style={{ color: antivirusActive ? 'var(--ansi-green)' : 'var(--ansi-red)' }} /><span style={{ color: 'var(--text-primary)' }}>Antivirus {status.antivirus}</span></div>
            <div className="flex items-center gap-2"><AlertTriangle size={12} style={{ color: status.issues.length ? 'var(--ansi-yellow)' : 'var(--ansi-green)' }} /><span style={{ color: 'var(--text-primary)' }}>{status.issues.length} issue(s) reported</span></div>
          </div>
        </div>
      </div>
    </div>
  );
}
