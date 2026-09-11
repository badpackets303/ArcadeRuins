//  ADR-034: text inputs stay legible in both macOS appearances.
//
//  The preset and bank editors' name fields have a fixed near-white background (#F8F8F8) and no
//  text colour, so their text took the dynamic label colour — white in Dark appearance. The name
//  was white on near-white in the running app, measured at a contrast of 1.05. The rest of the
//  design uses fixed colours or dynamic ones that suit Dark, so the fix pins those two fields,
//  not the app, to Light.
//
//  The test bundle has no window (a `UIWindow` throws without `NSApplication`), so the appearance
//  is applied as a view controller override, and every check first confirms it arrived.

import XCTest
import UIKit
@testable import SynthOneCore

final class TextInputAppearanceTests: XCTestCase {

    /// Offline, for the reason given in `UILoadTests`.
    private static let started: Bool = {
        SynthOneApp.start(mode: .offline)
        return true
    }()

    override func setUp() {
        super.setUp()
        _ = Self.started
    }

    /// WCAG AA for body text.
    private let minimumContrast: CGFloat = 4.5

    /// The two scenes `Manager` is. `MacIdiomControlTests` explains why they are left out.
    private let managerScenes: Set<String> = ["ParentViewController", "iPhoneParentVC"]

    // MARK: - The sweep

    /// Every text field and text view in every storyboard scene, in Dark and in Light, against
    /// what is painted behind it. Two kinds are skipped. An input with nothing opaque behind it
    /// shows whatever it is presented over, which only the running app knows. A bordered field
    /// with no background colour is filled by UIKit to match its own text: the mailing-list email
    /// fields are those, and the mailing list cannot be opened in this port (`Private.swift`).
    func testEveryStoryboardTextInputIsLegibleInDarkAndLight() throws {
        var failures: [String] = []
        var checked: [String: Int] = [:]
        var editorFieldsChecked: Set<String> = []

        for style in [UIUserInterfaceStyle.dark, .light] {
            for (scene, controller) in try allScenes() {
                load(controller, in: style)
                XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, style,
                               "\(scene): the appearance did not reach the scene, so nothing below means anything")

                for input in inputs(in: controller.view) where !hasSystemDrawnFill(input) {
                    guard let result = contrast(of: input) else { continue }
                    checked[name(style), default: 0] += 1
                    if input === (controller as? PresetEditorViewController)?.nameTextField
                        || input === (controller as? BankEditorViewController)?.nameTextField {
                        editorFieldsChecked.insert("\(scene) \(name(style))")
                    }
                    if result.ratio < minimumContrast {
                        failures.append(String(format: "%@ %@ in %@: contrast %.2f (text %@ over %@)",
                                               scene, "\(type(of: input))", name(style), result.ratio,
                                               result.text, result.background))
                    }
                }
            }
        }

