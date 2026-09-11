// PORT: upstream got UIKit for free — AudioKit re-exported it. S1Support is
// the value layer and does not.
import UIKit
//
//  Presets+CategoryDelegate.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 5/25/18.
//  Copyright © 2018 AudioKit. All rights reserved.
//


extension PresetsViewController: CategoryDelegate {

    func categoryDidChange(_ newCategoryIndex: Int) {
        categoryIndex = newCategoryIndex
        selectCurrentPreset()
    }

    func bankShare() {
        // Get Bank to Share
        guard let bank = conductor.banks.first(where: { $0.position == bankIndex }) else { return }
        let bankName = bank.name
        let bankPresetsToShare = presets.filter { $0.bank == bankName }

        // Save bank presets to temp directory to be shared
        let bankLocation = "temp/\(bankName).json"
        try? Disk.save(bankPresetsToShare, to: .caches, as: bankLocation)
        guard let path: URL = try? Disk.getURL(for: bankLocation, in: .caches) else { return }

        // PORT (ADR-044): upstream presents a `UIActivityViewController` here, which crashes the
        // plugin. `share(_:)` keeps it for the standalone and exports through a Save dialog in the plugin.
        share(path)
    }

    func bankEdit() {
        self.performSegue(withIdentifier: "SegueToBankEdit", sender: self)
    }
}
