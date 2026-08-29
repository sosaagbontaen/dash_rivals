import Foundation

/// Which half of the screen a touch landed on (used for the set-hold and the lean).
enum TapSide { case left, right }

/// Transient feedback events surfaced in the HUD.
enum TapVerdict: String {
    case falseStart = "FALSE START"
    case relax = "RELAX — EASE OFF"
    case lean = "LEAN!"
    case surge = "SURGE ✓"
    case still = "BE STILL"
}

/// The two player mechanics under A/B evaluation (menu toggle).
enum SprintMechanic: String {
    case band       // one thumb rides the choreographed effort band
    case moments    // drive mash → hands-off flight + timed surges → fade → lean
}

/// The player's sprint unfolds in three phases (display flavor; the band drives play).
enum SprintPhaseKind: String {
    case drive = "DRIVE"
    case maxVelocity = "MAX VELOCITY"
    case maintain = "HOLD ON"
}

/// The moving effort target the player's thumb rides.
struct EffortBand {
    let center: Double   // 0..1
    let half: Double     // half-width, 0..1
}

/// Live state of one runner during a race.
final class RunnerState {
    let athlete: Athlete
    let lane: Int

    var distance: Double = 0
    var velocity: Double = 0
    var reaction: Double = 0            // this race's reaction time
    var finishTime: Double? = nil       // official time (includes reaction)
    var split50: Double? = nil
    var topSpeed: Double = 0

    // AI shape for this race (recomputed each race)
    var aiVmax: Double = 0
    var aiTau: Double = 1.25
    var aiK: Double = 0.002

    // Animation bookkeeping
    var stridePhase: Double = 0         // 0..1, full cycle (two steps)

    init(athlete: Athlete, lane: Int) {
        self.athlete = athlete
        self.lane = lane
    }
}

enum RacePhase: Equatable {
    case menu
    case intro          // camera pans across the field
    case marks          // waiting for player to hold both sides
    case set            // holding, waiting for the gun
    case racing
    case finished       // player crossed, others finishing / celebration
    case results
}

struct RaceResultRow: Identifiable {
    let id = UUID()
    let place: Int
    let athlete: Athlete
    let time: Double?
    let reaction: Double
    let isPlayer: Bool
}

/// 100m simulation: 7 parameterized AI + 1 player.
///
/// The player mechanic is continuous, not timing-based: one thumb rides a vertical
/// "effort" position against a choreographed target band that follows a real sprint's
/// arc — push hard in the drive, *relax* into max velocity, then chase the band down
/// through the finish as the body decelerates. Riding above the band builds tension,
/// and tension is what makes you decelerate faster (tighten up = slow down).
final class RaceEngine {
    // MARK: Tunables (player model)
    struct Tuning {
        var playerTopSpeed = 11.55          // m/s ceiling with perfect tracking
        var accelMax = 9.6                  // m/s^2 at standstill
        var launchImpulse = 2.3             // m/s from the block clearance
        var driveEnd = 30.0                 // m: display phase boundary
        var maxVEnd = 80.0                  // m: display phase boundary
        var fatigueOnset = 5.8              // s of running before fatigue can bite
        var fatigueK = 0.0022               // late-race decay factor
        var tensionSpeedCut = 0.06          // fraction of vEff lost at full tension
        var tensionDecel = 0.6              // m/s^2 at full tension
        var leanZone = 94.0                 // m: second-thumb lean armed from here
        var leanBestAt = 98.6               // m: a dip here lands exactly on the line
        var leanMaxCredit = 0.03            // s saved by a perfectly timed lean
    }
    var tuning = Tuning()

    private(set) var runners: [RunnerState] = []
    private(set) var phase: RacePhase = .menu
    private(set) var clock: Double = 0              // official race clock (0 at gun)
    private(set) var gunFired = false

    /// Active player mechanic (set from the menu; applies from the next race).
    var mechanic: SprintMechanic = .band

    // Moments-mechanic state (drive mash; from 30m the band takes over)
    private(set) var burn: Double = 0               // drive-phase rev debt, 0..1.1
    private var rateEMA: Double = 3.0               // recent drive tap rate (Hz)
    private var lastDriveTapAt: Double = 0

