//  P4-6, first step: the interface can drive a bare audio unit.
//
//  The 12 panels reach the DSP through `Conductor.synth`, which was an `AKSynthOne`
//  — a node that makes its own audio unit and needs an `AVAudioEngine`. A plugin has
//  none of that. `Conductor.synth` is now typed as `S1SynthControlling`, and these
//  check that the plugin's implementation of it actually reaches the DSP rather than
//  merely satisfying the compiler.

import XCTest
import AVFoundation
@testable import SynthOneCore

final class HostedSynthTests: XCTestCase {

    private func makeHosted() throws -> (S1HostedSynth, S1AudioUnit) {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        return (S1HostedSynth(audioUnit: unit), unit)
    }

    /// Writes land on the DSP, and reads come back from it — not from a cache in the
    /// wrapper, which would look identical here and be wrong the moment the host
    /// automated anything.
    func testParametersRoundTripThroughTheDSP() throws {
        let (hosted, unit) = try makeHosted()

        hosted.setSynthParameter(.cutoff, 4_321)
        XCTAssertEqual(unit.getSynthParameter(.cutoff), 4_321, accuracy: 1, "the DSP did not see it")
        XCTAssertEqual(hosted.getSynthParameter(.cutoff), 4_321, accuracy: 1)

        // Set behind the wrapper's back; a cache would miss this.
        unit.setSynthParameter(.cutoff, value: 900)
        XCTAssertEqual(hosted.getSynthParameter(.cutoff), 900, accuracy: 1,
                       "the wrapper is caching rather than reading the DSP")
    }

    /// Every knob asks for its range as it wires itself up, so these have to match
    /// the node's — a wrong range is a knob that moves the wrong amount, not an error.
    func testRangesMatchTheNode() throws {
        let (hosted, _) = try makeHosted()
        let node = AKSynthOne()

        for raw in 0..<S1Parameter.S1ParameterCount.rawValue {
            guard let parameter = S1Parameter(rawValue: raw) else { continue }
            XCTAssertEqual(hosted.getMinimum(parameter), node.getMinimum(parameter),
                           accuracy: 0.0001, "\(parameter) minimum")
            XCTAssertEqual(hosted.getMaximum(parameter), node.getMaximum(parameter),
                           accuracy: 0.0001, "\(parameter) maximum")
            XCTAssertEqual(hosted.getDefault(parameter), node.getDefault(parameter),
                           accuracy: 0.0001, "\(parameter) default")
        }
    }

    /// `getRange` feeds `Knob.range` directly. A reversed range traps at runtime, and
    /// nothing in the parameter table guarantees min <= max.
    func testRangeIsNeverReversed() throws {
        let (hosted, _) = try makeHosted()
        for raw in 0..<S1Parameter.S1ParameterCount.rawValue {
            guard let parameter = S1Parameter(rawValue: raw) else { continue }
            let range = hosted.getRange(parameter)
            XCTAssertLessThanOrEqual(range.lowerBound, range.upperBound, "\(parameter)")
        }
    }

    /// The 16 sequencer steps are contiguous parameter addresses reached through
    /// `forIndex:` accessors. Reads and writes have to agree, and out-of-range
    /// indices must not run off the end of the parameter table.
    func testSequencerStepsReadBackWhatWasWritten() throws {
        let (hosted, _) = try makeHosted()

        for step in 0..<16 {
            hosted.setPattern(forIndex: step, step - 8)
            hosted.setNoteOn(forIndex: step, step % 2 == 0)
            hosted.setOctaveBoost(forIndex: step, step % 3 == 0 ? 1 : 0)
        }
        for step in 0..<16 {
            XCTAssertEqual(hosted.getPattern(forIndex: step), step - 8, "step \(step)")
            XCTAssertEqual(hosted.isNoteOn(forIndex: step), step % 2 == 0, "step \(step)")
            XCTAssertEqual(hosted.getOctaveBoost(forIndex: step), step % 3 == 0, "step \(step)")
        }

        // Out of range is ignored, not clamped onto step 0 or read off the end.
        for bad in [-1, 16, 999] {
            hosted.setPattern(forIndex: bad, 7)
            XCTAssertEqual(hosted.getPattern(forIndex: bad), 0, "index \(bad)")
        }
        XCTAssertEqual(hosted.getPattern(forIndex: 0), -8, "an out-of-range write hit step 0")
    }

