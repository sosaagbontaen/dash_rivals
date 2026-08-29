import SceneKit

/// Drives the single gameplay camera through the whole presentation:
/// menu beauty shot → intro dolly → set push-in → low chase cam → celebration orbit.
final class CameraDirector {
    enum Mode { case menu, intro, set, chase, orbit }

    let node = SCNNode()
    var mode: Mode = .menu

    private let camera = SCNCamera()
    private var shake: Float = 0
    private var smoothPos = SIMD3<Float>(5, 2, -14)
    private var smoothLook = SIMD3<Float>(5, 1, 20)
    private var smoothFov: Float = 62
    private var orbitAngle: Float = .pi

    init() {
        camera.zNear = 0.1
        camera.zFar = 600
        camera.fieldOfView = 62
        camera.wantsHDR = true
        camera.bloomIntensity = 0.45
        camera.bloomThreshold = 0.95
        camera.bloomBlurRadius = 10
        camera.motionBlurIntensity = 0.55
        camera.vignettingIntensity = 0.75
        camera.vignettingPower = 0.85
        camera.exposureOffset = 0.15
        node.camera = camera
        node.position = SCNVector3(smoothPos)
    }

    func impulse(_ amount: Float) {
        shake = min(1.2, shake + amount)
    }

    /// - Parameters:
    ///   - introT: seconds spent in the intro (for the dolly)
    ///   - playerX/Z: player runner position; v: velocity; phase: stride phase
    func update(dt: Double, time: Double, introT: Double,
                playerX: Float, playerZ: Float, v: Float, phase: Float) {
        let t = Float(time)
        var targetPos: SIMD3<Float>
        var targetLook: SIMD3<Float>
        var targetFov: Float = 62
        var stiffness: Float = 4.5

        switch mode {
        case .menu:
            // Front-on lineup shot, slow drift.
            let drift = sin(t * 0.14) * 2.2
            targetPos = SIMD3(5 + drift, 1.75, 7.5)
            targetLook = SIMD3(4.88, 1.15, -4)
            targetFov = 58

        case .intro:
            // Dolly across the field from lane 8 to the player's lane.
            let p = Float(min(1, introT / 6.0))
            let e = p * p * (3 - 2 * p)   // smoothstep
            let x = 11.8 - e * 13.5
            targetPos = SIMD3(x, 1.25, 2.6)
            targetLook = SIMD3(x - 0.6, 0.95, -0.9)
            targetFov = 48
            stiffness = 8

        case .set:
            // Low behind the player, creeping in.
            let creep = Float(min(1, introT / 3.0)) * 0.5
            targetPos = SIMD3(playerX + 0.9, 1.25 - creep * 0.25, playerZ - 4.4 + creep)
            targetLook = SIMD3(playerX, 0.75, playerZ + 3)
            targetFov = 55
            stiffness = 3.2

        case .chase:
            // The core camera: low, tight, widening with speed.
            let sp = min(1, v / 12)
            let sway = sin(phase * 2 * .pi * 2) * 0.05 * sp
            let bob = sin(phase * 2 * .pi * 2 + 1.3) * 0.03 * sp
            targetPos = SIMD3(playerX + sway, 1.52 - sp * 0.16 + bob, playerZ - 2.75 + sp * 0.2)
            targetLook = SIMD3(playerX, 1.15, playerZ + 7)
            targetFov = 57 + sp * 16
            stiffness = 14

        case .orbit:
            orbitAngle += Float(dt) * 0.35
            let r: Float = 5.6
            targetPos = SIMD3(playerX + sin(orbitAngle) * r, 2.1, playerZ + cos(orbitAngle) * r)
            targetLook = SIMD3(playerX, 1.15, playerZ)
            targetFov = 50
            stiffness = 2.2
        }

        // Exponential smoothing toward targets.
        let k = min(1, Float(dt) * stiffness)
        smoothPos += (targetPos - smoothPos) * k
        smoothLook += (targetLook - smoothLook) * k
        smoothFov += (targetFov - smoothFov) * min(1, Float(dt) * 6)

        // Shake (gun, stumble) decays quickly.
        shake *= exp(-Float(dt) * 6.5)
        let sx = sin(t * 39) * shake * 0.05
        let sy = cos(t * 47) * shake * 0.04

        node.simdPosition = smoothPos + SIMD3(sx, sy, 0)
        node.look(at: SCNVector3(smoothLook + SIMD3(sx * 0.5, sy * 0.5, 0)),
                  up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        node.simdEulerAngles.z += sin(t * 31) * shake * 0.02
        camera.fieldOfView = CGFloat(smoothFov)

        // Motion blur only matters at speed; keep menus crisp.
        camera.motionBlurIntensity = mode == .chase ? CGFloat(0.4 + 0.35 * min(1, v / 12)) : 0.1
    }

    /// Reset smoothing when jumping between distant shots to avoid a long swoop.
    func snap(to pos: SIMD3<Float>, look: SIMD3<Float>) {
        smoothPos = pos
        smoothLook = look
        orbitAngle = .pi
    }
}
