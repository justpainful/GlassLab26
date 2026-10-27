import XCTest
import CoreGraphics
@testable import GlassLab

/// Synthetic images with known ground truth, so the analysers can be checked numerically.
enum Synthetic {
    static func noise(_ w: Int, _ h: Int, seed: UInt64 = 7, cell: Int = 2) -> Plane {
        var p = Plane(width: w, height: h)
        for y in 0..<h { for x in 0..<w { p[x, y] = Float(ProceduralImageCache.hash(x / cell, y / cell, seed)) } }
        return p
    }

    static func image(_ p: Plane) -> LinearImage { LinearImage(r: p, g: p, b: p, sourceColorSpace: "test") }

    static func affine(_ p: Plane, gain: Float, offset: Float) -> Plane {
        var o = p
        for i in o.data.indices { o.data[i] = gain * p.data[i] + offset }
        return o
    }
}

final class ImageOperationTests: XCTestCase {
    func testGaussianPreservesMeanAndReducesVariance() {
        let n = Synthetic.noise(64, 64)
        let b = n.gaussianBlurred(sigma: 2)
        XCTAssertEqual(b.mean(), n.mean(), accuracy: 0.01)
        XCTAssertLessThan(b.std(), n.std() * 0.6)
        XCTAssertEqual(n.gaussianBlurred(sigma: 0).data, n.data)
    }

    func testCropShiftAndDownsample() {
        let n = Synthetic.noise(32, 32)
        let c = n.cropped(PixelRegion(x: 4, y: 4, width: 8, height: 8))
        XCTAssertEqual(c[0, 0], n[4, 4])
        let img = Synthetic.image(n).shifted(dx: 3, dy: 0)
        XCTAssertEqual(img.r[10, 5], n[7, 5])
        XCTAssertEqual(n.downsampled(by: 2).width, 16)
    }

    func testLinearDecodingOfSRGBGray() throws {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: space, components: [128.0 / 255, 128.0 / 255, 128.0 / 255, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let li = try XCTUnwrap(LinearImage(cgImage: ctx.makeImage()!))
        // sRGB 128/255 -> linear 0.2158; neutral gray maps to equal P3 channels.
        XCTAssertEqual(Double(li.r[1, 1]), 0.2158, accuracy: 0.004)
        XCTAssertEqual(Double(li.luminance()[1, 1]), 0.2158, accuracy: 0.004)
    }

    func testEncodeDecodeRoundTrip() throws {
        let n = Synthetic.noise(16, 16)
        let img = Synthetic.image(n)
        let cg = try XCTUnwrap(img.cgImage(bits16: true))
        let back = try XCTUnwrap(LinearImage(cgImage: cg))
        for i in stride(from: 0, to: 256, by: 17) { XCTAssertEqual(back.r.data[i], n.data[i], accuracy: 0.002) }
    }
}

final class RegionModelTests: XCTestCase {
    func testRoundedBoxAndCircle() {
        XCTAssertEqual(GlassRegionModel.roundedBox(0, 0, 10, 5, 0), -5, accuracy: 1e-12)
        XCTAssertEqual(GlassRegionModel.roundedBox(12, 0, 10, 5, 0), 2, accuracy: 1e-12)
        let m = GlassRegionModel(shape: .circle, elements: [CGRectCodable(CGRect(x: 0, y: 0, width: 20, height: 20))], cornerRadiusPx: 0, rotationDegrees: 0)
        XCTAssertEqual(m.signedDistance(10, 10), -10, accuracy: 1e-9)
        XCTAssertEqual(m.signedDistance(25, 10), 5, accuracy: 1e-9)
    }

    func testCapsuleAndStarSign() {
        let cap = GlassRegionModel(shape: .capsule, elements: [CGRectCodable(CGRect(x: 0, y: 0, width: 100, height: 40))], cornerRadiusPx: 0, rotationDegrees: 0)
        XCTAssertLessThan(cap.signedDistance(50, 20), 0)
        XCTAssertGreaterThan(cap.signedDistance(1, 1), 0)   // outside the rounded end
        let star = GlassRegionModel(shape: .customStar, elements: [CGRectCodable(CGRect(x: 0, y: 0, width: 100, height: 100))], cornerRadiusPx: 0, rotationDegrees: 0)
        XCTAssertLessThan(star.signedDistance(50, 50), 0)
        XCTAssertGreaterThan(star.signedDistance(2, 98), 0)
    }

