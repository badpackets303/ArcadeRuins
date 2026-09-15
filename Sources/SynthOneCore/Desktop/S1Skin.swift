//  Skins for the desktop layout (P7, ADR-046).
//
//  **New, not ported.** A skin is how the desktop layout looks, never where anything sits:
//  the palette every colour comes from, how strongly the accents glow, and a few pieces of
//  decoration the layout hangs when the skin supplies them (a wordmark, header and browser
//  art, a texture over the sections, a framed preset list). Layout, metrics, bindings and
//  tests are shared by every skin, so a control looks different under each and behaves the
//  same.
//
//  Two skins ship: **Studio**, the 0.2.0 look (dark greys, one orange), and **Neon Ruins**
//  (P7-4, ADR-048) — one neon colour per section, near-black worn panels, glowing controls, a
//  sunset and grid in the header and the owner's wordmark lit, drawn entirely in code. A
//  section's accent is the skin's word (`sectionAccent`); every drawn control finds it through
//  `UIView.s1Accent`, so Studio, which names none, draws exactly as it did.
//
//  A third, **Arcade**, shipped between them and was dropped at the owner's word on 2026-09-14
//  (P7-7, ADR-051). Nothing was released with it. `git show bf8a08a` has it.
//
//  The choice is a user default, read once at launch (like `S1Layout`):
//
//      defaults write com.badpackets303.ArcadeRuins S1Skin neonRuins
//
//  or `-S1Skin neonRuins` as a launch argument. The plugin keeps its own container and
//  therefore its own default.

import UIKit

public enum S1SkinChoice: String, CaseIterable {

    case studio
    case neonRuins

    public static let defaultsKey = "S1Skin"

    /// The skin the products open with. Absent or unknown means Studio.
    public static var chosen: S1SkinChoice {
        S1SkinChoice(rawValue: S1Preferences.store.string(forKey: defaultsKey) ?? "") ?? .studio
    }

    /// Remembered for the next launch; the running interface does not change.
    public static func choose(_ choice: S1SkinChoice) {
        S1Preferences.store.set(choice.rawValue, forKey: defaultsKey)
    }

    public var title: String {
        switch self {
        case .studio: return NSLocalizedString("Studio", comment: "Skin name")
        case .neonRuins: return NSLocalizedString("Neon Ruins", comment: "Skin name")
        }
    }

    func makeSkin() -> S1Skin {
        switch self {
        case .studio: return S1StudioSkin()
        case .neonRuins: return S1NeonRuinsSkin()
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

// MARK: - Neon Ruins: one neon colour per section (P7-4, ADR-048)

final class S1NeonRuinsSkin: S1Skin {

    let choice = S1SkinChoice.neonRuins
    let glow: CGFloat = 3
    var sectionTexture: UIImage? { S1NeonRuinsArt.grime }
    var sectionGlow: UIColor? { palette.accent }
    var frameAccent: UIColor? { palette.secondAccent }
    func makeWordmark() -> UIView? { S1NeonRuinsWordmark() }
    func makeToolbarArt() -> UIView? { S1NeonRuinsHeaderArt() }
    func makePanelArt() -> UIView? { S1NeonRuinsPanelArt() }
    func makeBackdropArt() -> UIView? { S1NeonRuinsBackdropArt() }

    let dress: S1SkinDress = {
        var dress = S1SkinDress()
        dress.sectionBorderWidth = 2
        dress.sectionGlowRadius = 9
        dress.sectionGlowOpacity = 0.7
        dress.sectionBloom = true
        dress.knobRingScale = 1.5
        dress.knobHalo = true
        dress.faderLitTrack = true
        dress.litFromAccent = true
        dress.wordmarkSize = CGSize(width: 220, height: 24)   // the artwork is ~14:1 once trimmed
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
        accent: S1NeonRuinsSkin.orange,
        accentLight: UIColor(hex: 0xffb257),
        accentBorder: UIColor(hex: 0xffd9a8),
        accentOnTop: UIColor(hex: 0xffb257),
        secondAccent: S1NeonRuinsSkin.cyan,
        windowBackground: S1NeonRuinsSkin.night,
        panelBackground: UIColor(hex: 0x0a0812),
        toolbarTop: UIColor(hex: 0x1c0c40),
        toolbarBottom: UIColor(hex: 0x0c0916),
        playBarTop: UIColor(hex: 0x0e081a, alpha: 0.55),      // the backdrop's floor shows through
        playBarBottom: UIColor(hex: 0x08060e, alpha: 0.5),
        statusBarBackground: UIColor(hex: 0x06050b, alpha: 0.6),
        sectionTop: UIColor(hex: 0x0f0c15),
        sectionBottom: UIColor(hex: 0x07060b),
        sectionBorder: S1NeonRuinsSkin.orange,
        sectionHeaderTop: UIColor(white: 1, alpha: 0.05),     // no band: a breath of light under the title
        sectionHeaderBottom: UIColor(white: 1, alpha: 0),
        hairline: UIColor(hex: 0xff7a1a, alpha: 0.5),
        text: .white,
        label: .white,
        value: UIColor(hex: 0x7ff5ff),
        dim: UIColor(hex: 0xc9bde0),
        fieldBackground: UIColor(hex: 0x04030a),
        controlFace: UIColor(hex: 0x160f26),
        controlBorder: S1NeonRuinsSkin.orange,
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
        buttonBorder: S1NeonRuinsSkin.orange,
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
        plotBorder: S1NeonRuinsSkin.cyan
    )
}
