// S1HeldNotes: the order upstream's NSMutableArray kept, and snapshots that are whole.
#include <cstdio>
#include <thread>
#include <atomic>
#include "S1HeldNotes.hpp"

namespace {
int failures = 0;
void check(bool ok, const char *what, long measured) {
    std::printf("%s  %s (measured %ld)\n", ok ? "ok  " : "FAIL", what, measured);
    if (!ok) { ++failures; }
}
}

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);   // see every line before a crash
    S1HeldNotes held;
    check(held.count() == 0, "starts empty", held.count());

    held.noteOn(60, 0, 100);
    held.noteOn(64, 0, 90);
    held.noteOn(67, 0, 80);
    S1HeldNoteList snap = held.snapshot();
    check(snap.count == 3, "three keys down", snap.count);
    check(snap.notes[0].noteNumber == 67 && snap.notes[2].noteNumber == 60, "most recent first, as upstream inserted at index 0", snap.notes[0].noteNumber);
    check(snap.notes[1].velocity == 90, "velocity travels with the key", snap.notes[1].velocity);

    held.noteOn(60, 12, 127);   // a key already down is pressed again
    snap = held.snapshot();
    check(snap.count == 3, "a re-press does not duplicate", snap.count);
    check(snap.notes[0].noteNumber == 60 && snap.notes[0].transpose == 12, "a re-press moves the key to the front with its new transpose", snap.notes[0].transpose);

    held.noteOff(64);
    snap = held.snapshot();
    check(snap.count == 2 && snap.notes[0].noteNumber == 60 && snap.notes[1].noteNumber == 67, "a release closes the gap and keeps the order", snap.count);

    held.noteOff(99);
    check(held.count() == 2, "releasing a key that is not down changes nothing", held.count());

    held.clear();
    check(held.snapshot().count == 0, "clear empties the list", held.snapshot().count);

    // 128 distinct keys is the ceiling; the 129th press of a new key is ignored, not overflowed.
    for (int n = 0; n < 128; ++n) { held.noteOn(n, 0, 64); }
    check(held.count() == 128, "128 keys fit", held.count());
    held.noteOn(5, 0, 64);
    check(held.count() == 128, "a re-press at the ceiling still fits", held.count());
    held.clear();

    // A reader on another thread never sees a torn list: every snapshot's entries are the
    // keys the writer put there, in a prefix the writer wrote as a whole.
    std::atomic<bool> stop{false};
    std::atomic<long> torn{0}, reads{0};
    std::thread reader([&] {
        while (!stop.load()) {
            const S1HeldNoteList s = held.snapshot();
            for (int i = 0; i < s.count; ++i) {
                if (s.notes[i].velocity != s.notes[i].noteNumber + 1) { torn.fetch_add(1); }
            }
            reads.fetch_add(1);
        }
    });
    // At least 2,000 rounds, and on until the reader has really read beside them: a busy CI
    // machine once finished all 2,000 before the reader thread had been scheduled at all
    // (Windows, X2-2), which proved nothing and failed "the reader ran".
    for (int round = 0; round < 2000 || (reads.load() < 1000 && round < 20000000); ++round) {
        for (int n = 0; n < 40; ++n) { held.noteOn(n, 0, n + 1); }
        for (int n = 0; n < 40; ++n) { held.noteOff(n); }
    }
    stop.store(true);
    reader.join();
    check(torn.load() == 0, "no snapshot was torn under concurrent writes", torn.load());
    check(reads.load() >= 1000, "the reader read at least a thousand snapshots while the writer wrote", reads.load());

    std::printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