    func testMasksPartition() {
        let m = GlassRegionModel(shape: .roundedRect, elements: [CGRectCodable(CGRect(x: 20, y: 20, width: 60, height: 40))], cornerRadiusPx: 8, rotationDegrees: 0)
        let k = m.masks(width: 100, height: 80, innerMargin: 4, edgeInner: 3, edgeOuter: 2, surroundGap: 4, surroundWidth: 6)
        XCTAssertGreaterThan(k.interior.count, 0)
        XCTAssertGreaterThan(k.surround.count, 0)
        XCTAssertEqual((k.interior & k.surround).count, 0)
        XCTAssertEqual(k.full.boundingBox?.width ?? 0, 60, accuracy: 1)
    }
}

final class OpticalAnalyzerTests: XCTestCase {
    /// Test frame = 0.7 * Gaussian(sigma 3) of the reference + 0.1 inside the glass; identical outside.
    func makePair(sigma: Double = 3, shift: Int = 0) -> (LinearImage, LinearImage, GlassRegionModel) {
        let w = 160, h = 120
        let ref = Synthetic.noise(w, h, cell: 2)
        let region = GlassRegionModel(shape: .roundedRect, elements: [CGRectCodable(CGRect(x: 30, y: 25, width: 100, height: 70))], cornerRadiusPx: 12, rotationDegrees: 0)
        var src = ref
        if shift != 0 { src = Synthetic.image(ref).shifted(dx: shift, dy: 0).r }
        let glass = Synthetic.affine(src.gaussianBlurred(sigma: sigma), gain: 0.7, offset: 0.1)
        var test = ref
        for y in 0..<h { for x in 0..<w where region.signedDistance(Double(x) + 0.5, Double(y) + 0.5) <= 0 { test[x, y] = glass[x, y] } }
        return (Synthetic.image(ref), Synthetic.image(test), region)
    }

    func testBlurFitRecoversSigmaGainOffset() {
        let (ref, test, region) = makePair()
        let masks = region.masks(width: ref.width, height: ref.height, innerMargin: 10, edgeInner: 0, edgeOuter: 0, surroundGap: 0, surroundWidth: 0)
        let r = OpticalAnalyzer.fitBlur(ref.luminance(), test.luminance(), mask: masks.interior)
        XCTAssertEqual(r.sigma, 3, accuracy: 0.25)
        XCTAssertEqual(r.fit!.gain, 0.7, accuracy: 0.02)
        XCTAssertEqual(r.fit!.offset, 0.1, accuracy: 0.02)
        XCTAssertGreaterThan(r.fit!.r2, 0.99)
    }

    func testDisplacementFieldDetectsShift() {
        let (ref, test, region) = makePair(sigma: 0.0, shift: 3)
        let masks = region.masks(width: ref.width, height: ref.height, innerMargin: 0, edgeInner: 0, edgeOuter: 0, surroundGap: 0, surroundWidth: 0)
        let field = OpticalAnalyzer.displacementField(ref.luminance(), test.luminance(), inside: masks.full, sdf: masks.sdf, maxShift: 8)
        let acc = field.filter(\.accepted)
        XCTAssertGreaterThan(acc.count, 10)
        // test(x) = ref(x - 3): content at x came from x - 3, so dx = -3.
        XCTAssertEqual(Statistics.median(acc.map(\.dx)), -3, accuracy: 0.3)
        XCTAssertEqual(Statistics.median(acc.map(\.dy)), 0, accuracy: 0.3)
    }