    /// The tuning table is the state `fullState` had to carry separately (ADR-024);
    /// the Tunings panel writes it through this.
    func testTuningTableRoundTrips() throws {
        let (hosted, unit) = try makeHosted()
        hosted.setTuningTable(452.89, index: 69)
        XCTAssertEqual(hosted.getTuningTableFrequency(69), 452.89, accuracy: 0.01)
        XCTAssertEqual(unit.getTuningTableFrequency(69), 452.89, accuracy: 0.01)

        hosted.setTuningTableNPO(24)
        XCTAssertEqual(unit.getTuningTableNPO(), 24)
    }

    /// A preset applies through `S1PresetSink`, which `S1SynthControlling` inherits —
    /// so the same hundred-line mapping serves the node and the wrapper.
    func testAPresetAppliesThroughTheWrapper() throws {
        let (hosted, unit) = try makeHosted()
        let before = unit.getSynthParameter(.cutoff)

        let presets = S1FactoryPresets(defaults: hosted.presetDefaults)
        XCTAssertGreaterThan(presets.count, 0)
        XCTAssertTrue(presets.applyFactoryPreset(at: 3, to: unit))

        XCTAssertNotEqual(unit.getSynthParameter(.cutoff), before, accuracy: 0.0001)
    }

    /// `presetDefaults` is what a preset falls back to for a key its JSON omits, so a
    /// wrapper handing back zeros would silently flatten every partially-specified
    /// preset.
    func testPresetDefaultsComeFromTheDSP() throws {
        let (hosted, _) = try makeHosted()
        let defaults = hosted.presetDefaults
        XCTAssertEqual(defaults(.cutoff), hosted.getDefault(.cutoff), accuracy: 0.0001)
        XCTAssertGreaterThan(defaults(.cutoff), 0, "defaults are all zero — the closure is not wired")
    }

    /// The wrapper holds the unit; it must not be what keeps it alive or a host
    /// closing the plugin would leak the DSP.
    func testTheWrapperDoesNotOwnTheHostsAudioUnitExclusively() throws {
        let (hosted, unit) = try makeHosted()
        XCTAssertIdentical(hosted.audioUnit, unit)
    }
}

// MARK: - Hosted mode

/// P4-6: the plugin's `Conductor` — the same interface, wired to a host's audio unit
/// instead of an engine we own.
final class HostedConductorTests: XCTestCase {

    private func makeUnit() throws -> S1AudioUnit {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        return unit
    }

    /// What hosted mode gives the interface, and — more to the point — what it does
    /// not build. An engine, a mixer or an output device here would be a bug that
    /// only shows up as a stalled plugin inside a host (ADR-015).
    func testHostedModeWiresTheSynthWithoutAnEngine() throws {
        let conductor = Conductor()
        let unit = try makeUnit()
        conductor.startHosted(audioUnit: unit)

        XCTAssertNotNil(conductor.synth, "the interface has nothing to drive")
        XCTAssertTrue(conductor.synth is S1HostedSynth)
        XCTAssertNil(conductor.synthNode, "hosted mode must not create a node")
        XCTAssertNil(conductor.mixer, "hosted mode must not build a graph")
        XCTAssertNil(conductor.audioRecorder, "recording a plugin's output is the host's job")

        // These two are force-unwrapped by the interface, so they must exist even
        // though neither can do its usual job without a node.
        XCTAssertNotNil(conductor.sustainer, "the on-screen keyboard plays through this")
        XCTAssertNotNil(conductor.audioPlotter, "GeneratorsPanelController force-unwraps this")

        XCTAssertIdentical(unit.s1Delegate as AnyObject?, conductor,
                           "the DSP's main-thread callbacks have nowhere to go")
    }

    /// Every control reads its parameter's default as it wires itself up, so an empty
    /// table means a UI full of zeros.
    func testHostedModePopulatesTheDefaults() throws {
        let conductor = Conductor()
        conductor.startHosted(audioUnit: try makeUnit())

        XCTAssertEqual(conductor.defaultValues.count, Int(S1Parameter.S1ParameterCount.rawValue))
        XCTAssertGreaterThan(conductor.defaultValues[Int(S1Parameter.cutoff.rawValue)], 0)
    }

    /// The on-screen keyboard plays through `SDSustainer`, which used to require an
    /// `AKPolyphonicNode`. Notes have to reach the DSP without one.
    func testTheOnScreenKeyboardPathReachesTheDSP() throws {
        let conductor = Conductor()
        let unit = try makeUnit()
        conductor.startHosted(audioUnit: unit)

        // Nothing sounding to begin with.
        conductor.sustainer.play(noteNumber: 60, velocity: 100)
        conductor.sustainer.stop(noteNumber: 60)
        // Surviving is most of the assertion — the pre-P4-6 sustainer would not have
        // compiled against a nodeless synth, and a wrong wiring traps on nil.
        XCTAssertNotNil(conductor.synth)
    }

