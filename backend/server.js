import express from 'express';
import bodyParser from 'body-parser';
import cors from 'cors';
import fs from 'fs';
import path from 'path';
import os from 'os';
import { exec, execFile, spawn, spawnSync } from 'child_process';
import { fileURLToPath } from 'url';
import { createAdvanceCleaner } from './engines/advanceCleaner.js';
import { createSanTurbo } from './engines/sanTurbo.js';

const app = express();
app.use(cors());
app.use(bodyParser.json());

const PORT = process.env.PORT || 3322;
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const APP_ROOT = process.env.APP_ROOT ? path.resolve(process.env.APP_ROOT) : path.resolve(__dirname, '..');
const APP_ASSET_ROOT = process.env.APP_ASSET_ROOT ? path.resolve(process.env.APP_ASSET_ROOT) : APP_ROOT;
const APP_DATA_ROOT = process.env.APP_DATA_ROOT ? path.resolve(process.env.APP_DATA_ROOT) : APP_ROOT;
const DATA_CONFIG_DIR = path.join(APP_DATA_ROOT, 'config');
const DATA_BACKEND_DIR = path.join(APP_DATA_ROOT, 'backend');
const ASSET_CONFIG_DIR = path.join(APP_ASSET_ROOT, 'config');
const engines = { advance: createAdvanceCleaner(), santurbo: createSanTurbo() };
const engineBuffers = {};
const appLogs = [];
const processTokens = new Map();
const PROCESS_TTL_MS = 30000;
const schedulerTasks = [
  { id: 'daily-clean', cron: '0 3 * * *', desc: 'Daily quick clean', user: 'system', status: 'active', lastRun: null, nextRun: 'pending' },
  { id: 'weekly-report', cron: '0 4 * * 0', desc: 'Weekly report generation', user: 'system', status: 'active', lastRun: null, nextRun: 'pending' }
];
const KICOMAV_ROOT = path.join(APP_ASSET_ROOT, 'kicomav-master');
const KICOMAV_MODULE = 'kicomav.k2';
const CLAMAV_RUNTIME_ROOT = path.join(APP_ASSET_ROOT, 'vendor', 'clamav-runtime');
const CLAMAV_SOURCE_ROOT = path.join(APP_ASSET_ROOT, 'clamav-1.5.1');
const CLAMAV_ROOT = fs.existsSync(path.join(CLAMAV_RUNTIME_ROOT, 'clamscan.exe'))
  ? CLAMAV_RUNTIME_ROOT
  : CLAMAV_SOURCE_ROOT;
const securityScan = {
  running: false,
  progress: 0,
  startedAt: null,
  finishedAt: null,
  threats: 0,
  suspicious: 0,
  scanned: 0,
  engine: 'kicomav',
  requestedEngine: 'auto',
  target: null,
  command: null,
  lastError: null
};
let securityProc = null;
let securityProgressTimer = null;
let securityStopRequested = false;
let clamavProbeCache = { key: '', at: 0, result: { runnable: false, version: null, error: null } };

let cpuSnap = null;
let netSnap = null;
const PROCESS_CACHE_MS = 3500;
const OVERVIEW_CACHE_MS = 2000;
const NETWORK_STATS_CACHE_MS = 3500;
const NETWORK_CONN_CACHE_MS = 4500;
const LOGS_CACHE_MS = 1000;
const runtimeCache = {
  processes: { at: 0, value: null, inflight: false, waiters: [] },
  overview: { at: 0, value: null, inflight: false, waiters: [] },
  networkStats: { at: 0, value: null, inflight: false, waiters: [] },
  networkConnections: { at: 0, value: null, inflight: false, waiters: [] },
  logs: { at: 0, value: null, key: '' }
};

const withCachedProducer = (bucket, ttlMs, producer, cb) => {
  const now = Date.now();
  if (bucket.value != null && now - Number(bucket.at || 0) < ttlMs) {
    cb(null, bucket.value, true);
    return;
  }
  bucket.waiters.push(cb);
  if (bucket.inflight) return;
  bucket.inflight = true;
  producer((err, value) => {
    bucket.inflight = false;
    if (!err) {
      bucket.value = value;
      bucket.at = Date.now();
    }
    const waiters = bucket.waiters.splice(0);
    waiters.forEach((fn) => {
      try {
        fn(err || null, value, false);
      } catch {}
    });
  });
};

const pushLog = (level, message, meta = {}) => {
  appLogs.push({ time: new Date().toISOString(), level, message, meta });
  if (appLogs.length > 3000) appLogs.shift();
};

const parseJson = (s, fb) => { try { return JSON.parse(s); } catch { return fb; } };
const uniqueNonEmpty = (arr = []) => {
  const seen = new Set();
  const out = [];
  arr.forEach((v) => {
    const s = String(v || '').trim();
    if (!s) return;
    const key = process.platform === 'win32' ? s.toLowerCase() : s;
    if (seen.has(key)) return;
    seen.add(key);
    out.push(s);
  });
  return out;
};
const parseMemKB = (v) => {
  const m = String(v || '').replace(/,/g, '').trim().toUpperCase().match(/^([\d.]+)\s*(K|KB|M|MB|G|GB)?$/);
  if (!m) return null;
  const n = Number(m[1]); const u = m[2] || 'KB';
  if (!Number.isFinite(n)) return null;
  if (u.startsWith('G')) return Math.round(n * 1024 * 1024);
  if (u.startsWith('M')) return Math.round(n * 1024);
  return Math.round(n);
};

