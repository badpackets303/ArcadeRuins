//
//  S1DSPCompressor.hpp
//  AudioKitSynthOne
//
//  Created by Matthias Frick on 11/03/2019.
//  Copyright © 2019 AudioKit. All rights reserved.
//

#include "S1KernelBase.hpp"
#include <memory>   // PORT (X1-3): std::unique_ptr; libc++ supplied it transitively, libstdc++ and MSVC do not
#include "S1Parameter.h"

#ifndef S1DSPCompressor_h
#define S1DSPCompressor_h
using DSPParameters = std::array<float, S1Parameter::S1ParameterCount>;

struct SPCompressorDeleter {
    void operator()(sp_compressor* compInst) const {
        sp_compressor_destroy(&compInst);
    }
};

struct SPCompressorAllocator {
    static auto allocate() -> sp_compressor* {
        sp_compressor* compPtr;
        sp_compressor_create(&compPtr);
        return compPtr;
    }
};

template<int RatioP, int ThresholdP, int AttP, int RelP, int MakeupP = -1>
struct S1Compressor {

    S1Compressor() = delete;
    S1Compressor(S1Compressor&&) = delete;
    S1Compressor(const S1Compressor&) = delete;

    S1Compressor(sp_data* sp, DSPParameters* params) :
        mSp(sp),
        mParams(params),
        mCompressorL(SPCompressorAllocator::allocate()),
        mCompressorR(SPCompressorAllocator::allocate())
    {
        sp_compressor_init(mSp, mCompressorR.get());
        sp_compressor_init(mSp, mCompressorL.get());
    }

    /// PORT FIX (X2-9, ADR-080): made again for the sample rate the kernel is now at. Upstream
    /// makes the compressors once, in the kernel's CONSTRUCTOR, and `sp_compressor_init` takes
    /// its time constants from the rate of that moment; `S1DSPKernel::init` — which every host
    /// calls afterwards with the real rate — never touched them. A kernel constructed at 44.1 kHz
    /// (every host's: the AU's, the JUCE plugin's) and run at 96 kHz attacked and released 2.2x
    /// too fast. New objects, not a second init: `sp_compressor_init` allocates its Faust state.
    void prepare() {
        mCompressorL.reset(SPCompressorAllocator::allocate());
        mCompressorR.reset(SPCompressorAllocator::allocate());
        sp_compressor_init(mSp, mCompressorR.get());
        sp_compressor_init(mSp, mCompressorL.get());
    }

    void compute(float &inL, float &inR, float &outL, float &outR) {
        configure(mCompressorR.get());
        configure(mCompressorL.get());
        compute(mCompressorR.get(), inR, outR);
        compute(mCompressorL.get(), inL, outL);
        if (MakeupP != -1) {
            outR *= (*mParams)[MakeupP];
            outL *= (*mParams)[MakeupP];
        }
    }

private:

    void configure(sp_compressor *comp) {
        *comp->atk = (*mParams)[AttP];
        *comp->rel = (*mParams)[RelP];
        *comp->thresh = (*mParams)[ThresholdP];
        *comp->ratio = (*mParams)[RatioP];
    }

    void compute(sp_compressor *comp, float &in, float &out) {
        sp_compressor_compute(mSp, comp, &in, &out);
    }

    // Parameter Reference
    DSPParameters* mParams;

    // DSP Internals
    std::unique_ptr<sp_compressor, SPCompressorDeleter> mCompressorR;
    std::unique_ptr<sp_compressor, SPCompressorDeleter> mCompressorL;
    sp_data* mSp;
};

#endif /* S1DSPCompressor_h */
