import { useEffect, useMemo, useRef, useState } from 'react';
import { useSystemStats } from '../hooks/SystemStatsContext';
import { AdaptiveDashboardPage } from './pages/AdaptiveDashboardPage';
import { CleanerPage } from './pages/CleanerPage';
import { OptimizerPage } from './pages/OptimizerPage';
import { SystemToolsPage } from './pages/SystemToolsPage';
import { SettingsPage } from './pages/SettingsPage';
import { SupportPage } from './pages/SupportPage';
import { SecurityPage } from './advanced/SecurityPage';
import { SectionId, UIMode } from '../types/ui';

type LogLevel = 'ok' | 'warn' | 'error' | 'info';
type DomainFilter = 'all' | 'cleaner' | 'optimizer' | 'security' | 'system';

const levelStyle: Record<LogLevel, { color: string; badge: string }> = {
  ok: { color: 'var(--ansi-green)', badge: 'OK  ' },
  warn: { color: 'var(--ansi-yellow)', badge: 'WARN' },
  error: { color: 'var(--ansi-red)', badge: 'ERR ' },
  info: { color: 'var(--ansi-blue)', badge: 'INFO' }
};

function detectDomain(message: string): Exclude<DomainFilter, 'all'> {
  const text = String(message || '').toLowerCase();
  if (
    text.includes('security') ||
    text.includes('clam') ||
    text.includes('kico') ||
    text.includes('firewall') ||
    text.includes('scan')
  ) return 'security';
  if (
    text.includes('clean') ||
    text.includes('registry') ||
    text.includes('backup') ||
    text.includes('junk')
  ) return 'cleaner';
  if (
    text.includes('optimize') ||
    text.includes('ram') ||
    text.includes('dns') ||
    text.includes('network')
  ) return 'optimizer';
  return 'system';
}

