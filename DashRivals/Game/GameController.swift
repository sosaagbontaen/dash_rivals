import SceneKit
import SwiftUI

struct VerdictFlash: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let good: Bool
}

struct MiniMapDot: Identifiable {
    let id: Int
    let color: UIColor
    let progress: Double
    let isPlayer: Bool
}

struct PlayerSummary {
    let time: Double
    let place: Int
    let reaction: Double
    let split50: Double?
    let topSpeed: Double
    let leanCredit: Double
    let isNewPB: Bool
    let previousPB: Double?
}

/// Central coordinator: owns the scene, the simulation, audio, cameras and the
/// published HUD state consumed by SwiftUI.
final class GameController: NSObject, ObservableObject, SCNSceneRendererDelegate {

    // MARK: Published HUD state (mutated on main thread only)
    @Published var uiPhase: RacePhase = .menu
    @Published var clockText = "0.00"
    @Published var speedText = "0.0"
    @Published var prompt: String? = nil
    @Published var verdictFlash: VerdictFlash? = nil
    @Published var splitToast: String? = nil
    @Published var introCard: Athlete? = nil
    @Published var resultRows: [RaceResultRow] = []
    @Published var summary: PlayerSummary? = nil
    @Published var miniMap: [MiniMapDot] = []
    @Published var gunFlash = false
    @Published var finishFlash = false
    @Published var holdingL = false
    @Published var holdingR = false
    @Published var bestTimeText = "—"
    // Effort gauge state
    @Published var effortValue: Double = 0.85
    @Published var bandCenter: Double = 0.9
    @Published var bandHalf: Double = 0.1
    @Published var tensionValue: Double = 0
    @Published var formValue: Double = 0.9          // qBar — tracking quality
    @Published var gaugeVisible = false
    @Published var phaseLabel: String? = nil        // DRIVE / MAX VELOCITY / HOLD ON
    // A/B tracking-style state (LINEAR bars vs CIRCLE dot-chase)
    @Published var trackingStyle: TrackingStyle = .circle
    @Published var discTol: Double = 0.2
    @Published var leanCue = false
    @Published var effortL: Double = 0.85
    @Published var effortR: Double = 0.85
    @Published var stickAngleL: Double = -1.2   // radians; knob rendering (view space)
    @Published var stickAngleR: Double = -1.9
    @Published var targetAngle: Double = -Double.pi / 2   // canonical; HUD mirrors for left
    // Broadcast replay
    @Published var replayActive = false
    @Published var windText = "+0.0"
    // Character choice (Remy = human, Y Bot = Mixamo mannequin)
    @Published var characterName = "remy"
    // Speed units
    @Published var useMph = false
    private var useMphInternal = false
    // Cinematic letterbox during full flight
    @Published var cinematicBars = false

    // MARK: Scene
    let scene = SCNScene()
    let engine = RaceEngine()
    let audio = GameAudio()
    let cameraDirector = CameraDirector()
    private let stadium = Stadium()
    private var figures: [AthleteFigure] = []
    private var figureLeans = [Double](repeating: 0.1, count: 8)

    // MARK: Loop bookkeeping (render thread)
    private var lastTime: TimeInterval?
    private var phaseTime: Double = 0
    private var sceneTime: Double = 0
    private var strideCounters = [Int](repeating: 0, count: 8)
    private var uiClockAccum: Double = 0
    private var mapAccum: Double = 0
    private var splitClearAt: Double? = nil
    private var celebrationAt: Double? = nil
    private var playerFinishedAt: Double? = nil
    private var lastRelaxFlashAt: Double = -10
    private var playerLeanUntil: Double = 0        // scene time: dip pose held until then

    // Broadcast replay: recorded sim frames, played back slow through a finish camera.
    private struct RunnerSnap { let d: Double; let v: Double; let ph: Double }
    private var replayFrames: [(t: Double, snaps: [RunnerSnap])] = []
    private var replayCursor = 0
    private var replayClock: Double = 0
    private var replayEnd: Double = 0
    private static let replayRate = 0.42
    private var replaying = false
    private var skipReplay = false

    // Input events from the touch view (main), consumed on the render thread.
    private let inputLock = NSLock()
    private var pendingInputs: [(side: TapSide, isDown: Bool, hostTime: Double)] = []
    private var latestEffort: [Bool: Double] = [:]  // per side (true = right)
    private var heldSides: Set<Bool> = []           // true = right
    private var sideDownAt: [Bool: Double] = [:]    // engine time each side last went down
    private var leanFeedbackDone = false

