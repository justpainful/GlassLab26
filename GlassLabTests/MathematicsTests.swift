import XCTest
@testable import GlassLab

final class ColorScienceTests: XCTestCase {
    func testTransferFunctionRoundTrip() {
        for v in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(ColorScience.linearToSRGB(ColorScience.srgbToLinear(v)), v, accuracy: 1e-12)
        }
        XCTAssertEqual(ColorScience.srgbToLinear(0.5), 0.21404, accuracy: 1e-5)
        XCTAssertEqual(ColorScience.srgbToLinear(0.04045), 0.04045 / 12.92, accuracy: 1e-12)
    }

    func testWhiteLuminanceAndLab() {
        XCTAssertEqual(Double(ColorScience.luminanceP3(1, 1, 1)), 1, accuracy: 1e-6)
        XCTAssertEqual(ColorScience.luminanceSRGB(1, 1, 1), 1, accuracy: 1e-6)
        let lab = ColorScience.labFromLinearP3(1, 1, 1)
        XCTAssertEqual(lab.L, 100, accuracy: 0.01)
        XCTAssertEqual(lab.a, 0, accuracy: 0.05)
        XCTAssertEqual(lab.b, 0, accuracy: 0.05)
        let black = ColorScience.labFromLinearSRGB(0, 0, 0)
        XCTAssertEqual(black.L, 0, accuracy: 1e-9)
    }

    /// Reference pairs from Sharma, Wu & Dalal (2005), Table 1.
    func testDeltaE2000ReferenceData() {
        let cases: [((Double, Double, Double), (Double, Double, Double), Double)] = [
            ((50.0000, 2.6772, -79.7751), (50.0000, 0.0000, -82.7485), 2.0425),
            ((50.0000, 3.1571, -77.2803), (50.0000, 0.0000, -82.7485), 2.8615),
            ((50.0000, 2.8361, -74.0200), (50.0000, 0.0000, -82.7485), 3.4412),
            ((50.0000, -1.3802, -84.2814), (50.0000, 0.0000, -82.7485), 1.0000),
            ((50.0000, 0.0000, 0.0000), (50.0000, -1.0000, 2.0000), 2.3669),
            ((50.0000, 2.4900, -0.0010), (50.0000, -2.4900, 0.0009), 7.1792),
            ((60.2574, -34.0099, 36.2677), (60.4626, -34.1751, 39.4387), 1.2644),
            ((22.7233, 20.0904, -46.6940), (23.0331, 14.9730, -42.5619), 2.0373),
            ((2.0776, 0.0795, -1.1350), (0.9033, -0.0636, -0.5514), 0.9082),
        ]
        for (a, b, expected) in cases {
            let d1 = ColorScience.deltaE2000((a.0, a.1, a.2), (b.0, b.1, b.2))
            let d2 = ColorScience.deltaE2000((b.0, b.1, b.2), (a.0, a.1, a.2))
            XCTAssertEqual(d1, expected, accuracy: 1e-4, "\(a) vs \(b)")
            XCTAssertEqual(d1, d2, accuracy: 1e-9, "symmetry")
        }
    }

    func testContrastRatio() {
        XCTAssertEqual(ColorScience.contrastRatio(1, 0), 21, accuracy: 1e-9)
        XCTAssertEqual(ColorScience.contrastRatio(0.18, 0.18), 1, accuracy: 1e-9)
    }

    func testHexAndHSV() {
        let c = RGBAColor(hex: "#FF8000")!
        XCTAssertEqual(c.r, 1); XCTAssertEqual(c.g, 128.0 / 255, accuracy: 1e-9); XCTAssertEqual(c.b, 0)
        XCTAssertEqual(c.hex, "#FF8000")
        XCTAssertEqual(c.hsv.h, 30.1, accuracy: 0.2)
        let back = RGBAColor.fromHSV(h: 120, s: 1, v: 1)
        XCTAssertEqual(back.g, 1, accuracy: 1e-9); XCTAssertEqual(back.r, 0, accuracy: 1e-9)
        XCTAssertNil(RGBAColor(hex: "zzz"))
    }
}

final class StatisticsTests: XCTestCase {
    func testSummary() {
        let s = Statistics.summary([2, 4, 4, 4, 5, 5, 7, 9])
        XCTAssertEqual(s.mean, 5, accuracy: 1e-12)
        XCTAssertEqual(s.median, 4.5, accuracy: 1e-12)
        XCTAssertEqual(s.standardDeviation, 2.13809, accuracy: 1e-5)
        XCTAssertEqual(s.min, 2); XCTAssertEqual(s.max, 9)
        XCTAssertEqual(s.ci95HalfWidth!, 2.365 * 2.13809 / 8.0.squareRoot(), accuracy: 1e-3)
    }

