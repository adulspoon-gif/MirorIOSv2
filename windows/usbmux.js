// Client usbmuxd minimal (protokol plist) — tanpa dependency npm.
// Di Windows, "Apple Mobile Device Service" (dari iTunes / Apple Devices / 3uTools)
// listen di 127.0.0.1:27015 dan bisa menyambung TCP ke port di dalam iPhone lewat USB.
const net = require('net');

const HOST = '127.0.0.1';
const PORT = 27015;
const CLIENT = { ClientVersionString: 'MirrorUSB', ProgName: 'MirrorUSB', kLibUSBMuxVersion: 3 };

function plistXml(obj) {
  const body = Object.entries(obj)
    .map(([k, v]) => `<key>${k}</key>` + (typeof v === 'number' ? `<integer>${v}</integer>` : `<string>${v}</string>`))
    .join('');
  return '<?xml version="1.0" encoding="UTF-8"?>' +
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' +
    `<plist version="1.0"><dict>${body}</dict></plist>`;
}

function packet(tag, obj) {
  const body = Buffer.from(plistXml(obj), 'utf8');
  const h = Buffer.alloc(16);
  h.writeUInt32LE(16 + body.length, 0);
  h.writeUInt32LE(1, 4); // version: plist
  h.writeUInt32LE(8, 8); // message: plist
  h.writeUInt32LE(tag, 12);
  return Buffer.concat([h, body]);
}

const pick = (xml, key, type) => {
  const m = xml.match(new RegExp(`<key>${key}</key>\\s*<${type}>([^<]*)</${type}>`));
  return m ? m[1] : null;
};

class Reader {
  constructor() { this.buf = Buffer.alloc(0); }
  push(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    const out = [];
    while (this.buf.length >= 16) {
      const len = this.buf.readUInt32LE(0);
      if (len < 16 || this.buf.length < len) break;
      out.push(this.buf.subarray(16, len).toString('utf8'));
      this.buf = this.buf.subarray(len);
    }
    return out;
  }
}

// Pantau iPhone yang dicolok/dicabut lewat USB. Return fungsi stop().
function watch({ onAttach, onDetach, onError }) {
  let sock, stopped = false;
  const open = () => {
    if (stopped) return;
    sock = net.connect(PORT, HOST);
    const r = new Reader();
    sock.on('connect', () => sock.write(packet(1, { MessageType: 'Listen', ...CLIENT })));
    sock.on('data', d => {
      for (const x of r.push(d)) {
        if (x.startsWith('bplist')) return onError('usbmuxd membalas binary plist (belum didukung)');
        const type = pick(x, 'MessageType', 'string');
        const id = Number(pick(x, 'DeviceID', 'integer'));
        if (type === 'Attached' && pick(x, 'ConnectionType', 'string') === 'USB') {
          onAttach(id, pick(x, 'SerialNumber', 'string'));
        } else if (type === 'Detached') {
          onDetach(id);
        }
      }
    });
    sock.on('error', () => onError('usbmuxd tidak ditemukan — install iTunes / Apple Devices / 3uTools'));
    sock.on('close', () => setTimeout(open, 1500));
  };
  open();
  return () => { stopped = true; if (sock) sock.destroy(); };
}

// Sambung ke TCP port di iPhone. Setelah sukses, socket jadi "pipa" langsung ke iPhone.
function connect(deviceId, devicePort) {
  return new Promise((resolve, reject) => {
    const sock = net.connect(PORT, HOST);
    const r = new Reader();
    sock.setNoDelay(true);
    sock.once('error', reject);
    sock.once('connect', () => sock.write(packet(2, {
      MessageType: 'Connect', ...CLIENT,
      DeviceID: deviceId,
      PortNumber: ((devicePort & 0xff) << 8) | (devicePort >> 8), // htons
    })));
    const onData = d => {
      const msgs = r.push(d);
      if (!msgs.length) return;
      sock.off('data', onData);
      sock.pause();
      const code = Number(pick(msgs[0], 'Number', 'integer'));
      if (code !== 0) { sock.destroy(); return reject(new Error('mux:' + code)); } // 3 = port belum listen
      resolve({ sock, leftover: r.buf });
    };
    sock.on('data', onData);
  });
}

module.exports = { watch, connect, _test: { packet, Reader, pick } };
