
/** @type {import('tailwindcss').Config} */
export default {
  content: [
  './index.html',
  './src/**/*.{js,ts,jsx,tsx}'
],
  theme: {
    extend: {
      fontFamily: {
        mono: ['"JetBrains Mono"', '"Courier New"', 'monospace'],
        sans: ['"JetBrains Mono"', '"Courier New"', 'monospace'],
      },
      colors: {
        terminal: {
          bg:        'var(--bg-primary)',
          card:      'var(--bg-secondary)',
          surface:   'var(--bg-tertiary)',
          border:    'var(--border-color)',
          text:      'var(--text-primary)',
          secondary: 'var(--text-secondary)',
          muted:     'var(--text-muted)',
          accent:    'var(--accent-primary)',
          warning:   'var(--status-warning)',
          error:     'var(--status-error)',
          info:      'var(--status-info)',
        },
      },
      animation: {
        'blink': 'blink 0.8s step-end infinite',
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
      },
      keyframes: {
        blink: {
          '0%, 100%': { opacity: '1' },
          '50%': { opacity: '0' },
        },
      },
    },
  },
  plugins: [],
}
