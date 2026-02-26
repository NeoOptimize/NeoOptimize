import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  ChevronDown,
  ChevronRight,
  Settings,
  Package,
  Zap,
  Terminal } from
'lucide-react';
const Section = ({
  title,
  icon,
  children




}: {title: string;icon: React.ReactNode;children: React.ReactNode;}) => {
  const [open, setOpen] = useState(false);
  return (
    <div
      className="border"
      style={{
        borderColor: 'var(--border-color)',
        backgroundColor: 'var(--bg-secondary)'
      }}>

      <button
        onClick={() => setOpen(!open)}
        className="w-full px-4 py-3 flex items-center justify-between text-xs font-bold hover:bg-[var(--bg-tertiary)] transition-colors"
        style={{
          color: 'var(--text-primary)'
        }}>

        <div className="flex items-center gap-2">
          {icon} {title}
        </div>
        {open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
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
          className="overflow-hidden">

            <div
            className="p-4 border-t"
            style={{
              borderColor: 'var(--border-color)'
            }}>

              {children}
            </div>
          </motion.div>
        }
      </AnimatePresence>
    </div>);

};
export function ConfigPage() {
  return (
    <div className="space-y-4">
      <div
        className="text-xs flex items-center gap-2"
        style={{
          color: 'var(--text-muted)'
        }}>

        <span
          style={{
            color: 'var(--ansi-green)',
            fontWeight: 700
          }}>

          $
        </span>
        <span>sudo nano /etc/neooptimize/godmode.conf</span>
      </div>

      <Section
        title="PERFORMANCE TWEAKS"
        icon={
        <Zap
          size={14}
          style={{
            color: 'var(--ansi-yellow)'
          }} />

        }>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
          <div className="space-y-1">
            <label
              style={{
                color: 'var(--text-muted)'
              }}>

              CPU Governor
            </label>
            <select
              className="w-full p-2 border font-mono text-xs"
              style={{
                borderColor: 'var(--border-color)',
                color: 'var(--text-primary)',
                backgroundColor: 'var(--bg-primary)'
              }}>

              <option value="performance">performance</option>
              <option value="powersave">powersave</option>
              <option value="ondemand">ondemand</option>
              <option value="conservative">conservative</option>
            </select>
          </div>
          <div className="space-y-1">
            <label
              style={{
                color: 'var(--text-muted)'
              }}>

              I/O Scheduler
            </label>
            <select
              className="w-full p-2 border font-mono text-xs"
              style={{
                borderColor: 'var(--border-color)',
                color: 'var(--text-primary)',
                backgroundColor: 'var(--bg-primary)'
              }}>

              <option value="deadline">deadline</option>
              <option value="cfq">cfq</option>
              <option value="noop">noop</option>
              <option value="bfq">bfq</option>
            </select>
          </div>
          <div className="space-y-1">
            <label
              style={{
                color: 'var(--text-muted)'
              }}>

              Swappiness (0-100)
            </label>
            <input
              type="range"
              min="0"
              max="100"
              defaultValue="10"
              className="w-full accent-[var(--ansi-green)]" />

            <div
              className="flex justify-between text-[10px]"
              style={{
                color: 'var(--text-muted)'
              }}>

              <span>0</span>
              <span>10</span>
              <span>100</span>
            </div>
          </div>
          <div className="space-y-1">
            <label
              style={{
                color: 'var(--text-muted)'
              }}>

              TCP Congestion
            </label>
            <select
              className="w-full p-2 border font-mono text-xs"
              style={{
                borderColor: 'var(--border-color)',
                color: 'var(--text-primary)',
                backgroundColor: 'var(--bg-primary)'
              }}>

              <option value="bbr">bbr</option>
              <option value="cubic">cubic</option>
              <option value="reno">reno</option>
            </select>
          </div>
        </div>
      </Section>

      <Section
        title="BLOATWARE REMOVAL"
        icon={
        <Package
          size={14}
          style={{
            color: 'var(--ansi-red)'
          }} />

        }>

        <div className="space-y-2 text-xs">
          {[
          {
            name: 'cups',
            desc: 'Printing service',
            size: '12MB',
            risk: 'LOW'
          },
          {
            name: 'avahi-daemon',
            desc: 'Network discovery',
            size: '4MB',
            risk: 'MED'
          },
          {
            name: 'snapd',
            desc: 'Snap package manager',
            size: '45MB',
            risk: 'LOW'
          },
          {
            name: 'telnet',
            desc: 'Insecure protocol',
            size: '1MB',
            risk: 'SAFE'
          }].
          map((pkg) =>
          <div
            key={pkg.name}
            className="flex items-center justify-between p-2 border"
            style={{
              borderColor: 'var(--border-color)',
              backgroundColor: 'var(--bg-primary)'
            }}>

              <div className="flex items-center gap-3">
                <input type="checkbox" className="accent-[var(--ansi-red)]" />
                <div>
                  <div
                  style={{
                    color: 'var(--text-primary)'
                  }}>

                    {pkg.name}
                  </div>
                  <div
                  style={{
                    color: 'var(--text-muted)',
                    fontSize: '10px'
                  }}>

                    {pkg.desc} • {pkg.size}
                  </div>
                </div>
              </div>
              <span
              className="px-1.5 py-0.5 text-[9px] border"
              style={{
                borderColor: 'var(--border-color)',
                color: 'var(--text-muted)'
              }}>

                {pkg.risk}
              </span>
            </div>
          )}
          <button
            className="mt-2 px-3 py-1.5 text-xs font-bold border hover:bg-[var(--ansi-red)] hover:text-black transition-colors"
            style={{
              borderColor: 'var(--ansi-red)',
              color: 'var(--ansi-red)'
            }}>

            UNINSTALL SELECTED
          </button>
        </div>
      </Section>

      <Section
        title="STARTUP OPTIMIZATION"
        icon={
        <Settings
          size={14}
          style={{
            color: 'var(--ansi-blue)'
          }} />

        }>

        <div className="space-y-2 text-xs">
          {[
          {
            name: 'NetworkManager',
            impact: '1.2s',
            enabled: true
          },
          {
            name: 'bluetooth',
            impact: '0.8s',
            enabled: false
          },
          {
            name: 'cups',
            impact: '0.5s',
            enabled: false
          },
          {
            name: 'ModemManager',
            impact: '0.9s',
            enabled: true
          }].
          map((svc) =>
          <div
            key={svc.name}
            className="flex items-center justify-between p-2 border"
            style={{
              borderColor: 'var(--border-color)'
            }}>

              <div>
                <div
                style={{
                  color: 'var(--text-primary)'
                }}>

                  {svc.name}
                </div>
                <div
                style={{
                  color: 'var(--text-muted)',
                  fontSize: '10px'
                }}>

                  Boot impact: {svc.impact}
                </div>
              </div>
              <button
              className="px-2 py-0.5 text-[10px] font-bold border"
              style={{
                borderColor: svc.enabled ?
                'var(--ansi-green)' :
                'var(--text-muted)',
                color: svc.enabled ?
                'var(--ansi-green)' :
                'var(--text-muted)'
              }}>

                {svc.enabled ? 'ENABLED' : 'DISABLED'}
              </button>
            </div>
          )}
        </div>
      </Section>

      <Section
        title="KERNEL PARAMETERS"
        icon={
        <Terminal
          size={14}
          style={{
            color: 'var(--ansi-green)'
          }} />

        }>

        <div className="space-y-2 text-xs font-mono">
          {[
          {
            key: 'vm.swappiness',
            val: '10'
          },
          {
            key: 'net.core.somaxconn',
            val: '1024'
          },
          {
            key: 'fs.file-max',
            val: '2097152'
          }].
          map((param) =>
          <div key={param.key} className="flex items-center gap-2">
              <span
              style={{
                color: 'var(--ansi-blue)'
              }}>

                {param.key}
              </span>
              <span
              style={{
                color: 'var(--text-muted)'
              }}>

                =
              </span>
              <input
              type="text"
              defaultValue={param.val}
              className="bg-transparent border-b outline-none w-24 text-center"
              style={{
                borderColor: 'var(--border-color)',
                color: 'var(--text-primary)'
              }} />

            </div>
          )}
          <button
            className="mt-2 px-3 py-1.5 text-xs font-bold border hover:bg-[var(--ansi-green)] hover:text-black transition-colors"
            style={{
              borderColor: 'var(--ansi-green)',
              color: 'var(--ansi-green)'
            }}>

            APPLY CHANGES
          </button>
        </div>
      </Section>
    </div>);

}