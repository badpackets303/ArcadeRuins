//
//  S1PresetBrowser.cpp
//  Arcade Ruins
//
//  X3-4 (ADR-086). See the header.
//
#include "S1PresetBrowser.hpp"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <sstream>

namespace fs = std::filesystem;

namespace s1plugin {

const std::array<const char *, 12> PresetBrowser::initialBankOrder = {
    "BankA", "User", "Brice Beasley", "DJ Puzzle", "Electronisounds", "Francis Preve",
    "JEC", "Red Sky Lullaby", "Spidericemidas", "Sound of Izrael", "Sound of Izrael 2", "Starter Bank"
};

const char *PresetBrowser::categoryName(int category) {
    switch (category) {
        case 0: return "All";
        case 1: return "Arp/Seq";
        case 2: return "Poly";
        case 3: return "Pad";
        case 4: return "Lead";
        case 5: return "Bass";
        case 6: return "Pluck";
        default: return "";
    }
}

namespace {

std::string lowercased(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) { return char(std::tolower(c)); });
    return text;
}

std::string trimmed(const std::string &text) {
    const auto space = [](unsigned char c) { return std::isspace(c) != 0; };
    size_t first = 0, last = text.size();
    while (first < last && space(static_cast<unsigned char>(text[first]))) { ++first; }
    while (last > first && space(static_cast<unsigned char>(text[last - 1]))) { --last; }
    return text.substr(first, last - first);
}

bool contains(const std::string &haystack, const std::string &needle) {
    return lowercased(haystack).find(needle) != std::string::npos;
}

fs::path pathFromUTF8(const std::string &text) { return fs::u8path(text); }

} // namespace

PresetBrowser::PresetBrowser(PresetLibrary &presetLibrary) : library(presetLibrary) {}

// MARK: - Reading the folder

void PresetBrowser::load() {
    if (!seeded) {
        seeded = true;
        // `loadBanks`: a bundled bank with no file yet is written out, and from then on the file
        // is the bank. BankA takes Bonus's presets with it (ADR-040) — they say "BankA" inside.
        const PresetLibrary::Listing listing = library.userBanks();
        const auto onDisk = [&listing](const std::string &name) {
            const std::string wanted = lowercased(PresetLibrary::fileNameFor(name));
            return std::any_of(listing.banks.begin(), listing.banks.end(),
                               [&wanted](const PresetBank &bank) { return lowercased(bank.name) == wanted; });
        };
        const std::vector<PresetBank> &factory = library.factoryBanks();
        const auto factoryBank = [&factory](const std::string &name) -> const PresetBank * {
            const auto found = std::find_if(factory.begin(), factory.end(), [&name](const PresetBank &bank) { return bank.name == name; });
            return found == factory.end() ? nullptr : &*found;
        };
        for (const char *name : initialBankOrder) {
            if (onDisk(name)) { continue; }
            PresetBank bank { name, {} };
            if (const PresetBank *linked = factoryBank(name)) { bank.presets = linked->presets; }
            if (std::string(name) == "BankA") {
                if (const PresetBank *bonus = factoryBank("Bonus")) {
                    bank.presets.insert(bank.presets.end(), bonus->presets.begin(), bonus->presets.end());
                }
            }
            if (bank.presets.empty()) { continue; }        // nothing linked in: no empty file either
            const std::string problem = library.writeBank(bank);
            if (!problem.empty()) { lastProblems.push_back(std::string(name) + ": " + problem); }
        }
    }
    loaded = true;
    refresh();
    rememberOrder();
}

void PresetBrowser::refresh() {
    readFolder();
    buildCategories();
    if (category >= int(categoryRows.size())) { category = 0; }
    sortPresets();
}

std::vector<std::string> PresetBrowser::readOrder() const {
    std::vector<std::string> order;
    if (library.userDirectory().empty()) { return order; }
    std::ifstream in(pathFromUTF8(library.userDirectory()) / kOrderFileName, std::ios::binary);
    if (!in) { return order; }
    std::ostringstream text;
    text << in.rdbuf();
    const nlohmann::json json = nlohmann::json::parse(text.str(), nullptr, false);
    if (!json.is_array()) { return order; }
    for (const nlohmann::json &entry : json) {
        if (entry.is_string()) { order.push_back(entry.get<std::string>()); }
    }
    return order;
}

