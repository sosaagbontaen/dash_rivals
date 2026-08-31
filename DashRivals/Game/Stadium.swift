import SceneKit
import SpriteKit

/// Builds the night-meet stadium: track, stands, crowd, floodlights, scoreboard, LED boards.
/// Everything is procedural — no asset files.
final class Stadium {
    let root = SCNNode()
    private(set) var scoreboard: Scoreboard!
    private var ledMaterials: [SCNMaterial] = []

    // Stadium oval center (infield is on the -x side of the straight).
    // The ring must clear the whole 100m corridor: at z∈[0,100] the ellipse edge
    // stays well outside lane 8 (x ≈ 9.8).
    static let center = SCNVector3(-36, 0, 50)
    static let ringAx: Float = 62     // semi-axis along x
    static let ringAz: Float = 115    // semi-axis along z

    func build(into scene: SCNScene) {
        buildSky(scene)
        buildTrack()
        buildInfield()
        buildStands()
        buildLights(scene)
        buildScoreboard()
        buildLEDBoards()
        buildTracksideProps()
        scene.rootNode.addChildNode(root)
    }

    /// Call once per frame for ambient animation (LED scroll).
    func update(time: TimeInterval) {
        let t = Float(time)
        for (i, m) in ledMaterials.enumerated() {
            let offset = (t * 0.045 + Float(i) * 0.3).truncatingRemainder(dividingBy: 1)
            var tf = SCNMatrix4MakeScale(4, 1, 1)   // repeat banner 4x along the board
            tf = SCNMatrix4Translate(tf, offset, 0, 0)
            m.diffuse.contentsTransform = tf
            m.emission.contentsTransform = tf
        }
    }

    // MARK: Sky & atmosphere

    private func buildSky(_ scene: SCNScene) {
        let img = ProceduralTexture.skyGradient()
        scene.background.contents = img
        scene.lightingEnvironment.contents = img
        scene.lightingEnvironment.intensity = 0.7
        scene.fogStartDistance = 70
        scene.fogEndDistance = 330
        scene.fogDensityExponent = 1.6
        scene.fogColor = UIColor(red: 0.03, green: 0.045, blue: 0.10, alpha: 1)
    }

    // MARK: Track

    private func buildTrack() {
        let totalLen = CGFloat(Track.backstretch + Track.raceLength + Track.runoutLength)  // 154
        let zMid = Float(totalLen) / 2 - Track.backstretch                                  // 55

        // Surface
        let surface = SCNBox(width: CGFloat(Track.width) + 3.4, height: 0.3, length: totalLen, chamferRadius: 0)
        let surfMat = SCNMaterial()
        surfMat.lightingModel = .physicallyBased
        surfMat.diffuse.contents = ProceduralTexture.trackSpeckle()
        surfMat.diffuse.wrapS = .repeat; surfMat.diffuse.wrapT = .repeat
        surfMat.diffuse.contentsTransform = SCNMatrix4MakeScale(6, 70, 1)
        surfMat.roughness.contents = 0.92
        surface.materials = [surfMat]
        let surfNode = SCNNode(geometry: surface)
        surfNode.position = SCNVector3(Track.width / 2, -0.15, zMid)
        root.addChildNode(surfNode)

        // Lane lines: plain painted white, lit by the floodlights (no glow).
        let lineMat = flatMaterial(UIColor(white: 0.92, alpha: 1))
        for i in 0...Track.lanes {
            let line = SCNBox(width: 0.05, height: 0.012, length: totalLen, chamferRadius: 0)
            line.materials = [lineMat]
            let n = SCNNode(geometry: line)
            n.position = SCNVector3(Float(i) * Track.laneWidth, 0.004, zMid)
            root.addChildNode(n)
        }

        // Start & finish lines
        for z: Float in [0, 100] {
            let line = SCNBox(width: CGFloat(Track.width), height: 0.012, length: z == 100 ? 0.30 : 0.18, chamferRadius: 0)
            line.materials = [flatMaterial(.white)]
            let n = SCNNode(geometry: line)
            n.position = SCNVector3(Track.width / 2, 0.006, z - 0.05)
            root.addChildNode(n)
        }

        // Lane numbers behind the start line
        for lane in 1...Track.lanes {
            let text = SCNText(string: "\(lane)", extrusionDepth: 0.02)
            text.font = UIFont.systemFont(ofSize: 1.0, weight: .heavy)
            text.flatness = 0.05
            text.materials = [flatMaterial(UIColor(white: 0.95, alpha: 1))]
            let n = SCNNode(geometry: text)
            let (minB, maxB) = text.boundingBox
            n.scale = SCNVector3(0.85, 0.85, 0.85)
            // Flat on the track, readable from the start-line camera behind the blocks.
            n.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            n.position = SCNVector3(Roster.laneX(lane) - (maxB.x - minB.x) * 0.85 / 2, 0.01, -2.2)
            root.addChildNode(n)
        }

        // Starting blocks
        for lane in 1...Track.lanes {
            root.addChildNode(startingBlock(atLaneX: Roster.laneX(lane)))
        }

        // 10m distance marks on the right edge
        for d in stride(from: 10, through: 90, by: 10) {
            let text = SCNText(string: "\(d)", extrusionDepth: 0.01)
            text.font = UIFont.systemFont(ofSize: 0.6, weight: .bold)
            text.flatness = 0.1
            text.materials = [flatMaterial(UIColor(white: 0.8, alpha: 1))]
            let n = SCNNode(geometry: text)
            n.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            n.position = SCNVector3(Track.width + 0.9, 0.01, Float(d))
            root.addChildNode(n)
        }
    }

