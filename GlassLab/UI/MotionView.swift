import SwiftUI
import Charts
import AVKit
import QuartzCore

struct MotionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var recording = false
    @State private var proRes = false
    @State private var maxDuration: Double = 5
    @State private var error: String?
    @State private var recorder = InteractionRecorder()
    @State private var stopRequested = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if hSize == .regular {
                    HStack(spacing: 0) {
                        recordPane.frame(width: 420)
                        Divider()
                        MotionResultsView(experimentID: model.selectedExperimentID)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            recordPane.frame(height: 560)
                            MotionResultsView(experimentID: model.selectedExperimentID).frame(minHeight: 700)
                        }
                    }
                }
            }
            .navigationTitle("Motion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ExperimentPicker(selection: $model.selectedExperimentID, filter: { !$0.recordings.isEmpty }, title: "Recording")
                }
            }
        }
    }

    private var recordPane: some View {
        VStack(spacing: 8) {
            InstructionStrip(text: recording ? (model.stage.config.interaction.isProgrammatic ? "Recording: running \(model.stage.config.interaction.rawValue)" : "Recording: perform \(model.stage.config.interaction.rawValue) on the subject") : nil,
                             status: "")
            ExperimentCanvas(stage: model.stage, probe: model.probe, reports: !model.stage.focusMode)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Form {
                Picker("Interaction", selection: Binding(get: { model.stage.config.interaction }, set: { model.stage.config.interaction = $0 })) {
                    ForEach(InteractionKind.allCases.filter { $0 != .none }) { Text($0.rawValue).tag($0) }
                }
                Toggle("ProRes 4444 (larger, higher quality; still lossy)", isOn: $proRes)
                Stepper("Max duration \(Int(maxDuration)) s", value: $maxDuration, in: 2...30)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Button(recording ? "Stop" : "Record interaction", systemImage: recording ? "stop.circle" : "record.circle") {
                    if recording { stopRequested = true } else { Task { await record() } }
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("recordMotion")
                Text("ReplayKit asks for permission the first time. Video is HEVC or ProRes (both lossy); exact still frames come from the Optics protocol. Timing resolution equals the capture frame interval.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .scrollDisabled(true)
        }
        .padding(8)
    }

    private func record() async {
        error = nil
        stopRequested = false
        let cap = model.capture
        guard let window = model.probe.window else { error = "Canvas not on screen."; return }
        do {
            try await cap.replay.start()
            // Wait for one frame to learn the buffer size.
            let first = try await cap.replay.frame(after: 0, timeout: 2)
            let sid = model.activeSessionID
            let name = "rec-" + Format.fileStamp.string(from: Date()) + "-" + String(UUID().uuidString.prefix(6)) + ".mov"
            let url = model.store.recordingURL(sid, name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try cap.replay.startRecording(to: url, width: first.width, height: first.height, proRes: proRes)
            let canvas = model.probe.frameInWindow
            recorder.begin(in: window, canvasOriginInWindow: canvas.origin)
            recording = true
            let started = CACurrentMediaTime()
            recorder.mark("Recording start", kind: .marker)
            let spacing = model.stage.config.geometry.elementSpacing
            if model.stage.config.interaction.isProgrammatic {
                try? await Task.sleep(for: .milliseconds(400))
                await InteractionDriver.run(model.stage.config.interaction, stage: model.stage) { label, kind in recorder.mark(label, kind: kind) }
                try? await Task.sleep(for: .milliseconds(500))
            } else {
                while !stopRequested && CACurrentMediaTime() - started < maxDuration { try? await Task.sleep(for: .milliseconds(50)) }
            }
            recorder.mark("Recording stop", kind: .marker)
            recorder.end()
            let result = await cap.replay.stopRecording()
            InteractionDriver.reset(model.stage, spacing: spacing)
            recording = false
            if let e = result.error { throw e }
            let sx = Double(first.width) / window.bounds.width
            let crop = PixelRegion(CGRect(x: canvas.minX * sx, y: canvas.minY * sx, width: canvas.width * sx, height: canvas.height * sx).integral)
            let times = result.times
            var rec = RecordingRecord(fileName: name, codec: proRes ? "ProRes 4444" : "HEVC", isLossless: false, pixelWidth: first.width, pixelHeight: first.height,
                                      pixelsPerPoint: sx, nominalFrameRate: Double(window.windowScene?.screen.maximumFramesPerSecond ?? 60),
                                      frameCount: times.count, startMediaTime: times.first ?? started, duration: (times.last ?? started) - (times.first ?? started),
                                      frameTimes: times, crop: crop, colorSpace: "Rec.709 YCbCr (ReplayKit) encoded by AVAssetWriter",
                                      pipelineNotes: ["ReplayKit startCapture -> AVAssetWriter (\(proRes ? "ProRes 4444" : "HEVC, quality 1.0")). Lossy.",
                                                      "Frames are delivered only when the screen changes; frame times are presentation timestamps on the host clock."],
                                      sha256: nil)
            rec.sha256 = FrameWriter.sha256(of: url)
            var exp = Experiment(configuration: model.stage.config, environment: model.environment.current,
                                 canvasSizePoints: CGSizeCodable(model.probe.canvasSize), subjectFramePoints: CGRectCodable(model.probe.subjectFrame))
            exp.elementFramesPoints = model.probe.orderedElementFrames.map(CGRectCodable.init)
            exp.recordings = [rec]
            exp.events = recorder.events
            exp.validity = Validity(status: .incomplete, reasons: ["Not analysed"])
            model.store.upsert(experiment: exp, in: sid)
            model.selectedExperimentID = exp.id
            _ = await model.engine.analyzeMotion(experimentID: exp.id, sessionID: sid, store: model.store)
        } catch {
            recording = false
            recorder.end()
            _ = await cap.replay.stopRecording()
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct MotionResultsView: View {
    @Environment(AppModel.self) private var model
    var experimentID: UUID?
    @State private var frameIndex: Double = 0
    @State private var frame: CGImage?
    @State private var player: AVPlayer?
    @State private var rate: Float = 0.25

    var body: some View {
        if let pair = model.experiment(experimentID), let rec = pair.1.recordings.last {
            let exp = pair.1
            let url = model.store.recordingURL(pair.0.id, rec.fileName)
            List {
                Section("Recording") {
                    KeyValueRow(key: "Frames", value: "\(rec.frameCount) in \(Format.number(rec.duration, digits: 4)) s", provenance: .measured)
                    KeyValueRow(key: "Codec", value: rec.codec + (rec.isLossless ? " (lossless)" : " (lossy)"), provenance: .recorded)
                    KeyValueRow(key: "Size", value: "\(rec.pixelWidth)x\(rec.pixelHeight) px · \(Format.number(rec.pixelsPerPoint, digits: 3)) px/pt", provenance: .recorded)
                    ForEach(rec.pipelineNotes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
                Section("Frame viewer") {
                    if let frame { Image(decorative: frame, scale: 1).resizable().scaledToFit().frame(maxHeight: 300) }
                    if rec.frameTimes.count > 1 {
                        Slider(value: $frameIndex, in: 0...Double(rec.frameTimes.count - 1), step: 1)
                        let i = min(rec.frameTimes.count - 1, Int(frameIndex))
                        let t = rec.frameTimes[i] - rec.frameTimes[0]
                        HStack {
                            Text("Frame \(i + 1)/\(rec.frameTimes.count)")
                            Spacer()
                            Text("t = \(Format.milliseconds(t, digits: 5))")
                            if i > 0 { Text("Δ \(Format.milliseconds(rec.frameTimes[i] - rec.frameTimes[i - 1], digits: 3))").foregroundStyle(.secondary) }
                        }
                        .font(.caption.monospacedDigit())
                    }
                }
                .task(id: "\(rec.fileName)-\(Int(frameIndex))") {
                    guard rec.frameTimes.count > 1 else { return }
                    let i = min(rec.frameTimes.count - 1, Int(frameIndex))
                    frame = await MotionAnalyzer.frameImage(url: url, at: rec.frameTimes[i] - rec.frameTimes[0])
                }
                Section("Slow-motion playback") {
                    if let player { VideoPlayer(player: player).frame(height: 260) }
                    Picker("Rate", selection: $rate) { Text("0.1x").tag(Float(0.1)); Text("0.25x").tag(Float(0.25)); Text("0.5x").tag(Float(0.5)); Text("1x").tag(Float(1)) }
                        .pickerStyle(.segmented)
                    Button("Play", systemImage: "play.fill") {
                        if player == nil { player = AVPlayer(url: url) }
                        player?.seek(to: .zero); player?.playImmediately(atRate: rate)
                    }
                }
                Section("Timeline (events)") {
                    let t0 = rec.frameTimes.first ?? rec.startMediaTime
                    ForEach(exp.events.filter { $0.kind != .touchMove }) { e in
                        HStack {
                            Text(e.kind.rawValue).font(.caption.weight(.medium))
                            if let l = e.label { Text(l).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text(Format.milliseconds(e.time - t0, digits: 5)).font(.caption.monospacedDigit())
                        }
                    }
                    Text("\(exp.events.filter { $0.kind == .touchMove }.count) touch-move samples").font(.caption).foregroundStyle(.secondary)
                }
                if let run = exp.latestAnalysis {
                    if let ts = run.measurements.first(where: { $0.name == "Motion Time Series" })?.series {
                        Section("Graphs") {
                            MotionChart(series: ts.filter { $0.label == "optical change" || $0.label == "frame delta" }, events: exp.events, t0: rec.frameTimes.first ?? 0, title: "Per-frame optical difference")
                            MotionChart(series: ts.filter { $0.label == "width" || $0.label == "height" }, events: exp.events, t0: rec.frameTimes.first ?? 0, title: "Displacement / apparent size (pt)")
                            MotionChart(series: ts.filter { $0.label.hasPrefix("centroid") }, events: exp.events, t0: rec.frameTimes.first ?? 0, title: "Motion trail (centroid, pt)")
                            ForEach(run.measurements.filter { $0.name.hasPrefix("Peak Centroid") }) { m in
                                if let s = m.series { MotionChart(series: s, events: exp.events, t0: rec.frameTimes.first ?? 0, title: m.name, seriesAreRelative: true) }
                            }
                        }
                    }
                    Section("Measurements") {
                        ForEach(run.measurements.filter { $0.name != "Motion Time Series" }) { MeasurementRow(m: $0) }
                        ForEach(run.log, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    }
                } else {
                    Button("Analyse motion") { Task { _ = await model.engine.analyzeMotion(experimentID: exp.id, sessionID: pair.0.id, store: model.store) } }
                }
            }
        } else {
            EmptyStateView(title: "No recording", symbol: "waveform.path.ecg", message: "Record an interaction to see its timeline, frames and graphs.")
        }
    }
}

struct MotionChart: View {
    var series: [Measurement.Series]
    var events: [InteractionEvent]
    var t0: Double
    var title: String
    var seriesAreRelative = true

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption.weight(.semibold))
            SeriesChart(series: series)
                .frame(height: 150)
            let marks = events.filter { $0.kind == .touchDown || $0.kind == .touchUp || $0.kind == .stateChange }
            if !marks.isEmpty {
                Text(marks.map { "\($0.kind.rawValue) @ \(Format.milliseconds($0.time - t0, digits: 4))" }.joined(separator: " · "))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}
