//  The Neon Ruins skin's decoration, drawn in code (P7-4, ADR-048).
//
//  **New, not ported.** The owner's second synthwave reference (2026-09-13/14) went further
//  than the skin it replaced: near-black panels behind hot two-point neon borders, one neon colour
//  per section, worn metal rather than rust, a saturated sunset behind the toolbar, the floor
//  grid showing through the play bar, and the owner's own wordmark lit. Designed on a canvas
//  first (the Neon Ruins Skin artifact), then drawn here with Core Graphics from seeded
//  sequences, with `S1SynthwaveArt`, so a render is the same twice and crisp at any scale.

import UIKit

enum S1NeonRuinsArt {

    static let orange = S1NeonRuinsSkin.orange
    static let cyan = S1NeonRuinsSkin.cyan
    static let pink = S1NeonRuinsSkin.pink

    /// Worn metal: dark cracks with a pale edge, brushed scratches, sparse light and dark
    /// specks and a fine grain. Neutral on purpose — the first pass on the canvas tinted the
    /// panels orange and read as reflected glow rather than a surface. Tiled over the sections.
    static let grime: UIImage = {
        let side: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let c = context.cgContext
            var seed = S1SynthwaveArt.Seed(0x9E0F_5EED)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            // Cracks: random walks, dark with a pale offset edge
            for _ in 0..<7 {
                var x = seed.next() * side, y = seed.next() * side
                var angle = seed.next() * .pi * 2
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x, y: y))
                for _ in 0..<(18 + Int(seed.next() * 22)) {
                    angle += (seed.next() - 0.5) * 1.2
                    let length = 3 + seed.next() * 9
                    x += cos(angle) * length
                    y += sin(angle) * length
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                c.saveGState()
                c.translateBy(x: 0.8, y: 0.8)
                c.setStrokeColor(UIColor.white.withAlphaComponent(0.10).cgColor)
                c.setLineWidth(0.7)
                c.addPath(path.cgPath)
                c.strokePath()
                c.restoreGState()
                c.setStrokeColor(UIColor.black.withAlphaComponent(0.55).cgColor)
                c.setLineWidth(1.4)
                c.addPath(path.cgPath)
                c.strokePath()
            }
            // Brushed scratches: near-horizontal, faint
            for _ in 0..<44 {
                let x = seed.next() * side, y = seed.next() * side
                let length = 16 + seed.next() * 80
                let angle = (seed.next() - 0.5) * 0.12
                c.setStrokeColor(UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 0.035 + seed.next() * 0.05).cgColor)
                c.setLineWidth(0.4 + seed.next() * 0.5)
                c.move(to: CGPoint(x: x, y: y))
                c.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
                c.strokePath()
            }
            // Specks
            for _ in 0..<200 {
                let x = seed.next() * side, y = seed.next() * side, size = 0.5 + seed.next() * 0.9
                c.setFillColor(UIColor.white.withAlphaComponent(0.10 + seed.next() * 0.25).cgColor)
                c.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
            }
            for _ in 0..<260 {
                let x = seed.next() * side, y = seed.next() * side, size = 0.6 + seed.next() * 1.2
                c.setFillColor(UIColor.black.withAlphaComponent(0.3 + seed.next() * 0.35).cgColor)
                c.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
            }
            // Grain
            for _ in 0..<2_600 {
                let x = seed.next() * side, y = seed.next() * side
                let light = seed.next() < 0.5
                c.setFillColor((light ? UIColor.white : UIColor.black).withAlphaComponent(0.02 + seed.next() * 0.04).cgColor)
                c.fill(CGRect(x: x, y: y, width: 0.7, height: 0.7))
            }
        }
    }()

    /// A palm silhouette in neon: a curved trunk and six fronds.
    static func drawPalm(_ c: CGContext, base: CGPoint, height: CGFloat, colour: UIColor) {
        let top = CGPoint(x: base.x + height * 0.14, y: base.y - height)
        let path = UIBezierPath()
        path.move(to: base)
        path.addCurve(to: top, controlPoint1: CGPoint(x: base.x + height * 0.02, y: base.y - height * 0.35),
                      controlPoint2: CGPoint(x: base.x + height * 0.08, y: base.y - height * 0.7))
        let fronds: [(dx: CGFloat, dy: CGFloat, cx: CGFloat, cy: CGFloat)] = [
            (-0.55, 0.10, -0.20, -0.18), (-0.45, -0.20, -0.15, -0.28), (0.45, -0.16, 0.15, -0.28),
            (0.50, 0.14, 0.25, -0.16), (0.18, 0.45, 0.22, 0.10), (-0.22, 0.42, -0.25, 0.08)
        ]
        for f in fronds {
            path.move(to: top)
            path.addQuadCurve(to: CGPoint(x: top.x + f.dx * height, y: top.y + f.dy * height),
                              controlPoint: CGPoint(x: top.x + f.cx * height, y: top.y + f.cy * height))
        }
        c.saveGState()
        c.setStrokeColor(colour.cgColor)
        c.setLineWidth(1.4)
        c.setLineCap(.round)
        c.setShadow(offset: .zero, blur: 4, color: colour.cgColor)
        c.addPath(path.cgPath)
        c.strokePath()
        c.restoreGState()
    }

    /// A perspective floor with a glow, fading out towards the horizon.
    static func drawFloor(_ c: CGContext, in b: CGRect, horizon: CGFloat, colour: UIColor, alpha: CGFloat,
                          verticals: Int, horizontals: Int, fade: CGFloat) {
        c.saveGState()
        c.setShadow(offset: .zero, blur: 3, color: colour.withAlphaComponent(alpha * 0.8).cgColor)
        S1SynthwaveArt.drawGrid(c, in: b, horizon: horizon, vanishingX: b.midX, colour: colour, alpha: alpha,
                             verticals: verticals, horizontals: horizontals)
        c.restoreGState()
        if fade > 0, let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                               colors: [S1NeonRuinsSkin.night.cgColor, S1NeonRuinsSkin.night.withAlphaComponent(0).cgColor] as CFArray,
                                               locations: [0, 1]) {
            c.drawLinearGradient(gradient, start: CGPoint(x: b.midX, y: horizon), end: CGPoint(x: b.midX, y: horizon + fade), options: [])
        }
    }

    /// A soft coloured light, for the nebulae behind the window and the sun's halo.
    static func drawGlow(_ c: CGContext, centre: CGPoint, radius: CGFloat, colour: UIColor, alpha: CGFloat) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [colour.withAlphaComponent(alpha).cgColor, colour.withAlphaComponent(alpha * 0.35).cgColor,
                                                 colour.withAlphaComponent(0).cgColor] as CFArray,
                                        locations: [0, 0.4, 1]) else { return }
        c.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius, options: [])
    }
}

