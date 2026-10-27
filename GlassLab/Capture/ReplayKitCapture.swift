import Foundation
import ReplayKit
import AVFoundation
import CoreImage
import QuartzCore

/// In-app screen capture through ReplayKit (`RPScreenRecorder.startCapture`). The system asks the
/// user for consent the first time. Frames are the app's composited screen output as delivered by
/// ReplayKit: YCbCr 4:2:0 buffers, so chroma is subsampled. That is recorded with every frame.
final class ReplayKitCapture: @unchecked Sendable {
    struct Frame: @unchecked Sendable {
        var pixelBuffer: CVPixelBuffer
        /// Presentation time in seconds on the host clock (same base as CACurrentMediaTime).
        var time: Double
        /// CACurrentMediaTime when the buffer reached the app.
        var arrival: Double
        var pixelFormat: OSType
        var width: Int
        var height: Int
    }

    private let lock = NSLock()
    private var latest: Frame?
    private var waiters: [(token: UUID, after: Double, cont: CheckedContinuation<Frame, Error>)] = []
    private(set) var isCapturing = false
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var writerStarted = false
    private var writtenTimes: [Double] = []
    private var arrivalOffsets: [Double] = []
    private let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!])

    var isAvailable: Bool { RPScreenRecorder.shared().isAvailable }

    func start() async throws {
        if isCapturing { return }
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else { throw GlassLabError.unsupported("ReplayKit capture is not available (simulator, AirPlay mirroring or restrictions).") }
        recorder.isMicrophoneEnabled = false
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            recorder.startCapture(handler: { [weak self] sample, type, error in
                guard type == .video, error == nil else { return }
                self?.receive(sample)
            }, completionHandler: { error in
                if let error { cont.resume(throwing: GlassLabError.permissionDenied("Screen capture was not started: \(error.localizedDescription)")) }
                else { cont.resume() }
            })
        }
        isCapturing = true
    }

    func stop() async {
        guard isCapturing else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            RPScreenRecorder.shared().stopCapture { _ in cont.resume() }
        }
        isCapturing = false
        let w: [(token: UUID, after: Double, cont: CheckedContinuation<Frame, Error>)] = lock.withLock {
            let w = waiters; waiters.removeAll(); return w
        }
        for x in w { x.cont.resume(throwing: GlassLabError.captureFailed("capture stopped")) }
    }

    private func receive(_ sample: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sample) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        let frame = Frame(pixelBuffer: pb, time: pts, arrival: CACurrentMediaTime(), pixelFormat: CVPixelBufferGetPixelFormatType(pb),
                          width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb))
        lock.lock()
        latest = frame
        arrivalOffsets.append(frame.arrival - frame.time)
        if arrivalOffsets.count > 600 { arrivalOffsets.removeFirst(300) }
        var ready: [CheckedContinuation<Frame, Error>] = []
        waiters.removeAll { w in
            if frame.time >= w.after { ready.append(w.cont); return true }
            return false
        }
        if let input = writerInput, let writer {
            if !writerStarted { writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample)); writerStarted = true }
            if input.isReadyForMoreMediaData, input.append(sample) { writtenTimes.append(pts) }
        }
        lock.unlock()
        for c in ready { c.resume(returning: frame) }
    }

    /// Waits for a frame whose presentation time is >= `after` (host clock seconds). ReplayKit only
    /// delivers frames when the screen changes, so after `timeout` the latest frame is returned and the
    /// caller must check its `time` against the moment of the scene change.
    func frame(after: Double, timeout: Double = 1.0) async throws -> Frame {
        guard isCapturing else { throw GlassLabError.captureFailed("ReplayKit capture is not running") }
        let token = UUID()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Frame, Error>) in
            lock.lock()
            if let l = latest, l.time >= after { lock.unlock(); cont.resume(returning: l); return }
            waiters.append((token, after, cont))
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in self?.expire(token) }
        }
    }

    private func expire(_ token: UUID) {
        lock.lock()
        guard let i = waiters.firstIndex(where: { $0.token == token }) else { lock.unlock(); return }
        let w = waiters.remove(at: i)
        let l = latest
        lock.unlock()
        if let l { w.cont.resume(returning: l) } else { w.cont.resume(throwing: GlassLabError.captureFailed("ReplayKit delivered no frame")) }
    }

    /// Median (arrival - presentation) delay, for timestamp validation.
    var medianArrivalDelay: Double? {
        lock.lock(); defer { lock.unlock() }
        return arrivalOffsets.isEmpty ? nil : Statistics.median(arrivalOffsets)
    }

    /// Converts a ReplayKit buffer to a Display P3 CGImage, cropping to `crop` (buffer pixels).
    func cgImage(_ f: Frame, crop: CGRect?) -> CGImage? {
        var img = CIImage(cvPixelBuffer: f.pixelBuffer)
        if let crop {
            // Core Image's origin is bottom-left.
            let flipped = CGRect(x: crop.minX, y: CGFloat(f.height) - crop.maxY, width: crop.width, height: crop.height)
            img = img.cropped(to: flipped)
        }
        return ciContext.createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
    }

    static func formatName(_ t: OSType) -> String {
        switch t {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: return "420f (YCbCr 4:2:0 full range)"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: return "420v (YCbCr 4:2:0 video range)"
        case kCVPixelFormatType_32BGRA: return "BGRA 8-bit"
        default:
            let c = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((t >> $0) & 0xFF))) }
            return String(c)
        }
    }

    // MARK: Recording

    func startRecording(to url: URL, width: Int, height: Int, proRes: Bool) throws {
        try? FileManager.default.removeItem(at: url)
        let w = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = proRes
            ? [AVVideoCodecKey: AVVideoCodecType.proRes4444, AVVideoWidthKey: width, AVVideoHeightKey: height]
            : [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: width, AVVideoHeightKey: height,
               AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 1.0]]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard w.canAdd(input) else { throw GlassLabError.captureFailed("video writer rejected the output settings") }
        w.add(input)
        guard w.startWriting() else { throw GlassLabError.captureFailed(w.error?.localizedDescription ?? "writer failed to start") }
        lock.withLock { writer = w; writerInput = input; writerStarted = false; writtenTimes = [] }
    }

    func stopRecording() async -> (times: [Double], error: Error?) {
        let (w, input, times): (AVAssetWriter?, AVAssetWriterInput?, [Double]) = lock.withLock {
            let r = (writer, writerInput, writtenTimes)
            writer = nil; writerInput = nil
            return r
        }
        guard let w, let input else { return ([], GlassLabError.captureFailed("no recording in progress")) }
        input.markAsFinished()
        await w.finishWriting()
        return (times, w.status == .completed ? nil : w.error)
    }

    var latestFrameSize: CGSize? {
        lock.lock(); defer { lock.unlock() }
        return latest.map { CGSize(width: $0.width, height: $0.height) }
    }
}
