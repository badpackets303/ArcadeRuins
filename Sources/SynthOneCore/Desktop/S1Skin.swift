//  Skins for the desktop layout (P7, ADR-046).
//
//  **New, not ported.** A skin is how the desktop layout looks, never where anything sits:
//  the palette every colour comes from, how strongly the accents glow, and a few pieces of
//  decoration the layout hangs when the skin supplies them (a wordmark, header and browser
//  art, a texture over the sections, a framed preset list). Layout, metrics, bindings and
//  tests are shared by every skin, so a control looks different under each and behaves the
//  same.
//
//  Two skins ship: **Studio**, the 0.2.0 look (dark greys, one orange), and **Cabinet** (P7-9,
//  ADR-059) — the owner's painted arcade cabinet as the window, with one neon colour per section
//  (P7-4, ADR-048) and glowing controls. A section's accent is the skin's word (`sectionAccent`);
//  every drawn control finds it through `UIView.s1Accent`, so Studio, which names none, draws
//  exactly as it did. Cabinet is also the one skin that says where sections sit (`template`).
//
//  Two others came and went at the owner's word, neither lost: **Arcade** (dropped 2026-09-14,
//  P7-7, ADR-051; `git show bf8a08a`) and **Neon Ruins** (released in 0.3.0 and 0.4.0, replaced by
//  Cabinet on 2026-09-17, P7-10, ADR-060; tag `v0.4.0`). A stored `neonRuins` opens Cabinet.
//
//  The choice is a user default, read once at launch (like `S1Layout`):
//
//      defaults write com.badpackets303.ArcadeRuins S1Skin cabinet
//
//  or `-S1Skin cabinet` as a launch argument. The plugin keeps its own container and
//  therefore its own default.

import UIKit

public enum S1SkinChoice: String, CaseIterable {

    case studio
    case cabinet
    /// 2026-09-24: the owner's calmer painted window, for the JUCE plugin (Arcade Ruins) only.
    /// It is here because the plugin's layout is MEASURED here (ADR-083); Classic does not offer
    /// it — see `offered`.
    case darkArcade

    public static let defaultsKey = "S1Skin"

    /// The skins Classic's Settings and View menu list. Dark Arcade is the plugin's alone
    /// (the owner, 2026-09-24): Classic stays at 0.5 as it shipped.
    public static let offered: [S1SkinChoice] = [.studio, .cabinet]

    /// The skin the desktop layout opens with when none has been chosen: Cabinet, at the owner's
    /// word (2026-09-17, ADR-064). It was Studio through 0.5.0.
    public static let `default` = S1SkinChoice.cabinet

    /// The skin the products open with. Absent or unknown means the default; an explicit
    /// `studio` — anyone who chose it — stays Studio.
    public static var chosen: S1SkinChoice {
        let stored = S1Preferences.store.string(forKey: defaultsKey) ?? ""
        // P7-10 (ADR-060): Cabinet replaced Neon Ruins, so whoever chose that gets its successor
        if stored == "neonRuins" { return .cabinet }
        guard let choice = S1SkinChoice(rawValue: stored), offered.contains(choice) else { return .default }
        return choice
    }

    /// Remembered for the next launch; the running interface does not change.
    public static func choose(_ choice: S1SkinChoice) {
        S1Preferences.store.set(choice.rawValue, forKey: defaultsKey)
    }

    public var title: String {
        switch self {
        case .studio: return NSLocalizedString("Studio", comment: "Skin name")
        case .cabinet: return NSLocalizedString("Cabinet", comment: "Skin name")
        case .darkArcade: return NSLocalizedString("Dark Arcade", comment: "Skin name")
        }
    }

    func makeSkin() -> S1Skin {
        switch self {
        case .studio: return S1StudioSkin()
        case .cabinet: return S1CabinetSkin()
        case .darkArcade: return S1DarkArcadeSkin()
        }
    }
}

/// The skin in use. Set from the default at first use; tests set it directly and put it back.
enum S1Skins {
    static var current: S1Skin = S1SkinChoice.chosen.makeSkin()
}

/// Every colour the desktop layout and its drawn controls use.
struct S1Palette {

    // Accents
    var accent: UIColor            // the value arcs, lit switches, note-on bars
    var accentLight: UIColor
    var accentBorder: UIColor      // the border of an accent-filled shape
    var accentOnTop: UIColor       // the top of a lit switch's gradient
    var secondAccent: UIColor      // LFO 2, MIDI learn

    // Regions
    var windowBackground: UIColor
    var panelBackground: UIColor       // the preset browser's card
    var toolbarTop: UIColor
    var toolbarBottom: UIColor
    var playBarTop: UIColor
    var playBarBottom: UIColor
    var statusBarBackground: UIColor

    // Sections
    var sectionTop: UIColor
    var sectionBottom: UIColor
    var sectionBorder: UIColor
    var sectionHeaderTop: UIColor
    var sectionHeaderBottom: UIColor
    var hairline: UIColor

