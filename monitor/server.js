import express from 'express';
import bodyParser from 'body-parser';
import cors from 'cors';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const app = express();
app.use(cors());
app.use(bodyParser.json({ limit: '6mb' }));

const PORT = Number(process.env.NEOMONITOR_PORT || 4411);
const DEFAULT_ADMIN_TOKEN = 'neo-monitor-admin';
const ADMIN_TOKEN = String(process.env.NEOMONITOR_ADMIN_TOKEN || DEFAULT_ADMIN_TOKEN);
const AUTO_REGISTER = String(process.env.NEOMONITOR_AUTO_REGISTER || '1') !== '0';

const dataDir = path.join(__dirname, 'data');
const diagnosticsDir = path.join(dataDir, 'diagnostics');
const storeFile = path.join(dataDir, 'store.json');
const publicDir = path.join(__dirname, 'public');

const allowedActionTypes = new Set([
  'ping',
  'readiness',
  'quick-safe-clean',
  'registry-safe-scan',
  'backup-now',
  'clear-logs',
  'diagnostics-send'
]);

function ensureDirs() {
  if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });
  if (!fs.existsSync(diagnosticsDir)) fs.mkdirSync(diagnosticsDir, { recursive: true });
}

function loadStore() {
  try {
    ensureDirs();
    if (!fs.existsSync(storeFile)) {
      return {
        createdAt: new Date().toISOString(),
        sequence: 0,
        agents: {},
        diagnostics: []
      };
    }
    const raw = JSON.parse(fs.readFileSync(storeFile, 'utf-8'));
    return {
      createdAt: raw.createdAt || new Date().toISOString(),
      sequence: Number(raw.sequence || 0),
      agents: raw.agents && typeof raw.agents === 'object' ? raw.agents : {},
      diagnostics: Array.isArray(raw.diagnostics) ? raw.diagnostics : []
    };
  } catch {
    return {
      createdAt: new Date().toISOString(),
      sequence: 0,
      agents: {},
      diagnostics: []
    };
  }
}

let store = loadStore();

function saveStore() {
  ensureDirs();
  fs.writeFileSync(storeFile, JSON.stringify(store, null, 2), 'utf-8');
}

function nextId(prefix = 'id') {
  store.sequence += 1;
  return `${prefix}-${Date.now()}-${store.sequence}`;
}

function sanitizeAgentSummary(agent) {
  return {
    id: agent.id,
    keyMasked: agent.key ? '***' : '',
    registeredAt: agent.registeredAt || null,
    lastSeenAt: agent.lastSeenAt || null,
    lastIp: agent.lastIp || '',
    appVersion: agent.lastSnapshot?.app?.version || '-',
    hostname: agent.lastSnapshot?.machine?.hostname || '-',
    os: `${agent.lastSnapshot?.machine?.platform || '-'} ${agent.lastSnapshot?.machine?.release || ''}`.trim(),
    arch: agent.lastSnapshot?.machine?.arch || '-',
    admin: Boolean(agent.lastSnapshot?.machine?.admin),
    monitorStatus: agent.status || 'unknown',
    pendingActions: Array.isArray(agent.actions) ? agent.actions.filter((a) => a.status === 'queued').length : 0,
    finishedActions: Array.isArray(agent.actions) ? agent.actions.filter((a) => a.status === 'done' || a.status === 'failed').length : 0
  };
}

function adminAuth(req, res, next) {
  const token = String(req.headers['x-admin-token'] || req.query.token || '');
  if (!token || token !== ADMIN_TOKEN) return res.status(401).send({ ok: false, error: 'unauthorized admin token' });
  return next();
}

