//  ADR-030: the plugin's mod wheel would not stay where it was dragged.
//
//  Owner-reported in Logic: the wheel "is jittery and doesn't remain at the position it's
//  dragged to", and on release it drifts back. A debugger on the running extension showed
//  two bugs stacked:
//
//  1. Out of process, the host sends every parameter write back into the extension's tree
//     without our originator token, so the interface heard its own writes as host moves.
//  2. Upstream's cutoff -> wheel placement is not the inverse of the wheel's own
//     wheel -> cutoff write, so hearing the wheel's own value moved the wheel.
//
//  `HostEchoTests` fails with fix 1 reverted; `testACutoffReportedBack…` with fix 2 reverted.

import XCTest
import AVFoundation
@testable import SynthOneCore

// MARK: - The echo

final class HostEchoTests: XCTestCase {

    private var units: [S1AudioUnit] = []

    override func tearDown() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        units.removeAll()
        super.tearDown()
    }

    private func makeHosted() throws -> (S1HostedSynth, AUParameter) {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        units.append(unit)
        let cutoff = try XCTUnwrap(unit.parameterTree?
            .parameter(withAddress: AUParameterAddress(S1Parameter.cutoff.rawValue)))
        return (S1HostedSynth(audioUnit: unit), cutoff)
    }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// **The copy of our writes a host sends back must not reach the interface.** Setting
    /// `value` with no originator is exactly what arrives out of process: our own writes,
    /// a little late, in order.
    func testTheHostEchoingOurWritesIsNotReportedAsAHostChange() throws {
        let (hosted, cutoff) = try makeHosted()
        hosted.echoWindow = 0.2
        var seen: [(S1Parameter, Double)] = []
        hosted.observeHostChanges { seen.append(($0, $1)) }

        hosted.setSynthParameter(.cutoff, 1_950)
        hosted.setSynthParameter(.cutoff, 2_000)
        cutoff.value = 1_950
        cutoff.value = 2_000
        wait(0.1)
        XCTAssertTrue(seen.isEmpty, "the host's echo of our own drag came back as a host move: \(seen)")

        // Once the window closes the DSP agrees with the last write, so there is nothing
        // to reconcile either.
        wait(0.4)
        XCTAssertTrue(seen.isEmpty, "a pure echo was reported after the window: \(seen)")
    }

    /// Suppression must not swallow automation: once the interface is quiet, a host move
    /// arrives exactly as before.
    func testAHostChangeAfterTheWindowStillReachesTheInterface() throws {
        let (hosted, cutoff) = try makeHosted()
        hosted.echoWindow = 0.1
        var seen: [(S1Parameter, Double)] = []
        hosted.observeHostChanges { seen.append(($0, $1)) }

        hosted.setSynthParameter(.cutoff, 2_000)
        wait(0.2)
        cutoff.value = 1_500
        wait(0.1)

        XCTAssertEqual(seen.count, 1, "\(seen)")
        XCTAssertEqual(seen.first?.0, .cutoff)
        XCTAssertEqual(seen.first?.1 ?? 0, 1_500, accuracy: 1)
    }

    /// Automation that lands *while* a control is moving looks exactly like an echo when it
    /// arrives. It must still show up once the control goes quiet, or the panel lies about
    /// what is playing.
    ///
    /// The first check waits 0.15 s, not less: the tree delivers observer callbacks late
    /// and coalesced (two writes above arrive as one), and a 50 ms wait passed with the
    /// suppression switched off — it was checking before anything had arrived.
    func testAHostChangeInsideTheWindowIsReportedOnceTheInterfaceIsQuiet() throws {
        let (hosted, cutoff) = try makeHosted()
        hosted.echoWindow = 0.4
        var seen: [(S1Parameter, Double)] = []
        hosted.observeHostChanges { seen.append(($0, $1)) }

        hosted.setSynthParameter(.cutoff, 2_000)
        cutoff.value = 800
        wait(0.15)
        XCTAssertTrue(seen.isEmpty, "reported inside the window: \(seen)")

        wait(0.5)
        XCTAssertEqual(seen.count, 1, "\(seen)")
        XCTAssertEqual(seen.first?.1 ?? 0, 800, accuracy: 1)
    }
}

