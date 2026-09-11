//  P2-1 acceptance: the audio path is ours.
//
//  P1-6 proved the DSP makes sound when driven by hand. This drives it the way the
//  app will — `AKSynthOne` instantiated through real audio-component registration,
//  attached to an `AVAudioEngine` we own, rendered through the engine's graph
//  rather than by calling the kernel's render block directly.
//
//  Nothing here touches AudioKit. `S1AudioEngine` replaces `AudioKit.engine` /
//  `AudioKit.output` / `AudioKit.start()` (ADR-014).

import XCTest
import AVFoundation
import AudioToolbox
@testable import SynthOneCore

final class S1AudioEngineTests: XCTestCase {

    private let sampleRate: Double = 44_100
    private let framesPerBlock: AVAudioFrameCount = 512

    /// Matches P1-6: every portamento-enabled parameter re-ramps from zero when
    /// render resources are allocated, so the synth sweeps into tune. Measure
    /// after this. ADR-013.
    private let settleTime: Double = 1.0

    // MARK: - Harness
    //
    // The render loop and the estimators live in `Support/OfflineRender.swift`;
    // P2-4 needed the same thing and this was the second copy.

    private func makeRig(sampleRate: Double? = nil) throws -> OfflineSynth {
        try OfflineSynth(sampleRate: sampleRate ?? self.sampleRate, framesPerBlock: framesPerBlock)
    }

    private func peak(_ x: [Float]) -> Float { Signal.peak(x) }
    private func rms(_ x: ArraySlice<Float>) -> Float { Signal.rms(x) }
    private func fundamental(_ x: [Float], sampleRate: Double) -> Double {
        Signal.fundamental(x, sampleRate: sampleRate)
    }

    // MARK: - Tests

    /// `AKSynthOne()` registers its audio unit subclass and instantiates it. The
    /// identity check is the point: the shipping AUv3 registers the *same*
    /// `aumu`/`ruin`/`BP03` description system-wide, and Mac Catalyst has no
    /// `.loadInProcess` option to force the issue. If this ever returns the
    /// installed extension instead, everything else here would still pass while
    /// testing the wrong binary.
    func testSynthInstantiatesOurOwnAudioUnitInProcess() {
        let synth = AKSynthOne()
        XCTAssertNotNil(synth.internalAU, "instantiation must be synchronous — init reads it")
        // Upstream assigns the AVAudioUnit to `avAudioNode`, never to `avAudioUnit`,
        // so `avAudioUnitOrNode` is the way to reach it. Preserved as-is; the
        // distinction only matters to code that asks.
        let node = synth.avAudioUnitOrNode as? AVAudioUnit
        XCTAssertNotNil(node, "the node in the graph is the audio unit itself")
        XCTAssertTrue(node?.auAudioUnit is S1AudioUnit,
                      "must be the registered in-process subclass, not the installed AUv3")
        XCTAssertNotNil(synth.midiInstrument, "a MusicDevice component must vend a MIDI instrument")
        XCTAssertEqual(synth.internalAU?.parameterTree?.allParameters.count, 150)
    }

    /// The wavetables come from the framework bundle now, not `Bundle.main`
    /// (upstream's iOS app bundle). If that lookup silently failed, the
    /// oscillators would have empty tables — so this asserts on the tables
    /// themselves rather than waiting to hear about it.
    func testWavetablesLoadFromTheFrameworkBundle() throws {
        let bundle = AKSynthOne.bundle
        XCTAssertNotNil(bundle.url(forResource: "bandlimitedWaveforms", withExtension: "json"))
        XCTAssertNotNil(bundle.url(forResource: "bandlimitedWaveformFrequencies", withExtension: "json"))
        let names = try JSONDecoder().decode(
            [String].self,
            from: Data(contentsOf: XCTUnwrap(bundle.url(forResource: "bandlimitedWaveforms",
                                                        withExtension: "json"))))
        XCTAssertEqual(names.count, AKSynthOne.SNUMWAVEFORMS * AKSynthOne.SNUMBANDLIMITEDFTABLES)
        for name in names {
            XCTAssertNotNil(bundle.url(forResource: name, withExtension: "json"), "missing \(name)")
        }
    }

