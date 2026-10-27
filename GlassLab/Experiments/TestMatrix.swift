import Foundation
import Observation

/// A factor of the test matrix and the levels chosen for it.
enum MatrixAxis: String, Codable, CaseIterable, Identifiable, Sendable {
    case variant = "Glass Variant"
    case background = "Background"
    case appearance = "Appearance"
    case shape = "Shape"
    case framework = "Framework"
    case tint = "Tint"
    case size = "Size"
    var id: String { rawValue }

    /// All levels the app can apply (appearance via the window's interface style override).
    var levels: [String] {
        switch self {
        case .variant: return GlassVariant.allCases.map(\.rawValue)
        case .background: return ["Black", "White", "18% Gray", "Checkerboard", "Random Dots", "Noise", "Step Edge", "Photo"]
        case .appearance: return ["Light", "Dark"]
        case .shape: return [GlassShapeKind.capsule, .circle, .roundedRect, .rect].map(\.rawValue)
        case .framework: return NativeFramework.allCases.map(\.rawValue)
        case .tint: return ["None", "Blue", "Orange"]
        case .size: return ["Small (120x48)", "Medium (220x88)", "Large (320x200)"]
        }
    }

    func apply(_ level: String, to c: inout SceneConfiguration) {
        switch self {
        case .variant: if let v = GlassVariant(rawValue: level) { c.variant = v }
        case .background:
            switch level {
            case "Black": c.background = .solid(.black)
            case "White": c.background = .solid(.white)
            case "18% Gray": c.background = .solid(.gray18)
            case "Checkerboard": c.background = .pattern(.checkerboard, scale: 12)
            case "Random Dots": c.background = .pattern(.randomDots, scale: 9)
            case "Noise": c.background = .pattern(.highFrequencyNoise)
            case "Step Edge": c.background = .pattern(.stepEdge)
            case "Photo": c.background.kind = .importedImage
            default: break
            }
        case .appearance: c.appearance = level == "Dark" ? .dark : .light
        case .shape: if let s = GlassShapeKind(rawValue: level) { c.shape = s }
        case .framework: if let f = NativeFramework(rawValue: level) { c.framework = f }
        case .tint:
            switch level {
            case "Blue": c.tint = RGBAColor(0.0, 0.48, 1.0, 0.5)
            case "Orange": c.tint = RGBAColor(1.0, 0.58, 0.0, 0.5)
            default: c.tint = nil
            }
        case .size:
            switch level {
            case "Small (120x48)": c.geometry.width = 120; c.geometry.height = 48
            case "Large (320x200)": c.geometry.width = 320; c.geometry.height = 200
            default: c.geometry.width = 220; c.geometry.height = 88
            }
        }
    }
}

enum MatrixMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case full = "Full Matrix"
    case pairwise = "Pairwise Coverage"
    case sampled = "Random Sample"
    case selected = "Selected Combinations"
    var id: String { rawValue }
}

enum MatrixOrdering: String, Codable, CaseIterable, Identifiable, Sendable {
    case asGenerated = "As Generated"
    case groupByBackground = "Group by Background"
    case shuffled = "Shuffled (seeded)"
    var id: String { rawValue }
}

struct MatrixCase: Codable, Hashable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case pending = "Pending", running = "Running", done = "Done", failed = "Failed", incomplete = "Incomplete", skipped = "Skipped" }
    var id = UUID()
    var levels: [String: String]
    var status: Status = .pending
    var attempts = 0
    var experimentIDs: [UUID] = []
    var error: String?
    var included = true

    var label: String { levels.keys.sorted().map { "\($0): \(levels[$0]!)" }.joined(separator: " · ") }
}

