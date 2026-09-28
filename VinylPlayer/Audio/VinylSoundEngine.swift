import AVFoundation
import Combine
import Foundation

/// Shared by app startup and sound effects. Keep session configuration and
/// engine operations serialized off the UI thread, including on iOS 26.
enum AudioExecutionQueue {
    static let shared = DispatchQueue(label: "com.vinylplayer.audio", qos: .userInitiated)
}

/// Synthesises vinyl-specific sound effects using AVAudioEngine.
///
/// Two effects:
/// 1. **Needle drop** — warm low-frequency thud (stylus landing on spinning vinyl)
///    followed by continuous surface hiss/crackle with random pops.
/// 2. **DJ scratch** — tonal "wicky-wicky" scratch that follows drag velocity
///    and direction, using AVAudioUnitTimePitch for real-time pitch shifting.
///
/// All sounds are generated procedurally — no audio asset files needed.
final class VinylSoundEngine {

    static let shared = VinylSoundEngine()

    // MARK: - Audio Engine

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()

    // Needle drop nodes
    private let thudPlayer = AVAudioPlayerNode()
    private let cracklePlayer = AVAudioPlayerNode()

    // Scratch nodes — player → timePitch → mixer for real-time pitch control
    private let scratchPlayer = AVAudioPlayerNode()
    private let scratchTimePitch = AVAudioUnitTimePitch()
    private var scratchBufferForward: AVAudioPCMBuffer?
    private var scratchBufferReverse: AVAudioPCMBuffer?

    // State
    private var isEngineRunning = false
    private var isScratchPlaying = false
    private var scratchVolumeFadeTimer: DispatchSourceTimer?
    private var needleGeneration = 0
    private var lastScratchDirection: Double = 1.0  // +1 = forward, -1 = reverse

    // Settings
    var volume: Float = 0.7 {
        didSet {
            let newVolume = volume
            AudioExecutionQueue.shared.async { self.mixer.outputVolume = newVolume }
        }
    }

    // MARK: - Constants

    private let sampleRate: Double = 44100

    // MARK: - Init

    private init() {
        AudioExecutionQueue.shared.async {
            self.setupEngine()
            self.prepareBuffers()
        }
    }

    private func setupEngine() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        // Attach all nodes
        engine.attach(mixer)
        engine.attach(thudPlayer)
        engine.attach(cracklePlayer)
        engine.attach(scratchPlayer)
        engine.attach(scratchTimePitch)

        // Needle drop: players → mixer
        engine.connect(thudPlayer, to: mixer, format: format)
        engine.connect(cracklePlayer, to: mixer, format: format)

        // Scratch: player → timePitch → mixer (pitch shifting for direction feel)
        engine.connect(scratchPlayer, to: scratchTimePitch, format: format)
        engine.connect(scratchTimePitch, to: mixer, format: format)

        // Mixer → output
        engine.connect(mixer, to: engine.mainMixerNode, format: format)

