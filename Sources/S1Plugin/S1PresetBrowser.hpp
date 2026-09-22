//
//  S1PresetBrowser.hpp
//  Arcade Ruins
//
//  X3-4 (ADR-086): what the preset browser DOES, with no JUCE in it — the model the panel is a
//  view of, so every operation can be driven and measured with no window (`PluginPresetBrowser`).
//
//  It is a port of the Mac browser's own logic, file for file: `PresetsViewController` and its
//  extensions (`loadBanks`, `sortPresets`, New, Reorder, Import, Import Bank, delete),
//  `PresetsCategoriesViewController` (the category rows and their numbers),
//  `Presets+PresetCellDelegate` (star, duplicate, share) and `Presets+BankPopOverDelegate`
//  (rename and delete a bank). The numbers are upstream's: a category row's index is the same
//  integer here as there, because the sorting is written against it.
//
//  THE BANKS ARE FILES. The Mac writes the thirteen bundled bank files into its Documents folder
//  the first time it runs (`loadBanks`) and never reads the bundle again; from then on a bank is
//  a file the person owns, which is what makes reordering, renaming and starring a FACTORY preset
//  work at all. This does the same, into the folder every format on the machine shares
//  (`S1SharedPresets::defaultUserDirectory`), and for the same reason. What a HOST stores is
//  untouched by any of it: `PresetLibrary::factoryProgram` still reads the banks linked into the
//  binary, so program 137 is the same sound after the person has reordered their copy of BankA.
//
//  The bundled banks are twelve in the browser, not thirteen: `Bonus.json`'s presets say
//  `"bank": "BankA"` inside, and the Mac appends them to BankA (ADR-040). The order is
//  AppSettings.swift's `initBanks`, transcribed below; a bank made later goes after them, and the
//  order lives in `banks.order` beside the banks — not a ".json", so the library never reads it
//  as a bank.
//
#pragma once

#include <array>
#include <random>
#include <string>
#include <vector>

#include "S1PresetLibrary.hpp"

namespace s1plugin {

/// A row of the category table: the seven categories, Alphabetical, Favorites, then the banks.
struct BrowserCategory {
    std::string title;        ///< the row's words, as the Mac writes them ("Arp/Seq", "⌾ BankA")
    bool isBank = false;
    std::string bank;         ///< the bank's name when `isBank`, else empty
};

class PresetBrowser {
public:
    /// upstream's `PresetCategory.categoryCount`. It is Pluck's raw value, so there are SEVEN
    /// category rows (0…6) — the name is upstream's and the arithmetic below depends on it.
    static constexpr int kCategoryCount = 6;
    static constexpr int kAlphabeticalIndex = kCategoryCount + 1;    ///< 7
    static constexpr int kFavouritesIndex = kCategoryCount + 2;      ///< 8
    static constexpr int kBankStartingIndex = kCategoryCount + 3;    ///< 9 — `PresetCategory.bankStartingIndex`
    /// Where the banks' order is kept, beside them. Deliberately not ".json".
    static constexpr const char *kOrderFileName = "banks.order";
    /// AppSettings.swift's `initBanks`: the banks the Mac starts with, in the order it lists them.
    static const std::array<const char *, 12> initialBankOrder;
    /// `PresetCategory.description()` for 0…6, else "".
    static const char *categoryName(int category);

    /// The library must outlive the browser. Nothing is read or written until `load`.
    explicit PresetBrowser(PresetLibrary &);

    /// Reads the user folder, writing any of the twelve bundled banks that has no file yet.
    /// Everything after this call works on what was read. Never the audio thread.
    void load();
    bool isLoaded() const { return loaded; }
    /// Reads the folder again without seeding — after another instance has written, or after an
    /// operation. Keeps the chosen category and the current preset.
    void refresh();
    /// What could not be read, as the library reported it ("<file>: <why>"). Empty is well.
    const std::vector<std::string> &problems() const { return lastProblems; }

    // MARK: the lists
    const std::vector<std::string> &bankNames() const { return banks; }
    const std::vector<BrowserCategory> &categories() const { return categoryRows; }
    int categoryIndex() const { return category; }
    /// Out of range is ignored, as a table's row cannot be.
    void selectCategory(int index);
    /// The name of the bank the chosen row shows, or "" for All, a category, Alphabetical or Favorites.
    std::string shownBank() const;
    /// The row the CATEGORY LIST should show as chosen for a bank, or -1.
    int categoryIndexOfBank(const std::string &bank) const;

