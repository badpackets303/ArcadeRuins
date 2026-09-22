#include "S1Preset.hpp"

#include <cmath>
#include <cstdio>
#include <random>

#include "S1DSPKernel.hpp"

namespace s1 {

namespace {

using json = nlohmann::json;

// The `as?` casts, as Foundation bridges JSON values into Swift:
//   as? Double  — any JSON number
//   as? Int     — an integer, or a float with no fractional part (NSNumber bridges 3.0 to 3, not 3.5)
//   as? Bool    — a JSON bool, or a number that is exactly 0 or 1
//   as? String  — a JSON string
//   as? [T]     — an array whose every element bridges as T
std::optional<double> asDouble(const json &v) {
    if (v.is_number()) return v.get<double>();
    if (v.is_boolean()) return v.get<bool>() ? 1.0 : 0.0;   // NSNumber(true) as? Double is 1
    return std::nullopt;
}
std::optional<int> asInt(const json &v) {
    if (v.is_number_integer()) return v.get<int>();
    if (v.is_number_float()) { const double d = v.get<double>(); if (d == std::trunc(d)) return int(d); }
    if (v.is_boolean()) return v.get<bool>() ? 1 : 0;
    return std::nullopt;
}
std::optional<bool> asBool(const json &v) {
    if (v.is_boolean()) return v.get<bool>();
    if (v.is_number()) { const double d = v.get<double>(); if (d == 0) return false; if (d == 1) return true; }
    return std::nullopt;
}
std::optional<std::string> asString(const json &v) {
    if (v.is_string()) return v.get<std::string>();
    return std::nullopt;
}
template <typename T, typename F>
std::optional<std::vector<T>> asArray(const json &v, F bridge) {
    if (!v.is_array()) return std::nullopt;
    std::vector<T> out;
    for (const json &e : v) { auto b = bridge(e); if (!b) return std::nullopt; out.push_back(*b); }
    return out;
}
template <typename T, size_t N>
std::optional<std::array<T, N>> asArrayN(const json &v, std::optional<std::vector<T>> (*bridge)(const json &)) {
    auto vec = bridge(v);
    if (!vec || vec->size() != N) return std::nullopt;   // Swift indexes [i] for i in 0..<16: a short array would trap
    std::array<T, N> out{};
    for (size_t i = 0; i < N; ++i) out[i] = (*vec)[i];
    return out;
}
std::optional<std::vector<int>> intArray(const json &v) { return asArray<int>(v, asInt); }
std::optional<std::vector<bool>> boolArray(const json &v) { return asArray<bool>(v, asBool); }
std::optional<std::vector<double>> doubleArray(const json &v) { return asArray<double>(v, asDouble); }

const json &field(const json &d, const char *key) {
    static const json missing;
    const auto it = d.find(key);
    return it == d.end() ? missing : *it;
}

}  // namespace

Preset Preset::fromJSON(const json &dictionary, const PresetDefaults &defaults) {
    Preset preset;
    if (!dictionary.is_object()) { return preset; }
    const json &d = dictionary;
    preset.name = asString(field(d, "name")).value_or(preset.name);
    preset.position = asInt(field(d, "position")).value_or(preset.position);
    preset.uid = asString(field(d, "uid")).value_or(preset.uid);
    preset.bank = asString(field(d, "bank")).value_or(preset.bank);
    preset.octavePosition = asInt(field(d, "octavePosition")).value_or(preset.octavePosition);
    preset.isMono = asDouble(field(d, "isMono")).value_or(defaults(S1Parameter::isMono));
    preset.isHoldMode = asDouble(field(d, "isHoldMode")).value_or(preset.isHoldMode);
    preset.isArpMode = asDouble(field(d, "isArpMode")).value_or(defaults(S1Parameter::arpIsOn));
    preset.tempoSyncToArpRate = asDouble(field(d, "tempoSyncToArpRate")).value_or(defaults(S1Parameter::tempoSyncToArpRate));
    preset.isLegato = asDouble(field(d, "isLegato")).value_or(defaults(S1Parameter::monoIsLegato));
    preset.masterVolume = asDouble(field(d, "masterVolume")).value_or(defaults(S1Parameter::masterVolume));
    preset.vco1Volume = asDouble(field(d, "vco1Volume")).value_or(defaults(S1Parameter::morph1Volume));
    preset.vco2Volume = asDouble(field(d, "vco2Volume")).value_or(defaults(S1Parameter::morph2Volume));
    preset.vco1Semitone = asDouble(field(d, "vco1Semitone")).value_or(defaults(S1Parameter::morph1SemitoneOffset));
    preset.vco2Semitone = asDouble(field(d, "vco2Semitone")).value_or(defaults(S1Parameter::morph2SemitoneOffset));
    preset.vco2Detuning = asDouble(field(d, "vco2Detuning")).value_or(defaults(S1Parameter::morph2Detuning));
    preset.vcoBalance = asDouble(field(d, "vcoBalance")).value_or(defaults(S1Parameter::morphBalance));
    preset.subVolume = asDouble(field(d, "subVolume")).value_or(defaults(S1Parameter::subVolume));
    preset.fmVolume = asDouble(field(d, "fmVolume")).value_or(defaults(S1Parameter::fmVolume));
    preset.fmAmount = asDouble(field(d, "fmAmount")).value_or(defaults(S1Parameter::fmAmount));
    preset.noiseVolume = asDouble(field(d, "noiseVolume")).value_or(defaults(S1Parameter::noiseVolume));
    preset.cutoff = asDouble(field(d, "cutoff")).value_or(defaults(S1Parameter::cutoff));
    preset.resonance = asDouble(field(d, "resonance")).value_or(defaults(S1Parameter::resonance));
    preset.filterType = asDouble(field(d, "filterType")).value_or(defaults(S1Parameter::filterType));
    preset.delayTime = asDouble(field(d, "delayTime")).value_or(defaults(S1Parameter::delayTime));
    preset.delayFeedback = asDouble(field(d, "delayFeedback")).value_or(defaults(S1Parameter::delayFeedback));
    preset.delayMix = asDouble(field(d, "delayMix")).value_or(defaults(S1Parameter::delayMix));
    preset.reverbFeedback = asDouble(field(d, "reverbFeedback")).value_or(defaults(S1Parameter::reverbFeedback));
    preset.reverbMix = asDouble(field(d, "reverbMix")).value_or(defaults(S1Parameter::reverbMix));
    preset.reverbHighPass = asDouble(field(d, "reverbHighPass")).value_or(defaults(S1Parameter::reverbHighPass));
    preset.midiBendRange = asDouble(field(d, "midiBendRange")).value_or(preset.midiBendRange);
    preset.crushFreq = asDouble(field(d, "crushFreq")).value_or(defaults(S1Parameter::bitCrushSampleRate));
    preset.autoPanFrequency = asDouble(field(d, "autoPanFrequency")).value_or(defaults(S1Parameter::autoPanFrequency));
    preset.filterADSRMix = asDouble(field(d, "filterADSRMix")).value_or(defaults(S1Parameter::filterADSRMix));
    preset.glide = asDouble(field(d, "glide")).value_or(defaults(S1Parameter::glide));
    preset.widen = asDouble(field(d, "widen")).value_or(defaults(S1Parameter::widen));
    preset.attackDuration = asDouble(field(d, "attackDuration")).value_or(defaults(S1Parameter::attackDuration));
    preset.decayDuration = asDouble(field(d, "decayDuration")).value_or(defaults(S1Parameter::decayDuration));
    preset.sustainLevel = asDouble(field(d, "sustainLevel")).value_or(defaults(S1Parameter::sustainLevel));
    preset.releaseDuration = asDouble(field(d, "releaseDuration")).value_or(defaults(S1Parameter::releaseDuration));
    preset.filterAttack = asDouble(field(d, "filterAttack")).value_or(defaults(S1Parameter::filterAttackDuration));
    preset.filterDecay = asDouble(field(d, "filterDecay")).value_or(defaults(S1Parameter::filterDecayDuration));
    preset.filterSustain = asDouble(field(d, "filterSustain")).value_or(defaults(S1Parameter::filterSustainLevel));
    preset.filterRelease = asDouble(field(d, "filterRelease")).value_or(defaults(S1Parameter::filterReleaseDuration));
    preset.delayToggled = asDouble(field(d, "delayToggled")).value_or(defaults(S1Parameter::delayOn));
    preset.reverbToggled = asDouble(field(d, "reverbToggled")).value_or(defaults(S1Parameter::reverbOn));
    preset.autoPanAmount = asDouble(field(d, "autoPanAmount")).value_or(defaults(S1Parameter::autoPanAmount));
    preset.subOsc24Toggled = asDouble(field(d, "subOsc24Toggled")).value_or(defaults(S1Parameter::subOctaveDown));
    preset.subOscSquareToggled = asDouble(field(d, "subOscSquareToggled")).value_or(defaults(S1Parameter::subIsSquare));
    preset.waveform1 = asDouble(field(d, "waveform1")).value_or(defaults(S1Parameter::index1));
    preset.waveform2 = asDouble(field(d, "waveform2")).value_or(defaults(S1Parameter::index2));
    preset.lfoWaveform = asDouble(field(d, "lfoWaveform")).value_or(defaults(S1Parameter::lfo1Index));
    preset.lfoAmplitude = asDouble(field(d, "lfoAmplitude")).value_or(defaults(S1Parameter::lfo1Amplitude));
    preset.lfoRate = asDouble(field(d, "lfoRate")).value_or(defaults(S1Parameter::lfo1Rate));
    preset.lfo2Waveform = asDouble(field(d, "lfo2Waveform")).value_or(defaults(S1Parameter::lfo2Index));
    preset.lfo2Amplitude = asDouble(field(d, "lfo2Amplitude")).value_or(defaults(S1Parameter::lfo2Amplitude));
    preset.lfo2Rate = asDouble(field(d, "lfo2Rate")).value_or(defaults(S1Parameter::lfo2Rate));
    { std::array<int, 16> fallback{}; for (int i = 0; i < 16; ++i) fallback[size_t(i)] = int(defaults(S1Parameter(S1Parameter::sequencerPattern00 + i)));
      preset.seqPatternNote = asArrayN<int, 16>(field(d, "seqPatternNote"), intArray).value_or(fallback); }
    { std::array<bool, 16> fallback{}; for (int i = 0; i < 16; ++i) fallback[size_t(i)] = defaults(S1Parameter(S1Parameter::sequencerNoteOn00 + i)) > 0;
      preset.seqNoteOn = asArrayN<bool, 16>(field(d, "seqNoteOn"), boolArray).value_or(fallback); }
    { std::array<bool, 16> fallback{}; for (int i = 0; i < 16; ++i) fallback[size_t(i)] = defaults(S1Parameter(S1Parameter::sequencerOctBoost00 + i)) > 0;
      preset.seqOctBoost = asArrayN<bool, 16>(field(d, "seqOctBoost"), boolArray).value_or(fallback); }
    preset.arpDirection = asDouble(field(d, "arpDirection")).value_or(defaults(S1Parameter::arpDirection));
    preset.arpInterval = asDouble(field(d, "arpInterval")).value_or(defaults(S1Parameter::arpInterval));
    preset.arpOctave = asDouble(field(d, "arpOctave")).value_or(defaults(S1Parameter::arpOctave));
    preset.arpRate = asDouble(field(d, "arpRate")).value_or(defaults(S1Parameter::arpRate));
    preset.arpIsSequencer = asBool(field(d, "arpIsSequencer")).value_or((defaults(S1Parameter::arpIsSequencer) > 0));
    preset.arpTotalSteps = asDouble(field(d, "arpTotalSteps")).value_or(defaults(S1Parameter::arpTotalSteps));
    preset.arpSeqTempoMultiplier = asDouble(field(d, "arpSeqTempoMultiplier")).value_or(defaults(S1Parameter::arpSeqTempoMultiplier));
    preset.transpose = asInt(field(d, "transpose")).value_or(int(defaults(S1Parameter::transpose)));
    preset.adsrPitchTracking = asDouble(field(d, "adsrPitchTracking")).value_or(defaults(S1Parameter::adsrPitchTracking));
    preset.author = asString(field(d, "author")).value_or(preset.author);
    preset.category = asInt(field(d, "category")).value_or(preset.category);
    preset.isUser = asBool(field(d, "isUser")).value_or(preset.isUser);
    preset.isFavorite = asBool(field(d, "isFavorite")).value_or(preset.isFavorite);
    preset.userText = asString(field(d, "userText")).value_or(preset.userText);
    preset.cutoffLFO = asDouble(field(d, "cutoffLFO")).value_or(defaults(S1Parameter::cutoffLFO));
    preset.resonanceLFO = asDouble(field(d, "resonanceLFO")).value_or(defaults(S1Parameter::resonanceLFO));
    preset.oscMixLFO = asDouble(field(d, "oscMixLFO")).value_or(defaults(S1Parameter::oscMixLFO));
    preset.reverbMixLFO = asDouble(field(d, "reverbMixLFO")).value_or(defaults(S1Parameter::reverbMixLFO));
    preset.decayLFO = asDouble(field(d, "decayLFO")).value_or(defaults(S1Parameter::decayLFO));
    preset.noiseLFO = asDouble(field(d, "noiseLFO")).value_or(defaults(S1Parameter::noiseLFO));
    preset.fmLFO = asDouble(field(d, "fmLFO")).value_or(defaults(S1Parameter::fmLFO));
    preset.detuneLFO = asDouble(field(d, "detuneLFO")).value_or(defaults(S1Parameter::detuneLFO));
    preset.filterEnvLFO = asDouble(field(d, "filterEnvLFO")).value_or(defaults(S1Parameter::filterEnvLFO));
    preset.pitchLFO = asDouble(field(d, "pitchLFO")).value_or(defaults(S1Parameter::pitchLFO));
    preset.bitcrushLFO = asDouble(field(d, "bitcrushLFO")).value_or(defaults(S1Parameter::bitcrushLFO));
    preset.tremoloLFO = asDouble(field(d, "tremoloLFO")).value_or(defaults(S1Parameter::tremoloLFO));
    preset.modWheelRouting = asDouble(field(d, "modWheelRouting")).value_or(preset.modWheelRouting);
    preset.pitchbendMaxSemitones = asDouble(field(d, "pitchbendMaxSemitones")).value_or(defaults(S1Parameter::pitchbendMaxSemitones));
    preset.pitchbendMinSemitones = asDouble(field(d, "pitchbendMinSemitones")).value_or(defaults(S1Parameter::pitchbendMinSemitones));
    preset.phaserFeedback = asDouble(field(d, "phaserFeedback")).value_or(defaults(S1Parameter::phaserFeedback));
    preset.phaserMix = asDouble(field(d, "phaserMix")).value_or(defaults(S1Parameter::phaserMix));
    preset.phaserRate = asDouble(field(d, "phaserRate")).value_or(defaults(S1Parameter::phaserRate));
    preset.phaserNotchWidth = asDouble(field(d, "phaserNotchWidth")).value_or(defaults(S1Parameter::phaserNotchWidth));
    preset.compressorMasterRatio = asDouble(field(d, "compressorMasterRatio")).value_or(defaults(S1Parameter::compressorMasterRatio));
    preset.compressorReverbInputRatio = asDouble(field(d, "compressorReverbInputRatio")).value_or(defaults(S1Parameter::compressorReverbInputRatio));
    preset.compressorReverbWetRatio = asDouble(field(d, "compressorReverbWetRatio")).value_or(defaults(S1Parameter::compressorReverbWetRatio));
    preset.compressorMasterThreshold = asDouble(field(d, "compressorMasterThreshold")).value_or(defaults(S1Parameter::compressorMasterThreshold));
    preset.compressorReverbInputThreshold = asDouble(field(d, "compressorReverbInputThreshold")).value_or(defaults(S1Parameter::compressorReverbInputThreshold));
    preset.compressorReverbWetThreshold = asDouble(field(d, "compressorReverbWetThreshold")).value_or(defaults(S1Parameter::compressorReverbWetThreshold));
    preset.compressorMasterAttack = asDouble(field(d, "compressorMasterAttack")).value_or(defaults(S1Parameter::compressorMasterAttack));
    preset.compressorReverbInputAttack = asDouble(field(d, "compressorReverbInputAttack")).value_or(defaults(S1Parameter::compressorReverbInputAttack));
    preset.compressorReverbWetAttack = asDouble(field(d, "compressorReverbWetAttack")).value_or(defaults(S1Parameter::compressorReverbWetAttack));
    preset.compressorMasterRelease = asDouble(field(d, "compressorMasterRelease")).value_or(defaults(S1Parameter::compressorMasterRelease));
    preset.compressorReverbInputRelease = asDouble(field(d, "compressorReverbInputRelease")).value_or(defaults(S1Parameter::compressorReverbInputRelease));
    preset.compressorReverbWetRelease = asDouble(field(d, "compressorReverbWetRelease")).value_or(defaults(S1Parameter::compressorReverbWetRelease));
    preset.compressorMasterMakeupGain = asDouble(field(d, "compressorMasterMakeupGain")).value_or(defaults(S1Parameter::compressorMasterMakeupGain));
    preset.compressorReverbInputMakeupGain = asDouble(field(d, "compressorReverbInputMakeupGain")).value_or(defaults(S1Parameter::compressorReverbInputMakeupGain));
    preset.compressorReverbWetMakeupGain = asDouble(field(d, "compressorReverbWetMakeupGain")).value_or(defaults(S1Parameter::compressorReverbWetMakeupGain));
    preset.delayInputCutoffTrackingRatio = asDouble(field(d, "delayInputCutoffTrackingRatio")).value_or(defaults(S1Parameter::delayInputCutoffTrackingRatio));
    preset.delayInputResonance = asDouble(field(d, "delayInputResonance")).value_or(defaults(S1Parameter::delayInputResonance));
    preset.oscBandlimitEnable = asDouble(field(d, "oscBandlimitEnable")).value_or(defaults(S1Parameter::oscBandlimitEnable));
    preset.frequencyA4 = asDouble(field(d, "frequencyA4")).value_or(defaults(S1Parameter::frequencyA4));
    preset.tuningName = asString(field(d, "tuningName"));
    preset.tuningMasterSet = doubleArray(field(d, "tuningMasterSet"));
    return preset;
}

std::vector<Preset> Preset::bankFromJSON(const json &array, const PresetDefaults &defaults) {
    std::vector<Preset> presets;
    if (!array.is_array()) return presets;
    for (const json &item : array) { if (item.is_object()) presets.push_back(fromJSON(item, defaults)); }
    return presets;
}

json Preset::toJSON() const {
    json j = json::object();
    j["uid"] = uid;
    j["position"] = position;
    j["name"] = name;
    j["bank"] = bank;
    j["octavePosition"] = octavePosition;
    j["isMono"] = isMono;
    j["isHoldMode"] = isHoldMode;
    j["isArpMode"] = isArpMode;
    j["isLegato"] = isLegato;
    j["tempoSyncToArpRate"] = tempoSyncToArpRate;
    j["masterVolume"] = masterVolume;
    j["vco1Volume"] = vco1Volume;
    j["vco2Volume"] = vco2Volume;
    j["vco1Semitone"] = vco1Semitone;
    j["vco2Semitone"] = vco2Semitone;
    j["vco2Detuning"] = vco2Detuning;
    j["vcoBalance"] = vcoBalance;
    j["subVolume"] = subVolume;
    j["fmVolume"] = fmVolume;
    j["fmAmount"] = fmAmount;
    j["noiseVolume"] = noiseVolume;
    j["cutoff"] = cutoff;
    j["resonance"] = resonance;
    j["filterType"] = filterType;
    j["delayTime"] = delayTime;
    j["delayMix"] = delayMix;
    j["delayFeedback"] = delayFeedback;
    j["reverbFeedback"] = reverbFeedback;
    j["reverbMix"] = reverbMix;
    j["reverbHighPass"] = reverbHighPass;
    j["midiBendRange"] = midiBendRange;
    j["crushFreq"] = crushFreq;
    j["autoPanAmount"] = autoPanAmount;
    j["autoPanFrequency"] = autoPanFrequency;
    j["filterADSRMix"] = filterADSRMix;
    j["glide"] = glide;
    j["widen"] = widen;
    j["phaserMix"] = phaserMix;
    j["phaserRate"] = phaserRate;
    j["phaserFeedback"] = phaserFeedback;
    j["phaserNotchWidth"] = phaserNotchWidth;
    j["attackDuration"] = attackDuration;
    j["decayDuration"] = decayDuration;
    j["sustainLevel"] = sustainLevel;
    j["releaseDuration"] = releaseDuration;
    j["filterAttack"] = filterAttack;
    j["filterDecay"] = filterDecay;
    j["filterSustain"] = filterSustain;
    j["filterRelease"] = filterRelease;
    j["delayToggled"] = delayToggled;
    j["reverbToggled"] = reverbToggled;
    j["subOsc24Toggled"] = subOsc24Toggled;
    j["subOscSquareToggled"] = subOscSquareToggled;
    j["waveform1"] = waveform1;
    j["waveform2"] = waveform2;
    j["lfoWaveform"] = lfoWaveform;
    j["lfoAmplitude"] = lfoAmplitude;
    j["lfoRate"] = lfoRate;
    j["lfo2Waveform"] = lfo2Waveform;
    j["lfo2Amplitude"] = lfo2Amplitude;
    j["lfo2Rate"] = lfo2Rate;
    j["seqPatternNote"] = std::vector<int>(seqPatternNote.begin(), seqPatternNote.end());
    j["seqOctBoost"] = std::vector<bool>(seqOctBoost.begin(), seqOctBoost.end());
    j["seqNoteOn"] = std::vector<bool>(seqNoteOn.begin(), seqNoteOn.end());
    j["arpDirection"] = arpDirection;
    j["arpInterval"] = arpInterval;
    j["arpOctave"] = arpOctave;
    j["arpRate"] = arpRate;
    j["arpIsSequencer"] = arpIsSequencer;
    j["arpTotalSteps"] = arpTotalSteps;
    j["arpSeqTempoMultiplier"] = arpSeqTempoMultiplier;
    j["transpose"] = transpose;
    j["adsrPitchTracking"] = adsrPitchTracking;
    j["author"] = author;
    j["category"] = category;
    j["isUser"] = isUser;
    j["isFavorite"] = isFavorite;
    j["userText"] = userText;
    j["cutoffLFO"] = cutoffLFO;
    j["resonanceLFO"] = resonanceLFO;
    j["oscMixLFO"] = oscMixLFO;
    j["reverbMixLFO"] = reverbMixLFO;
    j["decayLFO"] = decayLFO;
    j["noiseLFO"] = noiseLFO;
    j["fmLFO"] = fmLFO;
    j["detuneLFO"] = detuneLFO;
    j["filterEnvLFO"] = filterEnvLFO;
    j["pitchLFO"] = pitchLFO;
    j["bitcrushLFO"] = bitcrushLFO;
    j["tremoloLFO"] = tremoloLFO;
    j["modWheelRouting"] = modWheelRouting;
    j["pitchbendMinSemitones"] = pitchbendMinSemitones;
    j["pitchbendMaxSemitones"] = pitchbendMaxSemitones;
    j["compressorMasterRatio"] = compressorMasterRatio;
    j["compressorReverbInputRatio"] = compressorReverbInputRatio;
    j["compressorReverbWetRatio"] = compressorReverbWetRatio;
    j["compressorMasterThreshold"] = compressorMasterThreshold;
    j["compressorReverbInputThreshold"] = compressorReverbInputThreshold;
    j["compressorReverbWetThreshold"] = compressorReverbWetThreshold;
    j["compressorMasterAttack"] = compressorMasterAttack;
    j["compressorReverbInputAttack"] = compressorReverbInputAttack;
    j["compressorReverbWetAttack"] = compressorReverbWetAttack;
    j["compressorMasterRelease"] = compressorMasterRelease;
    j["compressorReverbInputRelease"] = compressorReverbInputRelease;
    j["compressorReverbWetRelease"] = compressorReverbWetRelease;
    j["compressorMasterMakeupGain"] = compressorMasterMakeupGain;
    j["compressorReverbInputMakeupGain"] = compressorReverbInputMakeupGain;
    j["compressorReverbWetMakeupGain"] = compressorReverbWetMakeupGain;
    j["delayInputCutoffTrackingRatio"] = delayInputCutoffTrackingRatio;
    j["delayInputResonance"] = delayInputResonance;
    j["oscBandlimitEnable"] = oscBandlimitEnable;
    j["frequencyA4"] = frequencyA4;
    if (tuningName) j["tuningName"] = *tuningName;
    if (tuningMasterSet) j["tuningMasterSet"] = *tuningMasterSet;
    return j;
}

void Preset::apply(S1DSPKernel &kernel) const {
    // Transcribed from Preset+Synth.swift, in upstream's order. Swift passed Float(value).
    // ADR-082: a preset's own `arpRate`, written among its other values, is not a tempo CHANGE —
    // upstream's re-quantising is what reads the preset's times back as the notes they were
    // saved as — so the switch is off while it is applied, whatever the kernel's owner has set.
    struct KeepSwitchOff {
        S1DSPKernel &kernel; const bool was;
        explicit KeepSwitchOff(S1DSPKernel &k) : kernel(k), was(k.tempoParameterKeepsNoteValues) { kernel.tempoParameterKeepsNoteValues = false; }
        ~KeepSwitchOff() { kernel.tempoParameterKeepsNoteValues = was; }
    } keepSwitchOff(kernel);
    auto set = [&kernel](S1Parameter p, double v) { kernel.setSynthParameter(p, float(v)); };
    set(S1Parameter::delayOn, delayToggled);
    set(S1Parameter::delayFeedback, delayFeedback);
    set(S1Parameter::delayMix, delayMix);
    set(S1Parameter::delayTime, delayTime);
    set(S1Parameter::delayInputCutoffTrackingRatio, delayInputCutoffTrackingRatio);
    set(S1Parameter::delayInputResonance, delayInputResonance);
    set(S1Parameter::reverbOn, reverbToggled);
    set(S1Parameter::reverbFeedback, reverbFeedback);
    set(S1Parameter::reverbHighPass, reverbHighPass);
    set(S1Parameter::reverbMix, reverbMix);
    set(S1Parameter::compressorReverbInputRatio, compressorReverbInputRatio);
    set(S1Parameter::compressorReverbWetRatio, compressorReverbWetRatio);
    set(S1Parameter::compressorReverbInputThreshold, compressorReverbInputThreshold);
    set(S1Parameter::compressorReverbWetThreshold, compressorReverbWetThreshold);
    set(S1Parameter::compressorReverbInputAttack, compressorReverbInputAttack);
    set(S1Parameter::compressorReverbWetAttack, compressorReverbWetAttack);
    set(S1Parameter::compressorReverbInputRelease, compressorReverbInputRelease);
    set(S1Parameter::compressorReverbWetRelease, compressorReverbWetRelease);
    set(S1Parameter::compressorReverbInputMakeupGain, compressorReverbInputMakeupGain);
    set(S1Parameter::compressorReverbWetMakeupGain, compressorReverbWetMakeupGain);
    set(S1Parameter::arpRate, arpRate);
    set(S1Parameter::arpIsOn, isArpMode);
    set(S1Parameter::arpIsSequencer, (arpIsSequencer ? 1 : 0));
    set(S1Parameter::arpDirection, arpDirection);
    set(S1Parameter::arpInterval, arpInterval);
    set(S1Parameter::arpOctave, arpOctave);
    set(S1Parameter::arpTotalSteps, arpTotalSteps);
    set(S1Parameter::arpSeqTempoMultiplier, arpSeqTempoMultiplier);
    for (int i = 0; i < 16; ++i) {
        set(S1Parameter(S1Parameter::sequencerPattern00 + i), double(seqPatternNote[size_t(i)]));   // setPattern(forIndex:)
        set(S1Parameter(S1Parameter::sequencerOctBoost00 + i), seqOctBoost[size_t(i)] ? 1 : 0);     // setOctaveBoost(forIndex:)
        set(S1Parameter(S1Parameter::sequencerNoteOn00 + i), seqNoteOn[size_t(i)] ? 1 : 0);          // setNoteOn(forIndex:)
    }
    set(S1Parameter::tempoSyncToArpRate, tempoSyncToArpRate);
    set(S1Parameter::lfo1Rate, lfoRate);
    set(S1Parameter::lfo2Rate, lfo2Rate);
    set(S1Parameter::autoPanFrequency, autoPanFrequency);
    set(S1Parameter::masterVolume, masterVolume);
    set(S1Parameter::isMono, isMono);
    set(S1Parameter::glide, glide);
    set(S1Parameter::widen, widen);
    set(S1Parameter::index1, waveform1);
    set(S1Parameter::index2, waveform2);
    set(S1Parameter::morph1SemitoneOffset, vco1Semitone);
    set(S1Parameter::morph2SemitoneOffset, vco2Semitone);
    set(S1Parameter::morph2Detuning, vco2Detuning);
    set(S1Parameter::morph1Volume, vco1Volume);
    set(S1Parameter::morph2Volume, vco2Volume);
    set(S1Parameter::morphBalance, vcoBalance);
    set(S1Parameter::subVolume, subVolume);
    set(S1Parameter::subOctaveDown, subOsc24Toggled);
    set(S1Parameter::subIsSquare, subOscSquareToggled);
    set(S1Parameter::fmVolume, fmVolume);
    set(S1Parameter::fmAmount, fmAmount);
    set(S1Parameter::noiseVolume, noiseVolume);
    set(S1Parameter::cutoff, cutoff);
    set(S1Parameter::resonance, resonance);
    set(S1Parameter::filterADSRMix, filterADSRMix);
    set(S1Parameter::filterAttackDuration, filterAttack);
    set(S1Parameter::filterDecayDuration, filterDecay);
    set(S1Parameter::filterSustainLevel, filterSustain);
    set(S1Parameter::filterReleaseDuration, filterRelease);
    set(S1Parameter::attackDuration, attackDuration);
    set(S1Parameter::decayDuration, decayDuration);
    set(S1Parameter::sustainLevel, sustainLevel);
    set(S1Parameter::releaseDuration, releaseDuration);
    set(S1Parameter::bitCrushSampleRate, crushFreq);
    set(S1Parameter::autoPanAmount, autoPanAmount);
    set(S1Parameter::lfo1Index, lfoWaveform);
    set(S1Parameter::lfo1Amplitude, lfoAmplitude);
    set(S1Parameter::lfo2Index, lfo2Waveform);
    set(S1Parameter::lfo2Amplitude, lfo2Amplitude);
    set(S1Parameter::cutoffLFO, cutoffLFO);
    set(S1Parameter::resonanceLFO, resonanceLFO);
    set(S1Parameter::oscMixLFO, oscMixLFO);
    set(S1Parameter::reverbMixLFO, reverbMixLFO);
    set(S1Parameter::decayLFO, decayLFO);
    set(S1Parameter::noiseLFO, noiseLFO);
    set(S1Parameter::fmLFO, fmLFO);
    set(S1Parameter::detuneLFO, detuneLFO);
    set(S1Parameter::filterEnvLFO, filterEnvLFO);
    set(S1Parameter::pitchLFO, pitchLFO);
    set(S1Parameter::bitcrushLFO, bitcrushLFO);
    set(S1Parameter::tremoloLFO, tremoloLFO);
    set(S1Parameter::monoIsLegato, isLegato);
    set(S1Parameter::phaserMix, phaserMix);
    set(S1Parameter::phaserRate, phaserRate);
    set(S1Parameter::phaserFeedback, phaserFeedback);
    set(S1Parameter::phaserNotchWidth, phaserNotchWidth);
    set(S1Parameter::filterType, filterType);
    set(S1Parameter::compressorMasterThreshold, compressorMasterThreshold);
    set(S1Parameter::compressorMasterRatio, compressorMasterRatio);
    set(S1Parameter::compressorMasterAttack, compressorMasterAttack);
    set(S1Parameter::compressorMasterRelease, compressorMasterRelease);
    set(S1Parameter::compressorMasterMakeupGain, compressorMasterMakeupGain);
    set(S1Parameter::pitchbendMinSemitones, pitchbendMinSemitones);
    set(S1Parameter::pitchbendMaxSemitones, pitchbendMaxSemitones);
    set(S1Parameter::frequencyA4, frequencyA4);
    set(S1Parameter::oscBandlimitEnable, oscBandlimitEnable);
    set(S1Parameter::transpose, double(transpose));
    set(S1Parameter::adsrPitchTracking, adsrPitchTracking);
    kernel.resetSequencer();
}

void Preset::capture(S1DSPKernel &kernel) {
    // getSynthParameter returned Double(Float).
    capture([&kernel](S1Parameter p) { return double(kernel.getSynthParameter(p)); });
}

void Preset::capture(const ParameterGetter &get) {
    // Transcribed from PresetDataManager.saveValuesToPreset.
    arpRate = get(S1Parameter::arpRate);
    delayToggled = get(S1Parameter::delayOn);
    delayFeedback = get(S1Parameter::delayFeedback);
    delayTime = get(S1Parameter::delayTime);
    delayMix = get(S1Parameter::delayMix);
    reverbToggled = get(S1Parameter::reverbOn);
    reverbFeedback = get(S1Parameter::reverbFeedback);
    reverbHighPass = get(S1Parameter::reverbHighPass);
    reverbMix = get(S1Parameter::reverbMix);
    tempoSyncToArpRate = get(S1Parameter::tempoSyncToArpRate);
    masterVolume = get(S1Parameter::masterVolume);
    isMono = get(S1Parameter::isMono);
    isLegato = get(S1Parameter::monoIsLegato);
    glide = get(S1Parameter::glide);
    widen = get(S1Parameter::widen) < 1 ? 0 : 1;
    waveform1 = get(S1Parameter::index1);
    waveform2 = get(S1Parameter::index2);
    vco1Semitone = get(S1Parameter::morph1SemitoneOffset);
    vco2Semitone = get(S1Parameter::morph2SemitoneOffset);
    vco2Detuning = get(S1Parameter::morph2Detuning);
    vco1Volume = get(S1Parameter::morph1Volume);
    vco2Volume = get(S1Parameter::morph2Volume);
    vcoBalance = get(S1Parameter::morphBalance);
    subVolume = get(S1Parameter::subVolume);
    subOsc24Toggled = get(S1Parameter::subOctaveDown);
    subOscSquareToggled = get(S1Parameter::subIsSquare);
    fmVolume = get(S1Parameter::fmVolume);
    fmAmount = get(S1Parameter::fmAmount);
    noiseVolume = get(S1Parameter::noiseVolume);
    cutoff = get(S1Parameter::cutoff);
    resonance = get(S1Parameter::resonance);
    filterADSRMix = get(S1Parameter::filterADSRMix);
    filterAttack = get(S1Parameter::filterAttackDuration);
    filterDecay = get(S1Parameter::filterDecayDuration);
    filterSustain = get(S1Parameter::filterSustainLevel);
    filterRelease = get(S1Parameter::filterReleaseDuration);
    attackDuration = get(S1Parameter::attackDuration);
    decayDuration = get(S1Parameter::decayDuration);
    sustainLevel = get(S1Parameter::sustainLevel);
    releaseDuration = get(S1Parameter::releaseDuration);
    crushFreq = get(S1Parameter::bitCrushSampleRate);
    autoPanAmount = get(S1Parameter::autoPanAmount);
    autoPanFrequency = get(S1Parameter::autoPanFrequency);
    reverbToggled = get(S1Parameter::reverbOn);
    reverbFeedback = get(S1Parameter::reverbFeedback);
    reverbHighPass = get(S1Parameter::reverbHighPass);
    reverbMix = get(S1Parameter::reverbMix);
    delayToggled = get(S1Parameter::delayOn);
    delayFeedback = get(S1Parameter::delayFeedback);
    delayTime = get(S1Parameter::delayTime);
    delayMix = get(S1Parameter::delayMix);
    lfoWaveform = get(S1Parameter::lfo1Index);
    lfoAmplitude = get(S1Parameter::lfo1Amplitude);
    lfoRate = get(S1Parameter::lfo1Rate);
    lfo2Waveform = get(S1Parameter::lfo2Index);
    lfo2Amplitude = get(S1Parameter::lfo2Amplitude);
    lfo2Rate = get(S1Parameter::lfo2Rate);
    cutoffLFO = get(S1Parameter::cutoffLFO);
    resonanceLFO = get(S1Parameter::resonanceLFO);
    oscMixLFO = get(S1Parameter::oscMixLFO);
    reverbMixLFO = get(S1Parameter::reverbMixLFO);
    decayLFO = get(S1Parameter::decayLFO);
    noiseLFO = get(S1Parameter::noiseLFO);
    fmLFO = get(S1Parameter::fmLFO);
    detuneLFO = get(S1Parameter::detuneLFO);
    filterEnvLFO = get(S1Parameter::filterEnvLFO);
    pitchLFO = get(S1Parameter::pitchLFO);
    bitcrushLFO = get(S1Parameter::bitcrushLFO);
    tremoloLFO = get(S1Parameter::tremoloLFO);
    arpDirection = get(S1Parameter::arpDirection);
    arpInterval = get(S1Parameter::arpInterval);
    arpOctave = get(S1Parameter::arpOctave);
    arpIsSequencer = get(S1Parameter::arpIsSequencer) > 0 ? true : false;
    arpTotalSteps = get(S1Parameter::arpTotalSteps);
    isArpMode = get(S1Parameter::arpIsOn);
    phaserMix = get(S1Parameter::phaserMix);
    phaserRate = get(S1Parameter::phaserRate);
    phaserFeedback = get(S1Parameter::phaserFeedback);
    phaserNotchWidth = get(S1Parameter::phaserNotchWidth);
    for (int i = 0; i < 16; ++i) {
        seqPatternNote[size_t(i)] = int(get(S1Parameter(S1Parameter::sequencerPattern00 + i)));   // getPattern(forIndex:)
        seqOctBoost[size_t(i)] = get(S1Parameter(S1Parameter::sequencerOctBoost00 + i)) > 0;     // getOctaveBoost(forIndex:)
        seqNoteOn[size_t(i)] = get(S1Parameter(S1Parameter::sequencerNoteOn00 + i)) > 0;          // isNoteOn(forIndex:)
    }
    filterType = get(S1Parameter::filterType);
    compressorMasterRatio = get(S1Parameter::compressorMasterRatio);
    compressorReverbInputRatio = get(S1Parameter::compressorReverbInputRatio);
    compressorReverbWetRatio = get(S1Parameter::compressorReverbWetRatio);
    compressorMasterThreshold = get(S1Parameter::compressorMasterThreshold);
    compressorReverbInputThreshold = get(S1Parameter::compressorReverbInputThreshold);
    compressorReverbWetThreshold = get(S1Parameter::compressorReverbWetThreshold);
    compressorMasterAttack = get(S1Parameter::compressorMasterAttack);
    compressorReverbInputAttack = get(S1Parameter::compressorReverbInputAttack);
    compressorReverbWetAttack = get(S1Parameter::compressorReverbWetAttack);
    compressorMasterRelease = get(S1Parameter::compressorMasterRelease);
    compressorReverbInputRelease = get(S1Parameter::compressorReverbInputRelease);
    compressorReverbWetRelease = get(S1Parameter::compressorReverbWetRelease);
    compressorMasterMakeupGain = get(S1Parameter::compressorMasterMakeupGain);
    compressorReverbInputMakeupGain = get(S1Parameter::compressorReverbInputMakeupGain);
    compressorReverbWetMakeupGain = get(S1Parameter::compressorReverbWetMakeupGain);
    delayInputCutoffTrackingRatio = get(S1Parameter::delayInputCutoffTrackingRatio);
    delayInputResonance = get(S1Parameter::delayInputResonance);
    pitchbendMinSemitones = get(S1Parameter::pitchbendMinSemitones);
    pitchbendMaxSemitones = get(S1Parameter::pitchbendMaxSemitones);
    oscBandlimitEnable = get(S1Parameter::oscBandlimitEnable);
    arpSeqTempoMultiplier = get(S1Parameter::arpSeqTempoMultiplier);
    transpose = int(get(S1Parameter::transpose));
    adsrPitchTracking = get(S1Parameter::adsrPitchTracking);
    frequencyA4 = get(S1Parameter::frequencyA4);
}

std::string Preset::newUID() {
    static std::random_device device;
    static std::mt19937_64 engine(device());
    std::uniform_int_distribution<uint64_t> bits;
    uint64_t hi = bits(engine), lo = bits(engine);
    hi = (hi & 0xFFFFFFFFFFFF0FFFull) | 0x0000000000004000ull;   // version 4
    lo = (lo & 0x3FFFFFFFFFFFFFFFull) | 0x8000000000000000ull;   // variant 1
    char out[37];
    std::snprintf(out, sizeof out, "%08X-%04X-%04X-%04X-%012llX",
                  unsigned(hi >> 32), unsigned((hi >> 16) & 0xFFFF), unsigned(hi & 0xFFFF),
                  unsigned(lo >> 48), (unsigned long long)(lo & 0xFFFFFFFFFFFFull));
    return out;
}

}  // namespace s1
