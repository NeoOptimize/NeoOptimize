const { app, BrowserWindow, ipcMain, Menu, dialog, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const dns = require('dns');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');
const { autoUpdater } = require('electron-updater');

let backendProcess = null;
let backendStartedInProcess = false;
let autoUpdateTimer = null;
let isUpdateCheckRunning = false;

const RELEASES_URL = 'https://github.com/NeoOptimize/NeoOptimize/releases';
const defaultUpdaterSettings = {
  autoCheck: true,
  autoDownload: false,
  checkIntervalMinutes: 360
};
let updaterSettings = { ...defaultUpdaterSettings };
let updateState = {
  status: 'idle',
  message: 'Updater idle',
  available: false,
  downloading: false,
  downloaded: false,
  progress: 0,
  currentVersion: app.getVersion(),
  latestVersion: null,
  releaseDate: null,
  error: null,
  at: new Date().toISOString()
};

// Optional safe-start: allow disabling GPU via env to mitigate GPU-driver crashes
if (process.env.NEOOPTIMIZE_SAFE_START === '1') {
  try {
    app.disableHardwareAcceleration();
    app.commandLine.appendSwitch('disable-gpu');
    appendDesktopCrashLog('safe-start', 'GPU disabled via NEOOPTIMIZE_SAFE_START');
  } catch (e) {
    // ignore
  }
}

function updaterSettingsPath() {
  return path.join(app.getPath('userData'), 'config', 'updater.json');
}

function clampUpdaterSettings(input = {}) {
  const interval = Number(input.checkIntervalMinutes ?? defaultUpdaterSettings.checkIntervalMinutes);
  return {
    autoCheck: Boolean(input.autoCheck ?? defaultUpdaterSettings.autoCheck),
    autoDownload: Boolean(input.autoDownload ?? defaultUpdaterSettings.autoDownload),
    checkIntervalMinutes: Number.isFinite(interval) ? Math.max(30, Math.min(1440, Math.floor(interval))) : defaultUpdaterSettings.checkIntervalMinutes
  };
}

function loadUpdaterSettings() {
  try {
    const p = updaterSettingsPath();
    if (!fs.existsSync(p)) return { ...defaultUpdaterSettings };
    const raw = JSON.parse(fs.readFileSync(p, 'utf-8'));
    return clampUpdaterSettings(raw);
  } catch {
    return { ...defaultUpdaterSettings };
  }
}

function saveUpdaterSettings(patch = {}) {
  const next = clampUpdaterSettings({ ...updaterSettings, ...patch });
  const p = updaterSettingsPath();
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(next, null, 2), 'utf-8');
  updaterSettings = next;
  autoUpdater.autoDownload = Boolean(updaterSettings.autoDownload);
  return updaterSettings;
}

function scheduleAutoUpdateChecks() {
  if (autoUpdateTimer) {
    clearInterval(autoUpdateTimer);
    autoUpdateTimer = null;
  }
  if (!updaterSettings.autoCheck) return;
  const ms = Math.max(30, Number(updaterSettings.checkIntervalMinutes || 360)) * 60 * 1000;
  autoUpdateTimer = setInterval(() => {
    checkForUpdates({ manual: false }).catch(() => {});
  }, ms);
}

async function hasInternetConnectivity(timeoutMs = 1800) {
  if (process.env.NEOOPTIMIZE_OFFLINE === '1') return false;
  const lookup = new Promise((resolve) => {
    dns.lookup('github.com', (err) => resolve(!err));
  });
  const timeout = new Promise((resolve) => setTimeout(() => resolve(false), Math.max(300, timeoutMs)));
  try {
    return Boolean(await Promise.race([lookup, timeout]));
  } catch {
    return false;
  }
}

function broadcastUpdateState() {
  const payload = { ...updateState, currentVersion: app.getVersion(), at: new Date().toISOString() };
  updateState = payload;
  BrowserWindow.getAllWindows().forEach((w) => {
    try {
      w.webContents.send('updater:status', payload);
    } catch {}
  });
}

function setUpdateState(patch) {
  updateState = { ...updateState, ...patch, currentVersion: app.getVersion(), at: new Date().toISOString() };
  broadcastUpdateState();
}

function resolveAppPaths() {
  const devRoot = path.join(__dirname, '..');
  const appRoot = app.getAppPath();
  const assetRoot = app.isPackaged ? process.resourcesPath : devRoot;
  const dataRoot = app.getPath('userData');
  const spawnCwd = app.isPackaged ? process.resourcesPath : devRoot;
  const serverPath = path.join(appRoot, 'backend', 'server.js');
  return { appRoot, assetRoot, dataRoot, spawnCwd, serverPath };
}

