//  S1HostMIDI.mm — see S1HostMIDI.hpp and ADR-031.
//
//  Read this beside the Swift it ports. Each function below says which method it is, and
//  the order of operations inside each is that method's, including the quirks: a note-off's
//  velocity re-strikes the highest held note in mono, and a second non-zero sustain value
//  lifts the pedal. `HostMIDIParityTests` would fail on either if "corrected" here alone.

#include "S1HostMIDI.hpp"
#include "S1DSPKernel.hpp"

namespace {

/// `Manager.whiteKeysOnlyMap`, entry for entry. `HostMIDIParityTests` compares all 128.
const uint8_t kWhiteKeysOnlyMap[128] = {
    25, 25, 26, 26, 27, 28, 28, 29, 29, 30, 30, 31,
    32, 32, 33, 33, 34, 35, 35, 36, 36, 37, 37, 38,
    39, 39, 40, 40, 41, 42, 42, 43, 43, 44, 44, 45,
    46, 46, 47, 47, 48, 49, 49, 50, 50, 51, 51, 52,
    53, 53, 54, 54, 55, 56, 56, 57, 57, 58, 58, 59,
    60, 60, 61, 61, 62, 63, 63, 64, 64, 65, 65, 66,
    67, 67, 68, 68, 69, 70, 70, 71, 71, 72, 72, 73,
    74, 74, 75, 75, 76, 77, 77, 78, 78, 79, 79, 80,
    81, 81, 82, 82, 83, 84, 84, 85, 85, 86, 86, 87,
    88, 88, 89, 89, 90, 91, 91, 92, 92, 93, 93, 94,
    95, 95, 96, 96, 97, 98, 98, 99
};

bool inMIDIRange(int note) { return note >= 0 && note <= 127; }

}  // namespace

// MARK: - Settings

bool S1HostMIDI::accepts(int channel) const {
    // `channel == conductor.midiInChannel || conductor.isOmniMode`
    return channel == midiChannel.load(std::memory_order_relaxed) ||
           omniMode.load(std::memory_order_relaxed);
}

bool S1HostMIDI::isMono(S1DSPKernel &kernel) const {
    // `!keyboardView.polyphonicMode`, which the interface derives from this parameter.
    return kernel.parameters[S1Parameter::isMono] > 0.f;
}

void S1HostMIDI::clear() {
    for (int n = 0; n < 128; ++n) {
        onKeys[n] = false;
        notesFromMIDI[n] = false;
        soundingFor[n] = -1;
        keyDown[n] = false;
        isPlaying[n] = false;
    }
    pedalIsDown = false;
    sustainMode = false;
}

// MARK: - Render thread entry points

void S1HostMIDI::handle(const S1MIDIEvent &event, S1DSPKernel &kernel) {
    if (event.length < 2) return;
    const int status  = event.data[0] & 0xF0;
    const int channel = event.data[0] & 0x0F;
    // Masked as `S1MIDI.dispatch` masks CoreMIDI's bytes.
    const int data1 = event.data[1] & 0x7F;
    const int data2 = event.length > 2 ? (event.data[2] & 0x7F) : 0;
    const bool threeBytes = event.length >= 3;

    switch (status) {
        case 0x90: if (threeBytes) noteOn(kernel, data1, data2, channel);     break;
        case 0x80: if (threeBytes) noteOff(kernel, data1, data2, channel);    break;
        case 0xB0: if (threeBytes) controller(kernel, data1, data2, channel); break;
        case 0xC0: forwardControl(kernel, event.data[0], data1, 0);           break;
        case 0xE0: if (threeBytes) pitchWheel(kernel, data1, data2, channel); break;
        default:   break;  // Aftertouch, both kinds: `Manager` ignores them.
    }
    postKeysIfChanged(kernel);
}

void S1HostMIDI::beginRenderCycle(S1DSPKernel &kernel) {
    // `KeyboardView.polyphonicMode`'s didSet.
    const bool mono = isMono(kernel);
    if (mono != lastMono) {
        lastMono = mono;
        allNotesOff(kernel);
    }
    // `KeyboardView.holdMode`'s didSet, which releases every key when hold goes off.
    const bool hold = holdMode.load(std::memory_order_relaxed);
    if (hold != lastHold) {
        lastHold = hold;
        if (!hold) allNotesOff(kernel);
    }
    // Also retries a key report the message queue had no room for.
    postKeysIfChanged(kernel);
}

