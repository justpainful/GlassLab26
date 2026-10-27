import Foundation
import CoreGraphics

struct BundleManifest: Codable, Hashable, Sendable {
    struct File: Codable, Hashable, Sendable {
        var path: String
        var bytes: UInt64
        var sha256: String
    }
    var format = "GlassLabSessionBundle"
    var formatVersion = 1
    var createdAt: Date
    var appVersion: String
    var appBuild: String
    var sessionID: UUID
    var sessionTitle: String
    var algorithmVersions: [String: String]
    var files: [File]
}

struct ImportReport: Sendable {
    var sessionTitle: String
    var verifiedFiles: Int
    var problems: [String]
    var imported: Bool
}

/// Creates and verifies export bundles. Everything stays on the device; files leave only through the
/// share sheet the user opens.
enum ExportManager {
    static var exportDirectory: URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("GlassLabExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func safeName(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }).prefix(60).description
    }

    // MARK: CSV / JSON

    static func csvField(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") { return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return s
    }

    static let csvHeader = ["session", "experiment_id", "experiment", "analysis_started", "measurement", "value", "unit", "provenance",
                            "confidence", "confidence_reason", "uncertainty", "uncertainty_kind", "sample_count", "validity", "validity_reasons",
                            "algorithm", "algorithm_version", "region_px", "device", "os", "app_version", "sources", "notes"]