// MARK: - The wheel

/// Commandeers `Conductor.sharedInstance` the way `HostedInterfaceTests` does, because every
/// view controller captures it at init.
final class ModWheelPlacementTests: XCTestCase {

    private var savedConductor: Conductor?

    override func setUp() {
        super.setUp()
        savedConductor = Conductor.sharedInstance
        Conductor.sharedInstance = Conductor()
    }

    override func tearDown() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        if let savedConductor { Conductor.sharedInstance = savedConductor }
        savedConductor = nil
        super.tearDown()
    }

    private func loadPlugin() throws -> (Manager, S1AudioUnit) {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        SynthOneApp.startHosted(audioUnit: unit)

        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        manager.loadViewIfNeeded()
        manager.view.layoutIfNeeded()
        // Cutoff — what 658 of the 695 factory presets route the wheel to.
        manager.activePreset.modWheelRouting = 0
        return (manager, unit)
    }

    private func drag(_ wheel: AKVerticalPad, toFractionDown fraction: CGFloat) {
        wheel.setPercentagesWithTouchPoint(CGPoint(x: wheel.bounds.midX, y: wheel.bounds.height * fraction))
    }

    /// **A cutoff the wheel just set must put the wheel back where it is.** This is the path
    /// every host notification takes — `updateSingleUI` with no control — and upstream's
    /// placement did not invert the wheel's own write. Both clamped ends are included.
    func testACutoffReportedBackPlacesTheWheelWhereItWasDragged() throws {
        let (manager, _) = try loadPlugin()
        let wheel = try XCTUnwrap(manager.modWheelPad)
        let conductor = Conductor.sharedInstance
        XCTAssertGreaterThan(wheel.bounds.height, 0, "the wheel was never laid out")

        for fraction: CGFloat in [0.02, 0.1, 0.3, 0.5, 0.7, 0.9, 0.98] {
            drag(wheel, toFractionDown: fraction)
            let dragged = wheel.value
            conductor.updateSingleUI(.cutoff, control: nil, value: conductor.synth.getSynthParameter(.cutoff))
            XCTAssertEqual(wheel.value, dragged, accuracy: 0.01,
                           "dragged \(Int(fraction * 100))% of the way down, redrawn elsewhere")
        }
    }

    /// **The owner's symptom, end to end:** drag the wheel in the plugin to the top, let the
    /// host echo each write back the way Logic does out of process, and the wheel stays put.
    /// Before ADR-030 the last echo, 360 Hz, redrew a wheel at 1.0 at 0.58.
    ///
    /// The interface settles first. Just after loading, the touch pad's reset animation
    /// reports cutoff with no control, which reaches the same placement code; without the
    /// pause this test measured that as well as the echo.
    func testTheWheelStaysWhereItWasDraggedWhenTheHostEchoesTheDrag() throws {
        let (manager, unit) = try loadPlugin()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let wheel = try XCTUnwrap(manager.modWheelPad)
        let cutoff = try XCTUnwrap(unit.parameterTree?
            .parameter(withAddress: AUParameterAddress(S1Parameter.cutoff.rawValue)))

        var written: [AUValue] = []
        for fraction: CGFloat in [0.6, 0.3, 0.02] {
            drag(wheel, toFractionDown: fraction)
            written.append(cutoff.value)
        }
        let dragged = wheel.value
        XCTAssertEqual(dragged, 1, accuracy: 0.001, "the drag did not reach the top")

        for value in written { cutoff.value = value }
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        XCTAssertEqual(wheel.value, dragged, accuracy: 0.01, "the wheel drifted after release")
    }
}
