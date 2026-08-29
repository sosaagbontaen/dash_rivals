import SceneKit

/// Procedurally-built articulated sprinter. No external assets: capsules, boxes and
/// spheres arranged in a joint hierarchy, posed every frame from simulation state.
final class RunnerFigure {
    enum Mode { case idle, blocks, set, running, decel, celebrate, exhausted }

    let root = SCNNode()
    var mode: Mode = .idle

    private let hips = SCNNode()
    private let torso = SCNNode()
    private let headPivot = SCNNode()
    private let shoulderL = SCNNode(); private let shoulderR = SCNNode()
    private let elbowL = SCNNode(); private let elbowR = SCNNode()
    private let thighL = SCNNode(); private let thighR = SCNNode()
    private let kneeL = SCNNode(); private let kneeR = SCNNode()
    private let ankleL = SCNNode(); private let ankleR = SCNNode()

    private let hipHeight: Float = 0.97
    /// Which leg is forward in the blocks (varies per athlete for a natural field).
    private let leftLegForward: Bool

    init(athlete: Athlete, leftLegForward: Bool = Bool.random()) {
        self.leftLegForward = leftLegForward

        let skin = Self.material(athlete.skinTone, roughness: 0.62)
        let vest = Self.material(athlete.kitPrimary, roughness: 0.85)
        let shorts = Self.material(athlete.kitSecondary, roughness: 0.85)
        let shoe = Self.material(athlete.shoeColor, roughness: 0.4)
        let hair = Self.material(UIColor(white: 0.06, alpha: 1), roughness: 0.9)
        let bibMat = Self.material(UIColor(white: 0.95, alpha: 1), roughness: 0.9)

        // Pelvis — kept narrow; the shorts live on the thighs so they move with the legs.
        hips.position = SCNVector3(0, hipHeight, 0)
        let pelvis = SCNNode(geometry: SCNBox(width: 0.26, height: 0.17, length: 0.155, chamferRadius: 0.06))
        pelvis.geometry?.materials = [shorts]
        pelvis.position = SCNVector3(0, -0.005, 0)
        hips.addChildNode(pelvis)
        root.addChildNode(hips)

        // Torso — broad chest, flat profile, tapering to the waist.
        torso.position = SCNVector3(0, 0.08, 0)
        hips.addChildNode(torso)
        let chest = SCNNode(geometry: SCNCapsule(capRadius: 0.145, height: 0.50))
        chest.geometry?.materials = [vest]
        chest.scale = SCNVector3(1.22, 1.0, 0.78)
        chest.position = SCNVector3(0, 0.285, 0)
        torso.addChildNode(chest)
        let waist = SCNNode(geometry: SCNCapsule(capRadius: 0.115, height: 0.26))
        waist.geometry?.materials = [vest]
        waist.scale = SCNVector3(1.1, 1.0, 0.82)
        waist.position = SCNVector3(0, 0.06, 0)
        torso.addChildNode(waist)
        let bib = SCNNode(geometry: SCNBox(width: 0.15, height: 0.11, length: 0.012, chamferRadius: 0.01))
        bib.geometry?.materials = [bibMat]
        bib.position = SCNVector3(0, 0.27, 0.122)
        torso.addChildNode(bib)

        // Head
        headPivot.position = SCNVector3(0, 0.56, 0)
        torso.addChildNode(headPivot)
        let neck = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.09))
        neck.geometry?.materials = [skin]
        neck.position = SCNVector3(0, 0.015, 0)
        headPivot.addChildNode(neck)
        let head = SCNNode(geometry: SCNSphere(radius: 0.092))
        head.geometry?.materials = [skin]
        head.position = SCNVector3(0, 0.115, 0.012)
        headPivot.addChildNode(head)
        let cap = SCNNode(geometry: SCNSphere(radius: 0.094))
        cap.geometry?.materials = [hair]
        cap.scale = SCNVector3(0.99, 0.72, 0.95)
        cap.position = SCNVector3(0, 0.165, -0.022)
        headPivot.addChildNode(cap)

        // Arms — deltoid caps hide the joint, blade hands for the sprinter look.
        func buildArm(_ shoulder: SCNNode, _ elbow: SCNNode, x: Float) {
            shoulder.position = SCNVector3(x, 0.46, 0)
            torso.addChildNode(shoulder)
            let deltoid = SCNNode(geometry: SCNSphere(radius: 0.068))
            deltoid.geometry?.materials = [skin]
            deltoid.position = SCNVector3(x > 0 ? 0.012 : -0.012, 0.01, 0)
            shoulder.addChildNode(deltoid)
            let upper = SCNNode(geometry: SCNCapsule(capRadius: 0.047, height: 0.30))
            upper.geometry?.materials = [skin]
            upper.position = SCNVector3(0, -0.14, 0)
            shoulder.addChildNode(upper)
            elbow.position = SCNVector3(0, -0.29, 0)
            shoulder.addChildNode(elbow)
            let fore = SCNNode(geometry: SCNCapsule(capRadius: 0.038, height: 0.26))
            fore.geometry?.materials = [skin]
            fore.position = SCNVector3(0, -0.12, 0)
            elbow.addChildNode(fore)
            let hand = SCNNode(geometry: SCNCapsule(capRadius: 0.03, height: 0.11))
            hand.geometry?.materials = [skin]
            hand.position = SCNVector3(0, -0.275, 0.012)
            hand.eulerAngles = SCNVector3(0.25, 0, 0)
            elbow.addChildNode(hand)
        }
        buildArm(shoulderL, elbowL, x: -0.245)
        buildArm(shoulderR, elbowR, x: 0.245)

        // Legs — shorts ride the thigh, calves give the silhouette, spikes get a sole.
        func buildLeg(_ thigh: SCNNode, _ knee: SCNNode, _ ankle: SCNNode, x: Float) {
            thigh.position = SCNVector3(x, -0.055, 0)
            hips.addChildNode(thigh)
            let thighGeo = SCNNode(geometry: SCNCapsule(capRadius: 0.068, height: 0.46))
            thighGeo.geometry?.materials = [skin]
            thighGeo.position = SCNVector3(0, -0.20, 0)
            thigh.addChildNode(thighGeo)
            let shortLeg = SCNNode(geometry: SCNCapsule(capRadius: 0.079, height: 0.21))
            shortLeg.geometry?.materials = [shorts]
            shortLeg.position = SCNVector3(0, -0.075, 0)
            thigh.addChildNode(shortLeg)
            knee.position = SCNVector3(0, -0.44, 0)
            thigh.addChildNode(knee)
            let shin = SCNNode(geometry: SCNCapsule(capRadius: 0.045, height: 0.44))
            shin.geometry?.materials = [skin]
            shin.position = SCNVector3(0, -0.20, 0)
            knee.addChildNode(shin)
            let calf = SCNNode(geometry: SCNCapsule(capRadius: 0.055, height: 0.17))
            calf.geometry?.materials = [skin]
            calf.position = SCNVector3(0, -0.115, -0.012)
            knee.addChildNode(calf)
            ankle.position = SCNVector3(0, -0.43, 0)
            knee.addChildNode(ankle)
            let foot = SCNNode(geometry: SCNBox(width: 0.088, height: 0.052, length: 0.185, chamferRadius: 0.024))
            foot.geometry?.materials = [shoe]
            foot.position = SCNVector3(0, -0.026, 0.038)
            ankle.addChildNode(foot)
            let toe = SCNNode(geometry: SCNBox(width: 0.078, height: 0.038, length: 0.085, chamferRadius: 0.018))
            toe.geometry?.materials = [shoe]
            toe.position = SCNVector3(0, -0.033, 0.155)
            toe.eulerAngles = SCNVector3(0.12, 0, 0)
            ankle.addChildNode(toe)
            let sole = SCNNode(geometry: SCNBox(width: 0.09, height: 0.014, length: 0.24, chamferRadius: 0.006))
            sole.geometry?.materials = [Self.material(UIColor(white: 0.92, alpha: 1), roughness: 0.5)]
            sole.position = SCNVector3(0, -0.055, 0.07)
            ankle.addChildNode(sole)
        }
        buildLeg(thighL, kneeL, ankleL, x: -0.10)
        buildLeg(thighR, kneeR, ankleR, x: 0.10)
    }

    private static func material(_ color: UIColor, roughness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        return m
    }

    // MARK: Per-frame posing

    /// - Parameters:
    ///   - phase: stride cycle 0..1 (full cycle = two steps)
    ///   - speed: current velocity in m/s
    ///   - lean: forward lean in radians (acceleration phase)
    ///   - time: absolute scene time, for idle/celebration motion
    func update(phase: Double, speed: Double, lean: Double, time: Double) {
        switch mode {
        case .idle: poseIdle(time: time)
        case .blocks: poseBlocks(setLift: 0)
        case .set: poseBlocks(setLift: 1)
        case .running, .decel: poseRun(phase: phase, speed: speed, lean: lean)
        case .celebrate: poseCelebrate(time: time)
        case .exhausted: poseExhausted(time: time)
        }
    }

    private func poseRun(phase: Double, speed: Double, lean: Double) {
        let s = Float(min(1.0, speed / 11.0))
        let w = Float(phase * 2 * .pi)
        // Drive intensity: deep lean = the violent, clawing block-exit strides.
        let drive = max(0, min(1, (Float(lean) - 0.15) / 0.6))

        hips.position.y = hipHeight - 0.03 * (1 - s) - 0.075 * drive + 0.038 * s * sin(2 * w)
        hips.eulerAngles = SCNVector3(0, 0, 0.03 * s * sin(w))

        torso.eulerAngles = SCNVector3(Float(lean) + 0.05 * s * sin(2 * w + 1.2),
                                       (0.10 + 0.08 * drive) * s * sin(w), 0)
        // Head stays buried during the drive, lifts as the body rises.
        headPivot.eulerAngles = SCNVector3(-Float(lean) * (0.8 - 0.45 * drive), 0, 0)

        // Gait asymmetry: real swing snaps forward and drags back — not a pure sine.
        func swingShape(_ x: Float) -> Float { sin(x + 0.32 * sin(x)) }

        // Legs: thigh swing + knee flexion; punching amplitude out of the blocks.
        let legAmp = 1 + 0.35 * drive
        func legPose(_ thigh: SCNNode, _ knee: SCNNode, _ ankle: SCNNode, _ ph: Float) {
            let swing = s * (0.38 + 0.88 * swingShape(ph)) * legAmp
            thigh.eulerAngles = SCNVector3(swing + Float(lean) * 0.35, 0, 0)
            // Sharp heel whip during swing-through, near-straight at stance.
            let flex = -s * (0.22 + (1.25 + 0.3 * drive) * pow(max(0, sin(ph + 1.15)), 1.35))
            knee.eulerAngles = SCNVector3(min(-0.06, flex), 0, 0)
            // Toe-off extension behind, dorsiflexed (toes up) through the swing.
            let toe = s * (0.18 + 0.55 * sin(ph - 2.1))
            ankle.eulerAngles = SCNVector3(toe, 0, 0)
        }
        legPose(thighL, kneeL, ankleL, w)
        legPose(thighR, kneeR, ankleR, w + .pi)

        // Arms: counter-swing with a cross-body arc; elbow opens on the backswing,
        // hand pumps up toward the chin at the front.
        let armAmp = 1 + 0.5 * drive
        func armPose(_ shoulder: SCNNode, _ elbow: SCNNode, _ ph: Float, mirror: Float) {
            let swing = s * (1.05 * swingShape(ph)) * armAmp - 0.12
            shoulder.eulerAngles = SCNVector3(swing, mirror * 0.20 * s * sin(ph), mirror * -0.14)
            let open = 0.55 * s * max(0, -sin(ph))     // unfolds behind
            elbow.eulerAngles = SCNVector3(-1.5 + open - 0.2 * s * max(0, sin(ph)), 0, 0)
        }
        armPose(shoulderL, elbowL, w + .pi, mirror: 1)    // opposite of left leg
        armPose(shoulderR, elbowR, w, mirror: -1)
        shoulderL.eulerAngles.z = -0.14
        shoulderR.eulerAngles.z = 0.14
    }

    private func poseBlocks(setLift: Float) {
        let crouch: Float = 0.52 + 0.17 * setLift
        hips.position.y = crouch
        hips.eulerAngles = SCNVector3(0, 0, 0)
        torso.eulerAngles = SCNVector3(1.12 - 0.10 * setLift, 0, 0)
        headPivot.eulerAngles = SCNVector3(-0.75, 0, 0)

        let frontThigh: Float = 1.45, frontKnee: Float = -1.75
        let backThigh: Float = 0.55 - 0.25 * setLift, backKnee: Float = -1.15 + 0.2 * setLift
        if leftLegForward {
            thighL.eulerAngles = SCNVector3(frontThigh, 0, 0); kneeL.eulerAngles = SCNVector3(frontKnee, 0, 0)
            thighR.eulerAngles = SCNVector3(backThigh, 0, 0); kneeR.eulerAngles = SCNVector3(backKnee, 0, 0)
        } else {
            thighR.eulerAngles = SCNVector3(frontThigh, 0, 0); kneeR.eulerAngles = SCNVector3(frontKnee, 0, 0)
            thighL.eulerAngles = SCNVector3(backThigh, 0, 0); kneeL.eulerAngles = SCNVector3(backKnee, 0, 0)
        }
        ankleL.eulerAngles = SCNVector3(0.9, 0, 0)
        ankleR.eulerAngles = SCNVector3(0.9, 0, 0)

        // Arms straight down to the track, shoulder-width.
        shoulderL.eulerAngles = SCNVector3(-1.12 + 0.06 * setLift, 0, -0.10)
        shoulderR.eulerAngles = SCNVector3(-1.12 + 0.06 * setLift, 0, 0.10)
        elbowL.eulerAngles = SCNVector3(-0.06, 0, 0)
        elbowR.eulerAngles = SCNVector3(-0.06, 0, 0)
    }

    private func poseIdle(time: Double) {
        let t = Float(time)
        hips.position.y = hipHeight - 0.015
        hips.eulerAngles = SCNVector3(0, 0, 0)
        torso.eulerAngles = SCNVector3(0.04 + 0.015 * sin(t * 0.9), 0, 0)
        headPivot.eulerAngles = SCNVector3(0, 0.08 * sin(t * 0.5), 0)
        thighL.eulerAngles = SCNVector3(0.02, 0, -0.04); kneeL.eulerAngles = SCNVector3(-0.06, 0, 0)
        thighR.eulerAngles = SCNVector3(-0.02, 0, 0.04); kneeR.eulerAngles = SCNVector3(-0.06, 0, 0)
        ankleL.eulerAngles = SCNVector3(0, 0, 0); ankleR.eulerAngles = SCNVector3(0, 0, 0)
        shoulderL.eulerAngles = SCNVector3(0.05, 0, -0.10)
        shoulderR.eulerAngles = SCNVector3(0.05, 0, 0.10)
        elbowL.eulerAngles = SCNVector3(-0.25, 0, 0)
        elbowR.eulerAngles = SCNVector3(-0.25, 0, 0)
    }

    private func poseCelebrate(time: Double) {
        let t = Float(time)
        hips.position.y = hipHeight + 0.02 * abs(sin(t * 3))
        torso.eulerAngles = SCNVector3(-0.12, 0, 0)
        headPivot.eulerAngles = SCNVector3(0.30, 0, 0)
        thighL.eulerAngles = SCNVector3(0.03, 0, -0.05); kneeL.eulerAngles = SCNVector3(-0.08, 0, 0)
        thighR.eulerAngles = SCNVector3(-0.03, 0, 0.05); kneeR.eulerAngles = SCNVector3(-0.08, 0, 0)
        shoulderL.eulerAngles = SCNVector3(2.95, 0, -0.55 - 0.1 * sin(t * 3))
        shoulderR.eulerAngles = SCNVector3(2.95, 0, 0.55 + 0.1 * sin(t * 3 + 1))
        elbowL.eulerAngles = SCNVector3(-0.35, 0, 0)
        elbowR.eulerAngles = SCNVector3(-0.35, 0, 0)
    }

    private func poseExhausted(time: Double) {
        let t = Float(time)
        hips.position.y = hipHeight - 0.14
        torso.eulerAngles = SCNVector3(0.58 + 0.05 * sin(t * 1.6), 0, 0)   // breathing
        headPivot.eulerAngles = SCNVector3(-0.15, 0, 0)
        thighL.eulerAngles = SCNVector3(0.35, 0, -0.06); kneeL.eulerAngles = SCNVector3(-0.55, 0, 0)
        thighR.eulerAngles = SCNVector3(0.35, 0, 0.06); kneeR.eulerAngles = SCNVector3(-0.55, 0, 0)
        shoulderL.eulerAngles = SCNVector3(-0.65, 0, -0.15)
        shoulderR.eulerAngles = SCNVector3(-0.65, 0, 0.15)
        elbowL.eulerAngles = SCNVector3(-0.35, 0, 0)
        elbowR.eulerAngles = SCNVector3(-0.35, 0, 0)
    }
}