function getOrCreateAgent(agentId, agentKey, req) {
  const id = String(agentId || '').trim();
  if (!id) return { ok: false, error: 'missing agentId' };
  let agent = store.agents[id];
  if (!agent) {
    if (!AUTO_REGISTER) return { ok: false, error: 'agent not registered' };
    if (!agentKey) return { ok: false, error: 'missing agent key for first registration' };
    agent = {
      id,
      key: String(agentKey),
      registeredAt: new Date().toISOString(),
      lastSeenAt: null,
      lastIp: '',
      status: 'online',
      actions: [],
      heartbeats: [],
      diagnostics: [],
      lastSnapshot: null
    };
    store.agents[id] = agent;
  } else if (agent.key !== String(agentKey || '')) {
    return { ok: false, error: 'invalid agent key' };
  }
  agent.lastIp = String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '');
  return { ok: true, agent };
}

app.get('/', (_req, res) => {
  return res.sendFile(path.join(publicDir, 'index.html'));
});

app.get('/api/health', (_req, res) => {
  return res.send({
    ok: true,
    service: 'NeoMonitor',
    time: new Date().toISOString(),
    agentCount: Object.keys(store.agents || {}).length
  });
});

app.post('/api/agent/heartbeat', (req, res) => {
  const body = req.body || {};
  const agentId = String(req.headers['x-agent-id'] || body.agentId || '').trim();
  const agentKey = String(req.headers['x-agent-key'] || body.agentKey || '').trim();
  const auth = getOrCreateAgent(agentId, agentKey, req);
  if (!auth.ok) return res.status(401).send({ ok: false, error: auth.error });

  const agent = auth.agent;
  const now = new Date().toISOString();
  const snapshot = body.device && typeof body.device === 'object' ? body.device : {};
  agent.lastSeenAt = now;
  agent.status = 'online';
  agent.lastSnapshot = snapshot;
  if (!Array.isArray(agent.heartbeats)) agent.heartbeats = [];
  agent.heartbeats.push({ at: now, trigger: String(body.trigger || 'unknown'), appVersion: String(body.appVersion || '-') });
  if (agent.heartbeats.length > 500) agent.heartbeats.shift();

  const results = Array.isArray(body.actionResults) ? body.actionResults : [];
  results.forEach((r) => {
    const rid = String(r.id || '').trim();
    const hit = (agent.actions || []).find((a) => String(a.id) === rid);
    if (hit) {
      hit.status = r.ok ? 'done' : 'failed';
      hit.finishedAt = String(r.at || now);
      hit.result = r.result || r;
    }
  });

  const actions = (agent.actions || []).filter((a) => a.status === 'queued').slice(0, 8).map((a) => {
    a.status = 'sent';
    a.sentAt = now;
    return { id: a.id, type: a.type, payload: a.payload || {} };
  });

  saveStore();
  return res.send({ ok: true, serverTime: now, actions });
});

app.post('/api/agent/diagnostics', (req, res) => {
  const body = req.body || {};
  const agentId = String(req.headers['x-agent-id'] || body.agentId || '').trim();
  const agentKey = String(req.headers['x-agent-key'] || body.agentKey || '').trim();
  const auth = getOrCreateAgent(agentId, agentKey, req);
  if (!auth.ok) return res.status(401).send({ ok: false, error: auth.error });

  const id = String(body.id || nextId('diag'));
  const out = path.join(diagnosticsDir, `${id}.json`);
  fs.writeFileSync(out, JSON.stringify(body, null, 2), 'utf-8');

  const meta = {
    id,
    agentId,
    at: new Date().toISOString(),
    path: out,
    logs: Array.isArray(body.logs) ? body.logs.length : 0
  };
  store.diagnostics.push(meta);
  if (store.diagnostics.length > 2000) store.diagnostics.shift();
  auth.agent.diagnostics = auth.agent.diagnostics || [];
  auth.agent.diagnostics.push(meta);
  if (auth.agent.diagnostics.length > 500) auth.agent.diagnostics.shift();
  saveStore();
  return res.send({ ok: true, id, path: out });
});

app.get('/api/admin/agents', adminAuth, (_req, res) => {
  const agents = Object.values(store.agents || {}).map((a) => sanitizeAgentSummary(a)).sort((a, b) => String(b.lastSeenAt || '').localeCompare(String(a.lastSeenAt || '')));
  return res.send({ ok: true, agents, count: agents.length });
});

