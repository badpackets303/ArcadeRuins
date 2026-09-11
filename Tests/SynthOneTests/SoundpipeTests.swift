//  P1-2 acceptance: the vendored Soundpipe modules are not merely linked, they
//  behave. These are cheap smoke tests over the primitives the S1 kernel leans
//  on, so a bad vendoring is caught here rather than at P1-5 under the kernel.

import XCTest
@testable import SynthOneCore

final class SoundpipeTests: XCTestCase {

    private let sampleRate: Float = 44_100

    /// Estimates frequency by counting rising zero crossings.
    private func estimateFrequency(_ signal: [Float]) -> Float {
        var crossings = 0
        for i in 1..<signal.count where signal[i - 1] <= 0 && signal[i] > 0 {
            crossings += 1
        }
        return Float(crossings) * sampleRate / Float(signal.count)
    }

    private func peak(_ signal: [Float]) -> Float {
        signal.reduce(0) { max($0, abs($1)) }
    }

    private func rms(_ signal: [Float]) -> Float {
        guard !signal.isEmpty else { return 0 }
        let sum = signal.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(signal.count)).squareRoot()
    }

    // MARK: - sp_osc / sp_ftbl / sp_gen_sine

    func testOscillatorProducesRequestedFrequency() {
        let signal = SoundpipeBridge.renderSine(frequency: 440, frames: 44_100)
        XCTAssertEqual(signal.count, 44_100)
        XCTAssertEqual(estimateFrequency(signal), 440, accuracy: 2.0)
    }

    func testOscillatorRespectsAmplitude() {
        let loud = SoundpipeBridge.renderSine(frequency: 440, amplitude: 1.0, frames: 4_096)
        let quiet = SoundpipeBridge.renderSine(frequency: 440, amplitude: 0.25, frames: 4_096)
        XCTAssertEqual(peak(loud), 1.0, accuracy: 0.05)
        XCTAssertEqual(peak(quiet), 0.25, accuracy: 0.05)
    }

    // MARK: - sp_moogladder

    func testMoogladderAttenuatesAboveCutoff() {
        let low = SoundpipeBridge.renderSine(frequency: 100, frames: 22_050)
        let high = SoundpipeBridge.renderSine(frequency: 8_000, frames: 22_050)

        let lowFiltered = SoundpipeBridge.moogladder(low, cutoff: 500)
        let highFiltered = SoundpipeBridge.moogladder(high, cutoff: 500)

        // A 500 Hz low-pass should pass 100 Hz largely intact and crush 8 kHz.
        XCTAssertGreaterThan(rms(lowFiltered), rms(low) * 0.5)
        XCTAssertLessThan(rms(highFiltered), rms(lowFiltered) * 0.1)
    }

    // MARK: - sp_adsr

    func testADSRRisesUnderGateAndReleasesAfter() {
        let env = SoundpipeBridge.renderADSR(attack: 0.01, decay: 0.05, sustain: 0.6, release: 0.1,
                                             gateFrames: 22_050, totalFrames: 44_100)
        XCTAssertEqual(env.count, 44_100)

        XCTAssertLessThan(env[0], 0.1, "envelope should start near zero")

        let duringSustain = env[20_000]
        XCTAssertEqual(duringSustain, 0.6, accuracy: 0.1, "should settle at the sustain level")

        let afterRelease = env[40_000]
        XCTAssertLessThan(afterRelease, duringSustain * 0.5, "should decay after gate-off")
    }

    // MARK: - sp_oscmorph2d (Synth One's own module, not stock Soundpipe)

    func testOscMorph2DProducesAudio() {
        let signal = SoundpipeBridge.renderOscMorph2D(frequency: 440, morphPosition: 0.5,
                                                      frames: 44_100)
        XCTAssertEqual(signal.count, 44_100)
        XCTAssertGreaterThan(peak(signal), 0.1, "morphing oscillator should not be silent")
        XCTAssertEqual(estimateFrequency(signal), 440, accuracy: 2.0)
    }
}