    // Type
    var text: UIColor
    var label: UIColor
    var value: UIColor
    var dim: UIColor

    // Fields and buttons
    var fieldBackground: UIColor
    var controlFace: UIColor
    var controlBorder: UIColor

    // Drawn controls (S1DesktopStyle)
    var knobTrack: UIColor
    var knobCapFill: UIColor
    var knobCap: [UIColor]         // four stops, highlight to rim
    var knobCapBorder: UIColor
    var glyph: UIColor             // an unselected glyph
    var chipText: UIColor          // an inactive LFO target's label (P7-4)
    var knobPointer: UIColor?      // the knob's indicator; nil means the accent (P7-4)
    var wellTop: UIColor           // the recessed background of a stepper or switch
    var wellBottom: UIColor
    var wellBorder: UIColor
    var buttonTop: UIColor         // a raised button face
    var buttonBottom: UIColor
    var buttonPressedTop: UIColor
    var buttonBorder: UIColor
    var litTop: UIColor            // a selected cell
    var litBottom: UIColor
    var litBorder: UIColor
    var plateTop: UIColor          // a wave picker's selected cell
    var plateBottom: UIColor
    var chipTop: UIColor
    var chipBottom: UIColor
    var chipBorder: UIColor
    var chipActiveTop: UIColor
    var chipActiveBottom: UIColor
    var faderTick: UIColor
    var grooveEdge: UIColor
    var grooveMid: UIColor
    var faderCapTop: UIColor
    var faderCapBottom: UIColor
    var faderCapBorder: UIColor
    var stepOffTop: UIColor
    var stepOffBottom: UIColor
    var stepOffBorder: UIColor
    var switchOffTop: UIColor
    var switchOffBottom: UIColor
    var thumbOff: UIColor
    var thumbOn: UIColor
    var plotBorder: UIColor        // the ADSR plots and the XY pads
}

extension S1Palette {
    /// P7-12 (ADR-062): the same palette with the light taken out, for a control drawn in a
    /// zone that has lost power. Every field, so a new one cannot be forgotten: the list is
    /// checked against the struct by `testTheGreyPaletteCoversEveryColour`.
    func greyed() -> S1Palette {
        var grey = self
        grey.accent = S1Power.grey(accent)
        grey.accentLight = S1Power.grey(accentLight)
        grey.accentBorder = S1Power.grey(accentBorder)
        grey.accentOnTop = S1Power.grey(accentOnTop)
        grey.secondAccent = S1Power.grey(secondAccent)
        grey.windowBackground = S1Power.grey(windowBackground)
        grey.panelBackground = S1Power.grey(panelBackground)
        grey.toolbarTop = S1Power.grey(toolbarTop)
        grey.toolbarBottom = S1Power.grey(toolbarBottom)
        grey.playBarTop = S1Power.grey(playBarTop)
        grey.playBarBottom = S1Power.grey(playBarBottom)
        grey.statusBarBackground = S1Power.grey(statusBarBackground)
        grey.sectionTop = S1Power.grey(sectionTop)
        grey.sectionBottom = S1Power.grey(sectionBottom)
        grey.sectionBorder = S1Power.grey(sectionBorder)
        grey.sectionHeaderTop = S1Power.grey(sectionHeaderTop)
        grey.sectionHeaderBottom = S1Power.grey(sectionHeaderBottom)
        grey.hairline = S1Power.grey(hairline)
        grey.text = S1Power.grey(text)
        grey.label = S1Power.grey(label)
        grey.value = S1Power.grey(value)
        grey.dim = S1Power.grey(dim)
        grey.fieldBackground = S1Power.grey(fieldBackground)
        grey.controlFace = S1Power.grey(controlFace)
        grey.controlBorder = S1Power.grey(controlBorder)
        grey.knobTrack = S1Power.grey(knobTrack)
        grey.knobCapFill = S1Power.grey(knobCapFill)
        grey.knobCap = knobCap.map(S1Power.grey)
        grey.knobCapBorder = S1Power.grey(knobCapBorder)
        grey.glyph = S1Power.grey(glyph)
        grey.chipText = S1Power.grey(chipText)
        grey.knobPointer = knobPointer.map(S1Power.grey)
        grey.wellTop = S1Power.grey(wellTop)
        grey.wellBottom = S1Power.grey(wellBottom)
        grey.wellBorder = S1Power.grey(wellBorder)
        grey.buttonTop = S1Power.grey(buttonTop)
        grey.buttonBottom = S1Power.grey(buttonBottom)
        grey.buttonPressedTop = S1Power.grey(buttonPressedTop)
        grey.buttonBorder = S1Power.grey(buttonBorder)
        grey.litTop = S1Power.grey(litTop)
        grey.litBottom = S1Power.grey(litBottom)
        grey.litBorder = S1Power.grey(litBorder)
        grey.plateTop = S1Power.grey(plateTop)
        grey.plateBottom = S1Power.grey(plateBottom)
        grey.chipTop = S1Power.grey(chipTop)
        grey.chipBottom = S1Power.grey(chipBottom)
        grey.chipBorder = S1Power.grey(chipBorder)
        grey.chipActiveTop = S1Power.grey(chipActiveTop)
        grey.chipActiveBottom = S1Power.grey(chipActiveBottom)
        grey.faderTick = S1Power.grey(faderTick)
        grey.grooveEdge = S1Power.grey(grooveEdge)
        grey.grooveMid = S1Power.grey(grooveMid)
        grey.faderCapTop = S1Power.grey(faderCapTop)
        grey.faderCapBottom = S1Power.grey(faderCapBottom)
        grey.faderCapBorder = S1Power.grey(faderCapBorder)
        grey.stepOffTop = S1Power.grey(stepOffTop)
        grey.stepOffBottom = S1Power.grey(stepOffBottom)
        grey.stepOffBorder = S1Power.grey(stepOffBorder)
        grey.switchOffTop = S1Power.grey(switchOffTop)
        grey.switchOffBottom = S1Power.grey(switchOffBottom)
        grey.thumbOff = S1Power.grey(thumbOff)
        grey.thumbOn = S1Power.grey(thumbOn)
        grey.plotBorder = S1Power.grey(plotBorder)
        return grey
    }

