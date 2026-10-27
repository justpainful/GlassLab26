import Foundation
import CoreGraphics

struct DerivedImage: @unchecked Sendable {
    var name: String
    var image: CGImage
    var legend: Heatmap.Legend?
    var note: String
}

/// Inputs to one optical analysis: a reference frame (no glass material) and a test frame (native glass),
/// both cropped to the experiment canvas and geometrically identical apart from the glass.
struct OpticalInput: @unchecked Sendable {
    var reference: LinearImage
    var test: LinearImage
    /// Glass geometry in capture pixels of these images.
    var region: GlassRegionModel
    var pixelsPerPoint: Double
    var background: BackgroundSpec
    var modules: Set<MeasurementModule>
    var sources: [String]
    /// Upper bound for displacement search (capture pixels).
    var maxDisplacementPx: Double = 36
}

struct OpticalReport: @unchecked Sendable {
    var measurements: [Measurement] = []
    var images: [DerivedImage] = []
    var vectors: [DisplacementVector] = []
    var log: [String] = []
    var validity: Validity = .valid
    var analysisScale: Int = 1
}

/// Optical analysis of native Liquid Glass captures. Every number it produces is computed from the
/// supplied pixels; when a quantity cannot be determined the measurement is returned as N/A with a reason.
enum OpticalAnalyzer {

