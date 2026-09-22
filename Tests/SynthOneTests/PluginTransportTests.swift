//  P4-5 acceptance: the plugin runs to the host's clock.
//
//  The host blocks (`musicalContextBlock`, `transportStateBlock`) are properties the
//  *host* sets before allocating render resources. These tests set them the same way
//  and then render, so the code under test is the real render-block path rather than
//  a method called directly.
//
//  Where it matters the assertion is on the **audio**: that the arpeggiator's notes
//  actually come twice as fast at twice the tempo, not merely that a parameter
//  changed. The P4-4 tuning bug is what that habit is for.

import XCTest
import AVFoundation
import AudioToolbox
@testable import SynthOneCore

final class PluginTransportTests: XCTestCase {

    private let sampleRate: Double = 44_100
    private let framesPerBlock: AVAudioFrameCount = 512
    private let settleTime: Double = 1.0

    private func makeUnit() throws -> S1AudioUnit {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        unit.maximumFramesToRender = framesPerBlock
        units.append(unit)
        return unit
    }

    /// Stands in for the host's tempo. `tempo` is a box so a test can move it
    /// mid-render, which is the case that matters — a tempo that never changes would
    /// not exercise the change detection.
    private final class HostClock {
        var tempo: Double = 120
        var isMoving = true
    }

    private func attach(_ clock: HostClock, to unit: S1AudioUnit) {
        unit.musicalContextBlock = { tempo, timeSignatureNumerator, timeSignatureDenominator,
                                     currentBeatPosition, sampleOffsetToNextBeat, currentMeasureDownbeatPosition in
            tempo?.pointee = clock.tempo
            timeSignatureNumerator?.pointee = 4
            timeSignatureDenominator?.pointee = 4
            currentBeatPosition?.pointee = 0
            sampleOffsetToNextBeat?.pointee = 0
            currentMeasureDownbeatPosition?.pointee = 0
            return true
        }
        unit.transportStateBlock = { flags, currentSamplePosition, cycleStart, cycleEnd in
            flags?.pointee = clock.isMoving ? .moving : []
            currentSamplePosition?.pointee = 0
            cycleStart?.pointee = 0
            cycleEnd?.pointee = 0
            return true
        }
    }