    private func startingBlock(atLaneX x: Float) -> SCNNode {
        let block = SCNNode()
        let dark = flatMaterial(UIColor(white: 0.13, alpha: 1))
        let accent = flatMaterial(UIColor(red: 0.95, green: 0.55, blue: 0.05, alpha: 1))

        let rail = SCNBox(width: 0.07, height: 0.05, length: 0.85, chamferRadius: 0.01)
        rail.materials = [dark]
        let railNode = SCNNode(geometry: rail)
        railNode.position = SCNVector3(0, 0.03, -0.30)
        block.addChildNode(railNode)

        for (i, dz) in [Float(-0.05), Float(-0.60)].enumerated() {
            let pedal = SCNBox(width: 0.16, height: 0.04, length: 0.18, chamferRadius: 0.01)
            pedal.materials = [accent]
            let p = SCNNode(geometry: pedal)
            p.position = SCNVector3(i == 0 ? -0.09 : 0.09, 0.10, dz)
            p.eulerAngles = SCNVector3(-0.7, 0, 0)
            block.addChildNode(p)
        }
        block.position = SCNVector3(x, 0, -0.50)
        return block
    }

    // MARK: Infield & surroundings

    private func buildInfield() {
        let grassMat = SCNMaterial()
        grassMat.lightingModel = .physicallyBased
        grassMat.diffuse.contents = ProceduralTexture.grass()
        grassMat.diffuse.wrapS = .repeat; grassMat.diffuse.wrapT = .repeat
        grassMat.diffuse.contentsTransform = SCNMatrix4MakeScale(40, 40, 1)
        grassMat.roughness.contents = 0.95

        let ground = SCNBox(width: 260, height: 0.2, length: 320, chamferRadius: 0)
        ground.materials = [grassMat]
        let g = SCNNode(geometry: ground)
        g.position = SCNVector3(Stadium.center.x, -0.21, Stadium.center.z)
        root.addChildNode(g)

        // Center-field monogram
        let logo = SCNPlane(width: 22, height: 22)
        let logoMat = SCNMaterial()
        logoMat.diffuse.contents = ProceduralTexture.infieldLogo()
        logoMat.isDoubleSided = true
        logoMat.emission.contents = UIColor(white: 0.10, alpha: 1)
        logo.materials = [logoMat]
        let l = SCNNode(geometry: logo)
        l.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        l.position = SCNVector3(Stadium.center.x + 4, -0.09, Stadium.center.z)
        root.addChildNode(l)

        // Suggestion of the back straight on the far side of the oval
        let far = SCNBox(width: 11, height: 0.25, length: 150, chamferRadius: 0)
        far.materials = [flatMaterial(UIColor(red: 0.30, green: 0.11, blue: 0.10, alpha: 1))]
        let f = SCNNode(geometry: far)
        f.position = SCNVector3(Stadium.center.x - 42, -0.14, Stadium.center.z)
        root.addChildNode(f)
    }

