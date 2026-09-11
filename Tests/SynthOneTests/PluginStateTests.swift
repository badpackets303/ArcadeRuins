//  P4-4 acceptance: a host saves a session and gets the same sound back.
//
//  These tests compare **rendered audio**, not dictionaries. Two `fullState`
//  dictionaries can be equal while the instrument sounds different — that is
//  exactly what happens when a piece of state has no key — and they can differ
//  harmlessly. The only question that matters is whether the restored unit plays
//  what the saved one played.

import XCTest
import AVFoundation
import AudioToolbox
@testable import SynthOneCore

final class PluginStateTests: XCTestCase {

    private let sampleRate: Double = 44_100
    private let framesPerBlock: AVAudioFrameCount = 512

    /// Portamento parameters re-ramp from zero at allocation (ADR-013), so nothing
    /// is worth measuring for about a second.
    private let settleTime: Double = 1.0

    private func makeUnit() throws -> S1AudioUnit {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        unit.maximumFramesToRender = framesPerBlock
        return unit
    }

    /// A patch that is audibly not the default, across several parts of the DSP.
    ///
    /// `noiseVolume` is pinned to zero deliberately: the sample-for-sample
    /// comparison below only means anything if the instrument is deterministic,
    /// and the noise oscillator is the one part that is not.
    private func applyDistinctivePatch(to unit: S1AudioUnit) {
        let patch: [(S1Parameter, Float)] = [
            (.noiseVolume, 0),
            (.cutoff, 1_800),
            (.resonance, 0.6),
            (.morphBalance, 0.8),
            (.index1, 0.25),
            (.index2, 0.75),
            (.morph2SemitoneOffset, 7),
            (.subVolume, 0.4),
            (.fmVolume, 0.3),
            (.fmAmount, 4),
            (.attackDuration, 0.01),
            (.releaseDuration, 0.3),
            (.filterADSRMix, 0.5),
            (.masterVolume, 0.4)
        ]
        for (parameter, value) in patch {
            unit.setSynthParameter(parameter, value: value)
        }
    }

