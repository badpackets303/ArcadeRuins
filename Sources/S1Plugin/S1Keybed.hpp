//
//  S1Keybed.hpp
//  Arcade Ruins
//
//  X3-8 (ADR-090): where the drawer's keys are, and which one is under a point.
//
//  **A port of `KeyboardView+Draw12ET` and `KeyboardView+Touches`**, which is the only on-screen
//  keyboard either product has ever had (the Mac's classic layout; the desktop layout leaves it
//  out — the owner, 2026-09-12, ADR-045). Its proportions are upstream's, not a piano's: an octave
//  is `width/octaves − width/(octaves² × 7)` wide, a black key is **55%** of the length
//  (`topKeyHeightRatio`) and about a third of a white key's width, and the black band is divided
//  into **28 equal slots** whose table says which note each sounds — a touch model, kept so the
//  drawer is the same instrument the Mac app draws.
//
//  **No JUCE in here** (ADR-086's pattern): the geometry is arithmetic, so it is tested with no
//  window and no mouse, and `s1ui::Keyboard` only draws what this says and turns a click into a
//  note. Nothing here sounds anything — the note goes to the processor, which plays it through the
//  router exactly as the host's own MIDI (ADR-031).
//
#ifndef S1_KEYBED_HPP
#define S1_KEYBED_HPP

namespace s1plugin {

/// One key, in the keyboard's own points. The origin is its top left.
struct KeyBox {
    float x = 0, y = 0, width = 0, height = 0;
    bool isWhite = true;
    int note = -1;
    bool exists() const { return width > 0 && note >= 0; }
};

class Keybed {
public:
    // Upstream's constants, `KeyboardView.swift`.
    static constexpr float kTopKeyHeightRatio = 0.55f;   ///< a black key is 55% of the length
    static constexpr float kXOffset = 1.0f;
    static constexpr float kTopKeyWidthIncrease = 4.0f;  ///< each black key is drawn this much wider
    static constexpr int kBaseMIDINote = 24;             ///< C0, as upstream counts octaves
    static constexpr int kSlotsPerOctave = 28;           ///< the black band's columns

    /// `firstOctave` is upstream's: 2 puts the lowest key at C3 (note 48).
    Keybed(int octaves, int firstOctave, float width, float height);

    int octaves() const { return howManyOctaves; }
    int firstOctave() const { return lowestOctave; }
    int firstNote() const { return lowestOctave * 12 + kBaseMIDINote; }
    int lastNote() const { return firstNote() + howManyOctaves * 12; }
    /// Every key, black and white, including the C that closes the keyboard.
    int keyCount() const { return howManyOctaves * 12 + 1; }
    int whiteKeyCount() const { return howManyOctaves * 7 + 1; }

    void setSize(float width, float height);
    void setOctaves(int octaves);
    void setFirstOctave(int octave);
    float width() const { return acrossPoints; }
    float height() const { return downPoints; }
    float octaveWidth() const;
    float whiteKeyWidth() const { return octaveWidth() / 7.0f; }

    /// The `index`th key from the bottom, in note order. Nothing outside the keyboard.
    KeyBox box(int index) const;
    /// The box for a MIDI note, or nothing when the keyboard does not reach it.
    KeyBox boxForNote(int note) const;
    /// Which note is drawn at this point — upstream's `noteFromTouchLocation12ET`: above
    /// `height × 0.55` the black band's 28 slots answer, below it the seven white keys do.
    /// -1: no key there.
    int noteAt(float x, float y) const;
    /// How hard a key pressed `y` points down it is played. Upstream plays every on-screen key at
    /// 127 (`pressAdded`'s default); a mouse has a position, so this follows how far down the key
    /// the click landed — 64 at the very top, 127 at the bottom.
    int velocityAt(float y, const KeyBox &key) const;

    static bool isWhiteKey(int note);

private:
    int howManyOctaves, lowestOctave;
    float acrossPoints, downPoints;
};

} // namespace s1plugin

#endif