    static func analyze(_ input: OpticalInput) throws -> OpticalReport {
        var rep = OpticalReport()
        let ref0 = input.reference, test0 = input.test
        guard ref0.width == test0.width, ref0.height == test0.height else {
            rep.validity = .invalid("Reference and test frames have different pixel sizes (\(ref0.width)x\(ref0.height) vs \(test0.width)x\(test0.height)).")
            return rep
        }
        try ResourceGuard.check(estimatedBytes: UInt64(ref0.width * ref0.height * 4 * 20))
        let ppp = input.pixelsPerPoint
        let src = input.sources

        // ---- Region of interest around the glass (capture pixels) ----
        let bbox = input.region.boundingBox
        let margin = max(24.0, 12 * ppp)
        let roiRect = bbox.insetBy(dx: -margin, dy: -margin).intersection(CGRect(x: 0, y: 0, width: ref0.width, height: ref0.height)).integral
        guard roiRect.width > 8, roiRect.height > 8 else {
            rep.validity = .invalid("Glass region lies outside the captured frame.")
            return rep
        }
        let roi = PixelRegion(roiRect)
        var ref = ref0.cropped(roi), test = test0.cropped(roi)
        var region = input.region.translated(dx: -Double(roi.x), dy: -Double(roi.y))

        // Downsample very large regions; all lengths are converted back to capture pixels.
        let maxSide = max(ref.width, ref.height)
        let f = maxSide > 900 ? 3 : (maxSide > 600 ? 2 : 1)
        if f > 1 {
            ref = ref.downsampled(by: f); test = test.downsampled(by: f)
            region = region.scaled(by: 1 / Double(f))
            rep.log.append("Analysis performed at 1/\(f) resolution (box-averaged); lengths converted back to capture pixels.")
        }
        rep.analysisScale = f
        let pxScale = Double(f)                 // analysis px -> capture px
        let ptPerAnalysisPx = pxScale / ppp      // analysis px -> points

        let edgeInnerPx = max(4.0, 6 * ppp / pxScale)
        let masks = region.masks(width: ref.width, height: ref.height,
                                 innerMargin: max(3, 4 * ppp / pxScale), edgeInner: edgeInnerPx, edgeOuter: max(3, 3 * ppp / pxScale),
                                 surroundGap: max(4, 6 * ppp / pxScale), surroundWidth: max(6, 8 * ppp / pxScale))
        guard masks.interior.count >= 20 else {
            rep.validity = .invalid("Glass interior is too small to analyse at this resolution.")
            return rep
        }

        // ---- Registration check on the surround ring ----
        let yRef0 = ref.luminance(), yTest0 = test.luminance()
        let reg = registration(yRef0, yTest0, mask: masks.surround, search: 4)
        if reg.dx != 0 || reg.dy != 0 {
            rep.log.append("Registration: applied integer shift (\(reg.dx), \(reg.dy)) px to the reference to align the surround ring.")
            ref = ref.shifted(dx: reg.dx, dy: reg.dy)
        }
        let yRef = (reg.dx != 0 || reg.dy != 0) ? ref.luminance() : yRef0
        let yTest = yTest0
        let surroundResidual = reg.residual
        let surroundLevel = max(yRef.mean(in: masks.surround), 1e-4)
        let surroundRelative = surroundResidual / surroundLevel
        var regValidity: Validity = .valid
        if surroundRelative > 0.05 {
            regValidity = .warning("Background outside the glass differs by \(Format.number(surroundRelative * 100, digits: 2))% between frames: the frames may not be temporally or geometrically matched.")
            rep.validity = regValidity
        }
        rep.measurements.append(Measurement(name: "Surround Residual (registration check)", value: surroundResidual, unit: "rel. luminance",
            provenance: .measured, algorithm: "Mean |Y_test - Y_ref| in the background ring after integer alignment", version: AlgorithmVersion.registration,
            confidence: surroundRelative < 0.01 ? .high("Surround matches within 1%") : .medium("Surround differs; see validity"),
            sampleCount: masks.surround.count, region: roi, validity: regValidity, significantDigits: 2, sources: src))

        let interior = masks.interior
        let nInt = interior.count

        // ---- Image statistics ----
        if input.modules.contains(.statistics) || input.modules.contains(.translucency) {
            let mT = yTest.mean(in: interior), mR = yRef.mean(in: interior)
            let sT = yTest.std(in: interior), sR = yRef.std(in: interior)
            let quant = 1.0 / 255.0 / 12.92 / Double(nInt).squareRoot()
            rep.measurements.append(Measurement(name: "Mean Relative Luminance (glass interior)", value: mT, unit: "Y",
                provenance: .measured, algorithm: "Mean CIE Y of linear Display P3 pixels inside the glass interior mask", version: AlgorithmVersion.imageStatistics,
                confidence: .high("Direct pixel average over \(nInt) samples"), uncertainty: Uncertainty(halfWidth: sT / Double(nInt).squareRoot(), kind: .standardError),
                sampleCount: nInt, region: roi, significantDigits: 3, sources: src,
                notes: "Relative digital luminance (0 = black, 1 = display white). Not photometric nits."))
            rep.measurements.append(Measurement(name: "Mean Relative Luminance (reference, same region)", value: mR, unit: "Y",
                provenance: .measured, algorithm: "Mean CIE Y of the reference frame inside the same mask", version: AlgorithmVersion.imageStatistics,
                confidence: .high("Direct pixel average"), uncertainty: Uncertainty(halfWidth: max(quant, sR / Double(nInt).squareRoot()), kind: .standardError),
                sampleCount: nInt, region: roi, significantDigits: 3, sources: src))
            rep.measurements.append(Measurement(name: "Luminance Std. Deviation (glass interior)", value: sT, unit: "Y",
                provenance: .measured, algorithm: "Sample standard deviation of Y inside the interior mask", version: AlgorithmVersion.imageStatistics,
                confidence: .high("Direct pixel statistic"), sampleCount: nInt, region: roi, significantDigits: 3, sources: src))
            rep.measurements.append(Measurement(name: "Local Luminance Difference", value: mT - mR, unit: "Y",
                provenance: .derived, algorithm: "Mean Y(test) - mean Y(reference) inside the interior", version: AlgorithmVersion.imageStatistics,
                confidence: .high("Difference of two direct averages"), sampleCount: nInt, region: roi, significantDigits: 2, sources: src))
            let yVals = yTest.values(in: interior)
            let hist = Statistics.histogram(yVals, bins: 64, range: 0...1)
            var m = Measurement(name: "Luminance Histogram (glass interior)", value: Statistics.median(yVals), unit: "Y (median)",
                provenance: .measured, algorithm: "64-bin histogram of Y", version: AlgorithmVersion.imageStatistics,
                confidence: .high("Direct pixel statistic"), sampleCount: nInt, region: roi, significantDigits: 3, sources: src)
            m.series = [Measurement.Series(label: "count", xUnit: "Y", yUnit: "pixels",
                                           x: (0..<64).map { (Double($0) + 0.5) / 64 }, y: hist.map(Double.init))]
            rep.measurements.append(m)
        }

        // ---- Blur model fit: T ~ g * (G_sigma * R) + o ----
        let refTexture = yRef.std(in: interior)
        let textured = refTexture > 0.004
        var blurSigma: Double? = nil
        var blurFit: (gain: Double, offset: Double, rmse: Double, r2: Double, n: Int)? = nil
        if input.modules.contains(.blur) || input.modules.contains(.translucency) || input.modules.contains(.refraction) || input.modules.contains(.highlights) {
            if textured {
                let result = fitBlur(yRef, yTest, mask: interior)
                blurSigma = result.sigma
                blurFit = result.fit
                if let fit = result.fit {
                    let sigmaCapture = result.sigma * pxScale
                    let interval = (result.interval.upperBound - result.interval.lowerBound) / 2 * pxScale
                    let adequate = fit.r2 >= 0.9
                    let conf: Confidence = adequate
                        ? (fit.r2 > 0.97 ? .high("Gaussian+affine model explains \(Format.number(fit.r2 * 100, digits: 3))% of interior variance") : .medium("Model R^2 = \(Format.number(fit.r2, digits: 3))"))
                        : .low("Model R^2 = \(Format.number(fit.r2, digits: 3)); the material is not well described by a single isotropic Gaussian")
                    var validity: Validity = adequate ? .valid : .warning("Single-Gaussian assumption is inadequate for this capture (R^2 < 0.9).")
                    if result.atBound { validity = .warning("Best sigma is at the search bound; true apparent blur may be larger.") }
                    rep.measurements.append(Measurement(name: "Apparent Blur Radius (Gaussian sigma)", value: sigmaCapture / ppp, unit: "pt",
                        provenance: .estimated, algorithm: "Grid + golden-section search of sigma minimising RMSE of T ~ g*(G_sigma*R)+o over the interior", version: AlgorithmVersion.blurFit,
                        confidence: conf, uncertainty: Uncertainty(halfWidth: interval / ppp, kind: .fitInterval),
                        sampleCount: fit.n, region: roi, validity: validity, significantDigits: 2, sources: src,
                        notes: "Equivalent isotropic Gaussian. Apple does not publish its blur kernel; this is a descriptive fit, not an internal parameter. sigma = \(Format.number(sigmaCapture, digits: 3)) capture px.",
                        series: [Measurement.Series(label: "RMSE vs sigma", xUnit: "pt", yUnit: "Y", x: result.curve.map { $0.0 * pxScale / ppp }, y: result.curve.map { $0.1 })]))
                    rep.measurements.append(Measurement(name: "Effective Blur Width (FWHM)", value: 2.3548 * sigmaCapture / ppp, unit: "pt",
                        provenance: .estimated, algorithm: "FWHM = 2.3548 * fitted sigma", version: AlgorithmVersion.blurFit,
                        confidence: conf, uncertainty: Uncertainty(halfWidth: 2.3548 * interval / ppp, kind: .fitInterval),
                        sampleCount: fit.n, region: roi, validity: validity, significantDigits: 2, sources: src))
                    rep.measurements.append(Measurement(name: "Blur Model Residual (RMSE)", value: fit.rmse, unit: "Y",
                        provenance: .derived, algorithm: "RMSE of the best Gaussian+affine model", version: AlgorithmVersion.blurFit,
                        confidence: .high("Computed from the fit"), sampleCount: fit.n, region: roi, significantDigits: 2, sources: src))
                    // Spatial variation of blur across tiles
                    if input.modules.contains(.blur) {
                        let tiles = tileBlur(yRef, yTest, mask: interior, tile: max(24, Int(24 * ppp / pxScale)))
                        if tiles.count >= 3 {
                            let s = Statistics.summary(tiles.map { $0 * pxScale / ppp })
                            rep.measurements.append(Measurement(name: "Blur Variation Across Surface (tile sigma SD)", value: s.standardDeviation, unit: "pt",
                                provenance: .estimated, algorithm: "Std. dev. of per-tile sigma fits", version: AlgorithmVersion.blurFit,
                                confidence: tiles.count >= 6 ? .medium("\(tiles.count) tiles") : .low("Only \(tiles.count) tiles"),
                                uncertainty: Uncertainty(halfWidth: (s.max - s.min) / 2, kind: .range), sampleCount: tiles.count, region: roi,
                                significantDigits: 2, sources: src, notes: "Tile sigma range \(Format.number(s.min, digits: 2))-\(Format.number(s.max, digits: 2)) pt."))
                        } else {
                            rep.measurements.append(.unavailable("Blur Variation Across Surface (tile sigma SD)", unit: "pt", algorithm: "Per-tile sigma", version: AlgorithmVersion.blurFit, reason: "Fewer than 3 textured tiles fit inside the glass interior."))
                        }
                    }
                } else {
                    rep.measurements.append(.unavailable("Apparent Blur Radius (Gaussian sigma)", unit: "pt", algorithm: "Gaussian+affine fit", version: AlgorithmVersion.blurFit, reason: "Fit failed: the reference has no variance inside the glass region."))
                }
            } else {
                rep.measurements.append(.unavailable("Apparent Blur Radius (Gaussian sigma)", unit: "pt", algorithm: "Gaussian+affine fit", version: AlgorithmVersion.blurFit,
                    reason: "Background has no spatial detail under the glass (reference SD \(Format.number(refTexture, digits: 2)) Y). Use a textured background such as Random Dots, Checkerboard or Noise."))
            }
        }

        // ---- Translucency ----
        if input.modules.contains(.translucency) {
            if textured {
                let sR = yRef.std(in: interior), sT = yTest.std(in: interior)
                rep.measurements.append(Measurement(name: "Local Contrast Retention", value: sT / sR, unit: "ratio",
                    provenance: .derived, algorithm: "SD(Y_test) / SD(Y_ref) inside the glass interior", version: AlgorithmVersion.translucency,
                    confidence: .high("Ratio of two direct statistics"), sampleCount: nInt, region: roi, significantDigits: 3, sources: src,
                    notes: input.background.kind.isPeriodic ? "Periodic background (period \(Format.number(input.background.patternScale, digits: 3)) pt): equals the modulation transfer at that frequency only if the response is linear." : nil))
                let gR = yRef.gradientMagnitude(), gT = yTest.gradientMagnitude()
                let eR = gR.mean(in: interior), eT = gT.mean(in: interior)
                rep.measurements.append(Measurement(name: "Texture Retention (gradient energy ratio)", value: eR > 0 ? eT / eR : nil, unit: "ratio",
                    provenance: .derived, algorithm: "Mean Sobel magnitude (test) / (reference) inside the interior", version: AlgorithmVersion.translucency,
                    confidence: .high("Ratio of direct statistics"), sampleCount: nInt, region: roi,
                    validity: eR > 0 ? .valid : .notAvailable("Reference has no gradients"), significantDigits: 3, sources: src))
                if let fit = blurFit {
                    rep.measurements.append(Measurement(name: "Background Visibility (model R^2)", value: fit.r2, unit: "",
                        provenance: .estimated, algorithm: "Fraction of test variance explained by a blurred, affine copy of the background", version: AlgorithmVersion.translucency,
                        confidence: .medium("Depends on the Gaussian+affine model"), sampleCount: fit.n, region: roi, significantDigits: 3, sources: src))
                    rep.measurements.append(Measurement(name: "Effective Background Transmission (gain g)", value: fit.gain, unit: "",
                        provenance: .estimated, algorithm: "Gain g of T ~ g*(G_sigma*R)+o", version: AlgorithmVersion.translucency,
                        confidence: fit.r2 > 0.9 ? .medium("Model R^2 \(Format.number(fit.r2, digits: 3))") : .low("Model R^2 \(Format.number(fit.r2, digits: 3))"),
                        sampleCount: fit.n, region: roi, significantDigits: 3, sources: src,
                        notes: "Effective linear-light transmission of background variation. This is not Apple's internal alpha; adaptive processing can change it per background."))
                    rep.measurements.append(Measurement(name: "Effective Additive Term (offset o)", value: fit.offset, unit: "Y",
                        provenance: .estimated, algorithm: "Offset o of T ~ g*(G_sigma*R)+o", version: AlgorithmVersion.translucency,
                        confidence: fit.r2 > 0.9 ? .medium("Model R^2 \(Format.number(fit.r2, digits: 3))") : .low("Model R^2 \(Format.number(fit.r2, digits: 3))"),
                        sampleCount: fit.n, region: roi, significantDigits: 3, sources: src))
                    if let s = blurSigma {
                        let tiles = tileGain(yRef.gaussianBlurred(sigma: s), yTest, mask: interior, tile: max(24, Int(24 * ppp / pxScale)))
                        if tiles.count >= 3 {
                            let st = Statistics.summary(tiles)
                            rep.measurements.append(Measurement(name: "Spatial Variation of Transmission (tile gain SD)", value: st.standardDeviation, unit: "",
                                provenance: .estimated, algorithm: "SD of per-tile affine gain against the blurred reference", version: AlgorithmVersion.translucency,
                                confidence: .medium("\(tiles.count) tiles"), uncertainty: Uncertainty(halfWidth: (st.max - st.min) / 2, kind: .range),
                                sampleCount: tiles.count, region: roi, significantDigits: 2, sources: src))
                        }
                    }
                }
            } else {
                rep.measurements.append(.unavailable("Local Contrast Retention", unit: "ratio", algorithm: "SD ratio", version: AlgorithmVersion.translucency,
                    reason: "Uniform background: contrast retention needs spatial variation. Use the multi-background transfer fit in Sessions for uniform colors."))
            }
            // Per-channel color transfer (valid on any background)
            for (name, pr, pt) in [("R", ref.r, test.r), ("G", ref.g, test.g), ("B", ref.b, test.b)] {
                let a = pr.mean(in: interior), b = pt.mean(in: interior)
                rep.measurements.append(Measurement(name: "Color Transfer \(name) (mean test / mean ref, linear)", value: a > 1e-4 ? b / a : nil, unit: "ratio",
                    provenance: .derived, algorithm: "Ratio of linear channel means inside the interior", version: AlgorithmVersion.translucency,
                    confidence: a > 0.01 ? .high("Direct averages") : .low("Reference channel is near zero; ratio is unstable"),
                    sampleCount: nInt, region: roi, validity: a > 1e-4 ? .valid : .notAvailable("Reference channel is zero"), significantDigits: 3, sources: src))
            }
        }

        // ---- Edge spread / MTF (step-edge target) ----
        if input.modules.contains(.edgeSpread) {
            if input.background.kind == .stepEdge && abs(input.background.edgeAngle) < 1 {
                rep.measurements.append(contentsOf: edgeSpread(yRef, yTest, mask: interior, pxScale: pxScale, ppp: ppp, roi: roi, sources: src))
            } else {
                rep.measurements.append(.unavailable("Edge Spread Function (10-90%)", unit: "pt", algorithm: "Vertical step-edge ESF", version: AlgorithmVersion.edgeSpread,
                    reason: "Requires the Step Edge background with a vertical edge (angle 0) crossing the glass."))
            }
        }

        // ---- Refraction & distortion (block matching) ----
        if input.modules.contains(.refraction) {
            if textured {
                let field = displacementField(yRef.gaussianBlurred(sigma: blurSigma ?? 0), yTest, inside: masks.full, sdf: masks.sdf,
                                              maxShift: Int((input.maxDisplacementPx / pxScale).rounded()))
                rep.vectors = field.map { var v = $0; v.x *= pxScale; v.y *= pxScale; v.dx *= pxScale; v.dy *= pxScale; return v }
                rep.measurements.append(contentsOf: displacementMeasurements(field, sdf: masks.sdf, edgeInner: edgeInnerPx, ptPerPx: ptPerAnalysisPx, roi: roi, sources: src, periodic: input.background.kind.isPeriodic))
                let base = test.cgImage()
                if let img = Heatmap.vectorField(base: base, width: test.width, height: test.height, vectors: field, gain: 3) {
                    rep.images.append(DerivedImage(name: "Displacement Vectors (x3)", image: img, legend: nil,
                                                   note: "Arrows show where each test patch's content came from in the reference, magnified 3x. Gray dots are rejected matches."))
                }
                let mag = magnitudeMap(field, width: test.width, height: test.height, ptPerPx: ptPerAnalysisPx)
                let (img, legend) = Heatmap.render(mag, mask: masks.full, colormap: .magma, unit: "pt")
                if let img { rep.images.append(DerivedImage(name: "Apparent Displacement Magnitude", image: img, legend: legend, note: "Nearest-vector fill of accepted displacement magnitudes.")) }
            } else {
                rep.measurements.append(.unavailable("Maximum Apparent Displacement", unit: "pt", algorithm: "NCC block matching", version: AlgorithmVersion.displacement,
                    reason: "Uniform background: displacement cannot be observed without texture. Use Random Dots, Noise or a Checker with Fiducials."))
            }
        }

        // ---- Highlights & edge lighting ----
        if input.modules.contains(.highlights) {
            rep.measurements.append(contentsOf: highlightProfile(yRef: yRef, yTest: yTest, masks: masks, region: region, sigma: blurSigma,
                                                                 edgeInner: edgeInnerPx, ptPerPx: ptPerAnalysisPx, roi: roi, sources: src))
        }

        // ---- Color science ----
        if input.modules.contains(.color) {
            rep.measurements.append(contentsOf: colorMeasurements(ref: ref, test: test, interior: interior, surround: masks.surround, roi: roi, sources: src))
        }

        // ---- Error metrics & difference images ----
        if input.modules.contains(.errorMetrics) || input.modules.contains(.color) {
            if let m = ImageMetrics.compare(ref, test, mask: masks.full) {
                if input.modules.contains(.errorMetrics) {
                    let n = m.sampleCount
                    rep.measurements.append(Measurement(name: "MAE (reference vs glass, encoded)", value: m.mae, unit: "",
                        provenance: .measured, algorithm: "Mean |a-b| of sRGB-encoded channels in the glass mask", version: AlgorithmVersion.errorMetrics,
                        confidence: .high("Direct"), sampleCount: n, region: roi, significantDigits: 3, sources: src))
                    rep.measurements.append(Measurement(name: "RMSE (reference vs glass, encoded)", value: m.rmse, unit: "",
                        provenance: .measured, algorithm: "Root mean squared difference of encoded channels", version: AlgorithmVersion.errorMetrics,
                        confidence: .high("Direct"), sampleCount: n, region: roi, significantDigits: 3, sources: src))
                    rep.measurements.append(Measurement(name: "PSNR (reference vs glass)", value: m.psnr.isFinite ? m.psnr : nil, unit: "dB",
                        provenance: .derived, algorithm: "10 log10(1/MSE), peak = 1", version: AlgorithmVersion.errorMetrics,
                        confidence: .medium("PSNR alone does not describe perceptual or structural similarity"), sampleCount: n, region: roi,
                        validity: m.psnr.isFinite ? .valid : .notAvailable("Images are identical"), significantDigits: 3, sources: src))
                    rep.measurements.append(Measurement(name: "SSIM (reference vs glass)", value: m.ssim, unit: "",
                        provenance: .derived, algorithm: "Mean SSIM, Gaussian window sigma 1.5, on Rec.709 luma of encoded values", version: AlgorithmVersion.errorMetrics,
                        confidence: .high("Standard definition"), sampleCount: n, region: roi, significantDigits: 3, sources: src))
                }
                rep.measurements.append(Measurement(name: "Color Difference dE00 (mean)", value: m.deltaEMean, unit: "dE00",
                    provenance: .measured, algorithm: "Per-pixel CIEDE2000 between reference and test, mean over the glass mask", version: AlgorithmVersion.colorScience,
                    confidence: .high("Direct per-pixel computation"), uncertainty: Uncertainty(halfWidth: m.deltaEP95 - m.deltaEMean, kind: .range),
                    sampleCount: m.sampleCount, region: roi, significantDigits: 3, sources: src, notes: "p95 = \(Format.number(m.deltaEP95, digits: 3)), max = \(Format.number(m.deltaEMax, digits: 3))."))
                let (img, legend) = Heatmap.render(m.deltaEMap, mask: masks.full, range: 0...max(10, m.deltaEP95), colormap: .viridis, unit: "dE00")
                if let img { rep.images.append(DerivedImage(name: "Color Difference Heatmap (dE00)", image: img, legend: legend, note: "Per-pixel CIEDE2000 between reference and glass frames.")) }
                if let diff = Heatmap.difference(ref, test) {
                    rep.images.append(DerivedImage(name: "Absolute Difference (x4)", image: diff, legend: nil, note: "|test - reference| in linear light, gain 4, sRGB-encoded for display."))
                }
            }
            if input.modules.contains(.errorMetrics), let s = blurSigma, let fit = blurFit {
                let model = yRef.gaussianBlurred(sigma: s)
                var predicted = model
                for i in predicted.data.indices { predicted.data[i] = Float(fit.gain) * model.data[i] + Float(fit.offset) }
                if let e = ImageMetrics.edgeAlignmentError(predicted, yTest, mask: masks.full) {
                    rep.measurements.append(Measurement(name: "Edge Alignment Error (blur model vs glass)", value: e.mean * ptPerAnalysisPx, unit: "pt",
                        provenance: .derived, algorithm: "Mean distance from strong edges in the model to the nearest strong edge in the capture", version: AlgorithmVersion.errorMetrics,
                        confidence: .medium("Edge threshold at the 90th gradient percentile"), sampleCount: e.count, region: roi, significantDigits: 2, sources: src,
                        notes: "Non-zero values indicate geometric warping that the blur model does not include."))
                }
            }
        }

        if let sigma = blurSigma {
            rep.log.append("Blur fit sigma = \(Format.number(sigma * pxScale, digits: 3)) capture px.")
        }
        return rep
    }