function appendDesktopCrashLog(kind, errorLike) {
  try {
    const { dataRoot } = resolveAppPaths();
    const dir = path.join(dataRoot, 'backend', 'diagnostics');
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, 'desktop-crash.log');
    const entry = {
      time: new Date().toISOString(),
      kind: String(kind || 'desktop'),
      message: String(errorLike?.message || errorLike || 'unknown'),
      stack: String(errorLike?.stack || '')
    };
    fs.appendFileSync(file, `${JSON.stringify(entry)}\n`, 'utf-8');
  } catch {}
}

function ensureUserDataWritable() {
  try {
    const dataPath = app.getPath('userData');
    const testDir = path.join(dataPath, '.__writetest');
    fs.mkdirSync(testDir, { recursive: true });
    const testFile = path.join(testDir, 'ping');
    fs.writeFileSync(testFile, 'ok', 'utf-8');
    try { fs.unlinkSync(testFile); } catch {};
    try { fs.rmdirSync(testDir); } catch {};
    return { ok: true, path: dataPath };
  } catch (err) {
    try {
      const alt = path.join(os.tmpdir(), `neo-user-data-${Date.now()}`);
      fs.mkdirSync(alt, { recursive: true });
      app.setPath('userData', alt);
      appendDesktopCrashLog('userDataFallback', `userData not writable, switched to ${alt}`);
      return { ok: false, fallback: alt };
    } catch (err2) {
      appendDesktopCrashLog('userDataError', err2 || err);
      return { ok: false, error: String(err2 || err) };
    }
  }
}

async function startBackendServer() {
  if (process.env.NEOOPTIMIZE_NO_BACKEND === '1') return;
  if (backendProcess || backendStartedInProcess) return;
  const appPaths = resolveAppPaths();
  process.env.APP_ROOT = appPaths.appRoot;
  process.env.APP_ASSET_ROOT = appPaths.assetRoot;
  process.env.APP_DATA_ROOT = appPaths.dataRoot;
  process.env.PORT = process.env.PORT || '3322';

  try {
    // Prefer in-process backend to avoid extra visible process and spawn ENOENT on portable runtimes.
    await import(pathToFileURL(appPaths.serverPath).href);
    backendStartedInProcess = true;
    return;
  } catch (err) {
    console.error('[backend] in-process start failed:', err);
  }

  if (!fs.existsSync(appPaths.serverPath)) {
    console.error(`[backend] server.js not found: ${appPaths.serverPath}`);
    return;
  }

  try {
    backendProcess = spawn(process.execPath, [appPaths.serverPath], {
      cwd: appPaths.spawnCwd,
      windowsHide: true,
      env: {
        ...process.env,
        PORT: process.env.PORT || '3322',
        APP_ROOT: appPaths.appRoot,
        APP_ASSET_ROOT: appPaths.assetRoot,
        APP_DATA_ROOT: appPaths.dataRoot
      }
    });
  } catch (err) {
    backendProcess = null;
    console.error('[backend] spawn failed:', err);
    return;
  }

  backendProcess.on('error', (err) => {
    console.error('[backend] process error:', err);
    backendProcess = null;
  });
  backendProcess.stdout.on('data', (d) => console.log(`[backend] ${String(d).trim()}`));
  backendProcess.stderr.on('data', (d) => console.error(`[backend] ${String(d).trim()}`));
  backendProcess.on('exit', () => { backendProcess = null; });
}

function stopBackendServer() {
  if (!backendProcess) return;
  try {
    backendProcess.kill();
  } catch {}
  backendProcess = null;
}

function runPowerShellScript(scriptPath, args = []) {
  return new Promise((resolve) => {
    if (!scriptPath || !fs.existsSync(scriptPath)) {
      resolve({ code: 127, out: '', err: `script not found: ${scriptPath}` });
      return;
    }
    const ps = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args], { windowsHide: true });
    let out = '';
    let err = '';
    let settled = false;
    const done = (payload) => {
      if (settled) return;
      settled = true;
      resolve(payload);
    };
    ps.stdout.on('data', (d) => (out += d.toString()));
    ps.stderr.on('data', (d) => (err += d.toString()));
    ps.on('error', (spawnErr) => done({ code: 127, out, err: String(spawnErr?.message || spawnErr || err) }));
    ps.on('close', (code) => done({ code, out, err }));
  });
}

