import UIKit
import Observation
import os

/// Reads device, display, accessibility, power and thermal state through public APIs only.
@MainActor
@Observable
final class DeviceEnvironmentMonitor {
    private(set) var current = EnvironmentSnapshot()
    /// Operator-entered values, persisted between launches.
    var userEntered: [String: String] {
        didSet { UserDefaults.standard.set(userEntered, forKey: "userEnteredEnvironment") }
    }
    private var observers: [NSObjectProtocol] = []

    init() {
        userEntered = (UserDefaults.standard.dictionary(forKey: "userEnteredEnvironment") as? [String: String]) ?? [:]
        UIDevice.current.isBatteryMonitoringEnabled = true
        let names: [Notification.Name] = [
            UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            UIAccessibility.boldTextStatusDidChangeNotification,
            UIAccessibility.buttonShapesEnabledStatusDidChangeNotification,
            UIAccessibility.invertColorsStatusDidChangeNotification,
            UIAccessibility.grayscaleStatusDidChangeNotification,
            UIContentSizeCategory.didChangeNotification,
            ProcessInfo.thermalStateDidChangeNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange,
            UIDevice.orientationDidChangeNotification,
            UIScreen.brightnessDidChangeNotification,
        ]
        for n in names {
            observers.append(NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func refresh() {
        current = Self.snapshot(userEntered: userEntered)
    }

    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first
    }

    static func snapshot(userEntered: [String: String] = [:]) -> EnvironmentSnapshot {
        var s = EnvironmentSnapshot()
        var sys = utsname()
        uname(&sys)
        s.machineIdentifier = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
        #if targetEnvironment(simulator)
        s.isSimulator = true
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { s.machineIdentifier = sim }
        #endif
        let device = UIDevice.current
        s.deviceModel = device.model
        s.systemName = device.systemName
        s.systemVersion = device.systemVersion
        switch device.userInterfaceIdiom {
        case .phone: s.idiom = "iPhone"
        case .pad: s.idiom = "iPad"
        case .mac: s.idiom = "Mac"
        case .vision: s.idiom = "Vision"
        default: s.idiom = "Other"
        }
        let info = Bundle.main.infoDictionary ?? [:]
        s.appVersion = info["CFBundleShortVersionString"] as? String ?? "unknown"
        s.appBuild = info["CFBundleVersion"] as? String ?? "unknown"
        s.sdkName = info["DTSDKName"] as? String ?? "unknown"
        s.sdkBuild = info["DTSDKBuild"] as? String ?? "unknown"
        s.xcodeVersion = info["DTXcode"] as? String ?? "unknown"

        let window = keyWindow
        if let screen = window?.windowScene?.screen {
            s.screenBoundsPoints = CGSizeCodable(screen.bounds.size)
            s.nativeBoundsPixels = CGSizeCodable(screen.nativeBounds.size)
            s.scale = screen.scale
            s.nativeScale = screen.nativeScale
            s.maximumFramesPerSecond = screen.maximumFramesPerSecond
            s.brightness = Double(screen.brightness)
        }
        if let window {
            s.windowSizePoints = CGSizeCodable(window.bounds.size)
            let t = window.traitCollection
            s.displayGamut = t.displayGamut == .P3 ? "P3" : (t.displayGamut == .SRGB ? "sRGB" : "unspecified")
            s.interfaceStyle = t.userInterfaceStyle == .dark ? "Dark" : (t.userInterfaceStyle == .light ? "Light" : "Unspecified")
            s.contentSizeCategory = t.preferredContentSizeCategory.rawValue
            s.layoutDirection = t.layoutDirection == .rightToLeft ? "RTL" : "LTR"
            s.horizontalSizeClass = t.horizontalSizeClass == .regular ? "regular" : (t.horizontalSizeClass == .compact ? "compact" : "unspecified")
            s.verticalSizeClass = t.verticalSizeClass == .regular ? "regular" : (t.verticalSizeClass == .compact ? "compact" : "unspecified")
            if let o = window.windowScene?.effectiveGeometry.interfaceOrientation {
                switch o {
                case .portrait: s.orientation = "Portrait"
                case .portraitUpsideDown: s.orientation = "Portrait Upside Down"
                case .landscapeLeft: s.orientation = "Landscape Left"
                case .landscapeRight: s.orientation = "Landscape Right"
                default: s.orientation = "Unknown"
                }
            }
        }
        s.reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        s.increaseContrast = UIAccessibility.isDarkerSystemColorsEnabled
        s.reduceMotion = UIAccessibility.isReduceMotionEnabled
        s.boldText = UIAccessibility.isBoldTextEnabled
        s.buttonShapes = UIAccessibility.buttonShapesEnabled
        s.differentiateWithoutColor = UIAccessibility.shouldDifferentiateWithoutColor
        s.invertColors = UIAccessibility.isInvertColorsEnabled
        s.grayscale = UIAccessibility.isGrayscaleEnabled
        s.onOffLabels = UIAccessibility.isOnOffSwitchLabelsEnabled
        s.prefersCrossFadeTransitions = UIAccessibility.prefersCrossFadeTransitions

        let pi = ProcessInfo.processInfo
        s.lowPowerMode = pi.isLowPowerModeEnabled
        s.thermalState = thermalName(pi.thermalState)
        switch device.batteryState {
        case .charging: s.batteryState = "Charging"
        case .full: s.batteryState = "Full"
        case .unplugged: s.batteryState = "Unplugged"
        default: s.batteryState = "Unknown"
        }
        s.batteryLevel = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        s.physicalMemoryBytes = pi.physicalMemory
        s.memoryFootprintBytes = MemoryProbe.footprint()
        s.timestamp = Date()
        s.userEntered = userEntered
        return s
    }

    nonisolated static func thermalName(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

enum MemoryProbe {
    /// Physical footprint of this process (bytes), the figure Xcode's memory gauge shows.
    static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : nil
    }

    static func availableForProcess() -> UInt64 {
        UInt64(os_proc_available_memory())
    }
}

/// Guards for long-running analysis work.
enum ResourceGuard {
    static var thermalAllowsHeavyWork: Bool {
        let t = ProcessInfo.processInfo.thermalState
        return t == .nominal || t == .fair
    }

    /// Throws when the device is hot or the process is close to its memory limit.
    static func check(estimatedBytes: UInt64 = 0) throws {
        if !thermalAllowsHeavyWork {
            throw GlassLabError.thermalLimit("thermal state is \(DeviceEnvironmentMonitor.thermalName(ProcessInfo.processInfo.thermalState))")
        }
        if estimatedBytes > 0 && estimatedBytes > MemoryProbe.availableForProcess() / 2 {
            throw GlassLabError.invalidData("operation needs ~\(Format.bytes(estimatedBytes)), more than half of the memory available to the app")
        }
    }
}
