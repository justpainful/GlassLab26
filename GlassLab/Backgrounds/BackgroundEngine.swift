import SwiftUI
import AVFoundation
import UIKit

/// Deterministic procedural backgrounds. For a given spec, canvas size and phase every pixel is
/// reproducible, which is what makes a reference/test pair comparable.
struct BackgroundView: View {
    var spec: BackgroundSpec
    /// When set, overrides playback (captures always pass a frozen phase).
    var forcedPhase: Double? = nil

    var body: some View {
        if spec.kind.isAnimated && spec.isPlaying && forcedPhase == nil {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                content(phase: spec.frozenPhase + t * spec.motionSpeed)
            }
        } else {
            content(phase: forcedPhase ?? spec.frozenPhase)
        }
    }

    @ViewBuilder
    private func content(phase: Double) -> some View {
        ZStack {
            Rectangle().fill(spec.base.color)
            layer(phase: phase)
                .opacity(spec.elementOpacity)
        }
        .contrast(spec.contrast)
        .saturation(spec.saturation)
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func layer(phase: Double) -> some View {
        switch spec.kind {
        case .solid:
            Rectangle().fill(spec.primary.color)
        case .linearGradient:
            LinearGradient(stops: gradientStops, startPoint: Self.unitPoint(angle: spec.gradientAngle + 180), endPoint: Self.unitPoint(angle: spec.gradientAngle))
        case .radialGradient:
            GeometryReader { g in
                RadialGradient(stops: gradientStops, center: UnitPoint(x: spec.objectX, y: spec.objectY),
                               startRadius: 0, endRadius: max(g.size.width, g.size.height) * 0.7)
            }
        case .movingGradient:
            let a = spec.gradientAngle + phase.truncatingRemainder(dividingBy: 1) * 360
            LinearGradient(stops: gradientStops, startPoint: Self.unitPoint(angle: a + 180), endPoint: Self.unitPoint(angle: a))
        case .importedImage:
            ImportedImageBackground(file: spec.importedFile)
        case .importedVideo:
            ImportedVideoBackground(file: spec.importedFile, playing: spec.isPlaying && forcedPhase == nil, phase: phase)
        case .highFrequencyNoise, .lowFrequencyNoise, .randomDots:
            ProceduralImageBackground(spec: spec)
        default:
            Canvas(rendersAsynchronously: false) { ctx, size in
                ProceduralPainter.paint(spec, phase: phase, in: &ctx, size: size)
            }
        }
    }

    private var gradientStops: [Gradient.Stop] {
        spec.stops.sorted { $0.location < $1.location }.map { Gradient.Stop(color: $0.color.color, location: $0.location) }
    }

    static func unitPoint(angle: Double) -> UnitPoint {
        let r = angle * .pi / 180
        return UnitPoint(x: 0.5 + 0.5 * cos(r), y: 0.5 + 0.5 * sin(r))
    }
}

