// PORT: upstream got UIKit for free — AudioKit re-exported it. S1Support is
// the value layer and does not.
import UIKit
//
//  ToggleButton.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 7/22/17.
//  Copyright © 2018 AudioKit. All rights reserved.
//

@IBDesignable
class ToggleButton: UIView, S1Control {

    // MARK: - ToggleButton

    var isOn = false {
        didSet {
            setNeedsDisplay()
            accessibilityValue = isOn ? NSLocalizedString("On", comment: "On") : NSLocalizedString("Off", comment: "Off")
        }
    }

    // MARK: - S1Control

    var value: Double = 0 {
        didSet {
            isOn = (value == 1)
        }
    }

    var setValueCallback: (Double) -> Void = { _ in }
    
    var resetToDefaultCallback: () -> Void = { }

    // MARK: - Desktop layout (P6, ADR-045)

    /// Drawn as a pill switch, the desktop's dress for a toggle. Set by the desktop
    /// layout when it takes the control; subclasses that draw themselves honour it too.
    var drawsAsSwitch = false {
        didSet { contentMode = .redraw; setNeedsDisplay() }   // P6-8: redraw on a bounds change, never stretch the old bitmap
    }

    // MARK: - Draw

    override func draw(_ rect: CGRect) {
        // PORT (P6, ADR-045): the same toggle, two dresses.
        if drawsAsSwitch {
            S1DesktopStyle.drawSwitch(in: bounds, isOn: isOn, accent: s1Accent)
            return
        }
        ToggleButtonStyleKit.drawRoundButton(frame: CGRect(x: 0,
                                                           y: 0,
                                                           width: self.bounds.width,
                                                           height: self.bounds.height),
                                             isToggled: isOn)
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for _ in touches {
            value = 1 - value
            setValueCallback(value)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {

        for _ in touches {
            setValueCallback(value)
        }
    }
}
