//
//  S1Scala.hpp
//  Arcade Ruins
//
//  PORT (X1-4, ADR-068): the Scala (.scl) parser the product uses — `frequencies2(fromScalaString:)`
//  in Tunings+TuneUp.swift, AudioKit's parser as Synth One carries it. Ported line for line, quirks
//  included (a cents line with trailing text is skipped, not parsed; 1/1 and 2/1 are dropped).
//

#ifndef S1_SCALA_HPP
#define S1_SCALA_HPP

#include <optional>
#include <string>
#include <vector>

namespace s1 {

/// The master set a .scl file describes, starting with the implicit 1/1. Empty optional when the
/// file cannot be parsed (a note count of 0 or over 127, a negative or zero ratio).
std::optional<std::vector<double>> frequenciesFromScalaString(const std::string &text);

}  // namespace s1

#endif
