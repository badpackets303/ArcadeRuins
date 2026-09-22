//
//  S1DSPKernel+events.cpp
//  Arcade Ruins
//
//  PORT (X1-3, ADR-067): a render cycle with its events, in plain C++.
//
//  This is Apple's DSPKernel::processWithEvents (AudioUnitBase/DSPKernel.mm, vendored by
//  AudioKit, with the P4-2 fix) over S1Event instead of AURenderEvent: render up to the next
//  event, apply every event at that offset, carry on. An event at or before the current frame
//  is due now; one past the end of the buffer is applied after the last frame. Same cuts in the
//  same places, so a JUCE host and an AU host render the same bytes from the same events.
//

#include "S1DSPKernel.hpp"

#include <algorithm>

void S1DSPKernel::processWithEvents(S1FrameCount frameCount, const S1Event *events, int eventCount) S1_NONBLOCKING {
    S1FrameCount now = 0;
    S1FrameCount framesRemaining = frameCount;
    int next = 0;

    auto apply = [this](const S1Event &event) {
        switch (event.kind) {
            case S1EventKind_Parameter:
                startRamp(event.address, event.value, event.rampFrames);
                break;
            case S1EventKind_MIDI:
                handleMIDIEvent(event.midi);
                break;
        }
    };

    while (framesRemaining > 0) {
        // No more events: render the rest and leave.
        if (events == nullptr || next >= eventCount) {
            process(framesRemaining, frameCount - framesRemaining);
            return;
        }

        // Up to the next event, and never past the end of this buffer (the P4-2 clamps).
        const S1FrameCount eventOffset = events[next].sampleOffset;
        const S1FrameCount framesThisSegment =
            eventOffset <= now ? 0 : std::min<S1FrameCount>(eventOffset - now, framesRemaining);

        if (framesThisSegment > 0) {
            process(framesThisSegment, frameCount - framesRemaining);
            framesRemaining -= framesThisSegment;
            now += framesThisSegment;
        }

        // Every event due at this frame — including all of them, if the list runs past the end.
        if (framesRemaining == 0) { break; }
        do {
            apply(events[next]);
            ++next;
        } while (next < eventCount && events[next].sampleOffset <= now);
    }

    // Events at or past the end of the buffer apply after the last frame, as AURenderEvents
    // scheduled beyond a cycle would be applied at the start of the next one by the host.
    while (next < eventCount) {
        apply(events[next]);
        ++next;
    }
}