    // MARK: - Registration

    static func registration(_ a: Plane, _ b: Plane, mask: Mask, search: Int) -> (dx: Int, dy: Int, residual: Double) {
        var best = (0, 0, Double.greatestFiniteMagnitude)
        let w = a.width, h = a.height
        for dy in -search...search {
            for dx in -search...search {
                var s = 0.0, n = 0
                for y in 0..<h {
                    let sy = y - dy
                    if sy < 0 || sy >= h { continue }
                    for x in 0..<w where mask.data[y * w + x] != 0 {
                        let sx = x - dx
                        if sx < 0 || sx >= w { continue }
                        s += Double(abs(b.data[y * w + x] - a.data[sy * w + sx])); n += 1
                    }
                }
                if n > 0 {
                    let r = s / Double(n)
                    // Prefer zero shift unless another shift is clearly better.
                    if r < best.2 * (dx == 0 && dy == 0 ? 1.0 : 0.98) { best = (dx, dy, r) }
                }
            }
        }
        return best.2 == .greatestFiniteMagnitude ? (0, 0, .nan) : best
    }

    // MARK: - Blur

    struct BlurResult {
        var sigma: Double
        var fit: (gain: Double, offset: Double, rmse: Double, r2: Double, n: Int)?
        var interval: ClosedRange<Double>
        var curve: [(Double, Double)]
        var atBound: Bool
    }