    // Player effort-band state (two thumbs, one gauge each, same target band)
    private var rawL: Double = 0.85
    private var rawR: Double = 0.85
    private var activeL = false
    private var activeR = false
    private(set) var playerEffortL: Double = 0.85   // smoothed, 0..1
    private(set) var playerEffortR: Double = 0.85
    private(set) var playerEffort: Double = 0.85    // combined
    private var prevCombined: Double = 0.85
    private var dropAccum: Double = 0               // fast both-thumb drop = the dip
    private(set) var tension: Double = 0            // 0..1, builds when over the band
    private(set) var qBar: Double = 0.9             // tracking quality EMA ("FORM")
    private var bandSeed1: Double = 0
    private var bandSeed2: Double = 0

    private(set) var playerLaunched = false
    private(set) var falseStarted = false
    private var stunUntil: Double = 0
    private(set) var leanExecutedAt: Double? = nil  // distance where the player dipped
    private(set) var leanCredit: Double = 0

    // Timeline
    private var phaseTime: Double = 0               // seconds inside current phase
    private var gunDelay: Double = 1.6              // set -> gun
    private(set) var timeSinceGun: Double = 0

    var player: RunnerState { runners[Roster.playerIndex] }

    /// Current sprint phase, by distance covered (display flavor).
    var sprintPhase: SprintPhaseKind {
        let d = player.distance
        if d < tuning.driveEnd { return .drive }
        if d < tuning.maxVEnd { return .maxVelocity }
        return .maintain
    }

    // MARK: The band

    /// Learnable "breathe" dips — same distances every race, so they reward mastery.
    static let breatheDips: [Double] = [40, 64, 86]

    /// The effort target at a given distance/time. Choreography: hard drive →
    /// sharp relax into max velocity → a slow sink through the final 20m with the
    /// wobble ramping up (the fight against deceleration).
    func band(atDistance d: Double, time t: Double) -> EffortBand {
        var c: Double; var h: Double
        switch d {
        case ..<30:  c = 0.90; h = 0.10
        case ..<42:  c = 0.90 - 0.13 * ((d - 30) / 12); h = 0.10 - 0.02 * ((d - 30) / 12)
        case ..<80:  c = 0.77 - 0.02 * ((d - 42) / 38); h = 0.08 - 0.012 * ((d - 42) / 38)
        default:     c = 0.75 - 0.14 * ((d - 80) / 20); h = 0.066
        }
        for dip in Self.breatheDips {
            let x = abs(d - dip)
            if x < 3.0 { c -= 0.08 * (1 - x / 3.0) }
        }
        let amp = d < 42 ? 0.015 : (d < 80 ? 0.035 : 0.07)
        c += amp * (sin(2 * .pi * 0.55 * t + bandSeed1) * 0.6 + sin(2 * .pi * 1.15 * t + bandSeed2) * 0.4)
        return EffortBand(center: max(0.2, min(0.97, c)), half: h)
    }

    var currentBand: EffortBand {
        band(atDistance: player.distance, time: timeSinceGun)
    }

    // MARK: Race lifecycle

    func loadField() {
        runners = Roster.athletes.enumerated().map { RunnerState(athlete: $1, lane: $0 + 1) }
    }

    /// Prepare a fresh race (does not start the clock).
    func resetRace() {
        if runners.isEmpty { loadField() }
        for r in runners {
            r.distance = 0
            r.velocity = 0
            r.finishTime = nil
            r.split50 = nil
            r.topSpeed = 0
            r.stridePhase = 0
            if !r.athlete.isPlayer {
                // This race's target: usually a touch over PB, occasionally close to it.
                let jitter = gaussian(mean: 0.055, sd: 0.065)
                let target = r.athlete.personalBest + max(-0.03, jitter)
                r.aiTau = r.athlete.accelTau
                r.aiK = r.athlete.enduranceK
                r.reaction = max(0.105, gaussian(mean: r.athlete.reactionMean, sd: 0.014))
                r.aiVmax = Self.solveVmax(targetTime: target, reaction: r.reaction, tau: r.aiTau, k: r.aiK)
            }
        }
        clock = 0
        timeSinceGun = 0
        gunFired = false
        rawL = 0.85; rawR = 0.85
        activeL = false; activeR = false
        playerEffortL = 0.85; playerEffortR = 0.85
        playerEffort = 0.85
        prevCombined = 0.85
        dropAccum = 0
        tension = 0
        qBar = 0.9
        bandSeed1 = Double.random(in: 0...(2 * .pi))
        bandSeed2 = Double.random(in: 0...(2 * .pi))
        playerLaunched = false
        falseStarted = false
        stunUntil = 0
        leanExecutedAt = nil
        leanCredit = 0
        burn = 0
        rateEMA = 3.0
        lastDriveTapAt = 0
        phaseTime = 0
    }