void PresetBrowser::rememberOrder() {
    if (library.userDirectory().empty()) { return; }
    nlohmann::json json = nlohmann::json::array();
    for (const std::string &bank : banks) { json.push_back(bank); }
    std::error_code error;
    fs::create_directories(pathFromUTF8(library.userDirectory()), error);
    std::ofstream out(pathFromUTF8(library.userDirectory()) / kOrderFileName, std::ios::binary | std::ios::trunc);
    if (out) { out << json.dump(1); }
}

void PresetBrowser::readFolder() {
    PresetLibrary::Listing listing = library.userBanks();
    lastProblems = listing.problems;

    // The order: what was remembered, then the bundled order for anything it does not name,
    // then whatever else is in the folder (the library lists files by name).
    std::vector<std::string> wanted = readOrder();
    for (const char *name : initialBankOrder) {
        if (std::none_of(wanted.begin(), wanted.end(), [name](const std::string &had) { return lowercased(had) == lowercased(name); })) {
            wanted.emplace_back(name);
        }
    }

    banks.clear();
    presets.clear();
    // A uid is how a row, a save and a deletion name a preset here, and the shipped banks do NOT
    // hold 695 different ones — 23 are used twice (a preset copied between banks upstream). One
    // of each pair is given a fresh uid and its bank written back, once: after that the files
    // hold what is read, so the uid a row was chosen by is the uid saved a moment later.
    std::vector<std::string> seen;
    std::vector<std::string> toRewrite;
    std::vector<bool> taken(listing.banks.size(), false);
    const auto take = [&](size_t index) {
        taken[index] = true;
        PresetBank &bank = listing.banks[index];
        banks.push_back(bank.name);
        std::stable_sort(bank.presets.begin(), bank.presets.end(),
                         [](const s1::Preset &a, const s1::Preset &b) { return a.position < b.position; });
        for (s1::Preset &preset : bank.presets) {
            preset.bank = bank.name;      // the FILE names the bank: an imported preset may say another
            if (preset.uid.empty() || std::find(seen.begin(), seen.end(), preset.uid) != seen.end()) {
                preset.uid = s1::Preset::newUID();
                if (std::find(toRewrite.begin(), toRewrite.end(), bank.name) == toRewrite.end()) { toRewrite.push_back(bank.name); }
            }
            seen.push_back(preset.uid);
            presets.push_back(std::move(preset));
        }
    };
    for (const std::string &name : wanted) {
        const std::string key = lowercased(name);
        for (size_t i = 0; i < listing.banks.size(); ++i) {
            if (!taken[i] && lowercased(listing.banks[i].name) == key) { take(i); break; }
        }
    }
    for (size_t i = 0; i < listing.banks.size(); ++i) { if (!taken[i]) { take(i); } }
    for (const std::string &bank : toRewrite) {
        const std::string problem = writeBankHolding(bank);
        if (!problem.empty()) { lastProblems.push_back(bank + ": " + problem); }
    }
}

void PresetBrowser::buildCategories() {
    categoryRows.clear();
    for (int i = 0; i <= kCategoryCount; ++i) { categoryRows.push_back({ categoryName(i), false, {} }); }
    categoryRows.push_back({ "Alphabetical", false, {} });
    categoryRows.push_back({ "Favorites", false, {} });
    for (const std::string &bank : banks) {
        // The Mac marks a bank's row with ⌾; the row's words are what it reads out.
        categoryRows.push_back({ "\xE2\x8C\xBE " + bank, true, bank });
    }
}

// MARK: - The shown list (`sortPresets`)

