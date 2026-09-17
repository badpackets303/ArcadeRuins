//  The cabinet loses power, and gets it back (P7-12, ADR-062).
//
//  **New, not ported.** The Cabinet painting's arcade machine has two big red buttons. The owner
//  asked (2026-09-17) for the left one to flicker the panels off at random until the synth looks
//  as if it has lost power — no highlight colours, the interface in greyscale — and the right one
//  to flicker them back on, each over about eight seconds. It is a look and nothing else: every
//  control still works and still sounds while the lights are out.
//
//  A **zone** is one thing that goes dark at once: a section, or a piece of the header. Dark is
//  three things together —
//    - a grey copy of the painting laid over the zone's rectangle (`cover`);
//    - every colour the zone's views *hold* — backgrounds, borders, glows, label colours, the
//      ADSR plots' fills, images — swapped for its grey, and put back exactly on the way up;
//    - every colour its controls *draw* with: `UIView.s1Accent` answers `S1Power.deadAccent` for
//      a view inside a dark zone and tells `S1DesktopStyle` to draw from the palette's grey twin.

import UIKit

enum S1Power {

    /// The roots of every dark zone. `s1Accent` looks here on its way up the tree.
    static let dark = NSHashTable<UIView>.weakObjects()

    /// What a control in a dark zone draws its value arc and lit cells from.
    static let deadAccent = UIColor(white: 0.34, alpha: 1)

    /// A colour with the light taken out of it: its luminance, dimmed, at the same alpha.
    static func grey(_ colour: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard colour.getRed(&r, green: &g, blue: &b, alpha: &a) else { return colour }
        let luminance = min(1, max(0, 0.299 * r + 0.587 * g + 0.114 * b)) * 0.72
        return UIColor(white: luminance, alpha: a)
    }

    static func isDark(_ view: UIView) -> Bool {
        guard dark.count > 0 else { return false }
        var current: UIView? = view
        while let here = current {
            if dark.contains(here) { return true }
            current = here.superview
        }
        return false
    }

    /// For the few controls a PaintCode style kit still draws, whose colours are inside the kit:
    /// lit, the drawing runs as it is; dark, it runs into an image and the image is drawn grey.
    static func draw(in view: UIView, _ drawing: () -> Void) {
        guard isDark(view), view.bounds.width > 0, view.bounds.height > 0 else { return drawing() }
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
            UIGraphicsPushContext(context.cgContext)
            drawing()
            UIGraphicsPopContext()
        }
        grey(image).draw(in: view.bounds)
    }

    static func grey(_ image: UIImage) -> UIImage {
        let bounds = CGRect(origin: .zero, size: image.size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            image.draw(in: bounds)
            UIColor(white: 0.5, alpha: 1).setFill()
            context.fill(bounds, blendMode: .saturation)
            UIColor(white: 0, alpha: 0.3).setFill()
            context.fill(bounds, blendMode: .sourceAtop)
            image.draw(in: bounds, blendMode: .destinationIn, alpha: 1)
        }
    }
}

/// A control that sets colours of its own from its state. What it held when the lights went out
/// may not be what it should hold when they come back — a filter type chosen, a step switched,
/// in the dark — so it is asked to colour itself again once its zone has power.
protocol S1PowerAware: UIView {
    func powerDidReturn()
}

/// One thing that goes dark at once.
final class S1PowerZone {

    let name: String
    let views: [UIView]
    /// The grey painting over this zone's rectangle, hidden while the zone is lit.
    let cover: UIView?
    /// Views that simply are not there in the dark: the scope's trace.
    let hiddenWhenDark: [UIView]

    private(set) var isPowered = true
    private var restore: [() -> Void] = []

    init(name: String, views: [UIView], cover: UIView?, hiddenWhenDark: [UIView] = []) {
        self.name = name
        self.views = views
        self.cover = cover
        self.hiddenWhenDark = hiddenWhenDark
        cover?.isHidden = true
    }

    func setPowered(_ powered: Bool) {
        guard powered != isPowered else { return }
        isPowered = powered
        cover?.isHidden = powered
        hiddenWhenDark.forEach { $0.alpha = powered ? 1 : 0 }
        if powered {
            views.forEach { S1Power.dark.remove($0) }
            restore.reversed().forEach { $0() }
            restore = []
            views.forEach(recolour)
        } else {
            views.forEach { S1Power.dark.add($0) }
            views.forEach(darken)
        }
        views.forEach(redraw)
    }

    private func recolour(_ view: UIView) {
        (view as? S1PowerAware)?.powerDidReturn()
        view.subviews.forEach(recolour)
    }

    private func redraw(_ view: UIView) {
        view.setNeedsDisplay()
        view.subviews.forEach(redraw)
    }

