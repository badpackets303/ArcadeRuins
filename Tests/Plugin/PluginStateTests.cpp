// X2-5 (ADR-076): what a host saves and reopens.
//
//   argv[1]  Tests/Plugin/Fixtures/state-v1.json     a version-1 state, written by the macOS build
//   argv[2]  Sources/SynthOneCore/Presets/Data        the factory banks
//   --write-fixture   write argv[1] from this build's recipe instead of reading it. A released
//                     version's fixture is never rewritten: a new format version gets a new file.
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "S1PluginProcessor.h"
#include "S1Wavetables.hpp"
#include "../../Sources/S1Engine/third_party/nlohmann/json.hpp"

namespace {

constexpr int kCount = S1PluginProcessor::kParameterCount;

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

std::string stateOf(S1PluginProcessor &processor) {
    juce::MemoryBlock block;
    processor.getStateInformation(block);
    return std::string(static_cast<const char *>(block.getData()), block.getSize());
}
void load(S1PluginProcessor &processor, const std::string &text) { processor.setStateInformation(text.data(), int(text.size())); }

void renderOneBlock(S1PluginProcessor &processor) {
    juce::AudioBuffer<float> buffer(2, 256);
    juce::MidiBuffer midi;
    processor.processBlock(buffer, midi);
}

/// A sound that is not Init anywhere: every parameter moved to a legal value of its own.
float recipeValue(const s1plugin::ParameterDescription &d) {
    if (d.address == S1Parameter::tempoSyncToArpRate) { return 0.f; }   // so the rates are kept as written
    if (d.address == S1Parameter::pitchbend) { return d.defaultValue; }  // a wheel at rest; the test moves it itself
    if (d.kind == s1plugin::ParameterKind::toggle) { return d.defaultValue >= 0.5f ? 0.f : 1.f; }
    // Rounded to four decimals IN DOUBLE before it becomes a float: `min + range * fraction` is one
    // fused multiply-add on Apple Silicon and two operations elsewhere, and the last bit differs —
    // the first CI run of this test had 13 "expected" values that only a Mac could compute
    // (ADR-071's lesson, met again in a test). The state itself was never in doubt.
    const double fraction = 0.21 + 0.011 * double(int(d.address) % 50);
    const double exact = std::round((double(d.minimum) + (double(d.maximum) - double(d.minimum)) * fraction) * 10000.0) / 10000.0;
    const float value = std::min(std::max(float(exact), d.minimum), d.maximum);
    if (d.kind != s1plugin::ParameterKind::continuous) { return std::round(value); }
    return d.address == S1Parameter::arpSeqTempoMultiplier ? 0.25f : value;   // a note value: the engine keeps those
}

/// 19 equal divisions of the octave around A4 = 432 — to a thousandth of a hertz, because `pow` is
/// another thing two C libraries need not agree on to the last bit.
float tuningRecipe(int note) {
    return float(std::round(432.0 * std::pow(2.0, double(note - 69) / 19.0) * 1000.0) / 1000.0);
}

/// The recipe, put into a processor the way a person and a host would.
void applyRecipe(S1PluginProcessor &processor) {
    s1plugin::PluginState state = processor.currentState();
    for (int i = 0; i < kCount; ++i) { state.parameters[size_t(i)] = recipeValue(processor.hostParameter(S1Parameter(i)).description()); }
    for (int note = 0; note < 128; ++note) {
        state.tuningFrequencies[size_t(note)] = tuningRecipe(note);
    }
    state.tuningNotesPerOctave = 19;
    state.preset.uid = "0F0E0D0C-0B0A-4908-8706-050403020100";
    state.preset.name = "Nineteen \xE2\x80\x94 \xC3\xA9tude";   // UTF-8 beyond ASCII, on purpose
    state.preset.bank = "User";
    state.preset.author = "PluginStateTests";
    state.preset.tuningName = "19 EDO";
    state.preset.tuningMasterSet = std::vector<double> {1.0, 1.0371550444461919, 1.0756905862293397};
    state.preset.modWheelRouting = 2;
    state.midi.octaveShift = -12;
    state.midi.channel = 3;
    state.midi.omni = false;
    state.midi.whiteKeysOnly = true;
    processor.applyState(state);
}

nlohmann::json withoutBuildVersion(const std::string &text) {
    nlohmann::json j = nlohmann::json::parse(text, nullptr, false);
    if (j.is_object()) { j.erase("plugin"); }
    return j;
}

int differingParameters(S1PluginProcessor &a, S1PluginProcessor &b, bool skipPitchbend) {
    int different = 0;
    for (int i = 0; i < kCount; ++i) {
        if (skipPitchbend && i == int(S1Parameter::pitchbend)) { continue; }
        if (a.hostParameter(S1Parameter(i)).plainValue() != b.hostParameter(S1Parameter(i)).plainValue()) { ++different; }
    }
    return different;
}

} // namespace

