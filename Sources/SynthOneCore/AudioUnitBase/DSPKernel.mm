/*
    Utility code to manage scheduled parameters in an audio unit implementation.

    Originally Apple sample code, as vendored by AudioKit 4.9.2. Ported verbatim.
 */

#import "AudioKit/DSPKernel.hpp"

#include <algorithm>

void DSPKernel::handleOneEvent(AURenderEvent const *event) {
    switch (event->head.eventType) {
        case AURenderEventParameter:
        case AURenderEventParameterRamp: {
            AUParameterEvent const& paramEvent = event->parameter;
            startRamp(paramEvent.parameterAddress, paramEvent.value, paramEvent.rampDurationSampleFrames);
            break;
        }

        case AURenderEventMIDI:
            handleMIDIEvent(event->MIDI);
            break;

        default:
            break;
    }
}

void DSPKernel::performAllSimultaneousEvents(AUEventSampleTime now, AURenderEvent const *&event) {
    do {
        handleOneEvent(event);
        event = event->head.next;
    } while (event && event->head.eventSampleTime == now);
}

/**
    Handles the event list processing and rendering loop.
    Call it inside your internalRenderBlock.
 */
void DSPKernel::processWithEvents(AudioTimeStamp const *timestamp, AUAudioFrameCount frameCount, AURenderEvent const *events) {

    AUEventSampleTime now = AUEventSampleTime(timestamp->mSampleTime);
    AUAudioFrameCount framesRemaining = frameCount;
    AURenderEvent const *event = events;

    while (framesRemaining > 0) {
        // If there are no more events, process the entire remaining segment and exit.
        if (event == nullptr) {
            AUAudioFrameCount const bufferOffset = frameCount - framesRemaining;
            process(framesRemaining, bufferOffset);
            return;
        }

        // PORT FIX (P4-2): upstream is
        //
        //     AUAudioFrameCount const framesThisSegment =
        //         AUAudioFrameCount(event->head.eventSampleTime - now);
        //
        // `eventSampleTime - now` is a **signed** AUEventSampleTime; AUAudioFrameCount
        // is **unsigned**. A parameter scheduled at or before `now` — which is exactly
        // what `AUEventSampleTimeImmediate` produces, and therefore what every host
        // automation move produces — makes that difference negative, and the cast
        // turns it into ~4 billion. `framesThisSegment > 0` is then true and
        // `process()` writes four billion frames into a 4,096-frame buffer.
        //
        // That is a hard segfault on the render thread. It killed the out-of-process
        // extension the first time `auval` set a parameter, which left `auval` itself
        // blocked forever in `signal_wait` waiting for an XPC reply that never came.
        //
        // Upstream never hit it because Synth One never implemented the AU parameter
        // tree — `///auv3, not yet used` in `S1AudioUnit.h`. This code has therefore
        // never run in Synth One's history.
        //
        // Two clamps are needed: an event at or before `now` is due immediately (0
        // frames), and an event scheduled past the end of this buffer must not make
        // us render beyond it.
        AUEventSampleTime const framesToNextEvent = event->head.eventSampleTime - now;
        AUAudioFrameCount const framesThisSegment =
            framesToNextEvent <= 0
                ? 0
                : AUAudioFrameCount(std::min<AUEventSampleTime>(framesToNextEvent,
                                                                AUEventSampleTime(framesRemaining)));

        // Compute everything before the next event.
        if (framesThisSegment > 0) {
            AUAudioFrameCount const bufferOffset = frameCount - framesRemaining;
            process(framesThisSegment, bufferOffset);
            framesRemaining -= framesThisSegment;
            now += AUEventSampleTime(framesThisSegment);
        }

        performAllSimultaneousEvents(now, event);
    }
}
