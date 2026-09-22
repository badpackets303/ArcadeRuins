//
//  S1HostParameter.h
//  Arcade Ruins
//
//  X2-2 (ADR-073): one of the engine's 150 parameters as a host sees it.
//
//  It holds the PLAIN value — the number the kernel takes — not JUCE's 0…1. The processor
//  compares that number with what it last gave the kernel, exactly, with no round trip through
//  a normalised float in between; hosts get the 0…1 form through the range, tapered as the Mac
//  interface's knob is.
//
#pragma once

#include <atomic>

#include <juce_audio_processors/juce_audio_processors.h>

#include "S1ParameterCatalog.hpp"

class S1HostParameter final : public juce::RangedAudioParameter {
public:
    /// The JUCE version hint (ADR-058): 1 for every parameter of the first release. A parameter
    /// added in a later release takes that release's number; none of these ever changes.
    static constexpr int kVersionHint = 1;

    /// `context` answers "is tempo sync on, and at what tempo" for the rates' readouts.
    S1HostParameter(const s1plugin::ParameterDescription &, std::function<s1plugin::RateContext()> context);

    const s1plugin::ParameterDescription &description() const noexcept { return info; }
    float plainValue() const noexcept { return plain.load(std::memory_order_relaxed); }

    /// The audio thread, after a render: the engine holds a different value from the one the
    /// host wrote (S1ParameterCatalog.hpp, `engineMayChange`). Stores it; the caller then tells
    /// the host through sendValueChangedMessageToListeners, which off the message thread reaches a
    /// VST3 host as an output parameter change — a report, not an edit a host would record.
    void setPlainValueFromEngine(float value) noexcept { plain.store(value, std::memory_order_relaxed); }
    /// The same, but only if the parameter still holds `written` — the value the processor gave
    /// the engine this block. False when a host has written it again in the meantime.
    bool replacePlainValueFromEngine(float written, float value) noexcept {
        return plain.compare_exchange_strong(written, value, std::memory_order_relaxed);
    }

    // juce::RangedAudioParameter
    const juce::NormalisableRange<float> &getNormalisableRange() const override { return range; }
    float getValue() const override { return range.convertTo0to1(plainValue()); }
    void setValue(float normalised) override;
    float getDefaultValue() const override { return range.convertTo0to1(info.defaultValue); }
    int getNumSteps() const override;
    bool isDiscrete() const override { return info.kind != s1plugin::ParameterKind::continuous; }
    bool isBoolean() const override { return info.kind == s1plugin::ParameterKind::toggle; }
    juce::String getText(float normalised, int maximumLength) const override;
    float getValueForText(const juce::String &text) const override;
    juce::StringArray getAllValueStrings() const override;

private:
    const s1plugin::ParameterDescription info;
    const juce::NormalisableRange<float> range;
    const std::function<s1plugin::RateContext()> rateContext;
    std::atomic<float> plain;
};
