//
//  S1Sequencer.hpp
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 3/06/19.
//  Copyright © 2019 AudioKit. All rights reserved.
//
#include <algorithm>
#include <array>
#include <cmath>
#include <atomic>
#include <functional>
#include <list>
#include <vector>

#include "S1EngineTypes.h"
#include "S1Parameter.h"
#include "S1SeqNoteNumber.hpp"
// PORT (X1-2, ADR-066): the held keys arrive as a snapshot, not an AEArray.
#include "../Kernel/S1HeldNotes.hpp"

#ifdef __cplusplus

using DSPParameters = std::array<float, S1Parameter::S1ParameterCount>;
using BeatCounterChangedCallback = std::function<void()>;
using KeyOnCallback = std::function<void(int, int)>;
using KeyOffCallback = std::function<void(int)>;

class S1Sequencer {

public:
    S1Sequencer() = delete;
    S1Sequencer(KeyOnCallback keyOnCb, KeyOffCallback keyOffCb, BeatCounterChangedCallback beatChangedCb);

    void setSampleRate(double sampleRate);
    void init();
    void reset(bool resetNotes);

    /// P4-5. Rewind to step 0 without touching notes.
    ///
    /// `reset(bool)` does **not** do this — it clears the pending-note vectors and
    /// leaves `mBeatTime` and `mStepCounter` where they were, which is why
    /// `S1DSPKernel::resetSequencer` never actually rewound anything. Upstream only
    /// ever rewound on the held-keys edge inside `process`.
    ///
    /// Called from the render thread, like `process`, so these are plain writes.
    void resetPosition();
    void setNotesPerOctave(int notes);

    int getArpBeatCount();
    void process(DSPParameters &params, const S1HeldNoteList &heldNotes);

private:
    double mSampleRate = 0;
    const int maxSequencerNotes = 1024; // 128 midi note numbers * 4 arp octaves * up+down
    void reserveNotes(); // Allocate notes before rendering

    // Array of midi note numbers of NoteState's which have had a noteOn event but not yet a noteOff event.
    int previousHeldNoteNumbersAECount; // previous render loop held key count

    // Beattime Counter
    double mBeatTime = 0;
    std::atomic<int> mStepCounter = 0;

    ///once init'd: sequencerNotes can be accessed and mutated only within process and resetDSP
    std::vector<SeqNoteNumber> sequencerNotes;
    std::vector<NoteNumber> sequencerNotes2;

    ///once init'd: sequencerLastNotes can be accessed and mutated only within process and resetDSP
    // PORT FIX (X2-8, ADR-079): was `std::list<int>` — a malloc for every note an arpeggio step
    // turns on and a free for every one it turns off, on the audio thread (found by the
    // RealtimeSanitizer). A vector at the capacity `reserveNotes` gives it does neither, and is
    // pushed to, walked and cleared in the same order. `reserveNotes` still RESIZES it, as
    // upstream does (so it starts as 1,024 zeros, which the first step boundary "turns off"):
    // that oddity is upstream's and the goldens', and it is kept.
    std::vector<int> sequencerLastNotes;

    std::atomic<int> mNotesPerOctave{12};

    // Change notifications
    BeatCounterChangedCallback mBeatCounterDidChange;
    KeyOnCallback mTurnOnKey;
    KeyOffCallback mTurnOffKey;
};

#endif
