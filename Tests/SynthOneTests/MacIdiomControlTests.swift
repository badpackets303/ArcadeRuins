//  ADR-033: controls the Mac idiom refuses, and the preset editor's bank picker.
//
//  Under Optimize Interface for Mac (ADR-023) a `UIPickerView` throws the moment it enters a
//  window — "UIPickerView is not supported when running Catalyst apps in the Mac idiom" — and
//  the preset editor's bank picker was one. Opening the editor crashed the plugin in Logic three
//  times on 2026-09-10, and the standalone the same way when reproduced under lldb.
//
//  The test bundle runs in the `.pad` idiom with no `NSApplication`, so nothing here can make
//  UIKit throw. What it can do is what the sweep in the running app did: walk every scene of every
//  storyboard and look for the classes UIKit restricts. And it checks that the replacement still
//  does the one thing the picker was for — choosing the bank a preset is saved into.

import XCTest
import UIKit
@testable import SynthOneCore

final class MacIdiomControlTests: XCTestCase {

    /// Offline, for the reason given in `UILoadTests`.
    private static let started: Bool = {
        SynthOneApp.start(mode: .offline)
        return true
    }()

    override func setUp() {
        super.setUp()
        _ = Self.started
    }

    /// **UIKit's own record** of the classes with Mac-idiom restrictions: those carrying a
    /// `UICatalystMacIdiomUnsupported_Internal` category in UIKitCore (macOS 26), read from the
    /// running app. `UIButton` is on that record too. It is used everywhere, does not throw, and
    /// its restriction is handled by `useDesignedButtonAppearance()` (ADR-026, ADR-029).
    ///
    /// Of the rest, the running app confirmed that `UIPickerView` throws. None of the others is
    /// used anywhere. Adding one should be tried in the running app first, not only here.
    private let restricted: [AnyClass] = [UIPickerView.self, UIRefreshControl.self,
                                          UISlider.self, UIStepper.self, UISwitch.self]

    /// The two scenes that are `Manager` itself. The walk takes Manager as the app builds it
    /// instead, and `iPhoneParentVC` is never loaded (`Conductor.device` is never `.phone`).
    private let managerScenes: Set<String> = ["ParentViewController", "iPhoneParentVC"]

    // MARK: - The sweep

    /// Every scene of every storyboard, by the identifiers the compiled storyboard itself records,
    /// loaded and walked view by view. Walking the hierarchy rather than naming controls is the
    /// lesson of ADR-029: a list of names missed live cases twice.
    func testNoStoryboardSceneHoldsAControlTheMacIdiomRefuses() throws {
        var scenes = 0
        var offenders: [String] = []

        for name in try storyboardNames() {
            let compiled = try XCTUnwrap(Bundle.synthOneCore.url(forResource: name, withExtension: "storyboardc"),
                                         "\(name).storyboardc is not in the framework")
            let info = try XCTUnwrap(NSDictionary(contentsOf: compiled.appendingPathComponent("Info.plist")))
            let identifiers = try XCTUnwrap(info["UIViewControllerIdentifiersToNibNames"] as? [String: String])
            let storyboard = UIStoryboard(name: name, bundle: .synthOneCore)

            for identifier in identifiers.keys.sorted() where !(name == "Main" && managerScenes.contains(identifier)) {
                let controller = storyboard.instantiateViewController(withIdentifier: identifier)
                controller.loadViewIfNeeded()
                offenders += restrictedViews(in: controller.view, scene: "\(name)/\(identifier)")
                scenes += 1
            }
        }

        let manager = try XCTUnwrap((SynthOneApp.makeRootViewController() as? S1ScalingContainer)?.content)
        manager.loadViewIfNeeded()
        offenders += restrictedViews(in: manager.view, scene: "Main/ParentViewController")

        XCTAssertGreaterThan(scenes, 50, "found suspiciously few scenes to walk")
        XCTAssertEqual(offenders, [],
                       "these throw, or may throw, when they enter a window under Optimize Interface for "
                       + "Mac, which crashes the app and the plugin. Replace them, or try them in the running "
                       + "app and record the evidence (ADR-033)")
    }

