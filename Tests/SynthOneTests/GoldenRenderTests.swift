//  P2-4 — the regression safety net.
//
//  Twenty of Synth One's own shipped presets, rendered offline and compared
//  against committed WAVs. This is what turns "preserve functionality" from an
//  opinion into a check: after this, a DSP change that alters the sound fails a
//  test instead of being noticed months later, or never.
//
//  ADR-011 is why it exists and why it was not deferred. A wrong Soundpipe fork
//  compiled, linked, ran, and would have aliased audibly with no error anywhere.
//  Nothing short of comparing rendered audio catches that class of bug.
//
//  ## Regenerating the goldens
//
//      Scripts/write-goldens.sh
//
//  Note the `TEST_RUNNER_` prefix that script uses: `xcodebuild` does not pass the
//  shell environment through to the test runner, so a plain
//  `SYNTHONE_WRITE_GOLDENS=1` in front of `xcodebuild` is silently ignored and the
//  test just reports missing files.
//
//  Only regenerate for a change you *intend* to hear, and listen to the result
//  before committing it. The whole point is that overwriting is a deliberate act.

import XCTest
import AVFoundation
@testable import SynthOneCore

final class GoldenRenderTests: XCTestCase {

    // MARK: - The fixed rendering recipe
    //
    // Every number here is part of the golden. Changing any of them invalidates
    // all twenty files, so they are constants with reasons rather than literals
    // sprinkled through the test.

    private let sampleRate: Double = 44_100
    private let framesPerBlock: AVAudioFrameCount = 512

    /// Applied, then given time to settle before the first note (ADR-013).
    private let settle: Double = 0.75
    /// Second voice in, so polyphony and voice allocation are covered.
    private let secondNoteAt: Double = 0.4
    /// Both released here, leaving a tail that exercises release, delay and reverb.
    private let releaseAt: Double = 1.0
    private let captureSeconds: Double = 1.5

    private let firstNote: MIDINoteNumber = 57   // A3
    private let secondNote: MIDINoteNumber = 64  // E4

    /// Tolerances. Goldens are float32, so an identical build on the same machine
    /// reproduces one *exactly* — these numbers exist only for the fact that the
    /// project ships a universal binary, where arm64 and x86_64 need not agree on
    /// the last bit of every float. If a comparison ever lands between "exact" and
    /// these limits, that is worth looking at rather than shrugging at.
    private let maximumSampleDifference: Float = 1e-4
    private let maximumRelativeRMSDifference: Float = 1e-5

    private struct Golden {
        let bank: String
        let preset: String
        init(_ bank: String, _ preset: String) { self.bank = bank; self.preset = preset }

        /// Stable filename. Non-ASCII and punctuation collapse to `-`; two of the
        /// twenty names need it (a curly apostrophe and a spider).
        var filename: String {
            let slug = (bank + "__" + preset).map { character -> String in
                character.isLetter && character.isASCII || character.isNumber ? String(character) : "-"
            }.joined()
            return slug + ".wav"
        }
    }

    /// Chosen by greedy coverage over 23 sonic features across all 695 shipped
    /// presets, then spread so every one of the 13 banks contributes. Between them
    /// they cover all three filter types, both LFOs and every LFO routing in use,
    /// arp and sequencer, mono and legato, glide, detune, FM, sub, noise,
    /// bitcrush, phaser, delay, reverb, autopan and widen.
    ///
    /// The list is fixed. Adding to it is fine; changing an entry orphans a golden.
    private let goldens: [Golden] = [
        Golden("BankA", "Tentacles Arp"),
        Golden("Bonus", "Let’s Play"),
        Golden("Brice Beasley", "BB Stunned By Splendor Drone"),
        Golden("DJ Puzzle", "Dublets"),
        Golden("Electronisounds", "ARP - Tekno Con Carne"),
        Golden("Francis Preve", "Power 5th"),
        Golden("JEC", "JEC Forth of Bass 2"),
        Golden("Red Sky Lullaby", "Hold It Feeder Drone"),
        Golden("Red Sky Lullaby", "Non Arpeggiating Arp"),
        Golden("Red Sky Lullaby", "Pulsating Ultraworlds"),
        Golden("Red Sky Lullaby", "SubSonic Pad"),
        Golden("Red Sky Lullaby", "Tentacles Arp"),
        Golden("Sound of Izrael", "Mr Swing"),
        Golden("Sound of Izrael 2", "Soi ARP 12"),
        Golden("Sound of Izrael 2", "Soi ARP 29"),
        Golden("Sound of Izrael 2", "Soi Ok Balagan"),
        Golden("Spidericemidas", "🕷- Missing Time"),
        Golden("Starter Bank", "BB BASICS - Mono Bass START"),
        Golden("Starter Bank", "Init"),
        Golden("User", "Init"),
    ]

