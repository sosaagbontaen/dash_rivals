import SceneKit
import simd

/// Common interface for the two athlete tiers: the procedural v3 figure and the
/// Mixamo-rigged v4 runner. GameController drives either identically.
protocol AthleteFigure: AnyObject {
    var root: SCNNode { get }
    var mode: RunnerFigure.Mode { get set }
    func update(phase: Double, speed: Double, lean: Double, time: Double)
    /// Called from renderer(_:didApplyAnimationsAtTime:) — the only safe point to
    /// layer procedural adjustments (lean/dip) on top of running clips.
    func postAnimationAdjust(lean: Double)
    /// Full-flight fire/smoke off the spikes. 0 = off. speedFactor slaves the
    /// particle clock to the world's (slow-mo finish, replay).
    func setFlight(intensity: Float, speedFactor: Float)
}

extension RunnerFigure: AthleteFigure {
    func postAnimationAdjust(lean: Double) {}   // fully procedural already
    func setFlight(intensity: Float, speedFactor: Float) {}
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
        if n.contains("fast run") || n.contains("sprint") { return "sprint" }
        if n.contains("plank") || n.contains("start") { return "start" }
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
                // A "Fast Run" download supersedes the stock Sprint clip.
                let preferred = url.lastPathComponent.lowercased().contains("fast run")
                if clipURLs[key] == nil || preferred { clipURLs[key] = url }
            } else {
                characters.append(url)
            }
        }
        // Always prefer a real human mesh. (The Y Bot mannequin doesn't bind
        // correctly to these clips yet — its limbs detach — so it is not offered.)
        let characterURL = characters.first { !$0.lastPathComponent.lowercased().contains("bot") }
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
            if key == "start" {
                // The block start is a *held frame* of real mocap, not a cycle:
                // frame 38 = "on your marks" (hips low), frame 52 = "set"
                // (hips up, hands planted). Frames chosen by running forward
                // kinematics over every frame of the clip and picking the poses
                // with the hands on the track and the feet split behind them.
                for (variant, frame) in [("startMarks", 38.0), ("startSet", 52.0)] {
                    guard let copy = group.copy() as? CAAnimationGroup else { continue }
                    copy.timeOffset = frame / 30.0
                    copy.isRemovedOnCompletion = false
                    copy.fillMode = .forwards
                    let held = SCNAnimation(caAnimation: copy)
                    held.repeatCount = .greatestFiniteMagnitude
                    held.isRemovedOnCompletion = false
                    held.blendInDuration = 0.2
                    held.blendOutDuration = 0.2
                    clips[variant] = held
                    durations[variant] = dur
                }
                continue
            }
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
        didSet {
            guard mode != oldValue else { return }
            if mode == .running, oldValue == .set || oldValue == .blocks,
               let h = hipsBone {
                // The block pose parks the hips ~0.25m behind where the launch
                // clip's hips land; carry that offset into the compensation and
                // decay it, so the gun drives the body out rather than snapping it.
                let hw = h.presentation.worldPosition
                let rw = root.presentation.worldPosition
                launchAnchorX = (hw.x - rw.x) - hipsBindX
                launchAnchorZ = (hw.z - rw.z) - hipsBindZ
                runStart = lastTime
            }
            applyMode()
        }
    }
    private var launchAnchorX: Float = 0
    private var launchAnchorZ: Float = 0
    private var leanRamp: Float = 0
    private var runStart: Double = -10

    // Full-flight FX: one emitter node per foot, parented to the (unscaled)
    // root and re-seated on the toe bone every frame. Particles are world-space.
    private var flightNodes: [SCNNode] = []
    private var flames: [SCNParticleSystem] = []
    private var smokes: [SCNParticleSystem] = []
    private var flightIntensity: Float = 0

    func setFlight(intensity: Float, speedFactor: Float) {
        if flightNodes.isEmpty {
            guard intensity > 0 else { return }
            for _ in 0..<2 {
                let n = SCNNode()
                let f = LaneFX.flame(), sm = LaneFX.smoke()
                n.addParticleSystem(f)
                n.addParticleSystem(sm)
                root.addChildNode(n)
                flightNodes.append(n); flames.append(f); smokes.append(sm)
            }
        }
        flightIntensity = intensity
        for f in flames { f.birthRate = CGFloat(340 * intensity); f.speedFactor = CGFloat(max(0.05, speedFactor)) }
        for sm in smokes { sm.birthRate = CGFloat(55 * intensity); sm.speedFactor = CGFloat(max(0.05, speedFactor)) }
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
    /// Measured foot travel per step, relative to the body (metres). This is the
    /// clip's real stride length, and it is what ground speed must be matched to.
    private var footExcursion: Float = 0
    private var footMin: Float = 0
    private var footMax: Float = 0
    /// How much to exaggerate thigh swing (1 = raw clip).
    private let strideBoost: Float = SkinnedRunner.strideBoostArg
#if DEBUG
    static let dipProbe = CommandLine.arguments.contains("-dipprobe")
#endif
    /// Overridable so the stride boost can be A/B'd from the command line.
    static let strideBoostArg: Float = {
        if let i = CommandLine.arguments.firstIndex(of: "-stride"), i + 1 < CommandLine.arguments.count,
           let v = Float(CommandLine.arguments[i + 1]) { return v }
        return 1.85
    }()
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

        // Normalize every rig to a ~1.85m athlete. Bounding boxes are unreliable
        // here (they vary with each export's hierarchy), but the hips bone is
        // consistent: a humanoid's hips sit at ~54% of standing height.
        let hips0 = Self.findNode(in: container, suffix: "Hips")
        let hipY = hips0?.position.y ?? 0
        if hipY > 0.01 {
            let s = Float(1.85 * 0.54) / hipY
            container.scale = SCNVector3(s, s, s)
            // Hinge leans about the hips, not the feet. The pivot shifts the mesh
            // down by the same amount, so position adds it straight back.
            container.pivot = SCNMatrix4MakeTranslation(0, hipY, 0)
            container.position = SCNVector3(0, hipY * s, 0)
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
                     "LeftForeArm", "RightForeArm", "LeftHand", "RightHand",
                     "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg",
                     "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"] {
            if let n = Self.findNode(in: container, suffix: name) {
                poseBones[name] = n
                poseBind[name] = n.orientation
            }
        }
        // The block poses as container-level clips, authored in the same shape
        // as the mocap groups (one sub-animation per bone, same key paths), so
        // setClip crossfades marks -> set -> launch instead of cutting. A pose
        // held on the bones themselves can't blend with a container clip.
        if let ref = template.clips["sprint"] ?? template.clips["running"] ?? template.clips["launch"] {
            for (key, pose, hips) in [("poseMarks", BlockPose.marks, BlockPose.marksHips),
                                      ("poseSet", BlockPose.set, BlockPose.setHips)] {
                guard let clip = Self.makePoseClip(like: ref, pose: pose, hipsPosition: hips, in: container) else { continue }
                let player = SCNAnimationPlayer(animation: clip)
                player.stop()
                container.addAnimationPlayer(player, forKey: key)
                players[key] = player
                clipDurations[key] = 1
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

    /// One-second constant clip holding `pose`: every bone the reference clip
    /// animates gets a keyframe animation on the same key path, valued at the
    /// pose (or the bone's bind transform when the pose doesn't list it, which
    /// is what keeps fingers straight on the track).
    private static func makePoseClip(like ref: SCNAnimation, pose: [(String, SCNQuaternion)],
                                     hipsPosition: SCNVector3, in container: SCNNode) -> SCNAnimation? {
        guard let group = CAAnimation(scnAnimation: ref) as? CAAnimationGroup,
              let subs = group.animations else { return nil }
        let quats = Dictionary(pose.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        var out: [CAAnimation] = []
        for sub in subs {
            guard let kp = (sub as? CAPropertyAnimation)?.keyPath, kp.hasSuffix(".transform") else { continue }
            // "/mixamorig:Hips.transform" -> "mixamorig:Hips"
            let nodeName = String(kp.dropLast(".transform".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let node = findNode(in: container, suffix: nodeName) else { continue }
            var m = node.transform
            // Rigs name bones "mixamorig:Hips" or "mixamorig_Hips"; match the
            // pose's short name at a ':' or '_' boundary.
            let short = quats.keys.first { name in
                nodeName.hasSuffix(name) && (nodeName.count == name.count
                    || [":", "_"].contains(nodeName[nodeName.index(nodeName.endIndex, offsetBy: -name.count - 1)]))
            }
            if let short, let q = quats[short] {
                var t = SCNMatrix4(simd_float4x4(simd_quatf(ix: q.x, iy: q.y, iz: q.z, r: q.w)))
                let p = short == "Hips" ? hipsPosition : node.position
                t.m41 = p.x; t.m42 = p.y; t.m43 = p.z
                m = t
            }
            let a = CAKeyframeAnimation(keyPath: kp)
            a.values = [NSValue(scnMatrix4: m), NSValue(scnMatrix4: m)]
            a.keyTimes = [0, 1]
            a.duration = 1
            a.isRemovedOnCompletion = false
            a.fillMode = .forwards
            out.append(a)
        }
        guard !out.isEmpty else { return nil }
        let g = CAAnimationGroup()
        g.animations = out
        g.duration = 1
        g.isRemovedOnCompletion = false
        g.fillMode = .forwards
        let anim = SCNAnimation(caAnimation: g)
        anim.repeatCount = .greatestFiniteMagnitude
        anim.isRemovedOnCompletion = false
        anim.blendInDuration = 0.2
        anim.blendOutDuration = 0.25
        return anim
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
                // Cut it short: the clip finishes nearly upright, and the sprint
                // clip plus the drive lean carry the rest.
                launchEndsAt = lastTime + min(0.26, (clipDurations["launch"] ?? 0.8) / 1.25)
            } else {
                key = players["sprint"] != nil ? "sprint" : "running"
            }
        case .idle: key = "idle"
        case .blocks: key = players["poseMarks"] != nil ? "poseMarks" : nil
        case .set: key = players["poseSet"] != nil ? "poseSet" : nil
        case .celebrate: key = players["victory"] != nil ? "victory" : "idle"
        // Not the "crouch" clip: Mixamo's Crouching Idle is a combat squat, and
        // eight athletes dropping into it at the line reads as a second block start.
        case .exhausted: key = "idle"
        }
        // Root-motion compensation leaves the container wherever the last race
        // ended; the block poses are authored against a zeroed container.
        if mode == .blocks, let c = characterContainer {
            c.position.x = 0
            c.position.z = 0
            c.eulerAngles.x = 0
            leanRamp = 0
        }
        setClip(key)
        if (mode == .blocks || mode == .set), key == nil {
            applyBlockPose(setLift: mode == .set ? 1 : 0)   // no reference clip: bone-level fallback
        } else {
            for (_, bone) in poseBones { bone.removeAnimation(forKey: "blockPose") }
            hipsBone?.removeAnimation(forKey: "blockPoseY")
        }
    }

    private func setClip(_ key: String?) {
        guard key != currentClip else { return }
        // SceneKit's blendIn/blendOut never crossfaded these clips (measured as
        // one-frame cuts), so the fade is driven by hand: the incoming player is
        // re-added so it evaluates last, then its blendFactor ramps 0 -> 1 over
        // the outgoing player at full weight, which stops when the ramp ends.
        if let k = key, let p = players[k], let c = characterContainer {
            if k == "launch" { p.speed = 1.25 }
            if k.hasPrefix("start") { p.speed = 0 }   // hold the frame
            c.removeAnimation(forKey: k)
            c.addAnimationPlayer(p, forKey: k)
            p.blendFactor = 0
            p.play()
            fadeIn = p
            fadeOut = currentClip.flatMap { players[$0] }
            fadeStart = lastTime
        }
        if key == nil {
            // Hand-posed modes: every clip must be fully detached, otherwise the
            // held animation pose (fillMode .forwards) overrides model writes.
            for (_, p) in players { p.stop() }
            fadeIn = nil; fadeOut = nil
        }
        currentClip = key
    }

    private var fadeIn: SCNAnimationPlayer?
    private var fadeOut: SCNAnimationPlayer?
    private var fadeStart: Double = 0
    private let fadeDuration: Double = 0.22

    private func stepCrossfade(time: Double) {
        guard let incoming = fadeIn else { return }
        let f = CGFloat(max(0, min(1, (time - fadeStart) / fadeDuration)))
        incoming.blendFactor = f
        if f >= 1 {
            fadeOut?.stop()
            fadeOut?.blendFactor = 1
            fadeIn = nil; fadeOut = nil
        }
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
        stepCrossfade(time: time)
        if currentClip == "launch", time >= launchEndsAt, mode == .running || mode == .decel {
            setClip(players["sprint"] != nil ? "sprint" : "running")
        }
        // Pace so the planted foot stays still: over one cycle the body travels
        // two strides, so cadence = v / (2 · stride). Clamp in *cadence*, not in
        // playback ratio — clip lengths differ (Overdrive shortens the cycle),
        // and a fixed ratio would silently become 9 steps/s on a short clip.
        if let clip = currentClip, clip == "sprint" || clip == "running", let p = players[clip] {
            let dur = clipDurations[clip] ?? 0.5
            let stride = footExcursion > 0.5 ? Double(footExcursion) : 1.2
            let wanted = speed / (2 * stride)                  // cycles per second
            let cadence = max(1.2, min(2.7, wanted))           // ~2.4-5.4 steps/s
            p.speed = CGFloat(max(0.3, min(2.2, cadence * dur)))
        }
        // New race begins when we go back to the blocks.
        if mode == .blocks { launchEndsAt = -1 }
    }

    /// Post-animation fixups, applied after clips are evaluated each frame.
    func postAnimationAdjust(lean: Double) {
        // Hand-authored block start: no clip is driving the rig in these modes,
        // so model-space bone writes stick.
        if mode == .blocks || mode == .set {
            return
        }

        if let hips = hipsBone, let container = characterContainer {
            // Measure where the hips actually landed this frame (presentation node —
            // the model node never sees animated values) and slide the un-animated
            // container back by the drift, so the mesh stays locked to its lane
            // position and the simulation owns every meter of travel.
            let hw = hips.presentation.worldPosition
            let rw = root.presentation.worldPosition
            let k = Float(exp(-lastDT / 0.16))
            launchAnchorX *= k
            launchAnchorZ *= k
            let driftX = (hw.x - rw.x) - (hipsBindX + launchAnchorX)
            let driftZ = (hw.z - rw.z) - (hipsBindZ + launchAnchorZ)
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
        if flightIntensity > 0, flightNodes.count == 2,
           let lt = poseBones["LeftToeBase"], let rt = poseBones["RightToeBase"] {
            flightNodes[0].position = root.convertPosition(lt.presentation.worldPosition, from: nil)
            flightNodes[1].position = root.convertPosition(rt.presentation.worldPosition, from: nil)
        }
        // Exaggerate the leg swing. Mixamo's run cycles carry a short stride
        // (~0.9 m/step); a sprinter at 11 m/s needs ~2.2 m. Amplifying each
        // thigh's rotation away from its bind pose lengthens the visual stride,
        // which the pacing below then converts into slower, longer strides.
        if mode == .running || mode == .decel {
            for name in ["LeftUpLeg", "RightUpLeg"] {
                amplify(name, by: strideBoost)
            }
            for name in ["LeftLeg", "RightLeg"] {
                amplify(name, by: 1 + (strideBoost - 1) * 0.45)
            }
        }

        // Measure the clip's stride: how far the foot travels front-to-back
        // relative to the body. Envelope followers decay slowly so the window
        // tracks a full cycle without collapsing.
        if mode == .running, let foot = poseBones["LeftFoot"] {
            let rel = foot.presentation.worldPosition.z - root.presentation.worldPosition.z
            let decay = Float(lastDT) * 0.12
            footMin = min(rel, footMin + decay)
            footMax = max(rel, footMax - decay)
            let span = footMax - footMin
            if span > 0.5, span < 4 {
                footExcursion = footExcursion == 0 ? span : footExcursion * 0.95 + span * 0.05
#if DEBUG
                if SkinnedRunner.dipProbe { print(String(format: "STRIDE k=%.2f excursion=%.3f", strideBoost, footExcursion)) }
#endif
            }
        }

        // Drive lean and finish dip. These have to live on the container, not the
        // spine: a clip owns every bone it animates, and neither a model write nor
        // a held bone animation displaces it (both measured as exact no-ops on the
        // head's world position). The container is the one node no clip touches -
        // it is what root-motion compensation already steers - and its pivot sits
        // at hip height, so the body hinges at the waist rather than the feet.
        guard mode == .running || mode == .decel else {
            characterContainer?.eulerAngles.x = 0
            return
        }
        // The launch clip carries its own drive posture; stacking a whole-body
        // pitch on its crouch put heads on the track. Hold off until the sprint
        // clip takes over, then ease the lean in.
        if currentClip == "launch" {
            leanRamp = 0
        } else {
            leanRamp = min(1, leanRamp + Float(lastDT) / 0.45)
        }
        let pitch = min(0.5, Float(max(0, lean - 0.20)) * 1.0) * leanRamp
        characterContainer?.eulerAngles.x = pitch
#if DEBUG
        if SkinnedRunner.dipProbe, let head = poseBones["Head"], let hips = hipsBone {
            let h = head.presentation.worldPosition
            let hp = hips.presentation.worldPosition
            print(String(format: "HEAD pitch=%.2f dz=%.3f dy=%.3f", pitch, h.z - hp.z, h.y - hp.y))
        }
#endif
    }

    /// Scale a bone's animated rotation away from its bind pose.
    private func amplify(_ name: String, by k: Float) {
        guard let n = poseBones[name], let bind = poseBind[name] else { return }
        let bindQ = simd_quatf(ix: bind.x, iy: bind.y, iz: bind.z, r: bind.w)
        let cur = n.presentation.orientation
        let curQ = simd_quatf(ix: cur.x, iy: cur.y, iz: cur.z, r: cur.w)
        let delta = curQ * bindQ.inverse
        let angle = delta.angle
        guard angle > 0.001, angle.isFinite else { return }
        let axis = delta.axis
        guard axis.x.isFinite, axis.y.isFinite, axis.z.isFinite else { return }
        let boosted = simd_quatf(angle: angle * k, axis: axis) * bindQ
        n.orientation = SCNQuaternion(boosted.imag.x, boosted.imag.y, boosted.imag.z, boosted.real)

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

    /// Four-point sprint start: the Start Plank mocap sampled bone-by-bone
    /// (see BlockPose.swift) and held as pose animations. Model-transform writes
    /// to skinned bones are ignored by SceneKit, and it won't evaluate a clip at
    /// speed 0, so a held frame has to be replayed as data.
    private func applyBlockPose(setLift: Float) {
        let pose = setLift > 0.5 ? BlockPose.set : BlockPose.marks
        let hipsPos = setLift > 0.5 ? BlockPose.setHips : BlockPose.marksHips

        for (name, orientation) in pose {
            guard let bone = poseBones[name] else { continue }
            let a = CABasicAnimation(keyPath: "orientation")
            a.fromValue = NSValue(scnVector4: orientation)
            a.toValue = NSValue(scnVector4: orientation)
            a.duration = 1e8
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
            bone.removeAnimation(forKey: "blockPose")
            bone.addAnimation(a, forKey: "blockPose")
        }

        if let hips = hipsBone {
            let a = CABasicAnimation(keyPath: "position")
            a.fromValue = NSValue(scnVector3: hipsPos)
            a.toValue = NSValue(scnVector3: hipsPos)
            a.duration = 1e8
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
            hips.removeAnimation(forKey: "blockPoseY")
            hips.addAnimation(a, forKey: "blockPoseY")
        }
    }

#if DEBUG
    /// Per-frame shape of the athlete across the gun: is the set -> launch ->
    /// sprint hand-off a curve or a step?
    func gunProbe() -> String? {
        guard mode == .set || (mode == .running && lastTime - runStart < 1.6),
              let head = poseBones["Head"], let hips = hipsBone else { return nil }
        let h = head.presentation.worldPosition, p = hips.presentation.worldPosition
        let rw = root.presentation.worldPosition
        return String(format: "t=%.3f mode=%@ clip=%@ headY=%.3f hipsY=%.3f hipsZ=%+.3f pitch=%.2f",
                      lastTime - runStart, "\(mode)", currentClip ?? "-", h.y, p.y, p.z - rw.z,
                      characterContainer?.eulerAngles.x ?? 0)
    }

    /// Where the feet actually land in the held block pose, world space. The
    /// pose is driven by animations, so only the presentation nodes carry it.
    /// This is what the starting-block pedals are placed from.
    func footProbe() -> String? {
        guard mode == .blocks || mode == .set else { return nil }
        let rw = root.presentation.worldPosition
        var out = String(format: "mode=%@ root x=%.3f z=%.3f", "\(mode)", rw.x, rw.z)
        for n in ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightLeg", "RightFoot", "RightToeBase"] {
            guard let b = poseBones[n] else { out += " | \(n)=MISSING"; continue }
            let w = b.presentation.worldPosition
            let sc = b.presentation.scale
            out += String(format: " | %@ dx=%.3f z=%.3f y=%.3f s=%.2f", n, w.x - rw.x, w.z, w.y, sc.y)
        }
        return out
    }
#endif
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
