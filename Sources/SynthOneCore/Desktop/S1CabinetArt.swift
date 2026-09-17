//  The Cabinet skin's drawn decoration (P7-4, ADR-048; P7-10, ADR-060).
//
//  **New, not ported.** What is left of Neon Ruins' code-drawn art now that the Cabinet skin's
//  window is the owner's painting: the art behind the preset browser's card — stars, a cyan
//  floor grid and a joystick — drawn with Core Graphics from seeded sequences, with
//  `S1SynthwaveArt`, so a render is the same twice. The header, backdrop, grime texture and lit
//  wordmark went with Neon Ruins; `git show v0.4.0:Sources/SynthOneCore/Desktop/S1NeonRuinsArt.swift`.

import UIKit

enum S1CabinetArt {

    static let orange = S1CabinetSkin.orange
    static let cyan = S1CabinetSkin.cyan
    static let pink = S1CabinetSkin.pink

    /// A perspective floor with a glow, fading out towards the horizon.
    static func drawFloor(_ c: CGContext, in b: CGRect, horizon: CGFloat, colour: UIColor, alpha: CGFloat,
                          verticals: Int, horizontals: Int, fade: CGFloat) {
        c.saveGState()
        c.setShadow(offset: .zero, blur: 3, color: colour.withAlphaComponent(alpha * 0.8).cgColor)
        S1SynthwaveArt.drawGrid(c, in: b, horizon: horizon, vanishingX: b.midX, colour: colour, alpha: alpha,
                             verticals: verticals, horizontals: horizontals)
        c.restoreGState()
        if fade > 0, let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                               colors: [S1CabinetSkin.night.cgColor, S1CabinetSkin.night.withAlphaComponent(0).cgColor] as CFArray,
                                               locations: [0, 1]) {
            c.drawLinearGradient(gradient, start: CGPoint(x: b.midX, y: horizon), end: CGPoint(x: b.midX, y: horizon + fade), options: [])
        }
    }

}

final class S1CabinetPanelArt: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        let b = bounds
        if let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [UIColor(hex: 0x0a0812).cgColor, UIColor(hex: 0x1a0f2e).cgColor, UIColor(hex: 0x0a0712).cgColor] as CFArray,
                                locations: [0, 0.6, 1]) {
            c.drawLinearGradient(sky, start: CGPoint(x: b.midX, y: b.minY), end: CGPoint(x: b.midX, y: b.maxY), options: [])
        }
        S1SynthwaveArt.drawStars(c, in: b, count: 140, seed: 0xCAB)
        let horizon = (b.height * 0.6).rounded()
        S1CabinetArt.drawFloor(c, in: b, horizon: horizon, colour: S1CabinetArt.cyan, alpha: 0.7,
                                 verticals: 16, horizontals: 12, fade: b.height * 0.28)
        S1SynthwaveArt.drawJoystick(c, in: b)
        c.setFillColor(UIColor.black.withAlphaComponent(0.25).cgColor)
        c.fill(b)
    }
}