    static func blurResidual(_ ref: Plane, _ test: Plane, mask: Mask, sigma: Double) -> (gain: Double, offset: Double, rmse: Double, r2: Double, n: Int)? {
        let b = ref.gaussianBlurred(sigma: sigma)
        return b.data.withUnsafeBufferPointer { x in
            test.data.withUnsafeBufferPointer { y in
                mask.data.withUnsafeBufferPointer { m in Optimization.affineFit(x: x, y: y, mask: m) }
            }
        }
    }

    static func fitBlur(_ ref: Plane, _ test: Plane, mask: Mask, maxSigma: Double = 48) -> BlurResult {
        let grid: [Double] = [0, 0.75, 1.5, 2.5, 4, 6, 8, 11, 15, 20, 26, 34, 42, 48].filter { $0 <= maxSigma }
        var curve: [(Double, Double)] = []
        var bestI = 0
        for (i, s) in grid.enumerated() {
            if Task.isCancelled { break }
            let r = blurResidual(ref, test, mask: mask, sigma: s)?.rmse ?? .infinity
            curve.append((s, r))
            if r < curve[bestI].1 { bestI = i }
        }
        let lo = grid[max(0, bestI - 1)], hi = grid[min(grid.count - 1, bestI + 1)]
        var sigma = grid[bestI]
        if hi > lo {
            let g = Optimization.goldenSection(lo, hi, tolerance: 0.05) { s in
                blurResidual(ref, test, mask: mask, sigma: s)?.rmse ?? .infinity
            }
            if g.value <= curve[bestI].1 { sigma = g.x; curve.append((g.x, g.value)) }
        }
        curve.sort { $0.0 < $1.0 }
        let fit = blurResidual(ref, test, mask: mask, sigma: sigma)
        let minR = fit?.rmse ?? .infinity
        let within = curve.filter { $0.1 <= minR * 1.02 }.map(\.0)
        let interval = (within.min() ?? sigma)...(within.max() ?? sigma)
        return BlurResult(sigma: sigma, fit: fit, interval: interval, curve: curve, atBound: bestI == grid.count - 1)
    }

