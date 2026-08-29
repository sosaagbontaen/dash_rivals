import AVFoundation

/// All game audio is synthesized at launch into PCM buffers — no audio files.
final class GameAudio {
    private let engine = AVAudioEngine()
    private let crowdPlayer = AVAudioPlayerNode()
    private let sfxPlayers = (0..<5).map { _ in AVAudioPlayerNode() }
    private var sfxIndex = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

    private var crowdLoop: AVAudioPCMBuffer!
    private var gun: AVAudioPCMBuffer!
    private var setBeep: AVAudioPCMBuffer!
    private var steps: [AVAudioPCMBuffer] = []
    private var cheer: AVAudioPCMBuffer!
    private var tick: AVAudioPCMBuffer!
    private var pbJingle: AVAudioPCMBuffer!
    private var heartbeat: AVAudioPCMBuffer!

    /// Crowd volume target; ramped smoothly in update().
    var crowdTarget: Float = 0.4
    private var started = false

    init() {
        crowdLoop = Synth.crowd(seconds: 7, format: format)
        gun = Synth.gunshot(format: format)
        setBeep = Synth.tone(freq: 700, seconds: 0.5, attack: 0.01, decay: 2.2, gain: 0.35, format: format)
        steps = (0..<3).map { i in Synth.footstep(pitch: 1.0 + Float(i) * 0.12 - 0.12, format: format) }
        cheer = Synth.cheer(format: format)
        tick = Synth.tone(freq: 1250, seconds: 0.06, attack: 0.002, decay: 28, gain: 0.18, format: format)
        pbJingle = Synth.jingle(format: format)
        heartbeat = Synth.heartbeat(format: format)

        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        engine.attach(crowdPlayer)
        engine.connect(crowdPlayer, to: engine.mainMixerNode, format: format)
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
            started = true
        } catch {
            // Audio is atmosphere, not critical — run silent if the engine fails.
        }
    }

    func update(dt: Double) {
        guard started else { return }
        let cur = crowdPlayer.volume
        let step = Float(dt) * 1.2
        if abs(cur - crowdTarget) > 0.005 {
            crowdPlayer.volume = cur + max(-step, min(step, crowdTarget - cur))
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
    func playSetBeep() { playSFX(setBeep, volume: 0.8) }
    func playFootstep(loud: Bool) { playSFX(steps.randomElement()!, volume: loud ? 0.5 : 0.16) }
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

    static func crowd(seconds: Double, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buf = buffer(seconds: seconds, format: format)
        let n = Int(buf.frameLength)
        let sr = Float(format.sampleRate)
        for ch in 0..<2 {
            let data = buf.floatChannelData![ch]
            var lp: Float = 0
            var lp2: Float = 0
            let phase = Float(ch) * 1.7
            for i in 0..<n {
                let t = Float(i) / sr
                let white = Float.random(in: -1...1)
                lp += 0.045 * (white - lp)      // rumble
                lp2 += 0.28 * (white - lp2)     // hiss/voices
                let swell = 0.75 + 0.18 * sin(2 * .pi * 0.11 * t + phase) + 0.09 * sin(2 * .pi * 0.043 * t + phase * 2)
                data[i] = (lp * 2.6 + lp2 * 0.5) * 0.42 * swell
            }
            // Loop-seam crossfade
            let fade = Int(sr * 0.25)
            for i in 0..<fade {
                let a = Float(i) / Float(fade)
                data[i] = data[i] * a + data[n - fade + i] * (1 - a)
            }
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
        let buf = buffer(seconds: 0.11, format: format)
        let sr = Float(format.sampleRate)
        var lp: Float = 0
        fill(buf) { i, _ in
            let t = Float(i) / sr
            let noise = Float.random(in: -1...1)
            lp += 0.12 * (noise - lp)
            let thud = sin(2 * .pi * 58 * pitch * t) * exp(-t * 42)
            return (lp * exp(-t * 55) * 0.9 + thud * 0.8) * 0.9
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
