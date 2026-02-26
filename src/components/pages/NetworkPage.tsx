import React, { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { Activity, ArrowDown, ArrowUp, Globe, Shield } from 'lucide-react';
const connections = [
{
  local: '127.0.0.1:5432',
  remote: '0.0.0.0:*',
  state: 'LISTEN',
  pid: 1892,
  process: 'mysqld'
},
{
  local: '192.168.1.42:22',
  remote: '10.0.0.5:54321',
  state: 'ESTABLISHED',
  pid: 2241,
  process: 'sshd'
},
{
  local: '192.168.1.42:80',
  remote: '172.16.0.4:33212',
  state: 'ESTABLISHED',
  pid: 1452,
  process: 'nginx'
},
{
  local: '192.168.1.42:443',
  remote: '172.16.0.8:44123',
  state: 'ESTABLISHED',
  pid: 1452,
  process: 'nginx'
},
{
  local: '127.0.0.1:6379',
  remote: '0.0.0.0:*',
  state: 'LISTEN',
  pid: 992,
  process: 'redis-server'
},
{
  local: '192.168.1.42:53422',
  remote: '8.8.8.8:53',
  state: 'TIME_WAIT',
  pid: 0,
  process: '-'
},
{
  local: '192.168.1.42:443',
  remote: '172.16.0.12:12345',
  state: 'ESTABLISHED',
  pid: 1452,
  process: 'nginx'
},
{
  local: '::1:25',
  remote: ':::*',
  state: 'LISTEN',
  pid: 882,
  process: 'master'
}];

export function NetworkPage() {
  const [download, setDownload] = useState(2.4);
  const [upload, setUpload] = useState(0.8);
  useEffect(() => {
    const i = setInterval(() => {
      setDownload((prev) => Math.max(0.1, prev + (Math.random() - 0.5)));
      setUpload((prev) => Math.max(0.1, prev + (Math.random() - 0.5) * 0.5));
    }, 1000);
    return () => clearInterval(i);
  }, []);
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
        <span>netstat -tulpn && ifconfig</span>
      </div>

      {/* Metric Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {[
        {
          label: 'Download',
          value: `${download.toFixed(1)} MB/s`,
          icon: <ArrowDown size={14} />,
          color: 'var(--ansi-green)'
        },
        {
          label: 'Upload',
          value: `${upload.toFixed(1)} MB/s`,
          icon: <ArrowUp size={14} />,
          color: 'var(--ansi-blue)'
        },
        {
          label: 'Latency',
          value: '12ms',
          icon: <Activity size={14} />,
          color: 'var(--ansi-yellow)'
        },
        {
          label: 'Packets/s',
          value: '1,247',
          icon: <Globe size={14} />,
          color: 'var(--ansi-cyan)'
        }].
        map((card, i) =>
        <motion.div
          key={card.label}
          initial={{
            opacity: 0,
            y: 10
          }}
          animate={{
            opacity: 1,
            y: 0
          }}
          transition={{
            delay: i * 0.1
          }}
          className="p-3 border"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-secondary)'
          }}>

            <div
            className="flex items-center gap-2 mb-2 text-xs"
            style={{
              color: 'var(--text-muted)'
            }}>

              {card.icon} {card.label}
            </div>
            <div
            className="text-xl font-bold font-mono"
            style={{
              color: card.color
            }}>

              {card.value}
            </div>
          </motion.div>
        )}
      </div>

      {/* Connections Table */}
      <div
        className="border"
        style={{
          borderColor: 'var(--border-color)',
          backgroundColor: 'var(--bg-secondary)'
        }}>

        <div
          className="px-3 py-2 text-[10px] font-bold border-b flex justify-between"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-tertiary)',
            color: 'var(--text-muted)'
          }}>

          <span>ACTIVE CONNECTIONS</span>
          <span>{connections.length} total</span>
        </div>
        <div
          className="grid grid-cols-12 gap-2 px-3 py-2 text-[10px] font-bold border-b"
          style={{
            borderColor: 'var(--border-color)',
            color: 'var(--text-muted)'
          }}>

          <div className="col-span-3">LOCAL ADDRESS</div>
          <div className="col-span-3">REMOTE ADDRESS</div>
          <div className="col-span-2">STATE</div>
          <div className="col-span-2">PID</div>
          <div className="col-span-2">PROCESS</div>
        </div>
        <div className="max-h-60 overflow-y-auto">
          {connections.map((c, i) =>
          <div
            key={i}
            className="grid grid-cols-12 gap-2 px-3 py-1.5 text-xs font-mono items-center"
            style={{
              backgroundColor:
              i % 2 === 0 ? 'var(--bg-primary)' : 'transparent'
            }}>

              <div
              className="col-span-3 truncate"
              style={{
                color: 'var(--text-primary)'
              }}>

                {c.local}
              </div>
              <div
              className="col-span-3 truncate"
              style={{
                color: 'var(--text-muted)'
              }}>

                {c.remote}
              </div>
              <div
              className="col-span-2"
              style={{
                color:
                c.state === 'LISTEN' ?
                'var(--ansi-green)' :
                c.state === 'ESTABLISHED' ?
                'var(--ansi-blue)' :
                'var(--text-muted)'
              }}>

                {c.state}
              </div>
              <div
              className="col-span-2"
              style={{
                color: 'var(--ansi-yellow)'
              }}>

                {c.pid}
              </div>
              <div
              className="col-span-2"
              style={{
                color: 'var(--text-primary)'
              }}>

                {c.process}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Interfaces & Firewall */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div
          className="border p-3 space-y-3"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-secondary)'
          }}>

          <div
            className="text-xs font-bold border-b pb-2"
            style={{
              borderColor: 'var(--border-color)',
              color: 'var(--text-muted)'
            }}>

            NETWORK INTERFACES
          </div>
          {[
          {
            name: 'eth0',
            ip: '192.168.1.42',
            mac: '00:1A:2B:3C:4D:5E',
            rx: '1.2 GB',
            tx: '450 MB'
          },
          {
            name: 'lo',
            ip: '127.0.0.1',
            mac: '00:00:00:00:00:00',
            rx: '45 MB',
            tx: '45 MB'
          }].
          map((iface) =>
          <div key={iface.name} className="text-xs space-y-1">
              <div className="flex justify-between">
                <span
                style={{
                  color: 'var(--ansi-green)',
                  fontWeight: 'bold'
                }}>

                  {iface.name}
                </span>
                <span
                style={{
                  color: 'var(--text-muted)'
                }}>

                  {iface.mac}
                </span>
              </div>
              <div
              className="pl-2 border-l-2"
              style={{
                borderColor: 'var(--border-color)'
              }}>

                <div
                style={{
                  color: 'var(--text-primary)'
                }}>

                  inet {iface.ip}
                </div>
                <div
                style={{
                  color: 'var(--text-muted)'
                }}>

                  RX: {iface.rx} | TX: {iface.tx}
                </div>
              </div>
            </div>
          )}
        </div>

        <div
          className="border p-3 space-y-3"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-secondary)'
          }}>

          <div
            className="text-xs font-bold border-b pb-2 flex justify-between"
            style={{
              borderColor: 'var(--border-color)',
              color: 'var(--text-muted)'
            }}>

            <span>FIREWALL STATUS</span>
            <span className="px-1.5 py-0.5 text-[9px] bg-[rgba(0,255,65,0.1)] text-[var(--ansi-green)]">
              ACTIVE
            </span>
          </div>
          <div className="space-y-2 text-xs">
            <div className="flex justify-between">
              <span
                style={{
                  color: 'var(--text-muted)'
                }}>

                Rules Active
              </span>
              <span
                style={{
                  color: 'var(--text-primary)'
                }}>

                247
              </span>
            </div>
            <div className="flex justify-between">
              <span
                style={{
                  color: 'var(--text-muted)'
                }}>

                Blocked Today
              </span>
              <span
                style={{
                  color: 'var(--ansi-red)'
                }}>

                12
              </span>
            </div>
            <div className="flex justify-between">
              <span
                style={{
                  color: 'var(--text-muted)'
                }}>

                Last Updated
              </span>
              <span
                style={{
                  color: 'var(--text-primary)'
                }}>

                04:22:15
              </span>
            </div>
            <div
              className="pt-2 border-t"
              style={{
                borderColor: 'var(--border-color)'
              }}>

              <div
                className="text-[10px] mb-1"
                style={{
                  color: 'var(--ansi-blue)'
                }}>

                DNS RESOLVERS
              </div>
              <div
                style={{
                  color: 'var(--text-primary)'
                }}>

                1.1.1.1, 8.8.8.8
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>);

}