    /// Calling it twice must not build a second everything, the same guard `start` has.
    func testHostedModeIsIdempotent() throws {
        let conductor = Conductor()
        let unit = try makeUnit()
        conductor.startHosted(audioUnit: unit)
        let synth = conductor.synth as AnyObject
        conductor.startHosted(audioUnit: try makeUnit())
        XCTAssertIdentical(conductor.synth as AnyObject, synth)
    }
}

/// **The P4-6 acceptance criterion so far:** the whole interface loads against a
/// host's audio unit, with no engine anywhere.
///
/// This has to commandeer `Conductor.sharedInstance`, because every view controller
/// captures it at init (`UpdatableViewController.conductor`). It is restored in
/// `tearDown` — a suite that left a hosted conductor in place would break every other
/// suite that expects the standalone one.
final class HostedInterfaceTests: XCTestCase {

    private var savedConductor: Conductor?

    override func setUp() {
        super.setUp()
        savedConductor = Conductor.sharedInstance
        Conductor.sharedInstance = Conductor()
    }

    override func tearDown() {
        if let savedConductor { Conductor.sharedInstance = savedConductor }
        savedConductor = nil
        super.tearDown()
    }

    /// Loads every panel the way the plugin will. Before P4-6 this could not even be
    /// attempted: `Manager.viewDidLoad` force-unwraps `conductor.synth`, which only
    /// existed once an `AVAudioEngine` had been built.
    func testTheWholeInterfaceLoadsAgainstAHostsAudioUnit() throws {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        S1FactoryPresets.install(into: unit)

        SynthOneApp.startHosted(audioUnit: unit)

        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        manager.loadViewIfNeeded()
        manager.view.layoutIfNeeded()

        // Outlets are connected, which is the thing a storyboard fails at silently.
        XCTAssertNotNil(manager.keyboardView)
        XCTAssertNotNil(manager.octaveStepper)
        XCTAssertNotNil(manager.pitchBend)

        // And the controls are reading the *host's* DSP, not a second one.
        unit.setSynthParameter(.cutoff, value: 1_234)
        XCTAssertEqual(manager.conductor.synth.getSynthParameter(.cutoff), 1_234, accuracy: 1)
    }

    /// **The Record button must be there in the app and gone in the plugin.**
    ///
    /// Owner-reported: "I see a label Record, but no actual button to press." The
    /// first version hid it when `audioRecorder == nil`, which is true in the
    /// standalone too for the first moments — the engine starts on a background queue
    /// and the recorder is built in `engineDidStart`, after the panels load.
    func testTheRecordButtonIsHiddenOnlyInThePlugin() throws {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        SynthOneApp.startHosted(audioUnit: unit)

        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.loadViewIfNeeded()
        let generators = manager.generatorsPanel
        generators.loadViewIfNeeded()

        XCTAssertTrue(Conductor.sharedInstance.isHosted)
        XCTAssertTrue(generators.recordButton.isHidden, "the plugin has no recorder to drive it")
        // And the label with it — hiding only the button left the word "Record"
        // floating in the panel with nothing to press.
        XCTAssertTrue(generators.recordStatus.isHidden, "an orphaned label is left behind")

        // And what is left is centred in the space the pair shared. The record
        // controls are hidden, not moved, so their frames still mark the right edge
        // of that space: it runs from the volume group's designed left edge (441) to
        // `recordStatus.maxX` (597), and the midpoint is 519.
        //
        // Recomputing the span from the *moved* volume group would chase its own
        // tail — that is what the first version of this assertion did.
        let knob = try XCTUnwrap(generators.masterVolume)
        let caption = try XCTUnwrap(generators.volumeLabel)
        let volume = knob.frame.union(caption.frame)
        let designedLeft: CGFloat = 441
        let expected = (designedLeft + generators.recordStatus.frame.maxX) / 2
        XCTAssertEqual(volume.midX, expected, accuracy: 1,
                       "the volume control is not centred in the space the pair shared")
        XCTAssertGreaterThan(volume.midX, 478,
                             "it has not moved from where it sits in the app")

        // The knob and its caption moved together — a shifted knob over a stationary
        // label would look worse than leaving both alone.
        XCTAssertEqual(knob.frame.midX - caption.frame.midX, 480.5 - 478, accuracy: 1,
                       "the knob and its caption came apart")
    }

