//
//  HeaderNavButton.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 8/31/17.
//  Copyright © 2017 AudioKit. All rights reserved.
//

import UIKit

class HeaderNavButton: UIButton {

    var callback: (Double) -> Void = { _ in }

    var value: Double {
        get {
            return isSelected ? 1 : 0
        }
        set {
            isSelected = value == 1.0
        }
    }

    override var isSelected: Bool {
        didSet {
            if isSelected {
                 backgroundColor =  #colorLiteral(red: 0.1803921569, green: 0.1803921569, blue: 0.2, alpha: 1)
                 setTitleColor(#colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0), for: .normal)
            } else {
                backgroundColor =   #colorLiteral(red: 0.1568627451, green: 0.1568627451, blue: 0.1568627451, alpha: 1)
                setTitleColor(#colorLiteral(red: 0.6666666667, green: 0.6666666667, blue: 0.6666666667, alpha: 1), for: .normal)
            }
        }
    }

    override var isEnabled: Bool {
        didSet {
            if isEnabled {
                setTitleColor(#colorLiteral(red: 0.8666666667, green: 0.8666666667, blue: 0.8666666667, alpha: 1), for: .normal)
                layer.borderWidth = 0
            } else {
                setTitleColor(#colorLiteral(red: 0.5333333333, green: 0.5333333333, blue: 0.5333333333, alpha: 1), for: .normal)
                layer.borderWidth = 0
            }
        }
    }

    // Init / Lifecycle
    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(pressed), for: .touchUpInside)
        useDesignedButtonAppearance()
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        addTarget(self, action: #selector(pressed), for: .touchUpInside)
        useDesignedButtonAppearance()

        backgroundColor = #colorLiteral(red: 0.1803921569, green: 0.1803921569, blue: 0.2, alpha: 1)
        layer.cornerRadius = 4
        layer.borderWidth = 1
        layer.borderColor = #colorLiteral(red: 0.06666666667, green: 0.06666666667, blue: 0.06666666667, alpha: 1)
    }

    // MARK: - Touches

    /// PORT FIX (P4-6): was an override of `touchesBegan`. A `UIButton` never
    /// receives it under the Mac idiom (ADR-023) — UIKit backs the button with an
    /// AppKit cell and handles the click there — so this control was silently dead.
    /// See `SynthButton.pressed`.
    @objc func pressed() {
        isSelected = !isSelected
        setNeedsDisplay()
        callback(value)
    }
}
