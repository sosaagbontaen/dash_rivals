import AVFoundation

/// Stadium announcer: on-device speech synthesis rendered offline, then pushed
/// through a homemade PA chain (comb reverb + lowpass). PA systems are muffled
/// and cavernous, which is exactly what hides the TTS artifacts.
final class Announcer {
    enum Phrase: String, CaseIterable {
        case marks = "Runners! To your marks."
        case set = "Set."
        case newPB = "A new personal best!"
    }

    private let format: AVAudioFormat
    private var buffers: [Phrase: AVAudioPCMBuffer] = [:]
    private let lock = NSLock()
    private let synth = AVSpeechSynthesizer()   // must outlive rendering

    init(format: AVAudioFormat) {
        self.format = format
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.renderAll()
        }
    }

    func buffer(for phrase: Phrase) -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        return buffers[phrase]
    }

    private func renderAll() {
        for phrase in Phrase.allCases {
            guard let raw = render(text: phrase.rawValue) else { continue }
            let processed = Self.stadiumPA(raw, format: format)
            lock.lock()
            buffers[phrase] = processed
            lock.unlock()
        }
    }

    /// Render one utterance to mono samples at its native rate.
    private func render(text: String) -> (samples: [Float], rate: Double)? {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.42
        utterance.pitchMultiplier = 0.72
        utterance.volume = 1.0

        var samples: [Float] = []
        var sampleRate: Double = 22050
        let done = DispatchSemaphore(value: 0)
        synth.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 { done.signal(); return }
            sampleRate = pcm.format.sampleRate
            if let data = pcm.floatChannelData {
                samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(pcm.frameLength)))
            } else if let i16 = pcm.int16ChannelData {
                let n = Int(pcm.frameLength)
                for i in 0..<n { samples.append(Float(i16[0][i]) / 32768) }
            }
        }
        // Rendering is asynchronous; wait briefly for the terminating empty buffer.
        _ = done.wait(timeout: .now() + 6)
        return samples.isEmpty ? nil : (samples, sampleRate)
    }

    /// Resample to the engine rate and run the PA chain.
    private static func stadiumPA(_ raw: (samples: [Float], rate: Double),
                                  format: AVAudioFormat) -> AVAudioPCMBuffer {
        let outRate = format.sampleRate
        let ratio = outRate / raw.rate
        let dryLen = Int(Double(raw.samples.count) * ratio)
        let tailLen = Int(outRate * 0.9)                    // reverb tail
        let n = dryLen + tailLen

        // Linear resample.
        var dry = [Float](repeating: 0, count: n)
        for i in 0..<dryLen {
            let src = Double(i) / ratio
            let i0 = Int(src)
            let f = Float(src - Double(i0))
            let a = raw.samples[min(i0, raw.samples.count - 1)]
            let b = raw.samples[min(i0 + 1, raw.samples.count - 1)]
            dry[i] = a * (1 - f) + b * f
        }

        // PA chain: lowpass (horn speakers), three comb echoes, gentle drive.
        var lp: Float = 0
        var out = [Float](repeating: 0, count: n)
        let combs: [(delay: Int, gain: Float)] = [
            (Int(outRate * 0.041), 0.42), (Int(outRate * 0.067), 0.33), (Int(outRate * 0.103), 0.25),
        ]
        for i in 0..<n {
            lp += 0.24 * (dry[i] - lp)
            var s = lp * 1.25
            for c in combs where i >= c.delay {
                s += out[i - c.delay] * c.gain
            }
            out[i] = max(-1, min(1, s)) * 0.92
        }

        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        for ch in 0..<2 {
            let data = buf.floatChannelData![ch]
            for i in 0..<n { data[i] = out[i] * 0.8 }
        }
        return buf
    }
}