function setupAutoUpdater() {
  autoUpdater.autoDownload = Boolean(updaterSettings.autoDownload);
  autoUpdater.autoInstallOnAppQuit = true;

  autoUpdater.on('checking-for-update', () => {
    setUpdateState({ status: 'checking', message: 'Checking updates from GitHub...', error: null });
  });
  autoUpdater.on('update-available', (info) => {
    setUpdateState({
      status: 'update-available',
      message: `Update available: ${info.version}`,
      available: true,
      latestVersion: info.version || null,
      releaseDate: info.releaseDate || null,
      downloaded: false,
      downloading: false,
      error: null
    });
    if (updaterSettings.autoDownload) {
      downloadUpdate().catch(() => {});
    }
  });
  autoUpdater.on('update-not-available', () => {
    setUpdateState({
      status: 'up-to-date',
      message: 'No update available',
      available: false,
      downloading: false,
      downloaded: false,
      progress: 0,
      error: null
    });
  });
  autoUpdater.on('download-progress', (p) => {
    setUpdateState({
      status: 'downloading',
      message: `Downloading update ${Math.round(Number(p.percent || 0))}%`,
      downloading: true,
      progress: Number(p.percent || 0),
      error: null
    });
  });
  autoUpdater.on('update-downloaded', (info) => {
    setUpdateState({
      status: 'downloaded',
      message: `Update ${info.version} downloaded. Ready to install.`,
      downloading: false,
      downloaded: true,
      available: true,
      latestVersion: info.version || null,
      progress: 100,
      error: null
    });
  });
  autoUpdater.on('error', (err) => {
    setUpdateState({
      status: 'error',
      message: 'Updater error',
      error: String(err?.message || err),
      downloading: false
    });
  });
}

async function checkForUpdates(options = {}) {
  const manual = Boolean(options.manual);
  if (isUpdateCheckRunning) {
    return { ok: false, error: 'Update check already running', busy: true, currentVersion: app.getVersion() };
  }
  if (!app.isPackaged) {
    const msg = 'Updater works in packaged build (.exe).';
    if (manual) setUpdateState({ status: 'idle', message: msg, error: null });
    return { ok: false, error: msg, available: false, currentVersion: app.getVersion() };
  }
  const online = await hasInternetConnectivity();
  if (!online) {
    const msg = 'Offline: update check skipped.';
    if (manual) setUpdateState({ status: 'idle', message: msg, error: null, downloading: false });
    return { ok: false, error: msg, available: false, currentVersion: app.getVersion() };
  }
  isUpdateCheckRunning = true;
  try {
    const result = await autoUpdater.checkForUpdates();
    const info = result?.updateInfo || null;
    const latestVersion = info?.version || null;
    const available = Boolean(latestVersion && latestVersion !== app.getVersion());
    return {
      ok: true,
      available,
      currentVersion: app.getVersion(),
      latestVersion,
      releaseDate: info?.releaseDate || null,
      releaseName: info?.releaseName || null
    };
  } catch (err) {
    const message = String(err?.message || err);
    if (manual) setUpdateState({ status: 'error', message: 'Check update failed', error: message });
    return { ok: false, error: message, currentVersion: app.getVersion() };
  } finally {
    isUpdateCheckRunning = false;
  }
}

async function downloadUpdate() {
  if (!app.isPackaged) {
    return { ok: false, error: 'Download update works in packaged build only.' };
  }
  const online = await hasInternetConnectivity();
  if (!online) {
    return { ok: false, error: 'Offline: cannot download update.' };
  }
  try {
    await autoUpdater.downloadUpdate();
    return { ok: true };
  } catch (err) {
    const message = String(err?.message || err);
    setUpdateState({ status: 'error', message: 'Download failed', error: message });
    return { ok: false, error: message };
  }
}

async function installUpdateNow() {
  if (!app.isPackaged) return { ok: false, error: 'Install update works in packaged build only.' };
  try {
    setTimeout(() => autoUpdater.quitAndInstall(), 250);
    return { ok: true };
  } catch (err) {
    return { ok: false, error: String(err?.message || err) };
  }
}

function createAppMenu() {
  Menu.setApplicationMenu(null);
}

// IPC handlers
ipcMain.handle('cleaner:run', async (event, action) => {
  try {
    const { assetRoot } = resolveAppPaths();
    const scriptsDir = path.join(assetRoot, 'scripts', 'windows');
    let script = '';
    switch (action) {
      case 'temp':
        script = path.join(scriptsDir, 'clean_temp.ps1');
        break;
      case 'registry':
        script = path.join(scriptsDir, 'clean_registry.ps1');
        break;
      case 'optimize-disk':
        script = path.join(scriptsDir, 'optimize_disk.ps1');
        break;
      default:
        return { error: 'unknown action' };
    }
    const res = await runPowerShellScript(script);
    return res;
  } catch (e) {
    return { error: String(e) };
  }
});

