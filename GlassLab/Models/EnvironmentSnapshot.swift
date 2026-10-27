import Foundation

/// Everything about the device and system state that public APIs expose at a given moment,
/// plus operator-entered facts that no API exposes.
struct EnvironmentSnapshot: Codable, Hashable, Sendable {
    // Device
    var machineIdentifier: String = "unknown"      // utsname.machine, e.g. "iPhone18,1"
    var deviceModel: String = "unknown"            // UIDevice.model
    var idiom: String = "unknown"
    var systemName: String = "unknown"
    var systemVersion: String = "unknown"
    var isSimulator: Bool = false
    // App build
    var appVersion: String = "unknown"
    var appBuild: String = "unknown"
    var sdkName: String = "unknown"                // DTSDKName injected by Xcode
    var sdkBuild: String = "unknown"
    var xcodeVersion: String = "unknown"
    // Screen
    var screenBoundsPoints: CGSizeCodable = CGSizeCodable(.zero)
    var nativeBoundsPixels: CGSizeCodable = CGSizeCodable(.zero)
    var scale: Double = 0
    var nativeScale: Double = 0
    var maximumFramesPerSecond: Int = 0
    var displayGamut: String = "unknown"
    var brightness: Double? = nil                  // UIScreen.brightness (0–1), API exposed
    var windowSizePoints: CGSizeCodable = CGSizeCodable(.zero)
    // Traits
    var interfaceStyle: String = "unknown"
    var contentSizeCategory: String = "unknown"
    var layoutDirection: String = "unknown"
    var orientation: String = "unknown"
    var horizontalSizeClass: String = "unknown"
    var verticalSizeClass: String = "unknown"
    // Accessibility (public UIAccessibility APIs)
    var reduceTransparency: Bool = false
    var increaseContrast: Bool = false
    var reduceMotion: Bool = false
    var boldText: Bool = false
    var buttonShapes: Bool = false
    var differentiateWithoutColor: Bool = false
    var invertColors: Bool = false
    var grayscale: Bool = false
    var onOffLabels: Bool = false
    var prefersCrossFadeTransitions: Bool = false
    // Power & thermal
    var lowPowerMode: Bool = false
    var thermalState: String = "unknown"
    var batteryState: String = "unknown"
    var batteryLevel: Double? = nil
    // Memory
    var physicalMemoryBytes: UInt64 = 0
    var memoryFootprintBytes: UInt64? = nil
    // Time
    var timestamp: Date = Date()
    var timeZone: String = TimeZone.current.identifier
    // Operator-entered (no public API)
    var userEntered: [String: String] = [:]

    /// Fields that cannot be read by an app and should be entered manually when they matter.
    static let userEnterableKeys: [(key: String, help: String)] = [
        ("True Tone", "Settings › Display & Brightness › True Tone (On/Off)"),
        ("Night Shift", "Settings › Display & Brightness › Night Shift (On/Off/Scheduled)"),
        ("Auto-Brightness", "Settings › Accessibility › Display & Text Size › Auto-Brightness"),
        ("Reduce White Point", "Settings › Accessibility › Display & Text Size › Reduce White Point (%)"),
        ("Display Zoom", "Settings › Display & Brightness › Display Zoom (Default/Larger Text)"),
        ("Liquid Glass Appearance", "Settings › Display & Brightness › Liquid Glass (Clear/Tinted), if present on this OS"),
        ("Refresh Rate Limit", "Settings › Accessibility › Motion › Limit Frame Rate"),
        ("Ambient Light", "Describe room lighting during capture (affects what you see, not captured pixels)"),
    ]

    var deviceLine: String { "\(machineIdentifier) · \(systemName) \(systemVersion)\(isSimulator ? " · Simulator" : "")" }
}
