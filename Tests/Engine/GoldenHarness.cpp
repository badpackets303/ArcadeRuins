// X1-7 (ADR-071): the twenty goldens through the engine alone.
//
// GoldenRenderTests.swift renders twenty factory presets through AKSynthOne, S1AudioUnit and
// AVAudioEngine and compares them with Tests/Goldens/*.wav. This renders the same twenty with
// nothing but Sources/S1Engine — kernel, s1::Wavetables, s1::Preset — and compares them with the
// same files, by the same recipe and the same tolerances. No Swift, no Objective-C, no Apple
// framework: this is the engine JUCE will host, proved against the sound of the shipped product.
//
//   argv[1]  Tests/Goldens
//   argv[2]  Sources/SynthOneCore/Presets/Data            the factory banks
//   argv[3]  Sources/SynthOneCore/DSP/BandlimitedWavetables
//   --list-differences      print the first samples that leave the golden by a tenth of the limit
//   --write-renders <dir>   save what was rendered, as WAVs named like the goldens
//   --mutation cutoff|late-note|detune --expect-rejected N
//                           self-check: render with a deliberate small fault; succeed only if
//                           the tolerance criterion rejects at least N of the twenty
//   --block-size N    render in N-frame blocks instead of the goldens' 512, with every note on the
//                     sample the goldens have it on (X2-3, ADR-074): what a host with another
//                     buffer size makes of the same performance. Never with --require-exact.
//   --free-voices-every-frame   the kernel option the JUCE plugin sets (ADR-074)
//   --check-block-independence  ADR-074's proof, instead of the comparison with the goldens:
//                     with that option every preset renders the SAME samples in blocks of 512, 64,
//                     480, 1024 and 37 — and they are the samples upstream's own code path renders
//                     in one-frame blocks. Exact on every OS: one binary, one arithmetic.
//   --require-exact   fail unless every golden is reproduced bit for bit (the toolchain that
//                     wrote them; elsewhere the tolerances are the criterion)
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#if defined(__APPLE__)
#include <fenv.h>   // FE_DFL_DISABLE_DENORMS_ENV, for --flush-to-zero
#endif
#include <fstream>
#include <map>
#include <memory>
#include <string>
#include <vector>
#include "S1DSPKernel.hpp"
#include "S1Preset.hpp"
#include "S1Wavetables.hpp"
#include "WavFile.hpp"

