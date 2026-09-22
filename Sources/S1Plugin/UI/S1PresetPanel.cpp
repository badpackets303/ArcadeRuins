//
//  S1PresetPanel.cpp
//  Arcade Ruins
//
//  X3-4 (ADR-086). See the header.
//
#include "S1PresetPanel.h"

namespace s1ui {

namespace {

/// The four marks a preset row carries, from the trailing edge in the Mac's order.
constexpr int kZoneSize = 22, kZoneGap = 4, kZoneMargin = 8;

/// The zone a click at `x` is in, of `count` of them at the row's trailing edge; -1 outside.
int zoneAt(float x, int width, int count) {
    for (int i = 0; i < count; ++i) {
        const float right = float(width - kZoneMargin - i * (kZoneSize + kZoneGap));
        if (x <= right && x >= right - float(kZoneSize)) { return i; }
    }
    return -1;
}

juce::Rectangle<float> zoneBounds(int index, int width, int height) {
    const float right = float(width - kZoneMargin - index * (kZoneSize + kZoneGap));
    return juce::Rectangle<float>(right - float(kZoneSize), float(height - kZoneSize) * 0.5f, float(kZoneSize), float(kZoneSize));
}

juce::String text(const std::string &from) { return juce::String::fromUTF8(from.c_str()); }

} // namespace

// MARK: - The lists

/// Both tables: the presets of the selection, and the categories and banks. A row's marks are
/// hit-tested by where the click landed, so the list needs no component per row.
class PresetPanel::RowList final : public juce::ListBox, private juce::ListBoxModel {
public:
    RowList(PresetPanel &owner, bool presets) : panel(owner), isPresets(presets) {
        setModel(this);
        setRowHeight(presets ? kPresetRowHeight : kCategoryRowHeight);
        setColour(juce::ListBox::backgroundColourId, juce::Colours::transparentBlack);
        setColour(juce::ListBox::outlineColourId, juce::Colours::transparentBlack);
        setOutlineThickness(0);
        getViewport()->setScrollBarsShown(true, false);
        setTitle(presets ? "Presets" : "Categories and banks");
    }

    int getNumRows() override {
        return isPresets ? int(panel.browser.shown().size()) : int(panel.browser.categories().size());
    }

    void paintListBoxItem(int row, juce::Graphics &g, int width, int height, bool selected) override {
        const Style &dress = panel.style;
        if (selected) {
            g.setColour(dress.colour("accent").withAlpha(0.22f));
            g.fillRect(0, 0, width, height);
            g.setColour(dress.colour("accent"));
            g.fillRect(0, 0, 2, height);
        }
        g.setColour(dress.colour("sectionBorder").withAlpha(0.6f));
        g.fillRect(0, height - 1, width, 1);

        if (!isPresets) {
            const std::vector<s1plugin::BrowserCategory> &rows = panel.browser.categories();
            if (row < 0 || row >= int(rows.size())) { return; }
            g.setColour(dress.colour(rows[size_t(row)].isBank ? "text" : "label"));
            g.setFont(dress.font(13.0f, rows[size_t(row)].isBank ? FontWeight::regular : FontWeight::medium));
            g.drawText(text(rows[size_t(row)].title), 12, 0, width - 12 - kZoneMargin - kZoneSize, height, juce::Justification::centredLeft, true);
            if (rows[size_t(row)].isBank) {
                g.setColour(dress.colour("dim"));
                g.setFont(dress.font(13.0f));
                g.drawText(juce::String::fromUTF8("\xE2\x9C\x8E"), zoneBounds(0, width, height), juce::Justification::centred, false);
            }
            return;
        }

        const std::vector<s1::Preset> &presets = panel.browser.shown();
        if (row < 0 || row >= int(presets.size())) { return; }
        const s1::Preset &preset = presets[size_t(row)];
        const int marks = panel.reordering ? 2 : 4;
        g.setColour(dress.colour("text"));
        g.setFont(dress.font(13.0f));
        g.drawText(text(preset.name), 12, 0, width - 12 - kZoneMargin - marks * (kZoneSize + kZoneGap), height,
                   juce::Justification::centredLeft, true);
        g.setFont(dress.font(12.0f));
        if (panel.reordering) {
            g.setColour(dress.colour("dim"));
            g.drawText(juce::String::fromUTF8("\xE2\x96\xBE"), zoneBounds(0, width, height), juce::Justification::centred, false);
            g.drawText(juce::String::fromUTF8("\xE2\x96\xB4"), zoneBounds(1, width, height), juce::Justification::centred, false);
            return;
        }
        // Trailing edge first, as PresetCell lays them out: share, duplicate, rename, star.
        g.setColour(dress.colour("dim"));
        g.drawText(juce::String::fromUTF8("\xE2\xA4\xB4"), zoneBounds(0, width, height), juce::Justification::centred, false);
        g.drawText(juce::String::fromUTF8("\xE2\xA7\x89"), zoneBounds(1, width, height), juce::Justification::centred, false);
        g.drawText(juce::String::fromUTF8("\xE2\x9C\x8E"), zoneBounds(2, width, height), juce::Justification::centred, false);
        g.setColour(preset.isFavorite ? dress.colour("accent") : dress.colour("dim"));
        g.drawText(juce::String::fromUTF8(preset.isFavorite ? "\xE2\x98\x85" : "\xE2\x98\x86"), zoneBounds(3, width, height), juce::Justification::centred, false);
    }

