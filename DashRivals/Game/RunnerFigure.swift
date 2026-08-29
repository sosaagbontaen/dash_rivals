import SceneKit

/// Procedurally-built articulated sprinter, v3: muscle-group silhouette
/// (chest/lats taper, glutes, quads, calves, deltoids, traps), a two-segment
/// spine for counter-rotation, and front-side sprint mechanics in the run cycle.
/// No external assets — posed every frame from simulation state.
final class RunnerFigure {
    enum Mode { case idle, blocks, set, running, decel, celebrate, exhausted }

    let root = SCNNode()
    var mode: Mode = .idle

    private let hips = SCNNode()
    private let torso = SCNNode()       // lower spine (lean)
    private let chest = SCNNode()       // upper spine (counter-rotation)
    private let headPivot = SCNNode()
    private let shoulderL = SCNNode(); private let shoulderR = SCNNode()
    private let elbowL = SCNNode(); private let elbowR = SCNNode()
    private let thighL = SCNNode(); private let thighR = SCNNode()
    private let kneeL = SCNNode(); private let kneeR = SCNNode()
    private let ankleL = SCNNode(); private let ankleR = SCNNode()

    private let hipHeight: Float = 1.0
    /// Which leg is forward in the blocks (varies per athlete for a natural field).
    private let leftLegForward: Bool