app.get('/api/admin/agents/:id', adminAuth, (req, res) => {
  const id = String(req.params.id || '').trim();
  const agent = store.agents[id];
  if (!agent) return res.status(404).send({ ok: false, error: 'agent not found' });
  return res.send({
    ok: true,
    agent: {
      summary: sanitizeAgentSummary(agent),
      snapshot: agent.lastSnapshot || {},
      actions: (agent.actions || []).slice(-300),
      heartbeats: (agent.heartbeats || []).slice(-200),
      diagnostics: (agent.diagnostics || []).slice(-100)
    }
  });
});

app.post('/api/admin/agents/:id/actions', adminAuth, (req, res) => {
  const id = String(req.params.id || '').trim();
  const agent = store.agents[id];
  if (!agent) return res.status(404).send({ ok: false, error: 'agent not found' });
  const type = String(req.body?.type || '').trim().toLowerCase();
  if (!allowedActionTypes.has(type)) return res.status(400).send({ ok: false, error: `unsupported action type: ${type}` });
  const action = {
    id: nextId('action'),
    type,
    payload: req.body?.payload && typeof req.body.payload === 'object' ? req.body.payload : {},
    status: 'queued',
    createdAt: new Date().toISOString(),
    sentAt: null,
    finishedAt: null,
    result: null
  };
  agent.actions = agent.actions || [];
  agent.actions.push(action);
  if (agent.actions.length > 1500) agent.actions.shift();
  saveStore();
  return res.send({ ok: true, action });
});

app.post('/api/admin/agents/:id/fix/basic', adminAuth, (req, res) => {
  const id = String(req.params.id || '').trim();
  const agent = store.agents[id];
  if (!agent) return res.status(404).send({ ok: false, error: 'agent not found' });
  const queue = ['backup-now', 'quick-safe-clean', 'registry-safe-scan', 'readiness'];
  const created = queue.map((type) => ({
    id: nextId('action'),
    type,
    payload: {},
    status: 'queued',
    createdAt: new Date().toISOString(),
    sentAt: null,
    finishedAt: null,
    result: null
  }));
  agent.actions = agent.actions || [];
  agent.actions.push(...created);
  if (agent.actions.length > 1500) {
    agent.actions = agent.actions.slice(-1500);
  }
  saveStore();
  return res.send({ ok: true, queued: created.length, actions: created });
});

app.delete('/api/admin/agents/:id/actions/:actionId', adminAuth, (req, res) => {
  const id = String(req.params.id || '').trim();
  const actionId = String(req.params.actionId || '').trim();
  const agent = store.agents[id];
  if (!agent) return res.status(404).send({ ok: false, error: 'agent not found' });
  const before = (agent.actions || []).length;
  agent.actions = (agent.actions || []).filter((a) => String(a.id) !== actionId);
  const removed = before - agent.actions.length;
  saveStore();
  return res.send({ ok: true, removed });
});

app.get('/api/admin/diagnostics', adminAuth, (_req, res) => {
  return res.send({ ok: true, diagnostics: (store.diagnostics || []).slice(-300).reverse() });
});

app.use((err, _req, res, next) => {
  void next;
  return res.status(500).send({ ok: false, error: String(err?.message || err || 'unknown') });
});

app.listen(PORT, () => {
  ensureDirs();
  saveStore();
  console.log(`NeoMonitor running on http://127.0.0.1:${PORT}`);
  console.log(`Admin token: ${ADMIN_TOKEN}`);

  // Security notice: warn loudly if the default admin token is in use
  if (ADMIN_TOKEN === DEFAULT_ADMIN_TOKEN) {
    const notice = `*** SECURITY WARNING: NeoMonitor is running with the default admin token. Set NEOMONITOR_ADMIN_TOKEN to a strong value before exposing this service. ***\n`;
    try {
      console.warn(notice);
      const noticePath = path.join(dataDir, 'SECURITY_NOTICE.txt');
      fs.appendFileSync(noticePath, `${new Date().toISOString()} - ${notice}\n`, 'utf-8');
    } catch (err) {
      // best-effort only
    }
  }
});
