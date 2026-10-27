import SwiftUI

struct OpticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var frameChoice = 1
    @State private var cgImage: CGImage?
    @State private var linear: LinearImage?
    @State private var reference: LinearImage?
    @State private var moduleFilter: String = "All"

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if let pair = model.experiment(model.selectedExperimentID), !pair.1.resultFrames.isEmpty {
                    let session = pair.0, exp = pair.1
                    if hSize == .regular {
                        HStack(alignment: .top, spacing: 0) {
                            imagePane(session, exp).frame(maxWidth: .infinity)
                            Divider()
                            resultsPane(session, exp).frame(width: 420)
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                imagePane(session, exp).frame(height: 520)
                                resultsPane(session, exp)
                            }
                        }
                    }
                } else {
                    EmptyStateView(title: "No experiment selected", symbol: "camera.aperture",
                                   message: "Acquire a reference/glass pair in the Experiment Lab, or choose one from a session.")
                }
            }
            .navigationTitle("Optics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ExperimentPicker(selection: $model.selectedExperimentID, filter: { !$0.resultFrames.isEmpty && !$0.referenceFrames.isEmpty })
                }
            }
        }
        .task(id: "\(model.selectedExperimentID?.uuidString ?? "")-\(frameChoice)") { await loadFrames() }
    }

    private func frameRecord(_ exp: Experiment) -> FrameRecord? {
        frameChoice == 0 ? exp.referenceFrames.last : exp.resultFrames.last
    }

    private func loadFrames() async {
        cgImage = nil; linear = nil; reference = nil
        guard let pair = model.experiment(model.selectedExperimentID), let f = frameRecord(pair.1) else { return }
        let url = model.store.url(for: f, in: pair.0.id)
        let refURL = pair.1.referenceFrames.last.map { model.store.url(for: $0, in: pair.0.id) }
        let loaded = await Task.detached { () -> (CGImage?, LinearImage?, LinearImage?) in
            let img = ImageIOHelper.loadCGImage(url)
            return (img, img.flatMap { LinearImage(cgImage: $0) }, refURL.flatMap { LinearImage.load(url: $0) })
        }.value
        cgImage = loaded.0; linear = loaded.1; reference = loaded.2
    }

    @ViewBuilder
    private func imagePane(_ session: ExperimentSession, _ exp: Experiment) -> some View {
        VStack(spacing: 8) {
            Picker("Frame", selection: $frameChoice) {
                Text("Reference").tag(0); Text("Native Glass").tag(1)
            }
            .pickerStyle(.segmented)
            if let cgImage, let f = frameRecord(exp) {
                MeasurementInspectorView(image: cgImage, linear: linear, comparison: frameChoice == 1 ? reference : nil, pixelsPerPoint: f.pixelsPerPoint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(f.pixelWidth)x\(f.pixelHeight) px · \(Format.number(f.pixelsPerPoint, digits: 3)) px/pt · \(f.captureMethod.rawValue) · \(f.colorSpace)")
                    Text("SHA-256 \(f.sha256.prefix(16))…  settle \(Format.number(f.settleMilliseconds, digits: 3)) ms, residual \(Format.number(f.settleResidual, digits: 2))")
                    ForEach(f.pipelineNotes, id: \.self) { Text($0) }
                }
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .padding()
    }

    private func resultsPane(_ session: ExperimentSession, _ exp: Experiment) -> some View {
        List {
            Section {
                HStack {
                    ValidityLabel(validity: exp.validity)
                    Spacer()
                    if model.engine.isRunning {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { model.engine.cancel() }
                    } else {
                        Button("Analyse", systemImage: "play.circle") {
                            Task { await model.engine.analyze(experimentID: exp.id, sessionID: session.id, store: model.store) }
                        }
                        .accessibilityIdentifier("analyse")
                    }
                }
                ForEach(exp.validity.reasons, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                if let err = model.engine.lastError { Text(err).font(.caption).foregroundStyle(.red) }
                Text(exp.title).font(.caption).foregroundStyle(.secondary)
            }
            if let run = exp.latestAnalysis {
                Section {
                    Picker("Show", selection: $moduleFilter) {
                        Text("All").tag("All")
                        ForEach(["Valid only", "N/A only"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ForEach(run.measurements.filter(filter)) { MeasurementRow(m: $0) }
                } header: {
                    Text("Measurements · \(Format.timestamp.string(from: run.startedAt)) · app \(run.appVersion)")
                } footer: {
                    Text("Tap a row for method, confidence, uncertainty and validity. Values marked Estimated depend on the stated model.")
                }
                if !run.derivedFrames.isEmpty {
                    Section("Heatmaps & derived images") {
                        ForEach(run.derivedFrames) { f in
                            VStack(alignment: .leading, spacing: 4) {
                                StoredFrameImage(url: model.store.derivedURL(session.id, f.fileName)).frame(height: 220)
                                ForEach(f.pipelineNotes, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if !run.log.isEmpty {
                    Section("Log") { ForEach(run.log, id: \.self) { Text($0).font(.caption) } }
                }
                if exp.analyses.count > 1 {
                    Section("History") {
                        ForEach(exp.analyses.reversed()) { a in
                            Text("\(Format.timestamp.string(from: a.startedAt)) · \(a.measurements.count) values · \(a.algorithmVersions["blurFit"] ?? "")").font(.caption)
                        }
                    }
                }
            } else {
                Section { Text("Not analysed yet.").foregroundStyle(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func filter(_ m: Measurement) -> Bool {
        switch moduleFilter {
        case "Valid only": return m.value != nil && m.validity.isUsable
        case "N/A only": return m.value == nil || !m.validity.isUsable
        default: return true
        }
    }
}