    private var goldenDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/SynthOneTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("Goldens")
    }

    private var isWriting: Bool {
        ProcessInfo.processInfo.environment["SYNTHONE_WRITE_GOLDENS"] == "1"
    }

    // MARK: - Loading presets

    private func loadBank(_ bank: String, defaults: @escaping PresetDefaults) throws -> [Preset] {
        let url = try XCTUnwrap(AKSynthOne.bundle.url(forResource: bank, withExtension: "json"),
                                "bank \(bank).json is not bundled")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let array = try XCTUnwrap(json as? [Any], "\(bank).json is not an array")
        return Preset.parseDataToPresets(jsonArray: array, defaults: defaults)
    }

    private func preset(_ golden: Golden, defaults: @escaping PresetDefaults) throws -> Preset {
        let bank = try loadBank(golden.bank, defaults: defaults)
        return try XCTUnwrap(bank.first { $0.name == golden.preset },
                             "\(golden.bank) has no preset named \(golden.preset)")
    }

    // MARK: - Rendering

    /// The recipe. A fresh synth every time, which is what makes this
    /// reproducible: `sp_create` seeds Soundpipe's RNG to 0, so even the presets
    /// with noise in them render identically as long as the kernel is new.
    private func render(_ golden: Golden) throws -> StereoRender {
        let rig = try OfflineSynth(sampleRate: sampleRate, framesPerBlock: framesPerBlock)
        let patch = try preset(golden, defaults: rig.synth.presetDefaults)
        patch.apply(to: rig.synth)

        _ = try rig.render(seconds: settle)

        var playedFirst = false, playedSecond = false, released = false
        return try rig.render(seconds: captureSeconds) { time, synth in
            if !playedFirst {
                playedFirst = true
                synth.play(noteNumber: self.firstNote, velocity: 100)
            }
            if !playedSecond && time >= self.secondNoteAt {
                playedSecond = true
                synth.play(noteNumber: self.secondNote, velocity: 100)
            }
            if !released && time >= self.releaseAt {
                released = true
                synth.stop(noteNumber: self.firstNote)
                synth.stop(noteNumber: self.secondNote)
            }
        }
    }

    private struct Difference {
        var maximum: Float = 0
        var relativeRMS: Float = 0
        var atFrame: Int = 0
        var channel = "L"
    }

    private func compare(_ rendered: StereoRender, to golden: StereoRender) -> Difference {
        var result = Difference()
        var sumSquares: Double = 0
        var goldenSquares: Double = 0
        var samples = 0

        for (name, pair) in [("L", (rendered.left, golden.left)), ("R", (rendered.right, golden.right))] {
            let (a, b) = pair
            for i in 0..<min(a.count, b.count) {
                let difference = abs(a[i] - b[i])
                if difference > result.maximum {
                    result.maximum = difference
                    result.atFrame = i
                    result.channel = name
                }
                sumSquares += Double(difference) * Double(difference)
                goldenSquares += Double(b[i]) * Double(b[i])
                samples += 1
            }
        }
        guard samples > 0, goldenSquares > 0 else { return result }
        result.relativeRMS = Float((sumSquares / goldenSquares).squareRoot())
        return result
    }

    // MARK: - Tests

    /// Every shipped preset in every shipped bank has to decode. Cheap, and it
    /// catches a preset-model regression without waiting for twenty renders.
    func testAllShippedPresetsDecode() throws {
        let rig = try OfflineSynth()
        let defaults = rig.synth.presetDefaults
        var total = 0
        let banks = Set(goldens.map(\.bank))
        XCTAssertEqual(banks.count, 13, "all thirteen banks should be represented")
        for bank in banks.sorted() {
            let presets = try loadBank(bank, defaults: defaults)
            XCTAssertFalse(presets.isEmpty, "\(bank) decoded to nothing")
            for preset in presets {
                XCTAssertFalse(preset.name.isEmpty)
                XCTAssertEqual(preset.seqPatternNote.count, 16)
                XCTAssertEqual(preset.seqNoteOn.count, 16)
                XCTAssertEqual(preset.seqOctBoost.count, 16)
            }
            total += presets.count
        }
        XCTAssertEqual(total, 695, "the shipped banks hold 695 presets between them")
    }

    /// Applying a preset must actually reach the DSP. Without this, a golden that
    /// silently rendered the *default* patch twenty times would still pass.
    func testApplyingAPresetChangesTheDSP() throws {
        let rig = try OfflineSynth()
        let patch = try preset(Golden("Starter Bank", "BB BASICS - Mono Bass START"),
                               defaults: rig.synth.presetDefaults)
        patch.apply(to: rig.synth)

        XCTAssertEqual(rig.synth.getSynthParameter(.cutoff), patch.cutoff, accuracy: 0.5)
        XCTAssertEqual(rig.synth.getSynthParameter(.masterVolume), patch.masterVolume, accuracy: 0.001)
        XCTAssertEqual(rig.synth.getSynthParameter(.index1), patch.waveform1, accuracy: 0.001)
        XCTAssertEqual(rig.synth.getSynthParameter(.morph1Volume), patch.vco1Volume, accuracy: 0.001)
        XCTAssertEqual(rig.synth.getSynthParameter(.isMono), patch.isMono, accuracy: 0.001)
    }

    /// **Determinism is the precondition for the whole suite.** Two renders of the
    /// same preset, in one process, must be bit-identical — otherwise the goldens
    /// flake and everyone learns to ignore them.
    ///
    /// It holds because each render builds a fresh `S1DSPKernel`, and `sp_create`
    /// seeds Soundpipe's RNG to zero. A preset with noise in it is as reproducible
    /// as one without.
    func testRendersAreBitIdenticalAcrossRuns() throws {
        // A patch with noise, bitcrush, delay, reverb and a sequencer — the parts
        // most likely to carry state between renders.
        let golden = Golden("JEC", "JEC Forth of Bass 2")
        let first = try render(golden)
        let second = try render(golden)

        XCTAssertEqual(first.left.count, second.left.count)
        XCTAssertGreaterThan(Signal.peak(first.left), 0.001, "a silent preset proves nothing")
        let difference = compare(first, to: second)
        XCTAssertEqual(difference.maximum, 0,
                       "two renders of the same preset must be identical, " +
                       "worst at \(difference.channel)[\(difference.atFrame)]")
    }

    /// **The P2-4 acceptance criterion.** Twenty presets against twenty committed
    /// WAVs.
    func testPresetsMatchTheirGoldens() throws {
        if isWriting {
            try FileManager.default.createDirectory(at: goldenDirectory,
                                                    withIntermediateDirectories: true)
        }
        var written = 0
        var missing: [String] = []
        var failures: [String] = []

        for golden in goldens {
            let url = goldenDirectory.appendingPathComponent(golden.filename)
            let rendered = try render(golden)

            // A golden of silence would pass every comparison forever.
            XCTAssertGreaterThan(Signal.peak(rendered.left) + Signal.peak(rendered.right), 0.001,
                                 "\(golden.bank)/\(golden.preset) rendered silence")

            if isWriting {
                try? FileManager.default.removeItem(at: url)
                try WAV.write(rendered, to: url, sampleRate: sampleRate)
                written += 1
                continue
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                missing.append(golden.filename)
                continue
            }
            let reference = try WAV.read(url)
            XCTAssertEqual(rendered.left.count, reference.left.count,
                           "\(golden.preset): golden is a different length")
            let difference = compare(rendered, to: reference)
            if difference.maximum > maximumSampleDifference
                || difference.relativeRMS > maximumRelativeRMSDifference {
                failures.append(String(format: "%@/%@ — max %.6f at %@[%d], relative RMS %.6f",
                                       golden.bank, golden.preset, difference.maximum,
                                       difference.channel, difference.atFrame,
                                       difference.relativeRMS))
            }
        }

        if isWriting {
            print("SYNTHONE_WRITE_GOLDENS: wrote \(written) goldens to \(goldenDirectory.path)")
            XCTAssertEqual(written, goldens.count)
            return
        }
        XCTAssertTrue(missing.isEmpty,
                      "no golden for: \(missing.joined(separator: ", ")). " +
                      "Generate with SYNTHONE_WRITE_GOLDENS=1.")
        XCTAssertTrue(failures.isEmpty,
                      "these presets no longer sound like their goldens:\n  " +
                      failures.joined(separator: "\n  "))
    }
}
