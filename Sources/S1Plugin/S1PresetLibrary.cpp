//
//  S1PresetLibrary.cpp
//  Arcade Ruins
//
//  X2-9 (ADR-080). See the header.
//
#include "S1PresetLibrary.hpp"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <sstream>

#include "S1DSPKernel.hpp"

namespace fs = std::filesystem;

namespace s1plugin {

PresetParameters presetParameters(const s1::Preset &preset) {
    S1DSPKernel scratch(2, 44100.0);
    preset.apply(scratch);
    PresetParameters values {};
    for (int i = 0; i < S1Parameter::S1ParameterCount; ++i) { values[size_t(i)] = scratch.getSynthParameter(S1Parameter(i)); }
    return values;
}

const std::array<const char *, 13> PresetLibrary::factoryBankOrder = {
    "BankA", "Bonus", "Brice Beasley", "DJ Puzzle", "Electronisounds",
    "Francis Preve", "JEC", "Red Sky Lullaby", "Sound of Izrael",
    "Sound of Izrael 2", "Spidericemidas", "Starter Bank", "User"
};

PresetLibrary::PresetLibrary(FactorySource factorySource, s1::PresetDefaults presetDefaults)
    : source(std::move(factorySource)), defaults(std::move(presetDefaults)) {}

// MARK: - Factory

s1::Preset PresetLibrary::initialPreset() const {
    if (const std::optional<std::string> text = factoryBankText("User")) {
        const nlohmann::json array = nlohmann::json::parse(*text, nullptr, false);
        if (array.is_array() && !array.empty() && array[0].is_object()) { return s1::Preset::fromJSON(array[0], defaults); }
    }
    return s1::Preset();
}

void PresetLibrary::loadFactory() {
    const std::lock_guard<std::mutex> lock(factoryLock);
    if (factoryLoaded) { return; }
    factoryLoaded = true;
    for (const char *name : factoryBankOrder) {
        PresetBank bank { name, {} };
        if (const std::optional<std::string> text = source ? source(name) : std::nullopt) {
            const nlohmann::json array = nlohmann::json::parse(*text, nullptr, false);
            if (array.is_array()) { bank.presets = s1::Preset::bankFromJSON(array, defaults); }
        }
        // A bank that is missing stays in the list, empty: the banks after it keep their place.
        for (int preset = 0; preset < int(bank.presets.size()); ++preset) { programs.push_back({ int(factory.size()), preset }); }
        factory.push_back(std::move(bank));
    }
}

const std::vector<PresetBank> &PresetLibrary::factoryBanks() { loadFactory(); return factory; }
int PresetLibrary::factoryProgramCount() { loadFactory(); return int(programs.size()); }

const s1::Preset *PresetLibrary::factoryProgram(int program) {
    loadFactory();
    if (program < 0 || program >= int(programs.size())) { return nullptr; }
    const Program &at = programs[size_t(program)];
    return &factory[size_t(at.bank)].presets[size_t(at.preset)];
}

std::string PresetLibrary::factoryProgramName(int program) {
    const s1::Preset *preset = factoryProgram(program);
    if (preset == nullptr) { return {}; }
    // S1FactoryPresets.swift: "\(bank): \(preset.name)", the bank being the FILE (Bonus.json's
    // presets say "BankA" inside and are listed under "Bonus").
    return factory[size_t(programs[size_t(program)].bank)].name + ": " + preset->name;
}

// MARK: - User

void PresetLibrary::setUserDirectory(const std::string &utf8Path) { directory = utf8Path; }

namespace {

fs::path pathFromUTF8(const std::string &text) { return fs::u8path(text); }
std::string utf8FromPath(const fs::path &path) { return path.u8string(); }

std::optional<std::string> readFile(const fs::path &path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) { return std::nullopt; }
    std::ostringstream text;
    text << in.rdbuf();
    return text.str();
}

std::string lowercased(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) { return char(std::tolower(c)); });
    return text;
}

} // namespace

std::string PresetLibrary::fileNameFor(const std::string &bankName) {
    std::string name;
    for (const unsigned char c : bankName) {
        const bool refused = c < 0x20 || c == 0x7F || std::string("/\\:*?\"<>|").find(char(c)) != std::string::npos;
        name += refused ? '_' : char(c);
    }
    while (!name.empty() && (name.back() == ' ' || name.back() == '.')) { name.pop_back(); }   // Windows drops these
    while (!name.empty() && name.front() == ' ') { name.erase(name.begin()); }
    if (name.size() > 120) { name.resize(120); while (!name.empty() && (static_cast<unsigned char>(name.back()) & 0xC0) == 0x80) { name.pop_back(); } }
    const std::string stem = lowercased(name.substr(0, name.find('.')));
    for (const char *reserved : { "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
                                  "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9" }) {
        if (stem == reserved) { name = "_" + name; break; }
    }
    return name;
}

