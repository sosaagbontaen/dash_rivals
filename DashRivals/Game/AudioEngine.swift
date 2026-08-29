import AVFoundation

/// All game audio is synthesized at launch into PCM buffers — no audio files.
final class GameAudio {
    private let engine = AVAudioEngine()
    private let crowdPlayer = AVAudioPlayerNode()
    private let windPlayer = AVAudioPlayerNode()
    private let sfxPlayers = (0..<5).map { _ in AVAudioPlayerNode() }
    private var sfxIndex = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

    private var crowdLoop: AVAudioPCMBuffer!
    private var windLoop: AVAudioPCMBuffer!
    private var whoosh: AVAudioPCMBuffer!
    private var gun: AVAudioPCMBuffer!
    private var setBeep: AVAudioPCMBuffer!
    private var steps: [AVAudioPCMBuffer] = []
    private var cheer: AVAudioPCMBuffer!
    private var tick: AVAudioPCMBuffer!
    private var pbJingle: AVAudioPCMBuffer!
    private var heartbeat: AVAudioPCMBuffer!
    private var breaths: [AVAudioPCMBuffer] = []

    /// Crowd volume target; ramped smoothly in update().
    var crowdTarget: Float = 0.4
    /// Wind-rush volume target (scaled with player speed); ramped in update().
    var windTarget: Float = 0
    private var started = false

    init() {
        crowdLoop = Synth.crowd(seconds: 7, format: format)
        windLoop = Synth.wind(seconds: 5, format: format)
        whoosh = Synth.whoosh(format: format)
        gun = Synth.gunshot(format: format)
        setBeep = Synth.tone(freq: 700, seconds: 0.5, attack: 0.01, decay: 2.2, gain: 0.35, format: format)
        steps = (0..<3).map { i in Synth.footstep(pitch: 1.0 + Float(i) * 0.12 - 0.12, format: format) }
        cheer = Synth.cheer(format: format)
        tick = Synth.tone(freq: 1250, seconds: 0.06, attack: 0.002, decay: 28, gain: 0.18, format: format)
        pbJingle = Synth.jingle(format: format)
        heartbeat = Synth.heartbeat(format: format)
        breaths = [Synth.breath(pitch: 0.95, grunt: false, format: format),
                   Synth.breath(pitch: 1.12, grunt: false, format: format),
                   Synth.breath(pitch: 1.0, grunt: true, format: format)]

        // .playback so game audio plays even with the ringer/silent switch on
        // (.ambient goes silent on a muted phone — the simulator ignores the switch,
        // which is why it sounded fine there).
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        engine.attach(crowdPlayer)
        engine.connect(crowdPlayer, to: engine.mainMixerNode, format: format)
        engine.attach(windPlayer)
        engine.connect(windPlayer, to: engine.mainMixerNode, format: format)
        for p in sfxPlayers {
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
        }
    }

    func start() {
        guard !started else { return }
        do {
            try engine.start()
            crowdPlayer.volume = 0.35
            crowdPlayer.scheduleBuffer(crowdLoop, at: nil, options: .loops)
            crowdPlayer.play()
            windPlayer.volume = 0
            windPlayer.scheduleBuffer(windLoop, at: nil, options: .loops)
            windPlayer.play()
            started = true
        } catch {
            // Audio is atmosphere, not critical — run silent if the engine fails.
        }
    }

    func update(dt: Double) {
        guard started else { return }
        let step = Float(dt) * 1.2
        let cur = crowdPlayer.volume
        if abs(cur - crowdTarget) > 0.005 {
            crowdPlayer.volume = cur + max(-step, min(step, crowdTarget - cur))
        }
        let wStep = Float(dt) * 2.0
        let wCur = windPlayer.volume
        if abs(wCur - windTarget) > 0.005 {
            windPlayer.volume = wCur + max(-wStep, min(wStep, windTarget - wCur))
        }
    }

    private func playSFX(_ buffer: AVAudioPCMBuffer, volume: Float = 1.0) {
        guard started else { return }
        let p = sfxPlayers[sfxIndex]
        sfxIndex = (sfxIndex + 1) % sfxPlayers.count
        p.volume = volume
        p.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !p.isPlaying { p.play() }
    }

