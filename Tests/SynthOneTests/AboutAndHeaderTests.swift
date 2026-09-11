//  ADR-040: the About screen and the header, trimmed at the owner's request.
//
//  The About screen loses upstream's "World's First Free & Open-Source Pro iOS Synth" tagline
//  and the "How Synth One was made" video link, and the credits move up into the space. The
//  header loses More, which in this port only re-added the bonus presets to BankA, because the
//  mailing-list sign-up it was for is stubbed out.

import XCTest
import UIKit
@testable import SynthOneCore

final class AboutAndHeaderTests: XCTestCase {

    /// Offline, as in `UILoadTests`: the header reads the synth when it updates its label.
    private static let started: Bool = {
        SynthOneApp.start(mode: .offline)
        return true
    }()

    override func setUp() {
        super.setUp()
        _ = Self.started
    }

    private func allViews(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(allViews)
    }

    func testTheHeaderHasNoMoreButton() throws {
        let header = try XCTUnwrap(
            UIStoryboard(name: "Header", bundle: .synthOneCore)
                .instantiateViewController(withIdentifier: "HeaderViewController") as? HeaderViewController)
        header.loadViewIfNeeded()

        XCTAssertTrue(header.morePresetsButton.isHidden, "More is still in the header")
        XCTAssertFalse(header.panicButton.isHidden, "the premise: the rest of the header is there")
    }

    func testTheAboutScreenHasNoTaglineAndNoVideoLink() throws {
        let about = try XCTUnwrap(
            UIStoryboard(name: "About", bundle: .synthOneCore).instantiateInitialViewController()
                as? AboutViewController)
        about.view.frame = CGRect(x: 0, y: 0, width: 1_024, height: 768)
        about.loadViewIfNeeded()
        about.view.layoutIfNeeded()

        let views = allViews(about.view)
        let labels = views.compactMap { ($0 as? UILabel)?.text }
        let buttonTitles = views.compactMap { ($0 as? UIButton)?.title(for: .normal) }
        XCTAssertTrue(buttonTitles.contains("AudioKit Synth One (the original)"),
                      "the premise: the About screen's other links loaded")

        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("Open-Source Pro iOS Synth") },
                       "the tagline is still there")
        XCTAssertFalse(buttonTitles.contains("How Synth One was made"), "the video link is still there")

        // The credits take the space the two gave up rather than leaving a hole under the logo.
        let credits = try XCTUnwrap(about.textContainer)
        XCTAssertLessThanOrEqual(credits.frame.minY, 60, "a gap is left where the tagline and link were")
        XCTAssertEqual(credits.frame.maxY, 502, accuracy: 0.5, "the credits box should end where it did")

        // A deliverable, like `UILoadTests`' renders: the About screen as `viewDidAppear` leaves it.
        about.parentView.alpha = 1
        about.textContainer.alpha = 1
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Renders/ui")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(bounds: about.view.bounds).image { context in
            about.view.layer.render(in: context.cgContext)
        }
        try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent("07-about.png"))
    }
}
