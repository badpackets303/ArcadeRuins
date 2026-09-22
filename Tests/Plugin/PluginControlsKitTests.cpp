// X3-2 (ADR-084): the controls kit, with no window — every control of the layout specification
// built for both skins and painted at 1x and 2x; each kind driven through the methods its mouse
// handlers call, against the real host parameters, with a listener counting the gestures a host
// would record; the keyboard, the wheel, the double-click's reset; what assistive technology is
// told; and edges that stay on the pixel grid.
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>

#include "S1LinkedLayoutSpec.h"
#include "S1PowerCycle.hpp"
#include "S1PluginProcessor.h"
#include "UI/S1KitControls.h"

namespace {

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

/// A host in write mode: what it would record.
struct HostEars final : juce::AudioProcessorParameter::Listener {
    int values = 0, begun = 0, ended = 0;
    void parameterValueChanged(int, float) override { ++values; }
    void parameterGestureChanged(int, bool starting) override { if (starting) { ++begun; } else { ++ended; } }
    void reset() { values = begun = ended = 0; }
};

struct Listening {
    Listening(S1HostParameter &p, HostEars &e) : parameter(p), ears(e) { ears.reset(); parameter.addListener(&ears); }
    ~Listening() { parameter.removeListener(&ears); }
    S1HostParameter &parameter;
    HostEars &ears;
};

juce::Image snapshot(juce::Component &component, float scale) {
    return component.createComponentSnapshot(component.getLocalBounds(), false, scale);
}

int inkedPixels(const juce::Image &image) {
    int inked = 0;
    for (int y = 0; y < image.getHeight(); ++y) {
        for (int x = 0; x < image.getWidth(); ++x) { if (image.getPixelAt(x, y).getAlpha() > 8) { ++inked; } }
    }
    return inked;
}

int differingPixels(const juce::Image &a, const juce::Image &b) {
    int different = 0;
    for (int y = 0; y < std::min(a.getHeight(), b.getHeight()); ++y) {
        for (int x = 0; x < std::min(a.getWidth(), b.getWidth()); ++x) { if (a.getPixelAt(x, y) != b.getPixelAt(x, y)) { ++different; } }
    }
    return different;
}

bool near(juce::Colour a, juce::Colour b, int tolerance = 10) {
    return std::abs(int(a.getRed()) - int(b.getRed())) <= tolerance && std::abs(int(a.getGreen()) - int(b.getGreen())) <= tolerance
        && std::abs(int(a.getBlue()) - int(b.getBlue())) <= tolerance && a.getAlpha() > 200;
}

/// How many pixels are close to `colour`.
int pixelsNear(const juce::Image &image, juce::Colour colour, int tolerance = 24) {
    int count = 0;
    for (int y = 0; y < image.getHeight(); ++y) {
        for (int x = 0; x < image.getWidth(); ++x) { if (near(image.getPixelAt(x, y), colour, tolerance)) { ++count; } }
    }
    return count;
}

} // namespace

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);
    const juce::ScopedJuceInitialiser_GUI gui;   // a message thread — this one — so attachments call back at once
    using namespace s1ui;

    S1PluginProcessor processor;
    const ParameterLookup lookup = [&](S1Parameter p) -> S1HostParameter & { return processor.hostParameter(p); };
    const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
    const s1plugin::LayoutSkin *studioSkin = spec.skin("studio"), *cabinetSkin = spec.skin("cabinet");
    check(studioSkin != nullptr && cabinetSkin != nullptr, "the linked specification has both skins", double(spec.skins.size()));
    if (studioSkin == nullptr || cabinetSkin == nullptr) { return 1; }
    const Style studio(*studioSkin), cabinet(*cabinetSkin);
    HostEars ears;

    // MARK: every control of the specification, both skins, 1x and 2x
    for (const Style *style : { &studio, &cabinet }) {
        const std::string name = style->skin().key + ": ";
        int made = 0, unpainted = 0, wrongSize = 0, untitled = 0, unfocusable = 0;
        for (const s1plugin::LayoutControl &entry : style->skin().controls) {
            const std::unique_ptr<ParameterControl> control = makeControl(entry, *style, lookup);
            if (control == nullptr) { std::printf("      no control for %s\n", entry.id.c_str()); continue; }
            ++made;
            control->setBounds(0, 0, juce::roundToInt(entry.frame.width), juce::roundToInt(entry.frame.height));
            const juce::Image once = snapshot(*control, 1.0f), twice = snapshot(*control, 2.0f);
            if (inkedPixels(once) == 0 || inkedPixels(twice) == 0) { ++unpainted; std::printf("      paints nothing: %s\n", entry.id.c_str()); }
            if (twice.getWidth() != once.getWidth() * 2 || twice.getHeight() != once.getHeight() * 2) { ++wrongSize; }
            if (control->getTitle().isEmpty()) { ++untitled; std::printf("      no accessible name: %s\n", entry.id.c_str()); }
            if (!control->getWantsKeyboardFocus()) { ++unfocusable; }
            if (&control->parameter() != &processor.hostParameter(entry.parameter)) { ++unpainted; }
        }
        check(made == int(style->skin().controls.size()) && made == 125, name + "a control for every one of the specification's 125", made);
        check(unpainted == 0, name + "each paints something at 1x and at 2x, on its own parameter", unpainted);
        check(wrongSize == 0, name + "and the 2x image is exactly twice the 1x", wrongSize);
        check(untitled == 0, name + "each has an accessible name", untitled);
        check(unfocusable == 0, name + "each takes the keyboard focus", unfocusable);
        int displays = 0;
        for (const s1plugin::LayoutDisplay &entry : style->skin().displays) {
            const std::unique_ptr<juce::Component> view = makeDisplay(entry, *style, lookup);
            if (view == nullptr) { continue; }
            view->setBounds(0, 0, juce::roundToInt(entry.frame.width), juce::roundToInt(entry.frame.height));
            if (inkedPixels(snapshot(*view, 1.0f)) > 0 && inkedPixels(snapshot(*view, 2.0f)) > 0 && view->getTitle().isNotEmpty()) { ++displays; }
        }
        check(displays == 4, name + "the two envelope plots and the two pads, painted and named", displays);
    }

    // MARK: the knob
    {
        const s1plugin::LayoutControl *entry = studioSkin->control("Filter.cutoff");
        S1HostParameter &cutoff = processor.hostParameter(S1Parameter::cutoff);
        std::unique_ptr<ParameterControl> made = makeControl(*entry, studio, lookup);
        auto *knob = dynamic_cast<Knob *>(made.get());
        check(knob != nullptr && knob->getTitle() == "Filter Cutoff", "the cutoff is a knob named \"Filter Cutoff\"", knob != nullptr);
        if (knob == nullptr) { return 1; }
        knob->setBounds(0, 0, 68, 68);

        knob->setPlainAsOneEdit(cutoff.convertFrom0to1(0.25f));
        const float start = knob->position();
        {
            const Listening listening(cutoff, ears);
            knob->grab();
            knob->dragBy(60, 0, false);     // right …
            knob->dragBy(0, -40, false);    // … and up add: 100 points = half the travel
            knob->letGo();
            check(std::fabs(knob->position() - (start + 0.5f)) < 0.002f, "100 points of drag, right and up together, are half the knob's travel", knob->position() - start);
            check(ears.begun == 1 && ears.ended == 1 && ears.values >= 2, "one gesture round the whole drag, the values inside it", ears.values);
        }
        const float beforeFine = knob->position();
        knob->grab(); knob->dragBy(-100, 0, true); knob->letGo();
        check(std::fabs((beforeFine - knob->position()) - 0.1f) < 0.002f, "with Alt the same drag moves a fifth as far", beforeFine - knob->position());
        check(std::fabs(cutoff.plainValue() - cutoff.convertFrom0to1(knob->position())) < 0.01f, "the host parameter holds what the knob shows", cutoff.plainValue());

        {
            const Listening listening(cutoff, ears);
            knob->resetToDefault();
            check(cutoff.plainValue() == cutoff.description().defaultValue && ears.begun == 1 && ears.ended == 1,
                  "a double-click's reset puts the default back as one recorded edit", cutoff.plainValue());
        }
        const float beforeKey = knob->position();
        const bool used = knob->keyPressed(juce::KeyPress(juce::KeyPress::upKey));
        check(used && std::fabs(knob->position() - beforeKey - 0.01f) < 0.002f, "the up key is a hundredth of the travel", knob->position() - beforeKey);
        knob->keyPressed(juce::KeyPress(juce::KeyPress::downKey, juce::ModifierKeys::shiftModifier, 0));
        check(std::fabs(knob->position() - (beforeKey + 0.01f - 0.1f)) < 0.003f, "shift-down is a tenth", knob->position());
        const float beforeWheel = knob->position();
        knob->nudge(0.05f);
        check(std::fabs(knob->position() - beforeWheel - 0.05f) < 0.002f, "the wheel nudges", knob->position() - beforeWheel);

        // What a host does reaches the control: automation, a preset, the engine's own report
        cutoff.setValueNotifyingHost(cutoff.convertTo0to1(1000.0f));
        const juce::Image low = snapshot(*knob, 2.0f);
        ValueReadout readout(cutoff, studio);
        check(readout.text() == "1.00 kHz", "the readout under it says what the host's list says: " + readout.text().toStdString(), cutoff.plainValue());
        cutoff.setValueNotifyingHost(1.0f);
        check(knob->position() == 1.0f && readout.text() != "1.00 kHz", "a host's write moves the knob and its readout: " + readout.text().toStdString(), knob->position());
        check(differingPixels(low, snapshot(*knob, 2.0f)) > 200, "and the knob draws it", differingPixels(low, snapshot(*knob, 2.0f)));

        // The accent is the section's: orange under Studio, Mix's mint under Cabinet
        std::unique_ptr<ParameterControl> mix = makeControl(*cabinetSkin->control("Mix.subVolume"), cabinet, lookup);
        mix->setBounds(0, 0, 52, 52);
        mix->setPlainAsOneEdit(mix->parameter().description().maximum);
        const int mint = pixelsNear(snapshot(*mix, 2.0f), juce::Colour(0xff3dffb4), 40);
        const int orange = pixelsNear(snapshot(*knob, 2.0f), studio.colour("accent"), 24);
        check(mint > 100 && orange > 100, "a knob's arc is its section's accent: mint in Cabinet's Mix, orange under Studio", mint);

        // What assistive technology is told
        const std::unique_ptr<juce::AccessibilityHandler> handler = knob->createAccessibilityHandler();
        juce::AccessibilityValueInterface *value = handler != nullptr ? handler->getValueInterface() : nullptr;
        check(handler != nullptr && handler->getRole() == juce::AccessibilityRole::slider && value != nullptr && !value->isReadOnly(),
              "a knob is an adjustable slider to assistive technology", value != nullptr);
        if (value != nullptr) {
            value->setValue(2000.0);
            check(std::fabs(cutoff.plainValue() - 2000.0f) < 0.5f && value->getCurrentValueAsString() == "2.00 kHz" && value->getRange().isValid(),
                  "which reads and sets the parameter in its own units: " + value->getCurrentValueAsString().toStdString(), cutoff.plainValue());
        }
    }

    // MARK: a stepped parameter under a knob
    {
        std::unique_ptr<ParameterControl> made = makeControl(*studioSkin->control("Sequencer.arpInterval"), studio, lookup);
        auto *knob = dynamic_cast<Knob *>(made.get());
        S1HostParameter &interval = processor.hostParameter(S1Parameter::arpInterval);
        check(knob != nullptr && interval.isDiscrete(), "the arpeggiator's interval is a knob over whole numbers", interval.getNumSteps());
        if (knob != nullptr) {
            knob->setPlainAsOneEdit(interval.description().minimum);
            knob->keyPressed(juce::KeyPress(juce::KeyPress::upKey));
            check(interval.plainValue() == interval.description().minimum + 1, "a key moves it one whole step", interval.plainValue());
            knob->grab();
            for (int i = 0; i < 100; ++i) { knob->dragBy(1, 0, false); }     // a slow drag: a point at a time
            knob->letGo();
            check(interval.plainValue() > interval.description().minimum + 1 && interval.plainValue() == std::round(interval.plainValue()),
                  "a slow drag still gets there, in whole numbers", interval.plainValue());
        }
    }

    // MARK: switches
    {
        std::unique_ptr<ParameterControl> made = makeControl(*studioSkin->control("Reverb.reverbOn"), studio, lookup);
        auto *toggle = dynamic_cast<Toggle *>(made.get());
        S1HostParameter &reverbOn = processor.hostParameter(S1Parameter::reverbOn);
        check(toggle != nullptr, "Reverb's On is a switch", toggle != nullptr);
        if (toggle != nullptr) {
            toggle->setBounds(0, 0, 28, 16);
            toggle->setPlainAsOneEdit(0);
            const juce::Image off = snapshot(*toggle, 2.0f);
            {
                const Listening listening(reverbOn, ears);
                toggle->toggle();
                check(reverbOn.plainValue() == 1 && ears.begun == 1 && ears.ended == 1, "a click switches it on, as one recorded edit", reverbOn.plainValue());
            }
            check(differingPixels(off, snapshot(*toggle, 2.0f)) > 50, "and it draws lit", differingPixels(off, snapshot(*toggle, 2.0f)));
            check(toggle->keyPressed(juce::KeyPress(juce::KeyPress::spaceKey)) && reverbOn.plainValue() == 0, "space switches it off again", reverbOn.plainValue());
            const std::unique_ptr<juce::AccessibilityHandler> handler = toggle->createAccessibilityHandler();
            toggle->toggle();
            check(handler != nullptr && handler->getRole() == juce::AccessibilityRole::toggleButton && handler->getCurrentState().isChecked(),
                  "a toggle button, checked, to assistive technology", handler != nullptr);
        }
        std::unique_ptr<ParameterControl> twoWay = makeControl(*studioSkin->control("Sequencer.arpIsSequencer"), studio, lookup);
        check(dynamic_cast<TwoWaySwitch *>(twoWay.get()) != nullptr, "Arp / Seq is the two-word switch", twoWay != nullptr);
        if (auto *sides = dynamic_cast<TwoWaySwitch *>(twoWay.get())) {
            sides->setPlainAsOneEdit(0);
            sides->toggle();
            check(processor.hostParameter(S1Parameter::arpIsSequencer).plainValue() == 1, "a click changes sides", sides->plain());
        }
        std::unique_ptr<ParameterControl> bar = makeControl(*studioSkin->control("Sequencer.sequencerNoteOn00"), studio, lookup);
        check(dynamic_cast<Toggle *>(bar.get()) != nullptr, "a step's note-on bar toggles too", bar != nullptr);
    }

    // MARK: the LFO chip, the pickers
    {
        std::unique_ptr<ParameterControl> made = makeControl(*studioSkin->control("LFO & Mod Targets.cutoffLFO"), studio, lookup);
        auto *chip = dynamic_cast<LFOChip *>(made.get());
        check(chip != nullptr && chip->getTitle() == "LFO & Mod Targets Cutoff", "the cutoff's LFO target is a chip, named", chip != nullptr);
        if (chip != nullptr) {
            chip->setBounds(0, 0, 66, 22);
            chip->setPlainAsOneEdit(0);
            chip->pressAt(10); const float one = chip->plain();
            chip->pressAt(50); const float both = chip->plain();
            chip->pressAt(10); const float two = chip->plain();
            check(one == 1 && both == 3 && two == 2, "its left half is LFO 1, its right half LFO 2: 1, then 3, then 2", both);
        }
        std::unique_ptr<ParameterControl> waves = makeControl(*studioSkin->control("LFO & Mod Targets.lfo1Index"), studio, lookup);
        if (auto *picker = dynamic_cast<CellPicker *>(waves.get())) {
            picker->setBounds(0, 0, 112, 26);
            picker->pressAt(112 * 0.6f);
            check(picker->plain() == 2 && picker->selected() == 2, "the wave picker's third cell is the ramp up", picker->plain());
        } else { check(false, "LFO 1's wave is a cell picker", 0); }
        std::unique_ptr<ParameterControl> direction = makeControl(*studioSkin->control("Sequencer.arpDirection"), studio, lookup);
        if (auto *picker = dynamic_cast<CellPicker *>(direction.get())) {
            picker->setBounds(0, 0, 96, 24);
            picker->pressAt(90);
            check(picker->plain() == 2, "the direction's third cell is down", picker->plain());
        } else { check(false, "the arpeggiator's direction is a cell picker", 0); }
        std::unique_ptr<ParameterControl> filter = makeControl(*studioSkin->control("Filter.filterType"), studio, lookup);
        if (auto *picker = dynamic_cast<CellPicker *>(filter.get())) {
            picker->setBounds(0, 0, 100, 18);
            picker->pressAt(50);
            check(picker->plain() == 1, "the filter picker's middle word is band-pass", picker->plain());
            picker->keyPressed(juce::KeyPress(juce::KeyPress::rightKey));
            check(picker->plain() == 2, "and the right key goes on to high-pass", picker->plain());
        } else { check(false, "the filter's type is a cell picker", 0); }
        std::unique_ptr<ParameterControl> morph = makeControl(*studioSkin->control("OSC 1.index1"), studio, lookup);
        check(dynamic_cast<MorphSelector *>(morph.get()) != nullptr && !morph->parameter().isDiscrete(), "an oscillator's waveform is a continuous morph", morph != nullptr);
    }

    // MARK: steppers and the tempo
    {
        std::unique_ptr<ParameterControl> made = makeControl(*studioSkin->control("Sequencer.arpOctave"), studio, lookup);
        auto *stepper = dynamic_cast<Stepper *>(made.get());
        check(stepper != nullptr, "Octaves is a stepper", stepper != nullptr);
        if (stepper != nullptr) {
            stepper->setBounds(0, 0, 96, 24);
            const auto &info = stepper->parameter().description();
            stepper->setPlainAsOneEdit(info.minimum);
            check(stepper->zoneAt({ 5, 12 }) == 1 && stepper->zoneAt({ 90, 12 }) == 2 && stepper->zoneAt({ 48, 12 }) == 0, "minus at the left, plus at the right, the value between", stepper->zoneAt({ 90, 12 }));
            stepper->press(2);
            check(stepper->plain() == info.minimum + 1 && stepper->text() == juce::String(int(info.minimum) + 1), "plus is one more, and it says so", stepper->plain());
            stepper->press(1); stepper->press(1);
            check(stepper->plain() == info.minimum, "minus stops at the bottom", stepper->plain());
        }
        std::unique_ptr<ParameterControl> tempoMade = makeControl(*studioSkin->control("Sequencer.arpRate"), studio, lookup);
        auto *tempo = dynamic_cast<Stepper *>(tempoMade.get());
        check(tempo != nullptr, "the tempo is the tall stepper", tempo != nullptr);
        if (tempo != nullptr) {
            tempo->setBounds(0, 0, 84, 50);
            tempo->setPlainAsOneEdit(120);
            check(tempo->text() == "120 bpm", "it reads in bpm", tempo->plain());
            tempo->grab(); tempo->dragBy(20, 0, false); tempo->letGo();
            check(tempo->plain() > 120, "its display drags like a knob", tempo->plain());
            const float held = tempo->plain();
            tempo->setHostOwned(true);
            tempo->press(2); tempo->grab(); tempo->dragBy(50, 0, false); tempo->letGo();
            check(tempo->plain() == held && !tempo->isEnabled(), "under a host's tempo it shows and does not edit (ADR-077)", tempo->plain());
        }
    }

    // MARK: a sequencer step
    {
        S1HostParameter &pattern = processor.hostParameter(S1Parameter::sequencerPattern03);
        std::unique_ptr<ParameterControl> made = makeControl(*studioSkin->control("Sequencer.sequencerOctBoost03"), studio, lookup);
        auto *box = dynamic_cast<StepOctave *>(made.get());
        check(box != nullptr, "a step's number box", box != nullptr);
        if (box != nullptr) {
            box->setPlainAsOneEdit(0);
            pattern.setValueNotifyingHost(pattern.convertTo0to1(7));
            const juce::String plainText = box->text();
            box->toggle();
            const juce::String boosted = box->text();
            pattern.setValueNotifyingHost(pattern.convertTo0to1(-5));
            check(plainText == "7" && boosted == "19" && box->text() == "-17", "shows its step's pattern, an octave outward while boosted: 7, 19, -17", box->text().getIntValue());
            box->toggle();
            check(box->text() == "-5", "and the number itself is never changed by the boost", box->text().getIntValue());
        }
        std::unique_ptr<ParameterControl> faderMade = makeControl(*studioSkin->control("Sequencer.sequencerPattern03"), studio, lookup);
        auto *fader = dynamic_cast<StepFader *>(faderMade.get());
        check(fader != nullptr, "a step's fader", fader != nullptr);
        if (fader != nullptr) {
            fader->setBounds(0, 0, 40, 120);
            fader->beginEdit(); fader->moveTo(10); fader->endEdit();
            const float top = fader->position();
            fader->beginEdit(); fader->moveTo(110); fader->endEdit();
            check(top == 1.0f && fader->position() == 0.0f, "the cap's travel is 10 points inside each end", top);
            const juce::Rectangle<float> cap = Style::faderCap({ 0, 0, 40, 120 }, 0.5f);
            check(cap.getCentreY() == 60 && cap.getWidth() == 32 && cap.getHeight() == 14, "a 32 x 14 cap, centred at the middle for the middle", cap.getCentreY());
        }
    }

    // MARK: the pads and the envelope plots
    {
        const s1plugin::LayoutDisplay *padEntry = nullptr, *plotEntry = nullptr;
        for (const s1plugin::LayoutDisplay &d : studioSkin->displays) {
            if (d.id == "Pads.pad2") { padEntry = &d; }
            if (d.id == "Amplitude Envelope.plot") { plotEntry = &d; }
        }
        check(padEntry != nullptr && plotEntry != nullptr, "the specification has the second pad and the amplitude plot", padEntry != nullptr);
        if (padEntry == nullptr || plotEntry == nullptr) { return 1; }
        std::unique_ptr<juce::Component> padMade = makeDisplay(*padEntry, studio, lookup);
        auto *pad = dynamic_cast<XYPad *>(padMade.get());
        S1HostParameter &cutoff = processor.hostParameter(S1Parameter::cutoff), &resonance = processor.hostParameter(S1Parameter::resonance);
        if (pad != nullptr) {
            pad->setBounds(0, 0, 180, 200);
            cutoff.setValueNotifyingHost(0.2f); resonance.setValueNotifyingHost(0.3f);
            const float cutoffBefore = cutoff.plainValue(), resonanceBefore = resonance.plainValue();
            HostEars other;
            resonance.addListener(&other);
            {
                const Listening listening(cutoff, ears);
                pad->grab(); pad->moveTo({ 90, 50 });
                check(std::fabs(cutoff.getValue() - 0.5f) < 0.01f && std::fabs(resonance.getValue() - 0.75f) < 0.01f, "the pad's x is the cutoff's position, its y — upward — the resonance's", resonance.getValue());
                pad->letGo();
                check(ears.begun == 1 && ears.ended == 1 && other.begun == 1 && other.ended == 1, "one gesture on each of its two parameters", other.begun);
            }
            resonance.removeListener(&other);
            pad->setSnapsBack(true);
            cutoff.setValueNotifyingHost(cutoff.convertTo0to1(cutoffBefore)); resonance.setValueNotifyingHost(resonance.convertTo0to1(resonanceBefore));
            pad->grab(); pad->moveTo({ 170, 10 }); pad->letGo();
            check(std::fabs(cutoff.plainValue() - cutoffBefore) < 0.5f && std::fabs(resonance.plainValue() - resonanceBefore) < 0.001f, "with Snap on, letting go puts both back", cutoff.plainValue());
        } else { check(false, "pad 2 is an XY pad", 0); }

        std::unique_ptr<juce::Component> plotMade = makeDisplay(*plotEntry, studio, lookup);
        auto *plot = dynamic_cast<EnvelopeView *>(plotMade.get());
        if (plot != nullptr) {
            plot->setBounds(0, 0, 460, 54);
            S1HostParameter &attack = processor.hostParameter(S1Parameter::attackDuration), &sustain = processor.hostParameter(S1Parameter::sustainLevel);
            attack.setValueNotifyingHost(attack.convertTo0to1(0.1f)); sustain.setValueNotifyingHost(sustain.convertTo0to1(0.5f));
            check(plot->areaAt({ 10, 30 }) == EnvelopeView::Area::attack && plot->areaAt({ 250, 30 }) == EnvelopeView::Area::decaySustain
                      && plot->areaAt({ 440, 30 }) == EnvelopeView::Area::release, "left is the attack's, the middle decay and sustain's, right the release's", 3);
            const juce::Image before = snapshot(*plot, 2.0f);
            {
                const Listening listening(attack, ears);
                plot->grab(EnvelopeView::Area::attack); plot->dragBy(50, 0, false); plot->letGo();
                check(std::fabs(attack.plainValue() - 0.15f) < 0.001f && ears.begun == 1 && ears.ended == 1, "a point across is a millisecond of attack, in one gesture", attack.plainValue());
            }
            plot->grab(EnvelopeView::Area::decaySustain); plot->dragBy(0, -100, false); plot->letGo();
            check(std::fabs(sustain.plainValue() - 0.6f) < 0.001f, "ten points up is one per cent of sustain", sustain.plainValue());
            check(differingPixels(before, snapshot(*plot, 2.0f)) > 100, "and the curve follows", differingPixels(before, snapshot(*plot, 2.0f)));
        } else { check(false, "the amplitude plot is an envelope view", 0); }
    }

    // MARK: edges on the pixel grid at 1x and 2x
    {
        // Cabinet's stepper: a cyan border round a near-black well, so a border smeared across two
        // pixel rows — half the cyan in each — is measurable. (Studio's border and well are six
        // levels apart: a check there passes whatever is drawn.)
        std::unique_ptr<ParameterControl> made = makeControl(*cabinetSkin->control("Sequencer.arpOctave"), cabinet, lookup);
        made->setBounds(0, 0, 96, 24);
        const juce::Image once = snapshot(*made, 1.0f), twice = snapshot(*made, 2.0f);
        // On the grid the border's row is all border (blue 212 here; 97 when it straddles two rows)
        const int edge1 = once.getPixelAt(48, 0).getBlue(), inside1 = once.getPixelAt(48, 1).getBlue();
        check(edge1 > 170 && inside1 < 60, "a one-point border is one whole pixel at 1x — nothing smeared across two", edge1);
        const int edge2a = twice.getPixelAt(96, 0).getBlue(), edge2b = twice.getPixelAt(96, 1).getBlue(), inside2 = twice.getPixelAt(96, 2).getBlue();
        check(edge2a > 170 && edge2b > 170 && inside2 < 60, "and two whole pixels at 2x", edge2b);
    }

    // MARK: X3-6 (ADR-088) — the screen bezel, and the starfield a held pad throws
    {
        const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
        const s1plugin::LayoutSkin *cabinet = spec.skin("cabinet");
        const s1plugin::LayoutSkin *studio = spec.skin("studio");
        check(cabinet != nullptr && studio != nullptr, "both skins are there", 0);
        const s1ui::Style cabinetStyle(*cabinet), studioStyle(*studio);
        check(cabinetStyle.hasCRTFrame() && !studioStyle.hasCRTFrame(),
              "Cabinet frames a pad as a screen and Studio does not, as on the Mac", 0);

        const juce::Colour cyan = juce::Colour(0xff2ee8ff);
        auto paint = [](const s1ui::Style &style, bool frame, float age) {
            // Transparent, and left that way: what is drawn is what is counted.
            juce::Image image(juce::Image::ARGB, 120, 90, true);
            juce::Graphics g(image);
            const juce::Rectangle<float> bounds(0, 0, 120, 90);
            if (age > 0) { style.drawPadParticles(g, bounds, age, 1); }
            if (frame) { style.drawCRTFrame(g, bounds.reduced(10.0f), 4.0f); }
            return image;
        };

        // The bezel: its colour on the border, and NOT inside it. The first cut drew the glow
        // over the pad it frames, which is what this second half catches.
        const juce::Image framed = paint(cabinetStyle, true, 0);
        int onBorder = 0, inside = 0;
        for (int x = 12; x < 108; ++x) {
            if (framed.getPixelAt(x, 10).getBrightness() > 0.2f) { ++onBorder; }
        }
        for (int y = 30; y < 60; ++y) {
            for (int x = 40; x < 80; ++x) {
                const juce::Colour at = framed.getPixelAt(x, y);
                if (at.getBlue() > 40 || at.getGreen() > 40) { ++inside; }
            }
        }
        check(onBorder > 80, "the bezel draws a line along the top of the frame", onBorder);
        check(inside == 0, "…and leaves what it frames alone: no glow spilled inside it", inside);
        check(pixelsNear(framed, cyan, 90) > 40, "…in the skin's own frame accent", pixelsNear(framed, cyan, 90));
        check(inkedPixels(paint(studioStyle, true, 0)) == 0, "Studio's pad gets no bezel at all", 0);

        // The starfield: nothing before the pad is held, something while it is, and it spreads.
        check(inkedPixels(paint(cabinetStyle, false, 0.0f)) == 0, "a pad that is not held throws no particles", 0);
        const int early = inkedPixels(paint(cabinetStyle, false, 0.08f));
        const int later = inkedPixels(paint(cabinetStyle, false, 0.60f));
        check(early > 0, "a held pad throws them", early);
        check(later > early, "…and more of them as it is held", later);
        // They come from the CENTRE, which is where the Mac's emitter sits — not the touch. What
        // says so is that they travel OUTWARD: the mean distance from the middle grows with the
        // hold. (Counting a middle box does not: by 0.3 s they have crossed a 120-point pad.)
        auto meanRadius = [&paint, &cabinetStyle](float age) {
            const juce::Image thrown = paint(cabinetStyle, false, age);
            double total = 0;
            int lit = 0;
            for (int y = 0; y < 90; ++y) {
                for (int x = 0; x < 120; ++x) {
                    if (thrown.getPixelAt(x, y).getAlpha() == 0) { continue; }
                    total += std::sqrt(double((x - 60) * (x - 60) + (y - 45) * (y - 45)));
                    ++lit;
                }
            }
            return lit > 0 ? total / double(lit) : 0.0;
        };
        const double young = meanRadius(0.05f), old = meanRadius(0.35f);
        check(young > 0 && young < 20.0, "a fresh burst is close to the middle of the pad", young);
        check(old > young * 1.5, "…and it travels outward from there", old);

        // The owner, 2026-09-21: "barely visible … a little bolder with smaller particles", and
        // "let the focus follow the cursor on the pad". Measured in the pixels, all three.
        using Trail = std::vector<s1ui::Style::PadTouch>;
        auto thrown = [&cabinetStyle](int width, int height, float age, const Trail &trail) {
            juce::Image image(juce::Image::ARGB, width, height, true);
            juce::Graphics g(image);
            cabinetStyle.drawPadParticles(g, juce::Rectangle<float>(0, 0, float(width), float(height)), age, 1, trail);
            return image;
        };
        {
            const juce::Image field = thrown(400, 300, 1.0f, {});
            int brightest = 0;
            std::vector<int> runs;
            for (int y = 0; y < field.getHeight(); ++y) {
                int run = 0;
                for (int x = 0; x <= field.getWidth(); ++x) {
                    const int alpha = x < field.getWidth() ? field.getPixelAt(x, y).getAlpha() : 0;
                    brightest = std::max(brightest, alpha);
                    if (alpha > 40) { ++run; } else if (run > 0) { runs.push_back(run); run = 0; }
                }
            }
            std::sort(runs.begin(), runs.end());
            const int median = runs.empty() ? 0 : runs[runs.size() / 2];
            check(brightest > 200, "the stars are BOLD: the brightest is nearly opaque (it was under a quarter)", brightest);
            check(median >= 1 && median <= 3, "…and SMALL: a star is one to three pixels across (the Mac's soft disc was ten and more)", median);
        }
        auto centroid = [](const juce::Image &image) {
            double sx = 0, sy = 0, weight = 0;
            for (int y = 0; y < image.getHeight(); ++y) {
                for (int x = 0; x < image.getWidth(); ++x) {
                    const double a = image.getPixelAt(x, y).getAlpha();
                    sx += a * x; sy += a * y; weight += a;
                }
            }
            return weight > 0 ? juce::Point<double>(sx / weight, sy / weight) : juce::Point<double>(-1000, -1000);
        };
        {
            const juce::Point<float> corner(30, 25), far(95, 70);
            const juce::Point<double> fresh = centroid(thrown(120, 90, 0.05f, Trail{ { 0.0f, corner } }));
            check(fresh.getDistanceFrom(corner.toDouble()) < 8.0, "the stars leave from the TOUCH, not the middle of the pad", fresh.getDistanceFrom(corner.toDouble()));
            // …and a star keeps the place it left from: move the touch, and the ones already
            // flying do not jump to it — the field streams behind the cursor.
            const juce::Image moved = thrown(120, 90, 0.30f, Trail{ { 0.0f, corner }, { 0.27f, far } });
            const juce::Image jumped = thrown(120, 90, 0.30f, Trail{ { 0.0f, far } });
            const double trailing = centroid(moved).getDistanceFrom(corner.toDouble());
            const double teleported = centroid(jumped).getDistanceFrom(corner.toDouble());
            check(trailing < teleported - 10.0, "a star already flying stays on its way when the touch moves", trailing);
            // (a star a thirtieth of a second old is still faint, so any ink counts — and the
            // same box with the touch never moved is the control: nothing has got that far)
            const juce::Image stayed = thrown(120, 90, 0.30f, Trail{ { 0.0f, corner } });
            int nearTouch = 0, withoutMoving = 0;
            for (int y = 62; y < 78; ++y) {
                for (int x = 87; x < 103; ++x) {
                    if (moved.getPixelAt(x, y).getAlpha() > 0) { ++nearTouch; }
                    if (stayed.getPixelAt(x, y).getAlpha() > 0) { ++withoutMoving; }
                }
            }
            check(nearTouch > 0 && withoutMoving == 0, "…while new ones leave from where the touch is now", nearTouch);
        }
        // The target is half TouchPointStyleKit's size: its solid block is 12 pixels across, not 24.
        {
            juce::Image image(juce::Image::ARGB, 200, 200, true);
            {
                // The Graphics must be GONE before the pixels are read: on Windows the drawing is
                // not in the image until it is (the owner's run at f0075c3 measured 0 here).
                juce::Graphics g(image);
                studioStyle.drawPad(g, juce::Rectangle<float>(0, 0, 200, 200), 0.5f, 0.5f);
            }
            int solid = 0;
            for (int x = 0; x < 200; ++x) {
                const juce::Colour at = image.getPixelAt(x, 100);
                if (at.getRed() > 220 && at.getGreen() > 125 && at.getGreen() < 150 && at.getBlue() < 20) { ++solid; }
            }
            check(solid >= 10 && solid <= 13, "the pad's target is half the size it was", solid);
        }
    }

    // MARK: X3-9 (ADR-091) — the cabinet's power: the schedule, and the one lever that greys a zone
    {
        const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
        const s1plugin::LayoutSkin *cabinet = spec.skin("cabinet");
        check(cabinet != nullptr, "the cabinet skin is there", 0);
        s1ui::Style lit(*cabinet), dead(*cabinet);
        dead.setDim(1.0f);
        const juce::Colour accent = lit.accentFor("Filter"), greyed = dead.accentFor("Filter");
        check(greyed.getFloatRed() == greyed.getFloatGreen() && greyed.getFloatGreen() == greyed.getFloatBlue(),
              "a dead zone's accent has no colour left in it", double(greyed.getFloatRed()));
        check(greyed.getBrightness() < accent.getBrightness(),
              "…and it is darker than the lit one, as the Mac's greyed() is", double(greyed.getBrightness()));
        check(dead.glow() == 0.0f && lit.glow() >= 0.0f, "a dead zone has no glow", double(dead.glow()));
        s1ui::Style half(*cabinet);
        half.setDim(0.5f);
        const juce::Colour between = half.accentFor("Filter");
        check(between.getSaturation() < accent.getSaturation() && between.getSaturation() > greyed.getSaturation(),
              "and half way there is half way", double(between.getSaturation()));

        // The schedule: the Mac's eight seconds, the first zone a second in, each blinking on the way.
        std::vector<std::string> zones;
        for (const s1plugin::LayoutSection &section : cabinet->sections) { zones.push_back(section.key); }
        zones.insert(zones.end(), { "display", "buttons", "screen", "bar" });
        check(zones.size() == 19, "fifteen sections and the four pieces of the chrome", double(zones.size()));
        const s1plugin::PowerCycle off(zones, false, 12345u);
        check(off.plans().size() == 19, "every zone is planned", double(off.plans().size()));
        double first = 99, last = 0;
        int blinks = 0, outsideTheWindow = 0;
        for (const s1plugin::PowerZonePlan &plan : off.plans()) {
            first = std::min(first, plan.settlesAt);
            last = std::max(last, plan.settlesAt);
            blinks += int(plan.blinkAt.size());
            if (plan.blinkAt.empty()) { continue; }
            if (plan.blinkAt.front() <= plan.settlesAt - 1.0 || plan.blinkAt.back() >= plan.settlesAt) { ++outsideTheWindow; }
        }
        check(outsideTheWindow == 0, "every zone's blinks fall in the second before it settles", outsideTheWindow);
        check(std::fabs(first - 1.0) < 0.001 && std::fabs(last - 8.0) < 0.001,
              "the first zone settles a second in and the last at eight", last);
        check(blinks >= 19 * 2 && blinks <= 19 * 4, "each blinks two to four times on the way", double(blinks));

        // Everything is lit before the press, and nothing after the cycle has run.
        int litAtStart = 0, litAtEnd = 0;
        for (const std::string &zone : zones) {
            if (off.isLit(zone, 0.0)) { ++litAtStart; }
            if (off.isLit(zone, 8.0)) { ++litAtEnd; }
        }
        check(litAtStart == 19, "at the press every zone is still lit", double(litAtStart));
        check(litAtEnd == 0, "…and eight seconds later the power is out everywhere", double(litAtEnd));
        check(off.settledBy(4.5) > 0 && off.settledBy(4.5) < 19, "half way through, some have gone and some have not", double(off.settledBy(4.5)));

        // The other button: the same cycle the other way.
        const s1plugin::PowerCycle on(zones, true, 999u);
        int backOn = 0;
        for (const std::string &zone : zones) { if (on.isLit(zone, 8.0)) { ++backOn; } }
        check(backOn == 19, "the other button brings every one of them back", double(backOn));
        check(!on.isLit(on.plans().front().zone, 0.0), "…starting from the dark", 0);

        // The same seed is the same cycle on every machine (std::shuffle is not).
        const s1plugin::PowerCycle again(zones, false, 12345u);
        bool identical = true;
        for (size_t i = 0; i < off.plans().size(); ++i) {
            if (off.plans()[i].zone != again.plans()[i].zone || off.plans()[i].blinkAt != again.plans()[i].blinkAt) { identical = false; }
        }
        check(identical, "a seed replays the cycle exactly, on any machine", 1);
    }

    std::printf("%s\n", failures == 0 ? "PASSED" : "FAILED");
    return failures == 0 ? 0 : 1;
}
