// The C++ preset model against what the Swift preset code did with every factory preset
// (Tests/Engine/Fixtures/factory-presets.txt, written by PresetFixtureTests).
// Usage: PresetTests <fixture> <bank directory>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "S1DSPKernel.hpp"
#include "S1Preset.hpp"

namespace {
int failures = 0;
void check(bool ok, const char *what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what, measured);
    if (!ok) { ++failures; }
}
std::vector<std::string> split(const std::string &s, char sep) {
    std::vector<std::string> out; std::string cur;
    for (char c : s) { if (c == sep) { out.push_back(cur); cur.clear(); } else { cur.push_back(c); } }
    out.push_back(cur); return out;
}
std::string unescaped(const std::string &s) {
    std::string out;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '\\' && i + 1 < s.size()) { const char n = s[++i]; out.push_back(n == 'n' ? '\n' : n == 'r' ? '\r' : n == 't' ? '\t' : n); }
        else { out.push_back(s[i]); }
    }
    return out;
}
std::string g17(double x) { char b[40]; std::snprintf(b, sizeof b, "%.17g", x); return b; }
template <typename C, typename F> std::string joined(const C &c, F f) {
    std::string out; bool first = true;
    for (const auto &v : c) { if (!first) out += ' '; first = false; out += f(v); }
    return out;
}
constexpr double kPi = 3.14159265358979323846;
void loadSineWavetables(S1DSPKernel &kernel) {
    for (uint32_t t = 0; t < S1_NUM_WAVEFORMS * S1_NUM_BANDLIMITED_FTABLES; ++t) {
        kernel.setupWaveform(t, 4096);
        for (uint32_t i = 0; i < 4096; ++i) kernel.setWaveformValue(t, i, float(std::sin(2.0 * kPi * i / 4096)));
    }
    for (uint32_t b = 0; b < S1_NUM_BANDLIMITED_FTABLES; ++b) kernel.setBandlimitFrequency(b, 20.f * std::pow(2.f, float(b)));
}
}  // namespace

