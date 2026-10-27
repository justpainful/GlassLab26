import Foundation
import CoreGraphics
import CryptoKit
import Observation

/// File-based session database.
///
/// Layout: Application Support/GlassLab/Sessions/<session-id>/
///   session.json            the ExperimentSession record (pretty, sorted keys)
///   frames/<id>.png         captured frames, original pixels, embedded color profile
///   derived/<id>.png        heatmaps and analysis images
///   recordings/<id>.mov     screen recordings
///
/// JSON was chosen over SwiftData/SQLite because the records are small, must be diffable and
/// re-importable on a desktop, and the export bundle is the storage format itself.
@MainActor
@Observable
final class DataStore {
    private(set) var sessions: [ExperimentSession] = []
    var activeSessionID: UUID? {
        didSet { UserDefaults.standard.set(activeSessionID?.uuidString, forKey: "activeSessionID") }
    }
    private(set) var lastError: String?

    nonisolated let root: URL

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GlassLab", isDirectory: true)
        self.root = base.appendingPathComponent("Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        if let s = UserDefaults.standard.string(forKey: "activeSessionID") { activeSessionID = UUID(uuidString: s) }
        reload()
    }

    // MARK: Paths

    nonisolated func directory(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    nonisolated func frameURL(_ session: UUID, _ name: String) -> URL { directory(for: session).appendingPathComponent("frames").appendingPathComponent(name) }
    nonisolated func derivedURL(_ session: UUID, _ name: String) -> URL { directory(for: session).appendingPathComponent("derived").appendingPathComponent(name) }
    nonisolated func recordingURL(_ session: UUID, _ name: String) -> URL { directory(for: session).appendingPathComponent("recordings").appendingPathComponent(name) }

    nonisolated func url(for frame: FrameRecord, in session: UUID) -> URL {
        frame.role == .derived ? derivedURL(session, frame.fileName) : frameURL(session, frame.fileName)
    }

    // MARK: Loading

    func reload() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var loaded: [ExperimentSession] = []
        for d in dirs {
            let file = d.appendingPathComponent("session.json")
            guard let data = try? Data(contentsOf: file) else { continue }
            do { loaded.append(try Self.decoder.decode(ExperimentSession.self, from: data)) }
            catch { lastError = "Could not read \(d.lastPathComponent): \(error.localizedDescription)"; Log.storage.error("\(error.localizedDescription)") }
        }
        // Experiments that were mid-acquisition when the app stopped are marked incomplete.
        for i in loaded.indices {
            for j in loaded[i].experiments.indices where loaded[i].experiments[j].validity.status == .incomplete
                && loaded[i].experiments[j].referenceFrames.isEmpty == false && loaded[i].experiments[j].resultFrames.isEmpty {
                loaded[i].experiments[j].validity = Validity(status: .incomplete, reasons: ["Acquisition was interrupted (reference captured, test missing)"])
            }
        }
        sessions = loaded.sorted { $0.modifiedAt > $1.modifiedAt }
        if let a = activeSessionID, !sessions.contains(where: { $0.id == a }) { activeSessionID = sessions.first?.id }
    }

    func session(_ id: UUID?) -> ExperimentSession? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    var activeSession: ExperimentSession? { session(activeSessionID) }

    // MARK: Mutation

    @discardableResult
    func createSession(title: String, environment: EnvironmentSnapshot) -> ExperimentSession {
        let s = ExperimentSession(title: title, environment: environment)
        let dir = directory(for: s.id)
        for sub in ["frames", "derived", "recordings"] {
            try? FileManager.default.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        save(s)
        activeSessionID = s.id
        return s
    }

    func ensureActiveSession(environment: EnvironmentSnapshot) -> ExperimentSession {
        if let s = activeSession { return s }
        return createSession(title: "Session " + Format.timestamp.string(from: Date()), environment: environment)
    }

    /// Atomic write: the previous file stays intact if the write fails mid-way.
    func save(_ session: ExperimentSession) {
        var s = session
        s.modifiedAt = Date()
        do {
            let dir = directory(for: s.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(s)
            try data.write(to: dir.appendingPathComponent("session.json"), options: [.atomic])
            if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.insert(s, at: 0) }
            sessions.sort { $0.modifiedAt > $1.modifiedAt }
        } catch {
            lastError = "Save failed: \(error.localizedDescription)"
            Log.storage.error("save failed \(error.localizedDescription)")
        }
    }

    func update(_ id: UUID, _ change: (inout ExperimentSession) -> Void) {
        guard var s = session(id) else { return }
        change(&s)
        save(s)
    }

    func upsert(experiment: Experiment, in sessionID: UUID) {
        update(sessionID) { s in
            if let i = s.experiments.firstIndex(where: { $0.id == experiment.id }) { s.experiments[i] = experiment }
            else { s.experiments.append(experiment) }
        }
    }

    func deleteSession(_ id: UUID) {
        try? FileManager.default.removeItem(at: directory(for: id))
        sessions.removeAll { $0.id == id }
        if activeSessionID == id { activeSessionID = sessions.first?.id }
    }

    func deleteExperiment(_ exp: UUID, in sessionID: UUID) {
        guard let s = session(sessionID), let e = s.experiments.first(where: { $0.id == exp }) else { return }
        for f in e.referenceFrames + e.resultFrames { try? FileManager.default.removeItem(at: frameURL(sessionID, f.fileName)) }
        for a in e.analyses { for f in a.derivedFrames { try? FileManager.default.removeItem(at: derivedURL(sessionID, f.fileName)) } }
        for r in e.recordings { try? FileManager.default.removeItem(at: recordingURL(sessionID, r.fileName)) }
        update(sessionID) { $0.experiments.removeAll { $0.id == exp } }
    }

    // MARK: Disk

    nonisolated static func availableCapacity() -> Int64? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage
    }

    nonisolated func sizeOnDisk(_ id: UUID) -> UInt64 {
        let dir = directory(for: id)
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: UInt64 = 0
        for case let u as URL in e { total += UInt64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return total
    }

    // MARK: Coding

    nonisolated static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }()
    nonisolated static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }()
}

/// Off-main helpers for writing pixel data.
enum FrameWriter {
    static func sha256(of url: URL) -> String {
        guard let h = FileHandle(forReadingAtPath: url.path) else { return "" }
        defer { try? h.close() }
        var hasher = SHA256()
        while true {
            let chunk = h.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes a PNG frame and returns its record. The CGImage's color space is embedded unchanged.
    static func write(_ image: CGImage, to url: URL, role: FrameRecord.Role, method: CaptureMethod, pixelsPerPoint: Double,
                      mediaTime: Double?, crop: PixelRegion?, notes: [String], settleResidual: Double? = nil, settleMs: Double? = nil) throws -> FrameRecord {
        if let free = DataStore.availableCapacity(), free < 200 * 1024 * 1024 {
            throw GlassLabError.storage("less than 200 MB free on the device; capture stopped to protect existing data")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ImageIOHelper.writePNG(image, to: url)
        return FrameRecord(fileName: url.lastPathComponent, role: role, pixelWidth: image.width, pixelHeight: image.height,
                           pixelsPerPoint: pixelsPerPoint, colorSpace: (image.colorSpace?.name as String?) ?? "untagged",
                           captureMethod: method, mediaTime: mediaTime, capturedAt: Date(), sha256: sha256(of: url),
                           cropInSource: crop, pipelineNotes: notes, settleResidual: settleResidual, settleMilliseconds: settleMs)
    }
}
