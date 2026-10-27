import Foundation

struct SummaryStatistics: Codable, Hashable, Sendable {
    var count: Int
    var mean: Double
    var median: Double
    var standardDeviation: Double   // sample (n − 1)
    var min: Double
    var max: Double
    /// 95% confidence interval half-width of the mean (Student t). nil for n < 2.
    var ci95HalfWidth: Double?
    var standardError: Double?
}

enum Statistics {
    static func mean(_ x: [Double]) -> Double {
        x.isEmpty ? .nan : x.reduce(0, +) / Double(x.count)
    }

    static func variance(_ x: [Double]) -> Double {
        guard x.count > 1 else { return .nan }
        let m = mean(x)
        return x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)
    }

    static func standardDeviation(_ x: [Double]) -> Double { variance(x).squareRoot() }

    static func median(_ x: [Double]) -> Double { quantile(x, 0.5) }

    /// Linear-interpolated quantile (type 7, the R/NumPy default).
    static func quantile(_ x: [Double], _ q: Double) -> Double {
        guard !x.isEmpty else { return .nan }
        let s = x.sorted()
        let h = Double(s.count - 1) * q
        let lo = Int(floor(h)), hi = Int(ceil(h))
        return s[lo] + (h - Double(lo)) * (s[hi] - s[lo])
    }

    static func summary(_ x: [Double]) -> SummaryStatistics {
        let v = x.filter { $0.isFinite }
        let n = v.count
        guard n > 0 else { return SummaryStatistics(count: 0, mean: .nan, median: .nan, standardDeviation: .nan, min: .nan, max: .nan) }
        let sd = n > 1 ? standardDeviation(v) : .nan
        let se = n > 1 ? sd / Double(n).squareRoot() : nil
        return SummaryStatistics(count: n, mean: mean(v), median: median(v), standardDeviation: sd,
                                 min: v.min()!, max: v.max()!,
                                 ci95HalfWidth: se.map { $0 * tCritical95(df: n - 1) }, standardError: se)
    }

    /// Two-sided 95% Student t critical value.
    static func tCritical95(df: Int) -> Double {
        let table: [Double] = [12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228,
                               2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086,
                               2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042]
        if df <= 0 { return .nan }
        if df <= table.count { return table[df - 1] }
        if df <= 60 { return 2.000 + (2.042 - 2.000) * Double(60 - df) / 30 }
        if df <= 120 { return 1.980 + (2.000 - 1.980) * Double(120 - df) / 60 }
        return 1.960
    }

    /// Median absolute deviation, scaled to be consistent with σ for normal data.
    static func mad(_ x: [Double]) -> Double {
        let m = median(x)
        return 1.4826 * median(x.map { abs($0 - m) })
    }

    /// Indices of outliers by the modified z-score rule (|z| > 3.5, Iglewicz & Hoaglin).
    static func outlierIndices(_ x: [Double], threshold: Double = 3.5) -> [Int] {
        guard x.count >= 3 else { return [] }
        let m = median(x), s = mad(x)
        guard s > 0 else { return [] }
        return x.indices.filter { abs(x[$0] - m) / s > threshold }
    }

    /// Ordinary least squares y = a + b·x. Returns (a, b, r²).
    static func linearFit(x: [Double], y: [Double]) -> (intercept: Double, slope: Double, r2: Double)? {
        let n = Double(x.count)
        guard x.count == y.count, x.count >= 2 else { return nil }
        let mx = mean(x), my = mean(y)
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for i in x.indices {
            let dx = x[i] - mx, dy = y[i] - my
            sxx += dx * dx; sxy += dx * dy; syy += dy * dy
        }
        guard sxx > 0, n >= 2 else { return nil }
        let b = sxy / sxx
        let a = my - b * mx
        let r2 = syy > 0 ? (sxy * sxy) / (sxx * syy) : 1
        return (a, b, r2)
    }

    static func histogram(_ x: [Double], bins: Int, range: ClosedRange<Double>) -> [Int] {
        var h = [Int](repeating: 0, count: bins)
        let w = (range.upperBound - range.lowerBound) / Double(bins)
        guard w > 0 else { return h }
        for v in x where v.isFinite {
            var i = Int((v - range.lowerBound) / w)
            i = Swift.max(0, Swift.min(bins - 1, i))
            h[i] += 1
        }
        return h
    }
}
