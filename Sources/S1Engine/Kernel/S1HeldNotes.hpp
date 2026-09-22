//
//  S1HeldNotes.hpp
//  Arcade Ruins
//
//  PORT (X1-2, ADR-066): the keys currently held, most recent first — what upstream kept in an
//  `NSMutableArray<NSValue *>` of `NoteNumber` mirrored into an `AEArray` for the render thread.
//  Plain C++ so the portable engine (Sources/S1Engine) can carry it.
//
//  Threads, as upstream had them: ONE writer at a time — the main thread in the standalone
//  (`startNote`/`stopNote` from the interface), the render thread in the plugin (`S1HostMIDI`).
//  Readers on either thread take a `snapshot()`. Publication is a seqlock, the pattern ADR-028's
//  waveform ring uses: no lock, no allocation, a reader that collides with a write copies again.
//

#ifndef S1_HELD_NOTES_HPP
#define S1_HELD_NOTES_HPP

#include <atomic>
#include <cstring>
#include "S1EngineTypes.h"   // NoteNumber, S1_NUM_MIDI_NOTES

/// A consistent copy of the held keys. `notes[0]` is the most recently pressed.
struct S1HeldNoteList {
    int count = 0;
    NoteNumber notes[S1_NUM_MIDI_NOTES] = {};

    const NoteNumber *begin() const { return notes; }
    const NoteNumber *end() const { return notes + count; }
};

class S1HeldNotes {
public:
    /// A key went down: forget any earlier press of the same key, then put it first.
    void noteOn(int noteNumber, int transpose, int velocity) {
        remove(noteNumber);
        if (working.count >= S1_NUM_MIDI_NOTES) { return; }   // 128 distinct keys is the ceiling anyway
        std::memmove(working.notes + 1, working.notes, sizeof(NoteNumber) * size_t(working.count));
        working.notes[0] = NoteNumber{noteNumber, transpose, velocity, 0.f};
        ++working.count;
        publish();
    }

    /// A key came up. Unknown keys are ignored, as `removeObjectAtIndex:` of a missing index was avoided.
    void noteOff(int noteNumber) {
        remove(noteNumber);
        publish();   // unconditionally, as upstream republished the array whether or not it changed
    }

    void clear() {
        working.count = 0;
        publish();
    }

    /// Any thread. The count as last published.
    int count() const { return publishedCount.load(std::memory_order_acquire); }

    /// Any thread. A copy that is consistent with itself.
    S1HeldNoteList snapshot() const {
        S1HeldNoteList copy;
        for (;;) {
            const uint32_t before = seq.load(std::memory_order_acquire);
            if (before & 1u) { continue; }                     // a write is in progress
            copy.count = published.count;
            std::memcpy(copy.notes, published.notes, sizeof(NoteNumber) * size_t(copy.count < 0 ? 0 : copy.count));
            std::atomic_thread_fence(std::memory_order_acquire);
            if (seq.load(std::memory_order_relaxed) == before) { break; }
        }
        if (copy.count < 0 || copy.count > S1_NUM_MIDI_NOTES) { copy.count = 0; }   // torn beyond repair: empty, never garbage
        return copy;
    }

private:
    bool remove(int noteNumber) {
        for (int i = 0; i < working.count; ++i) {
            if (working.notes[i].noteNumber == noteNumber) {
                std::memmove(working.notes + i, working.notes + i + 1, sizeof(NoteNumber) * size_t(working.count - i - 1));
                --working.count;
                return true;
            }
        }
        return false;
    }

    void publish() {
        seq.fetch_add(1, std::memory_order_release);            // odd: write in progress
        published.count = working.count;
        std::memcpy(published.notes, working.notes, sizeof(NoteNumber) * size_t(working.count));
        seq.fetch_add(1, std::memory_order_release);            // even: consistent again
        publishedCount.store(working.count, std::memory_order_release);
    }

    S1HeldNoteList working;                     // the writer's own; never read by anyone else
    S1HeldNoteList published;                   // what readers copy, under `seq`
    std::atomic<uint32_t> seq{0};
    std::atomic<int> publishedCount{0};
};

#endif
