import { useMemo, useState } from 'react';
import { Gauge, Network, ShieldCheck, SlidersHorizontal } from 'lucide-react';
import { apiFetch } from '../../lib/api';
import { asRecord, toErrorMessage } from '../../lib/safe';
import { UIMode } from '../../types/ui';

interface OptimizerPageProps {
  uiMode: UIMode;
}

export function OptimizerPage({ uiMode }: OptimizerPageProps) {
  const [runningType, setRunningType] = useState<'smart' | 'manual' | null>(null);
  const [manualCpu, setManualCpu] = useState(true);
  const [manualNetwork, setManualNetwork] = useState(true);
  const [manualPrivacy, setManualPrivacy] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [lastRun, setLastRun] = useState('');

  const canUseManual = useMemo(() => uiMode === 'advanced', [uiMode]);

  const runSmartOptimize = async () => {
    setRunningType('smart');
    setBusy(true);
    setMessage('');
    try {
      const actionRes = await apiFetch('/api/actions/execute', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'quick-safe-clean' })
      });
      const actionBody = asRecord(await actionRes.json().catch(() => ({})));
      if (!actionRes.ok || actionBody.ok === false) {
        throw new Error(String(actionBody.error || `request failed (${actionRes.status})`));
      }

      const pingRes = await apiFetch('/api/network/ping', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ host: '1.1.1.1', count: 1 })
      });
      const pingBody = asRecord(await pingRes.json().catch(() => ({})));
      const pingOutput = String(pingBody.output || '').split(/\r?\n/).find(Boolean) || 'ping complete';
      setMessage(`Smart optimize complete. ${pingOutput}`);
      setLastRun(new Date().toLocaleTimeString());
    } catch (err: unknown) {
      setMessage(toErrorMessage(err));
    } finally {
      setBusy(false);
      setRunningType(null);
    }
  };

  const runManualOptimize = async () => {
    setRunningType('manual');
    setBusy(true);
    setMessage('');
    try {
      const steps: string[] = [];

      if (manualCpu) {
        const actionRes = await apiFetch('/api/actions/execute', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'quick-safe-clean' })
        });
        const actionBody = asRecord(await actionRes.json().catch(() => ({})));
        if (!actionRes.ok || actionBody.ok === false) throw new Error(String(actionBody.error || 'CPU optimization step failed'));
        steps.push('cpu profile');
      }

      if (manualNetwork) {
        const pingRes = await apiFetch('/api/network/ping', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ host: '8.8.8.8', count: 1 })
        });
        const pingBody = asRecord(await pingRes.json().catch(() => ({})));
        if (!pingRes.ok || pingBody.ok === false) throw new Error(String(pingBody.error || 'network optimization step failed'));
        steps.push('network probe');
      }

      if (manualPrivacy) {
        const regRes = await apiFetch('/api/clean/advance/registry', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ dryRun: true, total: 90 })
        });
        const regBody = asRecord(await regRes.json().catch(() => ({})));
        if (!regRes.ok || regBody.ok === false) throw new Error(String(regBody.error || 'privacy pack step failed'));
        steps.push('privacy pack');
      }

      setMessage(`Manual optimize complete: ${steps.length > 0 ? steps.join(', ') : 'no step selected'}.`);
      setLastRun(new Date().toLocaleTimeString());
    } catch (err: unknown) {
      setMessage(toErrorMessage(err));
    } finally {
      setBusy(false);
      setRunningType(null);
    }
  };

  return (
    <div className="space-y-4">
      <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>$</span>
        <span>neooptimize optimizer --smart --manual</span>
        <span style={{ color: 'var(--ansi-cyan)' }}>{lastRun ? `last run ${lastRun}` : ''}</span>
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

      <div className="border p-4 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-green)' }}>
          <Gauge size={14} /> Smart Mode
        </div>
        <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
          Smart mode otomatis menjalankan profil optimize berdasarkan kondisi runtime.
        </div>
        <button
          onClick={runSmartOptimize}
          disabled={busy}
          className="px-3 py-2 text-xs border font-bold disabled:opacity-50"
          style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}
        >
          {busy && runningType === 'smart' ? 'RUNNING...' : 'Run Smart Optimize'}
        </button>
      </div>

      <div className="border p-4 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="flex items-center justify-between">
          <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-blue)' }}>
            <SlidersHorizontal size={14} /> Manual Mode
          </div>
          {!canUseManual && (
            <span className="text-[10px]" style={{ color: 'var(--ansi-yellow)' }}>
              Manual mode aktif di Advanced UI
            </span>
          )}
        </div>
        <div className="space-y-2 text-xs">
          <label className="flex items-center gap-2" style={{ color: canUseManual ? 'var(--text-primary)' : 'var(--text-muted)' }}>
            <input type="checkbox" checked={manualCpu} disabled={!canUseManual || busy} onChange={(e) => setManualCpu(e.target.checked)} />
            <Gauge size={12} /> CPU/RAM profile
          </label>
          <label className="flex items-center gap-2" style={{ color: canUseManual ? 'var(--text-primary)' : 'var(--text-muted)' }}>
            <input type="checkbox" checked={manualNetwork} disabled={!canUseManual || busy} onChange={(e) => setManualNetwork(e.target.checked)} />
            <Network size={12} /> Network tuning
          </label>
          <label className="flex items-center gap-2" style={{ color: canUseManual ? 'var(--text-primary)' : 'var(--text-muted)' }}>
            <input type="checkbox" checked={manualPrivacy} disabled={!canUseManual || busy} onChange={(e) => setManualPrivacy(e.target.checked)} />
            <ShieldCheck size={12} /> Privacy pack
          </label>
        </div>
        <button
          onClick={runManualOptimize}
          disabled={!canUseManual || busy}
          className="px-3 py-2 text-xs border font-bold disabled:opacity-50"
          style={{ borderColor: 'var(--ansi-blue)', color: 'var(--ansi-blue)' }}
        >
          {busy && runningType === 'manual' ? 'RUNNING...' : 'Run Manual Optimize'}
        </button>
      </div>

      <div className="border p-4 text-xs" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div style={{ color: 'var(--ansi-cyan)', fontWeight: 700, marginBottom: 6 }}>Adaptive Notes</div>
        <div style={{ color: 'var(--text-primary)' }}>
          Simple mode menampilkan optimize inti saja. Advanced mode membuka manual toggle dan privacy pack.
        </div>
      </div>
    </div>
  );
}
