import Foundation
import Network

/// Server TCP kecil di dalam iPhone. PC menyambung lewat USB (usbmuxd), bukan WiFi.
final class StreamServer {
    var onNeedKeyFrame: (() -> Void)?
    var onListenerFailed: ((String) -> Void)?   // listener tidak bisa dibuka / gagal

    private let port: NWEndpoint.Port
    private let q = DispatchQueue(label: "mirror.server")
    private var listener: NWListener?
    private var conn: NWConnection?
    private var inflight = 0
    private var waitKey = true

    init(port: UInt16) { self.port = NWEndpoint.Port(rawValue: port)! }

    func start() throws {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: port)

        // Dulu tidak ada handler ini, jadi kalau listener gagal, tidak ada yang tahu.
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let err): self?.onListenerFailed?("Listener gagal: \(err)")
            case .waiting(let err): self?.onListenerFailed?("Listener tertahan: \(err)")
            default: break
            }
        }

        l.newConnectionHandler = { [weak self] c in
            guard let self = self else { return }
            self.conn?.cancel()
            self.conn = c
            self.inflight = 0
            self.waitKey = true
            // Minta keyframe SETELAH koneksi benar-benar ready. Kalau diminta lebih awal,
            // keyframe bisa terbuang dan layar Windows hitam sampai layar iPhone berubah.
            c.stateUpdateHandler = { [weak self] state in
                if case .ready = state { self?.onNeedKeyFrame?() }
            }
            c.start(queue: self.q)
        }
        l.start(queue: q)
        listener = l
    }

    func stop() {
        q.async {
            self.conn?.cancel(); self.conn = nil
            self.listener?.cancel(); self.listener = nil
        }
    }

    /// Paket: [u32 BE panjang][u8 flags][u8 orientasi][data]
    func send(_ frame: Data, key: Bool, orient: UInt8) {
        q.async { [weak self] in
            guard let self = self, let c = self.conn, case .ready = c.state else { return }
            if key { self.waitKey = false } else if self.waitKey { return }
            if !key && self.inflight > 4 {         // jaringan/USB tersendat → buang frame, jaga latensi
                self.waitKey = true
                self.onNeedKeyFrame?()
                return
            }
            var pkt = Data(capacity: frame.count + 6)
            var len = UInt32(frame.count).bigEndian
            withUnsafeBytes(of: &len) { pkt.append(contentsOf: $0) }
            pkt.append(key ? 1 : 0)
            pkt.append(orient)
            pkt.append(frame)
            self.inflight += 1
            c.send(content: pkt, completion: .contentProcessed { [weak self] _ in
                self?.q.async { self?.inflight -= 1 }
            })
        }
    }
}