    func testQuantileAndOutliers() {
        XCTAssertEqual(Statistics.quantile([1, 2, 3, 4, 5], 0.25), 2, accuracy: 1e-12)
        XCTAssertEqual(Statistics.outlierIndices([10, 10.1, 9.9, 10.05, 9.95, 30]), [5])
        XCTAssertEqual(Statistics.outlierIndices([1, 1, 1]), [])
    }

    func testLinearFit() {
        let x = [0.0, 1, 2, 3], y = x.map { 2 * $0 + 1 }
        let f = Statistics.linearFit(x: x, y: y)!
        XCTAssertEqual(f.slope, 2, accuracy: 1e-12); XCTAssertEqual(f.intercept, 1, accuracy: 1e-12); XCTAssertEqual(f.r2, 1, accuracy: 1e-12)
        XCTAssertNil(Statistics.linearFit(x: [1, 1], y: [1, 2]))
    }

    func testTCritical() {
        XCTAssertEqual(Statistics.tCritical95(df: 1), 12.706)
        XCTAssertEqual(Statistics.tCritical95(df: 1000), 1.96)
    }

    func testHistogram() {
        let h = Statistics.histogram([0, 0.1, 0.5, 0.99, 1.0, 2.0], bins: 2, range: 0...1)
        XCTAssertEqual(h, [2, 4])
    }
}

final class OptimizationTests: XCTestCase {
    func testNelderMeadRosenbrock() {
        let r = Optimization.nelderMead(start: [-1.2, 1], step: [0.5, 0.5], lower: [-5, -5], upper: [5, 5], maxIterations: 2000, tolerance: 1e-12) { p in
            let a = 1 - p[0], b = p[1] - p[0] * p[0]
            return a * a + 100 * b * b
        }
        XCTAssertEqual(r.x[0], 1, accuracy: 1e-2)
        XCTAssertEqual(r.x[1], 1, accuracy: 2e-2)
    }

    func testGoldenSection() {
        let r = Optimization.goldenSection(0, 5, tolerance: 1e-6) { ($0 - 2.5) * ($0 - 2.5) }
        XCTAssertEqual(r.x, 2.5, accuracy: 1e-4)
    }

    func testDFTOfConstant() {
        let m = Spectral.dftMagnitude([1, 1, 1, 1])
        XCTAssertEqual(m[0], 4, accuracy: 1e-9)
        XCTAssertEqual(m[1], 0, accuracy: 1e-9)
    }
}

final class TimeSeriesTests: XCTestCase {
    func testStepResponseOfSpring() {
        let omega = 30.0, zeta = 0.3
        let t = stride(from: 0.0, through: 1.0, by: 1.0 / 240).map { $0 }
        let y = t.map { $0 < 0.1 ? 0 : TimeSeries.springStep(t: $0 - 0.1, omega: omega, zeta: zeta) }
        let r = TimeSeries.stepResponse(t: t, y: y, stimulusTime: 0.1)!
        let expectedOvershoot = exp(-zeta * .pi / (1 - zeta * zeta).squareRoot())
        XCTAssertEqual(r.overshoot!, expectedOvershoot, accuracy: 0.02)
        XCTAssertNotNil(r.riseTime)
        XCTAssertEqual(r.dampingRatio!, zeta, accuracy: 0.05)
        let wd = omega * (1 - zeta * zeta).squareRoot()
        XCTAssertEqual(r.oscillationFrequency!, wd / (2 * .pi), accuracy: 0.3)
    }

    func testSpringFitRecoversParameters() {
        let t = stride(from: 0.0, through: 0.8, by: 1.0 / 120).map { $0 }
        let y = t.map { TimeSeries.springStep(t: $0 - 0.05, omega: 25, zeta: 0.5) }
        let f = TimeSeries.fitSpring(t: t, normalized: y, t0: 0)!
        XCTAssertEqual(f.zeta, 0.5, accuracy: 0.05)
        XCTAssertEqual(f.omega, 25, accuracy: 2.5)
        XCTAssertGreaterThan(f.r2, 0.99)
    }

    func testUnresolvedRiseWarns() {
        let t = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        let y = [0.0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1]
        let r = TimeSeries.stepResponse(t: t, y: y)!
        XCTAssertFalse(r.warnings.isEmpty)
    }
}
