//
//  S1PluginState.hpp
//  Arcade Ruins
//
//  X2-5 (ADR-076): what a host's session file holds for one instance. No JUCE in here.
//
//  It is JSON text (UTF-8), so there is no byte order, no struct layout and no float format to
//  differ between a Mac that saved a session and a Windows machine that opens it:
//
//    { "format": "ArcadeRuins.state", "version": 1, "plugin": "0.5.0",
//      "parameters": { "<S1Parameter case name>": number, … },        the authority for the sound
//      "preset":     { …the engine's preset JSON (ADR-069)… },        identity, and a preset the Mac app reads
//      "tuning":     { "notesPerOctave": n, "frequencies": [128] },   as the AUv3's fullState keeps it (P4-4)
//      "midi":       { the router's settings (ADR-075) } }
//
//  Reading: when `parameters` does not name every parameter, `preset` is applied first — to a
//  scratch kernel, in upstream's order, because the order decides some values — and then every ID
//  found in `parameters` overrides it. A parameter this build does not know is ignored, one the state does not have
//  keeps its preset or current value — so states move between versions in both directions.
//  `pitchbend` is never written and always comes back centred: it is a wheel's position, and a
//  session reopened with the wheel at rest must not play bent.
//
#pragma once

#include <array>
#include <optional>
#include <string>

#include "S1Parameter.h"
#include "S1Preset.hpp"

namespace s1plugin {

struct PluginState {
    static constexpr int currentVersion = 1;
    static constexpr const char *formatName = "ArcadeRuins.state";

    std::array<float, S1Parameter::S1ParameterCount> parameters {};
    /// Name, bank, uid, author, text, tuning name and master set, mod wheel routing… and, when
    /// written, the parameters' values captured into its fields.
    s1::Preset preset;
    std::array<float, 128> tuningFrequencies {};
    int tuningNotesPerOctave = 12;
    struct MIDI {
        int octaveShift = 0;
        int channel = 0;
        bool omni = true;
        bool whiteKeysOnly = false;
        bool hold = false;
    } midi;
    /// X3-8 (ADR-090): what this instance's window shows. Not a sound, and not shared with other
    /// instances — a host restores it with the session, closed unless it was open.
    struct Window {
        bool keyboardShown = false;
    } window;

    /// `preset` with `parameters` captured into its fields (and the sequencer rows): the sound as
    /// a preset — what a state's "preset" holds, and what is saved into a user bank (X2-9).
    s1::Preset capturedPreset() const;

    /// Captures `parameters` into `preset`'s fields first, so the preset in the file is the sound.
    std::string toJSON(const std::string &pluginVersion) const;

    /// `current` supplies everything the text does not mention; `minimum`/`maximum` clamp what it
    /// does. Nothing when the text is not a state of this format — the caller then changes nothing.
    static std::optional<PluginState> fromJSON(const std::string &text, const PluginState &current,
                                               const std::array<float, S1Parameter::S1ParameterCount> &minimum,
                                               const std::array<float, S1Parameter::S1ParameterCount> &maximum,
                                               const s1::PresetDefaults &defaults);
};

} // namespace s1plugin
