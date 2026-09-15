//
//  TransposeButton.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 8/1/17.
//  Copyright © 2018 AudioKit. All rights reserved.
//

import UIKit

class SliderTransposeButton: UILabel, S1Control {

    // MARK: - Init

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        clipsToBounds = true
        layer.cornerRadius = 2
        layer.borderWidth = 1
        layer.borderColor = #colorLiteral(red: 0.09411764706, green: 0.09411764706, blue: 0.09411764706, alpha: 1)
    }

    override public func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
        contentMode = .scaleAspectFit
        clipsToBounds = true
    }

    public class override var requiresConstraintBasedLayout: Bool {
        return true
    }

    // MARK: - Properties

    private var _value: Double = 0

    var transposeAmt = 0 {
        didSet {
            text = String(transposeAmt)
            accessibilityValue = text
        }
    }

    var isActive = false {
        didSet {
            if isActive {
                layer.borderColor = #colorLiteral(red: 0.8812435269, green: 0.4256765842, blue: 0, alpha: 1)
                layer.borderWidth = 2
            } else {
                layer.borderColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
                layer.borderWidth = 1
            }
        }
    }


    // MARK: - Desktop layout (P6-3, ADR-045)

    /// The desktop dress: the field's colours, font and corners. Set by the desktop layout.
    var drawsDesktopStyle = false {
        didSet {
            contentMode = .redraw   // P6-8: redraw on a bounds change, never stretch the old bitmap
            font = S1DesktopTheme.font(12, weight: .medium)
            textColor = S1DesktopTheme.text
            layer.cornerRadius = 4
            let v = _value
            value = v      // re-applies the colours for the new dress
        }
    }

    // MARK: - S1Control

    var value: Double {
        get {
            return _value
        }
        set {
            if newValue > 0 {
                _value = 1
                backgroundColor = drawsDesktopStyle ? desktopBox(on: true)
                    : #colorLiteral(red: 0.3725490196, green: 0.3725490196, blue: 0.3921568627, alpha: 1)
                if transposeAmt >= 0 {
                    transposeAmt += 12
                } else {
                    transposeAmt -= 12
                }
            } else {
                _value = 0
                backgroundColor = drawsDesktopStyle ? desktopBox(on: false)
                    : #colorLiteral(red: 0.2156862745, green: 0.2156862745, blue: 0.2352941176, alpha: 1)
            }
            setNeedsDisplay()
        }
    }

    /// PORT (P7-4, ADR-048): the desktop box's face, and its border, from the section's accent.
    /// The accent is found through the view tree, so the colours are applied again when the
    /// box reaches its window (it is dressed before it is placed).
    private func desktopBox(on: Bool) -> UIColor {
        let box = S1DesktopStyle.numberBox(on: on, accent: s1Accent)
        layer.borderWidth = box.border == nil ? 0 : 1
        layer.borderColor = box.border?.cgColor
        return box.face
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard drawsDesktopStyle, window != nil else { return }
        let v = _value
        value = v
    }

    public var setValueCallback: (Double) -> Void = { _ in }

    var resetToDefaultCallback: () -> Void = { }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for _ in touches {

            // toggle
            if value > 0 {
                value = 0
            } else {
                value = 1
            }
            setValueCallback(value)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {

        for _ in touches {
            setValueCallback(value)
        }
    }
}
