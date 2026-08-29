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
    @Published var nextSide: TapSide? = nil
    @Published var bestTimeText = "—"
    // Metronome: HUD pulses at beatRef + k·beatInterval, alternating sides.
    @Published var beatRef: Date? = nil
    @Published var beatInterval: Double = 0.3
    @Published var beatNextIsRight = false
    @Published var formValue: Double = 0        // rhythm 0..1, drives the FORM meter
    @Published var phaseLabel: String? = nil    // DRIVE / MAX VELOCITY / HOLD FORM

    // MARK: Scene
    let scene = SCNScene()
    let engine = RaceEngine()
    let audio = GameAudio()
    let cameraDirector = CameraDirector()
    private let stadium = Stadium()
    private var figures: [RunnerFigure] = []

    // MARK: Loop bookkeeping (render thread)
    private var lastTime: TimeInterval?
    private var phaseTime: Double = 0
    private var sceneTime: Double = 0
    private var strideCounters = [Int](repeating: 0, count: 8)
    private var uiClockAccum: Double = 0
    private var mapAccum: Double = 0
    private var splitClearAt: Double? = nil
    private var celebrationAt: Double? = nil
    private var lastPrompt: String? = nil
    private var lastNextSide: TapSide? = nil
    private var playerFinishedAt: Double? = nil

    // Input events from the touch view (main) consumed on the render thread.
    // hostTime is CACurrentMediaTime at the touch, used to score taps at their
    // true moment rather than the next frame boundary.
    private let inputLock = NSLock()
    private var pendingInputs: [(side: TapSide, isDown: Bool, hostTime: Double)] = []
    private var heldSides: Set<Bool> = []   // true = right
    private var sideDownAt: [Bool: Double] = [:]   // engine time each side last went down
    private var playerLeanUntil: Double = 0        // scene time: dip pose held until then

    // Haptics
    private let tapHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let stumbleHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let successHaptic = UINotificationFeedbackGenerator()

    // Autopilot (DEBUG tuning aid): launch with -autopilot [-apq 0.9]
    private let autopilot = CommandLine.arguments.contains("-autopilot")
    /// With -aponce, the autopilot stops after one race so the results screen can be inspected.
    private let autopilotOnce = CommandLine.arguments.contains("-aponce")
    private var autoQuality: Double {
        if let i = CommandLine.arguments.firstIndex(of: "-apq"), i + 1 < CommandLine.arguments.count,
           let v = Double(CommandLine.arguments[i + 1]) { return v }
        return 0.88
    }
    private var nextAutoTap: Double = 0
    private var autoSide: TapSide = .left

    override init() {
        super.init()
        stadium.build(into: scene)
        scene.rootNode.addChildNode(cameraDirector.node)

        engine.loadField()
        for r in engine.runners {
            let fig = RunnerFigure(athlete: r.athlete, leftLegForward: r.lane % 2 == 0)
            fig.root.position = SCNVector3(Roster.laneX(r.lane), 0, -1.4)
            fig.mode = .idle
            scene.rootNode.addChildNode(fig.root)
            figures.append(fig)
        }
        bestTimeText = Self.formatPB(storedPB)
        tapHaptic.prepare()
        heavyHaptic.prepare()
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
            nextAutoTap = 0
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
            nextAutoTap = 0
            engine.setPhase(.marks)
            phaseTime = 0
            cameraDirector.mode = .set
            let px = Roster.laneX(Roster.playerLane)
            cameraDirector.snap(to: SIMD3(px + 0.9, 1.25, -4.6), look: SIMD3(px, 0.75, 3))
            audio.crowdTarget = 0.4
        }
        publish { $0.uiPhase = .marks; $0.summary = nil; $0.resultRows = [] }
        audio.playTick()
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
        runAutopilot()

        let events = engine.update(dt: dt)
        handle(events: events)
        updatePhaseLogic(dt: dt)
        updateFigures(dt: dt)
        updateCamera(dt: dt)
        updateScoreboardAndHUD(dt: dt)
        stadium.update(time: time)
        audio.update(dt: dt)
    }

    private func processInputs() {
        inputLock.lock()
        let inputs = pendingInputs
        pendingInputs.removeAll()
        inputLock.unlock()

        for (side, isDown, hostTime) in inputs {
            if isDown { heldSides.insert(side == .right) } else { heldSides.remove(side == .right) }
            // Engine-clock moment of this touch (correct for render latency).
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
                    audio.playSetBeep()
                    audio.playHeartbeat()
                    audio.crowdTarget = 0.08   // the stadium holds its breath
                    publish { $0.uiPhase = .set }
                    DispatchQueue.main.async { self.heavyHaptic.impactOccurred(intensity: 0.6) }
                }
            case .set:
                // Any movement in the blocks before the gun = false start.
                _ = engine.playerTap(side: side, engineTime: engineT)
                publish { $0.verdictFlash = VerdictFlash(text: "FALSE START", good: false) }
            case .racing:
                if !engine.playerLaunched {
                    // First movement after the gun launches the sprint (up or down).
                    if let v = engine.playerTap(side: side, engineTime: engineT) {
                        flashVerdict(v)
                        publishBeat()
                    }
                } else if isDown {
                    // Both thumbs planted in the final meters = the lean.
                    let opposite = side == .left
                    let oppositeHeldLong = heldSides.contains(opposite)
                        && (engineT - (sideDownAt[opposite] ?? -1)) > 0.12
                    if oppositeHeldLong, engine.player.distance >= engine.tuning.leanZone,
                       let v = engine.executeLean() {
                        flashVerdict(v)
                        playerLeanUntil = sceneTime + 0.55
                        DispatchQueue.main.async { self.heavyHaptic.impactOccurred() }
                    } else if let v = engine.playerTap(side: side, engineTime: engineT) {
                        flashVerdict(v)
                        publishBeat()
                    }
                    sideDownAt[side == .right] = engineT
                }
            default:
                break
            }
        }
    }

    /// Re-anchor the HUD metronome after each scored tap.
    private func publishBeat() {
        guard let beatAt = engine.nextBeatAt else { return }
        let delta = beatAt - engine.timeSinceGun
        let ref = Date(timeIntervalSinceNow: delta)
        let interval = engine.playerIdealTapInterval
        let nextRight = engine.expectedNextSide == .right
        publish {
            $0.beatRef = ref
            $0.beatInterval = interval
            $0.beatNextIsRight = nextRight
        }
    }

    private func flashVerdict(_ v: TapVerdict) {
        let good = v == .perfect || v == .good || v == .lean
        switch v {
        case .perfect, .good:
            DispatchQueue.main.async { self.tapHaptic.impactOccurred(intensity: v == .perfect ? 1.0 : 0.6) }
        case .stumble:
            cameraDirector.impulse(0.5)
            DispatchQueue.main.async { self.stumbleHaptic.impactOccurred() }
        default:
            DispatchQueue.main.async { self.tapHaptic.impactOccurred(intensity: 0.35) }
        }
        // Only surface notable feedback; PERFECT spam would wallpaper the screen.
        if v != .good {
            publish { $0.verdictFlash = VerdictFlash(text: v.rawValue, good: good) }
        }
    }

    private func skipIntro() {
        engine.setPhase(.marks)
        phaseTime = 0
        cameraDirector.mode = .set
        let px = Roster.laneX(Roster.playerLane)
        cameraDirector.snap(to: SIMD3(px + 0.9, 1.25, -4.6), look: SIMD3(px, 0.75, 3))
        publish { $0.uiPhase = .marks; $0.introCard = nil }
    }

    // MARK: Events & phase flow

    private func handle(events: RaceEngine.FrameEvents) {
        if events.gunJustFired {
            audio.playGun()
            audio.crowdTarget = 0.65
            cameraDirector.impulse(0.55)
            cameraDirector.mode = .chase
            publish {
                $0.uiPhase = .racing
                $0.gunFlash = true
            }
            DispatchQueue.main.async {
                self.heavyHaptic.impactOccurred()
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

        for r in events.runnersJustFinished where r.athlete.isPlayer {
            playerFinishedAt = phaseTime
            audio.playCheer()
            audio.crowdTarget = 0.95
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
            beginCelebrationAndResults()
        }
    }

    private func beginCelebrationAndResults() {
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
        if isNewPB { audio.playPB() }

        publish {
            $0.resultRows = rows
            $0.summary = sum
            $0.uiPhase = .results
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

    private func runAutopilot() {
        guard autopilot else { return }
        switch engine.phase {
        case .menu:
            if phaseTime > 1.0 { publish { $0.startRaceFromAuto() } ; phaseTime = 0 }
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
                    _ = engine.playerTap(side: autoSide, engineTime: 0.14)
                    scheduleNextAutoTap()
                    publishBeat()
                }
            } else if engine.player.distance > 98.2, engine.leanExecutedAt == nil,
                      engine.player.finishTime == nil {
                _ = engine.executeLean()
            } else if engine.timeSinceGun >= nextAutoTap {
                autoSide = autoSide == .left ? .right : .left
                // Score the tap at its intended moment, not the frame boundary.
                _ = engine.playerTap(side: autoSide, engineTime: nextAutoTap)
                scheduleNextAutoTap()
                publishBeat()
            }
        case .results:
            if !autopilotOnce, phaseTime > 6 { publish { $0.runAgain() }; phaseTime = 0 }
        default:
            break
        }
    }

    private func scheduleNextAutoTap() {
        let sd = 0.020 + (1 - autoQuality) * 0.25
        let u1 = Double.random(in: 0.001...0.999), u2 = Double.random(in: 0...1)
        let g = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        let base = engine.playerLaunched ? max(nextAutoTap, engine.player.reaction) : engine.timeSinceGun
        nextAutoTap = base + engine.playerIdealTapInterval * (1 + g * sd)
    }

    fileprivate func startRaceFromAuto() { startRace() }

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

            // Acceleration lean: deep at launch, upright at speed.
            var lean = max(0.06, 0.58 * (1 - r.velocity / 11.5))
            // The dip at the line.
            if r.athlete.isPlayer, sceneTime < playerLeanUntil { lean = 0.85 }
            fig.update(phase: r.stridePhase, speed: r.velocity, lean: r.velocity > 0.2 ? lean : 0.1,
                       time: sceneTime)

            // Footstep audio: two steps per stride cycle.
            let stepCount = Int(r.stridePhase * 2)
            if stepCount > strideCounters[i], r.velocity > 1 {
                strideCounters[i] = stepCount
                if r.athlete.isPlayer {
                    audio.playFootstep(loud: true)
                } else if abs(r.distance - engine.player.distance) < 6, i % 2 == 0 {
                    audio.playFootstep(loud: false)
                }
            }
        }
    }

    private func updateCamera(dt: Double) {
        let p = engine.player
        cameraDirector.update(dt: dt, time: sceneTime, introT: phaseTime,
                              playerX: Roster.laneX(Roster.playerLane),
                              playerZ: Float(p.distance) - 0.35,
                              v: Float(p.velocity),
                              phase: Float(p.stridePhase))
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
            let speedStr = String(format: "%.1f", engine.player.velocity)
            let promptStr = currentPrompt()
            let next = nextExpectedSide()
            let form = engine.rhythm
            let racing = engine.phase == .racing && engine.playerLaunched
            let phaseStr: String? = racing ? engine.sprintPhase.rawValue : nil
            publish {
                $0.clockText = clockStr
                $0.speedText = speedStr
                $0.formValue = form
                if $0.prompt != promptStr { $0.prompt = promptStr }
                if $0.nextSide != next { $0.nextSide = next }
                if $0.phaseLabel != phaseStr { $0.phaseLabel = phaseStr }
                if !racing, $0.beatRef != nil { $0.beatRef = nil }
            }
            lastPrompt = promptStr
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
            if !engine.playerLaunched { return "GO! TAP!" }
            if engine.player.finishTime == nil, engine.player.distance > 88,
               engine.leanExecutedAt == nil {
                return "LEAN — PLANT BOTH THUMBS"
            }
            return engine.timeSinceGun < 2.0 ? "TAP WITH THE PULSE" : nil
        default: return nil
        }
    }

    private func nextExpectedSide() -> TapSide? {
        guard engine.phase == .racing, engine.playerLaunched else { return nil }
        return engine.expectedNextSide
    }
}
