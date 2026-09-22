// S1DSPKernel::processWithEvents: a render cycle cut at its events, the way Apple's
// DSPKernel cuts one. The kernel cannot render a frame without its 52 wavetables
// (CLAUDE.md: load them before anything else), so the test fills them with sines; the real
// tables arrive with the loader at X1-6, and the goldens with the harness at X1-7.
#include <cmath>
#include <cstdio>
#include <vector>
#include "S1DSPKernel.hpp"

namespace {
constexpr double kPi = 3.14159265358979323846;

void loadSineWavetables(S1DSPKernel &kernel) {
    const uint32_t size = 4096;
    for (uint32_t table = 0; table < S1_NUM_WAVEFORMS * S1_NUM_BANDLIMITED_FTABLES; ++table) {
        kernel.setupWaveform(table, size);
        for (uint32_t i = 0; i < size; ++i) {
            kernel.setWaveformValue(table, i, float(std::sin(2.0 * kPi * double(i) / size)));
        }
    }
    // Ascending band edges, as bandlimitedWaveformFrequencies.json holds them.
    for (uint32_t band = 0; band < S1_NUM_BANDLIMITED_FTABLES; ++band) {
        kernel.setBandlimitFrequency(band, 20.f * std::pow(2.f, float(band)));
    }
}
}

namespace {
int failures = 0;
void check(bool ok, const char *what, double measured) {
    std::printf("%s  %s (measured %.4f)\n", ok ? "ok  " : "FAIL", what, measured);
    if (!ok) { ++failures; }
}

S1Event parameterEvent(S1FrameCount offset, S1Parameter p, float value) {
    S1Event e{};
    e.kind = S1EventKind_Parameter;
    e.sampleOffset = offset;
    e.address = S1ParameterAddress(p);
    e.value = value;
    e.rampFrames = 0;
    return e;
}
}

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);   // see every line before a crash
    S1DSPKernel kernel(2, 44100.0);
    loadSineWavetables(kernel);
    kernel.init(2, 44100.0);
    kernel.updateWavetableIncrementValuesForCurrentSampleRate();

    const S1FrameCount frames = 256;
    std::vector<float> left(frames, 1.f), right(frames, 1.f);   // 1.0 so we can see what was written
    kernel.setOutput(left.data(), right.data());

    // No events: every frame is rendered (silence, no notes), nothing is left untouched.
    kernel.processWithEvents(frames, nullptr, 0);
    bool allWritten = true, finite = true;
    for (S1FrameCount i = 0; i < frames; ++i) {
        allWritten = allWritten && left[i] != 1.f && right[i] != 1.f;
        finite = finite && std::isfinite(left[i]) && std::isfinite(right[i]);
    }
    check(allWritten, "with no events every frame of the cycle is rendered", frames);
    check(finite, "the output is finite", 1);

    // One parameter event mid-cycle: applied, and the whole cycle still rendered.
    const float before = kernel.getSynthParameter(cutoff);
    std::fill(left.begin(), left.end(), 1.f);
    S1Event one[] = {parameterEvent(100, cutoff, 1234.f)};
    kernel.processWithEvents(frames, one, 1);
    check(std::fabs(kernel.getSynthParameter(cutoff) - 1234.f) < 0.01f, "a parameter event at offset 100 reaches the kernel", kernel.getSynthParameter(cutoff));
    check(before != 1234.f, "(the value was different before)", before);
    allWritten = true;
    for (S1FrameCount i = 0; i < frames; ++i) { allWritten = allWritten && left[i] != 1.f; }
    check(allWritten, "the frames before and after the event are both rendered", frames);

    // Two events at one offset, and one past the end of the buffer: all applied, in order.
    S1Event three[] = {parameterEvent(0, resonance, 0.5f), parameterEvent(0, resonance, 0.7f), parameterEvent(999, glide, 0.1f)};
    kernel.processWithEvents(frames, three, 3);
    check(std::fabs(kernel.getSynthParameter(resonance) - 0.7f) < 0.001f, "simultaneous events apply in list order (the later wins)", kernel.getSynthParameter(resonance));
    check(std::fabs(kernel.getSynthParameter(glide) - 0.1f) < 0.001f, "an event past the end of the cycle is applied after the last frame", kernel.getSynthParameter(glide));

    // A note-on at offset 128 of 256: the frames before it are silent and the frames after are
    // not — the event was applied at its sample, not at the start of the cycle.
    std::fill(left.begin(), left.end(), 0.f);
    S1Event note{};
    note.kind = S1EventKind_MIDI;
    note.sampleOffset = 128;
    note.midi = {3, {0x90, 69, 100}};
    kernel.processWithEvents(frames, &note, 1);
    double energyBefore = 0, energyAfter = 0;
    for (S1FrameCount i = 0; i < 128; ++i) { energyBefore += double(left[i]) * left[i]; }
    for (S1FrameCount i = 128; i < frames; ++i) { energyAfter += double(left[i]) * left[i]; }
    check(energyBefore == 0.0, "before a note-on at offset 128 the cycle is silent", energyBefore);
    check(energyAfter > 0.0, "after it the note sounds", energyAfter);
    S1Event off{};
    off.kind = S1EventKind_MIDI;
    off.sampleOffset = 0;
    off.midi = {3, {0x80, 69, 0}};
    kernel.processWithEvents(frames, &off, 1);

    // An out-of-range address is ignored, as startRamp's bounds check promises (P4-3).
    S1Event bad[] = {parameterEvent(10, (S1Parameter)S1ParameterCount, 5.f)};
    kernel.processWithEvents(frames, bad, 1);
    check(std::fabs(kernel.getSynthParameter(cutoff) - 1234.f) < 0.01f, "an address past S1ParameterCount changes nothing", kernel.getSynthParameter(cutoff));

    // X2-2 (ADR-073): a value set and then carried across prepareToRender with no frame rendered in
    // between — a host restoring its state, then allocating. `cutoff` is smoothed (its value
    // glides to what was set as frames render), `filterType` is not; both must survive.
    kernel.setSynthParameter(cutoff, 777.f);
    kernel.setSynthParameter(filterType, 2.f);
    kernel.prepareToRender(2, 48000.0);
    check(kernel.getSynthParameter(cutoff) == 777.f, "a smoothed parameter set just before prepareToRender survives it", kernel.getSynthParameter(cutoff));
    check(kernel.getSynthParameter(filterType) == 2.f, "and so does one that is not smoothed", kernel.getSynthParameter(filterType));
    // (What it is SET to, not what the first frame hears: after any init every smoothed parameter
    // glides up from 0 — upstream passes the value where sp_port_init takes a half-time, and
    // sp_port starts at 0. That sweep is ADR-013's, it is in the goldens, and it stays.)

    std::printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
