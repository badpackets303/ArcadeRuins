//
//  S1FactoryTunings.hpp
//  Arcade Ruins
//
//  PORT (X1-4, ADR-068): the tunings the product ships — the bundle bank (Tunings+DefaultTunings:
//  defaultTunings) and "Hexanies With Proportional Triads" (hexanyTriadTunings) — as data.
//  S1FactoryTunings.cpp is GENERATED from the Swift by TuningFixtureTests (write mode) and
//  checked against it (check mode); do not edit it by hand. Each master set is what the Swift
//  builder returned, before octave reduction, printed with 17 significant digits so it
//  round-trips exactly. Duplicated names are upstream's and are kept.
//

#ifndef S1_FACTORY_TUNINGS_HPP
#define S1_FACTORY_TUNINGS_HPP

#include <vector>

namespace s1 {

struct FactoryTuning {
    const char *bank;
    const char *name;
    std::vector<double> masterSet;   ///< as the Swift builder returned it; feed to tuningTableFromFrequencies
};

const std::vector<FactoryTuning> &factoryTunings();

/// The bank names, as the Tunings panel shows them.
extern const char *const kBundleTuningsBankName;
extern const char *const kHexanyTriadTuningsBankName;

}  // namespace s1

#endif
