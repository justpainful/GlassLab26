import Foundation
import CoreGraphics

/// Comparisons across experiments: numerical tables, repeatability statistics, multi-background
/// transfer fits and spatially normalised image pairs.
enum ComparisonEngine {

    struct Row: Identifiable, Hashable {
        var id: String { name }
        var name: String
        var unit: String
        var a: Measurement?
        var b: Measurement?
        var delta: Double? {
            guard let x = a?.value, let y = b?.value else { return nil }
            return y - x
        }
        var relative: Double? {
            guard let x = a?.value, let d = delta, abs(x) > 1e-12 else { return nil }
            return d / abs(x)
        }
    }

    static func table(_ a: Experiment, _ b: Experiment) -> [Row] {
        let ma = a.latestAnalysis?.measurements ?? [], mb = b.latestAnalysis?.measurements ?? []
        var names: [String] = []
        for m in ma + mb where !names.contains(m.name) { names.append(m.name) }
        return names.map { n in
            let x = ma.first { $0.name == n }, y = mb.first { $0.name == n }
            return Row(name: n, unit: x?.unit ?? y?.unit ?? "", a: x, b: y)
        }
    }

    /// Describes the configuration differences between two experiments.
    static func configurationDiff(_ a: Experiment, _ b: Experiment) -> [(String, String, String)] {
        var out: [(String, String, String)] = []
        func add(_ k: String, _ x: String, _ y: String) { if x != y { out.append((k, x, y)) } }
        let ca = a.configuration, cb = b.configuration
        add("Subject", ca.subject.rawValue, cb.subject.rawValue)
        add("Framework", ca.effectiveFramework.rawValue, cb.effectiveFramework.rawValue)
        add("Variant", ca.variant.rawValue, cb.variant.rawValue)
        add("Shape", ca.shape.rawValue, cb.shape.rawValue)
        add("Size (pt)", "\(Int(ca.geometry.width))x\(Int(ca.geometry.height))", "\(Int(cb.geometry.width))x\(Int(cb.geometry.height))")
        add("Tint", ca.tint?.hex ?? "none", cb.tint?.hex ?? "none")
        add("Interactive", "\(ca.interactive)", "\(cb.interactive)")
        add("Background", ca.background.summary, cb.background.summary)
        add("Appearance", ca.appearance.rawValue, cb.appearance.rawValue)
        add("Capture", ca.captureMethod.rawValue, cb.captureMethod.rawValue)
        add("Device", a.environment.deviceLine, b.environment.deviceLine)
        add("Reduce Transparency", "\(a.environment.reduceTransparency)", "\(b.environment.reduceTransparency)")
        add("Increase Contrast", "\(a.environment.increaseContrast)", "\(b.environment.increaseContrast)")
        add("Interface Style", a.environment.interfaceStyle, b.environment.interfaceStyle)
        return out
    }

    // MARK: Repeatability

    /// Summary statistics of every measurement shared by a group of repeated experiments.
    static func repeatability(_ experiments: [Experiment]) -> [Measurement] {
        let runs = experiments.compactMap { $0.latestAnalysis }
        guard runs.count >= 2 else { return [] }
        var names: [String] = []
        for r in runs { for m in r.measurements where !names.contains(m.name) { names.append(m.name) } }
        var out: [Measurement] = []
        for n in names {
            let ms = runs.compactMap { r in r.measurements.first { $0.name == n } }
            let vals = ms.compactMap(\.value)
            guard vals.count >= 2, let proto = ms.first else { continue }
            let s = Statistics.summary(vals)
            let outliers = Statistics.outlierIndices(vals)
            var notes = "n=\(s.count), median \(Format.number(s.median, digits: proto.significantDigits)), SD \(Format.number(s.standardDeviation, digits: 2)), range \(Format.number(s.min, digits: proto.significantDigits))...\(Format.number(s.max, digits: proto.significantDigits))."
            if !outliers.isEmpty { notes += " Outliers (modified z > 3.5) at repetitions \(outliers.map { String($0 + 1) }.joined(separator: ", "))." }
            let cv = abs(s.mean) > 1e-12 ? s.standardDeviation / abs(s.mean) : .nan
            let conf: Confidence = cv < 0.05 ? .high("Coefficient of variation \(Format.number(cv * 100, digits: 2))%")
                : (cv < 0.15 ? .medium("CV \(Format.number(cv * 100, digits: 2))%") : .low("CV \(Format.number(cv * 100, digits: 2))%: unstable across repetitions"))
            out.append(Measurement(name: n + " (repeatability mean)", value: s.mean, unit: proto.unit, provenance: .derived,
                algorithm: "Mean of repeated measurements; 95% CI from Student t", version: proto.algorithmVersion,
                confidence: conf, uncertainty: s.ci95HalfWidth.map { Uncertainty(halfWidth: $0, kind: .confidenceInterval95) },
                sampleCount: s.count, validity: outliers.isEmpty ? .valid : .warning("\(outliers.count) outlier(s)"),
                significantDigits: proto.significantDigits, sources: experiments.map { $0.id.uuidString }, notes: notes))
        }
        return out
    }

    // MARK: Multi-background transfer

