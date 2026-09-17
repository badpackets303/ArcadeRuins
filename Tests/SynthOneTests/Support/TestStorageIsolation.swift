//  Keeps the test bundle out of the owner's real files and settings (ADR-036, ADR-050).
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

    /// P7-6 (ADR-050): the layout and skin choices are written through `S1Preferences.store`.
    /// `UserDefaults.standard` in the test host is the owner's real domain, so a test that chose
    /// a layout or a skin changed their settings — and one that cleaned up deleted them.
    static let preferencesSuite = "SynthOneTests-\(UUID().uuidString)"

    override init() {
        super.init()
        if let scratch = UserDefaults(suiteName: Self.preferencesSuite) {
            S1Preferences.store = scratch
        }
        // P6 (ADR-045): the suite was written against the classic layout, and most of it
        // asks `makeRootViewController()` for the scaling container that layout returns.
        // Registered, not set, so a test that reads it before choosing still sees classic.
        // ADR-064: likewise the desktop tests were written under Studio, which was the default
        // skin until Cabinet became it; `SkinTests` checks the real default on a suite of its own.
        // **Set, not registered**: a registered default is process-wide, so it would answer for the
        // empty suite that test reads too. Tests that choose a skin put Studio back, not nothing.
        S1Preferences.store.register(defaults: [S1Layout.classicDefaultsKey: true])
        S1SkinChoice.choose(.studio)
        Disk.sharedSupportURL = Self.supportURL
        Disk.settingsURL = Self.settingsURL
        Disk.cachesURL = Self.cachesURL
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        try? FileManager.default.removeItem(at: Self.root)
        UserDefaults.standard.removePersistentDomain(forName: Self.preferencesSuite)
    }
}