struct TestMatrixPlan: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name = "Matrix " + Format.timestamp.string(from: Date())
    var base = SceneConfiguration()
    var axes: [MatrixAxis: [String]] = [.variant: ["Regular", "Clear"], .background: ["Black", "White", "Checkerboard"]]
    var mode: MatrixMode = .full
    var sampleCount = 12
    var seed: UInt64 = 42
    var batchSize = 10
    var repetitions = 1
    var ordering: MatrixOrdering = .asGenerated
    var analyzeAfterCapture = true
    var cases: [MatrixCase] = []
    var sessionID: UUID?

    var activeAxes: [(MatrixAxis, [String])] {
        MatrixAxis.allCases.compactMap { a in axes[a].flatMap { $0.isEmpty ? nil : (a, $0) } }
    }

    var fullCount: Int { activeAxes.reduce(1) { $0 * $1.1.count } }

    /// Generates cases according to the mode. Pairwise uses a greedy all-pairs construction.
    mutating func generate() {
        var rng = ProceduralImageCache.SplitMix(state: seed)
        let ax = activeAxes
        var combos: [[String: String]] = []
        switch mode {
        case .full, .selected:
            combos = TestMatrixPlan.cartesian(ax)
        case .sampled:
            var all = TestMatrixPlan.cartesian(ax)
            all.shuffle(using: &rng)
            combos = Array(all.prefix(max(1, sampleCount)))
        case .pairwise:
            combos = TestMatrixPlan.pairwise(ax, rng: &rng)
        }
        switch ordering {
        case .asGenerated: break
        case .groupByBackground: combos.sort { ($0[MatrixAxis.background.rawValue] ?? "") < ($1[MatrixAxis.background.rawValue] ?? "") }
        case .shuffled: combos.shuffle(using: &rng)
        }
        cases = combos.map { MatrixCase(levels: $0, included: mode != .selected) }
    }

    static func cartesian(_ ax: [(MatrixAxis, [String])]) -> [[String: String]] {
        var out: [[String: String]] = [[:]]
        for (a, levels) in ax {
            out = out.flatMap { partial in levels.map { l in var p = partial; p[a.rawValue] = l; return p } }
        }
        return out
    }

    /// Greedy pairwise (all-pairs) covering set.
    static func pairwise(_ ax: [(MatrixAxis, [String])], rng: inout ProceduralImageCache.SplitMix) -> [[String: String]] {
        guard ax.count > 2 else { return cartesian(ax) }
        var uncovered = Set<String>()
        func key(_ i: Int, _ a: String, _ j: Int, _ b: String) -> String { "\(i)=\(a)|\(j)=\(b)" }
        for i in 0..<ax.count { for j in (i + 1)..<ax.count { for a in ax[i].1 { for b in ax[j].1 { uncovered.insert(key(i, a, j, b)) } } } }
        var rows: [[String]] = []
        var guardCount = 0
        while !uncovered.isEmpty && guardCount < 10_000 {
            guardCount += 1
            var best: [String] = []
            var bestGain = -1
            for _ in 0..<40 {
                var row = ax.map { $0.1[Int(rng.next() % UInt64($0.1.count))] }
                // Improve greedily axis by axis
                for i in 0..<ax.count {
                    var bestLevel = row[i], bestScore = -1
                    for l in ax[i].1 {
                        row[i] = l
                        var s = 0
                        for x in 0..<ax.count { for y in (x + 1)..<ax.count where uncovered.contains(key(x, row[x], y, row[y])) { s += 1 } }
                        if s > bestScore { bestScore = s; bestLevel = l }
                    }
                    row[i] = bestLevel
                }
                var gain = 0
                for x in 0..<ax.count { for y in (x + 1)..<ax.count where uncovered.contains(key(x, row[x], y, row[y])) { gain += 1 } }
                if gain > bestGain { bestGain = gain; best = row }
            }
            if bestGain <= 0 { break }
            for x in 0..<ax.count { for y in (x + 1)..<ax.count { uncovered.remove(key(x, best[x], y, best[y])) } }
            rows.append(best)
        }
        return rows.map { r in Dictionary(uniqueKeysWithValues: ax.indices.map { (ax[$0].0.rawValue, r[$0]) }) }
    }

    func configuration(for c: MatrixCase) -> SceneConfiguration {
        var cfg = base
        cfg.id = UUID()
        for a in MatrixAxis.allCases { if let l = c.levels[a.rawValue] { a.apply(l, to: &cfg) } }
        cfg.name = "\(name): \(c.label)"
        return cfg
    }

    /// Rough storage estimate: two PNG frames per case per repetition at ~3 bytes/px (PNG of mixed content),
    /// plus derived images. Shown as an estimate only.
    func estimatedBytes(canvasPixels: Int) -> UInt64 {
        let perFrame = UInt64(canvasPixels) * 3
        let perCase = perFrame * 2 + (analyzeAfterCapture ? perFrame : 0)
        return UInt64(cases.filter(\.included).count * max(1, repetitions)) * perCase
    }
}

/// Persists matrix plans so interrupted runs are detected and resumable.
@MainActor
@Observable
final class MatrixStore {
    private(set) var plans: [TestMatrixPlan] = []
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GlassLab", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("matrices.json")
        if let d = try? Data(contentsOf: url), var v = try? DataStore.decoder.decode([TestMatrixPlan].self, from: d) {
            // Cases left "running" by a previous launch were interrupted.
            for i in v.indices { for j in v[i].cases.indices where v[i].cases[j].status == .running { v[i].cases[j].status = .incomplete } }
            plans = v
        }
    }

    func save(_ p: TestMatrixPlan) {
        if let i = plans.firstIndex(where: { $0.id == p.id }) { plans[i] = p } else { plans.insert(p, at: 0) }
        try? DataStore.encoder.encode(plans).write(to: url, options: .atomic)
    }

    func delete(_ id: UUID) {
        plans.removeAll { $0.id == id }
        try? DataStore.encoder.encode(plans).write(to: url, options: .atomic)
    }
}
