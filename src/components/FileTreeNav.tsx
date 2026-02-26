import React, { useEffect, useState } from 'react';
import { Search, HelpCircle, CornerDownLeft } from 'lucide-react';
interface MenuItem {
  id: number;
  label: string;
  path: string;
  desc: string;
}
const menuItems: MenuItem[] = [
{
  id: 1,
  label: 'dashboard',
  path: '/',
  desc: 'System Overview'
},
{
  id: 2,
  label: 'processes',
  path: '/proc',
  desc: 'Process Manager'
},
{
  id: 3,
  label: 'network',
  path: '/net',
  desc: 'Network Monitor'
},
{
  id: 4,
  label: 'storage',
  path: '/mnt',
  desc: 'Disk & I/O'
},
{
  id: 5,
  label: 'config',
  path: '/etc',
  desc: 'System Config'
},
{
  id: 6,
  label: 'logs',
  path: '/var/log',
  desc: 'Event Logs'
},
{
  id: 7,
  label: 'security',
  path: '/sec',
  desc: 'Firewall & Auth'
},
{
  id: 8,
  label: 'scheduler',
  path: '/cron',
  desc: 'Task Scheduler'
}];

interface FileTreeNavProps {
  activeSection: number;
  onSectionChange: (id: number) => void;
}
export function FileTreeNav({
  activeSection,
  onSectionChange
}: FileTreeNavProps) {
  const [loadAvg, setLoadAvg] = useState([0.42, 0.38, 0.31]);
  const [tasks, setTasks] = useState(247);
  // Keyboard nav: 1-8 to select menu items
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement).tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      const n = parseInt(e.key);
      if (n >= 1 && n <= 8) onSectionChange(n);
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onSectionChange]);
  // Simulate system stats updates
  useEffect(() => {
    const interval = setInterval(() => {
      setLoadAvg((prev) =>
      prev.map((v) => Math.max(0.1, v + (Math.random() - 0.5) * 0.1))
      );
      setTasks((prev) =>
      Math.max(200, prev + Math.floor((Math.random() - 0.5) * 5))
      );
    }, 2000);
    return () => clearInterval(interval);
  }, []);
  return (
    <nav
      className="w-64 fixed left-0 top-14 bottom-0 hidden md:flex flex-col font-mono text-xs"
      style={{
        backgroundColor: 'var(--bg-secondary)',
        borderRight: '1px solid var(--border-color)'
      }}>

      {/* Header */}
      <div
        className="px-4 py-3"
        style={{
          borderBottom: '1px solid var(--border-color)'
        }}>

        <div className="flex items-center gap-2">
          <span
            style={{
              color: 'var(--ansi-green)',
              fontWeight: 'bold'
            }}>

            $
          </span>
          <span
            style={{
              color: 'var(--text-primary)'
            }}>

            ls -la /modules/
          </span>
        </div>
      </div>

      {/* Menu List */}
      <div className="flex-1 py-2 overflow-y-auto">
        <div className="flex flex-col">
          {menuItems.map((item) =>
          <button
            key={item.id}
            onClick={() => onSectionChange(item.id)}
            className="group flex items-center px-4 py-2 w-full text-left transition-colors relative"
            style={{
              backgroundColor:
              activeSection === item.id ?
              'var(--accent-primary)' :
              'transparent'
            }}>

              <div className="flex items-center gap-3 w-full">
                <span
                style={{
                  color:
                  activeSection === item.id ?
                  'var(--bg-primary)' :
                  'var(--ansi-yellow)',
                  fontWeight: 'bold'
                }}>

                  [{item.id}]
                </span>

                <span
                className="font-bold"
                style={{
                  color:
                  activeSection === item.id ?
                  'var(--bg-primary)' :
                  'var(--text-primary)'
                }}>

                  {item.label}/
                </span>

                <span
                className="hidden xl:inline-block ml-auto opacity-60"
                style={{
                  color:
                  activeSection === item.id ?
                  'var(--bg-primary)' :
                  'var(--text-muted)'
                }}>

                  {item.desc}
                </span>
              </div>
            </button>
          )}
        </div>
      </div>

      {/* System Status Block */}
      <div
        className="p-4 space-y-2"
        style={{
          borderTop: '1px solid var(--border-color)',
          backgroundColor: 'var(--bg-tertiary)'
        }}>

        <div className="flex justify-between">
          <span
            style={{
              color: 'var(--ansi-blue)'
            }}>

            KERNEL
          </span>
          <span
            style={{
              color: 'var(--text-muted)'
            }}>

            5.15.0-generic
          </span>
        </div>
        <div className="flex justify-between">
          <span
            style={{
              color: 'var(--ansi-blue)'
            }}>

            UPTIME
          </span>
          <span
            style={{
              color: 'var(--text-muted)'
            }}>

            04:22:11
          </span>
        </div>
        <div className="flex justify-between">
          <span
            style={{
              color: 'var(--ansi-blue)'
            }}>

            LOAD
          </span>
          <span
            style={{
              color: 'var(--text-muted)'
            }}>

            {loadAvg.map((n) => n.toFixed(2)).join(' ')}
          </span>
        </div>
        <div className="flex justify-between">
          <span
            style={{
              color: 'var(--ansi-blue)'
            }}>

            TASKS
          </span>
          <span
            style={{
              color: 'var(--text-muted)'
            }}>

            {tasks} total
          </span>
        </div>
      </div>

      {/* Footer / Hints */}
      <div
        className="px-4 py-3 text-[10px]"
        style={{
          borderTop: '1px solid var(--border-color)',
          color: 'var(--text-muted)'
        }}>

        <div className="flex flex-wrap gap-3 mb-2">
          <span>[↑↓] navigate</span>
          <span>[Enter] select</span>
          <span>[q] quit</span>
        </div>
        <div className="flex items-center justify-between pt-2 border-t border-[var(--border-color)]">
          <span className="flex items-center gap-1">
            <HelpCircle size={10} /> help
          </span>
          <span className="flex items-center gap-1">
            <Search size={10} /> search
          </span>
          <span className="flex items-center gap-1">
            <CornerDownLeft size={10} /> back
          </span>
        </div>
      </div>
    </nav>);

}