import SceneKit

/// Drives the single gameplay camera through the whole presentation:
/// menu beauty shot → intro dolly → set push-in → low chase cam → celebration orbit.
final class CameraDirector {
    enum Mode { case menu, intro, set, chase, orbit, finishCam }

    let node = SCNNode()
    var mode: Mode = .menu

    private let camera = SCNCamera()
    private var shake: Float = 0
    private var smoothPos = SIMD3<Float>(5, 2, -14)
    private var smoothLook = SIMD3<Float>(5, 1, 20)
    private var smoothFov: Float = 62
    private var orbitAngle: Float = .pi
    private var fovKick: Float = 0          // transient widening (top-gear bloom)
    private var streaks: SCNParticleSystem!

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
        camera.colorFringeStrength = 0.8
        camera.colorFringeIntensity = 0
        camera.exposureOffset = 0.15
        node.camera = camera
        node.position = SCNVector3(smoothPos)
        buildStreaks()
    }

    /// Wind streaks whipping past the lens at speed.
    private func buildStreaks() {
        streaks = SCNParticleSystem()
        streaks.emitterShape = SCNBox(width: 7, height: 4.5, length: 0.5, chamferRadius: 0)
        streaks.birthLocation = .volume
        streaks.emittingDirection = SCNVector3(0, 0, 1)   // toward the camera
        streaks.particleVelocity = 30
        streaks.particleVelocityVariation = 8
        streaks.particleLifeSpan = 0.4
        streaks.particleSize = 0.02
        streaks.stretchFactor = 0.12
        streaks.particleColor = UIColor(white: 1, alpha: 0.30)
        streaks.particleColorVariation = SCNVector4(0, 0, 0, 0.12)
        streaks.blendMode = .additive
        streaks.birthRate = 0
        let emitter = SCNNode()
        emitter.position = SCNVector3(0, 0, -9)
        emitter.addParticleSystem(streaks)
        node.addChildNode(emitter)
    }

    func impulse(_ amount: Float) {
        shake = min(1.2, shake + amount)
    }

    /// The "hit top gear" moment: a transient FOV bloom that settles back.
    func topGearBloom() {
        fovKick = 11
    }

    /// Drive the streak density from player speed (m/s).
    func setStreakSpeed(_ v: Float) {
        let n = max(0, (v - 7.5) / 4)
        streaks.birthRate = CGFloat(min(1.4, n)) * 210
        streaks.particleVelocity = CGFloat(18 + v * 1.6)
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
            // The core camera: in the tunnel during the drive (low, tight, narrow),
            // blooming out into full flight at speed.
            let sp = min(1, v / 12)
            let spE = sp * sp * (3 - 2 * sp)   // eased
            let sway = sin(phase * 2 * .pi * 2) * 0.05 * sp
            let bob = sin(phase * 2 * .pi * 2 + 1.3) * 0.03 * sp
            targetPos = SIMD3(playerX + sway, 1.46 - spE * 0.10 + bob, playerZ - 2.45 - spE * 0.55)
            targetLook = SIMD3(playerX, 1.12, playerZ + 6.5 + spE * 2.5)
            targetFov = 54 + spE * 21 + fovKick
            stiffness = 14
            // Rumble out of the blocks; smooths out as flight settles in.
            shake = max(shake, 0.10 * (1 - spE))

        case .orbit:
            orbitAngle += Float(dt) * 0.35
            let r: Float = 5.6
            targetPos = SIMD3(playerX + sin(orbitAngle) * r, 2.1, playerZ + cos(orbitAngle) * r)
            targetLook = SIMD3(playerX, 1.15, playerZ)
            targetFov = 50
            stiffness = 2.2

        case .finishCam:
            // Broadcast long lens from trackside at the line, tracking the field in.
            targetPos = SIMD3(14.2, 1.75, 97.2)
            targetLook = SIMD3(4.9, 1.0, min(99.5, playerZ + 1.5))
            targetFov = 30
            stiffness = 7
        }

        // Exponential smoothing toward targets.
        let k = min(1, Float(dt) * stiffness)
        smoothPos += (targetPos - smoothPos) * k
        smoothLook += (targetLook - smoothLook) * k
        smoothFov += (targetFov - smoothFov) * min(1, Float(dt) * 6)

        // Shake (gun, stumble) decays quickly; FOV bloom settles back.
        shake *= exp(-Float(dt) * 6.5)
        fovKick *= exp(-Float(dt) * 3.2)
        let sx = sin(t * 39) * shake * 0.05
        let sy = cos(t * 47) * shake * 0.04

        node.simdPosition = smoothPos + SIMD3(sx, sy, 0)
        node.look(at: SCNVector3(smoothLook + SIMD3(sx * 0.5, sy * 0.5, 0)),
                  up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        node.simdEulerAngles.z += sin(t * 31) * shake * 0.02
        camera.fieldOfView = CGFloat(smoothFov)

        // Motion blur and chromatic fringe only matter at speed; keep menus crisp.
        let sp = CGFloat(min(1, v / 12))
        camera.motionBlurIntensity = mode == .chase ? 0.4 + 0.45 * sp : 0.1
        camera.colorFringeIntensity = mode == .chase ? sp * 1.1 : 0
        camera.vignettingIntensity = mode == .chase ? 0.75 + 0.25 * sp : 0.75
    }

    /// Reset smoothing when jumping between distant shots to avoid a long swoop.
    func snap(to pos: SIMD3<Float>, look: SIMD3<Float>) {
        smoothPos = pos
        smoothLook = look
        orbitAngle = .pi
    }
}
