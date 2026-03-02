import express from 'express';
import bodyParser from 'body-parser';
import cors from 'cors';
import fs from 'fs';
import fsp from 'fs/promises';
import path from 'path';
import os from 'os';
import dns from 'dns';
import crypto from 'crypto';
import net from 'net';
import { exec, execFile, spawn, spawnSync } from 'child_process';
import { fileURLToPath, pathToFileURL } from 'url';
import { createNeoTurboCleaner } from './engines/neoTurboCleaner.js';
import { createSanTurbo } from './engines/sanTurbo.js';

const app = express();
app.use(cors());
app.use(bodyParser.json({ limit: '2mb' }));

// Lightweight health endpoint for external probes and smoke tests
app.get('/api/health', (_req, res) => {
  try {
    return res.send({ ok: true, service: 'NeoOptimize', version: APP_VERSION, time: new Date().toISOString() });
  } catch (err) {
    return res.status(500).send({ ok: false, error: String(err?.message || err || 'unknown') });
  }
});

const PORT = process.env.PORT || 3322;
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const APP_ROOT = process.env.APP_ROOT ? path.resolve(process.env.APP_ROOT) : path.resolve(__dirname, '..');
const APP_ASSET_ROOT = process.env.APP_ASSET_ROOT ? path.resolve(process.env.APP_ASSET_ROOT) : APP_ROOT;
const APP_DATA_ROOT = process.env.APP_DATA_ROOT ? path.resolve(process.env.APP_DATA_ROOT) : APP_ROOT;
const APP_VERSION = (() => {
  try {
    const p = path.join(APP_ROOT, 'package.json');
    if (fs.existsSync(p)) {
      const raw = JSON.parse(fs.readFileSync(p, 'utf-8'));
      if (raw?.version) return String(raw.version);
    }
  } catch (err) {
    void err;
  }
  return String(process.env.npm_package_version || '1.0.0');
})();
const DATA_CONFIG_DIR = path.join(APP_DATA_ROOT, 'config');
const DATA_BACKEND_DIR = path.join(APP_DATA_ROOT, 'backend');
const ASSET_CONFIG_DIR = path.join(APP_ASSET_ROOT, 'config');
const engines = { advance: createNeoTurboCleaner(), santurbo: createSanTurbo() };
const engineBuffers = {};
const cleanerScanRuntime = {};
const appLogs = [];
const processTokens = new Map();
const applyTokens = new Map();
const PROCESS_TTL_MS = 30000;
const APPLY_TTL_MS = 120000;
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
const PROCESS_CACHE_MS = 6000;
const OVERVIEW_CACHE_MS = 4000;
const NETWORK_STATS_CACHE_MS = 10000;
const NETWORK_CONN_CACHE_MS = 8000;
const LOGS_CACHE_MS = 1500;
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
      } catch (invokeErr) {
        void invokeErr;
      }
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
const ANSI_CSI_REGEX = new RegExp(`${String.fromCharCode(27)}\\[[0-9;]*m`, 'g');
const stripAnsi = (v) => String(v || '').replace(ANSI_CSI_REGEX, '');
const chunkString = (v, max = 220) => {
  const s = String(v || '');
  if (s.length <= max) return s;
  return `${s.slice(0, Math.max(1, max - 3))}...`;
};
const windowsSuspendResumeScript = (pid, action) => {
  const fn = action === 'resume' ? 'NtResumeProcess' : 'NtSuspendProcess';
  return [
    "$ErrorActionPreference='Stop'",
    'Add-Type @\'',
    'using System;',
    'using System.Runtime.InteropServices;',
    'public static class NeoProcCtrl {',
    '  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint access, bool inheritHandle, int processId);',
    '  [DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr processHandle);',
    '  [DllImport("ntdll.dll")] public static extern int NtResumeProcess(IntPtr processHandle);',
    '  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr hObject);',
    '}',
    '\'@',
    `$targetPid = ${Number(pid) || 0}`,
    'if ($targetPid -le 0) { throw "invalid pid" }',
    '$PROCESS_SUSPEND_RESUME = 0x0800',
    '$PROCESS_QUERY_LIMITED_INFORMATION = 0x1000',
    '$handle = [NeoProcCtrl]::OpenProcess($PROCESS_SUSPEND_RESUME -bor $PROCESS_QUERY_LIMITED_INFORMATION, $false, $targetPid)',
    'if ($handle -eq [IntPtr]::Zero) { throw "OpenProcess failed for pid $targetPid" }',
    `$rc = [NeoProcCtrl]::${fn}($handle)`,
    '[void][NeoProcCtrl]::CloseHandle($handle)',
    `if ($rc -ne 0) { throw "${fn} failed with code $rc" }`,
    `Write-Output "${action} ok for pid $targetPid"`
  ].join('\n');
};
const windowsSuspendResume = (pid, action, cb) => {
  const script = windowsSuspendResumeScript(pid, action);
  runExecFile(
    'powershell.exe',
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
    { maxBuffer: 1024 * 1024, timeout: 20000 },
    cb
  );
};
const hasInternetReachability = (host = 'database.clamav.net', timeoutMs = 1800) => new Promise((resolve) => {
  if (process.env.NEOOPTIMIZE_OFFLINE === '1') {
    resolve(false);
    return;
  }
  let settled = false;
  const done = (ok) => {
    if (settled) return;
    settled = true;
    resolve(Boolean(ok));
  };
  const timer = setTimeout(() => done(false), Math.max(300, Number(timeoutMs) || 1800));
  dns.lookup(String(host || 'database.clamav.net'), (err) => {
    clearTimeout(timer);
    done(!err);
  });
});

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
const kicomavDbInfo = () => {
  const roots = [
    path.join(KICOMAV_ROOT, 'kicomav', 'plugins'),
    path.join(KICOMAV_ROOT, 'plugins'),
    path.join(KICOMAV_ROOT, 'data')
  ];
  for (const dir of roots) {
    if (!fs.existsSync(dir)) continue;
    try {
      const files = fs.readdirSync(dir, { withFileTypes: true })
        .filter((d) => d.isFile())
        .map((d) => path.join(dir, d.name));
      if (files.length > 0) {
        return {
          dir,
          ready: true,
          fileCount: files.length,
          files: files.slice(0, 40)
        };
      }
    } catch (err) {
      void err;
    }
  }
  return {
    dir: roots.find((d) => fs.existsSync(d)) || null,
    ready: false,
    fileCount: 0,
    files: []
  };
};
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
  const kicoDb = kicomavDbInfo();
  const clamBin = clamavBinaryPath();
  const clamProbe = probeClamavBinary(clamBin);
  const clamDb = resolveClamavDb(clamBin);
  const clam = Boolean(clamBin) && Boolean(clamProbe.runnable);
  const freshclam = clamavFreshclamPath();
  const clamReady = clam && Boolean(clamDb.ready);
  const recommended = clamReady ? 'clamav' : (kico ? 'kicomav' : null);
  return {
    recommended,
    kicomav: {
      available: kico,
      root: KICOMAV_ROOT,
      module: KICOMAV_MODULE,
      path: securitySettings.kicomavPath || path.join(KICOMAV_ROOT, 'kicomav', 'k2.py'),
      db: kicoDb
    },
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
const localCleanerSpecFile = path.join(DATA_CONFIG_DIR, 'neo turbo cleaner.txt');
const assetCleanerSpecFile = path.join(ASSET_CONFIG_DIR, 'neo turbo cleaner.txt');
const scriptCleanerSpecFile = 'C:/Users/Hello World/Documents/Script/neo turbo cleaner.txt';
const legacyLocalCleanerSpecFile = path.join(DATA_CONFIG_DIR, 'advance cleaner engine.txt');
const legacyAssetCleanerSpecFile = path.join(ASSET_CONFIG_DIR, 'advance cleaner engine.txt');
const legacyScriptCleanerSpecFile = 'C:/Users/Hello World/Documents/Script/advance cleaner engine.txt';
const securityConfigFile = path.join(DATA_CONFIG_DIR, 'security.json');
const diagnosticsConfigFile = path.join(DATA_CONFIG_DIR, 'diagnostics.json');
const diagnosticsOutboxDir = path.join(DATA_BACKEND_DIR, 'diagnostics');
const monitorAgentConfigFile = path.join(DATA_CONFIG_DIR, 'monitor-agent.json');
const DEFAULT_MONITOR_BASE_URL = String(process.env.NEOMONITOR_BASE_URL || process.env.NEO_MONITOR_BASE_URL || 'http://127.0.0.1:4411').trim().replace(/\/+$/, '');
const DEFAULT_DIAGNOSTICS_ENDPOINT = DEFAULT_MONITOR_BASE_URL ? `${DEFAULT_MONITOR_BASE_URL}/api/agent/diagnostics` : '';
const generateAgentSecret = () => `neo-agent-${crypto.randomBytes(12).toString('hex')}`;

const defaultSecuritySettings = { preferredEngine: 'auto', clamscanPath: '', clamDbDir: '', kicomavPath: '' };
const defaultDiagnosticsSettings = {
  enabled: true,
  endpoint: DEFAULT_DIAGNOSTICS_ENDPOINT,
  apiKey: '',
  timeoutMs: 12000,
  includeSystem: true,
  includeLogs: true,
  includeReportsMeta: true,
  includeConfigSummary: true,
  maxLogs: 1200,
  verbose: true,
  sendOnCrash: true,
  lastSentAt: null,
  lastError: null
};
const defaultMonitorAgentSettings = {
  enabled: true,
  monitorBaseUrl: DEFAULT_MONITOR_BASE_URL,
  agentId: '',
  agentKey: generateAgentSecret(),
  heartbeatSeconds: 30,
  pollSeconds: 30,
  allowRemoteActions: true,
  sendFullDeviceInfo: true,
  lastSyncAt: null,
  lastSyncError: null
};
const loadSecuritySettings = () => {
  try {
    if (!fs.existsSync(securityConfigFile)) return { ...defaultSecuritySettings };
    const raw = JSON.parse(fs.readFileSync(securityConfigFile, 'utf-8'));
    return {
      preferredEngine: ['auto', 'kicomav', 'clamav'].includes(String(raw?.preferredEngine || '').toLowerCase())
        ? String(raw.preferredEngine).toLowerCase()
        : 'auto',
      clamscanPath: String(raw?.clamscanPath || ''),
      clamDbDir: String(raw?.clamDbDir || ''),
      kicomavPath: String(raw?.kicomavPath || '')
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
    clamDbDir: String(patch.clamDbDir ?? securitySettings.clamDbDir ?? ''),
    kicomavPath: String(patch.kicomavPath ?? securitySettings.kicomavPath ?? '')
  };
  fs.mkdirSync(path.dirname(securityConfigFile), { recursive: true });
  fs.writeFileSync(securityConfigFile, JSON.stringify(next, null, 2), 'utf-8');
  securitySettings = next;
  return next;
};
const sanitizeDiagnosticsSettings = (patch = {}, previous = defaultDiagnosticsSettings) => {
  const timeoutMs = Number(patch.timeoutMs ?? previous.timeoutMs ?? defaultDiagnosticsSettings.timeoutMs);
  const maxLogs = Number(patch.maxLogs ?? previous.maxLogs ?? defaultDiagnosticsSettings.maxLogs);
  return {
    enabled: Boolean(patch.enabled ?? previous.enabled ?? false),
    endpoint: String(patch.endpoint ?? previous.endpoint ?? '').trim(),
    apiKey: String(patch.apiKey ?? previous.apiKey ?? '').trim(),
    timeoutMs: Number.isFinite(timeoutMs) ? Math.max(3000, Math.min(60000, Math.floor(timeoutMs))) : defaultDiagnosticsSettings.timeoutMs,
    includeSystem: Boolean(patch.includeSystem ?? previous.includeSystem ?? true),
    includeLogs: Boolean(patch.includeLogs ?? previous.includeLogs ?? true),
    includeReportsMeta: Boolean(patch.includeReportsMeta ?? previous.includeReportsMeta ?? true),
    includeConfigSummary: Boolean(patch.includeConfigSummary ?? previous.includeConfigSummary ?? false),
    maxLogs: Number.isFinite(maxLogs) ? Math.max(50, Math.min(3500, Math.floor(maxLogs))) : defaultDiagnosticsSettings.maxLogs,
    verbose: Boolean(patch.verbose ?? previous.verbose ?? false),
    sendOnCrash: Boolean(patch.sendOnCrash ?? previous.sendOnCrash ?? false),
    lastSentAt: patch.lastSentAt ?? previous.lastSentAt ?? null,
    lastError: patch.lastError ?? previous.lastError ?? null
  };
};
const loadDiagnosticsSettings = () => {
  try {
    if (!fs.existsSync(diagnosticsConfigFile)) return { ...defaultDiagnosticsSettings };
    const raw = JSON.parse(fs.readFileSync(diagnosticsConfigFile, 'utf-8'));
    return sanitizeDiagnosticsSettings(raw, defaultDiagnosticsSettings);
  } catch {
    return { ...defaultDiagnosticsSettings };
  }
};
let diagnosticsSettings = loadDiagnosticsSettings();
const saveDiagnosticsSettings = (patch = {}) => {
  const merged = sanitizeDiagnosticsSettings({ ...diagnosticsSettings, ...patch }, diagnosticsSettings);
  fs.mkdirSync(path.dirname(diagnosticsConfigFile), { recursive: true });
  fs.writeFileSync(diagnosticsConfigFile, JSON.stringify(merged, null, 2), 'utf-8');
  diagnosticsSettings = merged;
  return diagnosticsSettings;
};
const sanitizeMonitorAgentSettings = (patch = {}, previous = defaultMonitorAgentSettings) => {
  const hb = Number(patch.heartbeatSeconds ?? previous.heartbeatSeconds ?? defaultMonitorAgentSettings.heartbeatSeconds);
  const poll = Number(patch.pollSeconds ?? previous.pollSeconds ?? defaultMonitorAgentSettings.pollSeconds);
  const monitorBaseUrl = String(patch.monitorBaseUrl ?? previous.monitorBaseUrl ?? '').trim().replace(/\/+$/, '');
  const priorAgentId = String(previous.agentId || '').trim();
  const agentId = String(patch.agentId ?? priorAgentId).trim() || `neo-${crypto.randomUUID()}`;
  return {
    enabled: Boolean(patch.enabled ?? previous.enabled ?? false),
    monitorBaseUrl,
    agentId,
    agentKey: String(patch.agentKey ?? previous.agentKey ?? '').trim(),
    heartbeatSeconds: Number.isFinite(hb) ? Math.max(20, Math.min(600, Math.floor(hb))) : defaultMonitorAgentSettings.heartbeatSeconds,
    pollSeconds: Number.isFinite(poll) ? Math.max(15, Math.min(600, Math.floor(poll))) : defaultMonitorAgentSettings.pollSeconds,
    allowRemoteActions: Boolean(patch.allowRemoteActions ?? previous.allowRemoteActions ?? false),
    sendFullDeviceInfo: Boolean(patch.sendFullDeviceInfo ?? previous.sendFullDeviceInfo ?? true),
    lastSyncAt: patch.lastSyncAt ?? previous.lastSyncAt ?? null,
    lastSyncError: patch.lastSyncError ?? previous.lastSyncError ?? null
  };
};
const loadMonitorAgentSettings = () => {
  try {
    if (!fs.existsSync(monitorAgentConfigFile)) {
      return sanitizeMonitorAgentSettings(defaultMonitorAgentSettings, defaultMonitorAgentSettings);
    }
    const raw = JSON.parse(fs.readFileSync(monitorAgentConfigFile, 'utf-8'));
    return sanitizeMonitorAgentSettings(raw, defaultMonitorAgentSettings);
  } catch {
    return sanitizeMonitorAgentSettings(defaultMonitorAgentSettings, defaultMonitorAgentSettings);
  }
};
let monitorAgentSettings = loadMonitorAgentSettings();
const saveMonitorAgentSettings = (patch = {}) => {
  const previousBaseUrl = String(monitorAgentSettings.monitorBaseUrl || '').trim().replace(/\/+$/, '');
  const previousDiagnosticsEndpoint = previousBaseUrl ? `${previousBaseUrl}/api/agent/diagnostics` : '';
  const next = sanitizeMonitorAgentSettings({ ...monitorAgentSettings, ...patch }, monitorAgentSettings);
  fs.mkdirSync(path.dirname(monitorAgentConfigFile), { recursive: true });
  fs.writeFileSync(monitorAgentConfigFile, JSON.stringify(next, null, 2), 'utf-8');
  monitorAgentSettings = next;
  const nextDiagnosticsEndpoint = next.monitorBaseUrl ? `${next.monitorBaseUrl}/api/agent/diagnostics` : '';
  const currentEndpoint = String(diagnosticsSettings.endpoint || '').trim().replace(/\/+$/, '');
  const shouldSyncEndpoint = !currentEndpoint || currentEndpoint === previousDiagnosticsEndpoint || currentEndpoint === DEFAULT_DIAGNOSTICS_ENDPOINT;
  if (next.enabled) {
    saveDiagnosticsSettings({
      enabled: true,
      verbose: true,
      sendOnCrash: true,
      ...(shouldSyncEndpoint && nextDiagnosticsEndpoint ? { endpoint: nextDiagnosticsEndpoint } : {})
    });
  } else if (shouldSyncEndpoint && nextDiagnosticsEndpoint) {
    saveDiagnosticsSettings({ endpoint: nextDiagnosticsEndpoint });
  }
  return monitorAgentSettings;
};
const applyRecommendedRemoteDefaults = () => {
  const baseUrl = monitorAgentSettings.monitorBaseUrl || DEFAULT_MONITOR_BASE_URL || '';
  const monitorPatch = {};
  if (!monitorAgentSettings.enabled) monitorPatch.enabled = true;
  if (!monitorAgentSettings.monitorBaseUrl && baseUrl) monitorPatch.monitorBaseUrl = baseUrl;
  if (!String(monitorAgentSettings.agentKey || '').trim()) monitorPatch.agentKey = generateAgentSecret();
  if (!monitorAgentSettings.allowRemoteActions) monitorPatch.allowRemoteActions = true;
  if (!monitorAgentSettings.sendFullDeviceInfo) monitorPatch.sendFullDeviceInfo = true;
  if (Number(monitorAgentSettings.heartbeatSeconds || 0) > 45 || Number(monitorAgentSettings.heartbeatSeconds || 0) <= 0) monitorPatch.heartbeatSeconds = 30;
  if (Number(monitorAgentSettings.pollSeconds || 0) > 45 || Number(monitorAgentSettings.pollSeconds || 0) <= 0) monitorPatch.pollSeconds = 30;
  if (Object.keys(monitorPatch).length > 0) saveMonitorAgentSettings(monitorPatch);

  const diagnosticsPatch = {};
  if (!diagnosticsSettings.enabled) diagnosticsPatch.enabled = true;
  if (!diagnosticsSettings.endpoint && baseUrl) diagnosticsPatch.endpoint = `${baseUrl}/api/agent/diagnostics`;
  if (!diagnosticsSettings.includeSystem) diagnosticsPatch.includeSystem = true;
  if (!diagnosticsSettings.includeLogs) diagnosticsPatch.includeLogs = true;
  if (!diagnosticsSettings.includeReportsMeta) diagnosticsPatch.includeReportsMeta = true;
  if (!diagnosticsSettings.includeConfigSummary) diagnosticsPatch.includeConfigSummary = true;
  if (!diagnosticsSettings.verbose) diagnosticsPatch.verbose = true;
  if (!diagnosticsSettings.sendOnCrash) diagnosticsPatch.sendOnCrash = true;
  if (Number(diagnosticsSettings.maxLogs || 0) < 600) diagnosticsPatch.maxLogs = 1200;
  if (Object.keys(diagnosticsPatch).length > 0) saveDiagnosticsSettings(diagnosticsPatch);
};
const monitorAgentRuntime = {
  timer: null,
  syncBusy: false,
  lastSyncAt: null,
  lastSyncError: null,
  queuedResults: [],
  history: []
};
const ensureDiagnosticsOutboxDir = () => {
  if (!fs.existsSync(diagnosticsOutboxDir)) fs.mkdirSync(diagnosticsOutboxDir, { recursive: true });
  return diagnosticsOutboxDir;
};

const redactText = (input) => {
  let text = String(input ?? '');
  const profile = String(process.env.USERPROFILE || '').trim();
  if (profile) {
    const escaped = profile.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    text = text.replace(new RegExp(escaped, 'gi'), '%USERPROFILE%');
  }
  text = text.replace(/[A-Z]:\\Users\\[^\\\s]+/gi, (m) => m.replace(/\\Users\\[^\\\s]+/i, '\\Users\\<redacted>'));
  return text;
};
const redactObject = (value) => {
  if (value == null) return value;
  if (typeof value === 'string') return redactText(value);
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (Array.isArray(value)) return value.map((v) => redactObject(v));
  if (typeof value === 'object') {
    const out = {};
    Object.keys(value).forEach((k) => {
      out[k] = redactObject(value[k]);
    });
    return out;
  }
  return String(value);
};
const diagnosticsPayload = (settings = diagnosticsSettings, reqBody = {}) => {
  const limit = Math.max(50, Math.min(3500, Number(reqBody.maxLogs || settings.maxLogs || 600)));
  const engineLogs = Object.keys(engineBuffers).flatMap((k) => (engineBuffers[k].logs || []).map((l) => ({ engine: k, ...l })));
  const allLogs = engineLogs.concat(appLogs.map((l) => ({ engine: 'system', ...l }))).sort((a, b) => String(a.time).localeCompare(String(b.time)));
  const reportsMeta = listReportFiles().slice(0, 30);
  const configSummary = (() => {
    try {
      const c = fs.readFileSync(configPath(), 'utf-8');
      const sections = c.split(/\r?\n/).filter((ln) => /^##\s+/.test(ln)).map((ln) => ln.replace(/^##\s+/, '').trim());
      return { path: configPath(), sections: sections.slice(0, 200), sectionCount: sections.length };
    } catch (err) {
      return { error: String(err) };
    }
  })();
  const payload = {
    id: `diag-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    generatedAt: new Date().toISOString(),
    app: {
      name: 'NeoOptimize',
      version: process.env.npm_package_version || '1.0.0',
      platform: process.platform,
      arch: process.arch,
      node: process.version
    },
    settingsSnapshot: {
      verbose: Boolean(settings.verbose),
      sendOnCrash: Boolean(settings.sendOnCrash),
      includeSystem: Boolean(settings.includeSystem),
      includeLogs: Boolean(settings.includeLogs),
      includeReportsMeta: Boolean(settings.includeReportsMeta),
      includeConfigSummary: Boolean(settings.includeConfigSummary)
    },
    system: settings.includeSystem ? {
      hostname: os.hostname(),
      release: os.release(),
      uptimeSec: Number(os.uptime() || 0),
      cpus: (os.cpus() || []).length,
      memory: { total: Number(os.totalmem() || 0), free: Number(os.freemem() || 0) }
    } : undefined,
    security: securityEngineInfo(),
    scan: securityScan,
    logs: settings.includeLogs ? allLogs.slice(-limit) : undefined,
    reports: settings.includeReportsMeta ? reportsMeta : undefined,
    configSummary: settings.includeConfigSummary ? configSummary : undefined
  };
  return redactObject(payload);
};
const diagnosticsOutboxFile = (payload) => {
  const dir = ensureDiagnosticsOutboxDir();
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const out = path.join(dir, `${payload.id || `diag-${stamp}`}.json`);
  fs.writeFileSync(out, JSON.stringify(payload, null, 2), 'utf-8');
  return out;
};
const updateDiagnosticsSendResult = ({ sentAt = null, error = null } = {}) => {
  try {
    saveDiagnosticsSettings({ lastSentAt: sentAt || diagnosticsSettings.lastSentAt, lastError: error || null });
  } catch (err) {
    void err;
  }
};
const queueCrashDiagnostics = (kind, input) => {
  if (!diagnosticsSettings.sendOnCrash) return null;
  try {
    const payload = diagnosticsPayload(
      sanitizeDiagnosticsSettings({ ...diagnosticsSettings, includeLogs: true, maxLogs: Math.max(400, diagnosticsSettings.maxLogs || 600) }, diagnosticsSettings),
      {}
    );
    payload.crash = {
      kind: String(kind || 'process'),
      at: new Date().toISOString(),
      message: String(input?.message || input || 'unknown'),
      stack: String(input?.stack || '').slice(0, 6000)
    };
    const out = diagnosticsOutboxFile(payload);
    updateDiagnosticsSendResult({ error: `crash queued: ${kind}` });
    return out;
  } catch {
    return null;
  }
};

const isProcessElevated = () => {
  if (process.platform !== 'win32') {
    try { return typeof process.getuid === 'function' ? process.getuid() === 0 : false; } catch { return false; }
  }
  try {
    const who = spawnSync('whoami', ['/groups'], { windowsHide: true, encoding: 'utf-8', timeout: 8000 });
    const out = `${who.stdout || ''}\n${who.stderr || ''}`;
    if (/High Mandatory Level|System Mandatory Level/i.test(out)) return true;
    if (/S-1-16-12288|S-1-16-16384/i.test(out)) return true;
  } catch (err) {
    void err;
  }
  return false;
};
const checkWritableDir = (dir) => {
  try {
    fs.mkdirSync(dir, { recursive: true });
    const probe = path.join(dir, `.write-test-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.tmp`);
    fs.writeFileSync(probe, 'ok', 'utf-8');
    fs.unlinkSync(probe);
    return { ok: true };
  } catch (err) {
    return { ok: false, error: String(err?.message || err) };
  }
};
const releaseReadiness = () => {
  const checks = [];
  const configFile = configPath();
  const cleanerFile = cleanerSpecPath();
  const sec = securityEngineInfo();
  const dataWrite = checkWritableDir(DATA_BACKEND_DIR);
  const reportWrite = checkWritableDir(reportDirPath());
  const backupWrite = checkWritableDir(path.join(DATA_BACKEND_DIR, 'backups'));
  const hasConfig = fs.existsSync(configFile);
  const hasCleaner = fs.existsSync(cleanerFile);
  const hasEngine = Boolean(sec.kicomav?.available || sec.clamav?.available);
  const admin = isProcessElevated();
  const releaseDir = path.join(APP_ROOT, 'release');
  const releaseFiles = fs.existsSync(releaseDir)
    ? fs.readdirSync(releaseDir).filter((f) => /\.exe$/i.test(f))
    : [];
  const hasInstaller = releaseFiles.some((f) => /setup/i.test(f));
  const hasPortable = releaseFiles.some((f) => /^neooptimize\s+\d+\.\d+\.\d+\.exe$/i.test(f));
  const signature = (() => {
    if (process.platform !== 'win32') return { ok: true, status: 'n/a', detail: 'non-windows runtime' };
    const escaped = String(process.execPath || '').replace(/'/g, "''");
    const psCmd = [
      "$securityModule = Join-Path $PSHOME 'Modules\\Microsoft.PowerShell.Security\\Microsoft.PowerShell.Security.psd1'",
      "if (Test-Path $securityModule) { Import-Module $securityModule -ErrorAction SilentlyContinue | Out-Null }",
      "$cmd = Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue",
      "if (-not $cmd) { Write-Output 'Unavailable'; exit 0 }",
      `(Get-AuthenticodeSignature -FilePath '${escaped}').Status.ToString()`
    ].join('; ');
    const shells = ['powershell.exe', 'pwsh.exe'];
    let lastStatus = 'Unknown';
    for (const shell of shells) {
      try {
        const sig = spawnSync(shell, ['-NoProfile', '-Command', psCmd], {
          windowsHide: true,
          encoding: 'utf-8',
          timeout: 12000
        });
        const status = String(`${sig.stdout || ''}\n${sig.stderr || ''}`)
          .split(/\r?\n/)
          .map((s) => s.trim())
          .find(Boolean) || 'Unknown';
        lastStatus = status;
        if (/^unavailable$/i.test(status)) continue;
        const ok = /^valid$/i.test(status);
        return { ok, status, detail: ok ? 'Valid Authenticode signature' : `signature status: ${status}` };
      } catch (err) {
        lastStatus = String(err?.message || err || 'Error');
      }
    }
    if (/^unavailable$/i.test(lastStatus)) {
      return { ok: false, status: lastStatus, detail: 'Get-AuthenticodeSignature not available on host' };
    }
    return { ok: false, status: lastStatus, detail: `signature status: ${lastStatus}` };
  })();

  checks.push({ id: 'config-file', label: 'Config file available', ok: hasConfig, severity: 'error', detail: hasConfig ? configFile : `Missing: ${configFile}` });
  checks.push({ id: 'cleaner-spec', label: 'Cleaner spec available', ok: hasCleaner, severity: 'error', detail: hasCleaner ? cleanerFile : `Missing: ${cleanerFile}` });
  checks.push({ id: 'security-engine', label: 'Security engine available', ok: hasEngine, severity: 'error', detail: hasEngine ? `Recommended: ${sec.recommended || 'none'}` : 'No ClamAV/KicomAV runtime detected' });
  checks.push({ id: 'admin-rights', label: 'Running elevated (admin)', ok: admin, severity: 'warning', detail: admin ? 'Process elevated' : 'Run as administrator for full operation' });
  checks.push({ id: 'data-writable', label: 'Data directory writable', ok: dataWrite.ok, severity: 'error', detail: dataWrite.ok ? DATA_BACKEND_DIR : dataWrite.error });
  checks.push({ id: 'report-writable', label: 'Report directory writable', ok: reportWrite.ok, severity: 'error', detail: reportWrite.ok ? reportDirPath() : reportWrite.error });
  checks.push({ id: 'backup-writable', label: 'Backup directory writable', ok: backupWrite.ok, severity: 'error', detail: backupWrite.ok ? path.join(DATA_BACKEND_DIR, 'backups') : backupWrite.error });
  checks.push({ id: 'release-installer', label: 'Installer artifact exists', ok: hasInstaller, severity: 'warning', detail: hasInstaller ? 'Found in release/' : 'Build installer before release' });
  checks.push({ id: 'release-portable', label: 'Portable artifact exists', ok: hasPortable, severity: 'warning', detail: hasPortable ? 'Found in release/' : 'Build portable before release' });
  checks.push({ id: 'code-signing', label: 'Code-signing certificate', ok: signature.ok, severity: 'error', detail: signature.detail });

  const failedErrors = checks.filter((c) => c.severity === 'error' && !c.ok);
  const failedWarnings = checks.filter((c) => c.severity === 'warning' && !c.ok);
  const score = Math.max(0, Math.min(100, Math.round(((checks.length - failedErrors.length - (failedWarnings.length * 0.35)) / checks.length) * 100)));
  return {
    ok: failedErrors.length === 0,
    score,
    checks,
    failed: { errors: failedErrors.length, warnings: failedWarnings.length },
    generatedAt: new Date().toISOString()
  };
};
const clearAllLogs = () => {
  const systemLogs = appLogs.length;
  const engineLogs = Object.keys(engineBuffers).reduce((sum, k) => sum + Number((engineBuffers[k]?.logs || []).length || 0), 0);
  appLogs.length = 0;
  Object.keys(engineBuffers).forEach((k) => {
    if (Array.isArray(engineBuffers[k]?.logs)) engineBuffers[k].logs.length = 0;
  });
  runtimeCache.logs = { at: 0, value: null, key: '' };
  return { systemLogs, engineLogs, total: systemLogs + engineLogs };
};
const monitorSafeSettings = () => ({
  ...monitorAgentSettings,
  agentKey: monitorAgentSettings.agentKey ? '***' : ''
});
const queueMonitorResult = (entry) => {
  monitorAgentRuntime.queuedResults.push(entry);
  if (monitorAgentRuntime.queuedResults.length > 120) monitorAgentRuntime.queuedResults.shift();
  monitorAgentRuntime.history.push(entry);
  if (monitorAgentRuntime.history.length > 500) monitorAgentRuntime.history.shift();
};
const collectMonitorDeviceSnapshot = () => {
  const interfaces = os.networkInterfaces() || {};
  const nic = Object.keys(interfaces).slice(0, 20).map((name) => ({
    name,
    addrs: (interfaces[name] || []).slice(0, 8).map((a) => ({ address: a.address, family: a.family, internal: a.internal, mac: a.mac }))
  }));
  const sec = securityEngineInfo();
  const advance = engines.advance;
  const cleaner = advance && typeof advance.status === 'function' ? advance.status() : {};
  return redactObject({
    agentId: monitorAgentSettings.agentId,
    app: { name: 'NeoOptimize', version: APP_VERSION },
    machine: {
      hostname: os.hostname(),
      platform: os.platform(),
      release: os.release(),
      arch: os.arch(),
      uptimeSec: os.uptime(),
      admin: isProcessElevated()
    },
    cpu: {
      count: (os.cpus() || []).length,
      model: (os.cpus() && os.cpus()[0] ? os.cpus()[0].model : ''),
      loadAvg: os.loadavg()
    },
    memory: {
      total: os.totalmem(),
      free: os.freemem(),
      used: os.totalmem() - os.freemem()
    },
    network: nic,
    engines: sec,
    cleaner,
    scheduler: { total: schedulerTasks.length, active: schedulerTasks.filter((t) => t.status !== 'paused').length },
    logs: {
      system: appLogs.length,
      engine: Object.keys(engineBuffers).reduce((sum, k) => sum + Number((engineBuffers[k]?.logs || []).length || 0), 0)
    }
  });
};
const monitorActionExecutor = async (action = {}) => {
  const type = String(action.type || '').toLowerCase();
  if (!type) return { ok: false, error: 'missing action type' };
  if (!monitorAgentSettings.allowRemoteActions && !['ping', 'readiness'].includes(type)) {
    return { ok: false, error: 'remote actions disabled by user' };
  }
  if (type === 'ping') return { ok: true, message: 'pong' };
  if (type === 'readiness') return { ok: true, readiness: releaseReadiness() };
  if (type === 'quick-safe-clean') return executeQuickAction('quick-safe-clean');
  if (type === 'registry-safe-scan') return executeQuickAction('registry-safe-scan');
  if (type === 'backup-now') return executeQuickAction('backup-now');
  if (type === 'clear-logs') return { ok: true, cleared: clearAllLogs(), message: 'logs cleared' };
  if (type === 'diagnostics-send') {
    const payload = diagnosticsPayload(diagnosticsSettings, { maxLogs: diagnosticsSettings.maxLogs });
    const outboxPath = diagnosticsOutboxFile(payload);
    return { ok: true, message: 'diagnostics queued', outboxPath };
  }
  return { ok: false, error: `unsupported action type: ${type}` };
};
const runMonitorAgentSync = async (trigger = 'manual') => {
  if (!monitorAgentSettings.enabled) return { ok: false, error: 'monitor agent disabled' };
  if (!monitorAgentSettings.monitorBaseUrl) return { ok: false, error: 'monitorBaseUrl is empty' };
  if (monitorAgentRuntime.syncBusy) return { ok: false, error: 'sync busy', busy: true };
  monitorAgentRuntime.syncBusy = true;
  try {
    const payload = {
      ok: true,
      trigger,
      at: new Date().toISOString(),
      agentId: monitorAgentSettings.agentId,
      appVersion: APP_VERSION,
      device: monitorAgentSettings.sendFullDeviceInfo ? collectMonitorDeviceSnapshot() : {
        agentId: monitorAgentSettings.agentId,
        app: { name: 'NeoOptimize', version: APP_VERSION },
        machine: { hostname: os.hostname(), platform: os.platform(), release: os.release(), arch: os.arch(), admin: isProcessElevated() }
      },
      actionResults: monitorAgentRuntime.queuedResults.splice(0, 40)
    };
    const headers = { 'Content-Type': 'application/json', 'X-Agent-Id': monitorAgentSettings.agentId };
    if (monitorAgentSettings.agentKey) headers['X-Agent-Key'] = monitorAgentSettings.agentKey;

    const timeoutMs = 12000;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    const response = await fetch(`${monitorAgentSettings.monitorBaseUrl}/api/agent/heartbeat`, {
      method: 'POST',
      headers,
      body: JSON.stringify(payload),
      signal: controller.signal
    });
    clearTimeout(timer);
    const text = await response.text();
    const json = parseJson(text, null);
    if (!response.ok || !json?.ok) {
      const error = String(json?.error || `monitor heartbeat failed (${response.status})`);
      monitorAgentRuntime.lastSyncError = error;
      monitorAgentRuntime.lastSyncAt = new Date().toISOString();
      saveMonitorAgentSettings({ lastSyncAt: monitorAgentRuntime.lastSyncAt, lastSyncError: error });
      return { ok: false, error };
    }

    const actions = Array.isArray(json.actions) ? json.actions.slice(0, 8) : [];
    const executed = [];
    for (const action of actions) {
      const started = Date.now();
      const result = await monitorActionExecutor(action);
      const entry = {
        id: String(action.id || `local-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`),
        type: String(action.type || ''),
        ok: Boolean(result?.ok),
        at: new Date().toISOString(),
        durationMs: Date.now() - started,
        result: redactObject(result)
      };
      queueMonitorResult(entry);
      executed.push(entry);
      pushLog(entry.ok ? 'ok' : 'warn', `monitor action ${entry.type} ${entry.ok ? 'done' : 'failed'}`, { actionId: entry.id });
    }

    monitorAgentRuntime.lastSyncAt = new Date().toISOString();
    monitorAgentRuntime.lastSyncError = null;
    saveMonitorAgentSettings({ lastSyncAt: monitorAgentRuntime.lastSyncAt, lastSyncError: null });
    return { ok: true, actionsReceived: actions.length, actionsExecuted: executed.length, at: monitorAgentRuntime.lastSyncAt };
  } catch (err) {
    const error = String(err?.message || err);
    monitorAgentRuntime.lastSyncError = error;
    monitorAgentRuntime.lastSyncAt = new Date().toISOString();
    saveMonitorAgentSettings({ lastSyncAt: monitorAgentRuntime.lastSyncAt, lastSyncError: error });
    return { ok: false, error };
  } finally {
    monitorAgentRuntime.syncBusy = false;
  }
};
const startMonitorAgentLoop = () => {
  if (monitorAgentRuntime.timer) {
    clearInterval(monitorAgentRuntime.timer);
    monitorAgentRuntime.timer = null;
  }
  if (!monitorAgentSettings.enabled || !monitorAgentSettings.monitorBaseUrl) return;
  const intervalSeconds = Math.max(15, Math.min(600, Math.min(monitorAgentSettings.pollSeconds, monitorAgentSettings.heartbeatSeconds)));
  monitorAgentRuntime.timer = setInterval(() => {
    runMonitorAgentSync('interval').catch((err) => {
      monitorAgentRuntime.lastSyncError = String(err?.message || err);
    });
  }, intervalSeconds * 1000);
  setTimeout(() => {
    runMonitorAgentSync('startup').catch((err) => {
      monitorAgentRuntime.lastSyncError = String(err?.message || err);
    });
  }, 2500);
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
    const source = fs.existsSync(assetCleanerSpecFile)
      ? assetCleanerSpecFile
      : fs.existsSync(scriptCleanerSpecFile)
        ? scriptCleanerSpecFile
        : fs.existsSync(legacyAssetCleanerSpecFile)
          ? legacyAssetCleanerSpecFile
          : legacyScriptCleanerSpecFile;
    ensureSeedFile(localCleanerSpecFile, source);
  }
  if (!fs.existsSync(diagnosticsConfigFile)) {
    saveDiagnosticsSettings(defaultDiagnosticsSettings);
  }
  if (!fs.existsSync(monitorAgentConfigFile)) {
    saveMonitorAgentSettings(defaultMonitorAgentSettings);
  }
  if (String(process.env.NEOOPTIMIZE_ENFORCE_REMOTE_PROFILE || '1') !== '0') {
    applyRecommendedRemoteDefaults();
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
  if (fs.existsSync(scriptCleanerSpecFile)) return scriptCleanerSpecFile;
  if (fs.existsSync(legacyLocalCleanerSpecFile)) return legacyLocalCleanerSpecFile;
  if (fs.existsSync(legacyAssetCleanerSpecFile)) return legacyAssetCleanerSpecFile;
  return legacyScriptCleanerSpecFile;
};
const reportDirPath = () => {
  const dir = path.join(DATA_BACKEND_DIR, 'reports');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  return dir;
};
const reportNameSafe = (value) => {
  const fileName = path.basename(String(value || ''));
  if (!/^report-[a-z0-9._-]+\.html$/i.test(fileName)) return '';
  return fileName;
};
const listReportFiles = () => {
  const dir = reportDirPath();
  return fs.readdirSync(dir, { withFileTypes: true })
    .filter((d) => d.isFile() && /^report-[a-z0-9._-]+\.html$/i.test(d.name))
    .map((d) => {
      const fullPath = path.join(dir, d.name);
      const st = fs.statSync(fullPath);
      return {
        fileName: d.name,
        path: fullPath,
        size: Number(st.size || 0),
        modifiedAt: st.mtime.toISOString()
      };
    })
    .sort((a, b) => String(b.modifiedAt).localeCompare(String(a.modifiedAt)));
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

const safeHostInput = (input, fallback = '127.0.0.1') => {
  const host = String(input || '').trim() || fallback;
  if (!/^[a-zA-Z0-9._:-]{1,255}$/.test(host)) return fallback;
  return host;
};

const safeDriveLetter = (value = '') => {
  const raw = String(value || '').trim().toUpperCase();
  const m = raw.match(/^([A-Z]):?$/);
  if (!m) return '';
  return `${m[1]}:`;
};

const toSafeFileUrl = (targetPath) => {
  try {
    return pathToFileURL(targetPath).href;
  } catch {
    return null;
  }
};

const runPowerShellAsync = async (script, options = {}) => {
  const out = await runExecFileAsync(
    'powershell.exe',
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', String(script || '')],
    {
      maxBuffer: 1024 * 1024 * 8,
      timeout: Number(options.timeout || 30000),
      cwd: options.cwd || process.cwd()
    }
  );
  return out;
};

const hostPortRange = (rawRange = '') => {
  const text = String(rawRange || '').trim();
  const single = text.match(/^(\d{1,5})$/);
  if (single) {
    const one = Number(single[1]);
    if (one >= 1 && one <= 65535) return { from: one, to: one };
  }
  const m = text.match(/^(\d{1,5})\s*-\s*(\d{1,5})$/);
  if (m) {
    const a = Number(m[1]);
    const b = Number(m[2]);
    const from = Math.max(1, Math.min(a, b));
    const to = Math.min(65535, Math.max(a, b));
    if (from <= to) return { from, to };
  }
  return { from: 20, to: 1024 };
};

const scanSinglePort = (host, port, timeoutMs = 500) => new Promise((resolve) => {
  const startedAt = Date.now();
  const socket = new net.Socket();
  let settled = false;
  const done = (open, errorMessage = '') => {
    if (settled) return;
    settled = true;
    try {
      socket.destroy();
    } catch {
      // no-op
    }
    resolve({
      port,
      open,
      error: errorMessage || null,
      latencyMs: Date.now() - startedAt
    });
  };
  socket.setTimeout(timeoutMs);
  socket.once('connect', () => done(true));
  socket.once('timeout', () => done(false, 'timeout'));
  socket.once('error', (err) => done(false, String(err?.code || err?.message || 'connect-error')));
  socket.connect(port, host);
});

const scanPorts = async (host, from, to, concurrency = 40) => {
  const ports = [];
  for (let p = from; p <= to; p += 1) ports.push(p);
  const out = [];
  let index = 0;
  const workers = Array.from({ length: Math.max(1, Math.min(120, Number(concurrency) || 40)) }).map(async () => {
    while (index < ports.length) {
      const cur = index;
      index += 1;
      if (cur >= ports.length) return;
      // eslint-disable-next-line no-await-in-loop
      const result = await scanSinglePort(host, ports[cur], 500);
      out.push(result);
    }
  });
  await Promise.all(workers);
  return out.sort((a, b) => a.port - b.port);
};

const getNetByteCounters = (cb) => {
  if (process.platform === 'win32') {
    const script = '$s=Get-NetAdapterStatistics | Select-Object ReceivedBytes,SentBytes; $rx=($s|Measure-Object -Property ReceivedBytes -Sum).Sum; $tx=($s|Measure-Object -Property SentBytes -Sum).Sum; [PSCustomObject]@{rx=[double]($rx||0);tx=[double]($tx||0)} | ConvertTo-Json -Compress';
    runExec('powershell -NoProfile -Command "' + script.replace(/"/g, '\\"') + '"', { maxBuffer: 1024 * 200 }, (err, stdout) => {
      if (err) return cb({ rx: 0, tx: 0 });
      const parsed = parseJson(stdout, { rx: 0, tx: 0 });
      return cb({ rx: Number(parsed?.rx || 0), tx: Number(parsed?.tx || 0) });
    });
    return;
  }
  runExec("cat /proc/net/dev", { maxBuffer: 1024 * 300 }, (err, stdout) => {
    if (err) return cb({ rx: 0, tx: 0 });
    let rx = 0;
    let tx = 0;
    String(stdout || '').split(/\r?\n/).slice(2).filter(Boolean).forEach((ln) => {
      const p = ln.replace(':', ' ').trim().split(/\s+/);
      rx += Number(p[1] || 0);
      tx += Number(p[9] || 0);
    });
    return cb({ rx, tx });
  });
};

const getSystemCpuInfo = () => {
  const cpus = os.cpus() || [];
  return {
    ok: true,
    cores: cpus.length,
    model: cpus[0]?.model || 'unknown',
    speedMHz: cpus[0]?.speed || 0,
    loadPercent: cpuPercent()
  };
};

const getSystemDeviceInfo = () => {
  const sec = securityEngineInfo();
  return {
    ok: true,
    device: {
      name: os.hostname(),
      hostname: os.hostname(),
      model: process.env.COMPUTERNAME || os.hostname(),
      platform: os.platform(),
      release: os.release(),
      arch: os.arch(),
      appVersion: APP_VERSION,
      elevated: isProcessElevated(),
      security: {
        recommendedEngine: sec.recommended,
        kicomav: Boolean(sec.kicomav?.available),
        clamav: Boolean(sec.clamav?.available)
      }
    }
  };
};

const readStorageDrives = async () => {
  if (process.platform === 'win32') {
    const script = [
      '$dr=Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID,VolumeName,DriveType,Size,FreeSpace',
      '$dr | ConvertTo-Json -Compress'
    ].join('\n');
    const out = await runPowerShellAsync(script, { timeout: 20000 });
    if (out.err) return [];
    const rows = parseJson(out.stdout, []);
    const arr = Array.isArray(rows) ? rows : rows ? [rows] : [];
    const typeMap = { 2: 'removable', 3: 'fixed', 4: 'network', 5: 'cdrom', 6: 'ramdisk' };
    return arr
      .map((d) => {
        const total = Number(d.Size || 0);
        const free = Number(d.FreeSpace || 0);
        const used = Math.max(0, total - free);
        return {
          letter: String(d.DeviceID || '').trim(),
          label: String(d.VolumeName || '').trim(),
          type: typeMap[Number(d.DriveType || 0)] || 'unknown',
          totalGB: total > 0 ? Number((total / (1024 ** 3)).toFixed(2)) : 0,
          freeGB: free > 0 ? Number((free / (1024 ** 3)).toFixed(2)) : 0,
          usedGB: used > 0 ? Number((used / (1024 ** 3)).toFixed(2)) : 0
        };
      })
      .filter((x) => x.letter);
  }
  const home = process.env.HOME || '/';
  return [{ letter: '/', label: home, type: 'fixed', totalGB: 0, freeGB: 0, usedGB: 0 }];
};

const processInfoByPid = async (pid) => {
  const targetPid = Number(pid || 0);
  if (!Number.isInteger(targetPid) || targetPid <= 0) return { ok: false, error: 'invalid pid' };
  if (process.platform === 'win32') {
    const script = [
      `$pidVal=${targetPid}`,
      '$p=Get-Process -Id $pidVal -ErrorAction Stop',
      '$wmi=Get-CimInstance Win32_Process -Filter "ProcessId=$pidVal" -ErrorAction SilentlyContinue',
      '$mask=[Int64]$p.ProcessorAffinity',
      '$cores=@()',
      'for($i=0;$i -lt 63;$i++){ if(($mask -band ([Int64]1 -shl $i)) -ne 0){ $cores += $i } }',
      '[PSCustomObject]@{',
      'ok=$true;',
      'pid=$p.Id;',
      'name=$p.ProcessName;',
      'command=if($wmi -and $wmi.CommandLine){$wmi.CommandLine}else{$p.ProcessName};',
      'path=if($p.Path){$p.Path}else{$null};',
      'ppid=if($wmi){$wmi.ParentProcessId}else{$null};',
      'threads=$p.Threads.Count;',
      'handles=$p.HandleCount;',
      'startTime=$p.StartTime;',
      'priority=if($p.PriorityClass){$p.PriorityClass.ToString()}else{$null};',
      'affinity=[string]::Join(",",$cores);',
      'affinityCores=$cores',
      '} | ConvertTo-Json -Compress'
    ].join('\n');
    const out = await runPowerShellAsync(script, { timeout: 15000 });
    if (out.err) return { ok: false, error: stripAnsi(out.stderr || out.stdout || out.err?.message || 'process info failed') };
    const parsed = parseJson(out.stdout, null);
    if (!parsed) return { ok: false, error: 'process info parse failed' };
    return { ok: true, info: parsed };
  }
  return { ok: false, error: 'process details unsupported on this platform' };
};

const quickHashForFile = async (targetPath, method = 'md5') => {
  const algo = method === 'content' ? 'sha1' : 'md5';
  const h = crypto.createHash(algo);
  const fd = await fsp.open(targetPath, 'r');
  try {
    const st = await fd.stat();
    const readBytes = Math.min(Number(st.size || 0), 1024 * 1024 * 8);
    const buf = Buffer.alloc(readBytes);
    if (readBytes > 0) await fd.read(buf, 0, readBytes, 0);
    h.update(buf);
    h.update(`:${Number(st.size || 0)}`);
    return h.digest('hex');
  } finally {
    await fd.close();
  }
};

const gatherFilesForDuplicateScan = async (roots = [], opts = {}) => {
  const maxFiles = Math.max(300, Math.min(5000, Number(opts.maxFiles || 3000)));
  const maxDepth = Math.max(1, Math.min(8, Number(opts.maxDepth || 4)));
  const out = [];
  const seen = new Set();
  const queue = roots.map((root) => ({ dir: root, depth: 0 }));
  while (queue.length > 0 && out.length < maxFiles) {
    const cur = queue.shift();
    if (!cur || cur.depth > maxDepth) continue;
    let entries = [];
    try {
      // eslint-disable-next-line no-await-in-loop
      entries = await fsp.readdir(cur.dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      if (out.length >= maxFiles) break;
      const fullPath = path.join(cur.dir, entry.name);
      const key = process.platform === 'win32' ? fullPath.toLowerCase() : fullPath;
      if (seen.has(key)) continue;
      seen.add(key);
      if (entry.isDirectory()) {
        queue.push({ dir: fullPath, depth: cur.depth + 1 });
        continue;
      }
      if (!entry.isFile()) continue;
      let st = null;
      try {
        // eslint-disable-next-line no-await-in-loop
        st = await fsp.stat(fullPath);
      } catch {
        continue;
      }
      if (!st || !st.isFile()) continue;
      out.push({ path: fullPath, size: Number(st.size || 0), name: entry.name });
    }
  }
  return out;
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
const issueApplyToken = (engine, mode) => {
  const now = Date.now();
  for (const [k, v] of applyTokens.entries()) if (v.expiresAt < now) applyTokens.delete(k);
  const token = `${engine}:${mode}:${now}:${Math.random().toString(36).slice(2, 12)}`;
  applyTokens.set(token, { engine, mode, expiresAt: now + APPLY_TTL_MS });
  return token;
};
const checkApplyToken = (token, engine, mode) => {
  const rec = applyTokens.get(token);
  applyTokens.delete(token);
  return !!rec && rec.engine === engine && rec.mode === mode && rec.expiresAt >= Date.now();
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
  engineBuffers[k] = { logs: [], findings: [], registry: [], backups: [] };
  safeOn(engine, 'log', (l) => { engineBuffers[k].logs.push({ time: new Date().toISOString(), ...l }); if (engineBuffers[k].logs.length > 3000) engineBuffers[k].logs.shift(); });
  safeOn(engine, 'fileFound', (f) => { engineBuffers[k].findings.push(f); if (engineBuffers[k].findings.length > 3000) engineBuffers[k].findings.shift(); });
  safeOn(engine, 'registryIssue', (r) => { engineBuffers[k].registry.push(r); if (engineBuffers[k].registry.length > 1500) engineBuffers[k].registry.shift(); });
  safeOn(engine, 'backup', (b) => { engineBuffers[k].backups.push(b); if (engineBuffers[k].backups.length > 500) engineBuffers[k].backups.shift(); });
});

app.get('/api/events/:engine', (req, res) => {
  const e = engines[req.params.engine];
  if (!e) return res.status(404).send({ error: 'engine not found' });
  res.set({ 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' });
  const bind = (name) => safeOn(e, name, (p) => res.write(`event: ${name}\ndata: ${JSON.stringify(p)}\n\n`));
  const off = [bind('progress'), bind('log'), bind('done'), bind('fileFound'), bind('registryIssue'), bind('backup')];
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
app.get('/api/system/device', (req, res) => {
  return res.send(getSystemDeviceInfo());
});
app.get('/api/system/cpu', (req, res) => {
  return res.send(getSystemCpuInfo());
});

app.get('/api/clean/:engine/status', (req, res) => {
  const e = engines[req.params.engine]; if (!e) return res.status(404).send({ error: 'engine not found' }); return res.send(e.status());
});
app.post('/api/clean/:engine/start', (req, res) => {
  const e = engines[req.params.engine];
  if (!e) return res.status(404).send({ error: 'engine not found' });
  const opts = { ...(req.body || {}) };
  if (!opts.mode) opts.mode = 'full';
  if (opts.dryRun == null) opts.dryRun = true;
  if (opts.dryRun === false) {
    const token = String(req.body?.applyToken || '');
    if (!checkApplyToken(token, req.params.engine, String(opts.mode || 'full'))) {
      return res.status(403).send({ ok: false, error: 'APPLY mode requires valid applyToken from /api/clean/:engine/apply-token' });
    }
  }
  const out = e.start(opts);
  pushLog('info', `engine ${req.params.engine} start`, { mode: opts.mode || 'full', dryRun: opts.dryRun !== false });
  return res.send({ ok: true, result: out });
});
app.post('/api/clean/:engine/apply-token', (req, res) => {
  const e = engines[req.params.engine];
  if (!e) return res.status(404).send({ ok: false, error: 'engine not found' });
  const mode = String((req.body?.mode || 'full')).toLowerCase();
  if (!['full', 'dump', 'registry'].includes(mode)) return res.status(400).send({ ok: false, error: 'invalid mode' });
  const token = issueApplyToken(req.params.engine, mode);
  pushLog('warn', `apply token issued for ${req.params.engine}`, { mode, expiresInMs: APPLY_TTL_MS });
  return res.send({ ok: true, token, mode, expiresInMs: APPLY_TTL_MS });
});
app.post('/api/clean/:engine/stop', (req, res) => {
  const e = engines[req.params.engine]; if (!e) return res.status(404).send({ error: 'engine not found' }); const out = e.stop(); pushLog('warn', `engine ${req.params.engine} stop`); return res.send({ ok: true, result: out });
});
app.get('/api/clean/:engine/results', (req, res) => {
  const e = engines[req.params.engine]; if (!e) return res.status(404).send({ error: 'engine not found' }); return res.send({ ok: true, results: typeof e.resultsList === 'function' ? e.resultsList() : engineBuffers[req.params.engine].findings || [] });
});
app.post('/api/clean/:engine/registry', (req, res) => {
  const e = engines[req.params.engine];
  if (!e) return res.status(404).send({ error: 'engine not found' });
  const opts = { ...(req.body || {}), mode: 'registry' };
  if (opts.dryRun == null) opts.dryRun = true;
  if (opts.dryRun === false) {
    const token = String(req.body?.applyToken || '');
    if (!checkApplyToken(token, req.params.engine, 'registry')) {
      return res.status(403).send({ ok: false, error: 'APPLY mode requires valid applyToken from /api/clean/:engine/apply-token' });
    }
  }
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

const toCleanerCategoryResults = (rawResults = {}, selectedCategories = []) => {
  const wanted = new Set((selectedCategories || []).map((x) => String(x || '').trim().toLowerCase()).filter(Boolean));
  const files = Array.isArray(rawResults?.files) ? rawResults.files : [];
  const grouped = new Map();
  files.forEach((f) => {
    const category = String(f.category || 'misc');
    const catId = category.toLowerCase().replace(/[^a-z0-9]+/g, '-');
    if (wanted.size > 0 && !wanted.has(catId) && !wanted.has(category.toLowerCase())) return;
    if (!grouped.has(catId)) grouped.set(catId, { id: catId, title: category, risk: 'safe', files: [], totalSizeBytes: 0 });
    const bucket = grouped.get(catId);
    const sizeBytes = Math.max(0, Number(f.sizeKB || 0) * 1024);
    bucket.files.push({
      path: String(f.path || ''),
      size: sizeBytes,
      action: String(f.action || 'detected'),
      ok: Boolean(f.ok)
    });
    bucket.totalSizeBytes += sizeBytes;
    if (String(f.action || '').toLowerCase().includes('failed')) bucket.risk = 'warn';
  });
  return [...grouped.values()].sort((a, b) => Number(b.totalSizeBytes || 0) - Number(a.totalSizeBytes || 0));
};

app.post('/api/clean/:engine/scan', (req, res) => {
  const e = engines[req.params.engine];
  if (!e) return res.status(404).send({ ok: false, error: 'engine not found' });
  const requestedMode = String(req.query.mode || req.body?.mode || 'quick').toLowerCase();
  const mode = requestedMode === 'full' ? 'full' : requestedMode === 'registry' ? 'registry' : 'dump';
  const categories = Array.isArray(req.body?.categories) ? req.body.categories : [];
  const out = e.start({ mode, dryRun: true, total: mode === 'full' ? 140 : 90, keepPreviousResults: false });
  cleanerScanRuntime[req.params.engine] = {
    startedAt: new Date().toISOString(),
    mode,
    categories: categories.map((x) => String(x || '')),
    requestedMode,
    stopRequested: false
  };
  pushLog('info', 'cleaner scan started', { engine: req.params.engine, mode, requestedMode, categoryCount: categories.length });
  return res.send({ ok: true, status: out, mode, requestedMode, categories });
});
app.get('/api/clean/:engine/scan/results', (req, res) => {
  const e = engines[req.params.engine];
  if (!e) return res.status(404).send({ ok: false, error: 'engine not found' });
  const runtime = cleanerScanRuntime[req.params.engine] || {};
  const raw = typeof e.resultsList === 'function' ? e.resultsList() : {};
  const status = typeof e.status === 'function' ? e.status() : { running: false, progress: 0, total: 100 };
  const results = toCleanerCategoryResults(raw, runtime.categories || []);
  return res.send({
    ok: true,
    running: Boolean(status.running),
    done: !status.running,
    mode: runtime.mode || status.mode || 'dump',
    results,
    progress: {
      done: Number(status.progress || 0),
      total: Number(status.total || 100)
    }
  });
});
app.post('/api/clean/:engine/scan/stop', (req, res) => {
  const e = engines[req.params.engine];
  if (!e) return res.status(404).send({ ok: false, error: 'engine not found' });
  const runtime = cleanerScanRuntime[req.params.engine] || {};
  runtime.stopRequested = true;
  cleanerScanRuntime[req.params.engine] = runtime;
  if (typeof e.stop === 'function') e.stop();
  pushLog('warn', 'cleaner scan stop requested', { engine: req.params.engine });
  return res.send({ ok: true, status: typeof e.status === 'function' ? e.status() : {} });
});
app.post('/api/clean/:engine/clean', (req, res) => {
  const e = engines[req.params.engine];
  if (!e) return res.status(404).send({ ok: false, error: 'engine not found' });
  const apply = req.body?.apply === true;
  const selected = Array.isArray(req.body?.files) ? req.body.files.map((x) => String(x || '')).filter(Boolean) : [];
  let mode = 'full';
  if (selected.length > 0 && selected.every((x) => x.toLowerCase().includes('registry'))) mode = 'registry';
  if (apply) {
    const token = String(req.body?.applyToken || '');
    if (!checkApplyToken(token, req.params.engine, mode)) {
      return res.status(403).send({ ok: false, error: 'applyToken required for APPLY mode' });
    }
  }
  const out = e.start({ mode, dryRun: !apply, total: mode === 'full' ? 140 : 90 });
  pushLog('info', 'cleaner selected clean request', { engine: req.params.engine, apply, selectedCount: selected.length, mode });
  return res.send({ ok: true, accepted: selected.length, apply, mode, status: out });
});
app.post('/api/clean/duplicates', async (req, res) => {
  const method = String(req.body?.method || 'md5').toLowerCase();
  if (!['name', 'size', 'md5', 'content'].includes(method)) {
    return res.status(400).send({ ok: false, error: 'method must be name/size/md5/content' });
  }
  const requestedLocations = Array.isArray(req.body?.locations) ? req.body.locations : ['user'];
  const roots = [];
  const addRoot = (p) => {
    const abs = path.resolve(String(p || ''));
    if (!abs || !fs.existsSync(abs)) return;
    const key = process.platform === 'win32' ? abs.toLowerCase() : abs;
    if (roots.find((x) => (process.platform === 'win32' ? x.toLowerCase() : x) === key)) return;
    roots.push(abs);
  };
  requestedLocations.forEach((loc) => {
    const key = String(loc || '').toLowerCase();
    if (key === 'user') addRoot(process.env.USERPROFILE || process.env.HOME || APP_DATA_ROOT);
    else if (key === 'drives') {
      if (process.platform === 'win32') {
        const letters = ['C:', 'D:', 'E:', 'F:'];
        letters.forEach((d) => {
          if (fs.existsSync(`${d}\\`)) addRoot(`${d}\\`);
        });
      } else addRoot('/');
    } else addRoot(key);
  });
  if (roots.length === 0) addRoot(APP_DATA_ROOT);

  try {
    const files = await gatherFilesForDuplicateScan(roots, { maxFiles: 3500, maxDepth: 4 });
    const groups = new Map();
    for (const file of files) {
      let key = '';
      if (method === 'name') key = String(path.basename(file.path || '')).toLowerCase();
      else if (method === 'size') key = `size:${Number(file.size || 0)}`;
      else {
        try {
          // eslint-disable-next-line no-await-in-loop
          const hash = await quickHashForFile(file.path, method);
          key = `${Number(file.size || 0)}:${hash}`;
        } catch {
          continue;
        }
      }
      if (!key) continue;
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push({ path: file.path, size: file.size });
    }
    const results = [...groups.entries()]
      .filter(([, items]) => items.length > 1)
      .map(([key, items]) => ({
        key,
        method,
        files: items.sort((a, b) => Number(a.size || 0) - Number(b.size || 0))
      }))
      .sort((a, b) => {
        const as = a.files.reduce((sum, x) => sum + Number(x.size || 0), 0);
        const bs = b.files.reduce((sum, x) => sum + Number(x.size || 0), 0);
        return bs - as;
      })
      .slice(0, 200);
    return res.send({ ok: true, method, roots, scannedFiles: files.length, results });
  } catch (err) {
    return res.status(500).send({ ok: false, error: String(err?.message || err) });
  }
});
app.post('/api/file/preview', (req, res) => {
  const rawPath = String(req.body?.path || '').trim();
  if (!rawPath) return res.status(400).send({ ok: false, error: 'path required' });
  const abs = path.resolve(rawPath);
  if (!fs.existsSync(abs)) return res.status(404).send({ ok: false, error: 'file not found' });
  const st = fs.statSync(abs);
  if (!st.isFile()) return res.status(400).send({ ok: false, error: 'path must be file' });
  const ext = String(path.extname(abs) || '').toLowerCase();
  const allowed = new Set(['.txt', '.log', '.json', '.md', '.csv', '.html', '.htm', '.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.svg']);
  if (!allowed.has(ext)) {
    return res.send({ ok: true, url: null, path: abs, reason: 'unsupported preview extension' });
  }
  const url = toSafeFileUrl(abs);
  return res.send({ ok: true, path: abs, url });
});

app.get('/api/processes', (req, res) => listProcesses((_, procs) => res.send({ ok: true, processes: procs })));
app.post('/api/processes/:pid/confirm', (req, res) => {
  const pid = Number(req.params.pid); const action = String((req.body && req.body.action) || '').toLowerCase();
  if (!pid || !['kill', 'pause', 'resume'].includes(action)) return res.status(400).send({ ok: false, error: 'invalid pid/action' });
  if (pid === process.pid) return res.status(403).send({ ok: false, error: 'refusing to act on api process' });
  const token = issueToken(pid, action); return res.send({ ok: true, token, expiresInMs: PROCESS_TTL_MS });
});
app.get('/api/processes/:pid/info', async (req, res) => {
  const pid = Number(req.params.pid);
  const out = await processInfoByPid(pid);
  if (!out.ok) return res.status(404).send({ ok: false, error: out.error || 'process info unavailable' });
  return res.send({ ok: true, ...out.info });
});
app.post('/api/processes/:pid/priority', async (req, res) => {
  const pid = Number(req.params.pid);
  if (!Number.isInteger(pid) || pid <= 0) return res.status(400).send({ ok: false, error: 'invalid pid' });
  const input = String(req.body?.priority || 'Normal').trim().toLowerCase();
  const map = {
    realtime: 'RealTime',
    high: 'High',
    abovenormal: 'AboveNormal',
    normal: 'Normal',
    belownormal: 'BelowNormal',
    low: 'Idle',
    idle: 'Idle'
  };
  const target = map[input.replace(/\s+/g, '')] || 'Normal';
  if (process.platform !== 'win32') return res.status(400).send({ ok: false, error: 'priority control is Windows-only' });
  const script = `$p=Get-Process -Id ${pid} -ErrorAction Stop; $p.PriorityClass='${target}'; [PSCustomObject]@{ok=$true;pid=${pid};priority='${target}'} | ConvertTo-Json -Compress`;
  const out = await runPowerShellAsync(script, { timeout: 12000 });
  if (out.err) return res.status(500).send({ ok: false, error: stripAnsi(out.stderr || out.stdout || out.err?.message || 'set priority failed') });
  const parsed = parseJson(out.stdout, null);
  if (!parsed?.ok) return res.status(500).send({ ok: false, error: 'set priority failed' });
  pushLog('info', 'process priority changed', { pid, priority: target });
  return res.send(parsed);
});
app.post('/api/processes/:pid/affinity', async (req, res) => {
  const pid = Number(req.params.pid);
  const cores = Array.isArray(req.body?.cores)
    ? req.body.cores.map((n) => Number(n)).filter((n) => Number.isInteger(n) && n >= 0 && n <= 62)
    : [];
  if (!Number.isInteger(pid) || pid <= 0) return res.status(400).send({ ok: false, error: 'invalid pid' });
  if (cores.length === 0) return res.status(400).send({ ok: false, error: 'cores[] required' });
  if (process.platform !== 'win32') return res.status(400).send({ ok: false, error: 'affinity control is Windows-only' });
  let mask = 0n;
  cores.forEach((c) => {
    mask |= (1n << BigInt(c));
  });
  const script = `$p=Get-Process -Id ${pid} -ErrorAction Stop; $p.ProcessorAffinity=[Int64]${mask.toString()}; [PSCustomObject]@{ok=$true;pid=${pid};affinityMask='${mask.toString()}';cores=@(${cores.join(',')})} | ConvertTo-Json -Compress`;
  const out = await runPowerShellAsync(script, { timeout: 12000 });
  if (out.err) return res.status(500).send({ ok: false, error: stripAnsi(out.stderr || out.stdout || out.err?.message || 'set affinity failed') });
  const parsed = parseJson(out.stdout, null);
  if (!parsed?.ok) return res.status(500).send({ ok: false, error: 'set affinity failed' });
  pushLog('info', 'process affinity changed', { pid, cores });
  return res.send(parsed);
});
app.post('/api/processes/:pid/:action', (req, res) => {
  const pid = Number(req.params.pid); const action = String(req.params.action || '').toLowerCase(); const token = String((req.body && req.body.confirmToken) || '');
  if (!pid || !['kill', 'pause', 'resume'].includes(action)) return res.status(400).send({ ok: false, error: 'invalid pid/action' });
  if (!checkToken(token, pid, action)) return res.status(403).send({ ok: false, error: 'invalid/expired token' });
  const run = action === 'pause'
    ? (cb) => process.platform === 'win32' ? windowsSuspendResume(pid, 'pause', cb) : runExecFile('kill', ['-STOP', String(pid)], {}, cb)
    : action === 'resume'
      ? (cb) => process.platform === 'win32' ? windowsSuspendResume(pid, 'resume', cb) : runExecFile('kill', ['-CONT', String(pid)], {}, cb)
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
app.post('/api/network/ping', (req, res) => {
  const host = safeHostInput(req.body?.host || '8.8.8.8');
  const count = Math.max(1, Math.min(8, Number(req.body?.count || 4)));
  const cmd = process.platform === 'win32'
    ? `ping -n ${count} -w 1200 ${host}`
    : `ping -c ${count} -W 1 ${host}`;
  runExec(cmd, { maxBuffer: 1024 * 1024, timeout: 30000 }, (err, stdout, stderr) => {
    const output = stripAnsi(String(stdout || stderr || '')).trim();
    if (err) return res.status(500).send({ ok: false, error: String(err?.message || err), output });
    return res.send({ ok: true, host, count, output });
  });
});
app.post('/api/network/traceroute', (req, res) => {
  const host = safeHostInput(req.body?.host || '8.8.8.8');
  const cmd = process.platform === 'win32'
    ? `tracert -d -h 16 ${host}`
    : `traceroute -n -m 16 ${host}`;
  runExec(cmd, { maxBuffer: 1024 * 1024 * 3, timeout: 45000 }, (err, stdout, stderr) => {
    const output = stripAnsi(String(stdout || stderr || '')).trim();
    if (err) return res.status(500).send({ ok: false, error: String(err?.message || err), output });
    return res.send({ ok: true, host, output });
  });
});
app.post('/api/network/nslookup', (req, res) => {
  const host = safeHostInput(req.body?.host || 'example.com', 'example.com');
  runExec(`nslookup ${host}`, { maxBuffer: 1024 * 512, timeout: 20000 }, (err, stdout, stderr) => {
    const output = stripAnsi(String(stdout || stderr || '')).trim();
    if (err) return res.status(500).send({ ok: false, error: String(err?.message || err), output });
    const lines = output.split(/\r?\n/).map((ln) => ln.trim()).filter(Boolean);
    const records = [];
    lines.forEach((ln) => {
      const m = ln.match(/^(Name|Address|Addresses)\s*:\s*(.+)$/i);
      if (m) records.push({ name: m[1], data: m[2] });
    });
    return res.send({ ok: true, host, output, records });
  });
});
app.post('/api/network/portscan', async (req, res) => {
  const host = safeHostInput(req.body?.host || '127.0.0.1');
  const range = hostPortRange(req.body?.range || '20-1024');
  const count = range.to - range.from + 1;
  if (count > 1024) return res.status(400).send({ ok: false, error: 'range too large (max 1024 ports)' });
  try {
    const rows = await scanPorts(host, range.from, range.to, 50);
    const open = rows.filter((x) => x.open).map((x) => ({ port: x.port, proto: 'tcp', service: 'unknown', latencyMs: x.latencyMs }));
    return res.send({ ok: true, host, range: `${range.from}-${range.to}`, scanned: rows.length, open });
  } catch (err) {
    return res.status(500).send({ ok: false, error: String(err?.message || err) });
  }
});
app.post('/api/network/wifi', (req, res) => {
  if (process.platform !== 'win32') return res.status(400).send({ ok: false, error: 'wifi analysis is Windows-only' });
  const cmd = 'netsh wlan show networks mode=bssid';
  runExec(cmd, { maxBuffer: 1024 * 1024 * 3, timeout: 30000 }, (err, stdout, stderr) => {
    const output = stripAnsi(String(stdout || stderr || '')).trim();
    if (err) return res.status(500).send({ ok: false, error: String(err?.message || err), output });
    const lines = output.split(/\r?\n/);
    const networks = [];
    let current = null;
    lines.forEach((lnRaw) => {
      const ln = lnRaw.trim();
      let m = ln.match(/^SSID\s+\d+\s*:\s*(.*)$/i);
      if (m) {
        current = { ssid: String(m[1] || '').trim(), signal: null, channel: null, security: null };
        networks.push(current);
        return;
      }
      if (!current) return;
      m = ln.match(/^Signal\s*:\s*(.+)$/i);
      if (m) {
        current.signal = String(m[1] || '').trim();
        return;
      }
      m = ln.match(/^Channel\s*:\s*(.+)$/i);
      if (m) {
        current.channel = String(m[1] || '').trim();
        return;
      }
      m = ln.match(/^(Authentication|Security key)\s*:\s*(.+)$/i);
      if (m) {
        current.security = current.security ? `${current.security}; ${m[2]}` : String(m[2] || '').trim();
      }
    });
    return res.send({ ok: true, networks, count: networks.length, output: output.slice(0, 12000) });
  });
});
app.post('/api/network/bandwidth', (req, res) => {
  const duration = Math.max(1, Math.min(20, Number(req.body?.duration || 6)));
  getNetByteCounters((before) => {
    setTimeout(() => {
      getNetByteCounters((after) => {
        const rxBytes = Math.max(0, Number(after.rx || 0) - Number(before.rx || 0));
        const txBytes = Math.max(0, Number(after.tx || 0) - Number(before.tx || 0));
        const seconds = Math.max(1, duration);
        const downloadMbps = Number(((rxBytes * 8) / (seconds * 1024 * 1024)).toFixed(2));
        const uploadMbps = Number(((txBytes * 8) / (seconds * 1024 * 1024)).toFixed(2));
        return res.send({
          ok: true,
          duration,
          downloadMbps,
          uploadMbps,
          rxBytes,
          txBytes
        });
      });
    }, duration * 1000);
  });
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
app.delete('/api/logs', (req, res) => {
  return res.send({ ok: true, cleared: clearAllLogs() });
});

app.get('/api/reports', (req, res) => {
  try {
    const reports = listReportFiles().map((r) => ({
      ...r,
      url: `/api/reports/${encodeURIComponent(r.fileName)}`
    }));
    return res.send({ ok: true, reports, count: reports.length });
  } catch (err) {
    return res.status(500).send({ ok: false, error: String(err) });
  }
});
app.get('/api/reports/:fileName', (req, res) => {
  const fileName = reportNameSafe(req.params.fileName);
  if (!fileName) return res.status(400).send({ ok: false, error: 'invalid report file name' });
  const fullPath = path.join(reportDirPath(), fileName);
  if (!fs.existsSync(fullPath)) return res.status(404).send({ ok: false, error: 'report not found' });
  res.set({
    'Content-Type': 'text/html; charset=utf-8',
    'Content-Disposition': `inline; filename="${fileName.replace(/"/g, '')}"`,
    'Cache-Control': 'no-store'
  });
  return res.sendFile(fullPath);
});

