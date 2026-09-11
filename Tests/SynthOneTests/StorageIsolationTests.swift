//  ADR-036: the test bundle reads and writes a temporary folder, never the owner's.
//
//  Each test fails if a save escapes to `Disk.defaultSharedSupportURL` or
//  `Disk.defaultCachesURL`. They name those two, not a home path, so the revert check
//  could point them at a scratch folder: proving these fail must not write the owner's
//  files.
//
//  The "real" side is only ever read: a file's size and modification date.

import XCTest
import UIKit
@testable import SynthOneCore

final class StorageIsolationTests: XCTestCase {

    private static let started: Bool = { SynthOneApp.start(mode: .offline); return true }()
    override func setUp() { super.setUp(); _ = Self.started }

    /// The principal class has already redirected every folder by the time any test runs.
    func testDiskResolvesTheRunsTemporaryFolders() {
        XCTAssertEqual(Disk.Directory.documents.url, TestStorageIsolation.supportURL)
        XCTAssertEqual(Disk.Directory.settings.url, TestStorageIsolation.settingsURL)
        XCTAssertEqual(Disk.Directory.caches.url, TestStorageIsolation.cachesURL)
        XCTAssertFalse(Disk.Directory.settings.url.path.hasPrefix(Disk.defaultSettingsURL.path),
                       "tests are writing a product's real settings folder")
        XCTAssertFalse(Disk.Directory.documents.url.path.hasPrefix(Disk.defaultSharedSupportURL.path),
                       "tests are writing the standalone's real support folder")
        XCTAssertFalse(Disk.Directory.caches.url.path.hasPrefix(Disk.defaultCachesURL.path),
                       "tests are writing the real caches folder")
    }

    /// The writer that was found: the keyboard toggle's callback saves `AppSettings`. Since
    /// ADR-041 it lands in the settings folder, not the shared one.
    func testTheKeyboardToggleSavesSettingsIntoTheTemporaryFolder() throws {
        let saved = TestStorageIsolation.settingsURL.appendingPathComponent("settings.json")
        let sharedCopy = TestStorageIsolation.supportURL.appendingPathComponent("settings.json")
        try? FileManager.default.removeItem(at: saved)
        try? FileManager.default.removeItem(at: sharedCopy)
        let before = snapshotOfTheRealFiles()

        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        manager.loadViewIfNeeded()
        let toggle = try XCTUnwrap(manager.keyboardToggle)
        toggle.value = 0
        toggle.setValueCallback(0)

        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path),
                      "the toggle's save did not land in the run's temporary settings folder")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sharedCopy.path),
                       "settings were saved into the folder shared with the plugin")
        XCTAssertEqual(snapshotOfTheRealFiles(), before, "a save escaped to the real folders")
    }

    /// `Tunings` saves `tunings_v1.json` on a background queue once it has loaded.
    func testTuningsSaveIntoTheTemporaryFolder() {
        let saved = TestStorageIsolation.supportURL.appendingPathComponent("tunings_v1.json")
        try? FileManager.default.removeItem(at: saved)
        let before = snapshotOfTheRealFiles()

        let tunings = Tunings()
        let loaded = expectation(description: "tunings loaded")
        tunings.loadTunings { loaded.fulfill() }
        wait(for: [loaded], timeout: 10)
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: saved.path) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path),
                      "the tunings save did not land in the run's temporary folder")
        XCTAssertEqual(snapshotOfTheRealFiles(), before, "a save escaped to the real folders")
    }

    /// The presets panel saves its active preset to `.caches` (`createActivePreset`).
    func testCachesSavesIntoTheTemporaryFolder() throws {
        let before = snapshotOfTheRealFiles()
        try Disk.save(Preset(position: 0), to: .caches, as: "currentPreset.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            TestStorageIsolation.cachesURL.appendingPathComponent("currentPreset.json").path))
        XCTAssertEqual(snapshotOfTheRealFiles(), before, "a save escaped to the real folders")
    }

    /// Size and modification date of everything in the real shared, old and settings folders,
    /// and of the files Synth One writes into the real caches folder. Absent files are left
    /// out.
    private func snapshotOfTheRealFiles() -> [String: String] {
        let manager = FileManager.default
        let folders = Set([Disk.defaultSharedSupportURL, Disk.legacySharedSupportURL, Disk.defaultSettingsURL])
        var files = folders.flatMap {
            (try? manager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }
        files += ["currentPreset.json", "tmp/presetcopy.json"]
            .map { Disk.defaultCachesURL.appendingPathComponent($0) }
        var snapshot: [String: String] = [:]
        for url in files {
            guard let attributes = try? manager.attributesOfItem(atPath: url.path) else { continue }
            let size = attributes[.size] as? Int ?? -1
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            snapshot[url.path] = "\(size) \(modified)"
        }
        return snapshot
    }
}
