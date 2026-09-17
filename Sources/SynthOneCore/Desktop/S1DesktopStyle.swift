//  How the desktop layout draws a knob and a switch (P6, ADR-045).
//
//  **New, not ported.** The classic controls draw with PaintCode style kits
//  (`KnobStyleKit`, `ToggleButtonStyleKit`). The desktop look — a value arc round a
//  brushed cap, a pill switch — is drawn here in Core Graphics and reached through a
//  flag on the control (`Knob.drawsDesktopStyle`, `ToggleButton.drawsAsSwitch`), so the
//  same instance, bindings and gestures serve both layouts. P7 (ADR-046): the colours are
//  the skin's palette and every glow is scaled by the skin's `glow`. P7-4 (ADR-048): every
//  drawing takes the control's `accent` — its section's under a skin that names one, the
//  palette's otherwise (`UIView.s1Accent`) — and a skin whose dress says `litFromAccent`
//  derives its lit colours from that accent instead of the palette's fixed entries.

import UIKit

enum S1DesktopStyle {

    /// P7-12 (ADR-062): set by `UIView.s1Accent` as each control fetches its accent on the way
    /// into a draw, so a control in a zone without power draws from the palette's grey twin and
    /// with no glow. Every drawing here takes `accent: s1Accent`, which is what makes this sound.
    static var unpowered = false
    private static var greyPalette: (of: S1SkinChoice, palette: S1Palette)?
    private static var p: S1Palette {
        let skin = S1Skins.current
        guard unpowered else { return skin.palette }
        if let cached = greyPalette, cached.of == skin.choice { return cached.palette }
        let grey = skin.palette.greyed()
        greyPalette = (skin.choice, grey)
        return grey
    }
    private static var glow: CGFloat { unpowered ? 0 : S1Skins.current.glow }
    private static var dress: S1SkinDress { S1Skins.current.dress }

    // MARK: - Colours from an accent (P7-4)

    /// A lit cell's top, bottom and border.
    private static func lit(_ accent: UIColor) -> (top: UIColor, bottom: UIColor, border: UIColor) {
        dress.litFromAccent
            ? (accent.mixed(with: .black, 0.38), accent.mixed(with: .black, 0.64), accent.mixed(with: .white, 0.45))
            : (p.litTop, p.litBottom, p.litBorder)
    }

    private static func plate(_ accent: UIColor) -> (top: UIColor, bottom: UIColor) {
        dress.litFromAccent ? (accent.mixed(with: .black, 0.38), accent.mixed(with: .black, 0.64)) : (p.plateTop, p.plateBottom)
    }

    private static func chipActive(_ accent: UIColor) -> (top: UIColor, bottom: UIColor) {
        dress.litFromAccent ? (accent.mixed(with: .black, 0.38), accent.mixed(with: .black, 0.64)) : (p.chipActiveTop, p.chipActiveBottom)
    }

    private static func accentLight(_ accent: UIColor) -> UIColor {
        dress.litFromAccent ? accent.mixed(with: .white, 0.35) : p.accentLight
    }

    private static func accentBorder(_ accent: UIColor) -> UIColor {
        dress.litFromAccent ? accent.mixed(with: .white, 0.45) : p.accentBorder
    }

    private static func accentOnTop(_ accent: UIColor) -> UIColor {
        dress.litFromAccent ? accent.mixed(with: .white, 0.3) : p.accentOnTop
    }

    private static func knobTrack(_ accent: UIColor) -> UIColor {
        dress.litFromAccent ? accent.withAlphaComponent(0.26) : p.knobTrack
    }

    private static func faderCap(_ accent: UIColor) -> (top: UIColor, bottom: UIColor, border: UIColor) {
        dress.litFromAccent
            ? (accent.mixed(with: .white, 0.35), accent.mixed(with: .black, 0.3), accent.mixed(with: .white, 0.7))
            : (p.faderCapTop, p.faderCapBottom, p.faderCapBorder)
    }

    private static func faderTick(_ accent: UIColor) -> UIColor {
        dress.litFromAccent ? accent.withAlphaComponent(0.5) : p.faderTick
    }

