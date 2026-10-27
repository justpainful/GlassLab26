import Foundation
import SwiftUI

/// A color stored with explicit color space and *encoded* (non-linear) components.
struct RGBAColor: Codable, Hashable, Sendable {
    enum Space: String, Codable, CaseIterable, Sendable { case sRGB = "sRGB", displayP3 = "Display P3" }
    var space: Space = .sRGB
    var r: Double, g: Double, b: Double
    var a: Double = 1

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1, space: Space = .sRGB) {
        self.r = r; self.g = g; self.b = b; self.a = a; self.space = space
    }

    var color: Color {
        Color(space == .sRGB ? .sRGB : .displayP3, red: r, green: g, blue: b, opacity: a)
    }
    var uiColor: UIColor {
        space == .sRGB ? UIColor(red: r, green: g, blue: b, alpha: a) : UIColor(displayP3Red: r, green: g, blue: b, alpha: a)
    }
    var cgColor: CGColor {
        let cs = CGColorSpace(name: space == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3)!
        return CGColor(colorSpace: cs, components: [r, g, b, a])!
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    init?(hex: String, space: Space = .sRGB) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255, 1, space: space)
    }

    /// HSV in encoded space. Hue in degrees.
    var hsv: (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = 60 * ((b - r) / d + 2) }
            else { h = 60 * ((r - g) / d + 4) }
        }
        if h < 0 { h += 360 }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    var hsl: (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        let s = d == 0 ? 0 : d / (1 - abs(2 * l - 1))
        return (hsv.h, s, l)
    }

    static func fromHSV(h: Double, s: Double, v: Double, space: Space = .sRGB) -> RGBAColor {
        let c = v * s, hp = (h.truncatingRemainder(dividingBy: 360)) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        var (r, g, b) = (0.0, 0.0, 0.0)
        switch Int(hp) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return RGBAColor(r + m, g + m, b + m, 1, space: space)
    }

    static let black = RGBAColor(0, 0, 0)
    static let white = RGBAColor(1, 1, 1)
    /// sRGB neutral 50% encoded gray.
    static let neutralGray = RGBAColor(0.5, 0.5, 0.5)
    /// 18% linear reflectance gray: encoded sRGB value 0.4614 (≈ #767676).
    static let gray18 = RGBAColor(0.4614, 0.4614, 0.4614)
}

// MARK: - Experiment axes

enum NativeFramework: String, Codable, CaseIterable, Identifiable, Sendable {
    case swiftUI = "SwiftUI"
    case uiKit = "UIKit"
    var id: String { rawValue }
}

/// The official glass variants. `none` removes the effect entirely (no modifier applied).
enum GlassVariant: String, Codable, CaseIterable, Identifiable, Sendable {
    case regular = "Regular"
    case clear = "Clear"
    case identity = "Identity"
    case none = "No Glass"
    var id: String { rawValue }
}

enum GlassShapeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case capsule = "Capsule"
    case circle = "Circle"
    case roundedRect = "Rounded Rectangle"
    case rect = "Rectangle"
    case ellipse = "Ellipse"
    case customStar = "Custom Shape (Star)"
    var id: String { rawValue }
}

enum GlassContentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case empty = "Empty"
    case text = "Text"
    case symbol = "SF Symbol"
    case mixed = "Text + Symbol"
    var id: String { rawValue }
}

/// What the experiment canvas renders as the subject. Every case is built from native API.
enum SubjectKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case glassSurface = "Glass Surface"
    case glassGroup = "Glass Group (Container)"
    case glassButton = "Button · .glass"
    case glassProminentButton = "Button · .glassProminent"
    case glassClearButton = "Button · .glass(.clear)"
    case segmentedControl = "Segmented Control"
    case toggle = "Toggle"
    case slider = "Slider"
    case uikitNavigationBar = "UINavigationBar"
    case uikitToolbar = "UIToolbar"
    case uikitTabBar = "UITabBar"
    case uikitSegmented = "UISegmentedControl"
    var id: String { rawValue }

    var framework: NativeFramework {
        switch self {
        case .uikitNavigationBar, .uikitToolbar, .uikitTabBar, .uikitSegmented: return .uiKit
        default: return .swiftUI
        }
    }
    /// Whether the user's glass variant/shape/tint settings apply to this subject.
    var usesGlassParameters: Bool {
        switch self {
        case .glassSurface, .glassGroup, .glassButton, .glassProminentButton, .glassClearButton: return true
        default: return false
        }
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

enum ReferenceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Same view tree with `Glass.identity` (content stays, material removed).
    case identityGlass = "Identity Glass"
    /// Subject hidden (opacity 0) while layout is preserved.
    case subjectHidden = "Subject Hidden"
    var id: String { rawValue }
}