    func playGun() { playSFX(gun, volume: 1.0) }
    func playWhoosh() { playSFX(whoosh, volume: 0.65) }
    func playSetBeep() { playSFX(setBeep, volume: 0.8) }
    func playFootstep(loud: Bool) { playSFX(steps.randomElement()!, volume: loud ? 0.85 : 0.22) }
    func playBreath(volume: Float) { playSFX(breaths.randomElement()!, volume: volume) }
    func playCheer() { playSFX(cheer, volume: 0.95) }
    func playTick() { playSFX(tick, volume: 0.7) }
    func playPB() { playSFX(pbJingle, volume: 0.9) }
    func playHeartbeat() { playSFX(heartbeat, volume: 0.75) }
}

// MARK: - Synthesis

private enum Synth {
    static func buffer(seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        return buf
    }

    /// Fill stereo channels with a generator (frame index, channel) -> sample.
    static func fill(_ buf: AVAudioPCMBuffer, _ gen: (Int, Int) -> Float) {
        let n = Int(buf.frameLength)
        for ch in 0..<2 {
            let data = buf.floatChannelData![ch]
            for i in 0..<n { data[i] = gen(i, ch) }
        }
    }

    /// Stadium crowd: a chorus of slowly-wandering "voice" partials in the vocal band,
    /// a resonant murmur bed, and sporadic distant claps/shouts — not just hissy noise.
    static func crowd(seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buf = buffer(seconds: seconds, format: format)
        let n = Int(buf.frameLength)
        let sr = Float(format.sampleRate)

        struct Voice {
            var freq: Float
            var phase: Float
            var amp: Float
            var ampTarget: Float
            var pan: Float
        }
        var voices: [Voice] = (0..<34).map { _ in
            Voice(freq: Float.random(in: 130...750) * (Bool.random() ? 1 : 1.5),
                  phase: .random(in: 0...(2 * .pi)),
                  amp: .random(in: 0.1...0.5), ampTarget: .random(in: 0.1...0.6),
                  pan: .random(in: 0...1))
        }
        // Distant claps/shouts: (start frame, length, pan, brightness)
        let events: [(Int, Int, Float, Float)] = (0..<26).map { _ in
            (Int.random(in: 0..<n), Int(sr * .random(in: 0.02...0.06)),
             Float.random(in: 0...1), Float.random(in: 0.4...1))
        }

        let left = buf.floatChannelData![0]
        let right = buf.floatChannelData![1]
        var res1: (Float, Float) = (0, 0)   // resonator state y1,y2
        var res2: (Float, Float) = (0, 0)
        let (r1w, r1r): (Float, Float) = (2 * .pi * 420 / sr, 0.985)
        let (r2w, r2r): (Float, Float) = (2 * .pi * 980 / sr, 0.975)

        for i in 0..<n {
            let t = Float(i) / sr
            // Murmur bed: white noise through two vocal-band resonators.
            let white = Float.random(in: -1...1)
            let y1 = 2 * r1r * cos(r1w) * res1.0 - r1r * r1r * res1.1 + white * 0.02
            res1 = (y1, res1.0)
            let y2 = 2 * r2r * cos(r2w) * res2.0 - r2r * r2r * res2.1 + white * 0.012
            res2 = (y2, res2.0)
            var l = y1 + y2 * 0.7
            var r = y1 * 0.9 + y2 * 0.8

            // Voice chorus (update targets sparsely for speed).
            if i % 4 == 0 {
                var sum: (Float, Float) = (0, 0)
                for v in 0..<voices.count {
                    voices[v].phase += 2 * .pi * voices[v].freq * 4 / sr
                    if i % 4410 == 0 { voices[v].ampTarget = .random(in: 0...0.7) }
                    voices[v].amp += (voices[v].ampTarget - voices[v].amp) * 0.0006 * 4
                    let s = sin(voices[v].phase) * voices[v].amp
                    sum.0 += s * (1 - voices[v].pan)
                    sum.1 += s * voices[v].pan
                }
                lastVoiceMix = (sum.0 / 22, sum.1 / 22)
            }
            l += lastVoiceMix.0
            r += lastVoiceMix.1

            // Sporadic claps/shouts.
            for e in events where i >= e.0 && i < e.0 + e.1 {
                let k = Float(i - e.0) / Float(e.1)
                let burst = Float.random(in: -1...1) * (1 - k) * 0.16 * e.3
                l += burst * (1 - e.2)
                r += burst * e.2
            }

            let swell = 0.78 + 0.15 * sin(2 * .pi * 0.09 * t) + 0.07 * sin(2 * .pi * 0.031 * t + 2)
            left[i] = l * 0.5 * swell
            right[i] = r * 0.5 * swell
        }
        // Loop-seam crossfade
        let fade = Int(sr * 0.25)
        for ch in [left, right] {
            for i in 0..<fade {
                let a = Float(i) / Float(fade)
                ch[i] = ch[i] * a + ch[n - fade + i] * (1 - a)
            }
        }
        return buf
    }
    private static var lastVoiceMix: (Float, Float) = (0, 0)