void PresetBrowser::sortPresets() {
    list.clear();
    if (!searchText.empty()) {
        // SearchViewController: the name or the notes, anywhere in the library, by name.
        const std::string wanted = lowercased(searchText);
        for (const s1::Preset &preset : presets) {
            if (contains(preset.name, wanted) || contains(preset.userText, wanted)) { list.push_back(preset); }
        }
        std::stable_sort(list.begin(), list.end(), [](const s1::Preset &a, const s1::Preset &b) {
            return lowercased(a.name) < lowercased(b.name);
        });
        return;
    }
    if (category == 0) {                                   // All, by bank
        list = presets;
    } else if (category >= 1 && category <= kCategoryCount) {
        for (const s1::Preset &preset : presets) { if (preset.category == category) { list.push_back(preset); } }
    } else if (category == kAlphabeticalIndex) {
        list = presets;
        std::stable_sort(list.begin(), list.end(), [](const s1::Preset &a, const s1::Preset &b) {
            return lowercased(a.name) < lowercased(b.name);
        });
    } else if (category == kFavouritesIndex) {
        for (const s1::Preset &preset : presets) { if (preset.isFavorite) { list.push_back(preset); } }
    } else {
        const std::string bank = shownBank();
        for (const s1::Preset &preset : presets) { if (preset.bank == bank) { list.push_back(preset); } }
    }
}

void PresetBrowser::selectCategory(int index) {
    if (index < 0 || index >= int(categoryRows.size())) { return; }
    category = index;
    sortPresets();
}

std::string PresetBrowser::shownBank() const {
    if (category < kBankStartingIndex || category >= int(categoryRows.size())) { return {}; }
    return categoryRows[size_t(category)].bank;
}

int PresetBrowser::categoryIndexOfBank(const std::string &bank) const {
    for (size_t i = 0; i < categoryRows.size(); ++i) {
        if (categoryRows[i].isBank && categoryRows[i].bank == bank) { return int(i); }
    }
    return -1;
}

void PresetBrowser::setSearch(const std::string &text) {
    const std::string wanted = trimmed(text);
    if (wanted == searchText) { return; }
    searchText = wanted;
    sortPresets();
}

// MARK: - What is playing

void PresetBrowser::setCurrent(const std::string &uid) { current = uid; }

const s1::Preset *PresetBrowser::presetWithUID(const std::string &uid) const {
    if (uid.empty()) { return nullptr; }
    const auto found = std::find_if(presets.begin(), presets.end(), [&uid](const s1::Preset &p) { return p.uid == uid; });
    return found == presets.end() ? nullptr : &*found;
}

s1::Preset *PresetBrowser::find(const std::string &uid) {
    const auto found = std::find_if(presets.begin(), presets.end(), [&uid](const s1::Preset &p) { return p.uid == uid; });
    return found == presets.end() ? nullptr : &*found;
}

int PresetBrowser::currentRow() const {
    for (size_t i = 0; i < list.size(); ++i) { if (list[i].uid == current) { return int(i); } }
    return -1;
}

const s1::Preset *PresetBrowser::step(int direction) {
    if (list.empty() || direction == 0) { return nullptr; }
    const int count = int(list.size());
    const int row = currentRow();
    const int next = row < 0 ? (direction > 0 ? 0 : count - 1)
                             : (((row + direction) % count) + count) % count;
    current = list[size_t(next)].uid;
    return &list[size_t(next)];
}

const s1::Preset *PresetBrowser::randomPreset() {
    if (list.empty()) { return nullptr; }
    std::uniform_int_distribution<size_t> pick(0, list.size() - 1);
    size_t row = pick(dice);
    if (list.size() > 1 && list[row].uid == current) { row = (row + 1) % list.size(); }
    current = list[row].uid;
    return &list[row];
}

// MARK: - Writing

std::string PresetBrowser::writeBankHolding(const std::string &bankName) {
    PresetBank bank { bankName, {} };
    for (const s1::Preset &preset : presets) { if (preset.bank == bankName) { bank.presets.push_back(preset); } }
    std::stable_sort(bank.presets.begin(), bank.presets.end(),
                     [](const s1::Preset &a, const s1::Preset &b) { return a.position < b.position; });
    for (size_t i = 0; i < bank.presets.size(); ++i) {
        bank.presets[i].position = int(i);                                  // `saveAllPresetsIn`
        bank.presets[i].name = trimmed(bank.presets[i].name);
    }
    return library.writeBank(bank);
}

