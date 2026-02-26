import React, { useState } from 'react';
import { motion } from 'framer-motion';
import { Play, Pause, XCircle, Info, Search } from 'lucide-react';
const processes = [
{
  pid: 1,
  user: 'root',
  cpu: 0.1,
  mem: 0.4,
  status: 'running',
  command: '/sbin/init'
},
{
  pid: 423,
  user: 'root',
  cpu: 0.0,
  mem: 0.1,
  status: 'sleeping',
  command: '[kworker/u16:3]'
},
{
  pid: 1337,
  user: 'root',
  cpu: 12.4,
  mem: 8.2,
  status: 'running',
  command: 'neooptimize --daemon'
},
{
  pid: 1452,
  user: 'www-data',
  cpu: 4.2,
  mem: 14.5,
  status: 'running',
  command: 'nginx: worker process'
},
{
  pid: 1892,
  user: 'mysql',
  cpu: 2.1,
  mem: 18.2,
  status: 'sleeping',
  command: '/usr/sbin/mysqld'
},
{
  pid: 2241,
  user: 'root',
  cpu: 0.5,
  mem: 1.2,
  status: 'running',
  command: '/usr/sbin/sshd -D'
},
{
  pid: 3321,
  user: 'user',
  cpu: 15.8,
  mem: 24.1,
  status: 'running',
  command: 'node server.js'
},
{
  pid: 4102,
  user: 'user',
  cpu: 8.4,
  mem: 5.6,
  status: 'sleeping',
  command: 'python3 analytics.py'
},
{
  pid: 5521,
  user: 'root',
  cpu: 0.0,
  mem: 0.1,
  status: 'sleeping',
  command: '/usr/sbin/cron -f'
},
{
  pid: 6621,
  user: 'user',
  cpu: 0.1,
  mem: 0.4,
  status: 'sleeping',
  command: '-bash'
},
{
  pid: 7721,
  user: 'user',
  cpu: 1.2,
  mem: 0.8,
  status: 'running',
  command: 'top'
},
{
  pid: 8821,
  user: 'user',
  cpu: 0.0,
  mem: 0.5,
  status: 'sleeping',
  command: 'vim /etc/hosts'
},
{
  pid: 9921,
  user: 'root',
  cpu: 0.2,
  mem: 0.3,
  status: 'zombie',
  command: '[defunct]'
},
{
  pid: 10231,
  user: 'user',
  cpu: 4.5,
  mem: 1.2,
  status: 'running',
  command: 'curl -sL https://api...'
},
{
  pid: 11231,
  user: 'user',
  cpu: 3.2,
  mem: 2.1,
  status: 'running',
  command: 'wget https://distro...'
}];