enum ProceduralPainter {
    static func paint(_ s: BackgroundSpec, phase: Double, in ctx: inout GraphicsContext, size: CGSize) {
        let p = max(1, s.patternScale)
        let fg = GraphicsContext.Shading.color(s.primary.color)
        let bg = GraphicsContext.Shading.color(s.secondary.color)
        let lw = max(0.25, s.lineWidth)
        switch s.kind {
        case .checkerboard, .fiducialChecker:
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: bg)
            var path = Path()
            let cols = Int(ceil(size.width / p)), rows = Int(ceil(size.height / p))
            for r in 0..<rows { for c in 0..<cols where (r + c) % 2 == 0 {
                path.addRect(CGRect(x: Double(c) * p, y: Double(r) * p, width: p, height: p))
            } }
            ctx.fill(path, with: fg)
            if s.kind == .fiducialChecker {
                // Asymmetric markers every 6 cells: red ring + offset dot, unique orientation for matching.
                let step = p * 6
                var y = step / 2
                var k = 0
                while y < size.height {
                    var x = step / 2
                    while x < size.width {
                        let ring = Path(ellipseIn: CGRect(x: x - p * 0.9, y: y - p * 0.9, width: p * 1.8, height: p * 1.8))
                        ctx.stroke(ring, with: .color(.red), lineWidth: max(1, p * 0.18))
                        let a = Double(k % 4) * .pi / 2
                        ctx.fill(Path(ellipseIn: CGRect(x: x + cos(a) * p * 0.45 - p * 0.2, y: y + sin(a) * p * 0.45 - p * 0.2, width: p * 0.4, height: p * 0.4)), with: .color(.red))
                        x += step; k += 1
                    }
                    y += step
                }
            }
        case .fineGrid, .denseGrid:
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: bg)
            let pitch = s.kind == .denseGrid ? p / 2 : p
            var path = Path()
            var x = 0.0
            while x <= size.width { path.addRect(CGRect(x: x - lw / 2, y: 0, width: lw, height: size.height)); x += pitch }
            var y = 0.0
            while y <= size.height { path.addRect(CGRect(x: 0, y: y - lw / 2, width: size.width, height: lw)); y += pitch }
            ctx.fill(path, with: fg)
        case .dotGrid:
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: bg)
            var path = Path()
            let rad = max(0.5, lw * 1.5)
            var y = p / 2
            while y < size.height { var x = p / 2; while x < size.width { path.addEllipse(in: CGRect(x: x - rad, y: y - rad, width: 2 * rad, height: 2 * rad)); x += p }; y += p }
            ctx.fill(path, with: fg)
        case .horizontalLines, .verticalLines, .diagonalLines:
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: bg)
            var path = Path()
            if s.kind == .horizontalLines {
                var y = 0.0; while y <= size.height { path.addRect(CGRect(x: 0, y: y, width: size.width, height: lw)); y += p }
            } else if s.kind == .verticalLines {
                var x = 0.0; while x <= size.width { path.addRect(CGRect(x: x, y: 0, width: lw, height: size.height)); x += p }
            } else {
                let span = size.width + size.height
                var d = -size.height
                while d <= span {
                    path.move(to: CGPoint(x: d, y: 0)); path.addLine(to: CGPoint(x: d + size.height, y: size.height)); d += p
                }
                ctx.stroke(path, with: fg, lineWidth: lw)
                return
            }
            ctx.fill(path, with: fg)
        case .stepEdge:
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: bg)
            let cx = size.width * s.objectX, cy = size.height * s.objectY
            var c = ctx
            c.translateBy(x: cx, y: cy)
            c.rotate(by: .degrees(s.edgeAngle))
            let big = (size.width + size.height) * 2
            c.fill(Path(CGRect(x: -big, y: -big, width: big, height: 2 * big)), with: fg)
        case .textPattern, .fineTypography, .largeTypography:
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: bg)
            let fs = s.kind == .fineTypography ? max(5, s.fontSize * 0.6) : (s.kind == .largeTypography ? s.fontSize * 4 : s.fontSize)
            let line = fs * 1.25
            let text = Text(s.text + "  " + s.text).font(.system(size: fs, weight: s.kind == .largeTypography ? .bold : .regular)).foregroundColor(s.primary.color)
            let resolved = ctx.resolve(text)
            var y = 0.0, row = 0
            while y < size.height {
                ctx.draw(resolved, at: CGPoint(x: -Double(row % 7) * fs, y: y), anchor: .topLeading)
                y += line; row += 1
            }
        case .movingObjects:
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: bg)
            let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]
            for i in 0..<6 {
                let t = phase + Double(i) / 6
                let x = size.width * (0.5 + 0.38 * cos(2 * .pi * t + Double(i)))
                let y = size.height * (0.5 + 0.38 * sin(2 * .pi * t * (1 + Double(i % 3) * 0.25)))
                let r = p * 2.5
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(colors[i]))
            }
            let ox = size.width * s.objectX, oy = size.height * s.objectY
            ctx.fill(Path(CGRect(x: ox - p * 2, y: oy - p * 2, width: p * 4, height: p * 4)), with: fg)
        case .scrollingContent:
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: bg)
            let rowH = max(24, p * 3)
            let offset = s.scrollOffset + phase * rowH * 4
            let colors: [Color] = [.red, .orange, .green, .teal, .blue, .indigo, .purple, .pink]
            var y = -offset.truncatingRemainder(dividingBy: rowH * Double(colors.count)) - rowH * Double(colors.count)
            var i = 0
            while y < size.height {
                ctx.fill(Path(roundedRect: CGRect(x: 12, y: y + 4, width: size.width - 24, height: rowH - 8), cornerRadius: 8), with: .color(colors[i % colors.count]))
                let label = ctx.resolve(Text("Row \(i)").font(.headline).foregroundColor(.white))
                ctx.draw(label, at: CGPoint(x: 28, y: y + rowH / 2), anchor: .leading)
                y += rowH; i += 1
            }
        default:
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: fg)
        }
    }
}

/// Noise and random-dot backgrounds rendered once into a bitmap at device pixel resolution.
struct ProceduralImageBackground: View {
    var spec: BackgroundSpec
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { g in
            if let img = ProceduralImageCache.shared.image(spec: spec, size: g.size, scale: displayScale) {
                Image(decorative: img, scale: displayScale).interpolation(.none).resizable().frame(width: g.size.width, height: g.size.height)
            } else {
                Color(spec.secondary.uiColor)
            }
        }
    }
}

final class ProceduralImageCache: @unchecked Sendable {
    static let shared = ProceduralImageCache()
    private let lock = NSLock()
    private var cache: [String: CGImage] = [:]

    func image(spec: BackgroundSpec, size: CGSize, scale: CGFloat) -> CGImage? {
        guard size.width > 1, size.height > 1 else { return nil }
        let key = "\(spec.kind.rawValue)|\(spec.seed)|\(spec.noiseFrequency)|\(spec.patternScale)|\(spec.lineWidth)|\(spec.primary.hex)|\(spec.secondary.hex)|\(Int(size.width))x\(Int(size.height))@\(scale)"
        lock.lock(); defer { lock.unlock() }
        if let c = cache[key] { return c }
        let img = Self.render(spec: spec, w: Int(size.width * scale), h: Int(size.height * scale), scale: Double(scale))
        if cache.count > 16 { cache.removeAll() }
        cache[key] = img
        return img
    }

