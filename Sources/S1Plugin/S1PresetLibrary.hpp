//
//  S1PresetLibrary.hpp
//  Arcade Ruins
//
//  X2-9 (ADR-080): the presets a plugin has without an interface of its own. No JUCE in here.
//
//  FACTORY banks are the Mac app's thirteen bank files, byte for byte, handed in by whoever
//  links them (the plugin: JUCE binary data). Read-only by construction: they are part of the
//  binary. In S1FactoryPresets.swift's order — which is the order of the numbers a host stores —
//  and with its names, "Bank: Preset": program N here is factory preset N in the Mac AUv3.
//
//  USER banks are files in a folder: <name>.json, a JSON array of presets — the Mac app's bank
//  file format, so a bank exported from either product opens in the other. The folder is given
//  to the library; nothing here decides where it is, and nothing touches the disk until asked.
//  Every instance of every format on the machine reads the same folder, so a bank saved in the
//  VST3 is there for the standalone: the folder is read again at every listing, files are
//  replaced whole (written beside, then renamed), and the last writer wins.
//
#pragma once

#include <array>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "S1Parameter.h"
#include "S1Preset.hpp"

namespace s1plugin {

/// The 150 values a preset gives a new engine — see `presetParameters`.
using PresetParameters = std::array<float, S1Parameter::S1ParameterCount>;

/// What a preset makes of the 150 parameters: applied, in upstream's order, to a kernel made for
/// the purpose (ADR-076: the order decides some values, and so does what was there before — a
/// new kernel is the one reproducible "before"). Allocates; never for the audio thread.
PresetParameters presetParameters(const s1::Preset &preset);

struct PresetBank {
    std::string name;                  ///< the file's name without ".json"
    std::vector<s1::Preset> presets;
};

class PresetLibrary {
public:
    /// A factory bank's JSON text by its name ("BankA"), or nothing.
    using FactorySource = std::function<std::optional<std::string>(const std::string &bankName)>;

    /// S1FactoryPresets.bankOrder. Never reordered, never inserted into: a host stores numbers.
    static const std::array<const char *, 13> factoryBankOrder;

    PresetLibrary(FactorySource source, s1::PresetDefaults defaults);

    /// A factory bank file's text as it was linked in, for a checksum against the repository's.
    std::optional<std::string> factoryBankText(const std::string &bankName) const { return source ? source(bankName) : std::nullopt; }

    /// The sound an instrument starts with: the shipped "Init", the one preset of the factory
    /// bank "User" — the Mac app's Init and one of the twenty goldens — read from that small file
    /// alone (the other banks are not parsed for it). The preset model's bare defaults,
    /// `s1::Preset()`, are NOT it: they differ in 28 parameters (bend range 0, compressors at
    /// their stops, tempo sync on). Falls back to them only if the bank is missing.
    s1::Preset initialPreset() const;

    // MARK: factory — parsed on first use, then fixed for the life of the library
    const std::vector<PresetBank> &factoryBanks();
    int factoryProgramCount();
    /// "Bank: Preset" for program 0 … count-1, never empty; nothing outside that range.
    std::string factoryProgramName(int program);
    const s1::Preset *factoryProgram(int program);

    // MARK: user — the folder is read at every call
    void setUserDirectory(const std::string &utf8Path);
    const std::string &userDirectory() const { return directory; }
    struct Listing {
        std::vector<PresetBank> banks;          ///< by name
        std::vector<std::string> problems;      ///< "<file>: <why it was left out>"
    };
    Listing userBanks() const;

    /// Puts `preset` in the user bank `bankName` — replacing the preset with the same uid, or the
    /// same name, else added at the end — and writes the bank. Empty on success, else why not.
    std::string savePreset(const std::string &bankName, s1::Preset preset) const;
    /// Removes the preset with this uid; an empty bank's file stays, as an empty bank.
    std::string removePreset(const std::string &bankName, const std::string &uid) const;
    std::string writeBank(const PresetBank &bank) const;
    /// X3-4: takes the bank's file away. A bank that is not there is not a failure.
    std::string removeBank(const std::string &bankName) const;

    /// What a preset's JSON leaves out takes from these — for whoever parses a file the browser
    /// was given (X3-4). Fixed for the life of the library.
    const s1::PresetDefaults &presetDefaults() const { return defaults; }

    /// A bank's name as a file's: nothing a filesystem here or on the next machine refuses.
    /// Empty when nothing usable is left.
    static std::string fileNameFor(const std::string &bankName);

private:
    FactorySource source;
    s1::PresetDefaults defaults;
    std::string directory;
    std::mutex factoryLock;            ///< the first use may come from any thread
    bool factoryLoaded = false;
    std::vector<PresetBank> factory;
    struct Program { int bank, preset; };
    std::vector<Program> programs;
    void loadFactory();
};

} // namespace s1plugin
