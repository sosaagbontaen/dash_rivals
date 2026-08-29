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

    /// Joystick effort: radial distance of the thumb from its side's stick origin
    /// (bottom corners, matching the on-screen joystick widgets). Push out = more.
    private func stickOrigin(for side: TapSide) -> CGPoint {
        let x: CGFloat = side == .left ? 79 : bounds.width - 79
        return CGPoint(x: x, y: bounds.height - 79)
    }

    private func effort(of touch: UITouch) -> Double {
        let p = touch.location(in: self)
        let o = stickOrigin(for: side(of: touch))
        let d = hypot(p.x - o.x, p.y - o.y)
        return Double(max(0, min(1, (d - 12) / 120)))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            gameController?.touch(side: side(of: t), isDown: true, hostTime: t.timestamp)
            gameController?.effortInput(side: side(of: t), value: effort(of: t))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            gameController?.effortInput(side: side(of: t), value: effort(of: t))
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
