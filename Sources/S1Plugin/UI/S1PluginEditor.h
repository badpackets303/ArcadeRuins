//
//  S1PluginEditor.h
//  Arcade Ruins
//
//  X3-3 (ADR-085): the interface — the layout specification's sections, controls, plots, pads,
//  toolbar and play bar, built from the controls kit at the design size (1440 x 900). Nothing here
//  knows a frame, a colour or a binding: they are the specification's (ADR-083), and every control
//  is the kit's (ADR-084).
//
//  X3-7 (ADR-089): the window scales. Everything is built at the design size on one `stage`
//  component and the window puts a scale transform on it, uniformly and centred, so nothing is
//  re-laid out and nothing is ever cropped — the Mac's `S1ScalingContainer` (ADR-019) in JUCE's
//  terms. Whatever is left over is the window's own colour.
//
//  Two skins from one build: Cabinet (the default, ADR-064) lays the kit over the owner's
//  painting, which carries the frames, the titles and the header's buttons; Studio draws its
//  own toolbar, section panels and bars. Choosing between them in the interface is X3-6; here
//  the constructor takes the skin's key.
//
//  What the editor adds to the kit is what spans controls: the playing step's ring, the tempo
//  shown as the host's, the rate readouts following the tempo and the sync switch, Snap, the
//  preset's name with previous / next, Panic, the scope, and a panel with EVERY parameter — the
//  26 the desktop layout gives no control (ADR-083) are reachable there.
//
#pragma once

#include <map>
#include <memory>
#include <string>
#include <vector>

#include <juce_audio_processors/juce_audio_processors.h>

#include "../S1LayoutSpec.hpp"
#include "../S1PowerCycle.hpp"
#include "../S1PresetBrowser.hpp"
#include "S1Keyboard.h"
#include "S1KitControls.h"
#include "S1PresetPanel.h"
#include "S1TuningsPanel.h"

class S1PluginProcessor;

class S1PluginEditor final : public juce::AudioProcessorEditor, private juce::Timer {
public:
    /// `skinKey` empty: the skin the processor remembers, or the specification's default.
    explicit S1PluginEditor(S1PluginProcessor &, const std::string &skinKey = {});
    ~S1PluginEditor() override;

    void paint(juce::Graphics &) override;
    void resized() override;
    bool keyPressed(const juce::KeyPress &) override;
    bool keyStateChanged(bool isKeyDown) override;
    void focusLost(FocusChangeType) override;

    // MARK: X3-7 (ADR-089): the window's size
    /// What the window may be scaled between. The design size itself is the layout's minimum
    /// (`spec.minimumSize`): below 1x nothing is re-laid out, it is drawn smaller.
    static constexpr float kMinScale = 0.75f, kMaxScale = 1.5f;
    /// The scale the interface is drawn at: the window's size over the design size, the smaller of
    /// the two so the whole of it always fits and nothing is ever cropped.
    float interfaceScale() const;

    const s1plugin::LayoutSkin &skin() const { return style->skin(); }