const std::string PresetBrowser::userBankName() const {
    for (const std::string &bank : banks) { if (bank == "User") { return bank; } }
    return banks.empty() ? std::string("User") : banks.front();
}

std::string PresetBrowser::unusedBankName(const std::string &wanted) const {
    const auto taken = [this](const std::string &name) {
        return std::any_of(banks.begin(), banks.end(), [&name](const std::string &bank) { return lowercased(bank) == lowercased(name); });
    };
    if (!taken(wanted)) { return wanted; }
    for (int n = 2; n < 1000; ++n) {
        const std::string tried = wanted + " " + std::to_string(n);
        if (!taken(tried)) { return tried; }
    }
    return wanted + " " + s1::Preset::newUID();
}

int PresetBrowser::countIn(const std::string &bankName) const {
    return int(std::count_if(presets.begin(), presets.end(), [&bankName](const s1::Preset &p) { return p.bank == bankName; }));
}

// MARK: - The operations

std::string PresetBrowser::createPreset() {
    lastNotice.clear();
    const std::string bank = userBankName();
    s1::Preset preset = library.initialPreset();
    preset.uid = s1::Preset::newUID();
    preset.bank = bank;
    preset.isUser = true;
    preset.isFavorite = false;
    preset.position = countIn(bank);
    const std::string uid = preset.uid;
    presets.push_back(std::move(preset));
    const std::string problem = writeBankHolding(bank);
    refresh();
    selectCategory(categoryIndexOfBank(bank));
    setCurrent(uid);
    return problem;
}

std::string PresetBrowser::createBank() {
    lastNotice.clear();
    const std::string name = unusedBankName("Bank" + std::to_string(banks.size()));
    s1::Preset preset = library.initialPreset();
    preset.uid = s1::Preset::newUID();
    preset.bank = name;
    preset.isUser = true;
    preset.isFavorite = false;
    preset.position = 0;
    const std::string uid = preset.uid;
    presets.push_back(std::move(preset));
    const std::string problem = writeBankHolding(name);
    if (problem.empty()) { banks.push_back(name); rememberOrder(); }
    refresh();
    selectCategory(categoryIndexOfBank(name));
    setCurrent(uid);
    return problem;
}

std::string PresetBrowser::duplicate(const std::string &uid) {
    lastNotice.clear();
    const s1::Preset *original = presetWithUID(uid);
    if (original == nullptr) { return "there is no such preset"; }
    const std::string bank = userBankName();
    s1::Preset copy = *original;
    copy.name += " [copy]";
    copy.uid = s1::Preset::newUID();
    copy.isUser = true;
    copy.bank = bank;
    copy.position = countIn(bank);
    const std::string madeUID = copy.uid;
    presets.push_back(std::move(copy));
    const std::string problem = writeBankHolding(bank);
    refresh();
    selectCategory(categoryIndexOfBank(bank));
    setCurrent(madeUID);
    return problem;
}

std::string PresetBrowser::toggleFavourite(const std::string &uid) {
    lastNotice.clear();
    s1::Preset *preset = find(uid);
    if (preset == nullptr) { return "there is no such preset"; }
    preset->isFavorite = !preset->isFavorite;
    const std::string problem = writeBankHolding(preset->bank);
    refresh();
    return problem;
}