    static func tiles(_ mask: Mask, tile: Int) -> [PixelRegion] {
        var out: [PixelRegion] = []
        var y = 0
        while y + tile <= mask.height {
            var x = 0
            while x + tile <= mask.width {
                var inside = true
                for yy in y..<(y + tile) where inside { for xx in x..<(x + tile) where mask.data[yy * mask.width + xx] == 0 { inside = false; break } }
                if inside { out.append(PixelRegion(x: x, y: y, width: tile, height: tile)) }
                x += tile
            }
            y += tile
        }
        return out
    }

    static func tileBlur(_ ref: Plane, _ test: Plane, mask: Mask, tile: Int) -> [Double] {
        var sigmas: [Double] = []
        let pad = tile / 2
        for t in tiles(mask, tile: tile).prefix(24) {
            if Task.isCancelled { break }
            let r = PixelRegion(x: t.x - pad, y: t.y - pad, width: t.width + 2 * pad, height: t.height + 2 * pad)
            let rc = ref.cropped(r), tc = test.cropped(r)
            var m = Mask(width: r.width, height: r.height)
            for y in pad..<(pad + tile) { for x in pad..<(pad + tile) { m.data[y * r.width + x] = 1 } }
            guard rc.std(in: m) > 0.004 else { continue }
            let res = fitBlur(rc, tc, mask: m, maxSigma: Double(pad))
            if let f = res.fit, f.r2 > 0.8 { sigmas.append(res.sigma) }
        }
        return sigmas
    }

    static func tileGain(_ blurredRef: Plane, _ test: Plane, mask: Mask, tile: Int) -> [Double] {
        var gains: [Double] = []
        for t in tiles(mask, tile: tile).prefix(48) {
            let rc = blurredRef.cropped(t), tc = test.cropped(t)
            guard rc.std() > 0.002 else { continue }
            let fit = rc.data.withUnsafeBufferPointer { x in tc.data.withUnsafeBufferPointer { y in Optimization.affineFit(x: x, y: y, mask: nil) } }
            if let f = fit, f.r2 > 0.5 { gains.append(f.gain) }
        }
        return gains
    }

    // MARK: - Edge spread

    static func edgeSpread(_ ref: Plane, _ test: Plane, mask: Mask, pxScale: Double, ppp: Double, roi: PixelRegion, sources: [String]) -> [Measurement] {
        let half = 24
        var profiles: [[Double]] = []
        let w = ref.width
        for y in 0..<ref.height {
            // Edge column in the reference: strongest horizontal gradient inside the mask on this row.
            var bestX = -1; var bestG: Float = 0
            for x in 1..<(w - 1) where mask.data[y * w + x] != 0 {
                let g = abs(ref[x + 1, y] - ref[x - 1, y])
                if g > bestG { bestG = g; bestX = x }
            }
            guard bestX - half >= 0, bestX + half < w, bestG > 0.05 else { continue }
            var ok = true
            for x in (bestX - half)...(bestX + half) where mask.data[y * w + x] == 0 { ok = false; break }
            if !ok { continue }
            profiles.append(((bestX - half)...(bestX + half)).map { Double(test[$0, y]) })
        }
        let name = "Edge Spread Function (10-90%)"
        guard profiles.count >= 5 else {
            return [.unavailable(name, unit: "pt", algorithm: "Vertical step-edge ESF", version: AlgorithmVersion.edgeSpread,
                                 reason: "The step edge does not cross the glass interior over at least 5 rows with a full window.")]
        }
        var esf = [Double](repeating: 0, count: 2 * half + 1)
        for p in profiles { for i in p.indices { esf[i] += p[i] / Double(profiles.count) } }
        let lo = Statistics.mean(Array(esf.prefix(5))), hi = Statistics.mean(Array(esf.suffix(5)))
        guard abs(hi - lo) > 0.01 else {
            return [.unavailable(name, unit: "pt", algorithm: "Vertical step-edge ESF", version: AlgorithmVersion.edgeSpread, reason: "Edge contrast under the glass is below 1% luminance.")]
        }
        let norm = esf.map { ($0 - lo) / (hi - lo) }
        func cross(_ level: Double) -> Double? {
            for i in 1..<norm.count where (norm[i - 1] - level) * (norm[i] - level) <= 0 && norm[i] != norm[i - 1] {
                return Double(i - 1) + (level - norm[i - 1]) / (norm[i] - norm[i - 1])
            }
            return nil
        }
        var out: [Measurement] = []
        let xs = (0..<norm.count).map { Double($0 - half) * pxScale / ppp }
        if let a = cross(0.1), let b = cross(0.9) {
            let widthPt = abs(b - a) * pxScale / ppp
            let quant = pxScale / ppp
            out.append(Measurement(name: name, value: widthPt, unit: "pt", provenance: .measured,
                algorithm: "Row-aligned average edge profile; 10%-90% rise distance", version: AlgorithmVersion.edgeSpread,
                confidence: profiles.count >= 20 ? .high("\(profiles.count) rows averaged") : .medium("\(profiles.count) rows averaged"),
                uncertainty: Uncertainty(halfWidth: quant / 2, kind: .quantization), sampleCount: profiles.count, region: roi,
                significantDigits: 2, sources: sources, notes: "Gaussian-equivalent sigma = width / 2.563 = \(Format.number(widthPt / 2.563, digits: 2)) pt (only meaningful if the ESF is Gaussian-shaped).",
                series: [Measurement.Series(label: "ESF", xUnit: "pt", yUnit: "normalised", x: xs, y: norm)]))
        }
        let lsf = TimeSeries.derivative(t: xs, y: norm)
        let area = lsf.reduce(0, +)
        out.append(Measurement(name: "Line Spread Function (peak)", value: lsf.max(), unit: "1/pt", provenance: .derived,
            algorithm: "Derivative of the measured ESF", version: AlgorithmVersion.edgeSpread,
            confidence: .medium("Differentiation amplifies noise"), sampleCount: profiles.count, region: roi, significantDigits: 2, sources: sources,
            series: [Measurement.Series(label: "LSF", xUnit: "pt", yUnit: "1/pt", x: xs, y: lsf)]))
        if area > 0 {
            // Hann-windowed LSF -> MTF
            let n = lsf.count
            let windowed = lsf.enumerated().map { $0.element * (0.5 - 0.5 * cos(2 * .pi * Double($0.offset) / Double(n - 1))) }
            let mag = Spectral.dftMagnitude(windowed)
            let dc = mag.first ?? 1
            let mtf = mag.map { dc > 0 ? $0 / dc : 0 }
            let stepPt = pxScale / ppp
            let freqs = (0..<mtf.count).map { Double($0) / (Double(n) * stepPt) }
            var mtf50: Double? = nil
            for i in 1..<mtf.count where mtf[i - 1] >= 0.5 && mtf[i] < 0.5 {
                mtf50 = freqs[i - 1] + (0.5 - mtf[i - 1]) / (mtf[i] - mtf[i - 1]) * (freqs[i] - freqs[i - 1]); break
            }
            out.append(Measurement(name: "MTF50 (spatial frequency at 50% modulation)", value: mtf50, unit: "cycles/pt", provenance: .derived,
                algorithm: "|DFT| of the Hann-windowed LSF, normalised at DC", version: AlgorithmVersion.edgeSpread,
                confidence: .medium("Window length \(n) samples limits frequency resolution"), sampleCount: profiles.count, region: roi,
                validity: mtf50 == nil ? .notAvailable("MTF never falls below 0.5 within the measured band") : .valid, significantDigits: 2, sources: sources,
                series: [Measurement.Series(label: "MTF", xUnit: "cycles/pt", yUnit: "modulation", x: freqs, y: mtf)]))
        }
        return out
    }

