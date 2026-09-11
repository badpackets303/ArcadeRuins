//  Shared offline-rendering harness for the test suite.
//
//  Three test files needed the same loop, so it lives here once (P2-4).
//  `S1AudioUnitRenderTests` deliberately does *not* use it — that one drives
//  `S1AudioUnit.internalRenderBlock` by hand on purpose, with no engine at all,
//  because proving the kernel works without an engine was the point of P1-6.

import XCTest
import Accelerate
import AVFoundation
@testable import SynthOneCore

/// A rendered stereo signal.
struct StereoRender {
    var left: [Float]
    var right: [Float]
    var frameCount: AVAudioFrameCount { AVAudioFrameCount(left.count) }
}

/// A synth wired into its own engine, rendering offline.
final class OfflineSynth {

    let synth: AKSynthOne
    let engine: S1AudioEngine
    let mixer: AKMixer
    let sampleRate: Double
    let framesPerBlock: AVAudioFrameCount

    /// Seconds to render before measuring anything. Every portamento-enabled
    /// parameter re-ramps from zero when render resources are allocated, so the
    /// synth sweeps into tune over roughly the first second (ADR-013).
    static let settleTime: Double = 1.0

    init(sampleRate: Double = 44_100, framesPerBlock: AVAudioFrameCount = 512) throws {
        self.sampleRate = sampleRate
        self.framesPerBlock = framesPerBlock
        synth = AKSynthOne()
        mixer = AKMixer(synth)
        engine = S1AudioEngine()
        engine.output = mixer
        // ADR-015: manual rendering must be chosen before anything touches
        // `engine.outputNode`, or the hardware output unit is created and blocks.
        try engine.startOfflineRendering(sampleRate: sampleRate, maximumFrameCount: framesPerBlock)
    }

    deinit { engine.stop() }

    /// Renders `seconds`, calling `schedule` before each block with that block's
    /// start time. Note events go through the same main-thread API the app uses.
    func render(seconds: Double,
                schedule: (Double, AKSynthOne) -> Void = { _, _ in }) throws -> StereoRender {
        guard let buffer = engine.makeRenderBuffer(frameCount: framesPerBlock) else {
            throw OfflineRenderError.noBuffer
        }
        var out = StereoRender(left: [], right: [])
        let total = Int(seconds * sampleRate)
        out.left.reserveCapacity(total)
        out.right.reserveCapacity(total)

        var frames = 0
        while frames < total {
            schedule(Double(frames) / sampleRate, synth)
            let status = try engine.render(into: buffer)
            guard status == .success else { throw OfflineRenderError.renderFailed(status) }
            if let channels = buffer.floatChannelData {
                out.left.append(contentsOf: UnsafeBufferPointer(start: channels[0],
                                                                count: Int(buffer.frameLength)))
                out.right.append(contentsOf: UnsafeBufferPointer(start: channels[1],
                                                                 count: Int(buffer.frameLength)))
            }
            frames += Int(buffer.frameLength)
        }
        return out
    }
}

enum OfflineRenderError: Error {
    case noBuffer
    case renderFailed(AVAudioEngineManualRenderingStatus)
}

// MARK: - Measurement

enum Signal {

    static func peak(_ x: [Float]) -> Float { x.reduce(0) { max($0, abs($1)) } }

