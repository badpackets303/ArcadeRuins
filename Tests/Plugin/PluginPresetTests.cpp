// X2-9 (ADR-080): the preset library — the factory banks linked into the plugin against the
// repository's files, the host's programs against the Mac AUv3's own list, a preset loaded as a
// host loads it and as a person does, and the user's banks on disk.
//
//   argv[1]  Tests/Plugin/Fixtures/factory-programs.txt   written by the Swift test FactoryProgramFixtureTests
//   argv[2]  Sources/SynthOneCore/Presets/Data             the Mac app's bank files
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <chrono>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "S1PluginProcessor.h"

namespace fs = std::filesystem;

namespace {

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

std::string readFile(const fs::path &path) {
    std::ifstream in(path, std::ios::binary);
    std::ostringstream text;
    text << in.rdbuf();
    return text.str();
}

struct HostEars final : juce::AudioProcessorParameter::Listener {
    int values = 0, begun = 0, ended = 0;
    void parameterValueChanged(int, float) override { ++values; }
    void parameterGestureChanged(int, bool starting) override { if (starting) { ++begun; } else { ++ended; } }
};

void listenToAll(S1PluginProcessor &processor, HostEars &ears, bool add) {
    for (int i = 0; i < S1PluginProcessor::kParameterCount; ++i) {
        if (add) { processor.hostParameter(S1Parameter(i)).addListener(&ears); } else { processor.hostParameter(S1Parameter(i)).removeListener(&ears); }
    }
}

/// How many of the 150 host parameters are not what `preset` gives a new engine (the wheel aside).
int differing(S1PluginProcessor &processor, const s1::Preset &preset) {
    const s1plugin::PresetParameters expected = s1plugin::presetParameters(preset);
    int different = 0;
    for (int i = 0; i < S1PluginProcessor::kParameterCount; ++i) {
        if (i == int(S1Parameter::pitchbend)) { continue; }
        S1HostParameter &parameter = processor.hostParameter(S1Parameter(i));
        if (parameter.plainValue() != parameter.getNormalisableRange().snapToLegalValue(expected[size_t(i)])) { ++different; }
    }
    return different;
}

} // namespace