    // MARK: - Displacement

    static func displacementField(_ ref: Plane, _ test: Plane, inside: Mask, sdf: Plane, maxShift: Int) -> [DisplacementVector] {
        let patch = 7                // half-size -> 15x15 patches
        let step = 8
        let search = max(4, min(maxShift, 40))
        let w = ref.width, h = ref.height
        var out: [DisplacementVector] = []
        var y = patch
        while y < h - patch {
            if Task.isCancelled { break }
            var x = patch
            while x < w - patch {
                defer { x += step }
                guard inside.data[y * w + x] != 0, sdf[x, y] < -2 else { continue }
                // Test patch stats
                var tp = [Float](); tp.reserveCapacity((2 * patch + 1) * (2 * patch + 1))
                for dy in -patch...patch { for dx in -patch...patch { tp.append(test[x + dx, y + dy]) } }
                let tm = tp.reduce(0, +) / Float(tp.count)
                var tv: Float = 0
                for i in tp.indices { tp[i] -= tm; tv += tp[i] * tp[i] }
                if tv / Float(tp.count) < 1e-6 {
                    out.append(DisplacementVector(x: Double(x), y: Double(y), dx: 0, dy: 0, correlation: 0, ambiguity: 1, accepted: false, rejectionReason: "Patch has no texture"))
                    continue
                }
                var scores = [Float](repeating: -2, count: (2 * search + 1) * (2 * search + 1))
                var best: Float = -2; var bx = 0, by = 0
                for sy in -search...search {
                    let cy = y + sy
                    if cy - patch < 0 || cy + patch >= h { continue }
                    for sx in -search...search {
                        let cx = x + sx
                        if cx - patch < 0 || cx + patch >= w { continue }
                        var rm: Float = 0
                        for dy in -patch...patch { for dx in -patch...patch { rm += ref[cx + dx, cy + dy] } }
                        rm /= Float(tp.count)
                        var cov: Float = 0, rv: Float = 0, k = 0
                        for dy in -patch...patch {
                            for dx in -patch...patch {
                                let r = ref[cx + dx, cy + dy] - rm
                                cov += r * tp[k]; rv += r * r; k += 1
                            }
                        }
                        let ncc = rv > 1e-9 ? cov / (rv * tv).squareRoot() : -1
                        scores[(sy + search) * (2 * search + 1) + (sx + search)] = ncc
                        if ncc > best { best = ncc; bx = sx; by = sy }
                    }
                }
                // Second-best peak at least 3 px away (ambiguity of periodic or flat texture)
                var second: Float = -2
                for sy in -search...search { for sx in -search...search where abs(sx - bx) > 2 || abs(sy - by) > 2 {
                    second = max(second, scores[(sy + search) * (2 * search + 1) + (sx + search)])
                } }
                // Parabolic sub-pixel refinement
                func s(_ ox: Int, _ oy: Int) -> Float? {
                    let ix = bx + ox, iy = by + oy
                    guard abs(ix) <= search, abs(iy) <= search else { return nil }
                    let v = scores[(iy + search) * (2 * search + 1) + (ix + search)]
                    return v > -2 ? v : nil
                }
                var fx = Double(bx), fy = Double(by)
                if let l = s(-1, 0), let r = s(1, 0) { let d = l - 2 * best + r; if d < 0 { fx += Double((l - r) / (2 * d)) } }
                if let u = s(0, -1), let d0 = s(0, 1) { let d = u - 2 * best + d0; if d < 0 { fy += Double((u - d0) / (2 * d)) } }
                let ambiguity = best > 0 ? Double(max(0, second) / best) : 1
                var reason: String? = nil
                if best < 0.6 { reason = "Peak correlation \(Format.number(Double(best), digits: 2)) < 0.6" }
                else if ambiguity > 0.95 { reason = "Ambiguous match (second peak \(Format.number(ambiguity * 100, digits: 2))% of best)" }
                else if abs(bx) == search || abs(by) == search { reason = "Best match at the search boundary" }
                // The vector points from the test location to its source in the reference.
                out.append(DisplacementVector(x: Double(x), y: Double(y), dx: fx, dy: fy, correlation: Double(best), ambiguity: ambiguity,
                                              accepted: reason == nil, rejectionReason: reason))
            }
            y += step
        }
        return out
    }

