// X3-8 (ADR-090): the interface's own keyboard — the drawer's keys, Hold and the octave shift.
//
// The plan's acceptance is "notes played on the drawer keyboard go through the same path as host
// MIDI and sound identical", and that is measured here the only way it can honestly be measured:
// the same note is played twice into two identical plugins, once from the interface and once as
// the host's own MIDI, and **the two renders are compared sample by sample**. Anything the router
// does — the octave shift, hold, white keys, mono, the arpeggiator, the held-key bookkeeping — is
// then the same by construction, because it is the same code (ADR-031).
//
// The keyboard's geometry is `s1plugin::Keybed`, which has no JUCE in it: which key is under a
// point, where each key is drawn, and what a key sounds. Tested here with no window.
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include "S1Keybed.hpp"
#include "S1PluginProcessor.h"

namespace {

constexpr double kSampleRate = 44100.0;
constexpr int kBlock = 512;

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

float peak(const juce::AudioBuffer<float> &buffer) { return buffer.getMagnitude(0, buffer.getNumSamples()); }

} // namespace

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);

    // MARK: the geometry — upstream's, measured against the Swift it is a port of
    {
        // The drawer's own size: four octaves from `firstOctave` 2, as the Mac's keyboard ships.
        const s1plugin::Keybed keys(4, 2, 1400.0f, 124.0f);
        check(keys.firstNote() == 48 && keys.lastNote() == 96, "four octaves from firstOctave 2 run C3 to C7", keys.firstNote());
        check(keys.whiteKeyCount() == 29, "…29 white keys, the C that closes it among them", keys.whiteKeyCount());
        check(keys.keyCount() == 49, "…and 49 keys with the black ones", keys.keyCount());

        // `updateOneOctaveSize`: an octave is narrower than a quarter of the view, which is what
        // leaves room for the closing C.
        check(std::fabs(keys.octaveWidth() - (1400.0f / 4.0f - 1400.0f / (16.0f * 7.0f))) < 0.01f,
              "an octave is width/octaves less width/(octaves squared x 7), as upstream sizes it", double(keys.octaveWidth()));

        const s1plugin::KeyBox first = keys.box(0);
        check(first.isWhite && std::fabs(first.height - 122.0f) < 0.01f && std::fabs(first.width - keys.octaveWidth() / 7.0f) < 0.01f,
              "a white key is a seventh of an octave, two points short of the full height", double(first.width));
        const s1plugin::KeyBox sharp = keys.box(1);
        check(!sharp.isWhite && std::fabs(sharp.height - 124.0f * 0.55f) < 0.01f,
              "a black key is 55% of the length (upstream's topKeyHeightRatio)", double(sharp.height));
        // Upstream draws a black key as TWO of the 28 slots, each slot four points wider than its
        // share, and the two overlap into one key — 0.58 of a white key here.
        check(std::fabs(sharp.width - (2.0f * keys.octaveWidth() / 28.0f + 4.0f)) < 0.01f
                  && sharp.x > first.x && sharp.x < first.x + first.width,
              "…two of the black band's 28 slots wide, overlapping the white key", double(sharp.width / first.width));

        // What is under a point: above the black keys the band's 28 slots answer, below them the
        // seven white keys do — `noteFromTouchLocation12ET`.
        check(keys.noteAt(sharp.x + sharp.width * 0.5f, 4.0f) == 49, "a click at the top of C sharp sounds it", keys.noteAt(sharp.x + sharp.width * 0.5f, 4.0f));
        // C sharp is centred on the line between C and D, so below the band its own centre is D's
        // by a hair; a point inside its left half is C's.
        check(keys.noteAt(sharp.x + 1.0f, 120.0f) == 48, "…and just below the black band, the white key under it sounds", keys.noteAt(sharp.x + 1.0f, 120.0f));
        check(keys.noteAt(-5.0f, 20.0f) == -1 && keys.noteAt(2000.0f, 20.0f) == -1 && keys.noteAt(10.0f, -3.0f) == -1,
              "and a point off the keyboard sounds nothing", keys.noteAt(-5.0f, 20.0f));

        // Every key is drawn, and a click in the middle of one sounds that key and no other.
        int found = 0, wrong = 0;
        for (int note = keys.firstNote(); note <= keys.lastNote(); ++note) {
            const s1plugin::KeyBox box = keys.boxForNote(note);
            if (!box.exists()) { ++wrong; continue; }
            ++found;
            // A white key is asked below the black band, where the white keys answer.
            const float y = box.isWhite ? 124.0f * 0.8f : box.height * 0.5f;
            const float x = box.isWhite && note == keys.lastNote() ? box.x + 2.0f : box.x + box.width * 0.5f;
            if (keys.noteAt(x, y) != note) { ++wrong; }
        }
        check(found == 49 && wrong == 0, "every one of the 49 keys is drawn, and a click on it sounds that note", wrong);

        // PORT FIX: upstream's own arithmetic sounds a D in the closing C's sliver, because the
        // octave it computes there is past the last one.
        const s1plugin::KeyBox closing = keys.boxForNote(96);
        check(keys.noteAt(closing.x + 1.0f, 100.0f) == 96 && keys.noteAt(1399.0f, 100.0f) == 96,
              "the C that closes the keyboard sounds a C, not the D upstream's arithmetic reaches", keys.noteAt(1399.0f, 100.0f));

        // A mouse has a position where a finger has none: upstream plays every on-screen key at
        // 127, and this follows how far down the key the click landed.
        check(keys.velocityAt(first.height * 0.95f, first) > keys.velocityAt(first.height * 0.05f, first),
              "pressing further down a key plays it harder", double(keys.velocityAt(first.height * 0.95f, first)));
        check(keys.velocityAt(first.height, first) == 127 && keys.velocityAt(0.0f, first) >= 1,
              "the bottom of a key is 127, and nothing is below MIDI's range", double(keys.velocityAt(0.0f, first)));

        // The octave the keyboard starts at moves every key with it.
        s1plugin::Keybed higher(2, 3, 600.0f, 120.0f);
        check(higher.keyCount() == 25 && higher.firstNote() == 60, "two octaves from firstOctave 3 start at middle C", higher.firstNote());
        higher.setFirstOctave(2);
        check(higher.firstNote() == 48 && higher.boxForNote(48).exists() && !higher.boxForNote(47).exists(),
              "…and moving it down an octave moves the lowest key with it", higher.firstNote());
    }

    // MARK: THE ACCEPTANCE — a key from the interface sounds exactly as the host's own note does
    {
        const auto renderNote = [](bool fromInterface) {
            S1PluginProcessor plugin;
            plugin.setPlayConfigDetails(0, 2, kSampleRate, kBlock);
            plugin.prepareToPlay(kSampleRate, kBlock);
            juce::AudioBuffer<float> audio(2, kBlock);
            std::vector<float> rendered;
            for (int block = 0; block < 24; ++block) {
                juce::MidiBuffer midi;
                if (block == 0) {
                    if (fromInterface) { plugin.sendMIDIFromInterface(0x90, 60, 100); }
                    else { midi.addEvent(juce::MidiMessage::noteOn(1, 60, juce::uint8(100)), 0); }
                }
                if (block == 16) {
                    if (fromInterface) { plugin.sendMIDIFromInterface(0x80, 60, 0); }
                    else { midi.addEvent(juce::MidiMessage::noteOff(1, 60), 0); }
                }
                audio.clear();
                plugin.processBlock(audio, midi);
                rendered.insert(rendered.end(), audio.getReadPointer(0), audio.getReadPointer(0) + kBlock);
            }
            plugin.releaseResources();
            return rendered;
        };
        const std::vector<float> byHand = renderNote(true), byHost = renderNote(false);
        check(byHand.size() == byHost.size() && !byHand.empty(), "both renders are the same length", double(byHand.size()));
        double worst = 0;
        float loudest = 0;
        for (size_t i = 0; i < std::min(byHand.size(), byHost.size()); ++i) {
            worst = std::max(worst, double(std::fabs(byHand[i] - byHost[i])));
            loudest = std::max(loudest, std::fabs(byHost[i]));
        }
        check(loudest > 0.01f, "the note sounds at all", double(loudest));
        check(worst == 0.0, "a key played in the interface renders SAMPLE FOR SAMPLE as the host's own note", worst);
    }

    // MARK: the octave shift moves the interface's notes and the host's together
    {
        S1PluginProcessor plugin;
        plugin.setPlayConfigDetails(0, 2, kSampleRate, kBlock);
        plugin.prepareToPlay(kSampleRate, kBlock);
        juce::AudioBuffer<float> audio(2, kBlock);
        juce::MidiBuffer none;
        plugin.hostMIDITrace().enabled.store(true);

        check(plugin.octaveShift() == 0, "a new instance is at the middle octave", plugin.octaveShift());
        plugin.setOctaveShift(1);
        check(plugin.octaveShift() == 1, "…and the stepper moves it in whole octaves", plugin.octaveShift());
        plugin.sendMIDIFromInterface(0x90, 60, 100);
        plugin.processBlock(audio, none);
        plugin.sendMIDIFromInterface(0x80, 60, 0);
        plugin.processBlock(audio, none);
        juce::uint32 entries[S1HostMIDITrace::capacity] = {};
        const int count = plugin.hostMIDITrace().take(entries, int(S1HostMIDITrace::capacity));
        int sounded = -1;
        for (int i = 0; i < count; ++i) {
            if ((entries[i] >> 24) == S1HostMIDITrace::hostNoteOn) { sounded = int((entries[i] >> 16) & 0xFF); }
        }
        check(sounded == 72, "middle C pressed in the interface sounds an octave up, as the host's own would", sounded);
        plugin.setOctaveShift(0);
        plugin.releaseResources();
    }

    // MARK: Hold — a note-off is ignored while it is on, and switching it off releases everything
    {
        S1PluginProcessor plugin;
        plugin.setPlayConfigDetails(0, 2, kSampleRate, kBlock);
        plugin.prepareToPlay(kSampleRate, kBlock);
        juce::AudioBuffer<float> audio(2, kBlock);
        juce::MidiBuffer none;
        const auto run = [&](int blocks) { for (int i = 0; i < blocks; ++i) { audio.clear(); plugin.processBlock(audio, none); } };

        check(!plugin.isHolding(), "a new instance is not holding", 0);
        plugin.setHolding(true);
        plugin.sendMIDIFromInterface(0x90, 60, 100);
        run(2);
        plugin.sendMIDIFromInterface(0x80, 60, 0);   // the key let go — and ignored, because Hold is on
        run(8);
        audio.clear();
        plugin.processBlock(audio, none);
        const float heldOn = peak(audio);
        check(heldOn > 0.01f, "with Hold on, a key let go keeps sounding", double(heldOn));

        plugin.setHolding(false);                     // its didSet releases every key
        run(60);                                      // the release, in full
        audio.clear();
        plugin.processBlock(audio, none);
        const float afterHold = peak(audio);
        check(afterHold < heldOn * 0.01f, "…and switching Hold off lets them all go", double(afterHold));

        // The key plays again afterwards: the router's held-key bookkeeping was not left behind
        // (ADR-081's rule — the fault that swallowed the next note-on twice before).
        plugin.sendMIDIFromInterface(0x90, 60, 100);
        run(2);
        audio.clear();
        plugin.processBlock(audio, none);
        check(peak(audio) > 0.01f, "and the same key plays again after it", double(peak(audio)));
        plugin.sendMIDIFromInterface(0x80, 60, 0);
        plugin.releaseResources();
    }

    // MARK: the queue is bounded, and a full one drops rather than blocking or growing
    {
        S1PluginProcessor plugin;
        plugin.setPlayConfigDetails(0, 2, kSampleRate, kBlock);
        plugin.prepareToPlay(kSampleRate, kBlock);
        int sent = 0;
        while (plugin.sendMIDIFromInterface(0x90, 60, 1) && sent < 4096) { ++sent; }
        check(sent > 200 && sent < 1000, "the interface's queue holds a few hundred messages", sent);
        check(!plugin.sendMIDIFromInterface(0x90, 60, 1), "…and says so when it is full, rather than allocating", 0);
        juce::AudioBuffer<float> audio(2, kBlock);
        juce::MidiBuffer none;
        audio.clear();
        plugin.processBlock(audio, none);             // drains it
        check(plugin.sendMIDIFromInterface(0x80, 60, 0), "a block empties it again", 1);
        plugin.requestAllNotesOff();
        plugin.processBlock(audio, none);
        plugin.releaseResources();
    }

    std::printf("%s\n", failures == 0 ? "PASSED" : "FAILED");
    return failures == 0 ? 0 : 1;
}