    void listBoxItemClicked(int row, const juce::MouseEvent &event) override {
        const int marks = isPresets ? (panel.reordering ? 2 : 4) : 1;
        const int zone = zoneAt(event.position.x, getWidth(), marks);
        if (!isPresets) {
            if (zone == 0 && row < int(panel.browser.categories().size()) && panel.browser.categories()[size_t(row)].isBank) {
                panel.editBankOfRow(row);
                return;
            }
            panel.chooseCategory(row);
            return;
        }
        if (zone < 0) { panel.chooseRow(row); return; }
        if (panel.reordering) { panel.pressRowButton(row, zone == 0 ? "down" : "up"); return; }
        panel.pressRowButton(row, zone == 3 ? "star" : zone == 2 ? "rename" : zone == 1 ? "duplicate" : "share");
    }

    void returnKeyPressed(int row) override { if (isPresets) { panel.chooseRow(row); } else { panel.chooseCategory(row); } }

private:
    PresetPanel &panel;
    const bool isPresets;
};

// MARK: - The card over the card

/// The preset editor (`PresetEditorViewController`: a name, a category and a bank) and the bank
/// editor (`BankEditorViewController`: a name, and Delete). The Mac shows the category and the
/// bank as tables — a `UIPickerView` crashes there (ADR-033); here they are pop-up menus.
class PresetPanel::EditorCard final : public juce::Component {
public:
    EditorCard(const Style &s, const juce::String &heading, const juce::String &name,
               int category, const juce::String &bank, const std::vector<std::string> &banks, bool isBankEditor)
        : style(s), title(heading), bankEditor(isBankEditor) {
        setTitle(heading);
        nameField.setText(name, juce::dontSendNotification);
        nameField.setSelectAllWhenFocused(true);
        nameField.setTitle("Name");
        addAndMakeVisible(nameField);
        if (!bankEditor) {
            for (int i = 0; i <= s1plugin::PresetBrowser::kCategoryCount; ++i) {
                categoryMenu.addItem(s1plugin::PresetBrowser::categoryName(i), i + 1);
            }
            categoryMenu.setSelectedId(juce::jlimit(0, s1plugin::PresetBrowser::kCategoryCount, category) + 1, juce::dontSendNotification);
            categoryMenu.setTitle("Category");
            addAndMakeVisible(categoryMenu);
            for (size_t i = 0; i < banks.size(); ++i) { bankMenu.addItem(text(banks[i]), int(i) + 1); }
            for (size_t i = 0; i < banks.size(); ++i) { if (text(banks[i]) == bank) { bankMenu.setSelectedId(int(i) + 1, juce::dontSendNotification); } }
            if (bankMenu.getSelectedId() == 0 && !banks.empty()) { bankMenu.setSelectedId(1, juce::dontSendNotification); }
            bankMenu.setTitle("Bank");
            addAndMakeVisible(bankMenu);
        }
        save.setButtonText("Save");
        save.onClick = [this] { if (onSave) { onSave(nameField.getText(), categoryMenu.getSelectedId() - 1, bankMenu.getText()); } };
        addAndMakeVisible(save);
        cancel.setButtonText("Cancel");
        cancel.onClick = [this] { if (onCancel) { onCancel(); } };
        addAndMakeVisible(cancel);
        if (bankEditor) {
            remove.setButtonText("Delete");
            remove.onClick = [this] { if (onDelete) { onDelete(); } };
            addAndMakeVisible(remove);
        }
    }

