//
//  ArrowButton.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 8/2/17.
//  Copyright © 2018 AudioKit. All rights reserved.
//

import UIKit

@IBDesignable
public class Stepper: UIView, S1Control {

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityTraits = UIAccessibilityTraits.adjustable
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        range = (Double(minValue) ... Double(maxValue))
        internalValue = 1
        text = "1"
    }

    // MARK: - S1Control

    public internal(set) var value: Double {
        get {
            return internalValue
        }
        set {
            internalValue = range.clamp(round(newValue))
            setNeedsDisplay()
        }
    }

    public var setValueCallback: (Double) -> Void = { _ in }

    var resetToDefaultCallback: () -> Void = { }

    // MARK: - Stepper
    
    var minusPath = UIBezierPath(roundedRect: CGRect(x: 0.5, y: 2, width: 35, height: 32), cornerRadius: 1)

    var plusPath = UIBezierPath(roundedRect: CGRect(x: 70.5, y: 2, width: 35, height: 32), cornerRadius: 1)
	
    var minValue = 0.0 {
        didSet {
            range = (Double(minValue) ... Double(maxValue))
            internalValue = range.clamp(internalValue)
        }
    }

    var maxValue = 3.0 {
        didSet {
            range = (Double(minValue) ... Double(maxValue))
            internalValue = range.clamp(internalValue)
        }
    }

	internal var internalValue: Double = 0 {
		didSet {
			accessibilityValue = String(format: "%.0f", internalValue)
		}
	}

    var range: ClosedRange = 0.0...1.0

    var valuePressed: CGFloat = 0

    // MARK: - Desktop layout (P6-3, ADR-045)

    /// Drawn in the desktop dress. Set by the desktop layout when it takes the control.
    var drawsDesktopStyle = false {
        didSet { contentMode = .redraw; setNeedsDisplay() }   // P6-8: redraw on a bounds change, never stretch the old bitmap
    }

    /// PORT FIX (P6-3): `minusPath` and `plusPath` are fixed for the storyboard's 108×35. In the
    /// desktop dress the stepper is sized by Auto Layout, so the zones follow the bounds.
    func hitZone(for point: CGPoint) -> CGFloat {
        if drawsDesktopStyle {
            let zones = S1DesktopStyle.stepperZones(in: bounds)
            if zones.minus.contains(point) { return 1 }
            if zones.plus.contains(point) { return 2 }
            return 0
        }
        if minusPath.contains(point) { return 1 }
        if plusPath.contains(point) { return 2 }
        return 0
    }

    open var text = "0"

    // MARK: - Draw

    override public func draw(_ rect: CGRect) {
        if drawsDesktopStyle {
            S1DesktopStyle.drawStepper(in: bounds, text: "\(Int(value))", pressed: valuePressed)
            return
        }
        StepperStyleKit.drawStepper(frame: CGRect(x: 0,
                                                  y: 0,
                                                  width: self.bounds.width,
                                                  height: self.bounds.height),
                                    valuePressed: valuePressed, text: "\(Int(value))")
    }

    // MARK: - Touches

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            let touchLocation = touch.location(in: self)
            let zone = hitZone(for: touchLocation)   // PORT FIX (P6-3)
            if zone == 1 {
                if value > minValue {
                    value -= 1
                    valuePressed = 1
                }
            }
            if zone == 2 {
                if value < maxValue {
                    value += 1
                    valuePressed = 2
                }
            }
            setValueCallback(value)
            setNeedsDisplay()
        }
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for _ in touches {
            valuePressed = 0
            setValueCallback(value)
            setNeedsDisplay()
        }
    }

    // MARK: - Accessibility
    
    override public func accessibilityIncrement() {
		if value < maxValue {
			value += 1
			valuePressed = 2
		}
		let newValue = String(format: "%.00f", value)
		accessibilityValue = newValue
		setValueCallback(value)
	}
	
	override public func accessibilityDecrement() {
		if value > minValue {
			value -= 1
			valuePressed = 1
			let newValue = String(format: "%.00f", value)
			accessibilityValue = newValue
			setValueCallback(value)
		}
	}
}
