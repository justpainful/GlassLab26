import UIKit
import UIKit.UIGestureRecognizerSubclass
import QuartzCore

/// Observes every touch in a window without taking part in gesture recognition. Touch timestamps
/// come from `UITouch.timestamp` (system uptime, the same clock as `CACurrentMediaTime`).
final class TouchObserverRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onEvent: ((InteractionEvent) -> Void)?
    weak var referenceView: UIView?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    private func emit(_ kind: InteractionEvent.Kind, _ touches: Set<UITouch>) {
        for t in touches {
            let p = t.location(in: referenceView ?? view)
            onEvent?(InteractionEvent(kind: kind, time: t.timestamp, x: p.x, y: p.y, label: nil,
                                      force: t.maximumPossibleForce > 0 ? Double(t.force / t.maximumPossibleForce) : nil))
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { emit(.touchDown, touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { emit(.touchMove, touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        emit(.touchUp, touches)
        if event.allTouches?.allSatisfy({ $0.phase == .ended || $0.phase == .cancelled }) ?? true { state = .failed }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { emit(.touchCancel, touches); state = .failed }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

/// Logs display-link callbacks. Callback count is not the number of frames the system rendered:
/// it shows when the app was given a chance to draw, and gaps reveal hitches on the main thread.
final class DisplayLinkLogger: NSObject {
    private var link: CADisplayLink?
    private(set) var timestamps: [Double] = []
    private(set) var targetTimestamps: [Double] = []
    var onTick: ((Double) -> Void)?

    func start(preferredFPS: Int? = nil) {
        stop()
        timestamps.removeAll(); targetTimestamps.removeAll()
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        if let f = preferredFPS { l.preferredFrameRateRange = CAFrameRateRange(minimum: Float(f), maximum: Float(f), preferred: Float(f)) }
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() { link?.invalidate(); link = nil }

    @objc private func tick(_ l: CADisplayLink) {
        timestamps.append(l.timestamp)
        targetTimestamps.append(l.targetTimestamp)
        onTick?(l.timestamp)
    }

    struct IntervalStats: Codable, Hashable, Sendable {
        var count: Int
        var meanInterval: Double
        var medianInterval: Double
        var p95Interval: Double
        var maxInterval: Double
        /// Intervals longer than 1.5x the nominal interval.
        var hitchCount: Int
        /// Sum of time beyond the nominal interval in hitches (s), divided by the duration: Apple's "hitch time ratio" idea.
        var hitchTimeRatio: Double
        var nominalInterval: Double
        var histogram: [Int]
        var histogramBinMs: Double
    }

    static func stats(_ ts: [Double], nominalFPS: Int) -> IntervalStats? {
        guard ts.count >= 3 else { return nil }
        let iv = zip(ts.dropFirst(), ts).map { $0 - $1 }
        let nominal = 1.0 / Double(max(1, nominalFPS))
        let hitches = iv.filter { $0 > nominal * 1.5 }
        let excess = hitches.reduce(0) { $0 + ($1 - nominal) }
        let duration = (ts.last ?? 0) - (ts.first ?? 0)
        let binMs = 2.0
        let hist = Statistics.histogram(iv.map { $0 * 1000 }, bins: 25, range: 0...(binMs * 25))
        return IntervalStats(count: iv.count, meanInterval: Statistics.mean(iv), medianInterval: Statistics.median(iv),
                             p95Interval: Statistics.quantile(iv, 0.95), maxInterval: iv.max() ?? .nan, hitchCount: hitches.count,
                             hitchTimeRatio: duration > 0 ? excess / duration : 0, nominalInterval: nominal, histogram: hist, histogramBinMs: binMs)
    }
}

/// Collects touch events and markers for one recording.
@MainActor
final class InteractionRecorder {
    private(set) var events: [InteractionEvent] = []
    private var recognizer: TouchObserverRecognizer?

    func begin(in window: UIWindow, reference: UIView? = nil, canvasOriginInWindow: CGPoint) {
        end()
        events.removeAll()
        let r = TouchObserverRecognizer(target: nil, action: nil)
        r.referenceView = window
        r.onEvent = { [weak self] e in
            var ev = e
            // Store canvas-relative points.
            if let x = ev.x, let y = ev.y { ev.x = x - canvasOriginInWindow.x; ev.y = y - canvasOriginInWindow.y }
            MainActor.assumeIsolated { self?.events.append(ev) }
        }
        window.addGestureRecognizer(r)
        recognizer = r
    }

    func mark(_ label: String, kind: InteractionEvent.Kind = .marker) {
        events.append(InteractionEvent(kind: kind, time: CACurrentMediaTime(), label: label))
    }

    func end() {
        if let r = recognizer { r.view?.removeGestureRecognizer(r) }
        recognizer = nil
    }
}
