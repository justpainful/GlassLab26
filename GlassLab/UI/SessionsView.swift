import SwiftUI
import UniformTypeIdentifiers

struct SessionsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var importing = false
    @State private var importReport: ImportReport?
    @State private var newTitle = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    HStack {
                        TextField("New session title", text: $newTitle)
                        Button("Create", systemImage: "plus.circle.fill") {
                            let t = newTitle.isEmpty ? "Session " + Format.timestamp.string(from: Date()) : newTitle
                            selection = model.store.createSession(title: t, environment: model.environment.current).id
                            newTitle = ""
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("createSession")
                    }
                }
                Section("Sessions") {
                    ForEach(model.store.sessions) { s in
                        NavigationLink(value: s.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(s.title)
                                    if s.id == model.store.activeSessionID { Image(systemName: "record.circle").foregroundStyle(.tint).accessibilityLabel("Active") }
                                }
                                Text("\(s.experiments.count) experiments · \(Format.timestamp.string(from: s.modifiedAt))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { model.store.deleteSession(s.id) }
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import", systemImage: "square.and.arrow.down") { importing = true }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { result in
                guard case .success(let url) = result else { return }
                Task {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    importReport = await ExportManager.importBundle(url, into: model.store)
                }
            }
            .alert("Import", isPresented: Binding(get: { importReport != nil }, set: { if !$0 { importReport = nil } })) {
                Button("OK") {}
            } message: {
                if let r = importReport {
                    Text(r.imported ? "Imported '\(r.sessionTitle)': \(r.verifiedFiles) files verified." : "Not imported. " + r.problems.joined(separator: "; "))
                }
            }
        } detail: {
            if let id = selection, let s = model.store.session(id) {
                SessionDetailView(session: s)
            } else {
                EmptyStateView(title: "No session selected", symbol: "tray.full", message: "Sessions store every experiment, frame, recording and analysis on this device.")
            }
        }
    }
}

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    var session: ExperimentSession
    @State private var shareItems: [Any]?
    @State private var exporting = false
    @State private var exportError: String?
    @State private var includeRecordings = true
    @State private var notes = ""

    var body: some View {
        List {
            Section {
                KeyValueRow(key: "Created", value: Format.timestamp.string(from: session.createdAt))
                KeyValueRow(key: "Device", value: session.environment.deviceLine, provenance: .apiExposed)
                KeyValueRow(key: "Validity", value: session.validity.status.rawValue)
                KeyValueRow(key: "On disk", value: Format.bytes(model.store.sizeOnDisk(session.id)))
                Button(session.id == model.store.activeSessionID ? "Active session" : "Make active", systemImage: "record.circle") {
                    model.store.activeSessionID = session.id
                }
                .disabled(session.id == model.store.activeSessionID)
                TextField("Session notes and conclusions", text: $notes, axis: .vertical)
                    .lineLimit(2...8)
                    .onSubmit { save() }
                Button("Save notes") { save() }
            }
            Section {
                Toggle("Include recordings", isOn: $includeRecordings)
                Button("Export session bundle (ZIP + manifest + PDF)", systemImage: "shippingbox") { export(.bundle) }
                Button("Export measurements CSV", systemImage: "tablecells") { export(.csv) }
                Button("Export session JSON", systemImage: "curlybraces") { export(.json) }
                Button("Export PDF report", systemImage: "doc.richtext") { export(.pdf) }
                if exporting { ProgressView("Exporting") }
                if let exportError { Text(exportError).foregroundStyle(.red).font(.caption) }
            } header: { Text("Export") } footer: {
                Text("Files are created on this device and leave it only through the share sheet you open. The bundle's manifest lists every file with its size and SHA-256.")
            }
            Section("Experiments") {
                ForEach(session.experiments.reversed()) { e in
                    NavigationLink {
                        ExperimentDetailView(sessionID: session.id, experimentID: e.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).lineLimit(2)
                            HStack {
                                ValidityLabel(validity: e.validity)
                                Text(Format.timestamp.string(from: e.createdAt)).font(.caption2).foregroundStyle(.secondary)
                                if !e.recordings.isEmpty { Image(systemName: "video").font(.caption2) }
                            }
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { model.store.deleteExperiment(e.id, in: session.id) } }
                }
            }
            if !session.crossAnalyses.isEmpty {
                Section("Session analyses") {
                    ForEach(session.crossAnalyses) { run in
                        DisclosureGroup(run.log.first ?? "Analysis") { ForEach(run.measurements) { MeasurementRow(m: $0) } }
                    }
                }
            }
        }
        .navigationTitle(session.title)
        .onAppear { notes = session.notes }
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let items = shareItems { ShareSheet(items: items) }
        }
    }

    enum ExportKind { case bundle, csv, json, pdf }

    private func save() { model.store.update(session.id) { $0.notes = notes } }

    private func export(_ kind: ExportKind) {
        exporting = true; exportError = nil
        let s = session
        let dir = model.store.directory(for: s.id)
        let rec = includeRecordings
        Task {
            do {
                let url: URL = try await Task.detached { () throws -> URL in
                    let base = ExportManager.exportDirectory.appendingPathComponent(ExportManager.safeName(s.title) + "-" + Format.fileStamp.string(from: Date()))
                    switch kind {
                    case .bundle: return try ExportManager.makeBundle(session: s, sessionDirectory: dir, includeReport: true, includeRecordings: rec)
                    case .csv:
                        let u = base.appendingPathExtension("csv")
                        try ExportManager.csv(s).write(to: u, atomically: true, encoding: .utf8)
                        return u
                    case .json:
                        let u = base.appendingPathExtension("json")
                        try DataStore.encoder.encode(s).write(to: u)
                        return u
                    case .pdf:
                        let u = base.appendingPathExtension("pdf")
                        try ReportGenerator.render(session: s, sessionDirectory: dir, to: u)
                        return u
                    }
                }.value
                shareItems = [url]
            } catch {
                exportError = error.localizedDescription
            }
            exporting = false
        }
    }
}

