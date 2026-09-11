//  P3-6b acceptance: the window resizes and the interface scales with it.
//
//  The thing being protected is that the layout never *changes* — every control
//  keeps its designed position and proportion, and only the overall size moves.
//  A relayout would strand controls, because the storyboards place everything by
//  hand at 1024×768 with no adaptive layout underneath.

import XCTest
import UIKit
@testable import SynthOneCore

final class ScalingContainerTests: XCTestCase {

    /// A stand-in for the synth UI: a fixed-size view with a control in a known
    /// place, so its position can be checked after scaling.
    private func makeContent() -> UIViewController {
        let controller = UIViewController()
        controller.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        let knob = UIView(frame: CGRect(x: 100, y: 200, width: 60, height: 60))
        knob.tag = 99
        controller.view.addSubview(knob)
        return controller
    }

    private func container(at size: CGSize) -> S1ScalingContainer {
        let container = S1ScalingContainer(content: makeContent())
        container.view.frame = CGRect(origin: .zero, size: size)
        container.view.layoutIfNeeded()
        return container
    }

    // MARK: - The window's traffic lights

    /// **Owner-reported.** `SceneDelegate` hides the title bar, so the content runs
    /// to the top edge of the window and macOS draws the close/minimise/zoom buttons
    /// *over* it — on top of the "AudioKit Synth One" label, which is the top-left of
    /// the header panel.
    ///
    /// Catalyst reports the room those buttons need as `safeAreaInsets.top`, measured
    /// at 32 points on a running build. These test `S1ScalingContainer.layout`
    /// directly rather than through a view, because a Catalyst safe area only exists
    /// inside a real window and a host-less test bundle cannot make one — a visible
    /// `UIWindow` here throws "NSApplication has not been created yet".
    func testTheInterfaceIsPlacedBelowTheWindowButtons() throws {
        let inset: CGFloat = 32
        let bounds = CGRect(x: 0, y: 0, width: 1_024, height: 768 + inset)
        let placement = try XCTUnwrap(S1ScalingContainer.layout(
            in: bounds, safeArea: UIEdgeInsets(top: inset, left: 0, bottom: 0, right: 0)))

        // Still 1:1 — the window is taller than the design by exactly the allowance.
        XCTAssertEqual(placement.scale, 1, accuracy: 0.001)
        let top = placement.center.y - S1ScalingContainer.designSize.height / 2
        XCTAssertEqual(top, inset, accuracy: 0.5, "the interface is under the window buttons")
    }

