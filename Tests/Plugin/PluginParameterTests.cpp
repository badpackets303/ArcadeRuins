// X2-2 (ADR-073): the 150 parameters as a host meets them.
//
//   argv[1]  Tests/Plugin/Fixtures/parameter-ids.txt   the frozen identity: index, ID, version hint
//   --write-fixture   write that file from the build instead of checking against it. Only ever to
//                     ADD lines for new parameters: an existing line that changes breaks sessions.
// Floats are compared exactly here, on purpose: "the same number" is what these checks assert.
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "S1PluginProcessor.h"

namespace {

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}
void checkText(const std::string &got, const std::string &expected, const std::string &what) {
    const bool ok = got == expected;
    std::printf("%s  %s: \"%s\"%s\n", ok ? "ok  " : "FAIL", what.c_str(), got.c_str(), ok ? "" : (" — expected \"" + expected + "\"").c_str());
    if (!ok) { ++failures; }
}

constexpr int kCount = S1PluginProcessor::kParameterCount;

void renderOneBlock(S1PluginProcessor &processor) {
    juce::AudioBuffer<float> buffer(2, 256);
    juce::MidiBuffer midi;
    processor.processBlock(buffer, midi);
}

/// What a host does when a person or an automation lane moves a parameter.
void hostWrites(S1HostParameter &parameter, float plain) {
    parameter.setValueNotifyingHost(parameter.convertTo0to1(plain));
}

std::string text(const S1HostParameter &parameter, float plain) {
    return parameter.getText(parameter.convertTo0to1(plain), 0).toStdString();
}

/// Counts what a host would be told: value changes, and gestures (which mean "a person is editing").
struct HostEars final : juce::AudioProcessorParameter::Listener {
    int values = 0, gestures = 0;
    void parameterValueChanged(int, float) override { ++values; }
    void parameterGestureChanged(int, bool) override { ++gestures; }
};

/// A legal value that is neither the default nor an end of the range, where there is one.
float testValue(const s1plugin::ParameterDescription &d) {
    if (d.kind == s1plugin::ParameterKind::toggle) { return d.defaultValue >= 0.5f ? 0.f : 1.f; }
    if (d.kind != s1plugin::ParameterKind::continuous) {
        const float candidate = std::round((d.minimum + d.maximum) / 2);
        return candidate != d.defaultValue ? candidate : (candidate < d.maximum ? candidate + 1 : candidate - 1);
    }
    const float candidate = d.minimum + (d.maximum - d.minimum) * 0.37f;
    return candidate != d.defaultValue ? candidate : d.minimum + (d.maximum - d.minimum) * 0.61f;
}

} // namespace

