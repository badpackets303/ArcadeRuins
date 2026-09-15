// PORT: upstream got UIKit for free — AudioKit re-exported it. S1Support is
// the value layer and does not.
import UIKit
//
//  ToggleSwitch.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 8/2/17.
//  Copyright © 2017 AudioKit. All rights reserved.
//

@IBDesignable
class ToggleSwitch: UIView, S1Control {

    // MARK: - Properties

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

    // MARK: - Desktop layout (P6-3, ADR-045)

    /// Drawn in the desktop dress. Set by the desktop layout when it takes the control.
    var drawsDesktopStyle = false {
        didSet { contentMode = .redraw; setNeedsDisplay() }   // P6-8: redraw on a bounds change, never stretch the old bitmap
    }

    /// The words either side of the switch in the desktop dress. The one use is Arp / Seq.
    var desktopLabels = ("Off", "On")

    // MARK: - Draw

    override func draw(_ rect: CGRect) {
        if drawsDesktopStyle {
            S1DesktopStyle.drawTwoWaySwitch(in: bounds, isOn: value != 0, left: desktopLabels.0, right: desktopLabels.1, accent: s1Accent)
            return
        }
        ToggleSwitchStyleKit.drawToggleSwitch(isToggled: value == 0 ? false : true )
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
