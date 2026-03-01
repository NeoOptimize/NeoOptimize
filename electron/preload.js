const { contextBridge } = require('electron');

// Expose minimal API surface to the renderer if needed later
contextBridge.exposeInMainWorld('neo', {
  version: () => '1.0.0'
});
