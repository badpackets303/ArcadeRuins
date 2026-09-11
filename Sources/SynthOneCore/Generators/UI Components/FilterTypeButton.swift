//
//  FilterTypeButton.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 8/23/17.
//  Copyright © 2017 AudioKit. All rights reserved.
//

import UIKit

class FilterTypeButton: UIButton, S1Control {

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        addTarget(self, action: #selector(pressed), for: .touchUpInside)
        useDesignedButtonAppearance()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(pressed), for: .touchUpInside)
        useDesignedButtonAppearance()
    }

    // MARK: - Properties

    private var _value: Double = 0 {
        didSet {
            switch _value {
            case 0:
                // low pass
                accessibilityValue = NSLocalizedString("Low Pass", comment: "Low Pass")
            case 1:
                // band pass
                accessibilityValue = NSLocalizedString("Band Pass", comment: "Low Pass")
            case 2:
                // high pass
                accessibilityValue = NSLocalizedString("High Pass", comment: "Low Pass")
            default:
                // low pass
                accessibilityValue = NSLocalizedString("Low Pass", comment: "Low Pass")
            }
      }
    }

    // MARK: - S1Control

    var value: Double {
        get {
            return _value
        }

        set {
            _value = (0 ... 3).clamp(newValue)
            DispatchQueue.main.async {
                switch self._value {
                case 0:
                    // low pass
                    self.setTitle("Low Pass", for: .normal)
                case 1:
                    // band pass
                    self.setTitle("Band Pass", for: .normal)
                case 2:
                    // high pass
                    self.setTitle("High Pass", for: .normal)
                case 3:
                    // reset to low pass
                    // swiftlint:disable fallthrough
                    fallthrough
                default:
                    // low pass
                    self._value = 0
                    self.setTitle("Low Pass", for: .normal)
                }
            }
        }
    }

    var setValueCallback: (Double) -> Void = { _ in }

    var resetToDefaultCallback: () -> Void = { }

    // MARK: - Touches

    /// PORT FIX (P4-6): was an override of `touchesBegan`. A `UIButton` never
    /// receives it under the Mac idiom (ADR-023) — UIKit backs the button with an
    /// AppKit cell and handles the click there — so this control was silently dead.
    /// See `SynthButton.pressed`.
    @objc func pressed() {
        value += 1
        if value == 3 {
            value = 0
        }
        setValueCallback(value)
        setNeedsDisplay()
    }
}
