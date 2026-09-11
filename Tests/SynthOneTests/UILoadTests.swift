//  P3-1 acceptance: the UI loads.
//
//  "The app launches and every panel renders" is the criterion, and a screenshot
//  is a poor way to check it — it needs a person, a display and a permission
//  dialog, and it says nothing the next session can re-run. So this instantiates
//  every storyboard from the framework bundle, forces each view controller to load
//  and lay out, and walks the resulting hierarchy.
//
//  What it is really testing is the two things that break silently:
//
//  1. **Class resolution.** The storyboards were authored with
//     `customModule="AudioKitSynthOne" customModuleProvider="target"`. Compiled
//     inside `SynthOneCore`, the module recorded in the nib becomes `SynthOneCore`
//     — but if that ever stops being true, `instantiateViewController` returns a
//     plain `UIViewController` and every `@IBOutlet` is nil. The casts here are the
//     check.
//  2. **Bundle.** Upstream loads storyboards from `Bundle.main`. They are framework
//     resources now, and a missed call site is a crash at runtime, not a build
//     error.

import XCTest
import UIKit
@testable import SynthOneCore

final class UILoadTests: XCTestCase {

    /// iPad portrait-ish, the size the storyboards were designed at.
    private let canvas = CGRect(x: 0, y: 0, width: 1_024, height: 768)

    /// `Conductor` is a singleton and the UI is built around that, so the audio
    /// side is started once for the whole class rather than per test.
    ///
    /// **Offline** on purpose. These tests want the synth to exist so panels can
    /// read parameter ranges off it; they do not want audio. A real-time engine
    /// opens the hardware output unit, and in a process that cannot get an output
    /// device that costs 90 seconds (ADR-015) — it took this class from 1 s to 300 s
    /// before it was noticed.
    private static let started: Bool = {
        SynthOneApp.start(mode: .offline)
        return true
    }()

    override func setUp() {
        super.setUp()
        _ = Self.started
    }

    // MARK: - Helpers

    private func storyboard(_ name: String) -> UIStoryboard {
        UIStoryboard(name: name, bundle: .synthOneCore)
    }

    /// Instantiates, loads the view, and lays it out at iPad size.
    @discardableResult
    private func realise(_ controller: UIViewController) -> UIViewController {
        controller.view.frame = canvas
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        return controller
    }

    private func countViews(_ view: UIView) -> Int {
        1 + view.subviews.reduce(0) { $0 + countViews($1) }
    }

    // MARK: - The storyboards themselves

    /// All twelve compile into the framework and can be found there.
    func testAllTwelveStoryboardsAreBundled() {
        let names = ["Main", "Header", "Generators", "Envelopes", "Effects", "Sequencer",
                     "TouchPad", "Tunings", "Presets", "About", "MailingList", "Dev"]
        XCTAssertEqual(names.count, 12)
        for name in names {
            XCTAssertNotNil(Bundle.synthOneCore.url(forResource: name, withExtension: "storyboardc"),
                            "\(name).storyboardc is not in the framework")
        }
    }

    /// Localised strings came across with them — 8 languages plus Base.
    func testLocalizationsAreBundled() {
        for language in ["Base", "en", "fr", "ja", "pt-BR", "tr", "zh-Hans", "zh-Hant"] {
            XCTAssertNotNil(Bundle.synthOneCore.path(forResource: language, ofType: "lproj"),
                            "no \(language).lproj in the framework")
        }
    }

    // MARK: - Class resolution

    /// **Every custom class named by every storyboard must resolve.**
    ///
    /// This is the check that the panel tests can only make one panel at a time.
    /// An unresolved class is silent: the nib substitutes a plain `UIView` or
    /// `UIViewController`, the outlets are nil, and the failure surfaces somewhere
    /// unrelated. P3-1 hit it for real — eighteen `customModule` attributes still
    /// named `AudioKitSynthOne`, `AudioKit` or `AudioKitUI`.
    ///
    /// The list is derived from the storyboards themselves rather than hand-written,
    /// so adding a control to a storyboard extends the check automatically.
    func testEveryStoryboardCustomClassResolves() throws {
        var checked = 0
        var missing: [String] = []

        for url in try storyboardSourceURLs() {
            let xml = try String(contentsOf: url, encoding: .utf8)
            for name in Self.customClassNames(in: xml) {
                checked += 1
                // Storyboards compiled inside the framework record `SynthOneCore`
                // as the module, which is what the Obj-C runtime is asked for.
                if NSClassFromString("SynthOneCore.\(name)") == nil
                    && NSClassFromString(name) == nil {
                    missing.append("\(url.lastPathComponent): \(name)")
                }
            }
        }
        XCTAssertGreaterThan(checked, 70, "found suspiciously few classes to check")
        XCTAssertTrue(missing.isEmpty, "storyboard classes that do not resolve:\n  " +
                      missing.joined(separator: "\n  "))
    }