/// The toolbar's backdrop: a saturated sunset sky, the sun on the horizon between the wordmark
/// and the preset navigator, two mountain ranges, a hot magenta grid, a palm in the gap before
/// the toolbar's buttons. Dimmed only where controls sit over it.
final class S1NeonRuinsHeaderArt: UIView {

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
                                colors: [UIColor(hex: 0x1c0c40).cgColor, UIColor(hex: 0x4a1466).cgColor,
                                         UIColor(hex: 0x8a1e62).cgColor, UIColor(hex: 0xe0405a).cgColor] as CFArray,
                                locations: [0, 0.45, 0.75, 1]) {
            c.drawLinearGradient(sky, start: CGPoint(x: b.midX, y: b.minY), end: CGPoint(x: b.midX, y: b.maxY), options: [])
        }
        S1SynthwaveArt.drawStars(c, in: CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height * 0.55), count: 110, seed: 0x5EED)
        let horizon = (b.height * 0.75).rounded()
        // Horizon glow
        if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [UIColor(hex: 0xff7850, alpha: 0).cgColor, UIColor(hex: 0xff7850, alpha: 0.45).cgColor] as CFArray,
                                 locations: [0, 1]) {
            c.drawLinearGradient(glow, start: CGPoint(x: b.midX, y: horizon - 22), end: CGPoint(x: b.midX, y: horizon), options: [])
        }
        // The sun sits in the gap between the wordmark and the preset navigator at the design width
        let sun = CGPoint(x: b.width * 0.255, y: horizon - b.height * 0.27)
        S1NeonRuinsArt.drawGlow(c, centre: sun, radius: b.height * 0.9, colour: UIColor(hex: 0xff8c5a), alpha: 0.8)
        S1SynthwaveArt.drawSun(c, centre: sun, radius: b.height * 0.46, ground: S1NeonRuinsSkin.night)
        S1SynthwaveArt.drawMountains(c, in: b, baseline: horizon + 1, seed: 0xA11CE, height: b.height * 0.46,
                                  edge: S1NeonRuinsArt.pink, fill: UIColor(hex: 0x150b22))
        S1SynthwaveArt.drawMountains(c, in: b, baseline: horizon + 1, seed: 0xA11CE, height: b.height * 0.46,
                                  edge: S1NeonRuinsArt.pink.withAlphaComponent(0.6), fill: UIColor(hex: 0x150b22))
        S1SynthwaveArt.drawMountains(c, in: b, baseline: horizon + 1, seed: 0xB0B, height: b.height * 0.19,
                                  edge: S1NeonRuinsArt.cyan.withAlphaComponent(0.85), fill: S1NeonRuinsSkin.night)
        c.setFillColor(S1NeonRuinsSkin.night.cgColor)
        c.fill(CGRect(x: b.minX, y: horizon, width: b.width, height: b.maxY - horizon))
        S1NeonRuinsArt.drawFloor(c, in: b, horizon: horizon, colour: S1NeonRuinsArt.pink, alpha: 0.95,
                                 verticals: 44, horizontals: 6, fade: 0)
        c.saveGState()
        c.setStrokeColor(S1NeonRuinsArt.cyan.cgColor)
        c.setShadow(offset: .zero, blur: 6, color: S1NeonRuinsArt.cyan.cgColor)
        c.setLineWidth(1)
        c.move(to: CGPoint(x: b.minX, y: horizon + 0.5)); c.addLine(to: CGPoint(x: b.maxX, y: horizon + 0.5))
        c.strokePath()
        c.restoreGState()
        // A palm in the gap between the scope and the buttons
        S1NeonRuinsArt.drawPalm(c, base: CGPoint(x: b.width * 0.77, y: horizon + 2), height: b.height * 0.7, colour: S1NeonRuinsArt.cyan)
        // Dim under the wordmark, the navigator and the buttons; clear in the gaps
        let stops: [(CGFloat, CGFloat)] = [(0, 0.6), (0.2, 0.45), (0.215, 0), (0.29, 0), (0.31, 0.3), (0.715, 0.3), (0.73, 0), (0.815, 0), (0.83, 0.3), (1, 0.3)]
        if let dim = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: stops.map { UIColor.black.withAlphaComponent($0.1).cgColor } as CFArray,
                                locations: stops.map { $0.0 }) {
            c.drawLinearGradient(dim, start: CGPoint(x: b.minX, y: b.midY), end: CGPoint(x: b.maxX, y: b.midY), options: [])
        }
    }
}

