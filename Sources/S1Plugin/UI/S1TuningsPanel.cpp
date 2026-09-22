//
//  S1TuningsPanel.cpp
//  Arcade Ruins
//
//  X3-5 (ADR-087). See the header.
//
#include "S1TuningsPanel.h"

#include <cmath>

namespace s1ui {

namespace {

juce::String text(const std::string &from) { return juce::String::fromUTF8(from.c_str()); }

/// `Tunings.pitch`: a ratio's place in the octave, 0…1.
double pitchOf(double ratio) {
    if (ratio <= 0) { return 0; }
    double f = ratio;
    while (f < 1) { f *= 2; }
    while (f > 2) { f /= 2; }
    double whole = 0;
    return std::modf(std::log2(f), &whole);
}

/// `Tunings.color(forPitch:)`: the octave IS the hue wheel.
juce::Colour colourForPitch(double pitch, float saturation = 0.625f, float brightness = 1.0f, float alpha = 0.75f) {
    return juce::Colour::fromHSV(float(pitch), saturation, brightness, alpha);
}

} // namespace

// MARK: - The two tables

class TuningsPanel::RowList final : public juce::ListBox, private juce::ListBoxModel {
public:
    RowList(TuningsPanel &owner, bool tunings) : panel(owner), isTunings(tunings) {
        setModel(this);
        setRowHeight(kRowHeight);
        setColour(juce::ListBox::backgroundColourId, juce::Colours::transparentBlack);
        setOutlineThickness(0);
        getViewport()->setScrollBarsShown(true, false);
        setTitle(tunings ? "Tunings" : "Banks");
    }

    int getNumRows() override {
        return isTunings ? int(panel.library.tunings().size()) : int(panel.library.banks().size());
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
        if (!isTunings) {
            if (row < 0 || row >= int(panel.library.banks().size())) { return; }
            g.setColour(dress.colour("text"));
            g.setFont(dress.font(13.0f, FontWeight::medium));
            g.drawText(text(panel.library.banks()[size_t(row)].name), 12, 0, width - 20, height, juce::Justification::centredLeft, true);
            return;
        }
        const std::vector<s1plugin::TuningEntry> &list = panel.library.tunings();
        if (row < 0 || row >= int(list.size())) { return; }
        // `nameForCell`: the note count, padded, then the name — drawn as two columns so the
        // numbers line up whatever face the plugin has.
        g.setColour(dress.colour("dim"));
        g.setFont(dress.font(12.0f));
        g.drawText(juce::String(list[size_t(row)].npo()), 10, 0, 26, height, juce::Justification::centredRight, false);
        g.setColour(dress.colour("text"));
        g.setFont(dress.font(13.0f));
        g.drawText(text(list[size_t(row)].name), 44, 0, width - 52, height, juce::Justification::centredLeft, true);
    }

    void listBoxItemClicked(int row, const juce::MouseEvent &) override { choose(row); }
    void returnKeyPressed(int row) override { choose(row); }

private:
    void choose(int row) { if (isTunings) { panel.chooseTuning(row); } else { panel.chooseBank(row); } }

    TuningsPanel &panel;
    const bool isTunings;
};

// MARK: - The pitch wheel

/// `TuningsPitchWheelView`: the scale as a horagram — every degree at its own place round the
/// octave, coloured by that place, which is what makes two tunings tell each other apart at a
/// glance. The Mac's labels and its touch overlay are not drawn here.
class TuningsPanel::PitchWheel final : public juce::Component {
public:
    PitchWheel(s1plugin::TuningLibrary &model, const Style &s) : library(model), style(s) {
        setInterceptsMouseClicks(false, false);
        setTitle("The scale");
    }