    /// Fits T_c = a_c * R_c + b_c per channel using the interior means of experiments that share subject,
    /// variant, geometry and appearance but use different solid backgrounds.
    static func transferFit(_ experiments: [Experiment], store: DataStore, sessionID: UUID) async -> [Measurement] {
        struct Pair { var r: (Double, Double, Double); var t: (Double, Double, Double); var name: String }
        var pairs: [Pair] = []
        for e in experiments where e.configuration.background.kind == .solid {
            guard let rf = e.referenceFrames.last, let tf = e.resultFrames.last else { continue }
            let ru = await store.url(for: rf, in: sessionID), tu = await store.url(for: tf, in: sessionID)
            let region = await CaptureCoordinator.regionModel(for: e, pixelsPerPoint: tf.pixelsPerPoint)
            let ppp = tf.pixelsPerPoint
            let result: Pair? = await Task.detached {
                guard let r = LinearImage.load(url: ru), let t = LinearImage.load(url: tu) else { return nil }
                let m = region.masks(width: r.width, height: r.height, innerMargin: 8 * ppp, edgeInner: 0, edgeOuter: 0, surroundGap: 0, surroundWidth: 0).interior
                guard m.count > 50 else { return nil }
                return Pair(r: (r.r.mean(in: m), r.g.mean(in: m), r.b.mean(in: m)), t: (t.r.mean(in: m), t.g.mean(in: m), t.b.mean(in: m)),
                            name: e.configuration.background.primary.hex)
            }.value
            if let result { pairs.append(result) }
        }
        let v = AlgorithmVersion.multiBackground
        let alg = "Per-channel least squares T = a*R + b over interior means of solid-background experiments (linear Display P3)"
        guard Set(pairs.map(\.name)).count >= 2 else {
            return [.unavailable("Effective Background Transmission (multi-background)", unit: "", algorithm: alg, version: v,
                                 reason: "Needs at least two experiments with different solid backgrounds and otherwise identical settings.")]
        }
        var out: [Measurement] = []
        for (ci, cname) in ["R", "G", "B"].enumerated() {
            let xs = pairs.map { [$0.r.0, $0.r.1, $0.r.2][ci] }, ys = pairs.map { [$0.t.0, $0.t.1, $0.t.2][ci] }
            guard let fit = Statistics.linearFit(x: xs, y: ys) else { continue }
            let residuals = zip(xs, ys).map { $1 - (fit.intercept + fit.slope * $0) }
            let rmse = (residuals.reduce(0) { $0 + $1 * $1 } / Double(residuals.count)).squareRoot()
            let n = pairs.count
            let conf: Confidence = n == 2 ? .low("Two backgrounds: exact fit, residual cannot test linearity")
                : (fit.r2 > 0.99 ? .medium("R^2 \(Format.number(fit.r2, digits: 4)) over \(n) backgrounds") : .low("R^2 \(Format.number(fit.r2, digits: 3)): response is not linear in the background (adaptive material)"))
            out.append(Measurement(name: "Effective Background Transmission a (\(cname), multi-background)", value: fit.slope, unit: "", provenance: .estimated,
                algorithm: alg, version: v, confidence: conf, sampleCount: n, validity: n == 2 ? .warning("Only two backgrounds") : .valid, significantDigits: 3,
                sources: experiments.map { $0.id.uuidString },
                notes: "Model residual RMSE \(Format.number(rmse, digits: 2)). Not Apple's internal alpha: an effective linear description of the composite.",
                series: [Measurement.Series(label: "T vs R", xUnit: "linear R", yUnit: "linear T", x: xs, y: ys)]))
            out.append(Measurement(name: "Effective Additive Term b (\(cname), multi-background)", value: fit.intercept, unit: "linear", provenance: .estimated,
                algorithm: alg, version: v, confidence: conf, sampleCount: n, significantDigits: 3, sources: experiments.map { $0.id.uuidString }))
        }
        return out
    }

    // MARK: Spatial normalisation

    /// Resamples two images to the smaller pixels-per-point density so they can be compared point for point.
    static func normalize(_ a: LinearImage, pppA: Double, _ b: LinearImage, pppB: Double) -> (LinearImage, LinearImage, Double, String) {
        if abs(pppA - pppB) < 1e-6 { return (a, b, pppA, "Same pixel density (\(Format.number(pppA, digits: 3)) px/pt); no resampling.") }
        let target = min(pppA, pppB)
        func resample(_ img: LinearImage, _ from: Double) -> LinearImage {
            let k = target / from
            let w = max(1, Int(Double(img.width) * k)), h = max(1, Int(Double(img.height) * k))
            func plane(_ p: Plane) -> Plane {
                var o = Plane(width: w, height: h)
                // Area-average then bilinear: pre-blur to avoid aliasing when shrinking.
                let src = p.gaussianBlurred(sigma: max(0, 0.5 / k - 0.5))
                for y in 0..<h { for x in 0..<w { o[x, y] = src.sample((Double(x) + 0.5) / k - 0.5, (Double(y) + 0.5) / k - 0.5) } }
                return o
            }
            return LinearImage(r: plane(img.r), g: plane(img.g), b: plane(img.b), sourceColorSpace: img.sourceColorSpace)
        }
        let ra = pppA == target ? a : resample(a, pppA)
        let rb = pppB == target ? b : resample(b, pppB)
        let w = min(ra.width, rb.width), h = min(ra.height, rb.height)
        let crop = PixelRegion(x: 0, y: 0, width: w, height: h)
        return (ra.cropped(crop), rb.cropped(crop), target,
                "Resampled to \(Format.number(target, digits: 3)) px/pt (Gaussian pre-filter + bilinear), cropped to the common \(w)x\(h) px area from the top-left canvas corner.")
    }
}
