import SceneKit

/// Common interface for the two athlete tiers: the procedural v3 figure and the
/// Mixamo-rigged v4 runner. GameController drives either identically.
protocol AthleteFigure: AnyObject {
    var root: SCNNode { get }
    var mode: RunnerFigure.Mode { get set }
    func update(phase: Double, speed: Double, lean: Double, time: Double)
    /// Called from renderer(_:didApplyAnimations:) — the only safe point to
    /// layer procedural adjustments (lean/dip) on top of running clips.
    func postAnimationAdjust(lean: Double)
}

extension RunnerFigure: AthleteFigure {
    func postAnimationAdjust(lean: Double) {}   // fully procedural already
}

/// v4 athlete: a Mixamo-rigged skinned mesh, animated by the bundled mocap clips
/// (sprint/run/idle/crouch/victory) with clip speed slaved to the simulation's
/// stride rate, plus bone-level tweaks for the race choreography.
final class SkinnedRunner: AthleteFigure {

    // MARK: Template discovery (once, at launch)

    struct Template {
        let characterScene: SCNScene
        let clips: [String: SCNAnimationPlayer]    // keys: sprint/running/idle/crouch/victory
    }

    /// Finds Mixamo files bundled from DashRivals/Assets/Mixamo. Returns nil if
    /// none are present (the game then uses procedural figures).
    static func loadTemplate() -> Template? {
        let exts = ["dae", "usdz", "scn"]
        var urls: [URL] = []
        for ext in exts {
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        }
        guard !urls.isEmpty else { return nil }

        let clipKeys = ["sprint", "running", "idle", "crouch", "victory"]
        var clipURLs: [String: URL] = [:]
        var characterURL: URL? = nil
        for url in urls {
            let name = url.lastPathComponent.lowercased()
            if let key = clipKeys.first(where: { name.contains($0) }) {
                if clipURLs[key] == nil { clipURLs[key] = url }
            } else if characterURL == nil {
                characterURL = url
            }
        }
        // A lone animation file can double as the character (it carries the skin).
        guard let charURL = characterURL ?? clipURLs["sprint"] ?? clipURLs.values.first,
              let scene = try? SCNScene(url: charURL, options: [.checkConsistency: false])
        else { return nil }

        var clips: [String: SCNAnimationPlayer] = [:]
        for (key, url) in clipURLs {
            if let player = Self.firstAnimationPlayer(inSceneAt: url) {
                player.animation.usesSceneTimeBase = false
                player.animation.repeatCount = .infinity
                clips[key] = player
            }
        }
        NSLog("SkinnedRunner: loaded template %@ with clips %@",
              charURL.lastPathComponent, clips.keys.sorted().joined(separator: ","))
        return Template(characterScene: scene, clips: clips)
    }

    private static func firstAnimationPlayer(inSceneAt url: URL) -> SCNAnimationPlayer? {
        guard let scene = try? SCNScene(url: url, options: [.checkConsistency: false]) else { return nil }
        var found: SCNAnimationPlayer? = nil
        scene.rootNode.enumerateHierarchy { node, stop in
            if let key = node.animationKeys.first,
               let player = node.animationPlayer(forKey: key) {
                found = player
                stop.pointee = true
            }
        }
        return found
    }

    // MARK: Instance

    let root = SCNNode()
    var mode: RunnerFigure.Mode = .idle {
        didSet { if mode != oldValue { applyMode() } }
    }

    private var skeletonRoot: SCNNode?          // mixamorig hips
    private var spine1: SCNNode?
    private var spine1Bind = SCNQuaternion(0, 0, 0, 1)
    private var players: [String: SCNAnimationPlayer] = [:]
    private var currentClip: String? = nil
    private var extraLean: Float = 0            // dip / drive layering

    init(athlete: Athlete, template: Template) {
        // Clone the whole character (clone() shares geometry; skinner follows).
        let character = template.characterScene.rootNode.clone()
        // Mixamo rigs are authored in centimeters; normalize to ~1.85m tall.
        let (minB, maxB) = character.boundingBox
        let height = maxB.y - minB.y
        if height > 0.01 {
            let s = 1.85 / height
            character.scale = SCNVector3(s, s, s)
        }
        root.addChildNode(character)

        // Find key bones (Collada import may swap ':' for '_').
        skeletonRoot = Self.findBone(in: character, suffix: "Hips")
        spine1 = Self.findBone(in: character, suffix: "Spine1")
        if let s = spine1 { spine1Bind = s.orientation }

        // Attach clip players to the skeleton so they drive these bones.
        let host = skeletonRoot ?? character
        for (key, player) in template.clips {
            let copy = SCNAnimationPlayer(animation: player.animation)
            copy.stop()
            host.addAnimationPlayer(copy, forKey: key)
            players[key] = copy
        }

        // Per-athlete tint: multiply the kit color into every material so the
        // field reads as different lanes even on a shared mesh.
        character.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] {
                material.multiply.contents = athlete.kitPrimary
            }
        }
        applyMode()
    }

    private static func findBone(in node: SCNNode, suffix: String) -> SCNNode? {
        var found: SCNNode? = nil
        node.enumerateHierarchy { n, stop in
            if let name = n.name,
               name.hasSuffix(suffix) || name.hasSuffix(suffix.replacingOccurrences(of: ":", with: "_")) {
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
        case .running, .decel: key = players["sprint"] != nil ? "sprint" : "running"
        case .idle: key = "idle"
        case .blocks, .set: key = "crouch"
        case .celebrate: key = "victory"
        case .exhausted: key = players["crouch"] != nil ? "crouch" : "idle"
        }
        guard key != currentClip else { return }
        if let old = currentClip, let p = players[old] { p.stop(withBlendOutDuration: 0.2) }
        if let k = key, let p = players[k] {
            p.play()
            currentClip = k
        } else {
            currentClip = nil
        }
    }

    // MARK: Per-frame

    func update(phase: Double, speed: Double, lean: Double, time: Double) {
        // Slave the mocap cycle to the simulation stride rate.
        if mode == .running || mode == .decel, let clip = currentClip, let p = players[clip] {
            // Mixamo sprint cycles are ~0.7s per stride pair at speed 1.
            let strideFreq = 1.7 + 1.1 * (speed / 12.0)     // cycles/sec (matches engine)
            p.speed = CGFloat(max(0.3, strideFreq * 0.7))
        }
        extraLean = Float(max(0, lean - 0.25)) * 0.8
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
