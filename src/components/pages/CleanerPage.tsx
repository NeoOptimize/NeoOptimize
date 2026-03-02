import { useEffect, useState } from 'react';
import { Database, Eraser, ShieldCheck } from 'lucide-react';
import { apiFetch } from '../../lib/api';
import { asArray, asRecord, toErrorMessage } from '../../lib/safe';
import { UIMode } from '../../types/ui';

type BackupEntry = {
  id: string;
  time: string;
  meta?: { note?: string };
};

interface CleanerPageProps {
  uiMode: UIMode;
}

export function CleanerPage({ uiMode }: CleanerPageProps) {
  const [advancedOpen, setAdvancedOpen] = useState(uiMode === 'advanced');
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState('');
  const [backups, setBackups] = useState<BackupEntry[]>([]);

  useEffect(() => {
    if (uiMode === 'advanced') setAdvancedOpen(true);
  }, [uiMode]);

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

  const runQuickClean = async () => {
    setBusy('quick');
    setMessage('');
    try {
      const r = await apiFetch('/api/clean/advance/start', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ mode: 'dump', dryRun: true, total: 90 })
      });
      const body = asRecord(await r.json().catch(() => ({})));
      if (!r.ok || body.ok === false) throw new Error(String(body.error || `request failed (${r.status})`));
      setMessage('Quick safe clean started.');
    } catch (err: unknown) {
      setMessage(toErrorMessage(err));
    } finally {
      setBusy(null);
    }
  };

  const runRegistryScan = async () => {
    setBusy('registry');
    setMessage('');
    try {
      const r = await apiFetch('/api/clean/advance/registry', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ dryRun: true, total: 90 })
      });
      const body = asRecord(await r.json().catch(() => ({})));
      if (!r.ok || body.ok === false) throw new Error(String(body.error || `request failed (${r.status})`));
      setMessage('Registry cleaner started (safe dry-run).');
    } catch (err: unknown) {
      setMessage(toErrorMessage(err));
    } finally {
      setBusy(null);
    }
  };

  const createBackup = async () => {
    setBusy('backup');
    setMessage('');
    try {
      const r = await apiFetch('/api/clean/advance/backup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ note: 'manual cleaner backup' })
      });
      const body = asRecord(await r.json().catch(() => ({})));
      if (!r.ok || body.ok === false) throw new Error(String(body.error || `request failed (${r.status})`));
      setMessage(`Backup created: ${String(asRecord(body.entry).id || 'ok')}`);
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
        <span>neooptimize cleaner --adaptive</span>
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
          <ShieldCheck size={14} /> Default Cleaner (Simple Mode)
        </div>
        <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
          Default action hanya cache/temp/junk dengan safe dry-run.
        </div>
        <button
          onClick={runQuickClean}
          disabled={busy != null}
          className="px-3 py-2 text-xs border font-bold disabled:opacity-50"
          style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}
        >
          {busy === 'quick' ? 'RUNNING...' : 'Smart Clean'}
        </button>
      </div>

      <div className="border p-4 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="flex items-center justify-between">
          <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-yellow)' }}>
            <Database size={14} /> Advanced Cleaner
          </div>
          <button
            onClick={() => setAdvancedOpen((v) => !v)}
            className="px-2 py-1 text-[10px] border font-bold"
            style={{ borderColor: 'var(--border-color)', color: 'var(--text-primary)' }}
          >
            {advancedOpen ? 'HIDE' : 'SHOW'}
          </button>
        </div>

        {advancedOpen && (
          <>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
              <button
                onClick={runRegistryScan}
                disabled={busy != null}
                className="px-3 py-2 text-xs border font-bold disabled:opacity-50"
                style={{ borderColor: 'var(--ansi-yellow)', color: 'var(--ansi-yellow)' }}
              >
                {busy === 'registry' ? 'RUNNING...' : 'Registry Cleaner'}
              </button>
              <button
                onClick={createBackup}
                disabled={busy != null}
                className="px-3 py-2 text-xs border font-bold disabled:opacity-50"
                style={{ borderColor: 'var(--ansi-blue)', color: 'var(--ansi-blue)' }}
              >
                {busy === 'backup' ? 'CREATING...' : 'Create Backup'}
              </button>
              <button
                onClick={loadBackups}
                disabled={busy != null}
                className="px-3 py-2 text-xs border font-bold disabled:opacity-50"
                style={{ borderColor: 'var(--text-muted)', color: 'var(--text-muted)' }}
              >
                Refresh Backups
              </button>
            </div>

            <div className="space-y-2">
              <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-cyan)' }}>
                <Eraser size={14} /> Backup Manager
              </div>
              {backups.length === 0 ? (
                <div className="text-xs" style={{ color: 'var(--text-muted)' }}>No backup entry available.</div>
              ) : (
                backups
                  .slice()
                  .reverse()
                  .slice(0, 8)
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
                        style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}
                      >
                        {busy === entry.id ? 'RESTORING...' : 'Restore'}
                      </button>
                    </div>
                  ))
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
