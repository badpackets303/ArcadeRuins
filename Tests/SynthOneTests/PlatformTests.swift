//  P3-2 and P3-3 acceptance.
//
//  P3-2: the iOS-only services are behind a protocol whose default implementation
//  does nothing, so the call sites upstream put in the UI stay where they are.
//
//  P3-3: presets, banks and tunings live in one shared folder outside any sandbox
//  container, and anything written into the old container before P3-3 is moved
//  across exactly once.

import XCTest
import UIKit
@testable import SynthOneCore

final class PlatformServicesTests: XCTestCase {

    override func tearDown() {
        S1PlatformServicesProvider.current = S1NoPlatformServices()
        super.tearDown()
    }

    /// The default has to be the do-nothing one — the same reasoning as the audio
    /// session (P2-2). Nothing on macOS ever replaces it.
    func testDefaultIsTheNoOpImplementation() {
        XCTAssertTrue(S1PlatformServicesProvider.current is S1NoPlatformServices)
    }

    /// Every entry point is safe to call and reports "not connected". The UI calls
    /// these unconditionally.
    func testNoOpServicesAnswerSafely() {
        let services = S1NoPlatformServices()
        services.requestAppStoreReview()
        services.openInterAppHost()
        services.registerInterAppHostStateDelegate(nil)
        XCTAssertFalse(services.isConnectedToInterAppHost)
        XCTAssertNil(services.interAppHostIcon(size: 44))
    }

    /// `requestReview()` is called from three places in the UI and must not reach
    /// StoreKit. There is no App Store listing for a locally built, ad-hoc-signed
    /// app, and upstream's fallback URL points at *AudioKit's* listing.
    func testReviewRequestGoesThroughTheProvider() {
        final class Spy: S1PlatformServices {
            var asked = 0
            func requestAppStoreReview() { asked += 1 }
            var isConnectedToInterAppHost: Bool { false }
            func interAppHostIcon(size: CGFloat) -> UIImage? { nil }
            func openInterAppHost() {}
            func registerInterAppHostStateDelegate(_ delegate: AnyObject?) {}
        }
        let spy = Spy()
        S1PlatformServicesProvider.current = spy
        UIViewController().requestReview()
        XCTAssertEqual(spy.asked, 1)
    }

    /// Upstream gates its mailing-list signup on `Private.MailChimpAPIKey` still
    /// being the placeholder they shipped. That string is load-bearing: filling it
    /// in switches the feature on. This pins it so nobody "tidies" it away.
    func testMailingListStaysDisabledByItsPlaceholderKey() {
        XCTAssertEqual(Private.MailChimpAPIKey, "***REMOVED***")
        XCTAssertEqual(Private.MailChimpID, "***REMOVED***")
    }

    /// AudioKit shipped their real Audiobus credential in this file. We do not use
    /// Audiobus and should not be carrying someone else's key.
    func testAudiobusCredentialIsNotVendored() {
        XCTAssertTrue(Private.AudioBusAPIKey.isEmpty,
                      "an Audiobus API key has come back into Private.swift")
    }
}

final class DiskTests: XCTestCase {

    private var root: URL!
    private var savedRoot: URL!

    override func setUpWithError() throws {
        // Never the real folder: these tests would otherwise write into the user's
        // actual presets.
        savedRoot = Disk.sharedSupportURL
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskTests-\(UUID().uuidString)")
        Disk.sharedSupportURL = root
        try Disk.prepareSharedStorage()
    }

    override func tearDownWithError() throws {
        Disk.sharedSupportURL = savedRoot
        try? FileManager.default.removeItem(at: root)
    }

    /// Two processes have to reach the same files, so the shared folder is never one
    /// process's sandbox container. Since ADR-041 it is the App Group's, and a process outside
    /// the group falls back to the P3-3 folder.
    func testTheSharedFolderIsNeverOneProcesssContainer() {
        let legacy = Disk.legacySharedSupportURL.path
        XCTAssertFalse(legacy.contains("/Library/Containers/"), legacy)
        XCTAssertTrue(legacy.hasSuffix("/Library/Application Support/SynthOne"), legacy)
        XCTAssertTrue(legacy.hasPrefix(Disk.realHomeURL.path), legacy)

        let shared = Disk.defaultSharedSupportURL.path
        XCTAssertFalse(shared.contains("/Library/Containers/"), shared)
        if let group = Disk.groupSupportURL {
            XCTAssertEqual(Disk.defaultSharedSupportURL, group)
            XCTAssertTrue(group.path.contains("/Library/Group Containers/\(Disk.appGroupIdentifier)/"), group.path)
        } else {
            XCTAssertEqual(Disk.defaultSharedSupportURL, Disk.legacySharedSupportURL)
        }
    }