    /// **The P2-1 acceptance criterion.** Audio comes out of an `AVAudioEngine`
    /// graph — synth into a mixer into the output — with no AudioKit anywhere.
    func testEngineGraphRendersAudio() throws {
        let rig = try makeRig()
        var started = false
        let render = try rig.render(seconds: settleTime + 1.5) { time, synth in
            guard !started, time >= settleTime else { return }
            started = true
            synth.play(noteNumber: 69, velocity: 127)
        }
        XCTAssertGreaterThan(peak(render.left), 0.05)
        XCTAssertGreaterThan(peak(render.right), 0.05)
        XCTAssertGreaterThan(rms(render.left[Int((settleTime + 0.5) * sampleRate)...]), 0.01)
    }

    /// `play(noteNumber:velocity:)` is `AKPolyphonicNode`'s — it looks the pitch up
    /// in the tuning table and forwards. The note that comes out must be the note
    /// that went in.
    func testPlayedNoteSoundsAtTheRightPitch() throws {
        for (note, expected) in [(69, 440.0), (57, 220.0), (64, 329.6276)] {
            let rig = try makeRig()
            var started = false
            let render = try rig.render(seconds: settleTime + 2.0) { time, synth in
                guard !started, time >= settleTime else { return }
                started = true
                synth.play(noteNumber: MIDINoteNumber(note), velocity: 127)
            }
            let window = Int((settleTime + 0.5) * sampleRate)..<Int((settleTime + 1.9) * sampleRate)
            let measured = fundamental(Array(render.left[window]), sampleRate: sampleRate)
            XCTAssertEqual(measured, expected, accuracy: expected * 0.005,
                           "MIDI \(note): expected \(expected) Hz, measured \(measured) Hz")
        }
    }

    /// `stop(noteNumber:)` must release the voice through the same path.
    func testStoppedNoteReleases() throws {
        let rig = try makeRig()
        var started = false, stopped = false
        let render = try rig.render(seconds: settleTime + 2.0) { time, synth in
            if !started, time >= settleTime { started = true; synth.play(noteNumber: 69, velocity: 127) }
            if !stopped, time >= settleTime + 1.0 { stopped = true; synth.stop(noteNumber: 69) }
        }
        let sustaining = rms(render.left[Int((settleTime + 0.5) * sampleRate)..<Int((settleTime + 0.9) * sampleRate)])
        let released = rms(render.left[Int((settleTime + 1.5) * sampleRate)..<Int((settleTime + 1.9) * sampleRate)])
        XCTAssertGreaterThan(sustaining, 0.01)
        XCTAssertLessThan(released, sustaining * 0.05)
    }

    /// The mixer is a real node in the graph, not decoration: its volume has to
    /// reach the output.
    func testMixerVolumeAffectsOutput() throws {
        func renderAtVolume(_ volume: Double) throws -> Float {
            let rig = try makeRig()
            // Set after the graph is built: an AVAudioMixerNode does not retain an
            // outputVolume set while it is unattached.
            rig.mixer.volume = volume
            var started = false
            let render = try rig.render(seconds: settleTime + 1.0) { time, synth in
                guard !started, time >= settleTime else { return }
                started = true
                synth.play(noteNumber: 69, velocity: 127)
            }
            return rms(render.left[Int((settleTime + 0.5) * sampleRate)...])
        }
        let loud = try renderAtVolume(1.0)
        let quiet = try renderAtVolume(0.25)
        XCTAssertGreaterThan(loud, 0.01)
        XCTAssertEqual(Double(quiet / loud), 0.25, accuracy: 0.05)
    }

