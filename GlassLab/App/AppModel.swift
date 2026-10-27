import SwiftUI
import Observation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case explore = "Explore"
    case lab = "Experiment Lab"
    case optics = "Optics"
    case motion = "Motion"
    case compare = "Compare"
    case sessions = "Sessions"
    case reconstruction = "Reconstruction"
    case matrix = "Test Matrix"
    case performance = "Performance"
    case research = "Models"
    case environment = "Environment"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .explore: return "square.grid.2x2"
        case .lab: return "flask"
        case .optics: return "camera.aperture"
        case .motion: return "waveform.path.ecg"
        case .compare: return "square.split.2x1"
        case .sessions: return "tray.full"
        case .reconstruction: return "cube.transparent"
        case .matrix: return "tablecells"
        case .performance: return "speedometer"
        case .research: return "function"
        case .environment: return "info.circle"
        }
    }
}

/// Root object graph. Everything UI-facing lives on the main actor; heavy work is detached.
@MainActor
@Observable
final class AppModel {
    var section: AppSection = .lab
    let store: DataStore
    let environment = DeviceEnvironmentMonitor()
    let stage = StageState()
    let probe = CanvasProbe()
    let capture: CaptureCoordinator
    let engine = MeasurementEngine()
    let presets = PresetStore()
    let matrices = MatrixStore()
    /// Experiment selected for Optics / Motion detail.
    var selectedExperimentID: UUID?
    var compareA: UUID?
    var compareB: UUID?
    var banner: String?

    init(store: DataStore? = nil) {
        self.store = store ?? DataStore()
        capture = CaptureCoordinator(stage: stage, probe: probe)
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            section = .explore
        }
    }

    var activeSessionID: UUID {
        store.ensureActiveSession(environment: environment.current).id
    }

    /// Applies the lab's appearance to the window through the public interface-style override, so system
    /// components (SwiftUI and UIKit) receive the same trait the system would set.
    func syncAppearance() {
        guard let w = probe.window ?? DeviceEnvironmentMonitor.keyWindow else { return }
        switch stage.config.appearance {
        case .system: w.overrideUserInterfaceStyle = .unspecified
        case .light: w.overrideUserInterfaceStyle = .light
        case .dark: w.overrideUserInterfaceStyle = .dark
        }
    }

    func load(_ config: SceneConfiguration) {
        var c = config
        c.id = UUID()
        stage.config = c
        stage.generation += 1
        syncAppearance()
        section = .lab
    }

    /// Runs the acquisition protocol for the current configuration `repetitions` times, analysing each.
    func acquireCurrent() async {
        environment.refresh()
        let sid = activeSessionID
        let reps = max(1, stage.config.repetitions)
        for r in 0..<reps {
            do {
                let exp = try await capture.acquire(store: store, environment: environment.current, sessionID: sid, repetition: r)
                selectedExperimentID = exp.id
                if !stage.config.modules.isEmpty {
                    await engine.analyze(experimentID: exp.id, sessionID: sid, store: store)
                }
            } catch {
                capture.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                break
            }
        }
    }

    func experiment(_ id: UUID?) -> (ExperimentSession, Experiment)? {
        guard let id else { return nil }
        for s in store.sessions { if let e = s.experiments.first(where: { $0.id == id }) { return (s, e) } }
        return nil
    }
}
