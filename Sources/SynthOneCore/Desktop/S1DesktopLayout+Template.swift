//  A painted window under the desktop layout (P7-9, ADR-059).
//
//  **New, not ported.** A skin may bring a `S1SkinTemplate`: one image of the whole window with
//  the section frames, their titles, the header and the toolbar's buttons painted in, and the
//  rectangle each of them occupies. The layout is built exactly as for any other skin — every
//  control moved, bound and remembered — and then this pass lifts the sections out of their
//  rows and pins each to its painted frame, and takes the toolbar's controls to the painted
//  header. Every rectangle is a fraction of the window, so the window stays fluid.
//
//  This is the one place a skin decides *where* things go (ADR-046 said never). It decides
//  only that: which controls a section holds, and how they are bound, is the layout's.

import UIKit

extension S1DesktopLayout {

    func applyTemplate(_ template: S1SkinTemplate) {
        let canvas = UIView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.clipsToBounds = true
        root.insertSubview(canvas, at: 0)
        // The canvas is the window: the painting stretches with it. The design window is the
        // painting's shape to a part in a thousand, and a fitted canvas (tried first) let the
        // solver shrink the canvas rather than the sections' contents.
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.topAnchor.constraint(equalTo: root.topAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        templateCanvas = canvas

        let painting = UIImageView(image: UIImage.synthOne(template.imageName))
        painting.contentMode = .scaleToFill
        painting.isAccessibilityElement = false
        pin(painting, to: CGRect(origin: .zero, size: template.size), of: template)

        // The rows and the toolbar stay where they were built, empty and unseen: the preset
        // browser and the tests still find them.
        toolbar.isHidden = true
        editor.isHidden = true
        statusDivider.isHidden = true

        for (key, rect) in template.sections {
            guard let section = sections[key] else { continue }
            section.removeFromSuperview()
            NSLayoutConstraint.deactivate(section.constraints.filter {
                $0.firstItem === section && $0.secondItem == nil && $0.firstAttribute == .width
            })
            pin(section, to: rect, of: template)
        }

        placeToolbar(template)
        if let joystick = template.joystick { placeJoystick(joystick, of: template) }

        // The play bar and the status bar share the painting's bottom strip
        NSLayoutConstraint.deactivate(root.constraints.filter { constraint in
            [playBar, statusBar, statusDivider].contains { constraint.firstItem === $0 || constraint.secondItem === $0 }
        })
        editor.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -S1DesktopTheme.playBarHeight).isActive = true
        statusDivider.removeFromSuperview()
        playBar.setColours(top: .clear, bottom: .clear)
        statusBar.backgroundColor = .clear
        pin(playBar, to: template.playBar, of: template)
        pin(statusBar, to: template.statusBar, of: template)
        if let power = template.power { placePower(power, of: template) }
    }

    // MARK: - The painted header