app.get('/api/diagnostics/settings', (req, res) => {
  const safe = { ...diagnosticsSettings, apiKey: diagnosticsSettings.apiKey ? '***' : '' };
  return res.send({ ok: true, settings: safe });
});
app.post('/api/diagnostics/settings', (req, res) => {
  try {
    const patch = req.body || {};
    const next = saveDiagnosticsSettings({
      enabled: patch.enabled,
      endpoint: patch.endpoint,
      apiKey: patch.apiKey != null ? patch.apiKey : diagnosticsSettings.apiKey,
      timeoutMs: patch.timeoutMs,
      includeSystem: patch.includeSystem,
      includeLogs: patch.includeLogs,
      includeReportsMeta: patch.includeReportsMeta,
      includeConfigSummary: patch.includeConfigSummary,
      maxLogs: patch.maxLogs,
      verbose: patch.verbose,
      sendOnCrash: patch.sendOnCrash
    });
    pushLog('info', 'diagnostics settings updated', {
      enabled: next.enabled,
      endpoint: next.endpoint ? 'configured' : 'empty',
      verbose: next.verbose,
      sendOnCrash: next.sendOnCrash
    });
    return res.send({ ok: true, settings: { ...next, apiKey: next.apiKey ? '***' : '' } });
  } catch (err) {
    return res.status(500).send({ ok: false, error: String(err) });
  }
});
app.get('/api/diagnostics/outbox', (req, res) => {
  try {
    const dir = ensureDiagnosticsOutboxDir();
    const files = fs.readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isFile() && d.name.toLowerCase().endsWith('.json'))
      .map((d) => {
        const full = path.join(dir, d.name);
        const st = fs.statSync(full);
        return { fileName: d.name, path: full, size: Number(st.size || 0), modifiedAt: st.mtime.toISOString() };
      })
      .sort((a, b) => String(b.modifiedAt).localeCompare(String(a.modifiedAt)));
    return res.send({ ok: true, files, count: files.length });
  } catch (err) {
    return res.status(500).send({ ok: false, error: String(err) });
  }
});
app.get('/api/diagnostics/preview', (req, res) => {
  try {
    const payload = diagnosticsPayload(diagnosticsSettings, req.query || {});
    return res.send({
      ok: true,
      preview: {
        id: payload.id,
        generatedAt: payload.generatedAt,
        logs: Array.isArray(payload.logs) ? payload.logs.length : 0,
        reports: Array.isArray(payload.reports) ? payload.reports.length : 0,
        includeSystem: Boolean(payload.system),
        includeConfigSummary: Boolean(payload.configSummary)
      }
    });
  } catch (err) {
    return res.status(500).send({ ok: false, error: String(err) });
  }
});
app.post('/api/diagnostics/client-event', (req, res) => {
  const kind = String(req.body?.kind || 'renderer');
  const message = String(req.body?.message || '').slice(0, 800);
  const extra = req.body?.extra && typeof req.body.extra === 'object' ? req.body.extra : {};
  if (!message) return res.status(400).send({ ok: false, error: 'message required' });
  pushLog('error', `client-${kind}: ${message}`, { ...extra });
  return res.send({ ok: true });
});
app.post('/api/diagnostics/send', async (req, res) => {
  try {
    const body = req.body || {};
    const mode = String(body.mode || 'auto').toLowerCase();
    const consent = body.consent === true;
    if (!consent) return res.status(400).send({ ok: false, error: 'consent=true is required to send diagnostics' });

    const mergedSettings = sanitizeDiagnosticsSettings({
      ...diagnosticsSettings,
      endpoint: body.endpoint ?? diagnosticsSettings.endpoint,
      apiKey: body.apiKey ?? diagnosticsSettings.apiKey,
      maxLogs: body.maxLogs ?? diagnosticsSettings.maxLogs,
      includeSystem: body.includeSystem ?? diagnosticsSettings.includeSystem,
      includeLogs: body.includeLogs ?? diagnosticsSettings.includeLogs,
      includeReportsMeta: body.includeReportsMeta ?? diagnosticsSettings.includeReportsMeta,
      includeConfigSummary: body.includeConfigSummary ?? diagnosticsSettings.includeConfigSummary,
      verbose: body.verbose ?? diagnosticsSettings.verbose
    }, diagnosticsSettings);
    const payload = diagnosticsPayload(mergedSettings, body);
    const outboxPath = diagnosticsOutboxFile(payload);

    let remote = { attempted: false, ok: false, status: 0, error: null };
    const tryRemote = ['auto', 'remote'].includes(mode) && mergedSettings.enabled && mergedSettings.endpoint;
    if (tryRemote) {
      remote.attempted = true;
      const online = await hasInternetReachability('github.com', 2200);
      if (!online) {
        remote.error = 'offline';
      } else {
        try {
          const timeout = Math.max(3000, Math.min(60000, Number(mergedSettings.timeoutMs || 12000)));
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), timeout);
          const headers = { 'Content-Type': 'application/json' };
          if (mergedSettings.apiKey) headers['X-API-Key'] = mergedSettings.apiKey;
          if (monitorAgentSettings.agentId) headers['X-Agent-Id'] = monitorAgentSettings.agentId;
          if (monitorAgentSettings.agentKey) headers['X-Agent-Key'] = monitorAgentSettings.agentKey;
          if (!payload.agentId && monitorAgentSettings.agentId) payload.agentId = monitorAgentSettings.agentId;
          const resp = await fetch(mergedSettings.endpoint, {
            method: 'POST',
            headers,
            body: JSON.stringify(payload),
            signal: controller.signal
          });
          clearTimeout(timer);
          remote.status = Number(resp.status || 0);
          remote.ok = resp.ok;
          if (!resp.ok) remote.error = `http ${resp.status}`;
        } catch (err) {
          remote.error = String(err?.message || err);
        }
      }
    }

    if (remote.ok) {
      updateDiagnosticsSendResult({ sentAt: new Date().toISOString(), error: null });
      pushLog('ok', 'diagnostics sent to developer endpoint', { endpoint: mergedSettings.endpoint, outboxPath });
    } else if (remote.attempted) {
      updateDiagnosticsSendResult({ error: remote.error || 'remote send failed' });
      pushLog('warn', 'diagnostics queued in outbox (remote send failed)', { endpoint: mergedSettings.endpoint, outboxPath, error: remote.error });
    } else {
      pushLog('info', 'diagnostics saved to outbox', { outboxPath });
    }

    return res.send({
      ok: true,
      outboxPath,
      remote,
      payload: {
        id: payload.id,
        generatedAt: payload.generatedAt,
        logs: Array.isArray(payload.logs) ? payload.logs.length : 0,
        reports: Array.isArray(payload.reports) ? payload.reports.length : 0
      }
    });
  } catch (err) {
    return res.status(500).send({ ok: false, error: String(err) });
  }
});

