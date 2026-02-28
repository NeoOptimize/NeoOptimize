import fs from 'fs';
import fsp from 'fs/promises';
import path from 'path';
import os from 'os';
import crypto from 'crypto';
import { execFile } from 'child_process';
import { fileURLToPath } from 'url';

const DEFAULT_MAX_FILES = 6000;
const DEFAULT_MAX_DUP_FILES = 5000;
const DEFAULT_MAX_FILE_SIZE_MB = 1024;
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const APP_ROOT = process.env.APP_ROOT ? path.resolve(process.env.APP_ROOT) : path.resolve(__dirname, '..', '..');
const APP_ASSET_ROOT = process.env.APP_ASSET_ROOT ? path.resolve(process.env.APP_ASSET_ROOT) : APP_ROOT;
const APP_DATA_ROOT = process.env.APP_DATA_ROOT ? path.resolve(process.env.APP_DATA_ROOT) : APP_ROOT;

function resolveSpecPath() {
  const local = path.join(APP_DATA_ROOT, 'config', 'advance cleaner engine.txt');
  if (fs.existsSync(local)) return local;
  const bundled = path.join(APP_ASSET_ROOT, 'config', 'advance cleaner engine.txt');
  if (fs.existsSync(bundled)) return bundled;
  return 'C:/Users/Hello World/Documents/Script/advance cleaner engine.txt';
}

function expandEnvWindows(input) {
  return String(input || '').replace(/%([^%]+)%/g, (_, key) => process.env[key] || `%${key}%`);
}

function normalizePath(p) {
  return path.resolve(expandEnvWindows(p));
}

function nowIso() {
  return new Date().toISOString();
}

function safeJoin(...parts) {
  return path.normalize(path.join(...parts));
}

function toKB(bytes) {
  return Math.round((Number(bytes) || 0) / 1024);
}

function chunkString(v, max = 120) {
  if (!v) return v;
  if (v.length <= max) return v;
  return `${v.slice(0, max - 3)}...`;
}

function parseExecPath(v) {
  const s = String(v || '').trim();
  if (!s) return '';
  if (s.startsWith('"')) {
    const m = s.match(/^"([^"]+)"/);
    return m ? m[1] : s;
  }
  const i = s.search(/\s/);
  return i < 0 ? s : s.slice(0, i);
}

function pathLooksFilesystem(v) {
  return /^[A-Za-z]:\\/.test(v || '') || /^\\\\/.test(v || '');
}

function createLimiter(maxCount) {
  let count = 0;
  return {
    ok() {
      if (count >= maxCount) return false;
      count += 1;
      return true;
    },
    count() {
      return count;
    }
  };
}

