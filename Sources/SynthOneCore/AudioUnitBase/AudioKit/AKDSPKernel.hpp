//  Replacement for AudioKit's AKDSPKernel.hpp. Ported from AudioKit 4.9.2 (MIT),
//  minus AKParametricKernel/ParameterRamper, which Synth One does not use.
//  Names kept per ADR-009. See PORTING.md.

#ifdef __cplusplus
#pragma once

#import "AudioKit/DSPKernel.hpp"

class AKDSPKernel : public DSPKernel {
protected:
    int channels;
    float sampleRate;
public:
    AKDSPKernel(int channelCount, float sampleRate) : channels(channelCount), sampleRate(sampleRate) { }
    AKDSPKernel() : channels(2), sampleRate(44100.f) { }

    float getSampleRate() { return sampleRate; }

    virtual ~AKDSPKernel() { }

    virtual void init(int channelCount, double sampleRate) {
        // PORT FIX: upstream reads `channels = channelCount; sampleRate = sampleRate;`
        // — the second is a self-assignment, so the member was never updated and
        // getSampleRate() returned a stale value after a sample-rate change.
        // See PORTING.md.
        this->channels = channelCount;
        this->sampleRate = sampleRate;
    }
};

class AKOutputBuffered {
protected:
    AudioBufferList *outBufferListPtr = nullptr;
public:
    void setBuffer(AudioBufferList *outBufferList) {
        outBufferListPtr = outBufferList;
    }
};

class AKBuffered: public AKOutputBuffered {
protected:
    AudioBufferList *inBufferListPtr = nullptr;
public:
    void setBuffers(AudioBufferList *inBufferList, AudioBufferList *outBufferList) {
        AKOutputBuffered::setBuffer(outBufferList);
        inBufferListPtr = inBufferList;
    }
};

// From AudioKit's AKBankDSPKernel.hpp. NOTE: this SQUARES its argument — it is
// not 2^x, despite the name. Synth One uses it as a velocity curve, so reading
// it as an exponential would change how the instrument responds to touch.
// X1-3 (ADR-067): see DSPKernel.hpp — S1KernelBase.hpp defines these too.
#ifndef S1_KERNEL_HELPERS_DEFINED
#define S1_KERNEL_HELPERS_DEFINED
static inline double pow2(double x) {
    return x * x;
}

static inline double noteToHz(int noteNumber)
{
    return 440. * exp2((noteNumber - 69)/12.);
}
#endif

#endif
