//  ADR-031: the plugin takes MIDI only from its host.
//
//  Measured in Logic on 2026-09-10, the plugin opened every CoreMIDI input itself *and* took its
//  host's MIDI in the render block. A key sounded twice — as two different notes, on two
//  threads — and a plugin on an unselected track still answered a hardware keyboard. Now the
//  render block is the only route, and `S1HostMIDI` does there what the standalone's MIDI chain
//  does on the main thread.
//
//  - `HostMIDIRouterTests` drives the plugin's audio unit as a host does, and reads back what
//    the router did.
//  - `HostMIDIParityTests` sends the same MIDI through the standalone's Swift chain and through
//    the router, and requires the same notes. It is what stops the two drifting apart.
//  - `HostMIDIInterfaceTests` loads the plugin's interface: it opens no MIDI inputs, every
//    setting reaches the render thread, and controls and held keys come back to it.

import XCTest
import AVFoundation
@testable import SynthOneCore

// MARK: - Harness

/// A note call the synth received, from either chain.
enum HostMIDINote: Equatable, CustomStringConvertible {
    case on(MIDINoteNumber, MIDIVelocity)
    case off(MIDINoteNumber)

    var description: String {
        switch self {
        case let .on(note, velocity): return "on(\(note), \(velocity))"
        case let .off(note): return "off(\(note))"
        }
    }

    /// `KeyboardView.allNotesOff` releases keys in `Set` order, so a run of consecutive stops is
    /// compared as a set. Nothing else in either chain releases several notes in an order of its
    /// own choosing — the sustain pedal goes lowest first in both.
    static func normalised(_ calls: [HostMIDINote]) -> [HostMIDINote] {
        var result: [HostMIDINote] = []
        var run: [MIDINoteNumber] = []
        func flush() {
            result += run.sorted().map { .off($0) }
            run.removeAll()
        }
        for call in calls {
            if case let .off(note) = call {
                run.append(note)
            } else {
                flush()
                result.append(call)
            }
        }
        flush()
        return result
    }
}

extension HostMIDINote {
    /// As `Tests/Engine/Fixtures/host-midi.txt` spells a note call.
    var fixtureWord: String {
        switch self {
        case let .on(note, velocity): return "+\(note):\(velocity)"
        case let .off(note): return "-\(note)"
        }
    }
}

/// One entry of `S1HostMIDITrace`.
struct HostMIDITraceEntry: Equatable {
    enum Op: UInt32 {
        case hostNoteOn = 1, hostNoteOff, keyNoteOn, keyNoteOff, allNotesOff, pitchBend
    }
    let op: Op
    let note: UInt8
    let value: UInt16
}

/// The plugin's audio unit, driven the way a host drives it: MIDI through
/// `scheduleMIDIEventBlock`, audio through `renderBlock`.
///
/// `renderBlock` and not `internalRenderBlock`: scheduled events are held by the framework, and
/// only `renderBlock` hands them over (ADR-022).
final class HostDriver {

    static let framesPerBlock: AVAudioFrameCount = 512

    let unit: S1AudioUnit
    private let buffer: AVAudioPCMBuffer
    private var sampleTime: Double = 0

    /// Built by the plugin's own factory, so it is the unit a host gets.
    convenience init() throws {
        try self.init(unit: SynthOneApp.makePluginAudioUnit(componentDescription: AKSynthOne.ComponentDescription))
    }

    init(unit: S1AudioUnit) throws {
        self.unit = unit
        unit.maximumFramesToRender = Self.framesPerBlock
        guard let buffer = AVAudioPCMBuffer(pcmFormat: unit.outputBus.format,
                                            frameCapacity: Self.framesPerBlock) else {
            throw HostDriverError.noBuffer
        }
        buffer.frameLength = Self.framesPerBlock
        self.buffer = buffer
        unit.hostMIDITraceEnabled = true
        try unit.allocateRenderResources()
    }

    deinit { unit.deallocateRenderResources() }

    var sampleRate: Double { unit.outputBus.format.sampleRate }

    /// Schedules `bytes` as a host would, then renders one block — which is when they arrive.
    func send(_ bytes: [UInt8]) {
        guard let schedule = unit.scheduleMIDIEventBlock else {
            XCTFail("the unit offers no scheduleMIDIEventBlock, so no host could send it MIDI")
            return
        }
        bytes.withUnsafeBufferPointer { pointer in
            schedule(AUEventSampleTimeImmediate, 0, pointer.count, pointer.baseAddress!)
        }
        render()
    }