        XCTAssertGreaterThan(checked["Dark", default: 0], 20, "found suspiciously few inputs to check")
        XCTAssertEqual(checked["Dark"], checked["Light"])
        XCTAssertEqual(editorFieldsChecked, ["Presets/PresetEditorViewController Dark", "Presets/PresetEditorViewController Light",
                                             "Presets/BankEditorViewController Dark", "Presets/BankEditorViewController Light"],
                       "the sweep must reach both editors' name fields, or it proves nothing about them")
        XCTAssertEqual(failures, [], "unreadable text inputs (ADR-034)")
    }

    /// The check has to be able to fail: a light field with the system text colour, in Dark.
    func testTheCheckFlagsALightFieldWithSystemTextInDark() throws {
        let controller = UIViewController()
        let field = UITextField()
        field.backgroundColor = UIColor(red: 0.9725, green: 0.9725, blue: 0.9725, alpha: 1)
        field.text = "Probe"
        controller.view.addSubview(field)
        load(controller, in: .dark)
        XCTAssertEqual(field.traitCollection.userInterfaceStyle, .dark)

        let result = try XCTUnwrap(contrast(of: field))
        XCTAssertLessThan(result.ratio, minimumContrast)
    }

    // MARK: - The editors keep their designed look

    /// Not only legible: in Dark, each name field draws exactly what it draws in Light, the
    /// appearance Interface Builder shows and upstream's iPads were designed in.
    func testTheEditorNameFieldsLookTheSameInDarkAsInLight() throws {
        for identifier in ["PresetEditorViewController", "BankEditorViewController"] {
            var looks: [String: String] = [:]
            for style in [UIUserInterfaceStyle.dark, .light] {
                let controller = UIStoryboard(name: "Presets", bundle: .synthOneCore)
                    .instantiateViewController(withIdentifier: identifier)
                load(controller, in: style)
                XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, style)

                let field = try XCTUnwrap((controller as? PresetEditorViewController)?.nameTextField
                                          ?? (controller as? BankEditorViewController)?.nameTextField,
                                          "\(identifier) has no name field")
                let result = try XCTUnwrap(contrast(of: field))
                looks[name(style)] = "text \(result.text) over \(result.background)"
            }
            XCTAssertEqual(looks["Dark"], looks["Light"], "\(identifier)'s name field changes with the appearance")
        }
    }

    // MARK: - Helpers

    private struct RGBA {
        var r, g, b, a: CGFloat

        var hex: String {
            String(format: "#%02X%02X%02X/%.2f", Int((min(max(r, 0), 1) * 255).rounded()),
                   Int((min(max(g, 0), 1) * 255).rounded()), Int((min(max(b, 0), 1) * 255).rounded()), a)
        }

        func over(_ bottom: RGBA) -> RGBA {
            let alpha = a + bottom.a * (1 - a)
            guard alpha > 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
            func mix(_ top: CGFloat, _ under: CGFloat) -> CGFloat { (top * a + under * bottom.a * (1 - a)) / alpha }
            return RGBA(r: mix(r, bottom.r), g: mix(g, bottom.g), b: mix(b, bottom.b), a: alpha)
        }

        /// WCAG relative luminance.
        var luminance: CGFloat {
            func linear(_ c: CGFloat) -> CGFloat {
                let c = min(max(c, 0), 1)
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
    }

    private func rgba(_ color: UIColor, in traits: UITraitCollection) -> RGBA? {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.resolvedColor(with: traits).cgColor
                .converted(to: sRGB, intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 4 else { return nil }
        return RGBA(r: c[0], g: c[1], b: c[2], a: c[3])
    }

    /// The input's own background composited over its superviews' down to the first opaque one,
    /// each resolved in its own appearance. Nil when nothing behind it is opaque.
    private func background(of view: UIView) -> RGBA? {
        var layers: [RGBA] = []
        var current: UIView? = view
        while let v = current {
            if let color = v.backgroundColor, let c = rgba(color, in: v.traitCollection), c.a > 0 {
                layers.append(c)
                if c.a >= 0.999 { break }
            }
            current = v.superview
        }
        guard let bottom = layers.last, bottom.a >= 0.999 else { return nil }
        return layers.dropLast().reversed().reduce(bottom) { $1.over($0) }
    }

    /// The lowest contrast of any colour the input's text is drawn in.
    private func contrast(of input: UIView) -> (ratio: CGFloat, text: String, background: String)? {
        guard let background = background(of: input) else { return nil }
        let traits = input.traitCollection
        var colors: [UIColor]
        let attributed: NSAttributedString?
        if let field = input as? UITextField {
            colors = [field.textColor ?? .label]
            attributed = field.attributedText
        } else if let view = input as? UITextView {
            colors = [view.textColor ?? .label]
            attributed = view.attributedText
        } else {
            return nil
        }
        if let attributed, attributed.length > 0 {
            attributed.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                if let color = value as? UIColor { colors.append(color) }
            }
        }

        var worst: (ratio: CGFloat, text: String, background: String)?
        for color in colors {
            guard let text = rgba(color, in: traits) else { continue }
            let drawn = text.over(background)
            let lighter = max(drawn.luminance, background.luminance), darker = min(drawn.luminance, background.luminance)
            let ratio = (lighter + 0.05) / (darker + 0.05)
            if worst == nil || ratio < worst!.ratio { worst = (ratio, text.hex, background.hex) }
        }
        return worst
    }

    private func inputs(in view: UIView) -> [UIView] {
        ((view is UITextField || view is UITextView) ? [view] : []) + view.subviews.flatMap { inputs(in: $0) }
    }

    private func name(_ style: UIUserInterfaceStyle) -> String { style == .dark ? "Dark" : "Light" }

    /// A bordered field with no background colour of its own is filled by UIKit, in a system colour
    /// that matches its system text colour. What that fill is cannot be read from the view.
    private func hasSystemDrawnFill(_ input: UIView) -> Bool {
        guard let field = input as? UITextField else { return false }
        return field.backgroundColor == nil && field.borderStyle != .none
    }

    /// Loads the controller in `style` and lets UIKit apply it. A view takes on a new appearance at
    /// the next trait update, which the running app gets from its first layout pass. With no window
    /// here, nothing triggers one, so an override set in `viewDidLoad` — where the fix sets it — is
    /// never seen, and the test failed identically with and without the fix until this was added.
    private func load(_ controller: UIViewController, in style: UIUserInterfaceStyle) {
        controller.overrideUserInterfaceStyle = style
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        if #available(macCatalyst 17.0, *) {
            controller.view.updateTraitsIfNeeded()
        }
    }

    /// Every scene the compiled storyboards record, freshly instantiated, `Manager` aside.
    private func allScenes() throws -> [(String, UIViewController)] {
        var scenes: [(String, UIViewController)] = []
        for name in try storyboardNames() {
            let compiled = try XCTUnwrap(Bundle.synthOneCore.url(forResource: name, withExtension: "storyboardc"))
            let info = try XCTUnwrap(NSDictionary(contentsOf: compiled.appendingPathComponent("Info.plist")))
            let identifiers = try XCTUnwrap(info["UIViewControllerIdentifiersToNibNames"] as? [String: String])
            let storyboard = UIStoryboard(name: name, bundle: .synthOneCore)
            for identifier in identifiers.keys.sorted() where !(name == "Main" && managerScenes.contains(identifier)) {
                scenes.append(("\(name)/\(identifier)", storyboard.instantiateViewController(withIdentifier: identifier)))
            }
        }
        return scenes
    }

    /// The storyboard names, from the `.storyboard` sources, as `UILoadTests` finds them.
    private func storyboardNames() throws -> [String] {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SynthOneCore")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let names = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "storyboard" }
            .map { $0.deletingPathExtension().lastPathComponent }
        XCTAssertEqual(names.count, 12, "expected the twelve storyboards")
        return names.sorted()
    }
}
