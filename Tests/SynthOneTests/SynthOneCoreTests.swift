import XCTest
@testable import SynthOneCore

final class SynthOneCoreTests: XCTestCase {

    /// P1-1 acceptance: the Soundpipe + S1Support link path is real, not just declared.
    func testCoreLinksAgainstSoundpipeAndSupport() {
        XCTAssertTrue(SynthOneCore.selfTest())
    }

    func testVersionIsSet() {
        XCTAssertFalse(SynthOneCore.version.isEmpty)
    }
}
