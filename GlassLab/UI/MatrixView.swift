import SwiftUI

struct MatrixView: View {
    @Environment(AppModel.self) private var model
    @State private var plan = TestMatrixPlan()
    @State private var running = false
    @State private var cancelRequested = false
    @State private var current: UUID?
    @State private var log: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    TextField("Name", text: $plan.name)
                    Text("Base configuration: \(plan.base.summary)").font(.caption).foregroundStyle(.secondary)
                    Button("Use current Lab configuration as base") { plan.base = model.stage.config }
                }
                Section("Factors") {
                    ForEach(MatrixAxis.allCases) { axis in
                        DisclosureGroup("\(axis.rawValue) (\(plan.axes[axis]?.count ?? 0))") {
                            ForEach(axis.levels, id: \.self) { level in
                                Toggle(level, isOn: Binding(get: { plan.axes[axis]?.contains(level) ?? false }, set: { on in
                                    var l = plan.axes[axis] ?? []
                                    if on { if !l.contains(level) { l.append(level) } } else { l.removeAll { $0 == level } }
                                    plan.axes[axis] = l.isEmpty ? nil : l
                                }))
                            }
                        }
                    }
                }
                Section {
                    Picker("Mode", selection: $plan.mode) { ForEach(MatrixMode.allCases) { Text($0.rawValue).tag($0) } }
                    if plan.mode == .sampled { Stepper("Sample size \(plan.sampleCount)", value: $plan.sampleCount, in: 1...500) }
                    Stepper("Seed \(plan.seed)", value: Binding(get: { Int(plan.seed) }, set: { plan.seed = UInt64(max(0, $0)) }), in: 0...9999)
                    Picker("Ordering", selection: $plan.ordering) { ForEach(MatrixOrdering.allCases) { Text($0.rawValue).tag($0) } }
                    Stepper("Batch size \(plan.batchSize)", value: $plan.batchSize, in: 1...100)
                    Stepper("Repetitions \(plan.repetitions)", value: $plan.repetitions, in: 1...10)
                    Toggle("Analyse after each capture", isOn: $plan.analyzeAfterCapture)
                    Button("Generate cases", systemImage: "wand.and.stars") { plan.generate(); model.matrices.save(plan) }
                } header: { Text("Generation") } footer: {
                    Text("Full matrix: \(plan.fullCount) combinations. Pairwise covers every pair of levels with fewer cases. Each case captures a reference and a native frame; a batch stops for review before the next one.")
                }
                if !plan.cases.isEmpty {
                    let included = plan.cases.filter(\.included)
                    Section {
                        KeyValueRow(key: "Cases", value: "\(included.count) of \(plan.cases.count), \(plan.repetitions) repetition(s) each")
                        KeyValueRow(key: "Estimated storage", value: "~" + Format.bytes(plan.estimatedBytes(canvasPixels: Int(model.probe.canvasSize.width * model.probe.canvasSize.height * 9))) + " (estimate)")
                        KeyValueRow(key: "Done / failed / incomplete", value: "\(plan.cases.filter { $0.status == .done }.count) / \(plan.cases.filter { $0.status == .failed }.count) / \(plan.cases.filter { $0.status == .incomplete }.count)")
                        if running {
                            ProgressView(value: Double(plan.cases.filter { $0.status == .done || $0.status == .failed }.count), total: Double(max(1, included.count)))
                            Button("Cancel after current case", role: .cancel) { cancelRequested = true }
                        } else {
                            Button("Run next batch", systemImage: "play.fill") { Task { await run(retryFailed: false) } }
                                .buttonStyle(.glassProminent)
                            Button("Retry failed / incomplete", systemImage: "arrow.counterclockwise") { Task { await run(retryFailed: true) } }
                        }
                        ForEach(log.suffix(6), id: \.self) { Text($0).font(.caption) }
                    } header: { Text("Run") }
                    Section("Cases") {
                        ForEach($plan.cases) { $c in
                            HStack {
                                if plan.mode == .selected { Toggle("", isOn: $c.included).labelsHidden() }
                                VStack(alignment: .leading) {
                                    Text(c.label).font(.caption)
                                    if let e = c.error { Text(e).font(.caption2).foregroundStyle(.red) }
                                }
                                Spacer()
                                Text(c.status.rawValue).font(.caption2).foregroundStyle(c.status == .done ? .green : (c.status == .failed ? .red : .secondary))
                                if current == c.id { ProgressView().controlSize(.mini) }
                            }
                        }
                    }
                }
                if !model.matrices.plans.isEmpty {
                    Section("Saved plans") {
                        ForEach(model.matrices.plans) { p in
                            Button { plan = p } label: {
                                VStack(alignment: .leading) {
                                    Text(p.name)
                                    Text("\(p.cases.filter { $0.status == .done }.count)/\(p.cases.count) done" + (p.cases.contains { $0.status == .incomplete } ? " · has incomplete cases" : "")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions { Button("Delete", role: .destructive) { model.matrices.delete(p.id) } }
                        }
                    }
                }
            }
            .navigationTitle("Test Matrix")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $running) {
                VStack(spacing: 0) {
                    InstructionStrip(text: model.capture.operatorInstruction, status: model.capture.status.isEmpty ? "Matrix running" : model.capture.status)
                    ExperimentCanvas(stage: model.stage, probe: model.probe, reports: true).ignoresSafeArea(edges: .bottom)
                }
                .statusBarHidden(true)
            }
        }
    }

    /// Runs one batch. Uses only what the app controls: configuration and the window's appearance override.
    private func run(retryFailed: Bool) async {
        guard ResourceGuard.thermalAllowsHeavyWork else { log.append("Paused: device thermal state is elevated."); return }
        let sid = plan.sessionID ?? model.store.createSession(title: plan.name, environment: model.environment.current).id
        plan.sessionID = sid
        let todo = plan.cases.indices.filter { i in
            plan.cases[i].included && (retryFailed ? (plan.cases[i].status == .failed || plan.cases[i].status == .incomplete) : plan.cases[i].status == .pending)
        }.prefix(plan.batchSize)
        guard !todo.isEmpty else { log.append("Nothing to run."); return }
        let saved = model.stage.config
        cancelRequested = false
        running = true
        try? await Task.sleep(for: .milliseconds(600))   // let the full-screen canvas lay out
        for i in todo {
            if cancelRequested { break }
            if !ResourceGuard.thermalAllowsHeavyWork { log.append("Stopped: thermal pressure."); break }
            current = plan.cases[i].id
            plan.cases[i].status = .running
            plan.cases[i].attempts += 1
            model.matrices.save(plan)
            let cfg = plan.configuration(for: plan.cases[i])
            model.stage.config = cfg
            model.stage.generation += 1
            model.syncAppearance()
            try? await Task.sleep(for: .milliseconds(400))
            model.environment.refresh()
            var ok = true
            for r in 0..<plan.repetitions {
                do {
                    let exp = try await model.capture.acquire(store: model.store, environment: model.environment.current, sessionID: sid, repetition: r, matrixCase: plan.cases[i].id)
                    plan.cases[i].experimentIDs.append(exp.id)
                    if plan.analyzeAfterCapture { await model.engine.analyze(experimentID: exp.id, sessionID: sid, store: model.store) }
                } catch {
                    ok = false
                    plan.cases[i].error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    break
                }
            }
            plan.cases[i].status = ok ? .done : .failed
            if ok { plan.cases[i].error = nil }
            log.append("\(plan.cases[i].status.rawValue): \(plan.cases[i].label)")
            model.matrices.save(plan)
        }
        current = nil
        model.stage.config = saved
        model.stage.generation += 1
        model.syncAppearance()
        running = false
    }
}
