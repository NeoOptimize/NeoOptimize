import { useEffect, useState } from 'react';
import { RefreshCw, Shield, Wrench } from 'lucide-react';
import { apiFetch } from '../../lib/api';
import { asArray, asRecord, toErrorMessage } from '../../lib/safe';
import { UIMode } from '../../types/ui';

type BackupEntry = {
  id: string;
  time: string;
};

interface SystemToolsPageProps {
  uiMode: UIMode;
}

export function SystemToolsPage({ uiMode }: SystemToolsPageProps) {
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState('');
  const [backups, setBackups] = useState<BackupEntry[]>([]);

  const loadBackups = async () => {
    try {
      const r = await apiFetch('/api/clean/advance/backups');
      const body = asRecord(await r.json().catch(() => ({})));
      if (!r.ok || body.ok === false) throw new Error(String(body.error || `request failed (${r.status})`));
      setBackups(asArray<BackupEntry>(body.backups));
    } catch (err: unknown) {
      setMessage(toErrorMessage(err));
    }
  };

  useEffect(() => {
    void loadBackups();
  }, []);

  const runSystemRepair = async () => {
    setBusy('repair');
    setMessage('');
    try {
      // Current backend has no dedicated SFC/DISM endpoint. Use safe pre-check flow.
      const r = await apiFetch('/api/clean/advance/registry', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ dryRun: true, total: 90 })
      });
      const body = asRecord(await r.json().catch(() => ({})));
      if (!r.ok || body.ok === false) throw new Error(String(body.error || `request failed (${r.status})`));
      setMessage('System Repair pre-check started. Next step: integrate SFC + DISM executor endpoint.');
    } catch (err: unknown) {
      setMessage(toErrorMessage(err));
    } finally {
      setBusy(null);
    }
  };

  const createRestoreBackup = async () => {
    setBusy('backup');
    setMessage('');
    try {
      const r = await apiFetch('/api/clean/advance/backup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ note: 'system-tools pre-repair backup' })
      });
      const body = asRecord(await r.json().catch(() => ({})));
      if (!r.ok || body.ok === false) throw new Error(String(body.error || `request failed (${r.status})`));
      setMessage(`Restore backup created: ${String(asRecord(body.entry).id || 'ok')}`);
      await loadBackups();
    } catch (err: unknown) {
      setMessage(toErrorMessage(err));
    } finally {
      setBusy(null);
    }
  };

  const restoreBackup = async (id: string) => {
    if (!id) return;
    setBusy(id);
    setMessage('');
    try {
      const r = await apiFetch('/api/clean/advance/backup/restore', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id })
      });
      const body = asRecord(await r.json().catch(() => ({})));
      if (!r.ok || body.ok === false) throw new Error(String(body.error || `request failed (${r.status})`));
      setMessage(`Backup restored: ${id}`);
    } catch (err: unknown) {
      setMessage(toErrorMessage(err));
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="space-y-4">
      <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>$</span>
        <span>neooptimize system-tools --repair --restore</span>
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
        <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-yellow)' }}>
          <Wrench size={14} /> System Repair
        </div>
        <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
          Target flow: SFC + DISM repair pipeline. Saat ini route backend yang tersedia menjalankan pre-check aman.
        </div>
        <button
          onClick={runSystemRepair}
          disabled={busy != null}
          className="px-3 py-2 text-xs border font-bold disabled:opacity-50"
          style={{ borderColor: 'var(--ansi-yellow)', color: 'var(--ansi-yellow)' }}
        >
          {busy === 'repair' ? 'RUNNING...' : 'Run Smart Fix'}
        </button>
      </div>

      <div className="border p-4 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-green)' }}>
          <Shield size={14} /> Restore & Backup
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={createRestoreBackup}
            disabled={busy != null}
            className="px-3 py-2 text-xs border font-bold disabled:opacity-50"
            style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}
          >
            {busy === 'backup' ? 'CREATING...' : 'Create Restore Backup'}
          </button>
          <button
            onClick={loadBackups}
            disabled={busy != null}
            className="px-3 py-2 text-xs border font-bold disabled:opacity-50"
            style={{ borderColor: 'var(--ansi-blue)', color: 'var(--ansi-blue)' }}
          >
            <RefreshCw size={12} className="inline mr-1" /> Refresh
          </button>
        </div>

        {uiMode !== 'advanced' && (
          <div className="text-[11px]" style={{ color: 'var(--ansi-yellow)' }}>
            Detail restore manager penuh lebih cocok dipakai di Advanced mode.
          </div>
        )}

        <div className="space-y-2">
          {backups.length === 0 ? (
            <div className="text-xs" style={{ color: 'var(--text-muted)' }}>No backup found.</div>
          ) : (
            backups
              .slice()
              .reverse()
              .slice(0, uiMode === 'advanced' ? 12 : 5)
              .map((entry) => (
                <div
                  key={entry.id}
                  className="flex items-center justify-between px-3 py-2 border text-xs"
                  style={{ borderColor: 'var(--border-color)' }}
                >
                  <div>
                    <div style={{ color: 'var(--text-primary)' }}>{entry.id}</div>
                    <div style={{ color: 'var(--text-muted)' }}>{new Date(entry.time).toLocaleString()}</div>
                  </div>
                  <button
                    onClick={() => restoreBackup(entry.id)}
                    disabled={busy != null}
                    className="px-2 py-1 text-[10px] border font-bold disabled:opacity-50"
                    style={{ borderColor: 'var(--ansi-cyan)', color: 'var(--ansi-cyan)' }}
                  >
                    {busy === entry.id ? 'RESTORING...' : 'Restore'}
                  </button>
                </div>
              ))
          )}
        </div>
      </div>
    </div>
  );
}
