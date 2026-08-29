import CoreHaptics
import UIKit

/// Race haptics via CoreHaptics, with UIKit-generator fallback (and a silent
/// fallback on the simulator, which has no haptic hardware).
final class Haptics {
    private var engine: CHHapticEngine?
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let fallbackLight = UIImpactFeedbackGenerator(style: .light)
    private let fallbackHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let queue = DispatchQueue(label: "haptics", qos: .userInteractive)

    init() {
        guard supported else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        engine?.stoppedHandler = { _ in }
        try? engine?.start()
        fallbackLight.prepare()
        fallbackHeavy.prepare()
    }

    /// (time offset, intensity, sharpness)
    private func play(_ events: [(Double, Float, Float)]) {
        queue.async { [self] in
            guard supported, let engine else {
                let strong = events.contains { $0.1 > 0.65 }
                DispatchQueue.main.async {
                    if strong { self.fallbackHeavy.impactOccurred() }
                    else { self.fallbackLight.impactOccurred(intensity: CGFloat(events.first.map { max(0.2, $0.1) } ?? 0.4)) }
                }
                return
            }
            let evs = events.map { (t, i, s) in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: s),
                ], relativeTime: t)
            }
            if let pattern = try? CHHapticPattern(events: evs, parameters: []),
               let player = try? engine.makePlayer(with: pattern) {
                try? player.start(atTime: CHHapticTimeImmediate)
            }
        }
    }

    /// Ground contact — sharper and harder as speed rises.
    func footstep(speedFactor: Float) {
        play([(0, 0.3 + 0.45 * speedFactor, 0.4 + 0.35 * speedFactor)])
    }

    /// The gun: a crack and its echo in the chest.
    func gun() { play([(0, 1.0, 0.9), (0.05, 0.7, 0.3)]) }

    /// Block clearance: double kick.
    func launch() { play([(0, 0.9, 0.6), (0.09, 1.0, 0.8)]) }

    /// Hitting top gear at the end of the drive.
    func topGear() { play([(0, 0.6, 1.0), (0.12, 0.9, 0.7)]) }

    /// Crouching into set.
    func setCrouch() { play([(0, 0.5, 0.3)]) }

    /// Tension creeping in — a hard little tick that says "ease off".
    func tensionTick() { play([(0, 0.4, 1.0)]) }

    /// The dip at the line.
    func lean() { play([(0, 1.0, 0.5)]) }

    /// Crossing the line: triple burst fading into the crowd.
    func finishBurst() { play([(0, 1.0, 0.8), (0.12, 0.8, 0.6), (0.26, 1.0, 0.35)]) }
}
