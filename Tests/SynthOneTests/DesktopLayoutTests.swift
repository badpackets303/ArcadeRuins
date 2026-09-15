//  P6 acceptance: the desktop layout re-homes every control it takes, and the classic
//  layout is still there (ADR-045).
//
//  The layout is built over the real `Manager` from the real storyboards, exactly as
//  `SynthOneApp.makeRootViewController(layout: .desktop)` does it in the app, and laid
//  out at the design size. What is checked is what breaks silently: a control that was
//  moved out of its panel but never landed anywhere, a readout that stops following its
//  knob, a MIDI-learn walk that can no longer find the knobs.

import XCTest
import UIKit
@testable import SynthOneCore

final class DesktopLayoutTests: XCTestCase {

    private static let started: Bool = {
        SynthOneApp.start(mode: .offline)
        return true
    }()

    override func setUp() {
        super.setUp()
        _ = Self.started
    }

    /// The desktop layout, built and laid out at the design size.
    private func makeDesktop() throws -> (Manager, S1DesktopLayout) {
        let manager = try XCTUnwrap(SynthOneApp.makeRootViewController(layout: .desktop) as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: SynthOneApp.desktopWindowSize)
        manager.view.layoutIfNeeded()
        let layout = try XCTUnwrap(manager.desktopLayout)
        return (manager, layout)
    }

    // MARK: - The two layouts

    func testClassicLayoutIsStillTheScalingContainer() throws {
        let root = SynthOneApp.makeRootViewController(layout: .classic)
        let container = try XCTUnwrap(root as? S1ScalingContainer)
        XCTAssertTrue(container.content is Manager)
        XCTAssertNil((container.content as? Manager)?.desktopLayout)
    }

    func testTestBundleDefaultsToClassic() {
        // `TestStorageIsolation` registers the classic default for the rest of the suite.
        XCTAssertEqual(S1Layout.current, .classic)
    }

    // MARK: - The desktop layout

    func testEveryBoundControlIsOnScreenOrDeliberatelyKeptBack() throws {
        let (manager, layout) = try makeDesktop()

        // Every control the conductor has a binding for should be inside the desktop
        // root, unless it belongs to a panel this layout shows whole (Tunings, if loaded;
        // the developer panel, never shown) or is one of the classic controls it hides on
        // purpose.
        let keptBack: [UIView] = [manager.keyboardToggle, manager.configKeyboardButton, manager.pitchBend,
                                  manager.modWheelPad, manager.bluetoothButton, manager.linkButton,
                                  // P6-2: the filter picker in the Filter header drives this one.
                                  manager.generatorsPanel.filterTypeToggle]
        var wholePanels: [UIView] = [manager.devViewController.view]
        if manager.tuningsPanel.isViewLoaded { wholePanels.append(manager.tuningsPanel.view) }

        let bound = manager.conductor.bindings.compactMap { $0.1 as? UIView }
        XCTAssertGreaterThan(bound.count, 100, "the storyboards should have bound well over a hundred controls")

        var missing: [String] = []
        // `Conductor` is a singleton and its bindings accumulate across every `Manager` the
        // suite builds; only this manager's controls are in question.
        for control in bound where control.isDescendant(of: manager.view) {
            if keptBack.contains(where: { $0 === control }) { continue }
            if wholePanels.contains(where: { control.isDescendant(of: $0) }) { continue }
            if !control.isDescendant(of: layout.root) {
                missing.append("\(type(of: control))")
            }
        }
        XCTAssertEqual(missing, [], "bound controls not in the desktop layout")
    }

    func testFourRowsOfSectionsAtTheDesignSize() throws {
        let (_, layout) = try makeDesktop()
        for name in ["OSC 1", "OSC 2", "Mix", "Filter", "Voice", "Master",
                     "Filter Envelope", "Amplitude Envelope", "LFO & Mod Targets",
                     "Reverb", "Delay", "Phaser", "Bitcrusher", "Sequencer", "Pads"] {
            let section = try XCTUnwrap(layout.sections[name], name)
            XCTAssertGreaterThan(section.bounds.width, 100, name)
            XCTAssertGreaterThan(section.bounds.height, 60, name)
            XCTAssertTrue(section.isDescendant(of: layout.editor), name)
        }
        XCTAssertEqual(layout.editor.arrangedSubviews.count, 4)
    }

