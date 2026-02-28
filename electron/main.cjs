const { app, BrowserWindow, ipcMain, Menu, dialog, shell } = require('electron');
const path = require('path');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');
const { autoUpdater } = require('electron-updater');

let backendProcess = null;
let backendStartedInProcess = false;

const RELEASES_URL = 'https://github.com/NeoOptimize/NeoOptimize/releases';
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

async function startBackendServer() {
  if (process.env.NEOOPTIMIZE_NO_BACKEND === '1') return;
  if (backendProcess || backendStartedInProcess) return;
  const rootDir = path.join(__dirname, '..');
  process.env.APP_ROOT = rootDir;
  const serverPath = path.join(rootDir, 'backend', 'server.js');
  process.env.PORT = process.env.PORT || '3322';

  // Prefer in-process backend for packaged build to avoid extra visible process.
  if (app.isPackaged) {
    try {
      await import(pathToFileURL(serverPath).href);
      backendStartedInProcess = true;
      return;
    } catch (err) {
      console.error('[backend] in-process start failed:', err);
    }
  }

  backendProcess = spawn(process.execPath, [serverPath], {
    cwd: rootDir,
    windowsHide: true,
    env: { ...process.env, PORT: process.env.PORT || '3322', APP_ROOT: rootDir }
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
    const ps = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args], { windowsHide: true });
    let out = '';
    let err = '';
    ps.stdout.on('data', (d) => (out += d.toString()));
    ps.stderr.on('data', (d) => (err += d.toString()));
    ps.on('close', (code) => resolve({ code, out, err }));
  });
}

function setupAutoUpdater() {
  autoUpdater.autoDownload = false;
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

async function checkForUpdates() {
  if (!app.isPackaged) {
    const msg = 'Updater works in packaged build (.exe).';
    setUpdateState({ status: 'idle', message: msg, error: null });
    return { ok: false, error: msg, available: false, currentVersion: app.getVersion() };
  }
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
    setUpdateState({ status: 'error', message: 'Check update failed', error: message });
    return { ok: false, error: message, currentVersion: app.getVersion() };
  }
}

async function downloadUpdate() {
  if (!app.isPackaged) {
    return { ok: false, error: 'Download update works in packaged build only.' };
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
    const scriptsDir = path.join(__dirname, '..', 'scripts', 'windows');
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
      proc.stdout.on('data', (d) => (out += d.toString()));
      proc.stderr.on('data', (d) => (err += d.toString()));
      proc.on('close', (code) => resolve({ code, out, err }));
    } catch (e) {
      resolve({ error: String(e) });
    }
  });
});

ipcMain.handle('updater:getState', async () => ({ ok: true, ...updateState, currentVersion: app.getVersion() }));
ipcMain.handle('updater:check', async () => checkForUpdates());
ipcMain.handle('updater:download', async () => downloadUpdate());
ipcMain.handle('updater:installNow', async () => installUpdateNow());
ipcMain.handle('updater:openReleases', async () => {
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

app.whenReady().then(async () => {
  setupAutoUpdater();
  await startBackendServer();
  createWindow();
  createAppMenu();
  broadcastUpdateState();
});

app.on('before-quit', () => {
  stopBackendServer();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
