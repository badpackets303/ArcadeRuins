//
//  S1DSPKernel+parameters.mm
//  AudioKitSynthOne
//
//  Created by Aurelius Prochazka on 6/4/18.
//  Copyright © 2018 AudioKit. All rights reserved.
//

#include "S1DSPKernel.hpp"
#include "S1NoteState.hpp"

///parameter min
float S1DSPKernel::minimum(S1Parameter i) {
    return s1p[i].minimum;
}

///parameter max
float S1DSPKernel::maximum(S1Parameter i) {
    return s1p[i].maximum;
}

///parameter defaults
float S1DSPKernel::defaultValue(S1Parameter i) {
    return clampedValue(i, s1p[i].defaultValue);
}

S1ParameterUnit S1DSPKernel::parameterUnit(S1Parameter i) {
    return s1p[i].unit;
}

///return clamped value
float S1DSPKernel::clampedValue(S1Parameter i, float inputValue) {
    const float minimum = s1p[i].minimum;
    const float maximum = s1p[i].maximum;
    const float clampedValue = std::min(std::max(inputValue, minimum), maximum);
    return clampedValue;
}

///parameter friendly name as c string
const char* S1DSPKernel::cString(S1Parameter i) {
    return s1p[i].friendlyName.c_str();
}

///parameter friendly name
std::string S1DSPKernel::friendlyName(S1Parameter i) {
    return s1p[i].friendlyName;
}

///parameter presetKey
std::string S1DSPKernel::presetKey(S1Parameter i) {
    return s1p[i].presetKey;
}

void S1DSPKernel::setParameters(float params[]) {
    for (int i = 0; i < S1Parameter::S1ParameterCount; i++) {
        setSynthParameter((S1Parameter)i, params[i]);
    }
}

void S1DSPKernel::setParameter(S1ParameterAddress address, S1ParameterValue value) {
    const int i = (S1Parameter)address;
    setSynthParameter((S1Parameter)i, value);
}

S1ParameterValue S1DSPKernel::getParameter(S1ParameterAddress address) {
    const int i = (S1Parameter)address;
    return parameters[i];
}

// PORT FIX (P4-3): upstream leaves this empty — Synth One never implemented the AU
// parameter path (`///auv3, not yet used` in S1AudioUnit.h), so every host
// automation move arrived on the render thread and was silently discarded.
//
// This is the render-thread end of the automation path:
//   host → AUParameter.value → implementorValueObserver (installed by
//   AKAudioUnit::setUpParameterRamp, *not* the one in S1AudioUnit::createParameters)
//   → scheduleParameterBlock → DSPKernel::processWithEvents → handleOneEvent → here.
//
// Two deliberate choices, both recorded in ADR-022:
//
//  * `duration` is ignored. The kernel already smooths, per sample, with Soundpipe
//    `sp_port` on the 46 parameters whose `usePortamento` is true (see the render
//    loop in S1DSPKernel+process.mm); the other 104 step, exactly as they do when
//    the standalone's UI sets them. Honouring an AU ramp as well would put a second
//    smoother in series with the first and make automation of those 46 lag twice.
//
//  * `setSynthParameter` — i.e. `notifyMainThread = true`. For 142 parameters that
//    flag does nothing at all. For the eight dependent ones it is the only channel
//    that reports which value actually took effect, because `_rateHelper`
//    *quantizes* what it is handed to the nearest musical division. The
//    notification is a lock-free ring-buffer write (TAAE), so it is safe from here;
//    it is best-effort, and dropping one under saturation costs a UI refresh, not
//    a sample.
void S1DSPKernel::startRamp(S1ParameterAddress address, S1ParameterValue value, S1FrameCount duration) {
    // The address comes from the host and nothing upstream of here validates it.
    // `s1p` and `parameters` are fixed 150-element arrays, so an address a host
    // invented would read and write past the end of the kernel — on the render
    // thread. Drop it instead.
    if (address >= (S1ParameterAddress)S1Parameter::S1ParameterCount) { return; }
    (void)duration;
    setSynthParameter((S1Parameter)address, value);
}

void S1DSPKernel::updatePortamento(float halfTime) {
    const float ht = clampedValue(portamentoHalfTime, halfTime);
    for(int i = 0; i< S1Parameter::S1ParameterCount; i++) {
        if (s1p[i].usePortamento) {
            s1p[i].portamento->htime = ht;
        }
    }
}