    // MARK: Stands & crowd

    private func buildStands() {
        let c = Stadium.center
        let ax = Stadium.ringAx
        let az = Stadium.ringAz
        let segments = 40
        let crowdVariants = (0..<3).map { _ in ProceduralTexture.crowd() }

        for i in 0..<segments {
            let theta = Float(i) / Float(segments) * 2 * .pi
            let px = c.x + ax * cos(theta)
            let pz = c.z + az * sin(theta)

            let seg = standSegment(crowd: crowdVariants[i % crowdVariants.count])
            seg.position = SCNVector3(px, 0, pz)
            seg.look(at: SCNVector3(c.x, 0, c.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            root.addChildNode(seg)
        }
    }

    /// One stand segment: front wall, sloped crowd bank, roof with glowing light band.
    /// Built facing local -Z (toward the field).
    private func standSegment(crowd: UIImage) -> SCNNode {
        let seg = SCNNode()
        let w: CGFloat = 17.5

        let concrete = flatMaterial(UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1))

        // Front wall with ad-board strip
        let wall = SCNBox(width: w, height: 2.4, length: 0.5, chamferRadius: 0)
        wall.materials = [concrete]
        let wallNode = SCNNode(geometry: wall)
        wallNode.position = SCNVector3(0, 1.2, 0)
        seg.addChildNode(wallNode)

        let ad = SCNBox(width: w * 0.92, height: 0.9, length: 0.1, chamferRadius: 0.02)
        let adMat = SCNMaterial()
        adMat.diffuse.contents = ProceduralTexture.adBoard()
        adMat.emission.contents = ProceduralTexture.adBoard()
        adMat.emission.intensity = 0.55
        ad.materials = [adMat]
        let adNode = SCNNode(geometry: ad)
        adNode.position = SCNVector3(0, 1.35, -0.31)
        seg.addChildNode(adNode)

        // Sloped crowd bank: rises 13 over depth 15
        let slopeLen: CGFloat = 19.8   // sqrt(13^2 + 15^2)
        let bank = SCNPlane(width: w, height: slopeLen)
        let bankMat = SCNMaterial()
        bankMat.diffuse.contents = crowd
        bankMat.emission.contents = crowd
        bankMat.emission.intensity = 0.10
        bankMat.isDoubleSided = true
        bank.materials = [bankMat]
        let bankNode = SCNNode(geometry: bank)
        bankNode.position = SCNVector3(0, 2.4 + 6.5, 7.5)
        bankNode.eulerAngles = SCNVector3(-0.714, 0, 0)   // atan(15/13) tilt toward field
        seg.addChildNode(bankNode)

        // Roof
        let roof = SCNBox(width: w, height: 0.5, length: 17, chamferRadius: 0.05)
        roof.materials = [flatMaterial(UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1))]
        let roofNode = SCNNode(geometry: roof)
        roofNode.position = SCNVector3(0, 17.4, 8.0)
        roofNode.eulerAngles = SCNVector3(-0.12, 0, 0)
        seg.addChildNode(roofNode)

        // Floodlight band under the roof lip — reads as the stadium light ring.
        let band = SCNBox(width: w * 0.96, height: 0.55, length: 0.3, chamferRadius: 0.05)
        let bandMat = SCNMaterial()
        bandMat.diffuse.contents = UIColor.white
        bandMat.emission.contents = UIColor(red: 1.0, green: 0.98, blue: 0.92, alpha: 1)
        bandMat.emission.intensity = 1.8
        band.materials = [bandMat]
        let bandNode = SCNNode(geometry: band)
        bandNode.position = SCNVector3(0, 16.9, 0.4)
        seg.addChildNode(bandNode)

        // Camera-flash sparkles in the crowd
        for _ in 0..<2 {
            let flash = SCNNode(geometry: SCNPlane(width: 0.35, height: 0.35))
            let fm = SCNMaterial()
            fm.diffuse.contents = UIColor.white
            fm.emission.contents = UIColor.white
            fm.emission.intensity = 2.0
            fm.isDoubleSided = true
            flash.geometry?.materials = [fm]
            let u = Float.random(in: -Float(w) / 2 * 0.8 ... Float(w) / 2 * 0.8)
            let v = Float.random(in: 0.2...0.9)
            flash.position = SCNVector3(u, 2.4 + 13 * v, 15 * v - 0.3)
            flash.opacity = 0
            flash.runAction(.repeatForever(.sequence([
                .wait(duration: Double.random(in: 1.5...7), withRange: 4),
                .fadeOpacity(to: 1, duration: 0.04),
                .fadeOpacity(to: 0, duration: 0.22),
            ])))
            seg.addChildNode(flash)
        }
        return seg.flattenedClone()
    }

