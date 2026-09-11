//  ADR-038: the plugin's presets when it cannot read the shared preset folder.
//
//  The sandboxed plugin can see that `~/Library/Application Support/SynthOne/banks.json`
//  exists but cannot read it (ADR-020, and measured again inside the installed plugin with
//  lldb). `Disk.exists` said yes, the load failed silently, and the plugin had no banks and no
//  presets. The list was empty, and ▶ crashed the plugin in Logic. Earlier installs had hidden
//  this by shipping a build signed by `xcodebuild test`, which Xcode gives read access to `/`.
//
//  These tests take read permission away from a file to stand in for the sandbox, inside a
//  folder of their own (the test bundle already keeps away from the owner's, ADR-036).

import XCTest
import UIKit
@testable import SynthOneCore

final class PluginPresetFallbackTests: XCTestCase {

    /// Offline, as in `UILoadTests`: the presets panel reads parameter ranges off the synth.
    private static let started: Bool = {
        SynthOneApp.start(mode: .offline)
        return true
    }()

    private var savedRoot: URL!
    private var root: URL!
    private var savedBanks: [Bank] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        _ = Self.started
        savedRoot = Disk.sharedSupportURL
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginPresetFallback-\(UUID().uuidString)", isDirectory: true)
        Disk.sharedSupportURL = root
        try Disk.prepareSharedStorage()
        savedBanks = Conductor.sharedInstance.banks
    }

    override func tearDownWithError() throws {
        Conductor.sharedInstance.banks = savedBanks
        // Give read permission back so the folder can be removed.
        for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: root.appendingPathComponent(name).path)
        }
        try? FileManager.default.removeItem(at: root)
        Disk.sharedSupportURL = savedRoot
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Writes a file into the shared folder, then takes away read permission, which is how the
    /// plugin's sandbox sees the owner's files.
    private func writeUnreadable(_ name: String) throws {
        let url = root.appendingPathComponent(name)
        try Data("[]".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
    }

    /// The real presets panel, loaded, as `Manager` builds it.
    private func makePresetsPanel() throws -> (Manager, PresetsViewController) {
        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        manager.loadViewIfNeeded()
        let presets = manager.presetsViewController
        presets.loadViewIfNeeded()
        return (manager, presets)
    }

    // MARK: - Tests

    func testAFileThatCannotBeReadDoesNotCountAsExisting() throws {
        try writeUnreadable("banks.json")
        let path = root.appendingPathComponent("banks.json").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "the premise: the file is there")
        XCTAssertFalse(FileManager.default.isReadableFile(atPath: path), "the premise: it cannot be read")

        XCTAssertFalse(Disk.exists("banks.json", in: .documents),
                       "an unreadable file sends every caller down a load that fails silently")

        try Data("[]".utf8).write(to: root.appendingPathComponent("readable.json"))
        XCTAssertTrue(Disk.exists("readable.json", in: .documents))
    }

    /// `Manager.viewDidAppear`'s load, run against a shared folder the plugin cannot read. It has
    /// to end with the factory banks and their presets, not with nothing.
    func testUnreadableSharedPresetsFallBackToTheFactoryBanks() throws {
        try writeUnreadable("banks.json")
        try writeUnreadable("BankA.json")
        let (manager, presets) = try makePresetsPanel()

        Conductor.sharedInstance.banks = []
        if Disk.exists("banks.json", in: .documents) {
            manager.loadBankSettings()
        } else {
            manager.createInitBanks()
        }
        presets.loadBanks()

        XCTAssertEqual(Conductor.sharedInstance.banks.count, initBanks.count,
                       "no banks loaded: the plugin's empty preset list")

        // Against what the bundle actually ships, not a guess. Factory BankA is BankA.json plus
        // Bonus.json since ADR-040, which is what upstream's More unlock produced.
        func bundledCount(_ bank: String) throws -> Int {
            let url = try XCTUnwrap(Bundle.synthOneCore.url(forResource: bank, withExtension: "json"))
            return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [Any]).count
        }
        let expected = try bundledCount("BankA") + bundledCount("Bonus")
        XCTAssertGreaterThan(try bundledCount("Bonus"), 0, "the premise: the bonus bank ships presets")
        XCTAssertEqual(presets.presets.filter { $0.bank == "BankA" }.count, expected,
                       "BankA's factory and bonus presets should stand in for the unreadable file")
    }

    /// **The crash in Logic**: ▶ with no presets loaded indexed an empty bank.
    func testTheArrowsDoNothingWhenTheBankIsEmpty() throws {
        let (_, presets) = try makePresetsPanel()
        presets.presets = []
        let before = presets.currentPreset

        presets.nextPreset()
        presets.previousPreset()

        XCTAssertTrue(presets.currentPreset === before)
    }
}
