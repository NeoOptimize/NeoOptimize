import { useEffect, useState } from 'react';
import { Globe, Sliders, Timer } from 'lucide-react';
import { Theme, useThemeContext } from '../../hooks/useThemeContext';
import { UIMode } from '../../types/ui';

interface SettingsPageProps {
  uiMode: UIMode;
  onModeChange: (mode: UIMode) => void;
}

function readLocal(key: string, fallback: string): string {
  try {
    const value = localStorage.getItem(key);
    return value ?? fallback;
  } catch {
    return fallback;
  }
}

export function SettingsPage({ uiMode, onModeChange }: SettingsPageProps) {
  const { theme, setTheme } = useThemeContext();
  const [language, setLanguage] = useState(readLocal('neo-language', 'id-ID'));
  const [autoClean, setAutoClean] = useState(readLocal('neo-auto-clean', 'off') === 'on');
  const [scheduleMinutes, setScheduleMinutes] = useState(Number(readLocal('neo-schedule-minutes', '60')) || 60);
  const [profileName, setProfileName] = useState(readLocal('neo-profile', 'default'));
  const [message, setMessage] = useState('');

  useEffect(() => {
    try {
      localStorage.setItem('neo-language', language);
      localStorage.setItem('neo-auto-clean', autoClean ? 'on' : 'off');
      localStorage.setItem('neo-schedule-minutes', String(scheduleMinutes));
      localStorage.setItem('neo-profile', profileName);
      setMessage('Settings saved locally.');
    } catch (err) {
      void err;
      setMessage('Unable to persist some local settings.');
    }
  }, [language, autoClean, scheduleMinutes, profileName]);

  const setThemeMode = (next: Theme) => {
    setTheme(next);
    setMessage(`Theme set to ${next}.`);
  };

  return (
    <div className="space-y-4">
      <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
        <span style={{ color: 'var(--ansi-green)', fontWeight: 700 }}>$</span>
        <span>neooptimize settings --mode --theme --scheduler</span>
      </div>

      {message && (
        <div
          className="px-3 py-2 text-xs border"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-tertiary)',
            color: 'var(--text-primary)'
          }}
        >
          {message}
        </div>
      )}

      <div className="border p-4 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-cyan)' }}>
          <Sliders size={14} /> Adaptive Mode
        </div>
        <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
          Simple menampilkan fitur inti. Advanced membuka modul lanjutan (system tools + security penuh).
        </div>
        <div className="flex gap-2">
          <button
            onClick={() => onModeChange('simple')}
            className="px-3 py-2 text-xs border font-bold"
            style={{
              borderColor: uiMode === 'simple' ? 'var(--ansi-cyan)' : 'var(--border-color)',
              color: uiMode === 'simple' ? 'var(--ansi-cyan)' : 'var(--text-muted)'
            }}
          >
            Simple
          </button>
          <button
            onClick={() => onModeChange('advanced')}
            className="px-3 py-2 text-xs border font-bold"
            style={{
              borderColor: uiMode === 'advanced' ? 'var(--ansi-green)' : 'var(--border-color)',
              color: uiMode === 'advanced' ? 'var(--ansi-green)' : 'var(--text-muted)'
            }}
          >
            Advanced
          </button>
        </div>
      </div>

      <div className="border p-4 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-yellow)' }}>
          <Globe size={14} /> Theme & Language
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div>
            <div className="text-[11px] mb-1" style={{ color: 'var(--text-muted)' }}>Theme</div>
            <div className="flex gap-2">
              <button
                onClick={() => setThemeMode('dark')}
                className="px-2 py-1 text-[11px] border"
                style={{
                  borderColor: theme === 'dark' ? 'var(--ansi-green)' : 'var(--border-color)',
                  color: theme === 'dark' ? 'var(--ansi-green)' : 'var(--text-muted)'
                }}
              >
                Dark
              </button>
              <button
                onClick={() => setThemeMode('light')}
                className="px-2 py-1 text-[11px] border"
                style={{
                  borderColor: theme === 'light' ? 'var(--ansi-green)' : 'var(--border-color)',
                  color: theme === 'light' ? 'var(--ansi-green)' : 'var(--text-muted)'
                }}
              >
                Light
              </button>
              <button
                onClick={() => setThemeMode('system')}
                className="px-2 py-1 text-[11px] border"
                style={{
                  borderColor: theme === 'system' ? 'var(--ansi-green)' : 'var(--border-color)',
                  color: theme === 'system' ? 'var(--ansi-green)' : 'var(--text-muted)'
                }}
              >
                System
              </button>
            </div>
          </div>
          <div>
            <div className="text-[11px] mb-1" style={{ color: 'var(--text-muted)' }}>Language</div>
            <select
              value={language}
              onChange={(e) => setLanguage(e.target.value)}
              className="w-full px-2 py-1 text-xs border bg-transparent"
              style={{ borderColor: 'var(--border-color)', color: 'var(--text-primary)' }}
            >
              <option value="id-ID">Indonesia</option>
              <option value="en-US">English</option>
            </select>
          </div>
        </div>
      </div>

      <div className="border p-4 space-y-3" style={{ borderColor: 'var(--border-color)', backgroundColor: 'var(--bg-secondary)' }}>
        <div className="text-xs font-bold flex items-center gap-2" style={{ color: 'var(--ansi-blue)' }}>
          <Timer size={14} /> Scheduler
        </div>
        <label className="flex items-center gap-2 text-xs" style={{ color: 'var(--text-primary)' }}>
          <input type="checkbox" checked={autoClean} onChange={(e) => setAutoClean(e.target.checked)} />
          Auto clean/optimize in background
        </label>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div>
            <div className="text-[11px] mb-1" style={{ color: 'var(--text-muted)' }}>Interval (minutes)</div>
            <input
              type="number"
              min={5}
              max={720}
              value={scheduleMinutes}
              onChange={(e) => setScheduleMinutes(Math.max(5, Math.min(720, Number(e.target.value) || 60)))}
              className="w-full px-2 py-1 text-xs border bg-transparent"
              style={{ borderColor: 'var(--border-color)', color: 'var(--text-primary)' }}
            />
          </div>
          <div>
            <div className="text-[11px] mb-1" style={{ color: 'var(--text-muted)' }}>Profile Name</div>
            <input
              value={profileName}
              onChange={(e) => setProfileName(e.target.value || 'default')}
              className="w-full px-2 py-1 text-xs border bg-transparent"
              style={{ borderColor: 'var(--border-color)', color: 'var(--text-primary)' }}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
