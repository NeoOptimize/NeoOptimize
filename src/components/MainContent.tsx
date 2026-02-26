import React, { useEffect, useState, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { DashboardPage } from './pages/DashboardPage';
import { ProcessesPage } from './pages/ProcessesPage';
import { NetworkPage } from './pages/NetworkPage';
import { StoragePage } from './pages/StoragePage';
import { ConfigPage } from './pages/ConfigPage';
import { LogsPage } from './pages/LogsPage';
import { SecurityPage } from './pages/SecurityPage';
import { SchedulerPage } from './pages/SchedulerPage';
// ─── Types ───────────────────────────────────────────────────────────────────
type LogLevel = 'ok' | 'warn' | 'error' | 'info';
interface LogEntry {
  id: number;
  time: string;
  level: LogLevel;
  message: string;
}
const initialLogs: LogEntry[] = [
{
  id: 1,
  time: '04:22:31',
  level: 'info',
  message: 'neooptimize daemon started — PID 1337'
},
{
  id: 2,
  time: '04:22:38',
  level: 'ok',
  message: 'Loaded config: /etc/neooptimize/system.conf'
},
{
  id: 3,
  time: '04:22:41',
  level: 'error',
  message: 'Disk optimization failed — retrying in 30s'
},
{
  id: 4,
  time: '04:22:58',
  level: 'ok',
  message: 'Network latency reduced → 12ms'
},
{
  id: 5,
  time: '04:23:05',
  level: 'warn',
  message: 'Memory threshold at 67% — monitoring'
}];

const newLogPool: Omit<LogEntry, 'id' | 'time'>[] = [
{
  level: 'ok',
  message: 'Heartbeat check passed — all nodes responsive'
},
{
  level: 'warn',
  message: 'CPU spike detected on node-03 — throttling'
},
{
  level: 'ok',
  message: 'Index rebuilt — query time −18%'
},
{
  level: 'error',
  message: 'Connection pool exhausted — scaling up'
},
{
  level: 'info',
  message: 'Backup snapshot initiated'
}];

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
  const [logs, setLogs] = useState<LogEntry[]>(initialLogs);
  const [nextId, setNextId] = useState(initialLogs.length + 1);
  const [filter, setFilter] = useState<LogLevel | 'all'>('all');
  const logRef = useRef<HTMLDivElement>(null);
  const nextIdRef = useRef(nextId);
  nextIdRef.current = nextId;
  useEffect(() => {
    const id = setInterval(() => {
      const entry = newLogPool[Math.floor(Math.random() * newLogPool.length)];
      const now = new Date();
      const time = now.toLocaleTimeString('en-US', {
        hour12: false
      });
      setLogs((prev) => [
      ...prev.slice(-50),
      {
        id: nextIdRef.current,
        time,
        ...entry
      }]
      );
      setNextId((n) => n + 1);
    }, 3200);
    return () => clearInterval(id);
  }, []);
  useEffect(() => {
    if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
  }, [logs]);
  const filtered =
  filter === 'all' ? logs : logs.filter((l) => l.level === filter);
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
        <AnimatePresence initial={false}>
          {filtered.map((log) => {
            const s = levelStyle[log.level];
            return (
              <motion.div
                key={log.id}
                initial={{
                  opacity: 0,
                  y: 4
                }}
                animate={{
                  opacity: 1,
                  y: 0
                }}
                transition={{
                  duration: 0.18
                }}
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
              </motion.div>);

          })}
        </AnimatePresence>
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