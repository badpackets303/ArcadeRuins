// s1::Wavetables against the Swift loader (X1-6, ADR-070).
//   argv[1]  Tests/Engine/Fixtures/wavetables.txt, written by WavetableFixtureTests from the Swift
//   argv[2]  Sources/SynthOneCore/DSP/BandlimitedWavetables, the JSON both loaders read
// The fixture holds a size, an FNV-1a 64 over the samples' bit patterns and the first eight
// samples per table, and the 13 band frequencies whole. Equal checksums = equal floats, bit for bit.
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#include "S1DSPKernel.hpp"
#include "S1Wavetables.hpp"

namespace {
int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

uint32_t bits(float value) {
    uint32_t result;
    std::memcpy(&result, &value, sizeof result);
    return result;
}

uint64_t fnv1a64(const float *samples, size_t count) {
    uint64_t hash = 0xcbf29ce484222325ull;
    for (size_t i = 0; i < count; ++i) {
        uint32_t b = bits(samples[i]);
        for (int byte = 0; byte < 4; ++byte) {
            hash ^= uint64_t(b & 0xff);
            hash *= 0x00000100000001b3ull;
            b >>= 8;
        }
    }
    return hash;
}

std::vector<std::string> split(const std::string &line, char separator) {
    std::vector<std::string> fields;
    std::string field;
    std::istringstream stream(line);
    while (std::getline(stream, field, separator)) { fields.push_back(field); }
    return fields;
}

struct ExpectedTable {
    std::string name;
    size_t size = 0;
    uint64_t checksum = 0;
    std::vector<uint32_t> first;
};

/// One note through a new kernel: 0.25 s of A3 from the real tables. Returns the output's checksum.
uint64_t renderOneNote(const s1::Wavetables &tables, double &energy, int &exactTables) {
    auto kernel = std::make_unique<S1DSPKernel>(2, 44100.0);
    tables.apply(*kernel);
    kernel->init(2, 44100.0);
    kernel->updateWavetableIncrementValuesForCurrentSampleRate();

    const S1FrameCount frames = 512;
    std::vector<float> left(frames), right(frames), all;
    kernel->setOutput(left.data(), right.data());
    S1Event note{};
    note.kind = S1EventKind_MIDI;
    note.sampleOffset = 0;
    note.midi = {3, {0x90, 57, 100}};
    for (int block = 0; block < 22; ++block) {
        kernel->processWithEvents(frames, &note, block == 0 ? 1 : 0);
        all.insert(all.end(), left.begin(), left.end());
        all.insert(all.end(), right.begin(), right.end());
    }
    energy = 0;
    for (float sample : all) { energy += double(sample) * sample; }

    // The host's deallocate/allocate cycle: destroy() and init() leave the tables alone.
    kernel->destroy();
    kernel->init(2, 44100.0);
    kernel->updateWavetableIncrementValuesForCurrentSampleRate();
    exactTables = 0;
    for (size_t i = 0; i < tables.waveforms.size(); ++i) {
        const sp_ftbl *table = kernel->ft_array[i];
        if (table != nullptr && table->size == tables.waveforms[i].size()
            && fnv1a64(table->tbl, table->size) == fnv1a64(tables.waveforms[i].data(), tables.waveforms[i].size())) {
            ++exactTables;
        }
    }
    return fnv1a64(all.data(), all.size());
}

bool throwsMentioning(const s1::Wavetables::Source &source, const std::string &needle, std::string &message) {
    try {
        s1::Wavetables::load(source);
    } catch (const std::exception &error) {
        message = error.what();
        return message.find(needle) != std::string::npos;
    }
    message = "(no exception)";
    return false;
}
}