    static let colourFieldCount = 63
}

/// P7-4 (ADR-048): the drawing choices a skin makes beyond its colours. Studio and Arcade keep
/// every default, so they draw as they did; Neon Ruins turns most of these up.
struct S1SkinDress {
    /// The section border's width, in points.
    var sectionBorderWidth: CGFloat = 1
    /// A section's outer glow (when the skin has `sectionGlow`): radius and opacity.
    var sectionGlowRadius: CGFloat = 6
    var sectionGlowOpacity: Float = 0.4
    /// A second, wider and fainter glow behind each section.
    var sectionBloom = false
    /// Multiplies the knob's value arc width.
    var knobRingScale: CGFloat = 1
    /// A soft disc of the accent round the whole knob, and a bright core along the arc.
    var knobHalo = false
    /// The fader groove below the cap lit in the accent.
    var faderLitTrack = false
    /// Lit cells, chips, plates, switches and fader caps take their colours from the section's
    /// accent (mixed with white and black) instead of the palette's fixed entries.
    var litFromAccent = false
    /// The wordmark's frame in the toolbar. 120×26 is the layout's own; a skin may ask for more.
    var wordmarkSize = CGSize(width: 120, height: 26)
    /// P7-9 (ADR-059): a section draws nothing of its own — no fill, border, glow, texture or
    /// title — because the skin's template has the frame and the title painted in.
    var bareSections = false
    /// The header strip's height; the template's strips are taller than the layout's.
    var sectionHeaderHeight: CGFloat = S1DesktopTheme.sectionHeaderHeight
    /// Dark Arcade (2026-09-24): its painted top two rows are shorter than Cabinet's (by about
    /// 20 and 13 points), and the compact oscillator, Filter, Voice and envelope stacks, sized
    /// for Cabinet, squeezed their value lines. This tightens those stacks; nothing else, and no
    /// other skin, moves.
    var shortRows = false
}

protocol S1Skin: AnyObject {

    var choice: S1SkinChoice { get }
    var palette: S1Palette { get }

    /// How the skin draws beyond its palette (P7-4).
    var dress: S1SkinDress { get }

    /// The accent of one section, by the layout's key ("Mix", "Filter Envelope", "Pads" …), or
    /// nil for the palette's accent. A skin that answers nil for every key is single-accent.
    func sectionAccent(for key: String) -> UIColor?

    /// Art behind the whole window, under the toolbar, rows and bars, or nil.
    func makeBackdropArt() -> UIView?

    /// P7-9 (ADR-059): a painted window the layout places its sections and toolbar over, or nil.
    var template: S1SkinTemplate? { get }

    /// Multiplies every glow's blur; 1 is the Studio glow.
    var glow: CGFloat { get }

    /// A pattern laid over each section, or nil for a plain gradient.
    var sectionTexture: UIImage? { get }

    /// A section's outer glow, or nil for the Studio drop shadow.
    var sectionGlow: UIColor? { get }

    /// The frame around the preset browser's lists and the XY pads, or nil for plain borders.
    var frameAccent: UIColor? { get }

    /// The wordmark, or nil for the header's image.
    func makeWordmark() -> UIView?

    /// Art behind the toolbar's controls, or nil.
    func makeToolbarArt() -> UIView?

    /// Art behind the preset browser's column, or nil.
    func makePanelArt() -> UIView?
}

