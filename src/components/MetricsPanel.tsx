import React, { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { AsciiChart, AsciiBar } from './AsciiChart';
import { Activity, Server, HardDrive, Zap } from 'lucide-react';
interface Metric {
  label: string;
  key: string;
  value: number;
  unit: string;
  icon: React.ReactNode;
  accentVar: string;
  history: number[];
  command: string;
}
function useMetrics() {
  const [metrics, setMetrics] = useState<
    Record<
      string,
      {
        value: number;
        history: number[];
      }>>(

    {
      cpu: {
        value: 34,
        history: [20, 35, 28, 45, 38, 52, 34, 41, 29, 38, 44, 34]
      },
      mem: {
        value: 67,
        history: [60, 62, 64, 65, 67, 66, 68, 67, 69, 67, 66, 67]
      },
      net: {
        value: 12,
        history: [8, 15, 10, 22, 12, 18, 9, 14, 20, 12, 16, 12]
      },
      disk: {
        value: 48,
        history: [44, 45, 46, 46, 47, 47, 48, 48, 47, 48, 48, 48]
      }
    });
  useEffect(() => {
    const id = setInterval(() => {
      setMetrics((prev) => {
        const next = {
          ...prev
        };
        const nudge = (v: number, lo: number, hi: number, delta: number) =>
        Math.max(lo, Math.min(hi, v + (Math.random() - 0.5) * delta));
        for (const [key, cfg] of Object.entries({
          cpu: {
            lo: 5,
            hi: 95,
            delta: 8
          },
          mem: {
            lo: 30,
            hi: 90,
            delta: 3
          },
          net: {
            lo: 1,
            hi: 80,
            delta: 6
          },
          disk: {
            lo: 40,
            hi: 60,
            delta: 1
          }
        })) {
          const newVal = nudge(prev[key].value, cfg.lo, cfg.hi, cfg.delta);
          next[key] = {
            value: newVal,
            history: [...prev[key].history.slice(-11), newVal]
          };
        }
        return next;
      });
    }, 1500);
    return () => clearInterval(id);
  }, []);
  return metrics;
}
const cardVariants = {
  hidden: {
    opacity: 0,
    y: 16
  },
  visible: (i: number) => ({
    opacity: 1,
    y: 0,
    transition: {
      delay: i * 0.1,
      duration: 0.35,
      ease: 'easeOut'
    }
  })
};
interface CardDef {
  key: string;
  label: string;
  unit: string;
  icon: React.ReactNode;
  accentVar: string;
  maxVal: number;
  command: string;
}
const cards: CardDef[] = [
{
  key: 'cpu',
  label: 'CPU_USAGE',
  unit: '%',
  icon: <Server size={14} />,
  accentVar: 'var(--accent-primary)',
  maxVal: 100,
  command: '$ top -bn1 | grep CPU'
},
{
  key: 'mem',
  label: 'MEMORY_ALLOC',
  unit: '%',
  icon: <Zap size={14} />,
  accentVar: 'var(--status-warning)',
  maxVal: 100,
  command: '$ free -m | grep Mem'
},
{
  key: 'net',
  label: 'NET_LATENCY',
  unit: 'ms',
  icon: <Activity size={14} />,
  accentVar: 'var(--status-info)',
  maxVal: 100,
  command: '$ ping -c 1 8.8.8.8'
},
{
  key: 'disk',
  label: 'DISK_IO',
  unit: '%',
  icon: <HardDrive size={14} />,
  accentVar: 'var(--accent-primary)',
  maxVal: 100,
  command: '$ iostat -d -x 1 1'
}];

export function MetricsPanel() {
  const metrics = useMetrics();
  return (
    <div className="space-y-6 mb-8">
      {/* Metric Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {cards.map((card, i) => {
          const m = metrics[card.key];
          const pct = m.value / card.maxVal;
          const dynColor =
          pct > 0.8 ?
          'var(--status-error)' :
          pct > 0.6 ?
          'var(--status-warning)' :
          card.accentVar;
          return (
            <motion.div
              key={card.key}
              custom={i}
              variants={cardVariants}
              initial="hidden"
              animate="visible"
              className="flex flex-col"
              style={{
                backgroundColor: 'var(--bg-secondary)',
                border: '1px solid var(--border-color)'
              }}>

              {/* Command Header */}
              <div
                className="px-3 py-1.5 text-[10px] font-mono border-b border-[var(--border-color)] bg-[var(--bg-tertiary)]"
                style={{
                  color: 'var(--text-muted)'
                }}>

                {card.command}
              </div>

              <div className="p-4 relative overflow-hidden flex-1">
                {/* Left accent bar */}
                <div
                  className="absolute left-0 top-0 bottom-0 w-0.5"
                  style={{
                    backgroundColor: dynColor
                  }} />


                <div className="flex items-center justify-between mb-2">
                  <span
                    className="text-xs font-bold flex items-center gap-1.5"
                    style={{
                      color: dynColor
                    }}>

                    {card.icon}
                    {card.label}
                  </span>
                </div>

                <div
                  className="text-2xl font-bold mb-3 font-mono"
                  style={{
                    color: 'var(--text-primary)'
                  }}>

                  {m.value.toFixed(1)}
                  <span
                    className="text-sm font-normal ml-0.5"
                    style={{
                      color: 'var(--text-muted)'
                    }}>

                    {card.unit}
                  </span>
                </div>

                <AsciiChart data={m.history} height={6} color={dynColor} />
              </div>
            </motion.div>);

        })}
      </div>

      {/* ASCII Progress Bars */}
      <motion.div
        initial={{
          opacity: 0,
          y: 12
        }}
        animate={{
          opacity: 1,
          y: 0
        }}
        transition={{
          delay: 0.5,
          duration: 0.35
        }}
        className="flex flex-col"
        style={{
          backgroundColor: 'var(--bg-secondary)',
          border: '1px solid var(--border-color)'
        }}>

        <div
          className="px-3 py-1.5 text-[10px] font-mono border-b border-[var(--border-color)] bg-[var(--bg-tertiary)]"
          style={{
            color: 'var(--text-muted)'
          }}>

          $ htop --sort-key PERCENT_CPU
        </div>

        <div className="p-4">
          <div
            className="text-xs font-bold mb-4 flex items-center gap-2"
            style={{
              color: 'var(--text-secondary)'
            }}>

            <span
              style={{
                color: 'var(--accent-primary)'
              }}>

              $
            </span>
            RESOURCE_UTILIZATION
          </div>
          <div className="space-y-2">
            {cards.map((card) =>
            <AsciiBar
              key={card.key}
              label={card.key.toUpperCase()}
              value={metrics[card.key].value}
              max={100}
              width={28} />

            )}
          </div>
        </div>
      </motion.div>
    </div>);

}