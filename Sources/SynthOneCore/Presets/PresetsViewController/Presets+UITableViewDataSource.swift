// PORT: upstream got UIKit for free — AudioKit re-exported it. S1Support is
// the value layer and does not.
import UIKit
//
//  Presets+UITableViewDataSource.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 5/25/18.
//  Copyright © 2018 AudioKit. All rights reserved.
//

extension PresetsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    @objc(tableView:heightForRowAtIndexPath:) func tableView(_ tableView: UITableView,
                                                             heightForRowAt indexPath: IndexPath) -> CGFloat {
        return rowHeight   // PORT (P6-6): 44 in the classic panel; the desktop sidebar sets its own
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if sortedPresets.isEmpty {
            return 0
        } else {
            return sortedPresets.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        // Get current preset

        if let cell = tableView.dequeueReusableCell(withIdentifier: "PresetCell") as? PresetCell {

            var alphabetical = false
            if categoryIndex == PresetCategory.categoryCount + 1 { alphabetical = true }

            let preset = sortedPresets[(indexPath as NSIndexPath).row]
           
            cell.delegate = self
            
            // Cell updated in PresetCell.swift
            cell.configureCell(preset: preset, alpha: alphabetical)
            
            return cell
        } else {
            return PresetCell()
        }
    }
}
