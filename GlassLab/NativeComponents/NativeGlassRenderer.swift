import SwiftUI
import UIKit

/// Builds every experiment subject from Apple's public Liquid Glass APIs. Nothing here draws glass
/// itself: the material is always rendered by the system (SwiftUI `glassEffect`, glass button styles,
/// `UIGlassEffect`, `UIGlassContainerEffect`, or system bars and controls).
enum NativeGlass {
    /// The `Glass` value for a configuration, or nil when no glass modifier should be applied.
    static func glass(_ variant: GlassVariant, tint: RGBAColor?, interactive: Bool) -> Glass? {
        var g: Glass
        switch variant {
        case .regular: g = .regular
        case .clear: g = .clear
        case .identity: g = .identity
        case .none: return nil
        }
        if let tint { g = g.tint(tint.color) }
        if interactive { g = g.interactive() }
        return g
    }

    static func shape(_ kind: GlassShapeKind, cornerRadius: Double) -> AnyShape {
        switch kind {
        case .capsule: return AnyShape(Capsule())
        case .circle: return AnyShape(Circle())
        // Circular corners so the analysis mask (exact SDF) matches the rendered outline.
        case .roundedRect: return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .circular))
        case .rect: return AnyShape(Rectangle())
        case .ellipse: return AnyShape(Ellipse())
        case .customStar: return AnyShape(StarShape())
        }
    }

    /// API call that a configuration maps to, shown in the inspector and stored in reports.
    static func apiDescription(_ c: SceneConfiguration) -> String {
        switch c.subject {
        case .glassSurface, .glassGroup:
            if c.effectiveFramework == .uiKit {
                var s = c.variant == .none ? "UIVisualEffectView(effect: nil)" : "UIVisualEffectView(effect: UIGlassEffect(style: .\(c.variant == .clear ? "clear" : "regular")))"
                if c.variant == .identity { s = "UIVisualEffectView(effect: nil) // identity reference" }
                if c.tint != nil { s += " + tintColor" }
                if c.interactive { s += " + isInteractive" }
                if c.subject == .glassGroup && c.geometry.useContainer { s = "UIGlassContainerEffect(spacing: \(Int(c.geometry.containerSpacing))) > " + s }
                return s
            }
            guard c.variant != .none else { return "(no glass modifier)" }
            var g = "Glass.\(c.variant.rawValue.lowercased())"
            if c.tint != nil { g += ".tint(_:)" }
            if c.interactive { g += ".interactive()" }
            var s = ".glassEffect(\(g), in: \(c.shape.rawValue))"
            if c.subject == .glassGroup {
                if c.geometry.useContainer { s = "GlassEffectContainer(spacing: \(Int(c.geometry.containerSpacing))) { \(s) + glassEffectID }" }
                if c.geometry.unionAll { s += " + glassEffectUnion" }
            }
            return s
        case .glassButton: return ".buttonStyle(.glass)"
        case .glassProminentButton: return ".buttonStyle(.glassProminent)"
        case .glassClearButton: return ".buttonStyle(.glass(.clear)) (iOS 26.1+)"
        case .segmentedControl: return "Picker(...).pickerStyle(.segmented)"
        case .toggle: return "Toggle(isOn:)"
        case .slider: return "Slider(value:)"
        case .uikitNavigationBar: return "UINavigationBar"
        case .uikitToolbar: return "UIToolbar"
        case .uikitTabBar: return "UITabBar"
        case .uikitSegmented: return "UISegmentedControl"
        }
    }
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let pts = StarGeometry.points(radius: r).map { CGPoint(x: $0.x + rect.midX, y: $0.y + rect.midY) }
        var p = Path()
        p.addLines(pts)
        p.closeSubpath()
        return p
    }
}

/// Collected frames of glass elements in the "canvas" coordinate space.
struct ElementFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func reportFrame(_ index: Int) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: ElementFramesKey.self, value: [index: proxy.frame(in: .named("canvas"))])
        })
    }
}

/// Applies the native glass effect, or the reference variant of it.
struct GlassEffectApplier: ViewModifier {
    var config: SceneConfiguration
    /// When false the reference rendering is produced (identity glass or hidden subject).
    var materialOn: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = NativeGlass.shape(config.shape, cornerRadius: config.geometry.cornerRadius * config.geometry.scale)
        if materialOn {
            if let g = NativeGlass.glass(config.variant, tint: config.tint, interactive: config.interactive) {
                content.glassEffect(g, in: shape)
            } else {
                content
            }
        } else {
            switch config.referenceMode {
            case .identityGlass: content.glassEffect(.identity, in: shape)
            case .subjectHidden: content.opacity(0)
            }
        }
    }
}

/// Content placed on a glass element.
struct GlassElementContent: View {
    var config: SceneConfiguration
    var index: Int

