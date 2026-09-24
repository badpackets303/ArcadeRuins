//  P7 acceptance: a skin changes how the desktop layout looks and nothing about where
//  anything sits (ADR-046).
//
//  Every skin is built over the real `Manager` at the design size. What is checked is the
//  contract: Studio is the 0.2.0 palette and hangs no art; Cabinet (P7-4, ADR-048; P7-9) hangs its
//  art, gives each section its own accent, which every control inside it draws in, and frames
//  its screens; and every section has the same frame under each skin, so a skin can never break
//  the layout tests that run under Studio. The Arcade skin was dropped at P7-7 (ADR-051).

import XCTest
import UIKit
@testable import SynthOneCore

final class SkinTests: XCTestCase {

    private static let started: Bool = {
        SynthOneApp.start(mode: .offline)
        return true
    }()

    override func setUp() {
        super.setUp()
        _ = Self.started
    }

    override func tearDown() {
        S1Skins.current = S1StudioSkin()
        // ADR-050: a scratch suite in the test bundle, never the owner's domain
        S1SkinChoice.choose(.studio)   // ADR-064: the suite's skin, not the product's default
        S1Preferences.store.removeObject(forKey: S1Layout.classicDefaultsKey)
        super.tearDown()
    }

    private func makeDesktop(skin: S1Skin) throws -> (Manager, S1DesktopLayout) {
        S1Skins.current = skin
        let manager = try XCTUnwrap(SynthOneApp.makeRootViewController(layout: .desktop) as? Manager)
        manager.view.frame = CGRect(origin: .zero, size: SynthOneApp.desktopWindowSize)
        manager.view.layoutIfNeeded()
        return (manager, try XCTUnwrap(manager.desktopLayout))
    }

    private func views<T: UIView>(of type: T.Type, under root: UIView) -> [T] {
        var found: [T] = []
        var queue: [UIView] = [root]
        while let view = queue.popLast() {
            if let match = view as? T { found.append(match) }
            queue.append(contentsOf: view.subviews)
        }
        return found
    }

    // MARK: - The choice

    func testCabinetIsTheDefaultAndTheChoiceRoundTrips() throws {
        // A suite with nothing in it and nothing registered: what a fresh install has
        let shared = S1Preferences.store
        let name = "SkinTests-default-\(UUID().uuidString)"
        S1Preferences.store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer {
            S1Preferences.store.removePersistentDomain(forName: name)
            S1Preferences.store = shared
        }
        XCTAssertEqual(S1SkinChoice.default, .cabinet, "the owner's word, 2026-09-17 (ADR-064)")
        XCTAssertEqual(S1SkinChoice.chosen, .cabinet, "nothing chosen opens Cabinet")
        S1SkinChoice.choose(.studio)
        XCTAssertEqual(S1SkinChoice.chosen, .studio, "whoever chose Studio keeps it")
        S1SkinChoice.choose(.cabinet)
        XCTAssertEqual(S1SkinChoice.chosen, .cabinet)
        XCTAssertEqual(S1SkinChoice.cabinet.makeSkin().choice, .cabinet)
        // A default naming a skin that no longer exists opens the default; it does not crash
        for stale in ["arcade", "no such skin"] {
            S1Preferences.store.set(stale, forKey: S1SkinChoice.defaultsKey)
            XCTAssertEqual(S1SkinChoice.chosen, .cabinet, stale)
        }
    }

