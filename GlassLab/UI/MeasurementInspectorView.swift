import SwiftUI
import Charts

/// Interactive measurement tools on a captured frame. All readouts are computed from the stored pixels
/// decoded to linear Display P3.
struct MeasurementInspectorView: View {
    enum Tool: String, CaseIterable, Identifiable {
        case pixel = "Pixel", region = "Region", ruler = "Ruler", profile = "Profile", magnifier = "Magnifier"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .pixel: return "scope"
            case .region: return "rectangle.dashed"
            case .ruler: return "ruler"
            case .profile: return "chart.xyaxis.line"
            case .magnifier: return "plus.magnifyingglass"
            }
        }
    }

    var image: CGImage
    var linear: LinearImage?
    /// Optional second frame (reference) for the difference magnifier.
    var comparison: LinearImage?
    var pixelsPerPoint: Double
    @State private var tool: Tool = .pixel
    @State private var start: CGPoint?
    @State private var end: CGPoint?

    var body: some View {
        VStack(spacing: 8) {
            Picker("Tool", selection: $tool) {
                ForEach(Tool.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            GeometryReader { g in
                let fit = fittedRect(container: g.size)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1).interpolation(.none).resizable()
                        .frame(width: fit.width, height: fit.height).offset(x: fit.minX, y: fit.minY)
                    overlay(fit)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let p0 = toPixel(v.startLocation, fit), p1 = toPixel(v.location, fit)
                        start = tool == .pixel || tool == .magnifier ? p1 : p0
                        end = p1
                    })
            }
            .frame(minHeight: 260)
            readout
        }
    }

    private func fittedRect(container: CGSize) -> CGRect {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let s = min(container.width / iw, container.height / ih)
        let w = iw * s, h = ih * s
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func toPixel(_ p: CGPoint, _ fit: CGRect) -> CGPoint {
        let x = (p.x - fit.minX) / fit.width * CGFloat(image.width), y = (p.y - fit.minY) / fit.height * CGFloat(image.height)
        return CGPoint(x: min(max(0, x), CGFloat(image.width - 1)), y: min(max(0, y), CGFloat(image.height - 1)))
    }

    private func toView(_ p: CGPoint, _ fit: CGRect) -> CGPoint {
        CGPoint(x: fit.minX + p.x / CGFloat(image.width) * fit.width, y: fit.minY + p.y / CGFloat(image.height) * fit.height)
    }

    @ViewBuilder
    private func overlay(_ fit: CGRect) -> some View {
        if let s = start, let e = end {
            let a = toView(s, fit), b = toView(e, fit)
            switch tool {
            case .pixel, .magnifier:
                Circle().stroke(.yellow, lineWidth: 2).frame(width: 18, height: 18).position(b)
            case .region:
                Path(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))).stroke(.yellow, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            case .ruler, .profile:
                Path { p in p.move(to: a); p.addLine(to: b) }.stroke(.yellow, lineWidth: 2)
            }
        }
    }

    private func encoded(_ v: Float) -> Int { Int((ColorScience.linearToSRGB(Double(max(0, min(1, v)))) * 255).rounded()) }

    @ViewBuilder
    private var readout: some View {
        if let li = linear, let s = start, let e = end {
            switch tool {
            case .pixel:
                let x = Int(e.x), y = Int(e.y)
                let r = li.r[x, y], g = li.g[x, y], b = li.b[x, y]
                let lab = ColorScience.labFromLinearP3(Double(r), Double(g), Double(b))
                VStack(alignment: .leading, spacing: 2) {
                    KeyValueRow(key: "Pixel", value: "x \(x)  y \(y)  (\(Format.number(Double(x) / pixelsPerPoint, digits: 4)), \(Format.number(Double(y) / pixelsPerPoint, digits: 4)) pt)")
                    KeyValueRow(key: "Encoded P3 (8-bit)", value: "\(encoded(r)) \(encoded(g)) \(encoded(b))", provenance: .measured)
                    KeyValueRow(key: "Linear P3", value: "\(Format.number(Double(r), digits: 4)) \(Format.number(Double(g), digits: 4)) \(Format.number(Double(b), digits: 4))", provenance: .derived)
                    KeyValueRow(key: "Relative luminance Y", value: Format.number(Double(ColorScience.luminanceP3(r, g, b)), digits: 4), provenance: .derived)
                    KeyValueRow(key: "CIELAB", value: "L \(Format.number(lab.L, digits: 3))  a \(Format.number(lab.a, digits: 3))  b \(Format.number(lab.b, digits: 3))", provenance: .derived)
                }
            case .region:
                regionReadout(li, s, e)
            case .ruler:
                let dx = Double(e.x - s.x), dy = Double(e.y - s.y), d = (dx * dx + dy * dy).squareRoot()
                VStack(alignment: .leading) {
                    KeyValueRow(key: "Distance", value: "\(Format.number(d, digits: 4)) px  =  \(Format.number(d / pixelsPerPoint, digits: 4)) pt")
                    KeyValueRow(key: "Angle", value: Format.number(atan2(dy, dx) * 180 / .pi, digits: 4) + "°")
                    KeyValueRow(key: "dx / dy", value: "\(Format.number(dx, digits: 4)) / \(Format.number(dy, digits: 4)) px")
                }
            case .profile:
                profileReadout(li, s, e)
            case .magnifier:
                magnifier(li, e)
            }
        } else {
            Text(linear == nil ? "Decoding frame..." : "Touch the image to measure.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func regionReadout(_ li: LinearImage, _ s: CGPoint, _ e: CGPoint) -> some View {
        let r = PixelRegion(x: Int(min(s.x, e.x)), y: Int(min(s.y, e.y)), width: max(1, Int(abs(e.x - s.x))), height: max(1, Int(abs(e.y - s.y))))
        let crop = li.cropped(r)
        let y = crop.luminance()
        let vals = y.data.map(Double.init)
        let st = Statistics.summary(vals)
        let lab = ColorScience.labFromLinearP3(crop.r.mean(), crop.g.mean(), crop.b.mean())
        let hist = Statistics.histogram(vals, bins: 32, range: 0...1)
        return VStack(alignment: .leading, spacing: 2) {
            KeyValueRow(key: "Region", value: "\(r.width)x\(r.height) px at (\(r.x), \(r.y)) = \(Format.number(Double(r.width) / pixelsPerPoint, digits: 4))x\(Format.number(Double(r.height) / pixelsPerPoint, digits: 4)) pt")
            KeyValueRow(key: "Mean Y ± SD", value: "\(Format.number(st.mean, digits: 4)) ± \(Format.number(st.standardDeviation, digits: 2))", provenance: .measured)
            KeyValueRow(key: "Min / Max Y", value: "\(Format.number(st.min, digits: 3)) / \(Format.number(st.max, digits: 3))", provenance: .measured)
            KeyValueRow(key: "Mean CIELAB", value: "L \(Format.number(lab.L, digits: 3)) a \(Format.number(lab.a, digits: 3)) b \(Format.number(lab.b, digits: 3))", provenance: .derived)
            Chart(Array(hist.enumerated()), id: \.offset) { item in
                BarMark(x: .value("Y", (Double(item.offset) + 0.5) / 32), y: .value("Pixels", item.element))
            }
            .frame(height: 90)
        }
    }

    private func profileReadout(_ li: LinearImage, _ s: CGPoint, _ e: CGPoint) -> some View {
        let n = max(2, Int(hypot(e.x - s.x, e.y - s.y)))
        let ylum = li.luminance()
        let pts: [(Double, Double, Double, Double, Double)] = (0..<n).map { i in
            let t = Double(i) / Double(n - 1)
            let x = Double(s.x) + (Double(e.x) - Double(s.x)) * t, y = Double(s.y) + (Double(e.y) - Double(s.y)) * t
            return (Double(i) / pixelsPerPoint, Double(ylum.sample(x, y)), Double(li.r.sample(x, y)), Double(li.g.sample(x, y)), Double(li.b.sample(x, y)))
        }
        return Chart {
            ForEach(Array(pts.enumerated()), id: \.offset) { item in
                LineMark(x: .value("pt", item.element.0), y: .value("value", item.element.1), series: .value("ch", "Y")).foregroundStyle(.primary)
                LineMark(x: .value("pt", item.element.0), y: .value("value", item.element.2), series: .value("ch", "R")).foregroundStyle(.red.opacity(0.7))
                LineMark(x: .value("pt", item.element.0), y: .value("value", item.element.3), series: .value("ch", "G")).foregroundStyle(.green.opacity(0.7))
                LineMark(x: .value("pt", item.element.0), y: .value("value", item.element.4), series: .value("ch", "B")).foregroundStyle(.blue.opacity(0.7))
            }
        }
        .chartXAxisLabel("distance along profile (pt)")
        .chartYAxisLabel("linear value")
        .frame(height: 160)
    }

    private func magnifier(_ li: LinearImage, _ p: CGPoint) -> some View {
        let half = 12
        let r = PixelRegion(x: Int(p.x) - half, y: Int(p.y) - half, width: 2 * half + 1, height: 2 * half + 1)
        let a = li.cropped(r)
        let b = comparison.flatMap { $0.width == li.width && $0.height == li.height ? $0.cropped(r) : nil }
        return HStack(spacing: 8) {
            magnified(a.cgImage(), "This frame")
            if let b {
                magnified(b.cgImage(), "Reference")
                magnified(Heatmap.difference(a, b, gain: 4), "|difference| x4")
            }
        }
    }

    private func magnified(_ img: CGImage?, _ caption: String) -> some View {
        VStack(spacing: 2) {
            if let img {
                Image(decorative: img, scale: 1).interpolation(.none).resizable().frame(width: 110, height: 110)
                    .overlay(Rectangle().stroke(.yellow, lineWidth: 1).frame(width: 110 / 25, height: 110 / 25))
            }
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
