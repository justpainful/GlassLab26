import Foundation

/// Step-response and oscillation metrics for a sampled signal.
/// Times are seconds on the media clock; values are any unit.
enum TimeSeries {
    struct StepResponse: Codable, Hashable, Sendable {
        var initial: Double
        var final: Double
        /// First sample where the signal leaves the noise band around `initial`.
        var onsetTime: Double?
        /// 10% -> 90% of the step.
        var riseTime: Double?
        /// Time after onset until the signal stays within +/- band of `final`.
        var settlingTime: Double?
        /// (peak - final) / |final - initial|, as a fraction.
        var overshoot: Double?
        var peakTime: Double?
        /// Damped oscillation frequency (Hz) from successive extrema, if at least two half-cycles exist.
        var oscillationFrequency: Double?
        /// Damping ratio from the logarithmic decrement, if applicable.
        var dampingRatio: Double?
        /// Smallest sample interval; the timing resolution of every value above.
        var sampleInterval: Double
        var warnings: [String]
    }

    /// Analyses a step-like response. `baselineCount` samples define the initial level;
    /// the last `tailCount` samples define the final level.
    static func stepResponse(t: [Double], y: [Double], stimulusTime: Double? = nil,
                             baselineCount: Int = 3, tailCount: Int = 5, settleBand: Double = 0.05) -> StepResponse? {
        guard t.count == y.count, t.count >= baselineCount + tailCount + 2 else { return nil }
        let intervals = zip(t.dropFirst(), t).map { $0 - $1 }.filter { $0 > 0 }
        let dt = intervals.min() ?? .nan
        let initial = Statistics.mean(Array(y.prefix(baselineCount)))
        let final = Statistics.mean(Array(y.suffix(tailCount)))
        let step = final - initial
        var warnings: [String] = []
        let baseNoise = max(Statistics.standardDeviation(Array(y.prefix(max(baselineCount, 2)))), 1e-9)
        if abs(step) < 4 * baseNoise {
            warnings.append("Step amplitude is below 4x the baseline noise; timing values are unreliable.")
        }
        let sign: Double = step >= 0 ? 1 : -1
        func frac(_ v: Double) -> Double { step == 0 ? 0 : (v - initial) / step }

        let startIndex = stimulusTime.flatMap { st in t.firstIndex { $0 >= st } } ?? 0
        var onset: Double?
        for i in startIndex..<y.count where abs(y[i] - initial) > max(4 * baseNoise, 0.02 * abs(step)) {
            onset = t[i]; break
        }
        func crossing(_ level: Double) -> Double? {
            for i in max(1, startIndex)..<y.count {
                let a = frac(y[i - 1]), b = frac(y[i])
                if a < level && b >= level {
                    let f = b == a ? 0 : (level - a) / (b - a)
                    return t[i - 1] + f * (t[i] - t[i - 1])
                }
            }
            return nil
        }
        let t10 = crossing(0.1), t90 = crossing(0.9)
        let rise = (t10 != nil && t90 != nil) ? t90! - t10! : nil

        var settle: Double?
        if let on = onset {
            var lastOutside: Int?
            for i in startIndex..<y.count where abs(frac(y[i]) - 1) > settleBand { lastOutside = i }
            if let lo = lastOutside, lo + 1 < t.count { settle = t[lo + 1] - on }
            else if lastOutside == nil { settle = 0 }
            else { warnings.append("Signal never settled within the recording.") }
        }

        var peakIdx = startIndex
        for i in startIndex..<y.count where sign * y[i] > sign * y[peakIdx] { peakIdx = i }
        let overshoot = step == 0 ? nil : max(0, (y[peakIdx] - final) * sign / abs(step))

        // Extrema after the peak for oscillation analysis.
        var extrema: [(Double, Double)] = []
        if peakIdx + 2 < y.count {
            for i in (peakIdx + 1)..<(y.count - 1) {
                let a = y[i] - y[i - 1], b = y[i + 1] - y[i]
                if a * b < 0 && abs(y[i] - final) > 2 * baseNoise { extrema.append((t[i], y[i] - final)) }
            }
        }
        var freq: Double?
        var zeta: Double?
        let allExtrema = [(t[peakIdx], y[peakIdx] - final)] + extrema
        if allExtrema.count >= 3 {
            let halfPeriods = zip(allExtrema.dropFirst(), allExtrema).map { $0.0 - $1.0 }
            let hp = Statistics.median(halfPeriods)
            if hp > 0 { freq = 1 / (2 * hp) }
            // Logarithmic decrement between same-sign peaks.
            let a0 = abs(allExtrema[0].1), a2 = abs(allExtrema[2].1)
            if a0 > 0, a2 > 0, a2 < a0 {
                let delta = log(a0 / a2)
                zeta = delta / (4 * .pi * .pi + delta * delta).squareRoot()
            }
        }
        if let r = rise, dt.isFinite, r < 3 * dt {
            warnings.append("Rise time spans fewer than 3 samples (\(Format.milliseconds(dt)) per sample); it is not resolved by this capture rate.")
        }
        return StepResponse(initial: initial, final: final, onsetTime: onset, riseTime: rise, settlingTime: settle,
                            overshoot: overshoot, peakTime: t[peakIdx], oscillationFrequency: freq, dampingRatio: zeta,
                            sampleInterval: dt, warnings: warnings)
    }

    /// Central-difference derivative. Endpoints use one-sided differences.
    static func derivative(t: [Double], y: [Double]) -> [Double] {
        guard t.count == y.count, t.count >= 2 else { return [] }
        return y.indices.map { i in
            let a = max(0, i - 1), b = min(y.count - 1, i + 1)
            let dt = t[b] - t[a]
            return dt > 0 ? (y[b] - y[a]) / dt : 0
        }
    }

    /// Simulates an underdamped spring step response x(t) for fitting: unit step, natural frequency
    /// omega (rad/s), damping ratio zeta. Used only as a descriptive model.
    static func springStep(t: Double, omega: Double, zeta: Double) -> Double {
        guard t > 0 else { return 0 }
        if zeta < 1 {
            let wd = omega * (1 - zeta * zeta).squareRoot()
            return 1 - exp(-zeta * omega * t) * (cos(wd * t) + zeta / (1 - zeta * zeta).squareRoot() * sin(wd * t))
        } else {
            return 1 - exp(-omega * t) * (1 + omega * t)
        }
    }

    struct SpringFit: Codable, Hashable, Sendable {
        var omega: Double
        var zeta: Double
        var delay: Double
        var rmse: Double
        var r2: Double
    }

    /// Fits a spring-damper step response to a normalised (0 -> 1) signal.
    static func fitSpring(t: [Double], normalized y: [Double], t0: Double) -> SpringFit? {
        guard t.count >= 6 else { return nil }
        let my = Statistics.mean(y)
        let sst = y.reduce(0) { $0 + ($1 - my) * ($1 - my) }
        let res = Optimization.nelderMead(start: [20, 0.6, 0], step: [10, 0.2, 0.01],
                                          lower: [0.5, 0.05, -0.05], upper: [400, 2.0, 0.5]) { p in
            var sse = 0.0
            for i in t.indices {
                let m = springStep(t: t[i] - t0 - p[2], omega: p[0], zeta: p[1])
                sse += (m - y[i]) * (m - y[i])
            }
            return sse
        }
        let rmse = (res.value / Double(t.count)).squareRoot()
        return SpringFit(omega: res.x[0], zeta: res.x[1], delay: res.x[2], rmse: rmse, r2: sst > 0 ? 1 - res.value / sst : 0)
    }
}