    @discardableResult
    func render() -> [Float] {
        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()
        timestamp.mSampleTime = sampleTime
        timestamp.mFlags = .sampleTimeValid
        XCTAssertEqual(unit.renderBlock(&flags, &timestamp, Self.framesPerBlock, 0,
                                        buffer.mutableAudioBufferList, nil), noErr)
        sampleTime += Double(Self.framesPerBlock)
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    func render(seconds: Double) -> [Float] {
        let blocks = Int((seconds * sampleRate / Double(Self.framesPerBlock)).rounded(.up))
        var out: [Float] = []
        for _ in 0..<blocks { out += render() }
        return out
    }

    func takeTrace() -> [HostMIDITraceEntry] {
        var raw = [UInt32](repeating: 0, count: 1024)
        let count = raw.withUnsafeMutableBufferPointer { words in
            unit.takeHostMIDITrace(words.baseAddress!, capacity: words.count)
        }
        return raw.prefix(count).compactMap { word in
            guard let op = HostMIDITraceEntry.Op(rawValue: word >> 24) else { return nil }
            return HostMIDITraceEntry(op: op, note: UInt8((word >> 16) & 0xFF), value: UInt16(word & 0xFFFF))
        }
    }

    /// Only the notes the router played for host MIDI.
    func takeNotes() -> [HostMIDINote] {
        takeTrace().compactMap { entry in
            switch entry.op {
            case .hostNoteOn: return .on(entry.note, MIDIVelocity(entry.value))
            case .hostNoteOff: return .off(entry.note)
            default: return nil
            }
        }
    }

    func setSettings(_ change: (inout S1HostMIDISettings) -> Void) {
        var settings = unit.hostMIDISettings
        change(&settings)
        unit.hostMIDISettings = settings
    }
}

enum HostDriverError: Error {
    case noBuffer
}

/// Runs the main queue until everything already on it has run. The standalone's note-offs arrive
/// that way.
private func drainMainQueue() {
    var drained = false
    DispatchQueue.main.async { drained = true }
    while !drained {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

/// Messages from the render thread reach the main queue through TAAE's endpoint thread, so they
/// need real run-loop time, not just a drain.
private func waitForRenderThreadMessages() {
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
}

/// SplitMix64: the same MIDI on every run, so a failure can be replayed.
private struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - The router, through the plugin's audio unit

final class HostMIDIRouterTests: XCTestCase {

    private var drivers: [HostDriver] = []

    override func tearDown() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        drivers.removeAll()
        super.tearDown()
    }

    private func makeHost() throws -> HostDriver {
        let host = try HostDriver()
        drivers.append(host)
        return host
    }

    /// The plugin's factory turns routing on, and nothing else does: the standalone's unit runs
    /// upstream's `handleMIDIEvent` exactly as before.
    func testOnlyThePluginsFactoryRoutesHostMIDI() throws {
        XCTAssertTrue(try makeHost().unit.routesHostMIDI)
        let bare = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        XCTAssertFalse(bare.routesHostMIDI)
    }

    /// **One key, one note**, at the velocity the host sent. That the plugin no longer plays a
    /// second copy through CoreMIDI is `HostMIDIInterfaceTests.testThePluginOpensNoMIDIInputsOfItsOwn`.
    func testAHostNoteIsPlayedOnce() throws {
        let host = try makeHost()
        host.send([0x90, 60, 100])
        XCTAssertEqual(host.takeNotes(), [.on(60, 100)])
        host.send([0x80, 60, 0])
        XCTAssertEqual(host.takeNotes(), [.off(60)])
    }

    /// **The plugin always plays the host's velocity** — the owner's decision, ADR-032. A DAW's
    /// regions carry their own dynamics. The standalone's velocity-sensitivity switch is not
    /// consulted, and the plugin could not have saved it anyway.
    func testTheHostsVelocityIsAlwaysPlayed() throws {
        let host = try makeHost()
        for velocity: UInt8 in [1, 64, 127] {
            host.send([0x90, 60, velocity])
            host.send([0x80, 60, 0])
            XCTAssertEqual(host.takeNotes(), [.on(60, velocity), .off(60)], "velocity \(velocity)")
        }
    }

    /// `Octave:` shifts host MIDI, and a note-off releases the note its note-on started even if the
    /// octave moved while the key was down.
    func testTheOctaveShiftsHostNotesAndANoteOffReleasesWhatItStarted() throws {
        let host = try makeHost()
        host.setSettings { $0.octaveShift = -12 }
        host.send([0x90, 60, 100])
        XCTAssertEqual(host.takeNotes(), [.on(48, 100)])
        host.setSettings { $0.octaveShift = 12 }
        host.send([0x80, 60, 0])
        XCTAssertEqual(host.takeNotes(), [.off(48)], "the note would stick")
    }

    func testANoteShiftedOutOfRangeIsDroppedNotClamped() throws {
        let host = try makeHost()
        host.setSettings { $0.octaveShift = 36 }
        host.send([0x90, 120, 100])
        host.send([0x80, 120, 0])
        XCTAssertEqual(host.takeNotes(), [])
    }

    func testTheSustainPedalHoldsHostNotesUntilItLifts() throws {
        let host = try makeHost()
        host.send([0x90, 60, 100])
        host.send([0xB0, 64, 127])
        host.send([0x80, 60, 0])
        XCTAssertEqual(host.takeNotes(), [.on(60, 100)], "released with the pedal down")
        host.send([0xB0, 64, 0])
        XCTAssertEqual(host.takeNotes(), [.off(60)])
    }

    /// Hold ignores note-offs; pressing a held key again releases it (`KeyboardView.pressAdded`);
    /// and switching hold off releases everything it held.
    func testHold() throws {
        let host = try makeHost()
        host.setSettings { $0.holdMode = true }
        host.render()
        host.send([0x90, 60, 100])
        host.send([0x80, 60, 0])
        XCTAssertEqual(host.takeNotes(), [.on(60, 100)])
        host.send([0x90, 60, 100])
        XCTAssertEqual(host.takeNotes(), [.off(60)], "a second press of a held key releases it")
        host.send([0x90, 62, 100])
        host.send([0x80, 62, 0])
        XCTAssertEqual(host.takeNotes(), [.on(62, 100)])
        host.setSettings { $0.holdMode = false }
        host.render()
        XCTAssertEqual(host.takeNotes(), [.off(62)], "hold off releases what it held")
    }

    func testTheMIDIChannelFiltersHostNotes() throws {
        let host = try makeHost()
        host.setSettings {
            $0.omniMode = false
            $0.midiChannel = 2
        }
        host.send([0x95, 60, 100])
        XCTAssertEqual(host.takeNotes(), [], "a note on another channel played")
        host.send([0x92, 60, 100])
        XCTAssertEqual(host.takeNotes(), [.on(60, 100)])
    }

    func testWhiteKeysOnlyRemapsHostNotes() throws {
        let host = try makeHost()
        host.setSettings { $0.whiteKeysOnly = true }
        host.send([0x90, 61, 100])
        XCTAssertEqual(host.takeNotes(), [.on(60, 100)], "`whiteKeysOnlyMap[61]` is 60")
    }

    func testMonoReturnsToTheHighestNoteStillHeld() throws {
        let host = try makeHost()
        host.unit.setSynthParameter(.isMono, value: 1)
        host.render()
        host.send([0x90, 60, 100])
        host.send([0x90, 64, 100])
        host.send([0x90, 62, 100])
        XCTAssertEqual(host.takeNotes(), [.on(60, 100), .off(60), .on(64, 100), .off(64), .on(62, 100)])
        host.send([0x80, 62, 40])
        XCTAssertEqual(host.takeNotes(), [.off(62), .on(64, 40)],
                       "upstream re-strikes the highest held note with the note-off's velocity")
    }

    func testPitchBendReachesTheDSP() throws {
        let host = try makeHost()
        host.send([0xE0, 0x7F, 0x7F])
        XCTAssertEqual(host.unit.getDependentParameter(.pitchbend), 16_383, accuracy: 1)
        host.send([0xE0, 0x00, 0x40])
        XCTAssertEqual(host.unit.getDependentParameter(.pitchbend), 8_192, accuracy: 1)
    }

    /// Hosts send CC123 on transport stop. The keys it releases must be forgotten, or the next
    /// press of the same key finds it still marked down and plays nothing.
    func testAllNotesOffReleasesHostNotesAndForgetsTheirKeys() throws {
        let host = try makeHost()
        host.send([0x90, 60, 100])
        _ = host.takeTrace()
        host.send([0xB0, 123, 0])
        XCTAssertEqual(host.takeNotes(), [.off(60)])
        host.send([0x90, 60, 100])
        XCTAssertEqual(host.takeNotes(), [.on(60, 100)], "a key left marked down swallowed the press")
    }

    /// On-screen and typed keys are queued to the render thread, so the kernel only ever starts
    /// notes on one thread. Nothing reaches it until the host renders.
    func testKeysFromTheInterfacePlayOnTheRenderThread() throws {
        let host = try makeHost()
        let hosted = S1HostedSynth(audioUnit: host.unit)
        hosted.play(noteNumber: 60, velocity: 100)
        XCTAssertEqual(host.takeTrace(), [], "played at once, from the main thread")
        host.render()
        XCTAssertEqual(host.takeTrace(), [HostMIDITraceEntry(op: .keyNoteOn, note: 60, value: 100)])
        hosted.stop(noteNumber: 60)
        host.render()
        XCTAssertEqual(host.takeTrace(), [HostMIDITraceEntry(op: .keyNoteOff, note: 60, value: 0)])
    }

    /// `Manager.stopAllNotes` releases MIDI keys as well as on-screen ones in the standalone,
    /// through `KeyboardView.allNotesOff`. In the plugin the host's keys are the router's.
    func testStoppingAllNotesFromTheInterfaceReleasesHostKeysToo() throws {
        let host = try makeHost()
        host.send([0x90, 60, 100])
        _ = host.takeTrace()
        S1HostedSynth(audioUnit: host.unit).stopAllNotes()
        host.render()
        XCTAssertEqual(host.takeTrace(), [HostMIDITraceEntry(op: .hostNoteOff, note: 60, value: 0),
                                          HostMIDITraceEntry(op: .allNotesOff, note: 0, value: 0)])
    }

    private final class InterfaceSpy: NSObject, S1Protocol {
        var controls: [[UInt8]] = []
        var keys: [S1HostKeys] = []
        func hostMIDIControlDidArrive(_ message: S1HostMIDIMessage) {
            controls.append([message.status, message.data1, message.data2])
        }
        func hostHeldKeysDidChange(_ keys: S1HostKeys) { self.keys.append(keys) }
        func dependentParameterDidChange(_ parameter: DependentParameter) {}
        func arpBeatCounterDidChange(_ counter: S1ArpBeatCounter) {}
        func heldNotesDidChange(_ notes: HeldNotes) {}
        func playingNotesDidChange(_ notes: PlayingNotes) {}
    }

    /// Controls go to the interface; notes do not go as controls; held keys are reported.
    func testControlsAndHeldKeysAreSentToTheInterface() throws {
        let host = try makeHost()
        let spy = InterfaceSpy()
        host.unit.s1Delegate = spy
        host.send([0xB1, 1, 127])
        host.send([0xC1, 5])
        host.send([0x90, 60, 100])
        waitForRenderThreadMessages()
        XCTAssertEqual(spy.controls, [[0xB1, 1, 127], [0xC1, 5, 0]])
        XCTAssertEqual(spy.keys.last?.low, UInt64(1) << 60)

        host.send([0x80, 60, 0])
        waitForRenderThreadMessages()
        XCTAssertEqual(spy.keys.last?.low, 0)
    }

    /// Behaviour, not bookkeeping: the octave setting moves the pitch a host note sounds at.
    func testAShiftedHostNoteSoundsAnOctaveDown() throws {
        let host = try makeHost()
        host.setSettings { $0.octaveShift = -12 }
        _ = host.render(seconds: 1.0)   // ADR-013: parameters sweep into tune after allocation
        host.send([0x90, 69, 127])
        let signal = host.render(seconds: 1.5)
        let window = Array(signal[Int(0.5 * host.sampleRate)..<Int(1.4 * host.sampleRate)])
        XCTAssertEqual(Signal.fundamental(window, sampleRate: host.sampleRate), 220, accuracy: 1.5)
    }
}

// MARK: - Parity with the standalone

/// The same MIDI through `Manager` → `KeyboardView` → `SDSustainer` and through `S1HostMIDI`,
/// compared note call for note call.
///
/// The standalone side is a real `Manager` loaded from the storyboard, with its sustainer wrapping
/// a recorder. Its `AKMIDIListener` methods are called directly, as `S1MIDI` calls them. Hold and
/// mono only ever *toggle*, as their buttons do: upstream's property observers also release every
/// key when set to the value they already hold, which no control does.
final class HostMIDIParityTests: XCTestCase {

    private final class RecordingInstrument: AKPolyphonic {
        private var calls: [HostMIDINote] = []
        func play(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, frequency: Double, channel: MIDIChannel) {
            calls.append(.on(noteNumber, velocity))
        }
        func play(noteNumber: MIDINoteNumber, velocity: MIDIVelocity, channel: MIDIChannel) {
            calls.append(.on(noteNumber, velocity))
        }
        func stop(noteNumber: MIDINoteNumber) {
            calls.append(.off(noteNumber))
        }
        /// Not `take()`. The property holding this is implicitly unwrapped, so Swift type-checks
        /// `instrument.take()` against `Optional` first — and `Optional.take()` exists: it hands
        /// back the value and sets the property to nil. That emptied `instrument` on first use.
        func takeCalls() -> [HostMIDINote] {
            defer { calls.removeAll() }
            return calls
        }
    }

    struct Settings: CustomStringConvertible {
        var octave = 0                 // `typedOctave`; one step is 12 semitones
        var channel: MIDIChannel?      // nil is omni
        var whiteKeysOnly = false
        var hold = false
        var mono = false

        var description: String {
            "octave \(octave), channel \(channel.map(String.init) ?? "omni"), " +
            "white keys \(whiteKeysOnly), hold \(hold), mono \(mono)"
        }
    }

    enum Event: CustomStringConvertible {
        case noteOn(MIDINoteNumber, MIDIVelocity, MIDIChannel)
        case noteOff(MIDINoteNumber, MIDIVelocity, MIDIChannel)
        case pedal(MIDIByte, MIDIChannel)
        case octave(Int)
        case toggleHold
        case toggleMono

        /// As `Tests/Engine/Fixtures/host-midi.txt` spells an event.
        var fixtureLine: String {
            switch self {
            case let .noteOn(note, velocity, channel): return "on \(note) \(velocity) \(channel)"
            case let .noteOff(note, velocity, channel): return "off \(note) \(velocity) \(channel)"
            case let .pedal(value, channel): return "pedal \(value) \(channel)"
            case let .octave(octave): return "octave \(octave)"
            case .toggleHold: return "hold"
            case .toggleMono: return "mono"
            }
        }

        var description: String {
            switch self {
            case let .noteOn(note, velocity, channel): return "noteOn(\(note), \(velocity), ch \(channel))"
            case let .noteOff(note, velocity, channel): return "noteOff(\(note), \(velocity), ch \(channel))"
            case let .pedal(value, channel): return "pedal(\(value), ch \(channel))"
            case let .octave(octave): return "octave(\(octave))"
            case .toggleHold: return "toggleHold"
            case .toggleMono: return "toggleMono"
            }
        }
    }

    private var savedConductor: Conductor?
    private var manager: Manager!
    private var instrument: RecordingInstrument!
    private var drivers: [HostDriver] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedConductor = Conductor.sharedInstance
        Conductor.sharedInstance = Conductor()

        let unit = try SynthOneApp.makePluginAudioUnit(componentDescription: AKSynthOne.ComponentDescription)
        SynthOneApp.startHosted(audioUnit: unit)
        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        manager = try XCTUnwrap(container.content as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        manager.loadViewIfNeeded()
        instrument = RecordingInstrument()
    }

    override func tearDown() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        drivers.removeAll()
        manager = nil
        instrument = nil
        if let savedConductor { Conductor.sharedInstance = savedConductor }
        savedConductor = nil
        super.tearDown()
    }

    /// Both chains in the same state, with nothing held.
    private func begin(_ settings: Settings) throws -> HostDriver {
        manager.keyboardView.holdMode = false
        manager.keyboardView.allNotesOff()
        manager.notesFromMIDI.removeAll()
        manager.soundingMIDINotes.removeAll()
        manager.sustainMode = false
        manager.conductor.sustainer = SDSustainer(instrument)
        manager.typedOctave = settings.octave
        manager.conductor.isOmniMode = settings.channel == nil
        manager.conductor.midiInChannel = settings.channel ?? 0
        // ADR-032: velocity sensitivity is always on in both products. The old setting is left *off*
        // here, so a standalone that still flattened velocity to 127 would fail parity.
        manager.appSettings.velocitySensitive = false
        manager.appSettings.whiteKeysOnly = settings.whiteKeysOnly
        manager.keyboardView.polyphonicMode = !settings.mono
        manager.keyboardView.holdMode = settings.hold
        drainMainQueue()
        _ = instrument.takeCalls()

        let host = try HostDriver()
        drivers.append(host)
        host.unit.setSynthParameter(.isMono, value: settings.mono ? 1 : 0)
        host.setSettings {
            $0.octaveShift = Int32(settings.octave * 12)
            $0.midiChannel = Int32(settings.channel ?? 0)
            $0.omniMode = settings.channel == nil
            $0.whiteKeysOnly = settings.whiteKeysOnly
            $0.holdMode = settings.hold
        }
        host.render()
        _ = host.takeTrace()
        return host
    }

    private func perform(_ event: Event, host: HostDriver,
                         state: inout Settings) -> (standalone: [HostMIDINote], plugin: [HostMIDINote]) {
        switch event {
        case let .noteOn(note, velocity, channel):
            manager.receivedMIDINoteOn(noteNumber: note, velocity: velocity, channel: channel)
            host.send([0x90 | channel, note, velocity])
        case let .noteOff(note, velocity, channel):
            manager.receivedMIDINoteOff(noteNumber: note, velocity: velocity, channel: channel)
            host.send([0x80 | channel, note, velocity])
        case let .pedal(value, channel):
            manager.receivedMIDIController(64, value: value, channel: channel)
            host.send([0xB0 | channel, 64, value])
        case let .octave(octave):
            manager.typedOctave = octave
            host.setSettings { $0.octaveShift = Int32(octave * 12) }
        case .toggleHold:
            state.hold.toggle()
            let hold = state.hold
            manager.keyboardView.holdMode = hold
            host.setSettings { $0.holdMode = hold }
            host.render()
        case .toggleMono:
            state.mono.toggle()
            manager.keyboardView.polyphonicMode = !state.mono
            host.unit.setSynthParameter(.isMono, value: state.mono ? 1 : 0)
            host.render()
        }
        drainMainQueue()
        return (instrument.takeCalls(), host.takeNotes())
    }

    private func assertParity(_ events: [Event], settings: Settings, _ label: String,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let host = try begin(settings)
        var state = settings
        transcript.append("scenario \(label)")
        transcript.append("settings \(settings.octave) \(settings.channel.map { Int($0) } ?? -1) "
                          + "\(settings.whiteKeysOnly ? 1 : 0) \(settings.hold ? 1 : 0) \(settings.mono ? 1 : 0)")
        for (index, event) in events.enumerated() {
            let (standalone, plugin) = perform(event, host: host, state: &state)
            transcript.append("\(event.fixtureLine) => "
                              + HostMIDINote.normalised(standalone).map(\.fixtureWord).joined(separator: " "))
            guard HostMIDINote.normalised(standalone) == HostMIDINote.normalised(plugin) else {
                let recent = events.prefix(index + 1).suffix(12).map { "  \($0)" }.joined(separator: "\n")
                XCTFail("""
                    \(label) [\(settings)]
                    event \(index), \(event): the standalone played \(standalone), the plugin \(plugin)
                    last events:
                    \(recent)
                    """, file: file, line: line)
                return
            }
        }
    }

    /// The scripted scenarios, as data: the parity test and the engine's fixture both run them.
    private func scriptedScenarios() -> [(label: String, settings: Settings, events: [Event])] {
        let chord: [Event] = [.noteOn(60, 90, 0), .noteOn(64, 70, 0), .noteOff(60, 0, 0),
                              .noteOn(60, 0, 0), .noteOff(64, 30, 0)]
        return [
            ("poly", Settings(), chord),
            ("mono", Settings(mono: true), chord),
            ("sustain, including a second non-zero value lifting the pedal", Settings(),
             [.noteOn(60, 100, 0), .pedal(127, 0), .noteOff(60, 0, 0), .noteOn(60, 100, 0),
              .pedal(64, 0), .noteOff(60, 0, 0), .pedal(0, 0)]),
            ("hold", Settings(),
             [.toggleHold, .noteOn(60, 100, 0), .noteOff(60, 0, 0), .noteOn(62, 100, 0),
              .noteOn(60, 100, 0), .toggleHold]),
            ("octave moved while a key is down", Settings(octave: 1),
             [.noteOn(60, 100, 0), .octave(-1), .noteOff(60, 0, 0), .noteOff(61, 0, 0)]),
            ("channel and white keys", Settings(channel: 2, whiteKeysOnly: true),
             [.noteOn(61, 100, 2), .noteOn(61, 100, 5), .noteOff(61, 0, 5), .noteOff(61, 0, 2)]),
            ("mono switched with keys down", Settings(),
             [.noteOn(60, 100, 0), .noteOn(64, 100, 0), .toggleMono, .noteOn(62, 100, 0),
              .toggleMono, .noteOff(62, 0, 0)])
        ]
    }

    /// Seeded random MIDI over a narrow range of notes, so that keys collide, with every setting
    /// in play and changing underneath.
    private func randomScenario(seed: UInt64) -> (label: String, settings: Settings, events: [Event]) {
        var random = SeededRandom(seed: seed)
        var settings = Settings()
        settings.octave = Int.random(in: -2...2, using: &random)
        settings.channel = Bool.random(using: &random) ? nil : 2
        settings.whiteKeysOnly = Bool.random(using: &random)
        settings.mono = Bool.random(using: &random)

        var events: [Event] = []
        for _ in 0..<150 {
            let channel: MIDIChannel = settings.channel == nil ? 0 : [2, 2, 5].randomElement(using: &random)!
            let note = MIDINoteNumber.random(in: 58...66, using: &random)
            switch Int.random(in: 0..<100, using: &random) {
            case 0..<40:  events.append(.noteOn(note, [0, 1, 64, 127].randomElement(using: &random)!, channel))
            case 40..<75: events.append(.noteOff(note, [0, 40, 127].randomElement(using: &random)!, channel))
            case 75..<87: events.append(.pedal([0, 64, 127].randomElement(using: &random)!, channel))
            case 87..<92: events.append(.octave(Int.random(in: -2...2, using: &random)))
            case 92..<96: events.append(.toggleHold)
            default:      events.append(.toggleMono)
            }
        }
        return ("seed \(seed)", settings, events)
    }

    func testScriptedScenariosMatchTheStandalone() throws {
        for scenario in scriptedScenarios() {
            try assertParity(scenario.events, settings: scenario.settings, scenario.label)
        }
    }

    func testRandomMIDIMatchesTheStandalone() throws {
        for seed in UInt64(1)...8 {
            let scenario = randomScenario(seed: seed)
            try assertParity(scenario.events, settings: scenario.settings, scenario.label)
        }
    }

    // MARK: The engine's fixture (X2-4, ADR-075)

    /// What `assertParity` saw the STANDALONE play, event by event. `Tests/Engine/HostMIDITests.cpp`
    /// replays the same MIDI through `S1HostMIDI` on macOS, Linux and Windows and requires these
    /// notes — the parity proved here, carried to the machines Swift does not run on.
    private var transcript: [String] = []

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Engine/Fixtures/host-midi.txt")
    }

