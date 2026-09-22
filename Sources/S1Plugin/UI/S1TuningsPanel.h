//
//  S1TuningsPanel.h
//  Arcade Ruins
//
//  X3-5 (ADR-087): the Tunings card — the Mac's Tunings panel
//  (`TuningsPanelController`, presented as a sheet by the desktop layout): the banks, the tunings
//  of the chosen bank, the pitch wheel that draws the scale, the master-tuning knob (A4), and
//  Reset / Random / Import.
//
//  A VIEW, as the preset browser's card is (ADR-086): every operation belongs to
//  `s1plugin::TuningLibrary`, which has no JUCE in it and is driven with no window by
//  `PluginTuningsTests`; this draws its lists in the skin's colours and turns a click into one of
//  its calls. Everything can be driven without a mouse, which is how `PluginEditorTests` works it.
//
//  Left out, deliberately: TuneUp, Wilsonic and D1: they hand a tuning to another iOS app by URL
//  (ADR-056's scope — the Dev panel and the app-launch buttons are not rebuilt).
//
#pragma once

#include <functional>
#include <memory>

#include <juce_gui_basics/juce_gui_basics.h>

#include "../S1TuningLibrary.hpp"
#include "S1KitControls.h"
#include "S1KitStyle.h"

namespace s1ui {

class TuningsPanel final : public juce::Component {
public:
    /// The Mac's sheet is 700 x 560 over the window; this is the same card over the sections.
    static constexpr int kWidth = 700, kHeight = 560;
    static constexpr int kRowHeight = 26, kBankListHeight = 108;

    /// All three must outlive the panel.
    TuningsPanel(s1plugin::TuningLibrary &, const Style &, s1ui::ParameterLookup);
    ~TuningsPanel() override;

    /// The tuning that plays has changed: the processor rebuilds the table.
    std::function<void()> onTuningChanged;
    std::function<void(const juce::String &)> onSay;
    std::function<void()> onClose;

    void refresh();

    void paint(juce::Graphics &) override;
    void resized() override;
    bool keyPressed(const juce::KeyPress &) override;

    // MARK: driving it without a mouse
    int tuningRowCount() const;
    void chooseTuning(int row);
    void chooseBank(int row);
    /// "reset", "random", "import", "delete". False: no such button.
    bool pressButton(const juce::String &id);
    /// What the wheel draws, for a test: one point per note of the scale, 0…1 round the circle.
    std::vector<float> wheelPositions() const;

private:
    class RowList;
    class PitchWheel;

    void tuningChanged();
    void importFile();

    s1plugin::TuningLibrary &library;
    const Style &style;
    std::unique_ptr<RowList> bankList, tuningList;
    std::unique_ptr<PitchWheel> wheel;
    std::unique_ptr<juce::Component> a4Knob;
    std::unique_ptr<juce::Label> a4Caption, heading;
    struct Item { juce::String id; std::unique_ptr<juce::TextButton> button; };
    std::vector<Item> buttons;
    std::unique_ptr<juce::FileChooser> chooser;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(TuningsPanel)
};

} // namespace s1ui