    /// The `.storyboard` sources in the repo, which carry the `customClass`
    /// attributes. The compiled `.storyboardc` in the bundle does not.
    private func storyboardSourceURLs() throws -> [URL] {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SynthOneCore")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources,
                                                                     includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "storyboard" }
    }

    private static func customClassNames(in xml: String) -> Set<String> {
        var names = Set<String>()
        var search = xml[...]
        while let range = search.range(of: "customClass=\"") {
            let rest = search[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                names.insert(String(rest[..<end]))
                search = rest[end...]
            } else { break }
        }
        return names
    }

    /// No storyboard may **hardcode** a module that no longer exists.
    ///
    /// The distinction matters and is the whole subtlety of the P3-1 fix: entries
    /// carrying `customModuleProvider="target"` keep `customModule="AudioKitSynthOne"`
    /// in the source and are rewritten by `ibtool` to the compiling target's module.
    /// Those are correct as they stand. Only the entries *without* a provider are
    /// taken literally, and those are the eighteen that had to change.
    ///
    /// Checking the whole file for the string would demand a pointless mass edit;
    /// checking the wrong thing would let a real one back in.
    func testNoStoryboardHardcodesAForeignModule() throws {
        var offenders: [String] = []
        for url in try storyboardSourceURLs() {
            let xml = try String(contentsOf: url, encoding: .utf8)
            for element in Self.elementsWithCustomClass(in: xml)
            where !element.contains("customModuleProvider=\"target\"") {
                for stale in ["AudioKitSynthOne", "AudioKitUI", "AudioKit"]
                where element.contains("customModule=\"\(stale)\"") {
                    let name = element.components(separatedBy: "customClass=\"")
                        .dropFirst().first?.components(separatedBy: "\"").first ?? "?"
                    offenders.append("\(url.lastPathComponent): \(name) hardcodes \(stale)")
                    break
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "these would silently fail to resolve:\n  " +
                      offenders.joined(separator: "\n  "))
    }

    /// The slice of each element's attributes from `customClass=` to the closing
    /// bracket — enough to see whether a module and a provider are set on it.
    private static func elementsWithCustomClass(in xml: String) -> [String] {
        var result: [String] = []
        var search = xml[...]
        while let range = search.range(of: "customClass=\"") {
            let rest = search[range.lowerBound...]
            let end = rest.firstIndex(of: ">") ?? rest.endIndex
            result.append(String(rest[..<end]))
            search = rest[rest.index(after: range.lowerBound)...]
        }
        return result
    }

    // MARK: - Panels

    /// Every panel, instantiated by the identifier `Manager` uses, loaded and laid
    /// out. A panel that fails class resolution comes back as a bare
    /// `UIViewController` and the cast fails; one whose outlets are unconnected
    /// traps on the first implicitly-unwrapped access during `viewDidLoad`.
    func testEveryPanelLoadsAndLaysOut() throws {
        let panels: [(storyboard: String, identifier: String, type: UIViewController.Type)] = [
            ("Header",     "HeaderViewController",     HeaderViewController.self),
            ("Generators", ChildPanel.generators.identifier(), GeneratorsPanelController.self),
            ("Envelopes",  ChildPanel.envelopes.identifier(),  EnvelopesPanelController.self),
            ("Effects",    ChildPanel.effects.identifier(),    EffectsPanelController.self),
            ("Sequencer",  ChildPanel.sequencer.identifier(),  SequencerPanelController.self),
            ("TouchPad",   ChildPanel.touchPad.identifier(),   TouchPadPanelController.self),
            ("Tunings",    ChildPanel.tunings.identifier(),    TuningsPanelController.self),
            ("Presets",    "Presets",                  PresetsViewController.self),
            ("Dev",        "Dev",                      DevViewController.self),
        ]

        for panel in panels {
            let controller = storyboard(panel.storyboard)
                .instantiateViewController(withIdentifier: panel.identifier)
            XCTAssertTrue(type(of: controller) == panel.type,
                          "\(panel.storyboard)/\(panel.identifier) came back as " +
                          "\(type(of: controller)) — storyboard class resolution failed")
            realise(controller)
            XCTAssertGreaterThan(countViews(controller.view), 3,
                                 "\(panel.identifier) laid out an empty view")
        }
    }

    /// The root of the whole UI: `Main.storyboard`'s initial view controller is
    /// `Manager`, wrapped by the scaling container that makes the window resizable
    /// (P3-6b), and it embeds the header.
    func testMainStoryboardLoadsTheManager() throws {
        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer,
                                      "the root should be wrapped for resizing")
        let manager = try XCTUnwrap(container.content as? Manager,
                                    "Main.storyboard's initial view controller should be Manager")
        realise(manager)

        XCTAssertGreaterThan(countViews(manager.view), 20, "the main view is nearly empty")
        XCTAssertTrue(manager.children.contains { $0 is HeaderViewController },
                      "the header should be embedded in Main.storyboard")
        XCTAssertNotNil(manager.keyboardView, "the keyboard outlet is not connected")
    }

    /// Switching panels is how the app is actually used, and each switch loads a
    /// storyboard lazily. This is what would fail if one of the nine `Bundle.main`
    /// call sites in `Manager` had been missed.
    func testSwitchingThroughEveryChildPanel() throws {
        let manager = try XCTUnwrap((SynthOneApp.makeRootViewController() as? S1ScalingContainer)?.content as? Manager)
        realise(manager)

        for panel in [ChildPanel.generators, .envelopes, .effects, .sequencer,
                      .touchPad, .tunings] {
            manager.switchToChildPanel(panel, isOnTop: true)
            manager.view.layoutIfNeeded()
            XCTAssertTrue(manager.children.contains { $0 is PanelController },
                          "no panel on screen after switching to \(panel)")
        }
    }

    /// Not an assertion — a deliverable. Renders the assembled UI to PNGs so a
    /// person can look at what P3-1 actually produced, and so a later session can
    /// see what changed. Written to `Renders/ui/`, which is gitignored.
    ///
    /// This is a layer render, not a screenshot: no window, no display, no screen
    /// recording permission, and it runs in CI.
    func testWritesPanelScreenshots() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Renders/ui")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func write(_ view: UIView, _ name: String) throws {
            let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
            let image = renderer.image { context in
                view.layer.render(in: context.cgContext)
            }
            let data = try XCTUnwrap(image.pngData(), "\(name) produced no image data")
            try data.write(to: directory.appendingPathComponent(name + ".png"))
            XCTAssertGreaterThan(data.count, 2_000, "\(name).png looks empty")
        }

        // No `UIWindow`: under Mac Catalyst, creating one inside `xctest` throws
        // "NSApplication has not been created yet". Laying the view out directly at
        // the canvas size is enough for a layer render.
        let manager = try XCTUnwrap((SynthOneApp.makeRootViewController() as? S1ScalingContainer)?.content as? Manager)
        realise(manager)
        try write(manager.view, "00-main")

        // Three window sizes, to show the interface scaling rather than reflowing
        // (P3-6b). Same layout, same proportions, different size.
        for (name, size) in [("small", CGSize(width: 800, height: 600)),
                             ("native", S1ScalingContainer.designSize),
                             ("large", CGSize(width: 1_600, height: 1_200))] {
            let container = S1ScalingContainer(
                content: try XCTUnwrap((SynthOneApp.makeRootViewController() as? S1ScalingContainer)?.content))
            container.view.frame = CGRect(origin: .zero, size: size)
            container.view.layoutIfNeeded()
            container.content.view.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            try write(container.view, "resize-\(name)")
        }

        // Only the *top* container is switched, and never to `.sequencer`.
        //
        // Each panel is a single lazily-created view controller, so putting one on
        // top reparents its view out of the bottom container — switch the sequencer
        // to the top and the bottom half goes empty and stays empty. That is
        // upstream's behaviour, not a porting defect, but it makes for a misleading
        // screenshot: the App Store reference captures all show a panel over the
        // sequencer, which is how the app looks at launch.
        for (index, panel) in [ChildPanel.generators, .envelopes, .effects,
                               .touchPad, .tunings].enumerated() {
            manager.switchToChildPanel(panel, isOnTop: true)
            manager.switchToChildPanel(.sequencer, isOnTop: false)
            manager.view.setNeedsLayout()
            manager.view.layoutIfNeeded()
            // Let any layout-driven drawing settle before capturing.
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            try write(manager.view, String(format: "%02d-%@", index + 1, "\(panel)"))
        }

        // The sequencer on top, over the generators — the arrangement the App Store
        // reference captures use (docs/reference/appstore/ipad-04.png), so the two
        // can be put side by side.
        manager.switchToChildPanel(.sequencer, isOnTop: true)
        manager.switchToChildPanel(.generators, isOnTop: false)
        manager.view.setNeedsLayout()
        manager.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        try write(manager.view, "06-sequencer-over-generators")
        print("P3-1 UI renders: \(directory.path)")
    }
}