    static func wind(seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buf = buffer(seconds: seconds, format: format)
        let n = Int(buf.frameLength)
        let sr = Float(format.sampleRate)
        for ch in 0..<2 {
            let data = buf.floatChannelData![ch]
            var lp: Float = 0
            var lp2: Float = 0
            let phase = Float(ch) * 2.3
            for i in 0..<n {
                let t = Float(i) / sr
                let white = Float.random(in: -1...1)
                lp += 0.11 * (white - lp)       // body of the rush
                lp2 += 0.5 * (white - lp2)      // high hiss
                let gust = 0.8 + 0.2 * sin(2 * .pi * 0.7 * t + phase)
                data[i] = (lp * 1.6 + lp2 * 0.5) * 0.5 * gust
            }
            let fade = Int(sr * 0.2)
            for i in 0..<fade {
                let a = Float(i) / Float(fade)
                data[i] = data[i] * a + data[n - fade + i] * (1 - a)
            }
        }
        return buf
    }

    /// A rising rush for the "top gear" moment.
    static func whoosh(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buf = buffer(seconds: 0.9, format: format)
        let sr = Float(format.sampleRate)
        var lp: Float = 0
        fill(buf) { i, _ in
            let t = Float(i) / sr
            let white = Float.random(in: -1...1)
            // opening filter: cutoff rises through the swell
            let a = 0.04 + 0.5 * min(1, t / 0.5)
            lp += a * (white - lp)
            let env = min(1, t / 0.35) * exp(-max(0, t - 0.4) * 6)
            return lp * env * 0.9
        }
        return buf
    }

    static func gunshot(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buf = buffer(seconds: 0.55, format: format)
        let sr = Float(format.sampleRate)
        fill(buf) { i, _ in
            let t = Float(i) / sr
            let crack = Float.random(in: -1...1) * exp(-t * 34)
            let thump = sin(2 * .pi * 68 * t) * exp(-t * 9) * 0.9
            let slap = Float.random(in: -1...1) * exp(-max(0, t - 0.05) * 60) * (t > 0.05 ? 0.25 : 0)
            return (crack * 0.85 + thump + slap) * 0.9
        }
        return buf
    }

    static func tone(freq: Float, seconds: Double, attack: Float, decay: Float, gain: Float,
                     format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buf = buffer(seconds: seconds, format: format)
        let sr = Float(format.sampleRate)
        fill(buf) { i, _ in
            let t = Float(i) / sr
            let env = min(1, t / attack) * exp(-t * decay)
            return sin(2 * .pi * freq * t) * env * gain
        }
        return buf
    }

    static func footstep(pitch: Float, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buf = buffer(seconds: 0.12, format: format)
        let sr = Float(format.sampleRate)
        var lp: Float = 0
        fill(buf) { i, _ in
            let t = Float(i) / sr
            let noise = Float.random(in: -1...1)
            lp += 0.14 * (noise - lp)
            // Spike bite on the track surface + body thud.
            let click = noise * exp(-t * 240) * 0.5
            let scrape = lp * exp(-t * 48) * 1.1
            let thud = sin(2 * .pi * 62 * pitch * t) * exp(-t * 36) * 1.0
            return (click + scrape + thud) * 0.95
        }
        return buf
    }