    /// ADR-041: each product keeps its own settings. For an unsandboxed process, as the
    /// standalone is, that is the old folder, so the owner's settings stay where they are.
    func testSettingsAreKeptApartFromTheSharedFolder() {
        XCTAssertNotEqual(Disk.Directory.settings.url, Disk.Directory.documents.url)
        XCTAssertEqual(Disk.defaultSettingsURL, Disk.legacySharedSupportURL)
    }

    /// ADR-041: both products must be entitled to the group `Disk` asks for, or one of them
    /// silently falls back to a folder the other cannot see. The entitlements files are what
    /// XcodeGen writes from project.yml and the build signs in.
    func testBothProductsAreEntitledToTheGroupDiskUses() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for path in ["Sources/SynthOne/SynthOne.entitlements", "Sources/SynthOneAU/SynthOneAU.entitlements"] {
            let data = try Data(contentsOf: repo.appendingPathComponent(path))
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let groups = plist["com.apple.security.application-groups"] as? [String] ?? []
            XCTAssertTrue(groups.contains(Disk.appGroupIdentifier), "\(path) is not in \(Disk.appGroupIdentifier)")
        }
    }

    /// ADR-041: the owner's banks, presets and tunings come across once, as copies, without
    /// settings. On that one run they replace factory files a plugin may already have made
    /// in the group, and never again after that.
    func testTheOldFolderIsCopiedIntoTheGroupOnce() throws {
        let manager = FileManager.default
        let legacy = manager.temporaryDirectory.appendingPathComponent("LegacyShared-\(UUID().uuidString)")
        let group = manager.temporaryDirectory.appendingPathComponent("Group-\(UUID().uuidString)")
        try manager.createDirectory(at: legacy, withIntermediateDirectories: true)
        try manager.createDirectory(at: group, withIntermediateDirectories: true)
        defer {
            try? manager.removeItem(at: legacy)
            try? manager.removeItem(at: group)
        }
        for (name, text) in [("banks.json", "owner-banks"), ("BankA.json", "owner-bankA"),
                             ("tunings_v1.json", "owner-tunings"), ("settings.json", "owner-settings"),
                             ("notes.txt", "junk")] {
            try Data(text.utf8).write(to: legacy.appendingPathComponent(name))
        }
        // What a plugin that started first would have written: the factory bank.
        try Data("factory-bankA".utf8).write(to: group.appendingPathComponent("BankA.json"))

        XCTAssertEqual(Disk.copyLegacySharedFilesIntoGroupIfNeeded(from: legacy, to: group), 3)

        func contents(_ name: String) -> String? {
            (try? Data(contentsOf: group.appendingPathComponent(name))).map { String(decoding: $0, as: UTF8.self) }
        }
        XCTAssertEqual(contents("BankA.json"), "owner-bankA", "the owner's bank should replace the factory one")
        XCTAssertEqual(contents("banks.json"), "owner-banks")
        XCTAssertEqual(contents("tunings_v1.json"), "owner-tunings")
        XCTAssertNil(contents("settings.json"), "settings stay with each product")
        XCTAssertNil(contents("notes.txt"), "only JSON is copied")
        XCTAssertTrue(manager.fileExists(atPath: legacy.appendingPathComponent("BankA.json").path),
                      "the old folder is a backup: copy, never move")

        // Once only: later edits to the old folder, or to the group, are left alone.
        try Data("owner-bankA-later".utf8).write(to: legacy.appendingPathComponent("BankA.json"))
        try Data("saved-in-plugin".utf8).write(to: group.appendingPathComponent("banks.json"))
        XCTAssertEqual(Disk.copyLegacySharedFilesIntoGroupIfNeeded(from: legacy, to: group), 0)
        XCTAssertEqual(contents("BankA.json"), "owner-bankA")
        XCTAssertEqual(contents("banks.json"), "saved-in-plugin")
    }

    /// A process outside the group resolves the shared folder to the old one, and copies nothing.
    func testNothingIsCopiedWhenTheSharedFolderIsTheOldOne() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Same-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("x".utf8).write(to: folder.appendingPathComponent("BankA.json"))
        XCTAssertEqual(Disk.copyLegacySharedFilesIntoGroupIfNeeded(from: folder, to: folder), 0)
    }

    /// `NSHomeDirectory()` answers the container inside a sandbox, so it cannot be
    /// used to name a location outside one.
    func testRealHomeIsNotAContainer() {
        XCTAssertFalse(Disk.realHomeURL.path.contains("/Library/Containers/"))
    }

    func testCodableRoundTrip() throws {
        let preset = Preset(position: 7)
        preset.name = "Round Trip"
        try Disk.save(preset, to: .documents, as: "rt.json")
        XCTAssertTrue(Disk.exists("rt.json", in: .documents))

        let read = try Disk.retrieve("rt.json", from: .documents, as: Preset.self)
        XCTAssertEqual(read.name, "Round Trip")
        XCTAssertEqual(read.position, 7)

        try Disk.remove("rt.json", from: .documents)
        XCTAssertFalse(Disk.exists("rt.json", in: .documents))
    }

    /// The pod writes `Data` straight through rather than JSON-encoding it, and
    /// Synth One relies on that symmetry — `Manager` reads `settings.json` back as
    /// `Data` after saving a Codable.
    func testDataIsWrittenThroughUnchanged() throws {
        let payload = Data("{\"hello\":1}".utf8)
        try Disk.save(payload, to: .documents, as: "raw.json")
        XCTAssertEqual(try Disk.retrieve("raw.json", from: .documents, as: Data.self), payload)
    }

    /// Nested paths are used for the files handed to a share sheet
    /// (`tmp/presetcopy.json`), so intermediate directories have to be created.
    func testNestedPathsAreCreated() throws {
        try Disk.save(Data("x".utf8), to: .documents, as: "tmp/nested/deep.json")
        XCTAssertTrue(Disk.exists("tmp/nested/deep.json", in: .documents))
    }

    func testRemovingSomethingAbsentIsNotAnError() {
        XCTAssertNoThrow(try Disk.remove("never-existed.json", from: .documents))
    }

    func testRetrievingSomethingAbsentThrows() {
        XCTAssertThrowsError(try Disk.retrieve("absent.json", from: .documents, as: Preset.self))
    }

    /// The upgrade path. Before P3-3 the app was sandboxed and wrote into its
    /// container; without this, upgrading silently loses every user preset and
    /// tuning bank — still on disk, just somewhere nothing looks any more.
    func testMigrationMovesLegacyFilesAndPreservesNewer() throws {
        let legacy = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyDocs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: legacy) }

        try Data("old-bank".utf8).write(to: legacy.appendingPathComponent("BankA.json"))
        try Data("old-settings".utf8).write(to: legacy.appendingPathComponent("settings.json"))
        // Not a preset file — must be left alone.
        try Data("junk".utf8).write(to: legacy.appendingPathComponent("notes.txt"))
        // Already present in the shared folder: the newer copy must win.
        try Disk.save(Data("new-settings".utf8), to: .documents, as: "settings.json")

        XCTAssertEqual(Disk.migrateFromContainerIfNeeded(from: legacy), 1, "only BankA.json should move")

        XCTAssertEqual(try Disk.retrieve("BankA.json", from: .documents, as: Data.self),
                       Data("old-bank".utf8))
        XCTAssertEqual(try Disk.retrieve("settings.json", from: .documents, as: Data.self),
                       Data("new-settings".utf8), "an existing file must not be overwritten")
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            legacy.appendingPathComponent("notes.txt").path), "non-JSON must be left behind")
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            legacy.appendingPathComponent("BankA.json").path), "migrated files are moved, not copied")

        // Running it again is a no-op.
        XCTAssertEqual(Disk.migrateFromContainerIfNeeded(from: legacy), 0)
    }

    func testMigrationWithNoLegacyFolderIsANoOp() {
        let absent = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        XCTAssertEqual(Disk.migrateFromContainerIfNeeded(from: absent), 0)
    }
}