    std::function<void(juce::String, int, juce::String)> onSave;
    std::function<void()> onDelete, onCancel;

    void saveWith(const juce::String &name, int category, const juce::String &bank) {
        if (onSave) { onSave(name, category, bank); }
    }
    void deleteIt() { if (onDelete) { onDelete(); } }

    void paint(juce::Graphics &g) override {
        g.fillAll(juce::Colours::black.withAlpha(0.55f));
        const juce::Rectangle<float> face = card().toFloat();
        g.setColour(style.colour("panelBackground"));
        g.fillRoundedRectangle(face, 8.0f);
        g.setColour(style.colour("controlBorder"));
        g.drawRoundedRectangle(face.reduced(0.5f), 8.0f, 1.0f);
        g.setColour(style.colour("text"));
        g.setFont(style.font(14.0f, FontWeight::demiBold));
        g.drawText(title, card().removeFromTop(34).reduced(14, 0), juce::Justification::centredLeft, false);
        g.setColour(style.colour("dim"));
        g.setFont(style.font(11.0f));
        juce::Rectangle<int> labels = card().reduced(14, 0).withTrimmedTop(34);
        g.drawText("Name", labels.removeFromTop(16), juce::Justification::bottomLeft, false);
        if (!bankEditor) {
            labels.removeFromTop(28 + 6);
            g.drawText("Category", labels.removeFromTop(16), juce::Justification::bottomLeft, false);
            labels.removeFromTop(28 + 6);
            g.drawText("Bank", labels.removeFromTop(16), juce::Justification::bottomLeft, false);
        }
    }

    void resized() override {
        juce::Rectangle<int> inside = card().reduced(14, 0).withTrimmedTop(34);
        inside.removeFromTop(16);
        nameField.setBounds(inside.removeFromTop(28));
        if (!bankEditor) {
            inside.removeFromTop(6 + 16);
            categoryMenu.setBounds(inside.removeFromTop(28));
            inside.removeFromTop(6 + 16);
            bankMenu.setBounds(inside.removeFromTop(28));
        }
        inside.removeFromTop(14);
        juce::Rectangle<int> row = inside.removeFromTop(26);
        save.setBounds(row.removeFromRight(76));
        row.removeFromRight(6);
        cancel.setBounds(row.removeFromRight(76));
        if (bankEditor) { remove.setBounds(row.removeFromLeft(76)); }
    }

