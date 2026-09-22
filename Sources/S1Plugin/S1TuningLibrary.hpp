//
//  S1TuningLibrary.hpp
//  Arcade Ruins
//
//  X3-5 (ADR-087): the tunings, with no JUCE in it — the model the Tunings card is a view of, so
//  every operation can be driven and measured with no window (`PluginTuningsTests`).
//
//  A port of the Mac's `Tunings` (Sources/SynthOneCore/Tunings/Model/Tunings.swift) and its
//  `Tuning` / `TuningBank`, operation for operation: three banks — Curated, User and "Hexanies
//  With Proportional Triads" — the sort that strips 12 ET and puts it back at row 0 of the two
//  banks that carry it, selection that persists, a user bank you can add to, reorder and delete
//  from, and Scala import. The 194 factory tunings are NOT rebuilt here: they are already data in
//  the engine (`s1::factoryTunings()`, generated from the Swift, ADR-068).
//
//  The file it keeps is `tunings_v1.json` beside the banks, in the Mac app's own format (an array
//  of banks), so a tunings file written by either product opens in the other.
//
//  WHAT PLAYS is a master set turned into 128 frequencies by the engine's own `S1TuningTable`
//  (ADR-068), at the A4 the caller gives. Nothing here touches a kernel or a parameter: the
//  processor asks for the table and delivers it (ADR-087 §A4).
//
#pragma once

#include <array>
#include <optional>
#include <random>
#include <string>
#include <vector>

#include "S1Preset.hpp"
#include "S1TuningTable.hpp"

namespace s1plugin {

/// `Tuning`. The property names are the JSON keys, as upstream insists.
struct TuningEntry {
    std::string name = "12 ET";
    std::vector<double> masterSet;          ///< `Tuning.defaultMasterSet` when it is 12 ET
    int order = 0;
    int userOrder = -1;

    int npo() const { return int(masterSet.size()); }
    /// `nameForCell`: the note count padded to three, then the name (" 12 ET", "19 Grady…").
    std::string nameForCell() const;
    /// `Tuning.encode`: every ratio octave-reduced to a log2 fraction, sorted, "%.12f_" each.
    /// Two tunings are the same tuning when name + encoding match.
    std::string encoding() const;
};

/// `TuningBank`.
struct TuningBankEntry {
    std::string name = "Curated";
    bool isEditable = false;
    std::vector<TuningEntry> tunings;
    int selectedTuningIndex = 0;
    int order = 0;
};

class TuningLibrary {
public:
    /// `Tunings.bundleBankIndex` / `userBankIndex` / `hexanyTriadIndex`.
    static constexpr int kCuratedBank = 0, kUserBank = 1, kHexanyTriadBank = 2;
    /// `Tunings.tuningFilenameV1`, and the Mac app's own file name.
    static constexpr const char *kFileName = "tunings_v1.json";
    /// `Tuning.defaultName` and `defaultMasterSet`.
    static const char *defaultTuningName();
    static const std::vector<double> &defaultMasterSet();
    /// A4 440 gives `S1TuningTable`'s own middle C, 261.6255653006. TuneUp's arithmetic, inverted
    /// (`Tunings+TuneUp`: frequencyA4 = frequencyMiddleC * 2^((69-60)/12)).
    static double middleCForA4(double frequencyA4);

    /// Nothing is read or written until `load`.
    explicit TuningLibrary(std::string utf8Directory = {});

    void setDirectory(const std::string &utf8Path);
    const std::string &directory() const { return folder; }
    /// `loadTunings`: the file if there is one and it holds all three banks, else the factory
    /// tunings; then the sort, and the selection the file remembered.
    void load();
    bool isLoaded() const { return loaded; }
    /// Why the file was not used, for the status bar. Empty when it was, or when there was none.
    const std::string &problem() const { return lastProblem; }

    // MARK: the lists
    const std::vector<TuningBankEntry> &banks() const { return tuningBanks; }
    int selectedBankIndex() const { return bankIndex; }
    int selectedTuningIndex() const;
    /// The tunings of the chosen bank, in the order the table shows them.
    const std::vector<TuningEntry> &tunings() const;
    std::string selectedBankName() const;
    /// Only the User bank can be added to, reordered or deleted from.
    bool selectedBankIsEditable() const { return bankIndex == kUserBank; }

    // MARK: what is playing
    const std::string &tuningName() const { return playingName; }
    const std::vector<double> &masterSet() const { return playingMasterSet; }
    /// `npo` of what is playing; 12 for 12 ET.
    int notesPerOctave() const { return int(playingMasterSet.size()); }
    /// The 128 frequencies the kernel plays, for the master set that is chosen and this A4.
    /// `S1TuningTable::tuningTableFromFrequencies`, then the reference moved to A4.
    std::array<double, S1TuningTable::midiNoteCount> frequencies(double frequencyA4) const;
    /// What a preset saves: the name and the master set that are playing (`Tunings.getTuning`).
    std::pair<std::string, std::vector<double>> currentTuning() const;

    // MARK: the operations. Each one writes the file. Never the audio thread.
    void selectBank(int row);
    void selectTuning(int row);
    /// `resetTuning`: the Curated bank, row 0, which is 12 ET. A4 is the caller's to reset.
    void resetTuning();
    /// `randomTuning`: another tuning of the chosen bank.
    void randomTuning();
    /// `setTuning`: makes this the tuning that plays, adding it to the User bank when the bank
    /// does not already hold one with the same name AND the same ratios. False: no master set.
    /// This is what a preset's own tuning arrives through.
    bool setTuning(const std::string &name, const std::vector<double> &inputMasterSet);
    /// `removeUserTuning`: only from the User bank, and never row 0 (12 ET).
    bool removeUserTuning(int index);
    /// `reorderUserBank`.
    bool reorderUserBank(int from, int to);
    /// A `.scl` file's text, through the engine's own parser (`s1::frequenciesFromScalaString`).
    /// The file's name without its extension becomes the tuning's name. Empty on success.
    std::string importScala(const std::string &fileName, const std::string &text);

private:
    enum class Sort { userOrder, npo, name };
    void loadFactoryTunings();
    void readFile();
    void writeFile() const;
    void sortTunings(TuningBankEntry &, Sort);
    void adoptSelection();                    ///< name and master set from the chosen row
    TuningBankEntry &bank() { return tuningBanks[size_t(bankIndex)]; }
    const TuningBankEntry &bank() const { return tuningBanks[size_t(bankIndex)]; }

    std::string folder;
    int chosenBankFromFile = -1;      ///< `isSelected` in the file: ours, not the Mac's
    bool loaded = false;
    std::string lastProblem;
    std::vector<TuningBankEntry> tuningBanks;
    int bankIndex = kCuratedBank;
    std::string playingName = "12 ET";
    std::vector<double> playingMasterSet;
    mutable std::mt19937 dice { std::random_device {}() };
};

} // namespace s1plugin