    var body: some View {
        switch config.content {
        case .empty: Color.clear
        case .text: Text(config.contentText).font(.headline)
        case .symbol: Image(systemName: config.contentSymbol).font(.title2)
        case .mixed: Label(config.contentText, systemImage: config.contentSymbol).font(.headline)
        }
    }
}

/// The experiment subject, built purely from native components.
struct NativeSubjectView: View {
    var config: SceneConfiguration
    var materialOn: Bool
    /// Number of elements actually shown (animated for merge/split/appear experiments).
    var visibleCount: Int? = nil
    /// Overrides the container spacing during spacing animations.
    var spacingOverride: Double? = nil
    @Namespace private var ns
    @State private var toggleValue = true
    @State private var sliderValue = 0.5
    @State private var segment = 0

    private var size: CGSize {
        CGSize(width: config.geometry.width * config.geometry.scale, height: config.geometry.height * config.geometry.scale)
    }

    var body: some View {
        switch config.subject {
        case .glassSurface:
            surface(0)
        case .glassGroup:
            group
        case .glassButton, .glassProminentButton, .glassClearButton:
            glassButton
                .opacity(!materialOn && config.referenceMode == .subjectHidden ? 0 : 1)
                .reportFrame(0)
        case .segmentedControl:
            Picker("Segment", selection: $segment) {
                Text("One").tag(0); Text("Two").tag(1); Text("Three").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: size.width)
            .opacity(materialOn ? 1 : 0)
            .reportFrame(0)
        case .toggle:
            Toggle("Toggle", isOn: $toggleValue).labelsHidden()
                .opacity(materialOn ? 1 : 0).reportFrame(0)
        case .slider:
            Slider(value: $sliderValue).frame(width: size.width)
                .opacity(materialOn ? 1 : 0).reportFrame(0)
        case .uikitNavigationBar, .uikitToolbar, .uikitTabBar, .uikitSegmented:
            UIKitBarSubject(kind: config.subject, width: size.width)
                .frame(width: size.width, height: UIKitBarSubject.height(for: config.subject))
                .opacity(materialOn ? 1 : 0)
                .reportFrame(0)
        }
    }

    @ViewBuilder
    private func surface(_ i: Int) -> some View {
        if config.effectiveFramework == .uiKit {
            UIKitGlassSurface(config: config, materialOn: materialOn, count: 1, spacing: 0)
                .frame(width: size.width, height: size.height)
                .opacity(!materialOn && config.referenceMode == .subjectHidden ? 0 : 1)
                .rotationEffect(.degrees(config.geometry.rotation))
                .reportFrame(i)
        } else {
            GlassElementContent(config: config, index: i)
                .padding(config.geometry.padding)
                .frame(width: size.width, height: size.height)
                .modifier(GlassEffectApplier(config: config, materialOn: materialOn))
                .rotationEffect(.degrees(config.geometry.rotation))
                .reportFrame(i)
        }
    }

    private var count: Int { max(1, min(12, visibleCount ?? config.geometry.elementCount)) }

    @ViewBuilder
    private var group: some View {
        if config.effectiveFramework == .uiKit {
            let n = count
            let w = config.geometry.vertical ? size.width : size.width * Double(n) + config.geometry.elementSpacing * Double(n - 1)
            let h = config.geometry.vertical ? size.height * Double(n) + config.geometry.elementSpacing * Double(n - 1) : size.height
            UIKitGlassSurface(config: config, materialOn: materialOn, count: n, spacing: config.geometry.elementSpacing)
                .frame(width: w, height: h)
                .opacity(!materialOn && config.referenceMode == .subjectHidden ? 0 : 1)
                .background(GeometryReader { proxy in
                    let f = proxy.frame(in: .named("canvas"))
                    Color.clear.preference(key: ElementFramesKey.self, value: Dictionary(uniqueKeysWithValues: (0..<n).map { i -> (Int, CGRect) in
                        let step = (config.geometry.vertical ? size.height : size.width) + config.geometry.elementSpacing
                        return (i, config.geometry.vertical
                                ? CGRect(x: f.minX, y: f.minY + Double(i) * step, width: size.width, height: size.height)
                                : CGRect(x: f.minX + Double(i) * step, y: f.minY, width: size.width, height: size.height))
                    }))
                })
        } else if config.geometry.useContainer {
            GlassEffectContainer(spacing: spacingOverride ?? config.geometry.containerSpacing) { stack }
        } else {
            stack
        }
    }

