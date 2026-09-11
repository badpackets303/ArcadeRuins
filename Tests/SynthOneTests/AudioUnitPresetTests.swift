//  P4-4 acceptance, second half: the host's preset menu.
//
//  A host offers one flat list of `AUAudioUnitPreset` and picks by *number*. That
//  number goes into the session file, so the tests here care as much about the
//  numbering being stable as about the presets working.

import XCTest
import AVFoundation
import AudioToolbox
@testable import SynthOneCore

final class AudioUnitPresetTests: XCTestCase {

    /// Units are held for the lifetime of the test case, not released as they go
    /// out of scope, and `tearDown` drains the main queue before letting them go.
    ///
    /// **This is working around a real bug, not tidiness.** Applying a preset sets
    /// the eight dependent parameters, each of which posts a message to TAAE's
    /// main-thread endpoint — and that message carries the audio unit as a **raw
    /// pointer** (`id target = message->target` in `AEMessageQueue.m`), because
    /// retaining on the render thread is not real-time safe. If the unit dies before
    /// the main queue drains, the handler retains freed memory and segfaults. It is
    /// upstream's design and it never mattered there, where one synth lived for the
    /// life of the app. See STATE.md's Known issues.
    private var units: [S1AudioUnit] = []

    override func tearDown() {
        drainMainThreadMessages()
        units.removeAll()
        super.tearDown()
    }

