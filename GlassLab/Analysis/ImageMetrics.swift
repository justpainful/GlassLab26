import Foundation
import CoreGraphics

/// Full-reference image comparison metrics. Inputs are linear Display P3; metrics that are defined
/// on encoded values (PSNR, SSIM) re-encode with the sRGB transfer curve first and say so.
enum ImageMetrics {
    struct Result: Sendable {
        var mae: Double
        var rmse: Double
        var psnr: Double
        var ssim: Double
        var deltaEMean: Double
        var deltaEP95: Double
        var deltaEMax: Double
        var deltaEMap: Plane
        var sampleCount: Int
    }

    static func encode(_ p: Plane) -> Plane {
        var o = p
        for i in o.data.indices { o.data[i] = Float(ColorScience.linearToSRGB(Double(max(0, min(1, p.data[i]))))) }
        return o
    }

    static func compare(_ a: LinearImage, _ b: LinearImage, mask: Mask?) -> Result? {
        guard a.width == b.width, a.height == b.height else { return nil }
        let n = a.width * a.height
        var absSum = 0.0, sqSum = 0.0, count = 0
        var de = Plane(width: a.width, height: a.height)
        var deValues: [Double] = []
        let ea = [encode(a.r), encode(a.g), encode(a.b)]
        let eb = [encode(b.r), encode(b.g), encode(b.b)]
        for i in 0..<n {
            if let m = mask, m.data[i] == 0 { continue }
            for c in 0..<3 {
                let d = Double(ea[c].data[i] - eb[c].data[i])
                absSum += abs(d); sqSum += d * d
            }
            let la = ColorScience.labFromLinearP3(Double(a.r.data[i]), Double(a.g.data[i]), Double(a.b.data[i]))
            let lb = ColorScience.labFromLinearP3(Double(b.r.data[i]), Double(b.g.data[i]), Double(b.b.data[i]))
            let e = ColorScience.deltaE2000(la, lb)
            de.data[i] = Float(e)
            deValues.append(e)
            count += 1
        }
        guard count > 0 else { return nil }
        let mae = absSum / Double(count * 3)
        let mse = sqSum / Double(count * 3)
        let psnr = mse > 0 ? 10 * log10(1 / mse) : .infinity
        let ssim = meanSSIM(luma(ea), luma(eb), mask: mask)
        return Result(mae: mae, rmse: mse.squareRoot(), psnr: psnr, ssim: ssim,
                      deltaEMean: Statistics.mean(deValues), deltaEP95: Statistics.quantile(deValues, 0.95),
                      deltaEMax: deValues.max() ?? .nan, deltaEMap: de, sampleCount: count)
    }

    /// Rec. 709 luma of encoded planes (for SSIM, which is defined on gamma-encoded signals).
    static func luma(_ p: [Plane]) -> Plane {
        var o = Plane(width: p[0].width, height: p[0].height)
        for i in o.data.indices { o.data[i] = 0.2126 * p[0].data[i] + 0.7152 * p[1].data[i] + 0.0722 * p[2].data[i] }
        return o
    }

    /// Mean SSIM with an 11-tap Gaussian window (sigma 1.5), K1 = 0.01, K2 = 0.03, L = 1 (Wang et al. 2004).
    static func meanSSIM(_ x: Plane, _ y: Plane, mask: Mask?) -> Double {
        let c1: Float = 0.0001, c2: Float = 0.0009
        var xx = x, yy = y, xy = x
        for i in x.data.indices { xx.data[i] = x.data[i] * x.data[i]; yy.data[i] = y.data[i] * y.data[i]; xy.data[i] = x.data[i] * y.data[i] }
        let mx = x.gaussianBlurred(sigma: 1.5), my = y.gaussianBlurred(sigma: 1.5)
        let sxx = xx.gaussianBlurred(sigma: 1.5), syy = yy.gaussianBlurred(sigma: 1.5), sxy = xy.gaussianBlurred(sigma: 1.5)
        var s = 0.0, n = 0
        for i in x.data.indices {
            if let m = mask, m.data[i] == 0 { continue }
            let ux = mx.data[i], uy = my.data[i]
            let vx = sxx.data[i] - ux * ux, vy = syy.data[i] - uy * uy, cxy = sxy.data[i] - ux * uy
            let num = (2 * ux * uy + c1) * (2 * cxy + c2)
            let den = (ux * ux + uy * uy + c1) * (vx + vy + c2)
            s += Double(num / den); n += 1
        }
        return n > 0 ? s / Double(n) : .nan
    }

    /// Mean distance between Sobel edge maps: for each strong edge pixel in `a`, the distance to the nearest
    /// strong edge pixel in `b` within `radius`. Pixels with no match count as `radius`.
    static func edgeAlignmentError(_ a: Plane, _ b: Plane, mask: Mask?, radius: Int = 6) -> (mean: Double, count: Int)? {
        let ga = a.gradientMagnitude(), gb = b.gradientMagnitude()
        let ta = Float(Statistics.quantile(ga.data.map(Double.init), 0.9))
        let tb = Float(Statistics.quantile(gb.data.map(Double.init), 0.9))
        guard ta > 1e-5, tb > 1e-5 else { return nil }
        var total = 0.0, count = 0
        let w = a.width, h = a.height
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if let m = mask, m.data[i] == 0 { continue }
                guard ga.data[i] >= ta else { continue }
                var best = Double(radius)
                for dy in -radius...radius {
                    let yy = y + dy
                    if yy < 0 || yy >= h { continue }
                    for dx in -radius...radius {
                        let xx = x + dx
                        if xx < 0 || xx >= w { continue }
                        if gb.data[yy * w + xx] >= tb {
                            best = min(best, Double(dx * dx + dy * dy).squareRoot())
                        }
                    }
                }
                total += best; count += 1
            }
        }
        return count > 0 ? (total / Double(count), count) : nil
    }
}
