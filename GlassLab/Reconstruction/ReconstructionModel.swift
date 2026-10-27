import Foundation
import CoreGraphics

/// An independent, deliberately simple parametric glass model used ONLY in the Reconstruction Lab.
/// It is never shown as Apple Liquid Glass. Stages:
/// background sampling -> distortion field -> spatial blur -> color adaptation (saturation) ->
/// transmission + per-channel additive term (tint) -> edge highlight -> final compositing.
struct ReconstructionParameters: Codable, Hashable, Sendable {
    static let names = ["Blur sigma", "Transmission g", "Offset R", "Offset G", "Offset B", "Saturation",
                        "Highlight amplitude", "Highlight width", "Refraction strength", "Rim width"]
    static let units = ["pt", "", "linear", "linear", "linear", "", "linear", "pt", "pt", "pt"]
    static let lower: [Double] = [0, 0, -0.5, -0.5, -0.5, 0, -0.5, 0.25, -30, 1]
    static let upper: [Double] = [40, 1.5, 1.0, 1.0, 1.0, 3, 1.0, 20, 30, 60]
    static let steps: [Double] = [3, 0.15, 0.05, 0.05, 0.05, 0.3, 0.05, 1.5, 3, 5]
    static let initial: [Double] = [6, 0.8, 0.05, 0.05, 0.05, 1.2, 0.05, 2, 4, 12]

    var values: [Double] = ReconstructionParameters.initial

    var blurSigma: Double { values[0] }
    var transmission: Double { values[1] }
    var offset: (Double, Double, Double) { (values[2], values[3], values[4]) }
    var saturation: Double { values[5] }
    var highlightAmplitude: Double { values[6] }
    var highlightWidth: Double { values[7] }
    var refraction: Double { values[8] }
    var rimWidth: Double { values[9] }
}

/// One training or validation sample prepared for fast model evaluation.
struct ReconstructionSample: @unchecked Sendable {
    var name: String
    var background: LinearImage   // reference frame (no glass), ROI crop, downsampled
    var target: LinearImage       // native glass frame, same crop
    var sdf: Plane                // signed distance in analysis pixels
    var normalX: Plane
    var normalY: Plane
    var mask: Mask                // pixels that contribute to the loss (glass + 2 pt band)
    var ptPerPx: Double

    /// Prepares a sample: crop to the glass with a margin, downsample to <= maxSide.
    static func make(name: String, reference: LinearImage, test: LinearImage, region: GlassRegionModel, ppp: Double, maxSide: Int = 160) -> ReconstructionSample? {
        guard reference.width == test.width, reference.height == test.height else { return nil }
        let bb = region.boundingBox.insetBy(dx: -8 * ppp, dy: -8 * ppp).intersection(CGRect(x: 0, y: 0, width: reference.width, height: reference.height)).integral
        guard bb.width > 8, bb.height > 8 else { return nil }
        let crop = PixelRegion(bb)
        let f = max(1, Int(ceil(Double(max(crop.width, crop.height)) / Double(maxSide))))
        let bg = reference.cropped(crop).downsampled(by: f), tg = test.cropped(crop).downsampled(by: f)
        let rm = region.translated(dx: -Double(crop.x), dy: -Double(crop.y)).scaled(by: 1 / Double(f))
        let ptPerPx = Double(f) / ppp
        let masks = rm.masks(width: bg.width, height: bg.height, innerMargin: 0, edgeInner: 0, edgeOuter: 2 / ptPerPx, surroundGap: 0, surroundWidth: 0)
        var lossMask = masks.full
        for i in lossMask.data.indices where masks.sdf.data[i] <= Float(2 / ptPerPx) { lossMask.data[i] = 1 }
        var nx = Plane(width: bg.width, height: bg.height), ny = Plane(width: bg.width, height: bg.height)
        let s = masks.sdf
        for y in 0..<s.height { for x in 0..<s.width {
            let gx = s[min(x + 1, s.width - 1), y] - s[max(x - 1, 0), y]
            let gy = s[x, min(y + 1, s.height - 1)] - s[x, max(y - 1, 0)]
            let l = max(1e-6, (gx * gx + gy * gy).squareRoot())
            nx[x, y] = gx / l; ny[x, y] = gy / l
        } }
        return ReconstructionSample(name: name, background: bg, target: tg, sdf: s, normalX: nx, normalY: ny, mask: lossMask, ptPerPx: ptPerPx)
    }
}

