//  S1HostMIDI — the plugin's MIDI input, handled on the render thread (ADR-031).
//
//  ## Why this exists
//
//  Upstream takes MIDI one way: CoreMIDI → `Manager+MIDIListener` → `KeyboardView` →
//  `Manager+Keyboard` → `SDSustainer` → the synth, on the main thread. That chain is where
//  the `Octave:` shift, velocity sensitivity, the MIDI channel, white-keys-only, hold and the
//  sustain pedal live.
//
//  A plugin has to take its *host's* MIDI, which arrives in the render block with sample
//  times. Measured in Logic on 2026-09-10, the plugin was doing both: every key sounded twice,
//  as two different notes on two threads, and a plugin on an unselected track still answered
//  a hardware keyboard. The host's route has to be the only route — and it cannot hop to the
//  main thread and back, because an offline bounce renders faster than real time.
//
//  So this is that chain again, in fixed-size state the render thread owns. Every step names
//  the Swift it mirrors. `HostMIDIParityTests` drives the same MIDI through both and requires
//  identical note calls: **change one, change the other.**
//
//  What belongs to the interface — the mod wheel, MIDI learn, program change, bank select,
//  and the sustain pedal's hold on on-screen keys — is forwarded to `Manager` through the
//  message queue, along with the set of held keys for the keyboard to light.
//
//  The standalone never enables this. It has no host, and upstream's `handleMIDIEvent` runs.

#ifndef S1_HOST_MIDI_HPP
#define S1_HOST_MIDI_HPP

#ifdef __cplusplus

#import <AudioToolbox/AudioToolbox.h>
#import "S1AudioUnit.h"

#include <atomic>
#include <cstdint>

class S1DSPKernel;

/// What the router and the queued keys did, for tests to read back (ADR-031).
///
/// Off by default; while it is off each note costs one relaxed atomic load. One writer (the
/// render thread) and one reader, and the writer never waits: if the reader has fallen behind
/// the entry is dropped, so a test sees a short trace and fails rather than a render thread
/// stalling.
struct S1HostMIDITrace {
    enum Op : uint32_t {
        hostNoteOn  = 1,   ///< the router started a note for host MIDI
        hostNoteOff = 2,   ///< … and stopped one
        keyNoteOn   = 3,   ///< an on-screen key, queued from the main thread
        keyNoteOff  = 4,
        allNotesOff = 5,
        pitchBend   = 6,   ///< value is the 14-bit bend
    };
    static constexpr uint32_t capacity = 1024;

    std::atomic<bool>     enabled{false};
    std::atomic<uint32_t> head{0};
    std::atomic<uint32_t> tail{0};
    uint32_t              entries[capacity] = {};

    /// Render thread. Packed as `[op:8][note:8][value:16]`.
    void record(Op op, uint32_t note, uint32_t value) {
        if (!enabled.load(std::memory_order_relaxed)) return;
        const uint32_t h = head.load(std::memory_order_relaxed);
        const uint32_t next = (h + 1) % capacity;
        if (next == tail.load(std::memory_order_acquire)) return;
        entries[h] = (uint32_t(op) << 24) | ((note & 0xFF) << 16) | (value & 0xFFFF);
        head.store(next, std::memory_order_release);
    }

    /// Reader. Copies and consumes up to `count` entries, oldest first.
    int take(uint32_t *destination, int count) {
        int copied = 0;
        uint32_t t = tail.load(std::memory_order_relaxed);
        const uint32_t h = head.load(std::memory_order_acquire);
        while (t != h && copied < count) {
            destination[copied++] = entries[t];
            t = (t + 1) % capacity;
        }
        tail.store(t, std::memory_order_release);
        return copied;
    }
};

class S1HostMIDI {
public:
    S1HostMIDI() { clear(); }

    // MARK: Settings — written by the interface, read on the render thread