    // For tests, and for whoever drives the interface without a pointer
    /// Every parameter control in the component tree, found by walking it.
    std::vector<s1ui::ParameterControl *> parameterControls();
    /// The parameters with a control, a plot or a pad of their own.
    std::vector<S1Parameter> parametersWithAControl();
    /// Presses the toolbar / play-bar item with this specification id ("button.Panic"). False: no such item.
    bool pressItem(const juce::String &itemID);
    /// Steps a play-bar stepper item ("octave") the way a click on one half of it does. X3-8.
    bool stepItem(const juce::String &itemID, int direction);
    void stepPreset(int direction);
    juce::String presetTitle() const;
    juce::String statusMessage() const;
    void showAllParameters(bool show);
    bool isShowingAllParameters() const;
    // X3-6 (ADR-088): Settings, and the skin.
    /// Dresses the whole window in another skin, in place: every control, plot, pad, item and the
    /// backdrop are made again from the specification. The processor remembers the choice, so a
    /// new instance opens in it. Nothing about the sound is touched.
    void applySkin(const std::string &skinKey);
    void showSettings(bool show);
    bool isShowingSettings() const;
    // The cabinet's stick (X3-6). Nothing under a skin that has none, Studio among them. These
    // are the plain methods its own mouse handlers call, so a test drives it with no window.
    bool hasJoystick() const { return joystick != nullptr; }
    juce::Rectangle<int> joystickBounds() const;
    void joystickGrab();
    /// From where it was grabbed, in points: right and down are positive.
    void joystickMoveBy(float dx, float dy);
    void joystickLetGo();
    float joystickLean() const;          ///< -1 … 1, the picture's own lean
    float joystickPush() const;          ///< -1 … 1, up is positive
    // X3-9 (ADR-091): the cabinet's red buttons cut and restore the power.
    /// Runs the eight-second cycle. `powered` false cuts it, true brings it back; pressing the
    /// other button mid-cycle abandons what is left of this one. A LOOK and nothing else: every
    /// control works and sounds in the dark.
    void runPower(bool powered);
    /// The cycle as it stands `seconds` after the press — the clock is the caller's, as the Mac's
    /// is injectable (ADR-062), so eight seconds of flicker are tested in none.
    void advancePowerTo(double seconds) { applyPower(seconds); }
    /// How many zones the cycle now running plans to change; 0 when none is running. For tests.
    int powerCyclePlans() const { return powerCycle != nullptr ? int(powerCycle->plans().size()) : 0; }
    /// 0 lit, 1 dead, for a zone ("Filter", "display", "buttons", "screen", "bar"). For tests.
    float zoneDim(const std::string &zone) const;
    /// Puts every zone back to lit at once, with no cycle. For tests, and for a skin change.
    void restorePower();
    bool hasPowerButtons() const { return powerOff != nullptr; }
    /// Every zone the skin darkens: the fifteen sections and the four pieces of the chrome.
    std::vector<std::string> powerZones() const;

    // X3-8 (ADR-090): the keyboard drawer, and what plays it.
    /// Slides the keys up over the lower sections, or puts them away. The play bar stays visible
    /// beneath them, because Hold, Octave, Transpose and the wheels belong with the keys. Closed
    /// by default, and remembered per instance in the session's state.
    static constexpr int kKeyboardHeight = 124;
    void showKeyboard(bool show);
    bool isShowingKeyboard() const { return keyboard != nullptr; }
    s1ui::Keyboard *keys() const { return keyboard.get(); }
    /// The Wheels card: the pitch wheel, its range, and what the mod wheel moves.
    void showWheels(bool show);
    bool isShowingWheels() const;
    /// Musical typing (A–K play, Z/X octave, C/V velocity), which the status bar has promised
    /// since X3-3. A key going down; false if it is not one of the keyboard's.
    bool typedKeyDown(int keyCode, const juce::ModifierKeys &);
    /// Every typed note let go — what happens when the interface loses the keyboard, and what the
    /// octave keys do before they move (their key-up would otherwise be a different note).
    void releaseTypedNotes();
    int typedOctave() const;
    int typedVelocity() const { return velocityOfTypedNotes; }

    // X3-4 (ADR-086): the preset browser.
    /// Drops the browser's card down from the preset name, or puts it away. Opening it reads the
    /// folder — the first time, that writes the banks the Mac starts with (ADR-086).
    void showPresets(bool show);
    bool isShowingPresets() const { return presetPanel != nullptr; }
    /// The card, or nothing while it is away.
    s1ui::PresetPanel *presets() const { return presetPanel.get(); }
    /// The browser's model, loaded if it has not been. Never the audio thread.
    s1plugin::PresetBrowser &presetBrowser();
    // X3-5 (ADR-087): the Tunings card.
    void showTunings(bool show);
    bool isShowingTunings() const { return tuningsPanel != nullptr; }
    s1ui::TuningsPanel *tunings() const { return tuningsPanel.get(); }
    /// The sound as it stands, with what names it: what Save keeps.
    s1::Preset soundNow() const;
    /// The panel's own editor, which lists every parameter of the processor; nothing while hidden.
    juce::Component *allParametersList() const;
    /// What the timer does, callable without one.
    void refreshLiveState();

private:
    class Backdrop;
    class ItemButton;
    class PresetField;
    class ScopeView;
    class Panel;
    class SettingsBody;
    class WheelsBody;
    class Joystick;

