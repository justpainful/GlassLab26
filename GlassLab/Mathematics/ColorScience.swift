import Foundation

/// Color math used by the analyzers. All images are analysed in *linear* Display P3
/// (D65 white), which is the space `LinearImage` decodes into.
enum ColorScience {
    // MARK: Transfer functions (sRGB and Display P3 share the sRGB curve)

    static func srgbToLinear(_ c: Double) -> Double {
        let a = abs(c)
        let v = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4)
        return c < 0 ? -v : v
    }

    static func linearToSRGB(_ c: Double) -> Double {
        let a = abs(c)
        let v = a <= 0.0031308 ? a * 12.92 : 1.055 * pow(a, 1 / 2.4) - 0.055
        return c < 0 ? -v : v
    }

    // MARK: Matrices (linear RGB → CIE XYZ, D65, Y normalised to 1 for white)

    static let p3ToXYZ: [Double] = [
        0.4865709, 0.2656677, 0.1982173,
        0.2289746, 0.6917385, 0.0792869,
        0.0000000, 0.0451134, 1.0439444,
    ]
    static let srgbToXYZ: [Double] = [
        0.4124564, 0.3575761, 0.1804375,
        0.2126729, 0.7151522, 0.0721750,
        0.0193339, 0.1191920, 0.9503041,
    ]
    /// D65 reference white (Y = 1).
    static let d65 = (x: 0.95047, y: 1.0, z: 1.08883)

    static func mul(_ m: [Double], _ v: (Double, Double, Double)) -> (Double, Double, Double) {
        (m[0] * v.0 + m[1] * v.1 + m[2] * v.2,
         m[3] * v.0 + m[4] * v.1 + m[5] * v.2,
         m[6] * v.0 + m[7] * v.1 + m[8] * v.2)
    }

    /// Relative luminance Y of a linear Display P3 triplet.
    @inline(__always)
    static func luminanceP3(_ r: Float, _ g: Float, _ b: Float) -> Float {
        0.2289746 * r + 0.6917385 * g + 0.0792869 * b
    }

    /// Relative luminance of a linear sRGB triplet (WCAG / Rec. 709 weights).
    static func luminanceSRGB(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    }

    // MARK: CIELAB

    static func xyzToLab(_ xyz: (Double, Double, Double)) -> (L: Double, a: Double, b: Double) {
        func f(_ t: Double) -> Double {
            let d = 6.0 / 29.0
            return t > d * d * d ? cbrt(t) : t / (3 * d * d) + 4.0 / 29.0
        }
        let fx = f(xyz.0 / d65.x), fy = f(xyz.1 / d65.y), fz = f(xyz.2 / d65.z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    static func labFromLinearP3(_ r: Double, _ g: Double, _ b: Double) -> (L: Double, a: Double, b: Double) {
        xyzToLab(mul(p3ToXYZ, (r, g, b)))
    }

    static func labFromLinearSRGB(_ r: Double, _ g: Double, _ b: Double) -> (L: Double, a: Double, b: Double) {
        xyzToLab(mul(srgbToXYZ, (r, g, b)))
    }

    // MARK: CIEDE2000 (Sharma, Wu, Dalal 2005), kL = kC = kH = 1

    static func deltaE2000(_ lab1: (L: Double, a: Double, b: Double), _ lab2: (L: Double, a: Double, b: Double)) -> Double {
        let (L1, a1, b1) = lab1, (L2, a2, b2) = lab2
        let C1 = (a1 * a1 + b1 * b1).squareRoot(), C2 = (a2 * a2 + b2 * b2).squareRoot()
        let Cbar = (C1 + C2) / 2
        let C7 = pow(Cbar, 7)
        let G = 0.5 * (1 - (C7 / (C7 + pow(25.0, 7))).squareRoot())
        let a1p = (1 + G) * a1, a2p = (1 + G) * a2
        let C1p = (a1p * a1p + b1 * b1).squareRoot(), C2p = (a2p * a2p + b2 * b2).squareRoot()
        func hp(_ b: Double, _ ap: Double) -> Double {
            if b == 0 && ap == 0 { return 0 }
            let h = atan2(b, ap) * 180 / .pi
            return h >= 0 ? h : h + 360
        }
        let h1p = hp(b1, a1p), h2p = hp(b2, a2p)
        let dLp = L2 - L1
        let dCp = C2p - C1p
        var dhp = 0.0
        if C1p * C2p != 0 {
            let d = h2p - h1p
            if abs(d) <= 180 { dhp = d } else if d > 180 { dhp = d - 360 } else { dhp = d + 360 }
        }
        let dHp = 2 * (C1p * C2p).squareRoot() * sin(dhp / 2 * .pi / 180)
        let Lbarp = (L1 + L2) / 2
        let Cbarp = (C1p + C2p) / 2
        var hbarp = h1p + h2p
        if C1p * C2p != 0 {
            if abs(h1p - h2p) <= 180 { hbarp = (h1p + h2p) / 2 }
            else if h1p + h2p < 360 { hbarp = (h1p + h2p + 360) / 2 }
            else { hbarp = (h1p + h2p - 360) / 2 }
        }
        let rad = Double.pi / 180
        let T = 1 - 0.17 * cos((hbarp - 30) * rad) + 0.24 * cos(2 * hbarp * rad)
            + 0.32 * cos((3 * hbarp + 6) * rad) - 0.20 * cos((4 * hbarp - 63) * rad)
        let dTheta = 30 * exp(-pow((hbarp - 275) / 25, 2))
        let Cbarp7 = pow(Cbarp, 7)
        let RC = 2 * (Cbarp7 / (Cbarp7 + pow(25.0, 7))).squareRoot()
        let L50 = (Lbarp - 50) * (Lbarp - 50)
        let SL = 1 + 0.015 * L50 / (20 + L50).squareRoot()
        let SC = 1 + 0.045 * Cbarp
        let SH = 1 + 0.015 * Cbarp * T
        let RT = -sin(2 * dTheta * rad) * RC
        let tL = dLp / SL, tC = dCp / SC, tH = dHp / SH
        return (tL * tL + tC * tC + tH * tH + RT * tC * tH).squareRoot()
    }

    /// WCAG 2.x contrast ratio between two relative luminances.
    static func contrastRatio(_ y1: Double, _ y2: Double) -> Double {
        let hi = max(y1, y2), lo = min(y1, y2)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Chroma and hue (degrees) of a Lab color.
    static func lch(_ lab: (L: Double, a: Double, b: Double)) -> (L: Double, C: Double, h: Double) {
        var h = atan2(lab.b, lab.a) * 180 / .pi
        if h < 0 { h += 360 }
        return (lab.L, (lab.a * lab.a + lab.b * lab.b).squareRoot(), h)
    }
}
