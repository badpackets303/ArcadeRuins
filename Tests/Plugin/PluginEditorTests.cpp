// X3-3 (ADR-085): the editor, with no window — built for both skins from the linked specification;
// the component tree walked for every parameter's control (the plan's acceptance) and the rest
// found in the every-parameter panel; the toolbar's and play bar's buttons pressed; what spans
// controls: the playing step, the host's tempo, Snap, Mono, the preset's name, Panic, the scope.
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <set>
#include <string>

#include "S1ArtData.h"
#include "S1LinkedLayoutSpec.h"
#include "S1PluginProcessor.h"
#include "UI/S1PluginEditor.h"

namespace {

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

struct HostEars final : juce::AudioProcessorParameter::Listener {
    int values = 0, begun = 0, ended = 0;
    void parameterValueChanged(int, float) override { ++values; }
    void parameterGestureChanged(int, bool starting) override { if (starting) { ++begun; } else { ++ended; } }
};

/// A play head that says what the test says (PluginTransportTests' idea).
struct PlayHead final : juce::AudioPlayHead {
    std::optional<double> bpm;
    juce::Optional<PositionInfo> getPosition() const override {
        PositionInfo info;
        if (bpm) { info.setBpm(*bpm); }
        info.setIsPlaying(true);
        return info;
    }
};

float peak(const juce::AudioBuffer<float> &buffer) { return buffer.getMagnitude(0, buffer.getNumSamples()); }

} // namespace

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);
    const juce::ScopedJuceInitialiser_GUI gui;

    S1PluginProcessor processor;
    // The preset browser writes banks, and the folder a plugin uses is the OWNER'S. Every test
    // here works in a folder of its own (ADR-036's rule, in the plugin's words).
    const std::filesystem::path scratch = std::filesystem::temp_directory_path()
        / ("ArcadeRuinsEditorTests-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    processor.presetLibrary().setUserDirectory((scratch / "Banks").u8string());
    processor.setPlayConfigDetails(0, 2, 44100.0, 512);
    processor.prepareToPlay(44100.0, 512);
    juce::AudioBuffer<float> audio(2, 512);
    juce::MidiBuffer midi;

    // MARK: both skins build, at the design size, with every control of the specification
    for (const char *skinKey : { "studio", "cabinet" }) {
        S1PluginEditor editor(processor, skinKey);
        const std::string name = std::string(skinKey) + ": ";
        check(editor.getWidth() == 1440 && editor.getHeight() == 900 && editor.skin().key == skinKey, name + "the editor opens at the design size", editor.getWidth());

        const std::vector<s1ui::ParameterControl *> controls = editor.parameterControls();
        int misplaced = 0;
        for (s1ui::ParameterControl *control : controls) {
            const s1plugin::LayoutControl *entry = editor.skin().control(control->getComponentID().toStdString());
            if (entry == nullptr) { ++misplaced; continue; }
            const juce::Rectangle<float> frame(entry->frame.x, entry->frame.y, entry->frame.width, entry->frame.height);
            if (control->getBounds() != frame.toNearestInt() || entry->parameter != control->parameter().description().address) { ++misplaced; }
        }
        check(controls.size() == 125 && misplaced == 0, name + "walking the tree finds 125 parameter controls, each on its specified frame and parameter", double(controls.size()));

        // The plan's acceptance: every parameter reachable from the interface
        const std::vector<S1Parameter> shown = editor.parametersWithAControl();
        std::set<int> has;
        for (S1Parameter p : shown) { has.insert(int(p)); }
        check(has.size() == 124, name + "124 of the 150 parameters have a control, a plot or a pad of their own", double(has.size()));
        // X3-6: Settings is its own card now, and the list of all 150 is one entry in it.
        editor.pressItem("button.Settings");
        check(editor.isShowingSettings(), name + "Settings opens its card", 0);
        editor.showSettings(false);
        editor.showAllParameters(true);
        auto *list = dynamic_cast<juce::GenericAudioProcessorEditor *>(editor.allParametersList());
        check(editor.isShowingAllParameters() && list != nullptr && list->getAudioProcessor() == &processor
                  && processor.getParameters().size() == S1PluginProcessor::kParameterCount,
              name + "and it reaches the list of every one of the 150, the other 26 among them", double(processor.getParameters().size()));
        std::printf("      without a control of their own:");
        for (int i = 0; i < S1PluginProcessor::kParameterCount; ++i) { if (has.count(i) == 0) { std::printf(" %s", s1plugin::parameterID(i)); } }
        std::printf("\n");
        editor.showAllParameters(false);
        check(!editor.isShowingAllParameters(), name + "and it closes", 0);

        const juce::Image picture = editor.createComponentSnapshot(editor.getLocalBounds(), false, 1.0f);
        int opaque = 0;
        for (int y = 0; y < picture.getHeight(); y += 9) { for (int x = 0; x < picture.getWidth(); x += 9) { if (picture.getPixelAt(x, y).getAlpha() == 255) { ++opaque; } } }
        check(opaque == ((picture.getHeight() + 8) / 9) * ((picture.getWidth() + 8) / 9), name + "the whole window paints, opaque everywhere", opaque);

        for (const char *item : { "button.Panic", "button.Save", "button.Hold", "button.Mono", "button.Snap", "button.Wheels", "button.Previous preset", "button.Next preset", "dice", "octave", "tuning" }) {
            if (!editor.pressItem(item)) { check(false, name + "the item " + item + " is there to press", 0); }
        }
        check(editor.pressItem("button.About") && !editor.isShowingAllParameters(), name + "About opens its own card", 1);
        check(!editor.pressItem("button.MIDI Learn") && !editor.pressItem("record"), name + "MIDI learn (ADR-056) and the recorder are not part of this interface", 0);
    }

    S1PluginEditor editor(processor, "cabinet");

    // MARK: the preset's name, previous and next
    {
        // The loop above pressed every item, the dice and Next among them: start from the sound
        // a new instance has.
        processor.loadPreset(processor.presetLibrary().initialPreset(), false);
        editor.presetBrowser().setCurrent(processor.currentState().capturedPreset().uid);
        editor.refreshLiveState();
        check(editor.presetTitle() == "User: Init", "a new instance shows the sound it starts with: " + editor.presetTitle().toStdString(), 0);
        S1HostParameter &cutoff = processor.hostParameter(S1Parameter::cutoff);
        HostEars ears;
        for (int i = 0; i < S1PluginProcessor::kParameterCount; ++i) { processor.hostParameter(S1Parameter(i)).addListener(&ears); }
        // X3-4: next and previous walk the list the BROWSER is showing — All, until a person
        // picks a bank — not the host's program order.
        const int row = editor.presetBrowser().currentRow();
        check(row >= 0, "the sound that is playing is a row of the browser's list", row);
        editor.stepPreset(1);
        const juce::String first = editor.presetTitle();
        check(editor.presetBrowser().currentRow() == row + 1, "Next is the row below it", editor.presetBrowser().currentRow());
        check(first != "User: Init" && first.contains(": "), "and the name follows: " + first.toStdString(), 0);
        check(ears.begun > 0 && ears.begun == ears.ended, "loaded as a person's choice: every changed parameter inside a gesture", ears.begun);
        editor.pressItem("button.Previous preset");
        check(editor.presetTitle() == "User: Init", "Previous comes back", editor.presetBrowser().currentRow());
        editor.presetBrowser().selectCategory(0);
        editor.presetBrowser().setCurrent(editor.presetBrowser().shown().front().uid);
        editor.pressItem("button.Previous preset");
        check(editor.presetBrowser().currentRow() == int(editor.presetBrowser().shown().size()) - 1, "and Previous from the first row wraps to the last", editor.presetBrowser().currentRow());
        editor.pressItem("button.Next preset");
        for (int i = 0; i < S1PluginProcessor::kParameterCount; ++i) { processor.hostParameter(S1Parameter(i)).removeListener(&ears); }
        (void)cutoff;
    }

    // MARK: Mono, Snap, and what is not built yet says so (Save and Tuning are built now: X3-4, X3-5)
    {
        S1HostParameter &mono = processor.hostParameter(S1Parameter::isMono);
        const float before = mono.plainValue();
        editor.pressItem("button.Mono");
        check(mono.plainValue() != before, "the play bar's Mono is the Mono parameter", mono.plainValue());
        editor.pressItem("button.Mono");
    }

    // MARK: Panic, heard; and the scope sees the output
    {
        // A sound that SUSTAINS — the shipped Init — or silence after Panic proves nothing: the first
        // version of this played a preset that dies away by itself and passed with Panic disconnected.
        processor.loadPreset(processor.presetLibrary().initialPreset(), false);
        midi.addEvent(juce::MidiMessage::noteOn(1, 57, 0.8f), 0);
        std::array<float, S1PluginProcessor::kScopeLength> scope {};
        float loudest = 0, scopePeak = 0, held = 0;
        for (int block = 0; block < 700; ++block) {   // eight seconds, the key down throughout
            audio.clear(); processor.processBlock(audio, midi); midi.clear();
            loudest = std::max(loudest, peak(audio));
            held = peak(audio);
            if (block % 10 == 0) {
                processor.readScope(scope);
                for (float sample : scope) { scopePeak = std::max(scopePeak, std::fabs(sample)); }
            }
        }
        check(loudest > 0.01f && held > 0.2f * loudest, "a held note is still sounding eight seconds on", held);
        check(scopePeak > 0.5f * loudest, "and the scope's ring holds what was played", scopePeak);

        editor.pressItem("button.Panic");
        float tail = 1;
        for (int block = 0; block < 700; ++block) { audio.clear(); processor.processBlock(audio, midi); tail = peak(audio); }
        check(tail < 1.0e-4f, "Panic releases it: eight seconds more, the key never lifted, and there is silence", tail);
        midi.addEvent(juce::MidiMessage::noteOn(1, 57, 0.8f), 0);
        float again = 0;
        for (int block = 0; block < 100; ++block) { audio.clear(); processor.processBlock(audio, midi); midi.clear(); again = std::max(again, peak(audio)); }
        check(again > 0.5f * loudest, "and the same key plays again afterwards (the router let go of it too)", again);
        editor.pressItem("button.Panic");
        for (int block = 0; block < 10; ++block) { audio.clear(); processor.processBlock(audio, midi); }
    }

    // MARK: the host's tempo is shown, not edited
    {
        s1ui::Stepper *tempo = nullptr;
        for (s1ui::ParameterControl *control : editor.parameterControls()) {
            if (control->getComponentID() == "Sequencer.arpRate") { tempo = dynamic_cast<s1ui::Stepper *>(control); }
        }
        check(tempo != nullptr && tempo->isEnabled(), "the tempo is editable with no host tempo", tempo != nullptr);
        PlayHead head;
        head.bpm = 97.0;
        processor.setPlayHead(&head);
        audio.clear(); processor.processBlock(audio, midi);
        audio.clear(); processor.processBlock(audio, midi);
        editor.refreshLiveState();
        check(tempo != nullptr && !tempo->isEnabled() && tempo->text() == "97 bpm", "under a host at 97 it reads 97 bpm and takes no edits", tempo != nullptr ? tempo->plain() : 0);
        processor.setPlayHead(nullptr);
        audio.clear(); processor.processBlock(audio, midi);
        editor.refreshLiveState();
        check(tempo != nullptr && tempo->isEnabled(), "and it is the plugin's own again when the host's goes", 0);
    }

    // MARK: the playing step
    {
        processor.hostParameter(S1Parameter::arpIsOn).setValueNotifyingHost(1.0f);
        midi.addEvent(juce::MidiMessage::noteOn(1, 60, 0.8f), 0);
        int lit = 0, litSteps = 0;
        std::set<juce::String> seen;
        for (int block = 0; block < 120; ++block) {
            audio.clear(); processor.processBlock(audio, midi); midi.clear();
            if (block % 3 != 0) { continue; }
            editor.refreshLiveState();
            const juce::Image boxes = editor.createComponentSnapshot(editor.getLocalBounds().withTop(640).withBottom(760), false, 1.0f);
            (void)boxes;
            ++lit;
        }
        // The ring is a StepOctave's state; ask the boxes through their pictures' difference instead of a getter
        for (s1ui::ParameterControl *control : editor.parameterControls()) {
            auto *box = dynamic_cast<s1ui::StepOctave *>(control);
            if (box == nullptr) { continue; }
            const juce::Image now = box->createComponentSnapshot(box->getLocalBounds(), false, 1.0f);
            box->setPlaying(false);
            const juce::Image idle = box->createComponentSnapshot(box->getLocalBounds(), false, 1.0f);
            bool differs = false;
            for (int x = 0; x < now.getWidth() && !differs; ++x) { differs = now.getPixelAt(x, 1) != idle.getPixelAt(x, 1); }
            if (differs) { ++litSteps; seen.insert(box->getComponentID()); }
        }
        check(lit > 0 && litSteps == 1, "while the arpeggiator runs exactly one step's box wears the playhead's ring", litSteps);
        midi.addEvent(juce::MidiMessage::noteOff(1, 60), 0);
        audio.clear(); processor.processBlock(audio, midi); midi.clear();
        processor.hostParameter(S1Parameter::arpIsOn).setValueNotifyingHost(0.0f);
        editor.refreshLiveState();
    }

    // MARK: X3-4 — the preset browser's card, driven without a mouse
    {
        check(!editor.isShowingPresets(), "the card is away until it is asked for", 0);
        editor.pressItem("presetField");
        check(editor.isShowingPresets() && editor.presets() != nullptr, "the preset name drops the card down", 0);
        s1ui::PresetPanel &card = *editor.presets();
        const juce::Rectangle<int> bounds = card.getBounds();
        check(bounds.getWidth() == 380 && bounds.getHeight() > 200 && editor.getLocalBounds().contains(bounds),
              "380 wide, hung under the name and inside the window", bounds.getHeight());
        check(card.rowCount() == int(editor.presetBrowser().shown().size()) && card.rowCount() > 600,
              "it shows the browser's list", card.rowCount());

        // Choosing a row plays it
        HostEars ears;
        for (int i = 0; i < S1PluginProcessor::kParameterCount; ++i) { processor.hostParameter(S1Parameter(i)).addListener(&ears); }
        card.chooseRow(3);
        const std::string chosen = editor.presetBrowser().shown()[3].name;
        check(processor.currentPresetName().toStdString() == chosen, "a row chosen is the sound that plays: " + chosen, 0);
        check(ears.begun > 0 && ears.begun == ears.ended, "…as a person's choice, in gestures a host records", ears.begun);
        for (int i = 0; i < S1PluginProcessor::kParameterCount; ++i) { processor.hostParameter(S1Parameter(i)).removeListener(&ears); }

        // A category row filters the list
        card.chooseCategory(s1plugin::PresetBrowser::kBankStartingIndex + 1);     // the User bank
        check(editor.presetBrowser().shownBank() == "User" && card.rowCount() == 1, "a bank's row shows that bank", card.rowCount());
        card.chooseCategory(0);

        // The search field
        card.setSearch("pressing on");
        check(card.rowCount() > 0 && card.rowCount() < 10, "the search field narrows the list", card.rowCount());
        card.setSearch("");

        // New, and the star
        const int before = card.rowCount();
        card.pressButton("new");
        check(editor.presetBrowser().shownBank() == "User", "New shows the User bank", card.rowCount());
        check(processor.currentPresetName() == "Init", "…and the new preset is what plays", 0);
        check(editor.presetBrowser().all().size() == size_t(before) + 1, "…one more preset in the library", double(editor.presetBrowser().all().size()));
        const std::string madeUID = editor.presetBrowser().currentUID();
        card.pressRowButton(card.rowCount() - 1, "star");
        check(editor.presetBrowser().presetWithUID(madeUID) != nullptr
                  && editor.presetBrowser().presetWithUID(madeUID)->isFavorite, "the star on a row stars that preset", 0);

        // Save: the toolbar's button opens the editor card on the sound as it stands
        processor.hostParameter(S1Parameter::cutoff).setValueNotifyingHost(0.33f);
        const float cutoff = processor.hostParameter(S1Parameter::cutoff).plainValue();
        editor.pressItem("button.Save");
        check(card.editorCard() != nullptr, "Save opens the preset editor over the card", 0);
        card.editorCardSave("Saved By The Test", 3, "User");
        const s1::Preset *saved = editor.presetBrowser().presetWithUID(madeUID);
        check(saved != nullptr && saved->name == "Saved By The Test", "the name it was given", 0);
        check(saved != nullptr && saved->category == 3, "the category it was given", saved != nullptr ? saved->category : -1);
        check(saved != nullptr && std::abs(float(saved->cutoff) - cutoff) < 0.5f, "and the sound that was playing", saved != nullptr ? saved->cutoff : 0);
        check(processor.currentPresetName() == "Saved By The Test", "what plays is the preset that was saved", 0);

        // Reorder, up and down, on a bank's own list
        card.chooseCategory(editor.presetBrowser().categoryIndexOfBank("Starter Bank"));
        const std::string wasFirst = editor.presetBrowser().shown().front().uid;
        const std::string wasSecond = editor.presetBrowser().shown()[1].uid;
        check(!card.pressRowButton(0, "down"), "a row carries no arrows until Reorder is pressed", 0);
        card.pressButton("reorder");
        check(card.isReordering(), "Reorder turns the rows' marks into arrows", 0);
        check(!card.pressRowButton(0, "star"), "…and the star, rename, duplicate and share are not there then", 0);
        check(card.pressRowButton(0, "down"), "the arrow moves the row", 0);
        check(editor.presetBrowser().shown()[1].uid == wasFirst && editor.presetBrowser().shown().front().uid == wasSecond,
              "…down one place, and the row above it up", 0);
        check(editor.presetBrowser().shown()[1].position == 1, "with the bank's positions written from the top", editor.presetBrowser().shown()[1].position);
        card.pressRowButton(1, "up");
        check(editor.presetBrowser().shown().front().uid == wasFirst, "and the other arrow puts it back", 0);
        card.pressButton("reorder");
        check(!card.isReordering(), "Done ends it", 0);

        // Duplicate
        card.chooseCategory(editor.presetBrowser().categoryIndexOfBank("User"));
        const int inUser = card.rowCount();
        card.pressRowButton(0, "duplicate");
        check(card.rowCount() == inUser + 1, "duplicate leaves a copy in the User bank", card.rowCount());
        check(processor.currentPresetName().endsWith("[copy]"), "…and the copy is what plays: " + processor.currentPresetName().toStdString(), 0);

        // The dice
        const juce::String was = processor.currentPresetName();
        editor.pressItem("dice");
        check(processor.currentPresetName() != was, "the dice plays another preset: " + processor.currentPresetName().toStdString(), 0);

        // Closing
        editor.pressItem("presetField");
        check(!editor.isShowingPresets(), "the name again puts the card away", 0);
        editor.showPresets(true);
        editor.showPresets(false);
        check(editor.presets() == nullptr, "and it can be opened and closed without a mouse", 0);
    }

    // MARK: X3-6 — the cabinet's joystick
    {
        editor.applySkin("cabinet");
        check(editor.hasJoystick(), "Cabinet has a joystick over the console the painting leaves empty", 0);
        if (editor.hasJoystick()) {
            // Where the Mac puts it: the `reach` box, in window points.
            const juce::Rectangle<int> where = editor.joystickBounds();
            // The box is the specification's `reach` widened to swing in (24 painting pixels a
            // side); the grab area inside it is the reach itself.
            check(where.getWidth() > 95 && where.getWidth() < 115 && where.getHeight() > 80 && where.getHeight() < 120,
                  "…on the specification's box, widened to swing in", where.getWidth());
            check(editor.getLocalBounds().contains(where), "…inside the window", 0);

            // Up is the mod wheel. It does not touch the kernel from here: the next block does.
            S1HostParameter &cutoff = processor.hostParameter(S1Parameter::cutoff);
            processor.setModWheelRouting(s1plugin::ModWheelRouting::cutoff);
            const float before = processor.engineValue(S1Parameter::cutoff);
            editor.joystickGrab();
            editor.joystickMoveBy(0.0f, -36.0f);               // a full push away
            juce::AudioBuffer<float> block(2, 512);
            juce::MidiBuffer none;
            block.clear();
            processor.processBlock(block, none);
            check(processor.engineValue(S1Parameter::cutoff) != before,
                  "pushing it away moves the mod wheel, and the kernel hears it at the next block",
                  processor.engineValue(S1Parameter::cutoff));
            check(editor.joystickPush() > 0.9f, "…and the stick is pushed over", editor.joystickPush());

            // X3-10 (the owner, 2026-09-21): PULLING it takes the bitcrusher's rate down with it.
            {
                S1HostParameter &rate = processor.hostParameter(S1Parameter::bitCrushSampleRate);
                const float sittingAt = rate.getValue(), hertzBefore = rate.plainValue();
                editor.joystickGrab();
                editor.joystickMoveBy(0.0f, 36.0f);           // a full pull towards you
                check(rate.getValue() < 0.001f, "pulling the stick all the way down puts the bitcrusher's rate at its floor", rate.getValue());
                check(std::fabs(rate.plainValue() - 2048.0f) < 1.0f, "…which is 2,048 Hz, the parameter's minimum", rate.plainValue());
                block.clear();
                processor.processBlock(block, none);
                check(std::fabs(processor.engineValue(S1Parameter::bitCrushSampleRate) - 2048.0f) < 1.0f,
                      "…and the kernel hears it at the next block", processor.engineValue(S1Parameter::bitCrushSampleRate));
                // Letting go springs it back to where the sound had it — at once, not over the
                // spring's 0.45 s: only the PICTURE takes that long.
                editor.joystickLetGo();
                check(std::fabs(rate.plainValue() - hertzBefore) < 1.0f, "letting go puts the rate back where it was", rate.plainValue());
                // Half way down is half way there, measured where the KNOB sits rather than in
                // hertz. A fresh grab, because a pull starts from wherever the sound has it.
                editor.joystickGrab();
                editor.joystickMoveBy(0.0f, 18.0f);
                check(std::fabs(rate.getValue() - sittingAt * 0.5f) < 0.02f, "half a pull is half way down the knob's travel", rate.getValue());
                editor.joystickLetGo();
                // And a PUSH is the mod wheel's alone: it leaves the bitcrusher where it is.
                editor.joystickGrab();
                editor.joystickMoveBy(0.0f, -36.0f);
                check(std::fabs(rate.plainValue() - hertzBefore) < 1.0f, "pushing it away does not touch the rate", rate.plainValue());
                editor.joystickLetGo();
                block.clear();
                processor.processBlock(block, none);
            }

            // Sideways bends the pitch, through the parameter a host would automate.
            S1HostParameter &bend = processor.hostParameter(S1Parameter::pitchbend);
            const float centred = bend.getValue();
            editor.joystickGrab();
            editor.joystickMoveBy(36.0f, 0.0f);
            check(bend.getValue() > centred + 0.3f, "leaning it sideways bends the pitch", bend.getValue());
            check(std::abs(editor.joystickLean() - 1.0f) < 0.01f, "…and the stick leans with it", editor.joystickLean());

            // The 15% dead zone is the PITCH's, not the picture's: a small lean moves the stick
            // and not the note.
            editor.joystickGrab();
            editor.joystickMoveBy(36.0f * 0.10f, 0.0f);
            check(std::abs(bend.getValue() - 0.5f) < 0.001f, "a lean inside the dead zone does not bend the pitch", bend.getValue());
            // The stick still LEANS in the picture, which is the half a stored number cannot
            // show: the dead zone is upstream's on the value only. Measured on the pixels,
            // because a check that reads back what was just written cannot fail.
            check(editor.joystickLean() > 0.05f, "…though the stick still leans", editor.joystickLean());
            const juce::Image leaning = editor.createComponentSnapshot(editor.joystickBounds(), false, 1.0f);
            editor.joystickLetGo();
            editor.joystickGrab();
            editor.joystickMoveBy(0.0f, 0.0f);
            const juce::Image upright = editor.createComponentSnapshot(editor.joystickBounds(), false, 1.0f);
            int moved = 0;
            for (int y = 0; y < upright.getHeight(); ++y) {
                for (int x = 0; x < upright.getWidth(); ++x) {
                    if (leaning.getPixelAt(x, y) != upright.getPixelAt(x, y)) { ++moved; }
                }
            }
            check(moved > 40, "…and it is drawn leaning, not just recorded as leaning", moved);

            // Leaned hard right, the ball must still be drawn WHOLE. JUCE clips a component to
            // its bounds where UIKit does not, so the box is wider than the grab area; without
            // that the ball was cut off against the console (the owner, 2026-09-20).
            editor.joystickGrab();
            editor.joystickMoveBy(36.0f, 0.0f);
            {
                const juce::Rectangle<int> box = editor.joystickBounds();
                const juce::Image leaned = editor.createComponentSnapshot(box, false, 1.0f);
                editor.joystickLetGo();
                editor.joystickGrab();
                editor.joystickMoveBy(0.0f, 0.0f);
                const juce::Image upright = editor.createComponentSnapshot(box, false, 1.0f);
                // Where the picture CHANGED is where the stick went; the painting behind it is
                // identical in both, so it cancels out.
                int rightmost = -1;
                for (int x = box.getWidth() - 1; x >= 0 && rightmost < 0; --x) {
                    for (int y = 0; y < box.getHeight(); ++y) {
                        if (leaned.getPixelAt(x, y) != upright.getPixelAt(x, y)) { rightmost = x; break; }
                    }
                }
                const int grabRight = juce::roundToInt((box.getWidth() + 60) * 0.5f);   // the reach's right edge
                check(rightmost > grabRight, "the leaned ball is drawn PAST the grab area's edge", rightmost);
                check(rightmost < box.getWidth() - 1, "…and is not cut off at the box's own edge", box.getWidth() - 1 - rightmost);
            }

            // Letting go springs it back and centres the bend.
            editor.joystickLetGo();
            check(std::abs(bend.getValue() - 0.5f) < 0.001f, "letting go centres the bend", bend.getValue());
        }
        editor.applySkin("studio");
        check(!editor.hasJoystick(), "Studio has none: it is the cabinet's", 0);
        editor.applySkin("cabinet");
    }

    // MARK: X3-9 — a CLICK puts no rectangle round a button; the keyboard still gets its ring
    // (the owner, 2026-09-21: clicking the console's red buttons drew a rectangle round them)
    {
        S1PluginEditor editor(processor, "cabinet");
        editor.setVisible(true);
        juce::Component *red = nullptr;
        for (juce::Component *layer : editor.getChildren()) {
            if (red == nullptr) { red = layer->findChildWithID("power.off"); }
        }
        check(red != nullptr, "Cabinet's console has its left red button", 0);
        if (red != nullptr) {
            const juce::Rectangle<int> where = editor.getLocalArea(red, red->getLocalBounds());
            const auto differs = [&](const juce::Image &a, const juce::Image &b) {
                int count = 0;
                for (int y = 0; y < a.getHeight(); ++y) {
                    for (int x = 0; x < a.getWidth(); ++x) { if (a.getPixelAt(x, y) != b.getPixelAt(x, y)) { ++count; } }
                }
                return count;
            };
            const juce::Image rest = editor.createComponentSnapshot(where, false, 1.0f);
            red->focusGained(juce::Component::focusChangedByMouseClick);
            const juce::Image clicked = editor.createComponentSnapshot(where, false, 1.0f);
            check(differs(rest, clicked) == 0, "clicked, the red button is still only the painting — no rectangle", differs(rest, clicked));
            red->focusLost(juce::Component::focusChangedByMouseClick);
            // …nor does focus that is HANDED to it, as JUCE does with the first button in the
            // window when a card closes: the owner saw that round the title (2026-09-21)
            red->focusGained(juce::Component::focusChangedDirectly);
            const juce::Image handed = editor.createComponentSnapshot(where, false, 1.0f);
            check(differs(rest, handed) == 0, "handed the focus when a card closes, it draws no rectangle either", differs(rest, handed));
            red->focusLost(juce::Component::focusChangedDirectly);
            red->focusGained(juce::Component::focusChangedByTabKey);
            const juce::Image tabbed = editor.createComponentSnapshot(where, false, 1.0f);
            check(differs(rest, tabbed) > 20, "reached by Tab, it has its focus ring", differs(rest, tabbed));
            red->focusLost(juce::Component::focusChangedByTabKey);
            const juce::Image left = editor.createComponentSnapshot(where, false, 1.0f);
            check(differs(rest, left) == 0, "…which goes when the focus does", differs(rest, left));
        }
    }

    // MARK: the console holds only what works (the owner's repaint, 2026-09-21): the three yellow
    // buttons did nothing and are gone. Measured in the pixels: no yellow above the red buttons.
    {
        S1PluginEditor editor(processor, "cabinet");
        editor.setVisible(true);
        const juce::Image console = editor.createComponentSnapshot({ 104, 768, 70, 34 }, false, 1.0f);
        int yellow = 0, red = 0;
        for (int y = 0; y < console.getHeight(); ++y) {
            for (int x = 0; x < console.getWidth(); ++x) {
                const juce::Colour c = console.getPixelAt(x, y);
                if (c.getRed() > 190 && c.getGreen() > 120 && c.getBlue() < 110) { ++yellow; }
            }
        }
        const juce::Image buttons = editor.createComponentSnapshot({ 118, 800, 60, 28 }, false, 1.0f);
        for (int y = 0; y < buttons.getHeight(); ++y) {
            for (int x = 0; x < buttons.getWidth(); ++x) {
                const juce::Colour c = buttons.getPixelAt(x, y);
                if (c.getRed() > 190 && c.getGreen() < 90 && c.getBlue() < 90) { ++red; }
            }
        }
        check(yellow == 0, "the console has no yellow buttons", yellow);
        check(red > 300, "…and still has its two red ones", red);
    }

    // MARK: Studio's wordmark is the owner's artwork PIXEL FOR PIXEL (2026-09-21: "the text on it
    // somehow seems misaligned" — it was a 13-pixel-tall iPhone asset stretched to 240). On a 2x
    // display at the design size the 360-pixel cut is laid down unscaled, so what is on the glass
    // must be that file over the header's colour and nothing else. Absolute: no resampler in it.
    {
        S1PluginEditor editor(processor, "studio");
        editor.setVisible(true);
        const s1plugin::LayoutItem *mark = nullptr;
        for (const s1plugin::LayoutItem &item : editor.skin().items) { if (item.id == "wordmark") { mark = &item; } }
        check(mark != nullptr, "Studio has a wordmark", 0);
        const juce::Image cut = juce::ImageFileFormat::loadFrom(S1ArtData::wordmark360_png, size_t(S1ArtData::wordmark360_pngSize));
        check(cut.isValid() && cut.getWidth() == 360, "its 2x cut is linked in, 360 pixels wide", cut.getWidth());
        if (mark != nullptr && cut.isValid()) {
            // Half as big again as the specification's frame (the owner: "it looks tiny"), grown to
            // the right about the same middle: 180 points, which is this cut at 2x exactly.
            const juce::Rectangle<float> measured(mark->frame.x, mark->frame.y, mark->frame.width, mark->frame.height);
            const juce::Rectangle<int> frame = measured.withSizeKeepingCentre(measured.getWidth(), measured.getHeight() * 1.5f)
                                                       .withWidth(measured.getWidth() * 1.5f).toNearestInt();
            check(frame.getWidth() == 180, "the wordmark is 180 points wide, not the Mac's 120", frame.getWidth());
            const juce::Image shown = editor.createComponentSnapshot(frame, false, 2.0f);
            // From the frame's left edge, and about its middle — on a whole pixel, which for a cut
            // with an odd number of rows is not where plain centring puts it.
            const int left = 0;
            const int top = juce::roundToInt((measured.getCentreY() - float(cut.getHeight()) * 0.25f) * 2.0f) - frame.getY() * 2;
            double difference = 0;
            int lettered = 0;
            for (int y = 0; y < cut.getHeight(); ++y) {
                for (int x = 0; x < cut.getWidth(); ++x) {
                    const juce::Colour ink = cut.getPixelAt(x, y);
                    if (ink.getAlpha() < 250) { continue; }          // the letters' solid insides: no blend to model
                    const juce::Colour seen = shown.getPixelAt(left + x, top + y);
                    difference += std::abs(int(seen.getRed()) - int(ink.getRed())) + std::abs(int(seen.getGreen()) - int(ink.getGreen())) + std::abs(int(seen.getBlue()) - int(ink.getBlue()));
                    ++lettered;
                }
            }
            const double mean = lettered > 0 ? difference / (3.0 * lettered) : 255.0;
            check(lettered > 800, "the wordmark has letters to measure", lettered);
            check(mean < 3.0, "every solid pixel of the artwork is on the glass where the file has it", mean);
        }
    }

    // MARK: X3-9 (ADR-091) — the power, in the PIXELS: every zone colourless when it is cut and
    // coloured when it is not, the chrome as well as the sections; and ADR-062's own check — a
    // render after off-then-on is pixel-identical to one never darkened. The clock is injected.
    {
        S1PluginEditor editor(processor, "cabinet");
        editor.setVisible(true);
        const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
        const auto &painting = *editor.skin().painting;
        auto settle = [&editor] { for (int i = 0; i < 130; ++i) { editor.refreshLiveState(); } };   // the status line's words lapse
        auto whole = [&editor] { return editor.createComponentSnapshot(editor.getLocalBounds(), false, 1.0f); };
        auto zoneBox = [&](const std::string &zone) {
            s1plugin::LayoutRect box;
            if (const auto chrome = painting.power->zones.find(zone); chrome != painting.power->zones.end()) { box = chrome->second; }
            else { box = painting.sections.at(zone); }
            const s1plugin::LayoutRect at = painting.inWindow(box, spec.designWidth, spec.designHeight);
            return juce::Rectangle<float>(at.x, at.y, at.width, at.height).toNearestInt().reduced(3);
        };
        auto coloured = [](const juce::Image &image, juce::Rectangle<int> box) {
            int count = 0;
            for (int y = box.getY(); y < box.getBottom(); ++y) {
                for (int x = box.getX(); x < box.getRight(); ++x) {
                    const juce::Colour c = image.getPixelAt(x, y);
                    const int most = std::max({ int(c.getRed()), int(c.getGreen()), int(c.getBlue()) });
                    const int least = std::min({ int(c.getRed()), int(c.getGreen()), int(c.getBlue()) });
                    if (most - least > 28) { ++count; }
                }
            }
            return count;
        };
        settle();
        const juce::Image never = whole();
        const std::vector<std::string> zones = editor.powerZones();
        check(zones.size() == 19, "nineteen zones: the fifteen sections and display, buttons, screen, bar", double(zones.size()));
        int dull = 0;
        for (const std::string &zone : zones) { if (coloured(never, zoneBox(zone)) < 40) { ++dull; std::printf("      (lit, but colourless: %s)\n", zone.c_str()); } }
        check(dull == 0, "lit, every zone has colour in it — so going grey is something to measure", dull);

        editor.runPower(false);
        editor.advancePowerTo(9.0);
        settle();
        const juce::Image dark = whole();
        int stillLit = 0, worst = 0;
        for (const std::string &zone : zones) {
            const int count = coloured(dark, zoneBox(zone));
            worst = std::max(worst, count);
            if (count > 0) { ++stillLit; std::printf("      (still coloured in the dark: %s, %d pixels)\n", zone.c_str(), count); }
        }
        check(stillLit == 0, "with the power cut NOTHING in any zone has colour: sections, preset name, scope, toolbar, bar", worst);

        // Dark is GREY, not gone: every caption beside a control is still there to read. (The first
        // cut laid the grey painting over the words, and a dead section lost them — seen in a render.)
        {
            int captions = 0, vanished = 0;
            for (const s1plugin::LayoutControl &control : editor.skin().controls) {
                if (!control.titleFrame || control.title.empty() || control.kind == s1plugin::LayoutControlKind::chip) { continue; }
                const juce::Rectangle<int> box = juce::Rectangle<float>(control.titleFrame->x, control.titleFrame->y, control.titleFrame->width, control.titleFrame->height).toNearestInt();
                int inked = 0;
                for (int y = box.getY(); y < box.getBottom(); ++y) {
                    for (int x = box.getX(); x < box.getRight(); ++x) { if (dark.getPixelAt(x, y).getBrightness() > 0.42f) { ++inked; } }
                }
                ++captions;
                if (inked < 6) { ++vanished; }
            }
            check(captions > 40, "there are captions to look for", captions);
            check(vanished == 0, "in the dark every caption is still there, in grey", vanished);
        }

        // …and half way, some are dark and some are not: it is a flicker, not a switch
        editor.runPower(true);
        editor.advancePowerTo(4.5);
        int back = 0;
        for (const std::string &zone : zones) { if (editor.zoneDim(zone) < 0.5f) { ++back; } }
        check(back > 3 && back < 16, "half way through the cycle some zones are back and some are not", back);
        editor.advancePowerTo(9.0);
        settle();
        const juce::Image again = whole();
        int different = 0;
        for (int y = 0; y < never.getHeight(); ++y) {
            for (int x = 0; x < never.getWidth(); ++x) { if (never.getPixelAt(x, y) != again.getPixelAt(x, y)) { ++different; } }
        }
        check(different == 0, "off and then on again is pixel-identical to never darkened (ADR-062's own check)", different);
    }

    // MARK: X3-9 — a CLICK on each red button reaches THAT button and does its own thing. Every
    // check until now pressed them by calling their action, so nothing ever asked what is under
    // the mouse there (the owner, 2026-09-22: "the red button turns off the colors, but neither of
    // them turn them back on again").
    {
        S1PluginEditor editor(processor, "cabinet");
        editor.setVisible(true);
        editor.restorePower();
        juce::Component *off = nullptr, *on = nullptr;
        for (juce::Component *layer : editor.getChildren()) {
            if (off == nullptr) { off = layer->findChildWithID("power.off"); }
            if (on == nullptr) { on = layer->findChildWithID("power.on"); }
        }
        check(off != nullptr && on != nullptr, "the console has both red buttons", 0);
        if (off != nullptr && on != nullptr) {
            check(!off->getBounds().intersects(on->getBounds()), "…and they do not overlap each other", double(off->getBounds().getRight() - on->getBounds().getX()));
            const auto hitAt = [&editor](juce::Component *button) {
                const juce::Point<int> centre = editor.getLocalArea(button, button->getLocalBounds()).getCentre();
                juce::Component *under = editor.getComponentAt(centre);
                return under != nullptr ? under->getComponentID() : juce::String("nothing");
            };
            check(hitAt(off) == "power.off", "a click where the LEFT button is reaches it", 0);
            std::printf("note  under the left button: %s; under the right: %s\n", hitAt(off).toRawUTF8(), hitAt(on).toRawUTF8());
            check(hitAt(on) == "power.on", "a click where the RIGHT button is reaches IT, not its neighbour", 0);
        }
    }

    // MARK: X3-9 (ADR-099) — the two faults the owner met: "the red button turns off the colors,
    // but neither of them turn them back on again". Both come of a cycle that assumed every zone
    // started in the state it was leaving.
    {
        S1PluginEditor editor(processor, "cabinet");
        editor.setVisible(true);
        const std::vector<std::string> zones = editor.powerZones();
        const auto lit = [&editor, &zones] {
            int n = 0;
            for (const std::string &zone : zones) { if (editor.zoneDim(zone) < 0.5f) { ++n; } }
            return n;
        };
        // (1) Pressing the button for the way it is ALREADY going must not start the eight seconds
        // again. The first zone does not settle for a second, so a person presses again — and used
        // to hold the interface dark for as long as they kept pressing.
        editor.runPower(false);
        editor.advancePowerTo(9.0);
        check(lit() == 0, "the power cut: nothing is lit", lit());
        editor.runPower(true);
        const int planned = editor.powerCyclePlans();
        check(planned == int(zones.size()), "restoring from the dark plans every zone", planned);
        editor.advancePowerTo(1.0);
        editor.runPower(true);           // …pressed again, a second in
        check(editor.powerCyclePlans() == planned, "pressing it again does NOT start the cycle over", editor.powerCyclePlans());
        editor.advancePowerTo(9.0);
        check(lit() == int(zones.size()), "…so it still finishes: everything is lit", lit());

        // (2) Pressing the OTHER button part way through must not black out what is still lit.
        editor.runPower(false);
        editor.advancePowerTo(3.0);
        const int stillLit = lit();
        check(stillLit > 2 && stillLit < int(zones.size()), "three seconds into the drain, some zones are lit and some are not", stillLit);
        editor.runPower(true);
        check(editor.powerCyclePlans() == int(zones.size()) - stillLit, "restoring mid-drain plans only the zones that went dark", editor.powerCyclePlans());
        editor.advancePowerTo(0.05);
        check(lit() == stillLit, "…and the ones still lit STAY lit: the interface does not black out", lit());
        editor.advancePowerTo(9.0);
        check(lit() == int(zones.size()), "…then everything comes back", lit());
    }

    // MARK: X3-6 — Settings, and changing the skin in place
    {
        check(!editor.isShowingSettings(), "Settings is away until it is asked for", 0);
        editor.pressItem("button.Settings");
        check(editor.isShowingSettings(), "the toolbar's Settings opens it", 0);
        check(!editor.isShowingAllParameters(), "…and it is no longer the list of every parameter", 0);
        // The picker is in there: two buttons, the one for the skin in use switched on.
        editor.pressItem("button.Settings");
        int found = 0, lit = 0;
        {
            std::vector<juce::Component *> queue { &editor };
            while (!queue.empty()) {
                juce::Component *component = queue.back();
                queue.pop_back();
                if (auto *button = dynamic_cast<juce::Button *>(component)) {
                    if (button->getComponentID().startsWith("skin.")) {
                        ++found;
                        if (button->getToggleState()) { ++lit; }
                    }
                }
                for (juce::Component *child : component->getChildren()) { queue.push_back(child); }
            }
        }
        check(found == 2 && lit == 1, "the card holds a button per skin, with the one in use lit", found);
        editor.showSettings(false);

        const std::string was = editor.skin().key;
        const std::string other = was == "cabinet" ? "studio" : "cabinet";
        const int controlsBefore = int(editor.parameterControls().size());
        editor.applySkin(other);
        check(editor.skin().key == other, "the skin changes in place, with no new editor: " + editor.skin().key, 0);
        check(int(editor.parameterControls().size()) == controlsBefore, "every control is built again", double(editor.parameterControls().size()));
        check(editor.getWidth() == 1440 && editor.getHeight() == 900, "at the same size", editor.getWidth());
        check(processor.interfaceSkin().toStdString() == other, "and the choice is remembered for the next instance", 0);
        {
            const juce::Image picture = editor.createComponentSnapshot(editor.getLocalBounds(), false, 1.0f);
            int opaque = 0;
            for (int y = 0; y < picture.getHeight(); y += 17) { for (int x = 0; x < picture.getWidth(); x += 17) { if (picture.getPixelAt(x, y).getAlpha() == 255) { ++opaque; } } }
            check(opaque == ((picture.getHeight() + 16) / 17) * ((picture.getWidth() + 16) / 17),
                  "…and the re-dressed window paints, opaque everywhere", opaque);
        }
        // What spans controls still works after the change
        editor.pressItem("button.Mono");
        editor.pressItem("button.Mono");
        editor.stepPreset(1);
        editor.refreshLiveState();
        check(editor.presetTitle().isNotEmpty(), "…and the toolbar still follows the sound", 0);
        editor.applySkin(was);
        check(editor.skin().key == was, "and back again", 0);
    }

    // MARK: X3-5 — the Tunings card
    {
        check(!editor.isShowingTunings(), "the Tunings card is away until it is asked for", 0);
        editor.pressItem("tuning");
        check(editor.isShowingTunings() && editor.tunings() != nullptr, "the toolbar's Tuning opens it", 0);
        s1ui::TuningsPanel &card = *editor.tunings();
        check(editor.getLocalBounds().contains(card.getBounds()) && card.getWidth() == 700, "it sits inside the window", card.getWidth());

        // The banks and the wheel
        check(processor.tuningLibrary().banks().size() == 3, "three banks", double(processor.tuningLibrary().banks().size()));
        check(int(card.wheelPositions().size()) == processor.tuningLibrary().notesPerOctave(),
              "the wheel draws one degree per note of the scale", double(card.wheelPositions().size()));

        // Choosing a tuning retunes the instrument
        card.chooseBank(s1plugin::TuningLibrary::kHexanyTriadBank);
        card.chooseTuning(2);
        editor.refreshLiveState();
        const int npo = processor.tuningLibrary().notesPerOctave();
        check(npo != 12, "a hexany chosen from the card: " + processor.tuningLibrary().tuningName(), npo);
        juce::AudioBuffer<float> settle(2, 512);
        juce::MidiBuffer none;
        settle.clear();
        processor.processBlock(settle, none);
        const double expected = processor.tuningLibrary().frequencies(double(processor.hostParameter(S1Parameter::frequencyA4).plainValue()))[60];
        check(std::fabs(double(processor.engineTuningFrequency(60)) - expected) < 0.01,
              "…and the kernel is playing it", double(processor.engineTuningFrequency(60)));
        check(int(card.wheelPositions().size()) == npo, "…and the wheel followed", double(card.wheelPositions().size()));

        // Reset puts 12 ET back
        card.pressButton("reset");
        editor.refreshLiveState();
        check(processor.tuningLibrary().notesPerOctave() == 12 && processor.tuningLibrary().tuningName() == "12 ET", "Reset puts 12 ET back", 0);

        // The master tuning is the frequencyA4 parameter, and it is live here
        S1HostParameter &a4 = processor.hostParameter(S1Parameter::frequencyA4);
        a4.setPlainValueFromEngine(432.0f);
        editor.refreshLiveState();
        settle.clear();
        processor.processBlock(settle, none);
        check(std::fabs(double(processor.engineTuningFrequency(69)) - 432.0) < 0.01,
              "moving A4 to 432 retunes the instrument, with no click of the card", double(processor.engineTuningFrequency(69)));
        a4.setPlainValueFromEngine(440.0f);
        editor.refreshLiveState();

        check(!card.pressButton("delete") || processor.tuningLibrary().notesPerOctave() == 12, "Delete refuses 12 ET", 0);
        editor.pressItem("tuning");
        check(!editor.isShowingTunings(), "and the same button puts the card away", 0);
    }

    // MARK: X3-8 (ADR-090): the keyboard drawer, Hold, the octave, the wheels, musical typing
    {
        S1PluginEditor played(processor, "cabinet");
        processor.hostMIDITrace().enabled.store(true);
        juce::AudioBuffer<float> sound(2, 512);
        juce::MidiBuffer none;
        const auto run = [&] { sound.clear(); processor.processBlock(sound, none); };
        const auto notesPlayed = [&] {
            juce::uint32 entries[S1HostMIDITrace::capacity] = {};
            const int count = processor.hostMIDITrace().take(entries, int(S1HostMIDITrace::capacity));
            std::vector<std::pair<int, int>> notes;   // op, note
            for (int i = 0; i < count; ++i) { notes.emplace_back(int(entries[i] >> 24), int((entries[i] >> 16) & 0xFF)); }
            return notes;
        };

        check(!played.isShowingKeyboard(), "the drawer is closed to begin with", 0);
        // The design's Command-K, which is how it opens without a mouse.
        played.keyPressed(juce::KeyPress('k', juce::ModifierKeys::commandModifier, 0));
        check(played.isShowingKeyboard() && played.keys() != nullptr, "Command-K opens it", 1);
        // Four octaves of the Mac's own keyboard, above the play bar — not over it, because Hold
        // and Octave belong with the keys.
        const juce::Rectangle<int> drawer = played.keys()->getBounds();
        const auto playBar = played.skin().regions.find("playBar");
        check(playBar != played.skin().regions.end() && float(drawer.getBottom()) < playBar->second.y,
              "…above the play bar, which stays where it is", drawer.getBottom());
        check(played.keys()->keybed().keyCount() == 49 && played.keys()->keybed().firstNote() == 48,
              "four octaves of keys, notes 48 to 96 (C2 to C6 as upstream numbers them)", played.keys()->keybed().keyCount());

        // A key pressed in the drawer sounds, through the router, as the host's own note.
        run();
        notesPlayed();
        const s1plugin::KeyBox middleC = played.keys()->keybed().boxForNote(60);
        const int sounded = played.keys()->pressAt({ middleC.x + middleC.width * 0.5f, middleC.height * 0.8f });
        run();
        std::vector<std::pair<int, int>> heard = notesPlayed();
        check(sounded == 60 && heard.size() == 1 && heard[0].first == S1HostMIDITrace::hostNoteOn && heard[0].second == 60,
              "a key clicked in the drawer plays that note through the router, as the host's own route", heard.empty() ? -1 : heard[0].second);
        check(played.keys()->litKeys().count(60) > 0, "…and the key is drawn down", 1);
        played.keys()->releaseAll();
        run();
        heard = notesPlayed();
        check(heard.size() == 1 && heard[0].first == S1HostMIDITrace::hostNoteOff, "letting go stops it", heard.empty() ? -1 : heard[0].first);

        // A note the HOST plays lights its key too, as `KeyboardView.hostOnKeys` does — the router
        // reports what it holds, and the drawer draws it. (Found missing by looking at a render:
        // the keys lit for a click and for nothing else.)
        {
            juce::MidiBuffer fromHost;
            fromHost.addEvent(juce::MidiMessage::noteOn(1, 64, juce::uint8(90)), 0);
            sound.clear();
            processor.processBlock(sound, fromHost);
            played.refreshLiveState();
            check(played.keys()->litKeys().count(64) > 0, "a note the host plays lights its key in the drawer", 1);
            juce::MidiBuffer off;
            off.addEvent(juce::MidiMessage::noteOff(1, 64), 0);
            sound.clear();
            processor.processBlock(sound, off);
            played.refreshLiveState();
            check(played.keys()->litKeys().count(64) == 0, "…and goes out when it is let go", 0);
            notesPlayed();
        }

        // Hold: the play bar's button is the router's latch, and it lights.
        played.pressItem("button.Hold");
        played.refreshLiveState();
        check(processor.isHolding(), "Hold latches the router", 1);
        played.pressItem("button.Hold");
        played.refreshLiveState();
        check(!processor.isHolding(), "…and lets go again", 0);

        // The octave stepper moves everything at once: the drawer's keys and the router.
        const int wasShifted = processor.octaveShift();
        check(played.stepItem("octave", 1), "the octave stepper steps", 1);
        played.refreshLiveState();
        check(processor.octaveShift() == wasShifted + 1 && played.keys()->soundingShift() == 12,
              "…and the drawer knows the keys now sound an octave up", played.keys()->soundingShift());
        // The shift must be applied ONCE. The keys do not move — the router adds it to every note
        // that reaches it, the drawer's and the host's alike — so the key that sounded middle C
        // now sounds the C above, and not two octaves up.
        run();
        notesPlayed();
        const int shiftedKey = played.keys()->pressAt({ middleC.x + middleC.width * 0.5f, middleC.height * 0.8f });
        run();
        heard = notesPlayed();
        check(shiftedKey == 60 && heard.size() == 1 && heard[0].second == 72,
              "the same key now sounds one octave up, not two: the shift is applied once", heard.empty() ? -1 : heard[0].second);
        played.keys()->releaseAll();
        run();
        notesPlayed();
        played.stepItem("octave", -1);
        played.refreshLiveState();
        check(processor.octaveShift() == wasShifted && played.keys()->soundingShift() == 0, "and back", processor.octaveShift());

        // Musical typing: what the status bar has promised since X3-3.
        run();
        notesPlayed();
        check(played.typedKeyDown('A', {}), "A is one of the typing keys", 1);
        run();
        heard = notesPlayed();
        check(heard.size() == 1 && heard[0].second == 60, "…and it plays middle C", heard.empty() ? -1 : heard[0].second);
        check(played.typedKeyDown('A', {}), "a held key repeating does not retrigger it", 1);
        run();
        check(notesPlayed().empty(), "…nothing more is played", 0);
        played.releaseTypedNotes();
        run();
        heard = notesPlayed();
        check(heard.size() == 1 && heard[0].first == S1HostMIDITrace::hostNoteOff, "letting the key go stops the note", heard.empty() ? -1 : heard[0].first);

        check(!played.typedKeyDown('S', juce::ModifierKeys::commandModifier), "Command-S is a menu, not a D", 0);
        const int velocityWas = played.typedVelocity();
        played.typedKeyDown('V', {});
        check(played.typedVelocity() == velocityWas + 16, "V raises the typing velocity by 16", played.typedVelocity());
        played.typedKeyDown('C', {});
        check(played.typedVelocity() == velocityWas, "and C lowers it", played.typedVelocity());
        played.typedKeyDown('X', {});
        check(processor.octaveShift() == wasShifted + 1 && played.typedOctave() == processor.octaveShift(),
              "X is the same octave the stepper moves — one octave, not two", played.typedOctave());
        played.typedKeyDown('Z', {});
        check(processor.octaveShift() == wasShifted, "…and Z brings it back", processor.octaveShift());

        // The Wheels card (`WheelSettingsViewController`): what the mod wheel moves, and the bend.
        check(played.pressItem("button.Wheels") && played.isShowingWheels(), "Wheels opens its card", 1);
        juce::Component *lfo1 = nullptr;
        std::vector<juce::Component *> queue { &played };
        while (!queue.empty()) {
            juce::Component *component = queue.back();
            queue.pop_back();
            if (component->getComponentID() == "wheel.1") { lfo1 = component; }
            for (juce::Component *child : component->getChildren()) { queue.push_back(child); }
        }
        // Not `triggerClick`, which POSTS its callback: there is no message loop here (ADR-086).
        if (auto *button = dynamic_cast<juce::Button *>(lfo1); button != nullptr && button->onClick) { button->onClick(); }
        check(processor.getModWheelRouting() == s1plugin::ModWheelRouting::lfo1Rate,
              "…and choosing LFO 1 in it routes the mod wheel there", int(processor.getModWheelRouting()));
        processor.setModWheelRouting(s1plugin::ModWheelRouting::cutoff);
        played.showWheels(false);

        // Remembered per instance: the processor carries it, so the next window opens as this one
        // was left — and a host's session carries it too (PluginStateTests).
        check(processor.keyboardShown(), "the instance remembers that the drawer is open", 1);
        {
            S1PluginEditor reopened(processor, "cabinet");
            check(reopened.isShowingKeyboard(), "…so a new window opens with it up", 1);
        }
        played.showKeyboard(false);
        check(!played.isShowingKeyboard() && !processor.keyboardShown(), "and closing it is remembered too", 0);
        {
            S1PluginEditor reopened(processor, "cabinet");
            check(!reopened.isShowingKeyboard(), "…a new window opens closed, as a host's first one does", 0);
        }
        processor.hostMIDITrace().enabled.store(false);
        processor.requestAllNotesOff();
        run();
    }

    // MARK: X3-7 (ADR-089): the window scales — uniformly, centred, and nothing is re-laid out
    {
        S1PluginEditor scaled(processor, "cabinet");
        const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
        const float dw = spec.designWidth, dh = spec.designHeight;

        juce::ComponentBoundsConstrainer *limits = scaled.getConstrainer();
        check(scaled.isResizable() && limits != nullptr && limits->getMinimumWidth() == juce::roundToInt(dw * 0.75f)
                  && limits->getMaximumWidth() == juce::roundToInt(dw * 1.5f) && limits->getMinimumHeight() == juce::roundToInt(dh * 0.75f)
                  && limits->getMaximumHeight() == juce::roundToInt(dh * 1.5f),
              "the window resizes, between 0.75x and 1.5x of the design size", limits != nullptr ? limits->getMinimumWidth() : 0);
        check(scaled.getWidth() == juce::roundToInt(dw) && scaled.getHeight() == juce::roundToInt(dh) && scaled.interfaceScale() == 1.0f,
              "and it still opens at the design size, 1:1", double(scaled.interfaceScale()));

        // A drag keeps the interface's shape: the constrainer holds the design's aspect ratio, so a
        // host's or a person's pull at one edge takes the other with it.
        scaled.setBoundsConstrained({ 0, 0, 2000, 900 });
        check(std::fabs(double(scaled.getWidth()) / scaled.getHeight() - double(dw) / dh) < 0.01
                  && scaled.getWidth() <= juce::roundToInt(dw * 1.5f),
              "a drag to 2000 x 900 keeps the design's shape and the limits", double(scaled.getWidth()) / scaled.getHeight());

        // Where a child is DRAWN, in the window's own coordinates — through whatever transform.
        const auto inWindow = [&scaled](const juce::Component &child) {
            return scaled.getLocalArea(&child, child.getLocalBounds().toFloat());
        };

        // The plan's acceptance: a 1280 x 800 laptop
        scaled.setSize(1224, 765);
        check(std::fabs(scaled.interfaceScale() - 0.85f) < 0.002f, "a 1280 x 800 laptop shows it at 0.85x", double(scaled.interfaceScale()));
        int cropped = 0;
        for (s1ui::ParameterControl *control : scaled.parameterControls()) {
            if (!scaled.getLocalBounds().toFloat().expanded(0.5f).contains(inWindow(*control))) { ++cropped; }
        }
        check(cropped == 0, "…with every one of its controls inside the window: nothing is cropped", cropped);

        // Uniform, centred, and every frame still the specification's: a control's drawn rectangle
        // is its measured frame times the scale, nothing re-laid out and nothing stretched.
        for (const float wanted : { 0.75f, 1.0f, 1.25f, 1.5f }) {
            scaled.setSize(juce::roundToInt(dw * wanted), juce::roundToInt(dh * wanted));
            int wrong = 0;
            double worst = 0;
            for (s1ui::ParameterControl *control : scaled.parameterControls()) {
                const s1plugin::LayoutControl *entry = scaled.skin().control(control->getComponentID().toStdString());
                if (entry == nullptr) { continue; }
                const juce::Rectangle<float> drawn = inWindow(*control);
                const double offX = (scaled.getWidth() - dw * wanted) * 0.5, offY = (scaled.getHeight() - dh * wanted) * 0.5;
                const double dx = std::fabs(drawn.getX() - (entry->frame.x * wanted + offX)), dy = std::fabs(drawn.getY() - (entry->frame.y * wanted + offY));
                const double dwide = std::fabs(drawn.getWidth() - entry->frame.width * wanted), dhigh = std::fabs(drawn.getHeight() - entry->frame.height * wanted);
                worst = std::max({ worst, dx, dy, dwide, dhigh });
                if (worst > 1.0) { ++wrong; }
            }
            check(wrong == 0, "at " + std::to_string(double(wanted)).substr(0, 4) + "x every control is drawn on its measured frame, scaled and centred", worst);
        }

        // The mouse goes where the eye does. This is what a transform on the drawing ALONE would
        // fail: ask the window what is under the middle of each control, as it is drawn now.
        const auto answering = [&](float at) {
            scaled.setSize(juce::roundToInt(dw * at), juce::roundToInt(dh * at));
            int answered = 0;
            for (s1ui::ParameterControl *control : scaled.parameterControls()) {
                juce::Component *under = scaled.getComponentAt(inWindow(*control).getCentre().roundToInt());
                for (; under != nullptr; under = under->getParentComponent()) { if (under == control) { ++answered; break; } }
            }
            return answered;
        };
        // A component is not visible until something shows it, and an invisible one answers no
        // clicks at all: the host puts the editor in a window, so the test must too.
        scaled.setVisible(true);
        const int at1x = answering(1.0f);
        check(at1x > 100, "at 1x the window finds a control under the middle of it", at1x);
        const int at075 = answering(0.75f), at15 = answering(1.5f);
        check(at1x > 100 && at075 == at1x && at15 == at1x,
              "…and the same ones at 0.75x and 1.5x: the clicks follow the drawing", double(at15));

        // A window that is not the design's shape letterboxes rather than stretching (ADR-019).
        scaled.setSize(1600, 675);
        check(std::fabs(scaled.interfaceScale() - 0.75f) < 0.002f, "a window of another shape scales by the tighter side", double(scaled.interfaceScale()));
        {
            const juce::Rectangle<float> first = inWindow(*scaled.parameterControls().front());
            const s1plugin::LayoutControl *entry = scaled.skin().control(scaled.parameterControls().front()->getComponentID().toStdString());
            const double left = first.getX() - entry->frame.x * 0.75;
            check(std::fabs(left - (1600 - dw * 0.75) * 0.5) < 1.0, "…with the interface centred in it", left);
            // What is left over is PAINTED, in the skin's own window colour. Counting opaque
            // pixels cannot answer this: the editor is opaque, so its snapshot is an RGB image
            // whose alpha is 255 whether anything was drawn or not (it passed with the fill taken
            // out). The colour can — Cabinet's window is #08070d, which is not the black an
            // unpainted image would leave.
            const juce::Image picture = scaled.createComponentSnapshot(scaled.getLocalBounds(), false, 1.0f);
            const s1ui::Style dressed(scaled.skin());
            const juce::Colour empty = dressed.colour("windowBackground");
            int wrongColour = 0;
            for (const juce::Point<int> where : { juce::Point<int>(4, 4), juce::Point<int>(4, 337), juce::Point<int>(120, 670),
                                                  juce::Point<int>(1595, 4), juce::Point<int>(1595, 337), juce::Point<int>(1480, 670) }) {
                if (picture.getPixelAt(where.x, where.y) != empty) { ++wrongColour; }
            }
            check(wrongColour == 0, "…and the margin on either side is painted in the window's own colour", wrongColour);
        }

        // The cards are laid out in the same space, so they scale with it.
        scaled.setSize(juce::roundToInt(dw * 1.5f), juce::roundToInt(dh * 1.5f));
        scaled.showPresets(true);
        const juce::Rectangle<float> card = inWindow(*scaled.presets());
        check(std::fabs(card.getWidth() - s1ui::PresetPanel::kWidth * 1.5f) < 1.0f && scaled.getLocalBounds().toFloat().expanded(0.5f).contains(card),
              "the preset browser's card scales with the window and stays inside it", double(card.getWidth()));
        scaled.showPresets(false);
        scaled.showTunings(true);
        const juce::Rectangle<float> tuningCard = inWindow(*scaled.tunings());
        check(std::fabs(tuningCard.getCentreX() - scaled.getWidth() * 0.5f) < 1.0f
                  && std::fabs(tuningCard.getWidth() - s1ui::TuningsPanel::kWidth * 1.5f) < 1.0f,
              "and the Tunings card stays centred in the window at its size", double(tuningCard.getWidth()));
        scaled.showTunings(false);

        // Crisp: the interface is drawn again at the size it is shown, and its edges still land on
        // WHOLE PIXELS there. ADR-084's measurement, through the window's transform this time: the
        // Transpose stepper's one-point border is a hard edge over a near-black well, and its top
        // sits at design y 868 — 1302.0 at 1.5x, a whole pixel, where it must still read its own
        // colour. A border smeared over two rows loses half of it, and so does one stretched out of
        // a 1x picture.
        //
        // This replaces a check that compared the 1.5x render's edge contrast with a 1x render
        // STRETCHED into the same size. The owner's Windows run failed it at 1.07 against a
        // threshold of 1.15, and showed why it was the wrong measurement: with the backdrop's
        // buffering switched OFF the ratio was 1.0725, against 1.0711 with it on — nothing is
        // cached and stretched there; the platforms' own resamplers differ, so the baseline was
        // measuring the renderer rather than this code. Two native renders compare like with like.
        const s1plugin::LayoutControl *edge = scaled.skin().control("playBar.transpose");
        check(edge != nullptr && std::fabs(edge->frame.y * 1.5f - std::round(edge->frame.y * 1.5f)) < 0.001f,
              "the border measured sits on a whole pixel at 1.5x", edge != nullptr ? double(edge->frame.y) : 0);
        // The colour is read ABSOLUTELY — the stepper's cyan is #22A6B8, the well behind it nearly
        // black — and not against another render of the same interface. The first version of this
        // check compared the border at 1.5x with the border at 1x, and a half-pixel offset moved
        // BOTH: a comparison whose two sides share the fault cannot see it.
        if (edge != nullptr) {
            const int middle = juce::roundToInt(edge->frame.x + edge->frame.width * 0.5f);
            scaled.setSize(juce::roundToInt(dw * 1.5f), juce::roundToInt(dh * 1.5f));
            const juce::Image big = scaled.createComponentSnapshot(scaled.getLocalBounds(), false, 1.0f);
            const juce::Colour border = big.getPixelAt(juce::roundToInt(middle * 1.5f), juce::roundToInt(edge->frame.y * 1.5f));
            const juce::Colour well = big.getPixelAt(juce::roundToInt(middle * 1.5f), juce::roundToInt(edge->frame.y * 1.5f) + 3);
            std::printf("note  at 1.5x the border reads %s and the well behind it %s\n",
                        border.toDisplayString(false).toRawUTF8(), well.toDisplayString(false).toRawUTF8());
            check(border.getBlue() > 150 && border.getGreen() > 130 && well.getBlue() < 90,
                  "at 1.5x a one-point border is still a whole pixel of its own colour, not a smear", border.getBlue());
        }
    }

    // MARK: an editor can go while the processor lives, and come back (hosts do)
    {
        for (int i = 0; i < 5; ++i) {
            std::unique_ptr<juce::AudioProcessorEditor> made(processor.createEditor());
            check(dynamic_cast<S1PluginEditor *>(made.get()) != nullptr || i > 0, "createEditor returns the interface", i);
            processor.hostParameter(S1Parameter::cutoff).setValueNotifyingHost(float(i) / 5.0f);
            made.reset();
            processor.hostParameter(S1Parameter::cutoff).setValueNotifyingHost(0.5f);   // nothing left listening
        }
        check(true, "five editors made and destroyed with parameters moving between", 5);
    }

    processor.releaseResources();
    std::error_code removing;
    std::filesystem::remove_all(scratch, removing);
    std::printf("%s\n", failures == 0 ? "PASSED" : "FAILED");
    return failures == 0 ? 0 : 1;
}
