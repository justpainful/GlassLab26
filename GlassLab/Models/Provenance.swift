import Foundation
import CoreGraphics

/// Where a number came from. Every value shown or stored by Glass Lab carries one of these.
enum Provenance: String, Codable, CaseIterable, Sendable {
    /// A value the operating system reports through a public API.
    case apiExposed = "API Exposed"
    /// Read directly from captured pixels or timestamps.
    case measured = "Measured"
    /// Computed deterministically from measured values.
    case derived = "Derived"
    /// The result of fitting a model; depends on the model's assumptions.
    case estimated = "Estimated"
    /// A value or relation from theory, not from this device.
    case theoretical = "Theoretical"
    /// Cannot be obtained through public interfaces.
    case unavailable = "Unavailable"
    /// Entered by the operator because no public API exposes it.
    case userEntered = "User Entered"
    /// A configuration value recorded at acquisition time (e.g. capture frame rate requested).
    case recorded = "Recorded"

    var symbol: String {
        switch self {
        case .apiExposed: return "cpu"
        case .measured: return "ruler"
        case .derived: return "function"
        case .estimated: return "chart.xyaxis.line"
        case .theoretical: return "book.closed"
        case .unavailable: return "nosign"
        case .userEntered: return "person.crop.circle"
        case .recorded: return "record.circle"
        }
    }
}

enum ConfidenceLevel: String, Codable, CaseIterable, Sendable, Comparable {
    case none = "None"
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    private var rank: Int {
        switch self { case .none: return 0; case .low: return 1; case .medium: return 2; case .high: return 3 }
    }
    static func < (a: ConfidenceLevel, b: ConfidenceLevel) -> Bool { a.rank < b.rank }
}

struct Confidence: Codable, Hashable, Sendable {
    var level: ConfidenceLevel
    /// Plain-language reason for the level, always shown next to it.
    var justification: String

    static func none(_ why: String) -> Confidence { Confidence(level: .none, justification: why) }
    static func low(_ why: String) -> Confidence { Confidence(level: .low, justification: why) }
    static func medium(_ why: String) -> Confidence { Confidence(level: .medium, justification: why) }
    static func high(_ why: String) -> Confidence { Confidence(level: .high, justification: why) }
}

enum ValidityStatus: String, Codable, Sendable {
    case valid = "Valid"
    case warning = "Valid with warnings"
    case invalid = "Invalid"
    case notAvailable = "N/A"
    case incomplete = "Incomplete"
}

struct Validity: Codable, Hashable, Sendable {
    var status: ValidityStatus
    var reasons: [String]

    static let valid = Validity(status: .valid, reasons: [])
    static func warning(_ r: String...) -> Validity { Validity(status: .warning, reasons: r) }
    static func invalid(_ r: String...) -> Validity { Validity(status: .invalid, reasons: r) }
    static func notAvailable(_ r: String...) -> Validity { Validity(status: .notAvailable, reasons: r) }

    var isUsable: Bool { status == .valid || status == .warning }
}

/// Uncertainty attached to a value. `halfWidth` is in the value's unit.
struct Uncertainty: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case standardDeviation = "±1σ (sample)"
        case standardError = "±1 SE"
        case confidenceInterval95 = "95% CI"
        case quantization = "Quantization bound"
        case fitInterval = "Fit interval"
        case range = "Range (min–max)"
    }
    var halfWidth: Double
    var kind: Kind
}

/// Pixel rectangle in the coordinate system of a stored frame.
struct PixelRegion: Codable, Hashable, Sendable {
    var x: Int, y: Int, width: Int, height: Int
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    init(x: Int, y: Int, width: Int, height: Int) { self.x = x; self.y = y; self.width = width; self.height = height }
    init(_ r: CGRect) { x = Int(r.minX.rounded()); y = Int(r.minY.rounded()); width = Int(r.width.rounded()); height = Int(r.height.rounded()) }
}

/// One quantitative result. Missing values are `nil` and must carry a reason in `validity`.
struct Measurement: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var value: Double?
    var unit: String
    var provenance: Provenance
    var algorithm: String
    var algorithmVersion: String
    var confidence: Confidence
    var uncertainty: Uncertainty?
    var sampleCount: Int
    var region: PixelRegion?
    var timestamp: Date
    var validity: Validity
    /// Number of significant digits the measurement precision justifies.
    var significantDigits: Int
    /// Source frame or recording identifiers.
    var sources: [String]
    var notes: String?
    /// Optional vector payload (profiles, histograms). Stored as plain arrays for CSV/JSON export.
    var series: [Series]?

    struct Series: Codable, Hashable, Sendable {
        var label: String
        var xUnit: String
        var yUnit: String
        var x: [Double]
        var y: [Double]
    }

    init(name: String, value: Double?, unit: String, provenance: Provenance,
         algorithm: String, version: String, confidence: Confidence,
         uncertainty: Uncertainty? = nil, sampleCount: Int, region: PixelRegion? = nil,
         validity: Validity = .valid, significantDigits: Int = 3, sources: [String] = [],
         notes: String? = nil, series: [Series]? = nil) {
        self.name = name
        self.value = (value?.isFinite ?? false) ? value : nil
        self.unit = unit
        self.provenance = provenance
        self.algorithm = algorithm
        self.algorithmVersion = version
        self.confidence = confidence
        self.uncertainty = uncertainty
        self.sampleCount = sampleCount
        self.region = region
        self.timestamp = Date()
        var v = validity
        if value != nil && !(value!.isFinite) { v = .invalid("Computation produced a non-finite value") }
        self.validity = v
        self.significantDigits = significantDigits
        self.sources = sources
        self.notes = notes
        self.series = series
    }

    /// A measurement that could not be obtained. Value is always nil.
    static func unavailable(_ name: String, unit: String, algorithm: String, version: String, reason: String, provenance: Provenance = .unavailable) -> Measurement {
        Measurement(name: name, value: nil, unit: unit, provenance: provenance, algorithm: algorithm, version: version,
                    confidence: .none(reason), sampleCount: 0, validity: .notAvailable(reason), significantDigits: 0)
    }
}

/// Algorithm identifiers and versions. Bump a version whenever the math changes so stored
/// results can be re-derived and compared across app versions.
enum AlgorithmVersion {
    static let imageStatistics = "stats-1.0"
    static let colorScience = "color-1.1"
    static let translucency = "translucency-1.0"
    static let blurFit = "blurfit-1.0"
    static let edgeSpread = "esf-1.0"
    static let displacement = "ncc-flow-1.0"
    static let highlights = "edge-excess-1.0"
    static let errorMetrics = "metrics-1.0"
    static let motion = "motion-1.0"
    static let multiBackground = "affine-transfer-1.0"
    static let registration = "register-int-1.0"
    static let reconstruction = "recon-model-1.0"
    static let performance = "perf-1.0"
}
