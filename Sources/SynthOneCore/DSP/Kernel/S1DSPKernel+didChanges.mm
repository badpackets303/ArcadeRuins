//
//  S1DSPKernel+didChanges.mm
//  AudioKitSynthOne
//
//  Created by Aurelius Prochazka on 6/4/18.
//  Copyright © 2018 AudioKit. All rights reserved.
//

#import "S1DSPKernel.hpp"
#import "AEArray.h"
#import "AEMessageQueue.h"
#import "S1NoteState.hpp"

// PORT FIX (P4-5): these post to `audioUnit.messageRelay`, not to `audioUnit`.
// The queue stores its target as a raw pointer and delivers asynchronously, so
// addressing the unit itself is a use-after-free the moment a unit is destroyed with
// a message in flight. See `S1MessageRelay` in S1AudioUnit.h.

// P4-6: the host's tempo, on its way to the tempo control.
void S1DSPKernel::hostTempoDidChange(float newTempo) {
    // A local, not `AEArgumentScalar`: that macro builds a C compound literal and
    // takes its address, which Obj-C++ rejects as the address of an rvalue.
    float tempoValue = newTempo;
    AEMessageQueuePerformSelectorOnMainThread(audioUnit->_messageQueue,
                                              audioUnit.messageRelay,
                                              @selector(hostTempoDidChange:),
                                              AEArgumentStruct(tempoValue),
                                              AEArgumentNone);
}

void S1DSPKernel::dependentParameterDidChange(DependentParameter param) {
    AEMessageQueuePerformSelectorOnMainThread(audioUnit->_messageQueue,
                                              audioUnit.messageRelay,
                                              @selector(dependentParameterDidChange:),
                                              AEArgumentStruct(param),
                                              AEArgumentNone);
}

//can be called from within the render loop
void S1DSPKernel::beatCounterDidChange() {
    S1ArpBeatCounter retVal = {sequencer.getArpBeatCount(), heldNoteNumbersAE.count};
    AEMessageQueuePerformSelectorOnMainThread(audioUnit->_messageQueue,
                                              audioUnit.messageRelay,
                                              @selector(arpBeatCounterDidChange:),
                                              AEArgumentStruct(retVal),
                                              AEArgumentNone);
}


///can be called from within the render loop
void S1DSPKernel::playingNotesDidChange() {
    aePlayingNotes.polyphony = S1_MAX_POLYPHONY;
    if (parameters[isMono] > 0.f) {
        aePlayingNotes.playingNotes[0] = { monoNote->rootNoteNumber, monoNote->transpose, monoNote->velocity, monoNote->amp };
        for(int i = 1; i<S1_MAX_POLYPHONY; i++) {
            aePlayingNotes.playingNotes[i] = { -1, -1, -1, -1 };
        }
    } else {
        for(int i=0; i<S1_MAX_POLYPHONY; i++) {
            const auto& note = (*noteStates)[i];
            aePlayingNotes.playingNotes[i] = { note.rootNoteNumber, note.transpose, note.velocity, note.amp };
        }
    }
    AEMessageQueuePerformSelectorOnMainThread(audioUnit->_messageQueue,
                                              audioUnit.messageRelay,
                                              @selector(playingNotesDidChange:),
                                              AEArgumentStruct(aePlayingNotes),
                                              AEArgumentNone);
}

///can be called from within the render loop
void S1DSPKernel::heldNotesDidChange() {
    for(int i = 0; i<S1_NUM_MIDI_NOTES; i++)
        aeHeldNotes.heldNotes[i] = false;
    int count = 0;
    AEArrayEnumeratePointers(heldNoteNumbersAE, NoteNumber *, note) {
        const int nn = note->noteNumber;
        aeHeldNotes.heldNotes[nn] = true;
        ++count;
    }
    aeHeldNotes.heldNotesCount = count;
    AEMessageQueuePerformSelectorOnMainThread(audioUnit->_messageQueue,
                                              audioUnit.messageRelay,
                                              @selector(heldNotesDidChange:),
                                              AEArgumentStruct(aeHeldNotes),
                                              AEArgumentNone);
}