async function fileExists(p) {
  try {
    await fsp.access(p, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function* walkFiles(rootDir, options = {}) {
  const {
    maxDepth = 6,
    maxFiles = DEFAULT_MAX_FILES,
    includeExt = null,
    minSize = 1,
    maxSizeBytes = DEFAULT_MAX_FILE_SIZE_MB * 1024 * 1024,
    stopRef = { stop: false }
  } = options;

  const limiter = createLimiter(maxFiles);

  async function* walk(dir, depth) {
    if (stopRef.stop) return;
    if (depth > maxDepth) return;
    let entries = [];
    try {
      entries = await fsp.readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      if (stopRef.stop) return;
      const full = safeJoin(dir, entry.name);
      if (entry.isDirectory()) {
        yield* walk(full, depth + 1);
        continue;
      }
      if (!entry.isFile()) continue;
      if (!limiter.ok()) return;
      let st = null;
      try {
        st = await fsp.stat(full);
      } catch {
        continue;
      }
      if (!st || st.size < minSize || st.size > maxSizeBytes) continue;
      const ext = path.extname(full).toLowerCase();
      if (includeExt && includeExt.size > 0 && !includeExt.has(ext)) continue;
      yield { path: full, size: st.size, mtimeMs: st.mtimeMs };
    }
  }

  yield* walk(rootDir, 0);
}

async function sha256File(filePath) {
  const hash = crypto.createHash('sha256');
  await new Promise((resolve, reject) => {
    const rs = fs.createReadStream(filePath);
    rs.on('data', (chunk) => hash.update(chunk));
    rs.on('error', reject);
    rs.on('end', resolve);
  });
  return hash.digest('hex');
}

function uniquePaths(list) {
  const out = [];
  const seen = new Set();
  list.forEach((v) => {
    const p = normalizePath(v);
    if (!seen.has(p)) {
      seen.add(p);
      out.push(p);
    }
  });
  return out;
}

function makeJunkTargets(mode = 'full') {
  const temp = process.env.TEMP || safeJoin(process.env.USERPROFILE || 'C:/Users/Public', 'AppData', 'Local', 'Temp');
  const localApp = process.env.LOCALAPPDATA || safeJoin(process.env.USERPROFILE || 'C:/Users/Public', 'AppData', 'Local');
  const appData = process.env.APPDATA || safeJoin(process.env.USERPROFILE || 'C:/Users/Public', 'AppData', 'Roaming');
  const programData = process.env.ProgramData || 'C:/ProgramData';

  const dumpOnly = [
    { category: 'memory-dump', dir: 'C:/Windows/Minidump', includeExt: ['.dmp', '.mdmp', '.hdmp'], maxDepth: 2 },
    { category: 'memory-dump', dir: 'C:/Windows', includeExt: ['.dmp', '.mdmp', '.hdmp'], maxDepth: 2 },
    { category: 'error-report', dir: safeJoin(localApp, 'Microsoft', 'Windows', 'WER'), includeExt: ['.wer', '.dmp', '.mdmp', '.hdmp'] },
    { category: 'error-report', dir: safeJoin(programData, 'Microsoft', 'Windows', 'WER'), includeExt: ['.wer', '.dmp', '.mdmp', '.hdmp'] }
  ];

  const full = [
    { category: 'windows-temp', dir: 'C:/Windows/Temp' },
    { category: 'windows-temp', dir: 'C:/Windows/Prefetch' },
    { category: 'windows-temp', dir: 'C:/Windows/SoftwareDistribution/Download' },
    { category: 'windows-logs', dir: 'C:/Windows/Logs' },
    { category: 'windows-logs', dir: 'C:/Windows/System32/LogFiles' },
    { category: 'user-temp', dir: temp },
    { category: 'user-temp', dir: safeJoin(localApp, 'Temp') },
    { category: 'recent', dir: safeJoin(appData, 'Microsoft', 'Windows', 'Recent') },
    { category: 'thumbnail-cache', dir: safeJoin(localApp, 'Microsoft', 'Windows', 'Explorer') },
    { category: 'browser-cache', dir: safeJoin(localApp, 'Google', 'Chrome', 'User Data', 'Default', 'Cache') },
    { category: 'browser-cache', dir: safeJoin(localApp, 'Microsoft', 'Edge', 'User Data', 'Default', 'Cache') },
    { category: 'browser-cache', dir: safeJoin(appData, 'Mozilla', 'Firefox', 'Profiles') },
    { category: 'browser-cache', dir: safeJoin(appData, 'Opera Software', 'Opera Stable', 'Cache') },
    { category: 'app-cache', dir: safeJoin(appData, 'discord', 'Cache') },
    { category: 'app-cache', dir: safeJoin(appData, 'Slack', 'Cache') },
    { category: 'app-cache', dir: safeJoin(appData, 'Telegram Desktop', 'tdata', 'user_data', 'cache') },
    { category: 'app-cache', dir: safeJoin(appData, 'Zoom', 'data') },
    { category: 'recycle-bin', dir: 'C:/$Recycle.Bin' },
    ...dumpOnly
  ];

  const out = mode === 'dump' ? dumpOnly : full;
  return out.filter((x) => fs.existsSync(normalizePath(x.dir)));
}

function makeDuplicateRoots() {
  const user = process.env.USERPROFILE || 'C:/Users/Public';
  return uniquePaths([
    safeJoin(user, 'Desktop'),
    safeJoin(user, 'Documents'),
    safeJoin(user, 'Downloads'),
    safeJoin(user, 'Pictures'),
    safeJoin(user, 'Videos'),
    safeJoin(user, 'Music')
  ]).filter((p) => fs.existsSync(p));
}

function duplicateExtSet() {
  return new Set(
    [
      '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff', '.webp', '.raw', '.cr2', '.nef',
      '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.rtf', '.odt',
      '.mp3', '.wav', '.flac', '.aac', '.m4a', '.ogg', '.wma',
      '.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm',
      '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.iso',
      '.exe', '.msi', '.dll', '.sys', '.bat', '.cmd', '.ps1'
    ].map((v) => v.toLowerCase())
  );
}

function runRegQuery(args) {
  return new Promise((resolve) => {
    execFile('reg', args, { windowsHide: true, maxBuffer: 1024 * 1024 * 8 }, (err, stdout, stderr) => {
      if (err) return resolve({ ok: false, stdout: String(stdout || ''), stderr: String(stderr || err.message || '') });
      return resolve({ ok: true, stdout: String(stdout || ''), stderr: String(stderr || '') });
    });
  });
}

function parseRegQueryRows(stdout) {
  const rows = [];
  const lines = String(stdout || '').split(/\r?\n/);
  let currentKey = '';
  lines.forEach((line) => {
    const trimmed = line.trimEnd();
    if (!trimmed) return;
    if (/^HKEY_/i.test(trimmed.trim())) {
      currentKey = trimmed.trim();
      return;
    }
    const m = trimmed.match(/^\s{2,}([^\s].*?)\s{2,}(REG_\w+)\s{2,}(.*)$/i);
    if (!m || !currentKey) return;
    rows.push({ key: currentKey, name: m[1].trim(), type: m[2].trim(), data: m[3].trim() });
  });
  return rows;
}

export function createAdvanceCleaner() {
  let running = false;
  let progress = 0;
  let total = 100;
  let statusMessage = 'idle';
  let currentMode = 'full';
  let dryRun = true;
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
  let duplicates = [];
  let registryIssues = [];
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
    if (runLog.length > 5000) runLog.shift();
    emit('log', { level, message, meta });
  };

  const setProgress = (value, info = {}) => {
    const next = Math.max(0, Math.min(100, Math.floor(value)));
    progress = next;
    emit('progress', { progress, total, mode: currentMode, dryRun, ...info });
  };

  const finish = (reason = 'completed') => {
    running = false;
    stopRef.stop = false;
    statusMessage = reason === 'stopped' ? 'stopped' : 'idle';
    lastRun = {
      time: nowIso(),
      mode: currentMode,
      dryRun,
      files: files.length,
      duplicates: duplicates.length,
      registry: registryIssues.length
    };
    const summary = {
      mode: currentMode,
      dryRun,
      status: statusMessage,
      files: files.length,
      duplicates: duplicates.length,
      registry: registryIssues.length,
      reclaimedKB: files.reduce((s, x) => s + Number(x.sizeKB || 0), 0)
    };
    emit('done', summary);
    log('ok', `AdvanceCleaner finished: mode=${currentMode} dryRun=${dryRun} files=${summary.files} dup=${summary.duplicates} reg=${summary.registry}`);
  };

  async function maybeDelete(filePath) {
    if (dryRun) return { action: 'would-delete', ok: true };
    try {
      await fsp.rm(filePath, { force: true });
      return { action: 'deleted', ok: true };
    } catch (err) {
      return { action: 'skip', ok: false, error: String(err?.message || err) };
    }
  }

async function scanJunk(opts = {}) {
    const targets = makeJunkTargets(currentMode);
    const maxFiles = Math.max(100, Number(opts.maxFiles || DEFAULT_MAX_FILES));
    const maxDepth = Math.max(1, Number(opts.maxDepth || 6));
    let scanned = 0;
    let targetIdx = 0;

    log('info', `Junk scan started: targets=${targets.length}, dryRun=${dryRun}`);
    for (const target of targets) {
      if (stopRef.stop) return;
      targetIdx += 1;
      const basePct = Math.floor(((targetIdx - 1) / Math.max(1, targets.length)) * 85);
      setProgress(basePct, { phase: 'junk', category: target.category });

      const root = normalizePath(target.dir);
      const includeExt = Array.isArray(target.includeExt) && target.includeExt.length > 0
        ? new Set(target.includeExt.map((x) => String(x || '').toLowerCase()))
        : null;
      const targetDepth = Math.max(1, Number(target.maxDepth || maxDepth));
      for await (const file of walkFiles(root, { maxDepth: targetDepth, maxFiles, stopRef, includeExt, maxSizeBytes: DEFAULT_MAX_FILE_SIZE_MB * 1024 * 1024 })) {
        if (stopRef.stop) return;
        scanned += 1;
        const result = await maybeDelete(file.path);
        const item = {
          path: file.path,
          sizeKB: toKB(file.size),
          category: target.category,
          action: result.action,
          ok: result.ok
        };
        files.push(item);
        if (files.length > 20000) files.shift();
        emit('fileFound', item);

        if (!result.ok) log('warn', `skip ${chunkString(file.path, 140)} (${result.error || 'unknown'})`);
        else log('info', `${result.action} ${chunkString(file.path, 140)} (${item.sizeKB}KB)`);

        const pct = Math.min(92, basePct + Math.floor((scanned / Math.max(1, maxFiles)) * 7));
        setProgress(pct, { phase: 'junk', scanned });
      }
    }
    setProgress(94, { phase: 'junk', scanned });
  }

  async function scanDuplicates(opts = {}) {
    const includeExt = duplicateExtSet();
    const roots = uniquePaths([...(Array.isArray(opts.paths) ? opts.paths : []), ...makeDuplicateRoots()]).filter((p) => fs.existsSync(p));
    const maxFiles = Math.max(200, Number(opts.maxFiles || DEFAULT_MAX_DUP_FILES));
    const maxDepth = Math.max(1, Number(opts.maxDepth || 6));
    const bySize = new Map();
    let scanned = 0;

    log('info', `Duplicate scan started: roots=${roots.length}, dryRun=${dryRun}`);
    for (const root of roots) {
      if (stopRef.stop) return;
      for await (const file of walkFiles(root, { maxDepth, maxFiles, stopRef, includeExt, minSize: 1024 })) {
        if (stopRef.stop) return;
        scanned += 1;
        const key = String(file.size);
        if (!bySize.has(key)) bySize.set(key, []);
        bySize.get(key).push(file);
        if (scanned % 50 === 0) {
          setProgress(Math.min(70, Math.floor((scanned / Math.max(1, maxFiles)) * 70)), { phase: 'duplicate-index', scanned });
        }
      }
    }

    const candidateGroups = [...bySize.values()].filter((x) => x.length > 1);
    let hashed = 0;
    let dupGroupCount = 0;

    for (const group of candidateGroups) {
      if (stopRef.stop) return;
      const byHash = new Map();
      for (const f of group) {
        if (stopRef.stop) return;
        try {
          const h = await sha256File(f.path);
          hashed += 1;
          if (!byHash.has(h)) byHash.set(h, []);
          byHash.get(h).push(f);
        } catch (err) {
          log('warn', `hash failed ${chunkString(f.path, 140)} (${String(err?.message || err)})`);
        }
        if (hashed % 10 === 0) {
          setProgress(Math.min(95, 70 + Math.floor((hashed / Math.max(1, scanned)) * 25)), { phase: 'duplicate-hash', hashed });
        }
      }
      for (const [hash, filesInHash] of byHash.entries()) {
        if (filesInHash.length < 2) continue;
        dupGroupCount += 1;
        const out = {
          hash: `sha256:${hash}`,
          group: filesInHash.map((x) => ({ path: x.path, sizeKB: toKB(x.size) })),
          suggestedKeep: filesInHash[0].path
        };
        duplicates.push(out);
        if (duplicates.length > 5000) duplicates.shift();
        emit('duplicateFound', out);
        log('info', `duplicate group found: ${out.hash} (${out.group.length} files)`);
      }
    }

    setProgress(98, { phase: 'duplicate', groups: dupGroupCount });
  }

async function scanRegistry(opts = {}) {
    if (process.platform !== 'win32') {
      log('warn', 'Registry scan skipped: Windows only');
      setProgress(98, { phase: 'registry', skipped: true });
      return;
    }

    const keys = [
      'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
      'HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Run',
      'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce',
      'HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce'
    ];

    let checked = 0;
    for (const key of keys) {
      if (stopRef.stop) return;
      const q = await runRegQuery(['query', key]);
      checked += 1;
      setProgress(Math.min(85, Math.floor((checked / keys.length) * 85)), { phase: 'registry-query', key });
      if (!q.ok) {
        log('warn', `registry query failed: ${key}`);
        continue;
      }
      const rows = parseRegQueryRows(q.stdout);
      for (const row of rows) {
        if (stopRef.stop) return;
        if (!['REG_SZ', 'REG_EXPAND_SZ'].includes(String(row.type).toUpperCase())) continue;
        const expanded = expandEnvWindows(row.data);
        const execPath = parseExecPath(expanded);
        if (!pathLooksFilesystem(execPath)) continue;
        const exists = await fileExists(execPath);
        if (exists) continue;
        let action = dryRun ? 'would-fix' : 'fixed';
        let ok = true;
        let error = '';
        if (!dryRun) {
          const del = await runRegQuery(['delete', row.key, '/v', row.name, '/f']);
          if (!del.ok) {
            action = 'failed-fix';
            ok = false;
            error = String(del.stderr || del.stdout || '').trim();
          }
        }
        const issue = {
          key: row.key,
          valueName: row.name,
          target: execPath,
          reason: 'target path not found',
          action,
          ok,
          error: error ? chunkString(error, 200) : undefined
        };
        registryIssues.push(issue);
        if (registryIssues.length > 8000) registryIssues.shift();
        emit('registryIssue', issue);
        if (action === 'fixed') log('ok', `registry fixed: ${row.key}\\${row.name}`);
        else if (action === 'failed-fix') log('warn', `registry fix failed: ${row.key}\\${row.name} (${chunkString(error, 140)})`);
        else log('warn', `registry issue: ${row.key}\\${row.name} -> ${chunkString(execPath, 120)}`);
      }
    }
    setProgress(98, { phase: 'registry', issues: registryIssues.length });
  }

  async function runMode(opts = {}) {
    try {
      if (currentMode === 'duplicate') await scanDuplicates(opts);
      else if (currentMode === 'registry') await scanRegistry(opts);
      else await scanJunk(opts);
      if (stopRef.stop) finish('stopped');
      else {
        setProgress(100, { phase: 'complete' });
        finish('completed');
      }
    } catch (err) {
      log('error', `AdvanceCleaner crash: ${String(err?.message || err)}`);
      finish('stopped');
    }
  }

  function start(opts = {}) {
    if (running) return { running: true, progress, total, mode: currentMode, dryRun };
    running = true;
    progress = 0;
    total = 100;
    stopRef = { stop: false };
    currentMode = String(opts.mode || 'full').toLowerCase();
    if (!['full', 'dump', 'duplicate', 'registry'].includes(currentMode)) currentMode = 'full';
    dryRun = opts.dryRun !== false;

    if (!opts.keepPreviousResults) {
      files = [];
      duplicates = [];
      registryIssues = [];
    }
    statusMessage = `scanning:${currentMode}`;
    log('info', `AdvanceCleaner start mode=${currentMode} dryRun=${dryRun}`);

    runMode(opts);
    return { running: true, progress, total, mode: currentMode, dryRun };
  }

  function stop() {
    if (!running) return { running: false, progress, total, mode: currentMode, dryRun };
    stopRef.stop = true;
    statusMessage = 'stopping';
    log('warn', 'AdvanceCleaner stop requested');
    return { running: true, stopping: true, progress, total, mode: currentMode, dryRun };
  }

  function status() {
    return {
      running,
      progress,
      total,
      statusMessage,
      mode: currentMode,
      dryRun,
      lastRun,
      counts: { files: files.length, duplicates: duplicates.length, registry: registryIssues.length, backups: backups.length }
    };
  }

  function resultsList() {
    return {
      files: files.slice(),
      duplicates: duplicates.slice(),
      registry: registryIssues.slice(),
      backups: backups.slice(),
      mode: currentMode,
      dryRun,
      statusMessage
    };
  }

  function backupDir() {
    return safeJoin(APP_DATA_ROOT, 'backend', 'backups');
  }

  function ensureBackupDir() {
    const dir = backupDir();
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    return dir;
  }

  function createBackup(meta = {}) {
    const dir = ensureBackupDir();
    const d = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const id = `backup-${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
    const outPath = safeJoin(dir, `${id}.json`);
    const payload = {
      id,
      time: nowIso(),
      meta: { ...meta, dryRunDefault: true, specPath: resolveSpecPath() },
      snapshot: resultsList(),
      logs: runLog.slice(-2000)
    };
    fs.writeFileSync(outPath, JSON.stringify(payload, null, 2), 'utf-8');
    const entry = { id, time: payload.time, path: outPath, meta: payload.meta };
    backups.push(entry);
    if (backups.length > 500) backups.shift();
    emit('backup', { action: 'created', entry });
    log('ok', `backup created ${id}`);
    return entry;
  }

  function listBackups() {
    const dir = backupDir();
    const diskEntries = [];
    if (fs.existsSync(dir)) {
      for (const name of fs.readdirSync(dir)) {
        if (!name.toLowerCase().endsWith('.json')) continue;
        const full = safeJoin(dir, name);
        try {
          const raw = JSON.parse(fs.readFileSync(full, 'utf-8'));
          if (!raw?.id || !raw?.time) continue;
          diskEntries.push({ id: raw.id, time: raw.time, path: full, meta: raw.meta || {} });
        } catch {}
      }
    }
    const byId = new Map();
    backups.forEach((b) => byId.set(b.id, b));
    diskEntries.forEach((b) => byId.set(b.id, b));
    return [...byId.values()].sort((a, b) => String(a.time).localeCompare(String(b.time)));
  }

  function restoreBackup(id) {
    const all = listBackups();
    const hit = all.find((x) => x.id === id);
    if (!hit) {
      log('error', `backup not found ${id}`);
      return { ok: false, error: 'backup not found' };
    }
    try {
      const raw = JSON.parse(fs.readFileSync(hit.path, 'utf-8'));
      const snap = raw?.snapshot || {};
      files = Array.isArray(snap.files) ? snap.files : [];
      duplicates = Array.isArray(snap.duplicates) ? snap.duplicates : [];
      registryIssues = Array.isArray(snap.registry) ? snap.registry : [];
      dryRun = true;
      statusMessage = 'idle';
      emit('backup', { action: 'restored', entry: hit });
      log('ok', `backup restored ${id}`);
      return { ok: true, entry: hit };
    } catch (err) {
      log('error', `restore failed ${id}: ${String(err?.message || err)}`);
      return { ok: false, error: String(err?.message || err) };
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

  return { start, stop, status, on, resultsList, createBackup, listBackups, restoreBackup };
}