    private func placeToolbar(_ template: S1SkinTemplate) {
        guard let header, let canvas = templateCanvas else { return }

        // The wordmark is painted; a click on it is About, which has no painted button
        let about = clearButton(NSLocalizedString("About Arcade Ruins", comment: "Accessibility")) { [weak header] in
            header?.aboutButton.sendActions(for: .touchUpInside)
        }
        pin(about, to: template.wordmark, of: template)

        // The preset name, in the painted display
        let field = presetField
        field.removeFromSuperview()
        NSLayoutConstraint.deactivate(field.constraints.filter {
            $0.firstItem === field && $0.secondItem == nil
        })
        field.backgroundColor = .clear
        field.layer.borderWidth = 0
        if let display = header.displayLabel {
            display.font = UIFont.monospacedSystemFont(ofSize: 19, weight: .semibold)
            display.textColor = S1CabinetSkin.cyan
            display.adjustsFontSizeToFitWidth = true
            display.minimumScaleFactor = 0.6
            display.layer.shadowColor = S1CabinetSkin.cyan.cgColor
            display.layer.shadowOpacity = 0.9
            display.layer.shadowRadius = 5
            display.layer.shadowOffset = .zero
        }
        for case let chevron as UILabel in field.subviews where chevron.text == "▾" {
            chevron.textColor = S1CabinetSkin.cyan
        }
        pin(field, to: template.presetField, of: template)

        let previous = clearButton(NSLocalizedString("Previous preset", comment: "Accessibility")) { [weak header] in
            header?.previousPresetPressed(UIButton())
        }
        let next = clearButton(NSLocalizedString("Next preset", comment: "Accessibility")) { [weak header] in
            header?.nextPresetPressed(UIButton())
        }
        pin(previous, to: template.previous, of: template)
        pin(next, to: template.next, of: template)

        if let dice = header.diceButton {
            dice.removeFromSuperview()
            centre(dice, at: template.dice, of: template)
        }

        // The painted buttons. The storyboard's own sit under each, unseen: a popover anchors
        // to its button, and a `SynthButton` paints itself grey when it is selected, which
        // would cover the painting — so a clear button on top takes the click and passes it on.
        let painted: [(UIButton?, CGRect, String)] = [
            (header.saveButton, template.save, NSLocalizedString("Save", comment: "Toolbar")),
            (header.panicButton, template.panic, NSLocalizedString("Panic", comment: "Toolbar")),
            (manager.midiButton, template.settings, NSLocalizedString("Settings", comment: "Toolbar"))
        ]
        for (button, rect, name) in painted {
            guard let button else { continue }
            button.removeFromSuperview()
            NSLayoutConstraint.deactivate(button.constraints.filter { $0.firstItem === button && $0.secondItem == nil })
            button.alpha = 0
            button.isAccessibilityElement = false
            pin(button, to: rect, of: template)
            let proxy = clearButton(name) { [weak button] in button?.sendActions(for: .touchUpInside) }
            pin(proxy, to: rect, of: template)
        }
        let presets = clearButton(NSLocalizedString("Presets", comment: "Open the preset browser")) { [weak self] in
            self?.togglePresetPanel()
        }
        pin(presets, to: template.presets, of: template)

        // Record: the painting leaves its plate empty, because a plugin has no recorder and
        // the label counts the time while one runs.
        let generators = manager.generatorsPanel
        if !manager.conductor.isHosted, let record = generators.recordButton, let status = generators.recordStatus,
           let pair = record.superview as? UIStackView {
            pair.removeFromSuperview()
            pair.translatesAutoresizingMaskIntoConstraints = false
            status.textColor = S1DesktopTheme.text
            centre(pair, at: CGPoint(x: template.record.midX, y: template.record.midY), of: template)
        } else {
            let label = UILabel()
            label.text = NSLocalizedString("About", comment: "Toolbar")
            label.font = S1DesktopTheme.font(12, weight: .medium)
            label.textColor = S1DesktopTheme.text
            label.translatesAutoresizingMaskIntoConstraints = false
            centre(label, at: CGPoint(x: template.record.midX, y: template.record.midY), of: template)
            let plate = clearButton(NSLocalizedString("About Arcade Ruins", comment: "Accessibility")) { [weak header] in
                header?.aboutButton.sendActions(for: .touchUpInside)
            }
            pin(plate, to: template.record, of: template)
        }

        // The scope, in the cabinet's screen
        if let plot = manager.conductor.audioPlotter {
            plot.removeFromSuperview()
            NSLayoutConstraint.deactivate(plot.constraints.filter { $0.firstItem === plot && $0.secondItem == nil })
            plot.backgroundColor = .clear
            plot.layer.cornerRadius = 14
            pin(plot, to: template.scope, of: template)
        }
        _ = canvas
    }

    // MARK: - The joystick (P7-11, ADR-061)

    /// The wheels are the classic ones, hidden with the keyboard; the stick moves them exactly as
    /// a touch on them does — set the pad, then run its callback — so the preset's mod-wheel
    /// routing and the bend range apply. Letting go puts the mod wheel back where it was, since
    /// a preset may rest it anywhere, and centres the bend as the pitch wheel's own release does.
    private func placeJoystick(_ joystick: S1TemplateJoystick, of template: S1SkinTemplate) {
        let stick = S1CabinetJoystick(parts: joystick)
        var modAtGrab = 0.0
        stick.onGrab = { [weak manager] in modAtGrab = manager?.modWheelPad.verticalValue ?? 0 }
        stick.onPush = { [weak manager] push in
            guard let wheel = manager?.modWheelPad else { return }
            let value = modAtGrab + (1 - modAtGrab) * push
            wheel.setVerticalValue01(value)
            wheel.callback(value)
        }
        stick.onLean = { [weak manager] lean in
            guard let wheel = manager?.pitchBend else { return }
            wheel.setVerticalValue01(lean)
            wheel.callback(lean)
        }
        stick.onRelease = { [weak manager] in
            guard let manager else { return }
            manager.modWheelPad.setVerticalValue01(modAtGrab)
            manager.modWheelPad.callback(modAtGrab)
            manager.pitchBend.setVerticalValue01(0.5)
            manager.pitchBend.callback(0.5)
        }
        pin(stick, to: joystick.reach, of: template)
        self.joystick = stick
    }