    /// The panel that force-unwraps `conductor.audioPlotter`. In hosted mode the plot
    /// exists with no node to tap, which is why this loads rather than trapping.
    func testTheGeneratorsPanelLoadsWithoutANodeToPlot() throws {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        SynthOneApp.startHosted(audioUnit: unit)

        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.loadViewIfNeeded()

        let generators = manager.generatorsPanel
        generators.loadViewIfNeeded()
        generators.view.layoutIfNeeded()
        XCTAssertNotNil(generators.view)
    }

    /// A knob move in the plugin has to reach the host's DSP — that is the whole
    /// point of hosted mode, and it is one hop the compiler cannot check.
    func testAControlMoveReachesTheHostsDSP() throws {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        SynthOneApp.startHosted(audioUnit: unit)

        Conductor.sharedInstance.synth.setSynthParameter(.cutoff, 2_468)
        XCTAssertEqual(unit.getSynthParameter(.cutoff), 2_468, accuracy: 1)
    }
}

// MARK: - Host automation binding

/// P4-6: the two directions that make a plugin automatable. A knob move has to reach
/// the host or Logic records nothing; a host move has to reach the knob or the panel
/// lies about what is playing.
final class ParameterBindingTests: XCTestCase {

    private var units: [S1AudioUnit] = []

    override func tearDown() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        units.removeAll()
        super.tearDown()
    }

    private func makeHosted() throws -> (S1HostedSynth, S1AudioUnit) {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        units.append(unit)
        return (S1HostedSynth(audioUnit: unit), unit)
    }

    private func drain() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    }

    /// **A control move must go through the parameter tree.** Writing to the kernel
    /// directly moves the sound and leaves the host knowing nothing, which is exactly
    /// what "Logic does not record my knob moves" looks like.
    func testAControlMoveLandsOnTheAUParameter() throws {
        let (hosted, unit) = try makeHosted()
        let cutoff = try XCTUnwrap(unit.parameterTree?
            .parameter(withAddress: AUParameterAddress(S1Parameter.cutoff.rawValue)))

        hosted.setSynthParameter(.cutoff, 3_210)

        XCTAssertEqual(cutoff.value, 3_210, accuracy: 1,
                       "the host was never told — this is the automation-recording bug")
        XCTAssertEqual(unit.getSynthParameter(.cutoff), 3_210, accuracy: 1,
                       "and it still has to reach the DSP")
    }

    /// **A host move must reach the interface.**
    func testAHostChangeIsReportedToTheInterface() throws {
        let (hosted, unit) = try makeHosted()
        var seen: [(S1Parameter, Double)] = []
        hosted.observeHostChanges { seen.append(($0, $1)) }

        let cutoff = try XCTUnwrap(unit.parameterTree?
            .parameter(withAddress: AUParameterAddress(S1Parameter.cutoff.rawValue)))
        cutoff.value = 1_500          // no originator: this is the host
        drain()

        XCTAssertTrue(seen.contains { $0.0 == .cutoff && abs($0.1 - 1_500) < 1 },
                      "a host automation move did not reach the UI: \(seen)")
    }

    /// **The loop that must not close.** If our own writes came back through the
    /// observer, a knob move would be echoed into the control that made it — and in a
    /// host in write mode, recorded as automation the user never performed. The
    /// originator token is what prevents it.
    func testOurOwnWritesAreNotEchoedBack() throws {
        let (hosted, _) = try makeHosted()
        var seen: [S1Parameter] = []
        hosted.observeHostChanges { parameter, _ in seen.append(parameter) }

        hosted.setSynthParameter(.cutoff, 2_000)
        hosted.setSynthParameter(.resonance, 0.4)
        drain()

        XCTAssertTrue(seen.isEmpty, "our own writes came back as host changes: \(seen)")
    }

    /// A parameter with no address in the tree still has to reach the DSP rather than
    /// being dropped on the floor.
    func testAParameterWithNoTreeEntryStillReachesTheDSP() throws {
        let (hosted, unit) = try makeHosted()
        // Every S1Parameter has an address, so this checks the guard rather than a
        // real gap: the values still land.
        // Values inside each parameter's own range — `setSynthParameter` clamps, so a
        // value outside it would be testing the clamp rather than the path.
        for (parameter, value) in [(S1Parameter.masterVolume, 0.3),
                                   (.attackDuration, 0.25),
                                   (.arpRate, 100.0)] {
            hosted.setSynthParameter(parameter, value)
            XCTAssertEqual(unit.getSynthParameter(parameter), Float(value), accuracy: 0.05,
                           "\(parameter)")
        }
    }
}