    // MARK: Lighting

    private func buildLights(_ scene: SCNScene) {
        // Key light: floodlight feel from high on the main-stand side, with shadows.
        let key = SCNLight()
        key.type = .directional
        key.color = UIColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1)
        key.intensity = 1700
        key.castsShadow = true
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowRadius = 4
        key.shadowColor = UIColor(white: 0, alpha: 0.55)
        key.orthographicScale = 90
        key.zNear = 1
        key.zFar = 200
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(30, 60, 50)
        keyNode.eulerAngles = SCNVector3(-1.05, 0.35, 0)
        scene.rootNode.addChildNode(keyNode)

        // Cool fill from the opposite side
        let fill = SCNLight()
        fill.type = .directional
        fill.color = UIColor(red: 0.60, green: 0.68, blue: 0.95, alpha: 1)
        fill.intensity = 450
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.9, .pi - 0.4, 0)
        scene.rootNode.addChildNode(fillNode)

        // Ambient night base
        let amb = SCNLight()
        amb.type = .ambient
        amb.color = UIColor(red: 0.20, green: 0.23, blue: 0.34, alpha: 1)
        amb.intensity = 480
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)
    }

    // MARK: Scoreboard

    private func buildScoreboard() {
        scoreboard = Scoreboard()
        let board = SCNBox(width: 18, height: 9.6, length: 0.8, chamferRadius: 0.15)
        let screenMat = SCNMaterial()
        screenMat.diffuse.contents = scoreboard.skScene
        screenMat.diffuse.contentsTransform = SCNMatrix4Translate(SCNMatrix4MakeScale(1, -1, 1), 0, 1, 0)
        screenMat.emission.contents = scoreboard.skScene
        screenMat.emission.contentsTransform = screenMat.diffuse.contentsTransform
        screenMat.emission.intensity = 0.9
        screenMat.lightingModel = .constant
        let frame = flatMaterial(UIColor(white: 0.05, alpha: 1))
        board.materials = [screenMat, frame, frame, frame, frame, frame]
        let b = SCNNode(geometry: board)
        b.position = SCNVector3(Track.width / 2, 13.5, 126)
        b.eulerAngles = SCNVector3(0.06, Float.pi, 0)
        root.addChildNode(b)

        for x: Float in [-6, 6] {
            let leg = SCNBox(width: 0.7, height: 9, length: 0.7, chamferRadius: 0.05)
            leg.materials = [flatMaterial(UIColor(white: 0.08, alpha: 1))]
            let ln = SCNNode(geometry: leg)
            ln.position = SCNVector3(Track.width / 2 + x, 4.5, 126)
            root.addChildNode(ln)
        }
    }

    // MARK: LED boards

    private func buildLEDBoards() {
        let banner = ProceduralTexture.ledBanner()
        // Left edge (infield side), facing the track; right edge facing back.
        let configs: [(x: Float, ry: Float)] = [(-1.6, Float.pi / 2 + Float.pi), (Track.width + 1.9, Float.pi / 2)]
        for cfg in configs {
            for zStart in stride(from: Float(-10), to: Float(120), by: 26) {
                // Dark housing box with a display plane on the track-facing side only,
                // so the thin side faces never show a stretched banner.
                let housing = SCNBox(width: 25, height: 0.8, length: 0.15, chamferRadius: 0.03)
                housing.materials = [flatMaterial(UIColor(white: 0.05, alpha: 1))]
                let n = SCNNode(geometry: housing)
                n.position = SCNVector3(cfg.x, 0.45, zStart + 13)
                n.eulerAngles = SCNVector3(0, cfg.ry, 0)
                root.addChildNode(n)

                let display = SCNPlane(width: 24.6, height: 0.68)
                let m = SCNMaterial()
                m.diffuse.contents = banner
                m.diffuse.wrapS = .repeat
                m.emission.contents = banner
                m.emission.wrapS = .repeat
                m.emission.intensity = 0.55
                m.lightingModel = .constant
                display.materials = [m]
                ledMaterials.append(m)
                let d = SCNNode(geometry: display)
                d.position = SCNVector3(0, 0, 0.09)
                n.addChildNode(d)
            }
        }
    }

    // MARK: Props

    private func buildTracksideProps() {
        // TV camera on tripod near the finish line
        let cam = SCNNode()
        let body = SCNBox(width: 0.5, height: 0.35, length: 0.8, chamferRadius: 0.05)
        body.materials = [flatMaterial(UIColor(white: 0.1, alpha: 1))]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 1.5, 0)
        cam.addChildNode(bodyNode)
        let tripod = SCNCylinder(radius: 0.05, height: 1.4)
        tripod.materials = [flatMaterial(UIColor(white: 0.2, alpha: 1))]
        let tripodNode = SCNNode(geometry: tripod)
        tripodNode.position = SCNVector3(0, 0.7, 0)
        cam.addChildNode(tripodNode)
        cam.position = SCNVector3(Track.width + 3.4, 0, 101.5)
        cam.eulerAngles = SCNVector3(0, 0.9, 0)
        root.addChildNode(cam)

        // Photo-finish timing boxes on both sides of the line
        for x: Float in [-1.0, Track.width + 1.0] {
            let post = SCNBox(width: 0.14, height: 1.5, length: 0.14, chamferRadius: 0.02)
            post.materials = [flatMaterial(UIColor(white: 0.85, alpha: 1))]
            let p = SCNNode(geometry: post)
            p.position = SCNVector3(x, 0.75, 100)
            root.addChildNode(p)
            let eye = SCNBox(width: 0.22, height: 0.22, length: 0.3, chamferRadius: 0.03)
            eye.materials = [flatMaterial(UIColor(white: 0.1, alpha: 1))]
            let e = SCNNode(geometry: eye)
            e.position = SCNVector3(x, 1.55, 100)
            root.addChildNode(e)
        }
    }

    // MARK: Helpers

    private func flatMaterial(_ color: UIColor, emission: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = 0.85
        m.metalness.contents = 0.05
        if emission > 0 {
            m.emission.contents = color
            m.emission.intensity = emission
        }
        return m
    }
}

