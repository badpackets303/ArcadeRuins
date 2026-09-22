//
//  S1ParameterCatalog.cpp
//  Arcade Ruins
//
//  X2-2 (ADR-073). See the header for where each fact comes from.
//

#include "S1ParameterCatalog.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>

#include "S1DSPKernel.hpp"
#include "S1Rate.hpp"

namespace s1plugin {

namespace {

// MARK: - IDs, generated

struct GeneratedName { const char *name; int address; };

#define S1_PARAMETER_NAME(name, number) { #name, number },
constexpr GeneratedName kGeneratedNames[] = {
#include "S1ParameterNames.inc"
};
#undef S1_PARAMETER_NAME

static_assert(sizeof kGeneratedNames / sizeof kGeneratedNames[0] == S1Parameter::S1ParameterCount,
              "S1ParameterNames.inc does not list every S1Parameter");
// Each generated number against the enum itself: a line the generator misread cannot pass.
#define S1_PARAMETER_NAME(name, number) static_assert(int(S1Parameter::name) == number, #name);
#include "S1ParameterNames.inc"
#undef S1_PARAMETER_NAME

// MARK: - Presentation

using Kind = ParameterKind;
using Format = ParameterFormat;

struct Presentation {
    S1Parameter address;
    std::string name;
    Kind kind;
    Format format;
    float taper;
    std::vector<std::string> choices;
};

const std::vector<std::string> kLFOWaveforms = {"Sine", "Square", "Saw", "Reversed Saw"};     // process(): lfo1Index
const std::vector<std::string> kLFORouting = {"Off", "LFO 1", "LFO 2", "LFO 1 + 2"};            // process(): 1, 2, 3 (lfo3 = both)
const std::vector<std::string> kFilterTypes = {"Low Pass", "Band Pass", "High Pass"};           // S1NoteState: moog, butbp, buthp
const std::vector<std::string> kArpDirections = {"Up", "Up / Down", "Down"};                     // S1ArpModes.hpp

Presentation continuous(S1Parameter p, const std::string &name, Format format, float taper = 1) {
    return {p, name, Kind::continuous, format, taper, {}};
}
Presentation integer(S1Parameter p, const std::string &name, Format format = Format::integer) {
    return {p, name, Kind::integer, format, 1, {}};
}
Presentation toggle(S1Parameter p, const std::string &name) {
    return {p, name, Kind::toggle, Format::integer, 1, {}};
}
Presentation choice(S1Parameter p, const std::string &name, const std::vector<std::string> &choices) {
    return {p, name, Kind::choice, Format::integer, 1, choices};
}

/// Names are the desktop layout's, with the section in front because a host shows one flat list.
/// Tapers are the classic panels' (`knob.taper = …`); everything else there is linear.
std::vector<Presentation> presentations() {
    using P = S1Parameter;
    std::vector<Presentation> list = {
        continuous(P::index1, "OSC 1 Waveform", Format::decimal),
        continuous(P::index2, "OSC 2 Waveform", Format::decimal),
        continuous(P::morphBalance, "Mix Blend", Format::percent),
        integer(P::morph1SemitoneOffset, "OSC 1 Semitones", Format::semitones),
        integer(P::morph2SemitoneOffset, "OSC 2 Semitones", Format::semitones),
        continuous(P::morph1Volume, "Mix OSC 1", Format::percent),
        continuous(P::morph2Volume, "Mix OSC 2", Format::percent),
        continuous(P::subVolume, "Mix Sub", Format::percent),
        toggle(P::subOctaveDown, "Sub -24"),
        toggle(P::subIsSquare, "Sub Square"),
        continuous(P::fmVolume, "Mix FM", Format::percent),
        continuous(P::fmAmount, "Mix FM Mod", Format::decimal),
        continuous(P::noiseVolume, "Mix Noise", Format::percent),
        choice(P::lfo1Index, "LFO 1 Waveform", kLFOWaveforms),
        continuous(P::lfo1Amplitude, "LFO 1 Amount", Format::percent),
        continuous(P::lfo1Rate, "LFO 1 Rate", Format::rateFrequency),
        continuous(P::cutoff, "Filter Cutoff", Format::hertz, 2),
        continuous(P::resonance, "Filter Resonance", Format::decimal),
        continuous(P::filterMix, "Filter Mix", Format::percent),
        continuous(P::filterADSRMix, "Filter Env Amount", Format::percent),
        toggle(P::isMono, "Voice Mono"),
        continuous(P::glide, "Voice Glide", Format::decimal, 2),
        continuous(P::filterAttackDuration, "Filter Env Attack", Format::seconds),
        continuous(P::filterDecayDuration, "Filter Env Decay", Format::seconds),
        continuous(P::filterSustainLevel, "Filter Env Sustain", Format::percent),
        continuous(P::filterReleaseDuration, "Filter Env Release", Format::seconds),
        continuous(P::attackDuration, "Amp Env Attack", Format::seconds),
        continuous(P::decayDuration, "Amp Env Decay", Format::seconds),
        continuous(P::sustainLevel, "Amp Env Sustain", Format::percent),
        continuous(P::releaseDuration, "Amp Env Release", Format::seconds),
        continuous(P::morph2Detuning, "OSC 2 Detune", Format::decimal),
        continuous(P::detuningMultiplier, "OSC 2 Detune Multiplier", Format::decimal),
        continuous(P::masterVolume, "Master Volume", Format::percent, 2),
        integer(P::bitCrushDepth, "Bitcrusher Depth"),
        continuous(P::bitCrushSampleRate, "Bitcrusher Bitrate", Format::hertz, 4.6f),
        continuous(P::autoPanAmount, "Auto Pan Amount", Format::percent),
        continuous(P::autoPanFrequency, "Auto Pan Rate", Format::rateFrequency),
        toggle(P::reverbOn, "Reverb On"),
        continuous(P::reverbFeedback, "Reverb Size", Format::percent),
        continuous(P::reverbHighPass, "Reverb Low Cut", Format::hertz),
        continuous(P::reverbMix, "Reverb Mix", Format::percent),
        toggle(P::delayOn, "Delay On"),
        continuous(P::delayFeedback, "Delay Feedback", Format::percent),
        continuous(P::delayTime, "Delay Time", Format::rateTime),
        continuous(P::delayMix, "Delay Mix", Format::percent),
        choice(P::lfo2Index, "LFO 2 Waveform", kLFOWaveforms),
        continuous(P::lfo2Amplitude, "LFO 2 Amount", Format::percent),
        continuous(P::lfo2Rate, "LFO 2 Rate", Format::rateFrequency),
        choice(P::cutoffLFO, "LFO > Cutoff", kLFORouting),
        choice(P::resonanceLFO, "LFO > Resonance", kLFORouting),
        choice(P::oscMixLFO, "LFO > OSC Mix", kLFORouting),
        choice(P::reverbMixLFO, "LFO > Reverb Mix", kLFORouting),
        choice(P::decayLFO, "LFO > Decay", kLFORouting),
        choice(P::noiseLFO, "LFO > Noise", kLFORouting),
        choice(P::fmLFO, "LFO > FM Mod", kLFORouting),
        choice(P::detuneLFO, "LFO > Detune", kLFORouting),
        choice(P::filterEnvLFO, "LFO > Filter Env", kLFORouting),
        choice(P::pitchLFO, "LFO > Pitch", kLFORouting),
        choice(P::bitcrushLFO, "LFO > Bitcrush", kLFORouting),
        choice(P::tremoloLFO, "LFO > Tremolo", kLFORouting),
        choice(P::arpDirection, "Arp Direction", kArpDirections),
        integer(P::arpInterval, "Arp Interval", Format::semitones),
        toggle(P::arpIsOn, "Arp / Seq On"),
        integer(P::arpOctave, "Arp Octaves"),
        continuous(P::arpRate, "Tempo", Format::bpm),
        toggle(P::arpIsSequencer, "Sequencer Mode"),
        integer(P::arpTotalSteps, "Seq Steps"),
        choice(P::filterType, "Filter Type", kFilterTypes),
        continuous(P::phaserMix, "Phaser Mix", Format::decimal),
        continuous(P::phaserRate, "Phaser Rate", Format::decimal, 2),
        continuous(P::phaserFeedback, "Phaser Feedback", Format::decimal),
        continuous(P::phaserNotchWidth, "Phaser Notch", Format::decimal),
        toggle(P::monoIsLegato, "Voice Legato"),
        toggle(P::widen, "Master Widen"),
        continuous(P::compressorMasterRatio, "Master Compressor Ratio", Format::ratio),
        continuous(P::compressorReverbInputRatio, "Reverb Input Compressor Ratio", Format::ratio),
        continuous(P::compressorReverbWetRatio, "Reverb Wet Compressor Ratio", Format::ratio),
        continuous(P::compressorMasterThreshold, "Master Compressor Threshold", Format::decibels),
        continuous(P::compressorReverbInputThreshold, "Reverb Input Compressor Threshold", Format::decibels),
        continuous(P::compressorReverbWetThreshold, "Reverb Wet Compressor Threshold", Format::decibels),
        continuous(P::compressorMasterAttack, "Master Compressor Attack", Format::seconds),
        continuous(P::compressorReverbInputAttack, "Reverb Input Compressor Attack", Format::seconds),
        continuous(P::compressorReverbWetAttack, "Reverb Wet Compressor Attack", Format::seconds),
        continuous(P::compressorMasterRelease, "Master Compressor Release", Format::seconds),
        continuous(P::compressorReverbInputRelease, "Reverb Input Compressor Release", Format::seconds),
        continuous(P::compressorReverbWetRelease, "Reverb Wet Compressor Release", Format::seconds),
        continuous(P::compressorMasterMakeupGain, "Master Compressor Makeup Gain", Format::decimal),
        continuous(P::compressorReverbInputMakeupGain, "Reverb Input Compressor Makeup Gain", Format::decimal),
        continuous(P::compressorReverbWetMakeupGain, "Reverb Wet Compressor Makeup Gain", Format::decimal),
        continuous(P::delayInputCutoffTrackingRatio, "Delay Input Cutoff Tracking", Format::decimal),
        continuous(P::delayInputResonance, "Delay Input Resonance", Format::decimal),
        toggle(P::tempoSyncToArpRate, "Tempo Sync"),
        integer(P::pitchbend, "Pitch Bend"),
        integer(P::pitchbendMinSemitones, "Pitch Bend Down Range", Format::semitones),
        integer(P::pitchbendMaxSemitones, "Pitch Bend Up Range", Format::semitones),
        integer(P::frequencyA4, "Tuning A4", Format::hertz),                      // the kernel truncates it to whole Hz
        continuous(P::portamentoHalfTime, "Parameter Smoothing", Format::decimal),
        integer(P::oscBandlimitIndexOverride, "Band Limit Override (deprecated)"),
        toggle(P::oscBandlimitEnable, "Master Anti-alias"),
        continuous(P::arpSeqTempoMultiplier, "Seq Step Length", Format::rateFactor),
        integer(P::transpose, "Transpose", Format::semitones),
        continuous(P::adsrPitchTracking, "Amp Env Pitch Tracking", Format::decimal, 3),
    };
    for (int step = 0; step < 16; ++step) {
        const std::string name = "Seq Step " + std::to_string(step + 1);
        list.push_back(integer(S1Parameter(int(P::sequencerPattern00) + step), name + " Pitch", Format::semitones));
        list.push_back(toggle(S1Parameter(int(P::sequencerOctBoost00) + step), name + " Octave Up"));
        list.push_back(toggle(S1Parameter(int(P::sequencerNoteOn00) + step), name + " On"));
    }
    return list;
}

// MARK: - Text

std::string printed(const char *format, double value) {
    char buffer[64];
    std::snprintf(buffer, sizeof buffer, format, value);
    return buffer;
}

std::string lowercased(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) { return char(std::tolower(c)); });
    return text;
}

