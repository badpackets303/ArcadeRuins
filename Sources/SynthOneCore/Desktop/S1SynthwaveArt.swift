//  The synthwave drawing kit the skins share (P7, ADR-046; trimmed at P7-7, ADR-051).
//
//  **New, not ported.** Seeded pseudo-random Core Graphics: a sun with the genre's cuts, ranges
//  of neon-edged peaks, a perspective floor, a starfield, an arcade joystick, scanlines, and the
//  screen bezel a skin can put round a list or a pad. Every random element runs from a seeded
//  generator, so a render is the same twice, and nothing is a bitmap, so it is crisp at any size.
//
//  Written for the Arcade skin (ADR-046) and kept when the owner dropped that skin (ADR-051):
//  Neon Ruins draws with all of it. The Arcade-only pieces — its palette, its header and browser
//  art, its drawn "ARCADE RUINS" wordmark and its grunge tile — went with the skin. They are in
//  the history if they are ever wanted: `git show bf8a08a`.

import UIKit

enum S1SynthwaveArt {

    static let orange = S1CabinetSkin.orange
    static let cyan = S1CabinetSkin.cyan
    static let magenta = S1CabinetSkin.pink
    static let sunTop = UIColor(hex: 0xffd66b)
    static let sunBottom = UIColor(hex: 0xff3d81)
    static let skyTop = UIColor(hex: 0x1c1038)
    static let skyBottom = UIColor(hex: 0x3a1650)
    static let ground = UIColor(hex: 0x0a0712)

    /// A deterministic pseudo-random sequence (a linear congruential generator).
    struct Seed {
        private var state: UInt32
        init(_ seed: UInt32) { state = seed }
        mutating func next() -> CGFloat {
            state = state &* 1_664_525 &+ 1_013_904_223
            return CGFloat(state >> 8) / CGFloat(1 << 24)
        }
    }