    func testKnobReadoutFollowsTheKnob() throws {
        let (manager, _) = try makeDesktop()
        let cutoff = manager.generatorsPanel.cutoff!
        let cell = try XCTUnwrap(cutoff.superview as? S1ControlCell)
        cutoff.value = 1_000
        XCTAssertEqual(cell.valueLabel.text, "1.00 kHz")
        cutoff.value = 250
        XCTAssertEqual(cell.valueLabel.text, "250 Hz")
        XCTAssertTrue(cutoff.drawsDesktopStyle)
    }

    func testMIDILearnStillFindsTheMovedKnobs() throws {
        let (manager, layout) = try makeDesktop()
        let generators = layout.controlViews(of: manager.generatorsPanel) ?? []
        XCTAssertTrue(generators.contains { $0 === manager.generatorsPanel.cutoff })
        XCTAssertTrue(generators.contains { $0 is MIDILearnable })
        XCTAssertNil(layout.controlViews(of: manager.tuningsPanel), "the tunings panel is shown whole")
    }

    func testSequencerSlidersFollowTheirNewHeight() throws {
        let (manager, _) = try makeDesktop()
        let slider = manager.sequencerPanel.sliders[0]
        XCTAssertNotEqual(slider.bounds.height, 160, "the desktop layout does not use the storyboard height")
        XCTAssertEqual(slider.barLength, slider.bounds.height - slider.barMargin * 2, accuracy: 0.5)
    }

    // MARK: - P6-2

    func testFilterPickerDrivesAndFollowsTheClassicButton() throws {
        let (manager, layout) = try makeDesktop()
        let button = manager.generatorsPanel.filterTypeToggle!
        let picker = try XCTUnwrap(layout.sections["Filter"]?.headerAccessories.arrangedSubviews
            .compactMap { $0 as? S1SegmentedControl }.first)
        XCTAssertEqual(picker.selectedIndex, Int(button.value))

        // The picker drives the classic button, which keeps the binding.
        picker.onSelect?(2)
        XCTAssertEqual(button.value, 2)
        XCTAssertEqual(manager.conductor.synth.getSynthParameter(.filterType), 2)

        // A parameter change from elsewhere (a preset, automation) moves the picker.
        layout.parameterDidChange(.filterType, value: 1)
        XCTAssertEqual(picker.selectedIndex, 1)
        picker.onSelect?(0)
    }

    func testRateReadoutsFollowTempoSync() throws {
        let (manager, layout) = try makeDesktop()
        let synth = manager.conductor.synth!
        XCTAssertEqual(layout.rateCells.count, 4, "LFO 1, LFO 2, delay time, auto-pan rate")
        let lfo1 = try XCTUnwrap(layout.rateCells.first { $0.control === manager.fxPanel.lfo1RateKnob })

        synth.setSynthParameter(.tempoSyncToArpRate, 0)
        synth.setSynthParameter(.lfo1Rate, 2.5)
        layout.parameterDidChange(.lfo1Rate, value: 2.5)
        XCTAssertEqual(lfo1.valueLabel.text, "2.5 Hz")

        synth.setSynthParameter(.tempoSyncToArpRate, 1)
        layout.parameterDidChange(.tempoSyncToArpRate, value: 1)
        XCTAssertEqual(lfo1.valueLabel.text, "\(Rate.fromFrequency(synth.getSynthParameter(.lfo1Rate)))")
        XCTAssertFalse(lfo1.valueLabel.text?.contains("%") ?? true, "a normalised position is not a rate")
        synth.setSynthParameter(.tempoSyncToArpRate, 0)
    }

    func testLFOChipHalvesFollowTheChipWidth() throws {
        let (manager, _) = try makeDesktop()
        let chip = manager.fxPanel.cutoffLFOToggle!
        XCTAssertTrue(chip.drawsDesktopStyle)
        XCTAssertLessThan(chip.bounds.width, 100, "the chip is narrower than the classic 106 points")
        XCTAssertTrue(manager.fxPanel.lfo1WavePicker.drawsDesktopStyle)
    }