    // Haptics
    private let haptics = Haptics()
    private let tapHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let successHaptic = UINotificationFeedbackGenerator()

    // Cinematic time scale (slow-mo launch & photo-finish)
    private var timeScale = 1.0
    private var heldScale = 0.45
    private var slowMoHoldUntil: Double = -1
    private var lastSprintPhase: SprintPhaseKind = .drive

    // Autopilot (DEBUG tuning aid): launch with -autopilot [-apq 0.9] [-aponce]
    private let autopilot = CommandLine.arguments.contains("-autopilot")
#if DEBUG
    private let blockProbe = CommandLine.arguments.contains("-blockprobe")
    private let dipDemo = CommandLine.arguments.contains("-dipdemo")
    private var blockProbeTick = 0
#endif
    private let autopilotOnce = CommandLine.arguments.contains("-aponce")
    private var autoQuality: Double {
        if let i = CommandLine.arguments.firstIndex(of: "-apq"), i + 1 < CommandLine.arguments.count,
           let v = Double(CommandLine.arguments[i + 1]) { return v }
        return 0.9
    }
    private var apNoise: Double = 0
    private var apNoise2: Double = 0

    override init() {
        super.init()
        stadium.build(into: scene)
        scene.rootNode.addChildNode(cameraDirector.node)

        engine.loadField()
        buildFigures()

        bestTimeText = Self.formatPB(storedPB)
        if let raw = UserDefaults.standard.string(forKey: "tracking"),
           let t = TrackingStyle(rawValue: raw) {
            trackingStyle = t
            engine.tracking = t
        }
        useMph = UserDefaults.standard.bool(forKey: "useMph")
        useMphInternal = useMph
        characterName = UserDefaults.standard.string(forKey: "character") ?? "remy"
        tapHaptic.prepare()
        heavyHaptic.prepare()
    }

    /// Menu toggle: switch the tracking style (linear bars vs circular dot-chase).
    func setTracking(_ t: TrackingStyle) {
        trackingStyle = t
        UserDefaults.standard.set(t.rawValue, forKey: "tracking")
        onRender { [self] in engine.tracking = t }
        audio.playTick()
    }

    /// (Re)create the eight athletes from whichever character is selected.
    /// v4 skinned athletes when Mixamo assets are bundled; procedural v3 otherwise.
    private func buildFigures() {
        for fig in figures { fig.root.removeFromParentNode() }
        figures.removeAll()
        let template = SkinnedRunner.loadTemplate()
        for r in engine.runners {
            let fig: AthleteFigure
            if let template, let skinned = SkinnedRunner(athlete: r.athlete, template: template) {
                fig = skinned
            } else {
                fig = RunnerFigure(athlete: r.athlete, leftLegForward: r.lane % 2 == 0, lane: r.lane)
            }
            fig.root.position = SCNVector3(Roster.laneX(r.lane), 0, -1.4)
            fig.mode = .idle
            scene.rootNode.addChildNode(fig.root)
            figures.append(fig)
        }
    }

    /// Menu toggle: swap the athlete model (needs the field rebuilt).
    func setCharacter(_ name: String) {
        characterName = name
        UserDefaults.standard.set(name, forKey: "character")
        onRender { [self] in buildFigures() }
        audio.playTick()
    }

    /// Menu toggle: speed readout units.
    func setUseMph(_ mph: Bool) {
        useMph = mph
        UserDefaults.standard.set(mph, forKey: "useMph")
        onRender { [self] in useMphInternal = mph }
        audio.playTick()
    }

    // MARK: Persistence

    private var storedPB: Double? {
        let v = UserDefaults.standard.double(forKey: "pb")
        return v > 0 ? v : nil
    }

    private static func formatPB(_ pb: Double?) -> String {
        pb.map { String(format: "%.2f", $0) } ?? "—"
    }

    // MARK: Public UI actions (main thread)

    func startRace() {
        engine.resetRace()
        onRender { [self] in
            for (i, r) in engine.runners.enumerated() {
                figures[i].mode = .blocks
                figures[i].root.position = SCNVector3(Roster.laneX(r.lane), 0, -0.35)
            }
            strideCounters = [Int](repeating: 0, count: 8)
            playerFinishedAt = nil
            celebrationAt = nil
            nextPantAt = 0
            leanFeedbackDone = false
            replayFrames.removeAll()
            replaying = false
            engine.setPhase(.intro)
            phaseTime = 0
            cameraDirector.mode = .intro
            cameraDirector.snap(to: SIMD3(11.8, 1.3, 2.6), look: SIMD3(11, 0.95, -0.9))
            audio.crowdTarget = 0.5
        }
        publish { $0.uiPhase = .intro; $0.summary = nil }
        audio.start()
        audio.playTick()
    }

