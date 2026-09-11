//
//  Conductor+Platform.swift
//  AudioKitSynthOne
//
//  Created by Matthias Frick on 03/11/2019.
//  Copyright © 2019 AudioKit. All rights reserved.
//

import Foundation

// PORT (P3-1): upstream keeps an iOS branch here that polls Audiobus and
// Inter-App Audio connections to decide whether to keep the engine running in the
// background. Neither exists on macOS, and upstream already shipped the Catalyst
// no-ops below — so only that half survives. The `#if` is gone with it: this file
// only ever builds for Catalyst now.
extension Conductor {

    @objc func checkIAAConnectionsEnterBackground() { }

    func checkIAAConnectionsEnterForeground() { }
}
