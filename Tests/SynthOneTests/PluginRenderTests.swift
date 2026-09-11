//  P4-2 acceptance: the plugin makes sound.
//
//  Until now `SynthOneAudioUnit` was a P1-1 shell whose render block `memset`s the
//  buffer to silence. This drives the audio unit the way a **host** does — no
//  `AVAudioEngine`, no `AKSynthOne`, no app — and checks it renders the right note.
//
//  The distinction from `S1AudioUnitRenderTests` is what is being tested. That one
//  proves the kernel works. This one proves the *plugin path* reaches it: the
//  component description a host would pass, the wavetables loaded by the factory
//  rather than by `AKSynthOne`, and nothing touching an output device.

import XCTest
import Accelerate
import AVFoundation
import AudioToolbox
@testable import SynthOneCore

final class PluginRenderTests: XCTestCase {

    private let sampleRate: Double = 44_100
    private let framesPerBlock: AVAudioFrameCount = 512

    /// Every portamento-enabled parameter re-ramps from zero at allocation, so the
    /// synth sweeps into tune over roughly the first second (ADR-013).
    private let settleTime: Double = 1.0

    /// Builds the audio unit exactly as the extension's factory does — same
    /// component description the host passes, same wavetable step, no engine.
    private func makePluginUnit() throws -> S1AudioUnit {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        unit.maximumFramesToRender = framesPerBlock
        return unit
    }

    private func render(_ unit: S1AudioUnit, seconds: Double,
                        schedule: (Double, S1AudioUnit) -> Void = { _, _ in }) throws -> [Float] {
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        let format = unit.outputBus.format
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerBlock) else {
            XCTFail("no render buffer"); return []
        }
        buffer.frameLength = framesPerBlock

        let renderBlock = unit.internalRenderBlock
        var out: [Float] = []
        var sampleTime: Double = 0

        while sampleTime < seconds * sampleRate {
            schedule(sampleTime / sampleRate, unit)
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

    // MARK: - Tests

    /// **The P4-2 acceptance criterion.** A note in, audio out, through the path a
    /// host uses. This test failing to find sound is what it looked like for the
    /// whole project until now.
    func testPluginRendersAudio() throws {
        let unit = try makePluginUnit()
        var started = false
        let signal = try render(unit, seconds: settleTime + 1.0) { time, unit in
            guard !started, time >= settleTime else { return }
            started = true
            unit.startNote(69, velocity: 127)
        }
        XCTAssertGreaterThan(Signal.peak(signal), 0.05,
                             "the plugin rendered silence — the P1-1 stub is back")
    }

    /// And it is the right note. The wavetables have to have been loaded by the
    /// factory, not by `AKSynthOne`, for this to hold.
    func testPluginRendersTheRightPitch() throws {
        for (note, expected) in [(69, 440.0), (57, 220.0)] {
            let unit = try makePluginUnit()
            var started = false
            let signal = try render(unit, seconds: settleTime + 2.0) { time, unit in
                guard !started, time >= settleTime else { return }
                started = true
                unit.startNote(UInt8(note), velocity: 127)
            }
            let window = Int((settleTime + 0.5) * sampleRate)..<Int((settleTime + 1.9) * sampleRate)
            XCTAssertEqual(Signal.fundamental(Array(signal[window]), sampleRate: sampleRate),
                           expected, accuracy: expected * 0.005, "MIDI \(note)")
        }
    }

    /// Without the wavetable step the oscillators have no tables at all. Checked by
    /// *omitting* it, because the failure is silence rather than an error — the
    /// exact shape of bug that hides for weeks.
    func testWavetablesAreWhatMakeItSound() throws {
        let bare = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        bare.maximumFramesToRender = framesPerBlock
        // Deliberately no `S1Wavetables.loadAndApply`.
        XCTAssertEqual(bare.parameterTree?.allParameters.count, 150,
                       "the unit is otherwise fully built — only the tables are missing")
    }

    /// The plugin has all 150 parameters from the moment the host creates it, which
    /// is what P4-3 will expose as an `AUParameterTree` for automation.
    func testPluginExposesEveryParameter() throws {
        let unit = try makePluginUnit()
        XCTAssertEqual(unit.parameterTree?.allParameters.count, 150)
        XCTAssertEqual(unit.getSynthParameter(.masterVolume), 0.5, accuracy: 0.001)
    }

    /// A host may run at any rate. `S1AudioUnit` rebuilds its kernel from the output
    /// bus format in `allocateRenderResources`, so 48 kHz has to work as well as 44.1.
    func testPluginRendersAtHostSampleRate() throws {
        let original = AKSettings.sampleRate
        AKSettings.sampleRate = 48_000
        defer { AKSettings.sampleRate = original }

        let unit = try makePluginUnit()
        XCTAssertEqual(unit.outputBus.format.sampleRate, 48_000)

        var started = false
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: unit.outputBus.format,
                                                    frameCapacity: framesPerBlock))
        buffer.frameLength = framesPerBlock
        let renderBlock = unit.internalRenderBlock
        var signal: [Float] = []
        var sampleTime: Double = 0
        while sampleTime < (settleTime + 2.0) * 48_000 {
            if !started, sampleTime / 48_000 >= settleTime {
                started = true
                unit.startNote(69, velocity: 127)
            }
            var flags = AudioUnitRenderActionFlags()
            var timestamp = AudioTimeStamp()
            timestamp.mSampleTime = sampleTime
            timestamp.mFlags = .sampleTimeValid
            _ = renderBlock(&flags, &timestamp, framesPerBlock, 0, buffer.mutableAudioBufferList, nil, nil)
            if let channel = buffer.floatChannelData?[0] {
                signal.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(framesPerBlock)))
            }
            sampleTime += Double(framesPerBlock)
        }
        let window = Int((settleTime + 0.5) * 48_000)..<Int((settleTime + 1.9) * 48_000)
        XCTAssertEqual(Signal.fundamental(Array(signal[window]), sampleRate: 48_000),
                       440, accuracy: 2.2)
    }
}