int main(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc != 3) { std::printf("usage: PluginPresetTests <factory-programs.txt> <bank dir>\n"); return 2; }
    const fs::path fixture = argv[1], bankDirectory = argv[2];

    // Every test's user folder is a new one under the system's temporary folder: the real one is
    // the owner's, and nothing here may read it, let alone write in it.
    const fs::path scratch = fs::temp_directory_path() / ("ArcadeRuinsPresetTests-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    const fs::path userFolder = scratch / "Banks \xC3\xA9";      // a folder name beyond ASCII, on purpose

    S1PluginProcessor processor;
    s1plugin::PresetLibrary &library = processor.presetLibrary();

    // MARK: where the user's banks go
    {
        const juce::String path = S1SharedPresets::defaultUserDirectory().getFullPathName().replaceCharacter('\\', '/');
        check(path.endsWith("BadPackets/Arcade Ruins/Banks"), "the user's banks: <application data>/BadPackets/Arcade Ruins/Banks", 0);
        check(!path.contains("Group Containers") && !path.contains("group."), "not the Catalyst products' App Group container: the two libraries sit side by side", 0);
        check(library.userDirectory() == S1SharedPresets::defaultUserDirectory().getFullPathName().toStdString(), "and that is where a new plugin looks", 0);
        std::printf("note  here: %s\n", path.toRawUTF8());
        library.setUserDirectory(userFolder.u8string());
        check(!fs::exists(scratch), "making a plugin, and asking where its banks go, touches no disk", 0);
    }

    // MARK: the factory banks are the Mac app's files
    {
        int same = 0, total = 0;
        for (const char *bank : s1plugin::PresetLibrary::factoryBankOrder) {
            ++total;
            const std::optional<std::string> linked = library.factoryBankText(bank);
            const std::string onDisk = readFile(bankDirectory / (std::string(bank) + ".json"));
            if (linked && !onDisk.empty() && *linked == onDisk) { ++same; } else { std::printf("      %s differs from the repository's file\n", bank); }
        }
        check(same == 13 && total == 13, "the thirteen banks linked into the plugin are the repository's files, byte for byte", same);
    }

    // MARK: the host's programs are the Mac AUv3's factory presets
    {
        std::vector<std::string> expected;
        std::ifstream in(fixture);
        for (std::string line; std::getline(in, line);) {
            if (line.empty() || line[0] == '#') { continue; }
            expected.push_back(line.substr(line.find('\t') + 1));
        }
        check(expected.size() == 695 && processor.getNumPrograms() == 695, "695 programs, as the AUv3 has factory presets", processor.getNumPrograms());
        int sameName = 0, empty = 0;
        for (int program = 0; program < processor.getNumPrograms(); ++program) {
            const juce::String name = processor.getProgramName(program);
            if (name.trim().isEmpty()) { ++empty; }
            if (size_t(program) < expected.size() && name == juce::String::fromUTF8(expected[size_t(program)].c_str())) { ++sameName; }
            else if (sameName + 5 > program) { std::printf("      program %d is \"%s\" here\n", program, name.toRawUTF8()); }
        }
        check(sameName == 695, "each under the AUv3's name and number (the Swift-written fixture)", sameName);
        check(empty == 0, "none without a name (Steinberg's validator fails one)", empty);
        check(processor.getProgramName(-1).isNotEmpty() && processor.getProgramName(695).isNotEmpty(), "nor outside the list", 0);
    }

    // MARK: what a new instance shows
    {
        S1PluginProcessor fresh;
        check(fresh.getCurrentProgram() == 694 && fresh.getProgramName(fresh.getCurrentProgram()) == "User: Init", "a new instance plays Init and shows the list's \"User: Init\"", fresh.getCurrentProgram());
        const int different = differing(fresh, *library.factoryProgram(694));
        check(different == 0, "and that program IS the sound it starts with: choosing it changes nothing", different);
    }

    // MARK: a program chosen by the host
    {
        HostEars ears;
        listenToAll(processor, ears, true);
        const float tuningBefore = processor.currentState().tuningFrequencies[69];
        processor.hostParameter(S1Parameter::pitchbend).setValueNotifyingHost(0.9f);
        int wrong = 0, tried = 0;
        const auto started = std::chrono::steady_clock::now();
        for (int program = 3; program < 695; program += 23) {
            processor.setCurrentProgram(program);
            ++tried;
            const s1::Preset &preset = *library.factoryProgram(program);
            if (differing(processor, preset) != 0 || processor.getCurrentProgram() != program
                || processor.currentState().preset.name != preset.name) { ++wrong; std::printf("      program %d: %d parameters differ\n", program, differing(processor, preset)); }
        }
        const double each = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count() / tried;
        check(wrong == 0 && tried == 31, "31 programs across the banks: the 149 parameters are what the preset gives a new engine, and the sound has its name", tried);
        std::printf("note  a program change takes %.2f ms here\n", each);
        check(ears.values > 0 && ears.begun == 0 && ears.ended == 0, "reported to the host with no gesture: the host chose it", ears.begun);
        check(processor.hostParameter(S1Parameter::pitchbend).plainValue() == 8192.f, "the pitch wheel is back at its centre", processor.hostParameter(S1Parameter::pitchbend).plainValue());
        check(processor.currentState().tuningFrequencies[69] == tuningBefore, "and the tuning table is as it was (a preset's tuning is X3-5's)", processor.currentState().tuningFrequencies[69]);
        listenToAll(processor, ears, false);

        // In the kernel after a block — and equal to the engine's own way of loading the preset.
        processor.setCurrentProgram(412);
        processor.setPlayConfigDetails(0, 2, 44100.0, 512);
        processor.prepareToPlay(44100.0, 512);
        juce::AudioBuffer<float> buffer(2, 512);
        juce::MidiBuffer midi;
        processor.processBlock(buffer, midi);
        const s1plugin::PresetParameters expected = s1plugin::presetParameters(*library.factoryProgram(412));
        int kernelWrong = 0;
        for (int i = 0; i < S1PluginProcessor::kParameterCount; ++i) {
            if (i == int(S1Parameter::pitchbend)) { continue; }
            const float wanted = processor.hostParameter(S1Parameter(i)).getNormalisableRange().snapToLegalValue(expected[size_t(i)]);
            if (processor.engineValue(S1Parameter(i)) != wanted) { ++kernelWrong; }
        }
        check(kernelWrong == 0, "after a block the kernel plays program 412 as a new engine would", kernelWrong);

        // A session saved on a factory preset comes back showing that program.
        juce::MemoryBlock state;
        processor.getStateInformation(state);
        S1PluginProcessor reopened;
        reopened.setStateInformation(state.getData(), int(state.getSize()));
        check(reopened.getCurrentProgram() == 412 && reopened.getProgramName(reopened.getCurrentProgram()) == processor.getProgramName(412),
              "a session saved on program 412 reopens showing program 412", reopened.getCurrentProgram());
    }

    // MARK: a preset chosen by a person
    {
        HostEars ears;
        processor.setCurrentProgram(0);
        listenToAll(processor, ears, true);
        processor.loadPreset(*library.factoryProgram(200), true);
        check(ears.begun > 20 && ears.begun == ears.ended && ears.begun == ears.values, "loaded as an edit: every changed parameter inside its own gesture, so a host records it", ears.begun);
        check(differing(processor, *library.factoryProgram(200)) == 0 && processor.getCurrentProgram() == 200, "and it is the sound, and the program shown", processor.getCurrentProgram());
        listenToAll(processor, ears, false);
    }

    // MARK: the user's banks
    {
        // X3-5 (ADR-087): loading a preset applies its tuning and remembers it, as the Mac does,
        // so `tunings_v1.json` is on disk by now — in the folder ABOVE the banks. The banks' own
        // folder is still untouched, which is what this check is about.
        check(library.userBanks().banks.empty() && library.userBanks().problems.empty() && !fs::exists(userFolder), "no folder yet is no banks — and listing them makes none", 0);
        check(fs::exists(scratch / "tunings_v1.json"), "…and the tunings the presets chose are kept beside the banks' folder, not in it", 0);

        processor.setCurrentProgram(77);
        processor.hostParameter(S1Parameter::cutoff).setValueNotifyingHost(processor.hostParameter(S1Parameter::cutoff).convertTo0to1(1234.f));
        const juce::String name = juce::String::fromUTF8("Mine \xE2\x80\x94 \xC3\xA9tude");
        check(processor.saveCurrentPreset("My Bank", name).isEmpty(), "the sound saved into a new user bank", 0);
        check(fs::exists(userFolder / "My Bank.json") && !fs::exists(userFolder / "My Bank.json.writing"), "one file, <bank>.json, and nothing left beside it", 0);
        check(processor.currentState().preset.name == name.toStdString() && processor.currentState().preset.bank == "My Bank", "it is now the current preset", 0);
        check(processor.saveCurrentPreset("My Bank", "  ").isNotEmpty(), "a preset with no name is refused", 0);

        // What the standalone — another process, another library object — sees in the same folder.
        s1plugin::PresetLibrary elsewhere([](const std::string &) { return std::nullopt; }, [](S1Parameter) { return 0.0; });
        elsewhere.setUserDirectory(userFolder.u8string());
        const s1plugin::PresetLibrary::Listing seen = elsewhere.userBanks();
        check(seen.banks.size() == 1 && seen.banks[0].name == "My Bank" && seen.banks[0].presets.size() == 1 && seen.banks[0].presets[0].name == name.toStdString(),
              "another instance reading the folder finds the bank and the preset, name and all", double(seen.banks.size()));

        // The file is the Mac app's bank format: a JSON array of presets, the bank's name in each.
        const nlohmann::json file = nlohmann::json::parse(readFile(userFolder / "My Bank.json"), nullptr, false);
        check(file.is_array() && file.size() == 1 && file[0].value("bank", "") == "My Bank" && file[0].value("position", -1) == 0 && file[0].contains("seqPatternNote"),
              "the file is a bank as the Mac app writes one: an array of presets", double(file.size()));

        // Loaded again, it is the sound that was saved.
        const s1plugin::PresetParameters saved = [&] { s1plugin::PresetParameters v {}; for (int i = 0; i < S1PluginProcessor::kParameterCount; ++i) { v[size_t(i)] = processor.hostParameter(S1Parameter(i)).plainValue(); } return v; }();
        processor.setCurrentProgram(5);
        processor.loadPreset(library.userBanks().banks[0].presets[0], true);
        int changed = 0;
        for (int i = 0; i < S1PluginProcessor::kParameterCount; ++i) {
            if (processor.hostParameter(S1Parameter(i)).plainValue() != saved[size_t(i)]) {
                if (++changed <= 6) { std::printf("      %s: saved %.7g, loaded %.7g\n", s1plugin::parameterID(i), double(saved[size_t(i)]), double(processor.hostParameter(S1Parameter(i)).plainValue())); }
            }
        }
        check(changed == 0, "saved, then loaded from the file: all 150 parameters the same numbers", changed);
        check(std::fabs(processor.hostParameter(S1Parameter::cutoff).plainValue() - 1234.f) < 0.01f, "the cutoff that was set before saving among them", processor.hostParameter(S1Parameter::cutoff).plainValue());

        // Saved again under the same name: replaced, not doubled. Under another: added.
        check(processor.saveCurrentPreset("My Bank", name).isEmpty() && library.userBanks().banks[0].presets.size() == 1, "saved again under its name: replaced, not doubled", double(library.userBanks().banks[0].presets.size()));
        check(processor.saveCurrentPreset("My Bank", "Second").isEmpty() && library.userBanks().banks[0].presets.size() == 2, "under another name: added", double(library.userBanks().banks[0].presets.size()));
        const std::string uid = library.userBanks().banks[0].presets[1].uid;
        check(library.removePreset("My Bank", uid).empty() && library.userBanks().banks[0].presets.size() == 1, "and removed by its uid", double(library.userBanks().banks[0].presets.size()));

        // The factory banks cannot be written: a user bank of the same name is a file in the user's folder.
        check(processor.saveCurrentPreset("BankA", "In my BankA").isEmpty() && fs::exists(userFolder / "BankA.json") && processor.getNumPrograms() == 695
                  && library.factoryBanks()[0].presets.size() == 41,
              "saving into \"BankA\" makes a USER bank of that name; the factory's BankA and the 695 programs are untouched", processor.getNumPrograms());

        // What is not a bank is left out, by name, and the rest still loads.
        { std::ofstream(userFolder / "garbage.json") << "{ this is not json"; }
        { std::ofstream(userFolder / "number.json") << "42"; }
        { std::ofstream(userFolder / "notes.txt") << "not a bank at all"; }
        { std::ofstream(userFolder / "single.json") << library.factoryProgram(9)->toJSON().dump(); }
        const s1plugin::PresetLibrary::Listing listing = library.userBanks();
        check(listing.banks.size() == 3 && listing.problems.size() == 2, "two files that are not banks are named as problems; the three that are still load (a single exported preset is a bank of one)", double(listing.problems.size()));
        for (const std::string &problem : listing.problems) { std::printf("      %s\n", problem.c_str()); }

        // Names a filesystem refuses, here or on the next machine.
        check(s1plugin::PresetLibrary::fileNameFor("A/B\\C:D*E?F\"G<H>I|J") == "A_B_C_D_E_F_G_H_I_J", "a bank's name as a file's: separators and wildcards replaced", 0);
        check(s1plugin::PresetLibrary::fileNameFor("  Pads.  ") == "Pads" && s1plugin::PresetLibrary::fileNameFor("con") == "_con" && s1plugin::PresetLibrary::fileNameFor(" . ").empty(),
              "trailing dots and spaces dropped, Windows' device names avoided, nothing left is no name", 0);
        check(processor.saveCurrentPreset("Live: Set/1", "Lead").isEmpty() && fs::exists(userFolder / "Live_ Set_1.json"), "and a bank so named is saved under the safe one", 0);
        check(processor.saveCurrentPreset(" . ", "Lead").isNotEmpty(), "a bank with no usable name is refused", 0);
    }

    std::error_code ignored;
    fs::remove_all(scratch, ignored);
    std::printf(failures == 0 ? "\nall passed\n" : "\n%d FAILED\n", failures);
    return failures == 0 ? 0 : 1;
}
