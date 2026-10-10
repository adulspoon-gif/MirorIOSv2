const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('mirror', {
  onFrame: cb => ipcRenderer.on('frame', (_e, key, orient, data) => cb(key, orient, data)),
  onStatus: cb => ipcRenderer.on('status', (_e, text) => cb(text)),
});