    @discardableResult
    private func render(_ unit: S1AudioUnit, seconds: Double,
                        each: (Double, S1AudioUnit) -> Void = { _, _ in }) throws -> [Float] {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: unit.outputBus.format,
                                                    frameCapacity: framesPerBlock))
        buffer.frameLength = framesPerBlock
        let renderBlock = unit.internalRenderBlock

        var out: [Float] = []
        var sampleTime: Double = 0
        while sampleTime < seconds * sampleRate {
            each(sampleTime / sampleRate, unit)
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

    /// Counts the sequencer's own beat notifications.
    ///
    /// The first version of these tests counted note attacks in the rendered audio,
    /// which was the wrong instrument: the arpeggiator's notes overlap and the whole
    /// patch fades up through portamento, so the envelope never falls back between
    /// notes and everything reads as one onset. The beat counter *is* the sequencer's
    /// clock, so counting it measures exactly the thing host tempo is supposed to
    /// change — and it is exact rather than heuristic.
    private final class BeatSpy: NSObject, S1Protocol {
        private(set) var beats = 0
        private(set) var lastCounter = -1
        func arpBeatCounterDidChange(_ counter: S1ArpBeatCounter) {
            beats += 1
            lastCounter = Int(counter.beatCounter)
        }
        func dependentParameterDidChange(_ parameter: DependentParameter) {}
        func heldNotesDidChange(_ notes: HeldNotes) {}
        func playingNotesDidChange(_ notes: PlayingNotes) {}
    }

    /// Beat notifications arrive through TAAE's main-thread endpoint, so they need
    /// runloop turns before they can be counted. Holding the units is for the
    /// *counting*; it is no longer required for safety — see
    /// `testDestroyingAUnitWithMessagesInFlightIsSafe`.
    private var units: [S1AudioUnit] = []

    override func tearDown() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        units.removeAll()
        super.tearDown()
    }

    private func drain() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    }

    // MARK: - Tempo

    /// **Host tempo is `arpRate`.** Settled by upstream's own Ableton Link listener,
    /// which did exactly this: `setSynthParameter(.arpRate, bpm)`. Link is dropped
    /// (ADR-004), which is why the work is here.
    func testHostTempoSetsArpRate() throws {
        let unit = try makeUnit()
        let clock = HostClock()
        clock.tempo = 90
        attach(clock, to: unit)

        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }
        XCTAssertEqual(unit.getSynthParameter(.arpRate), 120, accuracy: 0.001, "before any render")

        try render(unit, seconds: 0.05)
        XCTAssertEqual(unit.getSynthParameter(.arpRate), 90, accuracy: 0.001)

        // And it follows the host when the project tempo changes mid-playback.
        clock.tempo = 143
        try render(unit, seconds: 0.05)
        XCTAssertEqual(unit.getSynthParameter(.arpRate), 143, accuracy: 0.001)
    }

    /// **Owner-reported: Logic's default project tempo is 120, and the plugin did not
    /// pick it up.**
    ///
    /// The change detector compared the host tempo against a `tempo` member that was
    /// *initialised to 120*, so a 120 BPM project never looked like a change and
    /// `arpRate` was never set. Every tempo except 120 worked, which is the worst
    /// kind of bug — and the log line that looked like confirmation (`tempo=100`) was
    /// actually the preset's own `arpRate` showing that nothing had happened.
    func testTheHostsDefaultTempoIsApplied() throws {
        let unit = try makeUnit()
        let clock = HostClock()
        clock.tempo = 120                     // Logic's default
        attach(clock, to: unit)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        // A preset has set its own tempo, as one did in the case that exposed this.
        unit.setSynthParameter(.arpRate, value: 100)
        try render(unit, seconds: 0.05)

        XCTAssertEqual(unit.getSynthParameter(.arpRate), 120, accuracy: 0.001,
                       "the host's tempo did not reach the plugin")
    }

    /// The host stays authoritative: anything that moves `arpRate` away from the
    /// project tempo is corrected on the next block, so loading a preset in a plugin
    /// cannot leave the arpeggiator running at the wrong tempo.
    func testAPresetCannotLeaveTheTempoOutOfSyncWithTheHost() throws {
        let unit = try makeUnit()
        let clock = HostClock()
        clock.tempo = 137
        attach(clock, to: unit)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        try render(unit, seconds: 0.05)
        XCTAssertEqual(unit.getSynthParameter(.arpRate), 137, accuracy: 0.001)

        unit.setSynthParameter(.arpRate, value: 90)   // a preset load
        try render(unit, seconds: 0.05)
        XCTAssertEqual(unit.getSynthParameter(.arpRate), 137, accuracy: 0.001,
                       "the preset's tempo survived — the plugin is out of sync with the host")
    }

    /// A project tempo outside `arpRate`'s range must settle at the clamp rather than
    /// being re-applied on every render block — that would re-drive four dependent
    /// parameters and post a main-thread message thousands of times a second.
    func testAnOutOfRangeTempoSettlesInsteadOfRepeating() throws {
        let unit = try makeUnit()
        let spy = TempoCounter()
        unit.s1Delegate = spy
        let clock = HostClock()
        clock.tempo = 100_000
        attach(clock, to: unit)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        try render(unit, seconds: 1.0)
        drain()

        XCTAssertEqual(unit.getSynthParameter(.arpRate), unit.getMaximum(.arpRate), accuracy: 0.001)
        XCTAssertLessThan(spy.count, 5,
                          "the tempo was re-applied every block (\(spy.count) notifications)")
    }

    private final class TempoCounter: NSObject, S1Protocol {
        private(set) var count = 0
        func hostTempoDidChange(_ tempo: Float) { count += 1 }
        func dependentParameterDidChange(_ parameter: DependentParameter) {}
        func arpBeatCounterDidChange(_ counter: S1ArpBeatCounter) {}
        func heldNotesDidChange(_ notes: HeldNotes) {}
        func playingNotesDidChange(_ notes: PlayingNotes) {}
    }

    /// **The tempo has to reach the interface, not just the DSP** (owner-reported:
    /// "the plug-in tempo needs to match Logic's").
    ///
    /// `handleTempoSetting` runs on the render thread and writes `arpRate` straight
    /// into the kernel, which is right for the audio and invisible to everything
    /// else — the plugin's tempo control kept reading 120 while the arpeggiator ran
    /// at the project tempo. It now posts to the main thread as well.
    func testTheHostTempoIsReportedToTheInterface() throws {
        final class TempoSpy: NSObject, S1Protocol {
            var tempos: [Float] = []
            func hostTempoDidChange(_ tempo: Float) { tempos.append(tempo) }
            func dependentParameterDidChange(_ parameter: DependentParameter) {}
            func arpBeatCounterDidChange(_ counter: S1ArpBeatCounter) {}
            func heldNotesDidChange(_ notes: HeldNotes) {}
            func playingNotesDidChange(_ notes: PlayingNotes) {}
        }

        let unit = try makeUnit()
        let spy = TempoSpy()
        unit.s1Delegate = spy
        let clock = HostClock()
        clock.tempo = 96
        attach(clock, to: unit)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        try render(unit, seconds: 0.05)
        drain()

        XCTAssertTrue(spy.tempos.contains { abs($0 - 96) < 0.001 },
                      "the interface was never told the host tempo: \(spy.tempos)")
    }

    /// A tempo change has to re-quantize everything synced to it. `arpRate` re-drives
    /// four parameters through `_rateHelper` (ADR-022), and that is the mechanism —
    /// so this is really checking that the tempo goes in through the same door.
    func testATempoChangeRequantizesTheTempoSyncedParameters() throws {
        let unit = try makeUnit()
        let clock = HostClock()
        attach(clock, to: unit)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        unit.setSynthParameter(.tempoSyncToArpRate, value: 1)
        unit.setSynthParameter(.lfo1Rate, value: 4)
        try render(unit, seconds: 0.05)
        let atOneTwenty = unit.getSynthParameter(.lfo1Rate)

        // 100, not 60: at 60 BPM the beat is 1 Hz and 4 Hz is *still* an exact
        // division, so the value would legitimately not move and the test would be
        // measuring nothing. At 100 BPM the divisions are 1.67, 3.33, 6.67 …
        clock.tempo = 100
        try render(unit, seconds: 0.05)
        XCTAssertNotEqual(unit.getSynthParameter(.lfo1Rate), atOneTwenty, accuracy: 0.0001,
                          "changing the host tempo did not re-quantize lfo1Rate")
    }

    /// X2 gate (ADR-082, the owner's decision): a host's tempo change keeps the NOTE VALUE of
    /// what is synced to it. Upstream re-quantised by time, so a jump far enough landed on a
    /// neighbour — 125 → 90 BPM turned a quarter-note delay (0.48 s) into a quarter triplet
    /// (0.444 s), and a 3 Hz quarter-triplet LFO at 120 silently became an eighth note at 90.
    func testAHostTempoJumpKeepsTheNoteValue() throws {
        let unit = try makeUnit()
        let clock = HostClock()
        clock.tempo = 125
        attach(clock, to: unit)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        unit.setSynthParameter(.tempoSyncToArpRate, value: 1)
        try render(unit, seconds: 0.05)
        unit.setSynthParameter(.delayTime, value: 0.48)      // a quarter note at 125
        unit.setSynthParameter(.lfo1Rate, value: 125.0 / 60.0)
        try render(unit, seconds: 0.05)
        XCTAssertEqual(unit.getSynthParameter(.delayTime), 0.48, accuracy: 1e-5)

        clock.tempo = 90
        try render(unit, seconds: 0.05)
        XCTAssertEqual(unit.getSynthParameter(.delayTime), 60.0 / 90.0, accuracy: 1e-5,
                       "the quarter-note delay is not a quarter note at 90 BPM")
        XCTAssertEqual(unit.getSynthParameter(.lfo1Rate), 1.5, accuracy: 1e-5,
                       "the quarter-note LFO is not a quarter note at 90 BPM")

        clock.tempo = 125
        try render(unit, seconds: 0.05)
        XCTAssertEqual(unit.getSynthParameter(.delayTime), 0.48, accuracy: 1e-5, "and back")
    }

    /// An absurd tempo cannot push `arpRate` outside its own range — `setSynthParameter`
    /// clamps, and this pins that the render thread relies on it.
    func testAnAbsurdHostTempoIsClamped() throws {
        let unit = try makeUnit()
        let clock = HostClock()
        attach(clock, to: unit)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        for tempo in [0.0, -50, 100_000] {
            clock.tempo = tempo
            try render(unit, seconds: 0.05)
            let rate = unit.getSynthParameter(.arpRate)
            XCTAssertGreaterThanOrEqual(rate, unit.getMinimum(.arpRate))
            XCTAssertLessThanOrEqual(rate, unit.getMaximum(.arpRate))
        }
    }

    /// **Measured, not inferred.** Twice the tempo has to produce about twice as many
    /// arpeggiator steps in the same span. Asserting only that `arpRate` changed
    /// would pass even if the value never reached the sequencer's clock.
    func testTheArpeggiatorRunsAtTheHostTempo() throws {
        func beats(atTempo tempo: Double) throws -> Int {
            let unit = try makeUnit()
            let spy = BeatSpy()
            unit.s1Delegate = spy
            let clock = HostClock()
            clock.tempo = tempo
            attach(clock, to: unit)
            try unit.allocateRenderResources()
            defer { unit.deallocateRenderResources() }

            unit.setSynthParameter(.arpIsOn, value: 1)
            unit.startNote(60, velocity: 110)
            let signal = try render(unit, seconds: 4.0)
            drain()
            XCTAssertGreaterThan(Signal.peak(signal), 0.02, "the arpeggiator made no sound")
            return spy.beats
        }

        let slow = try beats(atTempo: 100)
        let fast = try beats(atTempo: 200)
        XCTAssertGreaterThan(slow, 4, "the arpeggiator did not run at all")
        XCTAssertEqual(Double(fast) / Double(slow), 2, accuracy: 0.35,
                       "double the host tempo gave \(fast) steps against \(slow) — "
                       + "the tempo is not reaching the sequencer's clock")
    }

    // MARK: - Transport

    /// A host that stops must not leave the synth droning. Hosts usually send
    /// note-offs when the transport stops, but not always, and a synth still sounding
    /// after the user hits stop is the worst version of this.
    func testStoppingTheTransportReleasesSoundingNotes() throws {
        let unit = try makeUnit()
        let clock = HostClock()
        attach(clock, to: unit)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        unit.setSynthParameter(.releaseDuration, value: 0.05)
        try render(unit, seconds: settleTime)
        unit.startNote(60, velocity: 120)

        let sounding = try render(unit, seconds: 0.5)
        XCTAssertGreaterThan(Signal.rms(sounding), 0.005, "nothing was playing to begin with")

        clock.isMoving = false
        let afterStop = try render(unit, seconds: 1.0)

        // The tail is allowed; what matters is that it is decaying to nothing.
        let end = Array(afterStop[(afterStop.count - Int(0.2 * sampleRate))...])
        XCTAssertLessThan(Signal.rms(end), Signal.rms(sounding) * 0.05,
                          "the note was still sounding a second after the host stopped")
    }

    /// Starting again should begin a phrase, not resume mid-arpeggio.
    func testStoppingTheTransportResetsTheSequencer() throws {
        let unit = try makeUnit()
        let spy = BeatSpy()
        unit.s1Delegate = spy
        let clock = HostClock()
        attach(clock, to: unit)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        unit.setSynthParameter(.arpIsOn, value: 1)
        unit.startNote(60, velocity: 110)
        try render(unit, seconds: 2.5)
        drain()
        XCTAssertGreaterThan(spy.lastCounter, 0, "the sequencer never advanced")

        let beforeStop = spy.lastCounter

        clock.isMoving = false
        // Short: the note is still held, so once the position is rewound the
        // arpeggiator starts counting up again from zero. What is being asserted is
        // that it *rewound*, not that it stayed still.
        try render(unit, seconds: 0.05)
        drain()
        XCTAssertLessThan(spy.lastCounter, beforeStop,
                          "the sequencer did not rewind — it was at \(spy.lastCounter)")
        XCTAssertEqual(unit.getSynthParameter(.arpIsOn), 1, "the arp itself must stay switched on")
    }

    /// X2-7 (ADR-078): the render cycle runs with subnormals flushed to zero, and the caller's
    /// floating-point mode is back when it returns. The host's tempo block is called from inside
    /// the render block, so what it computes is computed in the render's mode: two 1e-20 floats
    /// multiply to 1e-40 where subnormals exist, and to 0 where they are flushed.
    func testTheRenderFlushesSubnormalsAndHandsTheModeBack() throws {
        let unit = try makeUnit()
        let small: [Float] = [1e-20, Float(units.count) * 1e-20]
        func tinyProduct() -> Float { small[0] * small[1] }
        var seenInsideTheRender: Float = -1
        unit.musicalContextBlock = { tempo, _, _, _, _, _ in
            seenInsideTheRender = tinyProduct()
            tempo?.pointee = 120
            return true
        }
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        XCTAssertGreaterThan(tinyProduct(), 0, "this thread does not compute subnormals to begin with")
        try render(unit, seconds: 0.1)
        XCTAssertEqual(seenInsideTheRender, 0, "the render cycle computed a subnormal: flush-to-zero is not on")
        XCTAssertGreaterThan(tinyProduct(), 0, "the render left flush-to-zero on in its caller's thread")
    }

    /// X2-6 (ADR-077), found by the JUCE plugin's transport test and true here since P4-5: the
    /// stop released the voices without letting their envelopes see the gate fall. A voice that
    /// had already died away (no sustain) was freed before it ran again, its envelope still held
    /// open — and the next note given to it had no attack: the first note of the next phrase was
    /// silent. The stop also left every key down, so the arpeggio went on after it.
    func testAPhraseAfterAStopBeginsWithItsFirstNote() throws {
        let unit = try makeUnit()
        let clock = HostClock()
        attach(clock, to: unit)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        unit.setSynthParameter(.attackDuration, value: unit.getMinimum(.attackDuration))
        unit.setSynthParameter(.decayDuration, value: 0.01)
        unit.setSynthParameter(.sustainLevel, value: 0)
        unit.setSynthParameter(.releaseDuration, value: 0.01)
        unit.setSynthParameter(.filterADSRMix, value: 0)
        unit.setSynthParameter(.cutoff, value: 20_000)
        unit.setSynthParameter(.reverbOn, value: 0)
        unit.setSynthParameter(.delayOn, value: 0)
        unit.setSynthParameter(.arpIsOn, value: 1)
        unit.setSynthParameter(.arpSeqTempoMultiplier, value: 0.25)
        try render(unit, seconds: 2.0)      // the glides from 0 (ADR-013)

        func firstClick(_ samples: [Float]) -> Float {
            samples.prefix(Int(0.05 * sampleRate)).map(abs).max() ?? 0
        }
        for note in [UInt8(48), 55, 64] { unit.startNote(note, velocity: 110) }
        let before = try render(unit, seconds: 0.7)
        XCTAssertGreaterThan(firstClick(before), 0.02, "the first phrase had no first note either")

        clock.isMoving = false
        try render(unit, seconds: 0.1)
        let stopped = try render(unit, seconds: 1.0)
        XCTAssertLessThan(stopped.map(abs).max() ?? 1, 0.001,
                          "keys still down when the transport stopped went on arpeggiating")

        clock.isMoving = true
        try render(unit, seconds: 0.1)
        for note in [UInt8(48), 55, 64] { unit.startNote(note, velocity: 110) }
        let after = try render(unit, seconds: 0.7)
        XCTAssertGreaterThan(firstClick(after), firstClick(before) * 0.5,
                             "the first note of the phrase after a stop was silent")
    }

    /// Only the *edge* acts. A host reporting "playing" on every block must not be
    /// resetting the sequencer on every block — which would pin the beat counter at
    /// zero and stop the arpeggiator dead.
    func testAContinuouslyPlayingTransportDoesNotDisturbTheArpeggiator() throws {
        let unit = try makeUnit()
        let spy = BeatSpy()
        unit.s1Delegate = spy
        let clock = HostClock()
        attach(clock, to: unit)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        unit.setSynthParameter(.arpIsOn, value: 1)
        unit.startNote(60, velocity: 110)
        try render(unit, seconds: 3.0)
        drain()

        XCTAssertGreaterThan(spy.beats, 4, "the arpeggiator was reset on every render block")
        XCTAssertGreaterThan(spy.lastCounter, 0)
    }

    // MARK: - Render-thread messaging

    /// **The crash that took the test runner down twice.**
    ///
    /// `AEMessageQueuePerformSelectorOnMainThread` stores its target as a raw pointer
    /// in a lock-free ring buffer — retaining on the render thread is not real-time
    /// safe — and `AEMainThreadEndpoint` delivers it later via `dispatch_async`. A
    /// unit destroyed in between left the handler doing `objc_retain` on freed
    /// memory. Upstream never met it: one synth, alive for the life of the app.
    ///
    /// The render thread now addresses an immortal `S1MessageRelay` that holds a
    /// *weak* reference to the unit, so a late message finds `nil` and does nothing.
    ///
    /// **These three tests check the mechanism, not the crash.** A use-after-free is
    /// not deterministic — the version of this that dropped units with a backlog and
    /// then drained passed against the *unfixed* code, because the freed memory had
    /// not been reused yet. A test that only sometimes reproduces is worse than one
    /// that states what it actually verifies.
    func testTheRelayOutlivesItsAudioUnit() throws {
        weak var weakUnit: S1AudioUnit?
        var relay: S1MessageRelay?

        autoreleasepool {
            let unit = try? S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription,
                                        options: [])
            weakUnit = unit
            relay = unit?.messageRelay
            XCTAssertNotNil(relay, "the DSP has nothing to post to")
            XCTAssertIdentical(relay?.unit, unit)
        }

        XCTAssertNil(weakUnit, "the unit should be gone")
        XCTAssertNotNil(relay, "the relay must survive it — the ring buffer still points here")
        XCTAssertNil(relay?.unit, "and its reference to the unit must be weak, so it reads nil")
    }

    /// A message that arrives after its unit has gone is late, not wrong: every
    /// selector the DSP posts has to be a no-op rather than a crash.
    func testTheRelayIgnoresMessagesForAUnitThatHasGone() {
        let relay = S1MessageRelay()
        XCTAssertNil(relay.unit)

        // The four the render thread sends. Surviving is the assertion.
        relay.dependentParameterDidChange(DependentParameter())
        relay.arpBeatCounterDidChange(S1ArpBeatCounter())
        relay.heldNotesDidChange(HeldNotes())
        relay.playingNotesDidChange(PlayingNotes())
    }

    /// And while the unit *is* alive the relay must forward, or the UI would simply
    /// stop updating — a silent regression rather than a crash.
    func testTheRelayForwardsWhileTheUnitIsAlive() throws {
        let unit = try makeUnit()
        let spy = BeatSpy()
        unit.s1Delegate = spy
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        unit.setSynthParameter(.arpIsOn, value: 1)
        unit.startNote(60, velocity: 110)
        _ = try render(unit, seconds: 1.5)
        drain()

        XCTAssertGreaterThan(spy.beats, 0,
                             "nothing arrived — the relay is swallowing messages")
    }

    /// Not every host provides these blocks, and the standalone provides neither.
    /// Rendering without them has to behave exactly as before.
    func testAHostThatSuppliesNoClockStillRenders() throws {
        let unit = try makeUnit()
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        unit.startNote(69, velocity: 110)
        let signal = try render(unit, seconds: settleTime + 0.5)
        XCTAssertGreaterThan(Signal.peak(signal), 0.02)
        XCTAssertEqual(unit.getSynthParameter(.arpRate), 120, accuracy: 0.001,
                       "arpRate moved with no host to move it")
    }
}