    func setPhase(_ p: RacePhase) {
        phase = p
        phaseTime = 0
        if p == .set {
            gunDelay = Double.random(in: 1.35...2.3)
        }
    }

    // MARK: Player input

    /// Both thumbs down during .marks -> crouch into set.
    func playerIsSet() {
        guard phase == .marks else { return }
        setPhase(.set)
    }

    /// Any movement in the blocks before the gun (POC: time penalty, no DQ).
    func playerFalseStart() {
        guard phase == .set else { return }
        falseStarted = true
        stunUntil = 0.24
    }

    /// First movement after the gun — the thumb lift out of the blocks.
    func playerLaunch(engineTime: Double) {
        guard phase == .racing, gunFired, !playerLaunched else { return }
        playerLaunched = true
        player.reaction = falseStarted ? 0.30 : max(0.08, min(timeSinceGun, engineTime))
        player.velocity = tuning.launchImpulse
        lastDriveTapAt = player.reaction
    }

    // MARK: Moments-mechanic input

    /// A drive-phase power step. No timing windows: rate is intensity, and intensity
    /// both accelerates you and accrues burn you pay for after 80m.
    @discardableResult
    func momentsDriveTap(engineTime: Double) -> Bool {
        guard mechanic == .moments, phase == .racing, playerLaunched,
              player.finishTime == nil, player.distance < 32 else { return false }
        let now = min(timeSinceGun, max(engineTime, lastDriveTapAt + 0.02))
        let gap = now - lastDriveTapAt
        let instR = min(7.0, 1.0 / max(0.08, gap))
        rateEMA = rateEMA * 0.7 + min(instR, 5.5) * 0.3
        burn = min(1.1, burn + 0.05 * pow(instR / 4.5, 1.6))
        // Taps beyond the biomechanical cap waste sharply (mashing self-defeats).
        let popScale = instR <= 4.8 ? 1.0 : pow(4.8 / instR, 2)
        player.velocity += 0.42 * popScale * max(0, 1 - player.velocity / 11.2)
        lastDriveTapAt = now
        return true
    }


    /// Autopilot / single-source effort: drives both thumbs identically.
    func setPlayerEffort(_ e: Double) {
        let v = max(0, min(1, e))
        rawL = v; rawR = v
        activeL = true; activeR = true
    }

    /// Per-thumb effort from the touch layer; nil = that thumb is off the glass.
    func setPlayerEfforts(left: Double?, right: Double?) {
        if let l = left { rawL = max(0, min(1, l)) }
        if let r = right { rawR = max(0, min(1, r)) }
        activeL = left != nil
        activeR = right != nil
    }

    /// Second thumb planted in the final meters: the dip at the line.
    @discardableResult
    func executeLean() -> TapVerdict? {
        guard phase == .racing, playerLaunched, player.finishTime == nil,
              leanExecutedAt == nil, player.distance >= tuning.leanZone else { return nil }
        let d = player.distance
        leanExecutedAt = d
        leanCredit = tuning.leanMaxCredit * max(0, 1 - abs(tuning.leanBestAt - d) / 3.5)
        player.velocity *= 0.985   // the dip costs a touch of speed — don't go too early
        return .lean
    }

