//  P1-3 acceptance: the AudioKit replacements behave like the originals.
//
//  AKTuningTable is the highest-risk item in S1Support — it is ~1,000 lines of
//  ported microtonal maths that Synth One's entire Tunings panel depends on, and
//  the port needed three type-correctness fixes to compile at all. These tests
//  pin down the behaviour those fixes could have changed.

import XCTest
@testable import SynthOneCore

final class S1SupportTests: XCTestCase {

    private var repoRoot: URL {
        // Tests/SynthOneTests/<this file> -> repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - 12-tone equal temperament

    func testDefaultTuningIs12ET() {
        let tuning = AKTuningTable()

        XCTAssertEqual(tuning.frequency(forNoteNumber: 69), 440.0, accuracy: 0.01, "A4")
        XCTAssertEqual(tuning.frequency(forNoteNumber: 60), 261.625_565, accuracy: 0.01, "middle C")
        XCTAssertEqual(tuning.npo, 12)
    }

    func testOctavesDouble() {
        let tuning = AKTuningTable()
        for nn in MIDINoteNumber(24)...MIDINoteNumber(96) {
            let low = tuning.frequency(forNoteNumber: nn)
            let high = tuning.frequency(forNoteNumber: nn + 12)
            XCTAssertEqual(high, low * 2, accuracy: low * 0.001, "octave above note \(nn)")
        }
    }

    func testSemitoneRatioIsTwelfthRootOfTwo() {
        let tuning = AKTuningTable()
        let expected = pow(2.0, 1.0 / 12.0)
        for nn in MIDINoteNumber(48)...MIDINoteNumber(83) {
            let ratio = tuning.frequency(forNoteNumber: nn + 1) / tuning.frequency(forNoteNumber: nn)
            XCTAssertEqual(ratio, expected, accuracy: 0.000_1)
        }
    }

    /// Regression test for a PORT FIX. Upstream's base-class initialiser reads
    /// `exp2((noteNumber - 69) / 12)` — integer division. It does not compile on
    /// a modern Swift; had it been "fixed" by casting only the result, every note
    /// would collapse onto a handful of frequencies. See PORTING.md.
    func testBaseClassDefaultIs12ETNotIntegerDivision() {
        let base = AKTuningTableBase()
        XCTAssertEqual(base.frequency(forNoteNumber: 69), 440.0, accuracy: 0.01)
        XCTAssertEqual(base.frequency(forNoteNumber: 60), 261.625_565, accuracy: 0.01)

        // Integer division would make these two notes identical.
        XCTAssertNotEqual(base.frequency(forNoteNumber: 61),
                          base.frequency(forNoteNumber: 62), accuracy: 0.5)
    }

    // MARK: - Equal temperaments other than 12

    /// Regression test for the second PORT FIX (`Frequency(i) / npo`, Double / Int).
    func testArbitraryEqualTemperament() {
        let tuning = AKTuningTable()
        let npo = tuning.equalTemperament(notesPerOctave: 19)
        XCTAssertEqual(npo, 19)
        XCTAssertEqual(tuning.npo, 19)

        let masterSet = tuning.masterSet
        XCTAssertEqual(masterSet.count, 19)
        // Steps must be strictly ascending within the octave.
        for i in 1..<masterSet.count {
            XCTAssertGreaterThan(masterSet[i], masterSet[i - 1])
        }
        XCTAssertEqual(masterSet[0], 1.0, accuracy: 0.001)
    }

    // MARK: - Scala import

    func testScalaFileImport() throws {
        // A 5-limit just major scale in Scala .scl format.
        let scala = """
        ! just.scl
        !
        Five-limit just major
         7
        !
         9/8
         5/4
         4/3
         3/2
         5/3
         15/8
         2/1
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("s1-test-\(UUID().uuidString).scl")
        try scala.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let tuning = AKTuningTable()
        let npo = tuning.scalaFile(url.path)

        XCTAssertEqual(npo, 7, "seven degrees before the 2/1 octave")
        XCTAssertEqual(tuning.npo, 7)

        // The master set is the scale's ratios, octave-reduced and starting at 1/1.
        let masterSet = tuning.masterSet
        XCTAssertEqual(masterSet.count, 7)
        let expected: [Double] = [1.0, 9.0/8, 5.0/4, 4.0/3, 3.0/2, 5.0/3, 15.0/8]
        for (actual, want) in zip(masterSet.sorted(), expected) {
            XCTAssertEqual(actual, want, accuracy: 0.001)
        }
    }

    // MARK: - AKTable

    func testSineTableShape() {
        let table = AKTable(.sine, count: 4_096)
        XCTAssertEqual(table.count, 4_096)
        XCTAssertEqual(table.reduce(0) { max($0, abs($1)) }, 1.0, accuracy: 0.01)
        XCTAssertEqual(table[0], 0.0, accuracy: 0.01)
    }

    /// AKTable must decode Synth One's shipped band-limited wavetables, which are
    /// stored as JSON with keys `content` / `phase` / `type`. If the ported type's
    /// Codable shape drifted, every oscillator waveform would fail to load.
    func testDecodesShippedBandlimitedWavetable() throws {
        // The copy the framework actually ships, not `upstream/`: the public repository does not
        // include the upstream tree.
        let url = try XCTUnwrap(Bundle.synthOneCore.url(forResource: "sawtooth_0000", withExtension: "json"))
        let data = try Data(contentsOf: url)

        let table = try JSONDecoder().decode(AKTable.self, from: data)
        XCTAssertEqual(table.count, 4_096)
        XCTAssertEqual(table.reduce(0) { max($0, abs($1)) }, 1.0, accuracy: 0.01)
    }

    func testTableCodableRoundTrip() throws {
        let original = AKTable(.sawtooth, count: 256)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AKTable.self, from: data)
        XCTAssertEqual(decoded.count, original.count)
        for i in original.indices {
            XCTAssertEqual(decoded[i], original[i], accuracy: 0.000_01)
        }
    }
}

extension S1SupportTests {

    /// Regression for a PORT FIX at P3-1. Upstream's bounds assertion in
    /// `AKTuningTable+NorthIndianRaga` is `input.count < masterSet.count - 1`, which
    /// for the 17-degree preset reads `17 < 16` and traps. `assert` vanishes in
    /// Release, so the shipping app never saw it and every Debug build of the
    /// Tunings panel died on launch.
    func testPersian17TuningUsesAllSeventeenDegrees() {
        let tuning = AKTuningTable()
        let count = tuning.presetPersian17NorthIndian00_17()
        XCTAssertEqual(count, 17, "the 17-degree Persian tuning should install 17 degrees")

        // And the rest of the family still works, which is what the assertion was
        // meant to protect.
        XCTAssertEqual(tuning.presetPersian17NorthIndian01Kalyan(), 7)
        XCTAssertEqual(tuning.presetPersian17NorthIndian02Bilawal(), 7)
    }
}