    static func displacementMeasurements(_ field: [DisplacementVector], sdf: Plane, edgeInner: Double, ptPerPx: Double, roi: PixelRegion, sources: [String], periodic: Bool) -> [Measurement] {
        let acc = field.filter(\.accepted)
        let v = AlgorithmVersion.displacement
        let alg = "Normalised cross-correlation block matching (15x15 px patches, 8 px grid) of test vs blurred reference; parabolic sub-pixel peak"
        guard acc.count >= 4 else {
            return [.unavailable("Maximum Apparent Displacement", unit: "pt", algorithm: alg, version: v,
                                 reason: "Only \(acc.count) of \(field.count) matches passed the confidence checks.")]
        }
        let mags = acc.map { $0.magnitude * ptPerPx }
        let rejectedShare = 1 - Double(acc.count) / Double(max(1, field.count))
        let conf: Confidence = rejectedShare < 0.2 ? .high("\(acc.count) accepted vectors, \(Format.number(rejectedShare * 100, digits: 2))% rejected")
            : (rejectedShare < 0.5 ? .medium("\(Format.number(rejectedShare * 100, digits: 2))% of matches rejected") : .low("\(Format.number(rejectedShare * 100, digits: 2))% of matches rejected"))
        var validity: Validity = .valid
        if periodic { validity = .warning("Periodic background: block matching can lock onto the wrong period. Prefer Random Dots or Checker + Fiducials.") }
        let s = Statistics.summary(mags)
        let p95 = Statistics.quantile(mags, 0.95)
        var out: [Measurement] = []
        out.append(Measurement(name: "Maximum Apparent Displacement (p95)", value: p95, unit: "pt", provenance: .estimated, algorithm: alg, version: v,
            confidence: conf, uncertainty: Uncertainty(halfWidth: 0.25 * ptPerPx, kind: .quantization), sampleCount: acc.count, region: roi, validity: validity,
            significantDigits: 2, sources: sources, notes: "95th percentile used instead of the raw maximum, which is dominated by outliers. Raw max \(Format.number(s.max, digits: 2)) pt."))
        out.append(Measurement(name: "Mean Apparent Displacement", value: s.mean, unit: "pt", provenance: .estimated, algorithm: alg, version: v,
            confidence: conf, uncertainty: s.ci95HalfWidth.map { Uncertainty(halfWidth: $0, kind: .confidenceInterval95) }, sampleCount: acc.count, region: roi,
            validity: validity, significantDigits: 2, sources: sources))
        let edgeVecs = acc.filter { Double(sdf.sample($0.x, $0.y)) >= -edgeInner * 2 }
        let innerVecs = acc.filter { Double(sdf.sample($0.x, $0.y)) < -edgeInner * 2 }
        out.append(Measurement(name: "Edge Displacement (mean, rim zone)", value: edgeVecs.isEmpty ? nil : Statistics.mean(edgeVecs.map { $0.magnitude * ptPerPx }), unit: "pt",
            provenance: .estimated, algorithm: alg + "; vectors within 2x edge band of the rim", version: v, confidence: edgeVecs.count >= 4 ? conf : .low("\(edgeVecs.count) vectors"),
            sampleCount: edgeVecs.count, region: roi, validity: edgeVecs.isEmpty ? .notAvailable("No accepted vectors near the rim") : validity, significantDigits: 2, sources: sources))
        out.append(Measurement(name: "Interior Displacement (mean, away from rim)", value: innerVecs.isEmpty ? nil : Statistics.mean(innerVecs.map { $0.magnitude * ptPerPx }), unit: "pt",
            provenance: .estimated, algorithm: alg, version: v, confidence: innerVecs.count >= 4 ? conf : .low("\(innerVecs.count) vectors"),
            sampleCount: innerVecs.count, region: roi, validity: innerVecs.isEmpty ? .notAvailable("No accepted vectors in the interior") : validity, significantDigits: 2, sources: sources))
        // Horizontal / vertical components
        out.append(Measurement(name: "Horizontal Displacement Field (mean |dx|)", value: Statistics.mean(acc.map { abs($0.dx) * ptPerPx }), unit: "pt",
            provenance: .estimated, algorithm: alg, version: v, confidence: conf, sampleCount: acc.count, region: roi, validity: validity, significantDigits: 2, sources: sources,
            series: [Measurement.Series(label: "dx by x", xUnit: "px", yUnit: "pt", x: acc.map(\.x), y: acc.map { $0.dx * ptPerPx })]))
        out.append(Measurement(name: "Vertical Displacement Field (mean |dy|)", value: Statistics.mean(acc.map { abs($0.dy) * ptPerPx }), unit: "pt",
            provenance: .estimated, algorithm: alg, version: v, confidence: conf, sampleCount: acc.count, region: roi, validity: validity, significantDigits: 2, sources: sources,
            series: [Measurement.Series(label: "dy by y", xUnit: "px", yUnit: "pt", x: acc.map(\.y), y: acc.map { $0.dy * ptPerPx })]))
        // Deformation gradient from neighbouring grid vectors
        var grads: [Double] = []
        let byKey = Dictionary(acc.map { ("\(Int($0.x))_\(Int($0.y))", $0) }, uniquingKeysWith: { a, _ in a })
        for a in acc {
            if let r = byKey["\(Int(a.x) + 8)_\(Int(a.y))"], let d = byKey["\(Int(a.x))_\(Int(a.y) + 8)"] {
                let dudx = (r.dx - a.dx) / 8, dvdx = (r.dy - a.dy) / 8, dudy = (d.dx - a.dx) / 8, dvdy = (d.dy - a.dy) / 8
                grads.append((dudx * dudx + dvdx * dvdx + dudy * dudy + dvdy * dvdy).squareRoot())
            }
        }
        if grads.count >= 3 {
            out.append(Measurement(name: "Local Distortion Magnitude (|grad u|, mean)", value: Statistics.mean(grads), unit: "pt/pt",
                provenance: .derived, algorithm: "Frobenius norm of the finite-difference deformation gradient of the displacement field", version: v,
                confidence: .medium("Finite differences on an 8 px grid"), sampleCount: grads.count, region: roi, validity: validity, significantDigits: 2, sources: sources,
                notes: "Max \(Format.number(grads.max() ?? 0, digits: 2)). Dimensionless strain-like quantity."))
        }
        out.append(Measurement(name: "Rejected Match Share", value: rejectedShare * 100, unit: "%", provenance: .derived,
            algorithm: "Share of grid points failing NCC >= 0.6, ambiguity <= 0.95 or boundary checks", version: v,
            confidence: .high("Count"), sampleCount: field.count, region: roi, significantDigits: 2, sources: sources))
        return out
    }

    static func magnitudeMap(_ field: [DisplacementVector], width: Int, height: Int, ptPerPx: Double) -> Plane {
        var p = Plane(width: width, height: height, fill: .nan)
        let acc = field.filter(\.accepted)
        guard !acc.isEmpty else { return p }
        for y in 0..<height {
            for x in 0..<width {
                var best = Double.greatestFiniteMagnitude; var v = 0.0
                for a in acc {
                    let d = (a.x - Double(x)) * (a.x - Double(x)) + (a.y - Double(y)) * (a.y - Double(y))
                    if d < best { best = d; v = a.magnitude }
                }
                p[x, y] = best <= 128 ? Float(v * ptPerPx) : .nan
            }
        }
        return p
    }

    // MARK: - Highlights

