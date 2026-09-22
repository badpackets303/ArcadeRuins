//
//  S1PresetPanel.h
//  Arcade Ruins
//
//  X3-4 (ADR-086): the preset browser's card — the Mac desktop layout's drop-down
//  (`S1DesktopLayout.buildPresetPanel`), 380 x 720, hung under the toolbar's preset name: PRESETS
//  and New Bank, the search field, the categories and banks at 228 points, the presets of the
//  selection, the chosen preset's category and notes, and New / Import / Reorder / Import Bank.
//
//  It is a VIEW. What every operation does is `s1plugin::PresetBrowser`'s, which has no JUCE in
//  it and is driven by `PluginPresetBrowserTests` with no window; this draws the model's lists in
//  the skin's colours, and turns a click into one of its calls. Everything here can also be
//  driven without a mouse (`chooseRow`, `pressButton`, `pressRowButton`), which is how
//  `PluginEditorTests` works the panel.
//
#pragma once

#include <functional>
#include <memory>

#include <juce_gui_basics/juce_gui_basics.h>

#include "../S1PresetBrowser.hpp"
#include "S1KitStyle.h"

namespace s1ui {

class PresetPanel final : public juce::Component {
public:
    /// The Mac's card. `S1DesktopTheme.presetPanelWidth` / `presetPanelHeight`.
    static constexpr int kWidth = 380, kHeight = 720;
    /// The Mac's row heights under the desktop layout.
    static constexpr int kPresetRowHeight = 30, kCategoryRowHeight = 38, kCategoryListHeight = 228;

    /// Both must outlive the panel.
    PresetPanel(s1plugin::PresetBrowser &, const Style &);
    ~PresetPanel() override;

    /// A person chose this preset: play it.
    std::function<void(const s1::Preset &)> onChoose;
    /// Something to say in the status bar.
    std::function<void(const juce::String &)> onSay;
    /// The sound as it stands, with the current preset's name and notes — what Save keeps and
    /// what Share writes.
    std::function<s1::Preset()> soundNow;
    /// Put the card away.
    std::function<void()> onClose;

    /// The lists again from the model, keeping the chosen row in view.
    void refresh();
    /// Opens the preset editor over the card, on the preset that is playing: the toolbar's Save.
    void editCurrentPreset();

    void paint(juce::Graphics &) override;
    void resized() override;
    bool keyPressed(const juce::KeyPress &) override;

    // MARK: driving it without a mouse (tests, and the keyboard)
    int rowCount() const;
    /// Chooses the row, as a click on it does: the preset is played.
    void chooseRow(int row);
    void chooseCategory(int row);
    /// "new", "newBank", "import", "importBank", "reorder", "save". False: no such button.
    bool pressButton(const juce::String &id);
    /// "star", "rename", "duplicate", "share" — or, while reordering, "up" and "down", which are
    /// the only marks a row carries then. False: no such row, or not a mark this row is showing.
    bool pressRowButton(int row, const juce::String &which);
    bool isReordering() const { return reordering; }
    void setSearch(const juce::String &);
    juce::String searchText() const;
    juce::String notes() const;
    void setNotes(const juce::String &);
    /// The card over the card — the preset or bank editor — or nothing.
    juce::Component *editorCard() const;
    /// What the editor card is showing, for a test that fills it in.
    void editorCardSave(const juce::String &name, int category, const juce::String &bank);
    void editorCardDelete();

private:
    class RowList;
    class PresetRow;
    class CategoryRow;
    class EditorCard;

    void chooseAndPlay(const s1::Preset &);
    void report(const std::string &problem, const juce::String &done);
    void moveRow(int row, int by);                ///< while reordering: the row's ▲ / ▾
    void editPreset(const s1::Preset &);
    void editBankOfRow(int categoryRow);
    void openEditorCard(std::unique_ptr<EditorCard>);
    void closeEditorCard();
    void importFile(bool wholeBank);
    void shareRow(int row);

    s1plugin::PresetBrowser &browser;
    const Style &style;
    std::unique_ptr<RowList> presetList, categoryList;
    std::unique_ptr<juce::TextEditor> searchField, notesField;
    std::unique_ptr<juce::Label> categoryLabel;
    struct Item { juce::String id, title; std::unique_ptr<juce::TextButton> button; };
    std::vector<Item> buttons;
    std::unique_ptr<EditorCard> card;
    std::unique_ptr<juce::FileChooser> chooser;
    bool reordering = false;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(PresetPanel)
};

} // namespace s1ui
