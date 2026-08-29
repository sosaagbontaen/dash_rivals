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

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { gameController?.touch(side: side(of: t), isDown: true, hostTime: t.timestamp) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { gameController?.touch(side: side(of: t), isDown: false, hostTime: t.timestamp) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { gameController?.touch(side: side(of: t), isDown: false, hostTime: t.timestamp) }
    }
}
