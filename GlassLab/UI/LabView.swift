import SwiftUI

struct LabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showInspector = true
    @State private var showPresets = false
    @State private var validationResult: CaptureValidationResult?

    var body: some View {
        @Bindable var stage = model.stage
        NavigationStack {
            VStack(spacing: 0) {
                InstructionStrip(text: model.capture.operatorInstruction, status: model.capture.status.isEmpty ? (model.engine.isRunning ? model.engine.message : "") : model.capture.status)
                ExperimentCanvas(stage: model.stage, probe: model.probe, reports: !model.stage.focusMode)
                    .clipShape(RoundedRectangle(cornerRadius: hSize == .regular ? 16 : 0))
                    .padding(hSize == .regular ? 12 : 0)
                resultBar
            }
            .navigationTitle(model.stage.config.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .inspector(isPresented: $showInspector) {
                LabInspector()
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
            }
            .onChange(of: model.stage.config.appearance) { _, _ in model.syncAppearance() }
            .onAppear { model.syncAppearance() }
            .onDisappear { if let w = model.probe.window { w.overrideUserInterfaceStyle = .unspecified } }
        }
        .fullScreenCover(isPresented: $stage.focusMode) { FocusStageView() }
        .sheet(isPresented: $showPresets) { PresetBrowser() }
        .alert("Capture validation", isPresented: Binding(get: { validationResult != nil }, set: { if !$0 { validationResult = nil } })) {
            Button("OK") {}
        } message: {
            if let v = validationResult { Text((v.passed ? "PASSED. " : "FAILED. ") + v.notes.joined(separator: " ")) }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button("Presets", systemImage: "square.stack.3d.up") { showPresets = true }
            Menu {
                ForEach(CaptureMethod.allCases.filter { $0 != .imported }) { m in
                    Button {
                        Task { validationResult = await model.capture.validate(m) }
                    } label: {
                        let v = model.capture.validation(for: m)
                        Label("\(m.rawValue): \(v == nil ? "not validated" : (v!.passed ? "passed" : "failed"))",
                              systemImage: v == nil ? "questionmark.circle" : (v!.passed ? "checkmark.seal" : "xmark.octagon"))
                    }
                }
            } label: { Label("Validate Capture", systemImage: "checkmark.shield") }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Focus", systemImage: "viewfinder") { model.stage.focusMode = true }
                .accessibilityIdentifier("focusMode")
            Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await model.acquireCurrent() }
            } label: {
                Label("Acquire", systemImage: "camera.aperture")
            }
            .buttonStyle(.glassProminent)
            .disabled(model.capture.isBusy || model.engine.isRunning)
            .accessibilityIdentifier("acquire")
        }
    }

    @ViewBuilder
    private var resultBar: some View {
        if let err = model.capture.lastError ?? model.engine.lastError {
            Label(err, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange).padding(8)
        } else if let pair = model.experiment(model.selectedExperimentID) {
            let e = pair.1
            HStack(spacing: 10) {
                ValidityLabel(validity: e.validity)
                Text(e.title).font(.footnote).lineLimit(1)
                Spacer()
                Button("Optics", systemImage: "camera.aperture") { model.section = .optics }.font(.footnote)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }
}

/// Focus mode: the canvas fills the screen; only an instruction strip sits above it (outside the capture crop).
struct FocusStageView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                InstructionStrip(text: model.capture.operatorInstruction, status: model.capture.status)
                Button {
                    Task { await model.acquireCurrent() }
                } label: { Image(systemName: "camera.aperture").font(.title3) }
                .disabled(model.capture.isBusy)
                .accessibilityIdentifier("focusAcquire")
                Button { model.stage.focusMode = false } label: { Image(systemName: "xmark").font(.title3) }
                    .padding(.trailing, 12)
                    .accessibilityIdentifier("exitFocus")
            }
            .background(Color(uiColor: .systemBackground))
            ExperimentCanvas(stage: model.stage, probe: model.probe, reports: true)
                .ignoresSafeArea(edges: .bottom)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { model.syncAppearance() }
    }
}

struct PresetBrowser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Built-in") {
                    ForEach(PresetStore.builtIn) { p in
                        Button { model.load(p); dismiss() } label: {
                            VStack(alignment: .leading) { Text(p.name); Text(p.summary).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section("Saved") {
                    if model.presets.user.isEmpty { Text("Save the current configuration from the inspector.").foregroundStyle(.secondary) }
                    ForEach(model.presets.user) { p in
                        Button { model.load(p); dismiss() } label: {
                            VStack(alignment: .leading) { Text(p.name); Text(p.summary).font(.caption).foregroundStyle(.secondary) }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { model.presets.delete(p.id) }
                            Button("Duplicate") { model.presets.duplicate(p) }
                        }
                    }
                }
            }
            .navigationTitle("Presets")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