    static func csv(_ session: ExperimentSession) -> String {
        var lines = [csvHeader.joined(separator: ",")]
        for e in session.experiments {
            for run in e.analyses {
                for m in run.measurements {
                    let region = m.region.map { "\($0.x) \($0.y) \($0.width) \($0.height)" } ?? ""
                    let fields: [String] = [
                        session.title, e.id.uuidString, e.title, Format.iso.string(from: run.startedAt), m.name,
                        m.value.map { String($0) } ?? "N/A", m.unit, m.provenance.rawValue, m.confidence.level.rawValue, m.confidence.justification,
                        m.uncertainty.map { String($0.halfWidth) } ?? "", m.uncertainty?.kind.rawValue ?? "", String(m.sampleCount),
                        m.validity.status.rawValue, m.validity.reasons.joined(separator: "; "), m.algorithm, m.algorithmVersion, region,
                        e.environment.machineIdentifier, e.environment.systemVersion, run.appVersion, m.sources.joined(separator: " "), m.notes ?? ""]
                    lines.append(fields.map(csvField).joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One CSV row per series point (profiles, histograms, time series).
    static func seriesCSV(_ session: ExperimentSession) -> String {
        var lines = ["experiment_id,measurement,series,x,x_unit,y,y_unit"]
        for e in session.experiments {
            guard let run = e.latestAnalysis else { continue }
            for m in run.measurements {
                for s in m.series ?? [] {
                    for (x, y) in zip(s.x, s.y) {
                        lines.append([e.id.uuidString, m.name, s.label, String(x), s.xUnit, y.isFinite ? String(y) : "N/A", s.yUnit].map(csvField).joined(separator: ","))
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Bundle

    /// Builds `<title>.glasslab.zip` with session.json, frames, derived images, recordings, CSVs, an optional
    /// PDF report and manifest.json (sizes + SHA-256 of every other file).
    static func makeBundle(session: ExperimentSession, sessionDirectory: URL, includeReport: Bool, includeRecordings: Bool) throws -> URL {
        let fm = FileManager.default
        let staging = exportDirectory.appendingPathComponent("staging-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        var entries: [(String, URL)] = []
        let json = staging.appendingPathComponent("session.json")
        try DataStore.encoder.encode(session).write(to: json)
        entries.append(("session.json", json))
        let csvURL = staging.appendingPathComponent("measurements.csv")
        try csv(session).write(to: csvURL, atomically: true, encoding: .utf8)
        entries.append(("measurements.csv", csvURL))
        let seriesURL = staging.appendingPathComponent("series.csv")
        try seriesCSV(session).write(to: seriesURL, atomically: true, encoding: .utf8)
        entries.append(("series.csv", seriesURL))
        for sub in ["frames", "derived"] + (includeRecordings ? ["recordings"] : []) {
            let dir = sessionDirectory.appendingPathComponent(sub)
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                entries.append(("\(sub)/\(f.lastPathComponent)", f))
            }
        }
        if includeReport {
            let pdf = staging.appendingPathComponent("report.pdf")
            try ReportGenerator.render(session: session, sessionDirectory: sessionDirectory, to: pdf)
            entries.append(("report.pdf", pdf))
        }
        var files: [BundleManifest.File] = []
        for (path, url) in entries {
            if Task.isCancelled { throw GlassLabError.cancelled }
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
            files.append(BundleManifest.File(path: path, bytes: size, sha256: FrameWriter.sha256(of: url)))
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let manifest = BundleManifest(createdAt: Date(), appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
                                      appBuild: info["CFBundleVersion"] as? String ?? "?", sessionID: session.id, sessionTitle: session.title,
                                      algorithmVersions: MeasurementEngine.algorithmVersionsStatic, files: files)
        let manifestURL = staging.appendingPathComponent("manifest.json")
        try DataStore.encoder.encode(manifest).write(to: manifestURL)
        let out = exportDirectory.appendingPathComponent(safeName(session.title) + "-" + Format.fileStamp.string(from: Date()) + ".glasslab.zip")
        try ZipArchive.write(entries: ([("manifest.json", manifestURL)] + entries).map { ZipArchive.Entry(path: $0.0, source: $0.1) }, to: out)
        return out
    }

    /// Verifies a bundle against its manifest and, if every file matches, imports it as a new session.
    @MainActor
    static func importBundle(_ url: URL, into store: DataStore) async -> ImportReport {
        let root = store.root
        let result: ImportReport = await Task.detached {
            let fm = FileManager.default
            let temp = exportDirectory.appendingPathComponent("import-" + UUID().uuidString, isDirectory: true)
            defer { try? fm.removeItem(at: temp) }
            var problems: [String] = []
            do {
                try fm.createDirectory(at: temp, withIntermediateDirectories: true)
                _ = try ZipArchive.extract(url, to: temp)
                let manifest = try DataStore.decoder.decode(BundleManifest.self, from: Data(contentsOf: temp.appendingPathComponent("manifest.json")))
                guard manifest.format == "GlassLabSessionBundle" else { return ImportReport(sessionTitle: "?", verifiedFiles: 0, problems: ["Not a Glass Lab bundle"], imported: false) }
                var ok = 0
                for f in manifest.files {
                    let u = temp.appendingPathComponent(f.path)
                    guard fm.fileExists(atPath: u.path) else { problems.append("Missing \(f.path)"); continue }
                    let size = (try? fm.attributesOfItem(atPath: u.path)[.size] as? NSNumber)?.uint64Value ?? 0
                    if size != f.bytes { problems.append("Size mismatch \(f.path)"); continue }
                    if FrameWriter.sha256(of: u) != f.sha256 { problems.append("SHA-256 mismatch \(f.path)"); continue }
                    ok += 1
                }
                guard problems.isEmpty else { return ImportReport(sessionTitle: manifest.sessionTitle, verifiedFiles: ok, problems: problems, imported: false) }
                var session = try DataStore.decoder.decode(ExperimentSession.self, from: Data(contentsOf: temp.appendingPathComponent("session.json")))
                if fm.fileExists(atPath: root.appendingPathComponent(session.id.uuidString).path) {
                    session.id = UUID()
                    session.title += " (imported copy)"
                }
                let dest = root.appendingPathComponent(session.id.uuidString, isDirectory: true)
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                for sub in ["frames", "derived", "recordings"] {
                    let src = temp.appendingPathComponent(sub)
                    if fm.fileExists(atPath: src.path) { try fm.moveItem(at: src, to: dest.appendingPathComponent(sub)) }
                    else { try fm.createDirectory(at: dest.appendingPathComponent(sub), withIntermediateDirectories: true) }
                }
                session.notes += (session.notes.isEmpty ? "" : "\n") + "Imported \(Format.timestamp.string(from: Date())) from \(url.lastPathComponent); \(ok) files verified by SHA-256."
                try DataStore.encoder.encode(session).write(to: dest.appendingPathComponent("session.json"), options: .atomic)
                return ImportReport(sessionTitle: session.title, verifiedFiles: ok, problems: [], imported: true)
            } catch {
                problems.append(error.localizedDescription)
                return ImportReport(sessionTitle: "?", verifiedFiles: 0, problems: problems, imported: false)
            }
        }.value
        store.reload()
        return result
    }

    /// Writes PNG and HEIC copies of one frame for quick sharing.
    static func exportFrame(_ src: URL, heic: Bool) throws -> URL {
        guard heic else { return src }
        guard let img = ImageIOHelper.loadCGImage(src) else { throw GlassLabError.invalidData("cannot decode frame") }
        let out = exportDirectory.appendingPathComponent(src.deletingPathExtension().lastPathComponent + ".heic")
        try ImageIOHelper.writeHEIC(img, to: out)
        return out
    }
}

extension MeasurementEngine {
    nonisolated static var algorithmVersionsStatic: [String: String] {
        ["imageStatistics": AlgorithmVersion.imageStatistics, "colorScience": AlgorithmVersion.colorScience,
         "translucency": AlgorithmVersion.translucency, "blurFit": AlgorithmVersion.blurFit, "edgeSpread": AlgorithmVersion.edgeSpread,
         "displacement": AlgorithmVersion.displacement, "highlights": AlgorithmVersion.highlights, "errorMetrics": AlgorithmVersion.errorMetrics,
         "motion": AlgorithmVersion.motion, "registration": AlgorithmVersion.registration, "multiBackground": AlgorithmVersion.multiBackground,
         "reconstruction": AlgorithmVersion.reconstruction, "performance": AlgorithmVersion.performance]
    }
}