    /// SplitMix64: a small deterministic generator so patterns are identical across launches and devices.
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    static func hash(_ x: Int, _ y: Int, _ seed: UInt64) -> Double {
        var g = SplitMix(state: seed ^ (UInt64(bitPattern: Int64(x)) &* 0x9E3779B1) ^ (UInt64(bitPattern: Int64(y)) &* 0x85EBCA77))
        return Double(g.next() >> 11) / Double(1 << 53)
    }

    static func render(spec: BackgroundSpec, w: Int, h: Int, scale: Double) -> CGImage? {
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        let a = spec.primary, b = spec.secondary
        func put(_ i: Int, _ t: Double) {
            bytes[i * 4] = UInt8(max(0, min(255, (a.r * t + b.r * (1 - t)) * 255)))
            bytes[i * 4 + 1] = UInt8(max(0, min(255, (a.g * t + b.g * (1 - t)) * 255)))
            bytes[i * 4 + 2] = UInt8(max(0, min(255, (a.b * t + b.b * (1 - t)) * 255)))
        }
        switch spec.kind {
        case .highFrequencyNoise:
            let cell = max(1, Int((spec.noiseFrequency * scale / 4).rounded()))
            for y in 0..<h { for x in 0..<w { put(y * w + x, hash(x / cell, y / cell, spec.seed)) } }
        case .lowFrequencyNoise:
            let cell = max(2.0, spec.noiseFrequency * 8 * scale)
            for y in 0..<h {
                for x in 0..<w {
                    let fx = Double(x) / cell, fy = Double(y) / cell
                    let ix = Int(floor(fx)), iy = Int(floor(fy))
                    var tx = fx - Double(ix), ty = fy - Double(iy)
                    tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
                    let v00 = hash(ix, iy, spec.seed), v10 = hash(ix + 1, iy, spec.seed)
                    let v01 = hash(ix, iy + 1, spec.seed), v11 = hash(ix + 1, iy + 1, spec.seed)
                    put(y * w + x, (v00 * (1 - tx) + v10 * tx) * (1 - ty) + (v01 * (1 - tx) + v11 * tx) * ty)
                }
            }
        case .randomDots:
            for i in 0..<(w * h) { put(i, 0) }
            var rng = SplitMix(state: spec.seed)
            let rad = max(1.0, spec.lineWidth * 1.5 * scale)
            let count = Int(Double(w * h) / pow(max(spec.patternScale, 2) * scale * 0.6, 2))
            for _ in 0..<count {
                let cx = Double(rng.next() % UInt64(w)), cy = Double(rng.next() % UInt64(h))
                let r = rad * (0.6 + 0.8 * Double(rng.next() % 1000) / 1000)
                let x0 = max(0, Int(cx - r)), x1 = min(w - 1, Int(cx + r)), y0 = max(0, Int(cy - r)), y1 = min(h - 1, Int(cy + r))
                if x0 > x1 || y0 > y1 { continue }
                for y in y0...y1 { for x in x0...x1 where (Double(x) - cx) * (Double(x) - cx) + (Double(y) - cy) * (Double(y) - cy) <= r * r { put(y * w + x, 1) } }
            }
        default:
            break
        }
        let space = CGColorSpace(name: a.space == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)!
        return bytes.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
    }
}

enum BackgroundFiles {
    static var directory: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GlassLab/Backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    /// Copies an imported file into the app container and returns its stored name.
    static func store(data: Data, ext: String) throws -> String {
        let name = "bg-" + Format.fileStamp.string(from: Date()) + "-" + String(UUID().uuidString.prefix(6)) + "." + ext
        try data.write(to: url(name), options: .atomic)
        return name
    }
}

struct ImportedImageBackground: View {
    var file: String?
    var body: some View {
        GeometryReader { g in
            if let file, let img = UIImage(contentsOfFile: BackgroundFiles.url(file).path) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: g.size.width, height: g.size.height).clipped()
            } else {
                ZStack {
                    Color(white: 0.5)
                    Text("No image imported").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ImportedVideoBackground: UIViewRepresentable {
    var file: String?
    var playing: Bool
    var phase: Double

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var looper: AVPlayerLooper?
        var file: String?
    }

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.playerLayer.videoGravity = .resizeAspectFill
        v.backgroundColor = .gray
        return v
    }

    func updateUIView(_ v: PlayerView, context: Context) {
        if v.file != file {
            v.file = file
            if let file {
                let item = AVPlayerItem(url: BackgroundFiles.url(file))
                let player = AVQueuePlayer()
                player.isMuted = true
                v.looper = AVPlayerLooper(player: player, templateItem: item)
                v.playerLayer.player = player
            } else {
                v.playerLayer.player = nil
                v.looper = nil
            }
        }
        guard let player = v.playerLayer.player else { return }
        if playing {
            player.play()
        } else {
            player.pause()
            if let d = player.currentItem?.duration, d.isNumeric, d.seconds > 0 {
                let t = CMTime(seconds: phase.truncatingRemainder(dividingBy: 1) * d.seconds, preferredTimescale: 600)
                player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }
}