enum ReconstructionRenderer {
    /// Renders the model over the sample's background. Outside the glass the background is passed through.
    static func render(_ p: ReconstructionParameters, _ s: ReconstructionSample) -> LinearImage {
        let w = s.background.width, h = s.background.height
        let pxPerPt = 1 / s.ptPerPx
        // 1-2. Background sampling with a rim-weighted displacement along the outline normal.
        var warped = LinearImage(width: w, height: h)
        warped.sourceColorSpace = s.background.sourceColorSpace
        let k = p.refraction * pxPerPt, rim = max(0.5, p.rimWidth * pxPerPt)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let d = Double(s.sdf.data[i])
                var sx = Double(x), sy = Double(y)
                if d <= 0 && k != 0 {
                    let f = max(0, 1 + d / rim)
                    let amount = k * f * f
                    sx += amount * Double(s.normalX.data[i]); sy += amount * Double(s.normalY.data[i])
                }
                warped.r.data[i] = s.background.r.sample(sx, sy)
                warped.g.data[i] = s.background.g.sample(sx, sy)
                warped.b.data[i] = s.background.b.sample(sx, sy)
            }
        }
        // 3. Spatial blur
        let blurred = warped.blurred(sigma: p.blurSigma * pxPerPt)
        // 4-7. Color adaptation, transmission, tint offset, edge highlight, compositing
        var out = s.background
        let g = Float(p.transmission), sat = Float(p.saturation)
        let o = (Float(p.offset.0), Float(p.offset.1), Float(p.offset.2))
        let amp = Float(p.highlightAmplitude), hw = max(0.25, p.highlightWidth * pxPerPt)
        for i in 0..<(w * h) {
            let d = Double(s.sdf.data[i])
            guard d <= 0 else { continue }
            let r = blurred.r.data[i], gg = blurred.g.data[i], b = blurred.b.data[i]
            let yv = ColorScience.luminanceP3(r, gg, b)
            let hl = amp * Float(exp(-(d * d) / (hw * hw)))
            out.r.data[i] = g * (yv + sat * (r - yv)) + o.0 + hl
            out.g.data[i] = g * (yv + sat * (gg - yv)) + o.1 + hl
            out.b.data[i] = g * (yv + sat * (b - yv)) + o.2 + hl
            // Anti-aliased outline: blend over the last pixel.
            if d > -1 {
                let a = Float(-d)
                out.r.data[i] = a * out.r.data[i] + (1 - a) * s.background.r.data[i]
                out.g.data[i] = a * out.g.data[i] + (1 - a) * s.background.g.data[i]
                out.b.data[i] = a * out.b.data[i] + (1 - a) * s.background.b.data[i]
            }
        }
        return out
    }

    /// Mean squared error over the sample's loss mask (linear RGB).
    static func loss(_ p: ReconstructionParameters, _ s: ReconstructionSample) -> (mse: Double, count: Int) {
        let out = render(p, s)
        var sum = 0.0, n = 0
        for i in s.mask.data.indices where s.mask.data[i] != 0 {
            let dr = Double(out.r.data[i] - s.target.r.data[i]), dg = Double(out.g.data[i] - s.target.g.data[i]), db = Double(out.b.data[i] - s.target.b.data[i])
            sum += dr * dr + dg * dg + db * db; n += 3
        }
        return (n > 0 ? sum / Double(n) : .nan, n)
    }
}
