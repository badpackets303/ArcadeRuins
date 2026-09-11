//  ADR-035 and ADR-039: the keyboard strip.
//
//  The owner found the keyboard comically large on a big display. Shown, it covered the
//  lower panel with keys bigger than a grand piano's; hidden, it slid off the bottom of the
//  window. After trying a taller keybed and a Show/Hide that resized the window (ADR-037), they
//  chose the hidden look as the only one. The interface is upstream's 1024×768, the keyboard
//  container runs to the bottom edge so the keys are whole and 88 points tall, and there is no
//  Show/Hide. It has 4 octaves, and the keys are shaded.

import XCTest
import UIKit
@testable import SynthOneCore

final class KeybedTests: XCTestCase {

    /// Offline, as in `UILoadTests`: the panels read parameter ranges off the synth,
    /// and a real-time engine would open the hardware output (ADR-015).
    private static let started: Bool = {
        SynthOneApp.start(mode: .offline)
        return true
    }()

    override func setUp() {
        super.setUp()
        _ = Self.started
    }

    // MARK: - Helpers

    /// The real `Manager`, laid out at the design size.
    private func makeManager() throws -> Manager {
        let container = try XCTUnwrap(SynthOneApp.makeRootViewController() as? S1ScalingContainer)
        let manager = try XCTUnwrap(container.content as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: S1ScalingContainer.designSize)
        manager.loadViewIfNeeded()
        manager.view.setNeedsLayout()
        manager.view.layoutIfNeeded()
        return manager
    }

    private func frame(of view: UIView, in manager: Manager) -> CGRect {
        view.convert(view.bounds, to: manager.view)
    }

    /// The red channel of each pixel, read from a real UIKit drawing context so shadow
    /// offsets point the way they do in the app.
    private func redChannel(of view: UIView) throws -> (Int, Int) -> Int {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.draw(view.bounds)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return { x, y in Int(bytes[(y * width + x) * 4]) }
    }

    // MARK: - Geometry

    func testTheInterfaceIsUpstreamsSize() {
        XCTAssertEqual(S1ScalingContainer.designSize, CGSize(width: 1_024, height: 768))
    }

    /// Whole 88-point keys from under the toolbar to the bottom edge, where upstream showed the
    /// cut-off tops of 387-point ones. The lower panel is never covered.
    func testTheKeysAreWholeAndEndAtTheBottomEdge() throws {
        let manager = try makeManager()

        let keyboardBox = frame(of: try XCTUnwrap(manager.keyboardView.superview), in: manager)
        XCTAssertEqual(keyboardBox.minY, 636, accuracy: 0.5)
        let keys = frame(of: manager.keyboardView, in: manager)
        XCTAssertEqual(keys.minY, 680, accuracy: 0.5)
        XCTAssertEqual(keys.maxY, 768, accuracy: 0.5, "the keys should end at the bottom edge, not run past it")
        XCTAssertLessThanOrEqual(frame(of: manager.bottomContainerView, in: manager).maxY, 636.5)

        for pad in [manager.pitchBend!, manager.modWheelPad!] {
            let padFrame = frame(of: pad, in: manager)
            XCTAssertGreaterThan(padFrame.height, 30, "a wheel is too short to use")
            XCTAssertLessThanOrEqual(padFrame.maxY, 768.5, "a wheel runs past the bottom edge")
        }
        let pad = frame(of: manager.pitchBend, in: manager)
        for label in try XCTUnwrap(manager.pitchBend.superview).subviews.compactMap({ $0 as? UILabel }) {
            let labelFrame = frame(of: label, in: manager)
            XCTAssertGreaterThanOrEqual(labelFrame.minY, pad.maxY, "\(label.text ?? "") overlaps its wheel")
            XCTAssertLessThanOrEqual(labelFrame.maxY, 768.5, "\(label.text ?? "") is below the edge")
        }
    }

