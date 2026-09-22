//
//  S1Keyboard.h
//  Arcade Ruins
//
//  X3-8 (ADR-090): the drawer's keys — `KeyboardView`'s drawing on `juce::Graphics`.
//
//  A VIEW (ADR-086's pattern): where the keys are and which one is under a point belong to
//  `s1plugin::Keybed`, which has no JUCE in it; this paints them and turns a click into a note.
//  It sounds nothing itself — `onNoteOn` / `onNoteOff` hand the note to the processor, which
//  plays it through the router exactly as it plays the host's own MIDI (ADR-031).
//
//  The colours are upstream's light keyboard (`darkMode = NO` in the storyboard, which is what
//  the Mac ships), with the skin's accent for a key that is down — the Mac lights its own in
//  orange. Keys the HOST is holding light too, as `KeyboardView.hostOnKeys` does.
//
#pragma once

#include <functional>
#include <set>

#include <juce_gui_basics/juce_gui_basics.h>

#include "../S1Keybed.hpp"
#include "S1KitStyle.h"

namespace s1ui {

class Keyboard final : public juce::Component {
public:
    Keyboard(const Style &, int octaves, int firstOctave);
    ~Keyboard() override;

    std::function<void(int note, int velocity)> onNoteOn;
    std::function<void(int note)> onNoteOff;

    void paint(juce::Graphics &) override;
    void resized() override;
    void mouseDown(const juce::MouseEvent &) override;
    void mouseDrag(const juce::MouseEvent &) override;
    void mouseUp(const juce::MouseEvent &) override;
    void mouseExit(const juce::MouseEvent &) override;

    // MARK: driving it without a mouse
    /// Presses the key that is drawn at this point, as a click would. -1 if there is none.
    int pressAt(juce::Point<float> where);
    void releaseAll();
    /// The key the mouse is holding, or -1.
    int keyDown() const { return pressed; }
    /// Which notes are drawn lit: what this keyboard holds, and what the host does.
    std::set<int> litKeys() const;
    void setHostHeldKeys(const std::set<int> &notes);

    const s1plugin::Keybed &keybed() const { return keys; }
    /// The octave control does NOT move the keys: they are the instrument's, fixed. It moves what
    /// they SOUND — the router adds the same shift to every note that reaches it, the drawer's and
    /// the host's alike (`Manager.midiOctaveShift`), so a key sends the note it draws and the
    /// shift is applied once, there. This is only what the labels say and which key a sounding
    /// note lights. In semitones.
    void setSoundingShift(int semitones);
    int soundingShift() const { return shift; }

private:
    void play(int note, int velocity);
    void stop();

    const Style &style;
    s1plugin::Keybed keys;
    int shift = 0;
    std::set<int> hostHeld;
    int pressed = -1;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(Keyboard)
};

} // namespace s1ui
