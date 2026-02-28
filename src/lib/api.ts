const ENV_BASE = (import.meta as any).env?.VITE_API_BASE_URL as string | undefined;

function inferBase(): string {
  if (typeof window === 'undefined') return '';
  if (window.location.protocol === 'file:') return 'http://127.0.0.1:3322';
  return '';
}

const base = (ENV_BASE ?? inferBase()).replace(/\/+$/, '');

export function apiUrl(path: string): string {
  if (/^https?:\/\//i.test(path)) return path;
  const p = path.startsWith('/') ? path : `/${path}`;
  return `${base}${p}`;
}

export function apiFetch(input: string, init?: RequestInit) {
  return fetch(apiUrl(input), init);
}

export function apiEventSource(path: string): EventSource {
  return new EventSource(apiUrl(path));
}