    @ViewBuilder
    private var stack: some View {
        let layout = config.geometry.vertical
            ? AnyLayout(VStackLayout(spacing: config.geometry.elementSpacing))
            : AnyLayout(HStackLayout(spacing: config.geometry.elementSpacing))
        layout {
            ForEach(0..<count, id: \.self) { i in
                GlassElementContent(config: config, index: i)
                    .padding(config.geometry.padding)
                    .frame(width: size.width, height: size.height)
                    .modifier(GlassEffectApplier(config: config, materialOn: materialOn))
                    .glassEffectID(i, in: ns)
                    .glassEffectUnion(id: config.geometry.unionAll ? "union" as String? : nil, namespace: ns)
                    .rotationEffect(.degrees(config.geometry.rotation))
                    .reportFrame(i)
            }
        }
    }

    @ViewBuilder
    private var glassButton: some View {
        let label = Group {
            if config.content == .empty {
                Color.clear.frame(width: max(1, size.width - 2 * config.geometry.padding), height: max(1, size.height - 2 * config.geometry.padding))
            } else {
                GlassElementContent(config: config, index: 0)
            }
        }
        let button = Button { } label: { label }
        switch config.subject {
        case .glassProminentButton:
            button.buttonStyle(.glassProminent).buttonBorderShape(borderShape).tint(config.tint?.color)
        case .glassClearButton:
            if #available(iOS 26.1, *) {
                button.buttonStyle(.glass(.clear)).buttonBorderShape(borderShape)
            } else {
                // Not available before iOS 26.1: shown as the regular glass style and flagged in the inspector.
                button.buttonStyle(.glass).buttonBorderShape(borderShape)
            }
        default:
            button.buttonStyle(.glass).buttonBorderShape(borderShape).tint(config.tint?.color)
        }
    }

    private var borderShape: ButtonBorderShape {
        switch config.shape {
        case .circle: return .circle
        case .roundedRect, .rect: return .roundedRectangle(radius: config.shape == .rect ? 0 : config.geometry.cornerRadius)
        default: return .capsule
        }
    }
}

/// UIKit glass: one `UIVisualEffectView` with `UIGlassEffect` per element, optionally inside a
/// `UIVisualEffectView` whose effect is `UIGlassContainerEffect`.
struct UIKitGlassSurface: UIViewRepresentable {
    var config: SceneConfiguration
    var materialOn: Bool
    var count: Int
    var spacing: Double

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .clear
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        host.subviews.forEach { $0.removeFromSuperview() }
        let useContainer = config.subject == .glassGroup && config.geometry.useContainer && materialOn
        let parent: UIView
        if useContainer {
            let container = UIGlassContainerEffect()
            container.spacing = config.geometry.containerSpacing
            let cv = UIVisualEffectView(effect: container)
            cv.frame = host.bounds
            cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.addSubview(cv)
            parent = cv.contentView
        } else {
            parent = host
        }
        let w = config.geometry.width * config.geometry.scale, h = config.geometry.height * config.geometry.scale
        for i in 0..<count {
            let v = UIVisualEffectView(effect: effect())
            let step = (config.geometry.vertical ? h : w) + spacing
            v.frame = config.geometry.vertical ? CGRect(x: 0, y: Double(i) * step, width: w, height: h)
                                               : CGRect(x: Double(i) * step, y: 0, width: w, height: h)
            applyCorners(v, w: w, h: h)
            if config.content != .empty {
                let label = UILabel()
                label.text = config.content == .symbol ? nil : config.contentText
                if config.content == .symbol || config.content == .mixed {
                    let attachment = NSTextAttachment(image: UIImage(systemName: config.contentSymbol) ?? UIImage())
                    let s = NSMutableAttributedString(attachment: attachment)
                    if config.content == .mixed { s.append(NSAttributedString(string: " " + config.contentText)) }
                    label.attributedText = s
                }
                label.font = .preferredFont(forTextStyle: .headline)
                label.textAlignment = .center
                label.frame = v.contentView.bounds
                label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                v.contentView.addSubview(label)
            }
            parent.addSubview(v)
        }
    }

    private func effect() -> UIVisualEffect? {
        guard materialOn else { return nil }   // reference: no effect (identity)
        switch config.variant {
        case .none, .identity: return nil
        case .regular, .clear:
            let e = UIGlassEffect(style: config.variant == .clear ? .clear : .regular)
            e.tintColor = config.tint?.uiColor
            e.isInteractive = config.interactive
            return e
        }
    }

    private func applyCorners(_ v: UIView, w: Double, h: Double) {
        switch config.shape {
        case .capsule: v.cornerConfiguration = .capsule()
        case .circle: v.cornerConfiguration = .corners(radius: .fixed(min(w, h) / 2))
        case .roundedRect: v.cornerConfiguration = .corners(radius: .fixed(config.geometry.cornerRadius * config.geometry.scale))
        case .rect: v.cornerConfiguration = .corners(radius: .fixed(0))
        case .ellipse, .customStar:
            // UIKit glass views support corner configurations only; other outlines fall back to a capsule.
            v.cornerConfiguration = .capsule()
        }
    }
}