PresetLibrary::Listing PresetLibrary::userBanks() const {
    Listing listing;
    if (directory.empty()) { return listing; }
    std::error_code error;
    const fs::path folder = pathFromUTF8(directory);
    if (!fs::is_directory(folder, error)) { return listing; }      // no folder yet is no banks, not a problem
    std::vector<fs::path> files;
    for (fs::directory_iterator entry(folder, error), end; !error && entry != end; entry.increment(error)) {
        if (entry->is_regular_file(error) && lowercased(utf8FromPath(entry->path().extension())) == ".json") { files.push_back(entry->path()); }
    }
    std::sort(files.begin(), files.end(), [](const fs::path &a, const fs::path &b) { return lowercased(utf8FromPath(a.filename())) < lowercased(utf8FromPath(b.filename())); });
    for (const fs::path &file : files) {
        const std::string fileName = utf8FromPath(file.filename());
        const std::optional<std::string> text = readFile(file);
        if (!text) { listing.problems.push_back(fileName + ": cannot be read"); continue; }
        nlohmann::json json = nlohmann::json::parse(*text, nullptr, false);
        if (json.is_object()) { json = nlohmann::json::array({ json }); }          // one preset, exported by itself
        if (!json.is_array()) { listing.problems.push_back(fileName + ": not a bank (a JSON array of presets)"); continue; }
        PresetBank bank { utf8FromPath(file.stem()), {} };
        for (const nlohmann::json &entry : json) {
            if (!entry.is_object()) { continue; }
            try { bank.presets.push_back(s1::Preset::fromJSON(entry, defaults)); }
            catch (const std::exception &) { listing.problems.push_back(fileName + ": a preset in it cannot be read"); }
        }
        listing.banks.push_back(std::move(bank));
    }
    return listing;
}

std::string PresetLibrary::writeBank(const PresetBank &bank) const {
    if (directory.empty()) { return "there is no user folder"; }
    const std::string fileName = fileNameFor(bank.name);
    if (fileName.empty()) { return "the bank needs a name"; }
    std::error_code error;
    const fs::path folder = pathFromUTF8(directory);
    fs::create_directories(folder, error);
    if (!fs::is_directory(folder, error)) { return "the user folder cannot be made: " + directory; }

    nlohmann::json array = nlohmann::json::array();
    for (s1::Preset preset : bank.presets) {
        preset.bank = bank.name;
        preset.position = int(array.size());
        array.push_back(preset.toJSON());
    }
    // Beside the bank, then renamed over it: a reader — another instance, the standalone — sees
    // the old file or the new one, never half of either.
    const fs::path target = folder / pathFromUTF8(fileName + ".json");
    const fs::path beside = folder / pathFromUTF8(fileName + ".json.writing");
    {
        std::ofstream out(beside, std::ios::binary | std::ios::trunc);
        if (!out) { return "cannot write in " + directory; }
        out << array.dump(1);
        out.flush();
        if (!out) { fs::remove(beside, error); return "the disk refused the bank (full?)"; }
    }
    fs::rename(beside, target, error);
    if (error) { fs::remove(beside, error); return "the bank could not be put in place"; }
    return {};
}

std::string PresetLibrary::savePreset(const std::string &bankName, s1::Preset preset) const {
    if (preset.uid.empty()) { preset.uid = s1::Preset::newUID(); }
    PresetBank bank { bankName, {} };
    const std::string wanted = lowercased(fileNameFor(bankName));
    for (PresetBank &existing : userBanks().banks) {
        if (lowercased(existing.name) == wanted) { bank = std::move(existing); bank.name = bankName; break; }
    }
    auto place = std::find_if(bank.presets.begin(), bank.presets.end(), [&](const s1::Preset &p) { return p.uid == preset.uid; });
    if (place == bank.presets.end()) {
        place = std::find_if(bank.presets.begin(), bank.presets.end(), [&](const s1::Preset &p) { return p.name == preset.name; });
    }
    if (place == bank.presets.end()) { bank.presets.push_back(std::move(preset)); } else { *place = std::move(preset); }
    return writeBank(bank);
}

std::string PresetLibrary::removePreset(const std::string &bankName, const std::string &uid) const {
    const std::string wanted = lowercased(fileNameFor(bankName));
    for (PresetBank &bank : userBanks().banks) {
        if (lowercased(bank.name) != wanted) { continue; }
        const auto place = std::find_if(bank.presets.begin(), bank.presets.end(), [&](const s1::Preset &p) { return p.uid == uid; });
        if (place == bank.presets.end()) { return "no such preset in " + bankName; }
        bank.presets.erase(place);
        return writeBank(bank);
    }
    return "no such bank: " + bankName;
}

std::string PresetLibrary::removeBank(const std::string &bankName) const {
    if (directory.empty()) { return "there is no user folder"; }
    const std::string fileName = fileNameFor(bankName);
    if (fileName.empty()) { return "that is not a bank's name"; }
    std::error_code error;
    fs::remove(pathFromUTF8(directory) / pathFromUTF8(fileName + ".json"), error);
    // Gone already is what was asked for; only a refusal is a failure.
    return error ? "the bank's file could not be removed: " + error.message() : std::string();
}

} // namespace s1plugin