    // MARK: - P6-3

    func testSequencerControlsWearTheDesktopDressAndHitTestTheirBounds() throws {
        let (manager, _) = try makeDesktop()
        let seq = manager.sequencerPanel

        // Steppers: a button either side, at whatever size Auto Layout gave them.
        let stepper = seq.octaveStepper!
        XCTAssertTrue(stepper.drawsDesktopStyle)
        XCTAssertNotEqual(stepper.bounds.width, 108, "the storyboard's size")
        XCTAssertEqual(stepper.hitZone(for: CGPoint(x: 4, y: stepper.bounds.midY)), 1, "minus at the left edge")
        XCTAssertEqual(stepper.hitZone(for: CGPoint(x: stepper.bounds.maxX - 4, y: stepper.bounds.midY)), 2, "plus at the right edge")
        XCTAssertEqual(stepper.hitZone(for: CGPoint(x: stepper.bounds.midX, y: stepper.bounds.midY)), 0, "the value between")

        // Tempo: display on top, minus and plus below, all inside the bounds.
        let tempo = manager.generatorsPanel.tempoStepper!
        XCTAssertTrue(tempo.drawsDesktopStyle)
        XCTAssertEqual(tempo.hitZone(for: CGPoint(x: 6, y: tempo.bounds.maxY - 4)), 1)
        XCTAssertEqual(tempo.hitZone(for: CGPoint(x: tempo.bounds.maxX - 6, y: tempo.bounds.maxY - 4)), 2)
        XCTAssertEqual(tempo.hitZone(for: CGPoint(x: tempo.bounds.midX, y: 6)), 0, "the display is for dragging")

        // Direction: three equal cells.
        let direction = seq.arpDirectionButton!
        XCTAssertTrue(direction.drawsDesktopStyle)
        XCTAssertEqual(direction.cellWidth, direction.bounds.width / 3, accuracy: 0.01)

        // Steps: slider cap, note-on bar and transpose field in the desktop dress.
        XCTAssertTrue(seq.sliders.allSatisfy { $0.drawsDesktopStyle })
        XCTAssertEqual(seq.sliders[0].knobSize, CGSize(width: 32, height: 14))
        XCTAssertTrue(seq.noteOnButtons.allSatisfy { $0.drawsDesktopStyle })
        XCTAssertTrue(seq.octBoostButtons.allSatisfy { $0.drawsDesktopStyle })
        XCTAssertTrue(seq.sequencerToggle.drawsDesktopStyle)
        XCTAssertEqual(seq.sequencerToggle.desktopLabels.0, "Arp")
    }

