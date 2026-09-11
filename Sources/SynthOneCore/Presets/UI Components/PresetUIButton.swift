//
//  PresetUIButon.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 11/24/17.
//  Copyright © 2017 AudioKit. All rights reserved.
//

import UIKit

class PresetUIButton: SynthButton {

    // MARK: - Touches

    /// PORT FIX (P4-6): was an override of `touchesBegan`. A `UIButton` never
    /// receives it under the Mac idiom (ADR-023) — UIKit backs the button with an
    /// AppKit cell and handles the click there — so this control was silently dead.
    /// See `SynthButton.pressed`.
    override func pressed() {
        setNeedsDisplay()
        setValueCallback(value)
    }
}
