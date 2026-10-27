import SwiftUI
import Charts
import QuartzCore

/// Rendering-cost study. Uses only what an app can observe: display-link callback timing, the
/// process memory footprint and thermal state. GPU time and power are not available and not shown.
struct PerformanceView: View {
    @Environment(AppModel.self) private var model
    @State private var elements = 12
    @State private var containers = 1
    @State private var shape: GlassShapeKind = .capsule
    @State private var spacing: Double = 12
    @State private var animatedBackground = true
    @State private var scrolling = false
    @State private var morph = false
    @State private var withCapture = false
    @State private var duration: Double = 5
    @State private var running = false
    @State private var results: [Measurement] = []
    @State private var stats: DisplayLinkLogger.IntervalStats?
    @State private var phase = false
    private let logger = DisplayLinkLogger()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    stress.frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 12)).listRowInsets(EdgeInsets())
                }
                Section("Load") {
                    Stepper("Glass elements \(elements)", value: $elements, in: 1...80)
                    Stepper("Glass containers \(containers)", value: $containers, in: 0...8)
                    Picker("Shape", selection: $shape) { ForEach([GlassShapeKind.capsule, .circle, .roundedRect, .customStar]) { Text($0.rawValue).tag($0) } }
                    VStack(alignment: .leading) { Text("Spacing \(Int(spacing)) pt").font(.caption); Slider(value: $spacing, in: -20...40) }
                    Toggle("Animated background", isOn: $animatedBackground)
                    Toggle("Scroll content under glass", isOn: $scrolling)
                    Toggle("Merge/split animation loop", isOn: $morph)
                    Toggle("ReplayKit capture running (measures capture overhead separately)", isOn: $withCapture)
                    Stepper("Duration \(Int(duration)) s", value: $duration, in: 2...30)
                    Button(running ? "Measuring..." : "Measure", systemImage: "speedometer") { Task { await measure() } }
                        .disabled(running).buttonStyle(.glassProminent)
                }
                if let s = stats {
                    Section("Frame interval distribution") {
                        Chart(Array(s.histogram.enumerated()), id: \.offset) { item in
                            BarMark(x: .value("ms", Double(item.offset) * s.histogramBinMs + s.histogramBinMs / 2), y: .value("count", item.element))
                        }
                        .chartXAxisLabel("display-link interval (ms)")
                        .frame(height: 160)
                    }
                }
                if !results.isEmpty {
                    Section {
                        ForEach(results) { MeasurementRow(m: $0) }
                        Button("Save to active session", systemImage: "tray.and.arrow.down") { save() }
                    } header: { Text("Results") } footer: {
                        Text("Display-link callbacks are opportunities to draw on the main thread, not frames composited by the render server. For GPU time and power use Instruments (Core Animation, Metal System Trace, Power Profiler) and MetricKit on device.")
                    }
                }
            }
            .navigationTitle("Performance")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var stress: some View {
        ZStack {
            BackgroundView(spec: {
                var b = BackgroundSpec(); b.kind = animatedBackground ? .movingObjects : .checkerboard; b.isPlaying = animatedBackground; b.motionSpeed = 0.4; return b
            }())
            if scrolling {
                ScrollView { DemoScrollContent() }.scrollDisabled(false)
            }
            grid
        }
    }

    @ViewBuilder
    private var grid: some View {
        let perGroup = containers == 0 ? elements : max(1, Int(ceil(Double(elements) / Double(containers))))
        let groups = containers == 0 ? 1 : containers
        VStack(spacing: 10) {
            ForEach(0..<groups, id: \.self) { g in
                let count = min(perGroup, max(0, elements - g * perGroup))
                if count > 0 {
                    let row = HStack(spacing: morph && phase ? -6 : spacing) {
                        ForEach(0..<count, id: \.self) { _ in
                            Color.clear.frame(width: 34, height: 34).glassEffect(.regular.interactive(), in: NativeGlass.shape(shape, cornerRadius: 8))
                        }
                    }
                    if containers == 0 { row } else { GlassEffectContainer(spacing: 20) { row } }
                }
            }
        }
        .padding(8)
    }

    private func measure() async {
        running = true
        results = []
        if withCapture { try? await model.capture.replay.start() }
        let mem0 = MemoryProbe.footprint()
        let thermal0 = ProcessInfo.processInfo.thermalState
        let fps = DeviceEnvironmentMonitor.keyWindow?.windowScene?.screen.maximumFramesPerSecond ?? 60
        logger.start()
        let start = CACurrentMediaTime()
        var memSamples: [Double] = []
        while CACurrentMediaTime() - start < duration {
            if morph { withAnimation(.smooth(duration: 0.6)) { phase.toggle() } }
            try? await Task.sleep(for: .milliseconds(700))
            if let m = MemoryProbe.footprint() { memSamples.append(Double(m)) }
        }
        logger.stop()
        if withCapture { await model.capture.replay.stop() }
        let ts = logger.timestamps
        let v = AlgorithmVersion.performance
        let cfg = "\(elements) elements, \(containers) container(s), \(shape.rawValue), spacing \(Int(spacing)) pt, animated bg \(animatedBackground), scroll \(scrolling), morph \(morph), capture \(withCapture)"
        if let s = DisplayLinkLogger.stats(ts, nominalFPS: fps) {
            stats = s
            results.append(Measurement(name: "Display-link interval (median)", value: s.medianInterval * 1000, unit: "ms", provenance: .measured,
                algorithm: "CADisplayLink.timestamp differences", version: v, confidence: .high("\(s.count) intervals"), sampleCount: s.count, significantDigits: 3, notes: cfg))
            results.append(Measurement(name: "Display-link interval (p95)", value: s.p95Interval * 1000, unit: "ms", provenance: .measured,
                algorithm: "95th percentile of intervals", version: v, confidence: .high("\(s.count) intervals"), sampleCount: s.count, significantDigits: 3))
            results.append(Measurement(name: "Longest interval", value: s.maxInterval * 1000, unit: "ms", provenance: .measured,
                algorithm: "Maximum interval", version: v, confidence: .high("Direct"), sampleCount: s.count, significantDigits: 3))
            results.append(Measurement(name: "Hitches (> 1.5x nominal \(Format.number(s.nominalInterval * 1000, digits: 3)) ms)", value: Double(s.hitchCount), unit: "count", provenance: .measured,
                algorithm: "Intervals longer than 1.5x the display's nominal interval", version: v, confidence: .high("Count"), sampleCount: s.count, significantDigits: 3))
            results.append(Measurement(name: "Hitch time ratio", value: s.hitchTimeRatio * 1000, unit: "ms/s", provenance: .derived,
                algorithm: "Excess time beyond nominal in hitches / duration", version: v, confidence: .medium("Main-thread view of hitches"), sampleCount: s.count, significantDigits: 2))
        } else {
            results.append(.unavailable("Display-link interval", unit: "ms", algorithm: "CADisplayLink", version: v, reason: "Too few callbacks recorded."))
        }
        if let m0 = mem0, let mx = memSamples.max() {
            results.append(Measurement(name: "Memory footprint (peak during run)", value: mx / 1_048_576, unit: "MB", provenance: .apiExposed,
                algorithm: "task_info TASK_VM_INFO phys_footprint", version: v, confidence: .high("Kernel-reported"), sampleCount: memSamples.count, significantDigits: 4,
                notes: "Before run \(Format.bytes(m0)). Includes the whole app process."))
        }
        let thermal1 = ProcessInfo.processInfo.thermalState
        results.append(Measurement(name: "Thermal state (before -> after)", value: Double(thermal1.rawValue), unit: "level 0-3", provenance: .apiExposed,
            algorithm: "ProcessInfo.thermalState", version: v, confidence: .high("System-reported"), sampleCount: 2, significantDigits: 1,
            notes: "\(DeviceEnvironmentMonitor.thermalName(thermal0)) -> \(DeviceEnvironmentMonitor.thermalName(thermal1)). Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled)."))
        results.append(.unavailable("GPU time per frame", unit: "ms", algorithm: "-", version: v, reason: "Not exposed to apps. Use Instruments (Metal System Trace) on a connected device."))
        results.append(.unavailable("Power draw", unit: "W", algorithm: "-", version: v, reason: "Not exposed to apps. Use Instruments Power Profiler; MetricKit reports daily aggregates only."))
        running = false
    }

    private func save() {
        let sid = model.activeSessionID
        let run = AnalysisRun(startedAt: Date(), finishedAt: Date(), appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                              algorithmVersions: MeasurementEngine.algorithmVersionsStatic, measurements: results, derivedFrames: [],
                              log: ["Performance run"], validity: .valid)
        model.store.update(sid) { $0.crossAnalyses.append(run) }
    }
}
