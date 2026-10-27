import SwiftUI

/// Device & environment metadata (public APIs only), operator-entered facts, capture validation status
/// and a guide for preparing accessibility and appearance states.
struct EnvironmentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let e = model.environment.current
        NavigationStack {
            List {
                Section("Device") {
                    KeyValueRow(key: "Model identifier", value: e.machineIdentifier, provenance: .apiExposed)
                    KeyValueRow(key: "Device", value: "\(e.deviceModel) (\(e.idiom))", provenance: .apiExposed)
                    KeyValueRow(key: "System", value: "\(e.systemName) \(e.systemVersion)", provenance: .apiExposed)
                    if e.isSimulator { Label("Simulator: captures are not visual references", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    KeyValueRow(key: "App", value: "\(e.appVersion) (\(e.appBuild))", provenance: .apiExposed)
                    KeyValueRow(key: "SDK / Xcode", value: "\(e.sdkName) \(e.sdkBuild) / \(e.xcodeVersion)", provenance: .apiExposed)
                }
                Section("Display") {
                    KeyValueRow(key: "Screen bounds", value: "\(Int(e.screenBoundsPoints.width))x\(Int(e.screenBoundsPoints.height)) pt", provenance: .apiExposed)
                    KeyValueRow(key: "Native bounds", value: "\(Int(e.nativeBoundsPixels.width))x\(Int(e.nativeBoundsPixels.height)) px", provenance: .apiExposed)
                    KeyValueRow(key: "Scale / native scale", value: "\(Format.number(e.scale, digits: 4)) / \(Format.number(e.nativeScale, digits: 4))", provenance: .apiExposed)
                    KeyValueRow(key: "Display gamut", value: e.displayGamut, provenance: .apiExposed)
                    KeyValueRow(key: "Max frame rate", value: "\(e.maximumFramesPerSecond) Hz", provenance: .apiExposed)
                    KeyValueRow(key: "Brightness setting", value: Format.number(e.brightness, digits: 2), provenance: .apiExposed)
                    KeyValueRow(key: "Window", value: "\(Int(e.windowSizePoints.width))x\(Int(e.windowSizePoints.height)) pt", provenance: .apiExposed)
                    KeyValueRow(key: "Orientation", value: e.orientation, provenance: .apiExposed)
                    KeyValueRow(key: "Size classes", value: "H \(e.horizontalSizeClass) · V \(e.verticalSizeClass)", provenance: .apiExposed)
                }
                Section {
                    KeyValueRow(key: "Interface style", value: e.interfaceStyle, provenance: .apiExposed)
                    KeyValueRow(key: "Reduce Transparency", value: onOff(e.reduceTransparency), provenance: .apiExposed)
                    KeyValueRow(key: "Increase Contrast", value: onOff(e.increaseContrast), provenance: .apiExposed)
                    KeyValueRow(key: "Reduce Motion", value: onOff(e.reduceMotion), provenance: .apiExposed)
                    KeyValueRow(key: "Prefer Cross-Fade", value: onOff(e.prefersCrossFadeTransitions), provenance: .apiExposed)
                    KeyValueRow(key: "Bold Text", value: onOff(e.boldText), provenance: .apiExposed)
                    KeyValueRow(key: "Button Shapes", value: onOff(e.buttonShapes), provenance: .apiExposed)
                    KeyValueRow(key: "Differentiate Without Color", value: onOff(e.differentiateWithoutColor), provenance: .apiExposed)
                    KeyValueRow(key: "Smart Invert / Grayscale", value: "\(onOff(e.invertColors)) / \(onOff(e.grayscale))", provenance: .apiExposed)
                    KeyValueRow(key: "Text size", value: e.contentSizeCategory, provenance: .apiExposed)
                    KeyValueRow(key: "Layout direction", value: e.layoutDirection, provenance: .apiExposed)
                } header: { Text("Appearance & Accessibility") } footer: {
                    Text("Read live through UIAccessibility and trait collections. Glass Lab never changes system settings; the guide below shows where to set each one.")
                }
                Section("Power & thermal") {
                    KeyValueRow(key: "Thermal state", value: e.thermalState, provenance: .apiExposed)
                    KeyValueRow(key: "Low Power Mode", value: onOff(e.lowPowerMode), provenance: .apiExposed)
                    KeyValueRow(key: "Battery", value: "\(e.batteryState) \(e.batteryLevel.map { Format.number($0 * 100, digits: 3) + "%" } ?? "")", provenance: .apiExposed)
                    KeyValueRow(key: "Memory footprint", value: e.memoryFootprintBytes.map { Format.bytes($0) } ?? "N/A", provenance: .apiExposed)
                    KeyValueRow(key: "Physical memory", value: Format.bytes(e.physicalMemoryBytes), provenance: .apiExposed)
                }
                Section {
                    ForEach(EnvironmentSnapshot.userEnterableKeys, id: \.key) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            TextField(item.key, text: Binding(get: { model.environment.userEntered[item.key] ?? "" },
                                                              set: { model.environment.userEntered[item.key] = $0.isEmpty ? nil : $0; model.environment.refresh() }))
                            Text(item.help).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Operator-entered (no public API)") } footer: {
                    Text("Recorded with every experiment and marked User Entered.")
                }
                Section("Capture validation (this device & OS)") {
                    ForEach(CaptureMethod.allCases.filter { $0 != .imported }) { m in
                        if let v = model.capture.validation(for: m) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label("\(m.rawValue): \(v.passed ? "passed" : "failed")", systemImage: v.passed ? "checkmark.seal" : "xmark.octagon")
                                    .foregroundStyle(v.passed ? .green : .red)
                                ForEach(v.notes, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                            }
                        } else {
                            Label("\(m.rawValue): not validated", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Preparing a test state") {
                    ForEach(Self.guide, id: \.0) { g in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.0).font(.subheadline.weight(.semibold))
                            Text(g.1).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Limitations") {
                    ForEach(ResearchCatalog.limitations, id: \.self) { Text($0).font(.caption) }
                }
            }
            .navigationTitle("Environment")
            .refreshable { model.environment.refresh() }
            .onAppear { model.environment.refresh() }
        }
    }

    private func onOff(_ b: Bool) -> String { b ? "On" : "Off" }

    static let guide: [(String, String)] = [
        ("Light / Dark", "Use the Lab's Appearance control (window override) or Settings › Display & Brightness. System-wide changes also affect system UI."),
        ("Reduce Transparency", "Settings › Accessibility › Display & Text Size › Reduce Transparency. Glass becomes more opaque; verify here that it reads On."),
        ("Increase Contrast", "Settings › Accessibility › Display & Text Size › Increase Contrast."),
        ("Reduce Motion", "Settings › Accessibility › Motion › Reduce Motion. Affects interactive and morph animations."),
        ("Larger Text", "Settings › Accessibility › Display & Text Size › Larger Text. Changes content size category and control metrics."),
        ("Bold Text", "Settings › Accessibility › Display & Text Size › Bold Text."),
        ("Liquid Glass appearance", "On OS versions that offer it: Settings › Display & Brightness › Liquid Glass (Clear / Tinted). Enter the value above; no public API reads it."),
        ("Before measuring", "Disable True Tone and Night Shift if you compare across devices by eye; they do not change captured pixels. Let the device cool to Nominal thermal state."),
    ]
}
