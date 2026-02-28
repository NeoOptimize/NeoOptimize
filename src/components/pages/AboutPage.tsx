import { useEffect, useState } from 'react';
import { Info, Shield, Wrench } from 'lucide-react';
import { apiFetch } from '../../lib/api';

type EngineInfo = {
  recommended: 'kicomav' | 'clamav' | null;
  kicomav?: { available: boolean; root?: string };
  clamav?: { available: boolean; root?: string; binary?: string | null };
};

export function AboutPage() {
  const [engines, setEngines] = useState<EngineInfo | null>(null);
  const [version, setVersion] = useState('0.0.1');

  useEffect(() => {
    const neo = (window as any)?.neo;
    try {
      if (neo?.version) setVersion(String(neo.version()));
    } catch {}
    apiFetch('/api/security/engines')
      .then((r) => r.json())
      .then((j) => {
        if (j?.ok) setEngines(j);
      })
      .catch(() => {});
  }, []);

  return (
    <div className="space-y-4">
      <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>$</span>
        <span>neooptimize --about --developer</span>
      </div>

      <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="flex items-center gap-2 text-xs font-bold mb-2" style={{ color: 'var(--ansi-cyan)' }}>
          <Info size={14} />
          ABOUT NEOOPTIMIZE
        </div>
        <div className="text-xs space-y-1">
          <div style={{ color: 'var(--text-primary)' }}>Version: {version}</div>
          <div style={{ color: 'var(--text-primary)' }}>Build target: Windows Desktop</div>
          <div style={{ color: 'var(--text-muted)' }}>Mode default: SAFE dry-run, APPLY by explicit toggle.</div>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="flex items-center gap-2 text-xs font-bold mb-2" style={{ color: 'var(--ansi-green)' }}>
            <Wrench size={14} />
            DEVELOPER
          </div>
          <div className="text-xs space-y-1">
            <div style={{ color: 'var(--text-primary)' }}>Nama: Sigit profesional IT</div>
            <div style={{ color: 'var(--text-primary)' }}>WhatsApp: 087889911030</div>
            <div style={{ color: 'var(--text-primary)' }}>Email: neooptimizeofficial@gmail.com</div>
            <div className="pt-1">
              <a href="https://buymeacoffee.com/nol.eight" target="_blank" rel="noreferrer" style={{ color: 'var(--ansi-blue)' }}>BuyMeCoffe</a>
              {' | '}
              <a href="https://saweria.co/dtechtive" target="_blank" rel="noreferrer" style={{ color: 'var(--ansi-blue)' }}>Saweria</a>
              {' | '}
              <a href="https://ik.imagekit.io/dtechtive/Dana" target="_blank" rel="noreferrer" style={{ color: 'var(--ansi-blue)' }}>Dana</a>
            </div>
          </div>
        </div>

        <div className="border p-4" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
          <div className="flex items-center gap-2 text-xs font-bold mb-2" style={{ color: 'var(--ansi-yellow)' }}>
            <Shield size={14} />
            SECURITY ENGINE
          </div>
          <div className="text-xs space-y-1">
            <div style={{ color: 'var(--text-primary)' }}>Recommended: {engines?.recommended || 'none'}</div>
            <div style={{ color: engines?.kicomav?.available ? 'var(--ansi-green)' : 'var(--ansi-red)' }}>
              KicomAV: {engines?.kicomav?.available ? 'READY' : 'NOT READY'}
            </div>
            <div style={{ color: engines?.clamav?.available ? 'var(--ansi-green)' : 'var(--ansi-red)' }}>
              ClamAV: {engines?.clamav?.available ? 'READY' : 'SOURCE ONLY / NOT READY'}
            </div>
            {engines?.clamav?.binary && (
              <div className="text-[10px]" style={{ color: 'var(--text-muted)' }}>
                Binary: {engines.clamav.binary}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
