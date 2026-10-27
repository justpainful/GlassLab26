import Foundation
import CoreGraphics

/// Geometric description of the glass subject inside an analysis image, used to build
/// interior / edge / surround masks from a signed distance field (negative inside).
struct GlassRegionModel: Codable, Hashable, Sendable {
    var shape: GlassShapeKind
    /// Element frames in analysis-image pixels (unrotated).
    var elements: [CGRectCodable]
    var cornerRadiusPx: Double
    var rotationDegrees: Double

    /// Signed distance (pixels) from the nearest element boundary. Negative inside.
    func signedDistance(_ px: Double, _ py: Double) -> Double {
        var best = Double.greatestFiniteMagnitude
        for e in elements {
            best = min(best, Self.elementSDF(px, py, rect: e.cgRect, shape: shape, corner: cornerRadiusPx, rotation: rotationDegrees))
        }
        return best
    }

    static func elementSDF(_ px: Double, _ py: Double, rect: CGRect, shape: GlassShapeKind, corner: Double, rotation: Double) -> Double {
        let cx = Double(rect.midX), cy = Double(rect.midY)
        let a = -rotation * .pi / 180
        let dx = px - cx, dy = py - cy
        let x = dx * cos(a) - dy * sin(a), y = dx * sin(a) + dy * cos(a)
        let hw = Double(rect.width) / 2, hh = Double(rect.height) / 2
        switch shape {
        case .rect: return roundedBox(x, y, hw, hh, 0)
        case .roundedRect: return roundedBox(x, y, hw, hh, min(corner, min(hw, hh)))
        case .capsule: return roundedBox(x, y, hw, hh, min(hw, hh))
        case .circle:
            let r = min(hw, hh)
            return (x * x + y * y).squareRoot() - r
        case .ellipse: return ellipse(x, y, hw, hh)
        case .customStar: return polygon(x, y, StarGeometry.points(radius: min(hw, hh)))
        }
    }

    static func roundedBox(_ x: Double, _ y: Double, _ hw: Double, _ hh: Double, _ r: Double) -> Double {
        let qx = abs(x) - (hw - r), qy = abs(y) - (hh - r)
        let ox = max(qx, 0), oy = max(qy, 0)
        return (ox * ox + oy * oy).squareRoot() + min(max(qx, qy), 0) - r
    }

    /// Approximate ellipse distance (exact sign, distance accurate near the boundary).
    static func ellipse(_ x: Double, _ y: Double, _ a: Double, _ b: Double) -> Double {
        guard a > 0, b > 0 else { return .greatestFiniteMagnitude }
        let k0 = ((x / a) * (x / a) + (y / b) * (y / b)).squareRoot()
        let k1 = ((x / (a * a)) * (x / (a * a)) + (y / (b * b)) * (y / (b * b))).squareRoot()
        guard k1 > 0 else { return -min(a, b) }
        return k0 * (k0 - 1) / k1
    }

    /// Exact polygon distance with sign (Inigo Quilez' formulation).
    static func polygon(_ px: Double, _ py: Double, _ v: [CGPoint]) -> Double {
        guard v.count >= 3 else { return .greatestFiniteMagnitude }
        var d = (px - Double(v[0].x)) * (px - Double(v[0].x)) + (py - Double(v[0].y)) * (py - Double(v[0].y))
        var s = 1.0
        var j = v.count - 1
        for i in 0..<v.count {
            let ex = Double(v[j].x - v[i].x), ey = Double(v[j].y - v[i].y)
            let wx = px - Double(v[i].x), wy = py - Double(v[i].y)
            let t = max(0, min(1, (wx * ex + wy * ey) / (ex * ex + ey * ey)))
            let bx = wx - ex * t, by = wy - ey * t
            d = min(d, bx * bx + by * by)
            let c1 = py >= Double(v[i].y), c2 = py < Double(v[j].y), c3 = ex * wy > ey * wx
            if (c1 && c2 && c3) || (!c1 && !c2 && !c3) { s = -s }
            j = i
        }
        return s * d.squareRoot()
    }

    struct Masks: Sendable {
        var sdf: Plane
        /// sdf <= -innerMargin: glass interior away from the rim.
        var interior: Mask
        /// -edgeInner <= sdf <= edgeOuter: rim / edge band.
        var edge: Mask
        /// surroundGap <= sdf <= surroundGap + surroundWidth: background ring around the glass.
        var surround: Mask
        /// sdf <= 0
        var full: Mask
    }

    func masks(width: Int, height: Int, innerMargin: Double, edgeInner: Double, edgeOuter: Double,
               surroundGap: Double, surroundWidth: Double) -> Masks {
        var sdf = Plane(width: width, height: height)
        var interior = Mask(width: width, height: height), edge = Mask(width: width, height: height)
        var surround = Mask(width: width, height: height), full = Mask(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let d = signedDistance(Double(x) + 0.5, Double(y) + 0.5)
                let i = y * width + x
                sdf.data[i] = Float(d)
                if d <= -innerMargin { interior.data[i] = 1 }
                if d >= -edgeInner && d <= edgeOuter { edge.data[i] = 1 }
                if d >= surroundGap && d <= surroundGap + surroundWidth { surround.data[i] = 1 }
                if d <= 0 { full.data[i] = 1 }
            }
        }
        return Masks(sdf: sdf, interior: interior, edge: edge, surround: surround, full: full)
    }

    /// Center of the first element (pixels).
    var center: CGPoint {
        guard let e = elements.first else { return .zero }
        let all = elements.dropFirst().reduce(e.cgRect) { $0.union($1.cgRect) }
        return CGPoint(x: all.midX, y: all.midY)
    }

    var boundingBox: CGRect {
        elements.dropFirst().reduce(elements.first?.cgRect ?? .zero) { $0.union($1.cgRect) }
    }

    func scaled(by s: Double) -> GlassRegionModel {
        GlassRegionModel(shape: shape,
                         elements: elements.map { CGRectCodable(CGRect(x: $0.x * s, y: $0.y * s, width: $0.width * s, height: $0.height * s)) },
                         cornerRadiusPx: cornerRadiusPx * s, rotationDegrees: rotationDegrees)
    }

    func translated(dx: Double, dy: Double) -> GlassRegionModel {
        GlassRegionModel(shape: shape,
                         elements: elements.map { CGRectCodable(CGRect(x: $0.x + dx, y: $0.y + dy, width: $0.width, height: $0.height)) },
                         cornerRadiusPx: cornerRadiusPx, rotationDegrees: rotationDegrees)
    }
}

/// The five-pointed star used as the "supported custom shape". Shared by the SwiftUI Shape and the SDF
/// so the analysis mask matches the rendered geometry exactly.
enum StarGeometry {
    static let innerRatio = 0.45
    /// Vertices centred on the origin, first point straight up (y grows downward).
    static func points(radius: Double) -> [CGPoint] {
        (0..<10).map { i in
            let r = i % 2 == 0 ? radius : radius * innerRatio
            let a = -Double.pi / 2 + Double(i) * .pi / 5
            return CGPoint(x: r * cos(a), y: r * sin(a))
        }
    }
}