        mixer.outputVolume = 0.7
        scratchTimePitch.pitch = 0  // semitones offset
        scratchTimePitch.rate = 1.0
    }

    private func ensureEngineRunning() -> Bool {
        dispatchPrecondition(condition: .onQueue(AudioExecutionQueue.shared))
        guard !isEngineRunning else { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            isEngineRunning = true
        } catch {
            print("VinylSoundEngine: failed to start — \(error)")
        }
        return isEngineRunning
    }

    // MARK: - Buffer Generation

    private func prepareBuffers() {
        scratchBufferForward = generateScratchToneBuffer(reverse: false)
        scratchBufferReverse = generateScratchToneBuffer(reverse: true)
    }

    // MARK: Needle Drop Buffers

    /// Realistic needle-drop sound — noise-based impulse synthesis.
    /// Real needle drops are NOT tonal — they're mechanical impacts:
    /// a short broadband "pop/tick" shaped by the tonearm and vinyl surface.
    /// No sine waves — only filtered noise impulses and shaped transients.
    private func generateThudBuffer() -> AVAudioPCMBuffer {
        let duration: Double = 0.25
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        guard let data = buffer.floatChannelData?[0] else { return buffer }

        // Multi-stage low-pass filter state for shaping noise
        var lp1: Float = 0, lp2: Float = 0

        // One-pole high-pass to remove DC offset
        var hpPrev: Float = 0, hpOut: Float = 0

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate

            // --- Impact transient (0-8ms): broadband noise burst ---
            // This is the "tick/pop" of the stylus hitting the groove
            // Very short, filtered through a moderate low-pass for natural character
            let impactEnv = Float(t < 0.008 ? exp(-t * 300.0) : 0)
            let impactNoise = Float.random(in: -1...1)
            // Light filtering — keep some brightness for the click character
            let impactLP: Float = 0.35
            lp1 += impactLP * (impactNoise - lp1)
            let impact = lp1 * impactEnv * 0.7

            // --- Mechanical resonance (8-80ms): shaped noise decay ---
            // The tonearm and cartridge body resonate briefly after impact
            // Heavier low-pass = warmer, more "woody" character
            let resoEnv = Float(t > 0.005 ? exp(-(t - 0.005) * 35.0) : 0)
            let resoNoise = Float.random(in: -1...1)
            let resoLP: Float = 0.12  // Heavy filtering for warm body
            lp2 += resoLP * (resoNoise - lp2)
            let resonance = lp2 * resoEnv * 0.5

            // --- Low-frequency thump (0-100ms): the "weight" felt through speakers ---
            // Not a sine wave — a shaped noise pulse through very heavy LP
            // Gives a sense of mass without sounding tonal
            let thumpEnv = Float(exp(-t * 18.0))
            let thump = (lp2 * 0.3 + lp1 * 0.1) * thumpEnv * 0.4

            // --- Tail crackle (50ms+): very quiet surface noise onset ---
            let tailEnv = Float(t > 0.05 ? (1.0 - exp(-(t - 0.05) * 20.0)) * exp(-(t - 0.05) * 8.0) : 0)
            let tailNoise = Float.random(in: -1...1) * 0.08
            let tail = tailNoise * tailEnv

            // Combine all layers
            var sample = impact + resonance + thump + tail

            // High-pass to remove any DC drift from the filters
            let hpCoeff: Float = 0.995
            hpOut = hpCoeff * (hpOut + sample - hpPrev)
            hpPrev = sample
            sample = hpOut

            data[i] = sample * 0.9
        }

        return buffer
    }

    /// Vinyl surface noise — warm analog hiss with random crackle/pops.
    /// Longer duration, gentler character than before.
    private func generateSurfaceNoiseBuffer() -> AVAudioPCMBuffer {
        let duration: Double = 2.0  // 2 seconds of surface noise
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        guard let data = buffer.floatChannelData?[0] else { return buffer }

        // Two-pole low-pass state for warm character
        var lp1: Float = 0
        var lp2: Float = 0
        let lpCoeff: Float = 0.15  // heavier filtering = warmer

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate

            // Envelope: fade in over 50ms, sustain, fade out last 300ms
            let fadeIn = Float(min(1.0, t / 0.05))
            let fadeOut = Float(min(1.0, (duration - t) / 0.3))
            let envelope = fadeIn * fadeOut * 0.18

            // White noise → two-stage low-pass for warmth
            let noise = Float.random(in: -1...1)
            lp1 += lpCoeff * (noise - lp1)
            lp2 += lpCoeff * (lp1 - lp2)

            // Random vinyl pops (sparse, varied amplitude)
            var pop: Float = 0
            let popChance = Float.random(in: 0...1)
            if popChance < 0.001 {
                // Loud pop
                pop = Float.random(in: 0.3...0.6) * (Bool.random() ? 1 : -1)
            } else if popChance < 0.004 {
                // Soft tick
                pop = Float.random(in: 0.1...0.25) * (Bool.random() ? 1 : -1)
            }

            // Subtle periodic rumble (33⅓ RPM = ~0.556 Hz rotation)
            let rumble = Float(sin(2.0 * .pi * 0.556 * t)) * 0.03

            data[i] = (lp2 + pop + rumble) * envelope
        }

        return buffer
    }

    // MARK: Scratch Buffers

    /// Generate a warm vinyl scratch buffer that simulates a stylus being
    /// dragged across grooves. Character: low-mid frequency, soft "wub" texture.
    ///
    /// Approach:
    /// - Heavily low-passed noise (warm, not harsh)
    /// - Slow groove-crossing modulation (~30-60 Hz) for rhythmic texture
    /// - Gentle low-frequency resonance (~100 Hz) instead of sharp high comb
    /// - No sawtooth — avoids electronic/buzzy character
    private func generateScratchToneBuffer(reverse: Bool) -> AVAudioPCMBuffer {
        let duration: Double = 1.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        guard let data = buffer.floatChannelData?[0] else { return buffer }

        // 4-pole low-pass for very warm, muffled character
        var lp1: Float = 0, lp2: Float = 0, lp3: Float = 0, lp4: Float = 0
        let lpCoeff: Float = 0.08  // Very heavy filtering → deep warmth

        // Bandpass resonance state (centered ~100 Hz for body)
        var bp1: Float = 0, bp2: Float = 0
        let bpFreq: Double = 100.0
        let bpQ: Double = 1.5
        let bpW0 = 2.0 * Double.pi * bpFreq / sampleRate
        let bpAlpha = Float(sin(bpW0) / (2.0 * bpQ))
        let bpA0: Float = 1.0 + bpAlpha
        let bpB0: Float = bpAlpha / bpA0
        let bpB2: Float = -bpAlpha / bpA0
        let bpA1: Float = (-2.0 * Float(cos(bpW0))) / bpA0
        let bpA2: Float = (1.0 - bpAlpha) / bpA0

        // Previous input/output for biquad bandpass
        var bpX1: Float = 0, bpX2: Float = 0
        var bpY1: Float = 0, bpY2: Float = 0

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let idx = reverse ? (Int(frameCount) - 1 - i) : i

            // Pink-ish noise excitation (brown noise character)
            let white = Float.random(in: -1...1)
            lp1 += lpCoeff * (white - lp1)
            lp2 += lpCoeff * (lp1 - lp2)
            lp3 += lpCoeff * (lp2 - lp3)
            lp4 += lpCoeff * (lp3 - lp4)

            // Bandpass filter for groove body resonance
            let bpIn = lp4
            let bpOut = bpB0 * bpIn + 0 * bpX1 + bpB2 * bpX2 - bpA1 * bpY1 - bpA2 * bpY2
            bpX2 = bpX1; bpX1 = bpIn
            bpY2 = bpY1; bpY1 = bpOut

            // Slow groove-crossing modulation (~40 Hz "wub wub" texture)
            let grooveMod = Float(1.0 + 0.5 * sin(2.0 * .pi * 40.0 * t))

            // Gentle secondary modulation for organic feel (~7 Hz wobble)
            let wobble = Float(1.0 + 0.2 * sin(2.0 * .pi * 7.0 * t))

            // Mix: mostly filtered noise + resonance, modulated
            let mixed = (lp4 * 0.5 + bpOut * 0.5) * grooveMod * wobble

            data[idx] = mixed * 0.7
        }

        return buffer
    }

    // MARK: - Needle Drop

    /// Play the needle-drop sound: warm thud + vinyl surface noise.
    func playNeedleDrop() {
        AudioExecutionQueue.shared.async { self.playNeedleDropOnAudioQueue() }
    }

    private func playNeedleDropOnAudioQueue() {
        guard ensureEngineRunning() else { return }
        needleGeneration += 1
        let generation = needleGeneration

        let thudBuf = generateThudBuffer()
        let surfaceBuf = generateSurfaceNoiseBuffer()

        thudPlayer.stop()
        cracklePlayer.stop()

        // Thud: immediate
        thudPlayer.scheduleBuffer(thudBuf, at: nil, options: .interrupts)
        thudPlayer.volume = 1.0
        thudPlayer.play()

        // Surface noise: starts right after thud settles (~80ms)
        cracklePlayer.scheduleBuffer(surfaceBuf, at: nil, options: .interrupts)
        cracklePlayer.volume = 0.8
        // Small delay via dispatch for the surface noise onset
        AudioExecutionQueue.shared.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.isEngineRunning, self.needleGeneration == generation else { return }
            self.cracklePlayer.play()
        }
    }

    /// Play needle-lift sound: softer, shorter thud (stylus leaving surface).
    func playNeedleLift() {
        AudioExecutionQueue.shared.async { self.playNeedleLiftOnAudioQueue() }
    }

    private func playNeedleLiftOnAudioQueue() {
        needleGeneration += 1
        guard ensureEngineRunning() else { return }

        let thudBuf = generateThudBuffer()
        thudPlayer.stop()
        cracklePlayer.stop()
        thudPlayer.scheduleBuffer(thudBuf, at: nil, options: .interrupts)
        thudPlayer.volume = 0.5  // Softer than the drop
        thudPlayer.play()
    }

    // MARK: - DJ Scratch

    /// Start the scratch effect. Call when vinyl drag begins.
    func startScratch() {
        AudioExecutionQueue.shared.async { self.startScratchOnAudioQueue() }
    }

    private func startScratchOnAudioQueue() {
        guard ensureEngineRunning() else { return }
        guard let buffer = scratchBufferForward else { return }

        scratchVolumeFadeTimer?.cancel()
        scratchPlayer.stop()
        scratchPlayer.volume = 0
        scratchTimePitch.pitch = 0
        scratchTimePitch.rate = 1.0
        scratchPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        scratchPlayer.play()
        isScratchPlaying = true
        lastScratchDirection = 1.0
    }

    /// Update scratch based on drag velocity.
    /// - Parameter velocity: Angular velocity in degrees/second.
    ///   Sign indicates direction (positive = forward, negative = backward).
    func updateScratch(velocity: Double) {
        AudioExecutionQueue.shared.async { self.updateScratchOnAudioQueue(velocity: velocity) }
    }

    private func updateScratchOnAudioQueue(velocity: Double) {
        guard isScratchPlaying else { return }

        let absVel = abs(velocity)

        // Volume: gentle curve. Subtle at slow speeds, moderate at fast.
        // Max 0.55 — scratch should sit behind the music, not dominate.
        let targetVolume: Float
        if absVel < 5 {
            targetVolume = 0.08  // Barely audible when nearly stopped
        } else {
            targetVolume = Float(min(0.55, 0.12 + absVel / 400.0))
        }
        scratchPlayer.volume = targetVolume

        // Pitch: subtle variation ±300 cents (quarter-tone range).
        // Just enough to hear direction change, not a dramatic warp.
        let direction = velocity >= 0 ? 1.0 : -1.0
        let pitchShift = Float(direction * min(abs(velocity) / 200.0, 1.0) * 300.0)
        scratchTimePitch.pitch = pitchShift

        // Rate: maps drag speed to playback speed (0.6x – 1.5x).
        // Keeps the warm character without making it unnaturally fast.
        let rate = Float(max(0.6, min(1.5, 0.7 + absVel / 300.0)))
        scratchTimePitch.rate = rate

        // Swap buffer direction if drag direction changed significantly
        if direction != lastScratchDirection {
            lastScratchDirection = direction
            let buffer = direction > 0 ? scratchBufferForward : scratchBufferReverse
            if let buffer = buffer {
                scratchPlayer.stop()
                scratchPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
                scratchPlayer.volume = targetVolume
                scratchPlayer.play()
            }
        }
    }

    /// Stop the scratch effect with a short fade-out.
    func stopScratch() {
        AudioExecutionQueue.shared.async { self.stopScratchOnAudioQueue() }
    }

    private func stopScratchOnAudioQueue() {
        guard isScratchPlaying else { return }
        isScratchPlaying = false

        // Fade out over ~120ms for natural release
        let steps = 12
        let interval: TimeInterval = 0.01
        var step = 0
        let currentVol = scratchPlayer.volume

        scratchVolumeFadeTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: AudioExecutionQueue.shared)
        scratchVolumeFadeTimer = timer
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            step += 1
            let progress = Float(step) / Float(steps)
            self?.scratchPlayer.volume = currentVol * (1.0 - progress)
            // Also slide pitch back to neutral
            self?.scratchTimePitch.pitch *= (1.0 - progress)
            if step >= steps {
                self?.scratchVolumeFadeTimer?.cancel()
                self?.scratchVolumeFadeTimer = nil
                self?.scratchPlayer.stop()
                self?.scratchTimePitch.pitch = 0
                self?.scratchTimePitch.rate = 1.0
            }
        }
        timer.resume()
    }

    // MARK: - Cleanup

    func stop() {
        AudioExecutionQueue.shared.async { self.stopOnAudioQueue() }
    }

    private func stopOnAudioQueue() {
        needleGeneration += 1
        isScratchPlaying = false
        scratchVolumeFadeTimer?.cancel()
        scratchVolumeFadeTimer = nil
        thudPlayer.stop()
        cracklePlayer.stop()
        scratchPlayer.stop()
        if isEngineRunning {
            engine.stop()
            isEngineRunning = false
        }
    }
}