namespace {

// The fixed rendering recipe: every number is part of the goldens (GoldenRenderTests.swift).
constexpr double kSampleRate = 44100.0;
constexpr S1FrameCount kFramesPerBlock = 512;
constexpr double kSettle = 0.75;          // preset applied, then left to settle (ADR-013)
constexpr double kSecondNoteAt = 0.4;
constexpr double kReleaseAt = 1.0;
constexpr double kCaptureSeconds = 1.5;
constexpr int kFirstNote = 57;            // A3
constexpr int kSecondNote = 64;           // E4
constexpr int kVelocity = 100;
// Two criteria (ADR-071).
//
// 1. On the arithmetic that wrote the goldens — arm64 with fused multiply-add, which is every
//    Apple Silicon build — the engine must reproduce them bit for bit (--require-exact).
//
// 2. Anywhere else the same source rounds differently in the last bit (no FMA in x86-64's
//    baseline; another libm behind log2/exp2/sin), and the synth does two things with that:
//    its feedback paths (filters, delay, reverb) carry it forward as a difference some 80 dB
//    under the signal, and its bit-crusher's sample-and-hold — a float counter compared with
//    `<=` — now and then takes its new sample one sample earlier or later, which is ONE sample
//    off by as much as neighbouring samples differ (0.0255 measured) and nothing either side.
//    So the largest single difference is the wrong yardstick here, and the criterion is:
//      - the difference's RMS is at least 50 dB under the golden's (relative RMS <= 3.16e-3;
//        the worst measured on Linux and Windows is 6.9e-4), and
//      - no more than 1 sample in 200 differs by more than 0.001 (worst measured: 1 in 1,300).
//    A real fault is nowhere near either: see the mutation checks in ADR-071.
constexpr float kMaximumRelativeRMSDifference = 3.16e-3f;
constexpr float kOutlierThreshold = 1e-3f;
constexpr double kMaximumOutlierFraction = 1.0 / 200.0;

struct Golden { const char *bank; const char *preset; const char *filename; };

// Names as the bank JSON spells them (UTF-8 escaped, so no compiler has to guess the source
// encoding); filenames as GoldenRenderTests' slug wrote them.
const Golden kGoldens[] = {
    {"BankA", "Tentacles Arp", "BankA--Tentacles-Arp.wav"},
    {"Bonus", "Let\xE2\x80\x99s Play", "Bonus--Let-s-Play.wav"},
    {"Brice Beasley", "BB Stunned By Splendor Drone", "Brice-Beasley--BB-Stunned-By-Splendor-Drone.wav"},
    {"DJ Puzzle", "Dublets", "DJ-Puzzle--Dublets.wav"},
    {"Electronisounds", "ARP - Tekno Con Carne", "Electronisounds--ARP---Tekno-Con-Carne.wav"},
    {"Francis Preve", "Power 5th", "Francis-Preve--Power-5th.wav"},
    {"JEC", "JEC Forth of Bass 2", "JEC--JEC-Forth-of-Bass-2.wav"},
    {"Red Sky Lullaby", "Hold It Feeder Drone", "Red-Sky-Lullaby--Hold-It-Feeder-Drone.wav"},
    {"Red Sky Lullaby", "Non Arpeggiating Arp", "Red-Sky-Lullaby--Non-Arpeggiating-Arp.wav"},
    {"Red Sky Lullaby", "Pulsating Ultraworlds", "Red-Sky-Lullaby--Pulsating-Ultraworlds.wav"},
    {"Red Sky Lullaby", "SubSonic Pad", "Red-Sky-Lullaby--SubSonic-Pad.wav"},
    {"Red Sky Lullaby", "Tentacles Arp", "Red-Sky-Lullaby--Tentacles-Arp.wav"},
    {"Sound of Izrael", "Mr Swing", "Sound-of-Izrael--Mr-Swing.wav"},
    {"Sound of Izrael 2", "Soi ARP 12", "Sound-of-Izrael-2--Soi-ARP-12.wav"},
    {"Sound of Izrael 2", "Soi ARP 29", "Sound-of-Izrael-2--Soi-ARP-29.wav"},
    {"Sound of Izrael 2", "Soi Ok Balagan", "Sound-of-Izrael-2--Soi-Ok-Balagan.wav"},
    {"Spidericemidas", "\xF0\x9F\x95\xB7- Missing Time", "Spidericemidas-----Missing-Time.wav"},
    {"Starter Bank", "BB BASICS - Mono Bass START", "Starter-Bank--BB-BASICS---Mono-Bass-START.wav"},
    {"Starter Bank", "Init", "Starter-Bank--Init.wav"},
    {"User", "Init", "User--Init.wav"},
};

int failures = 0;

/// --block-size. 0 = the goldens' own recipe, which is what render() below does.
S1FrameCount blockSize = 0;
/// --free-voices-every-frame
bool freeVoicesEveryFrame = false;

/// --mutation: a deliberate fault, to prove the tolerance criterion rejects one (it must not only
/// accept the right answer). Small on purpose: these are the faults a port could really have.
enum class Mutation { none, cutoff, lateNote, detune };
Mutation mutation = Mutation::none;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

/// A new engine, prepared the way the Mac product prepares one. Each step is a step
/// AKSynthOne.init / S1AudioUnit take before GoldenRenderTests touches the synth.
std::unique_ptr<S1DSPKernel> makeEngine(const s1::Wavetables &tables) {
    auto kernel = std::make_unique<S1DSPKernel>(2, kSampleRate);   // S1AudioUnit.init
    tables.apply(*kernel);                                          // AKSynthOne.init: the tables…
    float parameters[S1Parameter::S1ParameterCount];                // …then `internalAU.parameters = parameters`,
    for (int i = 0; i < S1Parameter::S1ParameterCount; ++i) {       // every value read and written back
        parameters[i] = kernel->parameters[size_t(i)];
    }
    kernel->setParameters(parameters);
    kernel->prepareToRender(2, kSampleRate);                        // allocateRenderResources
    return kernel;
}

/// Renders `seconds` in whole blocks, as OfflineSynth.render does, calling `schedule` with each
/// block's start time first. Notes go in between blocks through startNote/stopNote — the calls
/// AKSynthOne.play/stop reach.
template <typename Schedule>
StereoRender render(S1DSPKernel &kernel, double seconds, Schedule schedule) {
    StereoRender out;
    out.sampleRate = kSampleRate;
    const size_t total = size_t(seconds * kSampleRate);
    std::vector<float> left(kFramesPerBlock), right(kFramesPerBlock);
    size_t frames = 0;
    while (frames < total) {
        schedule(double(frames) / kSampleRate);
        kernel.setOutput(left.data(), right.data());
        kernel.processWithEvents(kFramesPerBlock, nullptr, 0);
        out.left.insert(out.left.end(), left.begin(), left.end());
        out.right.insert(out.right.end(), right.begin(), right.end());
        frames += kFramesPerBlock;
    }
    return out;
}

/// The goldens' performance in blocks of another size. In the goldens a note starts at the first
/// 512-frame block boundary at or after its time, so those are the samples the notes belong on:
/// the block is cut there and the note started between the two process() calls, which is what
/// processWithEvents does with a MIDI event.
StereoRender renderInBlocks(S1DSPKernel &kernel, S1FrameCount frames, double secondNoteAt) {
    auto boundary = [](double seconds) {   // the first golden block starting at or after `seconds` of capture
        const size_t block = size_t(std::ceil(seconds * kSampleRate / double(kFramesPerBlock)));
        return block * kFramesPerBlock;
    };
    const size_t settle = boundary(kSettle), total = settle + boundary(kCaptureSeconds);
    struct Cue { size_t at; int action; };
    const Cue cues[] = {{settle, 0}, {settle + boundary(secondNoteAt), 1}, {settle + boundary(kReleaseAt), 2}};
    StereoRender out;
    out.sampleRate = kSampleRate;
    std::vector<float> left(frames), right(frames);
    size_t next = 0;
    for (size_t frame = 0; frame < total; frame += frames) {
        const size_t count = std::min<size_t>(frames, total - frame);
        size_t from = 0;
        auto renderUpTo = [&](size_t to) {
            if (to <= from) { return; }
            kernel.setOutput(left.data() + from, right.data() + from);
            kernel.processWithEvents(S1FrameCount(to - from), nullptr, 0);
            from = to;
        };
        while (next < 3 && cues[next].at < frame + count) {
            renderUpTo(cues[next].at - frame);
            if (cues[next].action == 0) { kernel.startNote(kFirstNote, kVelocity); }
            else if (cues[next].action == 1) { kernel.startNote(kSecondNote, kVelocity); }
            else { kernel.stopNote(kFirstNote); kernel.stopNote(kSecondNote); }
            ++next;
        }
        renderUpTo(count);
        for (size_t i = 0; i < count; ++i) {
            if (frame + i >= settle) { out.left.push_back(left[i]); out.right.push_back(right[i]); }
        }
    }
    return out;
}

StereoRender renderGolden(const s1::Wavetables &tables, const s1::Preset &preset) {
    std::unique_ptr<S1DSPKernel> kernel = makeEngine(tables);
    kernel->freeReleasedVoicesEveryFrame = freeVoicesEveryFrame;
    preset.apply(*kernel);
    if (mutation == Mutation::cutoff) {   // the filter 1% sharp
        kernel->setSynthParameter(cutoff, kernel->getSynthParameter(cutoff) * 1.01f);
    } else if (mutation == Mutation::detune) {   // the tuning 1 cent sharp
        for (int i = 0; i < S1_NUM_MIDI_NOTES; ++i) {
            kernel->setTuningTable(float(kernel->getTuningTableFrequency(i) * 1.00057779), i);
        }
    }
    const double secondNoteAt = mutation == Mutation::lateNote ? kSecondNoteAt + 512.0 / kSampleRate : kSecondNoteAt;
    if (blockSize != 0) { return renderInBlocks(*kernel, blockSize, secondNoteAt); }
    render(*kernel, kSettle, [](double) {});
    bool playedFirst = false, playedSecond = false, released = false;
    return render(*kernel, kCaptureSeconds, [&](double time) {
        if (!playedFirst) {
            playedFirst = true;
            kernel->startNote(kFirstNote, kVelocity);
        }
        if (!playedSecond && time >= secondNoteAt) {
            playedSecond = true;
            kernel->startNote(kSecondNote, kVelocity);
        }
        if (!released && time >= kReleaseAt) {
            released = true;
            kernel->stopNote(kFirstNote);
            kernel->stopNote(kSecondNote);
        }
    });
}

struct Difference {
    float maximum = 0;
    float relativeRMS = 0;
    size_t atFrame = 0;
    char channel = 'L';
    size_t outliers = 0;     // samples further than kOutlierThreshold from the golden
    size_t samples = 0;
};

Difference compare(const StereoRender &rendered, const StereoRender &golden) {
    Difference result;
    double sumSquares = 0, goldenSquares = 0;
    size_t samples = 0;
    const std::vector<float> *pairs[2][2] = {{&rendered.left, &golden.left}, {&rendered.right, &golden.right}};
    for (int c = 0; c < 2; ++c) {
        const std::vector<float> &a = *pairs[c][0], &b = *pairs[c][1];
        for (size_t i = 0; i < a.size() && i < b.size(); ++i) {
            const float difference = std::fabs(a[i] - b[i]);
            if (difference > result.maximum || std::isnan(difference)) {
                result.maximum = std::isnan(difference) ? INFINITY : difference;
                result.atFrame = i;
                result.channel = c == 0 ? 'L' : 'R';
            }
            if (!(difference <= kOutlierThreshold)) { ++result.outliers; }
            sumSquares += double(difference) * double(difference);
            goldenSquares += double(b[i]) * double(b[i]);
            ++samples;
        }
    }
    result.samples = samples;
    if (samples > 0 && goldenSquares > 0) { result.relativeRMS = float(std::sqrt(sumSquares / goldenSquares)); }
    return result;
}

float peak(const std::vector<float> &x) {
    float result = 0;
    for (float sample : x) { result = std::fmax(result, std::fabs(sample)); }
    return result;
}

} // namespace