    /// One dark line every three points, over a screen.
    static let scanlines: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 4, height: 3), format: format).image { context in
            context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.16).cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 2, width: 4, height: 1))
        }
    }()

    /// A perspective floor: lines from the bottom edge to a vanishing point, and horizontals
    /// spaced tighter towards the horizon.
    static func drawGrid(_ c: CGContext, in rect: CGRect, horizon: CGFloat, vanishingX: CGFloat,
                         colour: UIColor, alpha: CGFloat, verticals: Int = 24, horizontals: Int = 9) {
        c.saveGState()
        c.clip(to: CGRect(x: rect.minX, y: horizon, width: rect.width, height: rect.maxY - horizon))
        c.setStrokeColor(colour.withAlphaComponent(alpha).cgColor)
        c.setLineWidth(1)
        let spread = rect.width * 2.2
        for i in 0...verticals {
            let x = rect.minX - spread / 2 + rect.width / 2 + spread * CGFloat(i) / CGFloat(verticals)
            c.move(to: CGPoint(x: vanishingX, y: horizon))
            c.addLine(to: CGPoint(x: x, y: rect.maxY + 40))
        }
        c.strokePath()
        let depth = rect.maxY - horizon
        for i in 1...horizontals {
            let t = CGFloat(i) / CGFloat(horizontals)
            let y = horizon + depth * t * t
            c.setStrokeColor(colour.withAlphaComponent(alpha * (0.35 + 0.65 * t)).cgColor)
            c.move(to: CGPoint(x: rect.minX, y: y.rounded() + 0.5))
            c.addLine(to: CGPoint(x: rect.maxX, y: y.rounded() + 0.5))
            c.strokePath()
        }
        c.restoreGState()
    }

    /// A sun with the horizontal cuts of the genre, glowing.
    static func drawSun(_ c: CGContext, centre: CGPoint, radius: CGFloat, ground: UIColor) {
        let disc = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
        c.saveGState()
        c.setShadow(offset: .zero, blur: radius * 0.9, color: sunBottom.withAlphaComponent(0.8).cgColor)
        c.setFillColor(sunBottom.cgColor)
        c.fillEllipse(in: disc)
        c.restoreGState()
        c.saveGState()
        c.addEllipse(in: disc)
        c.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [sunTop.cgColor, UIColor(hex: 0xff8a3d).cgColor, sunBottom.cgColor] as CFArray,
                                     locations: [0, 0.55, 1]) {
            c.drawLinearGradient(gradient, start: CGPoint(x: centre.x, y: disc.minY), end: CGPoint(x: centre.x, y: disc.maxY), options: [])
        }
        // Cuts: thin at the equator, wider towards the bottom
        c.setFillColor(ground.cgColor)
        var y = centre.y + radius * 0.05
        var gap: CGFloat = 1.5
        while y < disc.maxY {
            c.fill(CGRect(x: disc.minX, y: y, width: disc.width, height: gap))
            y += gap + max(3, radius * 0.16 - gap)
            gap += 1.2
        }
        c.restoreGState()
    }

    /// A range of dark peaks with a neon edge.
    static func drawMountains(_ c: CGContext, in rect: CGRect, baseline: CGFloat, seed seedValue: UInt32,
                              height: CGFloat, edge: UIColor, fill: UIColor) {
        var seed = Seed(seedValue)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX - 2, y: baseline))
        var x = rect.minX - 2
        while x < rect.maxX + 2 {
            let step = 18 + seed.next() * 40
            x += step
            let y = baseline - height * (0.25 + seed.next() * 0.75)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX + 2, y: baseline))
        path.close()
        c.saveGState()
        c.setFillColor(fill.cgColor)
        c.addPath(path.cgPath)
        c.fillPath()
        c.setStrokeColor(edge.cgColor)
        c.setLineWidth(1)
        c.setShadow(offset: .zero, blur: 4, color: edge.withAlphaComponent(0.9).cgColor)
        c.addPath(path.cgPath)
        c.strokePath()
        c.restoreGState()
    }

    /// A joystick, bottom right: base, shaft, ball, two buttons.
    static func drawJoystick(_ c: CGContext, in b: CGRect) {
        let base = CGRect(x: b.maxX - 92, y: b.maxY - 34, width: 70, height: 16)
        c.saveGState()
        c.setFillColor(UIColor(hex: 0x1e1430).cgColor)
        c.setStrokeColor(S1SynthwaveArt.orange.withAlphaComponent(0.9).cgColor)
        c.setShadow(offset: .zero, blur: 5, color: S1SynthwaveArt.orange.withAlphaComponent(0.6).cgColor)
        c.addPath(UIBezierPath(roundedRect: base, cornerRadius: 4).cgPath); c.fillPath()
        c.addPath(UIBezierPath(roundedRect: base, cornerRadius: 4).cgPath); c.strokePath()
        let shaftX = base.minX + 18
        c.setLineWidth(3)
        c.setStrokeColor(UIColor(hex: 0xb8a8c8).cgColor)
        c.move(to: CGPoint(x: shaftX, y: base.minY)); c.addLine(to: CGPoint(x: shaftX + 6, y: base.minY - 26)); c.strokePath()
        c.setFillColor(UIColor(hex: 0xff2b4d).cgColor)
        c.setShadow(offset: .zero, blur: 6, color: UIColor(hex: 0xff2b4d).cgColor)
        c.fillEllipse(in: CGRect(x: shaftX - 1, y: base.minY - 38, width: 14, height: 14))
        for (i, colour) in [S1SynthwaveArt.cyan, S1SynthwaveArt.orange].enumerated() {
            c.setFillColor(colour.cgColor)
            c.setShadow(offset: .zero, blur: 5, color: colour.cgColor)
            c.fillEllipse(in: CGRect(x: base.minX + 38 + CGFloat(i) * 14, y: base.minY + 3, width: 9, height: 9))
        }
        c.restoreGState()
    }

    static func drawStars(_ c: CGContext, in rect: CGRect, count: Int, seed seedValue: UInt32) {
        var seed = Seed(seedValue)
        for _ in 0..<count {
            let x = rect.minX + seed.next() * rect.width, y = rect.minY + seed.next() * rect.height
            let size = 0.6 + seed.next() * 1.4
            c.setFillColor(UIColor.white.withAlphaComponent(0.25 + seed.next() * 0.6).cgColor)
            c.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
        }
    }
}

/// A screen bezel: a glowing frame round a view, with scanlines over it.
final class S1CRTFrame: UIView {

    let content: UIView
    private let scanlines = UIView()

    init(content: UIView, accent: UIColor, cornerRadius: CGFloat = 6) {
        self.content = content
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = cornerRadius
        layer.borderWidth = 1
        layer.borderColor = accent.withAlphaComponent(0.9).cgColor
        layer.shadowColor = accent.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 6
        layer.shadowOffset = .zero
        content.translatesAutoresizingMaskIntoConstraints = false
        content.layer.cornerRadius = cornerRadius
        content.layer.borderWidth = 0
        content.layer.masksToBounds = true
        addSubview(content)
        scanlines.backgroundColor = UIColor(patternImage: S1SynthwaveArt.scanlines)
        scanlines.isUserInteractionEnabled = false
        scanlines.layer.cornerRadius = cornerRadius
        scanlines.layer.masksToBounds = true
        scanlines.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scanlines)
        for view in [content, scanlines] {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }
}
