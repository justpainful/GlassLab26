import Foundation
import CoreGraphics

/// Renders scalar and vector fields to images. Colormaps are perceptually ordered so that
/// heatmaps can be read quantitatively next to their legend.
enum Heatmap {
    enum Colormap: String, Codable, CaseIterable, Sendable {
        case viridis = "Viridis"
        case magma = "Magma"
        case diverging = "Diverging (blue-white-red)"
        case gray = "Gray"
    }

    struct Legend: Codable, Hashable, Sendable {
        var minValue: Double
        var maxValue: Double
        var unit: String
        var colormap: Colormap
    }

    private static let viridisStops: [(Double, Double, Double)] = [
        (0.267, 0.005, 0.329), (0.283, 0.141, 0.458), (0.254, 0.265, 0.530), (0.207, 0.372, 0.553),
        (0.164, 0.471, 0.558), (0.128, 0.567, 0.551), (0.135, 0.659, 0.518), (0.267, 0.749, 0.441),
        (0.478, 0.821, 0.318), (0.741, 0.873, 0.150), (0.993, 0.906, 0.144),
    ]
    private static let magmaStops: [(Double, Double, Double)] = [
        (0.001, 0.000, 0.014), (0.087, 0.045, 0.224), (0.232, 0.059, 0.437), (0.390, 0.100, 0.502),
        (0.550, 0.161, 0.506), (0.716, 0.215, 0.475), (0.868, 0.288, 0.409), (0.967, 0.439, 0.360),
        (0.994, 0.624, 0.427), (0.995, 0.807, 0.565), (0.987, 0.991, 0.750),
    ]

    static func color(_ t: Double, _ map: Colormap) -> (Double, Double, Double) {
        let u = max(0, min(1, t.isFinite ? t : 0))
        switch map {
        case .gray: return (u, u, u)
        case .diverging:
            if u < 0.5 { let k = u / 0.5; return (0.15 + 0.85 * k, 0.35 + 0.65 * k, 0.85 + 0.15 * k) }
            let k = (u - 0.5) / 0.5; return (1.0, 1.0 - 0.75 * k, 1.0 - 0.8 * k)
        case .viridis, .magma:
            let stops = map == .viridis ? viridisStops : magmaStops
            let f = u * Double(stops.count - 1)
            let i = min(Int(f), stops.count - 2), k = f - Double(i)
            let a = stops[i], b = stops[i + 1]
            return (a.0 + (b.0 - a.0) * k, a.1 + (b.1 - a.1) * k, a.2 + (b.2 - a.2) * k)
        }
    }

    /// Renders a plane. Pixels outside `mask` are drawn as neutral dark gray.
    static func render(_ p: Plane, mask: Mask? = nil, range: ClosedRange<Double>? = nil, colormap: Colormap = .viridis, unit: String = "") -> (CGImage?, Legend) {
        var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
        if let range { lo = range.lowerBound; hi = range.upperBound } else {
            for i in p.data.indices where (mask == nil || mask!.data[i] != 0) && p.data[i].isFinite {
                lo = min(lo, Double(p.data[i])); hi = max(hi, Double(p.data[i]))
            }
            if lo > hi { lo = 0; hi = 1 }
            if colormap == .diverging { let m = max(abs(lo), abs(hi)); lo = -m; hi = m }
        }
        if hi - lo < 1e-12 { hi = lo + 1e-12 }
        let w = p.width, h = p.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let inside = mask == nil || mask!.data[i] != 0
            let c = inside ? color((Double(p.data[i]) - lo) / (hi - lo), colormap) : (0.18, 0.18, 0.18)
            bytes[i * 4] = UInt8(c.0 * 255); bytes[i * 4 + 1] = UInt8(c.1 * 255); bytes[i * 4 + 2] = UInt8(c.2 * 255); bytes[i * 4 + 3] = 255
        }
        let legend = Legend(minValue: lo, maxValue: hi, unit: unit, colormap: colormap)
        return (makeImage(bytes, w, h), legend)
    }

    static func makeImage(_ bytes: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        var b = bytes
        return b.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }

    /// Draws displacement vectors (scaled by `gain`) over a base image. Rejected vectors are drawn as small gray dots.
    static func vectorField(base: CGImage?, width: Int, height: Int, vectors: [DisplacementVector], gain: Double) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Core Graphics origin is bottom-left; flip so vectors use image (top-left) coordinates.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        if let base {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
            ctx.restoreGState()
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        } else {
            ctx.setFillColor(CGColor(gray: 0.12, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let maxMag = max(vectors.filter(\.accepted).map(\.magnitude).max() ?? 1, 1e-6)
        ctx.setLineWidth(max(1, CGFloat(width) / 400))
        for v in vectors {
            let p = CGPoint(x: v.x, y: v.y)
            if !v.accepted {
                ctx.setFillColor(CGColor(gray: 0.6, alpha: 0.6))
                ctx.fillEllipse(in: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2))
                continue
            }
            let c = color(v.magnitude / maxMag, .magma)
            ctx.setStrokeColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
            let q = CGPoint(x: v.x + v.dx * gain, y: v.y + v.dy * gain)
            ctx.move(to: p); ctx.addLine(to: q); ctx.strokePath()
            ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: q.x - 1.5, y: q.y - 1.5, width: 3, height: 3))
        }
        return ctx.makeImage()
    }

    /// Amplified absolute difference image of two linear images, for visual comparison.
    static func difference(_ a: LinearImage, _ b: LinearImage, gain: Float = 4) -> CGImage? {
        guard a.width == b.width, a.height == b.height else { return nil }
        var bytes = [UInt8](repeating: 255, count: a.width * a.height * 4)
        for i in 0..<(a.width * a.height) {
            let d = [abs(a.r.data[i] - b.r.data[i]), abs(a.g.data[i] - b.g.data[i]), abs(a.b.data[i] - b.b.data[i])]
            for c in 0..<3 {
                let e = ColorScience.linearToSRGB(Double(min(1, d[c] * gain)))
                bytes[i * 4 + c] = UInt8(max(0, min(255, e * 255)))
            }
        }
        return makeImage(bytes, a.width, a.height)
    }
}

/// One displacement estimate from block matching (pixels, analysis-image coordinates).
struct DisplacementVector: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var dx: Double
    var dy: Double
    var correlation: Double
    var ambiguity: Double
    var accepted: Bool
    var rejectionReason: String?
    var magnitude: Double { (dx * dx + dy * dy).squareRoot() }
}
