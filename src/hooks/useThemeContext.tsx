import React, {
  useCallback,
  useEffect,
  useState,
  createContext,
  useContext } from
'react';
export type Theme = 'dark' | 'light' | 'system';
interface ThemeContextValue {
  theme: Theme;
  setTheme: (t: Theme) => void;
  resolvedTheme: 'dark' | 'light';
}
const ThemeContext = createContext<ThemeContextValue>({
  theme: 'dark',
  setTheme: () => {},
  resolvedTheme: 'dark'
});
export function ThemeProvider({ children }: {children: React.ReactNode;}) {
  const [theme, setThemeState] = useState<Theme>(() => {
    try {
      return localStorage.getItem('neo-theme') as Theme || 'dark';
    } catch {
      return 'dark';
    }
  });
  const [flickering, setFlickering] = useState(false);
  const getSystemTheme = (): 'dark' | 'light' => {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ?
    'dark' :
    'light';
  };
  const resolvedTheme: 'dark' | 'light' =
  theme === 'system' ? getSystemTheme() : theme;
  const applyTheme = useCallback((resolved: 'dark' | 'light') => {
    const root = document.documentElement;
    if (resolved === 'light') {
      root.setAttribute('data-theme', 'light');
    } else {
      root.removeAttribute('data-theme');
    }
  }, []);
  useEffect(() => {
    applyTheme(resolvedTheme);
    try {
      localStorage.setItem('neo-theme', theme);
    } catch {}
  }, [theme, resolvedTheme, applyTheme]);
  // Listen for system preference changes
  useEffect(() => {
    if (theme !== 'system') return;
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const handler = () => applyTheme(mq.matches ? 'dark' : 'light');
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, [theme, applyTheme]);
  const setTheme = useCallback((t: Theme) => {
    // Trigger flicker effect
    const body = document.body;
    body.classList.add('theme-flicker');
    setTimeout(() => body.classList.remove('theme-flicker'), 400);
    setThemeState(t);
  }, []);
  return (
    <ThemeContext.Provider
      value={{
        theme,
        setTheme,
        resolvedTheme
      }}>

      {children}
    </ThemeContext.Provider>);

}
export function useThemeContext() {
  return useContext(ThemeContext);
}