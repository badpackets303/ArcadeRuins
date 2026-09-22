//
//  S1KernelBase.hpp
//  Arcade Ruins
//
//  PORT (X1-3, ADR-067): what the kernel used to inherit from AudioKit's AKSoundpipeKernel,
//  AKDSPKernel, DSPKernel and AKOutputBuffered, kept — and only what it used. Apple's
//  DSPKernel (the AURenderEvent splitter) and AKOutputBuffered (an AudioBufferList) stay in
//  Sources/SynthOneCore/AudioUnitBase for the Apple products; `S1KernelAUAdapter` there
//  bridges them to this. Plain C++: no Apple headers.
//

#ifndef S1_KERNEL_BASE_HPP
#define S1_KERNEL_BASE_HPP

#ifdef __cplusplus

// X2-8 (ADR-079): the render entry points say so — in the RealtimeSanitizer build only
// (-DS1_RTSAN=ON: Clang 20+, -fsanitize=realtime), where anything they reach that allocates,
// locks or makes a blocking system call stops the program with a stack. In every product build
// the macro is empty: the attribute would want the functions noexcept, and nothing here changes
// for a check that only one CI job makes.
#if defined(S1_RTSAN)
#  define S1_NONBLOCKING [[clang::nonblocking]]
#else
#  define S1_NONBLOCKING
#endif

extern "C" {
#include "soundpipe.h"
#include "soundpipeextension.h"
}
// The standard headers the kernel's files use. Spelled out here, once: Apple's libc++ pulls
// most of them in transitively and libstdc++ and MSVC do not (X1-3, found by CI).
#include <algorithm>
#include <array>
#include <atomic>
#include <cfloat>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <list>
#include <memory>
#include <optional>
#include <string>
#include <vector>
#include "S1EngineTypes.h"

// The three helpers AudioKit's headers gave the kernel. Guarded by name, not by file, because
// the Apple adapter's translation unit sees both this header and AudioKit's, which define the
// same three for the test-tone kernel; whichever comes first wins and the other steps aside.
#ifndef S1_KERNEL_HELPERS_DEFINED
#define S1_KERNEL_HELPERS_DEFINED
template <typename T>
T clamp(T input, T low, T high) {
    return std::min(std::max(input, low), high);
}
/// Squares. Synth One's velocity curve — NOT 2^x (CLAUDE.md).
static inline double pow2(double x) {
    return x * x;
}
static inline double noteToHz(int noteNumber) {
    return 440. * exp2((noteNumber - 69) / 12.);
}
#endif

/// AKDSPKernel + AKSoundpipeKernel, as the kernel used them: a Soundpipe context, a channel
/// count and a sample rate, created in the constructor and released in the destructor.
class S1SoundpipeKernel {
protected:
    sp_data *sp = nullptr;
    int channels;
    float sampleRate;

public:
    S1SoundpipeKernel() : channels(2), sampleRate(44100.f) {}
    S1SoundpipeKernel(int channelCount, double sampleRate_) : channels(channelCount), sampleRate(float(sampleRate_)) {
        sp_create(&sp);
        sp->sr = int(sampleRate_);
        sp->nchan = channelCount;
    }
    virtual ~S1SoundpipeKernel() {
        // Memory is released in the destructor only.
        sp_destroy(&sp);
    }
    S1SoundpipeKernel(const S1SoundpipeKernel &) = delete;
    S1SoundpipeKernel &operator=(const S1SoundpipeKernel &) = delete;

    sp_data *getSpData() { return sp; }
    float getSampleRate() { return sampleRate; }

    virtual void init(int channelCount, double sampleRate_) {
        // PORT FIX (AKDSPKernel): upstream's `sampleRate = sampleRate` was a self-assignment, so
        // getSampleRate() returned a stale value after a sample-rate change.
        this->channels = channelCount;
        this->sampleRate = float(sampleRate_);
        if (sp == nullptr) {
            sp_create(&sp);
        }
        sp->sr = int(sampleRate_);
        sp->nchan = channelCount;
    }
    void destroy() {}
};

/// Where the kernel writes. The adapter (AU, JUCE) points these at the host's buffers before
/// each render cycle; `process(frameCount, bufferOffset)` indexes from them.
class S1OutputBuffered {
protected:
    float *outputLeft = nullptr;
    float *outputRight = nullptr;

public:
    void setOutput(float *left, float *right) {
        outputLeft = left;
        outputRight = right;
    }
};

#endif
#endif