    /// Hosts run at 48 kHz as often as 44.1. `AKSettings.sampleRate` is what the
    /// audio unit builds its bus format from, so this exercises the rate all the
    /// way through `sicvt` rescaling in `updateWavetableIncrementValuesForCurrentSampleRate`.
    func testRendersAtFortyEightKilohertz() throws {
        let original = AKSettings.sampleRate
        AKSettings.sampleRate = 48_000
        defer { AKSettings.sampleRate = original }

        let rig = try makeRig(sampleRate: 48_000)
        XCTAssertEqual(rig.engine.engine.manualRenderingFormat.sampleRate, 48_000)
        var started = false
        let render = try rig.render(seconds: settleTime + 2.0) { time, synth in
            guard !started, time >= settleTime else { return }
            started = true
            synth.play(noteNumber: 69, velocity: 127)
        }
        let window = Int((settleTime + 0.5) * 48_000)..<Int((settleTime + 1.9) * 48_000)
        XCTAssertEqual(fundamental(Array(render.left[window]), sampleRate: 48_000),
                       440, accuracy: 2.2)
    }

    /// Start, pause, resume. `Conductor.stopEngine()` pauses rather than stops so
    /// the graph survives; the synth has to still be there afterwards.
    func testEngineSurvivesPauseAndResume() throws {
        let rig = try makeRig()
        var started = false
        _ = try rig.render(seconds: settleTime + 0.5) { time, synth in
            guard !started, time >= settleTime else { return }
            started = true
            synth.play(noteNumber: 69, velocity: 127)
        }
        rig.engine.pause()
        XCTAssertFalse(rig.engine.isRunning)
        try rig.engine.engine.start()
        XCTAssertTrue(rig.engine.isRunning)

        let render = try rig.render(seconds: 0.5)
        XCTAssertGreaterThan(peak(render.left), 0.01, "the held note should still be sounding")
    }

    // MARK: - ADR-043: restarting after the audio hardware changes
    //
    // The owner's standalone went silent 10 seconds after launch: AirPods came out of an ear, macOS
    // moved the default output, AVAudioEngine stopped itself and posted
    // `AVAudioEngineConfigurationChange`, and nothing started it again. A real restart would open a
    // hardware device, which blocks an xctest process for 90 seconds (ADR-015), so these replace the
    // restart with a counter. That `start()` sets the flag was checked in the running app.

    private func counting(_ audioEngine: S1AudioEngine) -> () -> Int {
        var restarts = 0
        audioEngine.restartAfterConfigurationChange = { _ in restarts += 1 }
        return { restarts }
    }

    private func postConfigurationChange(for engine: AVAudioEngine) {
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
    }

    /// **The silent standalone.**
    func testAHardwareChangeRestartsAnEngineThatShouldBeRunning() {
        let audioEngine = S1AudioEngine()
        let restarts = counting(audioEngine)
        audioEngine.shouldBeRunning = true      // what a realtime `start()` sets

        postConfigurationChange(for: audioEngine.engine)

        XCTAssertEqual(restarts(), 1, "the engine stopped itself and nothing started it again")
    }

    /// `Conductor.stopEngine()` pauses on purpose; a device change must not undo that.
    func testAHardwareChangeLeavesAPausedEngineAlone() {
        let audioEngine = S1AudioEngine()
        let restarts = counting(audioEngine)
        audioEngine.shouldBeRunning = true
        audioEngine.pause()

        postConfigurationChange(for: audioEngine.engine)

        XCTAssertEqual(restarts(), 0)
    }

    /// Each engine listens for its own changes only. The tests run many engines in one process.
    func testAnotherEnginesHardwareChangeIsIgnored() {
        let audioEngine = S1AudioEngine()
        let restarts = counting(audioEngine)
        audioEngine.shouldBeRunning = true

        postConfigurationChange(for: AVAudioEngine())

        XCTAssertEqual(restarts(), 0)
    }

    /// Offline rendering has no hardware, so switching to it clears the flag.
    func testAnOfflineRenderIsNeverRestarted() throws {
        let rig = try makeRig()
        let restarts = counting(rig.engine)
        rig.engine.shouldBeRunning = true
        try rig.engine.startOfflineRendering(sampleRate: sampleRate)

        postConfigurationChange(for: rig.engine.engine)

        XCTAssertEqual(restarts(), 0)
    }
}