extension S1Skin {
    var dress: S1SkinDress { S1SkinDress() }
    func sectionAccent(for key: String) -> UIColor? { nil }
    func makeBackdropArt() -> UIView? { nil }
    var template: S1SkinTemplate? { nil }
}

// MARK: - Studio: the 0.2.0 look

final class S1StudioSkin: S1Skin {

    let choice = S1SkinChoice.studio
    let glow: CGFloat = 1
    let sectionTexture: UIImage? = nil
    let sectionGlow: UIColor? = nil
    let frameAccent: UIColor? = nil
    func makeWordmark() -> UIView? { nil }
    func makeToolbarArt() -> UIView? { nil }
    func makePanelArt() -> UIView? { nil }

    /// The values the layout shipped with: upstream's orange, the storyboard greys.
    let palette = S1Palette(
        accent: UIColor(red: 0.902, green: 0.533, blue: 0.008, alpha: 1),
        accentLight: UIColor(red: 1.0, green: 0.655, blue: 0.2, alpha: 1),
        accentBorder: UIColor(hex: 0x7a4600),
        accentOnTop: UIColor(hex: 0xb86b00),
        secondAccent: UIColor(red: 0.455, green: 0.624, blue: 0.725, alpha: 1),
        windowBackground: UIColor(hex: 0x222224),
        panelBackground: UIColor(hex: 0x1d1d1e),
        toolbarTop: UIColor(hex: 0x333335),
        toolbarBottom: UIColor(hex: 0x2b2b2d),
        playBarTop: UIColor(hex: 0x242426),
        playBarBottom: UIColor(hex: 0x1e1e20),
        statusBarBackground: UIColor(hex: 0x1c1c1d),
        sectionTop: UIColor(hex: 0x2d2d30),
        sectionBottom: UIColor(hex: 0x262629),
        sectionBorder: UIColor(hex: 0x141415),
        sectionHeaderTop: UIColor(hex: 0x3b3b3f),
        sectionHeaderBottom: UIColor(hex: 0x2f2f32),
        hairline: UIColor(hex: 0x18181a),
        text: UIColor(hex: 0xeeeeee),
        label: UIColor(hex: 0xd0d0d2),
        value: UIColor(hex: 0x8f8f93),
        dim: UIColor(hex: 0x999999),
        fieldBackground: UIColor(hex: 0x1a1a1b),
        controlFace: UIColor(hex: 0x3a3a3d),
        controlBorder: UIColor(hex: 0x47474a),
        knobTrack: UIColor(hex: 0x1a1a1b),
        knobCapFill: UIColor(hex: 0x232325),
        knobCap: [UIColor(hex: 0x55555a), UIColor(hex: 0x323235), UIColor(hex: 0x212123), UIColor(hex: 0x19191a)],
        knobCapBorder: UIColor(hex: 0x0f0f10),
        glyph: UIColor(hex: 0x8a8a8e),
        chipText: UIColor(hex: 0xd0d0d2),
        knobPointer: nil,
        wellTop: UIColor(hex: 0x161617),
        wellBottom: UIColor(hex: 0x1c1c1d),
        wellBorder: UIColor(hex: 0x101011),
        buttonTop: UIColor(hex: 0x444448),
        buttonBottom: UIColor(hex: 0x333336),
        buttonPressedTop: UIColor(hex: 0x2c2c2f),
        buttonBorder: UIColor(hex: 0x1a1a1b),
        litTop: UIColor(hex: 0x4a4a4e),
        litBottom: UIColor(hex: 0x38383b),
        litBorder: UIColor(hex: 0x1a1a1b),
        plateTop: UIColor(hex: 0x3f3f43),
        plateBottom: UIColor(hex: 0x2f2f32),
        chipTop: UIColor(hex: 0x3a3a3e),
        chipBottom: UIColor(hex: 0x2c2c2f),
        chipBorder: UIColor(hex: 0x141415),
        chipActiveTop: UIColor(hex: 0x4a3410),
        chipActiveBottom: UIColor(hex: 0x3a2a0e),
        faderTick: UIColor(hex: 0x3a3a3e),
        grooveEdge: UIColor(hex: 0x0b0b0c),
        grooveMid: UIColor(hex: 0x1c1c1e),
        faderCapTop: UIColor(hex: 0x4c4c50),
        faderCapBottom: UIColor(hex: 0x2b2b2e),
        faderCapBorder: UIColor(hex: 0x0f0f10),
        stepOffTop: UIColor(hex: 0x3c3c40),
        stepOffBottom: UIColor(hex: 0x2c2c2f),
        stepOffBorder: UIColor(hex: 0x141415),
        switchOffTop: UIColor(hex: 0x161617),
        switchOffBottom: UIColor(hex: 0x262628),
        thumbOff: UIColor(hex: 0x5a5a5e),
        thumbOn: .white,
        plotBorder: UIColor(hex: 0x0f0f10)
    )
}

// MARK: - Cabinet: the owner's painted window, one neon colour per section (P7-9, ADR-059)