    juce::Rectangle<int> card() const {
        const int height = bankEditor ? 140 : 244;
        return getLocalBounds().withSizeKeepingCentre(getWidth() - 24, height);
    }

private:
    const Style &style;
    const juce::String title;
    const bool bankEditor;
    juce::TextEditor nameField;
    juce::ComboBox categoryMenu, bankMenu;
    juce::TextButton save, cancel, remove;
};

// MARK: - The panel

PresetPanel::PresetPanel(s1plugin::PresetBrowser &model, const Style &s) : browser(model), style(s) {
    setTitle("Presets");
    setOpaque(false);
    setWantsKeyboardFocus(true);

    categoryList = std::make_unique<RowList>(*this, false);
    presetList = std::make_unique<RowList>(*this, true);
    addAndMakeVisible(*categoryList);
    addAndMakeVisible(*presetList);

    searchField = std::make_unique<juce::TextEditor>();
    // A juce::String made from a char* is LATIN-1: UTF-8 bytes typed into one come out as
    // mojibake. Every non-ASCII string here goes through fromUTF8.
    searchField->setTextToShowWhenEmpty(juce::String::fromUTF8("Search presets\xe2\x80\xa6"), style.colour("dim"));
    searchField->setFont(style.font(12.0f));
    searchField->setTitle("Search presets");
    searchField->onTextChange = [this] {
        browser.setSearch(searchField->getText().toStdString());
        refresh();
    };
    addAndMakeVisible(*searchField);

    categoryLabel = std::make_unique<juce::Label>();
    categoryLabel->setFont(style.font(11.0f));
    categoryLabel->setColour(juce::Label::textColourId, style.colour("dim"));
    categoryLabel->setBorderSize({ 0, 0, 0, 0 });
    addAndMakeVisible(*categoryLabel);

    notesField = std::make_unique<juce::TextEditor>();
    notesField->setMultiLine(true, true);
    notesField->setReturnKeyStartsNewLine(true);
    notesField->setFont(style.font(11.0f));
    notesField->setTitle("Notes");
    notesField->onFocusLost = [this] {
        const s1::Preset *preset = browser.currentPreset();
        if (preset == nullptr || preset->userText == notesField->getText().toStdString()) { return; }
        report(browser.setNotes(browser.currentUID(), notesField->getText().toStdString()), "The notes are saved.");
        refresh();
    };
    addAndMakeVisible(*notesField);

    for (const char *id : { "new", "import", "reorder", "importBank", "newBank" }) {
        Item item;
        item.id = id;
        item.title = juce::String(id) == "new" ? "New"
                   : juce::String(id) == "import" ? "Import"
                   : juce::String(id) == "reorder" ? "Reorder"
                   : juce::String(id) == "importBank" ? "Import Bank" : "+";
        item.button = std::make_unique<juce::TextButton>(item.title);
        const juce::String which = id;
        item.button->onClick = [this, which] { pressButton(which); };
        addAndMakeVisible(*item.button);
        buttons.push_back(std::move(item));
    }
    buttons.back().button->setTitle("New Bank");        // the "+" beside PRESETS

    for (juce::Component *component : std::initializer_list<juce::Component *> { searchField.get(), notesField.get() }) {
        component->setColour(juce::TextEditor::backgroundColourId, style.colour("fieldBackground"));
        component->setColour(juce::TextEditor::outlineColourId, style.colour("sectionBorder"));
        component->setColour(juce::TextEditor::focusedOutlineColourId, style.colour("accent"));
        component->setColour(juce::TextEditor::textColourId, style.colour("text"));
        component->setColour(juce::TextEditor::highlightColourId, style.colour("accent").withAlpha(0.4f));
        component->setColour(juce::CaretComponent::caretColourId, style.colour("accent"));
    }
    for (Item &item : buttons) {
        item.button->setColour(juce::TextButton::buttonColourId, style.colour("controlFace"));
        item.button->setColour(juce::TextButton::textColourOffId, style.colour("text"));
    }
    refresh();
}

PresetPanel::~PresetPanel() = default;

void PresetPanel::paint(juce::Graphics &g) {
    const juce::Rectangle<float> face = getLocalBounds().toFloat();
    juce::DropShadow(juce::Colours::black.withAlpha(0.6f), 14, { 0, 6 }).drawForRectangle(g, getLocalBounds().reduced(2));
    g.setColour(style.colour("panelBackground"));
    g.fillRoundedRectangle(face, 10.0f);
    g.setColour(style.colour("controlBorder"));
    g.drawRoundedRectangle(face.reduced(0.5f), 10.0f, 1.0f);

    g.setColour(style.colour("dim"));
    g.setFont(style.font(11.0f, FontWeight::demiBold).withExtraKerningFactor(0.11f));
    g.drawText("PRESETS", 12, 12, getWidth() - 24 - 26, 20, juce::Justification::centredLeft, false);

    // The two lists sit in wells, as the Mac dresses its tables.
    for (const juce::Component *list : { static_cast<juce::Component *>(categoryList.get()),
                                         static_cast<juce::Component *>(presetList.get()) }) {
        const juce::Rectangle<float> well = list->getBounds().toFloat().expanded(1.0f);
        g.setColour(style.colour("fieldBackground"));
        g.fillRoundedRectangle(well, 6.0f);
        g.setColour(style.colour("sectionBorder"));
        g.drawRoundedRectangle(well.reduced(0.5f), 6.0f, 1.0f);
    }
}

void PresetPanel::resized() {
    juce::Rectangle<int> inside = getLocalBounds().reduced(12);
    inside.removeFromTop(0);
    juce::Rectangle<int> header = inside.removeFromTop(20);
    buttons.back().button->setBounds(header.removeFromRight(26));
    inside.removeFromTop(8);
    searchField->setBounds(inside.removeFromTop(26));
    inside.removeFromTop(8);
    categoryList->setBounds(inside.removeFromTop(kCategoryListHeight).reduced(1));

    juce::Rectangle<int> bottom = inside.removeFromBottom(24 + 6 + 24);
    juce::Rectangle<int> firstRow = bottom.removeFromTop(24);
    buttons[0].button->setBounds(firstRow.removeFromLeft(firstRow.getWidth() / 2 - 3));
    buttons[1].button->setBounds(firstRow.removeFromRight(firstRow.getWidth()));
    bottom.removeFromTop(6);
    buttons[2].button->setBounds(bottom.removeFromLeft(bottom.getWidth() / 2 - 3));
    buttons[3].button->setBounds(bottom.removeFromRight(bottom.getWidth()));

    inside.removeFromBottom(8);
    notesField->setBounds(inside.removeFromBottom(52));
    inside.removeFromBottom(8);
    categoryLabel->setBounds(inside.removeFromBottom(14));
    inside.removeFromBottom(8);
    inside.removeFromTop(8);
    presetList->setBounds(inside.reduced(1));

    if (card != nullptr) { card->setBounds(getLocalBounds()); }
}

// MARK: - The model, shown

void PresetPanel::refresh() {
    categoryList->updateContent();
    presetList->updateContent();
    categoryList->selectRow(browser.categoryIndex(), true, true);
    const int row = browser.currentRow();
    if (row >= 0) { presetList->selectRow(row, true, true); } else { presetList->deselectAllRows(); }

    const s1::Preset *preset = browser.currentPreset();
    categoryLabel->setText(preset != nullptr ? juce::String(s1plugin::PresetBrowser::categoryName(preset->category)) : juce::String(),
                           juce::dontSendNotification);
    if (preset != nullptr && !notesField->hasKeyboardFocus(true)) {
        notesField->setText(text(preset->userText), juce::dontSendNotification);
    }
    for (Item &item : buttons) {
        if (item.id == "reorder") {
            item.button->setButtonText(reordering ? "Done" : "Reorder");
            item.button->setColour(juce::TextButton::textColourOffId, reordering ? style.colour("accent") : style.colour("text"));
        }
    }
    repaint();
}

int PresetPanel::rowCount() const { return int(browser.shown().size()); }

void PresetPanel::chooseRow(int row) {
    const std::vector<s1::Preset> &presets = browser.shown();
    if (row < 0 || row >= int(presets.size())) { return; }
    chooseAndPlay(presets[size_t(row)]);
}

void PresetPanel::chooseCategory(int row) {
    browser.selectCategory(row);
    refresh();
}

void PresetPanel::chooseAndPlay(const s1::Preset &preset) {
    const s1::Preset copy = preset;                 // `refresh` rebuilds the list under us
    browser.setCurrent(copy.uid);
    if (onChoose) { onChoose(copy); }
    refresh();
}

void PresetPanel::report(const std::string &problem, const juce::String &done) {
    if (onSay == nullptr) { return; }
    if (!problem.empty()) { onSay(juce::String("That did not work: ") + text(problem)); return; }
    onSay(browser.notice().empty() ? done : text(browser.notice()));
}

void PresetPanel::moveRow(int row, int by) {
    const std::string problem = browser.movePreset(row, row + by);
    report(problem, {});
    refresh();
    presetList->selectRow(juce::jlimit(0, juce::jmax(0, rowCount() - 1), row + by), true, true);
}

bool PresetPanel::pressButton(const juce::String &id) {
    if (id == "new") {
        report(browser.createPreset(), "A new preset is in the User bank.");
        refresh();
        if (const s1::Preset *made = browser.currentPreset()) { chooseAndPlay(*made); }
        return true;
    }
    if (id == "newBank") {
        report(browser.createBank(), "A new bank.");
        refresh();
        return true;
    }
    if (id == "reorder") {
        reordering = !reordering;
        // Upstream's Reorder shows a bank first: its own list is the only one with an order.
        if (reordering && browser.shownBank().empty()) {
            browser.setSearch("");
            searchField->setText({}, juce::dontSendNotification);
            browser.selectCategory(s1plugin::PresetBrowser::kBankStartingIndex);
            if (onSay) { onSay("Reordering works on a bank's own list."); }
        }
        refresh();
        return true;
    }
    if (id == "import" || id == "importBank") { importFile(id == "importBank"); return true; }
    if (id == "save") { editCurrentPreset(); return true; }
    return false;
}

bool PresetPanel::pressRowButton(int row, const juce::String &which) {
    const std::vector<s1::Preset> &presets = browser.shown();
    if (row < 0 || row >= int(presets.size())) { return false; }
    const s1::Preset preset = presets[size_t(row)];
    // While reordering a row carries two arrows and nothing else — as upstream's Reorder turns
    // the rows into drag handles and takes the cell's own buttons away.
    if (reordering != (which == "up" || which == "down")) { return false; }
    if (which == "up" || which == "down") { moveRow(row, which == "down" ? 1 : -1); return true; }
    if (which == "star") {
        report(browser.toggleFavourite(preset.uid), preset.isFavorite ? "Unstarred." : "Starred.");
        refresh();
        return true;
    }
    if (which == "duplicate") {
        report(browser.duplicate(preset.uid), "A copy is in the User bank.");
        refresh();
        if (const s1::Preset *copy = browser.currentPreset()) { chooseAndPlay(*copy); }
        return true;
    }
    if (which == "rename") { editPreset(preset); return true; }
    if (which == "share") { shareRow(row); return true; }
    return false;
}

// MARK: - The editors

void PresetPanel::editCurrentPreset() {
    const s1::Preset *preset = browser.currentPreset();
    if (preset == nullptr) {
        // Nothing of the library is playing — a sound loaded from a host's session. Save it as new.
        s1::Preset sound = soundNow ? soundNow() : s1::Preset();
        sound.uid.clear();
        editPreset(sound);
        return;
    }
    editPreset(*preset);
}

void PresetPanel::editPreset(const s1::Preset &preset) {
    const std::string uid = preset.uid;
    auto made = std::make_unique<EditorCard>(style, "Save the preset", text(preset.name), preset.category,
                                             text(preset.bank), browser.bankNames(), false);
    made->onSave = [this, uid](juce::String name, int category, juce::String bank) {
        const s1::Preset sound = soundNow ? soundNow() : s1::Preset();
        const std::string problem = browser.savePreset(uid, sound, name.toStdString(), category, bank.toStdString());
        report(problem, juce::String("Saved as ") + name + ".");
        closeEditorCard();
        refresh();
        if (problem.empty()) { if (const s1::Preset *saved = browser.currentPreset()) { chooseAndPlay(*saved); } }
    };
    made->onCancel = [this] { closeEditorCard(); };
    openEditorCard(std::move(made));
}

void PresetPanel::editBankOfRow(int row) {
    const std::vector<s1plugin::BrowserCategory> &rows = browser.categories();
    if (row < 0 || row >= int(rows.size()) || !rows[size_t(row)].isBank) { return; }
    const std::string bank = rows[size_t(row)].bank;
    auto made = std::make_unique<EditorCard>(style, "The bank", text(bank), 0, text(bank), browser.bankNames(), true);
    made->onSave = [this, bank](juce::String name, int, juce::String) {
        report(browser.renameBank(bank, name.toStdString()), juce::String("The bank is called ") + name + " now.");
        closeEditorCard();
        refresh();
    };
    made->onDelete = [this, bank] {
        report(browser.removeBank(bank), text(bank) + " is gone.");
        closeEditorCard();
        refresh();
    };
    made->onCancel = [this] { closeEditorCard(); };
    openEditorCard(std::move(made));
}

void PresetPanel::openEditorCard(std::unique_ptr<EditorCard> made) {
    card = std::move(made);
    card->setBounds(getLocalBounds());
    addAndMakeVisible(*card);
    card->toFront(true);
}

void PresetPanel::closeEditorCard() {
    const juce::Component::SafePointer<PresetPanel> safe(this);
    juce::MessageManager::callAsync([safe] {
        if (safe != nullptr) { safe->card.reset(); }
    });
}

juce::Component *PresetPanel::editorCard() const { return card.get(); }

void PresetPanel::editorCardSave(const juce::String &name, int category, const juce::String &bank) {
    if (card != nullptr) { card->saveWith(name, category, bank); }
}

void PresetPanel::editorCardDelete() { if (card != nullptr) { card->deleteIt(); } }

// MARK: - Files

void PresetPanel::importFile(bool wholeBank) {
    // A plugin must never put up a modal window of its own: the host owns the event loop
    // (ADR-044's lesson, in JUCE's words — `launchAsync`, never `browseForFileToOpen`).
    chooser = std::make_unique<juce::FileChooser>(wholeBank ? "Import a bank" : "Import a preset",
                                                  juce::File::getSpecialLocation(juce::File::userDocumentsDirectory),
                                                  "*.json;*.synth1");
    const juce::Component::SafePointer<PresetPanel> safe(this);
    chooser->launchAsync(juce::FileBrowserComponent::openMode | juce::FileBrowserComponent::canSelectFiles,
                         [safe](const juce::FileChooser &result) {
        if (safe == nullptr) { return; }
        const juce::File file = result.getResult();
        if (file == juce::File()) { return; }
        safe->report(safe->browser.importFile(file.getFileName().toStdString(), file.loadFileAsString().toStdString()),
                     file.getFileName() + " came in.");
        safe->refresh();
        if (const s1::Preset *imported = safe->browser.currentPreset()) { safe->chooseAndPlay(*imported); }
    });
}

void PresetPanel::shareRow(int row) {
    const std::vector<s1::Preset> &presets = browser.shown();
    if (row < 0 || row >= int(presets.size())) { return; }
    const s1::Preset preset = presets[size_t(row)];
    chooser = std::make_unique<juce::FileChooser>("Export the preset",
                                                  juce::File::getSpecialLocation(juce::File::userDocumentsDirectory)
                                                      .getChildFile(text(preset.name) + ".json"),
                                                  "*.json;*.synth1");
    const juce::Component::SafePointer<PresetPanel> safe(this);
    const std::string uid = preset.uid;
    chooser->launchAsync(juce::FileBrowserComponent::saveMode | juce::FileBrowserComponent::warnAboutOverwriting,
                         [safe, uid](const juce::FileChooser &result) {
        if (safe == nullptr) { return; }
        const juce::File file = result.getResult();
        if (file == juce::File()) { return; }
        const bool written = file.replaceWithText(text(safe->browser.presetJSON(uid)));
        if (safe->onSay) { safe->onSay(written ? file.getFileName() + " is written." : juce::String("That file could not be written.")); }
    });
}

// MARK: - Keys

void PresetPanel::setSearch(const juce::String &wanted) {
    // `TextEditor::setText` POSTS its change message (`postCommandMessage`), so a search set from
    // code would not reach the model until the message loop ran — and in a test it never would.
    searchField->setText(wanted, juce::dontSendNotification);
    browser.setSearch(wanted.toStdString());
    refresh();
}

juce::String PresetPanel::searchText() const { return searchField->getText(); }
juce::String PresetPanel::notes() const { return notesField->getText(); }
void PresetPanel::setNotes(const juce::String &words) { notesField->setText(words, juce::dontSendNotification); }

bool PresetPanel::keyPressed(const juce::KeyPress &key) {
    if (key == juce::KeyPress::escapeKey) {
        if (card != nullptr) { closeEditorCard(); return true; }
        if (onClose) { onClose(); return true; }
    }
    return false;
}

} // namespace s1ui