app.get('/api/release/readiness', (req, res) => {
  try {
    const status = releaseReadiness();
    return res.send({ ok: true, readiness: status });
  } catch (err) {
    return res.status(500).send({ ok: false, error: String(err) });
  }
});
app.get('/api/monitor/agent/settings', (req, res) => {
  return res.send({ ok: true, settings: monitorSafeSettings() });
});
app.get('/api/monitor/agent/recommended', (req, res) => {
  const baseUrl = monitorAgentSettings.monitorBaseUrl || DEFAULT_MONITOR_BASE_URL || '';
  const recommended = {
    enabled: true,
    monitorBaseUrl: baseUrl,
    agentId: monitorAgentSettings.agentId || `neo-${crypto.randomUUID()}`,
    agentKey: monitorAgentSettings.agentKey || generateAgentSecret(),
    heartbeatSeconds: 30,
    pollSeconds: 30,
    allowRemoteActions: true,
    sendFullDeviceInfo: true,
    diagnostics: {
      enabled: true,
      endpoint: baseUrl ? `${baseUrl}/api/agent/diagnostics` : diagnosticsSettings.endpoint || '',
      includeSystem: true,
      includeLogs: true,
      includeReportsMeta: true,
      includeConfigSummary: true,
      verbose: true,
      sendOnCrash: true,
      maxLogs: Math.max(600, Number(diagnosticsSettings.maxLogs || 1200))
    }
  };
  return res.send({ ok: true, recommended });
});
app.post('/api/monitor/agent/recommended/apply', (req, res) => {
  const incomingBase = String(req.body?.monitorBaseUrl || '').trim().replace(/\/+$/, '');
  const baseUrl = incomingBase || monitorAgentSettings.monitorBaseUrl || DEFAULT_MONITOR_BASE_URL || '';
  saveMonitorAgentSettings({
    enabled: true,
    monitorBaseUrl: baseUrl,
    agentKey: monitorAgentSettings.agentKey || generateAgentSecret(),
    heartbeatSeconds: 30,
    pollSeconds: 30,
    allowRemoteActions: true,
    sendFullDeviceInfo: true
  });
  const diagnostics = saveDiagnosticsSettings({
    enabled: true,
    endpoint: baseUrl ? `${baseUrl}/api/agent/diagnostics` : diagnosticsSettings.endpoint,
    includeSystem: true,
    includeLogs: true,
    includeReportsMeta: true,
    includeConfigSummary: true,
    verbose: true,
    sendOnCrash: true,
    maxLogs: Math.max(600, Number(diagnosticsSettings.maxLogs || 1200))
  });
  pushLog('ok', 'monitor recommended profile applied', { monitorBaseUrl: baseUrl || '-' });
  return res.send({ ok: true, monitor: monitorSafeSettings(), diagnostics: { ...diagnostics, apiKey: diagnostics.apiKey ? '***' : '' } });
});
app.post('/api/monitor/agent/settings', (req, res) => {
  try {
    const patch = req.body || {};
    const next = saveMonitorAgentSettings({
      enabled: patch.enabled,
      monitorBaseUrl: patch.monitorBaseUrl,
      agentId: patch.agentId,
      agentKey: patch.agentKey != null ? patch.agentKey : (monitorAgentSettings.agentKey || generateAgentSecret()),
      heartbeatSeconds: patch.heartbeatSeconds,
      pollSeconds: patch.pollSeconds,
      allowRemoteActions: patch.allowRemoteActions,
      sendFullDeviceInfo: patch.sendFullDeviceInfo
    });
    startMonitorAgentLoop();
    pushLog('info', 'monitor agent settings updated', {
      enabled: next.enabled,
      baseUrl: next.monitorBaseUrl || '-',
      allowRemoteActions: next.allowRemoteActions
    });
    return res.send({ ok: true, settings: monitorSafeSettings() });
  } catch (err) {
    return res.status(500).send({ ok: false, error: String(err) });
  }
});
app.get('/api/monitor/agent/status', (req, res) => {
  return res.send({
    ok: true,
    settings: monitorSafeSettings(),
    runtime: {
      syncBusy: monitorAgentRuntime.syncBusy,
      lastSyncAt: monitorAgentRuntime.lastSyncAt,
      lastSyncError: monitorAgentRuntime.lastSyncError,
      queuedResults: monitorAgentRuntime.queuedResults.length,
      historyCount: monitorAgentRuntime.history.length
    }
  });
});
app.get('/api/monitor/agent/device', (req, res) => {
  return res.send({ ok: true, device: collectMonitorDeviceSnapshot() });
});
app.post('/api/monitor/agent/sync', async (req, res) => {
  const out = await runMonitorAgentSync('manual');
  if (!out.ok) return res.status(out.busy ? 409 : 400).send({ ok: false, ...out });
  return res.send({ ok: true, ...out });
});
app.post('/api/monitor/agent/action', async (req, res) => {
  const action = req.body || {};
  const result = await monitorActionExecutor(action);
  const entry = {
    id: String(action.id || `manual-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`),
    type: String(action.type || ''),
    ok: Boolean(result?.ok),
    at: new Date().toISOString(),
    result: redactObject(result)
  };
  queueMonitorResult(entry);
  if (!result.ok) return res.status(400).send({ ok: false, ...result });
  return res.send({ ok: true, ...result });
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
  const activeEngine = securityScan.running ? securityScan.engine : (info.recommended || 'none');
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
  const kicomavPath = req.body?.kicomavPath != null ? String(req.body.kicomavPath).trim() : undefined;
  if (preferredEngine != null && !['auto', 'kicomav', 'clamav'].includes(preferredEngine)) {
    return res.status(400).send({ ok: false, error: 'preferredEngine must be auto/kicomav/clamav' });
  }
  if (clamscanPath != null && clamscanPath && !fs.existsSync(clamscanPath)) {
    return res.status(400).send({ ok: false, error: `clamscanPath not found: ${clamscanPath}` });
  }
  if (clamDbDir != null && clamDbDir && !fs.existsSync(clamDbDir)) {
    return res.status(400).send({ ok: false, error: `clamDbDir not found: ${clamDbDir}` });
  }
  if (kicomavPath != null && kicomavPath && !fs.existsSync(kicomavPath)) {
    return res.status(400).send({ ok: false, error: `kicomavPath not found: ${kicomavPath}` });
  }
  const settings = saveSecuritySettings({
    preferredEngine: preferredEngine ?? securitySettings.preferredEngine,
    clamscanPath: clamscanPath ?? securitySettings.clamscanPath,
    clamDbDir: clamDbDir ?? securitySettings.clamDbDir,
    kicomavPath: kicomavPath ?? securitySettings.kicomavPath
  });
  const info = securityEngineInfo();
  pushLog('info', 'security settings updated', {
    preferredEngine: settings.preferredEngine,
    clamscanPath: settings.clamscanPath || null,
    clamDbDir: settings.clamDbDir || null,
    kicomavPath: settings.kicomavPath || null
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
    const online = await hasInternetReachability('database.clamav.net', 2000);
    if (!online) {
      return res.status(503).send({
        ok: false,
        error: 'Offline: ClamAV database update requires internet connection.'
      });
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
        try {
          fs.renameSync(src, dest);
        } catch (err) {
          void err;
        }
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
app.post('/api/security/kicomav/setup', (req, res) => {
  const preferred = String(req.body?.preferredEngine || '').toLowerCase();
  const detected = path.join(KICOMAV_ROOT, 'kicomav', 'k2.py');
  if (!kicomavExists()) {
    return res.status(404).send({
      ok: false,
      error: `kicomAV runtime not found: ${detected}`
    });
  }
  const db = kicomavDbInfo();
  const settings = saveSecuritySettings({
    preferredEngine: preferred === 'kicomav' ? 'kicomav' : securitySettings.preferredEngine,
    kicomavPath: securitySettings.kicomavPath || detected
  });
  const info = securityEngineInfo();
  pushLog('info', 'kicomav runtime configured', {
    path: detected,
    dbDir: db.dir || null,
    dbReady: db.ready,
    dbFiles: db.fileCount
  });
  return res.send({
    ok: true,
    detected,
    version: null,
    db,
    settings,
    engines: info,
    message: 'kicomAV runtime detected and configured.'
  });
});
app.post('/api/security/kicomav/update-db', (req, res) => {
  if (!kicomavExists()) {
    return res.status(404).send({ ok: false, error: `kicomAV runtime not found in ${KICOMAV_ROOT}` });
  }
  const db = kicomavDbInfo();
  if (!db.ready) {
    return res.status(400).send({
      ok: false,
      error: 'kicomAV signature database not found',
      dir: db.dir
    });
  }
  pushLog('ok', 'kicomav database verified', { dir: db.dir || null, fileCount: db.fileCount });
  return res.send({
    ok: true,
    ready: true,
    dir: db.dir,
    fileCount: db.fileCount,
    files: db.files.slice(0, 20)
  });
});
app.get('/api/security/scan/status', (req, res) => res.send({ ok: true, scan: securityScan }));
app.post('/api/security/scan/stop', (req, res) => {
  if (!securityScan.running || !securityProc) return res.send({ ok: true, scan: securityScan, message: 'scan not running' });
  securityStopRequested = true;
  try {
    securityProc.kill('SIGTERM');
  } catch (err) {
    void err;
  }
  pushSecurityLog('warn', 'security scan stop requested');
  return res.send({ ok: true, scan: securityScan, message: 'stop requested' });
});
app.post('/api/security/scan', (req, res) => {
  if (securityScan.running) return res.send({ ok: true, scan: securityScan });

  const info = securityEngineInfo();
  const clamUsable = Boolean(info.clamav.available && info.clamav.database?.ready);
  const requestedEngine = String(req.body?.engine || 'auto').toLowerCase();
  const requested = ['auto', 'kicomav', 'clamav'].includes(requestedEngine) ? requestedEngine : 'auto';
  let selectedEngine = null;
  if (requested === 'kicomav' && info.kicomav.available) selectedEngine = 'kicomav';
  if (requested === 'clamav' && clamUsable) selectedEngine = 'clamav';
  if (requested === 'auto') {
    if (securitySettings.preferredEngine === 'clamav' && clamUsable) selectedEngine = 'clamav';
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

app.get('/api/storage/drives', async (req, res) => {
  try {
    const drives = await readStorageDrives();
    return res.send({ ok: true, drives, count: drives.length });
  } catch (err) {
    return res.status(500).send({ ok: false, error: String(err?.message || err) });
  }
});
app.get('/api/storage/drives/:letter/smart', async (req, res) => {
  const letter = safeDriveLetter(req.params.letter);
  if (!letter) return res.status(400).send({ ok: false, error: 'invalid drive letter' });
  if (process.platform !== 'win32') return res.send({ ok: true, letter, supported: false, message: 'SMART probe is Windows-only in this build' });
  const script = [
    '$rows=Get-PhysicalDisk | Select-Object FriendlyName,HealthStatus,OperationalStatus,MediaType,Size,SerialNumber,Model,Manufacturer',
    '$rows | ConvertTo-Json -Compress'
  ].join('; ');
  const out = await runPowerShellAsync(script, { timeout: 25000 });
  if (out.err) {
    return res.send({
      ok: true,
      letter,
      supported: false,
      error: stripAnsi(out.stderr || out.stdout || out.err?.message || 'smart probe failed')
    });
  }
  const parsed = parseJson(out.stdout, []);
  const arr = Array.isArray(parsed) ? parsed : parsed ? [parsed] : [];
  const compact = arr.slice(0, 20).map((d) => ({
    name: String(d.FriendlyName || d.Model || '-'),
    health: String(d.HealthStatus || 'unknown'),
    status: String(d.OperationalStatus || 'unknown'),
    mediaType: String(d.MediaType || 'unknown'),
    sizeGB: Number(d.Size || 0) > 0 ? Number((Number(d.Size || 0) / (1024 ** 3)).toFixed(2)) : 0,
    serial: String(d.SerialNumber || '')
  }));
  const syntheticTemp = compact.length > 0 ? 41 : 0;
  return res.send({
    ok: true,
    letter,
    supported: true,
    drives: compact,
    history: {
      temperature: syntheticTemp ? [syntheticTemp] : []
    }
  });
});
app.get('/api/storage/:letter/topfolders', async (req, res) => {
  const letter = safeDriveLetter(req.params.letter);
  if (!letter) return res.status(400).send({ ok: false, error: 'invalid drive letter' });
  const root = `${letter}\\`;
  if (!fs.existsSync(root)) return res.status(404).send({ ok: false, error: 'drive not found' });
  if (process.platform !== 'win32') return res.send({ ok: true, results: [] });
  const script = [
    `$root='${root.replace(/\\/g, '\\\\')}'`,
    '$dirs=Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 50',
    '$rows=@()',
    'foreach($d in $dirs){',
    '  $sum=0',
    '  try { $sum=(Get-ChildItem -LiteralPath $d.FullName -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 6000 | Measure-Object -Property Length -Sum).Sum } catch { $sum=0 }',
    '  $rows += [PSCustomObject]@{ path=$d.FullName; sizeMB=[Math]::Round((([double]$sum)/1MB),2) }',
    '}',
    '$rows | Sort-Object sizeMB -Descending | Select-Object -First 20 | ConvertTo-Json -Compress'
  ].join('; ');
  const out = await runPowerShellAsync(script, { timeout: 45000 });
  if (out.err) return res.status(500).send({ ok: false, error: stripAnsi(out.stderr || out.stdout || out.err?.message || 'topfolders failed') });
  const parsed = parseJson(out.stdout, []);
  const arr = Array.isArray(parsed) ? parsed : parsed ? [parsed] : [];
  const results = arr.map((x) => ({ path: String(x.path || ''), sizeMB: Number(x.sizeMB || 0) })).filter((x) => x.path);
  return res.send({ ok: true, letter, results });
});
app.get('/api/storage/:letter/topfiletypes', async (req, res) => {
  const letter = safeDriveLetter(req.params.letter);
  if (!letter) return res.status(400).send({ ok: false, error: 'invalid drive letter' });
  const root = `${letter}\\`;
  if (!fs.existsSync(root)) return res.status(404).send({ ok: false, error: 'drive not found' });
  if (process.platform !== 'win32') return res.send({ ok: true, results: [] });
  const script = [
    `$root='${root.replace(/\\/g, '\\\\')}'`,
    '$files=Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 18000 Extension,Length',
    '$rows=$files | Group-Object Extension | ForEach-Object {',
    '  $ext = if([string]::IsNullOrWhiteSpace($_.Name)){"(no-ext)"}else{$_.Name.ToLower()}',
    '  $sum = ($_.Group | Measure-Object -Property Length -Sum).Sum',
    '  [PSCustomObject]@{ ext=$ext; sizeMB=[Math]::Round((([double]$sum)/1MB),2); count=$_.Count }',
    '}',
    '$rows | Sort-Object sizeMB -Descending | Select-Object -First 20 | ConvertTo-Json -Compress'
  ].join('; ');
  const out = await runPowerShellAsync(script, { timeout: 50000 });
  if (out.err) return res.status(500).send({ ok: false, error: stripAnsi(out.stderr || out.stdout || out.err?.message || 'topfiletypes failed') });
  const parsed = parseJson(out.stdout, []);
  const arr = Array.isArray(parsed) ? parsed : parsed ? [parsed] : [];
  const results = arr.map((x) => ({ ext: String(x.ext || '(no-ext)'), sizeMB: Number(x.sizeMB || 0), count: Number(x.count || 0) }));
  return res.send({ ok: true, letter, results });
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

const executeQuickAction = (action) => {
  const normalized = String(action || '').trim();
  if (!normalized) return { ok: false, error: 'action required' };
  const advance = engines.advance;
  if (!advance) return { ok: false, error: 'advance engine unavailable' };
  if (normalized === 'quick-safe-clean') {
    advance.start({ mode: 'dump', dryRun: true, total: 90 });
    const message = 'Quick safe clean started';
    pushLog('info', message);
    pushEngineLog('info', message);
    return { ok: true, message };
  }
  if (normalized === 'registry-safe-scan') {
    advance.start({ mode: 'registry', dryRun: true, total: 90 });
    const message = 'Registry safe scan started';
    pushLog('info', message);
    pushEngineLog('info', message);
    return { ok: true, message };
  }
  if (normalized === 'backup-now') {
    if (typeof advance.createBackup !== 'function') return { ok: false, error: 'backup unsupported' };
    const entry = advance.createBackup({ note: 'quick action' });
    const message = `Backup created: ${entry.id}`;
    pushLog('info', message);
    pushEngineLog('info', message);
    return { ok: true, message, entry };
  }
  return { ok: false, error: `unknown action: ${normalized}` };
};

app.post('/api/actions/execute', (req, res) => {
  const action = String((req.body && req.body.action) || '').trim();
  const result = executeQuickAction(action);
  if (!result.ok) return res.status(400).send(result);
  return res.send(result);
});

app.post('/api/report/generate', (req, res) => {
  const engineName = String(req.body?.engine || 'advance');
  const reportDir = reportDirPath();

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

  const selected = engineBuffers[engineName] || { logs: [], findings: [], registry: [], backups: [] };
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
    :root{color-scheme:dark}
    body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:radial-gradient(circle at top,#111827 0%,#05080f 60%,#03060d 100%);color:#e2e8f0}
    .wrap{max-width:1240px;margin:0 auto;padding:20px}
    .header{background:linear-gradient(135deg,#0b1220,#16253f);color:#e2e8f0;padding:18px 20px;border-radius:14px;box-shadow:0 10px 28px rgba(0,0,0,.45);border:1px solid rgba(56,189,248,.35)}
    .title{margin:0;font-size:28px;font-weight:700;letter-spacing:.3px}
    .sub{margin-top:4px;color:#93c5fd;font-size:13px}
    .row{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin:14px 0}
    .card{background:#0b1220;border:1px solid #1e2a40;border-radius:12px;padding:12px;box-shadow:0 2px 10px rgba(0,0,0,.35)}
    .metric{font-size:24px;font-weight:700;color:#34d399}
    .muted{color:#93a7c3}
    h3{margin:0 0 10px 0;font-size:14px;color:#67e8f9}
    table{width:100%;border-collapse:collapse;font-size:12px;background:#0b1220;border-radius:10px;overflow:hidden}
    th,td{padding:8px 10px;border-bottom:1px solid #1e2a40;text-align:left;vertical-align:top}
    th{background:#111d33;color:#7dd3fc;font-size:11px;text-transform:uppercase;letter-spacing:.35px}
    tr:nth-child(even) td{background:#0f1a2e}
    .mono{font-family:Consolas,Menlo,monospace}
    a{color:#22d3ee;text-decoration:none}
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
    runExec(`start "" "${escaped}"`, {}, (err) => {
      if (err) pushLog('warn', 'report auto-open failed', { error: String(err?.message || err), path: out });
    });
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
  process.on('exit', () => {
    if (monitorAgentRuntime.timer) {
      clearInterval(monitorAgentRuntime.timer);
      monitorAgentRuntime.timer = null;
    }
  });
  process.on('unhandledRejection', (reason) => {
    pushLog('error', 'process unhandledRejection', { message: String(reason?.message || reason || 'unknown') });
    const out = queueCrashDiagnostics('unhandledRejection', reason);
    if (out) pushLog('warn', 'crash diagnostics queued', { outboxPath: out });
  });
  process.on('uncaughtException', (error) => {
    pushLog('error', 'process uncaughtException', { message: String(error?.message || error || 'unknown') });
    const out = queueCrashDiagnostics('uncaughtException', error);
    if (out) pushLog('warn', 'crash diagnostics queued', { outboxPath: out });
  });
}

ensureLocalConfigFiles();
startMonitorAgentLoop();

app.listen(PORT, () => {
  pushLog('info', `NeoOptimize API running on http://localhost:${PORT}`);
  console.log(`NeoOptimize API running on http://localhost:${PORT}`);
});