/// The painting carries the frames, titles, header and cabinet; the controls are the layout's,
/// lit in one neon per section (P7-4, ADR-048). The colours and the drawing were Neon Ruins',
/// the skin this replaced at the owner's word on 2026-09-17 (P7-10, ADR-060).
final class S1CabinetSkin: S1Skin {

    let choice = S1SkinChoice.cabinet
    let glow: CGFloat = 3
    let sectionTexture: UIImage? = nil
    let sectionGlow: UIColor? = nil
    var frameAccent: UIColor? { palette.secondAccent }
    func makeWordmark() -> UIView? { nil }
    func makeToolbarArt() -> UIView? { nil }
    func makePanelArt() -> UIView? { S1CabinetPanelArt() }

    let dress: S1SkinDress = {
        var dress = S1SkinDress()
        dress.knobRingScale = 1.5
        dress.knobHalo = true
        dress.faderLitTrack = true
        dress.litFromAccent = true
        dress.bareSections = true
        dress.sectionHeaderHeight = 30
        return dress
    }()

    // The six neons of the canvas
    static let orange = UIColor(hex: 0xff7a1a)
    static let cyan = UIColor(hex: 0x2ee8ff)
    static let pink = UIColor(hex: 0xff2bd6)
    static let violet = UIColor(hex: 0xa86bff)
    static let gold = UIColor(hex: 0xffcf3a)
    static let mint = UIColor(hex: 0x3dffb4)
    /// The window under everything, and the ground in the art.
    static let night = UIColor(hex: 0x08070d)

    /// A spectrum across each row. The filter and its envelope share pink, the two modulation
    /// sections violet; orange is the sound sources, the output stage, the sequencer and the
    /// toolbar. Mix is mint like Delay at the owner's request (2026-09-14).
    static let accents: [String: UIColor] = [
        "OSC 1": orange, "OSC 2": orange, "Mix": mint, "Filter": pink, "Voice": violet,
        "Filter Envelope": pink, "Amplitude Envelope": gold, "LFO & Mod Targets": violet,
        "Reverb": cyan, "Delay": mint, "Phaser": violet, "Bitcrusher": pink, "Master": orange,
        "Sequencer": orange, "Pads": cyan
    ]

    func sectionAccent(for key: String) -> UIColor? { Self.accents[key] }

    let palette = S1Palette(
        accent: S1CabinetSkin.orange,
        accentLight: UIColor(hex: 0xffb257),
        accentBorder: UIColor(hex: 0xffd9a8),
        accentOnTop: UIColor(hex: 0xffb257),
        secondAccent: S1CabinetSkin.cyan,
        windowBackground: S1CabinetSkin.night,
        panelBackground: UIColor(hex: 0x0a0812),
        toolbarTop: UIColor(hex: 0x1c0c40),
        toolbarBottom: UIColor(hex: 0x0c0916),
        playBarTop: UIColor(hex: 0x0e081a, alpha: 0.55),      // the backdrop's floor shows through
        playBarBottom: UIColor(hex: 0x08060e, alpha: 0.5),
        statusBarBackground: UIColor(hex: 0x06050b, alpha: 0.6),
        sectionTop: UIColor(hex: 0x0f0c15),
        sectionBottom: UIColor(hex: 0x07060b),
        sectionBorder: S1CabinetSkin.orange,
        sectionHeaderTop: UIColor(white: 1, alpha: 0.05),     // no band: a breath of light under the title
        sectionHeaderBottom: UIColor(white: 1, alpha: 0),
        hairline: UIColor(hex: 0xff7a1a, alpha: 0.5),
        text: .white,
        label: .white,
        value: UIColor(hex: 0x7ff5ff),
        dim: UIColor(hex: 0xc9bde0),
        fieldBackground: UIColor(hex: 0x04030a),
        controlFace: UIColor(hex: 0x160f26),
        controlBorder: S1CabinetSkin.orange,
        knobTrack: UIColor(hex: 0x2a1a30),
        knobCapFill: UIColor(hex: 0x0d0a10),
        knobCap: [UIColor(hex: 0x4a3f54), UIColor(hex: 0x241d2c), UIColor(hex: 0x0d0a10), .black],
        knobCapBorder: .black,
        glyph: UIColor(hex: 0x9ff8ff),
        chipText: UIColor(hex: 0x9ff8ff),
        knobPointer: .white,
        wellTop: UIColor(hex: 0x06050c),
        wellBottom: UIColor(hex: 0x0a0812),
        wellBorder: UIColor(hex: 0x2ee8ff, alpha: 0.7),
        buttonTop: UIColor(hex: 0x1e1430),
        buttonBottom: UIColor(hex: 0x0e0a1c),
        buttonPressedTop: UIColor(hex: 0x0a0714),
        buttonBorder: S1CabinetSkin.orange,
        litTop: UIColor(hex: 0xa34a12),          // the accent-derived colours replace these
        litBottom: UIColor(hex: 0x5a2a0a),
        litBorder: UIColor(hex: 0xffd9a8),
        plateTop: UIColor(hex: 0xa34a12),
        plateBottom: UIColor(hex: 0x5a2a0a),
        chipTop: UIColor(hex: 0x140e26),
        chipBottom: UIColor(hex: 0x0a0716),
        chipBorder: UIColor(hex: 0x2ee8ff, alpha: 0.9),
        chipActiveTop: UIColor(hex: 0xa34a12),
        chipActiveBottom: UIColor(hex: 0x5a2a0a),
        faderTick: UIColor(hex: 0x5a3a20),
        grooveEdge: UIColor(hex: 0x05040a),
        grooveMid: UIColor(hex: 0x1a1226),
        faderCapTop: UIColor(hex: 0xffe0b0),
        faderCapBottom: UIColor(hex: 0xd4580c),
        faderCapBorder: UIColor(hex: 0xfff0d8),
        stepOffTop: UIColor(hex: 0x1a1228),
        stepOffBottom: UIColor(hex: 0x0c0816),
        stepOffBorder: UIColor(hex: 0x3a2850),
        switchOffTop: UIColor(hex: 0x0a0810),
        switchOffBottom: UIColor(hex: 0x1a1226),
        thumbOff: UIColor(hex: 0x6a5a80),
        thumbOn: .white,
        plotBorder: S1CabinetSkin.cyan
    )

