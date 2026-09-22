//
//  S1DSPKernel+didChanges.mm
//  AudioKitSynthOne
//
//  Created by Aurelius Prochazka on 6/4/18.
//  Copyright © 2018 AudioKit. All rights reserved.
//

#include "S1DSPKernel.hpp"
#include "S1NoteState.hpp"

// PORT (X1-2, ADR-066): these used to post through `audioUnit->_messageQueue` to
// `audioUnit.messageRelay` (the P4-5 fix). They call the listener now; `S1AudioUnit`'s
// listener does that posting, unchanged. Nothing here knows about the audio unit.

// P4-6: the host's tempo, on its way to the tempo control.
void S1DSPKernel::hostTempoDidChange(float newTempo) {
    if (listener) listener->hostTempoDidChange(newTempo);
}

void S1DSPKernel::dependentParameterDidChange(DependentParameter param) {
    if (listener) listener->dependentParameterDidChange(param);
}

//can be called from within the render loop
void S1DSPKernel::beatCounterDidChange() {
    S1ArpBeatCounter retVal = {sequencer.getArpBeatCount(), heldNotes.count()};
    if (listener) listener->arpBeatCounterDidChange(retVal);
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
    if (listener) listener->playingNotesDidChange(aePlayingNotes);
}

///can be called from within the render loop
void S1DSPKernel::heldNotesDidChange() {
    for(int i = 0; i<S1_NUM_MIDI_NOTES; i++)
        aeHeldNotes.heldNotes[i] = false;
    int count = 0;
    const S1HeldNoteList held = heldNotes.snapshot();
    for (const NoteNumber &note : held) {
        const int nn = note.noteNumber;
        aeHeldNotes.heldNotes[nn] = true;
        ++count;
    }
    aeHeldNotes.heldNotesCount = count;
    if (listener) listener->heldNotesDidChange(aeHeldNotes);
}
