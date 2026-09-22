// X3-4 (ADR-086): the preset browser's model, with no window and no JUCE component in sight —
// the folder it seeds, the category rows and their numbers, what each row shows, the search, and
// every operation the Mac browser performs: New, New Bank, duplicate, star, save, delete,
// reorder, rename and delete a bank, import and export.
//
// Every test works in a folder of its own under the system's temporary folder. The real one is
// the owner's; nothing here may read it, let alone write in it.
//
//   argv[1]  Sources/SynthOneCore/Presets/Data   the Mac app's bank files, for the import test
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "S1PresetBrowser.hpp"
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

int countInBank(const s1plugin::PresetBrowser &browser, const std::string &bank) {
    return int(std::count_if(browser.all().begin(), browser.all().end(),
                             [&bank](const s1::Preset &preset) { return preset.bank == bank; }));
}

bool hasBank(const s1plugin::PresetBrowser &browser, const std::string &bank) {
    const std::vector<std::string> &banks = browser.bankNames();
    return std::find(banks.begin(), banks.end(), bank) != banks.end();
}

/// The row the list shows a preset at, or -1.
int rowOf(const s1plugin::PresetBrowser &browser, const std::string &uid) {
    for (size_t i = 0; i < browser.shown().size(); ++i) { if (browser.shown()[i].uid == uid) { return int(i); } }
    return -1;
}

const s1::Preset *named(const s1plugin::PresetBrowser &browser, const std::string &name) {
    for (const s1::Preset &preset : browser.all()) { if (preset.name == name) { return &preset; } }
    return nullptr;
}

} // namespace