const baseExecOptions = process.platform === 'win32' ? { windowsHide: true } : {};
const runExec = (command, options, cb) => exec(command, { ...baseExecOptions, ...(options || {}) }, cb);
const runExecFile = (file, args, options, cb) => execFile(file, args, { ...baseExecOptions, ...(options || {}) }, cb);
const runExecFileAsync = (file, args = [], options = {}) => new Promise((resolve) => {
  runExecFile(file, args, options, (err, stdout, stderr) => {
    resolve({
      err: err || null,
      stdout: String(stdout || ''),
      stderr: String(stderr || '')
    });
  });
});
const escapeHtml = (v) => String(v || '').replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch] || ch));
const stripAnsi = (v) => String(v || '').replace(/\x1B\[[0-9;]*m/g, '');
const chunkString = (v, max = 220) => {
  const s = String(v || '');
  if (s.length <= max) return s;
  return `${s.slice(0, Math.max(1, max - 3))}...`;
};

const pushEngineLog = (level, message) => {
  Object.keys(engineBuffers).forEach((k) => {
    const bucket = engineBuffers[k];
    if (!bucket || !Array.isArray(bucket.logs)) return;
    bucket.logs.push({ time: new Date().toISOString(), level, message });
    if (bucket.logs.length > 3000) bucket.logs.shift();
  });
};

const pushSecurityLog = (level, message, meta = {}) => {
  pushLog(level, `security: ${message}`, meta);
  pushEngineLog(level, `security: ${message}`);
};

const kicomavExists = () => fs.existsSync(path.join(KICOMAV_ROOT, 'kicomav', 'k2.py'));
const rankClamavDist = (name) => {
  const arch = String(process.arch || '').toLowerCase();
  const n = String(name || '').toLowerCase();
  if (arch === 'x64') {
    if (n.includes('.x64')) return 0;
    if (n.includes('.win32')) return 1;
    if (n.includes('.arm64')) return 4;
    return 3;
  }
  if (arch === 'arm64') {
    if (n.includes('.arm64')) return 0;
    if (n.includes('.x64')) return 2;
    if (n.includes('.win32')) return 3;
    return 4;
  }
  if (n.includes('.win32')) return 0;
  if (n.includes('.x64')) return 2;
  return 3;
};
const clamavRootCandidates = () => {
  const candidates = [CLAMAV_SOURCE_ROOT, CLAMAV_RUNTIME_ROOT, CLAMAV_ROOT];
  const seen = new Set();
  return candidates.filter((root) => {
    const p = String(root || '').trim();
    if (!p || !fs.existsSync(p)) return false;
    const key = process.platform === 'win32' ? p.toLowerCase() : p;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
};
const detectClamavDistributionDirs = () => {
  try {
    const dirs = [];
    clamavRootCandidates().forEach((root) => {
      const entries = fs.readdirSync(root, { withFileTypes: true })
        .filter((d) => d.isDirectory() && /^clamav-.*\.win\./i.test(d.name))
        .map((d) => ({ name: d.name, full: path.join(root, d.name) }));
      dirs.push(...entries);
    });
    const seen = new Set();
    return dirs
      .sort((a, b) => rankClamavDist(a.name) - rankClamavDist(b.name))
      .filter((x) => {
        const key = process.platform === 'win32' ? x.full.toLowerCase() : x.full;
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      })
      .map((x) => x.full);
  } catch {
    return [];
  }
};
const clamavCandidateBins = () => ([
  securitySettings.clamscanPath || '',
  process.env.CLAMSCAN_PATH || '',
  ...detectClamavDistributionDirs().map((d) => path.join(d, 'clamscan.exe')),
  path.join(CLAMAV_RUNTIME_ROOT, 'clamscan.exe'),
  path.join(CLAMAV_SOURCE_ROOT, 'clamscan.exe'),
  path.join(CLAMAV_ROOT, 'clamscan.exe'),
  path.join(CLAMAV_ROOT, 'build', 'clamscan.exe'),
  path.join(CLAMAV_ROOT, 'build', 'Release', 'clamscan.exe'),
  path.join(CLAMAV_ROOT, 'build', 'Debug', 'clamscan.exe'),
  path.join(CLAMAV_ROOT, 'win32', 'clamscan.exe')
].filter(Boolean));
const clamavBinaryPath = () => clamavCandidateBins().find((p) => fs.existsSync(p)) || '';
const clamavDbFiles = (dir) => {
  try {
    if (!dir || !fs.existsSync(dir)) return [];
    return fs.readdirSync(dir)
      .filter((n) => /\.(cvd|cld|cud)$/i.test(n))
      .map((n) => path.join(dir, n));
  } catch {
    return [];
  }
};
const resolveClamavDb = (binPath = '') => {
  const bin = String(binPath || '').trim();
  const binDir = bin ? path.dirname(bin) : '';
  const preferredDir = binDir ? path.join(binDir, 'database') : '';
  let configuredDbDir = String(securitySettings?.clamDbDir || '').trim();
  if (configuredDbDir && binDir && path.resolve(configuredDbDir) === path.resolve(binDir)) configuredDbDir = '';
  const candidates = uniqueNonEmpty([
    process.env.CLAMAV_DB_DIR || '',
    configuredDbDir,
    preferredDir,
    path.join(binDir, 'db'),
    path.join(CLAMAV_ROOT, 'database'),
    path.join(CLAMAV_ROOT, 'db')
  ]).filter((d) => fs.existsSync(d));

  let best = { dir: '', files: [] };
  for (const dir of candidates) {
    const files = clamavDbFiles(dir);
    if (files.length > best.files.length) best = { dir, files };
    if (files.length > 0 && (dir.endsWith('\\database') || dir.endsWith('/database'))) break;
  }

  const fallbackDir = candidates[0] || preferredDir || '';
  const dir = best.files.length > 0 ? best.dir : fallbackDir;
  return {
    dir: dir || null,
    ready: best.files.length > 0,
    fileCount: best.files.length,
    files: best.files
  };
};
const probeClamavBinary = (binPath) => {
  const p = String(binPath || '').trim();
  if (!p) return { runnable: false, version: null, error: 'binary not found' };
  const key = `${p}|${process.arch}|${process.platform}`;
  const now = Date.now();
  if (clamavProbeCache.key === key && now - clamavProbeCache.at < 30000) return clamavProbeCache.result;

  const out = spawnSync(p, ['--version'], {
    cwd: path.dirname(p),
    windowsHide: true,
    encoding: 'utf-8',
    timeout: 12000
  });

  let result = { runnable: false, version: null, error: null };
  if (out.error) {
    result = { runnable: false, version: null, error: String(out.error.message || out.error) };
  } else if (Number(out.status) === 0) {
    const line = stripAnsi(String(out.stdout || '').split(/\r?\n/).find((ln) => ln.trim()) || '').trim();
    result = { runnable: true, version: line || null, error: null };
  } else {
    const stderr = stripAnsi(String(out.stderr || '')).trim();
    const stdout = stripAnsi(String(out.stdout || '')).trim();
    result = { runnable: false, version: null, error: stderr || stdout || `exit code ${out.status}` };
  }

  clamavProbeCache = { key, at: now, result };
  return result;
};
const clamavFreshclamPath = () => {
  const bin = clamavBinaryPath();
  const candidates = [];
  if (bin) {
    const dir = path.dirname(bin);
    candidates.push(path.join(dir, 'freshclam.exe'));
    candidates.push(path.join(path.dirname(dir), 'freshclam.exe'));
  }
  candidates.push(path.join(CLAMAV_ROOT, 'freshclam.exe'));
  candidates.push(path.join(CLAMAV_RUNTIME_ROOT, 'freshclam.exe'));
  candidates.push(path.join(CLAMAV_SOURCE_ROOT, 'freshclam.exe'));
  candidates.push(path.join(CLAMAV_ROOT, 'build', 'freshclam.exe'));
  candidates.push(path.join(CLAMAV_ROOT, 'build', 'Release', 'freshclam.exe'));
  candidates.push(path.join(CLAMAV_ROOT, 'build', 'Debug', 'freshclam.exe'));
  detectClamavDistributionDirs().forEach((dir) => candidates.push(path.join(dir, 'freshclam.exe')));
  if (process.platform === 'win32') candidates.push('freshclam.exe');
  else candidates.push('freshclam');
  return candidates.find((p) => p && fs.existsSync(p)) || '';
};
const securityEngineInfo = () => {
  const kico = kicomavExists();
  const clamBin = clamavBinaryPath();
  const clamProbe = probeClamavBinary(clamBin);
  const clamDb = resolveClamavDb(clamBin);
  const clam = Boolean(clamBin) && Boolean(clamProbe.runnable);
  const freshclam = clamavFreshclamPath();
  const recommended = clam ? 'clamav' : (kico ? 'kicomav' : null);
  return {
    recommended,
    kicomav: { available: kico, root: KICOMAV_ROOT, module: KICOMAV_MODULE },
    clamav: {
      available: clam,
      root: CLAMAV_ROOT,
      binary: clamBin || null,
      freshclam: freshclam || null,
      version: clamProbe.version || null,
      probeError: clamProbe.runnable ? null : clamProbe.error,
      database: clamDb
    }
  };
};

const normalizeScanTarget = (rawTarget) => {
  const fallback = process.env.USERPROFILE || APP_DATA_ROOT;
  const raw = String(rawTarget || '').trim();
  const resolved = raw ? path.resolve(raw) : path.resolve(fallback);
  if (fs.existsSync(resolved)) return resolved;
  if (fs.existsSync(fallback)) return path.resolve(fallback);
  return APP_DATA_ROOT;
};

const kicomavPlans = (target) => ([
  { cmd: 'py', args: ['-3', '-m', KICOMAV_MODULE, target, '--no-color'] },
  { cmd: 'python', args: ['-m', KICOMAV_MODULE, target, '--no-color'] },
  { cmd: 'python3', args: ['-m', KICOMAV_MODULE, target, '--no-color'] }
]);
const clamavPlans = (target) => {
  const bin = clamavBinaryPath();
  const db = resolveClamavDb(bin);
  const args = ['--recursive', '--infected', '--scan-archive=yes', '--max-filesize=256M'];
  if (db.dir) args.push(`--database=${db.dir}`);
  args.push(target);
  if (bin) return [{ cmd: bin, args }];
  if (process.platform === 'win32') return [{ cmd: 'clamscan.exe', args }, { cmd: 'clamscan', args }];
  return [{ cmd: 'clamscan', args }];
};

const parseKicomavSummary = (line) => {
  const files = line.match(/^Files\s*:\s*(\d+)/i);
  const infected = line.match(/^Infected files\s*:\s*(\d+)/i);
  const suspect = line.match(/^Suspect files\s*:\s*(\d+)/i);
  const warnings = line.match(/^Warnings\s*:\s*(\d+)/i);
  return {
    files: files ? Number(files[1]) : null,
    infected: infected ? Number(infected[1]) : null,
    suspect: suspect ? Number(suspect[1]) : null,
    warnings: warnings ? Number(warnings[1]) : null
  };
};
const parseClamavSummary = (line) => {
  const files = line.match(/^Scanned files:\s*(\d+)/i);
  const infected = line.match(/^Infected files:\s*(\d+)/i);
  const errors = line.match(/^Total errors:\s*(\d+)/i);
  return {
    files: files ? Number(files[1]) : null,
    infected: infected ? Number(infected[1]) : null,
    errors: errors ? Number(errors[1]) : null
  };
};

const normalizeCandidatePaths = (paths = []) => {
  const seen = new Set();
  const out = [];
  paths.forEach((p) => {
    const raw = String(p || '').trim();
    if (!raw) return;
    const abs = path.resolve(raw);
    const key = process.platform === 'win32' ? abs.toLowerCase() : abs;
    if (seen.has(key)) return;
    seen.add(key);
    out.push(abs);
  });
  return out;
};

const testClamavBinary = async (binPath) => {
  const candidate = String(binPath || '').trim();
  if (!candidate) return { ok: false, error: 'empty clamscan path' };
  const resolved = path.resolve(candidate);
  if (!fs.existsSync(resolved)) return { ok: false, error: `clamscan not found: ${resolved}` };

  const version = await runExecFileAsync(resolved, ['--version'], { cwd: path.dirname(resolved), maxBuffer: 1024 * 1024, timeout: 20000 });
  if (version.err) {
    const detail = stripAnsi(`${version.stderr || ''}\n${version.stdout || ''}`.trim());
    return { ok: false, error: detail || String(version.err.message || version.err) };
  }

  const versionLine = stripAnsi(version.stdout.split(/\r?\n/).find((ln) => ln.trim()) || version.stdout).trim();

  const freshCandidates = normalizeCandidatePaths([
    path.join(path.dirname(resolved), process.platform === 'win32' ? 'freshclam.exe' : 'freshclam'),
    path.join(path.dirname(path.dirname(resolved)), process.platform === 'win32' ? 'freshclam.exe' : 'freshclam'),
    clamavFreshclamPath()
  ]);

  let fresh = null;
  for (const f of freshCandidates) {
    if (!fs.existsSync(f)) continue;
    const test = await runExecFileAsync(f, ['--version'], { cwd: path.dirname(f), maxBuffer: 512 * 1024, timeout: 15000 });
    if (!test.err) {
      fresh = {
        path: f,
        version: stripAnsi(test.stdout.split(/\r?\n/).find((ln) => ln.trim()) || test.stdout).trim()
      };
      break;
    }
  }

  return { ok: true, binary: resolved, version: versionLine || 'ClamAV detected', freshclam: fresh };
};

const stopSecurityProgress = () => {
  if (!securityProgressTimer) return;
  clearInterval(securityProgressTimer);
  securityProgressTimer = null;
};

const localConfigFile = path.join(DATA_CONFIG_DIR, 'config.txt');
const assetConfigFile = path.join(ASSET_CONFIG_DIR, 'config.txt');
const scriptConfigFile = 'C:/Users/Hello World/Documents/Script/config.txt';
const localCleanerSpecFile = path.join(DATA_CONFIG_DIR, 'advance cleaner engine.txt');
const assetCleanerSpecFile = path.join(ASSET_CONFIG_DIR, 'advance cleaner engine.txt');
const scriptCleanerSpecFile = 'C:/Users/Hello World/Documents/Script/advance cleaner engine.txt';
const securityConfigFile = path.join(DATA_CONFIG_DIR, 'security.json');

const defaultSecuritySettings = { preferredEngine: 'auto', clamscanPath: '' };
const loadSecuritySettings = () => {
  try {
    if (!fs.existsSync(securityConfigFile)) return { ...defaultSecuritySettings };
    const raw = JSON.parse(fs.readFileSync(securityConfigFile, 'utf-8'));
    return {
      preferredEngine: ['auto', 'kicomav', 'clamav'].includes(String(raw?.preferredEngine || '').toLowerCase())
        ? String(raw.preferredEngine).toLowerCase()
        : 'auto',
      clamscanPath: String(raw?.clamscanPath || ''),
      clamDbDir: String(raw?.clamDbDir || '')
    };
  } catch {
    return { ...defaultSecuritySettings };
  }
};
let securitySettings = loadSecuritySettings();
const saveSecuritySettings = (patch = {}) => {
  const next = {
    preferredEngine: ['auto', 'kicomav', 'clamav'].includes(String(patch.preferredEngine || securitySettings.preferredEngine || 'auto').toLowerCase())
      ? String(patch.preferredEngine || securitySettings.preferredEngine || 'auto').toLowerCase()
      : 'auto',
    clamscanPath: String(patch.clamscanPath ?? securitySettings.clamscanPath ?? ''),
    clamDbDir: String(patch.clamDbDir ?? securitySettings.clamDbDir ?? '')
  };
  fs.mkdirSync(path.dirname(securityConfigFile), { recursive: true });
  fs.writeFileSync(securityConfigFile, JSON.stringify(next, null, 2), 'utf-8');
  securitySettings = next;
  return next;
};

const ensureSeedFile = (localPath, sourcePath) => {
  try {
    if (fs.existsSync(localPath)) return;
    if (!fs.existsSync(sourcePath)) return;
    fs.mkdirSync(path.dirname(localPath), { recursive: true });
    fs.copyFileSync(sourcePath, localPath);
    pushLog('info', 'seed file created', { localPath, sourcePath });
  } catch (err) {
    pushLog('warn', 'seed file failed', { localPath, sourcePath, error: String(err) });
  }
};

const ensureLocalConfigFiles = () => {
  if (!process.env.CONFIG_PATH) {
    ensureSeedFile(localConfigFile, fs.existsSync(assetConfigFile) ? assetConfigFile : scriptConfigFile);
  }
  if (!process.env.CLEANER_SPEC_PATH) {
    ensureSeedFile(localCleanerSpecFile, fs.existsSync(assetCleanerSpecFile) ? assetCleanerSpecFile : scriptCleanerSpecFile);
  }
};

const configPath = () => {
  if (process.env.CONFIG_PATH) return process.env.CONFIG_PATH;
  if (fs.existsSync(localConfigFile)) return localConfigFile;
  if (fs.existsSync(assetConfigFile)) return assetConfigFile;
  return scriptConfigFile;
};
const cleanerSpecPath = () => {
  if (process.env.CLEANER_SPEC_PATH) return process.env.CLEANER_SPEC_PATH;
  if (fs.existsSync(localCleanerSpecFile)) return localCleanerSpecFile;
  if (fs.existsSync(assetCleanerSpecFile)) return assetCleanerSpecFile;
  return scriptCleanerSpecFile;
};
const pathAllowed = (p) => {
  const abs = path.resolve(p);
  const roots = [path.resolve(DATA_CONFIG_DIR), path.resolve(ASSET_CONFIG_DIR), path.resolve('C:/Users/Hello World/Documents/Script')];
  return roots.some((r) => abs.startsWith(r));
};

const cpuPercent = () => {
  const cpus = os.cpus().map((c) => {
    const t = c.times; return { idle: t.idle, total: t.user + t.nice + t.sys + t.idle + t.irq };
  });
  if (!cpuSnap) { cpuSnap = cpus; return 0; }
  let idle = 0; let total = 0;
  cpus.forEach((c, i) => { idle += c.idle - cpuSnap[i].idle; total += c.total - cpuSnap[i].total; });
  cpuSnap = cpus;
  return total > 0 ? Number((((total - idle) / total) * 100).toFixed(1)) : 0;
};

const listProcesses = (cb, options = {}) => {
  const forceRefresh = Boolean(options.forceRefresh);
  if (forceRefresh) runtimeCache.processes.at = 0;
  withCachedProducer(runtimeCache.processes, PROCESS_CACHE_MS, (done) => {
    if (process.platform === 'win32') {
      runExec('tasklist /FO CSV /NH', { maxBuffer: 1024 * 1200 }, (err, stdout) => {
        if (err) {
          return done(null, [{ pid: process.pid, name: 'node', command: 'node', status: 'running', user: process.env.USERNAME || 'system' }]);
        }
        const rows = String(stdout)
          .trim()
          .split(/\r?\n/)
          .filter(Boolean)
          .map((ln) => ln.split(/","/).map((s) => s.replace(/^"|"$/g, '')));
        const procs = rows
          .map((c) => ({ pid: Number(c[1]), name: c[0], command: c[0], user: c[2], status: 'running', mem: c[4], memKB: parseMemKB(c[4]) }))
          .filter((p) => p.pid > 0);
        done(null, procs);
      });
      return;
    }
    runExec('ps -eo pid,user,comm,%cpu,%mem,state --no-headers | head -n 300', { maxBuffer: 1024 * 1000 }, (err, stdout) => {
      if (err) {
        return done(null, [{ pid: process.pid, name: 'node', command: 'node', status: 'running', user: process.env.USER || 'system' }]);
      }
      const procs = String(stdout)
        .trim()
        .split(/\r?\n/)
        .filter(Boolean)
        .map((ln) => {
          const p = ln.trim().split(/\s+/, 6);
          return { pid: Number(p[0]), user: p[1], name: p[2], command: p[2], cpu: Number(p[3]), memPercent: Number(p[4]), status: (p[5] || '').startsWith('R') ? 'running' : 'sleeping' };
        })
        .filter((p) => p.pid > 0);
      done(null, procs);
    });
  }, (err, data) => {
    cb(err || null, Array.isArray(data) ? data : []);
  });
};

const networkThroughput = (cb) => {
  const cmd = process.platform === 'win32'
    ? 'powershell -NoProfile -Command "Get-NetAdapterStatistics | Select-Object ReceivedBytes,SentBytes | ConvertTo-Json -Compress"'
    : "cat /proc/net/dev";
  runExec(cmd, { maxBuffer: 1024 * 500 }, (err, stdout) => {
    if (err) return cb({ rxKBs: 0, txKBs: 0 });
    let rx = 0; let tx = 0;
    if (process.platform === 'win32') {
      const data = parseJson(stdout, []);
      const arr = Array.isArray(data) ? data : [data];
      arr.forEach((r) => { rx += Number(r.ReceivedBytes || 0); tx += Number(r.SentBytes || 0); });
    } else {
      String(stdout).split(/\r?\n/).slice(2).filter(Boolean).forEach((ln) => {
        const p = ln.replace(':', ' ').trim().split(/\s+/); rx += Number(p[1] || 0); tx += Number(p[9] || 0);
      });
    }
    const now = Date.now();
    if (!netSnap) { netSnap = { now, rx, tx }; return cb({ rxKBs: 0, txKBs: 0 }); }
    const dt = Math.max(1, (now - netSnap.now) / 1000);
    const out = { rxKBs: Math.max(0, Math.round((rx - netSnap.rx) / 1024 / dt)), txKBs: Math.max(0, Math.round((tx - netSnap.tx) / 1024 / dt)) };
    netSnap = { now, rx, tx };
    cb(out);
  });
};

const networkConnections = (cb) => {
  const cmd = process.platform === 'win32' ? 'netstat -ano -p tcp' : 'netstat -tunap 2>/dev/null | tail -n +3';
  runExec(cmd, { maxBuffer: 1024 * 2000 }, (err, stdout) => {
    if (err) return cb([]);
    let rows = [];
    if (process.platform === 'win32') {
      rows = String(stdout).split(/\r?\n/).map((ln) => ln.trim()).filter((ln) => ln.startsWith('TCP')).map((ln) => {
        const p = ln.split(/\s+/); return { local: p[1], remote: p[2], state: p[3], pid: Number(p[4]) };
      });
    } else {
      rows = String(stdout).split(/\r?\n/).filter(Boolean).map((ln) => {
        const p = ln.trim().split(/\s+/); const pid = Number(String(p[6] || '').split('/')[0]) || 0; return { local: p[3], remote: p[4], state: p[5], pid };
      });
    }
    listProcesses((_, procs) => {
      const map = new Map((procs || []).map((p) => [p.pid, p.name || p.command || '-']));
      cb(rows.slice(0, 250).map((r) => ({ ...r, process: map.get(r.pid) || '-' })));
    });
  });
};

const issueToken = (pid, action) => {
  for (const [k, v] of processTokens.entries()) if (v.expiresAt < Date.now()) processTokens.delete(k);
  const token = `${pid}:${action}:${Date.now()}:${Math.random().toString(36).slice(2, 10)}`;
  processTokens.set(token, { pid, action, expiresAt: Date.now() + PROCESS_TTL_MS });
  return token;
};
const checkToken = (token, pid, action) => {
  const rec = processTokens.get(token);
  processTokens.delete(token);
  return !!rec && rec.pid === pid && rec.action === action && rec.expiresAt >= Date.now();
};

const safeOn = (engine, eventName, handler) => {
  if (!engine || typeof engine.on !== 'function') return null;
  try {
    return engine.on(eventName, handler);
  } catch {
    return null;
  }
};

Object.keys(engines).forEach((k) => {
  const engine = engines[k];
  engineBuffers[k] = { logs: [], findings: [], duplicates: [], registry: [], backups: [] };
  safeOn(engine, 'log', (l) => { engineBuffers[k].logs.push({ time: new Date().toISOString(), ...l }); if (engineBuffers[k].logs.length > 3000) engineBuffers[k].logs.shift(); });
  safeOn(engine, 'fileFound', (f) => { engineBuffers[k].findings.push(f); if (engineBuffers[k].findings.length > 3000) engineBuffers[k].findings.shift(); });
  safeOn(engine, 'duplicateFound', (d) => { engineBuffers[k].duplicates.push(d); if (engineBuffers[k].duplicates.length > 1500) engineBuffers[k].duplicates.shift(); });
  safeOn(engine, 'registryIssue', (r) => { engineBuffers[k].registry.push(r); if (engineBuffers[k].registry.length > 1500) engineBuffers[k].registry.shift(); });
  safeOn(engine, 'backup', (b) => { engineBuffers[k].backups.push(b); if (engineBuffers[k].backups.length > 500) engineBuffers[k].backups.shift(); });
});

app.get('/api/events/:engine', (req, res) => {
  const e = engines[req.params.engine];
  if (!e) return res.status(404).send({ error: 'engine not found' });
  res.set({ 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' });
  const bind = (name) => safeOn(e, name, (p) => res.write(`event: ${name}\ndata: ${JSON.stringify(p)}\n\n`));
  const off = [bind('progress'), bind('log'), bind('done'), bind('fileFound'), bind('duplicateFound'), bind('registryIssue'), bind('backup')];
  req.on('close', () => off.forEach((f) => typeof f === 'function' && f()));
});

app.get('/api/system/overview', (req, res) => {
  const forceRefresh = String(req.query.refresh || '').toLowerCase() === '1';
  if (forceRefresh) runtimeCache.overview.at = 0;
  withCachedProducer(runtimeCache.overview, OVERVIEW_CACHE_MS, (done) => {
    listProcesses((_, processes) => {
      const total = os.totalmem();
      const free = os.freemem();
      const payload = {
        ok: true,
        system: {
          hostname: os.hostname(),
          kernel: os.release(),
          platform: os.platform(),
          uptimeSec: os.uptime(),
          loadAvg: os.loadavg(),
          cpuPercent: cpuPercent(),
          memPercent: total > 0 ? Number((((total - free) / total) * 100).toFixed(1)) : 0,
          memory: { total, free, used: total - free }
        },
        tasks: processes.length
      };
      done(null, payload);
    });
  }, (_, payload) => res.send(payload || { ok: false, error: 'overview unavailable' }));
});

app.get('/api/clean/:engine/status', (req, res) => {
  const e = engines[req.params.engine]; if (!e) return res.status(404).send({ error: 'engine not found' }); return res.send(e.status());
});
app.post('/api/clean/:engine/start', (req, res) => {
  const e = engines[req.params.engine];
  if (!e) return res.status(404).send({ error: 'engine not found' });
  const opts = { ...(req.body || {}) };
  if (opts.dryRun == null) opts.dryRun = true;
  const out = e.start(opts);
  pushLog('info', `engine ${req.params.engine} start`, { mode: opts.mode || 'full', dryRun: opts.dryRun !== false });
  return res.send({ ok: true, result: out });
});
app.post('/api/clean/:engine/stop', (req, res) => {
  const e = engines[req.params.engine]; if (!e) return res.status(404).send({ error: 'engine not found' }); const out = e.stop(); pushLog('warn', `engine ${req.params.engine} stop`); return res.send({ ok: true, result: out });
});
app.get('/api/clean/:engine/results', (req, res) => {
  const e = engines[req.params.engine]; if (!e) return res.status(404).send({ error: 'engine not found' }); return res.send({ ok: true, results: typeof e.resultsList === 'function' ? e.resultsList() : engineBuffers[req.params.engine].findings || [] });
});
app.post('/api/clean/:engine/duplicate', (req, res) => {
  return res.status(410).send({ ok: false, error: 'duplicate finder removed from NeoOptimize' });
});
app.post('/api/clean/:engine/registry', (req, res) => {
  const e = engines[req.params.engine];
  if (!e) return res.status(404).send({ error: 'engine not found' });
  const opts = { ...(req.body || {}), mode: 'registry' };
  if (opts.dryRun == null) opts.dryRun = true;
  e.start(opts);
  pushLog('info', 'registry scan started', { dryRun: opts.dryRun !== false });
  return res.send({ ok: true });
});
app.get('/api/clean/:engine/profiles', (req, res) => {
  try {
    const content = fs.readFileSync(cleanerSpecPath(), 'utf-8');
    const labels = ['QUICK CLEAN', 'STANDARD CLEAN', 'DEEP CLEAN', 'AGGRESSIVE CLEAN', 'CUSTOM CLEAN'];
    const lines = content.split(/\r?\n/);
    const profiles = labels.map((label) => {
      const i = lines.findIndex((ln) => ln.toUpperCase().includes(label));
      return { id: label.toLowerCase().replace(/\s+/g, '-'), label, description: i >= 0 ? lines.slice(i, i + 10).join('\n') : `${label} profile` };
    });
    return res.send({ ok: true, profiles });
  } catch (err) { return res.status(500).send({ ok: false, error: String(err) }); }
});
app.post('/api/clean/:engine/backup', (req, res) => {
  const e = engines[req.params.engine]; if (!e) return res.status(404).send({ error: 'engine not found' }); if (typeof e.createBackup !== 'function') return res.status(400).send({ error: 'backup unsupported' }); const entry = e.createBackup(req.body || {}); pushLog('info', `backup ${entry.id} created`); return res.send({ ok: true, entry });
});
app.get('/api/clean/:engine/backups', (req, res) => {
  const e = engines[req.params.engine]; if (!e) return res.status(404).send({ error: 'engine not found' }); if (typeof e.listBackups !== 'function') return res.status(400).send({ error: 'backup unsupported' }); return res.send({ ok: true, backups: e.listBackups() });
});
app.post('/api/clean/:engine/backup/restore', (req, res) => {
  const e = engines[req.params.engine]; if (!e) return res.status(404).send({ error: 'engine not found' }); if (typeof e.restoreBackup !== 'function') return res.status(400).send({ error: 'backup unsupported' }); return res.send({ ok: true, result: e.restoreBackup(req.body && req.body.id) });
});

app.get('/api/processes', (req, res) => listProcesses((_, procs) => res.send({ ok: true, processes: procs })));
app.post('/api/processes/:pid/confirm', (req, res) => {
  const pid = Number(req.params.pid); const action = String((req.body && req.body.action) || '').toLowerCase();
  if (!pid || !['kill', 'pause', 'resume'].includes(action)) return res.status(400).send({ ok: false, error: 'invalid pid/action' });
  if (pid === process.pid) return res.status(403).send({ ok: false, error: 'refusing to act on api process' });
  const token = issueToken(pid, action); return res.send({ ok: true, token, expiresInMs: PROCESS_TTL_MS });
});
app.post('/api/processes/:pid/:action', (req, res) => {
  const pid = Number(req.params.pid); const action = String(req.params.action || '').toLowerCase(); const token = String((req.body && req.body.confirmToken) || '');
  if (!pid || !['kill', 'pause', 'resume'].includes(action)) return res.status(400).send({ ok: false, error: 'invalid pid/action' });
  if (!checkToken(token, pid, action)) return res.status(403).send({ ok: false, error: 'invalid/expired token' });
  const run = action === 'pause'
    ? (cb) => process.platform === 'win32' ? runExecFile('powershell', ['-NoProfile', '-Command', `Suspend-Process -Id ${pid} -ErrorAction Stop`], {}, cb) : runExecFile('kill', ['-STOP', String(pid)], {}, cb)
    : action === 'resume'
      ? (cb) => process.platform === 'win32' ? runExecFile('powershell', ['-NoProfile', '-Command', `Resume-Process -Id ${pid} -ErrorAction Stop`], {}, cb) : runExecFile('kill', ['-CONT', String(pid)], {}, cb)
      : (cb) => process.platform === 'win32' ? runExecFile('taskkill', ['/PID', String(pid), '/T', '/F'], {}, cb) : runExecFile('kill', ['-TERM', String(pid)], {}, cb);
  run((err, stdout, stderr) => {
    if (err) return res.status(500).send({ ok: false, error: String(stderr || err.message || err) });
    pushLog('warn', `process ${action}`, { pid });
    return res.send({ ok: true, pid, action, output: String(stdout || '').trim() });
  });
});

app.get('/api/network/stats', (req, res) => {
  const forceRefresh = String(req.query.refresh || '').toLowerCase() === '1';
  if (forceRefresh) runtimeCache.networkStats.at = 0;
  withCachedProducer(runtimeCache.networkStats, NETWORK_STATS_CACHE_MS, (done) => {
    const interfaces = Object.keys(os.networkInterfaces() || {}).map((name) => ({
      name,
      addrs: (os.networkInterfaces()[name] || []).map((a) => ({ address: a.address, family: a.family, mac: a.mac, internal: a.internal }))
    }));
    networkThroughput((throughput) => {
      runExec(process.platform === 'win32' ? 'ping -n 1 -w 1000 8.8.8.8' : 'ping -c 1 -W 1 8.8.8.8', { maxBuffer: 1024 * 100 }, (_, out) => {
        const txt = String(out || '');
        const m = txt.match(/Average\s*=\s*(\d+)\s*ms/i) || txt.match(/time[=<]\s*(\d+)\s*ms/i);
        const latencyMs = m ? Number(m[1]) : null;
        runExec(
          process.platform === 'win32'
            ? 'powershell -NoProfile -Command "Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object {$_.ServerAddresses} | Select-Object -ExpandProperty ServerAddresses | Sort-Object -Unique | ConvertTo-Json -Compress"'
            : "cat /etc/resolv.conf | grep nameserver | awk '{print $2}'",
          { maxBuffer: 1024 * 200 },
          (__, dnsOut) => {
            const dnsResolvers = process.platform === 'win32'
              ? (() => { const p = parseJson(dnsOut, []); return Array.isArray(p) ? p : p ? [p] : []; })()
              : String(dnsOut || '').split(/\r?\n/).filter(Boolean);
            done(null, {
              ok: true,
              interfaces,
              throughput,
              latencyMs,
              packetsPerSec: Math.max(0, Math.round((throughput.rxKBs + throughput.txKBs) / 1.5)),
              dnsResolvers
            });
          }
        );
      });
    });
  }, (_, payload) => res.send(payload || { ok: false, error: 'network stats unavailable' }));
});
app.get('/api/network/connections', (req, res) => {
  const forceRefresh = String(req.query.refresh || '').toLowerCase() === '1';
  if (forceRefresh) runtimeCache.networkConnections.at = 0;
  withCachedProducer(runtimeCache.networkConnections, NETWORK_CONN_CACHE_MS, (done) => {
    networkConnections((connections) => done(null, { ok: true, connections }));
  }, (_, payload) => res.send(payload || { ok: false, connections: [] }));
});

app.get('/api/logs', (req, res) => {
  const level = String(req.query.level || '').toLowerCase();
  const search = String(req.query.search || '').toLowerCase();
  const limit = Math.min(1000, Math.max(20, Number(req.query.limit || 300)));
  const key = `${level}|${search}|${limit}`;
  const now = Date.now();
  if (runtimeCache.logs.value && runtimeCache.logs.key === key && now - Number(runtimeCache.logs.at || 0) < LOGS_CACHE_MS) {
    return res.send(runtimeCache.logs.value);
  }
  const engineLogs = Object.keys(engineBuffers).flatMap((k) => (engineBuffers[k].logs || []).map((l) => ({ engine: k, ...l })));
  let logs = engineLogs.concat(appLogs.map((l) => ({ engine: 'system', ...l })));
  logs = logs.sort((a, b) => String(a.time).localeCompare(String(b.time)));
  if (level) logs = logs.filter((l) => String(l.level || '').toLowerCase() === level);
  if (search) logs = logs.filter((l) => `${l.engine} ${l.message || ''}`.toLowerCase().includes(search));
  const payload = { ok: true, logs: logs.slice(-limit) };
  runtimeCache.logs = { at: now, key, value: payload };
  return res.send(payload);
});

app.get('/api/security/status', (req, res) => {
  const info = securityEngineInfo();
  const issues = [];
  if (!info.kicomav.available) issues.push(`KicomAV engine not found: ${KICOMAV_ROOT}`);
  if (!info.clamav.available) {
    if (info.clamav.binary && info.clamav.probeError) {
      issues.push(`ClamAV binary detected but not runnable: ${info.clamav.binary} (${String(info.clamav.probeError).slice(0, 220)})`);
    } else {
      issues.push(`ClamAV binary not found: ${CLAMAV_ROOT}`);
    }
  } else if (!info.clamav.database?.ready) {
    issues.push(`ClamAV database missing. Run freshclam and ensure .cvd/.cld exists in ${info.clamav.database?.dir || 'database directory'}`);
  }
  if (!securityScan.running && securityScan.finishedAt && securityScan.suspicious > 0) {
    issues.push(`${securityScan.suspicious} suspicious item(s) found in latest scan`);
  }
  if (securityScan.lastError) issues.push(`Last scan error: ${securityScan.lastError}`);
  const activeEngine = securityScan.running ? securityScan.engine : (info.recommended || securityScan.engine || 'none');
  return res.send({
    ok: true,
    status: {
      antivirus: activeEngine === 'none' ? 'inactive' : `active (${activeEngine})`,
      firewall: 'enabled',
      scan: securityScan,
      engines: info,
      settings: securitySettings,
      issues
    }
  });
});
app.get('/api/security/engines', (req, res) => {
  const info = securityEngineInfo();
  return res.send({ ok: true, ...info, settings: securitySettings });
});
app.get('/api/security/settings', (req, res) => {
  const info = securityEngineInfo();
  return res.send({ ok: true, settings: securitySettings, engines: info });
});
app.post('/api/security/settings', (req, res) => {
  const preferredEngine = req.body?.preferredEngine != null ? String(req.body.preferredEngine).toLowerCase() : undefined;
  const clamscanPath = req.body?.clamscanPath != null ? String(req.body.clamscanPath).trim() : undefined;
  const clamDbDir = req.body?.clamDbDir != null ? String(req.body.clamDbDir).trim() : undefined;
  if (preferredEngine != null && !['auto', 'kicomav', 'clamav'].includes(preferredEngine)) {
    return res.status(400).send({ ok: false, error: 'preferredEngine must be auto/kicomav/clamav' });
  }
  if (clamscanPath != null && clamscanPath && !fs.existsSync(clamscanPath)) {
    return res.status(400).send({ ok: false, error: `clamscanPath not found: ${clamscanPath}` });
  }
  if (clamDbDir != null && clamDbDir && !fs.existsSync(clamDbDir)) {
    return res.status(400).send({ ok: false, error: `clamDbDir not found: ${clamDbDir}` });
  }
  const settings = saveSecuritySettings({
    preferredEngine: preferredEngine ?? securitySettings.preferredEngine,
    clamscanPath: clamscanPath ?? securitySettings.clamscanPath,
    clamDbDir: clamDbDir ?? securitySettings.clamDbDir
  });
  const info = securityEngineInfo();
  pushLog('info', 'security settings updated', {
    preferredEngine: settings.preferredEngine,
    clamscanPath: settings.clamscanPath || null,
    clamDbDir: settings.clamDbDir || null
  });
  return res.send({ ok: true, settings, engines: info });
});
app.post('/api/security/clamav/setup', (req, res) => {
  return (async () => {
    const preferred = String(req.body?.preferredEngine || '').toLowerCase();
    const requestedPath = String(req.body?.clamscanPath || req.body?.path || '').trim();
    const candidates = normalizeCandidatePaths([requestedPath, clamavBinaryPath(), ...clamavCandidateBins()]);
    const tested = [];

    for (const candidate of candidates) {
      if (!fs.existsSync(candidate)) {
        tested.push({ path: candidate, ok: false, error: 'not found' });
        continue;
      }
      const test = await testClamavBinary(candidate);
      tested.push({ path: candidate, ok: test.ok, error: test.ok ? null : test.error || 'unknown error' });
      if (!test.ok) continue;
      const db = resolveClamavDb(test.binary);

      const settings = saveSecuritySettings({
        preferredEngine: preferred === 'clamav' ? 'clamav' : securitySettings.preferredEngine,
        clamscanPath: test.binary,
        clamDbDir: db.dir || securitySettings.clamDbDir || ''
      });
      const info = securityEngineInfo();
      pushLog('info', 'clamav binary configured', {
        path: test.binary,
        version: test.version || null,
        freshclam: test.freshclam?.path || null,
        dbDir: db.dir || null,
        dbReady: db.ready
      });
      return res.send({
        ok: true,
        detected: test.binary,
        version: test.version || null,
        freshclam: test.freshclam || null,
        database: db,
        tested,
        settings,
        engines: info,
        message: 'ClamAV binary detected, verified, and configured.'
      });
    }

    const info = securityEngineInfo();
    return res.status(404).send({
      ok: false,
      error: 'ClamAV binary not ready. Build/install clamscan.exe then set path in settings.',
      engines: info,
      hintPaths: candidates,
      tested
    });
  })().catch((err) => {
    return res.status(500).send({ ok: false, error: String(err?.message || err) });
  });
});
app.post('/api/security/clamav/update-db', (req, res) => {
  return (async () => {
    const info = securityEngineInfo();
    if (!info.clamav.binary) {
      return res.status(400).send({ ok: false, error: 'ClamAV binary not configured' });
    }
    const freshclam = info.clamav.freshclam || clamavFreshclamPath();
    if (!freshclam || !fs.existsSync(freshclam)) {
      return res.status(400).send({ ok: false, error: 'freshclam not found near ClamAV binary' });
    }

    const requestedDbDir = String(req.body?.dbDir || '').trim();
    const baseDb = resolveClamavDb(info.clamav.binary);
    const defaultDbDir = path.join(path.dirname(info.clamav.binary), 'database');
    const binDir = path.dirname(info.clamav.binary);
    let configuredDbDir = String(securitySettings.clamDbDir || '').trim();
    if (configuredDbDir && path.resolve(configuredDbDir) === path.resolve(binDir)) configuredDbDir = '';
    const dbDir = requestedDbDir || configuredDbDir || (baseDb.dir && path.resolve(baseDb.dir) !== path.resolve(binDir) ? baseDb.dir : '') || defaultDbDir;
    if (!fs.existsSync(dbDir)) fs.mkdirSync(dbDir, { recursive: true });

    // Migrate any existing db files accidentally placed beside binaries.
    if (dbDir !== binDir) {
      const misplaced = clamavDbFiles(binDir);
      misplaced.forEach((src) => {
        const dest = path.join(dbDir, path.basename(src));
        try { fs.renameSync(src, dest); } catch {}
      });
    }

    const confPath = path.join(dbDir, 'neooptimize-freshclam.conf');
    const conf = [
      '# Auto-generated by NeoOptimize',
      `DatabaseDirectory "${dbDir}"`,
      'DatabaseMirror database.clamav.net',
      'DNSDatabaseInfo current.cvd.clamav.net',
      'Foreground true',
      'Checks 4'
    ].join('\n');
    fs.writeFileSync(confPath, conf, 'utf-8');

    const args = ['--stdout', '--verbose', `--config-file=${confPath}`];
    pushLog('info', 'clamav database update started', { freshclam, dbDir, config: confPath });
    const result = await runExecFileAsync(freshclam, args, {
      cwd: path.dirname(freshclam),
      windowsHide: true,
      timeout: 10 * 60 * 1000,
      maxBuffer: 1024 * 1024 * 20
    });

    const afterDb = resolveClamavDb(info.clamav.binary);
    const output = stripAnsi(`${result.stdout || ''}\n${result.stderr || ''}`).trim();
    const outputTail = output.split(/\r?\n/).slice(-100).join('\n');
    const ok = afterDb.ready;

    if (ok) {
      saveSecuritySettings({ clamDbDir: afterDb.dir || securitySettings.clamDbDir });
      pushLog('ok', 'clamav database update completed', {
        dbDir: afterDb.dir,
        fileCount: afterDb.fileCount
      });
      return res.send({
        ok: true,
        dbDir: afterDb.dir,
        fileCount: afterDb.fileCount,
        files: afterDb.files.slice(0, 20),
        configPath: confPath,
        output: outputTail
      });
    }

    const errMessage = result.err ? String(result.err.message || result.err) : 'freshclam completed but database files not found';
    pushLog('error', 'clamav database update failed', { error: errMessage, dbDir });
    return res.status(500).send({
      ok: false,
      error: errMessage,
      dbDir,
      configPath: confPath,
      output: outputTail
    });
  })().catch((err) => {
    return res.status(500).send({ ok: false, error: String(err?.message || err) });
  });
});
app.get('/api/security/scan/status', (req, res) => res.send({ ok: true, scan: securityScan }));
app.post('/api/security/scan/stop', (req, res) => {
  if (!securityScan.running || !securityProc) return res.send({ ok: true, scan: securityScan, message: 'scan not running' });
  securityStopRequested = true;
  try {
    securityProc.kill('SIGTERM');
  } catch {}
  pushSecurityLog('warn', 'security scan stop requested');
  return res.send({ ok: true, scan: securityScan, message: 'stop requested' });
});
app.post('/api/security/scan', (req, res) => {
  if (securityScan.running) return res.send({ ok: true, scan: securityScan });

  const info = securityEngineInfo();
  const requestedEngine = String(req.body?.engine || 'auto').toLowerCase();
  const requested = ['auto', 'kicomav', 'clamav'].includes(requestedEngine) ? requestedEngine : 'auto';
  let selectedEngine = null;
  if (requested === 'kicomav' && info.kicomav.available) selectedEngine = 'kicomav';
  if (requested === 'clamav' && info.clamav.available) selectedEngine = 'clamav';
  if (requested === 'auto') {
    if (securitySettings.preferredEngine === 'clamav' && info.clamav.available) selectedEngine = 'clamav';
    else if (securitySettings.preferredEngine === 'kicomav' && info.kicomav.available) selectedEngine = 'kicomav';
    else selectedEngine = info.recommended;
  }

  if (!selectedEngine) {
    const clamDetail = info?.clamav?.probeError ? ` (${String(info.clamav.probeError).slice(0, 220)})` : '';
    const error = requested === 'clamav'
      ? `ClamAV unavailable. Place compatible clamscan.exe or set CLAMSCAN_PATH.${clamDetail}`
      : requested === 'kicomav'
        ? `KicomAV engine not found in ${KICOMAV_ROOT}`
        : `No available security engine (KicomAV/ClamAV unavailable)`;
    securityScan.lastError = error;
    pushSecurityLog('error', error);
    return res.status(500).send({ ok: false, error, scan: securityScan, engines: info });
  }

  const target = normalizeScanTarget(req.body?.target);
  if (!fs.existsSync(target)) return res.status(400).send({ ok: false, error: `scan target not found: ${target}` });
  if (selectedEngine === 'clamav') {
    const db = resolveClamavDb(info.clamav.binary || '');
    if (!db.ready) {
      const error = `ClamAV database missing. Run /api/security/clamav/update-db first (dbDir: ${db.dir || 'unknown'})`;
      securityScan.lastError = error;
      pushSecurityLog('error', error);
      return res.status(400).send({ ok: false, error, scan: securityScan, engines: info });
    }
  }

  securityScan.running = true;
  securityScan.progress = 1;
  securityScan.startedAt = new Date().toISOString();
  securityScan.finishedAt = null;
  securityScan.threats = 0;
  securityScan.suspicious = 0;
  securityScan.scanned = 0;
  securityScan.requestedEngine = requested;
  securityScan.engine = selectedEngine;
  securityScan.target = target;
  securityScan.lastError = null;
  securityScan.command = null;
  securityStopRequested = false;

  pushSecurityLog('info', 'security scan started', { target, engine: selectedEngine, requestedEngine: requested });

  stopSecurityProgress();
  securityProgressTimer = setInterval(() => {
    if (!securityScan.running) return;
    securityScan.progress = Math.min(92, securityScan.progress + 1);
  }, 1400);

  const plans = selectedEngine === 'clamav' ? clamavPlans(target) : kicomavPlans(target);
  let planIndex = 0;
  let lineCount = 0;
  let settled = false;
  let failureDetail = '';

  const parseLine = (line, stream) => {
    const cleaned = stripAnsi(line).trim();
    if (!cleaned) return;
    lineCount += 1;
    if (selectedEngine === 'clamav') {
      const summary = parseClamavSummary(cleaned);
      if (summary.files != null) securityScan.scanned = summary.files;
      if (summary.infected != null) securityScan.threats = summary.infected;
      if (summary.errors != null) securityScan.suspicious = Math.max(securityScan.suspicious, summary.errors);
      if (/FOUND$/i.test(cleaned) && !/^Infected files/i.test(cleaned)) securityScan.threats += 1;
      if (/ERROR|Access denied|can'?t open|can't open|invalid/i.test(cleaned) && !/^Total errors/i.test(cleaned)) {
        securityScan.suspicious += 1;
      }
      if (/: OK$/i.test(cleaned) || /FOUND$/i.test(cleaned)) securityScan.scanned += 1;
    } else {
      const summary = parseKicomavSummary(cleaned);
      if (summary.files != null) securityScan.scanned = summary.files;
      if (summary.infected != null) securityScan.threats = summary.infected;
      if (summary.suspect != null) securityScan.suspicious = summary.suspect;
      if (summary.warnings != null && summary.suspect == null) securityScan.suspicious = Math.max(securityScan.suspicious, summary.warnings);
      if (/\binfected\b/i.test(cleaned) && !/^Infected files/i.test(cleaned)) securityScan.threats += 1;
      if ((/\bsuspect\b/i.test(cleaned) || /\bwarning\b/i.test(cleaned)) && !/^Suspect files/i.test(cleaned) && !/^Warnings/i.test(cleaned)) {
        securityScan.suspicious += 1;
      }
      if (/\bok\b/i.test(cleaned) || /\binfected\b/i.test(cleaned) || /\bsuspect\b/i.test(cleaned)) securityScan.scanned += 1;
    }

    securityScan.progress = Math.min(95, securityScan.progress + 1);

    const shouldLog = /^Results:|^Folders|^Files|^Infected files|^Suspect files|^Warnings|^Scan time|^Scanned files:|^Total errors:|^----------- SCAN SUMMARY -----------/i.test(cleaned)
      || /\berror\b|\bfailed\b|\binvalid\b|FOUND$/i.test(cleaned)
      || lineCount % 25 === 0;
    if (stream === 'stderr' && !failureDetail && /\berror\b|\bfailed\b|module|traceback|not found/i.test(cleaned)) {
      failureDetail = chunkString(cleaned, 220);
    }
    if (shouldLog) {
      const level = /\berror\b|\bfailed\b|\binvalid\b|FOUND$/i.test(cleaned) || stream === 'stderr' ? 'warn' : 'info';
      pushSecurityLog(level, cleaned, { stream });
    }
  };

  const finalize = (ok, errorMessage = '') => {
    if (settled) return;
    settled = true;
    stopSecurityProgress();
    securityScan.running = false;
    securityScan.finishedAt = new Date().toISOString();
    securityScan.progress = ok ? 100 : Math.max(1, securityScan.progress);
    securityScan.lastError = ok ? null : (errorMessage || failureDetail || 'security scan failed');
    const summary = { scanned: securityScan.scanned, threats: securityScan.threats, suspicious: securityScan.suspicious };
    if (ok) pushSecurityLog('ok', `security scan completed (${selectedEngine})`, summary);
    else pushSecurityLog('error', `security scan failed: ${securityScan.lastError}`, summary);
    securityProc = null;
  };

  const launch = () => {
    if (planIndex >= plans.length) {
      finalize(false, selectedEngine === 'clamav' ? 'clamscan launcher not found' : 'python launcher not found (py/python/python3)');
      return;
    }
    const plan = plans[planIndex];
    securityScan.command = `${plan.cmd} ${plan.args.join(' ')}`;
    pushSecurityLog('info', `security engine command: ${securityScan.command}`);
    const scanCwd = selectedEngine === 'clamav'
      ? (() => {
        const bin = clamavBinaryPath();
        const dir = bin ? path.dirname(bin) : CLAMAV_ROOT;
        return fs.existsSync(dir) ? dir : APP_ASSET_ROOT;
      })()
      : (fs.existsSync(KICOMAV_ROOT) ? KICOMAV_ROOT : APP_ASSET_ROOT);

    const proc = spawn(plan.cmd, plan.args, {
      cwd: scanCwd,
      windowsHide: true,
      env: { ...process.env, PYTHONUNBUFFERED: '1' }
    });
    securityProc = proc;

    const onChunk = (chunk, stream) => {
      String(chunk || '')
        .split(/\r?\n/)
        .forEach((line) => parseLine(line, stream));
    };
    proc.stdout.on('data', (d) => onChunk(d, 'stdout'));
    proc.stderr.on('data', (d) => onChunk(d, 'stderr'));

    proc.on('error', (err) => {
      if (securityStopRequested) {
        finalize(false, 'stopped by user');
        return;
      }
      const msg = String(err?.message || err || 'unknown spawn error');
      if (/ENOENT/i.test(msg)) {
        planIndex += 1;
        launch();
        return;
      }
      finalize(false, msg);
    });

    proc.on('close', (code) => {
      if (securityStopRequested) {
        finalize(false, 'stopped by user');
        return;
      }
      const successCodes = selectedEngine === 'clamav' ? [0, 1] : [0];
      if (successCodes.includes(Number(code))) {
        finalize(true);
        return;
      }
      if (code === 9009 || code === 127) {
        planIndex += 1;
        launch();
        return;
      }
      finalize(false, `exit code ${code}`);
    });
  };

  launch();
  return res.send({ ok: true, scan: securityScan });
});

app.get('/api/scheduler/tasks', (req, res) => res.send({ ok: true, tasks: schedulerTasks }));
app.post('/api/scheduler/tasks', (req, res) => {
  const schedule = String((req.body && req.body.schedule) || '').trim();
  const command = String((req.body && req.body.command) || '').trim();
  const user = String((req.body && req.body.user) || 'root');
  if (!schedule || !command) return res.status(400).send({ ok: false, error: 'schedule and command required' });
  const task = { id: `task-${Date.now()}`, cron: schedule, desc: command, user, status: 'active', lastRun: null, nextRun: 'pending' };
  schedulerTasks.push(task); pushLog('info', 'scheduler task created', { id: task.id }); return res.send({ ok: true, task });
});
app.patch('/api/scheduler/tasks/:id', (req, res) => {
  const t = schedulerTasks.find((x) => x.id === String(req.params.id));
  if (!t) return res.status(404).send({ ok: false, error: 'task not found' });
  if (req.body?.schedule != null) t.cron = String(req.body.schedule);
  if (req.body?.command != null) t.desc = String(req.body.command);
  if (req.body?.user != null) t.user = String(req.body.user);
  if (req.body?.status != null) t.status = String(req.body.status);
  return res.send({ ok: true, task: t });
});
app.delete('/api/scheduler/tasks/:id', (req, res) => {
  const i = schedulerTasks.findIndex((x) => x.id === String(req.params.id));
  if (i < 0) return res.status(404).send({ ok: false, error: 'task not found' });
  const removed = schedulerTasks.splice(i, 1)[0];
  return res.send({ ok: true, removed });
});
app.post('/api/scheduler/run', (req, res) => {
  const t = schedulerTasks.find((x) => x.id === String((req.body && req.body.id) || req.query.id || ''));
  if (!t) return res.status(404).send({ ok: false, error: 'task not found' });
  if (t.status === 'paused') return res.status(400).send({ ok: false, error: 'task paused' });
  t.lastRun = new Date().toISOString(); pushLog('info', `scheduler ran ${t.id}`); return res.send({ ok: true, result: { id: t.id, time: t.lastRun } });
});

app.post('/api/actions/execute', (req, res) => {
  const action = String((req.body && req.body.action) || '').trim();
  if (!action) return res.status(400).send({ ok: false, error: 'action required' });
  const advance = engines.advance;
  if (!advance) return res.status(500).send({ ok: false, error: 'advance engine unavailable' });

  if (action === 'quick-safe-clean') {
    advance.start({ mode: 'dump', dryRun: true, total: 90 });
    const message = 'Quick safe clean started';
    pushLog('info', message);
    pushEngineLog('info', message);
    return res.send({ ok: true, message });
  }
  if (action === 'registry-safe-scan') {
    advance.start({ mode: 'registry', dryRun: true, total: 90 });
    const message = 'Registry safe scan started';
    pushLog('info', message);
    pushEngineLog('info', message);
    return res.send({ ok: true, message });
  }
  if (action === 'backup-now') {
    if (typeof advance.createBackup !== 'function') return res.status(400).send({ ok: false, error: 'backup unsupported' });
    const entry = advance.createBackup({ note: 'quick action' });
    const message = `Backup created: ${entry.id}`;
    pushLog('info', message);
    pushEngineLog('info', message);
    return res.send({ ok: true, message, entry });
  }
  return res.status(400).send({ ok: false, error: `unknown action: ${action}` });
});

app.post('/api/report/generate', (req, res) => {
  const engineName = String(req.body?.engine || 'advance');
  const reportDir = path.join(DATA_BACKEND_DIR, 'reports');
  if (!fs.existsSync(reportDir)) fs.mkdirSync(reportDir, { recursive: true });

  const pad = (n) => String(n).padStart(2, '0');
  const now = new Date();
  const dd = pad(now.getDate());
  const mm = pad(now.getMonth() + 1);
  const yyyy = String(now.getFullYear());
  const baseName = `report-${dd}-${mm}-${yyyy}`;

  let out = path.join(reportDir, `${baseName}.html`);
  let idx = 1;
  while (fs.existsSync(out)) {
    out = path.join(reportDir, `${baseName}-${idx}.html`);
    idx += 1;
  }

  const selected = engineBuffers[engineName] || { logs: [], findings: [], duplicates: [], registry: [], backups: [] };
  const allEngineLogs = Object.keys(engineBuffers).flatMap((k) => (engineBuffers[k].logs || []).map((l) => ({ engine: k, ...l })));
  const allLogs = allEngineLogs
    .concat((appLogs || []).map((l) => ({ engine: 'system', ...l })))
    .sort((a, b) => String(a.time).localeCompare(String(b.time)));
  const logsForReport = allLogs.slice(-3500);

  const findings = selected.findings || [];
  const registry = selected.registry || [];
  const backups = selected.backups || [];

  const findingsRows = findings.slice(-3000).map((f) => `<tr><td class="mono">${escapeHtml(f.path)}</td><td>${Number(f.sizeKB || 0)}</td><td>${escapeHtml(f.category || '-')}</td><td>${escapeHtml(f.action || '-')}</td></tr>`).join('');
  const registryRows = registry.slice(-2000).map((r) => `<tr><td class="mono">${escapeHtml(r.key || '-')}</td><td>${escapeHtml(r.valueName || '-')}</td><td class="mono">${escapeHtml(r.target || '-')}</td><td>${escapeHtml(r.reason || '-')}</td><td>${escapeHtml(r.action || 'detected')}</td></tr>`).join('');
  const backupRows = backups.slice(-1000).map((b) => `<tr><td>${escapeHtml(b.id)}</td><td>${escapeHtml(b.time)}</td><td>${escapeHtml(b.meta?.note || '-')}</td></tr>`).join('');
  const logRows = logsForReport.map((l) => `<tr><td>${escapeHtml(l.time)}</td><td>${escapeHtml(String(l.level || 'info').toUpperCase())}</td><td>${escapeHtml(String(l.engine || 'system').toUpperCase())}</td><td class="mono">${escapeHtml(l.message || '')}</td></tr>`).join('');

  const html = `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>NeoOptimize Report ${dd}-${mm}-${yyyy}</title>
  <style>
    :root{color-scheme:light}
    body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:#f1f5f9;color:#0f172a}
    .wrap{max-width:1240px;margin:0 auto;padding:20px}
    .header{background:linear-gradient(135deg,#0f172a,#1e293b);color:#e2e8f0;padding:18px 20px;border-radius:14px;box-shadow:0 10px 28px rgba(2,6,23,.24)}
    .title{margin:0;font-size:28px;font-weight:700;letter-spacing:.3px}
    .sub{margin-top:4px;color:#cbd5e1;font-size:13px}
    .row{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin:14px 0}
    .card{background:#fff;border:1px solid #dbe4ee;border-radius:12px;padding:12px;box-shadow:0 2px 7px rgba(15,23,42,.05)}
    .metric{font-size:24px;font-weight:700;color:#0f172a}
    .muted{color:#475569}
    h3{margin:0 0 10px 0;font-size:14px;color:#0f172a}
    table{width:100%;border-collapse:collapse;font-size:12px;background:#fff;border-radius:10px;overflow:hidden}
    th,td{padding:8px 10px;border-bottom:1px solid #e2e8f0;text-align:left;vertical-align:top}
    th{background:#eef3f8;color:#1e293b;font-size:11px;text-transform:uppercase;letter-spacing:.35px}
    tr:nth-child(even) td{background:#fafcff}
    .mono{font-family:Consolas,Menlo,monospace}
    a{color:#0f62fe;text-decoration:none}
    a:hover{text-decoration:underline}
    @media (max-width:980px){.row{grid-template-columns:repeat(2,minmax(0,1fr))}}
    @media (max-width:640px){.row{grid-template-columns:1fr}}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="header">
      <h1 class="title">NeoOptimize Report</h1>
      <div class="sub">Generated: ${escapeHtml(now.toISOString())} | Engine: ${escapeHtml(engineName)} | Security Engine: ${escapeHtml(securityScan.engine || 'kicomav')}</div>
    </div>

    <div class="row">
      <div class="card"><div class="muted">Cleaner Findings</div><div class="metric">${findings.length}</div></div>
      <div class="card"><div class="muted">Registry Issues</div><div class="metric">${registry.length}</div></div>
      <div class="card"><div class="muted">Backups</div><div class="metric">${backups.length}</div></div>
      <div class="card"><div class="muted">Process Logs</div><div class="metric">${logsForReport.length}</div></div>
    </div>

    <div class="card">
      <h3>Cleaner Findings</h3>
      <table>
        <thead><tr><th>Path</th><th>Size KB</th><th>Category</th><th>Action</th></tr></thead>
        <tbody>${findingsRows || '<tr><td colspan="4" class="muted">No findings.</td></tr>'}</tbody>
      </table>
    </div>

    <div class="card">
      <h3>Registry Scan</h3>
      <table>
        <thead><tr><th>Registry Key</th><th>Value Name</th><th>Target Path</th><th>Reason</th><th>Action</th></tr></thead>
        <tbody>${registryRows || '<tr><td colspan="5" class="muted">No registry issues.</td></tr>'}</tbody>
      </table>
    </div>

    <div class="card">
      <h3>Backup Manager</h3>
      <table>
        <thead><tr><th>Backup ID</th><th>Time</th><th>Note</th></tr></thead>
        <tbody>${backupRows || '<tr><td colspan="3" class="muted">No backup records.</td></tr>'}</tbody>
      </table>
    </div>

    <div class="card">
      <h3>All Process Logs (System + Engine)</h3>
      <table>
        <thead><tr><th>Time</th><th>Level</th><th>Source</th><th>Message</th></tr></thead>
        <tbody>${logRows || '<tr><td colspan="4" class="muted">No log data.</td></tr>'}</tbody>
      </table>
    </div>

    <div class="card">
      <h3>Developer Contact</h3>
      <div>Nama: Sigit profesional IT</div>
      <div>WhatsApp: 087889911030</div>
      <div>Email: neooptimizeofficial@gmail.com</div>
      <div>Donasi:
        <a href="https://buymeacoffee.com/nol.eight" target="_blank" rel="noreferrer">BuyMeCoffe</a> |
        <a href="https://saweria.co/dtechtive" target="_blank" rel="noreferrer">Saweria</a> |
        <a href="https://ik.imagekit.io/dtechtive/Dana" target="_blank" rel="noreferrer">Dana</a>
      </div>
    </div>
  </div>
</body>
</html>`;

  fs.writeFileSync(out, html, 'utf-8');
  if (process.platform === 'win32') {
    const escaped = out.replace(/"/g, '""');
    runExec(`start "" "${escaped}"`, {}, () => {});
  }
  pushLog('info', 'report generated', { path: out, fileName: path.basename(out), logs: logsForReport.length, opened: process.platform === 'win32' });
  return res.send({
    ok: true,
    path: out,
    fileName: path.basename(out),
    generatedAt: now.toISOString(),
    logCount: logsForReport.length,
    opened: process.platform === 'win32'
  });
});

app.get('/api/config', (req, res) => {
  const p = req.query.path ? String(req.query.path) : configPath();
  try { return res.send({ ok: true, path: p, content: fs.readFileSync(p, 'utf-8') }); } catch (err) { return res.status(500).send({ ok: false, error: String(err) }); }
});
app.post('/api/config/save', (req, res) => {
  const p = req.body?.path ? String(req.body.path) : configPath();
  if (!pathAllowed(p)) return res.status(403).send({ ok: false, error: 'path not allowed' });
  const content = String(req.body?.content || '');
  try { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, content, 'utf-8'); pushLog('info', 'config saved', { path: p }); return res.send({ ok: true, path: p, size: content.length }); } catch (err) { return res.status(500).send({ ok: false, error: String(err) }); }
});
app.get('/api/config/summary', (req, res) => {
  const p = req.query.path ? String(req.query.path) : configPath();
  try { const c = fs.readFileSync(p, 'utf-8'); const sections = c.split(/\r?\n/).filter((ln) => /^##\s+/.test(ln)).map((ln) => ln.replace(/^##\s+/, '').trim()); return res.send({ ok: true, path: p, sections, sectionCount: sections.length }); } catch (err) { return res.status(500).send({ ok: false, error: String(err) }); }
});
app.get('/api/cleaner/spec', (req, res) => {
  const p = req.query.path ? String(req.query.path) : cleanerSpecPath();
  try { return res.send({ ok: true, path: p, content: fs.readFileSync(p, 'utf-8') }); } catch (err) { return res.status(500).send({ ok: false, error: String(err) }); }
});
app.get('/api/cleaner/spec/summary', (req, res) => {
  const p = req.query.path ? String(req.query.path) : cleanerSpecPath();
  try { const c = fs.readFileSync(p, 'utf-8'); const categories = c.split(/\r?\n/).filter((ln) => /^##\s+\*\*/.test(ln)).map((ln) => ln.replace(/^##\s+\*\*|\*\*$/g, '').trim()); return res.send({ ok: true, path: p, categories }); } catch (err) { return res.status(500).send({ ok: false, error: String(err) }); }
});

app.use((err, req, res, next) => {
  const message = String(err?.message || err || 'unknown error');
  pushLog('error', 'api unhandled exception', { path: req?.path || '-', message });
  if (res.headersSent) return next(err);
  return res.status(500).send({ ok: false, error: message });
});

if (!globalThis.__NEOOPTIMIZE_BACKEND_ERROR_HOOKS__) {
  globalThis.__NEOOPTIMIZE_BACKEND_ERROR_HOOKS__ = true;
  process.on('unhandledRejection', (reason) => {
    pushLog('error', 'process unhandledRejection', { message: String(reason?.message || reason || 'unknown') });
  });
  process.on('uncaughtException', (error) => {
    pushLog('error', 'process uncaughtException', { message: String(error?.message || error || 'unknown') });
  });
}

ensureLocalConfigFiles();

app.listen(PORT, () => {
  pushLog('info', `NeoOptimize API running on http://localhost:${PORT}`);
  console.log(`NeoOptimize API running on http://localhost:${PORT}`);
});
