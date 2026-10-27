import Foundation
import CoreGraphics
import Observation

/// Runs analyses off the main thread, stores the results and derived images with the session,
/// and keeps the algorithm versions so results can be recomputed after the app changes.
@MainActor
@Observable
final class MeasurementEngine {
    private(set) var runningExperiment: UUID?
    private(set) var progress: Double = 0
    private(set) var message: String = ""
    var lastError: String?
    private var cancelHandle: (() -> Void)?

    var isRunning: Bool { runningExperiment != nil }

    func cancel() {
        cancelHandle?()
        message = "Cancelling..."
    }

    static var algorithmVersions: [String: String] {
        ["imageStatistics": AlgorithmVersion.imageStatistics, "colorScience": AlgorithmVersion.colorScience,
         "translucency": AlgorithmVersion.translucency, "blurFit": AlgorithmVersion.blurFit, "edgeSpread": AlgorithmVersion.edgeSpread,
         "displacement": AlgorithmVersion.displacement, "highlights": AlgorithmVersion.highlights, "errorMetrics": AlgorithmVersion.errorMetrics,
         "motion": AlgorithmVersion.motion, "registration": AlgorithmVersion.registration]
    }

    /// Analyses the latest reference/test pair of an experiment. Returns when finished or cancelled.
    func analyze(experimentID: UUID, sessionID: UUID, store: DataStore) async {
        guard !isRunning else { lastError = "An analysis is already running."; return }
        guard let session = store.session(sessionID), let exp = session.experiments.first(where: { $0.id == experimentID }) else { return }
        runningExperiment = experimentID; progress = 0; message = "Loading frames"; lastError = nil
        let started = Date()
        let refFrame = exp.referenceFrames.last, testFrame = exp.resultFrames.last
        guard let refFrame, let testFrame else {
            finish(); lastError = "The experiment has no reference/test pair."; return
        }
        let refURL = store.url(for: refFrame, in: sessionID), testURL = store.url(for: testFrame, in: sessionID)
        let derivedDir = store.directory(for: sessionID).appendingPathComponent("derived")
        let region = CaptureCoordinator.regionModel(for: exp, pixelsPerPoint: testFrame.pixelsPerPoint)
        let config = exp.configuration
        let sources = [refFrame.fileName, testFrame.fileName]
        let ppp = testFrame.pixelsPerPoint

        let work = Task.detached(priority: .userInitiated) { () throws -> (OpticalReport, [FrameRecord]) in
            // Verify stored files before measuring: a changed file means the record no longer describes it.
            for (f, u) in [(refFrame, refURL), (testFrame, testURL)] where !f.sha256.isEmpty {
                if FrameWriter.sha256(of: u) != f.sha256 { throw GlassLabError.invalidData("\(f.fileName) does not match its recorded SHA-256") }
            }
            guard let ref = LinearImage.load(url: refURL), let test = LinearImage.load(url: testURL) else {
                throw GlassLabError.invalidData("frames could not be decoded")
            }
            let input = OpticalInput(reference: ref, test: test, region: region, pixelsPerPoint: ppp,
                                     background: config.background, modules: config.modules, sources: sources)
            var report = try OpticalAnalyzer.analyze(input)
            try Task.checkCancellation()
            var derived: [FrameRecord] = []
            try FileManager.default.createDirectory(at: derivedDir, withIntermediateDirectories: true)
            for img in report.images {
                let name = "derived-\(UUID().uuidString.prefix(10)).png"
                let url = derivedDir.appendingPathComponent(name)
                var rec = try FrameWriter.write(img.image, to: url, role: .derived, method: refFrame.captureMethod, pixelsPerPoint: ppp / Double(report.analysisScale),
                                                mediaTime: nil, crop: nil, notes: [img.name, img.note])
                if let l = img.legend { rec.pipelineNotes.append("Legend: \(Format.number(l.minValue, digits: 3))...\(Format.number(l.maxValue, digits: 3)) \(l.unit), \(l.colormap.rawValue)") }
                derived.append(rec)
            }
            report.images = []
            return (report, derived)
        }
        cancelHandle = { work.cancel() }
        message = "Analysing (\(config.modules.count) modules)"
        do {
            let (report, derived) = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: { work.cancel() }
            var run = AnalysisRun(startedAt: started, finishedAt: Date(), appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                                  algorithmVersions: Self.algorithmVersions, measurements: report.measurements, derivedFrames: derived,
                                  log: report.log, validity: report.validity)
            if !exp.validity.isUsable && exp.validity.status != .incomplete {
                run.validity = Validity(status: .invalid, reasons: ["Acquisition invalid: " + exp.validity.reasons.joined(separator: "; ")])
            } else if exp.validity.status == .warning && run.validity.status == .valid {
                run.validity = Validity(status: .warning, reasons: exp.validity.reasons)
            }
            store.update(sessionID) { s in
                if let i = s.experiments.firstIndex(where: { $0.id == experimentID }) {
                    s.experiments[i].analyses.append(run)
                    if s.experiments[i].validity.status == .incomplete && !s.experiments[i].resultFrames.isEmpty {
                        s.experiments[i].validity = run.validity
                    }
                }
            }
            message = "Done: \(report.measurements.count) measurements"
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if error is CancellationError { lastError = "Analysis cancelled; nothing was saved." }
        }
        finish()
    }

    private func finish() {
        runningExperiment = nil
        cancelHandle = nil
        progress = 1
    }

    /// Motion analysis of an experiment's latest recording.
    func analyzeMotion(experimentID: UUID, sessionID: UUID, store: DataStore) async -> MotionReport? {
        guard !isRunning, let s = store.session(sessionID), let exp = s.experiments.first(where: { $0.id == experimentID }),
              let rec = exp.recordings.last else { return nil }
        runningExperiment = experimentID; message = "Decoding frames"; lastError = nil
        let url = store.recordingURL(sessionID, rec.fileName)
        let events = exp.events
        let started = Date()
        let work = Task.detached(priority: .userInitiated) { try MotionAnalyzer.analyze(url: url, recording: rec, events: events) }
        cancelHandle = { work.cancel() }
        defer { finish() }
        do {
            let report = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            let run = AnalysisRun(startedAt: started, finishedAt: Date(), appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                                  algorithmVersions: Self.algorithmVersions, measurements: report.measurements, derivedFrames: [],
                                  log: report.warnings, validity: report.warnings.isEmpty ? .valid : Validity(status: .warning, reasons: report.warnings))
            store.update(sessionID) { s in
                if let i = s.experiments.firstIndex(where: { $0.id == experimentID }) {
                    s.experiments[i].analyses.append(run)
                    if s.experiments[i].validity.status == .incomplete { s.experiments[i].validity = run.validity }
                }
            }
            return report
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}
