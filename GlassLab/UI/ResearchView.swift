import SwiftUI
import Charts

/// Mathematical & physical models used by the analysers, each linked to its implementation, a preset
/// that produces data for it, and an interactive plot of the model itself (Theoretical provenance).
struct ResearchView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: ResearchModel?

    var body: some View {
        NavigationSplitView {
            List(ResearchCatalog.models, selection: $selected) { m in
                NavigationLink(value: m) { Text(m.title) }
            }
            .navigationTitle("Models")
        } detail: {
            if let m = selected { ModelDetail(model: m) } else {
                EmptyStateView(title: "Choose a model", symbol: "function", message: "Every equation here is used by a measurement or explains one, with its limits.")
            }
        }
    }
}

struct ModelDetail: View {
    @Environment(AppModel.self) private var app
    var model: ResearchModel
    @State private var p1 = 0.6
    @State private var p2 = 0.3

    var body: some View {
        List {
            Section {
                Text(model.equation).font(.body.monospaced()).textSelection(.enabled)
                ForEach(model.symbols, id: \.0) { s in KeyValueRow(key: s.0, value: s.1) }
            }
            Section("How Glass Lab uses it") { Text(model.usage) }
            Section("Limits") { Text(model.limits) }
            Section("Implementation") {
                Text(model.implementation).font(.caption.monospaced())
                if let preset = model.presetName, let cfg = PresetStore.builtIn.first(where: { $0.name == preset }) {
                    Button("Open preset '\(preset)' in the Lab") { app.load(cfg) }
                }
            }
            Section {
                plot.frame(height: 220)
                parameterControls
            } header: { Text("Model plot") } footer: { Text("Theoretical curves for intuition. They are not measurements.") }
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var points: [(Double, Double, String)] {
        let xs = stride(from: 0.0, through: 1.0, by: 0.01).map { $0 }
        switch model.title {
        case let t where t.hasPrefix("Linear compositing"):
            return xs.map { ($0, p1 * p2 + (1 - p1) * $0, "C(B)") } + xs.map { ($0, $0, "B") }
        case let t where t.hasPrefix("Spatial blur"):
            let s = max(0.01, p1 * 0.2)
            return xs.map { x in let u = (x - 0.5); return (x, exp(-u * u / (2 * s * s)), "Gaussian kernel") }
        case let t where t.hasPrefix("Edge spread"):
            let s = max(0.005, p1 * 0.1)
            return xs.map { x in (x, 0.5 * (1 + erf((x - 0.5) / (s * 2.0.squareRoot()))), "ESF") } + xs.map { x in let u = x - 0.5; return (x, exp(-u * u / (2 * s * s)), "LSF (scaled)") }
        case let t where t.hasPrefix("Snell"):
            let n2 = 1 + p1
            return xs.map { x in let th = x * .pi / 2; let s = sin(th) / n2; return (th * 180 / .pi, asin(min(1, s)) * 180 / .pi, "refracted angle (deg)") }
        case let t where t.hasPrefix("Schlick"):
            let f0 = p2 * 0.2
            return xs.map { x in let th = x * .pi / 2; return (th * 180 / .pi, f0 + (1 - f0) * pow(1 - cos(th), 5), "F(theta)") }
        case let t where t.hasPrefix("Second-order"):
            let w = 5 + p1 * 40, z = max(0.05, p2)
            return xs.map { x in (x, TimeSeries.springStep(t: x, omega: w, zeta: z), "x(t)") }
        case let t where t.hasPrefix("CIE"):
            return xs.map { x in (x, ColorScience.xyzToLab((ColorScience.d65.x * x, x, ColorScience.d65.z * x)).L, "L*(Y)") }
        default:
            return xs.map { x in (x, 10 * log10(1 / max(1e-6, x * x * p1)), "PSNR vs RMSE") }
        }
    }

    private var plot: some View {
        Chart(Array(points.enumerated()), id: \.offset) { item in
            LineMark(x: .value("x", item.element.0), y: .value("y", item.element.1), series: .value("s", item.element.2))
                .foregroundStyle(by: .value("Curve", item.element.2))
        }
    }

    private var parameterControls: some View {
        VStack(alignment: .leading) {
            HStack { Text("Parameter 1").font(.caption); Slider(value: $p1, in: 0...1); Text(Format.number(p1, digits: 2)).font(.caption.monospacedDigit()) }
            HStack { Text("Parameter 2").font(.caption); Slider(value: $p2, in: 0...1); Text(Format.number(p2, digits: 2)).font(.caption.monospacedDigit()) }
        }
    }
}
