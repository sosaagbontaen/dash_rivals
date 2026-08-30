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
            let anim = SCNAnimation(caAnimation: group)
            anim.repeatCount = key == "launch" ? 1 : .greatestFiniteMagnitude
            anim.blendInDuration = 0.15
            anim.blendOutDuration = 0.15
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
        case .blocks, .set: key = players["crouch"] != nil ? "crouch" : "idle"
        case .celebrate: key = players["victory"] != nil ? "victory" : "idle"
        case .exhausted: key = players["crouch"] != nil ? "crouch" : "idle"
        }
        setClip(key)
    }

    private func setClip(_ key: String?) {
        guard key != currentClip else { return }
        if let old = currentClip, let p = players[old] { p.stop(withBlendOutDuration: 0.15) }
        if let k = key, let p = players[k] {
            if k == "launch" { p.speed = 1.25 }
            p.play()
            currentClip = k
        } else {
            currentClip = nil
        }
    }

    /// Ready the figure for a new race (lets the launch clip fire again).
    func resetForRace() {
        launchEndsAt = -1
    }

    // MARK: Per-frame

    func update(phase: Double, speed: Double, lean: Double, time: Double) {
        lastTime = time
        if currentClip == "launch", time >= launchEndsAt, mode == .running || mode == .decel {
            setClip(players["sprint"] != nil ? "sprint" : "running")
        }
        // Slave the mocap cycle to the simulation stride rate (clip = one cycle).
        if let clip = currentClip, clip == "sprint" || clip == "running", let p = players[clip] {
            let strideFreq = 1.7 + 1.1 * (speed / 12.0)     // cycles/sec, matches engine
            let dur = clipDurations[clip] ?? 0.7
            p.speed = CGFloat(max(0.35, strideFreq * dur))
        }
        // New race begins when we go back to the blocks.
        if mode == .blocks { launchEndsAt = -1 }
    }

    /// Layer the drive lean / finish dip on the spine after clips are evaluated.
    func postAnimationAdjust(lean: Double) {
        guard mode == .running || mode == .decel, let s = spine1 else { return }
        let pitch = Float(max(0, lean - 0.20)) * 0.9
        guard pitch > 0.01 else { return }
        let delta = SCNQuaternion(sin(pitch / 2), 0, 0, cos(pitch / 2))
        s.orientation = SCNQuaternion.multiply(spine1Bind, delta)
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