enum InteractionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case tap = "Tap"
    case pressAndHold = "Press and Hold"
    case drag = "Drag"
    case slowDrag = "Slow Drag"
    case fastDrag = "Fast Drag"
    case repeatedTap = "Repeated Tap"
    case selectionChange = "Selection Change"
    case appear = "Appearance Transition"
    case disappear = "Disappearance Transition"
    case merge = "Glass Merge"
    case split = "Glass Split"
    case morph = "Glass Morph"
    case containerSpacing = "Container Spacing Animation"
    case menuOpenClose = "Menu Open / Close"
    case sheet = "Sheet Present / Dismiss"
    case navigationPushPop = "Navigation Push / Pop"
    var id: String { rawValue }
    /// Interactions the app can trigger programmatically (others need the operator's finger).
    var isProgrammatic: Bool {
        switch self {
        case .appear, .disappear, .merge, .split, .morph, .containerSpacing, .selectionChange: return true
        default: return false
        }
    }
}

enum CaptureMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    /// `UIWindow.drawHierarchy(in:afterScreenUpdates:)`. Must pass capture validation per device/OS.
    case viewSnapshot = "View Snapshot"
    /// ReplayKit in-app capture (`RPScreenRecorder.startCapture`). Real composited frames, YCbCr 4:2:0.
    case replayKit = "ReplayKit Frame"
    /// System screenshot taken by the operator (side + volume button), read from Photos. Lossless PNG.
    case systemScreenshot = "System Screenshot"
    /// Image imported by the operator.
    case imported = "Imported"
    var id: String { rawValue }
}

enum MeasurementModule: String, Codable, CaseIterable, Identifiable, Sendable {
    case statistics = "Image Statistics"
    case translucency = "Translucency"
    case blur = "Blur"
    case edgeSpread = "Edge Spread / MTF"
    case refraction = "Refraction & Distortion"
    case highlights = "Highlights & Edge Lighting"
    case color = "Color Science"
    case errorMetrics = "Image Error Metrics"
    var id: String { rawValue }
}

// MARK: - Geometry

struct GlassGeometry: Codable, Hashable, Sendable {
    var width: Double = 220          // pt
    var height: Double = 88          // pt
    var cornerRadius: Double = 24    // pt (rounded rect only)
    var offsetX: Double = 0          // pt from canvas center
    var offsetY: Double = 0          // pt from canvas center
    var rotation: Double = 0         // degrees
    var scale: Double = 1
    var padding: Double = 16         // pt (content inset)
    var elementCount: Int = 1
    var elementSpacing: Double = 24  // pt between elements in the stack
    var containerSpacing: Double = 40 // pt; GlassEffectContainer(spacing:)
    var useContainer: Bool = true
    var unionAll: Bool = false       // glassEffectUnion for all elements
    var vertical: Bool = false

    var aspectRatio: Double { height > 0 ? width / height : 0 }
}

// MARK: - Configuration

struct SceneConfiguration: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var name: String = "Untitled Experiment"
    var subject: SubjectKind = .glassSurface
    /// Framework used for glass surfaces and groups (fixed for other subjects).
    var framework: NativeFramework = .swiftUI
    var variant: GlassVariant = .regular
    var shape: GlassShapeKind = .capsule
    var geometry = GlassGeometry()
    var tint: RGBAColor? = nil
    var interactive: Bool = false
    var content: GlassContentKind = .empty
    var contentText: String = "Glass"
    var contentSymbol: String = "drop.fill"
    var background = BackgroundSpec()
    var appearance: AppearanceMode = .system
    var interaction: InteractionKind = .none
    var captureMethod: CaptureMethod = .viewSnapshot
    var referenceMode: ReferenceMode = .identityGlass
    var modules: Set<MeasurementModule> = Set(MeasurementModule.allCases)
    var repetitions: Int = 1
    /// Settle time after any scene change before a frame is accepted (ms).
    var settleMilliseconds: Double = 600
    /// Optional free-form notes stored with every experiment created from this configuration.
    var notes: String = ""

    /// A short, stable description used in lists and file names.
    var summary: String {
        var parts = [subject.rawValue]
        if subject == .glassSurface || subject == .glassGroup { parts.append(effectiveFramework.rawValue) }
        if subject.usesGlassParameters {
            parts.append(variant.rawValue)
            parts.append(shape.rawValue)
            if tint != nil { parts.append("Tinted") }
            if interactive { parts.append("Interactive") }
        }
        parts.append(background.kind.rawValue)
        if appearance != .system { parts.append(appearance.rawValue) }
        return parts.joined(separator: " · ")
    }

    var effectiveFramework: NativeFramework {
        (subject == .glassSurface || subject == .glassGroup) ? framework : subject.framework
    }

    func duplicated(named newName: String? = nil) -> SceneConfiguration {
        var c = self
        c.id = UUID()
        c.name = newName ?? (name + " Copy")
        return c
    }
}
