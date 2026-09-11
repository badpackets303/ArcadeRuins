//
//  MIDILearnable.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 10/21/17.
//  Copyright © 2018 AudioKit. All rights reserved.
//

// PORT: upstream got UIKit for free — AudioKit re-exported it. S1Support is the
// value layer and does not.
import UIKit
import S1Support


protocol MIDILearnable: AnyObject {

    var midiByteRange:ClosedRange<MIDIByte> { get set }

    var hotspotView: UIView { get set }

    var midiCC: MIDIByte { get set }

    var midiLearnMode: Bool { get set }

    var isMIDILearnActive: Bool { get set }

    func addHotspot()

    func hideHotspot()

    func showHotspot()

    func setControlValueFrom(midiValue: MIDIByte)
    
    func updateMIDILearnLabel()
    
}
