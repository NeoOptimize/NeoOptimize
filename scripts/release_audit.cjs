#!/usr/bin/env node
const { spawn } = require('child_process');

const BASE = process.env.NEO_AUDIT_BASE || 'http://127.0.0.1:3322';
const TIMEOUT_MS = 12000;

const checks = [
  { id: 'system-overview', path: '/api/system/overview' },
  { id: 'logs', path: '/api/logs?limit=20' },
  { id: 'reports', path: '/api/reports' },
  { id: 'security-status', path: '/api/security/status' },
  { id: 'scheduler', path: '/api/scheduler/tasks' },
  { id: 'config', path: '/api/config' },
  { id: 'readiness', path: '/api/release/readiness' },
  { id: 'diag-settings', path: '/api/diagnostics/settings' },
  { id: 'diag-preview', path: '/api/diagnostics/preview' },
  { id: 'monitor-agent', path: '/api/monitor/agent/status' }
];

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchJson(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, { signal: controller.signal });
    const text = await res.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch {}
    return { ok: res.ok, status: res.status, json, body: text };
  } finally {
    clearTimeout(timer);
  }
}

async function run() {
  const backend = spawn(process.execPath, ['backend/server.js'], { cwd: process.cwd(), windowsHide: true });
  backend.stdout.on('data', () => {});
  backend.stderr.on('data', () => {});
  backend.on('error', (err) => {
    console.error(`[audit] backend spawn error: ${String(err?.message || err)}`);
  });

  await sleep(1800);

  const rows = [];
  let pass = 0;
  let fail = 0;
  for (const c of checks) {
    try {
      const result = await fetchJson(`${BASE}${c.path}`);
      let isOk = Boolean(result.ok && result.json && result.json.ok !== false);
      let detail = isOk ? 'ok' : (result.json?.error || result.body || 'failed');
      if (isOk && c.id === 'readiness') {
        const ready = result.json?.readiness;
        if (!ready || ready.ok !== true) {
          isOk = false;
          detail = `readiness not green (score=${ready?.score ?? 0}, errors=${ready?.failed?.errors ?? 'n/a'}, warnings=${ready?.failed?.warnings ?? 'n/a'})`;
        }
      }
      if (isOk) pass += 1;
      else fail += 1;
      rows.push({ id: c.id, ok: isOk, status: result.status, detail });
    } catch (err) {
      fail += 1;
      rows.push({ id: c.id, ok: false, status: 0, detail: String(err?.message || err) });
    }
  }

  const summary = { total: checks.length, pass, fail, at: new Date().toISOString() };
  console.log(JSON.stringify({ summary, rows }, null, 2));

  try {
    backend.kill();
  } catch {}

  process.exit(fail > 0 ? 1 : 0);
}

run().catch((err) => {
  console.error(String(err?.message || err));
  process.exit(1);
});
