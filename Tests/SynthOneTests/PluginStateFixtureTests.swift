//  X2-5 (ADR-076): the JUCE plugin's session state holds a preset the Mac app reads.
//
//  `Tests/Plugin/Fixtures/state-v1.json` is a version-1 state written by the plugin's macOS build
//  and read back by the plugin's tests on three OSes. Its "preset" object claims to be the
//  engine's preset JSON — the Mac app's own format (ADR-069). This holds it to that with the Mac
//  app's own two readers: the dictionary initialiser the banks load through, and `Codable`.

import XCTest
@testable import SynthOneCore

final class PluginStateFixtureTests: XCTestCase {

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Plugin/Fixtures/state-v1.json")
    }

    func testTheMacAppReadsThePresetInAPluginState() throws {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        XCTAssertEqual(root["format"] as? String, "ArcadeRuins.state")
        let dictionary = try XCTUnwrap(root["preset"] as? [String: Any])
        let parameters = try XCTUnwrap(root["parameters"] as? [String: Double])

        let rig = try OfflineSynth()
        let preset = Preset(dictionary: dictionary, defaults: rig.synth.presetDefaults)
        XCTAssertEqual(preset.name, "Nineteen — étude")
        XCTAssertEqual(preset.uid, "0F0E0D0C-0B0A-4908-8706-050403020100")
        XCTAssertEqual(preset.tuningName, "19 EDO")
        XCTAssertEqual(preset.tuningMasterSet?.count, 3)
        XCTAssertEqual(preset.modWheelRouting, 2)
        // The preset's fields are the state's parameters: a few from each corner of the list.
        XCTAssertEqual(preset.cutoff, try XCTUnwrap(parameters["cutoff"]))
        XCTAssertEqual(preset.attackDuration, try XCTUnwrap(parameters["attackDuration"]))
        XCTAssertEqual(preset.delayTime, try XCTUnwrap(parameters["delayTime"]))
        XCTAssertEqual(preset.arpRate, try XCTUnwrap(parameters["arpRate"]))
        XCTAssertEqual(preset.compressorMasterRatio, try XCTUnwrap(parameters["compressorMasterRatio"]))
        XCTAssertEqual(preset.seqPatternNote.count, 16)
        for step in 0..<16 {
            let key = String(format: "%02d", step)
            XCTAssertEqual(Double(preset.seqPatternNote[step]), try XCTUnwrap(parameters["sequencerPattern" + key]), "step \(step)")
            XCTAssertEqual(preset.seqNoteOn[step], try XCTUnwrap(parameters["sequencerNoteOn" + key]) >= 0.5, "step \(step)")
            XCTAssertEqual(preset.seqOctBoost[step], try XCTUnwrap(parameters["sequencerOctBoost" + key]) >= 0.5, "step \(step)")
        }

        // And the strict reader: every key JSONDecoder requires is there, with the type it requires.
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)
        XCTAssertEqual(decoded.name, preset.name)
        XCTAssertEqual(decoded.cutoff, preset.cutoff)
    }
}
