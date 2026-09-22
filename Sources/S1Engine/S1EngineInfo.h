// S1EngineInfo — what this build of the portable engine is.
//
// X1-1's only C++: enough to prove the library builds, links Soundpipe and is callable from a
// host on every toolchain. The engine proper arrives in X1-2 … X1-6.
#ifndef S1ENGINE_INFO_H
#define S1ENGINE_INFO_H

namespace s1 {

struct EngineInfo {
    /// The number of synth parameters the engine will expose. S1Parameter.h's S1ParameterCount;
    /// asserted equal to it once that header moves here (X1-3).
    int parameterCount;
    /// sizeof(SPFLOAT). The goldens are float32 (ADR-016); a build with SPFLOAT=double is a
    /// different instrument.
    int sampleSizeInBytes;
    /// Soundpipe's default sample rate, read from a live sp_data — proof the C library is linked.
    int soundpipeDefaultSampleRate;
};

EngineInfo engineInfo();

}  // namespace s1

#endif