    // MARK: - Power (P7-12, ADR-062)

    /// A zone for every section and for the pieces of the header, each with a grey crop of the
    /// painting over its rectangle, and the two red buttons that run them.
    private func placePower(_ power: S1TemplatePower, of template: S1SkinTemplate) {
        guard let canvas = templateCanvas, let dark = UIImage.synthOne(power.darkImageName)?.cgImage else { return }
        var zones: [S1PowerZone] = []
        var above: UIView? = canvas.subviews.first   // the painting; the covers go straight over it

        func cover(_ rect: CGRect) -> UIView {
            let bounds = CGRect(origin: .zero, size: template.size)
            let rect = rect.intersection(bounds)
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.layer.contents = dark
            view.layer.contentsRect = CGRect(x: rect.minX / bounds.width, y: rect.minY / bounds.height,
                                             width: rect.width / bounds.width, height: rect.height / bounds.height)
            view.translatesAutoresizingMaskIntoConstraints = false
            if let below = above { canvas.insertSubview(view, aboveSubview: below) } else { canvas.addSubview(view) }
            above = view
            pin(view, to: rect, of: template)
            return view
        }

        for (key, rect) in template.sections.sorted(by: { $0.key < $1.key }) {
            guard let section = sections[key] else { continue }
            zones.append(S1PowerZone(name: key, views: [section],
                                     cover: cover(rect.insetBy(dx: -power.frameReach, dy: -power.frameReach))))
        }
        let header: [String: (views: [UIView], hidden: [UIView])] = [
            "display": ([presetField, header?.diceButton].compactMap { $0 }, []),
            "buttons": (canvas.subviews.filter { $0 is UIStackView || ($0 is UILabel) }, []),
            "screen": ([], [manager.conductor.audioPlotter].compactMap { $0 }),
            "bar": ([playBar, statusBar], [])
        ]
        for (key, rect) in power.zones.sorted(by: { $0.key < $1.key }) {
            guard let parts = header[key] else { continue }
            zones.append(S1PowerZone(name: key, views: parts.views, cover: cover(rect), hiddenWhenDark: parts.hidden))
        }

        let cabinet = S1CabinetPower(zones: zones)
        self.power = cabinet
        let off = clearButton(NSLocalizedString("Cut the power", comment: "The Cabinet skin's left red button")) { [weak cabinet] in
            cabinet?.run(powered: false)
        }
        let on = clearButton(NSLocalizedString("Restore the power", comment: "The Cabinet skin's right red button")) { [weak cabinet] in
            cabinet?.run(powered: true)
        }
        pin(off, to: power.off, of: template)
        pin(on, to: power.on, of: template)
    }

    private func clearButton(_ label: String, action: @escaping () -> Void) -> S1ActionButton {
        let button = S1ActionButton(type: .custom)
        button.useDesignedButtonAppearance()
        button.accessibilityLabel = label
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - Fractions of the canvas

    /// Pins a view to a rectangle of the painting. Trailing and bottom are the only anchors a
    /// multiplier can scale from zero, so every edge is a fraction of those.
    func pin(_ view: UIView, to rect: CGRect, of template: S1SkinTemplate) {
        guard let canvas = templateCanvas else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        if view.superview !== canvas { canvas.addSubview(view) }
        let size = template.size
        NSLayoutConstraint.activate([
            edge(view, .leading, canvas, .trailing, rect.minX / size.width),
            edge(view, .trailing, canvas, .trailing, rect.maxX / size.width),
            edge(view, .top, canvas, .bottom, rect.minY / size.height),
            edge(view, .bottom, canvas, .bottom, rect.maxY / size.height)
        ])
    }

    /// Centres a view that keeps its own size on a point of the painting.
    func centre(_ view: UIView, at point: CGPoint, of template: S1SkinTemplate) {
        guard let canvas = templateCanvas else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        if view.superview !== canvas { canvas.addSubview(view) }
        NSLayoutConstraint.activate([
            edge(view, .centerX, canvas, .trailing, point.x / template.size.width),
            edge(view, .centerY, canvas, .bottom, point.y / template.size.height)
        ])
    }

    private func edge(_ view: UIView, _ attribute: NSLayoutConstraint.Attribute, _ canvas: UIView,
                      _ other: NSLayoutConstraint.Attribute, _ fraction: CGFloat) -> NSLayoutConstraint {
        NSLayoutConstraint(item: view, attribute: attribute, relatedBy: .equal, toItem: canvas, attribute: other,
                           multiplier: max(fraction, 0.000_1), constant: 0)
    }
}
