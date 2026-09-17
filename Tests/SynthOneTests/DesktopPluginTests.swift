//  P6-5: the desktop layout as the plugin shows it (ADR-045).
//
//  The plugin builds the same layout over the same `Manager`, against a host's audio unit
//  and with no engine. What differs is checked here: no Record, the scope fed from the
//  render thread's ring, the transport caption, the size the host is asked for, and the
//  panel sheets presented as overlays inside the plugin's view rather than as Mac sheets
//  on a window the plugin does not own.
//
//  Commandeers `Conductor.sharedInstance` as `HostedInterfaceTests` does, and restores it.

import XCTest
import UIKit
@testable import SynthOneCore

final class DesktopPluginTests: XCTestCase {

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

    private func makeHostedDesktop() throws -> (Manager, S1DesktopLayout) {
        let unit = try S1AudioUnit(componentDescription: AKSynthOne.ComponentDescription, options: [])
        S1Wavetables.loadAndApply(to: unit)
        S1FactoryPresets.install(into: unit)
        // As a host does before it shows the view: without this the kernel's dependent
        // parameters can read as NaN, which `AKTouchPadView` now survives (P6-5).
        try unit.allocateRenderResources()
        SynthOneApp.startHosted(audioUnit: unit)
        let manager = try XCTUnwrap(SynthOneApp.makeRootViewController(layout: .desktop) as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: SynthOneApp.desktopWindowSize)
        manager.view.layoutIfNeeded()
        return (manager, try XCTUnwrap(manager.desktopLayout))
    }

    func testThePluginGetsTheLayoutWithoutRecordAndWithTheScope() throws {
        let (manager, layout) = try makeHostedDesktop()
        XCTAssertTrue(manager.conductor.isHosted)
        let generators = manager.generatorsPanel
        XCTAssertFalse(generators.recordButton.isDescendant(of: layout.root), "the host records; the plugin has no recorder")
        XCTAssertFalse(generators.recordStatus.isDescendant(of: layout.root))
        let plot = try XCTUnwrap(manager.conductor.audioPlotter)
        XCTAssertTrue(plot.isDescendant(of: layout.toolbar), "the scope is fed from the render thread's ring (ADR-028)")
        // The sequencer follows the host transport, and says so.
        let sequencer = try XCTUnwrap(layout.sections["Sequencer"])
        let caption = sequencer.headerAccessories.arrangedSubviews.compactMap { $0 as? UILabel }.first
        XCTAssertEqual(caption?.isHidden, false)
    }

    /// P7-5, P7-6: the plugin has no menu bar, so Settings is its only way to a layout or a
    /// skin — and its note says "the host loads", not "Arcade Ruins opens".
    func testThePluginsSettingsPopoverCarriesTheLayoutAndSkinPickers() throws {
        S1Layout.setCurrent(.desktop)
        let (manager, _) = try makeHostedDesktop()
        let settings = try XCTUnwrap(manager.storyboard?
            .instantiateViewController(withIdentifier: "MIDISettingsViewController") as? MIDISettingsViewController)
        settings.loadViewIfNeeded()
        let pickers = try XCTUnwrap(S1AppearanceSettings.installed(in: settings))
        XCTAssertEqual(pickers.noteString, S1AppearanceSettings.noteText(isHosted: true))
        XCTAssertTrue(try XCTUnwrap(pickers.noteString).contains("host"))
        // The plugin writes its own container's defaults, which its next load reads
        pickers.select(S1SkinChoice.cabinet)
        XCTAssertEqual(S1SkinChoice.chosen, .cabinet)
        pickers.select(S1Layout.classic)
        XCTAssertEqual(S1Layout.current, .classic, "a host can reach the classic interface too")
        S1Preferences.store.removeObject(forKey: S1Layout.classicDefaultsKey)
        S1SkinChoice.choose(.studio)   // ADR-064: the suite's skin, not the product's default
    }

    func testTheHostIsAskedForTheDesignSize() {
        XCTAssertEqual(SynthOneApp.desktopWindowSize, CGSize(width: 1_440, height: 900))
    }

    func testPanelSheetsAreOverlaysInThePlugin() throws {
        let (manager, _) = try makeHostedDesktop()
        let sheet = S1PanelSheet(title: "Tunings", panel: manager.tuningsPanel, owner: manager)
        XCTAssertTrue(sheet.isOverlay)
        XCTAssertEqual(sheet.modalPresentationStyle, .overCurrentContext,
                       "a Catalyst form sheet needs the presenting view's own window; a plugin's view lives in the host's (ADR-044)")
        sheet.loadViewIfNeeded()
        sheet.view.frame = CGRect(origin: .zero, size: SynthOneApp.desktopWindowSize)
        sheet.view.layoutIfNeeded()
        let done = try XCTUnwrap(sheet.closeButton)
        XCTAssertTrue(done.isDescendant(of: sheet.view))
        // The card is centred, not pinned to the edges.
        let card = try XCTUnwrap(done.superview?.superview)
        XCTAssertEqual(card.frame.midX, sheet.view.bounds.midX, accuracy: 1)
        XCTAssertLessThan(card.frame.width, sheet.view.bounds.width)
    }

    func testStandaloneSheetsStayMacSheets() throws {
        // The standalone conductor, started offline as the rest of the suite starts it.
        Conductor.sharedInstance = try XCTUnwrap(savedConductor)
        SynthOneApp.start(mode: .offline)
        let manager = try XCTUnwrap(SynthOneApp.makeRootViewController(layout: .desktop) as? Manager)
        manager.loadViewIfNeeded()
        let sheet = S1PanelSheet(title: "Tunings", panel: manager.tuningsPanel, owner: manager)
        XCTAssertFalse(sheet.isOverlay)
        XCTAssertEqual(sheet.modalPresentationStyle, .formSheet)
    }
}
