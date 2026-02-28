import React, { useEffect, useMemo, useState } from 'react';
import { Settings, Package, Zap, Terminal, FileText } from 'lucide-react';
import { apiFetch } from '../../lib/api';

export function ConfigPage() {
  const neo = (window as any)?.neo;
  const [configText, setConfigText] = useState('loading...');
  const [configPath, setConfigPath] = useState('');
  const [configSections, setConfigSections] = useState<string[]>([]);
  const [cleanerText, setCleanerText] = useState('loading...');
  const [cleanerPath, setCleanerPath] = useState('');
  const [cleanerCategories, setCleanerCategories] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [reportPath, setReportPath] = useState<string | null>(null);
  const [loadingConfig, setLoadingConfig] = useState(true);
  const [loadingCleaner, setLoadingCleaner] = useState(true);
  const [error, setError] = useState('');
  const [lastUpdated, setLastUpdated] = useState('');

  const loadConfig = React.useCallback(async () => {
    setLoadingConfig(true);
    try {
      const [cfgRes, sumRes] = await Promise.all([apiFetch('/api/config'), apiFetch('/api/config/summary')]);
      const cfg = await cfgRes.json();
      const sum = await sumRes.json();
      if (cfg?.ok) {
        setConfigText(cfg.content || '');
        setConfigPath(cfg.path || '');
      } else {
        setConfigText(String(cfg?.error || 'failed'));
      }
      if (sum?.ok) setConfigSections(sum.sections || []);
      setLastUpdated(new Date().toLocaleTimeString());
      setError('');
    } catch (err: any) {
      setConfigText(String(err?.message || err));
      setError(String(err?.message || err));
    } finally {
      setLoadingConfig(false);
    }
  }, []);

  const loadCleanerSpec = React.useCallback(async () => {
    setLoadingCleaner(true);
    try {
      const [specRes, catRes] = await Promise.all([apiFetch('/api/cleaner/spec'), apiFetch('/api/cleaner/spec/summary')]);
      const spec = await specRes.json();
      const cat = await catRes.json();
      if (spec?.ok) {
        setCleanerText(spec.content || '');
        setCleanerPath(spec.path || '');
      } else {
        setCleanerText(String(spec?.error || 'failed'));
      }
      if (cat?.ok) setCleanerCategories(cat.categories || []);
      setLastUpdated(new Date().toLocaleTimeString());
      setError('');
    } catch (err: any) {
      setCleanerText(String(err?.message || err));
      setError(String(err?.message || err));
    } finally {
      setLoadingCleaner(false);
    }
  }, []);

  useEffect(() => {
    loadConfig();
    loadCleanerSpec();
  }, [loadConfig, loadCleanerSpec]);

  const saveConfig = async () => {
    setSaving(true);
    try {
      const r = await apiFetch('/api/config/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: configPath, content: configText })
      });
      const j = await r.json();
      if (!r.ok || !j?.ok) {
        setMessage(`Save failed: ${j?.error || 'unknown error'}`);
        setError(`Save failed: ${j?.error || 'unknown error'}`);
      } else {
        setMessage(`Config saved: ${j.path}`);
        setError('');
        setLastUpdated(new Date().toLocaleTimeString());
      }
    } catch (err: any) {
      setMessage(`Save failed: ${String(err?.message || err)}`);
      setError(String(err?.message || err));
    } finally {
      setSaving(false);
    }
  };

  const generateReport = async () => {
    setReportPath('generating...');
    try {
      const r = await apiFetch('/api/report/generate', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ engine: 'advance' }) });
      const j = await r.json();
      if (j?.ok) {
        setReportPath(j.path);
        setError('');
      } else {
        setReportPath('failed');
        setError(String(j?.error || 'report generation failed'));
      }
    } catch (err: any) {
      setReportPath(String(err?.message || err));
      setError(String(err?.message || err));
    }
  };

  const cleanerProfiles = useMemo(() => {
    const labels = ['QUICK CLEAN', 'STANDARD CLEAN', 'DEEP CLEAN', 'AGGRESSIVE CLEAN', 'CUSTOM CLEAN'];
    return labels.map((label) => ({ label, enabled: cleanerText.toUpperCase().includes(label) }));
  }, [cleanerText]);

  const openUpdatePage = async () => {
    if (!neo?.openReleasesPage) {
      window.open('https://github.com/NeoOptimize/NeoOptimize/releases', '_blank');
      return;
    }
    await neo.openReleasesPage();
  };

  return (
    <div className="space-y-4">
      <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>$</span>
        <span>nano config.txt && load advance cleaner engine.txt</span>
        <span style={{ color: 'var(--ansi-cyan)' }}>{lastUpdated ? `updated ${lastUpdated}` : ''}</span>
      </div>

      {(loadingConfig || loadingCleaner || error || message) && (
        <div className="px-3 py-2 text-xs border font-mono" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)', color: error ? 'var(--ansi-red)' : 'var(--text-primary)' }}>
          {(loadingConfig || loadingCleaner) ? 'Loading config and cleaner spec...' : error || message}
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="flex items-center gap-2 mb-3 text-xs font-bold" style={{ color: 'var(--ansi-yellow)' }}><Zap size={14} /> CONFIG SECTIONS</div>
          <div className="space-y-2 max-h-48 overflow-y-auto text-xs">
            {configSections.map((s) => (
              <div key={s} className="p-2 border" style={{ borderColor: 'var(--border-color)', color: 'var(--text-primary)' }}>{s}</div>
            ))}
            {configSections.length === 0 && <div style={{ color: 'var(--text-muted)' }}>No section parsed</div>}
          </div>
        </div>

        <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="flex items-center gap-2 mb-3 text-xs font-bold" style={{ color: 'var(--ansi-blue)' }}><Package size={14} /> CLEANER PROFILES FROM SPEC</div>
          <div className="space-y-2 text-xs">
            {cleanerProfiles.map((p) => (
              <div key={p.label} className="flex justify-between p-2 border" style={{ borderColor: 'var(--border-color)' }}>
                <span style={{ color: 'var(--text-primary)' }}>{p.label}</span>
                <span style={{ color: p.enabled ? 'var(--ansi-green)' : 'var(--ansi-red)' }}>{p.enabled ? 'READY' : 'MISSING'}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="flex items-center justify-between mb-2">
          <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-green)' }}><Terminal size={14} /> CONFIG FILE EDITOR</div>
          <div className="flex gap-2">
            <button onClick={loadConfig} className="px-2 py-1 text-[10px] border" style={{ borderColor: 'var(--ansi-blue)', color: 'var(--ansi-blue)' }}>RELOAD</button>
            <button onClick={saveConfig} disabled={saving} className="px-2 py-1 text-[10px] border" style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}>{saving ? 'SAVING...' : 'SAVE'}</button>
          </div>
        </div>
        <div className="text-[11px] mb-2" style={{ color: 'var(--text-muted)' }}>Path: <span style={{ color: 'var(--ansi-cyan)' }}>{configPath || 'n/a'}</span></div>
        <textarea value={configText} onChange={(e) => setConfigText(e.target.value)} className="w-full min-h-[280px] p-3 border font-mono text-xs outline-none" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--terminal-output-bg)', color: 'var(--text-primary)' }} />
      </div>

      <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="flex items-center justify-between mb-2">
          <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-cyan)' }}><FileText size={14} /> ADVANCE CLEANER ENGINE SPEC</div>
          <button onClick={loadCleanerSpec} className="px-2 py-1 text-[10px] border" style={{ borderColor: 'var(--ansi-cyan)', color: 'var(--ansi-cyan)' }}>RELOAD</button>
        </div>
        <div className="text-[11px] mb-2" style={{ color: 'var(--text-muted)' }}>Path: <span style={{ color: 'var(--ansi-cyan)' }}>{cleanerPath || 'n/a'}</span></div>
        <div className="text-[11px] mb-2" style={{ color: 'var(--text-muted)' }}>Categories: {cleanerCategories.length}</div>
        <pre className="p-3 rounded text-xs font-mono" style={{ backgroundColor: 'var(--terminal-output-bg)', whiteSpace: 'pre-wrap', maxHeight: '300px', overflow: 'auto', color: 'var(--text-primary)' }}>{cleanerText}</pre>
      </div>

      <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="flex items-center gap-2 mb-2 text-xs font-bold" style={{ color: 'var(--ansi-green)' }}><Settings size={14} /> REPORTS</div>
        <button onClick={generateReport} className="px-3 py-1.5 mr-2 text-xs font-bold border" style={{ borderColor: 'var(--ansi-green)', color: 'var(--ansi-green)' }}>GENERATE REPORT</button>
        {reportPath && <span className="text-[12px]" style={{ color: 'var(--text-primary)' }}>{reportPath}</span>}
      </div>

      <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="flex items-center gap-2 mb-2 text-xs font-bold" style={{ color: 'var(--ansi-yellow)' }}><Settings size={14} /> APP UPDATE (GITHUB)</div>
        <div className="text-[11px] mb-2" style={{ color: 'var(--text-muted)' }}>
          Satu link update resmi: <span style={{ color: 'var(--ansi-cyan)' }}>https://github.com/NeoOptimize/NeoOptimize/releases</span>
        </div>
        <button onClick={openUpdatePage} className="px-3 py-1 text-[10px] border" style={{ borderColor: 'var(--ansi-blue)', color: 'var(--ansi-blue)' }}>
          OPEN UPDATE LINK
        </button>
      </div>
    </div>
  );
}
