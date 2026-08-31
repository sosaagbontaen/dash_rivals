import SceneKit

/// Common interface for the two athlete tiers: the procedural v3 figure and the
/// Mixamo-rigged v4 runner. GameController drives either identically.
protocol AthleteFigure: AnyObject {
    var root: SCNNode { get }
    var mode: RunnerFigure.Mode { get set }
    func update(phase: Double, speed: Double, lean: Double, time: Double)
    /// Called from renderer(_:didApplyAnimationsAtTime:) — the only safe point to
    /// layer procedural adjustments (lean/dip) on top of running clips.
    func postAnimationAdjust(lean: Double)
}

extension RunnerFigure: AthleteFigure {
    func postAnimationAdjust(lean: Double) {}   // fully procedural already
}

/// v4 athlete: a Mixamo-rigged skinned mesh (Collada export), animated by the
/// bundled mocap clips with playback slaved to the simulation's stride rate.
final class SkinnedRunner: AthleteFigure {

    // MARK: Template discovery (once, at launch)

    struct Template {
        let characterURL: URL
        let clips: [String: SCNAnimation]          // launch/sprint/crouch/idle/victory/running
        let clipDurations: [String: Double]
    }

    private static func clipKey(for filename: String) -> String? {
        let n = filename.lowercased()
        if n.contains("to sprint") { return "launch" }
        if n.contains("sprint") { return "sprint" }
        if n.contains("crouch") { return "crouch" }
        if n.contains("victory") { return "victory" }
        if n.contains("running") { return "running" }
        if n.contains("idle") { return "idle" }
        return nil
    }

    /// Finds Mixamo files bundled from DashRivals/Assets/Mixamo (flattened into
    /// the bundle root). Returns nil if none are present.
    static func loadTemplate() -> Template? {
        let daeURLs = Bundle.main.urls(forResourcesWithExtension: "dae", subdirectory: nil) ?? []
        guard !daeURLs.isEmpty else { return nil }

        var clipURLs: [String: URL] = [:]
        var characters: [URL] = []
        for url in daeURLs {
            if let key = clipKey(for: url.lastPathComponent) {
                if clipURLs[key] == nil { clipURLs[key] = url }
            } else {
                characters.append(url)
            }
        }
        // Prefer the human; `defaults write com.dashrivals.poc character "y bot"` to swap.
        let pref = (UserDefaults.standard.string(forKey: "character") ?? "remy").lowercased()
        let characterURL = characters.first { $0.lastPathComponent.lowercased().contains(pref) }
            ?? characters.first { !$0.lastPathComponent.lowercased().contains("bot") }
            ?? characters.first
        guard let characterURL else { return nil }

        // Mixamo DAE clips are one <animation> per bone: group them into one clip.
        var clips: [String: SCNAnimation] = [:]
        var durations: [String: Double] = [:]
        for (key, url) in clipURLs {
            guard let source = SCNSceneSource(url: url, options: nil) else { continue }
            let ids = source.identifiersOfEntries(withClass: CAAnimation.self)
            let anims = ids.compactMap { source.entryWithIdentifier($0, withClass: CAAnimation.self) }
            guard !anims.isEmpty else { continue }
            let group = CAAnimationGroup()
            group.animations = anims
            let dur = anims.map { $0.duration }.max() ?? 1
            group.duration = dur
            // Hold the last evaluated pose; without this the rig snaps back to
            // its bind pose (a T-pose flash) whenever a clip ends or is removed.
            group.isRemovedOnCompletion = false
            group.fillMode = .forwards
            for sub in anims {
                sub.isRemovedOnCompletion = false
                sub.fillMode = .forwards
            }
            let anim = SCNAnimation(caAnimation: group)
            anim.repeatCount = key == "launch" ? 1 : .greatestFiniteMagnitude
            anim.isRemovedOnCompletion = false
            anim.blendInDuration = 0.25
            anim.blendOutDuration = 0.25
            clips[key] = anim
            durations[key] = dur
        }
        NSLog("SkinnedRunner: character %@ · clips [%@]",
              characterURL.lastPathComponent, clips.keys.sorted().joined(separator: " "))
        return Template(characterURL: characterURL, clips: clips, clipDurations: durations)
    }

