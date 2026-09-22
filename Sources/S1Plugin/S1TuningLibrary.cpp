//
//  S1TuningLibrary.cpp
//  Arcade Ruins
//
//  X3-5 (ADR-087). See the header.
//
#include "S1TuningLibrary.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>

#include "S1FactoryTunings.hpp"
#include "S1Scala.hpp"

namespace fs = std::filesystem;

namespace s1plugin {

namespace {

fs::path pathFromUTF8(const std::string &text) { return fs::u8path(text); }

/// `Tuning.defaultMasterSet`, the twelve ratios exactly as the Swift spells them.
const std::vector<double> kTwelveET = {
    1.0, 1.0594630943592953, 1.122462048309373, 1.189207115002721, 1.2599210498948732,
    1.3348398541700344, 1.4142135623730951, 1.4983070768766815, 1.5874010519681994,
    1.681792830507429, 1.7817974362806785, 1.8877486253633868
};

} // namespace

const char *TuningLibrary::defaultTuningName() { return "12 ET"; }
const std::vector<double> &TuningLibrary::defaultMasterSet() { return kTwelveET; }

double TuningLibrary::middleCForA4(double frequencyA4) {
    // TuneUp does frequencyA4 = frequencyMiddleC * 2^((69-60)/12); this is that, inverted.
    return frequencyA4 * s1::powerOfTwo(-9.0 / 12.0);
}

// MARK: - A tuning's two derived strings

std::string TuningEntry::nameForCell() const {
    std::string count = std::to_string(npo());
    while (count.size() < 3) { count = " " + count; }
    return count + " " + name;
}

std::string TuningEntry::encoding() const {
    std::vector<double> reduced;
    for (const double input : masterSet) {
        if (input <= 0) { continue; }                 // `filter { $0 > 0 }`
        double f = input;
        while (f < 1) { f *= 2; }
        while (f > 2) { f /= 2; }
        double whole = 0;
        reduced.push_back(std::modf(std::log2(f), &whole));   // `truncatingRemainder(dividingBy: 1)`
    }
    std::sort(reduced.begin(), reduced.end());
    std::string key;
    for (const double p : reduced) {
        char digits[64];
        std::snprintf(digits, sizeof digits, "%.12f_", p);
        key += digits;
    }
    return key;
}

// MARK: - Building and reading

TuningLibrary::TuningLibrary(std::string utf8Directory) : folder(std::move(utf8Directory)) {
    playingMasterSet = kTwelveET;
}

void TuningLibrary::setDirectory(const std::string &utf8Path) { folder = utf8Path; }

void TuningLibrary::loadFactoryTunings() {
    tuningBanks.clear();
    tuningBanks.resize(3);
    tuningBanks[kCuratedBank].name = s1::kBundleTuningsBankName;          // "Curated"
    tuningBanks[kCuratedBank].order = kCuratedBank;
    tuningBanks[kUserBank].name = "User";
    tuningBanks[kUserBank].order = kUserBank;
    tuningBanks[kHexanyTriadBank].name = s1::kHexanyTriadTuningsBankName;
    tuningBanks[kHexanyTriadBank].order = kHexanyTriadBank;
    int curated = 0, hexany = 0;
    for (const s1::FactoryTuning &factory : s1::factoryTunings()) {
        TuningEntry entry;
        entry.name = factory.name;
        entry.masterSet = factory.masterSet;
        const bool isHexany = std::string(factory.bank) == s1::kHexanyTriadTuningsBankName;
        entry.order = isHexany ? hexany++ : curated++;
        tuningBanks[size_t(isHexany ? kHexanyTriadBank : kCuratedBank)].tunings.push_back(std::move(entry));
    }
}

void TuningLibrary::readFile() {
    if (folder.empty()) { return; }
    std::ifstream in(pathFromUTF8(folder) / kFileName, std::ios::binary);
    if (!in) { return; }                                   // no file yet is not a problem
    std::ostringstream text;
    text << in.rdbuf();
    const nlohmann::json json = nlohmann::json::parse(text.str(), nullptr, false);
    if (!json.is_array()) { lastProblem = std::string(kFileName) + " is not a list of banks"; return; }

    std::vector<TuningBankEntry> read;
    chosenBankFromFile = -1;
    for (const nlohmann::json &bankJSON : json) {
        if (!bankJSON.is_object()) { continue; }
        TuningBankEntry entry;
        if (bankJSON.contains("name") && bankJSON["name"].is_string()) { entry.name = bankJSON["name"].get<std::string>(); }
        if (bankJSON.contains("isEditable") && bankJSON["isEditable"].is_boolean()) { entry.isEditable = bankJSON["isEditable"].get<bool>(); }
        if (bankJSON.contains("order") && bankJSON["order"].is_number_integer()) { entry.order = bankJSON["order"].get<int>(); }
        if (bankJSON.contains("selectedTuningIndex") && bankJSON["selectedTuningIndex"].is_number_integer()) {
            entry.selectedTuningIndex = bankJSON["selectedTuningIndex"].get<int>();
        }
        // Ours, not the Mac's: upstream keeps the chosen BANK in AppSettings, which a plugin has
        // none of. An extra key is safe — Swift's synthesised decoder ignores what it does not know.
        if (bankJSON.contains("isSelected") && bankJSON["isSelected"].is_boolean() && bankJSON["isSelected"].get<bool>()) {
            chosenBankFromFile = int(read.size());
        }
        if (bankJSON.contains("tunings") && bankJSON["tunings"].is_array()) {
            for (const nlohmann::json &tuningJSON : bankJSON["tunings"]) {
                if (!tuningJSON.is_object()) { continue; }
                TuningEntry tuning;
                if (tuningJSON.contains("name") && tuningJSON["name"].is_string()) { tuning.name = tuningJSON["name"].get<std::string>(); }
                if (tuningJSON.contains("order") && tuningJSON["order"].is_number_integer()) { tuning.order = tuningJSON["order"].get<int>(); }
                // `init(from:)`: a missing userOrder is -1, and the rest must be there.
                tuning.userOrder = tuningJSON.contains("userOrder") && tuningJSON["userOrder"].is_number_integer()
                                       ? tuningJSON["userOrder"].get<int>() : -1;
                if (tuningJSON.contains("masterSet") && tuningJSON["masterSet"].is_array()) {
                    for (const nlohmann::json &ratio : tuningJSON["masterSet"]) {
                        if (ratio.is_number()) { tuning.masterSet.push_back(ratio.get<double>()); }
                    }
                }
                if (tuning.masterSet.empty()) { continue; }
                entry.tunings.push_back(std::move(tuning));
            }
        }
        read.push_back(std::move(entry));
    }
    // `loadTunings`: fewer than three banks and the factory tunings are used instead.
    if (int(read.size()) <= kHexanyTriadBank) {
        lastProblem = std::string(kFileName) + " holds " + std::to_string(read.size()) + " of 3 banks: the shipped tunings are used";
        return;
    }
    tuningBanks = std::move(read);
}

void TuningLibrary::load() {
    loadFactoryTunings();
    lastProblem.clear();
    readFile();
    sortTunings(tuningBanks[kUserBank], Sort::userOrder);
    sortTunings(tuningBanks[kCuratedBank], Sort::userOrder);
    sortTunings(tuningBanks[kHexanyTriadBank], Sort::userOrder);
    // The bank the file remembers; failing that, `loadTunings`' own rule — the User bank when it
    // holds more than 12 ET alone.
    bankIndex = chosenBankFromFile >= 0 && chosenBankFromFile < int(tuningBanks.size())
                    ? chosenBankFromFile
                    : (tuningBanks[kUserBank].tunings.size() > 1 ? kUserBank : kCuratedBank);
    loaded = true;
    adoptSelection();
}

void TuningLibrary::writeFile() const {
    if (folder.empty()) { return; }
    nlohmann::json json = nlohmann::json::array();
    for (const TuningBankEntry &entry : tuningBanks) {
        nlohmann::json bankJSON;
        bankJSON["name"] = entry.name;
        bankJSON["isEditable"] = entry.isEditable;
        bankJSON["order"] = entry.order;
        bankJSON["selectedTuningIndex"] = entry.selectedTuningIndex;
        bankJSON["isSelected"] = int(json.size()) == bankIndex;
        nlohmann::json list = nlohmann::json::array();
        for (const TuningEntry &tuning : entry.tunings) {
            nlohmann::json tuningJSON;
            tuningJSON["name"] = tuning.name;
            tuningJSON["masterSet"] = tuning.masterSet;
            tuningJSON["order"] = tuning.order;
            tuningJSON["userOrder"] = tuning.userOrder;
            list.push_back(std::move(tuningJSON));
        }
        bankJSON["tunings"] = std::move(list);
        json.push_back(std::move(bankJSON));
    }
    std::error_code error;
    fs::create_directories(pathFromUTF8(folder), error);
    // Beside it, then renamed over it, as a bank file is written (ADR-080).
    const fs::path target = pathFromUTF8(folder) / kFileName;
    const fs::path beside = pathFromUTF8(folder) / (std::string(kFileName) + ".writing");
    {
        std::ofstream out(beside, std::ios::binary | std::ios::trunc);
        if (!out) { return; }
        out << json.dump(1);
        out.flush();
        if (!out) { fs::remove(beside, error); return; }
    }
    fs::rename(beside, target, error);
    if (error) { fs::remove(beside, error); }
}

// MARK: - The sort (upstream's, 12 ET stripped and put back)

void TuningLibrary::sortTunings(TuningBankEntry &entry, Sort sortType) {
    TuningEntry twelve;
    twelve.name = defaultTuningName();
    twelve.masterSet = kTwelveET;
    const std::string twelveKey = twelve.name + twelve.encoding();
    const bool insertTwelveET = &entry == &tuningBanks[kCuratedBank] || &entry == &tuningBanks[kUserBank];

    std::vector<TuningEntry> list = entry.tunings;
    if (insertTwelveET) {
        list.erase(std::remove_if(list.begin(), list.end(), [&twelveKey](const TuningEntry &t) {
                       return t.name + t.encoding() == twelveKey || t.name == "Twelve Tone Equal Temperament";
                   }),
                   list.end());
    }
    switch (sortType) {
        case Sort::npo:
            std::sort(list.begin(), list.end(), [](const TuningEntry &a, const TuningEntry &b) {
                return a.nameForCell() + a.encoding() < b.nameForCell() + b.encoding();
            });
            break;
        case Sort::name:
            std::sort(list.begin(), list.end(), [](const TuningEntry &a, const TuningEntry &b) {
                return a.name + a.nameForCell() + a.encoding() < b.name + b.nameForCell() + b.encoding();
            });
            break;
        case Sort::userOrder:
            std::stable_sort(list.begin(), list.end(), [](const TuningEntry &a, const TuningEntry &b) {
                return a.userOrder < b.userOrder;
            });
            break;
    }
    // "If no userOrder (== -1) set a default" — upstream numbers them ALL when any is unset.
    if (std::any_of(list.begin(), list.end(), [](const TuningEntry &t) { return t.userOrder == -1; })) {
        for (size_t i = 0; i < list.size(); ++i) { list[i].userOrder = int(i) + 10; }
    }
    if (insertTwelveET) {
        twelve.userOrder = 0;
        list.insert(list.begin(), twelve);
    }
    entry.tunings = std::move(list);
}

// MARK: - The lists

int TuningLibrary::selectedTuningIndex() const { return bank().selectedTuningIndex; }
const std::vector<TuningEntry> &TuningLibrary::tunings() const { return bank().tunings; }
std::string TuningLibrary::selectedBankName() const { return bank().name; }

void TuningLibrary::adoptSelection() {
    TuningBankEntry &entry = bank();
    if (entry.tunings.empty()) { playingName = defaultTuningName(); playingMasterSet = kTwelveET; return; }
    entry.selectedTuningIndex = std::max(0, std::min(entry.selectedTuningIndex, int(entry.tunings.size()) - 1));
    const TuningEntry &tuning = entry.tunings[size_t(entry.selectedTuningIndex)];
    playingName = tuning.name;
    playingMasterSet = tuning.masterSet;
}

std::array<double, S1TuningTable::midiNoteCount> TuningLibrary::frequencies(double frequencyA4) const {
    S1TuningTable table;
    if (table.tuningTableFromFrequencies(playingMasterSet) == 0) { table.twelveToneEqualTemperament(); }
    // A4 moves the whole table: the reference is middle C, and 440 gives the table's own.
    if (frequencyA4 > 0) { table.setMiddleCFrequency(middleCForA4(frequencyA4)); }
    std::array<double, S1TuningTable::midiNoteCount> out {};
    for (int note = 0; note < S1TuningTable::midiNoteCount; ++note) { out[size_t(note)] = table.frequencyForNoteNumber(note); }
    return out;
}

std::pair<std::string, std::vector<double>> TuningLibrary::currentTuning() const {
    return { playingName, playingMasterSet };
}

// MARK: - The operations

void TuningLibrary::selectBank(int row) {
    if (tuningBanks.empty()) { return; }
    bankIndex = std::max(0, std::min(row, int(tuningBanks.size()) - 1));
    adoptSelection();
    writeFile();
}

void TuningLibrary::selectTuning(int row) {
    TuningBankEntry &entry = bank();
    if (entry.tunings.empty()) { return; }
    entry.selectedTuningIndex = std::max(0, std::min(row, int(entry.tunings.size()) - 1));
    adoptSelection();
    writeFile();
}

void TuningLibrary::resetTuning() {
    bankIndex = kCuratedBank;
    tuningBanks[kCuratedBank].selectedTuningIndex = 0;      // 12 ET is always row 0 there
    adoptSelection();
    writeFile();
}

void TuningLibrary::randomTuning() {
    TuningBankEntry &entry = bank();
    if (entry.tunings.empty()) { return; }
    std::uniform_int_distribution<int> pick(0, int(entry.tunings.size()) - 1);
    entry.selectedTuningIndex = pick(dice);
    adoptSelection();
    writeFile();
}

bool TuningLibrary::setTuning(const std::string &name, const std::vector<double> &inputMasterSet) {
    if (inputMasterSet.empty()) { return false; }
    TuningEntry wanted;
    wanted.name = name;
    wanted.masterSet = inputMasterSet;
    const std::string key = wanted.name + wanted.encoding();

    // Upstream looks only in the User bank; a tuning already there is chosen rather than added.
    TuningBankEntry &user = tuningBanks[kUserBank];
    auto found = std::find_if(user.tunings.begin(), user.tunings.end(),
                              [&key](const TuningEntry &t) { return t.name + t.encoding() == key; });
    if (found == user.tunings.end()) {
        user.tunings.push_back(wanted);
        sortTunings(user, Sort::userOrder);
        found = std::find_if(user.tunings.begin(), user.tunings.end(),
                             [&key](const TuningEntry &t) { return t.name + t.encoding() == key; });
    }
    if (found != user.tunings.end()) {
        bankIndex = kUserBank;
        user.selectedTuningIndex = int(found - user.tunings.begin());
    }
    // "Update global tuning table no matter what": what plays is what was asked for, even when
    // the bank could not take it.
    playingName = name;
    playingMasterSet = inputMasterSet;
    writeFile();
    return true;
}

bool TuningLibrary::removeUserTuning(int index) {
    if (bankIndex != kUserBank) { return false; }
    TuningBankEntry &user = tuningBanks[kUserBank];
    if (int(user.tunings.size()) <= 1 || index == 0) { return false; }   // 12 ET is always row 0
    if (index < 0 || index >= int(user.tunings.size())) { return false; }
    user.tunings.erase(user.tunings.begin() + index);
    selectTuning(index - 1);
    return true;
}

bool TuningLibrary::reorderUserBank(int from, int to) {
    TuningBankEntry &user = tuningBanks[kUserBank];
    const int count = int(user.tunings.size());
    if (from < 0 || from >= count || to < 0 || to >= count || from == to) { return false; }
    TuningEntry moved = user.tunings[size_t(from)];
    user.tunings.erase(user.tunings.begin() + from);
    user.tunings.insert(user.tunings.begin() + to, std::move(moved));
    for (size_t i = 0; i < user.tunings.size(); ++i) { user.tunings[i].userOrder = int(i); }
    sortTunings(user, Sort::userOrder);
    bankIndex = kUserBank;
    selectTuning(to);
    return true;
}

std::string TuningLibrary::importScala(const std::string &fileName, const std::string &text) {
    const std::optional<std::vector<double>> parsed = s1::frequenciesFromScalaString(text);
    // The parser hands back the implicit 1/1 even for a file with no usable line in it, so a
    // "scale" of one note is how nonsense arrives.
    if (!parsed || parsed->size() < 2) { return "that file is not a scale this reads"; }
    std::string name = fileName;
    const size_t dot = name.find_last_of('.');
    if (dot != std::string::npos && dot > 0) { name = name.substr(0, dot); }
    if (name.empty()) { name = "Imported"; }
    return setTuning(name, *parsed) ? std::string() : "that scale could not be added";
}

} // namespace s1plugin
