import { useEffect, useState } from 'react';
import { Search, HelpCircle, CornerDownLeft } from 'lucide-react';
import { useSystemStats } from '../hooks/SystemStatsContext';
import { apiFetch } from '../lib/api';
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
},
{
  id: 9,
  label: 'about',
  path: '/about',
  desc: 'Developer & Build'
}];

interface FileTreeNavProps {
  activeSection: number;
  onSectionChange: (id: number) => void;
}
export function FileTreeNav({
  activeSection,
  onSectionChange
}: FileTreeNavProps) {
  const { loadAvg, tasks, uptime, kernel } = useSystemStats();
  const [configPreview, setConfigPreview] = useState<string | null>(null);
  // Keyboard nav: 1-9 to select menu items
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement).tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      const n = parseInt(e.key);
      if (n >= 1 && n <= 9) onSectionChange(n);
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onSectionChange]);
    useEffect(() => {
      let mounted = true;
      if (activeSection === 5) {
        apiFetch('/api/config').then((r) => r.json()).then((j) => {
          if (!mounted) return;
          if (j.ok) {
            // show first 400 chars
            setConfigPreview(j.content.slice(0, 400));
          } else setConfigPreview('Failed to load: ' + String(j.error));
        }).catch((e) => { if (mounted) setConfigPreview(String(e)); });
      } else {
        setConfigPreview(null);
      }
      return () => { mounted = false; };
    }, [activeSection]);
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

      {/* Config preview when Config menu active */}
      {activeSection === 5 && (
        <div className="p-3 border-t" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-tertiary)' }}>
          <div className="text-xs font-bold mb-2" style={{ color: 'var(--ansi-blue)' }}>Loaded config (config.txt)</div>
          <div className="text-[11px] font-mono max-h-44 overflow-y-auto p-2" style={{ backgroundColor: 'var(--terminal-output-bg)', color: 'var(--text-muted)', border: '1px solid var(--border-color)' }}>
            {configPreview ?? 'Loading...'}
          </div>
        </div>
      )}

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

            {kernel}
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

            {uptime}
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
          <span>[1-9] jump</span>
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
