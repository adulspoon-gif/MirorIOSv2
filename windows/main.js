const { app, BrowserWindow } = require('electron');
const path = require('path');
const usbmux = require('./usbmux');

const DEVICE_PORT = 8765; // harus sama dengan port di app iOS
let win = null;
let deviceId = null;
let active = null;
let lastErr = '';

const sleep = ms => new Promise(r => setTimeout(r, ms));
const send = (ch, ...args) => { if (win && !win.isDestroyed()) win.webContents.send(ch, ...args); };

// Format paket dari iPhone: [u32 BE panjang][u8 flags (bit0=keyframe)][u8 orientasi][H.264 Annex B]
function pump({ sock, leftover }) {
  return new Promise(resolve => {
    let buf = Buffer.from(leftover);
    const drain = () => {
      while (buf.length >= 6) {
        const n = buf.readUInt32BE(0);
        if (n > 32 * 1024 * 1024) { sock.destroy(); return; } // data tidak sinkron
        if (buf.length < 6 + n) break;
        send('frame', buf[4] & 1, buf[5], new Uint8Array(buf.subarray(6, 6 + n)));
        buf = buf.subarray(6 + n);
      }
    };
    drain();
    sock.on('data', d => { buf = buf.length ? Buffer.concat([buf, d]) : d; drain(); });
    sock.on('error', () => {});
    sock.on('close', resolve);
    sock.resume();
  });
}

async function loop() {
  for (;;) {
    if (deviceId == null) { await sleep(500); continue; }
    try {
      const c = await usbmux.connect(deviceId, DEVICE_PORT);
      active = c.sock;
      lastErr = '';
      console.log('Tersambung ke iPhone (device ' + deviceId + ')');
      send('status', 'Terhubung, menunggu gambar…');
      await pump(c);
      send('status', 'Broadcast berhenti. Mulai lagi dari iPhone.');
    } catch (e) {
      if (e.message !== lastErr) { lastErr = e.message; console.log('Gagal menyambung:', e.message); }
      const hint = e.message === 'mux:3'
        ? 'Kabel USB sudah OK, tapi port 8765 di iPhone belum aktif.\nBroadcast belum dimulai, atau extension-nya berhenti/crash.'
        : 'Gagal menyambung ke iPhone.';
      send('status', 'iPhone terdeteksi.\n' + hint + '\n\nDi iPhone: buka app “Mirror USB” → tekan tombol Broadcast → Start Broadcast.\n\n[kode: ' + e.message + ']');
    }
    await sleep(600);
  }
}

app.whenReady().then(() => {
  win = new BrowserWindow({
    width: 540, height: 960, backgroundColor: '#000', autoHideMenuBar: true, title: 'MirrorUSB',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), backgroundThrottling: false },
  });
  win.loadFile('index.html');
  usbmux.watch({
    onAttach: id => { deviceId = id; console.log('iPhone terdeteksi, device id', id); send('status', 'iPhone terdeteksi.'); },
    onDetach: id => { if (id === deviceId) { deviceId = null; if (active) active.destroy(); send('status', 'Kabel dicabut. Menunggu iPhone…'); } },
    onError: t => send('status', t),
  });
  loop();
});

app.on('window-all-closed', () => app.quit());
