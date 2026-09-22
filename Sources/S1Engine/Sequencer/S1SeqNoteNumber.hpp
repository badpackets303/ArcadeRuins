//
//  S1SeqNoteNumber.hpp
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 3/06/19.
//  Copyright © 2019 AudioKit. All rights reserved.
//

// PORT FIX (X1-3): an include guard. Upstream had none, and once S1Sequencer.hpp and
// S1Arpeggiator.hpp are both included from one file the struct is defined twice.
#ifndef S1_SEQ_NOTE_NUMBER_HPP
#define S1_SEQ_NOTE_NUMBER_HPP

struct SeqNoteNumber {
    int noteNumber;
    int onOff;
    int velocity;
};

#endif