    /// check (the normal suite): fails when the committed fixture is not what this build plays.
    /// write: `Scripts/write-host-midi-fixtures.sh` (SYNTHONE_WRITE_HOST_MIDI_FIXTURES=1).
    func testTheEngineFixtureIsWhatTheStandalonePlays() throws {
        transcript = ["# GENERATED by HostMIDIParityTests (Scripts/write-host-midi-fixtures.sh). Do not edit.",
                      "# What the STANDALONE's Swift MIDI chain plays, event by event (ADR-031, ADR-075).",
                      "# settings: octave channel(-1 = omni) whiteKeysOnly hold mono",
                      "# events:   on note velocity channel | off note velocity channel | pedal value channel | octave n | hold | mono",
                      "# notes:    +note:velocity  -note   (a run of stops is sorted: HostMIDINote.normalised)"]
        for scenario in scriptedScenarios() + (UInt64(1)...8).map(randomScenario(seed:)) {
            try assertParity(scenario.events, settings: scenario.settings, scenario.label)
        }
        _ = try begin(Settings())
        transcript.append("whitekeys " + (0..<128).map { String(manager.whiteKeysOnlyMap[$0]) }.joined(separator: " "))
        let fixture = transcript.joined(separator: "\n") + "\n"

        if ProcessInfo.processInfo.environment["SYNTHONE_WRITE_HOST_MIDI_FIXTURES"] == "1" {
            try fixture.write(to: fixtureURL, atomically: true, encoding: .utf8)
            print("SYNTHONE_WRITE_HOST_MIDI_FIXTURES: wrote \(fixtureURL.path)")
            return
        }
        let onDisk = try String(contentsOf: fixtureURL, encoding: .utf8)
        XCTAssertEqual(onDisk, fixture, "Tests/Engine/Fixtures/host-midi.txt is stale: run Scripts/write-host-midi-fixtures.sh")
    }

