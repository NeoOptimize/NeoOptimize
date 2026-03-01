import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { apiFetch } from '../lib/api';

type Metrics = { cpu: number; mem: number; net: number };
type LogLevel = 'ok' | 'warn' | 'error' | 'info';
type LogEntry = { id: number; time: string; level: LogLevel; message: string };

type ContextValue = {
  metrics: Metrics;
  clock: string;
  uptime: string;
  loadAvg: number[];
  tasks: number;
  logs: LogEntry[];
  kernel: string;
  clearLogs: () => void;
};

const SystemStatsContext = createContext<ContextValue | null>(null);

function toLogLevel(level: string): LogLevel {
  const v = String(level || '').toLowerCase();
  if (v === 'error' || v === 'err') return 'error';
  if (v === 'warn' || v === 'warning') return 'warn';
  if (v === 'ok' || v === 'success') return 'ok';
  return 'info';
}

function formatUptime(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds || 0));
  const h = String(Math.floor(s / 3600)).padStart(2, '0');
  const m = String(Math.floor((s % 3600) / 60)).padStart(2, '0');
  const sec = String(s % 60).padStart(2, '0');
  return `${h}:${m}:${sec}`;
}

export function SystemStatsProvider({ children }: { children: React.ReactNode }) {
  const [metrics, setMetrics] = useState<Metrics>({ cpu: 0, mem: 0, net: 0 });
  const [clock, setClock] = useState('');
  const [uptime, setUptime] = useState('00:00:00');
  const [loadAvg, setLoadAvg] = useState<number[]>([0, 0, 0]);
  const [tasks, setTasks] = useState(0);
  const [kernel, setKernel] = useState('unknown');
  const [logs, setLogs] = useState<LogEntry[]>([]);

  useEffect(() => {
    const tickClock = () => {
      setClock(new Date().toLocaleTimeString('en-US', { hour12: false }));
    };
    tickClock();
    const clockTimer = setInterval(tickClock, 1000);
    return () => clearInterval(clockTimer);
  }, []);

  useEffect(() => {
    let mounted = true;
    let systemTimer: ReturnType<typeof setTimeout> | null = null;
    let logTimer: ReturnType<typeof setTimeout> | null = null;

    const scheduleSystem = (ms: number) => {
      if (systemTimer) clearTimeout(systemTimer);
      systemTimer = setTimeout(refreshSystem, ms);
    };
    const scheduleLogs = (ms: number) => {
      if (logTimer) clearTimeout(logTimer);
      logTimer = setTimeout(refreshLogs, ms);
    };

    const refreshSystem = async () => {
      try {
        const [ovRes, netRes] = await Promise.all([apiFetch('/api/system/overview'), apiFetch('/api/network/stats')]);
        const ov = await ovRes.json();
        const net = await netRes.json();
        if (!mounted) return;
        if (ov?.ok && ov.system) {
          setMetrics((prev) => ({
            cpu: Number(ov.system.cpuPercent || 0),
            mem: Number(ov.system.memPercent || 0),
            net: Number(net?.latencyMs ?? prev.net ?? 0)
          }));
          setUptime(formatUptime(Number(ov.system.uptimeSec || 0)));
          setLoadAvg(Array.isArray(ov.system.loadAvg) ? ov.system.loadAvg : [0, 0, 0]);
          setTasks(Number(ov.tasks || 0));
          setKernel(String(ov.system.kernel || 'unknown'));
        } else if (net?.ok) {
          setMetrics((prev) => ({ ...prev, net: Number(net.latencyMs || 0) }));
        }
      } catch {}
      if (!mounted) return;
      const hidden = typeof document !== 'undefined' && document.visibilityState === 'hidden';
      scheduleSystem(hidden ? 12000 : 4000);
    };

    const refreshLogs = async () => {
      try {
        const r = await apiFetch('/api/logs?limit=80');
        const j = await r.json();
        if (!mounted || !j?.ok) return;
        const mapped = (j.logs || []).slice(-80).map((l: any, i: number) => ({
          id: i + 1,
          time: l.time ? new Date(l.time).toLocaleTimeString('en-US', { hour12: false }) : '--:--:--',
          level: toLogLevel(l.level),
          message: l.engine ? `[${String(l.engine).toUpperCase()}] ${l.message || ''}` : (l.message || '')
        }));
        setLogs(mapped);
      } catch {}
      if (!mounted) return;
      const hidden = typeof document !== 'undefined' && document.visibilityState === 'hidden';
      scheduleLogs(hidden ? 15000 : 5000);
    };

    refreshSystem();
    refreshLogs();
    return () => {
      mounted = false;
      if (systemTimer) clearTimeout(systemTimer);
      if (logTimer) clearTimeout(logTimer);
    };
  }, []);

  const value = useMemo(() => ({
    metrics,
    clock,
    uptime,
    loadAvg,
    tasks,
    logs,
    kernel,
    clearLogs: () => setLogs([])
  }), [metrics, clock, uptime, loadAvg, tasks, logs, kernel]);

  return <SystemStatsContext.Provider value={value}>{children}</SystemStatsContext.Provider>;
}

export function useSystemStats() {
  const ctx = useContext(SystemStatsContext);
  if (!ctx) throw new Error('useSystemStats must be used within SystemStatsProvider');
  return ctx;
}

export default SystemStatsContext;