function LogSidebar() {
  const { logs, clearLogs } = useSystemStats();
  const [levelFilter, setLevelFilter] = useState<LogLevel | 'all'>('all');
  const [domainFilter, setDomainFilter] = useState<DomainFilter>('all');
  const logRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
  }, [logs]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement).tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      if (e.key.toLowerCase() === 'c') clearLogs();
      if (e.key.toLowerCase() === 'f') {
        const next: DomainFilter[] = ['all', 'cleaner', 'optimizer', 'security', 'system'];
        const current = next.indexOf(domainFilter);
        setDomainFilter(next[(current + 1) % next.length]);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [clearLogs, domainFilter]);

  const logsWithDomain = useMemo(() => logs.map((log) => ({ ...log, domain: detectDomain(log.message) })), [logs]);

  const filtered = logsWithDomain.filter((log) => {
    if (levelFilter !== 'all' && log.level !== levelFilter) return false;
    if (domainFilter !== 'all' && log.domain !== domainFilter) return false;
    return true;
  });

  const domainCounts: Record<DomainFilter, number> = {
    all: logsWithDomain.length,
    cleaner: logsWithDomain.filter((log) => log.domain === 'cleaner').length,
    optimizer: logsWithDomain.filter((log) => log.domain === 'optimizer').length,
    security: logsWithDomain.filter((log) => log.domain === 'security').length,
    system: logsWithDomain.filter((log) => log.domain === 'system').length
  };

  const levelOptions: Array<LogLevel | 'all'> = ['all', 'ok', 'warn', 'error', 'info'];
  const domainOptions: DomainFilter[] = ['all', 'cleaner', 'optimizer', 'security', 'system'];

  return (
    <div
      className="w-80 shrink-0 flex flex-col font-mono text-xs"
      style={{
        backgroundColor: 'var(--terminal-output-bg)',
        border: '1px solid var(--border-color)',
        height: 'calc(100vh - 3.5rem)'
      }}
    >
      <div
        className="px-3 py-2 shrink-0"
        style={{
          borderBottom: '1px solid var(--border-color)',
          backgroundColor: 'var(--bg-tertiary)'
        }}
      >
        <div className="flex items-center justify-between mb-2">
          <span style={{ color: 'var(--text-muted)' }}>
            <span style={{ color: 'var(--ansi-green)' }}>$</span> log_center --tail --filter
          </span>
          <span
            className="text-[9px] px-1.5 py-0.5 font-bold"
            style={{ backgroundColor: 'var(--ansi-green)', color: '#000' }}
          >
            LIVE
          </span>
        </div>
        <div className="flex flex-wrap items-center gap-1 mb-2">
          {levelOptions.map((opt) => (
            <button
              key={opt}
              onClick={() => setLevelFilter(opt)}
              className="px-1.5 py-0.5 text-[9px] font-bold border"
              style={{
                borderColor: levelFilter === opt ? 'var(--ansi-cyan)' : 'var(--border-color)',
                color: levelFilter === opt ? 'var(--ansi-cyan)' : 'var(--text-muted)'
              }}
            >
              {String(opt).toUpperCase()}
            </button>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-1">
          {domainOptions.map((opt) => (
            <button
              key={opt}
              onClick={() => setDomainFilter(opt)}
              className="px-1.5 py-0.5 text-[9px] font-bold border"
              style={{
                borderColor: domainFilter === opt ? 'var(--ansi-yellow)' : 'var(--border-color)',
                color: domainFilter === opt ? 'var(--ansi-yellow)' : 'var(--text-muted)'
              }}
            >
              {opt.toUpperCase()} {domainCounts[opt]}
            </button>
          ))}
        </div>
      </div>

      <div ref={logRef} className="flex-1 overflow-y-auto p-2 space-y-1">
        {filtered.map((log) => {
          const style = levelStyle[log.level];
          return (
            <div key={log.id} className="flex items-start gap-1.5 leading-relaxed">
              <span style={{ color: 'var(--text-muted)', flexShrink: 0, fontSize: '9px' }}>{log.time}</span>
              <span
                className="text-[9px] font-bold px-1 shrink-0"
                style={{
                  backgroundColor: `${style.color}22`,
                  color: style.color,
                  border: `1px solid ${style.color}44`
                }}
              >
                {style.badge}
              </span>
              <span
                className="text-[9px] font-bold px-1 shrink-0"
                style={{
                  backgroundColor: 'rgba(255,255,255,0.04)',
                  color: 'var(--text-muted)',
                  border: '1px solid var(--border-color)'
                }}
              >
                {log.domain.toUpperCase()}
              </span>
              <span style={{ color: 'var(--text-primary)', fontSize: '10px', lineHeight: 1.4 }}>{log.message}</span>
            </div>
          );
        })}
      </div>

      <div
        className="px-3 py-2 shrink-0 text-[9px]"
        style={{
          borderTop: '1px solid var(--border-color)',
          color: 'var(--text-muted)'
        }}
      >
        <div className="flex items-center justify-between">
          <span>{filtered.length}/{logs.length} events</span>
          <span>
            <span style={{ color: 'var(--ansi-yellow)' }}>[c]</span> clear
            <span style={{ color: 'var(--ansi-yellow)', marginLeft: 8 }}>[f]</span> source
          </span>
        </div>
      </div>
    </div>
  );
}

interface MainContentProps {
  activeSection: SectionId;
  uiMode: UIMode;
  onModeChange: (mode: UIMode) => void;
}

export function MainContent({ activeSection, uiMode, onModeChange }: MainContentProps) {
  const { securityAvailable } = useSystemStats();

  const content = (() => {
    if (activeSection === 'dashboard') return <AdaptiveDashboardPage />;
    if (activeSection === 'cleaner') return <CleanerPage uiMode={uiMode} />;
    if (activeSection === 'optimizer') return <OptimizerPage uiMode={uiMode} />;
    if (activeSection === 'system-tools') return <SystemToolsPage uiMode={uiMode} />;
    if (activeSection === 'security') {
      if (!securityAvailable) {
        return (
          <div
            className="px-3 py-2 text-xs border"
            style={{
              borderColor: 'var(--border-color)',
              backgroundColor: 'var(--bg-tertiary)',
              color: 'var(--ansi-yellow)'
            }}
          >
            Security module unavailable on this device/runtime.
          </div>
        );
      }
      return <SecurityPage />;
    }
    if (activeSection === 'settings') return <SettingsPage uiMode={uiMode} onModeChange={onModeChange} />;
    return <SupportPage />;
  })();

  return (
    <div
      className="flex-1 md:ml-64 flex min-h-[calc(100vh-3.5rem)] font-mono"
      style={{ backgroundColor: 'var(--bg-primary)' }}
    >
      <div className="flex-1 overflow-y-auto p-4">
        <div className="max-w-5xl mx-auto">{content}</div>
      </div>
      <div className="hidden xl:flex sticky top-0 self-start" style={{ height: 'calc(100vh - 3.5rem)' }}>
        <LogSidebar />
      </div>
    </div>
  );
}
