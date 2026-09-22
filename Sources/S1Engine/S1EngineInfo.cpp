#include "S1EngineInfo.h"
#include "S1Parameter.h"

extern "C" {
#include "soundpipe.h"
}

namespace s1 {

EngineInfo engineInfo() {
    EngineInfo info{};
    info.parameterCount = S1Parameter::S1ParameterCount;
    info.sampleSizeInBytes = static_cast<int>(sizeof(SPFLOAT));

    // sp_create returns 0, not SP_OK (CLAUDE.md): check the out-pointer, not the result.
    sp_data *sp = nullptr;
    sp_create(&sp);
    if (sp != nullptr) {
        info.soundpipeDefaultSampleRate = sp->sr;
        sp_destroy(&sp);
    }
    return info;
}

}  // namespace s1