void S1HostMIDI::allNotesOff(S1DSPKernel &kernel) {
    // `KeyboardView.allNotesOff`: each key's note-off, then forget them all.
    for (int key = 0; key < 128; ++key) {
        if (onKeys[key]) {
            onKeys[key] = false;
            keyboardNoteOff(kernel, key);
        }
    }
}

void S1HostMIDI::transportDidStop(S1DSPKernel &kernel) {
    // The CC123 case's three lines, without a controller to forward.
    allNotesOff(kernel);
    trace.record(S1HostMIDITrace::allNotesOff, 0, 0);
    kernel.stopAllNotes();
    postKeysIfChanged(kernel);
}

void S1HostMIDI::keyNoteOnFromInterface(S1DSPKernel &kernel, int note, int velocity) {
    trace.record(S1HostMIDITrace::keyNoteOn, note, velocity);
    kernel.startNote(note, velocity);
}

void S1HostMIDI::keyNoteOffFromInterface(S1DSPKernel &kernel, int note) {
    trace.record(S1HostMIDITrace::keyNoteOff, note, 0);
    kernel.stopNote(note);
}

// MARK: - Manager+MIDIListener

void S1HostMIDI::noteOn(S1DSPKernel &kernel, int note, int velocity, int channel) {
    // `receivedMIDINoteOn`
    if (!accepts(channel)) return;
    if (velocity == 0) {
        noteOff(kernel, note, velocity, channel);
        return;
    }
    // No velocity step to port: since ADR-032 neither product flattens velocity to 127.

    const int sounding = note + octaveShift.load(std::memory_order_relaxed);   // `soundingNote(for:)`
    if (!inMIDIRange(sounding)) return;
    soundingFor[note] = (int16_t)sounding;
    pressAdded(kernel, sounding, velocity);
    notesFromMIDI[sounding] = true;
}

void S1HostMIDI::noteOff(S1DSPKernel &kernel, int note, int velocity, int channel) {
    // `receivedMIDINoteOff`
    if (!accepts(channel) || holdMode.load(std::memory_order_relaxed)) return;

    // The note this key started, falling back to the current shift for a note-off with no
    // note-on.
    int sounding = soundingFor[note];
    soundingFor[note] = -1;
    if (sounding < 0) {
        sounding = note + octaveShift.load(std::memory_order_relaxed);
        if (!inMIDIRange(sounding)) return;
    }

    pressRemoved(kernel, sounding);
    notesFromMIDI[sounding] = false;

    // Mono: re-press the highest note still held — with this note-off's velocity, as upstream.
    if (isMono(kernel)) {
        for (int remaining = 127; remaining >= 0; --remaining) {
            if (notesFromMIDI[remaining] && remaining != sounding) {
                pressAdded(kernel, remaining, velocity);
                break;
            }
        }
    }
}

void S1HostMIDI::controller(S1DSPKernel &kernel, int number, int value, int channel) {
    // Every control goes to `Manager.receivedMIDIController`, which does its own channel check.
    forwardControl(kernel, (uint8_t)(0xB0 | channel), (uint8_t)number, (uint8_t)value);

    // Upstream's `handleMIDIEvent` stopped every note on CC123 from any channel, and hosts send
    // it on transport stop. Kept, and the keys it released are forgotten too.
    if (number == 123) {
        allNotesOff(kernel);
        trace.record(S1HostMIDITrace::allNotesOff, 0, 0);
        kernel.stopAllNotes();
        return;
    }

    if (!accepts(channel)) return;

    // `case AKMIDIControl.damperOnOff`
    if (number == 64) {
        if (value > 0 && !sustainMode) {
            sustainPedal(kernel, true);
            sustainMode = true;
        } else if (sustainMode) {
            sustainPedal(kernel, false);
            sustainMode = false;
        }
    }
}

void S1HostMIDI::pitchWheel(S1DSPKernel &kernel, int lsb, int msb, int channel) {
    // `receivedMIDIPitchWheel`. The kernel posts the change to the interface itself.
    if (!accepts(channel)) return;
    const int bend = lsb | (msb << 7);
    trace.record(S1HostMIDITrace::pitchBend, 0, (uint32_t)bend);
    kernel.setDependentParameter(S1Parameter::pitchbend, (float)bend / 16383.f, 0);
}

// MARK: - KeyboardView+Touches