int main(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc != 2) { std::printf("usage: PluginPresetBrowserTests <bank dir>\n"); return 2; }
    const fs::path bankDirectory = argv[1];

    const fs::path scratch = fs::temp_directory_path() / ("ArcadeRuinsBrowserTests-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    const fs::path userFolder = scratch / "Banks \xC3\xA9";      // a folder name beyond ASCII, on purpose

    S1PluginProcessor processor;
    s1plugin::PresetLibrary &library = processor.presetLibrary();
    library.setUserDirectory(userFolder.u8string());

    // MARK: the folder the Mac would have written
    s1plugin::PresetBrowser browser(library);
    {
        check(!fs::exists(userFolder), "making a browser touches no disk", 0);
        browser.load();
        const int files = int(std::count_if(fs::directory_iterator(userFolder), fs::directory_iterator {},
                                            [](const fs::directory_entry &entry) { return entry.path().extension() == ".json"; }));
        check(files == 12, "the first load writes the twelve banks the Mac starts with, as files", files);
        check(browser.bankNames().size() == 12, "and the browser lists twelve banks", double(browser.bankNames().size()));
        check(browser.bankNames().front() == "BankA" && browser.bankNames()[1] == "User",
              "in AppSettings' order — BankA, then User — not the folder's alphabetical one", 0);
        check(browser.bankNames().back() == "Starter Bank", "…down to Starter Bank", 0);
        check(!hasBank(browser, "Bonus"), "there is no Bonus bank: its presets belong to BankA (ADR-040)", 0);
        check(browser.problems().empty(), "nothing in the folder could not be read", double(browser.problems().size()));

        const int bankA = countInBank(browser, "BankA");
        check(bankA == 41 + 94, "BankA holds its own 41 presets and Bonus's 94", bankA);
        const bool uniqueUIDs = [&browser] {
            std::vector<std::string> uids;
            for (const s1::Preset &preset : browser.all()) { uids.push_back(preset.uid); }
            std::sort(uids.begin(), uids.end());
            return std::adjacent_find(uids.begin(), uids.end()) == uids.end() && uids.front() != "";
        }();
        // The shipped banks hold 670 different uids for 695 presets: 23 are used twice.
        check(uniqueUIDs, "every preset has a uid of its own, whatever the shipped banks do", 0);
        check(browser.all().size() == 695, "and the browser holds all 695 factory presets, each once", double(browser.all().size()));
    }

    // MARK: the category rows are upstream's, and so are their numbers
    {
        const std::vector<s1plugin::BrowserCategory> &rows = browser.categories();
        check(rows.size() == 7 + 2 + 12, "seven categories, Alphabetical, Favorites, then a row per bank", double(rows.size()));
        check(rows[0].title == "All" && rows[1].title == "Arp/Seq" && rows[6].title == "Pluck", "the categories read as the Mac's", 0);
        check(rows[size_t(s1plugin::PresetBrowser::kAlphabeticalIndex)].title == "Alphabetical"
                  && rows[size_t(s1plugin::PresetBrowser::kFavouritesIndex)].title == "Favorites",
              "Alphabetical at 7 and Favorites at 8, as PresetCategory numbers them", 0);
        check(s1plugin::PresetBrowser::kBankStartingIndex == 9 && rows[9].isBank && rows[9].bank == "BankA",
              "the banks start at 9 (PresetCategory.bankStartingIndex)", 0);
        check(rows[9].title == "\xE2\x8C\xBE BankA", "a bank's row is marked with the Mac's sign", 0);
    }

    // MARK: what each row shows (`sortPresets`)
    {
        browser.selectCategory(0);
        check(browser.shown().size() == browser.all().size(), "All shows every preset", double(browser.shown().size()));
        check(browser.shown().front().bank == "BankA", "…in bank order", 0);

        browser.selectCategory(1);
        const bool onlyArp = std::all_of(browser.shown().begin(), browser.shown().end(),
                                         [](const s1::Preset &preset) { return preset.category == 1; });
        check(onlyArp && !browser.shown().empty(), "Arp/Seq shows the presets whose category is 1", double(browser.shown().size()));

        browser.selectCategory(s1plugin::PresetBrowser::kAlphabeticalIndex);
        const bool sorted = std::is_sorted(browser.shown().begin(), browser.shown().end(), [](const s1::Preset &a, const s1::Preset &b) {
            std::string first = a.name, second = b.name;
            std::transform(first.begin(), first.end(), first.begin(), [](unsigned char c) { return char(std::tolower(c)); });
            std::transform(second.begin(), second.end(), second.begin(), [](unsigned char c) { return char(std::tolower(c)); });
            return first < second;
        });
        check(sorted && browser.shown().size() == browser.all().size(), "Alphabetical shows them all, by name", double(browser.shown().size()));

        browser.selectCategory(s1plugin::PresetBrowser::kFavouritesIndex);
        const bool onlyStarred = std::all_of(browser.shown().begin(), browser.shown().end(),
                                             [](const s1::Preset &preset) { return preset.isFavorite; });
        check(onlyStarred, "Favorites shows the starred presets and nothing else", double(browser.shown().size()));

        browser.selectCategory(10);      // the User bank
        check(browser.shownBank() == "User" && !browser.shown().empty(), "a bank's row shows that bank's presets", double(browser.shown().size()));
        const bool byPosition = std::is_sorted(browser.shown().begin(), browser.shown().end(),
                                               [](const s1::Preset &a, const s1::Preset &b) { return a.position <= b.position; });
        check(byPosition, "…in their own order", 0);
    }

    // MARK: the search — the Mac's rule, name or notes, by name
    {
        browser.selectCategory(0);
        browser.setSearch("pressing on");
        const bool found = !browser.shown().empty() && browser.shown().front().name.find("Pressing On") != std::string::npos;
        check(found, "a search finds a preset by name, whatever bank it is in", double(browser.shown().size()));
        const size_t byName = browser.shown().size();
        browser.setSearch("AudioKit Synth One");
        check(browser.shown().size() > byName, "…and by its notes", double(browser.shown().size()));
        browser.setSearch("");
        check(browser.shown().size() == browser.all().size(), "an empty search puts the category's list back", double(browser.shown().size()));
    }

    // MARK: stepping the shown list
    {
        browser.selectCategory(9);                        // BankA, which has more than one
        browser.setCurrent(browser.shown().front().uid);
        const s1::Preset *next = browser.step(1);
        check(next != nullptr && browser.currentRow() == 1, "next walks the shown list", browser.currentRow());
        browser.setCurrent(browser.shown().front().uid);
        const s1::Preset *previous = browser.step(-1);
        check(previous != nullptr && browser.currentRow() == int(browser.shown().size()) - 1, "previous from the first wraps to the last", browser.currentRow());
    }

    // MARK: New
    std::string newUID;
    {
        const int before = countInBank(browser, "User");
        const std::string problem = browser.createPreset();
        newUID = browser.currentUID();
        check(problem.empty(), "New: " + (problem.empty() ? std::string("saved") : problem), 0);
        check(countInBank(browser, "User") == before + 1, "New puts an Init preset at the end of the User bank", countInBank(browser, "User"));
        check(browser.shownBank() == "User", "…and shows the User bank", 0);
        check(browser.currentPreset() != nullptr && browser.currentPreset()->name == "Init", "…chosen", 0);
        check(rowOf(browser, newUID) == int(browser.shown().size()) - 1, "…as the last row", rowOf(browser, newUID));
    }

    // MARK: the star
    {
        browser.selectCategory(s1plugin::PresetBrowser::kFavouritesIndex);
        const int starredBefore = int(browser.shown().size());
        const std::string problem = browser.toggleFavourite(newUID);
        check(problem.empty(), "the star: " + (problem.empty() ? std::string("saved") : problem), 0);
        browser.selectCategory(s1plugin::PresetBrowser::kFavouritesIndex);
        check(rowOf(browser, newUID) >= 0 && int(browser.shown().size()) == starredBefore + 1,
              "a starred preset joins Favorites", double(browser.shown().size()));
        browser.toggleFavourite(newUID);
        browser.selectCategory(s1plugin::PresetBrowser::kFavouritesIndex);
        check(rowOf(browser, newUID) < 0 && int(browser.shown().size()) == starredBefore, "and unstarred it leaves", double(browser.shown().size()));
        browser.toggleFavourite(newUID);
    }

    // MARK: duplicate
    {
        const int before = countInBank(browser, "User");
        const std::string problem = browser.duplicate(newUID);
        check(problem.empty(), "duplicate: " + (problem.empty() ? std::string("saved") : problem), 0);
        check(countInBank(browser, "User") == before + 1, "a copy joins the User bank", countInBank(browser, "User"));
        const s1::Preset *copy = browser.currentPreset();
        check(copy != nullptr && copy->name == "Init [copy]", "named as the Mac names it", 0);
        check(copy != nullptr && copy->uid != newUID, "with a uid of its own", 0);
        check(copy != nullptr && copy->isFavorite, "…and everything else the original had", 0);
        browser.removePreset(browser.currentUID());
    }

    // MARK: save — the preset editor's name, category and bank, and the sound as it stands
    {
        s1::Preset sound = library.initialPreset();
        sound.cutoff = 1234.0;
        sound.userText = "written by the browser's test";
        const std::string problem = browser.savePreset(newUID, sound, "  A Test Sound  ", 4, "User");
        check(problem.empty(), "save: " + (problem.empty() ? std::string("saved") : problem), 0);
        const s1::Preset *saved = browser.currentPreset();
        check(saved != nullptr && saved->name == "A Test Sound", "the name is taken, trimmed", 0);
        check(saved != nullptr && saved->category == 4, "and the category", saved != nullptr ? saved->category : -1);
        check(saved != nullptr && saved->cutoff == 1234.0, "and the sound's own values", saved != nullptr ? saved->cutoff : 0);
        check(saved != nullptr && saved->uid == newUID, "the preset keeps its uid: it is the same preset", 0);
        check(browser.savePreset(newUID, sound, "   ", 0, "User") == "the preset needs a name", "a preset with no name is refused", 0);

        // Moving it to another bank
        const int inBankA = countInBank(browser, "BankA");
        const std::string moved = browser.savePreset(newUID, sound, "A Test Sound", 4, "BankA");
        check(moved.empty() && countInBank(browser, "BankA") == inBankA + 1, "saving into another bank moves it there", countInBank(browser, "BankA"));
        check(countInBank(browser, "User") == 1, "…and out of the one it was in", countInBank(browser, "User"));
        browser.savePreset(newUID, sound, "A Test Sound", 4, "User");
    }

    // MARK: delete
    {
        const int before = countInBank(browser, "User");
        browser.selectCategory(browser.categoryIndexOfBank("User"));
        browser.setCurrent(newUID);
        const int row = rowOf(browser, newUID);
        const std::string problem = browser.removePreset(newUID);
        check(problem.empty(), "delete: " + (problem.empty() ? std::string("saved") : problem), 0);
        check(countInBank(browser, "User") == before - 1, "the preset is gone from its bank", countInBank(browser, "User"));
        check(browser.presetWithUID(newUID) == nullptr, "…and from the library", 0);
        check(browser.currentUID() == browser.shown()[size_t(std::max(0, row - 1))].uid, "what plays is the preset above it, as on the Mac", 0);
    }

    // MARK: reorder
    {
        browser.selectCategory(browser.categoryIndexOfBank("Starter Bank"));
        const std::string first = browser.shown()[0].uid, third = browser.shown()[2].uid;
        const std::string problem = browser.movePreset(0, 2);
        check(problem.empty(), "reorder: " + (problem.empty() ? std::string("saved") : problem), 0);
        check(browser.shown()[2].uid == first && browser.shown()[1].uid == third, "the row moved down two, and the others came up", 0);
        check(browser.shown()[2].position == 2, "positions are written from the top of the bank", browser.shown()[2].position);

        browser.selectCategory(0);
        check(browser.movePreset(0, 2) == "reordering is for a bank's own list", "…and it is refused in a view that is not a bank's", 0);
    }

    // MARK: what the host stores is untouched by any of it
    {
        check(processor.getNumPrograms() == 695, "the host still has 695 programs", processor.getNumPrograms());
        check(library.factoryProgramName(0) == "BankA: Synthwave 1974", "program 0 is the same sound it was before the folder was ever written", 0);
        const s1::Preset *program = library.factoryProgram(137);
        check(program != nullptr && !program->name.empty(), "and every program still answers", 0);
    }

    // MARK: the banks' order, and the current preset, survive a new browser on the same folder
    std::string starterFirst;
    {
        browser.selectCategory(browser.categoryIndexOfBank("Starter Bank"));
        starterFirst = browser.shown().front().uid;
        s1plugin::PresetBrowser reopened(library);
        reopened.load();
        check(reopened.bankNames() == browser.bankNames(), "a second browser reads the same banks in the same order", 0);
        reopened.selectCategory(reopened.categoryIndexOfBank("Starter Bank"));
        check(reopened.shown().front().uid == starterFirst, "…with the reordering that was done", 0);
        check(countInBank(reopened, "User") == 1, "…and the deletion", countInBank(reopened, "User"));
        const int files = int(std::count_if(fs::directory_iterator(userFolder), fs::directory_iterator {},
                                            [](const fs::directory_entry &entry) { return entry.path().extension() == ".json"; }));
        check(files == 12, "a second load writes no bank again: the files ARE the banks now", files);
        check(fs::exists(userFolder / s1plugin::PresetBrowser::kOrderFileName), "the banks' order is kept beside them", 0);
        check(reopened.problems().empty(), "…in a file the library does not read as a bank", double(reopened.problems().size()));
    }

    // MARK: New Bank
    {
        const std::string problem = browser.createBank();
        check(problem.empty(), "New Bank: " + (problem.empty() ? std::string("saved") : problem), 0);
        check(browser.bankNames().size() == 13 && browser.bankNames().back() == "Bank12", "a bank is added at the end, named as the Mac names it", double(browser.bankNames().size()));
        check(browser.shownBank() == "Bank12" && browser.shown().size() == 1, "shown, with one Init preset in it", double(browser.shown().size()));
        s1plugin::PresetBrowser reopened(library);
        reopened.load();
        check(reopened.bankNames().size() == 13 && reopened.bankNames().back() == "Bank12", "and it keeps its place at the end", double(reopened.bankNames().size()));
    }

    // MARK: the banks' order is the order they were MADE in, not the folder's
    {
        // A second new bank, renamed to sort first: without the order file beside them, a
        // reopened browser would read this one before Bank12 (the library lists files by name).
        browser.createBank();
        check(browser.bankNames().back() == "Bank13", "a second new bank", double(browser.bankNames().size()));
        check(browser.renameBank("Bank13", "AAA Sounds").empty(), "renamed to sort before the other", 0);
        s1plugin::PresetBrowser reopened(library);
        reopened.load();
        const std::vector<std::string> &names = reopened.bankNames();
        check(names.size() == 14 && names[12] == "Bank12" && names[13] == "AAA Sounds",
              "a reopened browser keeps them in the order they were made", double(names.size()));
        check(browser.removeBank("AAA Sounds").empty(), "…and it is put away again", 0);
    }

    // MARK: rename a bank
    {
        const std::string problem = browser.renameBank("Bank12", "  Owner's Sounds  ");
        check(problem.empty(), "rename a bank: " + (problem.empty() ? std::string("saved") : problem), 0);
        check(hasBank(browser, "Owner's Sounds") && !hasBank(browser, "Bank12"), "the bank is under its new name", 0);
        check(!fs::exists(userFolder / "Bank12.json"), "the old file is gone", 0);
        check(countInBank(browser, "Owner's Sounds") == 1, "its presets moved with it", countInBank(browser, "Owner's Sounds"));
        check(browser.shownBank() == "Owner's Sounds", "…and it is the bank being shown", 0);
        check(browser.renameBank("Owner's Sounds", "BankA") == "there is already a bank called BankA", "a name another bank has is refused", 0);
        check(browser.renameBank("Owner's Sounds", "   ") == "the bank needs a name", "and so is no name at all", 0);
    }

    // MARK: import a bank the Mac app exported — unchanged
    {
        const std::string text = readFile(bankDirectory / "Starter Bank.json");
        check(!text.empty(), "the Mac app's Starter Bank.json is there to import", double(text.size()));
        const std::string problem = browser.importFile("Starter Bank.json", text);
        check(problem.empty(), "import a bank: " + (problem.empty() ? std::string("imported") : problem), 0);
        check(!browser.notice().empty(), "the name was taken, and the browser says so: " + browser.notice(), 0);
        check(hasBank(browser, "Starter Bank [rename]"), "…and it came in under the Mac's own ' [rename]'", 0);
        check(browser.shownBank() == "Starter Bank [rename]", "the imported bank is shown", 0);

        // Every preset, in the file's order, with the file's values.
        const s1plugin::PresetBank *linked = nullptr;
        for (const s1plugin::PresetBank &bank : library.factoryBanks()) { if (bank.name == "Starter Bank") { linked = &bank; } }
        check(linked != nullptr && browser.shown().size() == linked->presets.size(), "every preset in the file came in", double(browser.shown().size()));
        int sameName = 0, sameSound = 0;
        if (linked != nullptr) {
            for (size_t i = 0; i < browser.shown().size() && i < linked->presets.size(); ++i) {
                if (browser.shown()[i].name == linked->presets[i].name) { ++sameName; }
                if (browser.shown()[i].cutoff == linked->presets[i].cutoff
                    && browser.shown()[i].attackDuration == linked->presets[i].attackDuration
                    && browser.shown()[i].seqPatternNote == linked->presets[i].seqPatternNote) { ++sameSound; }
            }
        }
        check(linked != nullptr && sameName == int(linked->presets.size()), "under their own names, in the file's order", sameName);
        check(linked != nullptr && sameSound == int(linked->presets.size()), "and with the sounds the file holds", sameSound);
        const bool freshUIDs = std::none_of(browser.shown().begin(), browser.shown().end(), [&linked](const s1::Preset &preset) {
            return std::any_of(linked->presets.begin(), linked->presets.end(), [&preset](const s1::Preset &had) { return had.uid == preset.uid; });
        });
        check(freshUIDs, "each one with a uid of its own, so it is not the bank it was copied from", 0);
        browser.removeBank("Starter Bank [rename]");
    }

    // MARK: import one preset
    {
        browser.selectCategory(browser.categoryIndexOfBank("BankA"));
        const s1::Preset *one = named(browser, "Synthwave 1974");
        check(one != nullptr, "there is a preset to export", 0);
        const std::string json = one != nullptr ? browser.presetJSON(one->uid) : std::string();
        check(json.size() > 100 && json.front() == '{', "Share writes one preset as a JSON object", double(json.size()));
        const int before = countInBank(browser, "User");
        const std::string problem = browser.importFile("Sawtastic.synth1", json);
        check(problem.empty(), "import a preset: " + (problem.empty() ? std::string("imported") : problem), 0);
        check(countInBank(browser, "User") == before + 1, "one preset goes into the User bank", countInBank(browser, "User"));
        const s1::Preset *back = browser.currentPreset();
        check(back != nullptr && one != nullptr && back->name == one->name && back->cutoff == one->cutoff
                  && back->seqPatternNote == one->seqPatternNote,
              "…the sound it was written from", 0);
        check(back != nullptr && one != nullptr && back->uid != one->uid, "with a uid of its own", 0);
        check(browser.importFile("nonsense.json", "this is not JSON") == "that file is not a preset: it is not JSON", "something that is not a preset is refused", 0);
    }

    // MARK: delete a bank
    {
        const int presetsBefore = int(browser.all().size());
        const int inBank = countInBank(browser, "Owner's Sounds");
        const std::string problem = browser.removeBank("Owner's Sounds");
        check(problem.empty(), "delete a bank: " + (problem.empty() ? std::string("gone") : problem), 0);
        check(!hasBank(browser, "Owner's Sounds"), "the bank is gone from the list", 0);
        check(!fs::exists(userFolder / "Owner's Sounds.json"), "…and its file with it", 0);
        check(int(browser.all().size()) == presetsBefore - inBank, "its presets went too", double(browser.all().size()));
        check(browser.removeBank("Owner's Sounds") == "there is no bank called Owner's Sounds", "a bank that is not there is refused", 0);
    }

    std::error_code error;
    fs::remove_all(scratch, error);
    std::printf("\n%s: PluginPresetBrowserTests\n", failures == 0 ? "PASSED" : "FAILED");
    return failures == 0 ? 0 : 1;
}