    /// Late-race fade. Band: better tracking postpones it. Moments: burn brings it on.
    var currentFatigue: Double {
        let t = timeSinceGun
        guard t > tuning.fatigueOnset else { return 1.0 }
        let k: Double
        switch mechanic {
        case .band: k = tuning.fatigueK * (1.35 - 0.5 * qBar)
        case .moments: k = tuning.fatigueK * (1 + 0.9 * max(0, burn - 0.5))
        }
        return max(0.90, 1.0 - k * pow(t - tuning.fatigueOnset, 2))
    }

    // MARK: Simulation

    struct FrameEvents {
        var gunJustFired = false
        var runnersJustFinished: [RunnerState] = []
        var playerCrossed50 = false
        var raceComplete = false
    }

    func update(dt: Double) -> FrameEvents {
        var ev = FrameEvents()
        phaseTime += dt

        switch phase {
        case .set:
            if phaseTime >= gunDelay {
                gunFired = true
                setPhase(.racing)
                ev.gunJustFired = true
            }
        case .racing, .finished:
            timeSinceGun += dt
            clock = timeSinceGun
            step(dt: dt, events: &ev)
        default:
            break
        }
        return ev
    }

    private func step(dt: Double, events: inout FrameEvents) {
        for r in runners {
            guard r.finishTime == nil || r.velocity > 0.3 else { continue }
            let before = r.distance
            if r.athlete.isPlayer {
                stepPlayer(r, dt: dt)
            } else {
                stepAI(r, dt: dt)
            }
            r.topSpeed = max(r.topSpeed, r.velocity)

            // Stride phase advance. Turnover is frantic from the first step —
            // block exits are ~4 steps/s, not a jog that speeds up.
            let freq = 1.7 + 1.1 * (r.velocity / 12.0)    // full cycles per second
            r.stridePhase += Double(freq) * dt * (r.velocity > 0.2 ? 1 : 0)

            if r.finishTime == nil {
                if before < 50, r.distance >= 50 {
                    r.split50 = clock - (r.distance - 50) / max(0.1, r.velocity)
                    if r.athlete.isPlayer { events.playerCrossed50 = true }
                }
                if r.distance >= Double(Track.raceLength) {
                    var t = clock - (r.distance - Double(Track.raceLength)) / max(0.1, r.velocity)
                    if r.athlete.isPlayer { t -= leanCredit }   // the dip gets the chest there sooner
                    r.finishTime = t
                    events.runnersJustFinished.append(r)
                }
            }
        }
        if runners.allSatisfy({ $0.finishTime != nil }) {
            events.raceComplete = true
        }
    }

    private func stepAI(_ r: RunnerState, dt: Double) {
        let t = timeSinceGun - r.reaction
        guard t > 0 else { return }
        if r.finishTime != nil {
            r.velocity = max(0, r.velocity - 3.6 * dt)   // run-out
            r.distance += r.velocity * dt
            return
        }
        // v(t) = vmax (1 - e^(-t/tau)) with late-race decay.
        var v = r.aiVmax * (1 - exp(-t / r.aiTau))
        if t > 6.0 {
            let f = 1.0 - r.aiK * pow(t - 6.0, 2)
            v *= max(0.90, f)
        }
        r.velocity = v
        r.distance += v * dt
    }

    private func stepPlayer(_ r: RunnerState, dt: Double) {
        guard gunFired else { return }
        if r.finishTime != nil {
            r.velocity = max(0, r.velocity - 3.4 * dt)
            r.distance += r.velocity * dt
            return
        }
        // False-start stun: brief freeze right after the gun.
        if falseStarted, timeSinceGun < stunUntil { return }
        guard playerLaunched else { return }

        switch mechanic {
        case .band: stepPlayerBand(r, dt: dt)
        case .moments: stepPlayerMoments(r, dt: dt)
        }
    }

    private func stepPlayerMoments(_ r: RunnerState, dt: Double) {
        if r.distance < 30 {
            // Drive: acceleration flows while taps keep landing, scaled by intensity.
            if timeSinceGun - lastDriveTapAt < 0.45 {
                let A = 8.5 * min(1.12, max(0.22, rateEMA / 4.4))
                r.velocity += A * max(0, 1 - r.velocity / 11.2) * dt
            }
            r.velocity = max(0, r.velocity)
            r.distance += r.velocity * dt
        } else {
            // From 30m the race becomes the band: grab the gauges and ride it home.
            // Burn from the drive feeds the fatigue model (see currentFatigue).
            stepPlayerBand(r, dt: dt)
        }
    }

