//  Replacement for AudioKit's AKSoundpipeKernel.hpp. Ported from AudioKit 4.9.2
//  (MIT). Owns the sp_data lifecycle. Names kept per ADR-009. See PORTING.md.

#ifdef __cplusplus
#pragma once

extern "C" {
#include "soundpipe.h"
#include "soundpipeextension.h"
}

#import "AudioKit/AKDSPKernel.hpp"

class AKSoundpipeKernel: public AKDSPKernel {
protected:
    sp_data *sp = nullptr;
public:

    sp_data *getSpData() { return sp; }

    AKSoundpipeKernel() = default;

    AKSoundpipeKernel(int channelCount, double sampleRate) :
        AKDSPKernel(channelCount, sampleRate) {
        sp_create(&sp);
        sp->sr = sampleRate;
        sp->nchan = channelCount;
    }

    void init(int channelCount, double sampleRate) override {
        AKDSPKernel::init(channelCount, sampleRate);
        if (sp == nullptr) {
            sp_create(&sp);
        }
        sp->sr = sampleRate;
        sp->nchan = channelCount;
    }

    ~AKSoundpipeKernel() {
        // Memory is released in the destructor only.
        sp_destroy(&sp);
    }

    void destroy() {
    }
};

#endif