std::string trimmed(const std::string &text) {
    const auto first = text.find_first_not_of(" \t");
    if (first == std::string::npos) { return {}; }
    return text.substr(first, text.find_last_not_of(" \t") - first + 1);
}

// S1ControlCell.swift's S1ValueFormat, so a host's readout and the Mac interface's agree.
std::string hertz(double value) {
    if (value >= 1000) { return printed("%.2f kHz", value / 1000); }
    if (value >= 100) { return printed("%.0f Hz", value); }
    return printed("%.1f Hz", value);
}
std::string seconds(double value) {
    if (value >= 1) { return printed("%.2f s", value); }
    return printed("%.0f ms", value * 1000);
}

} // namespace

// MARK: - Catalog

const char *parameterID(int address) {
    if (address < 0 || address >= S1Parameter::S1ParameterCount) { return nullptr; }
    return kGeneratedNames[address].name;   // static_asserted above: entry i is parameter i
}

std::vector<ParameterDescription> makeParameterCatalog(S1DSPKernel &kernel) {
    std::vector<ParameterDescription> catalog(static_cast<size_t>(S1Parameter::S1ParameterCount));
    std::vector<bool> described(catalog.size(), false);
    for (const Presentation &p : presentations()) {
        ParameterDescription &d = catalog[size_t(p.address)];
        described[size_t(p.address)] = true;
        d.address = p.address;
        d.id = parameterID(int(p.address));
        d.name = p.name;
        d.kind = p.kind;
        d.format = p.format;
        d.taper = p.taper;
        d.choices = p.choices;
        d.minimum = kernel.minimum(p.address);
        d.defaultValue = kernel.defaultValue(p.address);
        d.maximum = kernel.maximum(p.address);
        d.engineMayChange = p.address == S1Parameter::lfo1Rate || p.address == S1Parameter::lfo2Rate
            || p.address == S1Parameter::autoPanFrequency || p.address == S1Parameter::delayTime
            || p.address == S1Parameter::arpSeqTempoMultiplier;
    }
    // A parameter added to the enum and not to presentations() still reaches the host, under its ID.
    for (size_t i = 0; i < catalog.size(); ++i) {
        if (described[i]) { continue; }
        ParameterDescription &d = catalog[i];
        d.address = S1Parameter(int(i));
        d.id = parameterID(int(i));
        d.name = d.id;
        d.minimum = kernel.minimum(d.address);
        d.defaultValue = kernel.defaultValue(d.address);
        d.maximum = kernel.maximum(d.address);
    }
    return catalog;
}

