// X2-7 (ADR-078): denormal protection. What is asserted: every render call runs with
// flush-to-zero on and hands the caller's floating-point mode back; nothing subnormal leaves the
// plugin; and a 40-second tail costs no more per block than the sounding part. What is measured
// and printed beside it, on every OS the CI runs: the same performance through the bare engine
// with no protection — what the protection is worth on that machine.
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include "S1PluginProcessor.h"
#include "S1Preset.hpp"

namespace {

constexpr double kSampleRate = 44100.0;
constexpr int kBlock = 512;
constexpr int kBlocksPerSecond = int(kSampleRate / kBlock);

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

/// The product of two small numbers the optimiser cannot see through: 1e-40 where subnormals
/// exist, 0 under flush-to-zero.
float tinyProduct() {
    volatile float a = 1e-20f, b = 1e-20f;
    volatile float product = a * b;
    return product;
}

/// A play head is asked for its position inside processBlock, and nowhere else: what it
/// computes there is computed in the floating-point mode the render runs in.
struct ProbingPlayHead final : juce::AudioPlayHead {
    mutable float seenInsideProcessBlock = -1;
    juce::Optional<PositionInfo> getPosition() const override {
        seenInsideProcessBlock = tinyProduct();
        return {};
    }
};

/// A sound and what is played on it.
struct Sound {
    const char *name;
    std::vector<std::pair<S1Parameter, float>> values;
};

struct Second { double medianMicroseconds; float peak; int subnormalSamples; };

double median(std::vector<double> &values) {
    std::sort(values.begin(), values.end());
    return values[values.size() / 2];
}

/// 2 s for the glides (ADR-013), a chord for `held` seconds, then `tail` seconds of nothing:
/// per second, the median time of a block, the peak, and how many output samples are subnormal.
template <typename RenderBlock, typename Keys>
std::vector<Second> perform(RenderBlock &&renderBlock, Keys &&keys, int held, int tail) {
    std::vector<Second> seconds;
    std::vector<float> left(kBlock), right(kBlock);
    for (int second = 0; second < 2 + held + tail; ++second) {
        std::vector<double> times;
        Second result { 0, 0, 0 };
        for (int block = 0; block < kBlocksPerSecond; ++block) {
            if (block == 0 && second == 2) { keys(true); }
            if (block == 0 && second == 2 + held) { keys(false); }
            const auto before = std::chrono::steady_clock::now();
            renderBlock(left.data(), right.data());
            times.push_back(std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - before).count());
            for (int i = 0; i < kBlock; ++i) {
                for (const float x : { left[size_t(i)], right[size_t(i)] }) {
                    result.peak = std::max(result.peak, std::fabs(x));
                    if (x != 0 && std::fabs(x) < 1.17549435e-38f) { ++result.subnormalSamples; }
                }
            }
        }
        result.medianMicroseconds = median(times);
        seconds.push_back(result);
    }
    return seconds;
}

struct Summary { double sounding, worstTail; int worstAt, subnormalSamples; float lastPeak; };

Summary summarise(const char *who, const Sound &sound, const std::vector<Second> &seconds, int held) {
    std::vector<double> sounding;
    for (int s = 2; s < 2 + held; ++s) { sounding.push_back(seconds[size_t(s)].medianMicroseconds); }
    Summary summary { median(sounding), 0, 0, 0, seconds.back().peak };
    for (size_t s = size_t(2 + held); s < seconds.size(); ++s) {
        summary.subnormalSamples += seconds[s].subnormalSamples;
        if (seconds[s].medianMicroseconds > summary.worstTail) { summary.worstTail = seconds[s].medianMicroseconds; summary.worstAt = int(s) - 2 - held; }
    }
    std::printf("note  %-10s %-22s a sounding block %7.1f us; the dearest second of the tail %7.1f us (x%.2f, %d s in); %d subnormal samples out; last peak %.3g\n",
                who, sound.name, summary.sounding, summary.worstTail, summary.worstTail / summary.sounding, summary.worstAt, summary.subnormalSamples, double(summary.lastPeak));
    std::printf("      per block, the held seconds:");
    for (size_t s = 2; s < size_t(2 + held); ++s) { std::printf(" %.0f", seconds[s].medianMicroseconds); }
    std::printf("; the tail's first eight:");
    for (size_t s = size_t(2 + held); s < size_t(2 + held + 8); ++s) { std::printf(" %.0f", seconds[s].medianMicroseconds); }
    std::printf("; then every tenth:");
    for (size_t s = size_t(2 + held + 10); s < seconds.size(); s += 10) { std::printf(" %.0f", seconds[s].medianMicroseconds); }
    std::printf("\n");
    return summary;
}

