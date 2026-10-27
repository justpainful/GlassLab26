import SwiftUI
import Charts

struct CompareView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case sideBySide = "Side by Side", overlay = "Overlay", difference = "Difference", split = "Split Slider"
        case magnified = "Magnified Region", edges = "Edge Comparison", falseColor = "False Color", heatmap = "dE Heatmap"
        case temporal = "Temporal", table = "Numerical Table"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .sideBySide
    @State private var useReference = false
    @State private var a: LinearImage?
    @State private var b: LinearImage?
    @State private var note = ""
    @State private var opacity = 0.5
    @State private var splitX = 0.5
    @State private var zoomCenter = CGPoint(x: 0.5, y: 0.5)
    @State private var sessionResults: [Measurement] = []
    @State private var busy = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    ExperimentPicker(selection: $model.compareA, filter: { !$0.resultFrames.isEmpty || !$0.recordings.isEmpty }, title: "A")
                    ExperimentPicker(selection: $model.compareB, filter: { !$0.resultFrames.isEmpty || !$0.recordings.isEmpty }, title: "B")
                    Picker("Frames", selection: $useReference) { Text("Native glass").tag(false); Text("Reference").tag(true) }.pickerStyle(.segmented)
                    Picker("Mode", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                    if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                if let ea = model.experiment(model.compareA)?.1, let eb = model.experiment(model.compareB)?.1 {
                    let diff = ComparisonEngine.configurationDiff(ea, eb)
                    Section("What differs") {
                        if diff.isEmpty { Text("Same configuration and environment (a repeatability pair).").foregroundStyle(.secondary) }
                        ForEach(diff, id: \.0) { d in
                            HStack { Text(d.0).foregroundStyle(.secondary); Spacer(); Text(d.1).lineLimit(1); Image(systemName: "arrow.right").font(.caption); Text(d.2).lineLimit(1) }
                                .font(.caption)
                        }
                    }
                    Section(mode.rawValue) { content(ea, eb) }
                }
                Section {
                    Button("Multi-background transfer fit (active session)", systemImage: "function") { Task { await transferFit() } }
                    Button("Repeatability of A's configuration", systemImage: "repeat") { repeatability() }
                    if busy { ProgressView() }
                    ForEach(sessionResults) { MeasurementRow(m: $0) }
                } header: { Text("Session analyses") } footer: {
                    Text("Transfer fit uses solid-background experiments with otherwise identical settings. Repeatability uses experiments acquired from the same configuration name.")
                }
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: "\(model.compareA?.uuidString ?? "")|\(model.compareB?.uuidString ?? "")|\(useReference)") { await load() }
    }

    private func load() async {
        a = nil; b = nil; note = ""
        guard let pa = model.experiment(model.compareA), let pb = model.experiment(model.compareB),
              let fa = (useReference ? pa.1.referenceFrames : pa.1.resultFrames).last,
              let fb = (useReference ? pb.1.referenceFrames : pb.1.resultFrames).last else { return }
        let ua = model.store.url(for: fa, in: pa.0.id), ub = model.store.url(for: fb, in: pb.0.id)
        let r = await Task.detached { () -> (LinearImage, LinearImage, String)? in
            guard let x = LinearImage.load(url: ua), let y = LinearImage.load(url: ub) else { return nil }
            let n = ComparisonEngine.normalize(x, pppA: fa.pixelsPerPoint, y, pppB: fb.pixelsPerPoint)
            return (n.0, n.1, n.3)
        }.value
        if let r { a = r.0; b = r.1; note = r.2 }
    }

    @ViewBuilder
    private func content(_ ea: Experiment, _ eb: Experiment) -> some View {
        switch mode {
        case .table:
            let rows = ComparisonEngine.table(ea, eb)
            if rows.isEmpty { Text("Analyse both experiments first.").foregroundStyle(.secondary) }
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name).font(.subheadline)
                    HStack {
                        Text("A " + (r.a.map(Format.measurement) ?? "–"))
                        Spacer()
                        Text("B " + (r.b.map(Format.measurement) ?? "–"))
                        Spacer()
                        Text("Δ " + Format.number(r.delta, digits: 3) + (r.relative.map { " (\(Format.number($0 * 100, digits: 2))%)" } ?? ""))
                    }
                    .font(.caption.monospacedDigit())
                }
            }
        case .temporal:
            temporal(ea, eb)
        default:
            if let a, let b { imageMode(a, b).frame(height: 420) } else { ProgressView() }
        }
    }

    @ViewBuilder
    private func imageMode(_ a: LinearImage, _ b: LinearImage) -> some View {
        switch mode {
        case .sideBySide:
            HStack(spacing: 4) { img(a.cgImage(), "A"); img(b.cgImage(), "B") }
        case .overlay:
            VStack {
                ZStack {
                    img(a.cgImage(), nil)
                    img(b.cgImage(), nil).opacity(opacity)
                }
                Slider(value: $opacity, in: 0...1) { Text("B opacity") }
            }
        case .difference:
            img(Heatmap.difference(a, b, gain: 4), "|A - B| x4 (linear light)")
        case .split:
            VStack {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        img(b.cgImage(), nil)
                        img(a.cgImage(), nil).mask(alignment: .leading) { Rectangle().frame(width: g.size.width * splitX) }
                        Rectangle().fill(.yellow).frame(width: 2).offset(x: g.size.width * splitX)
                    }
                }
                Slider(value: $splitX, in: 0...1) { Text("Split") }
            }
        case .magnified:
            let w = a.width, h = a.height
            let cx = Int(zoomCenter.x * Double(w)), cy = Int(zoomCenter.y * Double(h))
            let r = PixelRegion(x: cx - 24, y: cy - 24, width: 48, height: 48)
            VStack {
                HStack { img(a.cropped(r).cgImage(), "A"); img(b.cropped(r).cgImage(), "B"); img(Heatmap.difference(a.cropped(r), b.cropped(r), gain: 6), "diff x6") }
                Slider(value: Binding(get: { zoomCenter.x }, set: { zoomCenter.x = $0 }), in: 0...1) { Text("x") }
                Slider(value: Binding(get: { zoomCenter.y }, set: { zoomCenter.y = $0 }), in: 0...1) { Text("y") }
            }
        case .edges:
            let ea = a.luminance().gradientMagnitude(), eb = b.luminance().gradientMagnitude()
            HStack(spacing: 4) {
                img(Heatmap.render(ea, colormap: .gray).0, "Edges A")
                img(Heatmap.render(eb, colormap: .gray).0, "Edges B")
            }
        case .falseColor:
            HStack(spacing: 4) {
                img(Heatmap.render(a.luminance(), range: 0...1, colormap: .viridis).0, "Y of A")
                img(Heatmap.render(b.luminance(), range: 0...1, colormap: .viridis).0, "Y of B")
            }
        case .heatmap:
            if let m = ImageMetrics.compare(a, b, mask: nil) {
                let (image, legend) = Heatmap.render(m.deltaEMap, range: 0...max(10, m.deltaEP95), colormap: .viridis, unit: "dE00")
                VStack {
                    img(image, "Per-pixel dE00 · mean \(Format.number(m.deltaEMean, digits: 3)) · SSIM \(Format.number(m.ssim, digits: 3)) · PSNR \(Format.number(m.psnr, digits: 3)) dB")
                    LegendBar(legend: legend)
                }
            }
        default: EmptyView()
        }
    }

    private func img(_ c: CGImage?, _ caption: String?) -> some View {
        VStack(spacing: 2) {
            if let c { Image(decorative: c, scale: 1).interpolation(.none).resizable().scaledToFit() } else { Color.gray.opacity(0.2) }
            if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder
    private func temporal(_ ea: Experiment, _ eb: Experiment) -> some View {
        let sa = ea.latestAnalysis?.measurements.first { $0.name == "Motion Time Series" }?.series?.first { $0.label == "optical change" }
        let sb = eb.latestAnalysis?.measurements.first { $0.name == "Motion Time Series" }?.series?.first { $0.label == "optical change" }
        if let sa, let sb {
            SeriesChart(series: [relabel(sa, "A"), relabel(sb, "B")]).frame(height: 220)
            if let e = temporalError(sa, sb) {
                KeyValueRow(key: "Temporal RMS difference", value: Format.number(e, digits: 3) + " (mean |dY|)", provenance: .derived)
            }
        } else {
            Text("Temporal comparison needs two analysed Motion recordings.").foregroundStyle(.secondary)
        }
    }

    private func relabel(_ s: Measurement.Series, _ label: String) -> Measurement.Series {
        var c = s
        c.label = label
        return c
    }

    /// RMS difference of two time series resampled onto A's time base (linear interpolation).
    private func temporalError(_ a: Measurement.Series, _ b: Measurement.Series) -> Double? {
        guard a.x.count > 1, b.x.count > 1 else { return nil }
        var s = 0.0, n = 0
        for (t, y) in zip(a.x, a.y) {
            guard let j = b.x.firstIndex(where: { $0 >= t }), j > 0 else { continue }
            let f = (t - b.x[j - 1]) / max(1e-9, b.x[j] - b.x[j - 1])
            let yb = b.y[j - 1] + f * (b.y[j] - b.y[j - 1])
            s += (y - yb) * (y - yb); n += 1
        }
        return n > 0 ? (s / Double(n)).squareRoot() : nil
    }

    private func transferFit() async {
        guard let s = model.store.activeSession else { return }
        busy = true
        sessionResults = await ComparisonEngine.transferFit(s.experiments, store: model.store, sessionID: s.id)
        var run = AnalysisRun(startedAt: Date(), finishedAt: Date(), appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                              algorithmVersions: MeasurementEngine.algorithmVersionsStatic, measurements: sessionResults, derivedFrames: [], log: ["Multi-background transfer fit"], validity: .valid)
        if sessionResults.allSatisfy({ $0.value == nil }) { run.validity = .notAvailable("No usable experiment set") }
        model.store.update(s.id) { $0.crossAnalyses.append(run) }
        busy = false
    }

    private func repeatability() {
        guard let pa = model.experiment(model.compareA) else { sessionResults = []; return }
        let group = pa.0.experiments.filter { $0.configuration.name == pa.1.configuration.name && $0.latestAnalysis != nil }
        sessionResults = ComparisonEngine.repeatability(group)
        if sessionResults.isEmpty {
            sessionResults = [.unavailable("Repeatability", unit: "", algorithm: "Summary statistics", version: AlgorithmVersion.imageStatistics,
                                           reason: "Needs at least two analysed experiments with the configuration name '\(pa.1.configuration.name)'.")]
        } else {
            let run = AnalysisRun(startedAt: Date(), finishedAt: Date(), appVersion: "", algorithmVersions: MeasurementEngine.algorithmVersionsStatic,
                                  measurements: sessionResults, derivedFrames: [], log: ["Repeatability of \(pa.1.configuration.name) over \(group.count) experiments"], validity: .valid)
            model.store.update(pa.0.id) { $0.crossAnalyses.append(run) }
        }
    }
}
