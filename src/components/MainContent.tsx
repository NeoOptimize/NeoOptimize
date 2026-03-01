import { useEffect, useState, useRef } from 'react';
import { useSystemStats } from '../hooks/SystemStatsContext';
import { DashboardPage } from './pages/DashboardPage';
import { ProcessesPage } from './pages/ProcessesPage';
import { NetworkPage } from './pages/NetworkPage';
import { StoragePage } from './pages/StoragePage';
import { ConfigPage } from './pages/ConfigPage';
import { LogsPage } from './pages/LogsPage';
import { SecurityPage } from './pages/SecurityPage';
import { SchedulerPage } from './pages/SchedulerPage';
import { AboutPage } from './pages/AboutPage';
// ─── Types ───────────────────────────────────────────────────────────────────
type LogLevel = 'ok' | 'warn' | 'error' | 'info';

const levelStyle: Record<
  LogLevel,
  {
    color: string;
    prefix: string;
    badge: string;
  }> =
{
  ok: {
    color: 'var(--ansi-green)',
    prefix: '✓',
    badge: 'OK  '
  },
  warn: {
    color: 'var(--ansi-yellow)',
    prefix: '⚠',
    badge: 'WARN'
  },
  error: {
    color: 'var(--ansi-red)',
    prefix: '✗',
    badge: 'ERR '
  },
  info: {
    color: 'var(--ansi-blue)',
    prefix: 'i',
    badge: 'INFO'
  }
};
// ─── Log Sidebar ──────────────────────────────────────────────────────────────
function LogSidebar() {
  const { logs, clearLogs } = useSystemStats();
  const [filter, setFilter] = useState<LogLevel | 'all'>('all');
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
        const order: Array<LogLevel | 'all'> = ['all', 'ok', 'warn', 'error', 'info'];
        const idx = order.indexOf(filter);
        setFilter(order[(idx + 1) % order.length]);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [clearLogs, filter]);

  const filtered = filter === 'all' ? logs : logs.filter((l) => l.level === filter);
  const counts = {
    all: logs.length,
    ok: logs.filter((l) => l.level === 'ok').length,
    warn: logs.filter((l) => l.level === 'warn').length,
    error: logs.filter((l) => l.level === 'error').length,
    info: logs.filter((l) => l.level === 'info').length
  };
  const filterOptions: {
    key: LogLevel | 'all';
    label: string;
    color: string;
  }[] = [
  {
    key: 'all',
    label: 'ALL',
    color: 'var(--text-muted)'
  },
  {
    key: 'ok',
    label: 'OK',
    color: 'var(--ansi-green)'
  },
  {
    key: 'warn',
    label: 'WARN',
    color: 'var(--ansi-yellow)'
  },
  {
    key: 'error',
    label: 'ERR',
    color: 'var(--ansi-red)'
  },
  {
    key: 'info',
    label: 'INFO',
    color: 'var(--ansi-blue)'
  }];

  return (
    <div
      className="w-72 shrink-0 flex flex-col font-mono text-xs"
      style={{
        backgroundColor: 'var(--terminal-output-bg)',
        border: '1px solid var(--border-color)',
        height: 'calc(100vh - 3.5rem)'
      }}>

      <div
        className="px-3 py-2 shrink-0"
        style={{
          borderBottom: '1px solid var(--border-color)',
          backgroundColor: 'var(--bg-tertiary)'
        }}>

        <div className="flex items-center justify-between mb-2">
          <span
            style={{
              color: 'var(--text-muted)'
            }}>

            <span
              style={{
                color: 'var(--ansi-green)'
              }}>

              $
            </span>{' '}
            tail -f /var/log/neooptimize.log
          </span>
          <span
            className="text-[9px] px-1.5 py-0.5 font-bold"
            style={{
              backgroundColor: 'var(--ansi-green)',
              color: '#000'
            }}>

            LIVE
          </span>
        </div>
        <div className="flex items-center gap-1">
          {filterOptions.map((opt) =>
          <button
            key={opt.key}
            onClick={() => setFilter(opt.key)}
            className="px-1.5 py-0.5 text-[9px] font-bold transition-all duration-100"
            style={{
              backgroundColor: filter === opt.key ? opt.color : 'transparent',
              color: filter === opt.key ? '#000' : opt.color,
              border: `1px solid ${filter === opt.key ? opt.color : 'var(--border-color)'}`
            }}>

              {opt.label}
              <span
              style={{
                color: filter === opt.key ? '#000' : 'var(--text-muted)',
                marginLeft: '2px'
              }}>

                {counts[opt.key]}
              </span>
            </button>
          )}
        </div>
      </div>

      <div ref={logRef} className="flex-1 overflow-y-auto p-2 space-y-1">
        {filtered.map((log) => {
          const s = levelStyle[log.level];
          return (
            <div
              key={log.id}
              className="flex items-start gap-1.5 leading-relaxed">

              <span
                style={{
                  color: 'var(--text-muted)',
                  flexShrink: 0,
                  fontSize: '9px'
                }}>

                {log.time}
              </span>
              <span
                className="text-[9px] font-bold px-1 shrink-0"
                style={{
                  backgroundColor: s.color + '22',
                  color: s.color,
                  border: `1px solid ${s.color}44`
                }}>

                {s.badge}
              </span>
              <span
                style={{
                  color:
                  log.level === 'error' ? s.color : 'var(--text-primary)',
                  fontSize: '10px',
                  lineHeight: 1.4
                }}>

                {log.message}
              </span>
            </div>);

        })}
        <div
          className="flex items-center gap-1 mt-1"
          style={{
            color: 'var(--text-muted)'
          }}>

          <span
            style={{
              color: 'var(--ansi-green)'
            }}>

            {'>'}
          </span>
          <span
            className="cursor-blink"
            style={{
              color: 'var(--ansi-green)'
            }}>

            _
          </span>
        </div>
      </div>

      <div
        className="px-3 py-2 shrink-0 text-[9px]"
        style={{
          borderTop: '1px solid var(--border-color)',
          color: 'var(--text-muted)'
        }}>

        <div className="flex items-center justify-between">
          <span>{logs.length} events</span>
          <span>
            <span
              style={{
                color: 'var(--ansi-yellow)'
              }}>

              [c]
            </span>{' '}
            clear &nbsp;
            <span
              style={{
                color: 'var(--ansi-yellow)'
              }}>

              [f]
            </span>{' '}
            filter
          </span>
        </div>
      </div>
    </div>);

}
// ─── Main Content ─────────────────────────────────────────────────────────────
interface MainContentProps {
  activeSection: number;
}
export function MainContent({ activeSection }: MainContentProps) {
  return (
    <div
      className="flex-1 md:ml-64 flex min-h-[calc(100vh-3.5rem)] font-mono"
      style={{
        backgroundColor: 'var(--bg-primary)'
      }}>

      {/* ── Main scrollable area ── */}
      <div className="flex-1 overflow-y-auto p-4">
        <div className="max-w-4xl mx-auto">
          {activeSection === 1 && <DashboardPage />}
          {activeSection === 2 && <ProcessesPage />}
          {activeSection === 3 && <NetworkPage />}
          {activeSection === 4 && <StoragePage />}
          {activeSection === 5 && <ConfigPage />}
          {activeSection === 6 && <LogsPage />}
          {activeSection === 7 && <SecurityPage />}
          {activeSection === 8 && <SchedulerPage />}
          {activeSection === 9 && <AboutPage />}
        </div>
      </div>

      {/* ── Right log sidebar ── */}
      <div
        className="hidden lg:flex sticky top-0 self-start"
        style={{
          height: 'calc(100vh - 3.5rem)'
        }}>

        <LogSidebar />
      </div>
    </div>);

}
