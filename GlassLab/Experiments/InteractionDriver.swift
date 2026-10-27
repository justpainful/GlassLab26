import SwiftUI
import QuartzCore

/// Triggers the interactions that the app can drive itself (state changes animated with SwiftUI).
/// Touch interactions (tap, press, drag) are performed by the operator and recorded by InteractionRecorder.
@MainActor
enum InteractionDriver {
    static func run(_ kind: InteractionKind, stage: StageState, mark: @escaping (String, InteractionEvent.Kind) -> Void) async {
        let n = max(2, stage.config.geometry.elementCount)
        let originalSpacing = stage.config.geometry.elementSpacing
        func animate(_ label: String, duration: Double = 0.8, _ change: () -> Void) async {
            mark(label, .stateChange)
            withAnimation(.smooth(duration: duration)) { change() }
            try? await Task.sleep(for: .seconds(duration + 0.6))
            mark(label + " (expected end)", .animationEnd)
        }
        switch kind {
        case .appear:
            stage.visibleCount = 1
            try? await Task.sleep(for: .milliseconds(500))
            await animate("Appear") { stage.visibleCount = n }
        case .disappear:
            stage.visibleCount = n
            try? await Task.sleep(for: .milliseconds(500))
            await animate("Disappear") { stage.visibleCount = 1 }
        case .merge:
            stage.config.geometry.elementSpacing = max(originalSpacing, 60)
            try? await Task.sleep(for: .milliseconds(500))
            await animate("Merge") { stage.config.geometry.elementSpacing = 0 }
        case .split:
            stage.config.geometry.elementSpacing = 0
            try? await Task.sleep(for: .milliseconds(500))
            await animate("Split") { stage.config.geometry.elementSpacing = max(originalSpacing, 60) }
        case .morph:
            stage.visibleCount = 1
            try? await Task.sleep(for: .milliseconds(500))
            await animate("Morph expand") { stage.visibleCount = n }
            await animate("Morph collapse") { stage.visibleCount = 1 }
        case .containerSpacing:
            stage.spacingOverride = 0
            try? await Task.sleep(for: .milliseconds(500))
            await animate("Container spacing 0 -> 80", duration: 1.2) { stage.spacingOverride = 80 }
        default:
            mark("Operator interaction: \(kind.rawValue)", .marker)
        }
    }

    static func reset(_ stage: StageState, spacing: Double) {
        stage.visibleCount = nil
        stage.spacingOverride = nil
        stage.config.geometry.elementSpacing = spacing
    }
}
