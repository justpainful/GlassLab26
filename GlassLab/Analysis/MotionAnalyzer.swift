import Foundation
import AVFoundation
import CoreImage
import CoreGraphics

/// Per-frame measurements extracted from a recording of the canvas.
struct MotionSample: Codable, Hashable, Sendable {
    var time: Double            // media clock seconds
    var opticalChange: Double   // mean |Y - Y_first| over the canvas ROI
    var frameDelta: Double      // mean |Y - Y_previous|
    var changedArea: Double     // pt^2 of pixels differing from the first frame by > threshold
    var bboxWidth: Double?      // pt
    var bboxHeight: Double?     // pt
    var centroidX: Double?      // pt, canvas coordinates
    var centroidY: Double?
}

struct MotionReport: Sendable {
    var samples: [MotionSample]
    var measurements: [Measurement]
    var warnings: [String]
}

/// Streams a recording frame by frame (never holding more than two decoded frames) and derives
/// time series for the subject's apparent size, position and optical change.
enum MotionAnalyzer {
    static func analyze(url: URL, recording: RecordingRecord, events: [InteractionEvent], threshold: Double = 0.04,
                        progress: ((Double) -> Void)? = nil) throws -> MotionReport {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { throw GlassLabError.invalidData("recording has no video track") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw GlassLabError.invalidData(reader.error?.localizedDescription ?? "cannot read recording") }

        let crop = recording.crop
        let ppp = recording.pixelsPerPoint
        // Downsample so that the ROI is at most ~240 px wide.
        let roiW = Double(crop?.width ?? Int(track.naturalSize.width))
        let ds = max(1, Int(ceil(roiW / 240)))
        let ptPerSample = Double(ds) / ppp
        var first: [Float]? = nil
        var previous: [Float]? = nil
        var samples: [MotionSample] = []
        var index = 0
        let total = max(1, recording.frameCount)

        while reader.status == .reading, let sb = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); throw GlassLabError.cancelled }
            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            let (gray, w, h) = luma(pb, crop: crop, factor: ds)
            // Recording frame times are stored on the media clock; fall back to the file PTS offset.
            let t = index < recording.frameTimes.count ? recording.frameTimes[index] : recording.startMediaTime + CMSampleBufferGetPresentationTimeStamp(sb).seconds
            if first == nil { first = gray }
            var change = 0.0, delta = 0.0, area = 0
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            var sx = 0.0, sy = 0.0
            for i in gray.indices {
                let d = abs(Double(gray[i] - first![i]))
                change += d
                if let p = previous { delta += abs(Double(gray[i] - p[i])) }
                if d > threshold {
                    area += 1
                    let x = i % w, y = i / w
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    sx += Double(x); sy += Double(y)
                }
            }
            let n = Double(max(1, gray.count))
            samples.append(MotionSample(time: t, opticalChange: change / n, frameDelta: previous == nil ? 0 : delta / n,
                                        changedArea: Double(area) * ptPerSample * ptPerSample,
                                        bboxWidth: maxX >= 0 ? Double(maxX - minX + 1) * ptPerSample : nil,
                                        bboxHeight: maxY >= 0 ? Double(maxY - minY + 1) * ptPerSample : nil,
                                        centroidX: area > 0 ? (sx / Double(area) + 0.5) * ptPerSample : nil,
                                        centroidY: area > 0 ? (sy / Double(area) + 0.5) * ptPerSample : nil))
            _ = h
            previous = gray
            index += 1
            progress?(Double(index) / Double(total))
        }
        if reader.status == .failed { throw GlassLabError.invalidData(reader.error?.localizedDescription ?? "decode failed") }
        return summarize(samples: samples, events: events, recording: recording)
    }

    /// Luma (Rec.709 on encoded BGRA) of the cropped, box-downsampled frame.
    static func luma(_ pb: CVPixelBuffer, crop: PixelRegion?, factor: Int) -> ([Float], Int, Int) {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let W = CVPixelBufferGetWidth(pb), H = CVPixelBufferGetHeight(pb)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        guard let base = CVPixelBufferGetBaseAddress(pb)?.assumingMemoryBound(to: UInt8.self) else { return ([], 0, 0) }
        let r = crop ?? PixelRegion(x: 0, y: 0, width: W, height: H)
        let x0 = max(0, r.x), y0 = max(0, r.y)
        let w = max(1, min(r.width, W - x0) / factor), h = max(1, min(r.height, H - y0) / factor)
        var out = [Float](repeating: 0, count: w * h)
        let inv = 1 / Float(factor * factor * 255)
        for y in 0..<h {
            for x in 0..<w {
                var acc: Float = 0
                for dy in 0..<factor {
                    let row = base + (y0 + y * factor + dy) * stride
                    for dx in 0..<factor {
                        let p = row + (x0 + x * factor + dx) * 4
                        acc += 0.0722 * Float(p[0]) + 0.7152 * Float(p[1]) + 0.2126 * Float(p[2])
                    }
                }
                out[y * w + x] = acc * inv
            }
        }
        return (out, w, h)
    }

    static func summarize(samples: [MotionSample], events: [InteractionEvent], recording: RecordingRecord) -> MotionReport {
        var m: [Measurement] = []
        var warnings: [String] = []
        let v = AlgorithmVersion.motion
        let src = [recording.fileName]
        guard samples.count >= 4 else {
            return MotionReport(samples: samples, measurements: [.unavailable("Motion analysis", unit: "", algorithm: "frame differencing", version: v, reason: "Fewer than 4 frames recorded.")], warnings: [])
        }
        let t = samples.map(\.time)
        let iv = zip(t.dropFirst(), t).map { $0 - $1 }.filter { $0 > 0 }
        let medianIv = Statistics.median(iv)
        m.append(Measurement(name: "Capture Frame Interval (median)", value: medianIv * 1000, unit: "ms", provenance: .measured,
            algorithm: "Median difference of ReplayKit presentation timestamps", version: v, confidence: .high("\(iv.count) intervals"),
            sampleCount: iv.count, significantDigits: 3, sources: src,
            notes: "Effective capture rate \(Format.number(1 / medianIv, digits: 3)) fps. ReplayKit only delivers frames when the screen changes; long gaps can be static periods."))
        let dropped = iv.filter { $0 > medianIv * 1.5 }.count
        m.append(Measurement(name: "Irregular Capture Intervals (>1.5x median)", value: Double(dropped), unit: "count", provenance: .measured,
            algorithm: "Count of timestamp gaps", version: v, confidence: .high("Count"), sampleCount: iv.count, significantDigits: 3, sources: src))

        let touchDown = events.first { $0.kind == .touchDown }?.time
        let stimulus = touchDown ?? events.first { $0.kind == .stateChange || $0.kind == .animationStart }?.time
        let widths = samples.map { $0.bboxWidth ?? 0 }
        let changes = samples.map(\.opticalChange)

        if let sr = TimeSeries.stepResponse(t: t, y: changes, stimulusTime: stimulus) {
            warnings += sr.warnings
            if let on = sr.onsetTime, let s = stimulus {
                m.append(Measurement(name: "Response Onset (after stimulus)", value: (on - s) * 1000, unit: "ms", provenance: .measured,
                    algorithm: "First frame whose optical change leaves the baseline noise band, minus the stimulus timestamp", version: v,
                    confidence: medianIv < 0.02 ? .medium("Resolution limited to one frame interval") : .low("Frame interval \(Format.milliseconds(medianIv))"),
                    uncertainty: Uncertainty(halfWidth: medianIv * 1000, kind: .quantization), sampleCount: samples.count, significantDigits: 2, sources: src))
            }
            m.append(Measurement(name: "Rise Time 10-90% (optical change)", value: sr.riseTime.map { $0 * 1000 }, unit: "ms", provenance: .measured,
                algorithm: "Linear interpolation of 10% and 90% crossings of the optical-change signal", version: v,
                confidence: (sr.riseTime ?? 0) > 3 * medianIv ? .medium("Spans several frames") : .low("Spans fewer than 3 frames"),
                uncertainty: Uncertainty(halfWidth: medianIv * 1000, kind: .quantization), sampleCount: samples.count,
                validity: sr.riseTime == nil ? .notAvailable("No clean 10%-90% crossing") : .valid, significantDigits: 2, sources: src))
            m.append(Measurement(name: "Settling Time (5% band)", value: sr.settlingTime.map { $0 * 1000 }, unit: "ms", provenance: .measured,
                algorithm: "Time from onset until the signal stays within 5% of its final value", version: v,
                confidence: .medium("Final value from the last 5 frames"), uncertainty: Uncertainty(halfWidth: medianIv * 1000, kind: .quantization),
                sampleCount: samples.count, validity: sr.settlingTime == nil ? .notAvailable("Did not settle in the recording") : .valid, significantDigits: 2, sources: src))
        }
        if widths.contains(where: { $0 > 0 }), let sr = TimeSeries.stepResponse(t: t, y: widths, stimulusTime: stimulus) {
            m.append(Measurement(name: "Peak Overshoot (apparent width)", value: sr.overshoot.map { $0 * 100 }, unit: "%", provenance: .measured,
                algorithm: "(peak - final) / |step| of the changed-region bounding-box width", version: v, confidence: .medium("Bounding box of thresholded difference"),
                sampleCount: samples.count, validity: sr.overshoot == nil ? .notAvailable("No step in width") : .valid, significantDigits: 2, sources: src))
            m.append(Measurement(name: "Oscillation Frequency (apparent width)", value: sr.oscillationFrequency, unit: "Hz", provenance: .estimated,
                algorithm: "Median half-period between successive extrema after the peak", version: v,
                confidence: .low("Requires several resolved extrema"), sampleCount: samples.count,
                validity: sr.oscillationFrequency == nil ? .notAvailable("Fewer than 3 extrema: no resolved oscillation") : .valid, significantDigits: 2, sources: src))
            m.append(Measurement(name: "Damping Ratio (log decrement)", value: sr.dampingRatio, unit: "", provenance: .estimated,
                algorithm: "Logarithmic decrement between same-sign extrema; descriptive under a second-order model", version: v,
                confidence: .low("Model-based; not iOS's internal animation parameters"), sampleCount: samples.count,
                validity: sr.dampingRatio == nil ? .notAvailable("No decaying oscillation observed") : .valid, significantDigits: 2, sources: src))
            // Spring fit on normalised width
            let span = sr.final - sr.initial
            if abs(span) > 0.5, let s = stimulus {
                let norm = widths.map { ($0 - sr.initial) / span }
                if let fit = TimeSeries.fitSpring(t: t, normalized: norm, t0: s) {
                    m.append(Measurement(name: "Spring-Damper Fit (natural frequency)", value: fit.omega / (2 * .pi), unit: "Hz", provenance: .estimated,
                        algorithm: "Nelder-Mead fit of a unit-step second-order response to the normalised width", version: v,
                        confidence: fit.r2 > 0.9 ? .medium("R^2 \(Format.number(fit.r2, digits: 3))") : .low("R^2 \(Format.number(fit.r2, digits: 3))"),
                        sampleCount: samples.count, significantDigits: 2, sources: src,
                        notes: "Fitted zeta = \(Format.number(fit.zeta, digits: 2)), delay = \(Format.milliseconds(fit.delay)). A descriptive model of the observed motion, not the system's implementation."))
                }
            }
        }
        let vel = TimeSeries.derivative(t: t, y: samples.map { $0.centroidX ?? 0 })
        let vy = TimeSeries.derivative(t: t, y: samples.map { $0.centroidY ?? 0 })
        let speed = zip(vel, vy).map { ($0 * $0 + $1 * $1).squareRoot() }
        let acc = TimeSeries.derivative(t: t, y: speed)
        if samples.contains(where: { $0.centroidX != nil }) {
            m.append(Measurement(name: "Peak Centroid Velocity", value: speed.max(), unit: "pt/s", provenance: .derived,
                algorithm: "Central difference of the changed-region centroid", version: v, confidence: .low("Centroid of a thresholded difference region"),
                sampleCount: samples.count, significantDigits: 2, sources: src,
                series: [Measurement.Series(label: "speed", xUnit: "s", yUnit: "pt/s", x: t.map { $0 - t[0] }, y: speed)]))
            m.append(Measurement(name: "Peak Centroid Acceleration", value: acc.map { abs($0) }.max(), unit: "pt/s^2", provenance: .derived,
                algorithm: "Second central difference of the centroid", version: v, confidence: .low("Differentiation amplifies frame noise"),
                sampleCount: samples.count, significantDigits: 2, sources: src,
                series: [Measurement.Series(label: "acceleration", xUnit: "s", yUnit: "pt/s^2", x: t.map { $0 - t[0] }, y: acc)]))
        }
        let rel = t.map { $0 - t[0] }
        m.append(Measurement(name: "Motion Time Series", value: Double(samples.count), unit: "frames", provenance: .measured,
            algorithm: "Per-frame luma difference against the first frame (threshold \(Format.number(0.04, digits: 2))) on the canvas crop", version: v,
            confidence: .high("Direct per-frame computation"), sampleCount: samples.count, significantDigits: 4, sources: src,
            notes: "Times are seconds from the first recorded frame (media clock offset \(Format.number(t[0], digits: 9)) s).",
            series: [Measurement.Series(label: "optical change", xUnit: "s", yUnit: "mean |dY|", x: rel, y: samples.map(\.opticalChange)),
                     Measurement.Series(label: "frame delta", xUnit: "s", yUnit: "mean |dY|", x: rel, y: samples.map(\.frameDelta)),
                     Measurement.Series(label: "width", xUnit: "s", yUnit: "pt", x: rel, y: samples.map { $0.bboxWidth ?? .nan }),
                     Measurement.Series(label: "height", xUnit: "s", yUnit: "pt", x: rel, y: samples.map { $0.bboxHeight ?? .nan }),
                     Measurement.Series(label: "centroid x", xUnit: "s", yUnit: "pt", x: rel, y: samples.map { $0.centroidX ?? .nan }),
                     Measurement.Series(label: "centroid y", xUnit: "s", yUnit: "pt", x: rel, y: samples.map { $0.centroidY ?? .nan })]))
        if let s = stimulus, let firstT = t.first, s < firstT {
            warnings.append("The stimulus happened before the first recorded frame; onset times are lower bounds.")
        }
        if medianIv > 1.0 / 50 { warnings.append("Capture interval \(Format.milliseconds(medianIv)) cannot resolve responses shorter than ~\(Format.milliseconds(3 * medianIv)).") }
        return MotionReport(samples: samples, measurements: m, warnings: warnings)
    }

    /// Exact-frame thumbnail for the frame viewer.
    static func frameImage(url: URL, at seconds: Double, maxWidth: CGFloat = 900) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxWidth, height: maxWidth * 3)
        return try? await gen.image(at: CMTime(seconds: seconds, preferredTimescale: 6000)).image
    }
}
