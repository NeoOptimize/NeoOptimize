import React, { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
interface AsciiBarProps {
  value: number;
  max?: number;
  label?: string;
  color?: string;
  showPercent?: boolean;
  width?: number;
}
export function AsciiBar({
  value,
  max = 100,
  label,
  color,
  showPercent = true,
  width = 20
}: AsciiBarProps) {
  const pct = Math.min(1, Math.max(0, value / max));
  const filled = Math.round(pct * width);
  const empty = width - filled;
  const barColor =
  color || (
  pct > 0.8 ?
  'var(--status-error)' :
  pct > 0.6 ?
  'var(--status-warning)' :
  'var(--accent-primary)');
  return (
    <div className="flex items-center gap-2 text-xs font-mono">
      {label &&
      <span
        className="w-16 text-right shrink-0"
        style={{
          color: 'var(--text-muted)'
        }}>

          {label}
        </span>
      }
      <span
        style={{
          color: 'var(--border-color)'
        }}>

        [
      </span>
      <span
        style={{
          color: barColor,
          letterSpacing: '-1px'
        }}>

        {'█'.repeat(filled)}
        <span
          style={{
            color: 'var(--bg-tertiary)'
          }}>

          {'░'.repeat(empty)}
        </span>
      </span>
      <span
        style={{
          color: 'var(--border-color)'
        }}>

        ]
      </span>
      {showPercent &&
      <span
        className="w-10 shrink-0"
        style={{
          color: barColor,
          fontWeight: 600
        }}>

          {Math.round(pct * 100)}%
        </span>
      }
    </div>);

}
interface AsciiChartProps {
  data: number[];
  height?: number;
  color?: string;
  label?: string;
}
export function AsciiChart({
  data,
  height = 8,
  color = 'var(--accent-primary)',
  label
}: AsciiChartProps) {
  const [animated, setAnimated] = useState(false);
  useEffect(() => {
    const t = setTimeout(() => setAnimated(true), 100);
    return () => clearTimeout(t);
  }, []);
  const max = Math.max(...data, 1);
  const normalized = data.map((v) => Math.floor(v / max * height));
  return (
    <div className="font-mono text-xs leading-none select-none w-full">
      {label &&
      <div
        className="mb-1 text-xs font-bold"
        style={{
          color: 'var(--text-secondary)'
        }}>

          [{label}]
        </div>
      }
      <div className="flex items-end gap-px">
        {normalized.map((val, i) =>
        <div key={i} className="flex flex-col-reverse flex-1 min-w-0">
            {Array.from({
            length: height
          }).map((_, hIdx) => {
            const isFilled = animated && hIdx < val;
            return (
              <motion.span
                key={hIdx}
                initial={{
                  opacity: 0
                }}
                animate={{
                  opacity: 1
                }}
                transition={{
                  delay: i * 0.03 + hIdx * 0.01
                }}
                className="block text-center"
                style={{
                  color: isFilled ? color : 'var(--bg-tertiary)',
                  lineHeight: 1.1
                }}>

                  {isFilled ? '█' : '░'}
                </motion.span>);

          })}
          </div>
        )}
      </div>
    </div>);

}