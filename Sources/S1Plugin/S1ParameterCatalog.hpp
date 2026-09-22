//
//  S1ParameterCatalog.hpp
//  Arcade Ruins
//
//  X2-2 (ADR-073): what a host is told about each of the 150 parameters. No JUCE in here —
//  S1HostParameter wraps a description for JUCE, and X3's interface will read the same list.
//
//  Where each fact comes from:
//    id                       the S1Parameter enum case's NAME, generated from S1Parameter.h by
//                             CMake (S1ParameterNames.inc). Permanent: sessions store it (ADR-058).
//    minimum/default/maximum  the kernel's own table, read from a kernel. Never typed here.
//    name, kind, format,      presentation, and free to change: the desktop layout's names and
//    taper, choices           readouts (S1DesktopLayout+Rows.swift, S1ControlCell.swift), the
//                             classic panels' knob tapers, the kernel's meaning for each step of
//                             a stepped parameter.
//
#pragma once

#include <optional>
#include <string>
#include <vector>

#include "S1Parameter.h"

class S1DSPKernel;

namespace s1plugin {

enum class ParameterKind {
    continuous,
    integer,     ///< whole numbers between minimum and maximum
    toggle,      ///< 0 or 1
    choice       ///< minimum … maximum name `choices`, in order
};

enum class ParameterFormat {
    decimal, percent, hertz, seconds, semitones, decibels, integer, bpm, ratio,
    rateFrequency,   ///< Hz — or a note value while tempo sync is on (LFO rates, auto-pan)
    rateTime,        ///< seconds — or a note value while tempo sync is on (delay time)
    rateFactor       ///< bars per sequencer step, always read as a note value
};

struct ParameterDescription {
    S1Parameter address = S1Parameter::index1;
    const char *id = "";
    std::string name;
    ParameterKind kind = ParameterKind::continuous;
    ParameterFormat format = ParameterFormat::decimal;
    float minimum = 0, defaultValue = 0, maximum = 1;
    /// A knob's taper as the Mac interface defines it: value = min + (max - min) * position^taper.
    float taper = 1;
    std::vector<std::string> choices;
    /// The engine rewrites this one itself — quantised to a note value under tempo sync, re-driven
    /// when the tempo or the sync switch changes (ADR-022) — so the plugin reads it back after
    /// every render and tells the host, instead of trusting what the host last wrote.
    bool engineMayChange = false;
};

/// What a rate's readout depends on besides its own value.
struct RateContext {
    bool tempoSync = false;
    float tempo = 120;
};

/// All 150, in enum order — which is also the order the host sees. Ranges from `kernel`.
std::vector<ParameterDescription> makeParameterCatalog(S1DSPKernel &kernel);

/// The enum case's name: the permanent ID. nullptr outside 0 … 149.
const char *parameterID(int address);

std::string formatValue(const ParameterDescription &, float value, const RateContext &);
/// The inverse, as far as a person typing into a host's field needs: "440", "440 Hz", "1.2 kHz",
/// "35 ms", "50%", "On", a choice's name. Nothing when the text is not a value.
std::optional<float> parseValue(const ParameterDescription &, const std::string &text);

} // namespace s1plugin
