import Foundation
import CoreGraphics

/// A stored image. Pixels live in a PNG next to the session JSON; this record describes them.
struct FrameRecord: Codable, Hashable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable {
        case reference = "Reference"
        case test = "Test"
        case validationOn = "Validation (glass on)"
        case validationOff = "Validation (glass off)"
        case motion = "Motion Frame"
        case derived = "Derived Image"
        case imported = "Imported"
    }
    var id = UUID()
    var fileName: String
    var role: Role
    var pixelWidth: Int
    var pixelHeight: Int
    /// Points → pixels factor of the capture (pixels per point).
    var pixelsPerPoint: Double
    /// Name of the color space embedded in the stored file (e.g. kCGColorSpaceDisplayP3).
    var colorSpace: String
    var captureMethod: CaptureMethod
    /// Capture time on the media clock (CACurrentMediaTime-compatible seconds), when known.
    var mediaTime: Double?
    var capturedAt: Date
    var sha256: String
    /// Crop rectangle of the canvas inside the original full frame, in pixels.
    var cropInSource: PixelRegion?
    /// Facts about the pipeline the pixels went through (chroma subsampling, color conversion…).
    var pipelineNotes: [String]
    /// Mean absolute difference between the last two settle frames (0–1 encoded); nil when not measured.
    var settleResidual: Double?
    var settleMilliseconds: Double?
}

struct RecordingRecord: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var fileName: String
    var codec: String
    var isLossless: Bool
    var pixelWidth: Int
    var pixelHeight: Int
    var pixelsPerPoint: Double
    var nominalFrameRate: Double?
    var frameCount: Int
    var startMediaTime: Double
    var duration: Double
    /// Presentation times (seconds, media clock) of every written frame.
    var frameTimes: [Double]
    var crop: PixelRegion?
    var colorSpace: String
    var pipelineNotes: [String]
    var sha256: String?
}

/// A timestamped input or animation event used to align motion data.
struct InteractionEvent: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case touchDown = "Touch Down", touchMove = "Touch Move", touchUp = "Touch Up", touchCancel = "Touch Cancel"
        case stateChange = "State Change", animationStart = "Animation Start", animationEnd = "Animation End"
        case marker = "Marker", displayLink = "Display Link"
    }
    var id = UUID()
    var kind: Kind
    /// Seconds on the media clock (UITouch.timestamp / CACurrentMediaTime).
    var time: Double
    /// Location in canvas points, when relevant.
    var x: Double?
    var y: Double?
    var label: String?
    var force: Double?
}

struct AnalysisRun: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var startedAt: Date
    var finishedAt: Date?
    var appVersion: String
    var algorithmVersions: [String: String]
    var measurements: [Measurement]
    /// Derived images (heatmaps, difference maps) saved alongside the session.
    var derivedFrames: [FrameRecord]
    var log: [String]
    var validity: Validity
}

struct Experiment: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var configuration: SceneConfiguration
    var environment: EnvironmentSnapshot
    var referenceFrames: [FrameRecord] = []
    var resultFrames: [FrameRecord] = []
    var recordings: [RecordingRecord] = []
    var events: [InteractionEvent] = []
    var analyses: [AnalysisRun] = []
    /// Canvas size in points at capture time.
    var canvasSizePoints: CGSizeCodable
    /// Glass subject frame relative to the canvas, in points (unrotated).
    var subjectFramePoints: CGRectCodable
    /// Individual glass element frames relative to the canvas, in points.
    var elementFramesPoints: [CGRectCodable] = []
    var repetitionIndex: Int = 0
    var notes: String = ""
    var validity: Validity = Validity(status: .incomplete, reasons: ["Not acquired yet"])
    var matrixCaseID: UUID?

    var latestAnalysis: AnalysisRun? { analyses.last }
    var title: String { configuration.summary }
}

struct ExperimentSession: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var modifiedAt = Date()
    var environment: EnvironmentSnapshot
    var experiments: [Experiment] = []
    var notes: String = ""
    var tags: [String] = []
    /// Session-level analyses that use several experiments (multi-background transfer, repeatability).
    var crossAnalyses: [AnalysisRun] = []
    var schemaVersion: Int = 1

    var validity: Validity {
        if experiments.isEmpty { return Validity(status: .incomplete, reasons: ["No experiments"]) }
        let invalid = experiments.filter { $0.validity.status == .invalid }.count
        let incomplete = experiments.filter { $0.validity.status == .incomplete }.count
        if invalid > 0 { return .warning("\(invalid) experiment(s) invalid") }
        if incomplete > 0 { return Validity(status: .incomplete, reasons: ["\(incomplete) experiment(s) incomplete"]) }
        return .valid
    }
}

struct CGSizeCodable: Codable, Hashable, Sendable {
    var width: Double, height: Double
    init(_ s: CGSize) { width = s.width; height = s.height }
    var cgSize: CGSize { CGSize(width: width, height: height) }
}

struct CGRectCodable: Codable, Hashable, Sendable {
    var x: Double, y: Double, width: Double, height: Double
    init(_ r: CGRect) { x = r.minX; y = r.minY; width = r.width; height = r.height }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
