//
//  S1Wavetables.cpp
//  Arcade Ruins
//
//  PORT (X1-6, ADR-070): see S1Wavetables.hpp.
//
#include "S1Wavetables.hpp"

#include <filesystem>
#include <fstream>
#include <map>
#include <sstream>
#include <stdexcept>

#include "S1DSPKernel.hpp"
#include "../third_party/nlohmann/json.hpp"

namespace s1 {

namespace {

std::string text(const Wavetables::Source &source, const std::string &name) {
    std::optional<std::string> found = source(name);
    if (!found) {
        throw std::runtime_error(name + ".json is missing from the wavetable resources");
    }
    return *found;
}

/// AKTable's Codable form. JSON numbers are doubles; the table is Float, as in the Swift.
std::vector<float> table(const Wavetables::Source &source, const std::string &name) {
    const nlohmann::json object = nlohmann::json::parse(text(source, name));
    const nlohmann::json &content = object.at("content");
    std::vector<float> samples;
    samples.reserve(content.size());
    for (const nlohmann::json &sample : content) {
        samples.push_back(static_cast<float>(sample.get<double>()));
    }
    return samples;
}

} // namespace

Wavetables Wavetables::load(const Source &source) {
    Wavetables result;
    const nlohmann::json index = nlohmann::json::parse(text(source, "bandlimitedWaveforms"));
    result.names = index.get<std::vector<std::string>>();
    const size_t expected = size_t(waveformCount) * size_t(bandCount);
    if (result.names.size() != expected) {
        throw std::runtime_error("expected " + std::to_string(expected) + " wavetables, found "
                                 + std::to_string(result.names.size()));
    }
    result.waveforms.reserve(expected);
    for (const std::string &name : result.names) {
        result.waveforms.push_back(table(source, name));
        if (result.waveforms.back().size() != size_t(tableSize)) {
            throw std::runtime_error(name + ".json holds " + std::to_string(result.waveforms.back().size())
                                     + " samples, not " + std::to_string(tableSize));
        }
    }
    result.bandlimitFrequencies = table(source, "bandlimitedWaveformFrequencies");
    if (result.bandlimitFrequencies.size() != size_t(bandCount)) {
        throw std::runtime_error("expected " + std::to_string(bandCount) + " band frequencies, found "
                                 + std::to_string(result.bandlimitFrequencies.size()));
    }
    return result;
}

Wavetables Wavetables::loadFromDirectory(const std::string &directory) {
    namespace fs = std::filesystem;
    std::map<std::string, fs::path> byStem;
    std::error_code error;
    for (fs::recursive_directory_iterator it(fs::path(directory), error), end; !error && it != end; it.increment(error)) {
        if (it->is_regular_file() && it->path().extension() == ".json") {
            byStem[it->path().stem().string()] = it->path();
        }
    }
    if (error) {
        throw std::runtime_error("cannot read the wavetable directory " + directory + ": " + error.message());
    }
    return load([&byStem](const std::string &name) -> std::optional<std::string> {
        const auto found = byStem.find(name);
        if (found == byStem.end()) { return std::nullopt; }
        std::ifstream file(found->second, std::ios::binary);
        if (!file) { return std::nullopt; }
        std::ostringstream contents;
        contents << file.rdbuf();
        return contents.str();
    });
}

void Wavetables::apply(S1DSPKernel &kernel) const {
    for (size_t band = 0; band < bandlimitFrequencies.size(); ++band) {
        kernel.setBandlimitFrequency(uint32_t(band), bandlimitFrequencies[band]);
    }
    for (size_t tableIndex = 0; tableIndex < waveforms.size(); ++tableIndex) {
        const std::vector<float> &samples = waveforms[tableIndex];
        kernel.setupWaveform(uint32_t(tableIndex), uint32_t(samples.size()));
        for (size_t sampleIndex = 0; sampleIndex < samples.size(); ++sampleIndex) {
            kernel.setWaveformValue(uint32_t(tableIndex), uint32_t(sampleIndex), samples[sampleIndex]);
        }
    }
}

} // namespace s1
