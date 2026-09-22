/*
    Utility code to manage scheduled parameters in an audio unit implementation.

    Originally Apple sample code, as vendored by AudioKit 4.9.2.
    Ported verbatim — see Sources/SynthOneCore/AudioUnitBase/PORTING.md.
 */

#ifdef __cplusplus
#pragma once

#import <AudioToolbox/AudioToolbox.h>
#import <algorithm>

// X1-3 (ADR-067): the engine's S1KernelBase.hpp defines the same helper; whichever header a
// translation unit meets first defines it and the other steps aside.
#ifndef S1_KERNEL_HELPERS_DEFINED
template <typename T>
T clamp(T input, T low, T high) {
    return std::min(std::max(input, low), high);
}
#endif

// Put your DSP code into a subclass of DSPKernel.
class DSPKernel {
public:
    virtual void process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) = 0;
    virtual void startRamp(AUParameterAddress address, AUValue value, AUAudioFrameCount duration) = 0;

    // Override to handle MIDI events.
    virtual void handleMIDIEvent(AUMIDIEvent const& midiEvent) {}

    void processWithEvents(AudioTimeStamp const *timestamp, AUAudioFrameCount frameCount, AURenderEvent const *events);

private:
    void handleOneEvent(AURenderEvent const *event);
    void performAllSimultaneousEvents(AUEventSampleTime now, AURenderEvent const*& event);
};

#endif
