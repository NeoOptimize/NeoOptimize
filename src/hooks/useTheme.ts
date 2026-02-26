import { useState, useEffect } from 'react';

type Theme = 'dark' | 'light' | 'system';

export function useTheme() {
  const [theme, setTheme] = useState<Theme>(() => {
    const saved = localStorage.getItem('neo-theme');
    return saved as Theme || 'dark';
  });

  useEffect(() => {
    const root = document.documentElement;
    const systemDark = window.matchMedia('(prefers-color-scheme: dark)').matches;

    const appliedTheme =
    theme === 'system' ? systemDark ? 'dark' : 'light' : theme;

    if (appliedTheme === 'dark') {
      root.removeAttribute('data-theme');
      root.classList.add('dark');
    } else {
      root.setAttribute('data-theme', 'light');
      root.classList.remove('dark');
    }

    localStorage.setItem('neo-theme', theme);
  }, [theme]);

  return { theme, setTheme };
}