    /// **The standalone always plays the velocity it receives too** (ADR-032), whatever the old
    /// "Velocity Sensitive" setting says.
    func testTheStandaloneAlwaysPlaysTheVelocityItReceives() throws {
        _ = try begin(Settings())
        manager.appSettings.velocitySensitive = false
        manager.receivedMIDINoteOn(noteNumber: 60, velocity: 30, channel: 0)
        drainMainQueue()
        XCTAssertEqual(instrument.takeCalls(), [.on(60, 30)])
    }

    /// `S1HostMIDI` keeps its own copy of `Manager.whiteKeysOnlyMap`. All 128 entries.
    func testTheWhiteKeysMapIsTheStandalones() throws {
        let host = try HostDriver()
        drivers.append(host)
        host.setSettings { $0.whiteKeysOnly = true }
        for note in 0..<128 {
            host.send([0x90, UInt8(note), 100])
            host.send([0x80, UInt8(note), 0])
            XCTAssertEqual(host.takeNotes().first, .on(manager.whiteKeysOnlyMap[note], 100), "note \(note)")
        }
    }
}

// MARK: - The plugin's interface

final class HostMIDIInterfaceTests: XCTestCase {

    private var savedConductor: Conductor?
    private var savedSupportURL: URL?
    private var savedSettingsURL: URL?

