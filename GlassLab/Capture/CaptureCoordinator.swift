import UIKit
import QuartzCore
import Observation

/// A canvas-sized capture with everything needed to interpret its pixels.
struct CanvasCapture: @unchecked Sendable {
    var image: CGImage
    var crop: PixelRegion
    var pixelsPerPoint: Double
    var mediaTime: Double
    var method: CaptureMethod
    var notes: [String]
}

struct CaptureValidationResult: Codable, Hashable, Sendable {
    var method: CaptureMethod
    var machine: String
    var systemVersion: String
    var date: Date
    var passed: Bool
    /// Mean |dY| inside the glass between material off/on.
    var glassSignal: Double
    /// Mean |dY| in the background ring between the same frames.
    var surroundNoise: Double
    var pixelScaleOK: Bool
    var colorSpace: String
    var notes: [String]
}

/// Runs acquisition protocols against the live experiment canvas.
@MainActor
@Observable
final class CaptureCoordinator {
    let stage: StageState
    let probe: CanvasProbe
    let replay = ReplayKitCapture()

    var isBusy = false
    var status: String = ""
    /// Shown full-screen over the canvas when the operator must act (e.g. take a screenshot).
    var operatorInstruction: String?
    var lastError: String?
    private(set) var validations: [String: CaptureValidationResult] = [:]

    init(stage: StageState, probe: CanvasProbe) {
        self.stage = stage
        self.probe = probe
        if let data = UserDefaults.standard.data(forKey: "captureValidations"),
           let v = try? JSONDecoder().decode([String: CaptureValidationResult].self, from: data) { validations = v }
    }

    // MARK: Validation registry

    static func validationKey(_ m: CaptureMethod) -> String {
        "\(m.rawValue)|\(UIDevice.current.systemVersion)|\(DeviceEnvironmentMonitor.snapshot().machineIdentifier)"
    }

    func validation(for m: CaptureMethod) -> CaptureValidationResult? { validations[Self.validationKey(m)] }

    private func storeValidation(_ r: CaptureValidationResult) {
        validations[Self.validationKey(r.method)] = r
        if let d = try? JSONEncoder().encode(validations) { UserDefaults.standard.set(d, forKey: "captureValidations") }
    }

    // MARK: Primitive captures

    /// Renders the window with `drawHierarchy(afterScreenUpdates: true)` into an 8-bit Display P3 bitmap and crops the canvas.
    func snapshotCanvas() throws -> CanvasCapture {
        guard let window = probe.window else { throw GlassLabError.captureFailed("canvas is not on screen") }
        let scale = window.traitCollection.displayScale
        let bounds = window.bounds
        let w = Int((bounds.width * scale).rounded()), h = Int((bounds.height * scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw GlassLabError.captureFailed("could not allocate a \(w)x\(h) bitmap")
        }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(ctx)
        let ok = window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        UIGraphicsPopContext()
        let t = CACurrentMediaTime()
        guard ok, let full = ctx.makeImage() else { throw GlassLabError.captureFailed("drawHierarchy returned no image") }
        let r = probe.frameInWindow
        let crop = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale).integral
        guard let img = full.cropping(to: crop) else { throw GlassLabError.captureFailed("canvas crop failed") }
        return CanvasCapture(image: img, crop: PixelRegion(crop), pixelsPerPoint: scale, mediaTime: t, method: .viewSnapshot,
                             notes: ["UIWindow.drawHierarchy(afterScreenUpdates: true) into 8-bit Display P3; lossless PNG storage.",
                                     "Whether this path includes the full system glass composite is checked by Capture Validation."])
    }