    /// Measured on `Scripts/branding/source/ar-template.png`: each frame's inner edge.
    let template: S1SkinTemplate? = S1SkinTemplate(
        imageName: "s1_template_cabinet",
        size: CGSize(width: 1_585, height: 992),
        sections: [
            "OSC 1": rect(248, 118, 423, 286),
            "OSC 2": rect(438, 118, 627, 286),
            "Mix": rect(643, 118, 1_121, 286),
            "Filter": rect(1_135, 118, 1_407, 286),
            "Voice": rect(1_423, 118, 1_555, 286),
            "Filter Envelope": rect(235, 300, 640, 480),
            "Amplitude Envelope": rect(655, 300, 1_097, 480),
            "LFO & Mod Targets": rect(1_112, 300, 1_555, 487),
            "Reverb": rect(235, 495, 485, 656),
            "Delay": rect(500, 495, 780, 656),
            "Phaser": rect(794, 495, 1_081, 656),
            "Bitcrusher": rect(1_094, 503, 1_357, 656),
            "Master": rect(1_373, 505, 1_555, 656),
            "Sequencer": rect(236, 670, 1_189, 929),
            "Pads": rect(1_205, 672, 1_554, 931)
        ],
        presetField: rect(572, 26, 868, 68),
        displayColour: S1CabinetSkin.cyan,
        previous: rect(534, 28, 572, 66),
        next: rect(898, 28, 936, 66),
        dice: CGPoint(x: 882, y: 47),
        wordmark: rect(50, 10, 432, 60),
        scope: rect(34, 112, 210, 272),
        save: rect(1_147, 64, 1_232, 100),
        record: rect(1_238, 64, 1_319, 100),
        panic: rect(1_324, 64, 1_393, 100),
        settings: rect(1_397, 64, 1_474, 100),
        presets: rect(1_478, 64, 1_558, 100),
        playBar: rect(6, 950, 990, 992),
        statusBar: rect(1_000, 950, 1_578, 992),
        paintedButtons: true,
        // `JOYSTICK_BALL_BOX` and `JOYSTICK_ROD_BOX` in generate.py; the pivot is the socket
        joystick: S1TemplateJoystick(ballImageName: "s1_template_joystick_ball", ballBox: rect(88, 834, 126, 872),
                                     rodImageName: "s1_template_joystick_rod", rodBox: rect(94, 846, 114, 898),
                                     pivot: CGPoint(x: 103, y: 893), reach: rect(60, 800, 126, 912)),
        // The console's two big red buttons, left and right
        power: S1TemplatePower(darkImageName: "s1_template_cabinet_dark", off: rect(128, 879, 158, 911), on: rect(159, 874, 190, 906),
                               zones: ["display": rect(500, 4, 968, 88), "buttons": rect(1_136, 54, 1_568, 106),
                                       "screen": rect(14, 92, 232, 296), "bar": rect(0, 944, 1_585, 992)],
                               frameReach: 11)
    )
}

// MARK: - Dark Arcade: the calmer painted window (2026-09-24)

/// The owner's second painting: Cabinet's header and sections without the cabinet, the console
/// or the neon — "something a little easier on the eyes". One orange for every section, the
/// Studio greys under the controls, cyan only where a second colour is needed (LFO 2, pad 2).
/// **The JUCE plugin's only** (`S1SkinChoice.offered`); defined here because the plugin's layout
/// is measured from this one (ADR-083).
final class S1DarkArcadeSkin: S1Skin {

