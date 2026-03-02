import { useEffect, useMemo } from 'react';
import { HelpCircle, Search } from 'lucide-react';
import { useSystemStats } from '../hooks/SystemStatsContext';
import { SectionId, UIMode, visibleNavItems } from '../types/ui';

interface FileTreeNavProps {
  activeSection: SectionId;
  onSectionChange: (id: SectionId) => void;
  uiMode: UIMode;
  onModeChange: (mode: UIMode) => void;
}

export function FileTreeNav({ activeSection, onSectionChange, uiMode, onModeChange }: FileTreeNavProps) {
  const { loadAvg, tasks, uptime, kernel, securityAvailable } = useSystemStats();

  const menuItems = useMemo(
    () => visibleNavItems(uiMode).filter((item) => item.id !== 'security' || securityAvailable),
    [uiMode, securityAvailable]
  );

  useEffect(() => {
    if (!menuItems.some((item) => item.id === activeSection)) {
      onSectionChange('dashboard');
    }
  }, [menuItems, activeSection, onSectionChange]);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement).tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      const n = Number.parseInt(e.key, 10);
      if (!Number.isFinite(n) || n < 1 || n > menuItems.length) return;
      onSectionChange(menuItems[n - 1].id);
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [menuItems, onSectionChange]);

  return (
    <nav
      className="w-64 fixed left-0 top-14 bottom-0 hidden md:flex flex-col font-mono text-xs"
      style={{
        backgroundColor: 'var(--bg-secondary)',
        borderRight: '1px solid var(--border-color)'
      }}
    >
      <div className="px-4 py-3" style={{ borderBottom: '1px solid var(--border-color)' }}>
        <div className="flex items-center gap-2">
          <span style={{ color: 'var(--ansi-green)', fontWeight: 'bold' }}>$</span>
          <span style={{ color: 'var(--text-primary)' }}>neooptimize --adaptive-ui</span>
        </div>
        <div className="mt-3 flex gap-2">
          <button
            onClick={() => onModeChange('simple')}
            className="px-2 py-1 border text-[10px] font-bold"
            style={{
              borderColor: uiMode === 'simple' ? 'var(--ansi-cyan)' : 'var(--border-color)',
              color: uiMode === 'simple' ? 'var(--ansi-cyan)' : 'var(--text-muted)'
            }}
          >
            SIMPLE
          </button>
          <button
            onClick={() => onModeChange('advanced')}
            className="px-2 py-1 border text-[10px] font-bold"
            style={{
              borderColor: uiMode === 'advanced' ? 'var(--ansi-green)' : 'var(--border-color)',
              color: uiMode === 'advanced' ? 'var(--ansi-green)' : 'var(--text-muted)'
            }}
          >
            ADVANCED
          </button>
        </div>
      </div>

      <div className="flex-1 py-2 overflow-y-auto">
        <div className="flex flex-col">
          {menuItems.map((item, idx) => (
            <button
              key={item.id}
              onClick={() => onSectionChange(item.id)}
              className="group flex items-center px-4 py-2 w-full text-left transition-colors"
              style={{
                backgroundColor: activeSection === item.id ? 'var(--accent-primary)' : 'transparent'
              }}
            >
              <div className="flex items-center gap-3 w-full">
                <span
                  style={{
                    color: activeSection === item.id ? 'var(--bg-primary)' : 'var(--ansi-yellow)',
                    fontWeight: 'bold'
                  }}
                >
                  [{idx + 1}]
                </span>
                <span
                  className="font-bold"
                  style={{
                    color: activeSection === item.id ? 'var(--bg-primary)' : 'var(--text-primary)'
                  }}
                >
                  {item.label}/
                </span>
                <span
                  className="hidden xl:inline-block ml-auto opacity-70"
                  style={{
                    color: activeSection === item.id ? 'var(--bg-primary)' : 'var(--text-muted)'
                  }}
                >
                  {item.desc}
                </span>
              </div>
            </button>
          ))}
        </div>
      </div>

      <div
        className="p-4 space-y-2"
        style={{
          borderTop: '1px solid var(--border-color)',
          backgroundColor: 'var(--bg-tertiary)'
        }}
      >
        <div className="flex justify-between">
          <span style={{ color: 'var(--ansi-blue)' }}>KERNEL</span>
          <span style={{ color: 'var(--text-muted)' }}>{kernel}</span>
        </div>
        <div className="flex justify-between">
          <span style={{ color: 'var(--ansi-blue)' }}>UPTIME</span>
          <span style={{ color: 'var(--text-muted)' }}>{uptime}</span>
        </div>
        <div className="flex justify-between">
          <span style={{ color: 'var(--ansi-blue)' }}>LOAD</span>
          <span style={{ color: 'var(--text-muted)' }}>{loadAvg.map((n) => n.toFixed(2)).join(' ')}</span>
        </div>
        <div className="flex justify-between">
          <span style={{ color: 'var(--ansi-blue)' }}>TASKS</span>
          <span style={{ color: 'var(--text-muted)' }}>{tasks} total</span>
        </div>
      </div>

      <div
        className="px-4 py-3 text-[10px]"
        style={{
          borderTop: '1px solid var(--border-color)',
          color: 'var(--text-muted)'
        }}
      >
        <div className="flex flex-wrap gap-3 mb-2">
          <span>[1-7] jump</span>
          <span>[f] log filter</span>
          <span>[c] clear log</span>
        </div>
        <div className="flex items-center justify-between pt-2 border-t border-[var(--border-color)]">
          <span className="flex items-center gap-1">
            <HelpCircle size={10} /> adaptive
          </span>
          <span className="flex items-center gap-1">
            <Search size={10} /> lookup
          </span>
        </div>
      </div>
    </nav>
  );
}