    /// Name or notes, as the Mac's search screen matches them; empty shows the category's presets.
    void setSearch(const std::string &text);
    const std::string &search() const { return searchText; }

    /// What the preset list shows, in its order.
    const std::vector<s1::Preset> &shown() const { return list; }
    /// Every preset of every bank, in bank order then position.
    const std::vector<s1::Preset> &all() const { return presets; }

    // MARK: what is playing
    void setCurrent(const std::string &uid);
    const std::string &currentUID() const { return current; }
    const s1::Preset *currentPreset() const { return presetWithUID(current); }
    const s1::Preset *presetWithUID(const std::string &uid) const;
    /// Its row in the shown list, or -1 — the number the toolbar shows before the name.
    int currentRow() const;
    /// The next or previous preset of the SHOWN list, wrapping; nothing while it is empty.
    /// It becomes the current one.
    const s1::Preset *step(int direction);
    /// `randomPreset`: another preset of the shown list, never the one playing.
    const s1::Preset *randomPreset();

    // MARK: the operations
    // Each one writes a bank file and re-reads the folder. Empty on success, else what went
    // wrong, in words for the status bar. Never the audio thread.

    /// New: an Init preset at the end of the User bank, chosen, with the User bank shown.
    std::string createPreset();
    /// The "+" beside PRESETS: "Bank<n>" with one Init preset in it, shown.
    std::string createBank();
    /// Duplicate: a copy of `uid` in the User bank, named "… [copy]", chosen and shown.
    std::string duplicate(const std::string &uid);
    /// The star.
    std::string toggleFavourite(const std::string &uid);
    /// The preset editor's Save (and the toolbar's, which opens it): the preset keeps its place
    /// and takes `sound`'s 150 values, this name, this category and this bank.
    std::string savePreset(const std::string &uid, const s1::Preset &sound,
                           const std::string &name, int category, const std::string &bank);
    /// The notes field under the list: the preset keeps its sound and takes these words.
    std::string setNotes(const std::string &uid, const std::string &text);
    /// Swipe to delete. The last preset of the library is kept, as upstream keeps it.
    std::string removePreset(const std::string &uid);
    /// Reorder: the shown row `from` becomes the row `to`. Only while a bank is shown.
    std::string movePreset(int from, int to);
    /// The bank editor's Save: every preset in it moves with the file.
    std::string renameBank(const std::string &oldName, const std::string &newName);
    /// The bank editor's Delete.
    std::string removeBank(const std::string &name);

    /// Import / Import Bank: the text of a file the person chose, and its name. A JSON array is
    /// a bank taking the file's name (" [rename]" appended when that name is taken — the Mac's
    /// word, in `notice()`); anything else is one preset, into the User bank. A bank exported by
    /// the Mac app is a JSON array: it opens here unchanged.
    std::string importFile(const std::string &fileName, const std::string &text);
    /// What Share writes: one preset as a file's text, the Mac's format.
    std::string presetJSON(const std::string &uid) const;
    /// A bank as a file's text, for Export Bank.
    std::string bankJSON(const std::string &bankName) const;

    /// Something the last operation wants said that is not a failure. Cleared by the next one.
    const std::string &notice() const { return lastNotice; }

private:
    void readFolder();
    void buildCategories();
    void sortPresets();                                   ///< `sortPresets`, and the search
    std::string writeBankHolding(const std::string &bankName);   ///< the bank's presets from `presets`, renumbered
    void rememberOrder();
    std::vector<std::string> readOrder() const;
    /// A name no bank has ("Bank3", "Bank3 [rename]" …).
    std::string unusedBankName(const std::string &wanted) const;
    int countIn(const std::string &bankName) const;       ///< how many presets that bank holds
    s1::Preset *find(const std::string &uid);
    const std::string userBankName() const;               ///< "User", or the first bank if it is gone

    PresetLibrary &library;
    bool loaded = false;
    bool seeded = false;
    std::vector<std::string> banks;                       ///< in the browser's order
    std::vector<BrowserCategory> categoryRows;
    std::vector<s1::Preset> presets;                      ///< every bank's, in bank order
    std::vector<s1::Preset> list;                         ///< what the table shows
    std::vector<std::string> lastProblems;
    std::string lastNotice;
    std::string searchText;
    std::string current;
    int category = 0;
    std::mt19937 dice { std::random_device {}() };
};

} // namespace s1plugin