    // MARK: Instance

    let root = SCNNode()
    var mode: RunnerFigure.Mode = .idle {
        didSet { if mode != oldValue { applyMode() } }
    }

    private var players: [String: SCNAnimationPlayer] = [:]
    private var clipDurations: [String: Double] = [:]
    private var currentClip: String? = nil
    private var spine1: SCNNode?
    private var spine1Bind = SCNQuaternion(0, 0, 0, 1)
    private var hipsBone: SCNNode?
    private var characterContainer: SCNNode?
    /// Bones posed by hand for the block start, with their bind orientations.
    private var poseBones: [String: SCNNode] = [:]
    private var poseBind: [String: SCNQuaternion] = [:]
    private var hipsBindY: Float = 0
    /// Measured world metres of ground travel per second of clip playback at
    /// speed 1 — used to match leg turnover to actual ground speed (no skate).
    private var authoredRate: Float = 0
    private var lastDT: Double = 1.0 / 60.0
    private var currentSpeed: Double = 0
    private var leftLegForward = true

    private var hipsBindX: Float = 0      // hips origin in root space, bind pose
    private var hipsBindZ: Float = 0
    private var launchEndsAt: Double = -1
    private var lastTime: Double = 0

    /// Fresh scene load per athlete so each instance owns its own skeleton
    /// (cloned skinners share bones — the classic SceneKit trap).
    init?(athlete: Athlete, template: Template) {
        guard let scene = try? SCNScene(url: template.characterURL,
                                        options: [.checkConsistency: false]) else { return nil }
        let container = SCNNode()
        for child in scene.rootNode.childNodes {
            container.addChildNode(child)
        }

        // Mixamo units are centimeters; normalize to a ~1.85m athlete.
        let (minB, maxB) = container.boundingBox
        let height = maxB.y - minB.y
        if height > 0.01 {
            let s = 1.85 / height
            container.scale = SCNVector3(s, s, s)
        }
        root.addChildNode(container)

        clipDurations = template.clipDurations
        for (key, anim) in template.clips {
            let player = SCNAnimationPlayer(animation: anim)
            player.stop()
            container.addAnimationPlayer(player, forKey: key)
            players[key] = player
        }

        spine1 = Self.findNode(in: container, suffix: "Spine1")
        if let s = spine1 { spine1Bind = s.orientation }
        characterContainer = container
        for name in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
                     "LeftShoulder", "RightShoulder", "LeftArm", "RightArm",
                     "LeftForeArm", "RightForeArm",
                     "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg",
                     "LeftFoot", "RightFoot"] {
            if let n = Self.findNode(in: container, suffix: name) {
                poseBones[name] = n
                poseBind[name] = n.orientation
            }
        }
        hipsBone = Self.findNode(in: container, suffix: "Hips")
        if let h = hipsBone {
            // Where the hips sit in root space at bind pose — the anchor the
            // root-motion compensation holds them to every frame.
            let bind = root.convertPosition(SCNVector3Zero, from: h)
            hipsBindX = bind.x
            hipsBindZ = bind.z
            hipsBindY = h.position.y
        }