    /// Let queued `dependentParameterDidChange` messages be delivered while their
    /// audio unit is still alive. TAAE hands off through its own thread and then the
    /// main queue, so this needs real runloop turns rather than one.
    private func drainMainThreadMessages() {
        for _ in 0..<4 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func makeUnit(withPresets: Bool = true) throws -> S1AudioUnit {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        if withPresets { S1FactoryPresets.install(into: unit) }
        units.append(unit)
        return unit
    }

    /// Every shipped preset in every shipped bank reaches the host menu. 695 is a
    /// lot for one list and that is a deliberate choice — see `S1FactoryPresets`.
    func testEveryShippedPresetIsOffered() throws {
        let unit = try makeUnit()
        let presets = try XCTUnwrap(unit.factoryPresets)
        XCTAssertEqual(presets.count, 695)
        XCTAssertEqual(Set(presets.map(\.number)).count, presets.count, "numbers must be unique")
        XCTAssertEqual(presets.map(\.number), Array(0..<presets.count), "0..<n, in order")
        XCTAssertFalse(presets.contains { $0.name.isEmpty })
    }

    /// **The numbering is a compatibility surface.** A host writes the *number*
    /// into its session file, so bank order cannot change once anything has been
    /// saved: reordering silently repoints every saved session at a different
    /// sound, with no error and no migration.
    func testPresetNumberingIsStable() throws {
        let presets = try XCTUnwrap(try makeUnit().factoryPresets)
        XCTAssertEqual(presets.first?.name.hasPrefix("BankA: "), true)
        XCTAssertEqual(presets.last?.name.hasPrefix("User: "), true)
        // Names are `Bank: Preset`, so a host's alphabetical list groups by bank.
        XCTAssertTrue(presets.allSatisfy { $0.name.contains(": ") })
    }

    /// Choosing a preset has to change the DSP, not just the label.
    func testSelectingAFactoryPresetChangesTheSound() throws {
        let unit = try makeUnit()
        let presets = try XCTUnwrap(unit.factoryPresets)

        // Two presets far apart in the list; if they happened to be identical the
        // assertion below would be vacuous, so the fingerprint is over 150 values.
        func fingerprint() -> [Float] {
            (0..<150).compactMap { S1Parameter(rawValue: Int32($0)) }.map { unit.getSynthParameter($0) }
        }

        unit.currentPreset = presets[0]
        let first = fingerprint()
        XCTAssertEqual(unit.currentPreset?.number, 0)

        unit.currentPreset = presets[400]
        let other = fingerprint()
        XCTAssertEqual(unit.currentPreset?.number, 400)

        XCTAssertNotEqual(first, other, "selecting a different preset changed nothing")
    }

    /// A number from a session saved by a build with a different bank list must be
    /// refused, not applied to whatever now sits at that index.
    func testAnOutOfRangePresetNumberIsRefused() throws {
        let unit = try makeUnit()
        let presets = try XCTUnwrap(unit.factoryPresets)
        unit.currentPreset = presets[10]
        let expected = unit.getSynthParameter(.cutoff)

        let bogus = AUAudioUnitPreset()
        bogus.number = 99_999
        bogus.name = "from the future"
        unit.currentPreset = bogus

        XCTAssertEqual(unit.currentPreset?.number, 10, "the refused preset became current")
        XCTAssertEqual(unit.getSynthParameter(.cutoff), expected, accuracy: 0.001)
    }

    /// The preset source is installed, not built in — `S1AudioUnit` is Obj-C++ and
    /// cannot reach the Swift codec. A unit without one reports no factory presets,
    /// which is legitimate for an AU and therefore silent, so the *plugin's* factory
    /// installing one is pinned separately below.
    func testAUnitWithoutASourceHasNoFactoryPresets() throws {
        XCTAssertNil(try makeUnit(withPresets: false).factoryPresets)
    }

    /// The path a host actually takes.
    ///
    /// Until ADR-031 the setup lived in the extension's `createAudioUnit`, which the test bundle
    /// cannot link, so this could only read that file's source. It lives in
    /// `SynthOneApp.makePluginAudioUnit` now, and the extension calls it — so the unit built here
    /// is the unit a host gets, and it is exercised rather than grepped. What this catches is a
    /// setup step dropped: a plugin that loads and shows an empty preset menu, or loads and plays
    /// silence, or ignores its host's octave and pedal — with no error anywhere.
    func testThePluginFactoryInstallsWavetablesAndPresets() throws {
        // The one thing still only checkable at the source: that the extension uses this factory.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SynthOneAU/SynthOneAudioUnitViewController.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertTrue(text.contains("SynthOneApp.makePluginAudioUnit(componentDescription: componentDescription)"),
                      "the extension builds its audio unit some other way")

        let host = try HostDriver()
        units.append(host.unit)
        XCTAssertEqual(host.unit.factoryPresets?.count, 695, "the factory no longer installs the factory presets")
        XCTAssertTrue(host.unit.routesHostMIDI, "the factory no longer routes host MIDI (ADR-031)")

        // Wavetables: without them the oscillators have no tables and a note is silence.
        _ = host.render(seconds: 1.0)   // ADR-013
        host.send([0x90, 69, 127])
        XCTAssertGreaterThan(Signal.peak(host.render(seconds: 0.5)), 0.05,
                             "the factory no longer loads the wavetables")
    }

    /// User presets are the framework's, built on our `fullState`. Saying we support
    /// them is what gives a host any way to keep a sound outside the session.
    func testUserPresetsAreSupported() throws {
        XCTAssertTrue(try makeUnit().supportsUserPresets)
    }

    /// A preset that carries a sequencer pattern has to restore it. The 16 steps are
    /// contiguous parameter addresses reached through `setPattern(forIndex:)`, and
    /// `S1AudioUnit`'s conformance computes them without a node — a different code
    /// path from the standalone's.
    func testPresetsReachTheSequencerThroughTheNodelessPath() throws {
        let unit = try makeUnit()
        let presets = try XCTUnwrap(unit.factoryPresets)

        // Scan for a preset whose pattern is not all-zero, rather than assuming one.
        let patternParameters = (0..<16).compactMap {
            S1Parameter(rawValue: S1Parameter.sequencerPattern00.rawValue + Int32($0))
        }
        var found = false
        for preset in presets.prefix(24) {
            unit.currentPreset = preset
            if patternParameters.contains(where: { unit.getSynthParameter($0) != 0 }) {
                found = true
                break
            }
        }
        XCTAssertTrue(found, "no preset in the first 24 set a sequencer step — "
                      + "either the banks changed or the nodeless path is not writing them")
    }
}