    let choice = S1SkinChoice.darkArcade
    let glow: CGFloat = 1.5
    let sectionTexture: UIImage? = nil
    let sectionGlow: UIColor? = nil
    let frameAccent: UIColor? = nil
    func makeWordmark() -> UIView? { nil }
    func makeToolbarArt() -> UIView? { nil }
    func makePanelArt() -> UIView? { nil }

    let dress: S1SkinDress = {
        var dress = S1SkinDress()
        dress.knobRingScale = 1.25
        dress.faderLitTrack = true
        dress.litFromAccent = true
        dress.bareSections = true
        dress.sectionHeaderHeight = 30
        dress.shortRows = true
        return dress
    }()

    /// The painting's orange, and the one cool colour it uses.
    static let orange = UIColor(hex: 0xff8a1e)
    static let cyan = UIColor(hex: 0x38d6f0)

    let palette = S1Palette(
        accent: S1DarkArcadeSkin.orange,
        accentLight: UIColor(hex: 0xffb35c),
        accentBorder: UIColor(hex: 0xffd3a0),
        accentOnTop: UIColor(hex: 0xffa64a),
        secondAccent: S1DarkArcadeSkin.cyan,
        windowBackground: UIColor(hex: 0x0d0f12),
        panelBackground: UIColor(hex: 0x16181c),
        toolbarTop: UIColor(hex: 0x1c1f24),
        toolbarBottom: UIColor(hex: 0x131519),
        playBarTop: UIColor(hex: 0x14161a, alpha: 0.5),       // the painting's floor shows through
        playBarBottom: UIColor(hex: 0x0e1013, alpha: 0.5),
        statusBarBackground: UIColor(hex: 0x0c0d10, alpha: 0.5),
        sectionTop: UIColor(hex: 0x1d2025),
        sectionBottom: UIColor(hex: 0x15171b),
        sectionBorder: UIColor(hex: 0x3a3e45),
        sectionHeaderTop: UIColor(white: 1, alpha: 0.04),
        sectionHeaderBottom: UIColor(white: 1, alpha: 0),
        hairline: UIColor(hex: 0xff8a1e, alpha: 0.45),
        text: UIColor(hex: 0xf0f0f2),
        label: UIColor(hex: 0xdadade),
        value: UIColor(hex: 0x9c9fa6),
        dim: UIColor(hex: 0x9a9da4),
        fieldBackground: UIColor(hex: 0x0e1013),
        controlFace: UIColor(hex: 0x24272d),
        controlBorder: UIColor(hex: 0x3d4148),
        knobTrack: UIColor(hex: 0x101215),
        knobCapFill: UIColor(hex: 0x202328),
        knobCap: [UIColor(hex: 0x575b63), UIColor(hex: 0x33363c), UIColor(hex: 0x202328), UIColor(hex: 0x16181b)],
        knobCapBorder: UIColor(hex: 0x0b0c0e),
        glyph: UIColor(hex: 0x8e9199),
        chipText: UIColor(hex: 0xdadade),
        knobPointer: nil,
        wellTop: UIColor(hex: 0x0f1114),
        wellBottom: UIColor(hex: 0x181a1e),
        wellBorder: UIColor(hex: 0x2c2f35),
        buttonTop: UIColor(hex: 0x2c3036),
        buttonBottom: UIColor(hex: 0x1f2227),
        buttonPressedTop: UIColor(hex: 0x181a1e),
        buttonBorder: UIColor(hex: 0x3d4148),
        litTop: UIColor(hex: 0x9a4d10),          // the accent-derived colours replace these
        litBottom: UIColor(hex: 0x5c2e0a),
        litBorder: UIColor(hex: 0xffd3a0),
        plateTop: UIColor(hex: 0x9a4d10),
        plateBottom: UIColor(hex: 0x5c2e0a),
        chipTop: UIColor(hex: 0x282b31),
        chipBottom: UIColor(hex: 0x1d2025),
        chipBorder: UIColor(hex: 0x3d4148),
        chipActiveTop: UIColor(hex: 0x9a4d10),
        chipActiveBottom: UIColor(hex: 0x5c2e0a),
        faderTick: UIColor(hex: 0x3a3e45),
        grooveEdge: UIColor(hex: 0x08090b),
        grooveMid: UIColor(hex: 0x1b1d21),
        faderCapTop: UIColor(hex: 0xffc080),
        faderCapBottom: UIColor(hex: 0xe0660c),
        faderCapBorder: UIColor(hex: 0xffe2c0),
        stepOffTop: UIColor(hex: 0x282b31),
        stepOffBottom: UIColor(hex: 0x1d2025),
        stepOffBorder: UIColor(hex: 0x3d4148),
        switchOffTop: UIColor(hex: 0x111316),
        switchOffBottom: UIColor(hex: 0x23262b),
        thumbOff: UIColor(hex: 0x62666e),
        thumbOn: .white,
        plotBorder: UIColor(hex: 0x2c2f35)
    )