int main(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    std::string fixturePath;
    bool writeFixture = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--write-fixture") == 0) { writeFixture = true; } else { fixturePath = argv[i]; }
    }
    if (fixturePath.empty()) { std::printf("usage: PluginParameterTests <parameter-ids.txt> [--write-fixture]\n"); return 2; }

    S1PluginProcessor processor;
    processor.setPlayConfigDetails(0, 2, 44100.0, 256);
    const auto &hosted = processor.getParameters();

    // MARK: identity
    check(hosted.size() == kCount && kCount == 150, "the host is given 150 parameters", hosted.size());
    std::ostringstream identity;
    std::set<std::string> ids;
    int wrongOrder = 0, wrongHint = 0;
    for (int i = 0; i < hosted.size(); ++i) {
        auto *parameter = dynamic_cast<S1HostParameter *>(hosted[i]);
        if (parameter == nullptr || int(parameter->description().address) != i || parameter->getParameterIndex() != i) { ++wrongOrder; continue; }
        if (parameter->getVersionHint() != 1) { ++wrongHint; }
        ids.insert(parameter->getParameterID().toStdString());
        identity << i << ' ' << parameter->getParameterID() << ' ' << parameter->getVersionHint() << '\n';
    }
    check(wrongOrder == 0, "parameter i of the host's list is S1Parameter i", wrongOrder);
    check(wrongHint == 0, "every version hint is 1", wrongHint);
    check(ids.size() == size_t(kCount), "the IDs are 150 different strings", double(ids.size()));
    checkText(processor.hostParameter(S1Parameter::cutoff).getParameterID().toStdString(), "cutoff", "an ID is its enum case's name");
    checkText(processor.hostParameter(S1Parameter::filterAttackDuration).getParameterID().toStdString(), "filterAttackDuration",
              "also where the kernel's preset key differs (it is \"filterAttack\")");
    checkText(processor.hostParameter(S1Parameter::compressorReverbWetMakeupGain).getParameterID().toStdString(), "compressorReverbWetMakeupGain",
              "and where the kernel's key is a duplicate");
    if (writeFixture) {
        std::ofstream(fixturePath, std::ios::binary) << identity.str();
        std::printf("wrote %s\n", fixturePath.c_str());
    } else {
        std::ifstream in(fixturePath, std::ios::binary);
        std::stringstream frozen;
        frozen << in.rdbuf();
        std::string frozenText = frozen.str();
        frozenText.erase(std::remove(frozenText.begin(), frozenText.end(), '\r'), frozenText.end());   // a Windows checkout
        check(in.good() || !frozenText.empty(), "the frozen identity list can be read", double(frozenText.size()));
        // Every frozen line must still be there, unchanged. New parameters may follow.
        check(identity.str().compare(0, frozenText.size(), frozenText) == 0 && !frozenText.empty(),
              "index, ID and version hint of every released parameter are what they were", double(frozenText.size()));
    }

    // MARK: ranges and defaults are the kernel's
    {
        S1DSPKernel reference(2, 44100.0);
        int wrong = 0, outside = 0;
        for (int i = 0; i < kCount; ++i) {
            const S1Parameter p = S1Parameter(i);
            const S1HostParameter &parameter = processor.hostParameter(p);
            const auto &range = parameter.getNormalisableRange();
            if (range.start != reference.minimum(p) || range.end != reference.maximum(p)
                // (the default goes through 0…1 and back, so it is equal to a float's rounding, not to the bit)
                || std::fabs(parameter.convertFrom0to1(parameter.getDefaultValue()) - range.snapToLegalValue(reference.defaultValue(p)))
                       > 1e-5f * std::max(1.f, std::fabs(reference.defaultValue(p)))) {
                ++wrong;
                std::printf("      %s: range %g…%g default %g, kernel %g…%g default %g\n", parameter.getParameterID().toRawUTF8(),
                            double(range.start), double(range.end), double(parameter.convertFrom0to1(parameter.getDefaultValue())),
                            double(reference.minimum(p)), double(reference.maximum(p)), double(reference.defaultValue(p)));
            }
            const float n = parameter.getValue();
            if (!(n >= 0 && n <= 1)) { ++outside; }
        }
        check(wrong == 0, "minimum, maximum and default of all 150 are the kernel table's", wrong);
        check(outside == 0, "every parameter starts inside 0…1", outside);
    }

    // MARK: the parameters start as Init, and the kernel agrees
    {
        int different = 0;
        for (int i = 0; i < kCount; ++i) {
            if (processor.hostParameter(S1Parameter(i)).plainValue() != processor.engineValue(S1Parameter(i))) { ++different; }
        }
        check(different == 0, "at birth the host's values and the kernel's are the same 150 numbers", different);
    }

    // MARK: a value set before the host prepares the plugin survives (the prepareToRender PORT FIX)
    hostWrites(processor.hostParameter(S1Parameter::cutoff), 777.f);
    hostWrites(processor.hostParameter(S1Parameter::filterType), 2.f);
    processor.prepareToPlay(44100.0, 256);
    check(std::fabs(processor.engineValue(S1Parameter::cutoff) - 777.f) < 0.01f, "a smoothed parameter written before prepareToPlay is in the kernel after it", processor.engineValue(S1Parameter::cutoff));
    check(processor.engineValue(S1Parameter::filterType) == 2.f, "and a stepped one", processor.engineValue(S1Parameter::filterType));
    processor.prepareToPlay(48000.0, 512);
    check(std::fabs(processor.engineValue(S1Parameter::cutoff) - 777.f) < 0.01f, "and it survives a second prepareToPlay at another sample rate", processor.engineValue(S1Parameter::cutoff));

    // MARK: every parameter reaches the kernel through processBlock
    hostWrites(processor.hostParameter(S1Parameter::tempoSyncToArpRate), 0.f);   // so the rates are not quantised
    renderOneBlock(processor);
    {
        int notReached = 0, reported = 0;
        for (int i = 0; i < kCount; ++i) {
            const S1Parameter p = S1Parameter(i);
            if (p == S1Parameter::tempoSyncToArpRate) { continue; }
            S1HostParameter &parameter = processor.hostParameter(p);
            const float value = testValue(parameter.description());
            hostWrites(parameter, value);
            const float written = parameter.plainValue();
            renderOneBlock(processor);
            // The Seq Step Length is always a note value: the engine answers with the nearest one.
            const bool engineAnswers = p == S1Parameter::arpSeqTempoMultiplier;
            if (!engineAnswers && processor.engineValue(p) != written) {
                ++notReached;
                std::printf("      %s: wrote %.6g, the kernel holds %.6g\n", parameter.getParameterID().toRawUTF8(), double(written), double(processor.engineValue(p)));
            }
            if (parameter.plainValue() != processor.engineValue(p)) { ++reported; }
        }
        check(notReached == 0, "a value written to each of the 149 others is the kernel's value one block later", notReached);
        check(reported == 0, "and afterwards host and kernel hold the same number for every one", reported);
    }

    // MARK: a value the host SET survives a re-initialise with no audio between (ADR-093). Apple's
    // auval does exactly this — set, uninitialise, initialise, read — and fails the AU when the
    // value has moved; Logic will not load one that fails. The engine snaps a step length to its
    // nearest note value, and the plugin used to report that AT prepare, under the host. It is
    // reported at the first rendered block now, as every later snap is.
    {
        S1PluginProcessor plugin;
        plugin.setPlayConfigDetails(0, 2, 44100.0, 256);
        plugin.prepareToPlay(44100.0, 256);
        S1HostParameter &length = plugin.hostParameter(S1Parameter::arpSeqTempoMultiplier);
        HostEars ears;
        length.addListener(&ears);
        length.setValueNotifyingHost(0.308594f);              // auval's own number; not a note value
        const float asSet = length.getValue();
        plugin.releaseResources();
        plugin.prepareToPlay(48000.0, 512);
        check(length.getValue() == asSet, "set, then re-initialised with no audio between: the parameter is where the host put it", length.getValue());
        const int heard = ears.values;
        renderOneBlock(plugin);
        check(length.getValue() != asSet && length.plainValue() == plugin.engineValue(S1Parameter::arpSeqTempoMultiplier),
              "…and the first rendered block reports the engine's note value, as any later snap is", length.getValue());
        check(ears.values == heard + 1 && ears.gestures == 0, "…once, as a report: no gesture", ears.values - heard);
    }

    // MARK: the engine's own changes (ADR-022)
    {
        S1PluginProcessor synced;
        synced.setPlayConfigDetails(0, 2, 44100.0, 256);
        synced.prepareToPlay(44100.0, 256);
        hostWrites(synced.hostParameter(S1Parameter::tempoSyncToArpRate), 1.f);
        hostWrites(synced.hostParameter(S1Parameter::arpRate), 120.f);
        renderOneBlock(synced);

        S1HostParameter &rate = synced.hostParameter(S1Parameter::lfo1Rate);
        HostEars rateEars, delayEars;
        rate.addListener(&rateEars);
        synced.hostParameter(S1Parameter::delayTime).addListener(&delayEars);

        hostWrites(rate, 3.1f);              // not a note value at 120 BPM: a 1/4 triplet is 3 Hz, a 1/8 note 4 Hz
        const float asWritten = rate.plainValue();
        const int heardFromHost = rateEars.values;
        renderOneBlock(synced);
        const float quantised = synced.engineValue(S1Parameter::lfo1Rate);
        check(quantised != asWritten && std::fabs(quantised - 3.f) < 1e-4f, "under tempo sync a rate of 3.1 Hz becomes the nearest note value (1/4 triplet = 3 Hz at 120)", quantised);
        check(rate.plainValue() == quantised, "the host's parameter now holds the engine's value, not the 3.1 it wrote", rate.plainValue());
        check(rateEars.values == heardFromHost + 1 && rateEars.gestures == 0, "the host is told once, as a report: no gesture, so nothing for it to record", rateEars.values - heardFromHost);
        checkText(text(rate, quantised), "1/4 triplet", "its readout under tempo sync is the note value");

        const float delayBefore = synced.engineValue(S1Parameter::delayTime);
        const int delayHeard = delayEars.values;
        hostWrites(synced.hostParameter(S1Parameter::arpRate), 90.f);
        renderOneBlock(synced);
        const float delayAfter = synced.engineValue(S1Parameter::delayTime);
        check(delayAfter != delayBefore, "a new tempo re-drives the delay time in the engine", delayAfter);
        check(synced.hostParameter(S1Parameter::delayTime).plainValue() == delayAfter && delayEars.values == delayHeard + 1,
              "and the host is told the delay time it never touched", synced.hostParameter(S1Parameter::delayTime).plainValue());
        // Since the X2 gate (ADR-082, the owner's decision) a tempo change keeps the NOTE VALUE:
        // the 1/4 triplet that was 3 Hz at 120 is a 1/4 triplet at 90 — 2.25 Hz. (Upstream
        // re-quantised by frequency: 3 Hz is exactly a 1/8 note at 90, so the number stayed and
        // the note silently changed. This check pinned that until the gate.)
        check(std::fabs(synced.engineValue(S1Parameter::lfo1Rate) - 2.25f) < 1e-4f, "at 90 BPM the LFO is still a 1/4 triplet: 2.25 Hz", synced.engineValue(S1Parameter::lfo1Rate));
        checkText(text(rate, synced.engineValue(S1Parameter::lfo1Rate)), "1/4 triplet", "and reads as the note it was");

        // Nothing stale comes back: more blocks, with the host writing nothing, change nothing.
        const int settled = rateEars.values + delayEars.values;
        float before[kCount], after[kCount];
        for (int i = 0; i < kCount; ++i) { before[i] = synced.engineValue(S1Parameter(i)); }
        for (int block = 0; block < 8; ++block) { renderOneBlock(synced); }
        int drifted = 0;
        for (int i = 0; i < kCount; ++i) { after[i] = synced.engineValue(S1Parameter(i)); if (after[i] != before[i]) { ++drifted; } }
        check(drifted == 0 && rateEars.values + delayEars.values == settled, "eight more blocks: no kernel value moves and the host hears nothing", drifted);

        hostWrites(synced.hostParameter(S1Parameter::tempoSyncToArpRate), 0.f);
        hostWrites(rate, 3.1f);
        renderOneBlock(synced);
        check(synced.engineValue(S1Parameter::lfo1Rate) == rate.plainValue() && std::fabs(rate.plainValue() - 3.1f) < 1e-4f, "sync off and a rate in the SAME block: the rate is taken as written (the switch goes first)", synced.engineValue(S1Parameter::lfo1Rate));
        checkText(text(rate, 3.1f), "3.1 Hz", "and its readout is in Hz again");

        rate.removeListener(&rateEars);
        synced.hostParameter(S1Parameter::delayTime).removeListener(&delayEars);
    }

    // MARK: what a host shows and accepts
    {
        const auto &p = processor;
        checkText(p.hostParameter(S1Parameter::cutoff).getName(64).toStdString(), "Filter Cutoff", "names are the desktop layout's, with the section");
        checkText(text(p.hostParameter(S1Parameter::cutoff), 1000.f), "1.00 kHz", "cutoff 1000");
        checkText(text(p.hostParameter(S1Parameter::cutoff), 440.f), "440 Hz", "cutoff 440");
        checkText(text(p.hostParameter(S1Parameter::attackDuration), 0.05f), "50 ms", "attack 0.05");
        checkText(text(p.hostParameter(S1Parameter::releaseDuration), 1.5f), "1.50 s", "release 1.5");
        checkText(text(p.hostParameter(S1Parameter::morph1Volume), 0.8f), "80%", "OSC 1 level 0.8");
        checkText(text(p.hostParameter(S1Parameter::morph1SemitoneOffset), 7.f), "+7 st", "semitones 7");
        checkText(text(p.hostParameter(S1Parameter::compressorMasterThreshold), -9.f), "-9.0 dB", "threshold -9");
        checkText(text(p.hostParameter(S1Parameter::filterType), 1.f), "Band Pass", "filter type 1");
        checkText(text(p.hostParameter(S1Parameter::cutoffLFO), 3.f), "LFO 1 + 2", "LFO routing 3");
        checkText(text(p.hostParameter(S1Parameter::isMono), 1.f), "On", "a switch");
        checkText(text(p.hostParameter(S1Parameter::arpSeqTempoMultiplier), 0.25f), "1/4 note", "sequencer step length 0.25 bars");
        checkText(text(p.hostParameter(S1Parameter::arpRate), 120.f), "120.0 BPM", "tempo");

        const S1HostParameter &cutoffParameter = p.hostParameter(S1Parameter::cutoff);
        auto typed = [](const S1HostParameter &parameter, const char *entry) { return parameter.convertFrom0to1(parameter.getValueForText(entry)); };
        check(std::fabs(typed(cutoffParameter, "1.2 kHz") - 1200.f) < 0.5f, "typing \"1.2 kHz\" into cutoff", typed(cutoffParameter, "1.2 kHz"));
        check(std::fabs(typed(p.hostParameter(S1Parameter::attackDuration), "35 ms") - 0.035f) < 1e-5f, "typing \"35 ms\" into attack", typed(p.hostParameter(S1Parameter::attackDuration), "35 ms"));
        check(std::fabs(typed(p.hostParameter(S1Parameter::morph1Volume), "50%") - 0.5f) < 1e-5f, "typing \"50%\" into a level", typed(p.hostParameter(S1Parameter::morph1Volume), "50%"));
        check(typed(p.hostParameter(S1Parameter::filterType), "high pass") == 2.f, "typing a choice's name", typed(p.hostParameter(S1Parameter::filterType), "high pass"));
        check(typed(cutoffParameter, "99999") == cutoffParameter.getNormalisableRange().end, "a number past the range is the end of the range", typed(cutoffParameter, "99999"));

        // The cutoff knob's taper is the Mac's (2): half way round is a quarter of the way up.
        const auto &range = cutoffParameter.getNormalisableRange();
        const float half = cutoffParameter.convertFrom0to1(0.5f);
        check(std::fabs(half - (range.start + (range.end - range.start) * 0.25f)) < 0.5f, "cutoff at half its travel is min + range/4, as the Mac knob's", half);

        int unsteady = 0, roundTrip = 0;
        for (int i = 0; i < kCount; ++i) {
            const S1HostParameter &parameter = p.hostParameter(S1Parameter(i));
            if (parameter.isDiscrete()) {
                const int steps = parameter.getNumSteps();
                const auto &r = parameter.getNormalisableRange();
                if (steps != int(std::lround(r.end - r.start)) + 1 || steps < 2) { ++unsteady; }
            }
            for (float n : {0.f, 0.25f, 0.5f, 1.f}) {
                const float plain = parameter.convertFrom0to1(n);
                if (std::fabs(parameter.convertFrom0to1(parameter.convertTo0to1(plain)) - plain) > 1e-3f * std::max(1.f, std::fabs(plain))) { ++roundTrip; }
            }
        }
        check(unsteady == 0, "every stepped parameter has one step per whole number of its range", unsteady);
        check(roundTrip == 0, "plain -> 0…1 -> plain is stable for every parameter", roundTrip);
    }

    // MARK: the tail follows the parameters
    {
        S1PluginProcessor fresh;
        hostWrites(fresh.hostParameter(S1Parameter::delayOn), 0.f);
        hostWrites(fresh.hostParameter(S1Parameter::reverbOn), 0.f);
        hostWrites(fresh.hostParameter(S1Parameter::releaseDuration), 0.5f);
        const double dry = fresh.getTailLengthSeconds();
        hostWrites(fresh.hostParameter(S1Parameter::delayOn), 1.f);
        hostWrites(fresh.hostParameter(S1Parameter::delayMix), 0.5f);
        hostWrites(fresh.hostParameter(S1Parameter::delayTime), 0.5f);
        hostWrites(fresh.hostParameter(S1Parameter::delayFeedback), 0.5f);
        const double delayed = fresh.getTailLengthSeconds();
        check(std::fabs(dry - 0.5) < 1e-6, "with no effects the tail is the release", dry);
        check(std::fabs(delayed - (0.5 + 0.5 * 10)) < 1e-6, "a 0.5 s delay at 50% feedback adds ten repeats (-60 dB)", delayed);
    }

    processor.releaseResources();
    std::printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
