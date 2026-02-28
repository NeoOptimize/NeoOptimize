const { contextBridge, ipcRenderer } = require('electron');

// Expose minimal API surface to the renderer
contextBridge.exposeInMainWorld('neo', {
  version: () => '0.0.1',
  runCleaner: (action) => ipcRenderer.invoke('cleaner:run', action),
  // generic exec (use carefully)
  execCmd: (cmd, args) => ipcRenderer.invoke('exec:run', { cmd, args }),
  getUpdaterState: () => ipcRenderer.invoke('updater:getState'),
  checkForUpdates: () => ipcRenderer.invoke('updater:check'),
  downloadUpdate: () => ipcRenderer.invoke('updater:download'),
  installUpdateNow: () => ipcRenderer.invoke('updater:installNow'),
  openReleasesPage: () => ipcRenderer.invoke('updater:openReleases'),
  onUpdaterStatus: (cb) => {
    if (typeof cb !== 'function') return () => {};
    const handler = (_event, payload) => cb(payload);
    ipcRenderer.on('updater:status', handler);
    return () => ipcRenderer.removeListener('updater:status', handler);
  }
});