std::string PresetBrowser::savePreset(const std::string &uid, const s1::Preset &sound,
                                      const std::string &name, int presetCategory, const std::string &bank) {
    lastNotice.clear();
    const std::string wantedName = trimmed(name);
    if (wantedName.empty()) { return "the preset needs a name"; }
    if (trimmed(bank).empty()) { return "the preset needs a bank"; }

    const s1::Preset *existing = presetWithUID(uid);
    const std::string oldBank = existing != nullptr ? existing->bank : std::string();

    s1::Preset preset = sound;                   // the 150 values as they stand, and the notes
    preset.uid = existing != nullptr ? uid : s1::Preset::newUID();
    preset.name = wantedName;
    preset.category = presetCategory < 0 || presetCategory > kCategoryCount ? 0 : presetCategory;
    preset.bank = bank;
    preset.isUser = true;
    if (existing != nullptr) {
        preset.isFavorite = existing->isFavorite;
        // Its place: kept where it was, or the end of the bank it is moving to.
        preset.position = existing->bank == bank ? existing->position : countIn(bank);
        presets.erase(presets.begin() + (existing - presets.data()));
    } else {
        preset.position = countIn(bank);
    }
    const std::string savedUID = preset.uid;
    presets.push_back(std::move(preset));

    std::string problem = writeBankHolding(bank);
    if (!oldBank.empty() && oldBank != bank) {
        const std::string other = writeBankHolding(oldBank);
        if (problem.empty()) { problem = other; }
    }
    const bool isNewBank = std::none_of(banks.begin(), banks.end(), [&bank](const std::string &had) { return had == bank; });
    if (problem.empty() && isNewBank) { banks.push_back(bank); rememberOrder(); }
    refresh();
    setCurrent(savedUID);
    return problem;
}

std::string PresetBrowser::setNotes(const std::string &uid, const std::string &text) {
    lastNotice.clear();
    s1::Preset *preset = find(uid);
    if (preset == nullptr) { return "there is no such preset"; }
    if (preset->userText == text) { return {}; }
    preset->userText = text;
    const std::string problem = writeBankHolding(preset->bank);
    refresh();
    return problem;
}

std::string PresetBrowser::removePreset(const std::string &uid) {
    lastNotice.clear();
    const s1::Preset *preset = presetWithUID(uid);
    if (preset == nullptr) { return "there is no such preset"; }
    if (presets.size() <= 1) { return "the last preset stays"; }      // upstream: `guard presets.count > 1`
    const std::string bank = preset->bank;
    const int row = [this, &uid] {
        for (size_t i = 0; i < list.size(); ++i) { if (list[i].uid == uid) { return int(i); } }
        return -1;
    }();
    presets.erase(presets.begin() + (preset - presets.data()));
    const std::string problem = writeBankHolding(bank);
    refresh();
    // The Mac moves to the preset above the one that has gone.
    if (current == uid && !list.empty()) {
        const int above = row <= 0 ? 0 : std::min(row - 1, int(list.size()) - 1);
        setCurrent(list[size_t(above)].uid);
    }
    return problem;
}

std::string PresetBrowser::movePreset(int from, int to) {
    lastNotice.clear();
    const std::string bank = shownBank();
    if (bank.empty()) { return "reordering is for a bank's own list"; }   // upstream's Reorder picks a bank first
    if (!searchText.empty()) { return "reordering is for a bank's own list"; }
    const int count = int(list.size());
    if (from < 0 || from >= count || to < 0 || to >= count || from == to) { return {}; }

    std::vector<std::string> order;
    order.reserve(size_t(count));
    for (const s1::Preset &preset : list) { order.push_back(preset.uid); }
    const std::string moved = order[size_t(from)];
    order.erase(order.begin() + from);
    order.insert(order.begin() + to, moved);
    for (size_t i = 0; i < order.size(); ++i) {
        if (s1::Preset *preset = find(order[i])) { preset->position = int(i); }
    }
    const std::string problem = writeBankHolding(bank);
    refresh();
    return problem;
}

std::string PresetBrowser::renameBank(const std::string &oldName, const std::string &newName) {
    lastNotice.clear();
    const std::string wanted = trimmed(newName);
    if (wanted.empty()) { return "the bank needs a name"; }
    if (PresetLibrary::fileNameFor(wanted).empty()) { return "that is not a name a file can have"; }
    if (wanted == oldName) { return {}; }
    if (std::any_of(banks.begin(), banks.end(), [&wanted](const std::string &bank) { return lowercased(bank) == lowercased(wanted); })) {
        return "there is already a bank called " + wanted;
    }
    if (std::none_of(banks.begin(), banks.end(), [&oldName](const std::string &bank) { return bank == oldName; })) {
        return "there is no bank called " + oldName;
    }
    for (s1::Preset &preset : presets) { if (preset.bank == oldName) { preset.bank = wanted; } }
    const std::string problem = writeBankHolding(wanted);
    if (!problem.empty()) { refresh(); return problem; }
    const std::string removal = library.removeBank(oldName);
    for (std::string &bank : banks) { if (bank == oldName) { bank = wanted; } }
    rememberOrder();
    refresh();
    selectCategory(categoryIndexOfBank(wanted));
    return removal;
}