int main(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc < 3) { std::printf("usage: PresetTests <fixture> <bank dir>\n"); return 2; }
    std::ifstream fixture(argv[1]);
    if (!fixture) { std::printf("cannot open %s\n", argv[1]); return 2; }
    const std::string bankDir = argv[2];

    S1DSPKernel kernel(2, 44100.0);
    loadSineWavetables(kernel);
    kernel.init(2, 44100.0);
    const s1::PresetDefaults defaults = [&kernel](S1Parameter p) { return double(kernel.defaultValue(p)); };

    std::map<std::string, std::vector<s1::Preset>> banks;
    auto bank = [&](const std::string &name) -> const std::vector<s1::Preset> & {
        auto it = banks.find(name);
        if (it == banks.end()) {
            std::ifstream in(bankDir + "/" + name + ".json");
            nlohmann::json array = nlohmann::json::parse(in, nullptr, false);
            it = banks.emplace(name, s1::Preset::bankFromJSON(array, defaults)).first;
        }
        return it->second;
    };

    int presets = 0, fieldMismatches = 0, valueMismatches = 0, roundTripMismatches = 0;
    std::set<std::string> keysPlain, keysTuned;
    std::string line;
    while (std::getline(fixture, line)) {
        if (line.empty() || line[0] == '#') continue;
        const auto f = split(line, '\t');
        if (f[0] == "keys") { for (const auto &k : split(f[1], ' ')) keysPlain.insert(k); continue; }
        if (f[0] == "keysWithTuning") { for (const auto &k : split(f[1], ' ')) keysTuned.insert(k); continue; }
        if (f[0] != "preset") continue;

        const std::string &bankName = f[1];
        const size_t index = size_t(std::stoi(f[2]));
        const auto &list = bank(bankName);
        if (index >= list.size()) { std::printf("  %s has no preset %zu\n", bankName.c_str(), index); ++fieldMismatches; continue; }
        const s1::Preset &p = list[index];

        // Decoded fields, as the Swift decoded them.
        std::string got = joined(std::vector<std::string>{
            p.name, p.uid,
            p.tuningName ? *p.tuningName : "-",
            p.tuningMasterSet ? joined(*p.tuningMasterSet, g17) : "-",
            joined(p.seqPatternNote, [](int v) { return std::to_string(v); }),
            joined(p.seqOctBoost, [](bool v) { return std::string(v ? "1" : "0"); }),
            joined(p.seqNoteOn, [](bool v) { return std::string(v ? "1" : "0"); }),
            p.isUser ? "1" : "0", p.isFavorite ? "1" : "0", std::to_string(p.category),
            std::to_string(p.octavePosition), std::to_string(p.position), p.author, p.userText}, [](const std::string &s) { return s; });
        std::string expected = joined(std::vector<std::string>{unescaped(f[3]), f[4], unescaped(f[5]), f[6], f[7], f[8], f[9], f[10], f[11], f[12], f[13], f[14], unescaped(f[15]), unescaped(f[16])}, [](const std::string &s) { return s; });
        if (got != expected) { ++fieldMismatches; if (fieldMismatches <= 5) std::printf("  fields differ for %s/%s\n     got %s\n     exp %s\n", bankName.c_str(), p.name.c_str(), got.c_str(), expected.c_str()); }

        // The 150 values after apply — exact, this is the same float path.
        p.apply(kernel);
        std::istringstream values(f[17]);
        for (int i = 0; i < S1Parameter::S1ParameterCount; ++i) {
            double exp = 0; values >> exp;
            const double got = double(kernel.getSynthParameter(S1Parameter(i)));
            if (got != exp) { ++valueMismatches; if (valueMismatches <= 5) std::printf("  %s/%s parameter %d: %.17g vs %.17g\n", bankName.c_str(), p.name.c_str(), i, got, exp); }
        }

        // Round trip: what toJSON writes, fromJSON reads back to the same preset.
        const s1::Preset again = s1::Preset::fromJSON(p.toJSON(), defaults);
        if (again.toJSON() != p.toJSON()) { ++roundTripMismatches; }
        ++presets;
    }

    check(presets == 695, "the fixture holds the 695 factory presets", presets);
    check(fieldMismatches == 0, "every preset decodes to the Swift's fields (name, uid, tuning, sequencer, flags)", fieldMismatches);
    check(valueMismatches == 0, "every preset applies to the same 150 values as the Swift — bit-exact", valueMismatches);
    check(roundTripMismatches == 0, "every preset survives toJSON → fromJSON unchanged", roundTripMismatches);

    // The writer's key set is JSONEncoder's, so the Mac app reads what the engine saves.
    s1::Preset plain;
    std::set<std::string> plainKeys, tunedKeys;
    const nlohmann::json plainJSON = plain.toJSON();   // a named object: items() on a temporary is a dangling proxy
    for (auto &kv : plainJSON.items()) plainKeys.insert(kv.key());
    s1::Preset tuned; tuned.tuningName = "Wilson Hexany(1, 3, 5, 7)"; tuned.tuningMasterSet = std::vector<double>{1, 3, 5, 7};
    const nlohmann::json tunedJSON = tuned.toJSON();
    for (auto &kv : tunedJSON.items()) tunedKeys.insert(kv.key());
    check(!keysPlain.empty() && plainKeys == keysPlain, "toJSON writes exactly the keys Swift's JSONEncoder writes (no tuning)", double(plainKeys.size()));
    check(!keysTuned.empty() && tunedKeys == keysTuned, "… and with a tuning", double(tunedKeys.size()));
    if (plainKeys != keysPlain) {
        for (const auto &k : plainKeys) if (!keysPlain.count(k)) std::printf("  extra key %s\n", k.c_str());
        for (const auto &k : keysPlain) if (!plainKeys.count(k)) std::printf("  missing key %s\n", k.c_str());
    }

    // Defaults for a missing or wrongly typed key, as `as? … ?? …` gave them.
    const s1::Preset sparse = s1::Preset::fromJSON(nlohmann::json::parse(R"({"name": "sparse", "cutoff": "loud", "transpose": 2.5, "isFavorite": 1, "seqPatternNote": [1, 2, 3]})"), defaults);
    check(sparse.cutoff == defaults(S1Parameter::cutoff), "a key of the wrong type takes the DSP default", sparse.cutoff);
    check(sparse.transpose == int(defaults(S1Parameter::transpose)), "a fractional number does not bridge to Int", sparse.transpose);
    check(sparse.isFavorite == true, "a 1 bridges to Bool", 1);
    check(sparse.seqPatternNote[0] == int(defaults(S1Parameter::sequencerPattern00)), "a short sequencer array falls back to the defaults", sparse.seqPatternNote[0]);
    check(sparse.name == "sparse" && sparse.bank == "User" && sparse.masterVolume == defaults(S1Parameter::masterVolume), "missing keys take the field or DSP default", sparse.masterVolume);
    check(s1::Preset::newUID().size() == 36 && s1::Preset::newUID() != s1::Preset::newUID(), "newUID makes a 36-character UUID, different each time", 36);

    std::printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