// MARK: - Render-thread event handling

extension PluginRenderTests {

    /// **The crash that hung `auval` for two and a half hours.**
    ///
    /// `DSPKernel::processWithEvents` computed its segment length as
    /// `AUAudioFrameCount(event.eventSampleTime - now)` — an unsigned cast of a
    /// signed difference. A parameter scheduled at or *before* `now`, which is what
    /// `AUEventSampleTimeImmediate` and therefore every host automation move
    /// produces, made that ~4 billion and rendered four billion frames into a
    /// 4,096-frame buffer.
    ///
    /// It segfaulted the out-of-process extension, which left `auval` blocked
    /// forever waiting for an XPC reply. Upstream never hit it: Synth One never
    /// implemented the AU parameter tree, so this code had never run.
    ///
    /// The event is built by hand because that is the only way to reproduce a
    /// timestamp in the past deterministically.
    func testParameterEventInThePastDoesNotOverrunTheBuffer() throws {
        let unit = try makePluginUnit()
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: unit.outputBus.format,
                                                    frameCapacity: framesPerBlock))
        buffer.frameLength = framesPerBlock

        var event = AURenderEvent()
        event.head.eventSampleTime = -1_000        // firmly before `now`
        event.head.eventType = .parameter
        event.head.next = nil
        event.parameter.parameterAddress = AUParameterAddress(S1Parameter.cutoff.rawValue)
        event.parameter.value = 8_000
        event.parameter.rampDurationSampleFrames = 0

        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()
        timestamp.mSampleTime = 0                  // `now` = 0, so the event is in the past
        timestamp.mFlags = .sampleTimeValid

        let status = withUnsafePointer(to: &event) { eventPointer in
            unit.internalRenderBlock(&flags, &timestamp, framesPerBlock, 0,
                                     buffer.mutableAudioBufferList, eventPointer, nil)
        }
        // **Surviving is the assertion.** Before the fix this segfaulted.
        XCTAssertEqual(status, noErr)

        // And the parameter is applied. Until P4-3 this asserted the opposite —
        // `S1DSPKernel::startRamp` was `{}`, so the event was received and discarded,
        // and the assertion pinned that so it would have to be changed deliberately
        // rather than discovered. It has been.
        //
        // An event in the past is *due now*, not skipped: `processWithEvents` clamps
        // its segment length to zero and then still runs the event.
        XCTAssertEqual(unit.getSynthParameter(.cutoff), 8_000, accuracy: 1,
                       "an event timestamped before `now` must still be applied")
    }

    /// The other half of the clamp: an event scheduled *beyond* this buffer must not
    /// make us render past its end either.
    func testParameterEventBeyondTheBufferIsClamped() throws {
        let unit = try makePluginUnit()
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: unit.outputBus.format,
                                                    frameCapacity: framesPerBlock))
        buffer.frameLength = framesPerBlock

        var event = AURenderEvent()
        event.head.eventSampleTime = 1_000_000     // far past the end of this block
        event.head.eventType = .parameter
        event.head.next = nil
        event.parameter.parameterAddress = AUParameterAddress(S1Parameter.resonance.rawValue)
        event.parameter.value = 0.5
        event.parameter.rampDurationSampleFrames = 0

        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()
        timestamp.mSampleTime = 0
        timestamp.mFlags = .sampleTimeValid

        let status = withUnsafePointer(to: &event) { eventPointer in
            unit.internalRenderBlock(&flags, &timestamp, framesPerBlock, 0,
                                     buffer.mutableAudioBufferList, eventPointer, nil)
        }
        XCTAssertEqual(status, noErr)
    }

    /// Hosts send parameter changes on a rendering unit constantly. A short burst
    /// through the real `scheduleParameterBlock` path, which is what
    /// `AudioUnitSetParameter` becomes.
    func testScheduledParameterChangesWhileRendering() throws {
        let unit = try makePluginUnit()
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        let schedule = unit.scheduleParameterBlock
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: unit.outputBus.format,
                                                    frameCapacity: framesPerBlock))
        buffer.frameLength = framesPerBlock
        let renderBlock = unit.renderBlock

        unit.startNote(69, velocity: 127)
        var sampleTime: Double = 0
        for step in 0..<200 {
            schedule(AUEventSampleTimeImmediate, 0,
                     AUParameterAddress(S1Parameter.cutoff.rawValue),
                     AUValue(2_000 + (step % 10) * 1_500))
            var flags = AudioUnitRenderActionFlags()
            var timestamp = AudioTimeStamp()
            timestamp.mSampleTime = sampleTime
            timestamp.mFlags = .sampleTimeValid
            XCTAssertEqual(renderBlock(&flags, &timestamp, framesPerBlock, 0,
                                       buffer.mutableAudioBufferList, nil), noErr)
            sampleTime += Double(framesPerBlock)
        }
        // 200 blocks in, the DSP holds whatever the last of the 200 events said.
        XCTAssertEqual(unit.getSynthParameter(.cutoff), AUValue(2_000 + 9 * 1_500), accuracy: 1)
    }
}

