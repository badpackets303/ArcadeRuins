//  ADR-042: nothing pops up at launch.
//
//  Upstream counted launches and interrupted with prompts aimed at its App Store app: a
//  "please give a Great rating" alert on the 5th launch, an App Store review request every 50th,
//  the "Synth One + Share One!" card every 7th, and a push-notification request on the 9th and
//  every 75th. The owner saw the card, clipped, in the standalone and chose to remove them all.
//  The plugin counts its own launches, and Share crashes in it.
//
//  Each test runs `Manager.viewDidAppear` with a saved launch count. The test bundle has no
//  window, so nothing can really be presented: `performSegue` and `present` are replaced for the
//  test's duration and record what would have appeared.

import XCTest
import UIKit
import ObjectiveC
@testable import SynthOneCore

final class LaunchPromptTests: XCTestCase {

    /// Offline, as in `UILoadTests`: the panels read parameter ranges off the synth.
    private static let started: Bool = {
        SynthOneApp.start(mode: .offline)
        return true
    }()

    /// What the launch tried to put on screen.
    private static var shown: [String] = []

    private final class ReviewSpy: S1PlatformServices {
        var asked = 0
        func requestAppStoreReview() { asked += 1 }
        var isConnectedToInterAppHost: Bool { false }
        func interAppHostIcon(size: CGFloat) -> UIImage? { nil }
        func openInterAppHost() {}
        func registerInterAppHostStateDelegate(_ delegate: AnyObject?) {}
    }

    private var reviews: ReviewSpy!
    private var restoreImplementations: [() -> Void] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        _ = Self.started
        Self.shown = []
        reviews = ReviewSpy()
        S1PlatformServicesProvider.current = reviews

        let segue: @convention(block) (UIViewController, String, Any?) -> Void = { _, identifier, _ in
            LaunchPromptTests.shown.append("segue \(identifier)")
        }
        try replace(#selector(UIViewController.performSegue(withIdentifier:sender:)), with: segue)

        let present: @convention(block) (UIViewController, UIViewController, Bool,
                                         (@convention(block) () -> Void)?) -> Void = { _, presented, _, _ in
            let title = (presented as? UIAlertController)?.title ?? ""
            LaunchPromptTests.shown.append("\(type(of: presented)) \(title)")
        }
        try replace(#selector(UIViewController.present(_:animated:completion:)), with: present)
    }

    override func tearDownWithError() throws {
        restoreImplementations.forEach { $0() }
        restoreImplementations = []
        S1PlatformServicesProvider.current = S1NoPlatformServices()
        try? FileManager.default.removeItem(at: Disk.settingsURL.appendingPathComponent("settings.json"))
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func replace(_ selector: Selector, with block: Any) throws {
        let method = try XCTUnwrap(class_getInstanceMethod(UIViewController.self, selector))
        let original = method_getImplementation(method)
        method_setImplementation(method, imp_implementationWithBlock(block))
        restoreImplementations.append { method_setImplementation(method, original) }
    }

    /// A launch after `launches` earlier ones, as `Manager.viewDidAppear` runs it.
    private func launch(after launches: Int) throws {
        let settings = AppSettings()
        settings.launches = launches
        settings.firstRun = false
        try Disk.save(settings, to: .settings, as: "settings.json")

        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        manager.loadViewIfNeeded()
        manager.viewDidAppear(false)

        XCTAssertEqual(manager.appSettings.launches, launches + 1,
                       "the premise: the launch read the saved count")
    }

    // MARK: - Tests

    /// The premise: the recorder sees a presentation.
    func testTheRecorderSeesWhatIsPresented() {
        UIViewController().present(UIAlertController(title: "premise", message: nil, preferredStyle: .alert),
                                   animated: false)
        UIViewController().performSegue(withIdentifier: "premise", sender: nil)
        XCTAssertEqual(Self.shown, ["UIAlertController premise", "segue premise"])
    }

    func testTheFifthLaunchAsksForNoRating() throws {
        try launch(after: 5)
        XCTAssertEqual(Self.shown, [], "the launch put something on screen")
    }

    func testTheSeventhLaunchShowsNoShareCard() throws {
        try launch(after: 7)
        XCTAssertEqual(Self.shown, [], "the launch put something on screen")
    }

    func testTheFiftiethLaunchRequestsNoReview() throws {
        try launch(after: 50)
        XCTAssertEqual(reviews.asked, 0, "the launch asked for an App Store review")
        XCTAssertEqual(Self.shown, [], "the launch put something on screen")
    }
}