ipcMain.handle('exec:run', async (event, { cmd, args }) => {
  return new Promise((resolve) => {
    try {
      const proc = spawn(cmd, args || [], { windowsHide: true });
      let out = '';
      let err = '';
      let settled = false;
      const done = (payload) => {
        if (settled) return;
        settled = true;
        resolve(payload);
      };
      proc.stdout.on('data', (d) => (out += d.toString()));
      proc.stderr.on('data', (d) => (err += d.toString()));
      proc.on('error', (spawnErr) => done({ code: 127, out, err: String(spawnErr?.message || spawnErr || err) }));
      proc.on('close', (code) => done({ code, out, err }));
    } catch (e) {
      resolve({ error: String(e) });
    }
  });
});

ipcMain.handle('updater:getState', async () => ({ ok: true, ...updateState, currentVersion: app.getVersion() }));
ipcMain.handle('updater:getSettings', async () => ({ ok: true, settings: updaterSettings }));
ipcMain.handle('updater:setSettings', async (_event, patch) => {
  try {
    const next = saveUpdaterSettings(patch || {});
    scheduleAutoUpdateChecks();
    return { ok: true, settings: next };
  } catch (err) {
    return { ok: false, error: String(err?.message || err) };
  }
});
ipcMain.handle('updater:check', async () => checkForUpdates({ manual: true }));
ipcMain.handle('updater:download', async () => downloadUpdate());
ipcMain.handle('updater:installNow', async () => installUpdateNow());
ipcMain.handle('updater:openReleases', async () => {
  const online = await hasInternetConnectivity();
  if (!online) return { ok: false, error: 'Offline: releases page unavailable.' };
  await shell.openExternal(RELEASES_URL);
  return { ok: true, url: RELEASES_URL };
});

function createWindow() {
  const win = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true
    }
  });

  if (process.env.NODE_ENV === 'development') {
    win.loadURL('http://localhost:5173');
    win.webContents.openDevTools();
  } else {
    win.loadFile(path.join(__dirname, '..', 'dist', 'index.html'));
  }
}

process.on('uncaughtException', (err) => {
  appendDesktopCrashLog('uncaughtException', err);
});
process.on('unhandledRejection', (reason) => {
  appendDesktopCrashLog('unhandledRejection', reason);
});

app.whenReady().then(async () => {
  updaterSettings = loadUpdaterSettings();
  setupAutoUpdater();

  // Ensure userData is writable; if not, fallback to a temp path to avoid hard crashes
  try {
    const ud = ensureUserDataWritable();
    if (ud && ud.fallback) {
      console.warn('[startup] userData not writable, using fallback:', ud.fallback);
    }
  } catch (e) {
    appendDesktopCrashLog('startup-check', e);
  }

  // Start backend and create window with guarded fallbacks
  try {
    await startBackendServer();
  } catch (e) {
    appendDesktopCrashLog('backend.start.error', e);
  }

  try {
    createWindow();
  } catch (err) {
    appendDesktopCrashLog('createWindow.error', err);
    // Attempt fallback: set userData to tmp and retry once
    try {
      const alt = path.join(os.tmpdir(), `neo-user-data-retry-${Date.now()}`);
      fs.mkdirSync(alt, { recursive: true });
      app.setPath('userData', alt);
      appendDesktopCrashLog('createWindow.retry', `retrying with userData ${alt}`);
      createWindow();
    } catch (err2) {
      appendDesktopCrashLog('createWindow.retry.failed', err2);
    }
  }

  try { createAppMenu(); } catch (e) { appendDesktopCrashLog('menu.error', e); }
  try { broadcastUpdateState(); } catch (e) { appendDesktopCrashLog('broadcast.error', e); }
  try { scheduleAutoUpdateChecks(); } catch (e) { appendDesktopCrashLog('schedule.error', e); }

  if (updaterSettings.autoCheck) {
    setTimeout(() => {
      checkForUpdates({ manual: false }).catch(() => {});
    }, 8000);
  }
});

app.on('before-quit', () => {
  if (autoUpdateTimer) {
    clearInterval(autoUpdateTimer);
    autoUpdateTimer = null;
  }
  stopBackendServer();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
