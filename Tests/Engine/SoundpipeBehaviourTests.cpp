// Behaviour, not linkage (CLAUDE.md): a bad port compiles and links and sounds wrong. These
// measure what Soundpipe does on this toolchain — the same checks must pass under Clang, GCC
// and MSVC, which is what X1-1 is for.
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "S1EngineInfo.h"

extern "C" {
#include "soundpipe.h"
}

namespace {

int failures = 0;

void check(bool ok, const char *what, double measured) {
    std::printf("%s  %s (measured %.6f)\n", ok ? "ok  " : "FAIL", what, measured);
    if (!ok) { ++failures; }
}

sp_data *makeSoundpipe() {
    sp_data *sp = nullptr;
    sp_create(&sp);   // returns 0, not SP_OK — check the pointer
    return sp;
}

constexpr double kPi = 3.14159265358979323846;

/// Upward zero crossings per second, skipping the first `skip` samples.
double frequencyOf(const std::vector<float> &x, int sampleRate, size_t skip = 0) {
    int crossings = 0;
    for (size_t i = skip + 1; i < x.size(); ++i) {
        if (x[i - 1] < 0.f && x[i] >= 0.f) { ++crossings; }
    }
    return double(crossings) * sampleRate / double(x.size() - skip);
}

double rmsOf(const std::vector<float> &x, size_t from) {
    double sum = 0;
    for (size_t i = from; i < x.size(); ++i) { sum += double(x[i]) * x[i]; }
    return std::sqrt(sum / double(x.size() - from));
}

void testEngineInfo() {
    const s1::EngineInfo info = s1::engineInfo();
    check(info.sampleSizeInBytes == 4, "SPFLOAT is float32, as the goldens are", info.sampleSizeInBytes);
    check(info.soundpipeDefaultSampleRate == 44100, "Soundpipe is linked and live", info.soundpipeDefaultSampleRate);
    check(info.parameterCount == 150, "150 parameters", info.parameterCount);
}

void testOscillatorPitchAndLevel() {
    sp_data *sp = makeSoundpipe();
    sp_ftbl *sine = nullptr;
    sp_osc *osc = nullptr;
    sp_ftbl_create(sp, &sine, 4096);
    sp_gen_sine(sp, sine);
    sp_osc_create(&osc);
    sp_osc_init(sp, osc, sine, 0);
    osc->freq = 440.f;
    osc->amp = 0.5f;

    std::vector<float> out(size_t(sp->sr) * 2);
    float peak = 0;
    for (float &s : out) {
        sp_osc_compute(sp, osc, nullptr, &s);
        peak = std::fmax(peak, std::fabs(s));
    }
    const double hz = frequencyOf(out, sp->sr);
    check(std::fabs(hz - 440.0) < 0.6, "sp_osc at 440 Hz plays 440 Hz", hz);
    check(std::fabs(peak - 0.5f) < 0.001f, "sp_osc amp 0.5 peaks at 0.5", peak);

    sp_osc_destroy(&osc);
    sp_ftbl_destroy(&sine);
    sp_destroy(&sp);
}

/// RMS gain of sp_moogladder for a sine at `hz`, cutoff 500 Hz.
double ladderGain(double hz) {
    sp_data *sp = makeSoundpipe();
    sp_moogladder *ladder = nullptr;
    sp_moogladder_create(&ladder);
    sp_moogladder_init(sp, ladder);
    ladder->freq = 500.f;
    ladder->res = 0.1f;

    const size_t n = size_t(sp->sr);
    std::vector<float> in(n), out(n);
    for (size_t i = 0; i < n; ++i) {
        in[i] = float(0.25 * std::sin(2.0 * kPi * hz * double(i) / sp->sr));
        sp_moogladder_compute(sp, ladder, &in[i], &out[i]);
    }
    const double gain = rmsOf(out, n / 2) / rmsOf(in, n / 2);
    sp_moogladder_destroy(&ladder);
    sp_destroy(&sp);
    return gain;
}

void testLadderIsALowPass() {
    const double pass = 20.0 * std::log10(ladderGain(100.0));
    const double stop = 20.0 * std::log10(ladderGain(8000.0));
    check(pass > -4.0, "moogladder passes 100 Hz under a 500 Hz cutoff (dB)", pass);
    check(stop < -40.0, "moogladder stops 8 kHz under a 500 Hz cutoff (dB)", stop);
}

void testRandomIsTheSameEverywhere() {
    // Soundpipe's noise comes from its own generator, not the C library's, so a preset with
    // noise renders the same on every OS. These are the first four values from seed 0,
    // computed independently; a platform where integer promotion differs fails here.
    const uint32_t expected[4] = {12345u, 1406932606u, 654583775u, 1449466924u};
    sp_data *sp = makeSoundpipe();
    sp_srand(sp, 0);
    bool same = true;
    uint32_t last = 0;
    for (uint32_t e : expected) {
        last = sp_rand(sp);
        same = same && (last == e);
    }
    check(same, "sp_rand's sequence from seed 0 is the reference sequence", last);

    sp_noise *noise = nullptr;
    sp_noise_create(&noise);
    sp_noise_init(sp, noise);
    sp_srand(sp, 0);
    float first = 0;
    sp_noise_compute(sp, noise, nullptr, &first);
    // noise.c: ((rand % RANDMAX) / (RANDMAX * 1.0)) * 2 - 1, times amp (1.0 after init)
    float reference = float(12345.0 / 2147483648.0);   // the same steps, in the same types
    reference = (reference * 2) - 1;
    reference *= noise->amp;
    check(first == reference, "sp_noise's first sample from seed 0 is bit-exact", first);
    sp_noise_destroy(&noise);
    sp_destroy(&sp);
}

void testReverbTailDecaysAndStaysFinite() {
    sp_data *sp = makeSoundpipe();
    sp_revsc *reverb = nullptr;
    sp_revsc_create(&reverb);
    sp_revsc_init(sp, reverb);
    reverb->feedback = 0.9f;
    reverb->lpfreq = 8000.f;

    const size_t n = size_t(sp->sr) * 6;
    std::vector<float> left(n);
    bool finite = true;
    for (size_t i = 0; i < n; ++i) {
        float in = (i < 64) ? 0.5f : 0.f, outL = 0, outR = 0;   // a click, then silence
        sp_revsc_compute(sp, reverb, &in, &in, &outL, &outR);
        finite = finite && std::isfinite(outL) && std::isfinite(outR);
        left[i] = outL;
    }
    std::vector<float> early(left.begin(), left.begin() + sp->sr);
    std::vector<float> late(left.end() - sp->sr, left.end());
    check(finite, "sp_revsc output is finite for six seconds", finite ? 1 : 0);
    check(rmsOf(early, 0) > 1e-4, "sp_revsc rings after a click", rmsOf(early, 0));
    check(rmsOf(late, 0) < rmsOf(early, 0) * 0.05, "sp_revsc's tail has decayed by the sixth second", rmsOf(late, 0));

    sp_revsc_destroy(&reverb);
    sp_destroy(&sp);
}

}  // namespace

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);   // see every line before a crash
    testEngineInfo();
    testOscillatorPitchAndLevel();
    testLadderIsALowPass();
    testRandomIsTheSameEverywhere();
    testReverbTailDecaysAndStaysFinite();
    std::printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