    private func stepPlayerBand(_ r: RunnerState, dt: Double) {
        // Per-thumb smoothing so touch jitter isn't punished directly.
        playerEffortL += (rawL - playerEffortL) * min(1, dt * 14)
        playerEffortR += (rawR - playerEffortR) * min(1, dt * 14)
        let both = activeL && activeR
        if both { playerEffort = (playerEffortL + playerEffortR) / 2 }
        else if activeL { playerEffort = playerEffortL }
        else if activeR { playerEffort = playerEffortR }
        // (both thumbs off: effort holds its last value)

        // The dip at the line: both thumbs yanked down fast.
        let drop = max(0, prevCombined - playerEffort)
        dropAccum = dropAccum * exp(-dt * 9) + drop
        prevCombined = playerEffort
        if r.distance >= tuning.leanZone, leanExecutedAt == nil, dropAccum > 0.20 {
            _ = executeLean()
        }

        let b = currentBand
        let err = (playerEffort - b.center) / b.half
        var q: Double
        if abs(err) <= 1 {
            q = 1 - 0.25 * err * err
            tension = max(0, tension - dt * 0.25)
        } else if err > 1 {
            // Over the band: still driving, but tightening up.
            q = max(0.45, 1 - 0.35 * (err - 1))
            tension = min(1, tension + dt * min(2.5, (err - 1) * 1.6))
        } else {
            // Under the band: relaxed but underpowered.
            q = max(0.30, 1 - 0.42 * (-err - 1))
            tension = max(0, tension - dt * 0.35)
        }
        // Run with both arms: thumbs drifting apart costs form.
        if both {
            let div = abs(playerEffortL - playerEffortR)
            q *= 1 - 0.4 * min(1, div / 0.3)
        }
        qBar += (q - qBar) * dt * 1.4

        let vEff = tuning.playerTopSpeed
            * (0.76 + 0.24 * pow(qBar, 1.6))
            * currentFatigue
            * (1 - tuning.tensionSpeedCut * tension)
        if r.velocity < vEff {
            r.velocity += tuning.accelMax * (0.2 + 0.8 * qBar) * max(0, 1 - r.velocity / vEff) * dt
        } else {
            r.velocity -= 2.4 * dt
        }
        r.velocity -= tension * tuning.tensionDecel * dt
        r.velocity = max(0, r.velocity)
        r.distance += r.velocity * dt
    }

    // MARK: Results

    func results() -> [RaceResultRow] {
        let sorted = runners.sorted {
            ($0.finishTime ?? 99) < ($1.finishTime ?? 99)
        }
        return sorted.enumerated().map { i, r in
            RaceResultRow(place: i + 1, athlete: r.athlete, time: r.finishTime,
                          reaction: r.reaction, isPlayer: r.athlete.isPlayer)
        }
    }

    var playerPlace: Int {
        let t = player.finishTime ?? 99
        return runners.filter { ($0.finishTime ?? 98) < t }.count + 1
    }

    // MARK: Math helpers

    /// Find vmax such that the runner covers 100m at `targetTime` (official time incl. reaction).
    static func solveVmax(targetTime: Double, reaction: Double, tau: Double, k: Double) -> Double {
        let runTime = targetTime - reaction
        func distance(_ vmax: Double) -> Double {
            var d = 0.0
            var t = 0.0
            let dt = 0.01
            while t < runTime {
                var v = vmax * (1 - exp(-t / tau))
                if t > 6.0 { v *= max(0.90, 1.0 - k * pow(t - 6.0, 2)) }
                d += v * dt
                t += dt
            }
            return d
        }
        var lo = 9.0, hi = 13.5
        for _ in 0..<28 {
            let mid = (lo + hi) / 2
            if distance(mid) < 100 { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    private func gaussian(mean: Double, sd: Double) -> Double {
        let u1 = Double.random(in: 0.0001...0.9999)
        let u2 = Double.random(in: 0...1)
        return mean + sd * sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
