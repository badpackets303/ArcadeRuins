//
//  S1Preset.hpp
//  Arcade Ruins
//
//  PORT (X1-5, ADR-069): Preset.swift, Preset+Synth.swift (apply) and the parameter half of
//  PresetDataManager.saveValuesToPreset (capture), in C++. The field list, the JSON keys, the
//  defaults and the apply order are TRANSCRIBED from the Swift by a script (see the ADR), not
//  retyped: a preset must decode to the same 150 values here as there, and PresetTests proves it
//  against a fixture the Swift wrote for every factory preset.
//
//  "You MUST match these property names with the dictionary key used by init or you will forever
//  lose the original preset." — upstream. Still true: the JSON keys are the Swift property names.
//
#ifndef S1_PRESET_HPP
#define S1_PRESET_HPP

#include <array>
#include <functional>
#include <optional>
#include <string>
#include <vector>

#include "S1Parameter.h"
#include "../third_party/nlohmann/json.hpp"

class S1DSPKernel;

namespace s1 {

/// The DSP's default for a parameter a preset's JSON omits (Swift: `PresetDefaults`).
using PresetDefaults = std::function<double(S1Parameter)>;

struct Preset {
    std::string uid;   // Swift: UUID().uuidString; the engine gives a fresh preset one through newUID()
    int position = 0;
    std::string name = "Init";
    std::string bank = "User";
    int octavePosition = 0;
    double isMono = 0.0;
    double isHoldMode = 0.0;
    double isArpMode = 0.0;
    double isLegato = 0.0;
    double tempoSyncToArpRate = 1.0;
    double masterVolume = 0.5;
    double vco1Volume = 0.75;
    double vco2Volume = 0.75;
    double vco1Semitone = 0.0;
    double vco2Semitone = 0.0;
    double vco2Detuning = 0.0;
    double vcoBalance = 0.0;
    double subVolume = 0.0;
    double fmVolume = 0.0;
    double fmAmount = 0.0;
    double noiseVolume = 0.0;
    double cutoff = 4000.0;
    double resonance = 0.1;
    double filterType = 0.0;
    double delayTime = 0.5;
    double delayMix = 0.5;
    double delayFeedback = 0.1;
    double reverbFeedback = 0.5;
    double reverbMix = 0.5;
    double reverbHighPass = 80.0;
    double midiBendRange = 2.0;
    double crushFreq = 48000.0;
    double autoPanAmount = 0.0;
    double autoPanFrequency = 2.0;
    double filterADSRMix = 0.0;
    double glide = 0.0;
    double widen = 0.0;
    double phaserMix = 0.0;
    double phaserRate = 12.0;
    double phaserFeedback = 0.0;
    double phaserNotchWidth = 800.00;
    double attackDuration = 0.05;
    double decayDuration = 0.05;
    double sustainLevel = 0.8;
    double releaseDuration = 0.05;
    double filterAttack = 0.05;
    double filterDecay = 0.5;
    double filterSustain = 1.0;
    double filterRelease = 0.5;
    double delayToggled = 0.0;
    double reverbToggled = 0.0;
    double subOsc24Toggled = 0.0;
    double subOscSquareToggled = 0.0;
    double waveform1 = 0.0;
    double waveform2 = 0.0;
    double lfoWaveform = 0.0;
    double lfoAmplitude = 0.0;
    double lfoRate = 0.0;
    double lfo2Waveform = 0.0;
    double lfo2Amplitude = 0.0;
    double lfo2Rate = 0.0;
    std::array<int, 16> seqPatternNote = {};
    std::array<bool, 16> seqOctBoost = {false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false};
    std::array<bool, 16> seqNoteOn = {true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true};
    double arpDirection = 0.0;
    double arpInterval = 12.0;
    double arpOctave = 1.0;
    double arpRate = 120.0;
    bool arpIsSequencer = false;
    double arpTotalSteps = 8.0;
    double arpSeqTempoMultiplier = 0.25;
    int transpose = 0;
    double adsrPitchTracking = 0.0;
    std::string author = "";
    int category = 0;
    bool isUser = true;
    bool isFavorite = false;
    std::string userText = "AudioKit Synth One. Preset by ...";
    double cutoffLFO = 0.0;
    double resonanceLFO = 0.0;
    double oscMixLFO = 0.0;
    double reverbMixLFO = 0.0;
    double decayLFO = 0.0;
    double noiseLFO = 0.0;
    double fmLFO = 0.0;
    double detuneLFO = 0.0;
    double filterEnvLFO = 0.0;
    double pitchLFO = 0.0;
    double bitcrushLFO = 0.0;
    double tremoloLFO = 0.0;
    double modWheelRouting = 0.0;
    double pitchbendMinSemitones = 0.0;
    double pitchbendMaxSemitones = 0.0;
    double compressorMasterRatio = 0.0;
    double compressorReverbInputRatio = 0.0;
    double compressorReverbWetRatio = 0.0;
    double compressorMasterThreshold = 0.0;
    double compressorReverbInputThreshold = 0.0;
    double compressorReverbWetThreshold = 0.0;
    double compressorMasterAttack = 0.0;
    double compressorReverbInputAttack = 0.0;
    double compressorReverbWetAttack = 0.0;
    double compressorMasterRelease = 0.0;
    double compressorReverbInputRelease = 0.0;
    double compressorReverbWetRelease = 0.0;
    double compressorMasterMakeupGain = 0.0;
    double compressorReverbInputMakeupGain = 0.0;
    double compressorReverbWetMakeupGain = 0.0;
    double delayInputCutoffTrackingRatio = 0.75;
    double delayInputResonance = 0.0;
    double oscBandlimitEnable = 1.0;
    double frequencyA4 = 440.0;
    std::optional<std::string> tuningName;   // default is nil
    std::optional<std::vector<double>> tuningMasterSet;   // default is nil

    /// Preset(dictionary:defaults:). A key that is missing or of the wrong JSON type takes the
    /// DSP default (or the field's own), as `as? … ?? …` did.
    static Preset fromJSON(const nlohmann::json &dictionary, const PresetDefaults &defaults);
    /// Preset.parseDataToPresets: every object in the array; non-objects are skipped.
    static std::vector<Preset> bankFromJSON(const nlohmann::json &array, const PresetDefaults &defaults);
    /// What Swift's JSONEncoder writes for a Preset: every field under its property name;
    /// a nil tuningName / tuningMasterSet is omitted.
    nlohmann::json toJSON() const;

    /// Preset+Synth.apply(to:): every parameter, in upstream's order, then resetSequencer.
    /// Order matters: setSynthParameter writes are order-dependent through the dependent parameters.
    void apply(S1DSPKernel &kernel) const;
    /// The parameter half of PresetDataManager.saveValuesToPreset: reads the kernel back into
    /// the fields. (The rest — tuning, octave position, user text — is the interface's.)
    void capture(S1DSPKernel &kernel);
    /// X2-5 (ADR-076): the same reads from whatever holds the parameters — the JUCE plugin's host
    /// parameters, which a host saves while the kernel is rendering on another thread.
    using ParameterGetter = std::function<double(S1Parameter)>;
    void capture(const ParameterGetter &get);

    /// A fresh UUID string in Swift's uppercase 8-4-4-4-12 form.
    static std::string newUID();
};

}  // namespace s1

#endif
