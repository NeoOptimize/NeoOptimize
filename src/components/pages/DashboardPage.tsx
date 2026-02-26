import React, { useCallback, useState, useRef, memo, Component } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { MetricsPanel } from '../MetricsPanel';
import { TypingText } from '../TypingText';
import {
  Zap,
  User,
  Heart,
  ExternalLink,
  Mail,
  Phone,
  Trash2 } from
'lucide-react';
// ─── Types & Constants ───────────────────────────────────────────────────────
type LogLevel = 'ok' | 'warn' | 'error' | 'info';
type OptimizeState = 'idle' | 'running' | 'done';
const optimizeSteps = [
{
  delay: 0,
  level: 'info',
  text: 'Initializing optimization engine v2.4.1...'
},
{
  delay: 400,
  level: 'ok',
  text: 'Loading system profile: /etc/neooptimize/system.conf'
},
{
  delay: 800,
  level: 'ok',
  text: 'Analyzing CPU scheduler — governor: powersave'
},
{
  delay: 1300,
  level: 'ok',
  text: 'Applying CPU governor: performance [+8% throughput]'
},
{
  delay: 1800,
  level: 'ok',
  text: 'Flushing memory cache — 2.4GB freed'
},
{
  delay: 2300,
  level: 'warn',
  text: 'Network buffer: suboptimal — tuning TCP stack...'
},
{
  delay: 2800,
  level: 'ok',
  text: 'TCP stack optimized: rmem=16MB wmem=16MB'
},
{
  delay: 3200,
  level: 'ok',
  text: 'Disk I/O scheduler: set to deadline [latency −22%]'
},
{
  delay: 3600,
  level: 'ok',
  text: 'Swappiness adjusted: 60 → 10'
},
{
  delay: 4000,
  level: 'ok',
  text: 'Rebuilding package index cache...'
},
{
  delay: 4500,
  level: 'info',
  text: 'Running deep cleaner pass...'
},
{
  delay: 5000,
  level: 'ok',
  text: 'Removing orphaned packages — 847MB freed'
},
{
  delay: 5500,
  level: 'ok',
  text: 'Cleaning temp files: /tmp, /var/tmp'
},
{
  delay: 6000,
  level: 'ok',
  text: 'Defragmenting inode tables...'
},
{
  delay: 6500,
  level: 'ok',
  text: 'Deep clean complete — total freed: 3.2GB'
},
{
  delay: 7000,
  level: 'ok',
  text: 'Optimization complete — score: 98/100'
}];

const dumpClearSteps = [
{
  delay: 0,
  level: 'info',
  text: 'Scanning dump files...'
},
{
  delay: 800,
  level: 'warn',
  text: 'Found 12 crash dumps (1.8GB)'
},
{
  delay: 1600,
  level: 'ok',
  text: 'Clearing /var/crash/*.dump'
},
{
  delay: 2400,
  level: 'ok',
  text: 'Clearing Windows Error Reports...'
},
{
  delay: 3000,
  level: 'ok',
  text: 'Dump files cleared — 1.8GB freed'
}];

const levelStyle: Record<
  LogLevel,
  {
    color: string;
    prefix: string;
  }> =
{
  ok: {
    color: 'var(--ansi-green)',
    prefix: '✓'
  },
  warn: {
    color: 'var(--ansi-yellow)',
    prefix: '⚠'
  },
  error: {
    color: 'var(--ansi-red)',
    prefix: '✗'
  },
  info: {
    color: 'var(--ansi-blue)',
    prefix: 'i'
  }
};
const pendingActions = [
{
  label: 'Purge Cache Memory',
  level: 'warn' as LogLevel,
  shortcut: '[1]'
},
{
  label: 'Rotate API Keys',
  level: 'error' as LogLevel,
  shortcut: '[2]'
},
{
  label: 'Update Dependencies',
  level: 'info' as LogLevel,
  shortcut: '[3]'
},
{
  label: 'Rebuild Search Index',
  level: 'ok' as LogLevel,
  shortcut: '[4]'
}];