// MARK: - Value to text and back

std::string formatValue(const ParameterDescription &d, float value, const RateContext &context) {
    if (d.kind == ParameterKind::toggle) { return value >= 0.5f ? "On" : "Off"; }
    if (d.kind == ParameterKind::choice) {
        const long index = std::lround(value - d.minimum);
        if (index >= 0 && size_t(index) < d.choices.size()) { return d.choices[size_t(index)]; }
        return printed("%.0f", value);
    }
    S1Rate rates;
    switch (d.format) {
        case ParameterFormat::decimal: return printed("%.2f", value);
        case ParameterFormat::percent: return printed("%.0f%%", double(value) * 100);
        case ParameterFormat::hertz: return hertz(value);
        case ParameterFormat::seconds: return seconds(value);
        case ParameterFormat::semitones: {
            const long v = std::lround(value);
            return v == 0 ? "0 st" : printed("%+.0f st", double(v));
        }
        case ParameterFormat::decibels: return printed("%.1f dB", value);
        case ParameterFormat::integer: return printed("%.0f", std::round(value));
        case ParameterFormat::bpm: return printed("%.1f BPM", value);
        case ParameterFormat::ratio: return printed("%.1f:1", value);
        case ParameterFormat::rateFrequency:
            if (!context.tempoSync) { return hertz(value); }
            return rates.friendlyName(rates.nearestFrequency(value, context.tempo, d.minimum, d.maximum).rate);
        case ParameterFormat::rateTime:
            if (!context.tempoSync) { return seconds(value); }
            return rates.friendlyName(rates.nearestTime(value, context.tempo, d.minimum, d.maximum).rate);
        case ParameterFormat::rateFactor:
            return rates.friendlyName(rates.nearestFactor(value).rate);
    }
    return printed("%.2f", value);
}

std::optional<float> parseValue(const ParameterDescription &d, const std::string &input) {
    const std::string text = lowercased(trimmed(input));
    if (text.empty()) { return std::nullopt; }
    if (d.kind == ParameterKind::toggle) {
        if (text == "on" || text == "yes" || text == "true") { return 1.f; }
        if (text == "off" || text == "no" || text == "false") { return 0.f; }
    }
    if (d.kind == ParameterKind::choice) {
        for (size_t i = 0; i < d.choices.size(); ++i) {
            if (lowercased(d.choices[i]) == text) { return d.minimum + float(i); }
        }
    }
    char *end = nullptr;
    const double number = std::strtod(text.c_str(), &end);
    if (end == text.c_str() || !std::isfinite(number)) { return std::nullopt; }
    const std::string unit = trimmed(end);
    double value = number;
    if (unit == "khz") { value = number * 1000; }
    else if (unit == "ms") { value = number / 1000; }
    else if (unit == "%") { value = number / 100; }
    else if (unit.empty() && d.format == ParameterFormat::percent) { value = number / 100; }   // "50" in a percent field is 50%
    return float(std::clamp(value, double(d.minimum), double(d.maximum)));
}

} // namespace s1plugin
