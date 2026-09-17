//  P7 acceptance: a skin changes how the desktop layout looks and nothing about where
//  anything sits (ADR-046).
//
//  Every skin is built over the real `Manager` at the design size. What is checked is the
//  contract: Studio is the 0.2.0 palette and hangs no art; Neon Ruins (P7-4, ADR-048) hangs its
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
        S1Preferences.store.removeObject(forKey: S1SkinChoice.defaultsKey)
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

    func testStudioIsTheDefaultAndTheChoiceRoundTrips() {
        XCTAssertEqual(S1SkinChoice.chosen, .studio)
        S1SkinChoice.choose(.neonRuins)
        XCTAssertEqual(S1SkinChoice.chosen, .neonRuins)
        XCTAssertEqual(S1SkinChoice.neonRuins.makeSkin().choice, .neonRuins)
        // A default naming a skin that no longer exists — "arcade" on an owner's machine — opens Studio
        S1Preferences.store.set("arcade", forKey: S1SkinChoice.defaultsKey)
        XCTAssertEqual(S1SkinChoice.chosen, .studio, "a dropped skin falls back, it does not crash")
        S1Preferences.store.set("no such skin", forKey: S1SkinChoice.defaultsKey)
        XCTAssertEqual(S1SkinChoice.chosen, .studio, "an unknown value means Studio")
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

    // MARK: - Neon Ruins (P7-4, ADR-048)

    func testNeonRuinsGivesEverySectionItsOwnAccentAndTheControlsFollow() throws {
        let (manager, layout) = try makeDesktop(skin: S1NeonRuinsSkin())
        XCTAssertEqual(layout.skin.choice, .neonRuins)
        XCTAssertTrue(layout.toolbarArt is S1NeonRuinsHeaderArt)
        XCTAssertTrue(layout.panelArt is S1NeonRuinsPanelArt)
        XCTAssertTrue(layout.backdropArt is S1NeonRuinsBackdropArt)
        XCTAssertTrue(layout.wordmark is S1NeonRuinsWordmark)
        XCTAssertEqual(layout.backdropArt?.bounds.size, layout.root.bounds.size, "the backdrop covers the window")
        XCTAssertEqual(layout.root.subviews.first, layout.backdropArt, "and sits under everything")
        XCTAssertEqual(layout.wordmark?.bounds.size, S1NeonRuinsSkin().dress.wordmarkSize)
        XCTAssertEqual(views(of: S1CRTFrame.self, under: manager.view).count, 4)

        // Every section has an accent; the border and the glow are that accent
        XCTAssertEqual(layout.sections.count, S1NeonRuinsSkin.accents.count)
        for (name, section) in layout.sections {
            let accent = try XCTUnwrap(section.accent, "\(name) has an accent")
            XCTAssertEqual(accent, S1NeonRuinsSkin.accents[name], name)
            XCTAssertEqual(section.layer.shadowColor.map { UIColor(cgColor: $0) }, accent, "\(name) glows in its accent")
            XCTAssertEqual(section.layer.shadowOffset, .zero, name)
        }
        // The owner's pairings: Mix is mint like Delay; the filter and its envelope share pink
        XCTAssertEqual(layout.sections["Mix"]?.accent, S1NeonRuinsSkin.mint)
        XCTAssertEqual(layout.sections["Delay"]?.accent, S1NeonRuinsSkin.mint)
        XCTAssertEqual(layout.sections["Filter"]?.accent, S1NeonRuinsSkin.pink)
        XCTAssertEqual(layout.sections["Filter Envelope"]?.accent, S1NeonRuinsSkin.pink)
        XCTAssertEqual(layout.sections["Sequencer"]?.accent, S1NeonRuinsSkin.orange)
        XCTAssertEqual(layout.sections["Pads"]?.accent, S1NeonRuinsSkin.cyan)
        XCTAssertNotEqual(Set(S1NeonRuinsSkin.accents.values).count, 1, "more than one colour")

        // A control finds its section's accent through the view tree; one outside keeps the palette's
        let mixKnob = try XCTUnwrap(views(of: Knob.self, under: try XCTUnwrap(layout.sections["Mix"])).first)
        XCTAssertEqual(mixKnob.s1Accent, S1NeonRuinsSkin.mint)
        let padsKnobs = views(of: Knob.self, under: try XCTUnwrap(layout.sections["Pads"]))
        XCTAssertTrue(padsKnobs.isEmpty)
        let voiceSwitch = try XCTUnwrap(views(of: ToggleButton.self, under: try XCTUnwrap(layout.sections["Voice"])).first)
        XCTAssertEqual(voiceSwitch.s1Accent, S1NeonRuinsSkin.violet)
        XCTAssertEqual(layout.toolbar.s1Accent, S1DesktopTheme.orange, "the toolbar is not in a section")
        XCTAssertEqual(layout.wordmark?.s1Accent, S1NeonRuinsSkin.orange)

        // The dress
        let dress = S1NeonRuinsSkin().dress
        XCTAssertEqual(dress.sectionBorderWidth, 2)
        XCTAssertTrue(dress.litFromAccent)
        XCTAssertTrue(dress.knobHalo)
        XCTAssertGreaterThan(S1NeonRuinsSkin().glow, S1StudioSkin().glow)
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
        pickers.select(S1SkinChoice.neonRuins)   // still settable through the API; the control dims
        XCTAssertEqual(S1SkinChoice.chosen, .neonRuins)
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

    func testTheNeonRuinsArtDrawsAndTheWordmarkIsTheOwnersArtwork() throws {
        for (view, size) in [(S1NeonRuinsHeaderArt(frame: .zero), CGSize(width: 1_440, height: 48)),
                             (S1NeonRuinsPanelArt(frame: .zero), CGSize(width: 380, height: 720)),
                             (S1NeonRuinsBackdropArt(frame: .zero), CGSize(width: 1_440, height: 900))] as [(UIView, CGSize)] {
            view.frame = CGRect(origin: .zero, size: size)
            let image = UIGraphicsImageRenderer(bounds: view.bounds).image { view.layer.render(in: $0.cgContext) }
            XCTAssertEqual(image.size, size)
            XCTAssertNotNil(image.cgImage)
        }
        XCTAssertEqual(S1NeonRuinsArt.grime.size, CGSize(width: 256, height: 256))
        XCTAssertEqual(S1SynthwaveArt.scanlines.size.height, 3, "the shared kit outlived the Arcade skin")
        XCTAssertNotNil(UIImage.synthOne(S1NeonRuinsWordmark.imageName), "the lit wordmark is an asset, generated from the owner's artwork")
        let mark = S1NeonRuinsWordmark(frame: CGRect(origin: .zero, size: S1NeonRuinsSkin().dress.wordmarkSize))
        mark.layoutIfNeeded()
        XCTAssertEqual(mark.accessibilityLabel, "Arcade Ruins")
        XCTAssertEqual(mark.subviews.compactMap { $0 as? UIImageView }.count, 2, "the mark over its bloom")
        XCTAssertTrue(mark.subviews.compactMap { ($0 as? UIImageView)?.image }.allSatisfy { $0.size.width > $0.size.height * 8 })
    }

    func testTheChoiceListsNeonRuinsAndRoundTripsIt() {
        XCTAssertEqual(S1SkinChoice.allCases, [.studio, .neonRuins, .cabinet], "Arcade was dropped at P7-7; Cabinet came at P7-9")
        S1SkinChoice.choose(.neonRuins)
        XCTAssertEqual(S1SkinChoice.chosen, .neonRuins)
        XCTAssertEqual(S1SkinChoice.neonRuins.makeSkin().choice, .neonRuins)
        XCTAssertEqual(S1SkinChoice.neonRuins.rawValue, "neonRuins", "the launch argument and the default's value")
    }

    // MARK: - Cabinet: the owner's painted window (P7-9, ADR-059)

    func testCabinetPinsEverySectionToItsPaintedFrameAndKeepsEveryControl() throws {
        let (_, studio) = try makeDesktop(skin: S1StudioSkin())
        let studioKnobs = studio.sections.mapValues { views(of: Knob.self, under: $0).count }

        let skin = S1CabinetSkin()
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
}