std::string PresetBrowser::removeBank(const std::string &name) {
    lastNotice.clear();
    if (std::none_of(banks.begin(), banks.end(), [&name](const std::string &bank) { return bank == name; })) {
        return "there is no bank called " + name;
    }
    if (banks.size() <= 1) { return "the last bank stays"; }
    const bool held = [this, &name] {
        const s1::Preset *preset = currentPreset();
        return preset != nullptr && preset->bank == name;
    }();
    presets.erase(std::remove_if(presets.begin(), presets.end(),
                                 [&name](const s1::Preset &preset) { return preset.bank == name; }),
                  presets.end());
    const std::string problem = library.removeBank(name);
    banks.erase(std::remove(banks.begin(), banks.end(), name), banks.end());
    rememberOrder();
    refresh();
    selectCategory(kBankStartingIndex);                 // the Mac shows the first bank afterwards
    if (held && !list.empty()) { setCurrent(list.front().uid); }
    return problem;
}

// MARK: - Import and export

std::string PresetBrowser::importFile(const std::string &fileName, const std::string &text) {
    lastNotice.clear();
    const nlohmann::json json = nlohmann::json::parse(text, nullptr, false);
    if (json.is_discarded()) { return "that file is not a preset: it is not JSON"; }
    const s1::PresetDefaults &defaults = library.presetDefaults();

    if (json.is_array()) {
        std::vector<s1::Preset> imported = s1::Preset::bankFromJSON(json, defaults);
        if (imported.empty()) { return "that bank has no presets in it"; }
        std::string stem = fileName;
        const size_t dot = stem.find_last_of('.');
        if (dot != std::string::npos && dot > 0) { stem = stem.substr(0, dot); }
        stem = trimmed(stem);
        if (stem.empty()) { stem = "Imported"; }
        if (std::any_of(banks.begin(), banks.end(), [&stem](const std::string &bank) { return lowercased(bank) == lowercased(stem); })) {
            // The Mac's words, and its " [rename]".
            lastNotice = "There is already a bank called '" + stem + "'. This one came in as '" + stem + " [rename]'.";
            stem = unusedBankName(stem + " [rename]");
        }
        for (size_t i = 0; i < imported.size(); ++i) {
            imported[i].uid = s1::Preset::newUID();
            imported[i].bank = stem;
            imported[i].position = int(i);
            presets.push_back(imported[i]);
        }
        const std::string problem = writeBankHolding(stem);
        if (problem.empty()) { banks.push_back(stem); rememberOrder(); }
        refresh();
        selectCategory(categoryIndexOfBank(stem));
        if (!list.empty()) { setCurrent(list.front().uid); }
        return problem;
    }

    if (!json.is_object()) { return "that file is not a preset"; }
    const std::string bank = userBankName();
    s1::Preset preset = s1::Preset::fromJSON(json, defaults);
    preset.uid = s1::Preset::newUID();
    preset.bank = bank;
    preset.isUser = true;
    preset.isFavorite = false;
    preset.position = countIn(bank);
    const std::string uid = preset.uid;
    presets.push_back(std::move(preset));
    const std::string problem = writeBankHolding(bank);
    refresh();
    selectCategory(categoryIndexOfBank(bank));
    setCurrent(uid);
    return problem;
}

std::string PresetBrowser::presetJSON(const std::string &uid) const {
    const s1::Preset *preset = presetWithUID(uid);
    return preset == nullptr ? std::string() : preset->toJSON().dump(1);
}

std::string PresetBrowser::bankJSON(const std::string &bankName) const {
    nlohmann::json array = nlohmann::json::array();
    for (const s1::Preset &preset : presets) { if (preset.bank == bankName) { array.push_back(preset.toJSON()); } }
    return array.dump(1);
}

} // namespace s1plugin
