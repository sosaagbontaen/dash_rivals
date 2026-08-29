import Foundation

/// Which half of the screen a tap landed on.
enum TapSide { case left, right }

/// Player tap timing feedback, surfaced in the HUD.
enum TapVerdict: String {
    case perfect = "PERFECT"
    case good = "GOOD"
    case early = "EARLY"
    case late = "LATE"
    case stumble = "STUMBLE"
    case lean = "LEAN!"
}

/// The player's sprint unfolds in three phases (see BRIEF.md's sprint model).
/// Each has its own target cadence and timing tolerance.
enum SprintPhaseKind: String {
    case drive = "DRIVE"
    case maxVelocity = "MAX VELOCITY"
    case maintain = "HOLD FORM"
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

/// Deterministic-ish 100m simulation for 8 runners: 7 parameterized AI + 1 input-driven player.
final class RaceEngine {
    // MARK: Tunables (player model)
    struct Tuning {
        var playerTopSpeed = 11.45          // m/s, ceiling with perfect rhythm
        var accelMax = 9.4                  // m/s^2 at standstill
        var launchImpulse = 1.9             // m/s granted by first stride off the blocks
        var driveImpulse = 0.55             // extra m/s per quality drive-phase tap
        var driveEnd = 28.0                 // meters: end of the drive phase
        var maxVEnd = 82.0                  // meters: end of max velocity, fatigue zone begins
        var fatigueOnset = 5.8              // seconds of running before fatigue can bite
        var fatigueK = 0.0022               // late-race decay factor
        var driveFreqStart = 3.1            // taps/sec at the first drive step
        var driveFreqEnd = 4.3              // taps/sec at the end of the drive
        var topFreq = 4.4                   // taps/sec at max velocity
        var coastDecel = 2.8                // m/s^2 bleed when not tapping
        var stumblePenalty = 0.42           // rhythm multiplier on a stumble
        var leanZone = 94.0                 // meters: both-thumbs lean armed from here
        var leanBestAt = 98.6               // meters: a dip here lands exactly on the line
        var leanMaxCredit = 0.03            // seconds saved by a perfectly timed lean
    }
    var tuning = Tuning()

    private(set) var runners: [RunnerState] = []
    private(set) var phase: RacePhase = .menu
    private(set) var clock: Double = 0              // official race clock (0 at gun)
    private(set) var gunFired = false

    // Player rhythm state
    private(set) var rhythm: Double = 0             // 0..1 exponentially-averaged tap quality
    private var lastTapTime: Double? = nil
    private var lastTapSide: TapSide? = nil
    private(set) var playerLaunched = false
    private(set) var falseStarted = false
    private var stunUntil: Double = 0
    private(set) var leanExecutedAt: Double? = nil    // distance where the player dipped
    private(set) var leanCredit: Double = 0

    // Timeline
    private var phaseTime: Double = 0               // seconds inside current phase
    private var gunDelay: Double = 1.6              // set -> gun
    private(set) var timeSinceGun: Double = 0

    var player: RunnerState { runners[Roster.playerIndex] }
    /// Which side the player should tap next (for HUD guidance).
    var expectedNextSide: TapSide? {
        guard let last = lastTapSide else { return nil }
        return last == .left ? .right : .left
    }

    /// Current sprint phase, by distance covered.
    var sprintPhase: SprintPhaseKind {
        let d = player.distance
        if d < tuning.driveEnd { return .drive }
        if d < tuning.maxVEnd { return .maxVelocity }
        return .maintain
    }

    /// Target cadence is a function of *distance*, not velocity, so it ramps
    /// predictably: a rhythm the player can learn and anticipate.
    var playerIdealTapInterval: Double {
        let d = player.distance
        let f: Double
        if d < tuning.driveEnd {
            f = tuning.driveFreqStart + (tuning.driveFreqEnd - tuning.driveFreqStart) * (d / tuning.driveEnd)
        } else {
            f = tuning.topFreq
        }
        return 1.0 / f
    }

    /// Engine-clock moment of the next ideal tap — the metronome the HUD pulses to.
    var nextBeatAt: Double? {
        guard playerLaunched, phase == .racing, player.finishTime == nil else { return nil }
        return (lastTapTime ?? player.reaction) + playerIdealTapInterval
    }