int main(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc < 3) { std::printf("usage: WavetableTests <fixture> <wavetable directory>\n"); return 2; }

    std::vector<uint32_t> expectedFrequencies;
    std::vector<ExpectedTable> expected;
    {
        std::ifstream file(argv[1]);
        std::string line;
        while (std::getline(file, line)) {
            if (!line.empty() && line.back() == '\r') { line.pop_back(); }
            const std::vector<std::string> fields = split(line, '\t');
            if (fields.empty()) { continue; }
            if (fields[0] == "frequencies" && fields.size() == 2) {
                for (const std::string &hex : split(fields[1], ' ')) { expectedFrequencies.push_back(uint32_t(std::stoul(hex, nullptr, 16))); }
            } else if (fields[0] == "table" && fields.size() == 6) {
                ExpectedTable table;
                table.name = fields[2];
                table.size = size_t(std::stoul(fields[3]));
                table.checksum = std::stoull(fields[4], nullptr, 16);
                for (const std::string &hex : split(fields[5], ' ')) { table.first.push_back(uint32_t(std::stoul(hex, nullptr, 16))); }
                expected.push_back(table);
            }
        }
    }
    check(expected.size() == 52 && expectedFrequencies.size() == 13, "the fixture holds 52 tables and 13 frequencies", double(expected.size()));

    s1::Wavetables tables;
    try {
        tables = s1::Wavetables::loadFromDirectory(argv[2]);
    } catch (const std::exception &error) {
        std::printf("FAIL  loading %s: %s\n", argv[2], error.what());
        return 1;
    }

    // 1. The decoded floats are the Swift loader's.
    int exactFrequencies = 0;
    for (size_t i = 0; i < expectedFrequencies.size() && i < tables.bandlimitFrequencies.size(); ++i) {
        if (bits(tables.bandlimitFrequencies[i]) == expectedFrequencies[i]) { ++exactFrequencies; }
    }
    check(exactFrequencies == 13 && tables.bandlimitFrequencies.size() == 13, "the 13 band frequencies are bit-exact", exactFrequencies);

    int exact = 0;
    for (size_t i = 0; i < expected.size() && i < tables.waveforms.size(); ++i) {
        const std::vector<float> &samples = tables.waveforms[i];
        bool ok = tables.names[i] == expected[i].name && samples.size() == expected[i].size
            && fnv1a64(samples.data(), samples.size()) == expected[i].checksum;
        for (size_t k = 0; ok && k < expected[i].first.size(); ++k) { ok = bits(samples[k]) == expected[i].first[k]; }
        if (ok) { ++exact; } else { std::printf("      table %zu (%s) differs from the Swift loader's\n", i, expected[i].name.c_str()); }
    }
    std::printf("WavetableTests: %d of %zu tables decode bit-exactly (%zu floats)\n", exact, expected.size(), expected.size() * 4096);
    check(exact == 52 && tables.waveforms.size() == 52, "every table equals the Swift loader's, bit for bit", exact);

    // 2. apply() puts them in the kernel, and ten kernels made and thrown away from one
    //    Wavetables all get the same tables and make the same sound.
    std::vector<uint64_t> renders;
    int cyclesWithExactTables = 0;
    double energy = 0;
    for (int cycle = 0; cycle < 10; ++cycle) {
        int exactInKernel = 0;
        renders.push_back(renderOneNote(tables, energy, exactInKernel));
        if (exactInKernel == 52) { ++cyclesWithExactTables; }
    }
    check(cyclesWithExactTables == 10, "in ten create/destroy cycles the kernel's 52 tables are exact, after destroy() and init() too", cyclesWithExactTables);
    check(energy > 1.0, "a note from the real tables sounds", energy);
    int sameRender = 0;
    for (uint64_t render : renders) { if (render == renders.front()) { ++sameRender; } }
    check(sameRender == 10, "all ten kernels render the same samples", sameRender);

    // 3. A second apply() to a live kernel replaces the tables (and no longer leaks the first set).
    {
        S1DSPKernel kernel(2, 44100.0);
        tables.apply(kernel);
        tables.apply(kernel);
        check(kernel.ft_array[51] != nullptr && fnv1a64(kernel.ft_array[51]->tbl, 4096) == expected[51].checksum, "apply() twice leaves the tables exact", 51);
    }

    // 4. Failures name what is wrong instead of reaching the kernel's fixed arrays.
    const s1::Wavetables::Source real = [&](const std::string &name) -> std::optional<std::string> {
        if (name == "bandlimitedWaveforms") { std::string s = "["; for (size_t i = 0; i < 52; ++i) { s += (i ? ",\"" : "\"") + tables.names[i] + "\""; } return s + "]"; }
        if (name == "bandlimitedWaveformFrequencies") { return std::string("{\"content\":[0,1,2,3,4,5,6,7,8,9,10,11,12],\"phase\":0,\"type\":10}"); }
        std::string s = "{\"content\":[";
        for (int i = 0; i < 4096; ++i) { s += i ? ",0.5" : "0.5"; }
        return s + "],\"phase\":0,\"type\":0}";
    };
    std::string message;
    bool loadsSynthetic = true;
    try { s1::Wavetables::load(real); } catch (const std::exception &) { loadsSynthetic = false; }
    check(loadsSynthetic, "a well-formed in-memory source loads (the X2 path: no directory)", 1);
    check(throwsMentioning([&](const std::string &name) { return name == "square_0337" ? std::nullopt : real(name); }, "square_0337", message),
          "a missing table is named: " + message, 1);
    check(throwsMentioning([&](const std::string &name) { return name == "bandlimitedWaveforms" ? std::optional<std::string>("[\"a\",\"b\"]") : real(name); }, "found 2", message),
          "a short index is refused: " + message, 1);
    check(throwsMentioning([&](const std::string &name) { return name == "pwm_0000" ? std::optional<std::string>("{\"content\":[1,2,3]}") : real(name); }, "pwm_0000", message),
          "a short table is refused: " + message, 1);
    check(throwsMentioning([&](const std::string &name) { return name == "bandlimitedWaveformFrequencies" ? std::optional<std::string>("{\"content\":[1,2,3]}") : real(name); }, "band frequencies", message),
          "a short frequency list is refused: " + message, 1);

    std::printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
