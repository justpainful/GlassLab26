import Foundation

enum Optimization {
    struct Result {
        var x: [Double]
        var value: Double
        var iterations: Int
        var converged: Bool
    }

    /// Nelder-Mead simplex minimisation with box bounds (values are clamped into bounds).
    static func nelderMead(start: [Double], step: [Double], lower: [Double], upper: [Double],
                           maxIterations: Int = 400, tolerance: Double = 1e-7,
                           isCancelled: () -> Bool = { false },
                           f: ([Double]) -> Double) -> Result {
        let n = start.count
        func clamp(_ p: [Double]) -> [Double] { (0..<n).map { min(upper[$0], max(lower[$0], p[$0])) } }
        var simplex: [[Double]] = [clamp(start)]
        for i in 0..<n {
            var p = start
            p[i] += step[i]
            if p[i] > upper[i] { p[i] = start[i] - step[i] }
            simplex.append(clamp(p))
        }
        var values = simplex.map(f)
        var iter = 0
        var converged = false
        while iter < maxIterations {
            if isCancelled() { break }
            iter += 1
            let order = values.indices.sorted { values[$0] < values[$1] }
            simplex = order.map { simplex[$0] }
            values = order.map { values[$0] }
            if abs(values[n] - values[0]) <= tolerance * (abs(values[0]) + 1e-12) {
                converged = true
                break
            }
            var centroid = [Double](repeating: 0, count: n)
            for p in simplex.dropLast() { for j in 0..<n { centroid[j] += p[j] / Double(n) } }
            let worst = simplex[n]
            let reflected = clamp((0..<n).map { centroid[$0] + (centroid[$0] - worst[$0]) })
            let fr = f(reflected)
            if fr < values[0] {
                let expanded = clamp((0..<n).map { centroid[$0] + 2 * (centroid[$0] - worst[$0]) })
                let fe = f(expanded)
                if fe < fr { simplex[n] = expanded; values[n] = fe } else { simplex[n] = reflected; values[n] = fr }
            } else if fr < values[n - 1] {
                simplex[n] = reflected; values[n] = fr
            } else {
                let contracted = clamp((0..<n).map { centroid[$0] + 0.5 * (worst[$0] - centroid[$0]) })
                let fc = f(contracted)
                if fc < values[n] {
                    simplex[n] = contracted; values[n] = fc
                } else {
                    for i in 1...n {
                        simplex[i] = clamp((0..<n).map { simplex[0][$0] + 0.5 * (simplex[i][$0] - simplex[0][$0]) })
                        values[i] = f(simplex[i])
                    }
                }
            }
        }
        let best = values.indices.min { values[$0] < values[$1] }!
        return Result(x: simplex[best], value: values[best], iterations: iter, converged: converged)
    }

    /// Golden-section search for a minimum of a unimodal function on [a, b].
    static func goldenSection(_ a0: Double, _ b0: Double, tolerance: Double = 1e-3, f: (Double) -> Double) -> (x: Double, value: Double) {
        let g = (5.0.squareRoot() - 1) / 2
        var a = a0, b = b0
        var c = b - g * (b - a), d = a + g * (b - a)
        var fc = f(c), fd = f(d)
        while abs(b - a) > tolerance {
            if fc < fd { b = d; d = c; fd = fc; c = b - g * (b - a); fc = f(c) }
            else { a = c; c = d; fc = fd; d = a + g * (b - a); fd = f(d) }
        }
        let x = (a + b) / 2
        return (x, f(x))
    }

    /// Numerical second derivative of f at x along each axis (diagonal of the Hessian).
    static func diagonalCurvature(at x: [Double], steps: [Double], f: ([Double]) -> Double) -> [Double] {
        let f0 = f(x)
        return x.indices.map { i in
            var p = x, m = x
            p[i] += steps[i]; m[i] -= steps[i]
            return (f(p) - 2 * f0 + f(m)) / (steps[i] * steps[i])
        }
    }

    /// Least squares y ~ g*x + o over the masked samples. Returns nil if x has no variance.
    static func affineFit(x: UnsafeBufferPointer<Float>, y: UnsafeBufferPointer<Float>, mask: UnsafeBufferPointer<UInt8>?) -> (gain: Double, offset: Double, rmse: Double, r2: Double, n: Int)? {
        var n = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, syy = 0.0
        for i in 0..<x.count {
            if let m = mask, m[i] == 0 { continue }
            let a = Double(x[i]), b = Double(y[i])
            n += 1; sx += a; sy += b; sxx += a * a; sxy += a * b; syy += b * b
        }
        guard n >= 3 else { return nil }
        let vx = sxx - sx * sx / n
        let vy = syy - sy * sy / n
        let cxy = sxy - sx * sy / n
        guard vx > 1e-12 else { return nil }
        let g = cxy / vx
        let o = (sy - g * sx) / n
        let sse = max(0, vy - g * cxy)
        let r2 = vy > 1e-12 ? 1 - sse / vy : 1
        return (g, o, (sse / n).squareRoot(), r2, Int(n))
    }
}

enum Spectral {
    /// Magnitude of the discrete Fourier transform for k = 0 ... n/2 (direct O(n^2); n is small here).
    static func dftMagnitude(_ x: [Double]) -> [Double] {
        let n = x.count
        guard n > 1 else { return [] }
        return (0...(n / 2)).map { k in
            var re = 0.0, im = 0.0
            for t in 0..<n {
                let a = -2 * Double.pi * Double(k) * Double(t) / Double(n)
                re += x[t] * cos(a); im += x[t] * sin(a)
            }
            return (re * re + im * im).squareRoot()
        }
    }
}
