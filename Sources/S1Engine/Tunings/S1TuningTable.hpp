//
//  S1TuningTable.hpp
//  Arcade Ruins
//
//  PORT (X1-4, ADR-068): AudioKit's AKTuningTableBase + AKTuningTable (S1Support/Microtonality),
//  the part the instrument plays through: a master set of octave-reduced ratios becomes 128
//  frequencies. Ported line for line; the Swift stays the reference and Tests/Engine compares
//  every factory tuning's table against a fixture the Swift code wrote.
//
//  Not ported: the ETNN / delta-12ET dictionaries (12-ET note + pitch bend per key), which
//  nothing in the product reads, and the builders (MOS, CPS, raga, Brun …) — the factory
//  tunings they build are carried as data in S1FactoryTunings.cpp, generated from the Swift.
//

#ifndef S1_TUNING_TABLE_HPP
#define S1_TUNING_TABLE_HPP

#include <array>
#include <cmath>
#include <vector>

namespace s1 {
/// `pow(2, x)` as libm computes it. Spelled with a literal 2, LLVM rewrites pow(2, x) into
/// exp2(x), which differs from pow in the last bit for some x (1100 cents: 1.8877486253633871
/// vs 1.8877486253633868). The Swift code — the reference — gets libm's pow, so the base is
/// loaded through a volatile to keep the rewrite away. Same result on every compiler.
inline double powerOfTwo(double exponent) {
    static volatile double two = 2.0;
    return std::pow(double(two), exponent);
}
}  // namespace s1

class S1TuningTable {
public:
    static constexpr int midiNoteCount = 128;

    /// 12-tone equal temperament, as AKTuningTable() starts.
    S1TuningTable();

    /// Octave-reduces and sorts the input into the master set and rebuilds the table.
    /// Returns the notes per octave, or 0 if the input is empty or holds a zero.
    int tuningTableFromFrequencies(const std::vector<double> &inputMasterSet);

    int equalTemperament(int notesPerOctave);
    int twelveToneEqualTemperament() { return equalTemperament(12); }

    /// AKTuningTable.npo: the master set's size.
    int npo() const { return int(masterSet.size()); }
    double frequencyForNoteNumber(int noteNumber) const { return table[size_t(noteNumber)]; }
    void setFrequency(double frequency, int noteNumber) { table[size_t(noteNumber)] = frequency; }
    const std::vector<double> &masterSetRatios() const { return masterSet; }
    std::vector<double> masterSetInCents() const;

    // The reference. Each setter rebuilds the table, as the Swift property observers did.
    int middleCNoteNumber() const { return middleC; }
    double middleCFrequency() const { return middleCHz; }
    void setMiddleCNoteNumber(int noteNumber) { middleC = noteNumber; updateTuningTableFromMasterSet(); }
    void setMiddleCFrequency(double hz) { middleCHz = hz; updateTuningTableFromMasterSet(); }
    /// AKTuningTableBase.NYQUIST: `AKSettings.sampleRate / 2`, read once at first use — 22050
    /// on every path the fixture was written by. Frequencies above it are clamped to it.
    void setNyquist(double hz) { nyquist = hz; updateTuningTableFromMasterSet(); }

private:
    void updateTuningTableFromMasterSet();

    std::array<double, midiNoteCount> table{};
    std::vector<double> masterSet;
    int middleC = 60;
    double middleCHz = 261.6255653006;
    double nyquist = 22050.0;
};

#endif