    /// A selected step-number box's face and border (P6-3's inline colours, per accent since P7-4).
    static func numberBox(on: Bool, accent: UIColor) -> (face: UIColor, border: UIColor?) {
        if dress.litFromAccent {
            return on ? (accent.mixed(with: .black, 0.2), accent.mixed(with: .white, 0.45))
                      : (p.stepOffTop.mixed(with: p.stepOffBottom, 0.5), accent)
        }
        return (on ? UIColor(hex: 0x4a3410) : UIColor(hex: 0x333336), nil)
    }

    /// A segmented control's selected face (P6-2), per accent since P7-4.
    static func segmentFace(accent: UIColor) -> (face: UIColor, border: UIColor) {
        dress.litFromAccent ? (lit(accent).top, accent) : (p.buttonTop, p.wellBorder)
    }

    // MARK: - Knob

    /// The arc runs from 7:30 round to 4:30, as the classic knob's indicator does.
    private static let arcStart: CGFloat = .pi * 0.75
    private static let arcSweep: CGFloat = .pi * 1.5

    static func drawKnob(in rect: CGRect, value: CGFloat, accent: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let side = min(rect.width, rect.height)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let ringWidth = max(2.5, side * 0.07) * dress.knobRingScale
        let ringRadius = side / 2 - ringWidth / 2 - 0.5
        let clamped = max(0, min(1, value))

        // Halo (P7-4): a soft disc of the accent round the whole knob
        if dress.knobHalo {
            context.saveGState()
            context.setShadow(offset: .zero, blur: 5 * glow, color: accent.withAlphaComponent(0.7).cgColor)
            context.setStrokeColor(accent.withAlphaComponent(0.18).cgColor)
            context.setLineWidth(ringWidth)
            context.addArc(center: centre, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            context.strokePath()
            context.restoreGState()
        }

        // Track
        context.saveGState()
        context.setLineWidth(ringWidth)
        context.setLineCap(.round)
        context.setStrokeColor(knobTrack(accent).cgColor)
        context.addArc(center: centre, radius: ringRadius, startAngle: arcStart, endAngle: arcStart + arcSweep, clockwise: false)
        context.strokePath()

        // Value arc, with a glow
        if clamped > 0.001 {
            context.setShadow(offset: .zero, blur: 4 * glow, color: accent.withAlphaComponent(0.55).cgColor)
            context.setStrokeColor(accent.cgColor)
            context.addArc(center: centre, radius: ringRadius, startAngle: arcStart, endAngle: arcStart + arcSweep * clamped, clockwise: false)
            context.strokePath()
            if dress.knobHalo {
                // A bright core along the tube
                context.setShadow(offset: .zero, blur: 0, color: nil)
                context.setLineWidth(ringWidth * 0.35)
                context.setStrokeColor(accent.mixed(with: .white, 0.45).withAlphaComponent(0.85).cgColor)
                context.addArc(center: centre, radius: ringRadius, startAngle: arcStart, endAngle: arcStart + arcSweep * clamped, clockwise: false)
                context.strokePath()
            }
        }
        context.restoreGState()

        // Cap: drop shadow, radial gradient, hairline border
        let capRadius = ringRadius - ringWidth / 2 - max(3, side * 0.09)
        let capRect = CGRect(x: centre.x - capRadius, y: centre.y - capRadius, width: capRadius * 2, height: capRadius * 2)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: capRadius * 0.12), blur: capRadius * 0.3, color: UIColor.black.withAlphaComponent(0.7).cgColor)
        context.setFillColor(p.knobCapFill.cgColor)
        context.fillEllipse(in: capRect)
        context.restoreGState()