const sectionVariants = {
  hidden: {
    opacity: 0,
    y: 20
  },
  visible: (i: number) => ({
    opacity: 1,
    y: 0,
    transition: {
      delay: i * 0.12,
      duration: 0.4,
      ease: 'easeOut'
    }
  })
};
// ─── Components ──────────────────────────────────────────────────────────────
function OptimizePanel() {
  const [state, setState] = useState<OptimizeState>('idle');
  const [mode, setMode] = useState<'full' | 'dump'>('full');
  const [visibleSteps, setVisibleSteps] = useState<any[]>([]);
  const outputRef = useRef<HTMLDivElement>(null);
  const run = useCallback(
    (selectedMode: 'full' | 'dump') => {
      if (state !== 'idle') return;
      setState('running');
      setMode(selectedMode);
      setVisibleSteps([]);
      const steps = selectedMode === 'full' ? optimizeSteps : dumpClearSteps;
      steps.forEach((step, i) => {
        setTimeout(() => {
          setVisibleSteps((prev) => [...prev, step]);
          if (outputRef.current) {
            outputRef.current.scrollTop = outputRef.current.scrollHeight;
          }
          if (i === steps.length - 1) {
            setTimeout(() => setState('done'), 600);
          }
        }, step.delay);
      });
    },
    [state]
  );
  const reset = useCallback(() => {
    setState('idle');
    setVisibleSteps([]);
  }, []);
  const steps = mode === 'full' ? optimizeSteps : dumpClearSteps;
  const progress =
  state === 'done' ?
  100 :
  state === 'running' ?
  Math.round(visibleSteps.length / steps.length * 100) :
  0;
  const filledBars = Math.round(progress / 100 * 30);
  return (
    <motion.div
      custom={2}
      variants={sectionVariants}
      initial="hidden"
      animate="visible"
      style={{
        backgroundColor: 'var(--bg-secondary)',
        border: '1px solid var(--border-color)'
      }}>

      <div
        className="px-3 py-2 text-[10px] font-mono border-b flex items-center justify-between"
        style={{
          borderColor: 'var(--border-color)',
          backgroundColor: 'var(--bg-tertiary)',
          color: 'var(--text-muted)'
        }}>

        <span>
          <span
            style={{
              color: 'var(--ansi-green)'
            }}>

            root@neooptimize
          </span>
          <span
            style={{
              color: 'var(--text-muted)'
            }}>

            :~#{' '}
          </span>
          <span
            style={{
              color: 'var(--text-primary)'
            }}>

            {mode === 'full' ?
            'sudo neooptimize --full --verbose' :
            'sudo neooptimize --cleaner --dump-clear'}
          </span>
        </span>
        <span
          style={{
            color: 'var(--text-muted)'
          }}>

          shortcut:{' '}
          <span
            style={{
              color: 'var(--ansi-yellow)'
            }}>

            [o]
          </span>
        </span>
      </div>

      <div className="p-4">
        {state !== 'idle' &&
        <div className="mb-4 font-mono text-xs">
            <div className="flex items-center gap-2 mb-1">
              <span
              style={{
                color: 'var(--text-muted)'
              }}>

                [
              </span>
              <span
              style={{
                color:
                state === 'done' ?
                'var(--ansi-green)' :
                'var(--ansi-yellow)',
                letterSpacing: '-1px'
              }}>

                {'█'.repeat(filledBars)}
                <span
                style={{
                  color: 'var(--bg-tertiary)'
                }}>

                  {'░'.repeat(30 - filledBars)}
                </span>
              </span>
              <span
              style={{
                color: 'var(--text-muted)'
              }}>

                ]
              </span>
              <span
              style={{
                color:
                state === 'done' ?
                'var(--ansi-green)' :
                'var(--ansi-yellow)',
                fontWeight: 700
              }}>

                {progress}%
              </span>
              {state === 'running' &&
            <span
              className="cursor-blink"
              style={{
                color: 'var(--ansi-yellow)'
              }}>

                  ▌
                </span>
            }
            </div>
          </div>
        }

        {(state === 'running' || state === 'done') &&
        <div
          ref={outputRef}
          className="mb-4 max-h-40 overflow-y-auto space-y-0.5 font-mono text-xs"
          style={{
            backgroundColor: 'var(--terminal-output-bg)',
            border: '1px solid var(--border-color)',
            padding: '8px 12px'
          }}>

            {visibleSteps.map((step, i) => {
            const s = levelStyle[step.level as LogLevel];
            return (
              <motion.div
                key={i}
                initial={{
                  opacity: 0,
                  x: -4
                }}
                animate={{
                  opacity: 1,
                  x: 0
                }}
                transition={{
                  duration: 0.15
                }}
                className="flex items-start gap-2">

                  <span
                  style={{
                    color: 'var(--text-muted)',
                    flexShrink: 0
                  }}>

                    [{String(i).padStart(2, '0')}:
                    {String(Math.floor(step.delay / 1000)).padStart(2, '0')}]
                  </span>
                  <span
                  style={{
                    color: s.color,
                    flexShrink: 0
                  }}>

                    {s.prefix}
                  </span>
                  <span
                  style={{
                    color:
                    step.level === 'error' ?
                    s.color :
                    'var(--text-primary)'
                  }}>

                    {step.text}
                  </span>
                </motion.div>);

          })}
            {state === 'running' &&
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
          }
            {state === 'done' &&
          <motion.div
            initial={{
              opacity: 0
            }}
            animate={{
              opacity: 1
            }}
            transition={{
              delay: 0.3
            }}
            className="mt-2 pt-2 font-bold"
            style={{
              borderTop: '1px solid var(--border-color)',
              color: 'var(--ansi-green)'
            }}>

                [DONE]{' '}
                {mode === 'full' ?
            'System optimized. Performance gain: +23% ✓' :
            'Dump files cleared successfully ✓'}
              </motion.div>
          }
          </div>
        }

        <div className="flex items-center gap-4">
          {state === 'idle' &&
          <>
              <button
              onClick={() => run('full')}
              className="flex items-center gap-2 px-4 py-2 font-mono text-xs font-bold transition-all duration-150"
              style={{
                border: '1px solid var(--ansi-green)',
                color: 'var(--ansi-green)',
                backgroundColor: 'transparent',
                boxShadow: '0 0 8px var(--accent-glow)'
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.backgroundColor = 'var(--ansi-green)';
                e.currentTarget.style.color = 'var(--bg-primary)';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.backgroundColor = 'transparent';
                e.currentTarget.style.color = 'var(--ansi-green)';
              }}>

                <Zap size={12} />$ sudo neooptimize --run
              </button>

              <button
              onClick={() => run('dump')}
              className="flex items-center gap-2 px-4 py-2 font-mono text-xs font-bold transition-all duration-150"
              style={{
                border: '1px solid var(--ansi-yellow)',
                color: 'var(--ansi-yellow)',
                backgroundColor: 'transparent'
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.backgroundColor = 'var(--ansi-yellow)';
                e.currentTarget.style.color = 'var(--bg-primary)';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.backgroundColor = 'transparent';
                e.currentTarget.style.color = 'var(--ansi-yellow)';
              }}>

                <Trash2 size={12} />$ clean --dumps
              </button>
            </>
          }
          {state === 'running' &&
          <div
            className="flex items-center gap-2 text-xs font-mono"
            style={{
              color: 'var(--ansi-yellow)'
            }}>

              <span className="cursor-blink">▌</span>
              <span>Processing... please wait</span>
            </div>
          }
          {state === 'done' &&
          <div className="flex items-center gap-4">
              <span
              className="text-xs font-mono font-bold"
              style={{
                color: 'var(--ansi-green)'
              }}>

                ✓ Complete
              </span>
              <button
              onClick={reset}
              className="px-3 py-1 font-mono text-xs transition-all duration-150"
              style={{
                border: '1px solid var(--border-color)',
                color: 'var(--text-muted)',
                backgroundColor: 'transparent'
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.borderColor = 'var(--ansi-green)';
                e.currentTarget.style.color = 'var(--ansi-green)';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.borderColor = 'var(--border-color)';
                e.currentTarget.style.color = 'var(--text-muted)';
              }}>

                [r] run again
              </button>
            </div>
          }
        </div>
      </div>
    </motion.div>);

}
function KeyboardShortcuts() {
  const [open, setOpen] = useState(false);
  return (
    <motion.div
      custom={5}
      variants={sectionVariants}
      initial="hidden"
      animate="visible"
      style={{
        backgroundColor: 'var(--bg-secondary)',
        border: '1px solid var(--border-color)'
      }}>

      <button
        className="w-full px-3 py-2 text-[10px] font-mono flex items-center justify-between"
        style={{
          borderBottom: open ? '1px solid var(--border-color)' : 'none',
          color: 'var(--text-muted)',
          backgroundColor: 'var(--bg-tertiary)'
        }}
        onClick={() => setOpen((o) => !o)}>

        <span>
          <span
            style={{
              color: 'var(--ansi-green)'
            }}>

            $
          </span>{' '}
          man neooptimize | grep SHORTCUTS
        </span>
        <span
          style={{
            color: 'var(--ansi-yellow)'
          }}>

          [?] {open ? 'hide' : 'show'}
        </span>
      </button>
      <AnimatePresence>
        {open &&
        <motion.div
          initial={{
            height: 0,
            opacity: 0
          }}
          animate={{
            height: 'auto',
            opacity: 1
          }}
          exit={{
            height: 0,
            opacity: 0
          }}
          transition={{
            duration: 0.2
          }}
          style={{
            overflow: 'hidden'
          }}>

            <div className="p-4 grid grid-cols-2 gap-x-8 gap-y-1.5 font-mono text-xs">
              {[
            {
              key: '[1–8]',
              desc: 'Navigate sections'
            },
            {
              key: '[o]',
              desc: 'Run optimization'
            },
            {
              key: '[r]',
              desc: 'Refresh metrics'
            },
            {
              key: '[c]',
              desc: 'Clear logs'
            },
            {
              key: '[f]',
              desc: 'Filter logs'
            },
            {
              key: '[?]',
              desc: 'Toggle shortcuts'
            },
            {
              key: '[↑↓]',
              desc: 'Navigate menu'
            },
            {
              key: '[q]',
              desc: 'Quit / back'
            }].
            map((item) =>
            <div key={item.key} className="flex items-center gap-2">
                  <span
                className="font-bold"
                style={{
                  color: 'var(--ansi-yellow)'
                }}>

                    {item.key}
                  </span>
                  <span
                style={{
                  color: 'var(--text-muted)'
                }}>

                    {item.desc}
                  </span>
                </div>
            )}
            </div>
          </motion.div>
        }
      </AnimatePresence>
    </motion.div>);

}
function DeveloperInfo() {
  return (
    <motion.div
      custom={6}
      variants={sectionVariants}
      initial="hidden"
      animate="visible"
      style={{
        backgroundColor: 'var(--bg-secondary)',
        border: '1px solid var(--border-color)'
      }}>

      <div
        className="px-3 py-1.5 text-[10px] font-mono border-b flex items-center justify-between"
        style={{
          borderColor: 'var(--border-color)',
          backgroundColor: 'var(--bg-tertiary)',
          color: 'var(--text-muted)'
        }}>

        <span>
          <span
            style={{
              color: 'var(--ansi-green)'
            }}>

            root@neooptimize
          </span>
          <span
            style={{
              color: 'var(--text-muted)'
            }}>

            :~#{' '}
          </span>
          <span
            style={{
              color: 'var(--text-primary)'
            }}>

            cat /etc/neooptimize/developer.info
          </span>
        </span>
        <span
          style={{
            color: 'var(--ansi-green)',
            fontSize: '9px'
          }}>

          readonly
        </span>
      </div>

      <div className="p-4 font-mono text-xs space-y-4">
        <div>
          <div
            className="text-[10px] font-bold mb-2 tracking-widest"
            style={{
              color: 'var(--ansi-blue)'
            }}>

            ┌─ DEVELOPER INFORMATION ──────────────────────────────────┐
          </div>
          <div className="space-y-1.5 pl-2">
            {[
            {
              label: '  Name    ',
              value: 'Sigit Profesional IT',
              color: 'var(--text-primary)',
              href: undefined
            },
            {
              label: '  WhatsApp',
              value: '087889911030',
              color: 'var(--ansi-green)',
              href: 'https://wa.me/6287889911030'
            },
            {
              label: '  Email   ',
              value: 'gxmood@gmail.com',
              color: 'var(--ansi-blue)',
              href: 'mailto:gxmood@gmail.com'
            }].
            map((item) =>
            <div key={item.label} className="flex items-center gap-0">
                <span
                style={{
                  color: 'var(--text-muted)'
                }}>

                  {item.label}
                </span>
                <span
                style={{
                  color: 'var(--text-muted)'
                }}>

                  {' '}
                  :{' '}
                </span>
                {item.href ?
              <a
                href={item.href}
                target={item.href.startsWith('http') ? '_blank' : undefined}
                rel="noreferrer"
                style={{
                  color: item.color,
                  textDecoration: 'none'
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.textDecoration = 'underline';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.textDecoration = 'none';
                }}>

                    {item.value}
                  </a> :

              <span
                style={{
                  color: item.color
                }}>

                    {item.value}
                  </span>
              }
              </div>
            )}
          </div>
          <div
            className="text-[10px] mt-2"
            style={{
              color: 'var(--ansi-blue)'
            }}>

            └──────────────────────────────────────────────────────────┘
          </div>
        </div>

        <div>
          <div
            className="text-[10px] font-bold mb-2 tracking-widest"
            style={{
              color: 'var(--ansi-yellow)'
            }}>

            ┌─ SUPPORT & DONATION ─────────────────────────────────────┐
          </div>
          <div className="space-y-1.5 pl-2">
            {[
            {
              label: '  Saweria     ',
              value: 'saweria.co/dtechtive',
              href: 'https://saweria.co/dtechtive'
            },
            {
              label: '  BuyMeACoffee',
              value: 'buymeacoffee.com/nol.eight',
              href: 'https://buymeacoffee.com/nol.eight'
            }].
            map((item) =>
            <div key={item.label} className="flex items-center gap-0">
                <span
                style={{
                  color: 'var(--text-muted)'
                }}>

                  {item.label}
                </span>
                <span
                style={{
                  color: 'var(--text-muted)'
                }}>

                  {' '}
                  :{' '}
                </span>
                <a
                href={item.href}
                target="_blank"
                rel="noreferrer"
                className="flex items-center gap-1"
                style={{
                  color: 'var(--ansi-cyan)',
                  textDecoration: 'none'
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.textDecoration = 'underline';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.textDecoration = 'none';
                }}>

                  {item.value} <ExternalLink size={9} />
                </a>
              </div>
            )}
          </div>
          <div
            className="text-[10px] mt-2"
            style={{
              color: 'var(--ansi-yellow)'
            }}>

            └──────────────────────────────────────────────────────────┘
          </div>
        </div>

        <div
          className="pt-1 text-[10px] border-t"
          style={{
            borderColor: 'var(--border-color)',
            color: 'var(--text-muted)'
          }}>

          <span
            style={{
              color: 'var(--text-muted)'
            }}>

            #{' '}
          </span>
          <span>Thank you for using NeoOptimize </span>
          <span
            style={{
              color: 'var(--ansi-red)'
            }}>

            ♥
          </span>
          <span> — built with passion by </span>
          <span
            style={{
              color: 'var(--ansi-green)'
            }}>

            Sigit Profesional IT
          </span>
        </div>
      </div>
    </motion.div>);

}
export function DashboardPage() {
  return (
    <div className="space-y-4">
      {/* Breadcrumb / prompt */}
      <motion.div
        initial={{
          opacity: 0
        }}
        animate={{
          opacity: 1
        }}
        transition={{
          duration: 0.4
        }}
        className="text-xs flex items-center gap-1"
        style={{
          color: 'var(--text-muted)'
        }}>

        <span
          style={{
            color: 'var(--ansi-green)',
            fontWeight: 700
          }}>

          root@neooptimize
        </span>
        <span
          style={{
            color: 'var(--text-muted)'
          }}>

          :~#
        </span>
        <span
          style={{
            color: 'var(--text-primary)',
            marginLeft: '4px'
          }}>

          sudo neooptimize --status --verbose
        </span>
        <span
          className="cursor-blink ml-1"
          style={{
            color: 'var(--ansi-green)'
          }}>

          █
        </span>
      </motion.div>

      {/* Page header */}
      <motion.div
        custom={0}
        variants={sectionVariants}
        initial="hidden"
        animate="visible"
        className="pb-4"
        style={{
          borderBottom: '1px solid var(--border-color)'
        }}>

        <h1
          className="text-xl font-bold flex items-center gap-2 mb-2"
          style={{
            color: 'var(--text-primary)'
          }}>

          <span
            className="text-glow"
            style={{
              color: 'var(--ansi-green)'
            }}>

            {'>'}
          </span>
          <TypingText
            text="SYSTEM_OPTIMIZATION_PROTOCOL"
            speed={35}
            delay={200} />

        </h1>
        <p
          className="text-xs"
          style={{
            color: 'var(--text-muted)',
            lineHeight: 1.7
          }}>

          # Initiating core analysis. Efficiency rating:{' '}
          <span
            style={{
              color: 'var(--ansi-yellow)'
            }}>

            SUBOPTIMAL
          </span>
          {'. '}Recommended: clear cache, optimize indexes, compress assets.
        </p>
      </motion.div>

      {/* Metrics */}
      <motion.div
        custom={1}
        variants={sectionVariants}
        initial="hidden"
        animate="visible">

        <MetricsPanel />
      </motion.div>

      {/* Optimize panel */}
      <OptimizePanel />

      {/* Bottom grid: Pending Actions + System Health */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <motion.div
          custom={3}
          variants={sectionVariants}
          initial="hidden"
          animate="visible">

          <div
            style={{
              backgroundColor: 'var(--bg-secondary)',
              border: '1px solid var(--border-color)'
            }}>

            <div
              className="px-3 py-1.5 text-[10px] font-mono border-b flex items-center justify-between"
              style={{
                borderColor: 'var(--border-color)',
                backgroundColor: 'var(--bg-tertiary)',
                color: 'var(--text-muted)'
              }}>

              <span>$ pending_actions --list --priority</span>
              <span
                style={{
                  color: 'var(--ansi-yellow)'
                }}>

                [e] exec
              </span>
            </div>
            <div className="p-4 space-y-2">
              {pendingActions.map((action, i) => {
                const s = levelStyle[action.level];
                return (
                  <div
                    key={i}
                    className="flex items-center justify-between px-2 py-1.5 text-xs group"
                    style={{
                      border: '1px solid var(--border-color)',
                      backgroundColor: 'var(--bg-primary)'
                    }}>

                    <div className="flex items-center gap-2">
                      <span
                        style={{
                          color: s.color
                        }}>

                        ●
                      </span>
                      <span
                        style={{
                          color: 'var(--text-primary)'
                        }}>

                        {action.label}
                      </span>
                    </div>
                    <div className="flex items-center gap-2">
                      <span
                        style={{
                          color: 'var(--text-muted)',
                          fontSize: '9px'
                        }}>

                        {action.shortcut}
                      </span>
                      <button
                        className="px-2 py-0.5 text-xs font-bold transition-all duration-150"
                        style={{
                          border: '1px solid var(--ansi-green)',
                          color: 'var(--ansi-green)',
                          backgroundColor: 'transparent'
                        }}
                        onMouseEnter={(e) => {
                          e.currentTarget.style.backgroundColor =
                          'var(--ansi-green)';
                          e.currentTarget.style.color = 'var(--bg-primary)';
                        }}
                        onMouseLeave={(e) => {
                          e.currentTarget.style.backgroundColor = 'transparent';
                          e.currentTarget.style.color = 'var(--ansi-green)';
                        }}>

                        EXEC
                      </button>
                    </div>
                  </div>);

              })}
            </div>
          </div>
        </motion.div>

        <motion.div
          custom={4}
          variants={sectionVariants}
          initial="hidden"
          animate="visible">

          <div
            style={{
              backgroundColor: 'var(--bg-secondary)',
              border: '1px solid var(--border-color)'
            }}>

            <div
              className="px-3 py-1.5 text-[10px] font-mono border-b"
              style={{
                borderColor: 'var(--border-color)',
                backgroundColor: 'var(--bg-tertiary)',
                color: 'var(--text-muted)'
              }}>

              $ health_check --full --verbose
            </div>
            <div className="p-4 space-y-2 text-xs">
              {[
              {
                label: 'DB Integrity',
                value: 98,
                color: 'var(--ansi-green)'
              },
              {
                label: 'Firewall',
                value: 100,
                color: 'var(--ansi-green)'
              },
              {
                label: 'Load Balancer',
                value: 65,
                color: 'var(--ansi-yellow)'
              },
              {
                label: 'SSL Certs',
                value: 88,
                color: 'var(--ansi-green)'
              }].
              map((item) =>
              <div key={item.label} className="flex items-center gap-2">
                  <span
                  className="w-24 shrink-0"
                  style={{
                    color: 'var(--text-muted)'
                  }}>

                    {item.label}
                  </span>
                  <div
                  className="flex-1 h-1.5"
                  style={{
                    backgroundColor: 'var(--bg-tertiary)'
                  }}>

                    <motion.div
                    className="h-full"
                    style={{
                      backgroundColor: item.color
                    }}
                    initial={{
                      width: 0
                    }}
                    animate={{
                      width: `${item.value}%`
                    }}
                    transition={{
                      delay: 0.8,
                      duration: 0.6,
                      ease: 'easeOut'
                    }} />

                  </div>
                  <span
                  className="w-8 text-right shrink-0 font-bold"
                  style={{
                    color: item.color
                  }}>

                    {item.value}%
                  </span>
                </div>
              )}
            </div>
          </div>
        </motion.div>
      </div>

      <KeyboardShortcuts />
      <DeveloperInfo />
    </div>);

}