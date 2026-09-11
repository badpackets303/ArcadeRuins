//
//  RateKnob.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 8/5/17.
//  Copyright © 2017 AudioKit. All rights reserved.
//

import UIKit

public class RateKnob: MIDIKnob {

    var rate: Rate {
        return Rate(rawValue: Int(knobValue * CGFloat(Rate.count))) ?? Rate.sixtyFourth
    }

    private var _value: Double = 0

    override public var value: Double {
        get {
            if timeSyncMode {
                return rate.frequency
            } else {
                return _value
            }
        }
        set(newValue) {
            _value = onlyIntegers ? round(newValue) : newValue
            _value = range.clamp(_value)
            if !timeSyncMode {
                knobValue = CGFloat(_value.normalized(from: range, taper: taper))
            }
        }
    }

    // Init / Lifecycle
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = true
        contentMode = .redraw
    }

    // PORT (P3-5): upstream overrides `setPercentagesWithTouchPoint` in full to
    // change one line. Overriding the value derivation instead means this knob gets
    // ⌥ fine-drag and the scroll wheel for free, and there is only one copy of the
    // drag maths.
    override func valueForCurrentKnobValue() -> Double {
        if timeSyncMode {
            return rate.frequency
        }
        return Double(knobValue).denormalized(to: range, taper: taper)
    }
}