int main(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    std::vector<std::string> paths;
    bool writeFixture = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--write-fixture") == 0) { writeFixture = true; } else { paths.push_back(argv[i]); }
    }
    if (paths.size() != 2) { std::printf("usage: PluginStateTests <state-v1.json> <bank dir> [--write-fixture]\n"); return 2; }

    // MARK: save in one instance, reopen in another
    S1PluginProcessor saved;
    saved.setPlayConfigDetails(0, 2, 44100.0, 256);
    applyRecipe(saved);
    saved.hostParameter(S1Parameter::pitchbend).setValueNotifyingHost(0.9f);   // the wheel, held up while the host saves
    const std::string text = stateOf(saved);
    {
        int moved = 0;
        S1PluginProcessor fresh;
        for (int i = 0; i < kCount; ++i) {
            if (saved.hostParameter(S1Parameter(i)).plainValue() != fresh.hostParameter(S1Parameter(i)).plainValue()) { ++moved; }
        }
        check(moved >= 120, "the recipe moves most parameters away from Init", moved);
        check(text.size() > 4000 && text.find("\"format\": \"ArcadeRuins.state\"") != std::string::npos, "the state is JSON text that names its format", double(text.size()));
        check(text.find("\"pitchbend\"") == std::string::npos, "a wheel's position is not written", 0);
    }
    {
        S1PluginProcessor reopened;
        reopened.setPlayConfigDetails(0, 2, 48000.0, 512);
        load(reopened, text);
        check(differingParameters(saved, reopened, true) == 0, "all 149 saved parameters come back as the same numbers, to the bit", differingParameters(saved, reopened, true));
        check(reopened.hostParameter(S1Parameter::pitchbend).plainValue() == 8192.f, "and the pitch wheel comes back centred", reopened.hostParameter(S1Parameter::pitchbend).plainValue());
        const s1plugin::PluginState state = reopened.currentState();
        bool tuningSame = state.tuningNotesPerOctave == 19;
        for (int note = 0; note < 128; ++note) { tuningSame = tuningSame && state.tuningFrequencies[size_t(note)] == tuningRecipe(note); }
        check(tuningSame, "the tuning: 19 notes per octave and the same 128 frequencies", state.tuningNotesPerOctave);
        check(state.preset.name == "Nineteen \xE2\x80\x94 \xC3\xA9tude" && state.preset.uid == "0F0E0D0C-0B0A-4908-8706-050403020100"
                  && state.preset.tuningName == std::optional<std::string>("19 EDO") && state.preset.tuningMasterSet && state.preset.tuningMasterSet->size() == 3,
              "the preset's identity: name (UTF-8), uid, tuning name and master set", 0);
        // X2-8 (ADR-079) found a program without a name; since X2-9 (ADR-080) the list is the 695
        // factory presets (Tests/Plugin/PluginPresetTests). Here: a sound that is none of them
        // leaves the program shown where it was, and every program still has a name.
        check(reopened.getNumPrograms() == 695 && reopened.getProgramName(reopened.getCurrentProgram()).isNotEmpty(),
              "a restored sound that is no factory preset: the host's program list is intact, the program shown has a name", reopened.getNumPrograms());
        check(reopened.getModWheelRouting() == s1plugin::ModWheelRouting::lfo2Rate, "the mod wheel's routing", int(reopened.getModWheelRouting()));
        check(state.midi.octaveShift == -12 && state.midi.channel == 3 && !state.midi.omni && state.midi.whiteKeysOnly && !state.midi.hold, "the router's settings", state.midi.channel);

        // X3-8 (ADR-090): the keyboard drawer travels with the session, per instance — and a state
        // written before it existed still loads, with the drawer closed.
        {
            check(!reopened.keyboardShown(), "a restored session opens with the drawer closed unless it says otherwise", 0);
            S1PluginProcessor withDrawer;
            withDrawer.setKeyboardShown(true);
            S1PluginProcessor second;
            load(second, stateOf(withDrawer));
            check(second.keyboardShown(), "…and open when it does", 1);
            // A state written before the drawer existed does not name it, and what a state does
            // not name stays as it was — this file's rule for every other field. A fresh instance
            // is closed, so an old session opens closed.
            nlohmann::json older = nlohmann::json::parse(stateOf(withDrawer), nullptr, false);
            older.erase("window");
            S1PluginProcessor third;
            load(third, older.dump(1));
            check(!third.keyboardShown(), "a state from before the drawer existed opens closed, as a fresh instance is", 0);
            S1PluginProcessor fourth;
            fourth.setKeyboardShown(true);
            load(fourth, older.dump(1));
            check(fourth.keyboardShown(), "…and leaves a window that was already open alone, as every unnamed field is", 1);
        }

        // Before a single block has run — a host may save again at once.
        saved.hostParameter(S1Parameter::pitchbend).setValueNotifyingHost(0.5f);
        check(stateOf(reopened) == stateOf(saved), "saved again before any audio has run, it is the same text, byte for byte", double(stateOf(reopened).size()));

        // And then it reaches the kernel.
        reopened.prepareToPlay(48000.0, 512);
        renderOneBlock(reopened);
        int notInKernel = 0;
        for (int i = 0; i < kCount; ++i) {
            if (reopened.engineValue(S1Parameter(i)) != reopened.hostParameter(S1Parameter(i)).plainValue()) { ++notInKernel; }
        }
        check(notInKernel == 0, "after prepareToPlay and one block the kernel holds all 150 values", notInKernel);
        check(reopened.engineTuningFrequency(69) == 432.f && reopened.engineTuningFrequency(88) == 864.f, "and the tuning: A4 = 432 Hz, 19 steps up = 864 Hz", reopened.engineTuningFrequency(88));
        check(stateOf(reopened) == stateOf(saved), "and playing has not changed what would be saved", 0);
    }

    // MARK: a state loaded while audio runs
    {
        S1PluginProcessor running;
        running.setPlayConfigDetails(0, 2, 44100.0, 256);
        running.prepareToPlay(44100.0, 256);
        renderOneBlock(running);
        load(running, text);
        check(running.engineTuningFrequency(69) != 432.f, "(a state set between blocks is not written into the kernel by the thread that loads it)", running.engineTuningFrequency(69));
        renderOneBlock(running);
        check(running.engineTuningFrequency(69) == 432.f && running.engineValue(S1Parameter::cutoff) == running.hostParameter(S1Parameter::cutoff).plainValue()
                  && differingParameters(saved, running, true) == 0,
              "the next block carries tuning and parameters in", running.engineTuningFrequency(69));
    }

    // MARK: what is not a state changes nothing
    {
        S1PluginProcessor careful;
        applyRecipe(careful);
        const std::string before = stateOf(careful);
        load(careful, "");
        load(careful, "not json at all \x01\x02\xFF");
        load(careful, "{\"format\": \"SomebodyElse.state\", \"parameters\": {\"cutoff\": 100}}");
        load(careful, "[1, 2, 3]");
        load(careful, text.substr(0, text.size() / 2));   // a truncated file
        check(stateOf(careful) == before, "empty, garbage, another plugin's chunk, an array, half a file: nothing changes", 0);
    }

    // MARK: states from other versions — fewer keys, more keys, values out of range
    {
        S1PluginProcessor tolerant;
        applyRecipe(tolerant);
        const float resonanceBefore = tolerant.hostParameter(S1Parameter::resonance).plainValue();
        load(tolerant, R"({"format": "ArcadeRuins.state", "version": 7, "somethingNew": {"a": 1},
                          "parameters": {"cutoff": 1234.5, "aParameterFromTheFuture": 3, "filterType": 1.4, "resonance": "loud", "masterVolume": 99}})");
        check(tolerant.hostParameter(S1Parameter::cutoff).plainValue() == 1234.5f, "a later version's state: the parameters it names are taken", tolerant.hostParameter(S1Parameter::cutoff).plainValue());
        check(tolerant.hostParameter(S1Parameter::filterType).plainValue() == 1.f, "a stepped parameter lands on a step", tolerant.hostParameter(S1Parameter::filterType).plainValue());
        check(tolerant.hostParameter(S1Parameter::masterVolume).plainValue() == tolerant.hostParameter(S1Parameter::masterVolume).getNormalisableRange().end, "a value out of range is clamped", tolerant.hostParameter(S1Parameter::masterVolume).plainValue());
        check(tolerant.hostParameter(S1Parameter::resonance).plainValue() == resonanceBefore && tolerant.currentState().tuningNotesPerOctave == 19,
              "what it does not name, or names wrongly, stays as it was", tolerant.hostParameter(S1Parameter::resonance).plainValue());
    }

    // MARK: a preset the Mac app wrote, as a state
    {
        int presetsTried = 0, wrong = 0;
        for (const char *bankName : {"Starter Bank", "Brice Beasley", "Sound of Izrael 2"}) {
            std::ifstream in(paths[1] + "/" + bankName + ".json", std::ios::binary);
            const nlohmann::json bank = nlohmann::json::parse(in, nullptr, false);
            if (!bank.is_array()) { std::printf("FAIL  cannot read the bank %s\n", bankName); ++failures; continue; }
            for (size_t index = 0; index < bank.size(); index += 7) {
                // The engine's own reading of the preset, in a bare kernel…
                S1DSPKernel reference(2, 44100.0);
                const s1::PresetDefaults defaults = [&reference](S1Parameter p) { return double(reference.defaultValue(p)); };
                s1::Preset::fromJSON(bank[index], defaults).apply(reference);
                // …and the same JSON handed to the plugin as the "preset" of a state with nothing else in it.
                S1PluginProcessor plugin;
                plugin.setPlayConfigDetails(0, 2, 44100.0, 256);
                load(plugin, nlohmann::json({{"format", "ArcadeRuins.state"}, {"version", 1}, {"preset", bank[index]}}).dump());
                plugin.prepareToPlay(44100.0, 256);
                renderOneBlock(plugin);
                ++presetsTried;
                for (int i = 0; i < kCount; ++i) {
                    if (i == int(S1Parameter::pitchbend)) { continue; }
                    // A host's stepped parameter lands on its step: one factory preset has arpInterval 8.04.
                    const float expected = plugin.hostParameter(S1Parameter(i)).getNormalisableRange().snapToLegalValue(reference.getSynthParameter(S1Parameter(i)));
                    if (plugin.engineValue(S1Parameter(i)) != expected) {
                        if (++wrong <= 5) { std::printf("      %s / %s: %s is %.6g in the plugin's kernel, %.6g in the engine's\n", bankName, bank[index].value("name", "?").c_str(),
                                                        s1plugin::parameterID(i), double(plugin.engineValue(S1Parameter(i))), double(reference.getSynthParameter(S1Parameter(i)))); }
                    }
                }
                if (plugin.currentState().preset.name != bank[index].value("name", "?")) { ++wrong; }
            }
        }
        check(presetsTried >= 15 && wrong == 0, "factory presets from three banks, each loaded as a state's preset: the plugin's kernel holds what the engine's own apply gives, and the name", presetsTried);
    }

    // MARK: the committed version-1 state, written on macOS, read here
    {
        S1PluginProcessor recipe;
        applyRecipe(recipe);
        const std::string fromThisBuild = stateOf(recipe);
        if (writeFixture) {
            std::ofstream(paths[0], std::ios::binary) << fromThisBuild;
            std::printf("wrote %s\n", paths[0].c_str());
        } else {
            std::ifstream in(paths[0], std::ios::binary);
            std::stringstream contents;
            contents << in.rdbuf();
            const std::string fixture = contents.str();
            check(fixture.size() > 4000, "the committed version-1 state can be read", double(fixture.size()));
            S1PluginProcessor fromFixture;
            load(fromFixture, fixture);
            check(differingParameters(recipe, fromFixture, false) == 0, "loaded on this OS it gives the recipe's 150 parameters, to the bit", differingParameters(recipe, fromFixture, false));
            check(withoutBuildVersion(stateOf(fromFixture)) == withoutBuildVersion(fixture), "saved again it is the same JSON (the build's version string aside)", 0);
            check(withoutBuildVersion(fromThisBuild) == withoutBuildVersion(fixture), "and this OS writes the same JSON for the recipe as the Mac that wrote the file", 0);
        }
    }

    std::printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