    override func setUp() {
        super.setUp()
        savedConductor = Conductor.sharedInstance
        Conductor.sharedInstance = Conductor()
        // Several settings methods save to disk, and not to the owner's settings. Since
        // ADR-041 settings have their own folder, so both are redirected.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("HostMIDIInterfaceTests-\(UUID().uuidString)")
        savedSupportURL = Disk.sharedSupportURL
        savedSettingsURL = Disk.settingsURL
        Disk.sharedSupportURL = scratch
        Disk.settingsURL = scratch
    }

    override func tearDown() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        if let savedSupportURL { Disk.sharedSupportURL = savedSupportURL }
        if let savedSettingsURL { Disk.settingsURL = savedSettingsURL }
        if let savedConductor { Conductor.sharedInstance = savedConductor }
        savedConductor = nil
        super.tearDown()
    }

    private func loadPluginInterface() throws -> (Manager, S1AudioUnit) {
        let unit = try SynthOneApp.makePluginAudioUnit(componentDescription: AKSynthOne.ComponentDescription)
        SynthOneApp.startHosted(audioUnit: unit)
        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        manager.loadViewIfNeeded()
        return (manager, unit)
    }

    /// **The owner's measurement.** Registering with CoreMIDI is what opened every input on the
    /// system; the plugin's interface must not.
    func testThePluginOpensNoMIDIInputsOfItsOwn() throws {
        let (manager, _) = try loadPluginInterface()
        XCTAssertFalse(S1MIDI.shared.isListening(manager),
                       "the plugin hears hardware directly, around its host's routing")
    }

    /// And the standalone still does: hardware is its only MIDI.
    func testTheStandaloneStillOpensItsMIDIInputs() throws {
        Conductor.sharedInstance.start(mode: .offline)
        defer { Conductor.sharedInstance.engine.stop() }
        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        manager.loadViewIfNeeded()
        XCTAssertTrue(S1MIDI.shared.isListening(manager))
    }

    /// Every place a MIDI setting changes pushes it to the render thread, each exercised through
    /// the method the interface itself calls. A missing `syncHostMIDISettings()` fails here, and
    /// not as a control that silently does nothing inside a host.
    func testEverySettingReachesTheRenderThread() throws {
        let (manager, unit) = try loadPluginInterface()

        manager.typedOctave = -1   // what both the stepper and Z/X run
        XCTAssertEqual(unit.hostMIDISettings.octaveShift, -12, "Octave")

        manager.holdButton.setValueCallback(1)
        XCTAssertTrue(unit.hostMIDISettings.holdMode, "Hold on")
        manager.holdButton.setValueCallback(0)
        XCTAssertFalse(unit.hostMIDISettings.holdMode, "Hold off")

        manager.didSelectMIDIChannel(newChannel: 3)
        XCTAssertFalse(unit.hostMIDISettings.omniMode, "MIDI channel")
        XCTAssertEqual(unit.hostMIDISettings.midiChannel, 3, "MIDI channel")
        manager.didSelectMIDIChannel(newChannel: -1)
        XCTAssertTrue(unit.hostMIDISettings.omniMode, "omni")

        manager.whiteKeysOnlyChanged(true)
        XCTAssertTrue(unit.hostMIDISettings.whiteKeysOnly, "white keys only")

        manager.appSettings.omniMode = false
        manager.appSettings.midiChannel = 7
        manager.setDefaultsFromAppSettings()
        XCTAssertEqual(unit.hostMIDISettings.midiChannel, 7, "settings loaded from disk")
        XCTAssertFalse(unit.hostMIDISettings.omniMode, "settings loaded from disk")
    }

    /// The interface's velocity-sensitivity setting never reaches host notes, whatever it says
    /// (ADR-032).
    func testTheInterfacesVelocitySettingDoesNotReachHostNotes() throws {
        let (manager, unit) = try loadPluginInterface()
        manager.appSettings.velocitySensitive = false
        manager.syncHostMIDISettings()
        let host = try HostDriver(unit: unit)
        host.send([0x90, 60, 30])
        XCTAssertEqual(host.takeNotes(), [.on(60, 30)])
    }

    /// The plugin's MIDI settings show velocity sensitivity On, and it cannot be switched off —
    /// set up through `Manager`'s own `SegueToMIDI` preparation, as presenting the popover would.
    func testThePluginsVelocityToggleIsLockedOn() throws {
        let (manager, _) = try loadPluginInterface()
        manager.appSettings.velocitySensitive = false
        let popover = try openMIDISettings(from: manager)
        XCTAssertEqual(popover.velocityToggle.value, 1, "shown Off in a plugin that always plays velocity")
        XCTAssertFalse(popover.velocityToggle.isUserInteractionEnabled, "a switch that does nothing")
    }

    /// And the standalone's is locked on too — the owner extended ADR-032 to both products.
    func testTheStandalonesVelocityToggleIsLockedOnToo() throws {
        Conductor.sharedInstance.start(mode: .offline)
        defer { Conductor.sharedInstance.engine.stop() }
        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        manager.loadViewIfNeeded()
        manager.appSettings.velocitySensitive = false
        let popover = try openMIDISettings(from: manager)
        XCTAssertEqual(popover.velocityToggle.value, 1, "shown Off while velocity is always played")
        XCTAssertFalse(popover.velocityToggle.isUserInteractionEnabled, "a switch that does nothing")
    }

    private func openMIDISettings(from manager: Manager) throws -> MIDISettingsViewController {
        let popover = try XCTUnwrap(UIStoryboard(name: "Main", bundle: .synthOneCore)
            .instantiateViewController(withIdentifier: "MIDISettingsViewController") as? MIDISettingsViewController)
        manager.prepare(for: UIStoryboardSegue(identifier: "SegueToMIDI", source: manager, destination: popover),
                        sender: nil)
        popover.loadViewIfNeeded()
        return popover
    }

    /// A host's CC1 moves the mod wheel. Before ADR-031 only the plugin's own CoreMIDI copy did,
    /// and the kernel ignored the host's.
    func testAHostModWheelMovesTheWheel() throws {
        let (manager, unit) = try loadPluginInterface()
        let host = try HostDriver(unit: unit)
        manager.modWheelPad.setVerticalValue01(0)
        host.send([0xB0, 1, 127])
        // ADR-063: the wheel writes the cutoff through the parameter tree, which reaches the DSP
        // at the next render. Until then the kernel held the preset's 20 kHz, and whatever asked
        // it where the cutoff was — the XY pads settling into place — put the wheel back at
        // 20 kHz's position, 0.03, and the Cutoff knob with it. Reads see the interface's own
        // writes now; and the wait renders, because a host never stops.
        waitWhileRendering(host, seconds: 0.6)
        XCTAssertEqual(manager.modWheelPad.verticalValue, 1, accuracy: 0.001)
        XCTAssertEqual(Conductor.sharedInstance.synth.getSynthParameter(.cutoff), 360, accuracy: 0.5,
                       "the wheel at the top is 3 × 120 Hz under the cutoff routing")
        let cutoffKnob = try XCTUnwrap(manager.generatorsPanel.cutoff)
        XCTAssertEqual(cutoffKnob.value, 360, accuracy: 0.5, "and the Cutoff knob follows the wheel")
    }

    /// The main run loop turns while the audio clock keeps running, a block at a time.
    private func waitWhileRendering(_ host: HostDriver, seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            host.render()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    /// In the standalone the pedal holds on-screen keys too, through `Manager`'s sustainer.
    func testAHostSustainPedalAlsoHoldsOnScreenKeys() throws {
        let (manager, unit) = try loadPluginInterface()
        let host = try HostDriver(unit: unit)
        host.send([0xB0, 64, 127])
        waitForRenderThreadMessages()
        XCTAssertTrue(manager.conductor.sustainer.pedalIsDown)
    }

    func testHostNotesLightTheKeys() throws {
        let (manager, unit) = try loadPluginInterface()
        let host = try HostDriver(unit: unit)
        host.send([0x90, 60, 100])
        waitForRenderThreadMessages()
        XCTAssertEqual(manager.keyboardView.hostOnKeys, [60])
        host.send([0x80, 60, 0])
        waitForRenderThreadMessages()
        XCTAssertEqual(manager.keyboardView.hostOnKeys, [])
    }
}