    func runAgain() {
        engine.resetRace()
        onRender { [self] in
            for (i, r) in engine.runners.enumerated() {
                figures[i].mode = .blocks
                figures[i].root.position = SCNVector3(Roster.laneX(r.lane), 0, -0.35)
            }
            strideCounters = [Int](repeating: 0, count: 8)
            playerFinishedAt = nil
            celebrationAt = nil
            nextPantAt = 0
            leanFeedbackDone = false
            replayFrames.removeAll()
            replaying = false
            engine.setPhase(.marks)
            phaseTime = 0
            cameraDirector.mode = .set
            let px = Roster.laneX(Roster.playerLane)
            cameraDirector.snap(to: SIMD3(px + 0.9, 1.25, -4.6), look: SIMD3(px, 0.75, 3))
            audio.crowdTarget = 0.4
        }
        publish { $0.uiPhase = .marks; $0.summary = nil; $0.resultRows = [] }
        audio.playTick()
        audio.playAnnouncer(.marks)
    }

    func backToMenu() {
        onRender { [self] in
            engine.setPhase(.menu)
            for (i, r) in engine.runners.enumerated() {
                figures[i].mode = .idle
                figures[i].root.position = SCNVector3(Roster.laneX(r.lane), 0, -1.4)
            }
            cameraDirector.mode = .menu
            cameraDirector.snap(to: SIMD3(5, 1.75, 7.5), look: SIMD3(4.88, 1.15, -4))
            audio.crowdTarget = 0.4
        }
        publish { $0.uiPhase = .menu; $0.summary = nil; $0.resultRows = [] }
    }

    // MARK: Touch input (main thread)

    func touch(side: TapSide, isDown: Bool, hostTime: Double = CACurrentMediaTime()) {
        inputLock.lock()
        pendingInputs.append((side, isDown, hostTime))
        inputLock.unlock()
    }

    /// Continuous per-thumb effort (0 inner .. 1 outer) + the thumb's angle on
    /// its stick, so the HUD can draw the knob exactly under the thumb.
    func effortInput(side: TapSide, value: Double, angle: Double) {
        inputLock.lock()
        latestEffort[side == .right] = value
        latestAngle[side == .right] = angle
        inputLock.unlock()
    }
    private var latestAngle: [Bool: Double] = [:]

    /// Downward touch motion in points; a sharp drop in the final meters = the dip.
    func dipInput(points: Double) {
        inputLock.lock()
        pendingDip += points
        inputLock.unlock()
    }
    private var pendingDip: Double = 0
    private var dipAccum: Double = 0

    // MARK: Render-thread helpers

    private var renderActions: [() -> Void] = []
    private let renderLock = NSLock()
    private func onRender(_ body: @escaping () -> Void) {
        renderLock.lock()
        renderActions.append(body)
        renderLock.unlock()
    }

    /// Batch @Published mutations onto the main thread.
    private func publish(_ body: @escaping (GameController) -> Void) {
        DispatchQueue.main.async { body(self) }
    }

    // MARK: Frame update

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = min(0.05, lastTime.map { time - $0 } ?? 1.0 / 60.0)
        lastTime = time
        sceneTime = time
        phaseTime += dt

        renderLock.lock()
        let actions = renderActions
        renderActions.removeAll()
        renderLock.unlock()
        for a in actions { a() }

        processInputs()

        if replaying {
            runReplayFrame(dt: dt)
            stadium.update(time: time)
            audio.update(dt: dt)
            return
        }

        runAutopilot(dt: dt)

        // Slow-mo choreography: a beat on the gun, a stretch through the line.
        timeScale += (currentTimeScaleTarget() - timeScale) * min(1, dt * 10)
        let events = engine.update(dt: dt * timeScale)
        handle(events: events)
        updateSpectacle()

        // Record for the broadcast replay.
        if engine.phase == .racing || engine.phase == .finished {
            let snaps = engine.runners.map { RunnerSnap(d: $0.distance, v: $0.velocity, ph: $0.stridePhase) }
            replayFrames.append((engine.timeSinceGun, snaps))
        }

