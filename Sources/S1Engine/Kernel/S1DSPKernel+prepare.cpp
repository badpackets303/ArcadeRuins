//
//  S1DSPKernel+prepare.cpp
//  Arcade Ruins
//
//  PORT (X1-7, ADR-071): moved here from S1AudioUnit.mm's allocateRenderResourcesAndReturnError,
//  statement for statement.
//
#include "S1DSPKernel.hpp"

void S1DSPKernel::prepareToRender(int channelCount, double sampleRate) {
    // PORT FIX (X2-2, ADR-073): what is carried across `init` is what each parameter was SET to,
    // not where its smoothing has got to. Upstream saved `parameters`, and for the 45 smoothed
    // parameters that array is the glide's current position: it only reaches a newly set value
    // as frames are rendered. A host that restores its state and then allocates — no render in
    // between — therefore got the old values back for every smoothed parameter (cutoff, the
    // envelopes, the mix…) and the new ones for the rest. `getSynthParameter` is the target for a
    // smoothed parameter and the value for any other. When nothing is gliding — every path the
    // goldens and the Mac tests take — the two arrays are equal and nothing changes.
    auto savedParameters = parameters;
    for (int i = 0; i < S1Parameter::S1ParameterCount; i++) {
        savedParameters[size_t(i)] = getSynthParameter((S1Parameter)i);
    }

    // PORT FIX (P4-4): the tuning table has to be carried across `init` too.
    //
    // `S1DSPKernel::init` rewrites all 128 entries back to 12-ET. Upstream saved and
    // restored `parameters` around it, but not the tuning table, and the gap was
    // invisible because the standalone's Tunings panel re-applies the tuning from
    // the UI after the engine starts. A plugin has no such second chance: the host
    // hands back its saved state and then allocates, and the temperament the session was
    // saved in would be silently replaced by 12-ET.
    float savedTuningTable[S1_NUM_MIDI_NOTES];
    for (int i = 0; i < S1_NUM_MIDI_NOTES; i++) {
        savedTuningTable[i] = getTuningTableFrequency(i);
    }
    const int savedTuningNPO = getTuningTableNPO();

    init(channelCount, sampleRate);
    reset();
    hostMIDI.kernelWasPrepared();       // PORT FIX (X2-10, ADR-081): the router's keys go with the voices
    restoreValues(savedParameters);

    for (int i = 0; i < S1_NUM_MIDI_NOTES; i++) {
        setTuningTable(savedTuningTable[i], i);
    }
    // After `init`, because it re-creates the sequencer this also configures.
    setTuningTableNPO(savedTuningNPO);

    updateWavetableIncrementValuesForCurrentSampleRate();

    // PORT FIX (X2-8, ADR-079): make the voices HERE. Upstream's `init` ends with "initializeNoteStates()
    // must be called AFTER init returns, BEFORE process" and then left it to the first `process` (or
    // the first key): seven note states, a dozen Soundpipe modules each, every one a malloc — on the
    // audio thread, in the first render cycle of every host. Found by the RealtimeSanitizer on its
    // first run. This is the place upstream's comment asks for: after `init`, before any render,
    // off the audio thread, and the oscillator tables are already required by the line above.
    // The lazy calls stay where they are and find the work done.
    initializeNoteStates();
}
