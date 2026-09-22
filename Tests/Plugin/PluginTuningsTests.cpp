// X3-5 (ADR-087): the tunings — the model with no window (three banks, the sort that puts 12 ET
// at row 0, selection that persists, the user bank, Scala import), the 128 frequencies it makes,
// A4 moving the whole table, and the acceptance: a PRESET that carries a tuning plays in it,
// measured from the rendered audio and not just from the table.
//
// Every test works in a folder of its own under the system's temporary folder. The real one is
// the owner's; nothing here may read it, let alone write in it.
//
//   argv[1]  Sources/SynthOneCore/Presets/Data   the Mac app's bank files
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "S1PluginProcessor.h"
#include "S1FactoryTunings.hpp"
#include "S1TuningLibrary.hpp"

namespace fs = std::filesystem;

namespace {

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.8g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

constexpr double kSampleRate = 44100.0;

/// The pitch of a held note, by autocorrelation — PluginRenderTests' method, with the octave
/// error guarded against: the highest peak is often at a MULTIPLE of the true period (the note
/// correlates with itself an octave down just as well), so the answer is the SHORTEST lag whose
/// peak is nearly as tall as the best. Without that, two notes of the same pair came back 1,200
/// cents apart and the interval was nonsense.
double pitchOf(const std::vector<float> &left, double lowest, double highest) {
    // Late in the note, not at its start: a preset may glide into tune (ADR-013's sweep, and
    // portamento), and the first tenth of a second is not the pitch the key was given.
    const size_t from = std::min(left.size(), size_t(0.60 * kSampleRate)), to = std::min(left.size(), size_t(1.00 * kSampleRate));
    if (to <= from + 4) { return 0; }
    const size_t shortest = size_t(kSampleRate / highest);
    std::vector<double> score(size_t(kSampleRate / lowest) + 2, 0.0);
    double best = -1e30;
    for (size_t lag = shortest; lag < score.size(); ++lag) {
        double sum = 0;
        for (size_t i = from; i + lag < to; ++i) { sum += double(left[i]) * double(left[i + lag]); }
        score[lag] = sum / double(to - from - lag);
        best = std::max(best, score[lag]);
    }
    if (best <= 0) { return 0; }
    size_t bestLag = 0;
    for (size_t lag = shortest + 1; lag + 1 < score.size(); ++lag) {
        const bool isPeak = score[lag] >= score[lag - 1] && score[lag] >= score[lag + 1];
        if (isPeak && score[lag] >= 0.9 * best) { bestLag = lag; break; }
    }
    if (bestLag == 0 || bestLag + 1 >= score.size()) { return 0; }
    const double a = score[bestLag - 1], b = score[bestLag], c = score[bestLag + 1];
    const double shift = (a - c) / (2 * (a - 2 * b + c));
    return kSampleRate / (double(bestLag) + shift);
}

/// Holds one note and gives back the left channel.
std::vector<float> play(S1PluginProcessor &processor, int note, double seconds) {
    const int block = 512;
    juce::AudioBuffer<float> audio(2, block);
    std::vector<float> left;
    const int blocks = int(seconds * kSampleRate) / block;
    for (int b = 0; b < blocks; ++b) {
        juce::MidiBuffer midi;
        if (b == 0) { midi.addEvent(juce::MidiMessage::noteOn(1, note, 0.9f), 0); }
        audio.clear();
        processor.processBlock(audio, midi);
        for (int i = 0; i < block; ++i) { left.push_back(audio.getSample(0, i)); }
    }
    juce::MidiBuffer off;
    off.addEvent(juce::MidiMessage::noteOff(1, note), 0);
    audio.clear();
    processor.processBlock(audio, off);
    for (int b = 0; b < 40; ++b) { juce::MidiBuffer none; audio.clear(); processor.processBlock(audio, none); }
    return left;
}

/// One empty block, so a table set on this thread reaches the kernel.
void settle(S1PluginProcessor &processor) {
    juce::AudioBuffer<float> audio(2, 512);
    juce::MidiBuffer none;
    audio.clear();
    processor.processBlock(audio, none);
}

double cents(double a, double b) { return 1200.0 * std::log2(a / b); }

std::string readFile(const fs::path &path) {
    std::ifstream in(path, std::ios::binary);
    std::ostringstream text;
    text << in.rdbuf();
    return text.str();
}

/// The factory presets that carry a tuning of their own with a note count other than 12.
std::vector<s1::Preset> microtonalPresets(s1plugin::PresetLibrary &library) {
    std::vector<s1::Preset> found;
    for (int program = 0; program < library.factoryProgramCount(); ++program) {
        const s1::Preset *preset = library.factoryProgram(program);
        if (preset != nullptr && preset->tuningMasterSet && preset->tuningMasterSet->size() != 12) { found.push_back(*preset); }
    }
    return found;
}

} // namespace