    /// Without an inset it fills the window as before, so the change is confined to
    /// the case that motivated it.
    func testNoSafeAreaMeansTheOldBehaviour() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1_024, height: 768)
        let placement = try XCTUnwrap(S1ScalingContainer.layout(in: bounds, safeArea: .zero))
        XCTAssertEqual(placement.scale, 1, accuracy: 0.001)
        XCTAssertEqual(placement.center, CGPoint(x: 512, y: 384))
    }

    /// The safe area eats into the space available for scaling, so a window that is
    /// exactly the design size now renders slightly under 1:1 rather than clipping.
    func testTheSafeAreaReducesTheScaleRatherThanCropping() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1_024, height: 768)
        let placement = try XCTUnwrap(S1ScalingContainer.layout(
            in: bounds, safeArea: UIEdgeInsets(top: 32, left: 0, bottom: 0, right: 0)))
        XCTAssertEqual(placement.scale, 736.0 / 768.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(placement.center.y - 768 * placement.scale / 2, 32 - 0.5)
    }

    /// The allowance is only used to size the window at launch, so it has to match
    /// what the system actually reserves or the interface opens under 1:1.
    func testTitlebarAllowanceMatchesTheMeasuredInset() {
        XCTAssertEqual(S1ScalingContainer.titlebarAllowance, 32)
    }

    /// The content keeps its design geometry whatever the window is doing — that is
    /// what makes the layout survive.
    func testContentKeepsItsDesignSizeAtEveryWindowSize() {
        for size in [CGSize(width: 1_024, height: 768),
                     CGSize(width: 1_600, height: 1_200),
                     CGSize(width: 700, height: 520)] {
            let container = container(at: size)
            XCTAssertEqual(container.content.view.bounds.size, S1ScalingContainer.designSize,
                           "content was resized rather than scaled at \(size)")
        }
    }

    /// Scale is `min(width, height)`, so the interface always fits and is never
    /// cropped — whichever axis is tighter wins.
    func testScaleFitsWithoutCropping() {
        let wide = container(at: CGSize(width: 2_048, height: 768))
        XCTAssertEqual(wide.content.view.transform.a, 1.0, accuracy: 0.001,
                       "height is the tighter axis here")

        let tall = container(at: CGSize(width: 1_024, height: 1_536))
        XCTAssertEqual(tall.content.view.transform.a, 1.0, accuracy: 0.001,
                       "width is the tighter axis here")

        let big = container(at: CGSize(width: 2_048, height: 1_536))
        XCTAssertEqual(big.content.view.transform.a, 2.0, accuracy: 0.001)
    }

    /// Uniform: no stretching on one axis. A knob drawn round has to stay round.
    func testScaleIsUniform() {
        let container = container(at: CGSize(width: 1_800, height: 900))
        let transform = container.content.view.transform
        XCTAssertEqual(transform.a, transform.d, accuracy: 0.000_1, "aspect was distorted")
        XCTAssertEqual(transform.b, 0, accuracy: 0.000_1)
        XCTAssertEqual(transform.c, 0, accuracy: 0.000_1)
    }

    /// Letterboxed leftovers are centred, not pinned to a corner.
    func testContentIsCentredInTheWindow() {
        let size = CGSize(width: 1_800, height: 900)
        let container = container(at: size)
        XCTAssertEqual(container.content.view.center.x, size.width / 2, accuracy: 0.5)
        XCTAssertEqual(container.content.view.center.y, size.height / 2, accuracy: 0.5)
    }

    /// Repeated layout passes — which is what a live window drag is — must not
    /// accumulate. Setting a frame while a scale transform is applied is the classic
    /// way to make a view creep, so this is the regression that matters most.
    func testRepeatedLayoutDoesNotDrift() {
        let container = container(at: CGSize(width: 1_400, height: 900))
        let firstScale = container.content.view.transform.a
        for _ in 0..<20 { container.view.layoutIfNeeded() }
        XCTAssertEqual(container.content.view.transform.a, firstScale, accuracy: 0.000_1)
        XCTAssertEqual(container.content.view.bounds.size, S1ScalingContainer.designSize)
    }

    /// A control keeps its place *within* the interface, so hit-testing lands where
    /// the control looks. Checked in window coordinates after scaling.
    func testControlsStayWhereTheyWereDesigned() throws {
        let container = container(at: CGSize(width: 2_048, height: 1_536))   // exactly 2x
        let knob = try XCTUnwrap(container.content.view.viewWithTag(99))
        let inWindow = knob.convert(knob.bounds, to: container.view)
        XCTAssertEqual(inWindow.origin.x, 200, accuracy: 1, "100pt at 2x should be 200pt")
        XCTAssertEqual(inWindow.origin.y, 400, accuracy: 1)
        XCTAssertEqual(inWindow.width, 120, accuracy: 1)
    }

    /// Below half size the labels stop being readable, so the scale floors even if
    /// something hands us a smaller window.
    func testScaleFloorsAtTheReadableMinimum() {
        let tiny = container(at: CGSize(width: 200, height: 150))
        XCTAssertEqual(tiny.content.view.transform.a,
                       S1ScalingContainer.minimumScale, accuracy: 0.001)
    }

    /// The real UI goes in the container, and the real `Manager` is still reachable
    /// through it — several tests and the AUv3 at P4-6 depend on that.
    func testRealRootIsWrappedAndReachable() throws {
        let root = SynthOneApp.makeRootViewController()
        let container = try XCTUnwrap(root as? S1ScalingContainer)
        XCTAssertTrue(container.content is Manager)
    }
}
