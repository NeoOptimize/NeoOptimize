import fs from 'fs';
import fsp from 'fs/promises';
import path from 'path';
import { execFile } from 'child_process';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const APP_ROOT = process.env.APP_ROOT ? path.resolve(process.env.APP_ROOT) : path.resolve(__dirname, '..', '..');
const APP_ASSET_ROOT = process.env.APP_ASSET_ROOT ? path.resolve(process.env.APP_ASSET_ROOT) : APP_ROOT;
const APP_DATA_ROOT = process.env.APP_DATA_ROOT ? path.resolve(process.env.APP_DATA_ROOT) : APP_ROOT;

const CLEAN_PATHS = {
  'System Temp': [
    '%WINDIR%\\Temp\\*',
    '%WINDIR%\\Prefetch\\*',
    '%WINDIR%\\Logs\\*.log',
    '%WINDIR%\\SoftwareDistribution\\Download\\*'
  ],
  'User Temp': [
    '%TEMP%\\*',
    '%TMP%\\*',
    '%LOCALAPPDATA%\\Temp\\*'
  ],
  'Thumbnail & Icon Cache': [
    '%LOCALAPPDATA%\\Microsoft\\Windows\\Explorer\\thumbcache_*.db',
    '%LOCALAPPDATA%\\Microsoft\\Windows\\Explorer\\iconcache_*.db'
  ],
  'Browser Cache': [
    '%LOCALAPPDATA%\\Google\\Chrome\\User Data\\Default\\Cache\\*',
    '%LOCALAPPDATA%\\Google\\Chrome\\User Data\\Default\\Code Cache\\*',
    '%LOCALAPPDATA%\\Microsoft\\Edge\\User Data\\Default\\Cache\\*',
    '%APPDATA%\\Mozilla\\Firefox\\Profiles\\*\\cache2\\*'
  ],
  'App Cache': [
    '%APPDATA%\\discord\\Cache\\*',
    'C:\\Program Files (x86)\\Steam\\appcache\\*',
    '%APPDATA%\\Adobe\\Common\\Media Cache\\*',
    '%LOCALAPPDATA%\\NVIDIA\\GLCache\\*'
  ],
  'Driver Leftovers': [
    'C:\\NVIDIA\\*',
    'C:\\AMD\\*',
    'C:\\Intel\\*'
  ],
  'Windows Error & Memory Dumps': [
    'C:\\Windows\\Minidump\\*.dmp',
    'C:\\Windows\\memory.dmp',
    '%LOCALAPPDATA%\\CrashDumps\\*'
  ],
  'Telemetry & Traces': [
    'C:\\Windows\\System32\\SleepStudy\\*',
    'C:\\ProgramData\\Microsoft\\Diagnosis\\ETLLogs\\AutoLogger\\*.etl'
  ]
};

const DUMP_ONLY_CATEGORIES = new Set(['Windows Error & Memory Dumps']);

const PRIVACY_REGISTRY_KEYS = [
  'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\RecentDocs',
  'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\RunMRU',
  'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\TypedPaths',
  'HKCU\\Software\\Microsoft\\Internet Explorer\\TypedURLs',
  'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Applets\\Paint\\Recent File List'
];

const DEFAULT_MAX_FILES = 10000;
const DEFAULT_MAX_DEPTH = 8;
const LOG_LIMIT = 6000;
const RESULT_LIMIT = 30000;
const BACKUP_LIMIT = 500;

function nowIso() {
  return new Date().toISOString();
}

function toKB(bytes) {
  return Math.round((Number(bytes) || 0) / 1024);
}

