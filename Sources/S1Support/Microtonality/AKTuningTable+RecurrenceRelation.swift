//
//  AKTuningTable+RecurrenceRelation.swift
//  AudioKit
//
//  Created by Marcus W. Hobbs, revision history on GitHub.
//  Copyright © 2018 AudioKit. All rights reserved.
//

import Foundation

extension AKTuningTable {

    /// From Erv Wilson.  See http://anaphoria.com/genus.pdf
    @discardableResult public func presetRecurrenceRelation01() -> Int {
        return tuningTable(fromFrequencies: [1, 34, 5, 21, 3, 13, 55])
    }
}