        // Kit tint by material name (Remy: Topmat/Bottommat/Shoesmat;
        // Y Bot: Alpha_Body_MAT). Skin, hair and eyes stay untouched.
        container.enumerateHierarchy { node, _ in
            for m in node.geometry?.materials ?? [] {
                let name = (m.name ?? "").lowercased()
                if name.contains("top") || name.contains("alpha_body") {
                    m.multiply.contents = athlete.kitPrimary
                } else if name.contains("bottom") {
                    m.multiply.contents = athlete.kitSecondary
                } else if name.contains("shoes") {
                    m.multiply.contents = athlete.shoeColor
                }
            }
        }
        leftLegForward = athlete.bib.count % 2 == 0
        applyMode()
    }

    private static func findNode(in node: SCNNode, suffix: String) -> SCNNode? {
        var found: SCNNode? = nil
        node.enumerateHierarchy { n, stop in
            if let name = n.name, name.hasSuffix(suffix) {
                found = n
                stop.pointee = true
            }
        }
        return found
    }

    // MARK: Mode → clip

    private func applyMode() {
        let key: String?
        switch mode {
        case .running, .decel:
            // Explode out of the crouch with the transition clip, then loop the sprint.
            if launchEndsAt < 0, players["launch"] != nil, mode == .running {
                key = "launch"
                launchEndsAt = lastTime + (clipDurations["launch"] ?? 0.8) / 1.25
            } else {
                key = players["sprint"] != nil ? "sprint" : "running"
            }
        case .idle: key = "idle"
        case .blocks, .set:
            // Mixamo has no track block start — "Crouching Idle" is a stealth
            // crouch with the hips at standing height. Keep it attached only so
            // the animation pass runs, then override every bone by hand.
            key = players["crouch"] != nil ? "crouch" : "idle"
        case .celebrate: key = players["victory"] != nil ? "victory" : "idle"
        case .exhausted: key = players["crouch"] != nil ? "crouch" : "idle"
        }
        setClip(key)
    }

    private func setClip(_ key: String?) {
        guard key != currentClip else { return }
        // Start the incoming clip first, then blend the outgoing one away, so the
        // rig is never left with nothing driving it (that gap renders as a T-pose).
        if let k = key, let p = players[k] {
            if k == "launch" { p.speed = 1.25 }
            p.play()
        }
        if key == nil {
            // Hand-posed modes: every clip must be fully detached, otherwise the
            // held animation pose (fillMode .forwards) overrides model writes.
            for (_, p) in players { p.stop() }
        } else if let old = currentClip, let p = players[old] {
            p.stop(withBlendOutDuration: 0.25)
        }
        currentClip = key
    }

    /// Ready the figure for a new race (lets the launch clip fire again).
    func resetForRace() {
        launchEndsAt = -1
    }

    // MARK: Per-frame

    func update(phase: Double, speed: Double, lean: Double, time: Double) {
        lastDT = max(1.0 / 240.0, min(0.1, time - lastTime))
        lastTime = time
        currentSpeed = speed
        if currentClip == "launch", time >= launchEndsAt, mode == .running || mode == .decel {
            setClip(players["sprint"] != nil ? "sprint" : "running")
        }
        // Match leg turnover to real ground speed. The Sprint clip is authored at
        // ~12.2 m/s of travel per cycle; playing it faster than the body actually
        // moves is what makes a sprint read as frantic jogging (foot skate).
        if let clip = currentClip, clip == "sprint" || clip == "running", let p = players[clip] {
            if authoredRate > 0.5 {
                // Exact foot-lock would need speed/authoredRate. Mixamo's "Sprint"
                // only covers ~1.6m per step (a jog stride), so an exact match runs
                // the legs at ~6 steps/s — the frantic look. Cap at a real sprint
                // cadence (~4.9 steps/s) and accept a little slide at top speed.
                let target = Float(speed) / authoredRate
                p.speed = CGFloat(max(0.75, min(1.30, target)))
            } else {
                p.speed = 1.0        // until the first calibration lands
            }
        }
        // New race begins when we go back to the blocks.
        if mode == .blocks { launchEndsAt = -1 }
    }

    /// Post-animation fixups, applied after clips are evaluated each frame.
    func postAnimationAdjust(lean: Double) {
        // Hand-authored block start: no clip is driving the rig in these modes,
        // so model-space bone writes stick.
        if mode == .blocks || mode == .set {
            poseBlockStart(setLift: mode == .set ? 1 : 0)
            return
        }

        if let hips = hipsBone, let container = characterContainer {
            // Measure where the hips actually landed this frame (presentation node —
            // the model node never sees animated values) and slide the un-animated
            // container back by the drift, so the mesh stays locked to its lane
            // position and the simulation owns every meter of travel.
            let hw = hips.presentation.worldPosition
            let rw = root.presentation.worldPosition
            let driftX = (hw.x - rw.x) - hipsBindX
            let driftZ = (hw.z - rw.z) - hipsBindZ
            if driftX.isFinite, driftZ.isFinite {
                var p = container.position
                p.x -= driftX
                p.z -= driftZ
                container.position = p

                // Self-calibrate the clip's authored ground speed: this frame's
                // drift is exactly how far the animation travelled, so
                // rate = drift / (dt · playbackSpeed) world metres per clip-second.
                if mode == .running, currentClip == "sprint", currentSpeed > 4,
                   let player = players["sprint"], player.speed > 0.01 {
                    let rate = driftZ / (Float(lastDT) * Float(player.speed))
                    if rate > 2, rate < 40 {
                        authoredRate = authoredRate == 0 ? rate : authoredRate * 0.9 + rate * 0.1
                    }
                }
            }
        }
        // Layer the drive lean / finish dip on the spine.
        guard mode == .running || mode == .decel, let s = spine1 else { return }
        let pitch = Float(max(0, lean - 0.20)) * 0.9
        guard pitch > 0.01 else { return }
        let delta = SCNQuaternion(sin(pitch / 2), 0, 0, cos(pitch / 2))
        s.orientation = SCNQuaternion.multiply(spine1Bind, delta)
    }

    // MARK: Block start (posed by hand — Mixamo has no track start)

    private func axisQ(_ x: Float, _ y: Float, _ z: Float, _ angle: Float) -> SCNQuaternion {
        let h = angle / 2, s = sin(h)
        return SCNQuaternion(x * s, y * s, z * s, cos(h))
    }

    /// Rotate a bone by pitch/yaw/roll in its parent's frame, relative to bind.
    private func poseBone(_ name: String, pitch: Float = 0, yaw: Float = 0, roll: Float = 0) {
        guard let n = poseBones[name], let bind = poseBind[name] else { return }
        var q = SCNQuaternion(0, 0, 0, 1)
        if pitch != 0 { q = SCNQuaternion.multiply(q, axisQ(1, 0, 0, pitch)) }
        if yaw != 0 { q = SCNQuaternion.multiply(q, axisQ(0, 1, 0, yaw)) }
        if roll != 0 { q = SCNQuaternion.multiply(q, axisQ(0, 0, 1, roll)) }
        n.orientation = SCNQuaternion.multiply(q, bind)
    }

    /// Four-point sprint start. setLift 0 = "on your marks" (hips low),
    /// 1 = "set" (hips above the shoulders, weight over the hands).
    private func poseBlockStart(setLift: Float) {
        let lift = max(0, min(1, setLift))
        // Hips drop and tip forward; on "set" they rise above the shoulders.
        if let h = hipsBone {
            h.position.y = hipsBindY * (0.60 + 0.09 * lift)
        }
        poseBone("Hips", pitch: 1.32 - 0.16 * lift)
        poseBone("Spine", pitch: -0.16)
        poseBone("Spine1", pitch: -0.14)
        poseBone("Spine2", pitch: -0.10)
        poseBone("Neck", pitch: -0.55)
        poseBone("Head", pitch: -0.40)

        // Front leg tucked under the chest, back leg driven into the rear pedal.
        let front = leftLegForward ? "Left" : "Right"
        let back = leftLegForward ? "Right" : "Left"
        poseBone("\(front)UpLeg", pitch: -1.70 + 0.12 * lift)
        poseBone("\(front)Leg", pitch: 1.55 - 0.30 * lift)
        poseBone("\(front)Foot", pitch: 0.55)
        poseBone("\(back)UpLeg", pitch: -1.05 + 0.30 * lift)
        poseBone("\(back)Leg", pitch: 1.45 - 0.45 * lift)
        poseBone("\(back)Foot", pitch: 0.70)

        // Arms drop vertically to the line: counter the torso's forward pitch.
        poseBone("LeftArm", pitch: -1.15, roll: 1.50)
        poseBone("RightArm", pitch: -1.15, roll: -1.50)
        poseBone("LeftForeArm", pitch: -0.12)
        poseBone("RightForeArm", pitch: -0.12)
    }
}

private extension SCNQuaternion {
    static func multiply(_ a: SCNQuaternion, _ b: SCNQuaternion) -> SCNQuaternion {
        SCNQuaternion(
            a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
            a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
            a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
        )
    }
}