    /// The walk has to be able to fail: a matcher that never matches passes the test above too.
    func testTheSweepRecognisesARestrictedControl() {
        let container = UIView()
        container.addSubview(UIView())
        container.subviews[0].addSubview(UIPickerView())
        XCTAssertEqual(restrictedViews(in: container, scene: "control"), ["control: UIPickerView"])
    }

    // MARK: - The preset editor

    /// What the picker was for: every bank listed, the preset's own bank chosen when the editor
    /// opens, another one chosen by clicking it, and Save handing that bank to the Presets panel —
    /// without disturbing the category, which is the other table in the same editor.
    ///
    /// The bank list is found through the view hierarchy, not an outlet, so this compiles against
    /// the old picker too and fails there rather than not building.
    ///
    /// The banks are set here rather than loaded. `Manager` reads them from `banks.json` in the
    /// user's Documents, which the test bundle does not see, so a loaded list is empty.
    func testThePresetEditorStillChoosesTheDestinationBank() throws {
        let conductor = Conductor.sharedInstance
        let originalBanks = conductor.banks
        defer { conductor.banks = originalBanks }
        let banks = ["BankA", "Brice Beasley", "User"]
        conductor.banks = banks.enumerated().map { Bank(name: $0.element, position: $0.offset) }

        let preset = Preset()
        preset.name = "Arcade Test"
        preset.bank = banks[1]
        preset.category = 2

        let editor = try XCTUnwrap(UIStoryboard(name: "Presets", bundle: .synthOneCore)
            .instantiateViewController(withIdentifier: "PresetEditorViewController") as? PresetEditorViewController)
        let recorder = PresetEditRecorder()
        editor.delegate = recorder
        editor.preset = preset
        editor.loadViewIfNeeded()

        let table = try XCTUnwrap(firstView(in: editor.view) { $0.accessibilityIdentifier == "BankTableView" } as? UITableView,
                                  "the preset editor has no bank list")
        let dataSource = try XCTUnwrap(table.dataSource)
        guard dataSource.tableView(table, numberOfRowsInSection: 0) == banks.count else {
            return XCTFail("the bank list has \(dataSource.tableView(table, numberOfRowsInSection: 0)) rows "
                           + "for \(banks.count) banks")
        }
        let titles = (0..<banks.count).map {
            dataSource.tableView(table, cellForRowAt: IndexPath(row: $0, section: 0)).textLabel?.text
        }
        XCTAssertEqual(titles, banks, "every bank, in the Presets panel's order")
        XCTAssertEqual(table.indexPathForSelectedRow, IndexPath(row: 1, section: 0),
                       "the editor should open on the preset's own bank")
        XCTAssertEqual(editor.bankSelected, banks[1])

        let categoryBefore = editor.categoryIndex
        table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 2, section: 0))
        XCTAssertEqual(editor.bankSelected, banks[2])
        XCTAssertEqual(editor.categoryIndex, categoryBefore, "choosing a bank must not change the category")

        editor.saveButton.setValueCallback(1)
        XCTAssertEqual(recorder.edits.count, 1)
        XCTAssertEqual(recorder.edits.first?.newBank, banks[2])
        XCTAssertEqual(recorder.edits.first?.name, "Arcade Test")
    }

    // MARK: - Helpers

    private func restrictedViews(in view: UIView, scene: String) -> [String] {
        var found: [String] = []
        if restricted.contains(where: { view.isKind(of: $0) }) {
            found.append("\(scene): \(type(of: view))")
        }
        for subview in view.subviews {
            found += restrictedViews(in: subview, scene: scene)
        }
        return found
    }

    private func firstView(in view: UIView, where match: (UIView) -> Bool) -> UIView? {
        if match(view) { return view }
        for subview in view.subviews {
            if let found = firstView(in: subview, where: match) { return found }
        }
        return nil
    }

    /// The storyboard names, from the `.storyboard` sources, as `UILoadTests` finds them.
    private func storyboardNames() throws -> [String] {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SynthOneCore")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let names = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "storyboard" }
            .map { $0.deletingPathExtension().lastPathComponent }
        XCTAssertEqual(names.count, 12, "expected the twelve storyboards")
        return names.sorted()
    }
}

private final class PresetEditRecorder: PresetPopOverDelegate {
    var edits: [(name: String, category: Int, newBank: String)] = []

    func didFinishEditing(name: String, category: Int, newBank: String) {
        edits.append((name, category, newBank))
    }
}
