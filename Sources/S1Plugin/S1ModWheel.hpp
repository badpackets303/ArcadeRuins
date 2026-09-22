//
//  S1ModWheel.hpp
//  Arcade Ruins
//
//  X2-4 (ADR-075): the mod wheel, on the render thread. No JUCE in here.
//
//  On the Mac the wheel is an interface control: S1HostMIDI forwards CC 1 to the main thread,
//  `AKVerticalPad.setVerticalValueFrom(midiValue:)` sets the on-screen wheel, and the wheel's
//  callback (`Manager+callbacks.swift`) writes a parameter according to the preset's
//  `modWheelRouting`. A plugin cannot take that trip — an offline bounce renders faster than any
//  main thread answers, and the JUCE plugin has no interface at all until X3 — so the same three
//  lines of arithmetic run where the controller arrives. Each names the Swift it mirrors.
//
#pragma once

#include <algorithm>
#include <cmath>

#include "S1DSPKernel.hpp"

namespace s1plugin {

/// `Preset.modWheelRouting`.
enum class ModWheelRouting : int { cutoff = 0, lfo1Rate = 1, lfo2Rate = 2 };

/// The cutoff the wheel writes at `value01` (0 = wheel down): `3 × scaleRangeLog2(1 − value, 120…7600)`,
/// so 22.8 kHz — clamped by the kernel to its maximum — with the wheel down and 360 Hz at the top.
inline float modWheelCutoff(double value01) {
    const double position = std::clamp(1.0 - value01, 0.0, 1.0);
    const double scaled = std::exp2(std::log2(120.0) + (std::log2(7600.0) - std::log2(120.0)) * position);
    return float(scaled * 3.0);
}

/// CC 1 with `midiValue` 0…127. Render thread.
inline void applyModWheel(S1DSPKernel &kernel, ModWheelRouting routing, int midiValue) {
    const double value01 = std::clamp(double(midiValue) / 127.0, 0.0, 1.0);   // setVerticalValueFrom(midiValue:)
    switch (routing) {
        case ModWheelRouting::cutoff:
            kernel.setSynthParameter(S1Parameter::cutoff, modWheelCutoff(value01));
            break;
        case ModWheelRouting::lfo1Rate:
            kernel.setDependentParameter(S1Parameter::lfo1Rate, float(value01), 0);
            break;
        case ModWheelRouting::lfo2Rate:
            kernel.setDependentParameter(S1Parameter::lfo2Rate, float(value01), 0);
            break;
    }
}

} // namespace s1plugin
