//  Colours, type and metrics of the desktop layout (P6, ADR-045).
//
//  **New, not ported.** The Studio values come from the design canvas the owner approved on
//  2026-09-12, which in turn took its palette from the storyboards: the orange is
//  upstream's `UIColor(0.902, 0.533, 0.008)`, the greys are the panel greys, and the
//  type is Avenir Next Condensed, which every storyboard label already uses. Since P7 the
//  colours are the skin's (`S1Skin`, ADR-046); the metrics are the layout's and never change.

import UIKit

enum S1DesktopTheme {

    // MARK: - Colours

    // P7 (ADR-046): every colour comes from the skin in use. The names stay, so the layout
    // reads exactly as it did; only where the value comes from changed.
    private static var p: S1Palette { S1Skins.current.palette }

    static var orange: UIColor { p.accent }
    static var orangeLight: UIColor { p.accentLight }

    static var windowBackground: UIColor { p.windowBackground }
    static var panelBackground: UIColor { p.panelBackground }
    static var toolbarTop: UIColor { p.toolbarTop }
    static var toolbarBottom: UIColor { p.toolbarBottom }
    static var playBarTop: UIColor { p.playBarTop }
    static var playBarBottom: UIColor { p.playBarBottom }
    static var statusBarBackground: UIColor { p.statusBarBackground }

    static var sectionTop: UIColor { p.sectionTop }
    static var sectionBottom: UIColor { p.sectionBottom }
    static var sectionBorder: UIColor { p.sectionBorder }
    static var sectionHeaderTop: UIColor { p.sectionHeaderTop }
    static var sectionHeaderBottom: UIColor { p.sectionHeaderBottom }
    static var hairline: UIColor { p.hairline }

    static var text: UIColor { p.text }
    static var label: UIColor { p.label }
    static var value: UIColor { p.value }
    static var dim: UIColor { p.dim }

    static var fieldBackground: UIColor { p.fieldBackground }
    static var controlFace: UIColor { p.controlFace }
    static var controlBorder: UIColor { p.controlBorder }
    static var plotBorder: UIColor { p.plotBorder }

    // MARK: - Type

    static func font(_ size: CGFloat, weight: Weight = .regular) -> UIFont {
        let name: String
        switch weight {
        case .regular: name = "AvenirNextCondensed-Regular"
        case .medium: name = "AvenirNextCondensed-Medium"
        case .demiBold: name = "AvenirNextCondensed-DemiBold"
        }
        return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size)
    }

    enum Weight { case regular, medium, demiBold }

    // MARK: - Metrics

    static let toolbarHeight: CGFloat = 48
    /// Where the window's traffic lights sit when the title bar is hidden.
    static let trafficLightAllowance: CGFloat = 78
    /// P8-0: the preset browser drops down from the toolbar as a card this size (it was a
    /// 260-point sidebar from P6-6 to P7). A short window shortens it.
    static let presetPanelWidth: CGFloat = 380
    static let presetPanelHeight: CGFloat = 720
    static let playBarHeight: CGFloat = 36
    static let statusBarHeight: CGFloat = 24
    static let sectionHeaderHeight: CGFloat = 24
    static let sectionCornerRadius: CGFloat = 7
    static let editorPadding: CGFloat = 10
    static let rowGap: CGFloat = 8

    /// The window the layout is designed at. The editor grid is fluid above it.
    static let designSize = CGSize(width: 1_440, height: 900)
    /// P6-4: measured, not chosen; below 900 tall the fourth row starves the faders (26 points
    /// at 820). P8-0: with the sidebar gone the rows have the whole width, and the sections were
    /// re-spaced to use it (owner, 2026-09-13), so the minimum stays the design size.
    static let minimumWindowSize = CGSize(width: 1_440, height: 900)
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: alpha)
    }

    /// This colour moved `fraction` of the way towards `other`, component by component (P7-4):
    /// how a skin derives a lit cell, a border or a highlight from one accent.
    func mixed(with other: UIColor, _ fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, fraction))
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}

extension UIView {
    /// The accent a control draws in (P7-4, ADR-048): its section's, when the skin gives that
    /// section one, else the palette's. Found by walking up to the nearest `S1SectionView`, so
    /// a control moved between sections follows, and one outside any section — the toolbar,
    /// the play bar — keeps the palette's accent.
    var s1Accent: UIColor {
        // P7-12 (ADR-062): a zone without power answers first, and tells the style to draw grey
        if S1Power.dark.count > 0 {
            var view: UIView? = self
            while let current = view {
                if S1Power.dark.contains(current) {
                    S1DesktopStyle.unpowered = true
                    return S1Power.deadAccent
                }
                view = current.superview
            }
        }
        S1DesktopStyle.unpowered = false
        var view: UIView? = self
        while let current = view {
            if let section = current as? S1SectionView, let accent = section.accent { return accent }
            view = current.superview
        }
        return S1DesktopTheme.orange
    }
}

/// A view whose background is a vertical gradient, with an optional bottom hairline.
final class S1GradientView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradient: CAGradientLayer { layer as! CAGradientLayer }

    private let hairline = CALayer()

    /// Recolours the bottom hairline, if there is one (P7-4: a section's follows its accent).
    func setHairline(_ colour: UIColor) {
        guard hairline.superlayer != nil else { return }
        hairline.backgroundColor = colour.cgColor
    }

    /// P7-9: a template skin clears a region the painting already fills.
    func setColours(top: UIColor, bottom: UIColor) {
        gradient.colors = [top.cgColor, bottom.cgColor]
    }

    init(top: UIColor, bottom: UIColor, hairline hairlineColor: UIColor? = nil) {
        super.init(frame: .zero)
        gradient.colors = [top.cgColor, bottom.cgColor]
        if let hairlineColor {
            hairline.backgroundColor = hairlineColor.cgColor
            layer.addSublayer(hairline)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        hairline.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
    }
}
