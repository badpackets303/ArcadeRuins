//
//  S1Wavetables.hpp
//  Arcade Ruins
//
//  PORT (X1-6, ADR-070): S1Wavetables.swift in C++. The 4 waveforms x 13 band-limited oscillator
//  tables and their 13 band frequencies, decoded from the same JSON the Mac app reads
//  (AKTable's Codable form: {"content": [...], "phase": 0, "type": n}) and pushed into a kernel
//  through the same three calls. WavetableTests proves the decoded floats against a fixture the
//  Swift loader wrote.
//
//  The kernel cannot render a frame without these (S1NoteState::init hands ft_array to
//  sp_oscmorph2d_init): apply() comes after the kernel is constructed and before its first
//  process(). One Wavetables value serves any number of kernels; apply() copies.
//
#ifndef S1_WAVETABLES_HPP
#define S1_WAVETABLES_HPP

#include <functional>
#include <optional>
#include <string>
#include <vector>

class S1DSPKernel;

namespace s1 {

struct Wavetables {
    static constexpr int waveformCount = 4;
    static constexpr int bandCount = 13;
    static constexpr int tableSize = 4096;

    /// The names in bandlimitedWaveforms.json, in the kernel's table order.
    std::vector<std::string> names;
    /// waveformCount * bandCount tables of tableSize samples.
    std::vector<std::vector<float>> waveforms;
    /// bandCount ascending band edges in Hz.
    std::vector<float> bandlimitFrequencies;

    /// Gives the text of `<name>.json`, or nothing when there is no such resource. A directory on
    /// disk today; binary data linked into the plugin at X2.
    using Source = std::function<std::optional<std::string>(const std::string &name)>;

    /// Throws std::runtime_error naming what is missing or malformed. Stricter than the Swift,
    /// which would let a short frequency list or a ragged table through to the kernel's fixed arrays.
    static Wavetables load(const Source &source);

    /// Every `*.json` under `directory`, at any depth, by file stem: the repository keeps the
    /// tables in per-waveform folders, the Mac bundle keeps them flat.
    static Wavetables loadFromDirectory(const std::string &directory);

    /// setBandlimitFrequency, setupWaveform and setWaveformValue, in the Swift's order.
    void apply(S1DSPKernel &kernel) const;
};

} // namespace s1

#endif