    /// Timing tolerance per phase: generous in the drive, tight at top speed,
    /// slightly loose (but heavily punished by fatigue) at the end.
    private var deadzone: Double {
        switch sprintPhase {
        case .drive: return 0.10
        case .maxVelocity: return 0.06
        case .maintain: return 0.07
        }
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
        rhythm = 0
        lastTapTime = nil
        lastTapSide = nil
        playerLaunched = false
        falseStarted = false
        stunUntil = 0
        leanExecutedAt = nil
        leanCredit = 0
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

    /// A tap during the race or the gun window.
    /// `engineTime` is the tap's moment on the race clock (touch-timestamp corrected,
    /// so scoring quality is independent of frame rate / render latency).
    /// Returns the verdict for haptics/UI, or nil if the tap was ignored.
    @discardableResult
    func playerTap(side: TapSide, engineTime: Double) -> TapVerdict? {
        switch phase {
        case .set:
            // Moving before the gun: false start (POC: time penalty, no DQ).
            falseStarted = true
            stunUntil = 0.24 // applied relative to gun; see update
            return .early
        case .racing:
            guard gunFired else { return nil }
            if !playerLaunched {
                playerLaunched = true
                player.reaction = falseStarted ? 0.30 : max(0.08, min(timeSinceGun, engineTime))
                player.velocity = tuning.launchImpulse
                lastTapTime = player.reaction
                lastTapSide = side
                rhythm = 0.85
                return player.reaction < 0.16 ? .perfect : (player.reaction < 0.25 ? .good : .late)
            }
            return scoreStride(side: side, at: engineTime)
        default:
            return nil
        }
    }

    /// Both thumbs planted in the final meters: the dip at the line.
    /// Best executed so the chest drops right on the line; too early bleeds speed.
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

    /// Late-race fade; steadier rhythm postpones it.
    var currentFatigue: Double {
        let t = timeSinceGun
        guard t > tuning.fatigueOnset else { return 1.0 }
        let k = tuning.fatigueK * (1.35 - 0.5 * rhythm)
        return max(0.90, 1.0 - k * pow(t - tuning.fatigueOnset, 2))
    }

    private func scoreStride(side: TapSide, at engineTime: Double) -> TapVerdict {
        let now = min(timeSinceGun, max(engineTime, (lastTapTime ?? 0) + 0.01))
        let ideal = playerIdealTapInterval
        let dt = now - (lastTapTime ?? now)
        var verdict: TapVerdict

        if side == lastTapSide || dt < ideal * 0.45 {
            // Same thumb twice, or machine-gunning: stumble.
            verdict = .stumble
            rhythm *= tuning.stumblePenalty
            player.velocity *= 0.94
        } else {
            let err = abs(dt - ideal) / ideal
            // Dead zone + steep falloff: execution quality must matter.
            let dz = deadzone
            let q = err < dz ? 1.0 : max(0.05, 1.0 - (err - dz) * 2.8)
            if err < dz { verdict = .perfect }
            else if err < dz + 0.12 { verdict = .good }
            else { verdict = dt < ideal ? .early : .late }
            rhythm = rhythm * 0.55 + min(1.0, q) * 0.45
            // Drive phase: every well-timed tap is a power step off the ground.
            if sprintPhase == .drive {
                let fatigue = currentFatigue
                let vEff = tuning.playerTopSpeed * (0.70 + 0.30 * pow(rhythm, 1.6)) * fatigue
                player.velocity += tuning.driveImpulse * q * max(0, 1 - player.velocity / vEff)
            }
        }
        lastTapTime = now
        lastTapSide = side
        return verdict
    }

    // MARK: Simulation

    /// Advance the simulation. Returns events that occurred this frame.
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

            // Stride phase advance: stride frequency tied to speed.
            let freq = 0.4 + 2.15 * (r.velocity / 12.0)   // full cycles per second
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

        // Rhythm decays if the player stops tapping.
        let sinceTap = timeSinceGun - (lastTapTime ?? timeSinceGun)
        let ideal = playerIdealTapInterval
        if sinceTap > ideal * 1.55 {
            rhythm *= exp(-dt * 3.2)
        }

        // Wide rhythm band + superlinear response: execution quality separates times.
        let rEff = pow(rhythm, 1.6)
        let vEff = tuning.playerTopSpeed * (0.70 + 0.30 * rEff) * currentFatigue
        if r.velocity < vEff {
            let drive = tuning.accelMax * (0.10 + 0.90 * rhythm) * max(0, 1 - r.velocity / vEff)
            r.velocity += drive * dt
        } else {
            // Above sustainable speed (e.g. rhythm collapsed): bleed down.
            r.velocity -= tuning.coastDecel * dt
        }
        if sinceTap > ideal * 2.4 {
            r.velocity = max(0, r.velocity - tuning.coastDecel * dt)
        }
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
            // Integrate the same curve stepAI uses.
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
