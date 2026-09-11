//  P4-1 acceptance: the extension is packaged so a host can find and load it.
//
//  Most of this is guarding four-character codes. `aumu`/`ruin`/`BP03` is the
//  plugin's identity in every saved session in every DAW — change one and every
//  project that used SynthOne opens with a missing plugin. There is no migration
//  for that, so it gets a test rather than a comment.

import XCTest
import AVFoundation
@testable import SynthOneCore

final class AudioUnitPackagingTests: XCTestCase {

    private var extensionInfoPlist: [String: Any] {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/SynthOneAU/Info.plist")
            let data = try Data(contentsOf: url)
            return try XCTUnwrap(PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any])
        }
    }

    private var audioComponent: [String: Any] {
        get throws {
            let plist = try extensionInfoPlist
            let ext = try XCTUnwrap(plist["NSExtension"] as? [String: Any])
            let attributes = try XCTUnwrap(ext["NSExtensionAttributes"] as? [String: Any])
            let components = try XCTUnwrap(attributes["AudioComponents"] as? [[String: Any]])
            XCTAssertEqual(components.count, 1, "one component, or hosts see duplicates")
            return try XCTUnwrap(components.first)
        }
    }

    /// The **built** product's Info.plist, which is not the source one: Xcode
    /// derives some keys from build settings, and `UIDeviceFamily` is one of them.
    private func builtInfoPlist(_ relativePath: String) throws -> [String: Any] {
        let products = Bundle(for: type(of: self)).bundleURL.deletingLastPathComponent()
        let url = products.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any])
    }

    /// **P3-1b: the Catalyst idiom is Optimize Interface for Mac** (ADR-007).
    ///
    /// This is a one-line build setting with a whole-product consequence, and
    /// nothing about the source tree shows it — `TARGETED_DEVICE_FAMILY = "2,6"`
    /// in `project.yml` is what Xcode's General tab writes for "Optimize Interface
    /// for Mac", and the *built* plist is where it becomes visible as
    /// `UIDeviceFamily = [6]`. Drop the 6 and Catalyst silently reverts to
    /// rendering the entire iPad layout at 77%, which is a change nobody would see
    /// in a diff.
    ///
    /// The app and the extension must agree, or the plugin panel inside a host
    /// would be a different size from the standalone window.
    func testBothBundlesUseTheMacIdiom() throws {
        // The two bundles do not end up with the *same* array, which is worth
        // knowing before it looks like a bug: Xcode collapses the application's to
        // `[6]` and leaves the app extension's as `[2, 6]`. The invariant that
        // decides the idiom is the presence of 6, so that is what is asserted.
        for path in ["ArcadeRuins.app/Contents/Info.plist",
                     "ArcadeRuins.app/Contents/PlugIns/ArcadeRuinsAU.appex/Contents/Info.plist"] {
            let family = try XCTUnwrap(builtInfoPlist(path)["UIDeviceFamily"] as? [Int], path)
            XCTAssertTrue(family.contains(6),
                          "\(path): got \(family). 6 is the Mac family; without it "
                          + "Catalyst renders the whole iPad layout at 77%")
        }
        // The app's is the one measured end to end — a launched build reports
        // `UIUserInterfaceIdiom.mac` (5) rather than `.pad` (1).
        let app = try XCTUnwrap(builtInfoPlist("ArcadeRuins.app/Contents/Info.plist")["UIDeviceFamily"] as? [Int])
        XCTAssertEqual(app, [6])
    }

    /// **The plugin's identity.** A host stores these three codes in the session
    /// file; changing any of them orphans every project that used it.
    func testComponentIdentityIsStable() throws {
        let component = try audioComponent
        XCTAssertEqual(component["type"] as? String, "aumu", "music device — an instrument")
        XCTAssertEqual(component["subtype"] as? String, "ruin")
        XCTAssertEqual(component["manufacturer"] as? String, "BP03")
    }

    /// The in-process node the standalone app plays through must describe the *same*
    /// instrument as the extension, or the two drift apart.
    func testAppAndExtensionDescribeTheSameInstrument() throws {
        let component = try audioComponent
        let description = AKSynthOne.ComponentDescription

        XCTAssertEqual(description.componentType, kAudioUnitType_MusicDevice)
        XCTAssertEqual(description.componentSubType, fourCC(try XCTUnwrap(component["subtype"] as? String)))
        XCTAssertEqual(description.componentManufacturer,
                       fourCC(try XCTUnwrap(component["manufacturer"] as? String)))
    }

    /// Hosts read these to name and categorise the plugin.
    func testComponentIsDescribedForHosts() throws {
        let component = try audioComponent
        let name = try XCTUnwrap(component["name"] as? String)
        XCTAssertTrue(name.contains(":"),
                      "hosts split 'Manufacturer: Name' on the colon — got \(name)")
        XCTAssertFalse((component["description"] as? String ?? "").isEmpty)
        XCTAssertEqual(component["tags"] as? [String], ["Synthesizer"])
        XCTAssertNotNil(component["version"] as? Int)
        XCTAssertEqual(component["sandboxSafe"] as? Bool, true)
    }

    /// The extension point and principal class are what make the system load it at
    /// all. A typo here is a plugin that never appears, with no error anywhere.
    func testExtensionPointAndPrincipalClass() throws {
        let ext = try XCTUnwrap(try extensionInfoPlist["NSExtension"] as? [String: Any])
        XCTAssertEqual(ext["NSExtensionPointIdentifier"] as? String, "com.apple.AudioUnit-UI")
        XCTAssertEqual(ext["NSExtensionPrincipalClass"] as? String,
                       "ArcadeRuinsAU.SynthOneAudioUnitViewController")

        let attributes = try XCTUnwrap(ext["NSExtensionAttributes"] as? [String: Any])
        XCTAssertEqual(attributes["AudioComponentBundle"] as? String, "ArcadeRuinsAU")
    }

    /// **The extension must stay sandboxed.** Tested at P4-1 rather than assumed:
    /// with `app-sandbox: false` the system refuses to open the component at all —
    /// `auval` fails at `OpenAComponent: result: 4`. See ADR-020.
    func testExtensionIsSandboxed() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SynthOneAU/SynthOneAU.entitlements")
        let data = try Data(contentsOf: url)
        let entitlements = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any])
        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true,
                       "an unsandboxed app extension will not load on macOS")
    }

    /// What the sandbox costs and what it does not. The plugin cannot reach the
    /// app's user presets (ADR-018/ADR-020) — but the factory banks, wavetables and
    /// storyboards are framework resources and load fine, which is what makes the
    /// plugin usable anyway.
    func testFrameworkResourcesTheExtensionDependsOnArePresent() {
        let bundle = Bundle.synthOneCore
        XCTAssertNotNil(bundle.url(forResource: "BankA", withExtension: "json"),
                        "factory banks must be in the framework, not the app container")
        XCTAssertNotNil(bundle.url(forResource: "bandlimitedWaveforms", withExtension: "json"))
        XCTAssertNotNil(bundle.url(forResource: "Main", withExtension: "storyboardc"),
                        "P4-6 loads the UI from here")
    }
}
