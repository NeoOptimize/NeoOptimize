import React, { useEffect, useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import { AsciiChart, AsciiBar } from './AsciiChart';
import { Activity, HardDrive, Server, Zap } from 'lucide-react';
import { useSystemStats } from '../hooks/SystemStatsContext';

type MetricKey = 'cpu' | 'mem' | 'net' | 'tasks';

type MetricSeries = Record<MetricKey, { value: number; history: number[] }>;

const cardVariants = {
  hidden: { opacity: 0, y: 16 },
  visible: (i: number) => ({
    opacity: 1,
    y: 0,
    transition: { delay: i * 0.08, duration: 0.3, ease: 'easeOut' }
  })
};

const cardDefs: Array<{
  key: MetricKey;
  label: string;
  unit: string;
  icon: React.ReactNode;
  accentVar: string;
  max: number;
  command: string;
}> = [
  {
    key: 'cpu',
    label: 'CPU_USAGE',
    unit: '%',
    icon: <Server size={14} />,
    accentVar: 'var(--accent-primary)',
    max: 100,
    command: '$ GET /api/system/overview'
  },
  {
    key: 'mem',
    label: 'MEMORY_ALLOC',
    unit: '%',
    icon: <Zap size={14} />,
    accentVar: 'var(--status-warning)',
    max: 100,
    command: '$ GET /api/system/overview'
  },
  {
    key: 'net',
    label: 'NET_LATENCY',
    unit: 'ms',
    icon: <Activity size={14} />,
    accentVar: 'var(--status-info)',
    max: 250,
    command: '$ GET /api/network/stats'
  },
  {
    key: 'tasks',
    label: 'TASK_COUNT',
    unit: 'proc',
    icon: <HardDrive size={14} />,
    accentVar: 'var(--ansi-cyan)',
    max: 400,
    command: '$ GET /api/processes'
  }
];

export function MetricsPanel() {
  const { metrics, tasks } = useSystemStats();
  const values = useMemo(
    () => ({
      cpu: Number(metrics.cpu || 0),
      mem: Number(metrics.mem || 0),
      net: Number(metrics.net || 0),
      tasks: Number(tasks || 0)
    }),
    [metrics.cpu, metrics.mem, metrics.net, tasks]
  );

  const [series, setSeries] = useState<MetricSeries>({
    cpu: { value: values.cpu, history: [values.cpu] },
    mem: { value: values.mem, history: [values.mem] },
    net: { value: values.net, history: [values.net] },
    tasks: { value: values.tasks, history: [values.tasks] }
  });

  useEffect(() => {
    setSeries((prev) => ({
      cpu: { value: values.cpu, history: [...prev.cpu.history.slice(-19), values.cpu] },
      mem: { value: values.mem, history: [...prev.mem.history.slice(-19), values.mem] },
      net: { value: values.net, history: [...prev.net.history.slice(-19), values.net] },
      tasks: { value: values.tasks, history: [...prev.tasks.history.slice(-19), values.tasks] }
    }));
  }, [values.cpu, values.mem, values.net, values.tasks]);

  return (
    <div className="space-y-4 mb-8">
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {cardDefs.map((card, i) => {
          const m = series[card.key];
          const pct = Math.max(0, Math.min(1, m.value / card.max));
          const dynColor = pct > 0.85 ? 'var(--status-error)' : pct > 0.65 ? 'var(--status-warning)' : card.accentVar;
          return (
            <motion.div
              key={card.key}
              custom={i}
              variants={cardVariants}
              initial="hidden"
              animate="visible"
              className="flex flex-col"
              style={{ backgroundColor: 'var(--bg-secondary)', border: '1px solid var(--border-color)' }}
            >
              <div
                className="px-3 py-1.5 text-[10px] font-mono border-b border-[var(--border-color)] bg-[var(--bg-tertiary)]"
                style={{ color: 'var(--text-muted)' }}
              >
                {card.command}
              </div>

              <div className="p-4 relative overflow-hidden flex-1">
                <div className="absolute left-0 top-0 bottom-0 w-0.5" style={{ backgroundColor: dynColor }} />
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-bold flex items-center gap-1.5" style={{ color: dynColor }}>
                    {card.icon}
                    {card.label}
                  </span>
                </div>
                <div className="text-2xl font-bold mb-3 font-mono" style={{ color: 'var(--text-primary)' }}>
                  {m.value.toFixed(1)}
                  <span className="text-sm font-normal ml-0.5" style={{ color: 'var(--text-muted)' }}>
                    {card.unit}
                  </span>
                </div>
                <AsciiChart data={m.history} height={6} color={dynColor} />
              </div>
            </motion.div>
          );
        })}
      </div>

      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.35, duration: 0.3 }}
        className="flex flex-col"
        style={{ backgroundColor: 'var(--bg-secondary)', border: '1px solid var(--border-color)' }}
      >
        <div
          className="px-3 py-1.5 text-[10px] font-mono border-b border-[var(--border-color)] bg-[var(--bg-tertiary)]"
          style={{ color: 'var(--text-muted)' }}
        >
          $ live_metrics --bars
        </div>
        <div className="p-4">
          <div className="text-xs font-bold mb-4 flex items-center gap-2" style={{ color: 'var(--text-secondary)' }}>
            <span style={{ color: 'var(--accent-primary)' }}>$</span>
            RESOURCE_UTILIZATION
          </div>
          <div className="space-y-2">
            {cardDefs.map((card) => (
              <AsciiBar key={card.key} label={card.key.toUpperCase()} value={series[card.key].value} max={card.max} width={28} />
            ))}
          </div>
        </div>
      </motion.div>
    </div>
  );
}
