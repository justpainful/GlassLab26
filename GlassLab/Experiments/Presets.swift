import Foundation
import Observation

/// Built-in and user presets. User presets are stored as JSON in Application Support.
@MainActor
@Observable
final class PresetStore {
    private(set) var user: [SceneConfiguration] = []
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GlassLab", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("presets.json")
        if let d = try? Data(contentsOf: url), let v = try? DataStore.decoder.decode([SceneConfiguration].self, from: d) { user = v }
    }

    func save(_ c: SceneConfiguration) {
        if let i = user.firstIndex(where: { $0.id == c.id }) { user[i] = c } else { user.append(c) }
        persist()
    }
    func delete(_ id: UUID) { user.removeAll { $0.id == id }; persist() }
    func duplicate(_ c: SceneConfiguration) { user.append(c.duplicated()); persist() }
    private func persist() { try? DataStore.encoder.encode(user).write(to: url, options: .atomic) }

    nonisolated static let builtIn: [SceneConfiguration] = {
        func make(_ name: String, _ f: (inout SceneConfiguration) -> Void) -> SceneConfiguration {
            var c = SceneConfiguration(); c.name = name; f(&c); return c
        }
        return [
            make("Clear Glass on Black") { $0.variant = .clear; $0.background = .solid(.black) },
            make("Regular Glass on White") { $0.variant = .regular; $0.background = .solid(.white) },
            make("Regular Glass on 18% Gray") { $0.variant = .regular; $0.background = .solid(.gray18) },
            make("Glass on Checkerboard") { $0.background = .pattern(.checkerboard, scale: 12); $0.shape = .roundedRect; $0.geometry.width = 260; $0.geometry.height = 140 },
            make("Glass on Random Dots") { $0.background = .pattern(.randomDots, scale: 9); $0.shape = .roundedRect; $0.geometry.width = 260; $0.geometry.height = 160; $0.modules = [.statistics, .blur, .refraction, .highlights, .errorMetrics] },
            make("Glass over Moving Gradient") { $0.background.kind = .movingGradient; $0.background.isPlaying = true; $0.interaction = .none },
            make("Tinted Glass on Photography") { $0.tint = RGBAColor(0.1, 0.45, 1.0, 0.6); $0.background.kind = .importedImage },
            make("Glass Merge with Two Buttons") { $0.subject = .glassGroup; $0.geometry.elementCount = 2; $0.geometry.width = 72; $0.geometry.height = 72; $0.shape = .circle; $0.content = .symbol; $0.interaction = .merge; $0.background = .pattern(.fineGrid, scale: 14) },
            make("Navigation Bar over Scrolling Content") { $0.subject = .uikitNavigationBar; $0.geometry.width = 390; $0.background.kind = .scrollingContent; $0.referenceMode = .subjectHidden },
            make("Tab Bar on High Contrast Background") { $0.subject = .uikitTabBar; $0.geometry.width = 390; $0.background = .pattern(.verticalLines, scale: 10); $0.background.lineWidth = 5; $0.referenceMode = .subjectHidden },
            make("Interactive Glass Press Test") { $0.interactive = true; $0.interaction = .pressAndHold; $0.background = .pattern(.dotGrid, scale: 12); $0.content = .symbol },
            make("Edge Refraction Calibration") { $0.background = .pattern(.stepEdge); $0.background.primary = .black; $0.background.secondary = .white; $0.shape = .roundedRect; $0.geometry.width = 280; $0.geometry.height = 180; $0.modules = [.edgeSpread, .blur, .highlights, .statistics] },
            make("Glass on Fiducial Checker") { $0.background = .pattern(.fiducialChecker, scale: 10); $0.shape = .roundedRect; $0.geometry.width = 280; $0.geometry.height = 160 },
            make("Container Spacing Study") { $0.subject = .glassGroup; $0.geometry.elementCount = 3; $0.geometry.width = 64; $0.geometry.height = 64; $0.shape = .circle; $0.geometry.elementSpacing = 12; $0.geometry.containerSpacing = 40; $0.interaction = .containerSpacing },
            make("UIKit Regular Glass on Noise") { $0.framework = .uiKit; $0.background = .pattern(.highFrequencyNoise); $0.shape = .roundedRect },
        ]
    }()
}