    /// Swaps every colour this view holds for its grey, remembering how to put it back.
    private func darken(_ view: UIView) {
        if let colour = view.backgroundColor, colour.cgColor.alpha > 0, colour.cgColor.pattern == nil {
            view.backgroundColor = S1Power.grey(colour)
            restore.append { [weak view] in view?.backgroundColor = colour }
        }
        if let border = view.layer.borderColor, view.layer.borderWidth > 0 {
            view.layer.borderColor = S1Power.grey(UIColor(cgColor: border)).cgColor
            restore.append { [weak view] in view?.layer.borderColor = border }
        }
        if let shadow = view.layer.shadowColor, view.layer.shadowOpacity > 0 {
            let opacity = view.layer.shadowOpacity
            view.layer.shadowOpacity = 0                       // a glow is a highlight: out
            restore.append { [weak view] in view?.layer.shadowColor = shadow; view?.layer.shadowOpacity = opacity }
        }
        // Not a button's attributed title (the status bar's Tuning): one colour would flatten its
        // two, and they are greys already.
        let isAttributedTitle = (view.superview as? UIButton)?.attributedTitle(for: .normal) != nil
        if let label = view as? UILabel, let colour = label.textColor, !isAttributedTitle {
            label.textColor = S1Power.grey(colour)
            restore.append { [weak label] in label?.textColor = colour }
        }
        // A button's title is reached as its label, below: `titleColor(for:)` is not always what
        // the label shows (the play bar's Wheels is dimmed on its label), and setting it would
        // bring the wrong colour back.
        if let imageView = view as? UIImageView, let image = imageView.image {
            imageView.image = S1Power.grey(image)
            restore.append { [weak imageView] in imageView?.image = image }
        }
        if let plot = view as? AKADSRView {
            for path in [\AKADSRView.attackColor, \.decayColor, \.sustainColor, \.releaseColor, \.curveColor] {
                let colour = plot[keyPath: path]
                plot[keyPath: path] = S1Power.grey(colour)
                restore.append { [weak plot] in plot?[keyPath: path] = colour }
            }
        }
        view.subviews.forEach(darken)
    }
}

/// The two red buttons: every zone off, or on, flickering, in a random order.
final class S1CabinetPower {

    let zones: [S1PowerZone]

    /// How long a whole cycle takes, and how long before its end a zone starts to flicker.
    static let cycle: TimeInterval = 8
    static let flickerWindow: ClosedRange<TimeInterval> = 0.35...0.9

    /// Runs a block later. Tests replace it and fire the blocks themselves.
    var after: (TimeInterval, @escaping () -> Void) -> Void = { delay, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }

    /// Pressing the other button mid-cycle abandons what is still to come of this one.
    private var generation = 0

    init(zones: [S1PowerZone]) {
        self.zones = zones
    }

    var isPowered: Bool { zones.allSatisfy(\.isPowered) }
    var isDark: Bool { zones.allSatisfy { !$0.isPowered } }

    /// One zone's flicker: the moments it changes, ending on `target` at `settle`. It starts
    /// by going *to* the target — a lit panel's first flicker is a blink off — and alternates.
    static func flicker(settlingAt settle: TimeInterval, to target: Bool,
                        using random: inout some RandomNumberGenerator) -> [(time: TimeInterval, powered: Bool)] {
        let blinks = Int.random(in: 2...4, using: &random)
        let start = settle - TimeInterval.random(in: flickerWindow, using: &random)
        var times = (0..<blinks * 2).map { _ in TimeInterval.random(in: start..<settle, using: &random) }.sorted()
        times[0] = start
        var events = times.enumerated().map { (time: $0.element, powered: $0.offset.isMultiple(of: 2) ? target : !target) }
        events.append((time: settle, powered: target))
        return events
    }

    func run(powered target: Bool) {
        var random = SystemRandomNumberGenerator()
        run(powered: target, using: &random)
    }

    func run(powered target: Bool, using random: inout some RandomNumberGenerator) {
        generation += 1
        let mine = generation
        let pending = zones.filter { $0.isPowered != target }.shuffled(using: &random)
        guard !pending.isEmpty else { return }
        // The first settles about a second in and the last at the end, so it reads as a slow loss
        let first = 1.0
        for (index, zone) in pending.enumerated() {
            let share = pending.count == 1 ? 1 : Double(index) / Double(pending.count - 1)
            let settle = first + (Self.cycle - first) * share
            for event in Self.flicker(settlingAt: settle, to: target, using: &random) {
                after(max(0, event.time)) { [weak self, weak zone] in
                    guard let self, self.generation == mine else { return }
                    zone?.setPowered(event.powered)
                }
            }
        }
    }
}
