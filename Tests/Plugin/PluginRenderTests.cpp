// X2-1 (ADR-072): the JUCE processor adds nothing to the engine and loses nothing.
//
// The same notes are rendered twice: through S1PluginProcessor::processBlock, fed MIDI the way a
// host feeds it, with the oscillator tables linked into the binary; and through a bare
// S1DSPKernel hosted as GoldenHarness hosts one, with the tables read from the repository. Same
// compiler, same machine, same arithmetic — so on every OS the two must be equal bit for bit.
// Anything else is the wrapper's doing: a wrong hosting order, a lost or late event, a table that
// did not survive being linked in.
//
//   argv[1]  Sources/SynthOneCore/DSP/BandlimitedWavetables
#include <chrono>
#include <cmath>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include "S1PluginProcessor.h"
#include "S1Preset.hpp"

namespace {

// GoldenHarness's recipe (Tests/Engine/GoldenHarness.cpp).
// At another sample rate the recipe keeps its block COUNTS and stretches the block, so the notes
// fall at the same times in seconds (setRecipe).
double kSampleRate = 44100.0;
int kFramesPerBlock = 512;
void setRecipe(double sampleRate) {
    kSampleRate = sampleRate;
    kFramesPerBlock = int(std::lround(512.0 * sampleRate / 44100.0));
}
constexpr int kSettleBlocks = 65;         // 0.75 s, in whole blocks
constexpr int kCaptureBlocks = 130;       // 1.5 s
constexpr int kSecondNoteBlock = 35;      // 0.4 s
constexpr int kReleaseBlock = 87;         // 1.0 s
constexpr int kFirstNote = 57, kSecondNote = 64, kVelocity = 100;

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

struct Render { std::vector<float> left, right; };

float peak(const Render &r) {
    float result = 0;
    for (float s : r.left) { result = std::fmax(result, std::fabs(s)); }
    for (float s : r.right) { result = std::fmax(result, std::fabs(s)); }
    return result;
}

size_t differingSamples(const Render &a, const Render &b) {
    if (a.left.size() != b.left.size()) { return a.left.size() + b.left.size(); }
    size_t count = 0;
    // Where a difference begins and how large it gets says most of what it is.
    size_t first = 0, last = 0; double worst = 0;
    for (size_t i = 0; i < a.left.size(); ++i) {
        const double d = std::fmax(std::fabs(double(a.left[i]) - double(b.left[i])), std::fabs(double(a.right[i]) - double(b.right[i])));
        if (d > 0 || std::isnan(d)) { if (worst == 0 && first == 0) { first = i; } last = i; worst = std::fmax(worst, d); }
    }
    if (last != 0) { std::printf("      differs from sample %zu to %zu of %zu, by at most %.3g\n", first, last, a.left.size(), worst); }
    for (size_t i = 0; i < a.left.size(); ++i) {
        // Bit patterns are not compared, values are: -0 and +0 are the same sound. NaN fails.
        if (!juce::exactlyEqual(a.left[i], b.left[i])) { ++count; }
        if (!juce::exactlyEqual(a.right[i], b.right[i])) { ++count; }
    }
    return count;
}

/// Notes at sample `offset` of their block. 0 is what GoldenHarness does between blocks.
Render renderThroughProcessor(int blockSize, int offset) {
    S1PluginProcessor processor;
    processor.setPlayConfigDetails(0, 2, kSampleRate, blockSize);
    processor.prepareToPlay(kSampleRate, blockSize);
    juce::AudioBuffer<float> buffer(2, blockSize);
    Render out;
    const int total = (kSettleBlocks + kCaptureBlocks) * kFramesPerBlock;
    const int captureFrom = kSettleBlocks * kFramesPerBlock;
    auto at = [&](int block) { return captureFrom + block * kFramesPerBlock + offset; };
    for (int frame = 0; frame < total; frame += blockSize) {
        const int frames = std::min(blockSize, total - frame);
        juce::AudioBuffer<float> slice(buffer.getArrayOfWritePointers(), 2, frames);
        juce::MidiBuffer midi;
        auto add = [&](const juce::MidiMessage &message, int when) {
            if (when >= frame && when < frame + frames) { midi.addEvent(message, when - frame); }
        };
        add(juce::MidiMessage::noteOn(1, kFirstNote, juce::uint8(kVelocity)), at(0));
        add(juce::MidiMessage::noteOn(1, kSecondNote, juce::uint8(kVelocity)), at(kSecondNoteBlock));
        add(juce::MidiMessage::noteOff(1, kFirstNote), at(kReleaseBlock));
        // The second key is released as many keyboards do it: a note-on with velocity 0.
        add(juce::MidiMessage(0x90, kSecondNote, 0), at(kReleaseBlock));
        processor.processBlock(slice, midi);
        for (int i = 0; i < frames; ++i) {
            if (frame + i >= captureFrom) {
                out.left.push_back(slice.getSample(0, i));
                out.right.push_back(slice.getSample(1, i));
            }
        }
    }
    processor.releaseResources();
    return out;
}

/// The bare engine: GoldenHarness's makeEngine, rendered in the same blocks as the host's and cut
/// where the notes are — which is all processWithEvents does with an event. So the calls into
/// S1DSPKernel::process are the same calls, and the samples must be the same samples.
Render renderThroughEngine(const s1::Wavetables &tables, int blockSize, int offset) {
    // As every host of the engine renders (ADR-078): subnormals flushed to zero. Without it this
    // reference differs from the plugin by design — the shipped Init at 96 kHz leaves 9,328
    // samples of its silence subnormal where the plugin's are 0 (found when X2-9 changed Init).
    const juce::ScopedNoDenormals noDenormals;
    auto kernel = std::make_unique<S1DSPKernel>(2, kSampleRate);
    kernel->freeReleasedVoicesEveryFrame = true;   // as the plugin sets it (ADR-074)
    tables.apply(*kernel);
    float parameters[S1Parameter::S1ParameterCount];
    for (int i = 0; i < S1Parameter::S1ParameterCount; ++i) { parameters[i] = kernel->parameters[size_t(i)]; }
    kernel->setParameters(parameters);
    // The plugin's order since X2-2 (ADR-073): Init is what the parameters start as, so it is in
    // the kernel before the host prepares it, and prepareToRender carries it across.
    // The sound the plugin starts with (ADR-080): the shipped Init, from the same linked-in bank.
    juce::SharedResourcePointer<S1SharedPresets>()->library.initialPreset().apply(*kernel);
    kernel->prepareToRender(2, kSampleRate);

    Render out;
    const int total = (kSettleBlocks + kCaptureBlocks) * kFramesPerBlock;
    const int captureFrom = kSettleBlocks * kFramesPerBlock;
    const int first = captureFrom + offset;
    const int second = captureFrom + kSecondNoteBlock * kFramesPerBlock + offset;
    const int release = captureFrom + kReleaseBlock * kFramesPerBlock + offset;
    std::vector<float> left(static_cast<size_t>(blockSize)), right(static_cast<size_t>(blockSize));
    for (int frame = 0; frame < total; frame += blockSize) {
        const int frames = std::min(blockSize, total - frame);
        int from = 0;
        auto renderUpTo = [&](int to) {
            if (to <= from) { return; }
            kernel->setOutput(left.data() + from, right.data() + from);
            kernel->processWithEvents(S1FrameCount(to - from), nullptr, 0);
            from = to;
        };
        auto inBlock = [&](int when) { return when >= frame && when < frame + frames; };
        if (inBlock(first)) { renderUpTo(first - frame); kernel->startNote(kFirstNote, kVelocity); }
        if (inBlock(second)) { renderUpTo(second - frame); kernel->startNote(kSecondNote, kVelocity); }
        if (inBlock(release)) { renderUpTo(release - frame); kernel->stopNote(kFirstNote); kernel->stopNote(kSecondNote); }
        renderUpTo(frames);
        for (int i = 0; i < frames; ++i) {
            if (frame + i >= captureFrom) { out.left.push_back(left[size_t(i)]); out.right.push_back(right[size_t(i)]); }
        }
    }
    return out;
}

} // namespace

