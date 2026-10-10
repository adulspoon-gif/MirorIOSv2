import Foundation
import VideoToolbox
import CoreMedia
import ReplayKit

/// Encode frame layar ke H.264 hardware, latensi rendah (real-time, tanpa B-frame).
final class H264Encoder {
    var onFrame: ((Data, Bool, UInt8) -> Void)?   // (Annex B, keyframe?, orientasi)

    private let q = DispatchQueue(label: "mirror.encoder")   // semua state hanya disentuh di sini
    private var session: VTCompressionSession?
    private var width: Int32 = 0, height: Int32 = 0
    private var wantKey = true
    private var lastPB: CVPixelBuffer?
    private var lastPTS = CMTime.zero
    private var lastOrient: UInt8 = 1

    func encode(_ sb: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        let o = (CMGetAttachment(sb, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber)?.uint8Value ?? 1
        q.sync {
            lastPB = pb; lastPTS = pts; lastOrient = o
            submit(pb, pts, o)
        }
    }

    /// Dipanggil saat PC baru tersambung / ada frame dibuang. Layar yang diam tetap dikirim ulang.
    func requestKeyFrame() {
        q.async {
            self.wantKey = true
            guard let pb = self.lastPB else { return }
            self.lastPTS = CMTimeAdd(self.lastPTS, CMTime(value: 1, timescale: 1000))
            self.submit(pb, self.lastPTS, self.lastOrient)
        }
    }

    func stop() {
        q.sync {
            if let s = session { VTCompressionSessionInvalidate(s) }
            session = nil; lastPB = nil
        }
    }

    // MARK: - private

    private func submit(_ pb: CVPixelBuffer, _ pts: CMTime, _ orient: UInt8) {
        let w = Int32(CVPixelBufferGetWidth(pb)), h = Int32(CVPixelBufferGetHeight(pb))
        if session == nil || w != width || h != height { makeSession(w, h) }
        guard let s = session else { return }
        let props: CFDictionary? = wantKey ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        wantKey = false
        VTCompressionSessionEncodeFrame(s, imageBuffer: pb, presentationTimeStamp: pts, duration: .invalid,
                                        frameProperties: props, infoFlagsOut: nil) { [weak self] status, _, out in
            guard status == noErr, let out = out, let (data, isKey) = H264Encoder.annexB(out) else { return }
            self?.onFrame?(data, isKey, orient)
        }
    }

    private func makeSession(_ w: Int32, _ h: Int32) {
        if let old = session { VTCompressionSessionInvalidate(old) }
        session = nil
        var s: VTCompressionSession?
        let st = VTCompressionSessionCreate(
            allocator: nil, width: w, height: h, codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard st == noErr, let s = s else { return }

        let bitrate = Int(Double(w) * Double(h) * 8)   // ≈ 24 Mbps di 1170×2532; naikkan faktor 8 untuk kualitas lebih tinggi
        func set(_ k: CFString, _ v: CFTypeRef) { VTSessionSetProperty(s, key: k, value: v) }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
        set(kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, 60 as CFNumber)
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 2 as CFNumber)
        set(kVTCompressionPropertyKey_DataRateLimits, [bitrate * 2 / 8, 1] as CFArray)
        VTCompressionSessionPrepareToEncodeFrames(s)

        session = s; width = w; height = h; wantKey = true
    }

    /// AVCC (panjang-prefix) → Annex B (start code), SPS/PPS disisipkan di tiap keyframe.
    private static func annexB(_ sb: CMSampleBuffer) -> (Data, Bool)? {
        let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]]
        let isKey = !((att?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false)
        let start: [UInt8] = [0, 0, 0, 1]
        var out = Data()

        if isKey, let fmt = CMSampleBufferGetFormatDescription(sb) {
            var count = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, parameterSetIndex: 0, parameterSetPointerOut: nil,
                parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
            for i in 0..<count {
                var ptr: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, parameterSetIndex: i, parameterSetPointerOut: &ptr,
                    parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                if let p = ptr { out.append(contentsOf: start); out.append(p, count: size) }
            }
        }

        guard let bb = CMSampleBufferGetDataBuffer(sb) else { return nil }
        var total = 0
        var raw: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &total, dataPointerOut: &raw) == kCMBlockBufferNoErr,
              let base = raw else { return nil }
        var off = 0
        while off + 4 <= total {
            var n32: UInt32 = 0
            memcpy(&n32, base + off, 4)
            let n = Int(UInt32(bigEndian: n32))
            guard n > 0, off + 4 + n <= total else { break }
            out.append(contentsOf: start)
            out.append(Data(bytes: base + off + 4, count: n))
            off += 4 + n
        }
        return (out, isKey)
    }
}
