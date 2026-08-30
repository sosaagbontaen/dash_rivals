import SwiftUI
import SceneKit

/// SceneKit view + raw multitouch capture. Sits under the SwiftUI HUD;
/// SwiftUI buttons above it receive their own touches.
struct RaceHostView: UIViewRepresentable {
    let controller: GameController

    func makeUIView(context: Context) -> TouchSCNView {
        let v = TouchSCNView(frame: .zero)
        v.scene = controller.scene
        v.delegate = controller
        v.pointOfView = controller.cameraDirector.node
        v.antialiasingMode = .multisampling2X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.isPlaying = true
        v.backgroundColor = .black
        v.isMultipleTouchEnabled = true
        v.gameController = controller
        return v
    }

    func updateUIView(_ uiView: TouchSCNView, context: Context) {}
}

final class TouchSCNView: SCNView {
    weak var gameController: GameController?

    private func side(of touch: UITouch) -> TapSide {
        touch.location(in: self).x < bounds.midX ? .left : .right
    }

    /// Joystick effort: radial distance of the thumb from its side's stick origin.
    /// The mapping is 1:1 with the on-screen widget geometry, so the thumb sits
    /// exactly on the ring it is producing — hold the gold ring to hold the band.
    private func stickOrigin(for side: TapSide) -> CGPoint {
        let x: CGFloat = side == .left ? 109 : bounds.width - 109
        return CGPoint(x: x, y: bounds.height - 109)
    }

    /// CIRCLE: effort = radial deflection from the stick origin (1:1 with the
    /// widget: deadR 9, usable 82, size 190); angle places the knob under the thumb.
    /// LINEAR: effort = horizontal position sweeping outward along the bottom bars.
    private func stickState(of touch: UITouch) -> (effort: Double, angle: Double) {
        let p = touch.location(in: self)
        if gameController?.trackingStyle == .linear {
            let half = bounds.width / 2
            let fromCenter = abs(p.x - half)
            let inner = half * 0.06
            let usable = half * 0.86
            return (Double(max(0, min(1, (fromCenter - inner) / usable))), -Double.pi / 2)
        }
        let o = stickOrigin(for: side(of: touch))
        let dx = p.x - o.x, dy = p.y - o.y
        let d = hypot(dx, dy)
        return (Double(max(0, min(1, (d - 9) / 82))), Double(atan2(dy, dx)))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            gameController?.touch(side: side(of: t), isDown: true, hostTime: t.timestamp)
            let s = stickState(of: t)
            gameController?.effortInput(side: side(of: t), value: s.effort, angle: s.angle)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let s = stickState(of: t)
            gameController?.effortInput(side: side(of: t), value: s.effort, angle: s.angle)
            // Downward motion feeds the dip detector (the lean at the line).
            let dy = t.location(in: self).y - t.previousLocation(in: self).y
            if dy > 0 { gameController?.dipInput(points: Double(dy)) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { gameController?.touch(side: side(of: t), isDown: false, hostTime: t.timestamp) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { gameController?.touch(side: side(of: t), isDown: false, hostTime: t.timestamp) }
    }
}