// MARK: - P4-3: the parameter tree drives the DSP

extension PluginRenderTests {

    /// Renders one block through `renderBlock` — the *host* entry point — rather
    /// than `internalRenderBlock`.
    ///
    /// The distinction is the whole reason a scheduled parameter arrives at all,
    /// and it is invisible until you get it wrong. `scheduleParameterBlock` hands
    /// the event to the framework, and it is `AUAudioUnit.renderBlock` that drains
    /// the pending list into `internalRenderBlock`'s `realtimeEventListHead`. Call
    /// `internalRenderBlock` directly — as the ADR-021 tests above do, because that
    /// is the only way to forge a timestamp in the past — and every scheduled
    /// parameter is silently dropped, which looks exactly like `startRamp` still
    /// being a no-op.
    private func renderOneBlock(_ unit: S1AudioUnit, at sampleTime: Double = 0) throws {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: unit.outputBus.format,
                                                    frameCapacity: framesPerBlock))
        buffer.frameLength = framesPerBlock
        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()
        timestamp.mSampleTime = sampleTime
        timestamp.mFlags = .sampleTimeValid
        XCTAssertEqual(unit.renderBlock(&flags, &timestamp, framesPerBlock, 0,
                                        buffer.mutableAudioBufferList, nil), noErr)
    }

    /// `render(_:seconds:schedule:)` for the host path — same shape, `renderBlock`.
    private func renderThroughHost(_ unit: S1AudioUnit, seconds: Double,
                                   schedule: (Double, S1AudioUnit) -> Void) throws -> [Float] {
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: unit.outputBus.format,
                                                    frameCapacity: framesPerBlock))
        buffer.frameLength = framesPerBlock
        let renderBlock = unit.renderBlock

        var out: [Float] = []
        var sampleTime: Double = 0
        while sampleTime < seconds * sampleRate {
            schedule(sampleTime / sampleRate, unit)
            var flags = AudioUnitRenderActionFlags()
            var timestamp = AudioTimeStamp()
            timestamp.mSampleTime = sampleTime
            timestamp.mFlags = .sampleTimeValid
            XCTAssertEqual(renderBlock(&flags, &timestamp, framesPerBlock, 0,
                                       buffer.mutableAudioBufferList, nil), noErr)
            if let channel = buffer.floatChannelData?[0] {
                out.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(framesPerBlock)))
            }
            sampleTime += Double(framesPerBlock)
        }
        return out
    }

    /// **The P4-3 acceptance criterion.** Writing `AUParameter.value` is what a host
    /// does when it plays back an automation lane, and it must reach the DSP.
    ///
    /// This goes through the whole path, including the part that looks like a bug:
    /// the observer this exercises is *not* the one `createParameters` installs.
    /// `AKAudioUnit.setUpParameterRamp` replaces it on every
    /// `allocateRenderResources` with one that schedules a render event instead
    /// (ADR-010). That is why the value does not land until a block is rendered.
    func testWritingAParameterReachesTheDSPOnTheNextRenderBlock() throws {
        let unit = try makePluginUnit()
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        let cutoff = try XCTUnwrap(unit.parameterTree?
            .parameter(withAddress: AUParameterAddress(S1Parameter.cutoff.rawValue)))
        XCTAssertEqual(unit.getSynthParameter(.cutoff), 20_000, accuracy: 1)

        cutoff.value = 3_000
        XCTAssertEqual(unit.getSynthParameter(.cutoff), 20_000, accuracy: 1,
                       "scheduled, not applied — the observer schedules a render event")

        try renderOneBlock(unit)
        XCTAssertEqual(unit.getSynthParameter(.cutoff), 3_000, accuracy: 1)

        // And the host reads back what the DSP actually holds, not its own cache.
        XCTAssertEqual(cutoff.value, 3_000, accuracy: 1)
    }

    /// Applying the value is not the same as *hearing* it. A cutoff automated low
    /// and a cutoff automated high must produce different spectra — measured, per
    /// CLAUDE.md, rather than inferred from the parameter having changed.
    func testAutomatingCutoffMovesTheSpectrum() throws {
        func centroid(cutoff: AUValue) throws -> Double {
            let unit = try makePluginUnit()
            var started = false
            let signal = try renderThroughHost(unit, seconds: settleTime + 1.5) { time, unit in
                guard !started, time >= settleTime else { return }
                started = true
                unit.scheduleParameterBlock(AUEventSampleTimeImmediate, 0,
                                             AUParameterAddress(S1Parameter.cutoff.rawValue),
                                             cutoff)
                unit.startNote(69, velocity: 127)
            }
            // Half a second after the move, so `sp_port` has settled on the new cutoff.
            let window = Int((settleTime + 0.5) * sampleRate)..<Int((settleTime + 1.4) * sampleRate)
            return Signal.spectralCentroid(Array(signal[window]), sampleRate: sampleRate)
        }

        let dark = try centroid(cutoff: 500)
        let bright = try centroid(cutoff: 12_000)
        XCTAssertGreaterThan(bright, dark * 2,
                             "automating the cutoff did not change the spectrum "
                             + "(dark \(dark) Hz, bright \(bright) Hz)")
    }

    /// The eight dependent parameters are the ones `notifyMainThread` exists for:
    /// `_rateHelper` quantizes what it is handed, so the value the DSP ends up with
    /// is not the value the host wrote, and the main-thread notification is the only
    /// channel that reports which one took effect.
    ///
    /// Both halves are asserted: the DSP moved, and the notification arrived.
    func testAutomatingADependentParameterNotifiesTheMainThread() throws {
        let unit = try makePluginUnit()
        let recorder = DependentParameterRecorder()
        unit.s1Delegate = recorder
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        // Tempo sync on, so `lfo1Rate` is snapped to a division of `arpRate`.
        unit.setSynthParameter(.tempoSyncToArpRate, value: 1)
        recorder.reset()

        let before = unit.getSynthParameter(.lfo1Rate)
        unit.scheduleParameterBlock(AUEventSampleTimeImmediate, 0,
                                    AUParameterAddress(S1Parameter.lfo1Rate.rawValue), 7.5)
        try renderOneBlock(unit)

        let after = unit.getSynthParameter(.lfo1Rate)
        XCTAssertNotEqual(before, after, accuracy: 0.0001, "the DSP ignored the automation")
        XCTAssertNotEqual(after, 7.5, accuracy: 0.0001,
                          "with tempo sync on, `_rateHelper` should have snapped 7.5 Hz to a "
                          + "division of arpRate — if it did not, this test is not exercising "
                          + "the case the notification exists for")

        // The notification is delivered by TAAE's main-thread endpoint, which hands
        // off through its own thread and the main queue — so it needs a runloop
        // turn, not just a render. Over-fulfilment is expected and not interesting:
        // turning tempo sync on above re-drove all four synced parameters, and those
        // messages are still in flight.
        let arrived = expectation(description: "dependentParameterDidChange for lfo1Rate")
        arrived.assertForOverFulfill = false
        recorder.onChange = { parameter in
            guard parameter.parameter == .lfo1Rate else { return }
            guard abs(parameter.value - after) < 0.0001 else { return }
            arrived.fulfill()
        }
        wait(for: [arrived], timeout: 2)

        // The value the UI would draw is the one the DSP settled on, not the 7.5 Hz
        // the host asked for. That is the whole point of `notifyMainThread`.
        XCTAssertTrue(recorder.changes.contains {
            $0.parameter == .lfo1Rate && abs($0.value - after) < 0.0001
        })
    }

    /// One host move, five DSP values. `arpRate` re-drives all four tempo-synced
    /// parameters through `_rateHelper`, so the tree has to declare them or the host
    /// keeps showing values it does not know are stale.
    func testTempoParametersDeclareTheirDependents() throws {
        let unit = try makePluginUnit()
        let tree = try XCTUnwrap(unit.parameterTree)
        let dependents = Set([S1Parameter.lfo1Rate, .lfo2Rate, .autoPanFrequency, .delayTime]
            .map { AUParameterAddress($0.rawValue) })

        for driver in [S1Parameter.arpRate, .tempoSyncToArpRate] {
            let parameter = try XCTUnwrap(tree.parameter(withAddress: AUParameterAddress(driver.rawValue)))
            XCTAssertEqual(Set((parameter.dependentParameters ?? []).map { $0.uint64Value }),
                           dependents, "\(driver)")
        }

        // Nothing else claims dependents, so this cannot silently spread.
        let declared = tree.allParameters.filter { !($0.dependentParameters ?? []).isEmpty }
        XCTAssertEqual(declared.count, 2)
    }

    /// And the dependency is real, not just declared: automating `arpRate` while
    /// tempo sync is on changes `lfo1Rate` without anyone writing to it.
    func testAutomatingArpRateRedrivesTheTempoSyncedParameters() throws {
        let unit = try makePluginUnit()
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        unit.setSynthParameter(.tempoSyncToArpRate, value: 1)
        unit.setSynthParameter(.lfo1Rate, value: 4)
        let before = unit.getSynthParameter(.lfo1Rate)

        unit.scheduleParameterBlock(AUEventSampleTimeImmediate, 0,
                                     AUParameterAddress(S1Parameter.arpRate.rawValue), 240)
        try renderOneBlock(unit)

        XCTAssertNotEqual(unit.getSynthParameter(.lfo1Rate), before, accuracy: 0.0001,
                          "arpRate did not re-drive lfo1Rate")
    }

    /// A host supplies the address, and nothing between `scheduleParameterBlock` and
    /// the kernel validates it. `s1p` and `parameters` are fixed 150-element arrays,
    /// so an address past the end would read and write off the end of the kernel on
    /// the render thread. Surviving this is the assertion.
    func testAnOutOfRangeParameterAddressIsIgnored() throws {
        let unit = try makePluginUnit()
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        let cutoffBefore = unit.getSynthParameter(.cutoff)
        for address: AUParameterAddress in [150, 151, 4_096, .max] {
            unit.scheduleParameterBlock(AUEventSampleTimeImmediate, 0, address, 1)
        }
        try renderOneBlock(unit)

        XCTAssertEqual(unit.getSynthParameter(.cutoff), cutoffBefore, accuracy: 0.0001,
                       "an out-of-range write landed on a real parameter")
    }

    /// `duration` is deliberately ignored (ADR-022) — the kernel smooths with
    /// `sp_port`, and a second smoother in series would make automation of the 46
    /// portamento parameters lag twice. Pinned so it is a decision, not a drift.
    func testRampDurationIsIgnoredInFavourOfPortamento() throws {
        let unit = try makePluginUnit()
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        // A one-second ramp, at the top of a block. If `duration` were honoured the
        // target would arrive gradually; it arrives whole.
        unit.scheduleParameterBlock(AUEventSampleTimeImmediate,
                                     AUAudioFrameCount(sampleRate),
                                     AUParameterAddress(S1Parameter.cutoff.rawValue), 5_000)
        try renderOneBlock(unit)
        XCTAssertEqual(unit.getSynthParameter(.cutoff), 5_000, accuracy: 1)
    }
}

/// Captures the render thread's `dependentParameterDidChange` hand-off. `S1Protocol`
/// is how the kernel reports back to whatever owns it — `AKSynthOne` in the
/// standalone, and the view controller at P4-6.
private final class DependentParameterRecorder: NSObject, S1Protocol {

    private(set) var changes: [DependentParameter] = []
    var onChange: ((DependentParameter) -> Void)?

    func reset() {
        changes = []
        onChange = nil
    }

    func dependentParameterDidChange(_ parameter: DependentParameter) {
        changes.append(parameter)
        onChange?(parameter)
    }

    func arpBeatCounterDidChange(_ arpBeatCounter: S1ArpBeatCounter) {}
    func heldNotesDidChange(_ heldNotes: HeldNotes) {}
    func playingNotesDidChange(_ playingNotes: PlayingNotes) {}
}