// PORT FIX (P4-5): upstream stored the host tempo and did nothing with it —
// `//TODO:set s1 param arpRate`, and a second `// TODO: reset secPerBeat here?`.
// Both are answered by upstream's *own* Ableton Link listener, which is where a
// tempo came from on iOS:
//
//     ABLLinkManager.shared.add(listener: .tempo({ bpm, quantum in
//         self.tempoStepper.value = bpm
//         self.conductor.synth.setSynthParameter(.arpRate, bpm)
//     }))
//                              — upstream/AudioKitSynthOne/Link/LinkExtensions.swift
//
// So a host tempo *is* `arpRate`. Link is dropped (ADR-004), which is exactly why
// this work landed here. There is no "secPerBeat" to reset: the sequencer's clock is
// `mBeatTime += (arpRate / 60) / sampleRate`, in beats, so changing `arpRate` is the
// whole of it.
//
// Setting `arpRate` also re-drives `lfo1Rate`, `lfo2Rate`, `autoPanFrequency` and
// `delayTime` through `_rateHelper` (ADR-022), which is the point: a tempo change
// should re-quantize every tempo-synced value. `setSynthParameter` clamps to the
// parameter's own range, so an absurd host tempo cannot push it out of bounds.
void S1DSPKernel::handleTempoSetting(float currentTempo) {
    // Compare against **`arpRate`**, not against the last tempo we saw.
    //
    // The obvious `if (currentTempo != tempo)` is wrong twice, and the owner caught
    // it: `tempo` is initialised to 120, so a project at Logic's default 120 BPM
    // never differs from it and `arpRate` was never set at all. And even once it has
    // fired, loading a preset writes its own `arpRate` — 100, in the case that
    // exposed this — and a host tempo that has not changed since would never correct
    // it. Comparing against the value that actually matters makes the host
    // continuously authoritative and self-correcting after a preset.
    //
    // Clamped first so an out-of-range project tempo settles instead of being
    // re-applied every render block, which would re-drive four dependent parameters
    // and post a main-thread message each time.
    const float target = clampedValue(arpRate, currentTempo);
    if (getSynthParameter(arpRate) == target) { return; }

    tempo = currentTempo;
    // X2 gate (ADR-082): a host's tempo keeps what is synced to it on its note value. (With sync
    // off nothing is synced, and this is upstream's plain write.)
    if (parameters[tempoSyncToArpRate] > 0.f) {
        _setTempoKeepingNoteValues(target, true, 0);
    } else {
        setSynthParameter(arpRate, target);
    }
    // And tell the interface, or the plugin's tempo control keeps showing its own
    // value while the arpeggiator runs at the project tempo.
    hostTempoDidChange(getSynthParameter(arpRate));
}

// PORT: net-new at P4-5. Upstream had no host and never saw a transport.
//
// Only the *edges* matter, and only one of them does anything: when the host stops,
// release whatever is sounding and put the sequencer back to step 0, so starting
// again begins a phrase rather than resuming mid-arpeggio. A host normally sends
// note-offs when it stops, but not always — and a synth left droning after the
// transport stops is the worst version of this bug.
//
// Deliberately *not* done: forcing the sequencer's position from the host's beat
// position. `S1Sequencer::process` resets `mBeatTime` to 0 whenever held keys go
// from none to some, so the arpeggiator starts **when you play** rather than on the
// bar line. That is upstream's design and it is what makes a held-chord arpeggiator
// feel responsive. It also stays repeatable in an offline bounce, because the thing
// that sets the phase — the note-on — arrives at the same place every time.
void S1DSPKernel::handleTransportState(bool isMoving) {
    if (isMoving == transportIsMoving) { return; }
    transportIsMoving = isMoving;
    if (isMoving) { return; }

    // Release, not silence. `reset()` looks like the method for this and is not:
    // it calls `S1NoteState::clear()`, which sets `amp = 0` outright, so every
    // sounding voice would stop mid-cycle and click. These are the two lines
    // `turnOffKey` uses, without its held-note bookkeeping — `heldNoteNumbers` is
    // a main-thread `NSMutableArray` and this runs on the render thread.
    initializeNoteStates();
    for (int i = 0; i < S1_MAX_POLYPHONY; i++) {
        S1NoteState& note = (*noteStates)[i];
        if (note.stage != S1NoteState::stageOff) {
            note.stage = S1NoteState::stageRelease;
            note.internalGate = 0;
            // PORT FIX (X2-6, ADR-077): `turnOffKey` uses FOUR lines for a polyphonic voice, and
            // P4-5 copied two. Without these the envelopes never see the gate fall when the voice
            // has already decayed under the release threshold (any sound with no sustain): it is
            // freed before it runs again, the envelope stays where a held key left it, and the
            // voice's next note — gate still high, so no attack — is silent.
            sp_adsr_compute(sp, note.adsr, &note.internalGate, &note.amp);
            sp_adsr_compute(sp, note.fadsr, &note.internalGate, &note.filter);
        }
    }
    if (monoNote->stage != S1NoteState::stageOff) {
        monoNote->stage = S1NoteState::stageRelease;
        monoNote->internalGate = 0;
    }

    // PORT FIX (X2-6, ADR-077): and the keys go with the voices. Releasing the voices alone left
    // every key down — in `heldNotes`, so an arpeggio went on after the stop, and in the host MIDI
    // router, which does not press a key that is already down: a host that stopped without
    // note-offs (the case this function exists for) had its next note-on of the same key
    // swallowed. Found by Tests/Plugin/PluginTransportTests; a stop is now what CC123 is.
    // (`heldNotes` has been render-thread safe since X1-2, which the comment above predates.)
    if (hostMIDI.enabled.load(std::memory_order_relaxed)) {
        hostMIDI.transportDidStop(*this);
    } else {
        stopAllNotes();
    }

    sequencer.resetPosition();
    beatCounterDidChange();
}