/// Behind the preset browser's column: a starfield over a lit cyan floor, a joystick.
final class S1NeonRuinsPanelArt: UIView {

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
        S1NeonRuinsArt.drawFloor(c, in: b, horizon: horizon, colour: S1NeonRuinsArt.cyan, alpha: 0.7,
                                 verticals: 16, horizontals: 12, fade: b.height * 0.28)
        S1SynthwaveArt.drawJoystick(c, in: b)
        c.setFillColor(UIColor.black.withAlphaComponent(0.25).cgColor)
        c.fill(b)
    }
}

/// Behind the whole window: nebulae in the corners, faint stars, and a magenta floor that shows
/// through the translucent play bar and status bar and in the gaps between the rows.
final class S1NeonRuinsBackdropArt: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        let b = bounds
        c.setFillColor(S1NeonRuinsSkin.night.cgColor)
        c.fill(b)
        S1NeonRuinsArt.drawGlow(c, centre: CGPoint(x: b.width * 0.06, y: b.maxY), radius: b.width * 0.42, colour: UIColor(hex: 0xbe28e6), alpha: 0.5)
        S1NeonRuinsArt.drawGlow(c, centre: CGPoint(x: b.width * 0.97, y: b.maxY), radius: b.width * 0.38, colour: UIColor(hex: 0xff5a14), alpha: 0.38)
        S1NeonRuinsArt.drawGlow(c, centre: CGPoint(x: b.midX, y: b.minY), radius: b.width * 0.5, colour: S1NeonRuinsArt.pink, alpha: 0.28)
        S1NeonRuinsArt.drawGlow(c, centre: CGPoint(x: b.maxX, y: b.height * 0.4), radius: b.width * 0.3, colour: S1NeonRuinsArt.cyan, alpha: 0.14)
        S1NeonRuinsArt.drawGlow(c, centre: CGPoint(x: b.minX, y: b.height * 0.4), radius: b.width * 0.3, colour: S1NeonRuinsArt.pink, alpha: 0.18)
        S1SynthwaveArt.drawStars(c, in: b, count: 70, seed: 0xBAC)
        let horizon = (b.maxY - 150).rounded()
        S1NeonRuinsArt.drawFloor(c, in: b, horizon: horizon, colour: S1NeonRuinsArt.pink, alpha: 0.6,
                                 verticals: 30, horizontals: 8, fade: 80)
    }
}

/// The owner's wordmark, lit: the artwork with an orange glow behind it, at the toolbar's height.
final class S1NeonRuinsWordmark: UIView {

    static let imageName = "s1_wordmark_neon"

    private let bloom = UIImageView()
    private let mark = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = "Arcade Ruins"
        let image = UIImage.synthOne(Self.imageName)
        for (view, radius, opacity) in [(bloom, CGFloat(14), Float(0.55)), (mark, CGFloat(5), Float(0.95))] {
            view.image = image
            view.contentMode = .scaleAspectFit
            view.translatesAutoresizingMaskIntoConstraints = false
            view.layer.shadowColor = S1NeonRuinsArt.orange.cgColor
            view.layer.shadowOpacity = opacity
            view.layer.shadowRadius = radius
            view.layer.shadowOffset = .zero
            addSubview(view)
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
}