    init(athlete: Athlete, leftLegForward: Bool = Bool.random(), lane: Int = 0) {
        self.leftLegForward = leftLegForward

        let skin = Self.material(athlete.skinTone, roughness: 0.48)   // faint sweat sheen
        let vest = Self.material(athlete.kitPrimary, roughness: 0.78)
        let shorts = Self.material(athlete.kitSecondary, roughness: 0.78)
        let shoe = Self.material(athlete.shoeColor, roughness: 0.38)
        let hair = Self.material(UIColor(white: 0.06, alpha: 1), roughness: 0.9)
        let bibMat = Self.material(UIColor(white: 0.95, alpha: 1), roughness: 0.9)

        // ── Pelvis & glutes ──────────────────────────────────────────────
        hips.position = SCNVector3(0, hipHeight, 0)
        root.addChildNode(hips)
        let pelvis = SCNNode(geometry: SCNBox(width: 0.27, height: 0.16, length: 0.15, chamferRadius: 0.06))
        pelvis.geometry?.materials = [shorts]
        pelvis.position = SCNVector3(0, -0.005, 0)
        hips.addChildNode(pelvis)
        for x: Float in [-0.07, 0.07] {
            let glute = SCNNode(geometry: SCNSphere(radius: 0.075))
            glute.geometry?.materials = [shorts]
            glute.scale = SCNVector3(1.0, 0.92, 0.9)
            glute.position = SCNVector3(x, -0.03, -0.055)
            hips.addChildNode(glute)
        }

        // ── Spine: abdomen (torso) + chest with taper ────────────────────
        torso.position = SCNVector3(0, 0.07, 0)
        hips.addChildNode(torso)
        let abdomen = SCNNode(geometry: SCNCapsule(capRadius: 0.10, height: 0.22))
        abdomen.geometry?.materials = [vest]
        abdomen.scale = SCNVector3(1.12, 1.0, 0.78)
        abdomen.position = SCNVector3(0, 0.05, 0.005)
        torso.addChildNode(abdomen)

        chest.position = SCNVector3(0, 0.20, 0)
        torso.addChildNode(chest)
        let ribcage = SCNNode(geometry: SCNCapsule(capRadius: 0.148, height: 0.34))
        ribcage.geometry?.materials = [vest]
        ribcage.scale = SCNVector3(1.28, 1.0, 0.76)
        ribcage.position = SCNVector3(0, 0.10, 0.005)
        chest.addChildNode(ribcage)
        let lats = SCNNode(geometry: SCNCapsule(capRadius: 0.118, height: 0.24))
        lats.geometry?.materials = [vest]
        lats.scale = SCNVector3(1.22, 1.0, 0.72)
        lats.position = SCNVector3(0, 0.0, -0.012)
        chest.addChildNode(lats)
        for x: Float in [-0.095, 0.095] {
            let trap = SCNNode(geometry: SCNSphere(radius: 0.052))
            trap.geometry?.materials = [skin]
            trap.scale = SCNVector3(1.25, 0.7, 1.0)
            trap.position = SCNVector3(x, 0.255, -0.012)
            chest.addChildNode(trap)
        }

        // Bib + lane number
        let bib = SCNNode(geometry: SCNBox(width: 0.15, height: 0.11, length: 0.012, chamferRadius: 0.01))
        bib.geometry?.materials = [bibMat]
        bib.position = SCNVector3(0, 0.09, 0.125)
        chest.addChildNode(bib)
        if lane > 0 {
            let text = SCNText(string: "\(lane)", extrusionDepth: 0.004)
            text.font = UIFont.systemFont(ofSize: 1, weight: .heavy)
            text.flatness = 0.05
            text.materials = [Self.material(UIColor(red: 0.08, green: 0.10, blue: 0.25, alpha: 1), roughness: 0.8)]
            let n = SCNNode(geometry: text)
            let (minB, maxB) = text.boundingBox
            let scale = 0.075 / (maxB.y - minB.y)
            n.scale = SCNVector3(scale, scale, 1)
            n.position = SCNVector3(-(maxB.x - minB.x) * scale / 2, 0.055, 0.132)
            chest.addChildNode(n)
        }

        // ── Head & neck ──────────────────────────────────────────────────
        headPivot.position = SCNVector3(0, 0.30, 0)
        chest.addChildNode(headPivot)
        let neck = SCNNode(geometry: SCNCylinder(radius: 0.042, height: 0.10))
        neck.geometry?.materials = [skin]
        neck.position = SCNVector3(0, 0.02, 0)
        headPivot.addChildNode(neck)
        let head = SCNNode(geometry: SCNSphere(radius: 0.088))
        head.geometry?.materials = [skin]
        head.scale = SCNVector3(0.94, 1.06, 0.98)
        head.position = SCNVector3(0, 0.135, 0.012)
        headPivot.addChildNode(head)
        let jaw = SCNNode(geometry: SCNSphere(radius: 0.056))
        jaw.geometry?.materials = [skin]
        jaw.scale = SCNVector3(0.92, 0.72, 0.95)
        jaw.position = SCNVector3(0, 0.072, 0.045)
        headPivot.addChildNode(jaw)
        let cap = SCNNode(geometry: SCNSphere(radius: 0.09))
        cap.geometry?.materials = [hair]
        cap.scale = SCNVector3(0.99, 0.74, 0.96)
        cap.position = SCNVector3(0, 0.185, -0.018)
        headPivot.addChildNode(cap)
        let eyeMat = Self.material(UIColor(white: 0.05, alpha: 1), roughness: 0.3)
        for x: Float in [-0.032, 0.032] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.011))
            eye.geometry?.materials = [eyeMat]
            eye.position = SCNVector3(x, 0.148, 0.082)
            headPivot.addChildNode(eye)
        }

        // ── Arms ─────────────────────────────────────────────────────────
        func buildArm(_ shoulder: SCNNode, _ elbow: SCNNode, x: Float) {
            shoulder.position = SCNVector3(x, 0.235, 0)
            chest.addChildNode(shoulder)
            let deltoid = SCNNode(geometry: SCNSphere(radius: 0.068))
            deltoid.geometry?.materials = [skin]
            deltoid.position = SCNVector3(x > 0 ? 0.014 : -0.014, 0.012, 0)
            shoulder.addChildNode(deltoid)
            let upper = SCNNode(geometry: SCNCapsule(capRadius: 0.047, height: 0.30))
            upper.geometry?.materials = [skin]
            upper.position = SCNVector3(0, -0.14, 0)
            shoulder.addChildNode(upper)
            let bicep = SCNNode(geometry: SCNSphere(radius: 0.054))
            bicep.geometry?.materials = [skin]
            bicep.scale = SCNVector3(0.95, 1.25, 0.95)
            bicep.position = SCNVector3(0, -0.11, 0.012)
            shoulder.addChildNode(bicep)
            elbow.position = SCNVector3(0, -0.295, 0)
            shoulder.addChildNode(elbow)
            let elbowCap = SCNNode(geometry: SCNSphere(radius: 0.044))
            elbowCap.geometry?.materials = [skin]
            elbow.addChildNode(elbowCap)
            let fore = SCNNode(geometry: SCNCapsule(capRadius: 0.038, height: 0.26))
            fore.geometry?.materials = [skin]
            fore.position = SCNVector3(0, -0.12, 0)
            elbow.addChildNode(fore)
            let hand = SCNNode(geometry: SCNCapsule(capRadius: 0.029, height: 0.11))
            hand.geometry?.materials = [skin]
            hand.position = SCNVector3(0, -0.275, 0.012)
            hand.eulerAngles = SCNVector3(0.25, 0, 0)
            elbow.addChildNode(hand)
        }
        buildArm(shoulderL, elbowL, x: -0.25)
        buildArm(shoulderR, elbowR, x: 0.25)

        // ── Legs ─────────────────────────────────────────────────────────
        func buildLeg(_ thigh: SCNNode, _ knee: SCNNode, _ ankle: SCNNode, x: Float) {
            thigh.position = SCNVector3(x, -0.055, 0)
            hips.addChildNode(thigh)
            let quad = SCNNode(geometry: SCNCapsule(capRadius: 0.076, height: 0.46))
            quad.geometry?.materials = [skin]
            quad.scale = SCNVector3(1.0, 1.0, 1.1)
            quad.position = SCNVector3(0, -0.205, 0.004)
            thigh.addChildNode(quad)
            let shortLeg = SCNNode(geometry: SCNCapsule(capRadius: 0.086, height: 0.21))
            shortLeg.geometry?.materials = [shorts]
            shortLeg.position = SCNVector3(0, -0.075, 0)
            thigh.addChildNode(shortLeg)
            knee.position = SCNVector3(0, -0.45, 0)
            thigh.addChildNode(knee)
            let kneeCap = SCNNode(geometry: SCNSphere(radius: 0.055))
            kneeCap.geometry?.materials = [skin]
            knee.addChildNode(kneeCap)
            let shin = SCNNode(geometry: SCNCapsule(capRadius: 0.046, height: 0.45))
            shin.geometry?.materials = [skin]
            shin.position = SCNVector3(0, -0.205, 0)
            knee.addChildNode(shin)
            let calf = SCNNode(geometry: SCNCapsule(capRadius: 0.058, height: 0.19))
            calf.geometry?.materials = [skin]
            calf.position = SCNVector3(0, -0.125, -0.014)
            knee.addChildNode(calf)
            ankle.position = SCNVector3(0, -0.44, 0)
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

        // Stance-locked bob (lowest just after contact); pelvis counter-rotates.
        hips.position.y = hipHeight - 0.03 * (1 - s) - 0.075 * drive + 0.04 * s * sin(2 * w - 0.6)
        hips.eulerAngles = SCNVector3(0, -0.12 * s * sin(w), 0.035 * s * sin(w))

        // Lower spine carries the lean; chest counter-rotates against the pelvis
        // with a touch of side-flex.
        torso.eulerAngles = SCNVector3(Float(lean) + 0.04 * s * sin(2 * w + 1.2), 0, 0)
        chest.eulerAngles = SCNVector3(0.06 * s, (0.17 + 0.08 * drive) * s * sin(w),
                                       0.035 * s * sin(w + 0.5))
        // Head stays level and stable — sprinters' heads don't bounce.
        headPivot.eulerAngles = SCNVector3(-Float(lean) * (0.78 - 0.42 * drive)
                                           - 0.04 * s * sin(2 * w + 1.2),
                                           -0.10 * s * sin(w), 0)

        // Gait asymmetry: swing snaps forward, drags back.
        func swingShape(_ x: Float) -> Float { sin(x + 0.32 * sin(x)) }

        // Legs: front-side mechanics — high knee punch, near-full extension behind,
        // heel whipped to the glute through the swing.
        let legAmp = 1 + 0.32 * drive
        func legPose(_ thigh: SCNNode, _ knee: SCNNode, _ ankle: SCNNode, _ ph: Float) {
            let swing = s * (0.44 + 0.82 * swingShape(ph)) * legAmp
            thigh.eulerAngles = SCNVector3(swing + Float(lean) * 0.35, 0, 0)
            let flex = -s * (0.15 + (1.42 + 0.25 * drive) * pow(max(0, sin(ph + 1.2)), 1.5))
            knee.eulerAngles = SCNVector3(max(-2.15, min(-0.06, flex)), 0, 0)
            // Plantarflex at toe-off behind, dorsiflexed (toes up) through the swing.
            let toe = s * (0.22 + 0.5 * sin(ph - 2.0))
            ankle.eulerAngles = SCNVector3(toe, 0, 0)
        }
        legPose(thighL, kneeL, ankleL, w)
        legPose(thighR, kneeR, ankleR, w + .pi)

        // Arms: hip-pocket to chin, slight cross-body arc, elbow unfolding behind.
        let armAmp = 1 + 0.45 * drive
        func armPose(_ shoulder: SCNNode, _ elbow: SCNNode, _ ph: Float, mirror: Float) {
            let swing = s * (1.15 * swingShape(ph)) * armAmp - 0.10
            shoulder.eulerAngles = SCNVector3(swing, mirror * 0.20 * s * sin(ph), mirror * -0.13)
            let open = 0.58 * s * max(0, -sin(ph))
            elbow.eulerAngles = SCNVector3(-1.55 + open - 0.22 * s * max(0, sin(ph)), 0, 0)
        }
        armPose(shoulderL, elbowL, w + .pi, mirror: 1)
        armPose(shoulderR, elbowR, w, mirror: -1)
    }

    private func poseBlocks(setLift: Float) {
        let crouch: Float = 0.54 + 0.17 * setLift
        hips.position.y = crouch
        hips.eulerAngles = SCNVector3(0, 0, 0)
        torso.eulerAngles = SCNVector3(1.10 - 0.10 * setLift, 0, 0)
        chest.eulerAngles = SCNVector3(0.10, 0, 0)
        headPivot.eulerAngles = SCNVector3(-0.85, 0, 0)

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

        // Arms straight down to the track, shoulder-width, weight over the hands.
        shoulderL.eulerAngles = SCNVector3(-1.30 + 0.08 * setLift, 0, -0.10)
        shoulderR.eulerAngles = SCNVector3(-1.30 + 0.08 * setLift, 0, 0.10)
        elbowL.eulerAngles = SCNVector3(-0.05, 0, 0)
        elbowR.eulerAngles = SCNVector3(-0.05, 0, 0)
    }

    private func poseIdle(time: Double) {
        let t = Float(time)
        hips.position.y = hipHeight - 0.015
        hips.eulerAngles = SCNVector3(0, 0, 0)
        torso.eulerAngles = SCNVector3(0.03 + 0.012 * sin(t * 0.9), 0, 0)
        chest.eulerAngles = SCNVector3(0.02, 0, 0)
        headPivot.eulerAngles = SCNVector3(-0.02, 0.08 * sin(t * 0.5), 0)
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
        hips.eulerAngles = SCNVector3(0, 0, 0)
        torso.eulerAngles = SCNVector3(-0.10, 0, 0)
        chest.eulerAngles = SCNVector3(-0.06, 0, 0)
        headPivot.eulerAngles = SCNVector3(0.32, 0, 0)
        thighL.eulerAngles = SCNVector3(0.03, 0, -0.05); kneeL.eulerAngles = SCNVector3(-0.08, 0, 0)
        thighR.eulerAngles = SCNVector3(-0.03, 0, 0.05); kneeR.eulerAngles = SCNVector3(-0.08, 0, 0)
        ankleL.eulerAngles = SCNVector3(0, 0, 0); ankleR.eulerAngles = SCNVector3(0, 0, 0)
        shoulderL.eulerAngles = SCNVector3(2.95, 0, -0.55 - 0.1 * sin(t * 3))
        shoulderR.eulerAngles = SCNVector3(2.95, 0, 0.55 + 0.1 * sin(t * 3 + 1))
        elbowL.eulerAngles = SCNVector3(-0.35, 0, 0)
        elbowR.eulerAngles = SCNVector3(-0.35, 0, 0)
    }

    private func poseExhausted(time: Double) {
        let t = Float(time)
        hips.position.y = hipHeight - 0.14
        hips.eulerAngles = SCNVector3(0, 0, 0)
        torso.eulerAngles = SCNVector3(0.55 + 0.05 * sin(t * 1.6), 0, 0)   // breathing
        chest.eulerAngles = SCNVector3(0.10 + 0.03 * sin(t * 1.6), 0, 0)
        headPivot.eulerAngles = SCNVector3(-0.18, 0, 0)
        thighL.eulerAngles = SCNVector3(0.35, 0, -0.06); kneeL.eulerAngles = SCNVector3(-0.55, 0, 0)
        thighR.eulerAngles = SCNVector3(0.35, 0, 0.06); kneeR.eulerAngles = SCNVector3(-0.55, 0, 0)
        ankleL.eulerAngles = SCNVector3(0, 0, 0); ankleR.eulerAngles = SCNVector3(0, 0, 0)
        shoulderL.eulerAngles = SCNVector3(-0.65, 0, -0.15)
        shoulderR.eulerAngles = SCNVector3(-0.65, 0, 0.15)
        elbowL.eulerAngles = SCNVector3(-0.35, 0, 0)
        elbowR.eulerAngles = SCNVector3(-0.35, 0, 0)
    }
}