const int kChord[] = { 45, 52, 57, 60, 64 };

std::vector<Second> oncePerformedByThePlugin(const Sound &sound, int held, int tail) {
    S1PluginProcessor processor;
    processor.setPlayConfigDetails(0, 2, kSampleRate, kBlock);
    processor.prepareToPlay(kSampleRate, kBlock);
    for (const auto &[parameter, value] : sound.values) {
        S1HostParameter &host = processor.hostParameter(parameter);
        host.setValueNotifyingHost(host.convertTo0to1(value));
    }
    juce::AudioBuffer<float> buffer(2, kBlock);
    juce::MidiBuffer midi;
    const std::vector<Second> seconds = perform(
        [&](float *left, float *right) {
            processor.processBlock(buffer, midi);
            midi.clear();
            std::copy_n(buffer.getReadPointer(0), kBlock, left);
            std::copy_n(buffer.getReadPointer(1), kBlock, right);
        },
        [&](bool down) {
            for (const int note : kChord) { midi.addEvent(down ? juce::MidiMessage::noteOn(1, note, juce::uint8(110)) : juce::MidiMessage::noteOff(1, note), 0); }
        }, held, tail);
    return seconds;
}

/// Three times, and each second's quickest: whatever else the machine was doing can only have
/// added time, and a CI machine is always doing something else.
Summary throughPlugin(const Sound &sound, int held, int tail) {
    std::vector<Second> best = oncePerformedByThePlugin(sound, held, tail);
    for (int again = 0; again < 2; ++again) {
        const std::vector<Second> next = oncePerformedByThePlugin(sound, held, tail);
        for (size_t s = 0; s < best.size(); ++s) {
            best[s].medianMicroseconds = std::min(best[s].medianMicroseconds, next[s].medianMicroseconds);
            best[s].subnormalSamples += next[s].subnormalSamples;
            best[s].peak = std::max(best[s].peak, next[s].peak);
        }
    }
    return summarise("plugin", sound, best, held);
}