    func testFullAnalysisProducesProvenancedResults() throws {
        let (ref, test, region) = makePair()
        var bg = BackgroundSpec.pattern(.highFrequencyNoise)
        bg.patternScale = 2
        let input = OpticalInput(reference: ref, test: test, region: region, pixelsPerPoint: 2, background: bg,
                                 modules: [.statistics, .translucency, .blur, .highlights, .color, .errorMetrics], sources: ["ref", "test"])
        let rep = try OpticalAnalyzer.analyze(input)
        XCTAssertFalse(rep.measurements.isEmpty)
        let sigma = try XCTUnwrap(rep.measurements.first { $0.name.hasPrefix("Apparent Blur Radius") })
        XCTAssertEqual(sigma.provenance, .estimated)
        XCTAssertEqual(try XCTUnwrap(sigma.value), 1.5, accuracy: 0.15)   // 3 px at 2 px/pt
        for m in rep.measurements {
            XCTAssertFalse(m.algorithm.isEmpty, m.name)
            XCTAssertFalse(m.algorithmVersion.isEmpty, m.name)
            if m.value == nil { XCTAssertFalse(m.validity.reasons.isEmpty, "N/A without a reason: \(m.name)") }
        }
        let residual = try XCTUnwrap(rep.measurements.first { $0.name.hasPrefix("Surround Residual") })
        XCTAssertEqual(try XCTUnwrap(residual.value), 0, accuracy: 1e-6)
    }

    func testUniformBackgroundGivesNAForBlur() throws {
        let w = 120, h = 90
        let ref = Synthetic.image(Plane(width: w, height: h, fill: 0.5))
        let test = Synthetic.image(Plane(width: w, height: h, fill: 0.6))
        let region = GlassRegionModel(shape: .capsule, elements: [CGRectCodable(CGRect(x: 20, y: 20, width: 80, height: 50))], cornerRadiusPx: 0, rotationDegrees: 0)
        let rep = try OpticalAnalyzer.analyze(OpticalInput(reference: ref, test: test, region: region, pixelsPerPoint: 1,
                                                           background: .solid(.neutralGray), modules: [.blur, .refraction], sources: []))
        let blur = try XCTUnwrap(rep.measurements.first { $0.name.hasPrefix("Apparent Blur Radius") })
        XCTAssertNil(blur.value)
        XCTAssertEqual(blur.validity.status, .notAvailable)
    }
}

final class ImageMetricsTests: XCTestCase {
    func testIdenticalImages() throws {
        let img = Synthetic.image(Synthetic.noise(40, 40))
        let m = try XCTUnwrap(ImageMetrics.compare(img, img, mask: nil))
        XCTAssertEqual(m.mae, 0, accuracy: 1e-9)
        XCTAssertEqual(m.ssim, 1, accuracy: 1e-6)
        XCTAssertFalse(m.psnr.isFinite)
        XCTAssertEqual(m.deltaEMean, 0, accuracy: 1e-9)
    }

    func testDifferentImages() throws {
        let a = Synthetic.image(Synthetic.noise(40, 40, seed: 1)), b = Synthetic.image(Synthetic.noise(40, 40, seed: 2))
        let m = try XCTUnwrap(ImageMetrics.compare(a, b, mask: nil))
        XCTAssertGreaterThan(m.mae, 0.1)
        XCTAssertLessThan(m.ssim, 0.5)
        XCTAssertGreaterThan(m.deltaEMean, 5)
    }

    func testEdgeAlignment() throws {
        let a = Synthetic.noise(40, 40, cell: 4)
        let e = try XCTUnwrap(ImageMetrics.edgeAlignmentError(a, a, mask: nil))
        XCTAssertEqual(e.mean, 0, accuracy: 1e-9)
    }
}

final class MeasurementModelTests: XCTestCase {
    func testNonFiniteValuesBecomeNA() {
        let m = Measurement(name: "x", value: .nan, unit: "", provenance: .measured, algorithm: "a", version: "1", confidence: .high("t"), sampleCount: 1)
        XCTAssertNil(m.value)
    }

    func testFormattingRespectsSignificantDigits() {
        XCTAssertEqual(Format.number(3.14159, digits: 3), "3.14")
        XCTAssertEqual(Format.number(0.0012345, digits: 2), "0.0012")
        XCTAssertEqual(Format.number(nil), "N/A")
        XCTAssertEqual(Format.number(1234.6, digits: 3), "1235")
    }
}
