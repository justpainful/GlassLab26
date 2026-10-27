import SwiftUI
import Charts
import UIKit

struct ProvenanceBadge: View {
    var provenance: Provenance
    var body: some View {
        Label(provenance.rawValue, systemImage: provenance.symbol)
            .font(.caption2.weight(.medium))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("Provenance \(provenance.rawValue)")
    }
    private var color: Color {
        switch provenance {
        case .apiExposed: return .blue
        case .measured: return .green
        case .derived: return .teal
        case .estimated: return .orange
        case .theoretical: return .purple
        case .unavailable: return .gray
        case .userEntered: return .pink
        case .recorded: return .indigo
        }
    }
}

struct ValidityLabel: View {
    var validity: Validity
    var body: some View {
        Label(validity.status.rawValue, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
    }
    private var symbol: String {
        switch validity.status {
        case .valid: return "checkmark.seal"
        case .warning: return "exclamationmark.triangle"
        case .invalid: return "xmark.octagon"
        case .notAvailable: return "minus.circle"
        case .incomplete: return "hourglass"
        }
    }
    private var color: Color {
        switch validity.status {
        case .valid: return .green
        case .warning: return .orange
        case .invalid: return .red
        case .notAvailable, .incomplete: return .secondary
        }
    }
}

/// One measurement, compact. Tapping expands method, confidence, uncertainty and validity.
struct MeasurementRow: View {
    var m: Measurement
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(m.name).font(.subheadline)
                Spacer(minLength: 8)
                Text(Format.measurement(m))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(m.value == nil ? .secondary : .primary)
            }
            HStack(spacing: 6) {
                ProvenanceBadge(provenance: m.provenance)
                Text(m.confidence.level.rawValue + " confidence").font(.caption2).foregroundStyle(.secondary)
                if let u = Format.uncertainty(m) { Text(u).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                if m.validity.status != .valid { ValidityLabel(validity: m.validity) }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    detail("Method", m.algorithm + " (" + m.algorithmVersion + ")")
                    detail("Confidence", m.confidence.justification)
                    detail("Samples", "\(m.sampleCount)")
                    if let r = m.region { detail("Region", "x \(r.x) y \(r.y) w \(r.width) h \(r.height) px") }
                    if !m.validity.reasons.isEmpty { detail("Validity", m.validity.reasons.joined(separator: " ")) }
                    if let n = m.notes { detail("Notes", n) }
                    if !m.sources.isEmpty { detail("Sources", m.sources.joined(separator: ", ")) }
                    detail("Time", Format.timestamp.string(from: m.timestamp))
                    if let series = m.series, !series.isEmpty { SeriesChart(series: series).frame(height: 160) }
                }
                .padding(.top, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(k).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            Text(v).font(.caption).textSelection(.enabled)
        }
    }
}

struct SeriesChart: View {
    var series: [Measurement.Series]

    struct Point: Identifiable { let id: Int; let x: Double; let y: Double; let label: String }

    private var points: [Point] {
        var out: [Point] = []
        for s in series {
            for (x, y) in zip(s.x, s.y) where x.isFinite && y.isFinite {
                out.append(Point(id: out.count, x: x, y: y, label: s.label))
            }
        }
        return out
    }

    var body: some View {
        Chart(points) { p in
            LineMark(x: .value(series.first?.xUnit ?? "x", p.x), y: .value(series.first?.yUnit ?? "y", p.y))
                .foregroundStyle(by: .value("Series", p.label))
        }
        .chartXAxisLabel(series.first?.xUnit ?? "")
        .chartYAxisLabel(series.first?.yUnit ?? "")
        .chartLegend(series.count > 1 ? .visible : .hidden)
    }
}

/// A full-resolution image with pinch zoom and pan. Uses nearest-neighbour sampling so pixels stay visible.
struct ZoomableImage: View {
    var image: CGImage
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { g in
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: g.size.width, height: g.size.height)
                .gesture(MagnifyGesture().onChanged { scale = max(1, min(40, base * $0.magnification)) }.onEnded { _ in base = scale })
                .simultaneousGesture(DragGesture().onChanged { offset = CGSize(width: baseOffset.width + $0.translation.width, height: baseOffset.height + $0.translation.height) }
                                        .onEnded { _ in baseOffset = offset })
                .onTapGesture(count: 2) { withAnimation { scale = 1; base = 1; offset = .zero; baseOffset = .zero } }
        }
        .clipped()
    }
}

struct LegendBar: View {
    var legend: Heatmap.Legend
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LinearGradient(colors: (0...10).map { i in
                let c = Heatmap.color(Double(i) / 10, legend.colormap); return Color(red: c.0, green: c.1, blue: c.2)
            }, startPoint: .leading, endPoint: .trailing)
            .frame(height: 8).clipShape(RoundedRectangle(cornerRadius: 2))
            HStack {
                Text(Format.number(legend.minValue, digits: 3)); Spacer()
                Text(legend.unit); Spacer()
                Text(Format.number(legend.maxValue, digits: 3))
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct KeyValueRow: View {
    var key: String
    var value: String
    var provenance: Provenance? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing).textSelection(.enabled)
            if let provenance { Image(systemName: provenance.symbol).foregroundStyle(.secondary).font(.caption).accessibilityLabel(provenance.rawValue) }
        }
        .font(.subheadline)
    }
}

/// Shows an experiment's frames loaded from disk.
struct StoredFrameImage: View {
    var url: URL
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image { ZoomableImage(image: image) } else { ProgressView() }
        }
        .task(id: url) { image = await Task.detached { ImageIOHelper.loadCGImage(url) }.value }
    }
}

struct EmptyStateView: View {
    var title: String
    var symbol: String
    var message: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

/// Session + experiment picker shared by Optics, Motion and Compare.
struct ExperimentPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: UUID?
    var filter: (Experiment) -> Bool = { _ in true }
    var title = "Experiment"

    var body: some View {
        Menu {
            ForEach(model.store.sessions) { s in
                let list = s.experiments.filter(filter)
                if !list.isEmpty {
                    Section(s.title) {
                        ForEach(list.reversed()) { e in
                            Button { selection = e.id } label: {
                                Text(e.title + " · " + Format.timestamp.string(from: e.createdAt))
                            }
                        }
                    }
                }
            }
        } label: {
            Label(model.experiment(selection)?.1.title ?? "Choose \(title)", systemImage: "list.bullet.rectangle")
                .lineLimit(1)
        }
        .accessibilityIdentifier("experimentPicker")
    }
}
