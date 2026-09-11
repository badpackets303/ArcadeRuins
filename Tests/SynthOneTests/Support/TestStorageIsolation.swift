//  Keeps the test bundle out of the owner's real files (ADR-036).
//
//  `Disk` resolves `~/Library/Application Support/SynthOne/` against the real home
//  directory (P3-3, ADR-018), and the test bundle is not sandboxed. So any test that
//  reached a save wrote the owner's real `settings.json` and `tunings_v1.json`, and
//  `.caches` wrote `~/Library/Caches/currentPreset.json`. Loading only happens in
//  `Manager.viewDidAppear`, which no test calls, so what got saved was a fresh
//  `AppSettings`, and ADR-035's `keybedVersion` was stamped into the owner's file.
//
//  This is the bundle's principal class (`NSPrincipalClass` in project.yml). XCTest
//  creates it when the bundle loads, before any test class runs, so the redirect also
//  covers tests nobody has written yet. A per-class `setUp` would not.

import XCTest
@testable import SynthOneCore

@objc(S1TestStorageIsolation)
final class TestStorageIsolation: NSObject, XCTestObservation {

    /// One folder per run, under the temporary directory.
    static let root: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("SynthOneTests-\(UUID().uuidString)", isDirectory: true)
    static let supportURL = root.appendingPathComponent("Application Support/SynthOne", isDirectory: true)
    /// ADR-041: settings have their own folder, apart from the one shared with the plugin.
    static let settingsURL = root.appendingPathComponent("Settings", isDirectory: true)
    static let cachesURL = root.appendingPathComponent("Caches", isDirectory: true)

    override init() {
        super.init()
        Disk.sharedSupportURL = Self.supportURL
        Disk.settingsURL = Self.settingsURL
        Disk.cachesURL = Self.cachesURL
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        try? FileManager.default.removeItem(at: Self.root)
    }
}