export function ProcessesPage() {
  const [search, setSearch] = useState('');
  const filtered = processes.filter(
    (p) =>
    p.command.toLowerCase().includes(search.toLowerCase()) ||
    p.user.toLowerCase().includes(search.toLowerCase()) ||
    String(p.pid).includes(search)
  );
  return (
    <div className="space-y-4">
      {/* Header */}
      <div
        className="flex items-center justify-between text-xs"
        style={{
          color: 'var(--text-muted)'
        }}>

        <div className="flex items-center gap-2">
          <span
            style={{
              color: 'var(--ansi-green)',
              fontWeight: 700
            }}>

            $
          </span>
          <span>ps aux --sort=-%cpu | head -20</span>
        </div>
        <div className="flex gap-4">
          <span>
            Total:{' '}
            <span
              style={{
                color: 'var(--text-primary)'
              }}>

              {processes.length}
            </span>
          </span>
          <span>
            Running:{' '}
            <span
              style={{
                color: 'var(--ansi-green)'
              }}>

              {processes.filter((p) => p.status === 'running').length}
            </span>
          </span>
          <span>
            Sleeping:{' '}
            <span
              style={{
                color: 'var(--ansi-blue)'
              }}>

              {processes.filter((p) => p.status === 'sleeping').length}
            </span>
          </span>
        </div>
      </div>

      {/* Search */}
      <div
        className="flex items-center gap-2 px-3 py-2 text-xs border"
        style={{
          borderColor: 'var(--border-color)',
          backgroundColor: 'var(--bg-secondary)'
        }}>

        <span
          style={{
            color: 'var(--ansi-green)'
          }}>

          grep -i
        </span>
        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="bg-transparent outline-none flex-1 font-mono"
          style={{
            color: 'var(--text-primary)'
          }}
          placeholder="[search process...]"
          autoFocus />

      </div>

      {/* Table */}
      <div
        className="border"
        style={{
          borderColor: 'var(--border-color)',
          backgroundColor: 'var(--bg-secondary)'
        }}>

        <div
          className="grid grid-cols-12 gap-2 px-3 py-2 text-[10px] font-bold border-b"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-tertiary)',
            color: 'var(--text-muted)'
          }}>

          <div className="col-span-1">PID</div>
          <div className="col-span-2">USER</div>
          <div className="col-span-1">CPU%</div>
          <div className="col-span-1">MEM%</div>
          <div className="col-span-2">STATUS</div>
          <div className="col-span-3">COMMAND</div>
          <div className="col-span-2 text-right">ACTIONS</div>
        </div>
        <div className="max-h-[60vh] overflow-y-auto">
          {filtered.map((p, i) =>
          <motion.div
            key={p.pid}
            initial={{
              opacity: 0,
              x: -10
            }}
            animate={{
              opacity: 1,
              x: 0
            }}
            transition={{
              delay: i * 0.03
            }}
            className="grid grid-cols-12 gap-2 px-3 py-2 text-xs font-mono items-center hover:bg-[var(--bg-tertiary)] transition-colors"
            style={{
              borderBottom: '1px solid var(--border-color)',
              backgroundColor:
              i % 2 === 0 ? 'var(--bg-primary)' : 'transparent'
            }}>

              <div
              className="col-span-1"
              style={{
                color: 'var(--ansi-yellow)'
              }}>

                {p.pid}
              </div>
              <div
              className="col-span-2"
              style={{
                color: 'var(--text-muted)'
              }}>

                {p.user}
              </div>
              <div
              className="col-span-1"
              style={{
                color: p.cpu > 10 ? 'var(--ansi-red)' : 'var(--text-primary)'
              }}>

                {p.cpu}
              </div>
              <div
              className="col-span-1"
              style={{
                color:
                p.mem > 10 ? 'var(--ansi-yellow)' : 'var(--text-primary)'
              }}>

                {p.mem}
              </div>
              <div className="col-span-2">
                <span
                className="px-1.5 py-0.5 text-[9px] font-bold rounded-sm"
                style={{
                  backgroundColor:
                  p.status === 'running' ?
                  'rgba(0,255,65,0.1)' :
                  p.status === 'zombie' ?
                  'rgba(255,68,68,0.1)' :
                  'rgba(85,153,255,0.1)',
                  color:
                  p.status === 'running' ?
                  'var(--ansi-green)' :
                  p.status === 'zombie' ?
                  'var(--ansi-red)' :
                  'var(--ansi-blue)'
                }}>

                  {p.status.toUpperCase()}
                </span>
              </div>
              <div
              className="col-span-3 truncate"
              style={{
                color: 'var(--text-primary)'
              }}>

                {p.command}
              </div>
              <div className="col-span-2 flex justify-end gap-1">
                <button
                className="p-1 border hover:bg-[var(--ansi-red)] hover:text-black transition-colors"
                style={{
                  borderColor: 'var(--ansi-red)',
                  color: 'var(--ansi-red)'
                }}
                title="Kill">

                  <XCircle size={10} />
                </button>
                <button
                className="p-1 border hover:bg-[var(--ansi-yellow)] hover:text-black transition-colors"
                style={{
                  borderColor: 'var(--ansi-yellow)',
                  color: 'var(--ansi-yellow)'
                }}
                title="Pause">

                  <Pause size={10} />
                </button>
                <button
                className="p-1 border hover:bg-[var(--ansi-blue)] hover:text-black transition-colors"
                style={{
                  borderColor: 'var(--ansi-blue)',
                  color: 'var(--ansi-blue)'
                }}
                title="Info">

                  <Info size={10} />
                </button>
              </div>
            </motion.div>
          )}
        </div>
      </div>

      {/* Kill Input */}
      <div
        className="flex items-center gap-2 px-3 py-2 text-xs border"
        style={{
          borderColor: 'var(--border-color)',
          backgroundColor: 'var(--bg-secondary)'
        }}>

        <span
          style={{
            color: 'var(--ansi-red)'
          }}>

          $ kill -9
        </span>
        <input
          type="text"
          className="bg-transparent outline-none flex-1 font-mono"
          style={{
            color: 'var(--text-primary)'
          }}
          placeholder="[PID]" />

        <button
          className="px-3 py-1 text-[10px] font-bold border hover:bg-[var(--ansi-red)] hover:text-black transition-colors"
          style={{
            borderColor: 'var(--ansi-red)',
            color: 'var(--ansi-red)'
          }}>

          EXEC
        </button>
      </div>
    </div>);

}