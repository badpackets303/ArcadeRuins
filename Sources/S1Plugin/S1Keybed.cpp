//
//  S1Keybed.cpp
//  Arcade Ruins
//
//  X3-8 (ADR-090). See the header. Every line names the Swift it mirrors.
//
#include "S1Keybed.hpp"

namespace s1plugin {
namespace {

/// `KeyboardView.whiteKeyNotes`: the semitone each of the seven white keys sounds.
constexpr int kWhiteKeyNotes[7] = { 0, 2, 4, 5, 7, 9, 11 };
/// `KeyboardView.topKeyNotes`: the 28 slots of the black band, and what each sounds.
constexpr int kTopKeyNotes[Keybed::kSlotsPerOctave] = {
    0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 11
};
constexpr bool kWhite[12] = { true, false, true, false, true, true, false, true, false, true, false, true };

int floorDivide(int value, int by) { return value >= 0 ? value / by : -(((-value) + by - 1) / by); }
int positiveModulo(int value, int by) { return value - floorDivide(value, by) * by; }

/// Which of the seven white keys sounds this semitone, or -1.
int whiteIndexOf(int semitone) {
    for (int i = 0; i < 7; ++i) { if (kWhiteKeyNotes[i] == semitone) { return i; } }
    return -1;
}

/// The first of the black band's slots that sounds this semitone.
int firstSlotOf(int semitone) {
    for (int i = 0; i < Keybed::kSlotsPerOctave; ++i) { if (kTopKeyNotes[i] == semitone) { return i; } }
    return -1;
}

int slotsFor(int semitone) {
    int count = 0;
    for (const int slot : kTopKeyNotes) { if (slot == semitone) { ++count; } }
    return count;
}

} // namespace

bool Keybed::isWhiteKey(int note) { return kWhite[positiveModulo(note, 12)]; }

Keybed::Keybed(int octaves, int firstOctave, float width, float height)
    : howManyOctaves(octaves < 1 ? 1 : octaves), lowestOctave(firstOctave), acrossPoints(width), downPoints(height) {}

void Keybed::setSize(float width, float height) {
    acrossPoints = width;
    downPoints = height;
}

void Keybed::setOctaves(int octaves) { howManyOctaves = octaves < 1 ? 1 : octaves; }
void Keybed::setFirstOctave(int octave) { lowestOctave = octave; }

float Keybed::octaveWidth() const {
    // `updateOneOctaveSize`: width/count − width/(count² × 7). The keyboard is a little narrower
    // than the view, which is what leaves room for the C that closes it.
    const float count = float(howManyOctaves);
    return acrossPoints / count - acrossPoints / (count * count * 7.0f);
}

KeyBox Keybed::boxForNote(int note) const {
    if (note < firstNote() || note > lastNote() || downPoints <= 0) { return {}; }
    const int fromFirst = note - firstNote();
    const int octave = floorDivide(fromFirst, 12), semitone = positiveModulo(fromFirst, 12);
    const float oneOctave = octaveWidth();
    KeyBox key;
    key.note = note;
    key.isWhite = isWhiteKey(note);
    if (key.isWhite) {
        const int index = whiteIndexOf(semitone);
        key.width = oneOctave / 7.0f;
        key.height = downPoints - 2.0f;                       // `whiteKeySize`
        key.x = float(index) * key.width + kXOffset + oneOctave * float(octave);   // `whiteKeyX`
        key.y = 1.0f;
        // The C that closes the keyboard is drawn as a half-width sliver, as `draw12ET` does.
        if (note == lastNote()) { key.width = (acrossPoints - (float(howManyOctaves * 7 - 1) * (oneOctave / 7.0f)) - 1.0f) * 0.5f; }
    } else {
        const int slot = firstSlotOf(semitone);
        const float slotWidth = oneOctave / float(kSlotsPerOctave);
        key.width = slotWidth * float(slotsFor(semitone)) + kTopKeyWidthIncrease;   // one key, its slots joined
        key.height = downPoints * kTopKeyHeightRatio;                               // `topKeySize`
        key.x = float(slot) * slotWidth - kTopKeyWidthIncrease * 0.5f + kXOffset + oneOctave * float(octave);
        key.y = 1.0f;
    }
    return key;
}

KeyBox Keybed::box(int index) const {
    if (index < 0 || index >= keyCount()) { return {}; }
    return boxForNote(firstNote() + index);
}

int Keybed::noteAt(float x, float y) const {
    // `noteFromTouchLocation12ET`, with its `bounds.contains` guard.
    if (x < 0 || y < 0 || x > acrossPoints || y > downPoints) { return -1; }
    const float atX = x - kXOffset;
    if (atX < 0) { return -1; }
    const float oneOctave = octaveWidth();
    if (oneOctave <= 0) { return -1; }
    int octaveNumber = int(atX / oneOctave);
    float scaledX = atX - float(octaveNumber) * oneOctave;
    // PORT FIX: upstream lets `octaveNumber` run past the last octave into the closing C's
    // sliver, where its own arithmetic then sounds a D (the slot table is indexed from a
    // scaledX that belongs to no octave). The C that closes the keyboard is that key.
    if (octaveNumber >= howManyOctaves) { return lastNote(); }
    int semitone = 0;
    if (y > downPoints * kTopKeyHeightRatio) {
        const float whiteWidth = oneOctave / 7.0f;
        int index = int(scaledX / whiteWidth);
        if (index < 0) { index = 0; }
        if (index > 6) { index = 6; }
        semitone = kWhiteKeyNotes[index];
    } else {
        const float slotWidth = oneOctave / float(kSlotsPerOctave);
        int slot = int(scaledX / slotWidth);
        if (slot < 0) { slot = 0; }
        if (slot > kSlotsPerOctave - 1) { slot = kSlotsPerOctave - 1; }
        semitone = kTopKeyNotes[slot];
    }
    return (lowestOctave + octaveNumber) * 12 + semitone + kBaseMIDINote;
}

int Keybed::velocityAt(float y, const KeyBox &key) const {
    if (key.height <= 0) { return 127; }
    const float down = y / key.height;
    const float clamped = down < 0 ? 0 : (down > 1 ? 1 : down);
    const int velocity = int(64.0f + clamped * 63.0f + 0.5f);
    return velocity < 1 ? 1 : (velocity > 127 ? 127 : velocity);
}

} // namespace s1plugin