int main(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc != 2) { std::printf("usage: PluginTuningsTests <bank dir>\n"); return 2; }
    const fs::path bankDirectory = argv[1];

    const fs::path scratch = fs::temp_directory_path() / ("ArcadeRuinsTuningTests-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    const fs::path userFolder = scratch / "Banks";

    S1PluginProcessor processor;
    processor.presetLibrary().setUserDirectory(userFolder.u8string());
    processor.setPlayConfigDetails(0, 2, kSampleRate, 512);
    processor.prepareToPlay(kSampleRate, 512);

    // MARK: the three banks, as the Mac builds them
    {
        check(!fs::exists(scratch), "making a plugin touches no disk", 0);
        s1plugin::TuningLibrary &library = processor.tuningLibrary();
        check(library.banks().size() == 3, "three banks: Curated, User, and the hexany triads", double(library.banks().size()));
        check(library.banks()[0].name == "Curated" && library.banks()[1].name == "User"
                  && library.banks()[2].name == "Hexanies With Proportional Triads",
              "under the Mac's own names, in its own order", 0);
        check(library.problem().empty(), "nothing wrong with the folder", 0);

        // The tunings file sits ABOVE the banks: PresetLibrary reads every .json beside them.
        check(processor.tuningLibrary().directory() == scratch.u8string(), "the tunings live in the folder above the banks", 0);

        const size_t curated = library.banks()[0].tunings.size(), hexany = library.banks()[2].tunings.size();
        check(curated + hexany == s1::factoryTunings().size() + 1, "every shipped tuning is in a bank, and 12 ET is put in besides", double(curated + hexany));
        check(library.banks()[0].tunings[0].name == "12 ET" && library.banks()[1].tunings[0].name == "12 ET",
              "12 ET is row 0 of Curated and of User", 0);
        check(library.banks()[1].tunings.size() == 1, "and the User bank holds nothing else yet", double(library.banks()[1].tunings.size()));
        const bool hexanyHasNo12 = std::none_of(library.banks()[2].tunings.begin(), library.banks()[2].tunings.end(),
                                                [](const s1plugin::TuningEntry &t) { return t.name == "12 ET"; });
        check(hexanyHasNo12, "the hexany bank is left as it is: no 12 ET put in", double(hexany));
        check(library.tuningName() == "12 ET" && library.notesPerOctave() == 12, "a new instance plays 12 ET", library.notesPerOctave());
    }

    // MARK: a tuning's two derived strings, which decide what is the same tuning
    {
        s1plugin::TuningEntry twelve;
        twelve.masterSet = s1plugin::TuningLibrary::defaultMasterSet();
        check(twelve.nameForCell() == " 12 12 ET", "nameForCell pads the note count to three: \"" + twelve.nameForCell() + "\"", 0);
        s1plugin::TuningEntry shuffled = twelve;
        std::reverse(shuffled.masterSet.begin(), shuffled.masterSet.end());
        check(shuffled.encoding() == twelve.encoding(), "the same ratios in another order encode the same", 0);
        s1plugin::TuningEntry doubled = twelve;
        for (double &r : doubled.masterSet) { r *= 2; }
        check(doubled.encoding() == twelve.encoding(), "and so do the same ratios an octave up", 0);
        s1plugin::TuningEntry other;
        other.masterSet = { 1.0, 1.5 };
        check(other.encoding() != twelve.encoding(), "a different scale does not", 0);
    }

    // MARK: the 128 frequencies, and A4
    {
        s1plugin::TuningLibrary &library = processor.tuningLibrary();
        const std::array<double, 128> table = library.frequencies(440.0);
        check(std::fabs(table[69] - 440.0) < 1e-9, "12 ET at A4 440: note 69 is 440 Hz", table[69]);
        check(std::fabs(table[60] - 261.6255653006) < 1e-6, "…and middle C is 261.6255653006", table[60]);
        check(std::fabs(table[81] - 880.0) < 1e-6, "…and the octave above A4 is 880", table[81]);
        check(std::fabs(cents(table[61], table[60]) - 100.0) < 1e-6, "…a semitone is 100 cents", cents(table[61], table[60]));

        const std::array<double, 128> at432 = library.frequencies(432.0);
        check(std::fabs(at432[69] - 432.0) < 1e-9, "A4 432 puts note 69 at 432 Hz", at432[69]);
        check(std::fabs(cents(at432[60], table[60]) - cents(432.0, 440.0)) < 1e-9,
              "…and moves the WHOLE table by the same interval, not just the As", cents(at432[60], table[60]));
    }

    // MARK: choosing a tuning, and remembering it
    {
        s1plugin::TuningLibrary &library = processor.tuningLibrary();
        library.selectBank(s1plugin::TuningLibrary::kHexanyTriadBank);
        library.selectTuning(3);
        const std::string chosen = library.tuningName();
        const int npo = library.notesPerOctave();
        check(!chosen.empty() && npo != 12, "a hexany chosen: " + chosen, npo);

        s1plugin::TuningLibrary reopened(scratch.u8string());
        reopened.load();
        check(reopened.selectedBankIndex() == s1plugin::TuningLibrary::kHexanyTriadBank && reopened.tuningName() == chosen,
              "a second library on the same folder opens on it", reopened.notesPerOctave());
        check(fs::exists(scratch / "tunings_v1.json"), "…because it is written beside the banks' folder", 0);
        check(!fs::exists(userFolder / "tunings_v1.json"), "…and NOT in it, where it would be read as a bank", 0);
        library.resetTuning();
        check(library.tuningName() == "12 ET" && library.selectedBankIndex() == 0, "Reset goes back to 12 ET in the Curated bank", 0);
    }

    // MARK: the user bank — adding, refusing a duplicate, deleting, reordering
    {
        s1plugin::TuningLibrary &library = processor.tuningLibrary();
        const std::vector<double> bagpipes = { 1.0, 1.125, 1.25, 1.3333333333333333, 1.5, 1.6875, 1.875 };
        check(library.setTuning("Test Scale", bagpipes), "a tuning set", 0);
        check(library.selectedBankIndex() == s1plugin::TuningLibrary::kUserBank, "it goes into the User bank and is chosen", double(library.selectedTuningIndex()));
        check(library.banks()[1].tunings.size() == 2, "the User bank holds 12 ET and it", double(library.banks()[1].tunings.size()));
        check(library.tuningName() == "Test Scale" && library.notesPerOctave() == 7, "and it is what plays", library.notesPerOctave());

        library.setTuning("Test Scale", bagpipes);
        check(library.banks()[1].tunings.size() == 2, "setting the same tuning again adds nothing", double(library.banks()[1].tunings.size()));
        library.setTuning("Test Scale", { 1.0, 1.5 });
        check(library.banks()[1].tunings.size() == 3, "…but the same NAME with other ratios is another tuning", double(library.banks()[1].tunings.size()));

        check(!library.removeUserTuning(0), "12 ET cannot be deleted from the User bank", 0);
        check(library.removeUserTuning(2), "another tuning can", double(library.banks()[1].tunings.size()));
        check(library.banks()[1].tunings.size() == 2, "…and it is gone", double(library.banks()[1].tunings.size()));

        library.setTuning("Second Scale", { 1.0, 1.2, 1.4 });
        const std::string first = library.banks()[1].tunings[1].name, second = library.banks()[1].tunings[2].name;
        check(library.reorderUserBank(1, 2), "the user bank reorders", 0);
        check(library.banks()[1].tunings[1].name == second && library.banks()[1].tunings[2].name == first, "…the two swapped", 0);
        check(library.banks()[1].tunings[0].name == "12 ET", "…and 12 ET is still row 0", 0);
    }

    // MARK: Scala import, through the engine's own parser
    {
        s1plugin::TuningLibrary &library = processor.tuningLibrary();
        const std::string scala = "! meanquar.scl\n!\n1/4-comma meantone\n 7\n!\n 76.04900\n 193.15686\n 310.26471\n"
                                  " 5/4\n 696.57843\n 772.62743\n 889.73529\n 2/1\n";
        const size_t before = library.banks()[1].tunings.size();
        check(library.importScala("meanquar.scl", scala).empty(), "a .scl file is read", 0);
        check(library.banks()[1].tunings.size() == before + 1, "…into the User bank", double(library.banks()[1].tunings.size()));
        check(library.tuningName() == "meanquar", "…named after the file, and playing", double(library.notesPerOctave()));
        check(!library.importScala("rubbish.scl", "this is not a scale").empty(), "what is not a scale is refused", 0);
        library.resetTuning();
    }

    // MARK: THE ACCEPTANCE — a preset that carries a tuning plays in it
    const std::vector<s1::Preset> microtonal = microtonalPresets(processor.presetLibrary());
    {
        check(microtonal.size() == 11, "eleven factory presets carry a tuning that is not twelve notes", double(microtonal.size()));
        int inTune = 0, namedRight = 0;
        for (const s1::Preset &preset : microtonal) {
            processor.loadPreset(preset, false);
            settle(processor);
            if (processor.tuningLibrary().notesPerOctave() == int(preset.tuningMasterSet->size())) { ++inTune; }
            if (processor.tuningLibrary().tuningName() == preset.tuningName.value_or("")) { ++namedRight; }
        }
        check(inTune == int(microtonal.size()), "each one leaves the instrument in a tuning of its own note count", inTune);
        check(namedRight == int(microtonal.size()), "…under the name the preset gives it", namedRight);

        // And the kernel really has it: the table the engine plays equals the library's.
        const s1::Preset &last = microtonal.back();
        processor.loadPreset(last, false);
        settle(processor);
        const std::array<double, 128> expected = processor.tuningLibrary().frequencies(double(processor.hostParameter(S1Parameter::frequencyA4).plainValue()));
        int same = 0;
        for (int note = 0; note < 128; ++note) {
            if (std::fabs(double(processor.engineTuningFrequency(note)) - expected[size_t(note)]) < 0.01) { ++same; }
        }
        check(same == 128, "all 128 of the kernel's frequencies are the tuning's, not 12 ET's", same);

        // Back to a 12 ET preset and the instrument is in 12 ET again.
        processor.loadPreset(processor.presetLibrary().initialPreset(), false);
        settle(processor);
        check(processor.tuningLibrary().notesPerOctave() == 12
                  && std::fabs(double(processor.engineTuningFrequency(69)) - 440.0) < 0.01,
              "a preset with no tuning of its own puts 12 ET back", double(processor.engineTuningFrequency(69)));
    }

    // MARK: …and it is HEARD, not just tabled
    //
    // What a tuning changes is the INTERVAL between two keys, and an interval is what can be
    // measured without knowing anything else about the sound: the shipped Init plays an octave
    // below the key it is given (PluginRenderTests measures note 69 at 220 Hz), and a preset may
    // transpose or detune as it likes. Absolute pitches would be measuring the preset, not the
    // tuning.
    {
        const s1::Preset init = processor.presetLibrary().initialPreset();
        processor.loadPreset(init, false);
        settle(processor);
        const double lowET = pitchOf(play(processor, 60, 1.2), 60.0, 900.0);
        const double highET = pitchOf(play(processor, 61, 1.2), 60.0, 900.0);
        std::printf("note  12 ET: key 60 at %.3f Hz, key 61 at %.3f Hz\n", lowET, highET);
        check(lowET > 0 && highET > 0, "two keys sounded in 12 ET", lowET);
        check(std::fabs(cents(highET, lowET) - 100.0) < 8.0, "in 12 ET, one key up is a hundred cents", cents(highET, lowET));

        // The same two keys in the same sound, with a microtonal scale put under it.
        //
        // The SCALE is applied here rather than a preset carrying it, on purpose: a preset is
        // free to run two detuned oscillators a fifth apart, and "JEC Digiharp" does — its two
        // keys measure 292 cents where its scale says 315, because what is measured is the blend,
        // not the tuning. That the ELEVEN presets each put their own scale in the kernel is
        // checked exactly, above, against all 128 frequencies. This checks that the scale in the
        // kernel is the scale that is heard.
        const s1::Preset &odd = microtonal.front();
        processor.tuningLibrary().setTuning(odd.tuningName.value_or("odd"), *odd.tuningMasterSet);
        processor.retune();
        settle(processor);
        const std::array<double, 128> table = processor.tuningLibrary().frequencies(double(processor.hostParameter(S1Parameter::frequencyA4).plainValue()));
        const double wanted = cents(table[61], table[60]);
        const double low = pitchOf(play(processor, 60, 1.2), 60.0, 900.0);
        const double high = pitchOf(play(processor, 61, 1.2), 60.0, 900.0);
        const double heard = cents(high, low);
        std::printf("note  %s: key 60 at %.3f Hz (table %.3f), key 61 at %.3f Hz (table %.3f)\n",
                    processor.tuningLibrary().tuningName().c_str(), low, table[60], high, table[61]);
        check(std::fabs(heard - wanted) < 10.0,
              "with \"" + processor.tuningLibrary().tuningName() + "\" under it ("
                  + std::to_string(processor.tuningLibrary().notesPerOctave())
                  + " notes to the octave) the two keys are " + std::to_string(int(wanted)) + " cents apart, as its scale says",
              heard);
        check(std::fabs(heard - 100.0) > 25.0, "…which is audibly not the semitone 12 ET would give", std::fabs(heard - 100.0));
        check(std::fabs(cents(low, table[60])) < 10.0, "…and each key is at the frequency the table gives it", cents(low, table[60]));
        processor.loadPreset(init, false);
        settle(processor);
    }

    // MARK: the switch, and what a saved sound carries
    {
        processor.loadPreset(processor.presetLibrary().initialPreset(), false);
        settle(processor);
        processor.setSavesTuningWithPreset(false);
        processor.loadPreset(microtonal.front(), false);
        settle(processor);
        check(processor.tuningLibrary().notesPerOctave() == 12,
              "with \"save the tuning with the preset\" off, a preset's tuning is left alone", processor.tuningLibrary().notesPerOctave());
        processor.setSavesTuningWithPreset(true);

        processor.tuningLibrary().setTuning("Saved With It", { 1.0, 1.25, 1.5 });
        processor.retune();
        settle(processor);
        const s1::Preset captured = processor.currentState().capturedPreset();
        check(captured.tuningName.value_or("") == "Saved With It", "a sound saved now names the tuning it is in", 0);
        check(captured.tuningMasterSet && captured.tuningMasterSet->size() == 3, "…and carries its ratios", double(captured.tuningMasterSet ? captured.tuningMasterSet->size() : 0));

        // Round trip: saved, loaded into a second instance, same tuning.
        S1PluginProcessor second;
        second.presetLibrary().setUserDirectory((scratch / "Banks2").u8string());
        second.setPlayConfigDetails(0, 2, kSampleRate, 512);
        second.prepareToPlay(kSampleRate, 512);
        second.loadPreset(captured, false);
        settle(second);
        check(second.tuningLibrary().notesPerOctave() == 3 && second.tuningLibrary().tuningName() == "Saved With It",
              "and another instance loading it plays in that tuning", second.tuningLibrary().notesPerOctave());
    }

    // MARK: A4 — inert upstream, live here (ADR-087)
    {
        processor.loadPreset(processor.presetLibrary().initialPreset(), false);
        settle(processor);
        S1HostParameter &a4 = processor.hostParameter(S1Parameter::frequencyA4);
        a4.setPlainValueFromEngine(432.0f);
        processor.retune();
        settle(processor);
        check(std::fabs(double(processor.engineTuningFrequency(69)) - 432.0) < 0.01, "A4 at 432 retunes the kernel", double(processor.engineTuningFrequency(69)));
        const double at432 = pitchOf(play(processor, 69, 1.2), 60.0, 900.0);
        a4.setPlainValueFromEngine(440.0f);
        processor.retune();
        settle(processor);
        const double at440 = pitchOf(play(processor, 69, 1.2), 60.0, 900.0);
        std::printf("note  A4: key 69 at %.3f Hz with A4 432, %.3f Hz with A4 440\n", at432, at440);
        check(std::fabs(cents(at432, at440) - cents(432.0, 440.0)) < 8.0,
              "…and the SAME key is heard 31.77 cents flatter at A4 432 than at 440", cents(at432, at440));

        // The five factory presets that ask for something other than 440.
        int nonDefault = 0;
        for (int program = 0; program < processor.presetLibrary().factoryProgramCount(); ++program) {
            const s1::Preset *preset = processor.presetLibrary().factoryProgram(program);
            if (preset != nullptr && preset->frequencyA4 != 440.0) { ++nonDefault; }
        }
        check(nonDefault == 5, "five of the 695 factory presets ask for an A4 that is not 440", nonDefault);
    }

    processor.releaseResources();
    std::error_code error;
    fs::remove_all(scratch, error);
    std::printf("\n%s: PluginTuningsTests\n", failures == 0 ? "PASSED" : "FAILED");
    return failures == 0 ? 0 : 1;
}