function chunkString(v, max = 150) {
  const s = String(v || '');
  if (s.length <= max) return s;
  return `${s.slice(0, Math.max(1, max - 3))}...`;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function expandEnvWindows(input) {
  return String(input || '').replace(/%([^%]+)%/g, (_, key) => process.env[key] || `%${key}%`);
}

function normalizeWinPath(input) {
  const expanded = expandEnvWindows(input).replace(/\//g, '\\');
  return path.normalize(expanded);
}

function escapeRegExp(s) {
  return String(s || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function wildcardToRegex(pattern) {
  const p = normalizeWinPath(pattern);
  const out = `^${escapeRegExp(p).replace(/\\\*/g, '.*').replace(/\\\?/g, '.')}\\?$`;
  return new RegExp(out, process.platform === 'win32' ? 'i' : '');
}

function wildcardRoot(pattern) {
  const p = normalizeWinPath(pattern);
  const parts = p.split('\\');
  const fixed = [];
  for (const seg of parts) {
    if (seg.includes('*') || seg.includes('?')) break;
    fixed.push(seg);
  }
  if (fixed.length === 0) return '';
  if (fixed.length === 1 && /^[A-Za-z]:$/.test(fixed[0])) return `${fixed[0]}\\`;
  return path.normalize(fixed.join('\\'));
}

async function fileExists(p) {
  try {
    await fsp.access(p, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

function runReg(args) {
  return new Promise((resolve) => {
    execFile('reg', args, { windowsHide: true, maxBuffer: 1024 * 1024 * 8, timeout: 15000 }, (err, stdout, stderr) => {
      resolve({
        ok: !err,
        stdout: String(stdout || ''),
        stderr: String(stderr || err?.message || '')
      });
    });
  });
}

function parseRegRows(stdout) {
  const rows = [];
  const lines = String(stdout || '').split(/\r?\n/);
  let currentKey = '';
  for (const line of lines) {
    const trimmed = line.trimEnd();
    if (!trimmed) continue;
    if (/^HKEY_/i.test(trimmed.trim())) {
      currentKey = trimmed.trim();
      continue;
    }
    const m = trimmed.match(/^\s{2,}([^\s].*?)\s{2,}(REG_\w+)\s{2,}(.*)$/i);
    if (!m || !currentKey) continue;
    rows.push({ key: currentKey, valueName: m[1].trim(), type: m[2].trim(), data: m[3].trim() });
  }
  return rows;
}

async function walkAndMatch(root, regex, maxDepth, maxFiles, stopRef) {
  const out = [];
  const stack = [{ dir: root, depth: 0 }];
  while (stack.length > 0 && out.length < maxFiles && !stopRef.stop) {
    const cur = stack.pop();
    if (!cur || cur.depth > maxDepth) continue;
    let entries = [];
    try {
      entries = await fsp.readdir(cur.dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      if (stopRef.stop || out.length >= maxFiles) break;
      const full = path.join(cur.dir, entry.name);
      if (entry.isDirectory()) {
        stack.push({ dir: full, depth: cur.depth + 1 });
        continue;
      }
      if (!entry.isFile()) continue;
      const normalized = normalizeWinPath(full);
      if (!regex.test(normalized)) continue;
      try {
        const st = await fsp.stat(full);
        out.push({ path: full, size: Number(st.size || 0) });
      } catch {}
    }
  }
  return out;
}

function backupDir() {
  return path.join(APP_DATA_ROOT, 'backend', 'backups');
}

function ensureBackupDir() {
  const dir = backupDir();
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  return dir;
}

export function createNeoTurboCleaner() {
  let running = false;
  let progress = 0;
  let total = 100;
  let mode = 'full';
  let dryRun = true;
  let statusMessage = 'idle';
  let stopRef = { stop: false };
  let lastRun = null;

  const listeners = {
    progress: [],
    log: [],
    done: [],
    fileFound: [],
    duplicateFound: [],
    registryIssue: [],
    backup: []
  };

  let files = [];
  let registry = [];
  let backups = [];
  let runLog = [];

  const emit = (name, payload) => {
    const l = listeners[name];
    if (!l) return;
    l.forEach((cb) => {
      try {
        cb(payload);
      } catch {}
    });
  };

  const log = (level, message, meta = {}) => {
    const entry = { time: nowIso(), level, message, meta };
    runLog.push(entry);
    if (runLog.length > LOG_LIMIT) runLog.shift();
    emit('log', { level, message, meta });
  };

  const setProgress = (value, meta = {}) => {
    progress = Math.max(0, Math.min(100, Math.floor(value)));
    emit('progress', { progress, total, mode, dryRun, statusMessage, ...meta });
  };

  async function maybeDelete(filePath) {
    if (dryRun) return { ok: true, action: 'would-delete' };
    try {
      await fsp.rm(filePath, { recursive: false, force: true });
      return { ok: true, action: 'deleted' };
    } catch (err) {
      return { ok: false, action: 'skip', error: String(err?.message || err) };
    }
  }

  async function scanJunk(opts = {}) {
    const maxFiles = Math.max(200, Math.min(DEFAULT_MAX_FILES, Number(opts.maxFiles || DEFAULT_MAX_FILES)));
    const maxDepth = Math.max(2, Math.min(12, Number(opts.maxDepth || DEFAULT_MAX_DEPTH)));
    const categories = Object.keys(CLEAN_PATHS).filter((name) => (mode === 'dump' ? DUMP_ONLY_CATEGORIES.has(name) : true));
    const jobs = [];
    categories.forEach((cat) => {
      (CLEAN_PATHS[cat] || []).forEach((pattern) => jobs.push({ category: cat, pattern }));
    });
    log('info', `NeoTurbo scan start mode=${mode} jobs=${jobs.length} dryRun=${dryRun}`);

    let processed = 0;
    for (let i = 0; i < jobs.length; i += 1) {
      if (stopRef.stop) break;
      const job = jobs[i];
      const regex = wildcardToRegex(job.pattern);
      const root = wildcardRoot(job.pattern);
      if (!root || !fs.existsSync(root)) {
        log('warn', `skip pattern root not found: ${job.pattern}`);
        setProgress(Math.floor(((i + 1) / Math.max(1, jobs.length)) * 90), { phase: 'scan', category: job.category });
        continue;
      }
      const found = await walkAndMatch(root, regex, maxDepth, maxFiles, stopRef);
      for (const f of found) {
        if (stopRef.stop) break;
        const result = await maybeDelete(f.path);
        const item = {
          path: f.path,
          sizeKB: toKB(f.size),
          category: job.category,
          action: result.action,
          ok: result.ok
        };
        files.push(item);
        if (files.length > RESULT_LIMIT) files.shift();
        emit('fileFound', item);
        processed += 1;
        if (result.ok) log('info', `${result.action} ${chunkString(f.path, 180)} (${item.sizeKB}KB)`, { category: job.category });
        else log('warn', `skip ${chunkString(f.path, 180)} (${chunkString(result.error, 120)})`, { category: job.category });
        if (processed % 40 === 0) await sleep(0);
      }
      const pct = Math.floor(((i + 1) / Math.max(1, jobs.length)) * 92);
      setProgress(pct, { phase: 'scan', category: job.category, processed });
    }
  }

  async function scanPrivacyRegistry() {
    if (process.platform !== 'win32') {
      log('warn', 'Registry privacy scan skipped: Windows only');
      return;
    }
    log('info', `NeoTurbo registry scan start keys=${PRIVACY_REGISTRY_KEYS.length} dryRun=${dryRun}`);
    for (let i = 0; i < PRIVACY_REGISTRY_KEYS.length; i += 1) {
      if (stopRef.stop) break;
      const key = PRIVACY_REGISTRY_KEYS[i];
      const q = await runReg(['query', key]);
      if (!q.ok) {
        log('warn', `registry query failed: ${key}`);
        continue;
      }
      const rows = parseRegRows(q.stdout).filter((row) => row.valueName !== '(Default)');
      if (rows.length === 0) continue;
      for (const row of rows) {
        if (stopRef.stop) break;
        let action = 'would-clear';
        let ok = true;
        let error = '';
        if (!dryRun) {
          const del = await runReg(['delete', row.key, '/v', row.valueName, '/f']);
          ok = del.ok;
          action = del.ok ? 'cleared' : 'failed-clear';
          if (!del.ok) error = del.stderr || del.stdout || 'delete failed';
        }
        const issue = {
          key: row.key,
          valueName: row.valueName,
          reason: 'privacy trace',
          action,
          ok,
          error: error ? chunkString(error, 180) : undefined
        };
        registry.push(issue);
        if (registry.length > RESULT_LIMIT) registry.shift();
        emit('registryIssue', issue);
        if (ok) log(action === 'cleared' ? 'ok' : 'warn', `registry ${action}: ${row.key}\\${row.valueName}`);
        else log('error', `registry clear failed: ${row.key}\\${row.valueName} (${chunkString(error, 120)})`);
      }
      setProgress(92 + Math.floor(((i + 1) / Math.max(1, PRIVACY_REGISTRY_KEYS.length)) * 7), { phase: 'registry' });
    }
  }

  function finalize(reason = 'completed') {
    running = false;
    stopRef.stop = false;
    statusMessage = reason === 'stopped' ? 'stopped' : 'idle';
    const reclaimedKB = files.reduce((sum, f) => sum + Number(f.sizeKB || 0), 0);
    lastRun = {
      time: nowIso(),
      mode,
      dryRun,
      files: files.length,
      registry: registry.length,
      reclaimedKB
    };
    const summary = {
      mode,
      dryRun,
      files: files.length,
      registry: registry.length,
      reclaimedKB,
      status: statusMessage
    };
    emit('done', summary);
    log('ok', `NeoTurbo finished mode=${mode} dryRun=${dryRun} files=${summary.files} reg=${summary.registry} reclaimed=${summary.reclaimedKB}KB`);
  }

  async function runMode(opts = {}) {
    try {
      if (mode === 'registry') {
        await scanPrivacyRegistry();
      } else {
        await scanJunk(opts);
        if (mode === 'full') await scanPrivacyRegistry();
      }
      if (stopRef.stop) {
        finalize('stopped');
        return;
      }
      setProgress(100, { phase: 'complete' });
      finalize('completed');
    } catch (err) {
      log('error', `NeoTurbo crash: ${String(err?.message || err)}`);
      finalize('stopped');
    }
  }

  function start(opts = {}) {
    if (running) return status();
    mode = String(opts.mode || 'full').toLowerCase();
    if (!['full', 'dump', 'registry'].includes(mode)) mode = 'full';
    dryRun = opts.dryRun !== false;
    running = true;
    progress = 0;
    total = 100;
    statusMessage = `scanning:${mode}`;
    stopRef = { stop: false };

    if (!opts.keepPreviousResults) {
      files = [];
      registry = [];
    }
    log('info', `NeoTurbo start mode=${mode} dryRun=${dryRun}`);
    runMode(opts);
    return status();
  }

  function stop() {
    if (!running) return status();
    stopRef.stop = true;
    statusMessage = 'stopping';
    log('warn', 'NeoTurbo stop requested');
    return status();
  }

  function status() {
    return {
      running,
      progress,
      total,
      mode,
      dryRun,
      statusMessage,
      lastRun,
      counts: {
        files: files.length,
        duplicates: 0,
        registry: registry.length,
        backups: backups.length
      }
    };
  }

  function resultsList() {
    return {
      files: files.slice(),
      duplicates: [],
      registry: registry.slice(),
      backups: backups.slice(),
      mode,
      dryRun,
      statusMessage
    };
  }

  function createBackup(meta = {}) {
    const dir = ensureBackupDir();
    const d = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const id = `backup-${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
    const outPath = path.join(dir, `${id}.json`);
    const payload = {
      id,
      time: nowIso(),
      meta: {
        ...meta,
        engine: 'neo-turbo-cleaner',
        dryRunDefault: true,
        source: path.join(APP_ASSET_ROOT, 'config', 'neo turbo cleaner.txt')
      },
      snapshot: resultsList(),
      logs: runLog.slice(-2000)
    };
    fs.writeFileSync(outPath, JSON.stringify(payload, null, 2), 'utf-8');
    const entry = { id, time: payload.time, path: outPath, meta: payload.meta };
    backups.push(entry);
    if (backups.length > BACKUP_LIMIT) backups.shift();
    emit('backup', { action: 'created', entry });
    log('ok', `backup created ${id}`);
    return entry;
  }

  function listBackups() {
    const dir = backupDir();
    const out = [];
    if (fs.existsSync(dir)) {
      for (const name of fs.readdirSync(dir)) {
        if (!name.toLowerCase().endsWith('.json')) continue;
        const full = path.join(dir, name);
        try {
          const raw = JSON.parse(fs.readFileSync(full, 'utf-8'));
          if (!raw?.id || !raw?.time) continue;
          out.push({ id: raw.id, time: raw.time, path: full, meta: raw.meta || {} });
        } catch {}
      }
    }
    const map = new Map();
    backups.forEach((b) => map.set(b.id, b));
    out.forEach((b) => map.set(b.id, b));
    return [...map.values()].sort((a, b) => String(a.time).localeCompare(String(b.time)));
  }

  function restoreBackup(id) {
    const all = listBackups();
    const hit = all.find((b) => b.id === id);
    if (!hit) {
      log('error', `backup not found ${id}`);
      return { ok: false, error: 'backup not found' };
    }
    try {
      const raw = JSON.parse(fs.readFileSync(hit.path, 'utf-8'));
      const snap = raw?.snapshot || {};
      files = Array.isArray(snap.files) ? snap.files : [];
      registry = Array.isArray(snap.registry) ? snap.registry : [];
      dryRun = true;
      statusMessage = 'idle';
      emit('backup', { action: 'restored', entry: hit });
      log('ok', `backup restored ${id}`);
      return { ok: true, entry: hit };
    } catch (err) {
      const message = String(err?.message || err);
      log('error', `restore failed ${id}: ${message}`);
      return { ok: false, error: message };
    }
  }

  function on(event, cb) {
    if (!listeners[event]) throw new Error(`unknown event ${event}`);
    listeners[event].push(cb);
    return () => {
      const i = listeners[event].indexOf(cb);
      if (i >= 0) listeners[event].splice(i, 1);
    };
  }

  return {
    start,
    stop,
    status,
    on,
    resultsList,
    createBackup,
    listBackups,
    restoreBackup
  };
}