    void timerCallback() override { refreshLiveState(); }
    /// X3-9: the style a control in this zone draws with — its own, so greying it greys the zone
    /// and nothing else. Zones are section keys, plus "display", "buttons", "screen" and "bar".
    s1ui::Style &styleFor(const std::string &zone);
    static std::string zoneOfSection(const std::string &section);
    static std::string zoneOfItem(const s1plugin::LayoutItem &item);
    void applyPower();                       ///< …by the editor's own clock
    void applyPower(double seconds);                       ///< the cycle's state to the styles and the backdrop
    void layoutStage();                      ///< what fills the design-size space: the backdrop and the cards
    void buildControls();
    void buildItems();
    void tearDownSkin();                     ///< everything `buildControls` / `buildItems` made
    void playPreset(const s1::Preset &);
    void placePresetPanel();
    void say(const juce::String &message);
    void showAbout();

    S1PluginProcessor &plugin;
    /// X3-7 (ADR-089): EVERYTHING is a child of this, and it is always the design size. The window
    /// scales it with one transform, so every frame the specification measured stays in design
    /// points — including the cards, which are placed in the same space.
    std::unique_ptr<juce::Component> stage;
    std::unique_ptr<s1ui::Style> style;
    std::unique_ptr<Backdrop> backdrop;
    std::vector<std::unique_ptr<juce::Component>> owned;      ///< controls, readouts, plots, pads, items — in paint order
    std::vector<s1ui::ValueReadout *> rateReadouts;
    std::vector<juce::Component *> rateViews;                 ///< what sits by note value: repainted when the tempo or the sync switch moves
    float lastSync = -1, lastTempo = -1;
    std::vector<s1ui::StepOctave *> stepBoxes;
    std::vector<s1ui::XYPad *> pads;
    std::vector<ItemButton *> itemButtons;
    s1ui::Stepper *tempo = nullptr;
    PresetField *presetField = nullptr;
    ScopeView *scope = nullptr;
    ItemButton *monoButton = nullptr, *snapButton = nullptr;
    std::unique_ptr<juce::Label> status;
    std::unique_ptr<Panel> panel;
    std::unique_ptr<s1plugin::PresetBrowser> browser;
    std::unique_ptr<s1ui::PresetPanel> presetPanel;
    std::unique_ptr<juce::Component> presetBackdrop;   ///< a click anywhere else closes the card
    std::unique_ptr<s1ui::TuningsPanel> tuningsPanel;
    ItemButton *tuningButton = nullptr;   ///< its words follow the tuning
    std::unique_ptr<Joystick> joystick;   ///< Cabinet only (ADR-088)
    // X3-8 (ADR-090)
    std::unique_ptr<s1ui::Keyboard> keyboard;
    // X3-9 (ADR-091)
    std::map<juce::Component *, std::string> itemZones;               ///< the zone each toolbar / bar button draws in
    std::map<std::string, std::unique_ptr<s1ui::Style>> zoneStyles;   ///< one per zone, so one can be greyed alone
    std::unique_ptr<s1plugin::PowerCycle> powerCycle;
    double powerStartedAt = 0;                                        ///< juce::Time::getMillisecondCounterHiRes when it began
    ItemButton *powerOff = nullptr, *powerOn = nullptr;
    ItemButton *holdButton = nullptr, *octaveButton = nullptr;   ///< their words and their light follow the router
    std::map<int, int> typedNotes;        ///< the key code a typed note came from, and the note it plays
    int velocityOfTypedNotes = 100;       ///< `Manager.typedVelocity`, C and V move it by 16
    juce::String hint, shownPreset;
    int lastBeat = -1, ticksSinceBeat = 1000, ticksOfMessage = 0;
    bool snap = false;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(S1PluginEditor)
};
