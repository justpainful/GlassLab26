import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LabInspector: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @State private var running = false

    var body: some View {
        @Bindable var stage = model.stage
        Form {
            Section("Experiment") {
                TextField("Name", text: $stage.config.name)
                Text(NativeGlass.apiDescription(stage.config)).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button("Save Preset", systemImage: "square.and.arrow.down") { model.presets.save(stage.config) }
                    Spacer()
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.presets.save(stage.config.duplicated()) }
                }
                .buttonStyle(.borderless)
            }
            Section("Subject") {
                Picker("Component", selection: $stage.config.subject) {
                    ForEach(SubjectKind.allCases) { Text($0.rawValue).tag($0) }
                }
                if stage.config.subject == .glassSurface || stage.config.subject == .glassGroup {
                    Picker("Framework", selection: $stage.config.framework) {
                        ForEach(NativeFramework.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                if stage.config.subject == .glassClearButton {
                    if #available(iOS 26.1, *) {
                        EmptyView()
                    } else {
                        Label(".glass(.clear) requires iOS 26.1; this OS renders .glass.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            if stage.config.subject.usesGlassParameters {
                Section("Glass") {
                    Picker("Variant", selection: $stage.config.variant) { ForEach(GlassVariant.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                    Picker("Shape", selection: $stage.config.shape) { ForEach(GlassShapeKind.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Tint", isOn: Binding(get: { stage.config.tint != nil }, set: { stage.config.tint = $0 ? RGBAColor(0, 0.48, 1, 0.6) : nil }))
                    if stage.config.tint != nil {
                        ColorEditor(title: "Tint color", color: Binding(get: { stage.config.tint ?? .black }, set: { stage.config.tint = $0 }), showsAlpha: true)
                    }
                    Toggle("Interactive", isOn: $stage.config.interactive)
                    Picker("Content", selection: $stage.config.content) { ForEach(GlassContentKind.allCases) { Text($0.rawValue).tag($0) } }
                    if stage.config.content == .text || stage.config.content == .mixed { TextField("Text", text: $stage.config.contentText) }
                    if stage.config.content == .symbol || stage.config.content == .mixed { TextField("SF Symbol name", text: $stage.config.contentSymbol).autocorrectionDisabled().textInputAutocapitalization(.never) }
                }
            }
            GeometryEditor(geometry: $stage.config.geometry, shape: stage.config.shape, isGroup: stage.config.subject == .glassGroup, displayScale: displayScale)
            BackgroundEditor(spec: $stage.config.background)
            Section("Appearance & Reference") {
                Picker("Appearance", selection: $stage.config.appearance) { ForEach(AppearanceMode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                Picker("Reference frame", selection: $stage.config.referenceMode) { ForEach(ReferenceMode.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Show native glass (preview)", isOn: $stage.materialOn)
                Text("Appearance is applied with the window's interface-style override. Accessibility settings are read from the system and recorded; change them in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Interaction") {
                Picker("Interaction", selection: $stage.config.interaction) { ForEach(InteractionKind.allCases) { Text($0.rawValue).tag($0) } }
                Button(stage.config.interaction.isProgrammatic ? "Run interaction" : "Operator performs it (recorded in Motion)") {
                    let spacing = stage.config.geometry.elementSpacing
                    running = true
                    Task {
                        await InteractionDriver.run(stage.config.interaction, stage: stage) { _, _ in }
                        InteractionDriver.reset(stage, spacing: spacing)
                        running = false
                    }
                }
                .disabled(!stage.config.interaction.isProgrammatic || running)
            }
            Section("Capture & Measurement") {
                Picker("Capture method", selection: $stage.config.captureMethod) {
                    ForEach(CaptureMethod.allCases.filter { $0 != .imported }) { Text($0.rawValue).tag($0) }
                }
                if let v = model.capture.validation(for: stage.config.captureMethod) {
                    Label(v.passed ? "Validated \(Format.timestamp.string(from: v.date))" : "Failed validation: measurements will be rejected",
                          systemImage: v.passed ? "checkmark.seal" : "xmark.octagon")
                        .font(.caption).foregroundStyle(v.passed ? .green : .red)
                } else if stage.config.captureMethod != .systemScreenshot {
                    Label("Not validated on this device/OS", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.orange)
                }
                Stepper("Settle \(Int(stage.config.settleMilliseconds)) ms", value: $stage.config.settleMilliseconds, in: 100...3000, step: 100)
                Stepper("Repetitions \(stage.config.repetitions)", value: $stage.config.repetitions, in: 1...20)
                ForEach(MeasurementModule.allCases) { m in
                    Toggle(m.rawValue, isOn: Binding(get: { stage.config.modules.contains(m) },
                                                     set: { if $0 { stage.config.modules.insert(m) } else { stage.config.modules.remove(m) } }))
                }
            }
            Section("Notes") {
                TextField("Notes stored with each experiment", text: $stage.config.notes, axis: .vertical).lineLimit(2...6)
            }
        }
        .onChange(of: stage.config.subject) { _, _ in stage.generation += 1 }
        .onChange(of: stage.config.framework) { _, _ in stage.generation += 1 }
    }
}

struct GeometryEditor: View {
    @Binding var geometry: GlassGeometry
    var shape: GlassShapeKind
    var isGroup: Bool
    var displayScale: CGFloat

    var body: some View {
        Section {
            row("Width", $geometry.width, 20...600, unit: "pt")
            row("Height", $geometry.height, 20...600, unit: "pt")
            KeyValueRow(key: "Aspect ratio", value: Format.number(geometry.aspectRatio, digits: 3) + " : 1")
            if shape == .roundedRect { row("Corner radius", $geometry.cornerRadius, 0...200, unit: "pt") }
            row("Position X", $geometry.offsetX, -400...400, unit: "pt")
            row("Position Y", $geometry.offsetY, -400...400, unit: "pt")
            row("Rotation", $geometry.rotation, -180...180, unit: "°", pixels: false)
            row("Scale", $geometry.scale, 0.25...3, unit: "x", pixels: false)
            row("Content padding", $geometry.padding, 0...80, unit: "pt")
            if isGroup {
                Stepper("Elements \(geometry.elementCount)", value: $geometry.elementCount, in: 1...12)
                row("Element spacing", $geometry.elementSpacing, -120...200, unit: "pt")
                Toggle("GlassEffectContainer", isOn: $geometry.useContainer)
                if geometry.useContainer { row("Container spacing", $geometry.containerSpacing, 0...200, unit: "pt") }
                Toggle("glassEffectUnion (all)", isOn: $geometry.unionAll)
                Toggle("Vertical stack", isOn: $geometry.vertical)
            }
        } header: {
            Text("Geometry")
        } footer: {
            Text("1 pt = \(Format.number(Double(displayScale), digits: 3)) px on this display (scale factor). Sizes are layout points; captured frames are in pixels.")
        }
    }

    private func row(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, unit: String, pixels: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                    .multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation).frame(width: 72).monospacedDigit()
                Text(unit).foregroundStyle(.secondary).frame(width: 18, alignment: .leading)
            }
            Slider(value: value, in: range)
            if pixels && unit == "pt" {
                Text("= \(Format.number(value.wrappedValue * Double(displayScale), digits: 4)) px").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

/// Edits an RGBAColor with a system color picker plus exact HEX, RGB and HSV/HSL readouts.
struct ColorEditor: View {
    var title: String
    @Binding var color: RGBAColor
    var showsAlpha = false
    @State private var hexText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ColorPicker(title, selection: Binding(get: { color.color }, set: { color = RGBAColor.from($0, alpha: showsAlpha) ?? color }), supportsOpacity: showsAlpha)
            HStack {
                TextField("HEX", text: $hexText).font(.caption.monospaced()).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .onSubmit { if let c = RGBAColor(hex: hexText, space: color.space) { var n = c; n.a = color.a; color = n } }
                Picker("Space", selection: $color.space) { ForEach(RGBAColor.Space.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.menu).labelsHidden()
            }
            channel("R", $color.r); channel("G", $color.g); channel("B", $color.b)
            if showsAlpha { channel("A", $color.a) }
            let hsv = color.hsv, hsl = color.hsl
            Text("HSV \(Int(hsv.h))° \(Int(hsv.s * 100))% \(Int(hsv.v * 100))%  ·  HSL \(Int(hsl.h))° \(Int(hsl.s * 100))% \(Int(hsl.l * 100))%")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .onAppear { hexText = color.hex }
        .onChange(of: color) { _, c in hexText = c.hex }
    }

    private func channel(_ name: String, _ v: Binding<Double>) -> some View {
        HStack {
            Text(name).font(.caption.monospaced()).frame(width: 14)
            Slider(value: v, in: 0...1)
            Text("\(Int((v.wrappedValue * 255).rounded()))").font(.caption.monospacedDigit()).frame(width: 30, alignment: .trailing)
        }
    }
}

extension RGBAColor {
    /// Converts a SwiftUI color into encoded sRGB components (values outside sRGB are clamped).
    static func from(_ c: Color, alpha: Bool) -> RGBAColor? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = UIColor(c).cgColor.converted(to: srgb, intent: .relativeColorimetric, options: nil),
              let comps = cg.components, comps.count >= 3 else { return nil }
        return RGBAColor(min(1, max(0, comps[0])), min(1, max(0, comps[1])), min(1, max(0, comps[2])), alpha ? (comps.count > 3 ? comps[3] : 1) : 1)
    }
}

struct BackgroundEditor: View {
    @Binding var spec: BackgroundSpec
    @State private var photo: PhotosPickerItem?
    @State private var importError: String?

    var body: some View {
        Section {
            Picker("Background", selection: $spec.kind) {
                ForEach(BackgroundKind.groups, id: \.0) { group in
                    Section(group.0) { ForEach(group.1) { Text($0.rawValue).tag($0) } }
                }
            }
            switch spec.kind {
            case .solid:
                ColorEditor(title: "Color", color: $spec.primary)
                quickColors
            case .linearGradient, .radialGradient, .movingGradient:
                ForEach($spec.stops) { $stop in
                    VStack(alignment: .leading) {
                        ColorEditor(title: "Stop", color: $stop.color)
                        HStack { Text("Location").font(.caption); Slider(value: $stop.location, in: 0...1); Text(Format.number(stop.location, digits: 2)).font(.caption.monospacedDigit()) }
                    }
                }
                .onDelete { spec.stops.remove(atOffsets: $0) }
                Button("Add stop", systemImage: "plus") { spec.stops.append(GradientStop(color: .white, location: 0.5)) }
                if spec.kind != .radialGradient { slider("Angle", $spec.gradientAngle, 0...360, "°") }
            case .importedImage, .importedVideo:
                PhotosPicker(selection: $photo, matching: spec.kind == .importedImage ? .images : .videos) {
                    Label(spec.importedFile == nil ? "Choose from Photos" : "Replace (\(spec.importedFile!))", systemImage: "photo.on.rectangle")
                }
                if let importError { Text(importError).font(.caption).foregroundStyle(.red) }
            default:
                ColorEditor(title: "Foreground", color: $spec.primary)
                ColorEditor(title: "Background", color: $spec.secondary)
            }
            if spec.kind.isPeriodic || spec.kind == .randomDots || spec.kind == .movingObjects || spec.kind == .scrollingContent {
                slider("Pattern scale", $spec.patternScale, 2...120, "pt")
            }
            if [BackgroundKind.fineGrid, .denseGrid, .dotGrid, .horizontalLines, .verticalLines, .diagonalLines, .randomDots].contains(spec.kind) {
                slider("Line width", $spec.lineWidth, 0.25...12, "pt")
            }
            if spec.kind == .highFrequencyNoise || spec.kind == .lowFrequencyNoise {
                slider("Texture frequency (cell)", $spec.noiseFrequency, 1...40, "pt")
            }
            if [BackgroundKind.highFrequencyNoise, .lowFrequencyNoise, .randomDots].contains(spec.kind) {
                Stepper("Seed \(spec.seed)", value: Binding(get: { Int(spec.seed) }, set: { spec.seed = UInt64(max(0, $0)) }), in: 0...99_999)
            }
            if spec.kind == .stepEdge { slider("Edge angle", $spec.edgeAngle, -45...45, "°"); slider("Edge position", $spec.objectX, 0...1, "") }
            if spec.kind == .radialGradient || spec.kind == .movingObjects { slider("Object X", $spec.objectX, 0...1, ""); slider("Object Y", $spec.objectY, 0...1, "") }
            if spec.kind == .scrollingContent { slider("Scroll offset", $spec.scrollOffset, 0...2000, "pt") }
            if [BackgroundKind.textPattern, .fineTypography, .largeTypography].contains(spec.kind) {
                TextField("Text", text: $spec.text, axis: .vertical)
                slider("Font size", $spec.fontSize, 5...48, "pt")
            }
            if spec.kind.isAnimated {
                Toggle("Play", isOn: $spec.isPlaying)
                slider("Motion speed", $spec.motionSpeed, 0...2, "Hz")
                slider("Frozen phase (used for captures)", $spec.frozenPhase, 0...1, "")
            }
            slider("Element opacity", $spec.elementOpacity, 0...1, "")
            slider("Contrast", $spec.contrast, 0...2, "x")
            slider("Saturation", $spec.saturation, 0...2, "x")
            ColorEditor(title: "Base (behind everything)", color: $spec.base)
        } header: {
            Text("Background")
        } footer: {
            Text("Element opacity affects background elements only, never the glass. Wherever nothing is drawn, the recorded base color shows.")
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { importError = "Could not load the item."; return }
                    let ext = spec.kind == .importedVideo ? "mov" : (item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg")
                    spec.importedFile = try BackgroundFiles.store(data: data, ext: ext)
                    importError = nil
                } catch { importError = error.localizedDescription }
            }
        }
    }

    private var quickColors: some View {
        let presets: [(String, RGBAColor)] = [("Black", .black), ("White", .white), ("50% Gray", .neutralGray), ("18% Gray", .gray18),
                                              ("Red", RGBAColor(1, 0, 0)), ("Green", RGBAColor(0, 1, 0)), ("Blue", RGBAColor(0, 0, 1)),
                                              ("Cyan", RGBAColor(0, 1, 1)), ("Magenta", RGBAColor(1, 0, 1)), ("Yellow", RGBAColor(1, 1, 0))]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(presets, id: \.0) { p in
                    Button { spec.primary = p.1 } label: {
                        Circle().fill(p.1.color).frame(width: 26, height: 26).overlay(Circle().stroke(.secondary, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(p.0)
                }
            }
        }
    }

    private func slider(_ title: String, _ v: Binding<Double>, _ r: ClosedRange<Double>, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text(title).font(.subheadline); Spacer(); Text(Format.number(v.wrappedValue, digits: 3) + (unit.isEmpty ? "" : " " + unit)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            Slider(value: v, in: r)
        }
    }
}