        updatePhaseLogic(dt: dt)
        updateFigures(dt: dt)
        updateCamera(dt: dt)
        updateScoreboardAndHUD(dt: dt)
        stadium.update(time: time)
        audio.update(dt: dt)
    }

    // MARK: Broadcast replay

    private func startReplay() {
        engine.setPhase(.results)          // stop the sim; the recording takes over
        guard replayFrames.count > 40 else { finishCelebration(); return }
        let tFin = engine.player.finishTime ?? engine.timeSinceGun
        replayClock = max(replayFrames.first!.t, tFin - 2.4)
        replayEnd = min(replayFrames.last!.t, tFin + 0.55)
        replayCursor = 0
        skipReplay = false
        replaying = true
        cameraDirector.mode = .finishCam
        cameraDirector.setStreakSpeed(0)
        audio.windTarget = 0
        audio.crowdTarget = 0.6
        publish { $0.replayActive = true }
    }

    private func runReplayFrame(dt: Double) {
        replayClock += dt * Self.replayRate
        while replayCursor < replayFrames.count - 1, replayFrames[replayCursor].t < replayClock {
            replayCursor += 1
        }
        let frame = replayFrames[replayCursor]
        for (i, s) in frame.snaps.enumerated() {
            let fig = figures[i]
            fig.mode = .running
            fig.root.position = SCNVector3(Roster.laneX(i + 1), 0, Float(s.d) - 0.35)
            let lean = 0.06 + 0.88 * exp(-s.d / 11.0)
            // The replay runs at replayRate; the leg cycle has to match it.
            fig.update(phase: s.ph, speed: s.v * Self.replayRate,
                       lean: s.v > 0.2 ? lean : 0.1, time: sceneTime)
        }
        let pd = frame.snaps[Roster.playerIndex].d
        cameraDirector.update(dt: dt, time: sceneTime, introT: phaseTime,
                              playerX: Roster.laneX(Roster.playerLane),
                              playerZ: Float(pd) - 0.35, v: 0, phase: 0)
        if replayClock >= replayEnd || skipReplay {
            finishCelebration()
        }
    }

    /// Safe point to layer procedural bone tweaks over evaluated animation clips.
    func renderer(_ renderer: SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
        for (i, fig) in figures.enumerated() {
            fig.postAnimationAdjust(lean: figureLeans[i])
        }
#if DEBUG
        if blockProbe, let s = figures.first as? SkinnedRunner {
            blockProbeTick += 1
            if blockProbeTick % 15 == 0, let line = s.footProbe() { print("BLOCKPROBE \(line)") }
        }
#endif
    }

    private func processInputs() {
        inputLock.lock()
        let inputs = pendingInputs
        pendingInputs.removeAll()
        let effL = latestEffort[false]
        let effR = latestEffort[true]
        let angL = latestAngle[false]
        let angR = latestAngle[true]
        let dip = pendingDip
        pendingDip = 0
        inputLock.unlock()
        if angL != nil || angR != nil {
            publish {
                if let a = angL { $0.stickAngleL = a }
                if let a = angR { $0.stickAngleR = a }
            }
        }

        // Dip detector: fast downward swipe in the final meters.
        dipAccum = dipAccum * 0.86 + dip
        if engine.phase == .racing, engine.playerLaunched,
           engine.player.distance >= engine.tuning.leanZone, dipAccum > 55 {
            _ = engine.executeLean()
        }

        for (side, isDown, hostTime) in inputs {
            if isDown { heldSides.insert(side == .right) } else { heldSides.remove(side == .right) }
            if replaying { if isDown { skipReplay = true }; continue }
            let latency = max(0, min(0.25, sceneTime - hostTime))
            let engineT = engine.timeSinceGun - latency

            switch engine.phase {
            case .intro:
                if isDown { skipIntro() }
            case .marks:
                let l = heldSides.contains(false), r = heldSides.contains(true)
                publish { $0.holdingL = l; $0.holdingR = r }
                if l && r {
                    engine.playerIsSet()
                    audio.playAnnouncer(.set)
                    audio.playSetBeep()
                    audio.playHeartbeat()
                    audio.crowdTarget = 0.08   // the stadium holds its breath
                    publish { $0.uiPhase = .set }
                    haptics.setCrouch()
                }
            case .set:
                engine.playerFalseStart()
                publish { $0.verdictFlash = VerdictFlash(text: TapVerdict.falseStart.rawValue, good: false) }
            case .racing:
                if !engine.playerLaunched {
                    // First movement after the gun — usually the thumb lift.
                    engine.playerLaunch(engineTime: engineT)
                    haptics.launch()
                    cameraDirector.impulse(0.5)
                }
                if isDown { sideDownAt[side == .right] = engineT }
            default:
                break
            }
        }

        // Feed both thumb sticks to the tracking model (canonical space: the left
        // stick's angle is mirrored so outward reads the same on both sides).
        if engine.phase == .racing, engine.playerLaunched {
            var left: (effort: Double, angle: Double)? = nil
            var right: (effort: Double, angle: Double)? = nil
            if heldSides.contains(false), let e = effL {
                left = (e, Double.pi - (angL ?? -Double.pi / 2))
            }
            if heldSides.contains(true), let e = effR {
                right = (e, angR ?? -Double.pi / 2)
            }
            engine.setPlayerSticks(left: left, right: right)
        }

        // Lean feedback (the dip can be triggered inside the engine or by autopilot).
        if engine.leanExecutedAt != nil, !leanFeedbackDone {
            leanFeedbackDone = true
            publish { $0.verdictFlash = VerdictFlash(text: TapVerdict.lean.rawValue, good: true) }
            playerLeanUntil = sceneTime + 0.55
            haptics.lean()
        }
    }

    private func currentTimeScaleTarget() -> Double {
        if sceneTime < slowMoHoldUntil { return heldScale }
        if engine.phase == .racing, engine.playerLaunched, engine.player.finishTime == nil,
           engine.player.distance > 96.5 {
            return 0.45   // the line approaches in super slow motion
        }
        return 1.0
    }

    /// One-shot spectacle moments driven by race state.
    private func updateSpectacle() {
        if engine.phase == .racing, engine.playerLaunched {
            let sp = engine.sprintPhase
            if sp != lastSprintPhase {
                if sp == .maxVelocity {
                    // Hitting top gear: FOV blooms, the air starts to howl.
                    cameraDirector.topGearBloom()
                    audio.playWhoosh()
                    haptics.topGear()
                    publish { $0.verdictFlash = VerdictFlash(text: "FULL FLIGHT", good: true) }
                }
                lastSprintPhase = sp
            }
        } else if engine.phase != .finished {
            lastSprintPhase = .drive
        }
    }

    private func skipIntro() {
        engine.setPhase(.marks)
        phaseTime = 0
        cameraDirector.mode = .set
        let px = Roster.laneX(Roster.playerLane)
        cameraDirector.snap(to: SIMD3(px + 0.9, 1.25, -4.6), look: SIMD3(px, 0.75, 3))
        audio.playAnnouncer(.marks)
        publish { $0.uiPhase = .marks; $0.introCard = nil }
    }

    // MARK: Events & phase flow

    private func handle(events: RaceEngine.FrameEvents) {
        if events.gunJustFired {
            audio.playGun()
            audio.crowdTarget = 0.65
            cameraDirector.impulse(0.55)
            cameraDirector.mode = .chase
            haptics.gun()
            // A short impact-freeze on the bang, then time SNAPS back — the field
            // should explode, not wade, out of the blocks.
            timeScale = 0.3
            heldScale = 0.35
            slowMoHoldUntil = sceneTime + 0.18
            publish {
                $0.uiPhase = .racing
                $0.gunFlash = true
            }
            DispatchQueue.main.async {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.gunFlash = false }
            }
        }

        if events.playerCrossed50, let s = engine.player.split50 {
            let ahead = engine.runners.filter { !$0.athlete.isPlayer && $0.distance >= engine.player.distance }.count
            let place = ahead + 1
            let text = String(format: "50m — %.2f  ·  P%d", s, place)
            publish { $0.splitToast = text }
            splitClearAt = phaseTime + 1.8
            audio.playTick()
        }

        // Tension coaching: tightening up is the thing that slows you late.
        if engine.phase == .racing, engine.tension > 0.55, sceneTime - lastRelaxFlashAt > 2.5 {
            lastRelaxFlashAt = sceneTime
            publish { $0.verdictFlash = VerdictFlash(text: TapVerdict.relax.rawValue, good: false) }
            haptics.tensionTick()
        }

        for r in events.runnersJustFinished where r.athlete.isPlayer {
            playerFinishedAt = phaseTime
            audio.playCheer()
            audio.crowdTarget = 0.95
            cameraDirector.impulse(0.7)
            haptics.finishBurst()
            // Hold the super-slow-mo through the line, then let time snap back.
            heldScale = 0.4
            slowMoHoldUntil = sceneTime + 0.55
            publish { $0.finishFlash = true }
            DispatchQueue.main.async {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { self.finishFlash = false }
            }
        }

        if engine.phase == .racing || engine.phase == .finished {
            let allDone = events.raceComplete
            let playerDone = engine.player.finishTime != nil
            // Timeout also covers a player who stalls or never launches: DNF to results.
            let timeout = engine.timeSinceGun > 16
            if engine.phase == .racing, playerDone || timeout {
                engine.setPhase(.finished)
                publish { $0.uiPhase = .finished }
            }
            if celebrationAt == nil, allDone || timeout {
                celebrationAt = phaseTime + 1.4   // let the run-out breathe first
            }
        }

        if let at = celebrationAt, phaseTime >= at, engine.phase == .finished {
            celebrationAt = nil
            startReplay()
        }
    }

    private func finishCelebration() {
        replaying = false
        publish { $0.replayActive = false }
        // Return everyone to their true final positions after the replay scrub.
        for (i, r) in engine.runners.enumerated() {
            figures[i].root.position = SCNVector3(Roster.laneX(r.lane), 0, Float(r.distance) - 0.35)
        }
        cameraDirector.mode = .orbit
        audio.crowdTarget = 0.7

        let rows = engine.results()
        let pTime = engine.player.finishTime ?? 0
        let prevPB = storedPB
        let isNewPB = pTime > 0 && (prevPB.map { pTime < $0 } ?? true)
        if isNewPB {
            UserDefaults.standard.set(pTime, forKey: "pb")
        }
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "races") + 1, forKey: "races")

        let sum = PlayerSummary(time: pTime,
                                place: engine.playerPlace,
                                reaction: engine.player.reaction,
                                split50: engine.player.split50,
                                topSpeed: engine.player.topSpeed,
                                leanCredit: engine.leanCredit,
                                isNewPB: isNewPB,
                                previousPB: prevPB)

        // Poses: winner celebrates; player celebrates on podium/PB, else catches breath.
        let winnerIdx = engine.runners.firstIndex { r in
            r.finishTime != nil && r.finishTime == rows.first?.time
        }
        for (i, r) in engine.runners.enumerated() {
            if i == winnerIdx || (r.athlete.isPlayer && (isNewPB || engine.playerPlace <= 3)) {
                figures[i].mode = .celebrate
            } else {
                figures[i].mode = .exhausted
            }
        }
        if isNewPB {
            audio.playPB()
            audio.playAnnouncer(.newPB)
        }

        let wind = String(format: "%+.1f", engine.windReading)
        publish {
            $0.resultRows = rows
            $0.summary = sum
            $0.uiPhase = .results
            $0.windText = wind
            $0.bestTimeText = Self.formatPB(isNewPB ? pTime : prevPB)
        }
        if isNewPB {
            DispatchQueue.main.async { self.successHaptic.notificationOccurred(.success) }
        }
        engine.setPhase(.results)
    }

    private func updatePhaseLogic(dt: Double) {
        switch engine.phase {
        case .intro:
            // Cycle athlete intro cards with the camera dolly (lane 8 → lane 1).
            let per = 6.0 / 8.0
            let idx = min(7, Int(phaseTime / per))
            let lane = 8 - idx
            let athlete = engine.runners[lane - 1].athlete
            if introCardLane != lane {
                introCardLane = lane
                publish { $0.introCard = athlete }
            }
            if phaseTime >= 6.2 { skipIntro() }
        case .marks:
            if phaseTime > 0.5, heldSides.isEmpty {
                publish { $0.holdingL = false; $0.holdingR = false }
            }
        default:
            break
        }

        if let clearAt = splitClearAt, phaseTime >= clearAt {
            splitClearAt = nil
            publish { $0.splitToast = nil }
        }
    }
    private var introCardLane = 0

    // MARK: Autopilot

    private func runAutopilot(dt: Double) {
        guard autopilot else { return }
        switch engine.phase {
        case .menu:
            if phaseTime > 1.0 { publish { $0.startRace() }; phaseTime = 0 }
        case .intro:
            if phaseTime > 1.0 { skipIntro() }
        case .marks:
            if phaseTime > 0.6 {
                engine.playerIsSet()
                audio.crowdTarget = 0.08
                publish { $0.uiPhase = .set }
            }
        case .racing:
            guard engine.gunFired else { break }
            if !engine.playerLaunched {
                if engine.timeSinceGun > 0.14 {
                    engine.playerLaunch(engineTime: 0.14)
                }
            } else if engine.player.distance > 98.2, engine.leanExecutedAt == nil,
                      engine.player.finishTime == nil {
                _ = engine.executeLean()
            } else {
                // Track the yellow dot like a human: lag, smoothed 2D noise, over-press bias.
                let q = autoQuality
                let sd = 0.008 + (1 - q) * 0.15
                let lag = 0.06 + (1 - q) * 0.5
                let bias = (1 - q) * 0.12
                apNoise += -6 * apNoise * dt + sd * (12 * dt).squareRoot() * gaussianRand()
                apNoise2 += -6 * apNoise2 * dt + sd * (12 * dt).squareRoot() * gaussianRand()
                let p = engine.player
                let laggedD = max(0, p.distance - p.velocity * lag)
                let target = engine.band(atDistance: laggedD, time: engine.timeSinceGun - lag)
                let angle = engine.targetAngle(time: engine.timeSinceGun - lag, distance: laggedD)
                    + apNoise2 * 0.5
                engine.setAutoStick(effort: target.center + apNoise + bias, angle: angle)
                publish {
                    $0.stickAngleL = Double.pi - angle
                    $0.stickAngleR = angle
                }
            }
        case .results:
            if !autopilotOnce, phaseTime > 6 { publish { $0.runAgain() }; phaseTime = 0 }
        default:
            break
        }
    }

    private func gaussianRand() -> Double {
        let u1 = Double.random(in: 0.0001...0.9999), u2 = Double.random(in: 0...1)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }

    // MARK: Per-frame scene updates

    private func updateFigures(dt: Double) {
        for (i, r) in engine.runners.enumerated() {
            let fig = figures[i]

            switch engine.phase {
            case .racing, .finished, .results:
                if r.velocity > 0.25 {
                    if fig.mode == .blocks || fig.mode == .set { fig.mode = .running }
                    if fig.mode == .running || fig.mode == .decel {
                        fig.root.position = SCNVector3(Roster.laneX(r.lane), 0, Float(r.distance) - 0.35)
                        fig.mode = r.finishTime == nil ? .running : .decel
                    }
                } else if r.finishTime != nil, fig.mode == .decel {
                    fig.mode = .exhausted
                }
            case .set:
                if fig.mode == .blocks { fig.mode = .set }
            default:
                break
            }

            // Drive lean by distance, not speed: buried out of the blocks (~50°),
            // rising smoothly through the first ~25m.
            var lean = r.finishTime == nil
                ? 0.06 + 0.88 * exp(-r.distance / 11.0)
                : max(0.06, 0.30 * (1 - r.velocity / 11.5))
            // The dip at the line.
            if r.athlete.isPlayer, sceneTime < playerLeanUntil { lean = 0.85 }
            figureLeans[i] = r.velocity > 0.2 ? lean : 0.1
#if DEBUG
            if dipDemo, r.velocity > 0.2 { figureLeans[i] = 0.9 }
#endif
            // Feed the *displayed* speed: during impact-freeze and the slow-motion
            // finish the world advances at timeScale, so the legs must cycle at
            // timeScale too, or they churn while the ground crawls.
            fig.update(phase: r.stridePhase, speed: r.velocity * timeScale,
                       lean: figureLeans[i], time: sceneTime)

            // Footstep audio + haptic: two steps per stride cycle.
            let stepCount = Int(r.stridePhase * 2)
            if stepCount > strideCounters[i], r.velocity > 1 {
                strideCounters[i] = stepCount
                if r.athlete.isPlayer {
                    audio.playFootstep(loud: true)
                    haptics.footstep(speedFactor: Float(min(1, r.velocity / 12)))
                    // The first strides are warfare: camera concussion + power grunts.
                    if r.distance < 22, r.finishTime == nil {
                        cameraDirector.impulse(0.13)
                        if stepCount <= 5, stepCount % 2 == 0 { audio.playBreath(volume: 0.65) }
                    }
                    // Breathe out every second stride cycle, harder as the race wears on.
                    if stepCount % 4 == 0, r.distance > 22, r.finishTime == nil {
                        let strain = Float(min(1, engine.timeSinceGun / 10))
                        audio.playBreath(volume: 0.25 + 0.5 * strain)
                    }
                } else if abs(r.distance - engine.player.distance) < 6, i % 2 == 0 {
                    audio.playFootstep(loud: false)
                }
            }
        }

        // Heavy panting after the line while the player recovers.
        if let fin = playerFinishedAt, phaseTime - fin < 4.0, phaseTime > nextPantAt {
            nextPantAt = phaseTime + 0.55
            audio.playBreath(volume: 0.85)
        }
    }
    private var nextPantAt: Double = 0

    private func updateCamera(dt: Double) {
        let p = engine.player
        cameraDirector.update(dt: dt, time: sceneTime, introT: phaseTime,
                              playerX: Roster.laneX(Roster.playerLane),
                              playerZ: Float(p.distance) - 0.35,
                              v: Float(p.velocity),
                              phase: Float(p.stridePhase))
        let racingish = engine.phase == .racing || engine.phase == .finished
        audio.windTarget = racingish ? Float(min(1, p.velocity / 12)) * 0.55 : 0
        cameraDirector.setStreakSpeed(racingish ? Float(p.velocity) : 0)
    }

    private func updateScoreboardAndHUD(dt: Double) {
        switch engine.phase {
        case .menu: stadium.scoreboard.setStatus("TONIGHT · MEN 100M FINAL")
        case .intro: stadium.scoreboard.setStatus("INTRODUCING THE FIELD")
        case .marks: stadium.scoreboard.setStatus("ON YOUR MARKS")
        case .set: stadium.scoreboard.setStatus("SET")
        case .racing, .finished:
            stadium.scoreboard.setClock(engine.clock)
            stadium.scoreboard.setStatus("")
        case .results:
            if let t = engine.player.finishTime {
                stadium.scoreboard.setClock(t)
                stadium.scoreboard.setStatus(String(format: "YOU — P%d", engine.playerPlace))
            }
        }

        // Throttled HUD publishing.
        uiClockAccum += dt
        if uiClockAccum > 1.0 / 30.0 {
            uiClockAccum = 0
            let clock = engine.phase == .results ? (engine.player.finishTime ?? engine.clock) : engine.clock
            let clockStr = String(format: "%.2f", max(0, clock))
            let v = engine.player.velocity
            let speedStr = String(format: "%.1f", useMphInternal ? v * 2.23694 : v)
            let promptStr = currentPrompt()
            let racing = engine.phase == .racing && engine.playerLaunched
            let phaseStr: String? = racing ? engine.sprintPhase.rawValue : nil
            let band = engine.currentBand
            let tolValue = engine.discTolerance
            let tAngle = engine.targetAngle(time: engine.timeSinceGun, distance: engine.player.distance)
            let effort = engine.playerEffort
            let tension = engine.tension
            let form = engine.qBar
            let effL = engine.playerEffortL
            let effR = engine.playerEffortR
            let gauge = racing && engine.player.finishTime == nil
            let lean = racing && engine.player.finishTime == nil
                && engine.player.distance > 88 && engine.leanExecutedAt == nil
            let bars = racing && engine.sprintPhase != .drive
            publish {
                $0.clockText = clockStr
                $0.speedText = speedStr
                $0.formValue = form
                $0.effortValue = effort
                $0.effortL = effL
                $0.effortR = effR
                $0.bandCenter = band.center
                $0.bandHalf = band.half
                $0.discTol = tolValue
                $0.targetAngle = tAngle
                $0.tensionValue = tension
                if $0.gaugeVisible != gauge { $0.gaugeVisible = gauge }
                if $0.leanCue != lean { $0.leanCue = lean }
                if $0.prompt != promptStr { $0.prompt = promptStr }
                if $0.phaseLabel != phaseStr { $0.phaseLabel = phaseStr }
                if $0.cinematicBars != bars { $0.cinematicBars = bars }
            }
        }

        mapAccum += dt
        if mapAccum > 0.12, engine.phase == .racing || engine.phase == .finished {
            mapAccum = 0
            let dots = engine.runners.map { r in
                MiniMapDot(id: r.lane, color: r.athlete.kitPrimary,
                           progress: min(1, r.distance / 100), isPlayer: r.athlete.isPlayer)
            }
            publish { $0.miniMap = dots }
        }
    }

    private func currentPrompt() -> String? {
        switch engine.phase {
        case .marks: return "HOLD BOTH SIDES"
        case .set: return "SET…"
        case .racing:
            if !engine.playerLaunched { return "GUN! LIFT A THUMB!" }
            if engine.player.finishTime == nil, engine.player.distance > 88,
               engine.leanExecutedAt == nil {
                return "DIP — YANK BOTH THUMBS DOWN!"
            }
            guard engine.timeSinceGun < 2.6 else { return nil }
            switch engine.tracking {
            case .linear: return "RIDE THE GOLD BANDS — BOTH THUMBS"
            case .circle: return "CHASE THE GOLD DOT — BOTH THUMBS"
            }
        default: return nil
        }
    }
}