    func testClassicStepperKeepsItsStoryboardZones() throws {
        // The classic layout is untouched: the fixed paths still decide.
        let root = try XCTUnwrap(SynthOneApp.makeRootViewController(layout: .classic) as? S1ScalingContainer)
        let manager = try XCTUnwrap(root.content as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        manager.view.layoutIfNeeded()
        let stepper = manager.sequencerPanel.octaveStepper!
        XCTAssertFalse(stepper.drawsDesktopStyle)
        XCTAssertEqual(stepper.hitZone(for: CGPoint(x: 10, y: 10)), 1)
        XCTAssertEqual(stepper.hitZone(for: CGPoint(x: 90, y: 10)), 2)
        XCTAssertEqual(stepper.hitZone(for: CGPoint(x: 50, y: 10)), 0)
    }

    func testPanelSheetHasAVisibleDoneButtonAndEscape() throws {
        let (manager, _) = try makeDesktop()
        let sheet = S1PanelSheet(title: "Tunings", panel: manager.tuningsPanel, owner: manager)
        sheet.loadViewIfNeeded()
        sheet.view.frame = CGRect(origin: .zero, size: sheet.preferredContentSize)
        sheet.view.layoutIfNeeded()
        let done = try XCTUnwrap(sheet.closeButton)
        XCTAssertEqual(done.buttonType, .custom, "a .system button drew nothing under the Mac idiom")
        XCTAssertEqual(done.currentTitle, "Done")
        XCTAssertGreaterThan(done.bounds.width, 30)
        XCTAssertTrue(done.isDescendant(of: sheet.view))
        XCTAssertTrue(sheet.keyCommands?.contains { $0.input == UIKeyCommand.inputEscape } ?? false)
        XCTAssertTrue(manager.tuningsPanel.parent === sheet, "the sheet adopts the panel while it is up")
        sheet.releasePanel()
        XCTAssertTrue(manager.tuningsPanel.parent === manager, "and hands it back")
    }

    // MARK: - P6-6: the preset sidebar

    func testThePresetBrowserIsTheClassicPanelInADropDown() throws {
        let (manager, layout) = try makeDesktop()
        let presets = manager.presetsViewController
        let categories = try XCTUnwrap(presets.children.first { $0 is PresetsCategoriesViewController } as? PresetsCategoriesViewController)
        // Both tables, the search button, the notes and the buttons are in the panel.
        for view in [presets.tableView, categories.categoryTableView, presets.searchtoolButton, presets.presetDescriptionField,
                     presets.newButton, presets.importButton, presets.reorderButton, presets.importBankButton, presets.newBankButton] as [UIView] {
            XCTAssertTrue(view.isDescendant(of: layout.presetPanel), "\(type(of: view))")
        }
        // Wired: the category list drives the preset list without the classic panel ever appearing.
        XCTAssertTrue(categories.categoryDelegate === presets)
        XCTAssertEqual(presets.rowHeight, 30)
        XCTAssertEqual(categories.rowHeight, 38, "the category cell's constraints need 22 + 2 × 8")
        XCTAssertGreaterThan(presets.tableView.bounds.height, 200, "the preset list takes the height")
        XCTAssertEqual(layout.presetPanel.bounds.width, 380)
        XCTAssertEqual(layout.presetPanel.bounds.height, 720)
        // P8-0: no sidebar — the rows have the whole width
        XCTAssertEqual(layout.editor.bounds.width, layout.root.bounds.width)
    }

    func testThePresetBrowserDropsDownFromTheNameAndClosesOnAClickOutside() throws {
        let (manager, layout) = try makeDesktop()
        XCTAssertFalse(layout.isPresetPanelVisible)
        XCTAssertTrue(layout.presetPanel.isHidden, "closed until asked for")
        XCTAssertEqual(layout.presetFieldButton.accessibilityLabel, "Presets")

        // `sendActions` needs a running UIApplication; the button's action is the closure.
        let open = try XCTUnwrap(layout.presetFieldButton.action)
        open()
        manager.view.layoutIfNeeded()
        XCTAssertTrue(layout.isPresetPanelVisible)
        XCTAssertFalse(layout.presetPanel.isHidden)
        let panel = layout.presetPanel.convert(layout.presetPanel.bounds, to: layout.root)
        let field = layout.presetField.convert(layout.presetField.bounds, to: layout.root)
        XCTAssertEqual(panel.minY, layout.toolbar.bounds.maxY + 4, accuracy: 0.5, "hangs from the toolbar")
        XCTAssertEqual(panel.midX, field.midX, accuracy: 0.5, "under the preset name")
        XCTAssertTrue(layout.root.bounds.contains(panel), "inside the window")
        XCTAssertTrue(layout.root.subviews.last === layout.presetPanel, "over the rows")

        // A click anywhere else puts it away; so does Escape, ⌥⌘P toggles, ⌘F searches
        let backdrop = try XCTUnwrap(layout.root.subviews.first { $0.accessibilityLabel == "Close the preset browser" })
        XCTAssertFalse(backdrop.isHidden)
        let clickOutside = try XCTUnwrap((backdrop.subviews.first as? S1ActionButton)?.action)
        clickOutside()
        XCTAssertFalse(layout.isPresetPanelVisible)
        XCTAssertTrue(backdrop.isHidden)
        let commands = manager.keyCommands ?? []
        XCTAssertTrue(commands.contains { $0.input == "f" && $0.modifierFlags == .command }, "⌘F searches")
        XCTAssertTrue(commands.contains { $0.input == "p" && $0.modifierFlags == [.command, .alternate] }, "⌥⌘P toggles")
        XCTAssertTrue(commands.contains { $0.input == UIKeyCommand.inputEscape }, "Escape closes")
        manager.desktopTogglePresets(nil)
        XCTAssertTrue(layout.isPresetPanelVisible)
        manager.desktopClosePresets(nil)
        XCTAssertFalse(layout.isPresetPanelVisible)
    }

    func testSelectingABankFillsThePresetList() throws {
        let (manager, _) = try makeDesktop()
        let presets = manager.presetsViewController
        let categories = try XCTUnwrap(presets.children.first { $0 is PresetsCategoriesViewController } as? PresetsCategoriesViewController)
        // The test bundle's storage is empty, so load the factory banks the way Manager does at launch.
        manager.loadBankSettings()
        presets.loadBanks()
        categories.updateChoices()
        let bankRow = PresetCategory.bankStartingIndex + 1   // the first factory bank after User
        categories.tableView(categories.categoryTableView, didSelectRowAt: IndexPath(row: bankRow, section: 0))
        XCTAssertEqual(presets.categoryIndex, bankRow)
        XCTAssertGreaterThan(presets.sortedPresets.count, 0, "a bank's presets are listed")
        XCTAssertEqual(presets.tableView.numberOfRows(inSection: 0), presets.sortedPresets.count)
    }

    // MARK: - P6-4

    func testMinimumWindowIsTheDesignSize() {
        XCTAssertEqual(SynthOneApp.desktopMinimumWindowSize, SynthOneApp.desktopWindowSize)
        XCTAssertEqual(SynthOneApp.desktopWindowSize, CGSize(width: 1_440, height: 900))
    }

    func testLayoutIsAlwaysDarkAndTheHiddenHierarchyHasNoActiveConstraints() throws {
        let (manager, layout) = try makeDesktop()
        XCTAssertEqual(manager.overrideUserInterfaceStyle, .dark)
        // Every direct subview of the manager's view other than the desktop root is the
        // hidden classic hierarchy; none of its constraints may still be active.
        // Autoresizing-mask and intrinsic-content-size constraints are UIKit's own, regenerated
        // on every layout pass for the storyboard's fixed-frame views and image views, and
        // cannot conflict with anything once the storyboard's explicit constraints are gone;
        // they are not what is being counted.
        func isExplicit(_ constraint: NSLayoutConstraint) -> Bool {
            let kind = NSStringFromClass(type(of: constraint))
            return constraint.isActive && !kind.contains("Autoresizing") && !kind.contains("ContentSize")
        }
        var active: [String] = []
        func walk(_ view: UIView) {
            active += view.constraints.filter(isExplicit).map { "\($0)" }
            view.subviews.forEach(walk)
        }
        for subview in manager.view.subviews where subview !== layout.root {
            XCTAssertTrue(subview.isHidden)
            walk(subview)
        }
        XCTAssertEqual(active, [], "the hidden classic hierarchy still has active constraints")
        XCTAssertEqual(manager.view.constraints.filter { isExplicit($0) && $0.firstItem !== layout.root && $0.secondItem !== layout.root }.count, 0)
    }

    func testTheFourthRowTakesTheExtraHeight() throws {
        let (manager, layout) = try makeDesktop()
        let rows = layout.editor.arrangedSubviews
        let atDesign = rows.map { $0.bounds.height }
        manager.view.frame = CGRect(origin: .zero, size: CGSize(width: 1_680, height: 1_100))
        manager.view.layoutIfNeeded()
        let taller = rows.map { $0.bounds.height }
        XCTAssertEqual(taller[0], atDesign[0]); XCTAssertEqual(taller[1], atDesign[1]); XCTAssertEqual(taller[2], atDesign[2])
        XCTAssertEqual(taller[3], atDesign[3] + 200, accuracy: 1, "the fourth row alone grows")
        let slider = manager.sequencerPanel.sliders[0]
        XCTAssertGreaterThan(slider.bounds.height, 200)
        XCTAssertEqual(slider.barLength, slider.bounds.height - slider.barMargin * 2, accuracy: 0.5, "the bar follows the new height")
        // The flexible sections took the extra width; the fixed ones did not.
        XCTAssertEqual(layout.sections["OSC 1"]!.bounds.width, 184)   // P8-0
        XCTAssertGreaterThan(layout.sections["Mix"]!.bounds.width, 400)
    }

    // MARK: - P6-7: the classic screens as cards

    func testAboutAndTheEditorsPresentAsCentredCards() throws {
        let (manager, layout) = try makeDesktop()
        let about = try XCTUnwrap(UIStoryboard(name: "About", bundle: .synthOneCore).instantiateInitialViewController())
        let editor = UIStoryboard(name: "Presets", bundle: .synthOneCore).instantiateViewController(withIdentifier: "PresetEditorViewController")
        for (controller, identifier, size) in [(about, "SegueToAbout", CGSize(width: 1_024, height: 768)),
                                               (editor, "SegueToEdit", CGSize(width: 560, height: 336))] {
            let original = controller.view!
            let card = try XCTUnwrap(layout.dressPresented(controller, segue: identifier), identifier)
            XCTAssertEqual(controller.modalPresentationStyle, .overCurrentContext)
            XCTAssertTrue(original.isDescendant(of: card), "the controller's own view sits inside the card")
            controller.view.frame = CGRect(origin: .zero, size: SynthOneApp.desktopWindowSize)
            controller.view.layoutIfNeeded()
            XCTAssertEqual(card.frame.size, size, identifier)
            XCTAssertEqual(card.frame.midX, 720, accuracy: 1, identifier)
            XCTAssertEqual(card.frame.midY, 450, accuracy: 1, identifier)
            XCTAssertEqual(original.frame.size, size, "the original view fills the card")
            // Never twice.
            XCTAssertNil(layout.dressPresented(controller, segue: identifier))
        }
        // The popovers are not touched.
        XCTAssertNil(layout.dressPresented(about, segue: "SegueToMIDI"))
        _ = manager
    }

    func testPresetRowsCentreTheirContent() throws {
        let (manager, _) = try makeDesktop()
        XCTAssertTrue(PresetCell.centresContentVertically)
        let presets = manager.presetsViewController
        manager.loadBankSettings()
        presets.loadBanks()
        presets.categoryIndex = PresetCategory.bankStartingIndex + 1
        presets.tableView.layoutIfNeeded()
        let cell = try XCTUnwrap(presets.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? PresetCell)
        cell.layoutIfNeeded()
        XCTAssertEqual(cell.presetNameLabel.center.y, cell.contentView.bounds.midY, accuracy: 0.5,
                       "the label sat at the storyboard's y 13 in a 30-point row")
        // P8-0: the selected row's four buttons — the rename button is the way to the preset
        // editor — are inside the row, in the storyboard's order, and the name stops before them.
        cell.setSelected(true, animated: false)
        cell.layoutIfNeeded()
        let buttons: [UIButton] = [cell.favoriteButton, cell.renameButton, cell.duplicateButton, cell.shareButton]
        for button in buttons {
            XCTAssertFalse(button.isHidden)
            XCTAssertLessThanOrEqual(button.frame.maxX, cell.contentView.bounds.width, "\(button.accessibilityLabel ?? "button") off the right edge")
            XCTAssertGreaterThan(button.frame.minX, cell.presetNameLabel.frame.minX)
        }
        XCTAssertEqual(buttons.map(\.frame.minX), buttons.map(\.frame.minX).sorted(), "storyboard order kept")
        XCTAssertLessThanOrEqual(cell.presetNameLabel.frame.maxX, cell.favoriteButton.frame.minX)
        XCTAssertGreaterThan(cell.presetNameLabel.frame.width, 120, "the name still has room")
    }

    func testValueFormats() {
        XCTAssertEqual(S1ValueFormat.hertz.string(for: 2_400), "2.40 kHz")
        XCTAssertEqual(S1ValueFormat.hertz.string(for: 180), "180 Hz")
        XCTAssertEqual(S1ValueFormat.seconds.string(for: 0.012), "12 ms")
        XCTAssertEqual(S1ValueFormat.seconds.string(for: 1.5), "1.50 s")
        XCTAssertEqual(S1ValueFormat.semitones.string(for: -12), "-12 st")
        XCTAssertEqual(S1ValueFormat.percent.string(for: 0.62), "62%")
    }
}