        context.saveGState()
        context.addEllipse(in: capRect)
        context.clip()
        let colours = p.knobCap.map { $0.cgColor } as CFArray
        let locations: [CGFloat] = [0, 0.45, 0.75, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: locations) {
            let highlight = CGPoint(x: capRect.minX + capRect.width * 0.38, y: capRect.minY + capRect.height * 0.30)
            context.drawRadialGradient(gradient, startCenter: highlight, startRadius: 0,
                                       endCenter: centre, endRadius: capRadius * 1.05, options: [.drawsAfterEndLocation])
        }
        // Brushed grain: faint spokes
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.035).cgColor)
        context.setLineWidth(0.5)
        for i in stride(from: 0, to: 360, by: 3) {
            let a = CGFloat(i) * .pi / 180
            context.move(to: CGPoint(x: centre.x + cos(a) * capRadius * 0.35, y: centre.y + sin(a) * capRadius * 0.35))
            context.addLine(to: CGPoint(x: centre.x + cos(a) * capRadius, y: centre.y + sin(a) * capRadius))
        }
        context.strokePath()
        // Top highlight
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.16).cgColor)
        context.setLineWidth(1)
        context.addArc(center: centre, radius: capRadius - 1, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(p.knobCapBorder.cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: capRect.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()

        // Indicator
        let angle = arcStart + arcSweep * clamped
        let outer = capRadius - max(2, side * 0.05)
        let inner = capRadius * 0.55
        context.saveGState()
        context.setShadow(offset: .zero, blur: 3 * glow, color: accent.withAlphaComponent(0.7).cgColor)
        context.setStrokeColor((p.knobPointer ?? accent).cgColor)
        context.setLineWidth(max(2, side * 0.06))
        context.setLineCap(.round)
        context.move(to: CGPoint(x: centre.x + cos(angle) * inner, y: centre.y + sin(angle) * inner))
        context.addLine(to: CGPoint(x: centre.x + cos(angle) * outer, y: centre.y + sin(angle) * outer))
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - LFO target chip (P6-2)

    static var lfo2Colour: UIColor { p.secondAccent }   // MIDI learn's blue in Studio, cyan in Neon Ruins

    /// A labelled chip. Its left half is LFO 1, its right half LFO 2, as the classic control's
    /// hit-test divides it; an active half shows a bar along the bottom in its colour.
    static func drawLFOChip(in rect: CGRect, text: String, lfo1: Bool, lfo2: Bool, accent: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let body = rect.insetBy(dx: 0.5, dy: 0.5)
        let path = UIBezierPath(roundedRect: body, cornerRadius: 4)
        context.saveGState()
        path.addClip()
        let active = lfo1 || lfo2
        let lit = chipActive(accent)
        let colours: [CGColor] = active
            ? [lit.top.cgColor, lit.bottom.cgColor]
            : [p.chipTop.cgColor, p.chipBottom.cgColor]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: body.midX, y: body.minY),
                                       end: CGPoint(x: body.midX, y: body.maxY), options: [])
        }
        let bar = CGRect(x: body.minX, y: body.maxY - 3, width: body.width / 2, height: 3)
        if lfo1 {
            context.setFillColor(accent.cgColor)
            context.fill(bar)
        }
        if lfo2 {
            context.setFillColor(lfo2Colour.cgColor)
            context.fill(bar.offsetBy(dx: body.width / 2, dy: 0))
        }
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor((active ? accentBorder(accent) : p.chipBorder).cgColor)
        context.setLineWidth(1)
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: S1DesktopTheme.font(10.5, weight: active ? .medium : .regular),
            .foregroundColor: active ? S1DesktopTheme.text : p.chipText,
            .paragraphStyle: paragraph
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let textRect = CGRect(x: body.minX, y: body.midY - size.height / 2 - 1, width: body.width, height: size.height)
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }

    // MARK: - LFO wave picker (P6-2)

    /// Four cells — sine, square, ramp up, ramp down — the selected one raised and orange.
    static func drawWavePicker(in rect: CGRect, selected: Int, accent: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let cellWidth = rect.width / 4
        let plateColours = plate(accent)
        for index in 0..<4 {
            let cell = CGRect(x: rect.minX + CGFloat(index) * cellWidth, y: rect.minY, width: cellWidth, height: rect.height).insetBy(dx: 1, dy: 0)
            let on = index == selected
            if on {
                context.saveGState()
                let plate = UIBezierPath(roundedRect: cell, cornerRadius: 4)
                plate.addClip()
                let colours = [plateColours.top.cgColor, plateColours.bottom.cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1]) {
                    context.drawLinearGradient(gradient, start: CGPoint(x: cell.midX, y: cell.minY),
                                               end: CGPoint(x: cell.midX, y: cell.maxY), options: [])
                }
                context.restoreGState()
                context.saveGState()
                context.setStrokeColor((dress.litFromAccent ? accentBorder(accent) : p.chipBorder).cgColor)
                context.setLineWidth(1)
                context.addPath(UIBezierPath(roundedRect: cell.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4).cgPath)
                context.strokePath()
                context.restoreGState()
            }
            let glyph = cell.insetBy(dx: cellWidth * 0.22, dy: rect.height * 0.28)
            let path = UIBezierPath()
            switch index {
            case 0:   // sine
                path.move(to: CGPoint(x: glyph.minX, y: glyph.midY))
                path.addCurve(to: CGPoint(x: glyph.midX, y: glyph.midY),
                              controlPoint1: CGPoint(x: glyph.minX + glyph.width * 0.25, y: glyph.minY - glyph.height * 0.4),
                              controlPoint2: CGPoint(x: glyph.midX - glyph.width * 0.25, y: glyph.minY - glyph.height * 0.4))
                path.addCurve(to: CGPoint(x: glyph.maxX, y: glyph.midY),
                              controlPoint1: CGPoint(x: glyph.midX + glyph.width * 0.25, y: glyph.maxY + glyph.height * 0.4),
                              controlPoint2: CGPoint(x: glyph.maxX - glyph.width * 0.25, y: glyph.maxY + glyph.height * 0.4))
            case 1:   // square
                path.move(to: CGPoint(x: glyph.minX, y: glyph.maxY))
                path.addLine(to: CGPoint(x: glyph.minX, y: glyph.minY))
                path.addLine(to: CGPoint(x: glyph.midX, y: glyph.minY))
                path.addLine(to: CGPoint(x: glyph.midX, y: glyph.maxY))
                path.addLine(to: CGPoint(x: glyph.maxX, y: glyph.maxY))
                path.addLine(to: CGPoint(x: glyph.maxX, y: glyph.minY))
            case 2:   // ramp up
                path.move(to: CGPoint(x: glyph.minX, y: glyph.maxY))
                path.addLine(to: CGPoint(x: glyph.maxX, y: glyph.minY))
                path.addLine(to: CGPoint(x: glyph.maxX, y: glyph.maxY))
            default:  // ramp down
                path.move(to: CGPoint(x: glyph.minX, y: glyph.minY))
                path.addLine(to: CGPoint(x: glyph.minX, y: glyph.maxY))
                path.addLine(to: CGPoint(x: glyph.maxX, y: glyph.minY))
            }
            context.saveGState()
            if on { context.setShadow(offset: .zero, blur: 4 * glow, color: accent.withAlphaComponent(0.5).cgColor) }
            context.setStrokeColor((on ? (dress.litFromAccent ? .white : accent) : p.glyph).cgColor)
            context.setLineWidth(1.6)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.addPath(path.cgPath)
            context.strokePath()
            context.restoreGState()
        }
    }

    // MARK: - Sequencer (P6-3)

    private static func fillRounded(_ context: CGContext, _ rect: CGRect, radius: CGFloat, top: UIColor, bottom: UIColor, border: UIColor) {
        let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius)
        context.saveGState()
        path.addClip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        }
        context.restoreGState()
        context.saveGState()
        context.setStrokeColor(border.cgColor)
        context.setLineWidth(1)
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawText(_ text: String, in rect: CGRect, size: CGFloat, weight: S1DesktopTheme.Weight = .regular, colour: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: S1DesktopTheme.font(size, weight: weight), .foregroundColor: colour, .paragraphStyle: paragraph
        ]
        let height = (text as NSString).size(withAttributes: attributes).height
        (text as NSString).draw(in: CGRect(x: rect.minX, y: rect.midY - height / 2 - 0.5, width: rect.width, height: height),
                                withAttributes: attributes)
    }

    /// A raised button face, pressed or not.
    private static func drawButtonFace(_ context: CGContext, _ rect: CGRect, pressed: Bool) {
        fillRounded(context, rect, radius: 4,
                    top: pressed ? p.buttonPressedTop : p.buttonTop,
                    bottom: p.buttonBottom,
                    border: p.buttonBorder)
    }

    private static func drawGlyph(_ context: CGContext, _ path: UIBezierPath, colour: UIColor, width: CGFloat = 1.6) {
        context.saveGState()
        context.setStrokeColor(colour.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
    }

    /// `[−]  value  [+]`. `pressed` is the classic 0 / 1 (minus) / 2 (plus).
    static func drawStepper(in rect: CGRect, text: String, pressed: CGFloat) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let zones = stepperZones(in: rect)
        fillRounded(context, rect, radius: 5, top: p.wellTop, bottom: p.wellBottom, border: p.wellBorder)
        drawButtonFace(context, zones.minus.insetBy(dx: 2, dy: 2), pressed: pressed == 1)
        drawButtonFace(context, zones.plus.insetBy(dx: 2, dy: 2), pressed: pressed == 2)
        let minus = UIBezierPath()
        minus.move(to: CGPoint(x: zones.minus.midX - 4, y: zones.minus.midY))
        minus.addLine(to: CGPoint(x: zones.minus.midX + 4, y: zones.minus.midY))
        drawGlyph(context, minus, colour: S1DesktopTheme.label)
        let plus = UIBezierPath()
        plus.move(to: CGPoint(x: zones.plus.midX - 4, y: zones.plus.midY))
        plus.addLine(to: CGPoint(x: zones.plus.midX + 4, y: zones.plus.midY))
        plus.move(to: CGPoint(x: zones.plus.midX, y: zones.plus.midY - 4))
        plus.addLine(to: CGPoint(x: zones.plus.midX, y: zones.plus.midY + 4))
        drawGlyph(context, plus, colour: S1DesktopTheme.label)
        drawText(text, in: zones.value, size: 13, weight: .medium, colour: S1DesktopTheme.text)
    }

    /// Where a stepper's zones are at any size: a button either side, the value between.
    static func stepperZones(in rect: CGRect) -> (minus: CGRect, value: CGRect, plus: CGRect) {
        let button = min(rect.height, rect.width * 0.3)
        return (CGRect(x: rect.minX, y: rect.minY, width: button, height: rect.height),
                CGRect(x: rect.minX + button, y: rect.minY, width: rect.width - button * 2, height: rect.height),
                CGRect(x: rect.maxX - button, y: rect.minY, width: button, height: rect.height))
    }

    /// The tempo: a draggable display over a minus and a plus.
    static func drawTempoStepper(in rect: CGRect, text: String, pressed: CGFloat) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let zones = tempoZones(in: rect)
        fillRounded(context, zones.display, radius: 5, top: p.wellTop, bottom: p.wellBottom, border: p.wellBorder)
        drawText(text, in: zones.display, size: 14, weight: .medium, colour: S1DesktopTheme.text)
        drawButtonFace(context, zones.minus, pressed: pressed == 1)
        drawButtonFace(context, zones.plus, pressed: pressed == 2)
        let minus = UIBezierPath()
        minus.move(to: CGPoint(x: zones.minus.midX - 4, y: zones.minus.midY))
        minus.addLine(to: CGPoint(x: zones.minus.midX + 4, y: zones.minus.midY))
        drawGlyph(context, minus, colour: S1DesktopTheme.label)
        let plus = UIBezierPath()
        plus.move(to: CGPoint(x: zones.plus.midX - 4, y: zones.plus.midY))
        plus.addLine(to: CGPoint(x: zones.plus.midX + 4, y: zones.plus.midY))
        plus.move(to: CGPoint(x: zones.plus.midX, y: zones.plus.midY - 4))
        plus.addLine(to: CGPoint(x: zones.plus.midX, y: zones.plus.midY + 4))
        drawGlyph(context, plus, colour: S1DesktopTheme.label)
    }

    static func tempoZones(in rect: CGRect) -> (display: CGRect, minus: CGRect, plus: CGRect) {
        let displayHeight = (rect.height * 0.55).rounded()
        let gap: CGFloat = 4
        let buttons = CGRect(x: rect.minX, y: rect.minY + displayHeight + gap, width: rect.width, height: rect.height - displayHeight - gap)
        return (CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: displayHeight),
                CGRect(x: buttons.minX, y: buttons.minY, width: (buttons.width - gap) / 2, height: buttons.height),
                CGRect(x: buttons.midX + gap / 2, y: buttons.minY, width: (buttons.width - gap) / 2, height: buttons.height))
    }

    /// A two-way switch with a word each side: the lit side is the value.
    static func drawTwoWaySwitch(in rect: CGRect, isOn: Bool, left: String, right: String, accent: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        fillRounded(context, rect, radius: 5, top: p.wellTop, bottom: p.wellBottom, border: p.wellBorder)
        let half = CGRect(x: rect.minX + 2, y: rect.minY + 2, width: rect.width / 2 - 2, height: rect.height - 4)
        let litRect = isOn ? half.offsetBy(dx: rect.width / 2 - 2, dy: 0) : half
        let litColours = lit(accent)
        fillRounded(context, litRect, radius: 4, top: litColours.top, bottom: litColours.bottom, border: litColours.border)
        drawText(left, in: half, size: 12, weight: isOn ? .regular : .medium, colour: isOn ? S1DesktopTheme.label : S1DesktopTheme.text)
        drawText(right, in: half.offsetBy(dx: rect.width / 2 - 2, dy: 0), size: 12, weight: isOn ? .medium : .regular,
                 colour: isOn ? S1DesktopTheme.text : S1DesktopTheme.label)
    }

    /// Up · up-and-down · down, as three arrow cells.
    static func drawDirection(in rect: CGRect, selected: Int, accent: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        fillRounded(context, rect, radius: 5, top: p.wellTop, bottom: p.wellBottom, border: p.wellBorder)
        let cellWidth = rect.width / 3
        let litColours = lit(accent)
        for index in 0..<3 {
            let cell = CGRect(x: rect.minX + CGFloat(index) * cellWidth, y: rect.minY, width: cellWidth, height: rect.height).insetBy(dx: 2, dy: 2)
            let on = index == selected
            if on {
                fillRounded(context, cell, radius: 4, top: litColours.top, bottom: litColours.bottom, border: litColours.border)
            }
            let colour = on ? (dress.litFromAccent ? .white : accent) : p.glyph
            let c = CGPoint(x: cell.midX, y: cell.midY)
            let h = min(cell.height, 14) / 2
            func arrow(_ up: Bool, at x: CGFloat) -> UIBezierPath {
                let path = UIBezierPath()
                let tip = CGPoint(x: x, y: up ? c.y - h : c.y + h)
                let tail = CGPoint(x: x, y: up ? c.y + h : c.y - h)
                path.move(to: tail); path.addLine(to: tip)
                path.move(to: CGPoint(x: x - 3.5, y: up ? tip.y + 3.5 : tip.y - 3.5)); path.addLine(to: tip)
                path.addLine(to: CGPoint(x: x + 3.5, y: up ? tip.y + 3.5 : tip.y - 3.5))
                return path
            }
            switch index {
            case 0: drawGlyph(context, arrow(true, at: c.x), colour: colour)
            case 1: drawGlyph(context, arrow(true, at: c.x - 4), colour: colour); drawGlyph(context, arrow(false, at: c.x + 4), colour: colour)
            default: drawGlyph(context, arrow(false, at: c.x), colour: colour)
            }
        }
    }

    /// The sequencer fader: a ticked groove and a capped handle.
    static func drawFader(in rect: CGRect, cap: CGRect, accent: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        // Ticks
        context.saveGState()
        context.setStrokeColor(faderTick(accent).cgColor)
        context.setLineWidth(1)
        let top = rect.minY + cap.height / 2, bottom = rect.maxY - cap.height / 2
        let steps = 12
        for i in 0...steps {
            let y = (top + (bottom - top) * CGFloat(i) / CGFloat(steps)).rounded() + 0.5
            let long = i % 6 == 0
            context.move(to: CGPoint(x: rect.midX - (long ? 12 : 8), y: y))
            context.addLine(to: CGPoint(x: rect.midX - 5, y: y))
            context.move(to: CGPoint(x: rect.midX + 5, y: y))
            context.addLine(to: CGPoint(x: rect.midX + (long ? 12 : 8), y: y))
        }
        context.strokePath()
        context.restoreGState()
        // Groove
        let groove = CGRect(x: rect.midX - 2.5, y: top, width: 5, height: bottom - top)
        context.saveGState()
        UIBezierPath(roundedRect: groove, cornerRadius: 2.5).addClip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [p.grooveEdge.cgColor, p.grooveMid.cgColor, p.grooveEdge.cgColor] as CFArray,
                                     locations: [0, 0.5, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: groove.minX, y: groove.midY), end: CGPoint(x: groove.maxX, y: groove.midY), options: [])
        }
        context.restoreGState()
        // Lit track (P7-4): the groove below the cap, in the accent
        if dress.faderLitTrack, cap.midY < bottom - 1 {
            context.saveGState()
            context.setShadow(offset: .zero, blur: 3 * glow, color: accent.withAlphaComponent(0.7).cgColor)
            context.setFillColor(accent.cgColor)
            context.addPath(UIBezierPath(roundedRect: CGRect(x: rect.midX - 1.5, y: cap.midY, width: 3, height: bottom - cap.midY), cornerRadius: 1.5).cgPath)
            context.fillPath()
            context.restoreGState()
        }
        // Cap
        let capColours = faderCap(accent)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.7).cgColor)
        context.setFillColor(capColours.bottom.cgColor)
        context.addPath(UIBezierPath(roundedRect: cap, cornerRadius: 3).cgPath)
        context.fillPath()
        context.restoreGState()
        if dress.faderLitTrack {
            context.saveGState()
            context.setShadow(offset: .zero, blur: 4 * glow, color: accent.withAlphaComponent(0.8).cgColor)
            context.setFillColor(capColours.bottom.cgColor)
            context.addPath(UIBezierPath(roundedRect: cap, cornerRadius: 3).cgPath)
            context.fillPath()
            context.restoreGState()
        }
        fillRounded(context, cap, radius: 3, top: capColours.top, bottom: capColours.bottom, border: capColours.border)
        context.saveGState()
        context.setShadow(offset: .zero, blur: 3 * glow, color: accent.withAlphaComponent(0.8).cgColor)
        context.setFillColor((dress.litFromAccent ? accent.mixed(with: .black, 0.55) : accent).cgColor)
        context.fill(CGRect(x: cap.minX + 5, y: cap.midY - 1.5, width: cap.width - 10, height: 3))
        context.restoreGState()
    }

    /// A step's note-on bar.
    static func drawStepButton(in rect: CGRect, isOn: Bool, accent: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        if isOn {
            context.saveGState()
            context.setShadow(offset: .zero, blur: 5 * glow, color: accent.withAlphaComponent(0.6).cgColor)
            context.setFillColor(accent.cgColor)
            context.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2).cgPath)
            context.fillPath()
            context.restoreGState()
            fillRounded(context, rect, radius: 2, top: accentLight(accent), bottom: accent, border: accentBorder(accent))
        } else {
            fillRounded(context, rect, radius: 2, top: p.stepOffTop, bottom: p.stepOffBottom, border: p.stepOffBorder)
        }
    }

    // MARK: - Switch

    /// A pill switch drawn to fill `rect`'s width, centred vertically at a 26×14 aspect.
    static func drawSwitch(in rect: CGRect, isOn: Bool, accent: UIColor) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let width = min(rect.width, rect.height * 26 / 14)
        let height = width * 14 / 26
        let track = CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        let radius = height / 2
        let path = UIBezierPath(roundedRect: track, cornerRadius: radius)

        if isOn && glow > 1 {
            context.saveGState()
            context.setShadow(offset: .zero, blur: 5 * glow, color: accent.withAlphaComponent(0.6).cgColor)
            context.setFillColor(accent.cgColor)
            context.addPath(path.cgPath)
            context.fillPath()
            context.restoreGState()
        }
        context.saveGState()
        path.addClip()
        let colours: [CGColor] = isOn
            ? [accentOnTop(accent).cgColor, accent.cgColor]
            : [p.switchOffTop.cgColor, p.switchOffBottom.cgColor]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: track.midX, y: track.minY),
                                       end: CGPoint(x: track.midX, y: track.maxY), options: [])
        }
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor((isOn ? accentBorder(accent) : p.wellBorder).cgColor)
        context.setLineWidth(1)
        context.addPath(UIBezierPath(roundedRect: track.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius).cgPath)
        context.strokePath()
        context.restoreGState()

        let thumbDiameter = height - 4
        let thumbX = isOn ? track.maxX - 2 - thumbDiameter : track.minX + 2
        let thumb = CGRect(x: thumbX, y: track.minY + 2, width: thumbDiameter, height: thumbDiameter)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.6).cgColor)
        context.setFillColor((isOn ? p.thumbOn : p.thumbOff).cgColor)
        context.fillEllipse(in: thumb)
        context.restoreGState()
    }
}
