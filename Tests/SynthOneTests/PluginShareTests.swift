//  ADR-044: Share in the plugin exports through a Save dialog.
//
//  Apple's share sheet cannot be presented from a plugin: UIKit's Mac bridge places it relative to the
//  presenting view's window, and a plugin's view lives in the host's. The assertion that fails kills the
//  plugin. These check the choice both Share buttons go through. That the plugin passes
//  `conductor.isHosted` into it is one line these cannot reach: `isHosted` is only set by a real host.

import XCTest
import UIKit
@testable import SynthOneCore

final class PluginShareTests: XCTestCase {

    private var url: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginShare-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Synthwave 1974.synth1")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        try super.tearDownWithError()
    }

    /// **The crash.** The plugin must never be handed the share sheet.
    func testThePluginExportsThroughASaveDialog() throws {
        let controller = PresetsViewController.makeShareController(for: url, hosted: true)

        XCTAssertFalse(controller is UIActivityViewController, "the share sheet crashes a plugin")
        XCTAssertTrue(controller is UIDocumentPickerViewController, "the plugin should get a Save dialog")
    }

    /// The standalone has a window of its own, and keeps upstream's share sheet.
    func testTheStandaloneKeepsTheShareSheet() throws {
        let controller = PresetsViewController.makeShareController(for: url, hosted: false)

        let sheet = try XCTUnwrap(controller as? UIActivityViewController)
        XCTAssertEqual(sheet.excludedActivityTypes, [.copyToPasteboard])
    }
}