    /// Captures the next ReplayKit frame presented after `after` (host clock) and crops the canvas.
    func replayKitCanvas(after: Double) async throws -> CanvasCapture {
        if !replay.isCapturing { try await replay.start() }
        guard let window = probe.window, let screen = window.windowScene?.screen else { throw GlassLabError.captureFailed("canvas is not on screen") }
        let f = try await replay.frame(after: after, timeout: 1.0)
        let bounds = window.bounds
        guard abs(bounds.width - screen.bounds.width) < 1, abs(bounds.height - screen.bounds.height) < 1 else {
            throw GlassLabError.unsupported("ReplayKit frames map to the full screen; the app window is not full screen (Split View / Stage Manager). Use View Snapshot or System Screenshot.")
        }
        let sx = Double(f.width) / bounds.width, sy = Double(f.height) / bounds.height
        guard abs(sx - sy) / sx < 0.02 else {
            throw GlassLabError.unsupported("ReplayKit buffer \(f.width)x\(f.height) does not match the window aspect \(Int(bounds.width))x\(Int(bounds.height)) pt (orientation mismatch). Capture in the orientation ReplayKit reports.")
        }
        var notes = ["ReplayKit startCapture buffer \(f.width)x\(f.height), pixel format \(ReplayKitCapture.formatName(f.pixelFormat)).",
                     "Converted YCbCr -> Display P3 RGB with Core Image; chroma is subsampled 4:2:0 by the source."]
        if f.time < after { notes.append("No new frame after the scene change; the latest frame (presented \(Format.milliseconds(after - f.time)) earlier) was used.") }
        let r = probe.frameInWindow
        let crop = CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy).integral
        guard let img = replay.cgImage(f, crop: crop) else { throw GlassLabError.captureFailed("frame conversion failed") }
        return CanvasCapture(image: img, crop: PixelRegion(crop), pixelsPerPoint: sx, mediaTime: f.time, method: .replayKit, notes: notes)
    }

    func capture(_ method: CaptureMethod, after: Double) async throws -> CanvasCapture {
        switch method {
        case .viewSnapshot: return try snapshotCanvas()
        case .replayKit: return try await replayKitCanvas(after: after)
        case .systemScreenshot: return try await screenshotCanvas()
        case .imported: throw GlassLabError.unsupported("Imported frames are added from the Sessions screen.")
        }
    }

    func screenshotCanvas() async throws -> CanvasCapture {
        guard let window = probe.window else { throw GlassLabError.captureFailed("canvas is not on screen") }
        let (img, data, taken) = try await ScreenshotIngest.nextScreenshot()
        operatorInstruction = nil
        let sx = Double(img.width) / window.bounds.width
        let r = probe.frameInWindow
        let crop = CGRect(x: r.minX * sx, y: r.minY * sx, width: r.width * sx, height: r.height * sx).integral
        guard let c = img.cropping(to: crop) else { throw GlassLabError.captureFailed("screenshot crop failed") }
        return CanvasCapture(image: c, crop: PixelRegion(crop), pixelsPerPoint: sx, mediaTime: CACurrentMediaTime(), method: .systemScreenshot,
                             notes: ["System screenshot (\(img.width)x\(img.height), \(data.count) bytes, profile \((img.colorSpace?.name as String?) ?? "untagged")) taken \(Format.timestamp.string(from: taken)).",
                                     "Lossless PNG from the system compositor; cropped without resampling."])
    }

    // MARK: Settle detection

    /// Captures until two consecutive frames differ by less than `threshold` (mean |dY|, encoded 0-1)
    /// or `maxWait` elapses. System screenshots are taken once (the operator controls timing).
    func settledCapture(_ method: CaptureMethod, changeTime: Double, minWaitMs: Double, maxWait: Double = 3,
                        threshold: Double = 0.0015) async throws -> (CanvasCapture, residual: Double?, waitedMs: Double) {
        if method == .systemScreenshot {
            let c = try await capture(method, after: changeTime)
            return (c, nil, (CACurrentMediaTime() - changeTime) * 1000)
        }
        try await Task.sleep(for: .milliseconds(Int(minWaitMs)))
        var previous = try await capture(method, after: changeTime + minWaitMs / 1000)
        var residual: Double = .infinity
        while CACurrentMediaTime() - changeTime < maxWait {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(90))
            let next = try await capture(method, after: CACurrentMediaTime() - 0.02)
            residual = Self.meanAbsDifference(previous.image, next.image) ?? .infinity
            previous = next
            if residual < threshold { break }
        }
        return (previous, residual.isFinite ? residual : nil, (CACurrentMediaTime() - changeTime) * 1000)
    }

    /// Mean absolute luma difference of two images, computed on 160 px wide thumbnails.
    nonisolated static func meanAbsDifference(_ a: CGImage, _ b: CGImage) -> Double? {
        func thumb(_ i: CGImage) -> [UInt8]? {
            let w = 160, h = max(1, Int(Double(i.height) * 160 / Double(max(1, i.width))))
            var buf = [UInt8](repeating: 0, count: w * h)
            let ok: Bool = buf.withUnsafeMutableBytes { raw in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                ctx.interpolationQuality = .medium
                ctx.draw(i, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            return ok ? buf : nil
        }
        guard let x = thumb(a), let y = thumb(b), x.count == y.count, !x.isEmpty else { return nil }
        var s = 0
        for i in x.indices { s += abs(Int(x[i]) - Int(y[i])) }
        return Double(s) / Double(x.count) / 255
    }

    // MARK: Acquisition protocol

    /// Reference / test acquisition (Optics protocol 9.1):
    /// 1 freeze the background phase, 2 render the reference (no material), 3 wait until stable and capture,
    /// 4 enable native glass, 5 wait until stable and capture, 6 record geometry, environment and pipeline facts.
    func acquire(store: DataStore, environment: EnvironmentSnapshot, sessionID: UUID, repetition: Int = 0, matrixCase: UUID? = nil) async throws -> Experiment {
        guard !isBusy else { throw GlassLabError.captureFailed("another acquisition is running") }
        isBusy = true; lastError = nil
        defer { isBusy = false; status = ""; operatorInstruction = nil; stage.forcedPhase = nil; stage.materialOn = true }
        let config = stage.config
        let method = config.captureMethod
        guard probe.window != nil, probe.canvasSize.width > 10 else { throw GlassLabError.captureFailed("open the canvas before acquiring") }

        var notes: [String] = []
        stage.forcedPhase = config.background.frozenPhase
        if config.background.kind.isAnimated {
            notes.append("Animated background frozen at phase \(Format.number(config.background.frozenPhase, digits: 3)) for both frames.")
        }

        // Reference
        status = "Reference: settling"
        stage.materialOn = false
        if method == .systemScreenshot { operatorInstruction = "Take a screenshot now (side button + volume up).\nREFERENCE frame: glass material off." }
        var t0 = CACurrentMediaTime()
        let ref = try await settledCapture(method, changeTime: t0, minWaitMs: config.settleMilliseconds)
        let dir = store.directory(for: sessionID).appendingPathComponent("frames")
        let stamp = Format.fileStamp.string(from: Date())
        let refRecord = try FrameWriter.write(ref.0.image, to: dir.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8))-ref.png"),
                                              role: .reference, method: method, pixelsPerPoint: ref.0.pixelsPerPoint, mediaTime: ref.0.mediaTime,
                                              crop: ref.0.crop, notes: ref.0.notes, settleResidual: ref.residual, settleMs: ref.waitedMs)

        // Test
        status = "Native glass: settling"
        stage.materialOn = true
        if method == .systemScreenshot { operatorInstruction = "Take a screenshot now (side button + volume up).\nTEST frame: native glass on." }
        t0 = CACurrentMediaTime()
        let test = try await settledCapture(method, changeTime: t0, minWaitMs: config.settleMilliseconds)
        let testRecord = try FrameWriter.write(test.0.image, to: dir.appendingPathComponent("\(stamp)-\(UUID().uuidString.prefix(8))-test.png"),
                                               role: .test, method: method, pixelsPerPoint: test.0.pixelsPerPoint, mediaTime: test.0.mediaTime,
                                               crop: test.0.crop, notes: test.0.notes, settleResidual: test.residual, settleMs: test.waitedMs)

        var exp = Experiment(configuration: config, environment: environment,
                             canvasSizePoints: CGSizeCodable(probe.canvasSize), subjectFramePoints: CGRectCodable(probe.subjectFrame))
        exp.elementFramesPoints = probe.orderedElementFrames.map(CGRectCodable.init)
        exp.referenceFrames = [refRecord]
        exp.resultFrames = [testRecord]
        exp.repetitionIndex = repetition
        exp.matrixCaseID = matrixCase
        exp.notes = (notes + [config.notes]).filter { !$0.isEmpty }.joined(separator: "\n")

        var reasons: [String] = []
        var vstatus: ValidityStatus = .valid
        if ref.0.image.width != test.0.image.width || ref.0.image.height != test.0.image.height {
            vstatus = .invalid; reasons.append("Reference and test crops differ in size.")
        }
        for (name, r) in [("Reference", ref.residual), ("Test", test.residual)] {
            if let r, r >= 0.0015 { vstatus = vstatus == .invalid ? .invalid : .warning; reasons.append("\(name) frame did not settle (residual \(Format.number(r, digits: 2))).") }
        }
        if let v = validation(for: method) {
            if !v.passed { vstatus = .invalid; reasons.append("\(method.rawValue) failed capture validation on this device/OS: glass not reliably captured.") }
        } else if method != .systemScreenshot {
            if vstatus == .valid { vstatus = .warning }
            reasons.append("\(method.rawValue) has not been validated on this device/OS. Run Capture Validation.")
        }
        if exp.elementFramesPoints.isEmpty { vstatus = .invalid; reasons.append("Subject frame was not reported by the canvas.") }
        exp.validity = Validity(status: vstatus, reasons: reasons)
        store.upsert(experiment: exp, in: sessionID)
        return exp
    }

    /// Region model of an experiment in its frame pixels.
    static func regionModel(for exp: Experiment, pixelsPerPoint ppp: Double) -> GlassRegionModel {
        let shape: GlassShapeKind
        switch exp.configuration.subject {
        case .glassSurface, .glassGroup:
            shape = exp.configuration.effectiveFramework == .uiKit && (exp.configuration.shape == .ellipse || exp.configuration.shape == .customStar)
                ? .capsule : exp.configuration.shape
        case .glassButton, .glassProminentButton, .glassClearButton:
            switch exp.configuration.shape {
            case .circle: shape = .circle
            case .roundedRect: shape = .roundedRect
            case .rect: shape = .rect
            default: shape = .capsule
            }
        case .uikitNavigationBar, .uikitToolbar, .uikitTabBar: shape = .rect
        default: shape = .capsule
        }
        let frames = exp.elementFramesPoints.isEmpty ? [exp.subjectFramePoints] : exp.elementFramesPoints
        let rotates = exp.configuration.subject == .glassSurface || exp.configuration.subject == .glassGroup
        return GlassRegionModel(shape: shape,
                                elements: frames.map { CGRectCodable(CGRect(x: $0.x * ppp, y: $0.y * ppp, width: $0.width * ppp, height: $0.height * ppp)) },
                                cornerRadiusPx: exp.configuration.geometry.cornerRadius * exp.configuration.geometry.scale * ppp,
                                rotationDegrees: rotates ? exp.configuration.geometry.rotation : 0)
    }

    // MARK: Capture validation

    /// Checks that a capture method actually records the native glass: renders a fixed scene, captures
    /// material off/on, and requires a glass-region difference well above the background-ring noise.
    func validate(_ method: CaptureMethod) async -> CaptureValidationResult {
        let saved = stage.config
        var c = SceneConfiguration()
        c.subject = .glassSurface; c.variant = .regular; c.shape = .capsule
        c.geometry.width = 240; c.geometry.height = 96
        c.background = .pattern(.randomDots, scale: 10)
        c.referenceMode = .identityGlass
        stage.config = c
        stage.generation += 1
        var notes: [String] = []
        var result = CaptureValidationResult(method: method, machine: DeviceEnvironmentMonitor.snapshot().machineIdentifier,
                                             systemVersion: UIDevice.current.systemVersion, date: Date(), passed: false,
                                             glassSignal: .nan, surroundNoise: .nan, pixelScaleOK: false, colorSpace: "", notes: [])
        defer { stage.config = saved; stage.generation += 1; stage.materialOn = true }
        do {
            try await Task.sleep(for: .milliseconds(500))
            stage.materialOn = false
            if method == .systemScreenshot { operatorInstruction = "Validation 1/2: take a screenshot now (glass off)." }
            let off = try await settledCapture(method, changeTime: CACurrentMediaTime(), minWaitMs: 500)
            stage.materialOn = true
            if method == .systemScreenshot { operatorInstruction = "Validation 2/2: take a screenshot now (glass on)." }
            let on = try await settledCapture(method, changeTime: CACurrentMediaTime(), minWaitMs: 500)
            operatorInstruction = nil
            guard let a = LinearImage(cgImage: off.0.image), let b = LinearImage(cgImage: on.0.image), a.width == b.width, a.height == b.height else {
                throw GlassLabError.captureFailed("validation frames could not be decoded or differ in size")
            }
            let ppp = on.0.pixelsPerPoint
            let frames = probe.orderedElementFrames
            let model = GlassRegionModel(shape: .capsule, elements: frames.map { CGRectCodable(CGRect(x: $0.minX * ppp, y: $0.minY * ppp, width: $0.width * ppp, height: $0.height * ppp)) },
                                         cornerRadiusPx: 0, rotationDegrees: 0)
            let m = model.masks(width: a.width, height: a.height, innerMargin: 4 * ppp, edgeInner: 0, edgeOuter: 0, surroundGap: 8 * ppp, surroundWidth: 12 * ppp)
            let ya = a.luminance(), yb = b.luminance()
            let d = yb - ya
            var absd = d; for i in absd.data.indices { absd.data[i] = abs(d.data[i]) }
            result.glassSignal = absd.mean(in: m.interior)
            result.surroundNoise = absd.mean(in: m.surround)
            let expectedW = probe.frameInWindow.width * ppp
            result.pixelScaleOK = abs(Double(on.0.image.width) - expectedW) <= 2
            result.colorSpace = (on.0.image.colorSpace?.name as String?) ?? "untagged"
            notes.append("Glass signal \(Format.number(result.glassSignal, digits: 3)) vs surround noise \(Format.number(result.surroundNoise, digits: 2)) (mean |dY|).")
            notes.append("Pixel scale \(Format.number(ppp, digits: 4)) px/pt; crop width \(on.0.image.width) px vs expected \(Format.number(expectedW, digits: 5)).")
            if method == .replayKit, let delay = replay.medianArrivalDelay {
                notes.append("Timestamp check: median ReplayKit delivery delay \(Format.milliseconds(delay)) after presentation.")
            }
            result.passed = result.glassSignal.isFinite && result.glassSignal > max(0.01, 5 * result.surroundNoise) && result.pixelScaleOK
            if !result.passed { notes.append("FAILED: the glass is not clearly present in captured frames, or pixel scale mismatched. Measurements with this method are rejected.") }
        } catch {
            notes.append("Validation could not run: \(error.localizedDescription)")
            operatorInstruction = nil
        }
        result.notes = notes
        storeValidation(result)
        return result
    }
}