    static func highlightProfile(yRef: Plane, yTest: Plane, masks: GlassRegionModel.Masks, region: GlassRegionModel, sigma: Double?,
                                 edgeInner: Double, ptPerPx: Double, roi: PixelRegion, sources: [String]) -> [Measurement] {
        let v = AlgorithmVersion.highlights
        let alg = "Excess luminance E = Y_test - model(Y_ref), binned by signed distance to the shape outline and by angular sector"
        // Predicted glass without edge effects: blurred affine background fitted on the interior only.
        let base = yRef.gaussianBlurred(sigma: sigma ?? 0)
        let fit = base.data.withUnsafeBufferPointer { x in yTest.data.withUnsafeBufferPointer { y in masks.interior.data.withUnsafeBufferPointer { m in Optimization.affineFit(x: x, y: y, mask: m) } } }
        let g = fit?.gain ?? 0
        let o = fit?.offset ?? yTest.mean(in: masks.interior)
        let lo = -Int(ceil(edgeInner * 2)), hi = Int(ceil(edgeInner / 2))
        let bins = hi - lo + 1
        let sectors = 8
        var sum = [[Double]](repeating: [Double](repeating: 0, count: bins), count: sectors + 1)
        var cnt = [[Int]](repeating: [Int](repeating: 0, count: bins), count: sectors + 1)
        let c = region.center
        for y in 0..<yTest.height {
            for x in 0..<yTest.width {
                let d = Double(masks.sdf[x, y])
                let bi = Int(d.rounded()) - lo
                guard bi >= 0, bi < bins else { continue }
                let e = Double(yTest[x, y]) - (g * Double(base[x, y]) + o)
                var ang = atan2(Double(y) - Double(c.y), Double(x) - Double(c.x))
                if ang < 0 { ang += 2 * .pi }
                let s = min(sectors - 1, Int(ang / (2 * .pi) * Double(sectors)))
                sum[s][bi] += e; cnt[s][bi] += 1
                sum[sectors][bi] += e; cnt[sectors][bi] += 1
            }
        }
        func profile(_ s: Int) -> [Double] { (0..<bins).map { cnt[s][$0] > 0 ? sum[s][$0] / Double(cnt[s][$0]) : .nan } }
        let all = profile(sectors)
        let xs = (0..<bins).map { Double($0 + lo) * ptPerPx }
        let insideIdx = (0..<bins).filter { $0 + lo <= 0 && all[$0].isFinite }
        guard let peakI = insideIdx.max(by: { all[$0] < all[$1] }) else {
            return [.unavailable("Edge Brightness Profile", unit: "Y", algorithm: alg, version: v, reason: "No samples near the outline.")]
        }
        let peak = all[peakI]
        // FWHM of the positive excess around the peak
        var l = peakI, r = peakI
        while l > 0, all[l - 1].isFinite, all[l - 1] > peak / 2 { l -= 1 }
        while r < bins - 1, all[r + 1].isFinite, all[r + 1] > peak / 2 { r += 1 }
        let fwhm = Double(r - l + 1) * ptPerPx
        var out: [Measurement] = []
        let conf: Confidence = fit == nil ? .low("No interior model; excess relative to the interior mean") : .medium("Relative to a blurred-affine interior model")
        out.append(Measurement(name: "Peak Relative Edge Luminance (excess)", value: peak, unit: "Y", provenance: .estimated, algorithm: alg, version: v,
            confidence: conf, sampleCount: cnt[sectors].reduce(0, +), region: roi, significantDigits: 2, sources: sources,
            notes: "Positive values: the rim is brighter than the interior model predicts.",
            series: [Measurement.Series(label: "all sectors", xUnit: "pt from outline (negative = inside)", yUnit: "excess Y", x: xs, y: all)]))
        out.append(Measurement(name: "Highlight Position (distance inside outline)", value: -Double(peakI + lo) * ptPerPx, unit: "pt", provenance: .estimated, algorithm: alg, version: v,
            confidence: conf, uncertainty: Uncertainty(halfWidth: ptPerPx / 2, kind: .quantization), sampleCount: cnt[sectors][peakI], region: roi, significantDigits: 2, sources: sources))
        out.append(Measurement(name: "Highlight Width (FWHM)", value: peak > 0 ? fwhm : nil, unit: "pt", provenance: .estimated, algorithm: alg, version: v,
            confidence: conf, uncertainty: Uncertainty(halfWidth: ptPerPx, kind: .quantization), sampleCount: cnt[sectors].reduce(0, +), region: roi,
            validity: peak > 0 ? .valid : .notAvailable("No positive rim excess"), significantDigits: 2, sources: sources))
        // Falloff: excess at 2x FWHM inward relative to peak
        let falloffIdx = max(0, peakI - Int((fwhm / ptPerPx * 2).rounded()))
        if peak > 0, all[falloffIdx].isFinite {
            out.append(Measurement(name: "Highlight Falloff (excess at 2xFWHM inward / peak)", value: all[falloffIdx] / peak, unit: "ratio", provenance: .estimated, algorithm: alg, version: v,
                confidence: conf, sampleCount: cnt[sectors][falloffIdx], region: roi, significantDigits: 2, sources: sources))
        }
        // Asymmetry across sectors
        var sectorPeaks: [Double] = []
        var series: [Measurement.Series] = []
        let names = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
        for s in 0..<sectors {
            let p = profile(s)
            let inside = (0..<bins).filter { $0 + lo <= 0 && p[$0].isFinite }
            if let m = inside.map({ p[$0] }).max() { sectorPeaks.append(m) }
            series.append(Measurement.Series(label: names[s], xUnit: "pt", yUnit: "excess Y", x: xs, y: p))
        }
        if sectorPeaks.count == sectors {
            let mx = sectorPeaks.max()!, mn = sectorPeaks.min()!
            let mean = Statistics.mean(sectorPeaks)
            out.append(Measurement(name: "Edge Asymmetry ((max-min)/mean sector peak)", value: abs(mean) > 1e-4 ? (mx - mn) / abs(mean) : nil, unit: "ratio",
                provenance: .estimated, algorithm: alg, version: v, confidence: conf, sampleCount: sectors, region: roi,
                validity: abs(mean) > 1e-4 ? .valid : .notAvailable("Mean rim excess is zero: no highlight to compare between sectors"), significantDigits: 2, sources: sources,
                notes: "Brightest sector: \(names[sectorPeaks.firstIndex(of: mx)!]); dimmest: \(names[sectorPeaks.firstIndex(of: mn)!]). Sectors are image directions (N = up).",
                series: series))
        }
        // Local gradient magnitude at the rim
        let gm = yTest.gradientMagnitude()
        out.append(Measurement(name: "Local Gradient Magnitude (rim band, mean)", value: gm.mean(in: masks.edge) / ptPerPx, unit: "Y/pt", provenance: .measured,
            algorithm: "Mean Sobel magnitude of Y_test in the edge band", version: v, confidence: .high("Direct"), sampleCount: masks.edge.count, region: roi,
            significantDigits: 2, sources: sources))
        return out
    }

    // MARK: - Color

    static func colorMeasurements(ref: LinearImage, test: LinearImage, interior: Mask, surround: Mask, roi: PixelRegion, sources: [String]) -> [Measurement] {
        let v = AlgorithmVersion.colorScience
        func meanRGB(_ img: LinearImage, _ m: Mask) -> (Double, Double, Double) { (img.r.mean(in: m), img.g.mean(in: m), img.b.mean(in: m)) }
        let mr = meanRGB(ref, interior), mt = meanRGB(test, interior), ms = meanRGB(test, surround)
        let labR = ColorScience.labFromLinearP3(mr.0, mr.1, mr.2), labT = ColorScience.labFromLinearP3(mt.0, mt.1, mt.2)
        let lchR = ColorScience.lch(labR), lchT = ColorScience.lch(labT)
        let n = interior.count
        var out: [Measurement] = []
        out.append(Measurement(name: "dE00 of Mean Colors (reference vs glass)", value: ColorScience.deltaE2000(labR, labT), unit: "dE00", provenance: .derived,
            algorithm: "CIEDE2000 between Lab of mean linear colors", version: v, confidence: .high("Standard formula on direct averages"), sampleCount: n, region: roi,
            significantDigits: 3, sources: sources))
        out.append(Measurement(name: "Lightness L* (glass interior)", value: labT.L, unit: "L*", provenance: .derived, algorithm: "CIELAB (D65) of mean linear P3 color", version: v,
            confidence: .high("Standard conversion"), sampleCount: n, region: roi, significantDigits: 3, sources: sources, notes: "Reference L* = \(Format.number(labR.L, digits: 3))."))
        out.append(Measurement(name: "Chroma Ratio C*(glass)/C*(reference)", value: lchR.C > 1 ? lchT.C / lchR.C : nil, unit: "ratio", provenance: .derived,
            algorithm: "CIELCh chroma ratio of mean colors", version: v, confidence: lchR.C > 5 ? .high("Reference chroma \(Format.number(lchR.C, digits: 2))") : .low("Reference nearly achromatic"),
            sampleCount: n, region: roi, validity: lchR.C > 1 ? .valid : .notAvailable("Reference is achromatic (C* <= 1)"), significantDigits: 3, sources: sources))
        var dh = lchT.h - lchR.h
        if dh > 180 { dh -= 360 }; if dh < -180 { dh += 360 }
        out.append(Measurement(name: "Hue Shift (h glass - h reference)", value: (lchR.C > 5 && lchT.C > 5) ? dh : nil, unit: "deg", provenance: .derived,
            algorithm: "CIELCh hue difference of mean colors", version: v, confidence: .medium("Hue is unstable at low chroma"), sampleCount: n, region: roi,
            validity: (lchR.C > 5 && lchT.C > 5) ? .valid : .notAvailable("Chroma below 5: hue is undefined"), significantDigits: 3, sources: sources))
        let yT = ColorScience.luminanceP3(Float(mt.0), Float(mt.1), Float(mt.2)), yS = ColorScience.luminanceP3(Float(ms.0), Float(ms.1), Float(ms.2))
        out.append(Measurement(name: "Contrast Ratio (glass vs surround)", value: ColorScience.contrastRatio(Double(yT), Double(yS)), unit: ":1", provenance: .derived,
            algorithm: "WCAG 2.x (Y1+0.05)/(Y2+0.05) on relative digital luminance", version: v, confidence: .high("Standard formula"), sampleCount: n, region: roi,
            significantDigits: 3, sources: sources, notes: "Digital values, not measured display luminance."))
        return out
    }
}
