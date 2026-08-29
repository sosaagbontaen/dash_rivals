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

    /// Vertical thumb position → effort 0..1 (comfortable margins top/bottom).
    private func effort(of touch: UITouch) -> Double {
        let y = touch.location(in: self).y
        let top = bounds.height * 0.08
        let usable = bounds.height * 0.80
        return Double(max(0, min(1, 1 - (y - top) / usable)))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { gameController?.touch(side: side(of: t), isDown: true, hostTime: t.timestamp) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // The riding thumb: its vertical position is the effort input.
        if let t = touches.first { gameController?.effortInput(effort(of: t)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { gameController?.touch(side: side(of: t), isDown: false, hostTime: t.timestamp) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { gameController?.touch(side: side(of: t), isDown: false, hostTime: t.timestamp) }
    }
}