    void paint(juce::Graphics &g) override {
        const juce::Rectangle<float> bounds = getLocalBounds().toFloat().reduced(6.0f);
        const juce::Point<float> centre = bounds.getCentre();
        const float radius = std::min(bounds.getWidth(), bounds.getHeight()) * 0.5f;

        g.setColour(style.colour("fieldBackground"));
        g.fillEllipse(juce::Rectangle<float>(radius * 2, radius * 2).withCentre(centre));
        g.setColour(style.colour("sectionBorder"));
        g.drawEllipse(juce::Rectangle<float>(radius * 2, radius * 2).withCentre(centre), 1.0f);

        for (const double ratio : library.masterSet()) {
            const double pitch = pitchOf(ratio);
            // Twelve o'clock is 1/1, and the octave runs clockwise (the Mac's horagram).
            const float angle = float(pitch) * juce::MathConstants<float>::twoPi - juce::MathConstants<float>::halfPi;
            const juce::Point<float> spoke = centre.getPointOnCircumference(radius * 0.72f, angle + juce::MathConstants<float>::halfPi);
            g.setColour(colourForPitch(pitch, 0.625f, 1.0f, 0.35f));
            g.drawLine(centre.x, centre.y, spoke.x, spoke.y, 1.0f);
            g.setColour(colourForPitch(pitch, 0.625f, 1.0f, 0.9f));
            g.fillEllipse(juce::Rectangle<float>(11.0f, 11.0f).withCentre(spoke));
        }
        g.setColour(style.colour("dim"));
        g.setFont(style.font(22.0f, FontWeight::demiBold));
        juce::Rectangle<float> corner = bounds;
        g.drawText(juce::String(library.notesPerOctave()), corner.removeFromTop(30.0f).reduced(4.0f, 0.0f), juce::Justification::topLeft, false);
        g.setFont(style.font(12.0f));
        g.setColour(style.colour("label"));
        g.drawText(text(library.tuningName()), getLocalBounds().removeFromBottom(18), juce::Justification::centred, true);
    }

private:
    s1plugin::TuningLibrary &library;
    const Style &style;
};

// MARK: - The panel

TuningsPanel::TuningsPanel(s1plugin::TuningLibrary &model, const Style &s, s1ui::ParameterLookup lookup)
    : library(model), style(s) {
    setTitle("Tunings");
    setOpaque(false);
    setWantsKeyboardFocus(true);

    bankList = std::make_unique<RowList>(*this, false);
    tuningList = std::make_unique<RowList>(*this, true);
    wheel = std::make_unique<PitchWheel>(library, style);
    addAndMakeVisible(*bankList);
    addAndMakeVisible(*tuningList);
    addAndMakeVisible(*wheel);

    // The master-tuning knob IS the frequencyA4 parameter — one of the 26 the desktop layout
    // gives no control (ADR-083). Here it has one, and here it does something (ADR-087).
    auto knob = std::make_unique<Knob>(lookup(S1Parameter::frequencyA4), style, style.colour("accent"));
    knob->setComponentID("tuning.frequencyA4");
    a4Knob = std::move(knob);
    addAndMakeVisible(*a4Knob);
    a4Caption = std::make_unique<juce::Label>();
    a4Caption->setFont(style.font(11.0f));
    a4Caption->setColour(juce::Label::textColourId, style.colour("dim"));
    a4Caption->setJustificationType(juce::Justification::centred);
    addAndMakeVisible(*a4Caption);

    for (const char *id : { "reset", "random", "import", "delete" }) {
        Item item;
        item.id = id;
        const juce::String title = juce::String(id) == "reset" ? "Reset"
                                 : juce::String(id) == "random" ? juce::String::fromUTF8("\xF0\x9F\x8E\xB2")
                                 : juce::String(id) == "import" ? "Import a scale" : "Delete";
        item.button = std::make_unique<juce::TextButton>(title);
        const juce::String which = id;
        item.button->onClick = [this, which] { pressButton(which); };
        item.button->setColour(juce::TextButton::buttonColourId, style.colour("controlFace"));
        item.button->setColour(juce::TextButton::textColourOffId, style.colour("text"));
        addAndMakeVisible(*item.button);
        buttons.push_back(std::move(item));
    }
    refresh();
}

TuningsPanel::~TuningsPanel() = default;

void TuningsPanel::paint(juce::Graphics &g) {
    g.fillAll(juce::Colours::black.withAlpha(0.55f));
    const juce::Rectangle<float> face = getLocalBounds().toFloat();
    g.setColour(style.colour("panelBackground"));
    g.fillRoundedRectangle(face, 10.0f);
    g.setColour(style.colour("controlBorder"));
    g.drawRoundedRectangle(face.reduced(0.5f), 10.0f, 1.0f);
    g.setColour(style.colour("dim"));
    g.setFont(style.font(11.0f, FontWeight::demiBold).withExtraKerningFactor(0.11f));
    g.drawText("TUNINGS", 16, 12, getWidth() - 32, 20, juce::Justification::centredLeft, false);
    for (const juce::Component *list : { static_cast<juce::Component *>(bankList.get()),
                                         static_cast<juce::Component *>(tuningList.get()) }) {
        const juce::Rectangle<float> well = list->getBounds().toFloat().expanded(1.0f);
        g.setColour(style.colour("fieldBackground"));
        g.fillRoundedRectangle(well, 6.0f);
        g.setColour(style.colour("sectionBorder"));
        g.drawRoundedRectangle(well.reduced(0.5f), 6.0f, 1.0f);
    }
}

void TuningsPanel::resized() {
    juce::Rectangle<int> inside = getLocalBounds().reduced(16);
    inside.removeFromTop(24);                              // the heading
    juce::Rectangle<int> left = inside.removeFromLeft(300);
    inside.removeFromLeft(16);

    bankList->setBounds(left.removeFromTop(kBankListHeight).reduced(1));
    left.removeFromTop(10);
    juce::Rectangle<int> row = left.removeFromBottom(26);
    buttons[0].button->setBounds(row.removeFromLeft(78));   // Reset
    row.removeFromLeft(6);
    buttons[1].button->setBounds(row.removeFromLeft(38));   // the dice
    row.removeFromLeft(6);
    buttons[3].button->setBounds(row.removeFromRight(70));  // Delete
    left.removeFromBottom(8);
    juce::Rectangle<int> importRow = left.removeFromBottom(26);
    buttons[2].button->setBounds(importRow);
    left.removeFromBottom(8);
    tuningList->setBounds(left.reduced(1));

    // The wheel, with the master tuning under it
    juce::Rectangle<int> a4 = inside.removeFromBottom(76);
    a4Knob->setBounds(a4.withSizeKeepingCentre(52, 52).translated(0, -10));
    a4Caption->setBounds(a4.removeFromBottom(16));
    wheel->setBounds(inside);
}

void TuningsPanel::refresh() {
    bankList->updateContent();
    tuningList->updateContent();
    bankList->selectRow(library.selectedBankIndex(), true, true);
    tuningList->selectRow(library.selectedTuningIndex(), true, true);
    a4Caption->setText("Master tuning  A4 " + juce::String(juce::roundToInt(a4Knob != nullptr
                           ? static_cast<ParameterControl *>(a4Knob.get())->plain() : 440.0f)) + " Hz",
                       juce::dontSendNotification);
    for (Item &item : buttons) {
        if (item.id == "delete") { item.button->setEnabled(library.selectedBankIsEditable() && library.selectedTuningIndex() > 0); }
    }
    if (wheel != nullptr) { wheel->repaint(); }
    repaint();
}

int TuningsPanel::tuningRowCount() const { return int(library.tunings().size()); }

void TuningsPanel::chooseTuning(int row) {
    library.selectTuning(row);
    tuningChanged();
}

void TuningsPanel::chooseBank(int row) {
    library.selectBank(row);
    tuningChanged();
}

void TuningsPanel::tuningChanged() {
    if (onTuningChanged) { onTuningChanged(); }
    refresh();
}

bool TuningsPanel::pressButton(const juce::String &id) {
    if (id == "reset") {
        library.resetTuning();
        if (onSay) { onSay("12 ET."); }
        tuningChanged();
        return true;
    }
    if (id == "random") {
        library.randomTuning();
        if (onSay) { onSay(juce::String::fromUTF8("\xF0\x9F\x8E\xB2 ") + text(library.tuningName())); }
        tuningChanged();
        return true;
    }
    if (id == "delete") {
        if (!library.removeUserTuning(library.selectedTuningIndex())) {
            if (onSay) { onSay("Only a tuning of your own can go, and never 12 ET."); }
            return true;
        }
        tuningChanged();
        return true;
    }
    if (id == "import") { importFile(); return true; }
    return false;
}

std::vector<float> TuningsPanel::wheelPositions() const {
    std::vector<float> places;
    for (const double ratio : library.masterSet()) { places.push_back(float(pitchOf(ratio))); }
    return places;
}

void TuningsPanel::importFile() {
    // `launchAsync` only: a plugin does not own the host's event loop (ADR-044, ADR-086).
    chooser = std::make_unique<juce::FileChooser>("Import a Scala scale",
                                                  juce::File::getSpecialLocation(juce::File::userDocumentsDirectory),
                                                  "*.scl");
    const juce::Component::SafePointer<TuningsPanel> safe(this);
    chooser->launchAsync(juce::FileBrowserComponent::openMode | juce::FileBrowserComponent::canSelectFiles,
                         [safe](const juce::FileChooser &result) {
        if (safe == nullptr) { return; }
        const juce::File file = result.getResult();
        if (file == juce::File()) { return; }
        const std::string problem = safe->library.importScala(file.getFileName().toStdString(), file.loadFileAsString().toStdString());
        if (safe->onSay) {
            safe->onSay(problem.empty() ? file.getFileNameWithoutExtension() + " is in the User bank."
                                        : juce::String("That did not work: ") + text(problem));
        }
        safe->tuningChanged();
    });
}

bool TuningsPanel::keyPressed(const juce::KeyPress &key) {
    if (key == juce::KeyPress::escapeKey && onClose) { onClose(); return true; }
    return false;
}

} // namespace s1ui
