//
//  S1DSPKernel+MIDI.mm
//  AudioKitSynthOne
//
//  Created by Aurelius Prochazka on 6/4/18.
//  Copyright © 2018 AudioKit. All rights reserved.
//

#include "S1DSPKernel.hpp"

// MIDI
void S1DSPKernel::handleMIDIEvent(S1MIDIEvent const& midiEvent) {
    // PORT FIX (ADR-031): in the plugin, host MIDI goes through `S1HostMIDI`, the render-thread
    // port of the standalone's MIDI chain. The body below plays note on and off and honours
    // CC123, and nothing else — no octave, velocity setting, channel, hold, pedal or bend.
    // That was hidden while the plugin also opened every CoreMIDI input itself, which played
    // each key a second time through `Manager`. The standalone never enables the router, so
    // it still runs upstream's code, which no host ever calls there anyway.
    if (hostMIDI.enabled.load(std::memory_order_relaxed)) {
        hostMIDI.handle(midiEvent, *this);
        return;
    }
    if (midiEvent.length != 3) return;
    uint8_t status = midiEvent.data[0] & 0xF0;
    switch (status) {
        case 0x80 : {
            // note off
            uint8_t note = midiEvent.data[1];
            if (note > 127) break;
            stopNote(note);
            break;
        }
        case 0x90 : {
            // note on
            uint8_t note = midiEvent.data[1];
            uint8_t veloc = midiEvent.data[2];
            if (note > 127 || veloc > 127) break;
            startNote(note, veloc);
            break;
        }
        case 0xB0 : {
            uint8_t num = midiEvent.data[1];
            if (num == 123) {
                stopAllNotes();
            }
            break;
        }
    }
}