// MARK: - Live scoreboard (SpriteKit scene used as a texture)

final class Scoreboard {
    let skScene: SKScene
    private let clockLabel: SKLabelNode
    private let statusLabel: SKLabelNode

    init() {
        skScene = SKScene(size: CGSize(width: 1024, height: 546))
        skScene.backgroundColor = SKColor(red: 0.02, green: 0.04, blue: 0.12, alpha: 1)

        let title = SKLabelNode(fontNamed: "HelveticaNeue-CondensedBlack")
        title.text = "DASH RIVALS"
        title.fontSize = 92
        title.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)
        title.position = CGPoint(x: 512, y: 430)
        skScene.addChild(title)

        let sub = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        sub.text = "NIGHT MEET · MEN 100M FINAL"
        sub.fontSize = 42
        sub.fontColor = SKColor(white: 0.85, alpha: 1)
        sub.position = CGPoint(x: 512, y: 368)
        skScene.addChild(sub)

        clockLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        clockLabel.text = "0.00"
        clockLabel.fontSize = 190
        clockLabel.fontColor = SKColor(red: 1.0, green: 0.95, blue: 0.4, alpha: 1)
        clockLabel.position = CGPoint(x: 512, y: 130)
        skScene.addChild(clockLabel)

        statusLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        statusLabel.text = "ON YOUR MARKS"
        statusLabel.fontSize = 44
        statusLabel.fontColor = SKColor(red: 0.4, green: 0.9, blue: 1.0, alpha: 1)
        statusLabel.position = CGPoint(x: 512, y: 40)
        skScene.addChild(statusLabel)
    }

    func setClock(_ t: Double) {
        clockLabel.text = String(format: "%.2f", t)
    }

    func setStatus(_ s: String) {
        statusLabel.text = s
    }
}
