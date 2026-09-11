// PORT: upstream got UIKit for free — AudioKit re-exported it. S1Support is
// the value layer and does not.
import UIKit
//
//  CallbackButton.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 9/12/17.
//  Copyright © 2017 AudioKit. All rights reserved.
//

class CallbackButton: UIButton {

    var callback: (Double) -> Void = { _ in }

    var valuePressed = 0.0

    // Init / Lifecycle
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    private func commonInit() {
        addTarget(self, action: #selector(pressed), for: .touchUpInside)
        useDesignedButtonAppearance()
    }

    // MARK: - Presses

    /// PORT FIX (P4-6): was an override of `touchesBegan`, which a `UIButton` never
    /// receives under the Mac idiom — see `SynthButton.pressed`.
    @objc func pressed() {
        valuePressed = 1
        callback(valuePressed)
    }
}