    func testStudioIsTheShippedPalette() {
        S1Skins.current = S1StudioSkin()
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        S1DesktopTheme.orange.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.902, accuracy: 0.001)
        XCTAssertEqual(g, 0.533, accuracy: 0.001)
        XCTAssertEqual(b, 0.008, accuracy: 0.001)
        XCTAssertEqual(S1DesktopTheme.windowBackground, UIColor(hex: 0x222224))
        XCTAssertEqual(S1StudioSkin().glow, 1)
    }

    // MARK: - What each skin hangs

    func testStudioHangsNoArt() throws {
        let (manager, layout) = try makeDesktop(skin: S1StudioSkin())
        XCTAssertEqual(layout.skin.choice, .studio)
        XCTAssertNil(layout.toolbarArt)
        XCTAssertNil(layout.panelArt)
        XCTAssertTrue(layout.wordmark is UIImageView)
        XCTAssertTrue(views(of: S1CRTFrame.self, under: manager.view).isEmpty)
        let section = try XCTUnwrap(layout.sections.values.first)
        XCTAssertEqual(section.layer.shadowColor.map { UIColor(cgColor: $0) }, UIColor.black)
    }

    // MARK: - One neon per section (P7-4, ADR-048; Cabinet's since P7-10)

    func testCabinetGivesEverySectionItsOwnAccentAndTheControlsFollow() throws {
        let (manager, layout) = try makeDesktop(skin: S1CabinetSkin())
        XCTAssertEqual(layout.skin.choice, .cabinet)
        XCTAssertNil(layout.toolbarArt, "the header is the painting's")
        XCTAssertTrue(layout.panelArt is S1CabinetPanelArt)
        XCTAssertNil(layout.backdropArt)
        XCTAssertEqual(layout.root.subviews.first, layout.templateCanvas, "the painting sits under everything")
        XCTAssertEqual(views(of: S1CRTFrame.self, under: manager.view).count, 4)

        // Every section has an accent, which its controls take; the frame itself is painted
        XCTAssertEqual(layout.sections.count, S1CabinetSkin.accents.count)
        for (name, section) in layout.sections {
            let accent = try XCTUnwrap(section.accent, "\(name) has an accent")
            XCTAssertEqual(accent, S1CabinetSkin.accents[name], name)
            XCTAssertEqual(section.layer.shadowOpacity, 0, "\(name): the frame and its glow are the painting's")
        }
        // The owner's pairings: Mix is mint like Delay; the filter and its envelope share pink
        XCTAssertEqual(layout.sections["Mix"]?.accent, S1CabinetSkin.mint)
        XCTAssertEqual(layout.sections["Delay"]?.accent, S1CabinetSkin.mint)
        XCTAssertEqual(layout.sections["Filter"]?.accent, S1CabinetSkin.pink)
        XCTAssertEqual(layout.sections["Filter Envelope"]?.accent, S1CabinetSkin.pink)
        XCTAssertEqual(layout.sections["Sequencer"]?.accent, S1CabinetSkin.orange)
        XCTAssertEqual(layout.sections["Pads"]?.accent, S1CabinetSkin.cyan)
        XCTAssertNotEqual(Set(S1CabinetSkin.accents.values).count, 1, "more than one colour")

        // A control finds its section's accent through the view tree; one outside keeps the palette's
        let mixKnob = try XCTUnwrap(views(of: Knob.self, under: try XCTUnwrap(layout.sections["Mix"])).first)
        XCTAssertEqual(mixKnob.s1Accent, S1CabinetSkin.mint)
        let padsKnobs = views(of: Knob.self, under: try XCTUnwrap(layout.sections["Pads"]))
        XCTAssertTrue(padsKnobs.isEmpty)
        let voiceSwitch = try XCTUnwrap(views(of: ToggleButton.self, under: try XCTUnwrap(layout.sections["Voice"])).first)
        XCTAssertEqual(voiceSwitch.s1Accent, S1CabinetSkin.violet)
        XCTAssertEqual(layout.toolbar.s1Accent, S1DesktopTheme.orange, "the toolbar is not in a section")

        // The dress
        let dress = S1CabinetSkin().dress
        XCTAssertTrue(dress.bareSections, "the frames are the painting's")
        XCTAssertTrue(dress.litFromAccent)
        XCTAssertTrue(dress.knobHalo)
        XCTAssertGreaterThan(S1CabinetSkin().glow, S1StudioSkin().glow)
        XCTAssertEqual(S1DesktopTheme.label, .white)
    }

    func testStudioNamesNoSectionAccentAndKeepsTheDefaultDress() throws {
        for skin in [S1StudioSkin()] as [S1Skin] {
            let (_, layout) = try makeDesktop(skin: skin)
            for (name, section) in layout.sections {
                XCTAssertNil(section.accent, "\(name) under \(skin.choice)")
            }
            XCTAssertNil(layout.backdropArt)
            XCTAssertEqual(layout.wordmark?.bounds.size, CGSize(width: 120, height: 26))
            XCTAssertEqual(skin.dress.sectionBorderWidth, 1)
            XCTAssertFalse(skin.dress.litFromAccent)
            XCTAssertFalse(skin.dress.knobHalo)
            XCTAssertFalse(skin.dress.faderLitTrack)
            XCTAssertFalse(skin.dress.sectionBloom)
            XCTAssertEqual(skin.dress.knobRingScale, 1)
            XCTAssertNil(skin.palette.knobPointer)
            XCTAssertNil(skin.sectionAccent(for: "Mix"))
        }
        // Mixing: the ends and the middle (compared by component: a mix is always sRGB)
        func white(_ colour: UIColor) -> CGFloat { var w: CGFloat = 0, a: CGFloat = 0; colour.getWhite(&w, alpha: &a); return w }
        XCTAssertEqual(white(UIColor.black.mixed(with: .white, 0)), 0, accuracy: 0.001)
        XCTAssertEqual(white(UIColor.black.mixed(with: .white, 1)), 1, accuracy: 0.001)
        XCTAssertEqual(white(UIColor.black.mixed(with: .white, 0.5)), 0.5, accuracy: 0.001)
    }

    // MARK: - Choosing from Settings (P7-5, P7-6)

    /// The pickers ride in the Settings scene itself, so they are there in **both** layouts and
    /// both products — the point of P7-6: Classic must not be a one-way trip in a host.
    private func makeSettings() throws -> (MIDISettingsViewController, S1AppearanceSettings) {
        let storyboard = UIStoryboard(name: "Main", bundle: .synthOneCore)
        let settings = try XCTUnwrap(storyboard
            .instantiateViewController(withIdentifier: "MIDISettingsViewController") as? MIDISettingsViewController)
        settings.loadViewIfNeeded()
        return (settings, try XCTUnwrap(S1AppearanceSettings.installed(in: settings), "the pickers install themselves"))
    }

    /// P7-8 (ADR-052): with nothing stored, the products open classic — the owner's default.
    func testTheDefaultLayoutIsClassicAndAnExplicitNoChoosesDesktop() {
        S1Preferences.store.removeObject(forKey: S1Layout.classicDefaultsKey)
        // `TestStorageIsolation` registers classic as well; clear the registration's effect by
        // asking the same question the products ask.
        XCTAssertEqual(S1Layout.current, .classic, "unanswered is classic")
        S1Layout.setCurrent(.desktop)
        XCTAssertEqual(S1Layout.current, .desktop, "an explicit NO is the desktop layout")
        S1Layout.setCurrent(.classic)
        XCTAssertEqual(S1Layout.current, .classic)
        S1Preferences.store.removeObject(forKey: S1Layout.classicDefaultsKey)
    }

    func testSettingsCarriesTheLayoutAndSkinPickersWithNoDesktopLayoutInSight() throws {
        S1Layout.setCurrent(.desktop)
        let (settings, pickers) = try makeSettings()
        XCTAssertEqual(pickers.selectedLayout, .desktop, "it opens on the layout in use")
        XCTAssertEqual(pickers.selectedSkin, .studio)
        XCTAssertTrue(pickers.skinPickerIsEnabled)

        // Choosing writes the defaults the next launch reads
        pickers.select(S1Layout.classic)
        XCTAssertEqual(S1Layout.current, .classic)
        pickers.select(S1SkinChoice.cabinet)   // still settable through the API; the control dims
        XCTAssertEqual(S1SkinChoice.chosen, .cabinet)
        pickers.select(S1Layout.desktop)
        XCTAssertEqual(S1Layout.current, .desktop)

        // Installed once, however many times the scene is prepared
        S1AppearanceSettings.install(in: settings)
        XCTAssertEqual(settings.view.subviews.filter { $0 is S1AppearanceSettings }.count, 1)

        // Inside the scene's 600×382, in the right column under the buffer note
        settings.view.frame = CGRect(x: 0, y: 0, width: 600, height: 382)
        settings.view.layoutIfNeeded()
        XCTAssertTrue(settings.view.bounds.contains(pickers.frame), "\(pickers.frame) is inside the popover")
        XCTAssertGreaterThan(pickers.frame.minX, 300, "the right column")
        XCTAssertGreaterThan(pickers.frame.minY, 230, "below the buffer note")
    }

    func testTheSkinPickerDimsUnderTheClassicLayoutAndSaysWhy() throws {
        S1Layout.setCurrent(.classic)
        let (_, pickers) = try makeSettings()
        XCTAssertEqual(pickers.selectedLayout, .classic)
        XCTAssertFalse(pickers.skinPickerIsEnabled, "skins dress the desktop layout only (ADR-046)")
        XCTAssertEqual(pickers.skinTitleString, S1AppearanceSettings.skinTitleText(skinsApply: false))
        XCTAssertTrue(try XCTUnwrap(pickers.skinTitleString).contains("DESKTOP ONLY"), "the caveat rides in the title")
        XCTAssertEqual(pickers.noteString, S1AppearanceSettings.noteText(isHosted: false), "the note stays one line")

        // Choosing Desktop lights the skin picker without a relaunch
        pickers.select(S1Layout.desktop)
        XCTAssertTrue(pickers.skinPickerIsEnabled)
        XCTAssertEqual(pickers.skinTitleString, "SKIN")
    }

    // MARK: - A skin never moves anything

    func testEverySkinLaysOutEverySectionInTheSamePlace() throws {
        let (_, studio) = try makeDesktop(skin: S1StudioSkin())
        let studioFrames = studio.sections.mapValues { $0.convert($0.bounds, to: nil) }
        // P7-9 (ADR-059): a skin with a template places the sections itself; its own test follows
        for choice in S1SkinChoice.allCases where choice != .studio && choice.makeSkin().template == nil {
            let (_, other) = try makeDesktop(skin: choice.makeSkin())
            XCTAssertEqual(Set(other.sections.keys), Set(studioFrames.keys), "\(choice)")
            for (name, section) in other.sections {
                let frame = section.convert(section.bounds, to: nil)
                let expected = try XCTUnwrap(studioFrames[name])
                XCTAssertEqual(frame.origin.x, expected.origin.x, accuracy: 0.5, "\(choice) \(name)")
                XCTAssertEqual(frame.origin.y, expected.origin.y, accuracy: 0.5, "\(choice) \(name)")
                XCTAssertEqual(frame.width, expected.width, accuracy: 0.5, "\(choice) \(name)")
                XCTAssertEqual(frame.height, expected.height, accuracy: 0.5, "\(choice) \(name)")
            }
            XCTAssertEqual(other.presetPanel.bounds.size, studio.presetPanel.bounds.size, "\(choice)")
        }
        XCTAssertEqual(S1DesktopLayout.minimumWindowSize, SynthOneApp.desktopMinimumWindowSize)
    }

    // MARK: - The art draws

    func testTheCabinetPanelArtDraws() throws {
        let view = S1CabinetPanelArt(frame: CGRect(x: 0, y: 0, width: 380, height: 720))
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { view.layer.render(in: $0.cgContext) }
        XCTAssertEqual(image.size, view.bounds.size)
        XCTAssertNotNil(image.cgImage)
        XCTAssertEqual(S1SynthwaveArt.scanlines.size.height, 3, "the shared kit outlived the Arcade skin")
    }

    func testTheChoiceListsCabinetAndAStoredNeonRuinsOpensIt() {
        XCTAssertEqual(S1SkinChoice.allCases, [.studio, .cabinet, .darkArcade], "Arcade went at P7-7; Cabinet replaced Neon Ruins at P7-10; Dark Arcade 2026-09-24")
        // Dark Arcade is measured here for the plugin and not offered by Classic, which stays as it shipped
        XCTAssertEqual(S1SkinChoice.offered, [.studio, .cabinet])
        S1Preferences.store.set("darkArcade", forKey: S1SkinChoice.defaultsKey)
        XCTAssertEqual(S1SkinChoice.chosen, S1SkinChoice.default, "Classic never opens in a skin it does not list")
        S1SkinChoice.choose(.cabinet)
        XCTAssertEqual(S1SkinChoice.chosen, .cabinet)
        XCTAssertEqual(S1SkinChoice.cabinet.rawValue, "cabinet", "the launch argument and the default's value")
        // Whoever chose Neon Ruins under 0.3.0 or 0.4.0 gets its successor, not Studio
        S1Preferences.store.set("neonRuins", forKey: S1SkinChoice.defaultsKey)
        XCTAssertEqual(S1SkinChoice.chosen, .cabinet)
    }

    // MARK: - Cabinet: the owner's painted window (P7-9, ADR-059)

    func testCabinetPinsEverySectionToItsPaintedFrameAndKeepsEveryControl() throws {
        try assertPinsEverySectionAndKeepsEveryControl(S1CabinetSkin())
    }

    /// 2026-09-24: the plugin's calmer painting, held to everything Cabinet is.
    func testDarkArcadePinsEverySectionToItsPaintedFrameAndKeepsEveryControl() throws {
        try assertPinsEverySectionAndKeepsEveryControl(S1DarkArcadeSkin())
        let template = try XCTUnwrap(S1DarkArcadeSkin().template)
        XCTAssertNil(template.scope, "no painted screen")
        XCTAssertNil(template.joystick)
        XCTAssertNil(template.power)
    }

    private func assertPinsEverySectionAndKeepsEveryControl(_ skin: S1Skin, file: StaticString = #filePath, line line_: UInt = #line) throws {
        let (_, studio) = try makeDesktop(skin: S1StudioSkin())
        let studioKnobs = studio.sections.mapValues { views(of: Knob.self, under: $0).count }

        let template = try XCTUnwrap(skin.template)
        XCTAssertNotNil(UIImage.synthOne(template.imageName), "the painting is an asset, generated from the owner's template")
        let (manager, layout) = try makeDesktop(skin: skin)
        let canvas = try XCTUnwrap(layout.templateCanvas)
        XCTAssertEqual(canvas.frame, manager.view.bounds)
        XCTAssertEqual(Set(template.sections.keys), Set(layout.sections.keys), "a frame for every section, and no other")

        let scale = CGPoint(x: canvas.bounds.width / template.size.width, y: canvas.bounds.height / template.size.height)
        for (name, section) in layout.sections {
            let painted = try XCTUnwrap(template.sections[name])
            let frame = section.convert(section.bounds, to: canvas)
            XCTAssertEqual(frame.minX, painted.minX * scale.x, accuracy: 1, name)
            XCTAssertEqual(frame.minY, painted.minY * scale.y, accuracy: 1, name)
            XCTAssertEqual(frame.width, painted.width * scale.x, accuracy: 1, name)
            XCTAssertEqual(frame.height, painted.height * scale.y, accuracy: 1, name)
            XCTAssertEqual(views(of: Knob.self, under: section).count, studioKnobs[name], "\(name) keeps its knobs")
            XCTAssertEqual(section.titleLabel.alpha, 0, "the title is the painting's")
            // Nothing a section holds may be squeezed out of its painted frame
            for knob in views(of: Knob.self, under: section) {
                XCTAssertTrue(section.bounds.insetBy(dx: -0.5, dy: -0.5).contains(knob.convert(knob.bounds, to: section)), "\(name)")
                XCTAssertGreaterThan(knob.bounds.width, 20, name)
            }
            // …nor a knob's title and value lines: Dark Arcade's shorter top row first SQUEEZED
            // them — a value line 2 points tall, inside the frame and unreadable — while every
            // knob still fitted (2026-09-24). So: each keeps the height its text needs.
            for cell in views(of: S1ControlCell.self, under: section) {
                for text in [cell.titleLabel, cell.valueLabel] where !text.isHidden && text.superview != nil {
                    XCTAssertTrue(section.bounds.insetBy(dx: -0.5, dy: -0.5).contains(text.convert(text.bounds, to: section)),
                                  "\(name): \(cell.titleLabel.text ?? "?") \(text === cell.titleLabel ? "title" : "value") inside", file: file, line: line_)
                    XCTAssertGreaterThanOrEqual(text.bounds.height, text.font.lineHeight - 0.5,
                                                "\(name): \(cell.titleLabel.text ?? "?") \(text === cell.titleLabel ? "title" : "value") squeezed", file: file, line: line_)
                }
            }
        }
        XCTAssertTrue(layout.toolbar.isHidden)
        XCTAssertTrue(layout.editor.isHidden)
        XCTAssertTrue(layout.presetField.isDescendant(of: canvas), "the preset name sits in the painted display")
        let labels = Set(views(of: S1ActionButton.self, under: canvas).compactMap(\.accessibilityLabel))
        XCTAssertTrue(labels.isSuperset(of: ["Save", "Panic", "Settings", "Presets", "Previous preset", "Next preset", "About Arcade Ruins"]))
    }

    func testTheCabinetPresetsButtonDropsTheBrowser() throws {
        let (_, layout) = try makeDesktop(skin: S1CabinetSkin())
        let canvas = try XCTUnwrap(layout.templateCanvas)
        let presets = try XCTUnwrap(views(of: S1ActionButton.self, under: canvas).first { $0.accessibilityLabel == "Presets" && $0 !== layout.presetFieldButton })
        XCTAssertFalse(layout.isPresetPanelVisible)
        presets.action?()
        XCTAssertTrue(layout.isPresetPanelVisible)
    }

    // MARK: - The joystick (P7-11, ADR-061)

    func testTheCabinetJoystickIsTheModWheelAndThePitchWheelAndSpringsBack() throws {
        let (manager, layout) = try makeDesktop(skin: S1CabinetSkin())
        let stick = try XCTUnwrap(layout.joystick)
        let canvas = try XCTUnwrap(layout.templateCanvas)
        XCTAssertTrue(stick.isDescendant(of: canvas))
        XCTAssertNotNil(UIImage.synthOne("s1_template_joystick_ball"), "the sprites are cut from the owner's painting")
        XCTAssertNotNil(UIImage.synthOne("s1_template_joystick_rod"))
        XCTAssertEqual(stick.accessibilityLabel, "Joystick")

        // Pushed all the way up: the mod wheel at the top, the pitch untouched inside the dead zone
        manager.modWheelPad.setVerticalValue01(0.25)
        manager.pitchBend.setVerticalValue01(0.5)   // where the wheel rests once it has appeared
        stick.onGrab()
        stick.drag(by: CGPoint(x: 3, y: -S1CabinetJoystick.travel))
        XCTAssertEqual(manager.modWheelPad.verticalValue, 1, accuracy: 0.001)
        XCTAssertEqual(manager.pitchBend.verticalValue, 0.5, accuracy: 0.001)
        // Nothing stretches (owner, 2026-09-17): the ball slides up the rod, and the rod only leans
        XCTAssertLessThan(stick.ballTransform.ty, 0, "pushed away, the ball rides up")
        XCTAssertEqual(stick.ballTransform.a, 1); XCTAssertEqual(stick.ballTransform.d, 1)

        // Halfway up is halfway from where the wheel rested to the top
        stick.drag(by: CGPoint(x: 0, y: -S1CabinetJoystick.travel / 2))
        XCTAssertEqual(manager.modWheelPad.verticalValue, 0.625, accuracy: 0.001)

        // Leaned right bends up, left bends down; pulled down is not a push
        stick.drag(by: CGPoint(x: S1CabinetJoystick.travel, y: 20))
        XCTAssertGreaterThan(stick.ballTransform.ty, 0, "pulled forward, the ball comes down over the rod")
        let lean = stick.stickTransform
        XCTAssertEqual(lean.a * lean.d - lean.b * lean.c, 1, accuracy: 0.000_1, "a rotation: no scale in it")
        XCTAssertEqual(manager.pitchBend.verticalValue, 1, accuracy: 0.001)
        XCTAssertEqual(manager.modWheelPad.verticalValue, 0.25, accuracy: 0.001)
        stick.drag(by: CGPoint(x: -S1CabinetJoystick.travel, y: 0))
        XCTAssertEqual(manager.pitchBend.verticalValue, 0, accuracy: 0.001)

        // Let go: the bend centres and the mod wheel is back where the preset had it
        stick.release()
        XCTAssertEqual(manager.pitchBend.verticalValue, 0.5, accuracy: 0.001)
        XCTAssertEqual(manager.modWheelPad.verticalValue, 0.25, accuracy: 0.001)
        XCTAssertEqual(stick.push, 0)
    }

    func testOnlyATemplateWithAJoystickHasOne() throws {
        let (_, studio) = try makeDesktop(skin: S1StudioSkin())
        XCTAssertNil(studio.joystick)
    }

    // MARK: - Power (P7-12, ADR-062)

    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private func isGrey(_ colour: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard colour.getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        return abs(r - g) < 0.002 && abs(g - b) < 0.002
    }

    func testTheLeftRedButtonFlickersEveryZoneDarkInEightSecondsAndTheRightBringsThemBack() throws {
        let (manager, layout) = try makeDesktop(skin: S1CabinetSkin())
        let power = try XCTUnwrap(layout.power)
        let canvas = try XCTUnwrap(layout.templateCanvas)
        XCTAssertEqual(power.zones.count, layout.sections.count + 4, "every section, and the display, buttons, screen and bar")
        let labels = Set(views(of: S1ActionButton.self, under: canvas).compactMap(\.accessibilityLabel))
        XCTAssertTrue(labels.isSuperset(of: ["Cut the power", "Restore the power"]))

        var scheduled: [(time: TimeInterval, block: () -> Void)] = []
        power.after = { scheduled.append(($0, $1)) }
        func fire() { scheduled.sorted { $0.time < $1.time }.forEach { $0.block() }; scheduled = [] }

        let mix = try XCTUnwrap(layout.sections["Mix"])
        let knob = try XCTUnwrap(views(of: Knob.self, under: mix).first)
        let readout = try XCTUnwrap(views(of: S1ControlCell.self, under: mix).first).valueLabel
        let litColour = try XCTUnwrap(readout.textColor)
        XCTAssertFalse(isGrey(litColour), "the readout is the palette's cyan while lit")

        var random = Seeded(state: 7)
        power.run(powered: false, using: &random)
        XCTAssertEqual(try XCTUnwrap(scheduled.map(\.time).max()), S1CabinetPower.cycle, accuracy: 0.001, "the last zone settles at eight seconds")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(scheduled.map(\.time).min()), 0)
        XCTAssertGreaterThan(scheduled.count, power.zones.count * 4, "each zone flickers before it settles")
        XCTAssertTrue(power.isPowered, "nothing changes until the clock runs")
        fire()
        XCTAssertTrue(power.isDark)
        XCTAssertEqual(knob.s1Accent, S1Power.deadAccent)
        XCTAssertTrue(S1DesktopStyle.unpowered, "and the style draws from the grey palette")
        XCTAssertTrue(isGrey(try XCTUnwrap(readout.textColor)))
        XCTAssertTrue(power.zones.allSatisfy { $0.cover?.isHidden == false }, "the grey painting is over every zone")
        XCTAssertEqual(manager.conductor.audioPlotter?.alpha, 0, "the scope's trace is gone")

        // Still a synth in the dark: a control moves and its readout follows; and a choice made
        // in the dark is the one lit when the power comes back
        let picker = try XCTUnwrap(layout.filterPicker)
        picker.selectedIndex = 2
        knob.value = knob.range.upperBound
        knob.valueDidChange?(knob.value)

        power.run(powered: true, using: &random)
        XCTAssertEqual(try XCTUnwrap(scheduled.map(\.time).max()), S1CabinetPower.cycle, accuracy: 0.001)
        fire()
        XCTAssertTrue(power.isPowered)
        XCTAssertEqual(knob.s1Accent, S1CabinetSkin.mint)
        XCTAssertFalse(S1DesktopStyle.unpowered)
        XCTAssertEqual(readout.textColor, litColour, "every held colour comes back exactly")
        let faces = views(of: UIButton.self, under: picker).sorted { $0.tag < $1.tag }.map { $0.backgroundColor ?? .clear }
        XCTAssertEqual(faces[0].cgColor.alpha, 0, "Low was lit when the power went; it is not now")
        XCTAssertFalse(isGrey(faces[2]), "High, chosen in the dark, is")
        XCTAssertTrue(power.zones.allSatisfy { $0.cover?.isHidden == true })
        XCTAssertEqual(manager.conductor.audioPlotter?.alpha, 1)
        XCTAssertEqual(S1Power.dark.count, 0)
    }

    func testTheOtherButtonMidCycleAbandonsWhatWasStillToCome() throws {
        let (_, layout) = try makeDesktop(skin: S1CabinetSkin())
        let power = try XCTUnwrap(layout.power)
        var scheduled: [(time: TimeInterval, block: () -> Void)] = []
        power.after = { scheduled.append(($0, $1)) }
        var random = Seeded(state: 11)
        power.run(powered: false, using: &random)
        let ordered = scheduled.sorted { $0.time < $1.time }
        ordered.prefix(ordered.count / 2).forEach { $0.block() }
        XCTAssertFalse(power.isPowered); XCTAssertFalse(power.isDark)
        let stale = Array(ordered.suffix(from: ordered.count / 2))
        scheduled = []
        power.run(powered: true, using: &random)
        (stale + scheduled).sorted { $0.time < $1.time }.forEach { $0.block() }
        XCTAssertTrue(power.isPowered, "the abandoned cycle's blocks do nothing")
    }

    func testTheGreyPaletteCoversEveryColour() {
        let palette = S1CabinetSkin().palette
        var colours = 0
        for child in Mirror(reflecting: palette.greyed()).children {
            let all: [UIColor]
            switch child.value {
            case let colour as UIColor: all = [colour]
            case let list as [UIColor]: all = list
            case let maybe as UIColor?: all = maybe.map { [$0] } ?? []
            default: XCTFail("\(child.label ?? "?") is not a colour; teach greyed() about it"); continue
            }
            colours += 1
            XCTAssertTrue(all.allSatisfy(isGrey), child.label ?? "?")
        }
        XCTAssertEqual(colours, S1Palette.colourFieldCount, "a field added to S1Palette must be added to greyed()")
    }

    func testStudioHasNoPowerButtons() throws {
        let (_, studio) = try makeDesktop(skin: S1StudioSkin())
        XCTAssertNil(studio.power)
    }
}
