import SwiftUI
import QuartzCore
import Combine

/// Frame-accurate vinyl rotation animator using CADisplayLink.
/// Uses a bounded display rate and sleeps when the record has stopped.
@MainActor
final class VinylAnimator: NSObject, ObservableObject {
    @Published private(set) var rotation: Double = 0

    // Spin physics
    private(set) var spinSpeed: Double = 0

    // External state (set by the view)
    var isPlaying: Bool = false { didSet { updatePausedState() } }
    var needleLifted: Bool = true { didSet { updatePausedState() } }
    var isDragging: Bool = false
    var rpm: Double = 33.33
    var reduceMotion: Bool = false { didSet { updatePausedState() } }

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleFrame(_:)))
        // Rotation is time-based, so limiting visual refresh does not change RPM.
        let rate = min(Float(UIScreen.main.maximumFramesPerSecond), 60)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: rate,
                                                       maximum: rate, preferred: rate)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = 0
        updatePausedState()
    }

    private func updatePausedState() {
        let paused = reduceMotion || (spinSpeed == 0 && (!isPlaying || needleLifted))
        if displayLink?.isPaused != paused {
            lastTimestamp = 0
            displayLink?.isPaused = paused
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Add rotation externally (e.g. from vinyl drag gesture).
    func addRotation(_ degrees: Double) {
        rotation += degrees
    }

    /// Reset rotation (e.g. when switching tracks).
    func resetRotation() {
        rotation = 0
        spinSpeed = 0
    }

    @objc private func handleFrame(_ link: CADisplayLink) {
        // First frame — just record timestamp
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }

        let dt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp

        // Guard against unreasonable intervals (backgrounding, tab switches)
        guard dt > 0 && dt < 0.5 else { return }

        // Skip rotation update while user drags vinyl
        guard !isDragging else { return }

        let degreesPerSecond = (rpm * 360.0) / 60.0

        // Smooth acceleration / deceleration
        let accel: Double = isPlaying && !needleLifted ? 2.5 : -3.0
        spinSpeed = max(0, min(1, spinSpeed + accel * dt))
        // Skip visual rotation when Reduce Motion is on
        if !reduceMotion && spinSpeed > 0 {
            rotation += degreesPerSecond * spinSpeed * dt
        }

        updatePausedState()
    }

    deinit {
        displayLink?.invalidate()
    }
}
