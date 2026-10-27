import Foundation

/// Fits ReconstructionParameters to Apple reference captures, then reports per-parameter sensitivity,
/// an identifiability check and leave-one-out generalisation on unseen backgrounds.
enum ParameterEstimator {
    struct ParameterReport: Codable, Hashable, Sendable, Identifiable {
        var id: String { name }
        var name: String
        var unit: String
        var value: Double
        /// Approximate standard error from the diagonal of the loss Hessian (ignores correlations).
        var standardError: Double?
        /// Relative loss increase for a +/-10% (or one-step) perturbation.
        var sensitivity: Double
        var identifiable: Bool
        var atBound: Bool
    }

    struct FoldResult: Codable, Hashable, Sendable, Identifiable {
        var id: String { heldOut }
        var heldOut: String
        var trainRMSE: Double
        var heldOutRMSE: Double
    }

    struct Result: Sendable {
        var parameters: ReconstructionParameters
        var report: [ParameterReport]
        var trainingRMSE: Double
        var perSampleRMSE: [(String, Double)]
        var folds: [FoldResult]
        var iterations: Int
        var converged: Bool
        var notes: [String]
    }

    static func totalLoss(_ v: [Double], _ samples: [ReconstructionSample]) -> (mse: Double, n: Int) {
        let p = ReconstructionParameters(values: v)
        var s = 0.0, n = 0
        for x in samples { let l = ReconstructionRenderer.loss(p, x); s += l.mse * Double(l.count); n += l.count }
        return (n > 0 ? s / Double(n) : .infinity, n)
    }

    static func fit(_ samples: [ReconstructionSample], start: [Double] = ReconstructionParameters.initial, maxIterations: Int = 350,
                    progress: ((Double) -> Void)? = nil) -> Optimization.Result {
        var it = 0
        return Optimization.nelderMead(start: start, step: ReconstructionParameters.steps, lower: ReconstructionParameters.lower,
                                       upper: ReconstructionParameters.upper, maxIterations: maxIterations, tolerance: 1e-6,
                                       isCancelled: { Task.isCancelled }) { v in
            it += 1
            if it % 20 == 0 { progress?(min(1, Double(it) / Double(maxIterations * 2))) }
            return totalLoss(v, samples).mse
        }
    }

    static func estimate(training: [ReconstructionSample], crossValidate: Bool = true, progress: ((Double) -> Void)? = nil) throws -> Result {
        guard !training.isEmpty else { throw GlassLabError.invalidData("no training samples") }
        try ResourceGuard.check()
        var notes: [String] = []
        // Two starts (smooth / refractive) to reduce the chance of a poor local minimum.
        var startB = ReconstructionParameters.initial
        startB[0] = 12; startB[8] = -6
        let a = fit(training, progress: { progress?($0 * 0.4) })
        let b = fit(training, start: startB, progress: { progress?(0.4 + $0 * 0.2) })
        let best = a.value <= b.value ? a : b
        notes.append("Best of two Nelder-Mead starts (losses \(Format.number(a.value, digits: 3)) / \(Format.number(b.value, digits: 3))).")
        try Task.checkCancellation()
        let total = totalLoss(best.x, training)
        let rmse = total.mse.squareRoot()

        // Sensitivity and approximate standard errors
        let steps = zip(best.x, ReconstructionParameters.steps).map { max(abs($0) * 0.05, $1 * 0.2) }
        let curv = Optimization.diagonalCurvature(at: best.x, steps: steps) { totalLoss($0, training).mse }
        var report: [ParameterReport] = []
        for i in best.x.indices {
            var up = best.x; up[i] = min(ReconstructionParameters.upper[i], best.x[i] + max(abs(best.x[i]) * 0.1, ReconstructionParameters.steps[i] * 0.3))
            let lossUp = totalLoss(up, training).mse
            let sens = total.mse > 0 ? (lossUp - total.mse) / total.mse : 0
            let h = curv[i]
            let se: Double? = (h > 1e-12 && total.n > 0) ? (2 * total.mse / (Double(total.n) * h)).squareRoot() : nil
            let identifiable = sens > 0.002 && h > 1e-12
            let atBound = abs(best.x[i] - ReconstructionParameters.lower[i]) < 1e-6 || abs(best.x[i] - ReconstructionParameters.upper[i]) < 1e-6
            report.append(ParameterReport(name: ReconstructionParameters.names[i], unit: ReconstructionParameters.units[i], value: best.x[i],
                                          standardError: se, sensitivity: sens, identifiable: identifiable, atBound: atBound))
        }
        let unidentified = report.filter { !$0.identifiable }.map(\.name)
        if !unidentified.isEmpty { notes.append("Not identifiable from these captures (flat loss): \(unidentified.joined(separator: ", ")). Add backgrounds that excite them (texture for blur/refraction, colors for saturation).") }

        let perSample = training.map { ($0.name, ReconstructionRenderer.loss(ReconstructionParameters(values: best.x), $0).mse.squareRoot()) }

        var folds: [FoldResult] = []
        if crossValidate && training.count >= 3 {
            for (i, held) in training.enumerated() {
                try Task.checkCancellation()
                let rest = training.enumerated().filter { $0.offset != i }.map(\.element)
                let f = fit(rest, start: best.x, maxIterations: 150)
                folds.append(FoldResult(heldOut: held.name, trainRMSE: totalLoss(f.x, rest).mse.squareRoot(),
                                        heldOutRMSE: ReconstructionRenderer.loss(ReconstructionParameters(values: f.x), held).mse.squareRoot()))
                progress?(0.6 + 0.4 * Double(i + 1) / Double(training.count))
            }
            let gap = Statistics.mean(folds.map { $0.heldOutRMSE / max($0.trainRMSE, 1e-9) })
            notes.append("Leave-one-out: held-out RMSE is on average \(Format.number(gap, digits: 3))x the training RMSE.")
        } else if crossValidate {
            notes.append("Cross-validation needs at least 3 samples; a single good fit does not show that the model generalises.")
        }
        return Result(parameters: ReconstructionParameters(values: best.x), report: report, trainingRMSE: rmse, perSampleRMSE: perSample,
                      folds: folds, iterations: a.iterations + b.iterations, converged: best.converged, notes: notes)
    }
}