    /// Measured on `Scripts/branding/source/dark-arcade.png` (the owner's clean painting, the
    /// second of 2026-09-24): each frame's inner edge, seven pixels in from the dark gutter between
    /// frames (a frame here is six pixels and a dark line). No screen, joystick or power buttons —
    /// and no painted header buttons: the plugin draws those (`paintedButtons`).
    let template: S1SkinTemplate? = S1SkinTemplate(
        imageName: "s1_template_darkarcade",
        size: CGSize(width: 1_586, height: 992),
        sections: [
            // The top row as `generate.py` re-cuts it (the owner: narrower oscillators, a wider Mix)
            "OSC 1": rect(30, 119, 215, 265),
            "OSC 2": rect(238, 119, 449, 265),
            "Mix": rect(473, 119, 1_097, 265),
            "Filter": rect(1_120, 119, 1_383, 265),
            "Voice": rect(1_406, 119, 1_555, 265),
            "Filter Envelope": rect(30, 288, 581, 454),
            "Amplitude Envelope": rect(605, 288, 1_076, 454),
            "LFO & Mod Targets": rect(1_099, 288, 1_555, 454),
            "Reverb": rect(30, 477, 356, 621),
            "Delay": rect(379, 477, 711, 621),
            "Phaser": rect(734, 477, 1_052, 621),
            "Bitcrusher": rect(1_075, 477, 1_357, 621),
            "Master": rect(1_381, 477, 1_555, 621),
            "Sequencer": rect(30, 644, 1_166, 903),
            "Pads": rect(1_189, 644, 1_555, 903)
        ],
        presetField: rect(610, 28, 930, 72),
        displayColour: S1DarkArcadeSkin.orange,
        previous: rect(557, 30, 597, 70),
        next: rect(976, 30, 1_016, 70),
        dice: CGPoint(x: 952, y: 50),
        wordmark: rect(56, 14, 478, 62),
        scope: nil,
        save: rect(1_190, 58, 1_258, 92),
        record: rect(1_264, 58, 1_332, 92),
        panic: rect(1_338, 58, 1_400, 92),
        settings: rect(1_406, 58, 1_480, 92),
        presets: rect(1_486, 58, 1_556, 92),
        playBar: rect(24, 914, 1_000, 952),
        statusBar: rect(1_000, 914, 1_562, 952),
        paintedButtons: false,
        joystick: nil,
        power: nil
    )
}

// MARK: - A painted window (P7-9, ADR-059)

/// Where a painted window keeps each thing, in the painting's own pixels. The layout pins its
/// sections and toolbar controls to these, as fractions of the canvas, so the window stays fluid.
struct S1SkinTemplate {
    let imageName: String
    let size: CGSize
    /// By the section keys `S1DesktopLayout.sections` uses.
    let sections: [String: CGRect]
    let presetField: CGRect
    /// The preset's name in the painted display: Cabinet's cyan, Dark Arcade's orange.
    let displayColour: UIColor
    let previous: CGRect
    let next: CGRect
    let dice: CGPoint
    let wordmark: CGRect
    /// The oscilloscope, in a painted screen — or nil where the painting has none (Dark Arcade).
    let scope: CGRect?
    let save: CGRect
    let record: CGRect
    let panic: CGRect
    let settings: CGRect
    let presets: CGRect
    let playBar: CGRect
    let statusBar: CGRect
    /// Whether the painting has Save, Panic, Settings and Presets painted in (Cabinet), so a
    /// clear button over each takes the click — or leaves the header bare (Dark Arcade), so the
    /// JUCE plugin draws them. The Mac layout lays clear buttons either way: Classic offers no
    /// painting without them.
    let paintedButtons: Bool
    /// P7-11 (ADR-061): a live joystick over the painted one, or nil.
    let joystick: S1TemplateJoystick?
    /// P7-12 (ADR-062): the painted buttons that cut and restore the power, the grey painting,
    /// and the pieces of the header that go dark with the sections. Nil for no such thing.
    let power: S1TemplatePower?
}

struct S1TemplatePower {
    let darkImageName: String
    let off: CGRect
    let on: CGRect
    /// By name: "display", "buttons", "screen", "bar".
    let zones: [String: CGRect]
    /// How far a section's frame and its glow reach beyond its inner edge.
    let frameReach: CGFloat
}

/// The two sprites, the boxes they were cut from, where the rod hinges, and the rectangle the
/// stick can be grabbed in. All in the painting's pixels; the boxes are `generate.py`'s.
struct S1TemplateJoystick {
    let ballImageName: String
    let ballBox: CGRect
    let rodImageName: String
    let rodBox: CGRect
    let pivot: CGPoint
    let reach: CGRect
}

private func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
    CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
}