    static func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_rmsqv(x, 1, &result, vDSP_Length(x.count))
        return result
    }

    static func rms(_ x: ArraySlice<Float>) -> Float { rms(Array(x)) }

    /// Fundamental frequency by normalised autocorrelation.
    ///
    /// Not zero-crossing counting: the default patch is a sawtooth and crosses
    /// zero many times per cycle. Taking the *first* strong peak rather than the
    /// tallest avoids reporting an octave down, since r(2T) is as high as r(T)
    /// for anything periodic.
    static func fundamental(_ signal: [Float], sampleRate: Double,
                            minHz: Double = 50, maxHz: Double = 2_000) -> Double {
        var x = signal
        var mean: Float = 0
        vDSP_meanv(x, 1, &mean, vDSP_Length(x.count))
        var negativeMean = -mean
        vDSP_vsadd(x, 1, &negativeMean, &x, 1, vDSP_Length(x.count))

        let minLag = max(1, Int(sampleRate / maxHz))
        let maxLag = min(Int(sampleRate / minHz), x.count / 2)
        guard maxLag > minLag + 1 else { return 0 }
        let window = vDSP_Length(x.count - maxLag)

        var r = [Float](repeating: 0, count: maxLag + 1)
        x.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var zeroLagEnergy: Float = 0
            vDSP_dotpr(base, 1, base, 1, &zeroLagEnergy, window)
            guard zeroLagEnergy > 0 else { return }
            for lag in minLag...maxLag {
                var numerator: Float = 0
                var lagEnergy: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &numerator, window)
                vDSP_dotpr(base + lag, 1, base + lag, 1, &lagEnergy, window)
                r[lag] = numerator / (sqrt(zeroLagEnergy * lagEnergy) + .leastNormalMagnitude)
            }
        }
        let best = r[minLag...maxLag].max() ?? 0
        guard best > 0.3 else { return 0 }
        var lag = -1
        for candidate in (minLag + 1)..<maxLag
        where r[candidate] >= 0.85 * best
            && r[candidate] >= r[candidate - 1]
            && r[candidate] >= r[candidate + 1] {
            lag = candidate
            break
        }
        guard lag > minLag, lag < maxLag else { return 0 }
        let y0 = Double(r[lag - 1]), y1 = Double(r[lag]), y2 = Double(r[lag + 1])
        let curvature = y0 - 2 * y1 + y2
        let delta = curvature != 0 ? 0.5 * (y0 - y2) / curvature : 0
        return sampleRate / (Double(lag) + delta)
    }

    /// Spectral centroid in Hz — the magnitude-weighted mean frequency, i.e. how
    /// bright the signal is.
    ///
    /// This is the measurement for a filter sweep. Peak and RMS both move when the
    /// cutoff moves, but they also move when the amplitude does, so neither tells
    /// you the *spectrum* changed. The centroid is amplitude-invariant.
    static func spectralCentroid(_ signal: [Float], sampleRate: Double) -> Double {
        guard signal.count >= 1024 else { return 0 }
        let log2n = vDSP_Length(floor(log2(Double(signal.count))))
        let count = 1 << Int(log2n)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return 0 }
        defer { vDSP_destroy_fftsetup(setup) }

        // Hann first: a sawtooth chopped at an arbitrary sample has a step at each
        // end, and the resulting spectral leakage is broadband — it would drag the
        // centroid toward Nyquist regardless of where the filter is.
        var window = [Float](repeating: 0, count: count)
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
        var windowed = [Float](repeating: 0, count: count)
        vDSP_vmul(Array(signal[0..<count]), 1, window, 1, &windowed, 1, vDSP_Length(count))

        let half = count / 2
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!,
                                            imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // Bin 0 is DC — a constant offset is not brightness, and including it pulls
        // the centroid down by an amount that depends on the patch, not the filter.
        var weighted = 0.0
        var total = 0.0
        for bin in 1..<half {
            let magnitude = Double(magnitudes[bin])
            weighted += magnitude * Double(bin) * sampleRate / Double(count)
            total += magnitude
        }
        return total > 0 ? weighted / total : 0
    }
}

// MARK: - WAV

enum WAV {

    /// Writes 32-bit float stereo.
    ///
    /// 16-bit was tried first, to halve what goes into git. It does not work:
    /// **four of the twenty golden presets render above full scale** — loud
    /// patches through the master compressor, which is the instrument behaving as
    /// designed — and integer PCM clamps them. The worst mismatch was 1.37, a
    /// clipped peak rather than any change in the DSP.
    ///
    /// Goldens have to record what the DSP actually produced, over-full-scale
    /// included, because that is the behaviour being protected. Float32 also makes
    /// the comparison exact on one machine, so the tolerance is left doing only
    /// the job it was meant for: absorbing arm64/x86_64 differences.
    static func write(_ render: StereoRender, to url: URL, sampleRate: Double) throws {
        let file = try AVAudioFile(forWriting: url,
                                   settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                                              AVSampleRateKey: sampleRate,
                                              AVNumberOfChannelsKey: 2,
                                              AVLinearPCMBitDepthKey: 32,
                                              AVLinearPCMIsFloatKey: true,
                                              AVLinearPCMIsBigEndianKey: false],
                                   commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: render.frameCount),
              let channels = buffer.floatChannelData else { throw OfflineRenderError.noBuffer }
        buffer.frameLength = render.frameCount
        render.left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: $0.count) }
        render.right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: $0.count) }
        try file.write(from: buffer)
    }

    static func read(_ url: URL) throws -> StereoRender {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              file.length > 0 else { throw OfflineRenderError.noBuffer }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { throw OfflineRenderError.noBuffer }
        let count = Int(buffer.frameLength)
        return StereoRender(left: Array(UnsafeBufferPointer(start: channels[0], count: count)),
                            right: Array(UnsafeBufferPointer(start: channels[1], count: count)))
    }
}