    /// Off until the plugin's factory turns it on: `SynthOneApp.makePluginAudioUnit`.
    std::atomic<bool> enabled{false};

    // Each default is the standalone's own before its settings load, so a plugin whose window
    // was never opened plays exactly as the standalone would out of the box.
    std::atomic<int>  octaveShift{0};            ///< `Manager.midiOctaveShift`
    std::atomic<int>  midiChannel{0};            ///< `Conductor.midiInChannel`
    std::atomic<bool> omniMode{true};            ///< `Conductor.isOmniMode`
    // No velocity-sensitivity setting: velocity is always played as sent, in both products (ADR-032).
    std::atomic<bool> whiteKeysOnly{false};      ///< `AppSettings.whiteKeysOnly`
    std::atomic<bool> holdMode{false};           ///< `KeyboardView.holdMode`

    S1HostMIDITrace trace;

    // MARK: Render thread

    /// One MIDI event from the host's render event list.
    void handle(const AUMIDIEvent &event, S1DSPKernel &kernel);

    /// Once per render cycle, before the host's events: the two `KeyboardView` property
    /// observers that release every key, which here have to be noticed rather than called.
    void beginRenderCycle(S1DSPKernel &kernel);

    /// `KeyboardView.allNotesOff`, for the keys host MIDI is holding.
    void allNotesOff(S1DSPKernel &kernel);

    /// An on-screen or typed key the interface queued. Played as given — the interface has
    /// already applied its own octave and sustain.
    void keyNoteOnFromInterface(S1DSPKernel &kernel, int note, int velocity);
    void keyNoteOffFromInterface(S1DSPKernel &kernel, int note);

    /// Forget every held key and the pedal, without sounding anything. For `resetDSP`, which
    /// clears the voices itself.
    void clear();

private:
    bool accepts(int channel) const;
    bool isMono(S1DSPKernel &kernel) const;

    // `Manager+MIDIListener`
    void noteOn(S1DSPKernel &kernel, int note, int velocity, int channel);
    void noteOff(S1DSPKernel &kernel, int note, int velocity, int channel);
    void controller(S1DSPKernel &kernel, int number, int value, int channel);
    void pitchWheel(S1DSPKernel &kernel, int lsb, int msb, int channel);

    // `KeyboardView+Touches`
    void pressAdded(S1DSPKernel &kernel, int key, int velocity);
    void pressRemoved(S1DSPKernel &kernel, int key);

    // `Manager+Keyboard`
    void keyboardNoteOn(S1DSPKernel &kernel, int key, int velocity);
    void keyboardNoteOff(S1DSPKernel &kernel, int key);

    // `SDSustainer`
    void sustainerPlay(S1DSPKernel &kernel, int note, int velocity);
    void sustainerStop(S1DSPKernel &kernel, int note);
    void sustainPedal(S1DSPKernel &kernel, bool down);

    void start(S1DSPKernel &kernel, int note, int velocity);
    void stop(S1DSPKernel &kernel, int note);
    void forwardControl(S1DSPKernel &kernel, uint8_t status, uint8_t data1, uint8_t data2);
    void postKeysIfChanged(S1DSPKernel &kernel);

    /// `KeyboardView.onKeys`, for keys host MIDI pressed.
    bool onKeys[128];
    /// `Manager.notesFromMIDI`.
    bool notesFromMIDI[128];
    /// `Manager.soundingMIDINotes`: incoming note → the note it sounded, or -1.
    int16_t soundingFor[128];
    /// `SDSustainer.keyDown`, `.isPlaying` and `.pedalIsDown`.
    bool keyDown[128];
    bool isPlaying[128];
    bool pedalIsDown = false;
    /// `Manager.sustainMode`.
    bool sustainMode = false;

    bool lastMono = false;
    bool lastHold = false;
    uint64_t postedKeysLow = 0;
    uint64_t postedKeysHigh = 0;
};

#endif  // __cplusplus
#endif  // S1_HOST_MIDI_HPP
