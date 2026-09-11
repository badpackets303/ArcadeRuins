//
//  S1Control.swift
//  AudioKitSynthOne
//
//  Created by Marcus W. Hobbs on 3/29/19.
//  Copyright © 2019 AudioKit. All rights reserved.
//

// PORT: `class` is the deprecated spelling of `AnyObject` for a
// class-constrained protocol. Internal, as upstream — every conformer is in
// this module.
protocol S1Control: AnyObject {

    var value: Double { get set }

    var setValueCallback: (Double) -> Void { get set }

    var resetToDefaultCallback: () -> Void { get set }
}

typealias S1ControlCallback = (S1Parameter, S1Control?) -> ((_: Double) -> Void)

typealias S1ControlDefaultCallback = (S1Parameter, S1Control?) -> (() -> Void)