/// The same through the engine alone, in whatever mode this thread is in: no protection.
Summary throughBareEngine(const s1::Wavetables &tables, const Sound &sound, int held, int tail, bool protect) {
    auto kernel = std::make_unique<S1DSPKernel>(2, kSampleRate);
    kernel->freeReleasedVoicesEveryFrame = true;
    tables.apply(*kernel);
    float parameters[S1Parameter::S1ParameterCount];
    for (int i = 0; i < S1Parameter::S1ParameterCount; ++i) { parameters[i] = kernel->parameters[size_t(i)]; }
    kernel->setParameters(parameters);
    // The sound the plugin starts with (ADR-080): the shipped Init, from the same linked-in bank.
    juce::SharedResourcePointer<S1SharedPresets>()->library.initialPreset().apply(*kernel);
    kernel->prepareToRender(2, kSampleRate);
    for (const auto &[parameter, value] : sound.values) { kernel->setSynthParameter(parameter, value); }
    const std::vector<Second> seconds = perform(
        [&](float *left, float *right) {
            kernel->setOutput(left, right);
            if (protect) {
                const juce::ScopedNoDenormals noDenormals;
                kernel->processWithEvents(S1FrameCount(kBlock), nullptr, 0);
            } else {
                kernel->processWithEvents(S1FrameCount(kBlock), nullptr, 0);
            }
        },
        [&](bool down) {
            for (const int note : kChord) { if (down) { kernel->startNote(note, 110); } else { kernel->stopNote(note); } }
        }, held, tail);
    return summarise(protect ? "engine+ftz" : "bare engine", sound, seconds, held);
}

} // namespace

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);

    // MARK: the render call is wrapped, and the wrapping comes off
    {
        check(tinyProduct() > 0, "this thread computes subnormals before the plugin is called", double(tinyProduct()));
        S1PluginProcessor processor;
        ProbingPlayHead playHead;
        processor.setPlayConfigDetails(0, 2, kSampleRate, kBlock);
        processor.setPlayHead(&playHead);
        processor.prepareToPlay(kSampleRate, kBlock);
        check(tinyProduct() > 0, "and after prepareToPlay", double(tinyProduct()));
        juce::AudioBuffer<float> buffer(2, kBlock);
        juce::MidiBuffer midi;
        for (int block = 0; block < 4; ++block) {
            playHead.seenInsideProcessBlock = -1;
            processor.processBlock(buffer, midi);
            if (playHead.seenInsideProcessBlock != 0) { break; }
        }
        check(playHead.seenInsideProcessBlock == 0, "inside processBlock the same product is 0: the render runs with flush-to-zero on", double(playHead.seenInsideProcessBlock));
        check(tinyProduct() > 0, "and the caller's mode is back when processBlock returns", double(tinyProduct()));
    }

    // MARK: a long silent tail
    const Sound sounds[] = {
        // Reverb-heavy: a long, fully wet reverb, the delay feeding it.
        { "reverb-heavy", { { S1Parameter::reverbOn, 1 }, { S1Parameter::reverbMix, 1 }, { S1Parameter::reverbFeedback, 0.95f },
                            { S1Parameter::delayOn, 1 }, { S1Parameter::delayMix, 0.5f }, { S1Parameter::delayFeedback, 0.6f },
                            { S1Parameter::phaserMix, 0.5f }, { S1Parameter::releaseDuration, 1.5f } } },
        // And the case that reaches the subnormal range soonest: short effects, so every filter
        // and delay line after the voices is left to decay from a real signal towards nothing.
        { "short effects", { { S1Parameter::reverbOn, 1 }, { S1Parameter::reverbMix, 0.5f }, { S1Parameter::reverbFeedback, 0.3f },
                             { S1Parameter::delayOn, 1 }, { S1Parameter::delayMix, 0.5f }, { S1Parameter::delayFeedback, 0.2f }, { S1Parameter::delayTime, 0.05f },
                             { S1Parameter::phaserMix, 1 }, { S1Parameter::releaseDuration, 0.05f } } },
        { "dry", { { S1Parameter::reverbOn, 0 }, { S1Parameter::delayOn, 0 }, { S1Parameter::releaseDuration, 0.05f } } },
    };
    const juce::SharedResourcePointer<S1SharedWavetables> wavetables;
    constexpr int held = 4, tail = 40;
    for (const Sound &sound : sounds) {
        const Summary plugin = throughPlugin(sound, held, tail);
        const Summary bare = throughBareEngine(wavetables->tables, sound, held, tail, false);
        throughBareEngine(wavetables->tables, sound, held, tail, true);
        check(plugin.subnormalSamples == 0, std::string(sound.name) + ": nothing subnormal leaves the plugin in 40 s of tail, three times over", plugin.subnormalSamples);
        // Measured on the CI's x86 machines (ADR-078): unprotected, the engine's long release
        // costs 1.39x the held chord on Windows and its silence 1.15-1.8x the protected silence;
        // protected, no second of the tail is over 1.01x. A quarter is room for a machine's noise.
        check(plugin.worstTail <= 1.25 * plugin.sounding, std::string(sound.name) + ": no second of the tail costs more than the sounding part", plugin.worstTail / plugin.sounding);
        std::printf("note  %s: unprotected, the engine's dearest tail second is x%.2f of the plugin's\n", sound.name, bare.worstTail / plugin.worstTail);
    }

    std::printf(failures == 0 ? "\nall passed\n" : "\n%d FAILED\n", failures);
    return failures == 0 ? 0 : 1;
}
