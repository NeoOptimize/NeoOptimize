import React, { useState } from 'react';
import { motion } from 'framer-motion';
import { HardDrive, Trash2, Folder, Database } from 'lucide-react';
export function StoragePage() {
  const [clearing, setClearing] = useState(false);
  const [cleared, setCleared] = useState(false);
  const handleClear = () => {
    setClearing(true);
    setTimeout(() => {
      setClearing(false);
      setCleared(true);
    }, 2000);
  };
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
        <span>df -h && lsblk</span>
      </div>

      {/* Disk Usage Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {[
        {
          mount: '/',
          dev: '/dev/sda1',
          used: 68,
          total: '256GB',
          type: 'ext4'
        },
        {
          mount: '/home',
          dev: '/dev/sda2',
          used: 45,
          total: '1TB',
          type: 'ext4'
        },
        {
          mount: '/var',
          dev: '/dev/sdb1',
          used: 78,
          total: '64GB',
          type: 'xfs',
          warning: true
        },
        {
          mount: '/tmp',
          dev: 'tmpfs',
          used: 12,
          total: '16GB',
          type: 'tmpfs'
        }].
        map((disk, i) =>
        <motion.div
          key={disk.mount}
          initial={{
            opacity: 0,
            scale: 0.95
          }}
          animate={{
            opacity: 1,
            scale: 1
          }}
          transition={{
            delay: i * 0.1
          }}
          className="p-3 border"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-secondary)'
          }}>

            <div className="flex justify-between items-start mb-2">
              <div
              className="flex items-center gap-2 font-bold"
              style={{
                color: 'var(--text-primary)'
              }}>

                <HardDrive size={14} /> {disk.mount}
              </div>
              <span
              className="text-[10px]"
              style={{
                color: 'var(--text-muted)'
              }}>

                {disk.type}
              </span>
            </div>
            <div
            className="text-xs mb-2"
            style={{
              color: 'var(--text-muted)'
            }}>

              {disk.dev}
            </div>

            <div className="h-2 w-full bg-[var(--bg-tertiary)] mb-1 overflow-hidden">
              <div
              className="h-full transition-all duration-500"
              style={{
                width: `${disk.used}%`,
                backgroundColor: disk.warning ?
                'var(--ansi-yellow)' :
                'var(--ansi-green)'
              }} />

            </div>
            <div className="flex justify-between text-xs">
              <span
              style={{
                color: disk.warning ?
                'var(--ansi-yellow)' :
                'var(--ansi-green)'
              }}>

                {disk.used}%
              </span>
              <span
              style={{
                color: 'var(--text-muted)'
              }}>

                {disk.total}
              </span>
            </div>
          </motion.div>
        )}
      </div>

      {/* I/O Stats */}
      <div
        className="grid grid-cols-4 gap-4 p-3 border"
        style={{
          borderColor: 'var(--border-color)',
          backgroundColor: 'var(--bg-secondary)'
        }}>

        {[
        {
          label: 'Read IOPS',
          value: '423'
        },
        {
          label: 'Write IOPS',
          value: '128'
        },
        {
          label: 'Queue Depth',
          value: '2.4'
        },
        {
          label: 'Throughput',
          value: '45 MB/s'
        }].
        map((stat) =>
        <div key={stat.label} className="text-center">
            <div
            className="text-[10px]"
            style={{
              color: 'var(--text-muted)'
            }}>

              {stat.label}
            </div>
            <div
            className="text-lg font-mono font-bold"
            style={{
              color: 'var(--ansi-cyan)'
            }}>

              {stat.value}
            </div>
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Clear Dump Files */}
        <div
          className="border p-4"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-secondary)'
          }}>

          <div
            className="flex items-center gap-2 mb-3 text-xs font-bold"
            style={{
              color: 'var(--ansi-yellow)'
            }}>

            <Trash2 size={14} /> CLEAR DUMP FILES
          </div>
          <div
            className="text-xs font-mono mb-3 p-2 border"
            style={{
              borderColor: 'var(--border-color)',
              backgroundColor: 'var(--terminal-output-bg)',
              color: 'var(--text-muted)'
            }}>

            $ sudo find /var/crash /tmp -name '*.dump' -delete
          </div>

          {!cleared ?
          <div className="space-y-3">
              <div className="flex justify-between text-xs">
                <span
                style={{
                  color: 'var(--text-primary)'
                }}>

                  Found 12 dump files
                </span>
                <span
                style={{
                  color: 'var(--ansi-red)'
                }}>

                  1.8 GB
                </span>
              </div>
              <button
              onClick={handleClear}
              disabled={clearing}
              className="w-full py-1.5 text-xs font-bold border transition-colors flex items-center justify-center gap-2"
              style={{
                borderColor: 'var(--ansi-red)',
                color: clearing ? 'var(--bg-primary)' : 'var(--ansi-red)',
                backgroundColor: clearing ? 'var(--ansi-red)' : 'transparent'
              }}>

                {clearing ? 'CLEARING...' : '[CLEAR DUMPS]'}
              </button>
            </div> :

          <div
            className="text-xs text-center py-2"
            style={{
              color: 'var(--ansi-green)'
            }}>

              ✓ Dump files cleared — 1.8GB freed
            </div>
          }
        </div>

        {/* Top Directories */}
        <div
          className="border p-4"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-secondary)'
          }}>

          <div
            className="flex items-center gap-2 mb-3 text-xs font-bold"
            style={{
              color: 'var(--ansi-blue)'
            }}>

            <Folder size={14} /> TOP DIRECTORIES
          </div>
          <div className="space-y-2">
            {[
            {
              path: '/var/log',
              size: '4.2 GB',
              pct: 45
            },
            {
              path: '/home/user',
              size: '12.4 GB',
              pct: 30
            },
            {
              path: '/opt',
              size: '2.1 GB',
              pct: 15
            },
            {
              path: '/usr/lib',
              size: '1.8 GB',
              pct: 10
            }].
            map((dir) =>
            <div key={dir.path} className="text-xs">
                <div className="flex justify-between mb-1">
                  <span
                  style={{
                    color: 'var(--text-primary)'
                  }}>

                    {dir.path}
                  </span>
                  <span
                  style={{
                    color: 'var(--text-muted)'
                  }}>

                    {dir.size}
                  </span>
                </div>
                <div className="h-1.5 w-full bg-[var(--bg-tertiary)]">
                  <div
                  className="h-full bg-[var(--ansi-blue)]"
                  style={{
                    width: `${dir.pct}%`
                  }} />

                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>);

}