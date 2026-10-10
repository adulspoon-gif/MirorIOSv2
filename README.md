# MirrorUSB — mirror iPhone/iPad ke Windows lewat kabel USB

## Cara kerja
iPhone (ReplayKit) → encode H.264 hardware → TCP di iPhone → usbmuxd (kabel USB) → Electron → WebCodecs → canvas.

## Windows
Syarat: Node.js, dan Apple Mobile Device Service (otomatis ada kalau iTunes / Apple Devices / 3uTools terpasang).
    cd windows
    npm install
    npm start          # atau: npm run dist  → exe portable

## iOS (tanpa Mac)
1. Upload folder ini ke repo GitHub (private boleh).
2. Tab Actions → "Build IPA" → Run workflow → download artifact `MirrorUSB-ipa` → ekstrak `MirrorUSB.ipa`.
3. Install ke iPhone dengan 3uTools (sign pakai Apple ID) — kalau gagal, pakai Sideloadly.
4. iPhone: Settings → General → VPN & Device Management → Trust.

## Dipakai
1. Colok kabel, tap "Trust" di iPhone, buka MirrorUSB di Windows.
2. iPhone: buka app Mirror USB → tekan ikon → pilih "Mirror USB" → Start Broadcast.
3. Double-click / F11 di Windows = fullscreen.

## Setelan kualitas
- `ios/Broadcast/H264Encoder.swift` → faktor bitrate `* 8` (naik = lebih tajam).
- Resolusi = resolusi asli layar iPhone (tidak di-upscale).
