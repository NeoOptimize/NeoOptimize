import React, { useEffect, useState } from 'react';
import { ThemeToggle } from './ThemeToggle';
import { TypingText } from './TypingText';
interface Metric {
  label: string;
  value: string;
  color?: string;
}
function useSystemMetrics() {
  const [metrics, setMetrics] = useState({
    cpu: 34,
    mem: 67,
    net: 12
  });
  const [uptime, setUptime] = useState(0);
  const [clock, setClock] = useState('');
  useEffect(() => {
    const start = Date.now();
    const tick = () => {
      const now = new Date();
      setClock(
        now.toLocaleTimeString('en-US', {
          hour12: false
        })
      );
      setUptime(Math.floor((Date.now() - start) / 1000));
      setMetrics((prev) => ({
        cpu: Math.max(5, Math.min(95, prev.cpu + (Math.random() - 0.5) * 6)),
        mem: Math.max(20, Math.min(90, prev.mem + (Math.random() - 0.5) * 3)),
        net: Math.max(1, Math.min(99, prev.net + (Math.random() - 0.5) * 4))
      }));
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);
  const fmtUptime = (s: number) => {
    const h = String(Math.floor(s / 3600)).padStart(2, '0');
    const m = String(Math.floor(s % 3600 / 60)).padStart(2, '0');
    const sec = String(s % 60).padStart(2, '0');
    return `${h}:${m}:${sec}`;
  };
  return {
    metrics,
    clock,
    uptime: fmtUptime(uptime)
  };
}
const navItems = [
{
  id: 1,
  label: 'Dashboard'
},
{
  id: 2,
  label: 'Processes'
},
{
  id: 3,
  label: 'Network'
},
{
  id: 4,
  label: 'Storage'
},
{
  id: 5,
  label: 'Config'
}];

export function TerminalHeader() {
  const { metrics, clock, uptime } = useSystemMetrics();
  const [activeNav, setActiveNav] = useState(1);
  // Global keyboard nav: press 1-5 to switch sections
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement).tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      const n = parseInt(e.key);
      if (n >= 1 && n <= 5) setActiveNav(n);
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, []);
  const cpuColor =
  metrics.cpu > 80 ?
  'var(--status-error)' :
  metrics.cpu > 60 ?
  'var(--status-warning)' :
  'var(--accent-primary)';
  const memColor =
  metrics.mem > 80 ?
  'var(--status-error)' :
  metrics.mem > 60 ?
  'var(--status-warning)' :
  'var(--accent-primary)';
  return (
    <header
      className="h-14 fixed top-0 left-0 right-0 z-50 flex items-center justify-between px-4 select-none"
      style={{
        backgroundColor: 'var(--bg-secondary)',
        borderBottom: '1px solid var(--border-color)',
        boxShadow:
        '0 1px 30px rgba(0,255,65,0.2), 0 0 60px rgba(0,255,65,0.05)'
      }}>

      {/* Left: Window Controls + Prompt */}
      <div className="flex items-center gap-4">
        {/* Window Dots */}
        <div className="flex items-center gap-1.5">
          <div className="w-3 h-3 rounded-full bg-[#ff5f56] border border-[#e0443e]" />
          <div className="w-3 h-3 rounded-full bg-[#ffbd2e] border border-[#dea123]" />
          <div className="w-3 h-3 rounded-full bg-[#27c93f] border border-[#1aab29]" />
        </div>

        {/* Terminal Prompt */}
        <div className="hidden lg:flex items-center gap-2 text-sm font-mono ml-2">
          <span
            className="matrix-glow"
            style={{
              color: 'var(--ansi-green)',
              fontWeight: 'bold'
            }}>

            root@neooptimize:~$
          </span>
          <TypingText
            text="./init_dashboard.sh --verbose"
            speed={40}
            delay={500}
            className="text-gray-400"
            cursor={false} />

          <span
            className="cursor-blink matrix-glow"
            style={{
              color: 'var(--ansi-green)'
            }}>

            █
          </span>
        </div>
      </div>

      {/* Center: Numbered Nav */}
      <div className="hidden md:flex items-center gap-1 text-xs font-mono">
        {navItems.map((item) =>
        <button
          key={item.id}
          onClick={() => setActiveNav(item.id)}
          className="flex items-center gap-1.5 px-3 py-1.5 transition-colors"
          style={{
            backgroundColor:
            activeNav === item.id ? 'var(--accent-primary)' : 'transparent',
            color:
            activeNav === item.id ?
            'var(--bg-primary)' :
            'var(--text-primary)',
            fontWeight: activeNav === item.id ? 'bold' : 'normal'
          }}>

            <span
            style={{
              color:
              activeNav === item.id ?
              'var(--bg-primary)' :
              'var(--ansi-yellow)'
            }}>

              [{item.id}]
            </span>
            {item.label}
          </button>
        )}
      </div>

      {/* Right: Metrics + Theme */}
      <div className="flex items-center gap-4">
        <div className="hidden xl:flex items-center gap-3 text-xs font-mono">
          <MetricPill
            label="CPU"
            value={`${metrics.cpu.toFixed(0)}%`}
            color={cpuColor} />

          <MetricPill
            label="MEM"
            value={`${metrics.mem.toFixed(0)}%`}
            color={memColor} />

          <MetricPill
            label="NET"
            value={`${metrics.net.toFixed(0)}ms`}
            color="var(--status-info)" />

          <MetricPill label="UP" value={uptime} color="var(--text-secondary)" />
        </div>

        <ThemeToggle />
      </div>
    </header>);

}
function MetricPill({
  label,
  value,
  color




}: {label: string;value: string;color: string;}) {
  return (
    <div
      className="flex items-center gap-1.5 px-2 py-1"
      style={{
        border: '1px solid var(--border-color)',
        backgroundColor: 'rgba(0,0,0,0.2)'
      }}>

      <span
        style={{
          color: 'var(--text-muted)'
        }}>

        {label}:
      </span>
      <span
        style={{
          color,
          fontWeight: 600
        }}>

        {value}
      </span>
    </div>);

}