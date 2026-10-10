import SwiftUI
import ReplayKit
import Network

@main
struct MirrorApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var probeResult = ""

    var body: some View {
        VStack(spacing: 24) {
            Text("Mirror USB").font(.largeTitle.bold())
            Text("1. Colok kabel USB ke PC dan buka MirrorUSB di Windows\n2. Tekan ikon di bawah → pilih “Mirror USB” → Start Broadcast")
                .multilineTextAlignment(.center)
            BroadcastPicker().frame(width: 96, height: 96)
            Text("Untuk berhenti: tekan status bar merah / ikon rekam layar di Control Center.")
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)

            // Diagnosis: cek apakah extension broadcast benar-benar membuka port 8765.
            // Pakai SETELAH Start Broadcast, SEBELUM membuka MirrorUSB di Windows
            // (tes ini ikut menyambung ke extension, jadi bisa memutus sambungan PC).
            Button("Cek: apakah port 8765 aktif?") { probe() }
                .buttonStyle(.bordered)
            Text(probeResult)
                .font(.footnote).multilineTextAlignment(.center)
        }
        .padding()
    }

    private func probe() {
        probeResult = "Mengecek…"
        let c = NWConnection(host: "127.0.0.1", port: 8765, using: .tcp)
        c.stateUpdateHandler = { state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    probeResult = "✅ Port 8765 aktif — extension broadcast hidup dan listen."
                    c.cancel()
                case .failed(let e):
                    probeResult = "❌ Tidak ada yang listen di 8765 (\(e))"
                    c.cancel()
                case .waiting(let e):
                    probeResult = "❌ Tidak ada yang listen di 8765 (\(e))"
                    c.cancel()
                default: break
                }
            }
        }
        c.start(queue: .main)
    }
}

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 96, height: 96))
        // Bundle ID extension = bundle ID app + ".broadcast" (tetap benar walau di-resign 3uTools/Sideloadly)
        v.preferredExtension = (Bundle.main.bundleIdentifier ?? "") + ".broadcast"
        v.showsMicrophoneButton = false
        return v
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
