// The C++ tuning table and Scala parser against what the Swift code produced
// (Tests/Engine/Fixtures/factory-tunings.txt, written by TuningFixtureTests), and the generated
// factory list against the same fixture. Usage: TuningTableTests <fixture path>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "S1FactoryTunings.hpp"
#include "S1Scala.hpp"
#include "S1TuningTable.hpp"

namespace {
int failures = 0;
void check(bool ok, const char *what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what, measured);
    if (!ok) { ++failures; }
}

std::vector<std::string> split(const std::string &s, char sep) {
    std::vector<std::string> out;
    std::string cur;
    for (char c : s) { if (c == sep) { out.push_back(cur); cur.clear(); } else { cur.push_back(c); } }
    out.push_back(cur);
    return out;
}
std::vector<double> doubles(const std::string &s) {
    std::vector<double> out;
    std::istringstream in(s);
    double v;
    while (in >> v) { out.push_back(v); }
    return out;
}
std::string unescaped(const std::string &s) {
    std::string out;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '\\' && i + 1 < s.size()) {
            const char n = s[++i];
            out.push_back(n == 'n' ? '\n' : n == 'r' ? '\r' : n == 't' ? '\t' : n);
        } else { out.push_back(s[i]); }
    }
    return out;
}
}  // namespace

int main(int argc, char **argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc < 2) { std::printf("usage: TuningTableTests <fixture>\n"); return 2; }
    std::ifstream file(argv[1]);
    if (!file) { std::printf("cannot open %s\n", argv[1]); return 2; }

    double nyquist = 22050;
    int tunings = 0, exactTables = 0, scalaCases = 0;
    double worstRelative = 0;
    bool allNpoMatch = true, allWithinTolerance = true, factoryListMatches = true, allScalaMatch = true;
    const auto &factory = s1::factoryTunings();

    std::string line;
    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '#') continue;
        const auto fields = split(line, '\t');
        if (fields[0] == "nyquist") { nyquist = std::stod(fields[1]); continue; }

        if (fields[0] == "tuning") {
            const std::string &bank = fields[1], &name = fields[2];
            const int npo = std::stoi(fields[3]);
            const std::vector<double> masterSet = doubles(fields[4]);
            const std::vector<double> expected = doubles(fields[5]);

            S1TuningTable table;
            table.setNyquist(nyquist);
            const int got = table.tuningTableFromFrequencies(masterSet);
            if (got != npo) { allNpoMatch = false; std::printf("  npo differs for %s: %d vs %d\n", name.c_str(), got, npo); }
            bool exact = true;
            for (int n = 0; n < 128; ++n) {
                const double a = table.frequencyForNoteNumber(n), b = expected[size_t(n)];
                if (a != b) { exact = false; }
                const double rel = b != 0 ? std::fabs(a - b) / std::fabs(b) : std::fabs(a - b);
                worstRelative = std::max(worstRelative, rel);
                if (rel > 1e-9) { allWithinTolerance = false; std::printf("  %s note %d: %.17g vs %.17g\n", name.c_str(), n, a, b); }
            }
            if (exact) { ++exactTables; }

            // The generated list carries this tuning at the same position, byte for byte.
            if (size_t(tunings) >= factory.size() || name != factory[size_t(tunings)].name
                || bank != factory[size_t(tunings)].bank || masterSet != factory[size_t(tunings)].masterSet) {
                factoryListMatches = false;
                std::printf("  factory list differs at %d (%s)\n", tunings, name.c_str());
            }
            ++tunings;
            continue;
        }

        if (fields[0] == "scala") {
            const std::string text = unescaped(fields[1]);
            const auto parsed = s1::frequenciesFromScalaString(text);
            if (fields[2] == "nil") {
                if (parsed.has_value()) { allScalaMatch = false; std::printf("  scala case %d: parsed, Swift rejected\n", scalaCases); }
            } else {
                const std::vector<double> expected = doubles(fields[2]);
                if (!parsed.has_value() || *parsed != expected) {
                    allScalaMatch = false;
                    std::printf("  scala case %d: %zu values vs %zu expected\n", scalaCases, parsed ? parsed->size() : 0, expected.size());
                }
            }
            ++scalaCases;
        }
    }

    check(tunings >= 190, "the fixture holds the factory tunings", tunings);
    check(allNpoMatch, "every tuning reports the Swift code's notes per octave", 1);
    check(allWithinTolerance, "every note of every tuning is within 1e-9 relative of the Swift table", worstRelative);
    std::printf("      %d of %d tables are bit-exact\n", exactTables, tunings);
    check(factory.size() == size_t(tunings) && factoryListMatches, "the generated factory list is the fixture's list, in order", double(factory.size()));
    check(scalaCases >= 6 && allScalaMatch, "the Scala parser agrees with the Swift parser on every case", scalaCases);

    // The defaults, without a fixture: 12-ET around middle C = 261.6255653006 Hz, A4 = 440.
    S1TuningTable et;
    check(et.npo() == 12, "a fresh table is 12-ET", et.npo());
    check(std::fabs(et.frequencyForNoteNumber(69) - 440.0) < 1e-9, "A4 is 440 Hz", et.frequencyForNoteNumber(69));
    check(std::fabs(et.frequencyForNoteNumber(60) - 261.6255653006) < 1e-9, "middle C is 261.6255653006 Hz", et.frequencyForNoteNumber(60));
    check(et.tuningTableFromFrequencies({}) == 0 && et.tuningTableFromFrequencies({1, 0, 1.5}) == 0, "an empty set or a zero is rejected", 0);
    check(et.npo() == 12, "and leaves the table as it was", et.npo());

    std::printf("%d failure(s)\n", failures);
    return failures == 0 ? 0 : 1;
}
