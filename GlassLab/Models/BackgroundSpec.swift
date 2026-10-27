import Foundation

enum BackgroundKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case solid = "Solid Color"
    case linearGradient = "Linear Gradient"
    case radialGradient = "Radial Gradient"
    case checkerboard = "Checkerboard"
    case fiducialChecker = "Checker + Fiducials"
    case fineGrid = "Fine Grid"
    case denseGrid = "Dense Grid"
    case dotGrid = "Dot Grid"
    case horizontalLines = "Horizontal Lines"
    case verticalLines = "Vertical Lines"
    case diagonalLines = "Diagonal Lines"
    case stepEdge = "Step Edge"
    case highFrequencyNoise = "High-Frequency Noise"
    case lowFrequencyNoise = "Low-Frequency Noise"
    case randomDots = "Random Dots (matching)"
    case textPattern = "Text Pattern"
    case fineTypography = "Fine Typography"
    case largeTypography = "Large Typography"
    case movingGradient = "Moving Gradient"
    case movingObjects = "Moving Objects"
    case importedImage = "Imported Image / Photo"
    case importedVideo = "Imported Video"
    case scrollingContent = "Scrolling Content"
    var id: String { rawValue }

    /// Backgrounds whose content changes over time when playback is on.
    var isAnimated: Bool {
        switch self {
        case .movingGradient, .movingObjects, .importedVideo, .scrollingContent: return true
        default: return false
        }
    }
    /// Backgrounds with enough spatial detail for blur and displacement estimation.
    var isTextured: Bool {
        switch self {
        case .solid, .linearGradient, .radialGradient, .movingGradient: return false
        default: return true
        }
    }
    /// Backgrounds with a known period (pt) along at least one axis.
    var isPeriodic: Bool {
        switch self {
        case .checkerboard, .fineGrid, .denseGrid, .dotGrid, .horizontalLines, .verticalLines, .diagonalLines, .fiducialChecker: return true
        default: return false
        }
    }

    static let groups: [(String, [BackgroundKind])] = [
        ("Uniform", [.solid]),
        ("Gradients", [.linearGradient, .radialGradient]),
        ("Calibration", [.checkerboard, .fiducialChecker, .fineGrid, .denseGrid, .dotGrid, .stepEdge, .randomDots]),
        ("Lines", [.horizontalLines, .verticalLines, .diagonalLines]),
        ("Noise", [.highFrequencyNoise, .lowFrequencyNoise]),
        ("Typography", [.textPattern, .fineTypography, .largeTypography]),
        ("Dynamic", [.movingGradient, .movingObjects, .scrollingContent]),
        ("Imported", [.importedImage, .importedVideo]),
    ]
}

struct GradientStop: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var color: RGBAColor
    var location: Double
}

/// A fully specified, reproducible background. Procedural backgrounds are deterministic for
/// a given spec and `phase`, so a reference and a test frame see identical pixels.
struct BackgroundSpec: Codable, Hashable, Sendable {
    var kind: BackgroundKind = .checkerboard
    /// Primary color (solid fill, pattern foreground).
    var primary: RGBAColor = .black
    /// Secondary color (pattern background).
    var secondary: RGBAColor = .white
    /// Color shown wherever nothing else is drawn. Always recorded; the screen never shows "no background".
    var base: RGBAColor = .neutralGray
    var stops: [GradientStop] = [
        GradientStop(color: RGBAColor(0.05, 0.35, 0.95), location: 0),
        GradientStop(color: RGBAColor(0.98, 0.45, 0.10), location: 1),
    ]
    var gradientAngle: Double = 0          // degrees
    /// Pattern period (pt): checker square, grid pitch, line pitch.
    var patternScale: Double = 16
    /// Stroke width (pt) for grids and lines.
    var lineWidth: Double = 1
    /// Noise cell size (pt) for noise backgrounds.
    var noiseFrequency: Double = 4
    var seed: UInt64 = 0x5EED
    /// Opacity of background elements only (never the glass).
    var elementOpacity: Double = 1
    /// Contrast multiplier around mid-gray applied to procedural and imported content.
    var contrast: Double = 1
    var saturation: Double = 1
    /// Animation speed in cycles per second for dynamic backgrounds.
    var motionSpeed: Double = 0.25
    /// Phase used when playback is frozen (0…1). Captures always use a frozen phase.
    var frozenPhase: Double = 0
    var isPlaying: Bool = false
    /// Position of moving objects / gradient center, in unit coordinates.
    var objectX: Double = 0.5
    var objectY: Double = 0.5
    /// Edge angle for the step-edge target (degrees, 0 = vertical edge).
    var edgeAngle: Double = 0
    /// Scroll offset (pt) for scrolling content.
    var scrollOffset: Double = 0
    /// Text used by typography backgrounds.
    var text: String = "Glass Lab 0123456789 The quick brown fox jumps over the lazy dog."
    var fontSize: Double = 13
    /// File name of an imported image or video inside the app's Backgrounds folder.
    var importedFile: String? = nil

    var summary: String {
        switch kind {
        case .solid: return "Solid \(primary.hex) (\(primary.space.rawValue))"
        case .checkerboard, .fiducialChecker, .fineGrid, .denseGrid, .dotGrid, .horizontalLines, .verticalLines, .diagonalLines:
            return "\(kind.rawValue) period \(Format.number(patternScale, digits: 3)) pt"
        case .importedImage, .importedVideo: return "\(kind.rawValue): \(importedFile ?? "none")"
        default: return kind.rawValue
        }
    }

    static func solid(_ c: RGBAColor) -> BackgroundSpec {
        var s = BackgroundSpec(); s.kind = .solid; s.primary = c; return s
    }
    static func pattern(_ k: BackgroundKind, scale: Double = 16) -> BackgroundSpec {
        var s = BackgroundSpec(); s.kind = k; s.patternScale = scale; return s
    }
}