struct ExperimentDetailView: View {
    @Environment(AppModel.self) private var model
    var sessionID: UUID
    var experimentID: UUID
    @State private var share: [Any]?

    var body: some View {
        if let s = model.store.session(sessionID), let e = s.experiments.first(where: { $0.id == experimentID }) {
            List {
                Section("Configuration") {
                    KeyValueRow(key: "API", value: NativeGlass.apiDescription(e.configuration))
                    KeyValueRow(key: "Background", value: e.configuration.background.summary)
                    KeyValueRow(key: "Capture", value: e.configuration.captureMethod.rawValue, provenance: .recorded)
                    KeyValueRow(key: "Canvas", value: "\(Format.number(e.canvasSizePoints.width, digits: 4))x\(Format.number(e.canvasSizePoints.height, digits: 4)) pt", provenance: .measured)
                    KeyValueRow(key: "Subject frame", value: "\(Format.number(e.subjectFramePoints.width, digits: 4))x\(Format.number(e.subjectFramePoints.height, digits: 4)) pt at (\(Format.number(e.subjectFramePoints.x, digits: 4)), \(Format.number(e.subjectFramePoints.y, digits: 4)))", provenance: .measured)
                    KeyValueRow(key: "Repetition", value: "\(e.repetitionIndex + 1)")
                    ForEach(e.validity.reasons, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    if !e.notes.isEmpty { Text(e.notes).font(.caption) }
                }
                Section("Environment") {
                    KeyValueRow(key: "Device", value: e.environment.deviceLine, provenance: .apiExposed)
                    KeyValueRow(key: "Interface", value: e.environment.interfaceStyle, provenance: .apiExposed)
                    KeyValueRow(key: "Reduce Transparency", value: "\(e.environment.reduceTransparency)", provenance: .apiExposed)
                    KeyValueRow(key: "Increase Contrast", value: "\(e.environment.increaseContrast)", provenance: .apiExposed)
                    KeyValueRow(key: "Thermal", value: e.environment.thermalState, provenance: .apiExposed)
                    ForEach(e.environment.userEntered.sorted(by: { $0.key < $1.key }), id: \.key) { KeyValueRow(key: $0.key, value: $0.value, provenance: .userEntered) }
                }
                Section("Frames") {
                    ForEach(e.referenceFrames + e.resultFrames) { f in
                        VStack(alignment: .leading) {
                            StoredFrameImage(url: model.store.url(for: f, in: sessionID)).frame(height: 200)
                            Text("\(f.role.rawValue) · \(f.pixelWidth)x\(f.pixelHeight) · \(f.colorSpace)").font(.caption2)
                            Text("sha256 \(f.sha256)").font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            HStack {
                                Button("PNG") { share = [model.store.url(for: f, in: sessionID)] }
                                Button("HEIC") { if let u = try? ExportManager.exportFrame(model.store.url(for: f, in: sessionID), heic: true) { share = [u] } }
                            }
                            .buttonStyle(.bordered).font(.caption)
                        }
                    }
                }
                Section {
                    Button("Re-analyse with current algorithms", systemImage: "arrow.clockwise") {
                        model.selectedExperimentID = e.id
                        Task { await model.engine.analyze(experimentID: e.id, sessionID: sessionID, store: model.store) }
                    }
                    .disabled(e.resultFrames.isEmpty || model.engine.isRunning)
                    Button("Open in Optics") { model.selectedExperimentID = e.id; model.section = .optics }
                    Button("Load configuration in Lab") { model.load(e.configuration) }
                } footer: { Text("Original frames are never modified; each analysis is appended with its algorithm versions.") }
                ForEach(e.analyses.reversed()) { run in
                    Section("Analysis \(Format.timestamp.string(from: run.startedAt))") {
                        ValidityLabel(validity: run.validity)
                        ForEach(run.measurements) { MeasurementRow(m: $0) }
                    }
                }
            }
            .navigationTitle("Experiment")
            .sheet(isPresented: Binding(get: { share != nil }, set: { if !$0 { share = nil } })) { if let share { ShareSheet(items: share) } }
        } else {
            Text("Experiment not found")
        }
    }
}