    /// **The owner's decision**: Show only lengthened the keys, so the toolbar has no Show/Hide.
    func testTheToolbarHasNoShowHideButton() throws {
        let manager = try makeManager()
        XCTAssertTrue(manager.keyboardToggle.isHidden, "the Show/Hide button is still on the toolbar")
    }

    // MARK: - Settings

    /// A "shown" saved by upstream, or by ADR-037's build, is ignored: there is nothing to show.
    func testASavedShownKeyboardIsIgnored() {
        let underKeybed = AppSettings(dictionary: ["showKeyboard": 1.0, "keybedVersion": 1])
        XCTAssertEqual(underKeybed.showKeyboard, 0)
        let upstream = AppSettings(dictionary: ["showKeyboard": 1.0])
        XCTAssertEqual(upstream.showKeyboard, 0)
    }

    func testANewInstallHasFourOctaves() {
        let settings = AppSettings()
        XCTAssertEqual(settings.octaveRange, 4)
        XCTAssertEqual(settings.showKeyboard, 0)
    }

    /// Settings saved before the keybed have 2 octaves. Loading them once moves them to 4 and
    /// leaves every other setting alone.
    func testSettingsSavedBeforeTheKeybedTakeFourOctaves() {
        let saved: [String: Any] = ["octaveRange": 2, "labelMode": 2, "launches": 40]
        let settings = AppSettings(dictionary: saved)
        XCTAssertEqual(settings.octaveRange, 4)
        XCTAssertEqual(settings.labelMode, 2, "only the keybed's settings should change")
        XCTAssertEqual(settings.launches, 40)
    }

    /// Only once: after that, the octave range the owner chooses is kept.
    func testAnOctaveRangeSavedUnderTheKeybedIsKept() throws {
        let settings = AppSettings()
        settings.octaveRange = 3
        let data = try JSONEncoder().encode(settings)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(AppSettings(dictionary: saved).octaveRange, 3)
    }

    /// The Keys popover offered 1 to 3. With 4 as the default, a 3-segment control would
    /// be handed an index it does not have.
    func testTheKeysPopoverOffersFourAndFiveOctaves() throws {
        let controller = try XCTUnwrap(
            UIStoryboard(name: "Main", bundle: .synthOneCore)
                .instantiateViewController(withIdentifier: "KeyboardSettingsViewController")
                as? KeyboardSettingsViewController)
        controller.octaveRange = 4
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.octaveRangeSegment.numberOfSegments, 5)
        XCTAssertEqual(controller.octaveRangeSegment.selectedSegmentIndex, 3)
        XCTAssertEqual(controller.octaveRangeSegment.titleForSegment(at: 4), "5")
    }

    // MARK: - Shading, at the keyboard's real size

    /// 4 octaves across 898 × 88 points: C♯ spans x ≈ 22–42 and ends at y ≈ 49. Just below its
    /// tip, on D, the shadow darkens the key; at the front it does not. Upstream draws both
    /// points pure white.
    func testBlackKeysCastAShadowOntoTheWhiteKeys() throws {
        let keyboard = KeyboardView(width: 898, height: 88, firstOctave: 2, octaveCount: 4)
        keyboard.labelMode = 0
        let red = try redChannel(of: keyboard)

        XCTAssertLessThan(red(36, 53), red(36, 78) - 20, "no shadow below C♯")
        XCTAssertGreaterThan(red(36, 78), 240, "the front of a white key should stay white")
    }

    /// E at x = 88 has no black key over its back, so only the shading darkens it there.
    func testWhiteKeysDarkenTowardTheBack() throws {
        let keyboard = KeyboardView(width: 898, height: 88, firstOctave: 2, octaveCount: 4)
        keyboard.labelMode = 0
        let red = try redChannel(of: keyboard)

        XCTAssertLessThan(red(88, 3), red(88, 78) - 30, "the back of the key is as bright as the front")
    }
}