    /// One hard exhale. Breath is turbulence, not tone: broadband noise with a
    /// closing-mouth brightness sweep and *wide* (non-ringing) formants. The grunt
    /// variant adds a short voiced "uh" — a damped, pitch-dropping buzz underneath.
    static func breath(pitch: Float, grunt: Bool, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buf = buffer(seconds: 0.42, format: format)
        let sr = Float(format.sampleRate)
        var f1: (Float, Float) = (0, 0)
        var f2: (Float, Float) = (0, 0)
        let r1: Float = 0.88   // wide bandwidth: shapes, never rings
        let r2: Float = 0.85
        let w1 = 2 * .pi * 520 * pitch / sr
        let w2 = 2 * .pi * 1400 * pitch / sr
        var lp: Float = 0
        var vPhase: Float = 0
        fill(buf) { i, _ in
            let t = Float(i) / sr
            let white = Float.random(in: -1...1)
            // Mouth opens then closes: lowpass cutoff sweeps bright -> dull.
            let cut = 0.10 + 0.26 * exp(-t * 7)
            lp += cut * (white - lp)
            let y1n = 2 * r1 * cos(w1) * f1.0 - r1 * r1 * f1.1 + lp * 0.35
            f1 = (y1n, f1.0)
            let y2n = 2 * r2 * cos(w2) * f2.0 - r2 * r2 * f2.1 + white * 0.10
            f2 = (y2n, f2.0)
            let env = min(1, t / 0.05) * exp(-max(0, t - 0.10) * 8)
            var s = (lp * 1.2 + y1n * 0.9 + y2n * 0.45) * env
            if grunt {
                // Voiced "uh": pitch falls 132 -> 90 Hz, dies fast, roughened by the noise.
                let f0 = 132 - 42 * min(1, t / 0.14)
                vPhase += 2 * .pi * f0 / sr
                let voiced = sin(vPhase) * exp(-t * 9) * (0.7 + 0.3 * lp)
                s += voiced * 0.55 * min(1, t / 0.02)
            }
            return s * 0.85
        }
        return buf
    }

    static func cheer(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buf = buffer(seconds: 3.2, format: format)
        let n = Int(buf.frameLength)
        let sr = Float(format.sampleRate)
        for ch in 0..<2 {
            let data = buf.floatChannelData![ch]
            var lp: Float = 0
            var lp2: Float = 0
            for i in 0..<n {
                let t = Float(i) / sr
                let white = Float.random(in: -1...1)
                lp += 0.07 * (white - lp)
                lp2 += 0.35 * (white - lp2)
                let rise = min(1, t / 0.35)
                let fall = t > 2.0 ? exp(-(t - 2.0) * 1.8) : 1
                let flutter = 0.85 + 0.15 * sin(2 * .pi * 7 * t + Float(ch))
                data[i] = (lp * 2.0 + lp2 * 1.1) * 0.5 * rise * fall * flutter
            }
        }
        return buf
    }

    static func jingle(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buf = buffer(seconds: 0.9, format: format)
        let sr = Float(format.sampleRate)
        let notes: [(Float, Float)] = [(659, 0.0), (880, 0.14), (1047, 0.28)]
        fill(buf) { i, _ in
            let t = Float(i) / sr
            var s: Float = 0
            for (f, start) in notes where t >= start {
                let lt = t - start
                s += sin(2 * .pi * f * lt) * exp(-lt * 6) * 0.22
            }
            return s
        }
        return buf
    }

    static func heartbeat(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buf = buffer(seconds: 0.7, format: format)
        let sr = Float(format.sampleRate)
        fill(buf) { i, _ in
            let t = Float(i) / sr
            let b1 = sin(2 * .pi * 52 * t) * exp(-t * 22)
            let t2 = max(0, t - 0.24)
            let b2 = sin(2 * .pi * 48 * t2) * exp(-t2 * 24) * (t > 0.24 ? 0.7 : 0)
            return (b1 + b2) * 0.8
        }
        return buf
    }
}