    private func render(_ unit: S1AudioUnit, seconds: Double) throws -> [Float] {
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: unit.outputBus.format,
                                                    frameCapacity: framesPerBlock))
        buffer.frameLength = framesPerBlock
        let renderBlock = unit.internalRenderBlock

        var out: [Float] = []
        var sampleTime: Double = 0
        var started = false
        while sampleTime < seconds * sampleRate {
            if !started, sampleTime / sampleRate >= settleTime {
                started = true
                unit.startNote(69, velocity: 100)
            }
            var flags = AudioUnitRenderActionFlags()
            var timestamp = AudioTimeStamp()
            timestamp.mSampleTime = sampleTime
            timestamp.mFlags = .sampleTimeValid
            XCTAssertEqual(renderBlock(&flags, &timestamp, framesPerBlock, 0,
                                       buffer.mutableAudioBufferList, nil, nil), noErr)
            if let channel = buffer.floatChannelData?[0] {
                out.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(framesPerBlock)))
            }
            sampleTime += Double(framesPerBlock)
        }
        return out
    }

    // MARK: - The acceptance criterion

    /// **P4-4's whole point.** Save a patch, throw the unit away, restore into a
    /// fresh one, and play the same note: the audio has to match.
    ///
    /// Sample-for-sample, not "roughly" — the DSP is deterministic (that is what
    /// the P2-4 golden files rest on), so any difference here is a piece of state
    /// that did not survive the round trip.
    func testFullStateRoundTripsTheRenderedAudio() throws {
        let saved = try makeUnit()
        applyDistinctivePatch(to: saved)
        let state = try XCTUnwrap(saved.fullState)
        let before = try render(saved, seconds: settleTime + 1.0)

        let restored = try makeUnit()
        restored.fullState = state
        let after = try render(restored, seconds: settleTime + 1.0)

        XCTAssertEqual(before.count, after.count)
        XCTAssertGreaterThan(Signal.peak(before), 0.02, "the patch rendered near-silence")

        var worst: Float = 0
        for (a, b) in zip(before, after) { worst = max(worst, abs(a - b)) }
        XCTAssertLessThan(worst, 1e-6,
                          "restored audio differs by \(worst) — some state is not in fullState")
    }

    /// And the comparison above can actually fail. A restore that quietly did
    /// nothing would pass a test that only compared a unit against itself, so this
    /// pins that a *default* unit sounds different from the patched one.
    func testTheComparisonWouldCatchAFailedRestore() throws {
        let patched = try makeUnit()
        applyDistinctivePatch(to: patched)
        let patchedAudio = try render(patched, seconds: settleTime + 1.0)

        let untouched = try makeUnit()
        let defaultAudio = try render(untouched, seconds: settleTime + 1.0)

        var worst: Float = 0
        for (a, b) in zip(patchedAudio, defaultAudio) { worst = max(worst, abs(a - b)) }
        XCTAssertGreaterThan(worst, 1e-3,
                             "the patch is not audibly distinct, so the round-trip test proves little")
    }

    // MARK: - The part the parameter tree does not carry

    /// The tuning table is 128 arbitrary frequencies with no parameter address —
    /// the Tunings panel can load them from a Scala file. `AUAudioUnit`'s default
    /// `fullState` serialises the parameter tree and would drop every one of them,
    /// and a preset restored in the wrong temperament is a wrong preset.
    func testFullStateCarriesTheTuningTable() throws {
        let saved = try makeUnit()
        // A tuning nothing else would produce: every note a quarter-tone sharp.
        for note in 0..<128 {
            saved.setTuningTable(Float(440.0 * pow(2.0, (Double(note) - 69 + 0.5) / 12.0)), index: Int32(note))
        }
        saved.setTuningTableNPO(24)
        let state = try XCTUnwrap(saved.fullState)

        let restored = try makeUnit()
        XCTAssertNotEqual(restored.getTuningTableFrequency(69), saved.getTuningTableFrequency(69),
                          accuracy: 0.01, "a fresh unit should still be in 12-ET")
        restored.fullState = state

        for note in [0, 21, 60, 69, 100, 127] {
            XCTAssertEqual(restored.getTuningTableFrequency(Int32(note)),
                           saved.getTuningTableFrequency(Int32(note)),
                           accuracy: 0.001, "MIDI \(note)")
        }
        XCTAssertEqual(restored.getTuningTableNPO(), 24)
    }

    /// And it is audible, not just stored. A quarter-tone table has to make the
    /// same MIDI note come out at a different pitch.
    func testARestoredTuningChangesThePitchThatIsPlayed() throws {
        let saved = try makeUnit()
        for note in 0..<128 {
            saved.setTuningTable(Float(440.0 * pow(2.0, (Double(note) - 69 + 0.5) / 12.0)), index: Int32(note))
        }
        let restored = try makeUnit()
        restored.fullState = try XCTUnwrap(saved.fullState)

        let signal = try render(restored, seconds: settleTime + 2.0)
        let window = Int((settleTime + 0.5) * sampleRate)..<Int((settleTime + 1.9) * sampleRate)
        let pitch = Signal.fundamental(Array(signal[window]), sampleRate: sampleRate)

        // A4 a quarter-tone sharp is 452.89 Hz, not 440.
        XCTAssertEqual(pitch, 452.89, accuracy: 2.5,
                       "the restored tuning table is not reaching the oscillators")
    }

    // MARK: - What a host will actually hand back

    /// A session written by a build *older than P4-4* has none of our keys. It must
    /// restore its parameters and leave the tuning alone — not refuse to open.
    func testAStateWithoutOurKeysStillRestoresParameters() throws {
        let saved = try makeUnit()
        applyDistinctivePatch(to: saved)
        var state = try XCTUnwrap(saved.fullState)
        for key in state.keys where key.hasPrefix("com.badpackets303.SynthOne") {
            state.removeValue(forKey: key)
        }

        let restored = try makeUnit()
        restored.fullState = state

        XCTAssertEqual(restored.getSynthParameter(.cutoff), 1_800, accuracy: 1)
        XCTAssertEqual(restored.getTuningTableFrequency(69), 440, accuracy: 0.01,
                       "no tuning in the state means 12-ET, not garbage")
    }

    /// Hosts and files are not always well behaved. Wrong types and a truncated
    /// table are the two shapes a corrupt session actually takes, and neither may
    /// take the plugin down.
    func testAMalformedStateIsIgnoredRatherThanTrusted() throws {
        let unit = try makeUnit()
        let reference = unit.getTuningTableFrequency(69)

        for bad: [String: Any] in [
            ["com.badpackets303.SynthOne.tuningTable": "not data"],
            ["com.badpackets303.SynthOne.tuningTable": Data(repeating: 0xFF, count: 7)],
            ["com.badpackets303.SynthOne.tuningNPO": "twelve"]
        ] {
            unit.fullState = bad
            XCTAssertEqual(unit.getTuningTableFrequency(69), reference, accuracy: 0.01)
        }
        unit.fullState = nil
    }

    /// The 48 sequencer values look like separate state and are not: they are
    /// `S1Parameter`s, so the parameter tree already carries them. Worth pinning,
    /// because the obvious reading of `Preset+Synth.swift` — where they are set
    /// through `setPattern(forIndex:)` rather than by name — suggests otherwise.
    func testTheSequencerPatternIsCarriedByTheParameterTree() throws {
        let saved = try makeUnit()
        for step in 0..<16 {
            saved.setSynthParameter(S1Parameter(rawValue: S1Parameter.sequencerPattern00.rawValue
                                                + Int32(step))!, value: Float(step - 8))
            saved.setSynthParameter(S1Parameter(rawValue: S1Parameter.sequencerNoteOn00.rawValue
                                                + Int32(step))!, value: step % 2 == 0 ? 1 : 0)
        }
        let restored = try makeUnit()
        restored.fullState = try XCTUnwrap(saved.fullState)

        for step in 0..<16 {
            let pattern = S1Parameter(rawValue: S1Parameter.sequencerPattern00.rawValue + Int32(step))!
            let noteOn = S1Parameter(rawValue: S1Parameter.sequencerNoteOn00.rawValue + Int32(step))!
            XCTAssertEqual(restored.getSynthParameter(pattern), Float(step - 8), accuracy: 0.001,
                           "step \(step) pattern")
            XCTAssertEqual(restored.getSynthParameter(noteOn), step % 2 == 0 ? 1 : 0, accuracy: 0.001,
                           "step \(step) note-on")
        }
    }

    /// `tempoSyncToArpRate` and `arpRate` re-drive four other parameters through
    /// `_rateHelper` (ADR-022), so restoring 150 values is order-sensitive in a way
    /// setting one value is not. Tempo-synced rates have to survive the round trip.
    func testTempoSyncedRatesSurviveTheRoundTrip() throws {
        let saved = try makeUnit()
        saved.setSynthParameter(.tempoSyncToArpRate, value: 1)
        saved.setSynthParameter(.arpRate, value: 132)
        saved.setSynthParameter(.lfo1Rate, value: 4.4)
        saved.setSynthParameter(.delayTime, value: 0.37)

        let restored = try makeUnit()
        restored.fullState = try XCTUnwrap(saved.fullState)

        XCTAssertEqual(restored.getSynthParameter(.arpRate), saved.getSynthParameter(.arpRate),
                       accuracy: 0.001)
        XCTAssertEqual(restored.getSynthParameter(.lfo1Rate), saved.getSynthParameter(.lfo1Rate),
                       accuracy: 0.001, "quantized rate did not survive")
        XCTAssertEqual(restored.getSynthParameter(.delayTime), saved.getSynthParameter(.delayTime),
                       accuracy: 0.001)
    }

    /// State carries a version so a later schema change can migrate rather than
    /// guess what an old dictionary meant.
    func testStateIsVersioned() throws {
        let state = try XCTUnwrap(try makeUnit().fullState)
        XCTAssertEqual(state["com.badpackets303.SynthOne.stateVersion"] as? Int, 1)
    }
}
