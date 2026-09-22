//
//  S1Keyboard.cpp
//  Arcade Ruins
//
//  X3-8 (ADR-090). See the header; every constant is `KeyboardView`'s.
//
#include "S1Keyboard.h"

namespace s1ui {
namespace {

/// `KeyboardView`'s light palette, which is what the Mac ships (`darkMode = NO`).
const juce::Colour kWhiteKeyOff = juce::Colours::white;
const juce::Colour kBlackKeyOff = juce::Colour::fromFloatRGBA(0.0941f, 0.0941f, 0.0941f, 1.0f);

/// `KeyboardShading.whiteKey`: black, 27% at the back and nothing at the front.
void shadeWhiteKey(juce::Graphics &g, const juce::Rectangle<float> &key) {
    juce::ColourGradient shade(juce::Colours::black.withAlpha(0.27f), key.getX(), key.getY(),
                               juce::Colours::black.withAlpha(0.0f), key.getX(), key.getBottom(), false);
    shade.addColour(0.14, juce::Colours::black.withAlpha(0.105f));
    shade.addColour(0.60, juce::Colours::black.withAlpha(0.015f));
    g.setGradientFill(shade);
    g.fillRect(key);
}

/// `KeyboardShading.blackKey`: white, a lighter band only in the last fifth.
void shadeBlackKey(juce::Graphics &g, const juce::Rectangle<float> &key) {
    juce::ColourGradient shade(juce::Colours::white.withAlpha(0.0f), key.getX(), key.getY(),
                               juce::Colours::white.withAlpha(0.1f), key.getX(), key.getBottom(), false);
    shade.addColour(0.80, juce::Colours::white.withAlpha(0.0f));
    shade.addColour(0.86, juce::Colours::white.withAlpha(0.1f));
    shade.addColour(0.90, juce::Colours::white.withAlpha(0.2f));
    g.setGradientFill(shade);
    g.fillRect(key);
}

juce::Rectangle<float> rectangleOf(const s1plugin::KeyBox &key) { return { key.x, key.y, key.width, key.height }; }

} // namespace

Keyboard::Keyboard(const Style &s, int octaves, int firstOctave)
    : style(s), keys(octaves, firstOctave, 100.0f, 40.0f) {
    setTitle("Keyboard");
    setAccessible(true);
    setDescription("Click a key to play it");
    setWantsKeyboardFocus(false);
}

Keyboard::~Keyboard() = default;

void Keyboard::resized() { keys.setSize(float(getWidth()), float(getHeight())); }

void Keyboard::setSoundingShift(int semitones) {
    if (semitones == shift) { return; }
    shift = semitones;
    repaint();
}

std::set<int> Keyboard::litKeys() const {
    // `hostHeld` are the notes the ROUTER is holding — already shifted. The key that sounds one is
    // the one below it by the shift.
    std::set<int> lit;
    for (const int sounding : hostHeld) { lit.insert(sounding - shift); }
    if (pressed >= 0) { lit.insert(pressed); }
    return lit;
}

void Keyboard::setHostHeldKeys(const std::set<int> &notes) {
    if (notes == hostHeld) { return; }
    hostHeld = notes;
    repaint();
}

void Keyboard::paint(juce::Graphics &g) {
    const std::set<int> lit = litKeys();
    const juce::Colour down = style.colour("accent");
    g.fillAll(juce::Colours::black);

    // The white keys first, then the black ones over them — upstream's order.
    for (int note = keys.firstNote(); note <= keys.lastNote(); ++note) {
        if (!s1plugin::Keybed::isWhiteKey(note)) { continue; }
        const s1plugin::KeyBox key = keys.boxForNote(note);
        if (!key.exists()) { continue; }
        const juce::Rectangle<float> box = rectangleOf(key).withTrimmedRight(1.0f);
        juce::Path path;
        path.addRoundedRectangle(box.getX(), box.getY(), box.getWidth(), box.getHeight(), 5.0f, 5.0f,
                                 false, false, true, true);   // the bottom corners only
        g.setColour(lit.count(note) > 0 ? down : kWhiteKeyOff);
        g.fillPath(path);
        {
            juce::Graphics::ScopedSaveState clip(g);
            g.reduceClipRegion(path);
            shadeWhiteKey(g, box);
        }
        // `labelMode` 1: only the Cs are named, six points above the bottom.
        if (note % 12 == 0) {
            g.setColour(juce::Colours::black.withAlpha(0.55f));
            g.setFont(style.font(11.0f));
            // What the key SOUNDS, in upstream's octave numbering (`baseMIDINote` 24 is C0).
            g.drawText("C" + juce::String((note + shift) / 12 - 2), box.withTrimmedBottom(6.0f), juce::Justification::centredBottom, false);
        }
    }
    for (int note = keys.firstNote(); note <= keys.lastNote(); ++note) {
        if (s1plugin::Keybed::isWhiteKey(note)) { continue; }
        const s1plugin::KeyBox key = keys.boxForNote(note);
        if (!key.exists()) { continue; }
        const juce::Rectangle<float> box = rectangleOf(key);
        juce::Path path;
        path.addRoundedRectangle(box.getX(), box.getY(), box.getWidth(), box.getHeight(), 3.0f);
        // One shadow for the whole key, as upstream's transparency layer gives it.
        juce::DropShadow(juce::Colours::black.withAlpha(0.65f), 7, { 2, 5 }).drawForPath(g, path);
        g.setColour(lit.count(note) > 0 ? down : kBlackKeyOff);
        g.fillPath(path);
        {
            juce::Graphics::ScopedSaveState clip(g);
            g.reduceClipRegion(path);
            shadeBlackKey(g, box);
        }
    }
}

void Keyboard::play(int note, int velocity) {
    if (note == pressed) { return; }
    stop();
    pressed = note;
    if (onNoteOn) { onNoteOn(note, velocity); }
    repaint();
}

void Keyboard::stop() {
    if (pressed < 0) { return; }
    const int was = pressed;
    pressed = -1;
    if (onNoteOff) { onNoteOff(was); }
    repaint();
}

int Keyboard::pressAt(juce::Point<float> where) {
    const int note = keys.noteAt(where.x, where.y);
    if (note < 0) { return -1; }
    const s1plugin::KeyBox key = keys.boxForNote(note);
    play(note, keys.velocityAt(where.y - key.y, key));
    return note;
}

void Keyboard::releaseAll() { stop(); }

void Keyboard::mouseDown(const juce::MouseEvent &event) { pressAt(event.position); }

void Keyboard::mouseDrag(const juce::MouseEvent &event) {
    // Sliding along the keys plays them in turn, as a finger does on the Mac.
    if (keys.noteAt(event.position.x, event.position.y) < 0) { stop(); return; }
    pressAt(event.position);
}

void Keyboard::mouseUp(const juce::MouseEvent &) { stop(); }
void Keyboard::mouseExit(const juce::MouseEvent &) { stop(); }

} // namespace s1ui
