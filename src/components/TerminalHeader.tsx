import { ThemeToggle } from './ThemeToggle';
import { TypingText } from './TypingText';
import { useSystemStats } from '../hooks/SystemStatsContext';

export function TerminalHeader() {
  const { metrics, uptime } = useSystemStats();
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

      <div />

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
