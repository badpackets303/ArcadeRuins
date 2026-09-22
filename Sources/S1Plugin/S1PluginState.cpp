//
//  S1PluginState.cpp
//  Arcade Ruins
//
//  X2-5 (ADR-076). See the header for the format and its rules.
//

#include "S1PluginState.hpp"

#include <algorithm>
#include <cmath>

#include "S1DSPKernel.hpp"
#include "S1ParameterCatalog.hpp"
#include "../S1Engine/third_party/nlohmann/json.hpp"

namespace s1plugin {

namespace {

constexpr int kCount = S1Parameter::S1ParameterCount;

bool isWheelPosition(int address) { return address == int(S1Parameter::pitchbend); }

/// The preset's fields from the parameters, plus the sequencer rows `Preset::capture` leaves to
/// the Mac's interface.
void captureInto(s1::Preset &preset, const std::array<float, kCount> &parameters) {
    preset.capture([&parameters](S1Parameter p) { return double(parameters[size_t(p)]); });
    for (int i = 0; i < 16; ++i) {
        preset.seqPatternNote[size_t(i)] = int(std::lround(parameters[size_t(S1Parameter::sequencerPattern00 + i)]));
        preset.seqOctBoost[size_t(i)] = parameters[size_t(S1Parameter::sequencerOctBoost00 + i)] >= 0.5f;
        preset.seqNoteOn[size_t(i)] = parameters[size_t(S1Parameter::sequencerNoteOn00 + i)] >= 0.5f;
    }
}

} // namespace

s1::Preset PluginState::capturedPreset() const {
    s1::Preset captured = preset;
    captureInto(captured, parameters);
    return captured;
}

std::string PluginState::toJSON(const std::string &pluginVersion) const {
    nlohmann::json root;
    root["format"] = formatName;
    root["version"] = currentVersion;
    root["plugin"] = pluginVersion;

    nlohmann::json values = nlohmann::json::object();
    for (int i = 0; i < kCount; ++i) {
        if (!isWheelPosition(i)) { values[parameterID(i)] = double(parameters[size_t(i)]); }   // float -> double is exact
    }
    root["parameters"] = std::move(values);

    root["preset"] = capturedPreset().toJSON();

    nlohmann::json frequencies = nlohmann::json::array();
    for (float frequency : tuningFrequencies) { frequencies.push_back(double(frequency)); }
    root["tuning"] = {{"notesPerOctave", tuningNotesPerOctave}, {"frequencies", std::move(frequencies)}};

    root["midi"] = {{"octaveShift", midi.octaveShift}, {"channel", midi.channel}, {"omni", midi.omni},
                    {"whiteKeysOnly", midi.whiteKeysOnly}, {"hold", midi.hold}};
    root["window"] = {{"keyboardShown", window.keyboardShown}};
    return root.dump(1);
}

std::optional<PluginState> PluginState::fromJSON(const std::string &text, const PluginState &current,
                                                 const std::array<float, kCount> &minimum,
                                                 const std::array<float, kCount> &maximum,
                                                 const s1::PresetDefaults &defaults) {
    const nlohmann::json root = nlohmann::json::parse(text, nullptr, false);
    if (root.is_discarded() || !root.is_object()) { return std::nullopt; }
    const auto format = root.find("format");
    if (format == root.end() || !format->is_string() || format->get<std::string>() != formatName) { return std::nullopt; }

    PluginState state = current;
    auto store = [&](S1Parameter p, double value) {
        if (!std::isfinite(value)) { return; }
        const size_t i = size_t(p);
        state.parameters[i] = std::clamp(float(value), minimum[i], maximum[i]);
    };

    const auto values = root.find("parameters");
    bool everyParameterIsNamed = values != root.end() && values->is_object();
    for (int i = 0; everyParameterIsNamed && i < kCount; ++i) {
        everyParameterIsNamed = isWheelPosition(i) || values->contains(parameterID(i));
    }
    if (const auto preset = root.find("preset"); preset != root.end() && preset->is_object()) {
        state.preset = s1::Preset::fromJSON(*preset, defaults);
        if (!everyParameterIsNamed) {
            // The sound has to come from the preset — a bank file's JSON, or a state from a build
            // with fewer parameters. What a preset's fields make of the 150 values is decided by
            // upstream's apply ORDER, not by the fields alone: `delayTime` is written while the
            // previous sync setting still stands and is quantised to a note value by it, before the
            // preset's own switch arrives. So the preset is applied, in that order, to a kernel of
            // this function's own — new, as the goldens' kernels are — and the values read back.
            // (Never the rendering kernel: this is not the audio thread.)
            S1DSPKernel scratch(2, 44100.0);
            state.preset.apply(scratch);
            for (int i = 0; i < kCount; ++i) { store(S1Parameter(i), double(scratch.getSynthParameter(S1Parameter(i)))); }
        }
    }
    if (values != root.end() && values->is_object()) {
        for (int i = 0; i < kCount; ++i) {
            const auto value = values->find(parameterID(i));
            if (value != values->end() && value->is_number()) { store(S1Parameter(i), value->get<double>()); }
        }
    }
    // A wheel's position is not part of a session, whatever the file says.
    state.parameters[size_t(S1Parameter::pitchbend)] = float(defaults(S1Parameter::pitchbend));

    if (const auto tuning = root.find("tuning"); tuning != root.end() && tuning->is_object()) {
        const auto frequencies = tuning->find("frequencies");
        if (frequencies != tuning->end() && frequencies->is_array() && frequencies->size() == state.tuningFrequencies.size()) {
            bool usable = true;
            std::array<float, 128> table {};
            for (size_t i = 0; i < table.size(); ++i) {
                const nlohmann::json &entry = (*frequencies)[i];
                usable = usable && entry.is_number() && std::isfinite(entry.get<double>()) && entry.get<double>() > 0;
                if (usable) { table[i] = float(entry.get<double>()); }
            }
            if (usable) { state.tuningFrequencies = table; }   // all 128 or none: half a temperament is worse than the old one
        }
        if (const auto npo = tuning->find("notesPerOctave"); npo != tuning->end() && npo->is_number_integer()) {
            state.tuningNotesPerOctave = std::clamp(npo->get<int>(), 1, 128);
        }
    }

    if (const auto midiObject = root.find("midi"); midiObject != root.end() && midiObject->is_object()) {
        auto integer = [&](const char *key, int fallback) {
            const auto found = midiObject->find(key);
            return found != midiObject->end() && found->is_number_integer() ? found->get<int>() : fallback;
        };
        auto boolean = [&](const char *key, bool fallback) {
            const auto found = midiObject->find(key);
            return found != midiObject->end() && found->is_boolean() ? found->get<bool>() : fallback;
        };
        state.midi.octaveShift = std::clamp(integer("octaveShift", state.midi.octaveShift), -127, 127);
        state.midi.channel = std::clamp(integer("channel", state.midi.channel), 0, 15);
        state.midi.omni = boolean("omni", state.midi.omni);
        state.midi.whiteKeysOnly = boolean("whiteKeysOnly", state.midi.whiteKeysOnly);
        state.midi.hold = boolean("hold", state.midi.hold);
    }
    // X3-8: an older state has no "window", and then the drawer stays as it is — closed.
    if (const auto windowObject = root.find("window"); windowObject != root.end() && windowObject->is_object()) {
        const auto shown = windowObject->find("keyboardShown");
        if (shown != windowObject->end() && shown->is_boolean()) { state.window.keyboardShown = shown->get<bool>(); }
    }
    return state;
}

} // namespace s1plugin
