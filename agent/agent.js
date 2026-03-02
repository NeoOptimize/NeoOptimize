import os from 'node:os';
import http from 'node:http';
import https from 'node:https';
import { URL } from 'node:url';

const MONITOR_URL = process.env.NEOMONITOR_URL || 'http://127.0.0.1:4411';
const AGENT_ID = process.env.NEO_AGENT_ID || `agent-${os.hostname()}-${Date.now()}`;
const AGENT_KEY = process.env.NEO_AGENT_KEY || 'temporary-agent-key';

function fetchJson(url, opts = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const lib = u.protocol === 'https:' ? https : http;
    const body = opts.body ? JSON.stringify(opts.body) : null;
    const headers = Object.assign({ 'Content-Type': 'application/json' }, opts.headers || {});
    const req = lib.request(u, { method: opts.method || 'GET', headers }, (res) => {
      let data = '';
      res.setEncoding('utf8');
      res.on('data', (c) => { data += c; });
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: data ? JSON.parse(data) : null }); }
        catch (err) { reject(err); }
      });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

async function sendHeartbeat() {
  try {
    const payload = {
      agentId: AGENT_ID,
      agentKey: AGENT_KEY,
      device: {
        hostname: os.hostname(),
        platform: os.platform(),
        release: os.release(),
        arch: os.arch(),
        cpus: os.cpus().length,
        memory: Math.round(os.totalmem() / 1024 / 1024)
      }
    };
    const url = `${MONITOR_URL.replace(/\/$/, '')}/api/agent/heartbeat`;
    const res = await fetchJson(url, { method: 'POST', body: payload });
    if (res && res.status >= 200 && res.status < 300) {
      const actions = res.body?.actions || [];
      if (actions.length) {
        console.log(new Date().toISOString(), 'received actions', actions.map(a => a.type));
        // execute simple dummy actions for PoC
        actions.forEach((a) => {
          // mark as done by reporting via diagnostics endpoint
          reportActionResult(a.id, true, { note: 'executed (poC)' });
        });
      }
    } else {
      console.warn('heartbeat failed', res && res.status);
    }
  } catch (err) {
    console.warn('heartbeat error', String(err));
  }
}

async function reportActionResult(id, ok, result) {
  try {
    const url = `${MONITOR_URL.replace(/\/$/, '')}/api/agent/heartbeat`;
    const payload = {
      agentId: AGENT_ID,
      agentKey: AGENT_KEY,
      actionResults: [{ id, ok, at: new Date().toISOString(), result }]
    };
    await fetchJson(url, { method: 'POST', body: payload });
  } catch (err) {
    void err;
  }
}

console.log('NeoOptimize Agent starting');
console.log('MONITOR_URL=', MONITOR_URL);
console.log('AGENT_ID=', AGENT_ID);

sendHeartbeat();
const hb = setInterval(sendHeartbeat, 10000);

process.on('SIGINT', () => {
  clearInterval(hb);
  console.log('Agent exiting');
  process.exit(0);
});