int main(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    bool requireExact = false, listDifferences = false, checkBlockIndependence = false;
    std::string writeDirectory;
    int expectRejected = -1;
    std::vector<std::string> paths;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--require-exact") == 0) { requireExact = true; }
        else if (std::strcmp(argv[i], "--list-differences") == 0) { listDifferences = true; }
        else if (std::strcmp(argv[i], "--write-renders") == 0 && i + 1 < argc) { writeDirectory = argv[++i]; }
        else if (std::strcmp(argv[i], "--mutation") == 0 && i + 1 < argc) {
            const std::string name = argv[++i];
            mutation = name == "cutoff" ? Mutation::cutoff : name == "late-note" ? Mutation::lateNote
                : name == "detune" ? Mutation::detune : Mutation::none;
            if (mutation == Mutation::none) { std::printf("unknown mutation %s\n", name.c_str()); return 2; }
        }
        else if (std::strcmp(argv[i], "--free-voices-every-frame") == 0) { freeVoicesEveryFrame = true; }
        else if (std::strcmp(argv[i], "--flush-to-zero") == 0) {
            // X2-7 (ADR-078): render as a protected host does — subnormals flushed to zero — to
            // show the protection is not heard. Apple's <fenv.h> has the mode on both its
            // architectures UNDER TWO NAMES (found by X4's universal build: the Intel half did not
            // compile); the exact comparison is only made on Apple Silicon anyway.
#if defined(__APPLE__) && defined(__x86_64__)
            fesetenv(FE_DFL_DISABLE_SSE_DENORMS_ENV);
#elif defined(__APPLE__)
            fesetenv(FE_DFL_DISABLE_DENORMS_ENV);
#else
            std::printf("--flush-to-zero is only implemented on macOS\n");
            return 2;
#endif
        }
        else if (std::strcmp(argv[i], "--check-block-independence") == 0) { checkBlockIndependence = true; }
        else if (std::strcmp(argv[i], "--block-size") == 0 && i + 1 < argc) { blockSize = S1FrameCount(std::atoi(argv[++i])); }
        else if (std::strcmp(argv[i], "--expect-rejected") == 0 && i + 1 < argc) { expectRejected = std::atoi(argv[++i]); }
        else { paths.push_back(argv[i]); }
    }
    if (paths.size() != 3) { std::printf("usage: GoldenHarness <goldens> <bank dir> <wavetable dir> [--require-exact]\n"); return 2; }
    const std::string goldenDir = paths[0], bankDir = paths[1];

    s1::Wavetables tables;
    try {
        tables = s1::Wavetables::loadFromDirectory(paths[2]);
    } catch (const std::exception &error) {
        std::printf("FAIL  wavetables: %s\n", error.what());
        return 1;
    }

    // Preset defaults are the DSP's own, read from a kernel — as `synth.presetDefaults` is.
    std::unique_ptr<S1DSPKernel> reference = makeEngine(tables);
    const s1::PresetDefaults defaults = [&reference](S1Parameter p) { return double(reference->defaultValue(p)); };
    std::map<std::string, std::vector<s1::Preset>> banks;
    auto find = [&](const Golden &golden) -> const s1::Preset * {
        auto it = banks.find(golden.bank);
        if (it == banks.end()) {
            std::ifstream in(bankDir + "/" + golden.bank + ".json", std::ios::binary);
            const nlohmann::json array = nlohmann::json::parse(in, nullptr, false);
            it = banks.emplace(golden.bank, s1::Preset::bankFromJSON(array, defaults)).first;
        }
        for (const s1::Preset &preset : it->second) { if (preset.name == golden.preset) { return &preset; } }
        return nullptr;
    };

    if (checkBlockIndependence) {
        int independent = 0, asOneFrameBlocks = 0, changedByBlockSizeUpstream = 0;
        const int count = int(sizeof kGoldens / sizeof kGoldens[0]);
        for (const Golden &golden : kGoldens) {
            const s1::Preset *preset = find(golden);
            if (preset == nullptr) { std::printf("FAIL  %s/%s is not in the bank\n", golden.bank, golden.preset); ++failures; continue; }
            auto renderWith = [&](bool everyFrame, S1FrameCount frames) {
                freeVoicesEveryFrame = everyFrame;
                blockSize = frames;
                return renderGolden(tables, *preset);
            };
            const StereoRender reference = renderWith(true, 512);
            size_t worst = 0;
            for (S1FrameCount frames : {64u, 480u, 1024u, 37u}) {
                const Difference d = compare(renderWith(true, frames), reference);
                worst = std::max(worst, d.maximum == 0 ? size_t(0) : std::max<size_t>(d.outliers, 1));
            }
            const bool same = worst == 0;
            const bool oneFrame = compare(renderWith(false, 1), reference).maximum == 0;
            // What the option is for: upstream's path at two ordinary buffer sizes.
            const bool upstreamMoves = compare(renderWith(false, 64), renderWith(false, 512)).maximum != 0;
            if (same) { ++independent; }
            if (oneFrame) { ++asOneFrameBlocks; }
            if (upstreamMoves) { ++changedByBlockSizeUpstream; }
            std::printf("%s  %-48s same in blocks of 512/64/480/1024/37: %s; equal to upstream's path in 1-frame blocks: %s; upstream's path 64 vs 512: %s\n",
                        same && oneFrame ? "ok  " : "FAIL", golden.filename, same ? "yes" : "NO", oneFrame ? "yes" : "NO",
                        upstreamMoves ? "differs" : "same");
            if (!(same && oneFrame)) { ++failures; }
        }
        std::printf("GoldenHarness block independence: %d of %d presets render the same samples at every block size with voices freed "
                    "every frame; %d of %d equal upstream's path in one-frame blocks; upstream's path changes with the block size for %d of %d\n",
                    independent, count, asOneFrameBlocks, count, changedByBlockSizeUpstream, count);
        check(changedByBlockSizeUpstream > 0, "(and the option is needed: upstream's path does depend on the block size)", changedByBlockSizeUpstream);
        std::printf("%d failure(s)\n", failures);
        return failures == 0 ? 0 : 1;
    }

    // Determinism first: without it the rest means nothing. A patch with noise, bitcrush,
    // delay, reverb and a sequencer, twice, each from a new engine.
    {
        const s1::Preset *preset = find(kGoldens[6]);
        if (preset == nullptr) { std::printf("FAIL  %s/%s is not in the bank\n", kGoldens[6].bank, kGoldens[6].preset); return 1; }
        const StereoRender first = renderGolden(tables, *preset), second = renderGolden(tables, *preset);
        check(peak(first.left) > 0.001f, "the determinism patch is not silent", peak(first.left));
        check(compare(first, second).maximum == 0, "two renders of one preset from two new engines are identical", compare(first, second).maximum);
    }

    int exact = 0, withinTolerance = 0;
    float worstMaximum = 0, worstRMS = 0;
    size_t worstOutliers = 0;
    const int count = int(sizeof kGoldens / sizeof kGoldens[0]);
    for (const Golden &golden : kGoldens) {
        const s1::Preset *preset = find(golden);
        if (preset == nullptr) { std::printf("FAIL  %s/%s is not in the bank\n", golden.bank, golden.preset); ++failures; continue; }
        StereoRender reference_;
        try {
            reference_ = wav::read(goldenDir + "/" + golden.filename);
        } catch (const std::exception &error) {
            std::printf("FAIL  %s\n", error.what()); ++failures; continue;
        }
        const StereoRender rendered = renderGolden(tables, *preset);
        if (!writeDirectory.empty()) { wav::write(rendered, writeDirectory + "/" + golden.filename); }
        const Difference difference = compare(rendered, reference_);
        const bool sameLength = rendered.left.size() == reference_.left.size();
        const bool audible = peak(rendered.left) + peak(rendered.right) > 0.001f;
        const double outlierFraction = difference.samples > 0 ? double(difference.outliers) / double(difference.samples) : 1.0;
        const bool ok = sameLength && audible && difference.relativeRMS <= kMaximumRelativeRMSDifference
            && outlierFraction <= kMaximumOutlierFraction;
        worstOutliers = std::max(worstOutliers, difference.outliers);
        if (difference.maximum == 0 && sameLength) { ++exact; }
        if (ok) { ++withinTolerance; } else { ++failures; }
        if (listDifferences) {
            // Where the render leaves the golden by more than a tenth of the limit: isolated samples
            // (an edge landing one sample over) read very differently from a drift.
            int listed = 0;
            for (size_t i = 0; i < rendered.left.size() && i < reference_.left.size() && listed < 12; ++i) {
                const float dl = rendered.left[i] - reference_.left[i], dr = rendered.right[i] - reference_.right[i];
                if (std::fabs(dl) > kOutlierThreshold / 10 || std::fabs(dr) > kOutlierThreshold / 10) {
                    std::printf("        frame %zu: L %.6f vs %.6f (%+.2e)  R %.6f vs %.6f (%+.2e)\n", i,
                                double(rendered.left[i]), double(reference_.left[i]), double(dl),
                                double(rendered.right[i]), double(reference_.right[i]), double(dr));
                    ++listed;
                }
            }
        }
        worstMaximum = std::fmax(worstMaximum, difference.maximum);
        worstRMS = std::fmax(worstRMS, difference.relativeRMS);
        std::printf("%s  %-48s relative RMS %.3g, %zu of %zu samples over %.0e, max %.3g at %c[%zu], peak %.3f%s%s\n",
                    ok ? (difference.maximum == 0 ? "ok = " : "ok ~ ") : "FAIL", golden.filename,
                    double(difference.relativeRMS), difference.outliers, difference.samples, double(kOutlierThreshold),
                    double(difference.maximum), difference.channel, difference.atFrame,
                    double(std::fmax(peak(rendered.left), peak(rendered.right))),
                    sameLength ? "" : "  LENGTH DIFFERS", audible ? "" : "  SILENT");
    }
    std::printf("GoldenHarness: %d of %d goldens reproduced bit-exactly, %d of %d within tolerance "
                "(worst relative RMS %.3g, limit %.3g; worst outlier count %zu; worst single sample %.3g)\n",
                exact, count, withinTolerance, count, double(worstRMS), double(kMaximumRelativeRMSDifference),
                worstOutliers, double(worstMaximum));
    if (expectRejected >= 0) {
        // Self-check mode: the renders are wrong on purpose, and the verdict is inverted.
        const int rejected = count - withinTolerance;
        std::printf("GoldenHarness self-check: the criterion rejected %d of %d mutated renders (at least %d expected)\n",
                    rejected, count, expectRejected);
        return rejected >= expectRejected ? 0 : 1;
    }
    if (requireExact) { check(exact == count, "--require-exact: every golden is reproduced bit for bit", exact); }

    std::printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
