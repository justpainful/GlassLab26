import SwiftUI
import UIKit
import Observation

/// Live state of the experiment stage. The canvas renders exactly this and nothing else.
@MainActor
@Observable
final class StageState {
    var config = SceneConfiguration()
    /// false renders the reference (identity glass / hidden subject).
    var materialOn = true
    /// Frozen background phase used during acquisition; nil follows playback.
    var forcedPhase: Double?
    /// Animated element count for appear / merge / split studies.
    var visibleCount: Int?
    var spacingOverride: Double?
    var focusMode = false
    /// Incremented to force a fresh subject view (resets internal control state).
    var generation = 0
}

/// Where the canvas is in the window and where the glass elements are inside it.
@MainActor
@Observable
final class CanvasProbe {
    var frameInWindow: CGRect = .zero
    weak var window: UIWindow?
    var elementFrames: [Int: CGRect] = [:]
    var canvasSize: CGSize = .zero

    var subjectFrame: CGRect {
        let frames = elementFrames.values
        guard let first = frames.first else { return .zero }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    var orderedElementFrames: [CGRect] { elementFrames.keys.sorted().compactMap { elementFrames[$0] } }
}

struct ExperimentCanvas: View {
    var stage: StageState
    var probe: CanvasProbe
    /// Only the canvas that is actually on screen reports its geometry (focus mode covers the inline one).
    var reports = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BackgroundView(spec: stage.config.background, forcedPhase: stage.forcedPhase)
                NativeSubjectView(config: stage.config, materialOn: stage.materialOn,
                                  visibleCount: stage.visibleCount, spacingOverride: stage.spacingOverride)
                    .id(stage.generation)
                    .fixedSize()
                    .position(x: geo.size.width / 2 + stage.config.geometry.offsetX,
                              y: geo.size.height / 2 + stage.config.geometry.offsetY)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(.named("canvas"))
            .onPreferenceChange(ElementFramesKey.self) { frames in
                guard reports else { return }
                Task { @MainActor in probe.elementFrames = frames }
            }
            .background(WindowFrameReader { frame, window in
                guard reports else { return }
                if probe.frameInWindow != frame { probe.frameInWindow = frame }
                if probe.window !== window { probe.window = window }
                if probe.canvasSize != geo.size { probe.canvasSize = geo.size }
            })
        }
        .clipped()
        .accessibilityIdentifier("experimentCanvas")
    }
}

/// Reports the frame of its host view in window coordinates after every layout pass.
struct WindowFrameReader: UIViewRepresentable {
    var onChange: (CGRect, UIWindow?) -> Void

    final class ReaderView: UIView {
        var onChange: ((CGRect, UIWindow?) -> Void)?
        override func layoutSubviews() { super.layoutSubviews(); report() }
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        func report() {
            guard let w = window else { return }
            let f = convert(bounds, to: w)
            let cb = onChange
            DispatchQueue.main.async { cb?(f, w) }
        }
    }

    func makeUIView(context: Context) -> ReaderView {
        let v = ReaderView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.onChange = onChange
        return v
    }

    func updateUIView(_ v: ReaderView, context: Context) {
        v.onChange = onChange
        v.report()
    }
}
