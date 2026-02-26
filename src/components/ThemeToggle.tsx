import React from 'react';
import { Sun, Moon, Monitor } from 'lucide-react';
import { useThemeContext, Theme } from '../hooks/useThemeContext';
interface ToggleOption {
  value: Theme;
  icon: React.ReactNode;
  label: string;
  short: string;
}
const options: ToggleOption[] = [
{
  value: 'light',
  icon: <Sun size={12} />,
  label: 'Light Terminal',
  short: 'LIT'
},
{
  value: 'system',
  icon: <Monitor size={12} />,
  label: 'System',
  short: 'SYS'
},
{
  value: 'dark',
  icon: <Moon size={12} />,
  label: 'Dark Terminal',
  short: 'DRK'
}];

export function ThemeToggle() {
  const { theme, setTheme } = useThemeContext();
  return (
    <div
      className="flex items-center border text-xs"
      style={{
        borderColor: 'var(--border-color)',
        backgroundColor: 'var(--bg-secondary)'
      }}>

      {options.map((opt, i) =>
      <button
        key={opt.value}
        onClick={() => setTheme(opt.value)}
        title={opt.label}
        className="flex items-center gap-1 px-2 py-1.5 transition-all duration-200 font-mono"
        style={{
          backgroundColor:
          theme === opt.value ? 'var(--accent-primary)' : 'transparent',
          color:
          theme === opt.value ? 'var(--bg-primary)' : 'var(--text-muted)',
          borderRight:
          i < options.length - 1 ? '1px solid var(--border-color)' : 'none',
          fontWeight: theme === opt.value ? 700 : 400
        }}>

          {opt.icon}
          <span className="hidden sm:inline">{opt.short}</span>
        </button>
      )}
    </div>);

}