void S1HostMIDI::pressAdded(S1DSPKernel &kernel, int key, int velocity) {
    // `pressAdded(_:velocity:)`
    bool noteIsAlreadyOn = false;
    if (holdMode.load(std::memory_order_relaxed) && onKeys[key]) {
        noteIsAlreadyOn = true;
        pressRemoved(kernel, key);
    }
    if (isMono(kernel)) {
        for (int other = 0; other < 128; ++other) {
            if (onKeys[other] && other != key) pressRemoved(kernel, other);
        }
    }
    if (!onKeys[key] && !noteIsAlreadyOn) {
        onKeys[key] = true;
        keyboardNoteOn(kernel, key, velocity);
    }
}

void S1HostMIDI::pressRemoved(S1DSPKernel &kernel, int key) {
    // `pressRemoved(_:touches:isFromMIDI:)`. Its mono branch re-presses the highest remaining
    // *touch*, and MIDI passes none, so there is nothing to port.
    if (!onKeys[key]) return;
    onKeys[key] = false;
    keyboardNoteOff(kernel, key);
}

// MARK: - Manager+Keyboard

void S1HostMIDI::keyboardNoteOn(S1DSPKernel &kernel, int key, int velocity) {
    // `noteOn(note:velocity:)`
    if (key >= 128) return;
    const int note = whiteKeysOnly.load(std::memory_order_relaxed) ? kWhiteKeysOnlyMap[key] : key;
    sustainerPlay(kernel, note, velocity);
}

void S1HostMIDI::keyboardNoteOff(S1DSPKernel &kernel, int key) {
    // `noteOff(note:)`
    if (key >= 128) return;
    const int note = whiteKeysOnly.load(std::memory_order_relaxed) ? kWhiteKeysOnlyMap[key] : key;
    sustainerStop(kernel, note);
}

// MARK: - SDSustainer

void S1HostMIDI::sustainerPlay(S1DSPKernel &kernel, int note, int velocity) {
    // `play(noteNumber:velocity:)`
    if (pedalIsDown && keyDown[note]) {
        stop(kernel, note);
    } else {
        keyDown[note] = true;
    }
    start(kernel, note, velocity);
    isPlaying[note] = true;
}

void S1HostMIDI::sustainerStop(S1DSPKernel &kernel, int note) {
    // `stop(noteNumber:)`
    if (!pedalIsDown) {
        stop(kernel, note);
        isPlaying[note] = false;
    }
    keyDown[note] = false;
}

void S1HostMIDI::sustainPedal(S1DSPKernel &kernel, bool down) {
    // `sustain(down:)`
    if (down) {
        pedalIsDown = true;
        return;
    }
    for (int note = 0; note < 128; ++note) {
        if (isPlaying[note] && !keyDown[note]) {
            stop(kernel, note);
            keyDown[note] = false;
            isPlaying[note] = false;
        }
    }
    pedalIsDown = false;
}

// MARK: - To the kernel and the interface

void S1HostMIDI::start(S1DSPKernel &kernel, int note, int velocity) {
    trace.record(S1HostMIDITrace::hostNoteOn, note, velocity);
    kernel.startNote(note, velocity);
}

void S1HostMIDI::stop(S1DSPKernel &kernel, int note) {
    trace.record(S1HostMIDITrace::hostNoteOff, note, 0);
    kernel.stopNote(note);
}

void S1HostMIDI::forwardControl(S1DSPKernel &kernel, uint8_t status, uint8_t data1, uint8_t data2) {
    // PORT (X1-2, ADR-066): through the kernel's listener; the audio unit posts it.
    const S1HostMIDIMessage message = {status, data1, data2};
    if (kernel.listener) kernel.listener->hostMIDIControlDidArrive(message);
}

void S1HostMIDI::postKeysIfChanged(S1DSPKernel &kernel) {
    S1HostKeys keys = {0, 0};
    for (int key = 0; key < 128; ++key) {
        if (!onKeys[key]) continue;
        if (key < 64) keys.low |= (1ull << key);
        else          keys.high |= (1ull << (key - 64));
    }
    if (keys.low == postedKeysLow && keys.high == postedKeysHigh) return;
    // Only remembered once it is on its way: a full queue is retried next render cycle.
    if (kernel.listener && kernel.listener->hostHeldKeysDidChange(keys)) {
        postedKeysLow = keys.low;
        postedKeysHigh = keys.high;
    }
}
