// PORT: upstream got UIKit for free — AudioKit re-exported it. S1Support is
// the value layer and does not.
import UIKit

extension UIButton {

    /// Draw as the interface was designed, not as macOS would.
    ///
    /// Under *Optimize Interface for Mac* (ADR-023) UIKit resolves a `UIButton` to
    /// the **Mac** behavioural style, which paints the system accent colour behind a
    /// selected button. Synth One's buttons set their own dark backgrounds and title
    /// colours to match the panel; the accent fill overrides the background and
    /// leaves the design's pale title on blue. The owner saw it on `Mono`.
    ///
    /// `.pad` opts this control back into iPad drawing, which is the interface hard
    /// requirement 1 is preserving. It does not affect the *idiom* — that stays
    /// Optimize-for-Mac for everything else.
    func useDesignedButtonAppearance() {
        if #available(macCatalyst 15.0, *) {
            preferredBehavioralStyle = .pad
        }
    }
}

extension UIView {

    /// Applies `useDesignedButtonAppearance()` to every `UIButton` beneath this view.
    ///
    /// The six custom button classes opt themselves out in `init`. **Plain `UIButton`s
    /// straight out of a storyboard do not**, and the header has two: the transparent
    /// title hit area over the wordmark, and the dice. Under the Mac behavioural style
    /// a bare `.system` button is drawn as a real macOS push button — so an invisible
    /// hit area becomes a bordered rectangle sitting on the header, which is what the
    /// owner saw around the wordmark.
    ///
    /// Same root cause as ADR-026, and these two were missed there because that sweep
    /// went class by class and neither of these has a `customClass`. A hierarchy walk
    /// cannot miss one; it is idempotent for the classes that already opted out.
    func useDesignedButtonAppearanceThroughout() {
        if let button = self as? UIButton { button.useDesignedButtonAppearance() }
        subviews.forEach { $0.useDesignedButtonAppearanceThroughout() }
    }
}

//
//  SynthButton.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 8/8/17.
//  Copyright © 2017 AudioKit. All rights reserved.
//

class SynthButton: UIButton, S1Control {

    // MARK: - Init

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    /// Both initialisers, deliberately. P3-5 fixed exactly this shape of bug in
    /// `Knob`, which wired its gestures only in `init?(coder:)` and did nothing when
    /// built in code.
    private func commonInit() {
        clipsToBounds = true
        layer.cornerRadius = 2
        layer.borderWidth = 1
        addTarget(self, action: #selector(pressed), for: .touchUpInside)
        useDesignedButtonAppearance()
    }

    // MARK: - S1Control

    var value: Double = 0 {
        didSet {
            isSelected = value == 1
            setNeedsDisplay()
        }
    }

    var setValueCallback: (Double) -> Void = { _ in }

    var resetToDefaultCallback: () -> Void = { }

    // MARK: - Properties

    var isOn: Bool {
        return value == 1
    }

    override var isSelected: Bool {
        didSet {
            backgroundColor = isOn ? #colorLiteral(red: 0.3058823529, green: 0.3058823529, blue: 0.3254901961, alpha: 1) : #colorLiteral(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
            accessibilityValue = isOn ?
                NSLocalizedString("On", comment: "On") :
                NSLocalizedString("Off", comment: "Off")
        }
    }

    // MARK: - Presses

    /// PORT FIX (P4-6): upstream toggles in `touchesBegan` and calls the callback
    /// again from `touchesEnded`. Both had to go.
    ///
    /// **`touchesBegan` is never called on a `UIButton` under the Mac idiom.** With
    /// *Optimize Interface for Mac* (ADR-023) UIKit backs `UIButton` with an AppKit
    /// cell — `UIButtonMacIdiomCell`, `UIButtonMacVisualProvider` — and the click is
    /// handled there. The override simply stops running, so every button in the
    /// interface goes dead while every custom `UIView` control keeps working. That is
    /// exactly what the owner reported: knobs and the Octave stepper fine, `Hide` and
    /// `Wheels` doing nothing.
    ///
    /// A `.touchUpInside` action is delivered under **both** idioms, which is what a
    /// `UIButton` subclass should have been using all along.
    ///
    /// It also fixes a second bug that was invisible on iPad: upstream ran the
    /// callback **twice per tap**, once on touch-down and once on touch-up. For the
    /// keyboard toggle that meant running the animation and saving settings twice.
    ///
    /// The value now changes on release rather than on press, which is standard for a
    /// button and means a press can be cancelled by dragging off it.
    @objc func pressed() {
        value = isOn ? 0 : 1
        setValueCallback(value)
    }
}