int main(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc != 2) { std::printf("usage: PluginRenderTests <wavetable dir>\n"); return 2; }

    s1::Wavetables fromDisk;
    try {
        fromDisk = s1::Wavetables::loadFromDirectory(argv[1]);
    } catch (const std::exception &error) {
        std::printf("FAIL  wavetables: %s\n", error.what());
        return 1;
    }

    {
        const auto before = std::chrono::steady_clock::now();
        S1SharedWavetables linkedIn;
        const double milliseconds = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - before).count();
        // What the first instance in a process pays for JSON rather than a float blob (ADR-072).
        check(milliseconds < 2000.0, "the linked-in tables decode in reasonable time (ms)", milliseconds);
        size_t different = 0;
        for (size_t t = 0; t < fromDisk.waveforms.size() && t < linkedIn.tables.waveforms.size(); ++t) {
            if (fromDisk.waveforms[t] != linkedIn.tables.waveforms[t]) { ++different; }
        }
        check(linkedIn.tables.waveforms.size() == 52 && different == 0
                  && linkedIn.tables.bandlimitFrequencies == fromDisk.bandlimitFrequencies,
              "the 52 tables linked into the plugin equal the repository's", double(different));
    }

    const Render engine = renderThroughEngine(fromDisk, kFramesPerBlock, 0);
    check(peak(engine) > 0.01f, "Init through the bare engine is not silent", peak(engine));

    // Block sizes: the recipe's own, a host's small and large ones, and sizes that divide nothing.
    // Notes at the start of their block, then 129 samples into it (sample-accurate MIDI).
    for (int offset : {0, 129}) {
        for (int blockSize : {512, 64, 1024, 441, 37, 1}) {
            const Render reference = renderThroughEngine(fromDisk, blockSize, offset);
            const Render plugin = renderThroughProcessor(blockSize, offset);
            const std::string how = "blocks of " + std::to_string(blockSize) + ", notes at +" + std::to_string(offset);
            check(peak(plugin) > 0.01f, "Init through processBlock makes sound, " + how, peak(plugin));
            check(differingSamples(plugin, reference) == 0,
                  "processBlock equals the bare engine sample for sample, " + how,
                  double(differingSamples(plugin, reference)));
            if (offset == 0) {
                // ADR-074: with voices freed every frame the engine renders the same samples
                // however the host cuts its buffers. (Upstream's path did not: X2-1 measured up
                // to 1,024 samples of Init differing here, and whole arpeggios in the goldens.)
                check(differingSamples(reference, engine) == 0,
                      "the engine in " + how + " renders the same samples as in blocks of 512",
                      double(differingSamples(reference, engine)));
            }
        }
    }
    const Render engineOffset = renderThroughEngine(fromDisk, kFramesPerBlock, 129);
    check(differingSamples(engineOffset, engine) > 1000, "a note 129 samples later is a different render", double(differingSamples(engineOffset, engine)));

    // MARK: X2-3 — other sample rates. There are no goldens at 48 or 96 kHz, so: the wrapper is
    // still exact, and the engine plays the same performance — same pitch, same level.
    {
        auto pitchAndLevel = [](const Render &r, double &hertz, double &rms) {
            // The first note alone, 0.1 s to 0.35 s into the capture: autocorrelation's best lag near A3.
            const size_t from = size_t(0.10 * kSampleRate), to = size_t(0.35 * kSampleRate);
            double best = -1e30; size_t bestLag = 0;
            std::vector<double> score(size_t(kSampleRate / 90.0) + 2, 0.0);
            for (size_t lag = size_t(kSampleRate / 480.0); lag < score.size(); ++lag) {
                double sum = 0;
                for (size_t i = from; i + lag < to; ++i) { sum += double(r.left[i]) * double(r.left[i + lag]); }
                score[lag] = sum / double(to - from - lag);
                if (score[lag] > best) { best = score[lag]; bestLag = lag; }
            }
            const double a = score[bestLag - 1], b = score[bestLag], c = score[bestLag + 1];
            const double shift = (a - c) / (2 * (a - 2 * b + c));   // the parabola through the three
            hertz = kSampleRate / (double(bestLag) + shift);
            double squares = 0;
            for (size_t i = from; i < to; ++i) { squares += double(r.left[i]) * double(r.left[i]); }
            rms = std::sqrt(squares / double(to - from));
        };
        double referenceHertz = 0, referenceRMS = 0;
        pitchAndLevel(engine, referenceHertz, referenceRMS);
        check(std::fabs(referenceHertz - 220.0) < 2.2, "at 44.1 kHz Init's A3 is measured at 220 Hz", referenceHertz);
        for (double sampleRate : {48000.0, 96000.0}) {
            setRecipe(sampleRate);
            const std::string rate = std::to_string(int(sampleRate)) + " Hz";
            const Render reference = renderThroughEngine(fromDisk, kFramesPerBlock, 0);
            for (int blockSize : {512, 480, 37}) {
                const Render plugin = renderThroughProcessor(blockSize, 0);
                check(differingSamples(plugin, reference) == 0,
                      "at " + rate + " processBlock equals the bare engine sample for sample, blocks of " + std::to_string(blockSize),
                      double(differingSamples(plugin, reference)));
            }
            double hertz = 0, rms = 0;
            pitchAndLevel(reference, hertz, rms);
            check(std::fabs(hertz / referenceHertz - 1.0) < 0.002, "at " + rate + " the note is at the pitch it has at 44.1 kHz", hertz);
            check(std::fabs(20 * std::log10(rms / referenceRMS)) < 0.5, "at " + rate + " it is as loud, within half a dB", 20 * std::log10(rms / referenceRMS));
        }
        setRecipe(44100.0);
    }

    // MARK: X2-3 — a note lands on its sample (the plan's onset check)
    {
        S1PluginProcessor processor;
        processor.setPlayConfigDetails(0, 2, 44100.0, 512);
        processor.prepareToPlay(44100.0, 512);
        juce::AudioBuffer<float> buffer(2, 512);
        juce::MidiBuffer none, note;
        for (int block = 0; block < 100; ++block) { processor.processBlock(buffer, none); }
        note.addEvent(juce::MidiMessage::noteOn(1, kFirstNote, juce::uint8(kVelocity)), 300);
        processor.processBlock(buffer, note);
        int firstSound = -1;
        for (int i = 0; i < 512 && firstSound < 0; ++i) {
            if (!juce::exactlyEqual(buffer.getSample(0, i), 0.f) || !juce::exactlyEqual(buffer.getSample(1, i), 0.f)) { firstSound = i; }
        }
        // The envelope's first sample may itself be 0: sample 300 or the one after.
        check(firstSound == 300 || firstSound == 301, "a note-on at sample 300 of a 512-frame block: silence before it, sound from it", firstSound);
    }

    // MARK: X2-3 — a parameter change is a ramp, not a step, for the smoothed parameters
    {
        S1PluginProcessor processor;
        processor.setPlayConfigDetails(0, 2, 44100.0, 512);
        processor.prepareToPlay(44100.0, 512);
        juce::AudioBuffer<float> buffer(2, 512), one(2, 1);
        juce::MidiBuffer none;
        S1HostParameter &cutoffParameter = processor.hostParameter(S1Parameter::cutoff);
        cutoffParameter.setValueNotifyingHost(cutoffParameter.convertTo0to1(500.f));
        for (int block = 0; block < 400; ++block) { processor.processBlock(buffer, none); }   // 4.6 s: every glide has arrived
        const float from = processor.engineValueInUse(S1Parameter::cutoff);
        // (Not exactly: sp_port's last step falls under a float's resolution at 500 and the glide
        // stops 0.135 Hz short. Upstream's smoothing, the goldens', left alone.)
        check(std::fabs(from - 500.f) < 0.5f, "the cutoff the DSP uses has settled at 500 Hz", from);

        cutoffParameter.setValueNotifyingHost(cutoffParameter.convertTo0to1(5000.f));
        const float target = cutoffParameter.plainValue();
        const double halfTime = processor.engineValue(S1Parameter::portamentoHalfTime);
        const double largestAllowed = double(target - from) * (1.0 - std::pow(0.5, 1.0 / (44100.0 * halfTime)));
        double largestStep = 0, previous = from;
        bool rising = true;
        for (int frame = 0; frame < 512; ++frame) {
            processor.processBlock(one, none);
            const double now = processor.engineValueInUse(S1Parameter::cutoff);
            largestStep = std::max(largestStep, now - previous);
            rising = rising && now > previous;
            previous = now;
        }
        check(largestStep <= largestAllowed * 1.001 && largestStep > 0,
              "a 500 -> 5000 Hz cutoff change moves the filter by at most the smoothing's step per sample (allowed "
                  + std::to_string(largestAllowed) + " Hz)", largestStep);
        check(rising && previous < target, "rising every sample, and still on its way after 512", previous);

        // The unsmoothed ones step, at the block's first sample: a rate has no zipper to hide.
        S1HostParameter &sync = processor.hostParameter(S1Parameter::tempoSyncToArpRate);
        sync.setValueNotifyingHost(0.f);
        S1HostParameter &rate = processor.hostParameter(S1Parameter::lfo1Rate);
        rate.setValueNotifyingHost(rate.convertTo0to1(7.f));
        processor.processBlock(one, none);
        check(juce::exactlyEqual(processor.engineValueInUse(S1Parameter::lfo1Rate), rate.plainValue()), "an unsmoothed parameter (an LFO rate) is in use from the block's first sample", processor.engineValueInUse(S1Parameter::lfo1Rate));
    }

    // A second instance while the first is alive, then both gone: the shared tables outlive neither wrongly.
    {
        S1PluginProcessor first, second;
        first.prepareToPlay(48000.0, 256);
        second.prepareToPlay(96000.0, 256);
    }
    const Render again = renderThroughProcessor(512, 0);
    check(differingSamples(again, engine) == 0, "a new instance after others were destroyed renders the same", double(differingSamples(again, engine)));

    std::printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
