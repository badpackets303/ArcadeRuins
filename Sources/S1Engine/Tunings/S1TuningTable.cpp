#include "S1TuningTable.hpp"

#include <algorithm>
#include <cmath>

S1TuningTable::S1TuningTable() {
    // AKTuningTableBase.init: 12-ET around A440 …
    for (int noteNumber = 0; noteNumber < midiNoteCount; ++noteNumber) {
        table[size_t(noteNumber)] = 440 * exp2(double(noteNumber - 69) / 12.0);
    }
    // … then AKTuningTable.init: defaultTuning(), which rebuilds it from a 12-ET master set.
    twelveToneEqualTemperament();
}

int S1TuningTable::tuningTableFromFrequencies(const std::vector<double> &inputMasterSet) {
    if (inputMasterSet.empty()) {
        return 0;   // "No input frequencies"
    }
    bool frequenciesAreValid = true;
    std::vector<double> frequenciesOctaveReduce;
    frequenciesOctaveReduce.reserve(inputMasterSet.size());
    for (const double frequency : inputMasterSet) {
        if (frequency == 0) {
            frequenciesAreValid = false;
            frequenciesOctaveReduce.push_back(1.0);
            continue;
        }
        double l2 = std::fabs(frequency);
        while (l2 < 1) { l2 *= 2.0; }
        while (l2 >= 2) { l2 /= 2.0; }
        frequenciesOctaveReduce.push_back(l2);
    }
    if (!frequenciesAreValid) {
        return 0;   // "Invalid input frequencies"
    }
    std::sort(frequenciesOctaveReduce.begin(), frequenciesOctaveReduce.end());
    masterSet = frequenciesOctaveReduce;
    updateTuningTableFromMasterSet();
    return int(masterSet.size());
}

int S1TuningTable::equalTemperament(int notesPerOctave) {
    std::vector<double> nf(size_t(notesPerOctave), 1.0);
    for (int i = 0; i < notesPerOctave; ++i) {
        nf[size_t(i)] = s1::powerOfTwo(double(i) / double(notesPerOctave));
    }
    tuningTableFromFrequencies(nf);
    return notesPerOctave;
}

std::vector<double> S1TuningTable::masterSetInCents() const {
    std::vector<double> cents;
    cents.reserve(masterSet.size());
    for (const double ratio : masterSet) { cents.push_back(std::log2(ratio) * 1200); }
    return cents;
}

void S1TuningTable::updateTuningTableFromMasterSet() {
    const double count = double(masterSet.size());
    for (int i = 0; i < midiNoteCount; ++i) {
        const double ff = double(i - middleC) / count;
        double ttOctaveFactor = std::trunc(ff);
        if (ff < 0) {
            ttOctaveFactor -= 1;
        }
        double frac = std::fabs(ttOctaveFactor - ff);
        if (frac == 1) {
            frac = 0;
            ttOctaveFactor += 1;
        }
        const int frequencyIndex = int(std::round(frac * count));
        const double tone = masterSet[size_t(frequencyIndex)];
        const double lp2 = s1::powerOfTwo(ttOctaveFactor);
        double f = tone * lp2 * middleCHz;
        f = std::min(std::max(f, 0.0), nyquist);   // (0...NYQUIST).clamp(f)
        table[size_t(i)] = f;
    }
}
