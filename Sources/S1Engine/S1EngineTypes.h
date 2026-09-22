//
//  S1EngineTypes.h
//  Arcade Ruins
//
//  PORT (X1-3, ADR-067): the engine's own vocabulary, plain C so Swift, Objective-C and every
//  C++ compiler read it. The typedefs stand in for the AudioToolbox names the kernel used to
//  spell out (`AUParameterAddress`, `AUValue`, `AUAudioFrameCount`, `AUMIDIEvent`,
//  `AudioUnitParameterUnit`) and are laid out so the Apple adapter converts by assignment.
//  The structs below moved here from S1AudioUnit.h unchanged.
//
//  Self-contained apart from S1Parameter.h, which is included by its bare name on purpose: the
//  two are siblings both in Sources/S1Engine and in the framework's flattened Headers/ folder
//  (ADR-012), so the same line resolves in both worlds.
//

#ifndef S1_ENGINE_TYPES_H
#define S1_ENGINE_TYPES_H

#include <stdint.h>
#include <stdbool.h>
#include "S1Parameter.h"

#define S1_MAX_POLYPHONY (6)
#define S1_NUM_MIDI_NOTES (128)

/// A parameter's address in the host's tree: `S1Parameter` as an integer. Same width as
/// AudioToolbox's AUParameterAddress.
typedef uint64_t S1ParameterAddress;
/// A parameter's value, as AudioToolbox's AUValue.
typedef float S1ParameterValue;
/// A count of sample frames, as AudioToolbox's AUAudioFrameCount.
typedef uint32_t S1FrameCount;

/// One MIDI message, as it reaches the kernel inside a render cycle. The fields AUMIDIEvent
/// carries that the kernel reads: length and up to three bytes.
typedef struct S1MIDIEvent {
    uint16_t length;
    uint8_t data[3];
} S1MIDIEvent;

/// The units the parameter table declares. The values are AudioToolbox's
/// `AudioUnitParameterUnit` values, so the Apple adapter casts and nothing else.
typedef enum S1ParameterUnit {
    S1ParameterUnit_Generic = 0,
    S1ParameterUnit_Seconds = 4,
    S1ParameterUnit_Rate = 7,
    S1ParameterUnit_Hertz = 8,
    S1ParameterUnit_RelativeSemiTones = 10,
    S1ParameterUnit_BPM = 22
} S1ParameterUnit;

/// An event positioned inside a render cycle, for `S1DSPKernel::processWithEvents`. Events
/// are handed over in ascending `sampleOffset`; the kernel renders up to each one, applies
/// every event at that offset, and carries on — the split Apple's `DSPKernel` makes for
/// AURenderEvents, so both hosts cut a buffer in the same places.
typedef enum S1EventKind {
    S1EventKind_Parameter = 0,
    S1EventKind_MIDI = 1
} S1EventKind;

typedef struct S1Event {
    S1EventKind kind;
    S1FrameCount sampleOffset;    ///< 0 … frameCount-1; an offset at or past the end applies after the last frame
    S1ParameterAddress address;   ///< S1EventKind_Parameter
    S1ParameterValue value;       ///< S1EventKind_Parameter
    S1FrameCount rampFrames;      ///< S1EventKind_Parameter: 0 for an immediate change
    S1MIDIEvent midi;             ///< S1EventKind_MIDI
} S1Event;


// helper for midi/render thread communication: held+playing notes
typedef struct NoteNumber {
    int noteNumber;
    int transpose;
    int velocity;
    float amp;
} NoteNumber;

// helper for render/main thread communication:
// DSP updates UI elements lfo1Rate, lfo2Rate, autoPanRate, delayTime when arpOn/tempoSyncArpRate update
// DSP updates lfo1Rate, lfo2Rate, autoPanRate, delayTime based on current arpOn/tempoSyncArpRate
typedef struct DependentParameter {
    S1Parameter parameter;
    float normalizedValue;// [0,1] for ui
    float value;
    int payload;
} DependentParameter;

// helper for main+render thread communication: array of playing notes
typedef struct PlayingNotes {
    int polyphony;
    NoteNumber playingNotes[S1_MAX_POLYPHONY];
} PlayingNotes;

// helper for main+render thread communication: array of held notes
typedef struct HeldNotes {
    int heldNotesCount;
    bool heldNotes[S1_NUM_MIDI_NOTES];
} HeldNotes;

// helper for main+render thread communcation: arp beat counter, and number of held notes
typedef struct S1ArpBeatCounter {
    int beatCounter;
    int heldNotesCount;
} S1ArpBeatCounter;

/// The interface's MIDI settings, as the plugin's render thread applies them to host MIDI
/// (ADR-031). Each field is a value the standalone reads on the main thread — see S1HostMIDI.hpp.
typedef struct S1HostMIDISettings {
    int octaveShift;          ///< Semitones added to each incoming note: `Manager.midiOctaveShift`
    int midiChannel;          ///< 0–15. Ignored in omni mode
    bool omniMode;
    // No `velocitySensitive`: velocity is always played as sent, in both products (ADR-032).
    bool whiteKeysOnly;
    bool holdMode;            ///< The keyboard's Hold button
} S1HostMIDISettings;

/// A control change or program change from the host, on its way to the interface (ADR-031).
/// `data2` is 0 for a program change.
typedef struct S1HostMIDIMessage {
    uint8_t status;
    uint8_t data1;
    uint8_t data2;
} S1HostMIDIMessage;

/// The keys host MIDI is holding, as a 128-bit set for the on-screen keyboard to light: bit `n`
/// of `low` is note `n`, and bit `n` of `high` is note `64 + n`.
typedef struct S1HostKeys {
    uint64_t low;
    uint64_t high;
} S1HostKeys;

#endif
