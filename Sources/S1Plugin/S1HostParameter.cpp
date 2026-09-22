//
//  S1HostParameter.cpp
//  Arcade Ruins
//
//  X2-2 (ADR-073).
//

#include "S1HostParameter.h"

#include <cmath>

namespace {

juce::NormalisableRange<float> makeRange(const s1plugin::ParameterDescription &d) {
    const bool stepped = d.kind != s1plugin::ParameterKind::continuous;
    juce::NormalisableRange<float> range(d.minimum, d.maximum, stepped ? 1.f : 0.f);
    // The Mac knob: value = min + (max - min) * position^taper. JUCE: position^(1 / skew).
    if (!stepped && d.taper > 0 && !juce::approximatelyEqual(d.taper, 1.f)) { range.skew = 1.f / d.taper; }
    return range;
}

} // namespace

S1HostParameter::S1HostParameter(const s1plugin::ParameterDescription &d, std::function<s1plugin::RateContext()> context)
    : juce::RangedAudioParameter(juce::ParameterID { d.id, kVersionHint }, d.name),
      info(d), range(makeRange(d)), rateContext(std::move(context)), plain(d.defaultValue) {}

void S1HostParameter::setValue(float normalised) {
    plain.store(range.snapToLegalValue(range.convertFrom0to1(juce::jlimit(0.f, 1.f, normalised))), std::memory_order_relaxed);
}

int S1HostParameter::getNumSteps() const {
    if (info.kind == s1plugin::ParameterKind::continuous) { return juce::AudioProcessor::getDefaultNumParameterSteps(); }
    return int(std::lround(info.maximum - info.minimum)) + 1;
}

juce::String S1HostParameter::getText(float normalised, int maximumLength) const {
    const float value = range.snapToLegalValue(range.convertFrom0to1(juce::jlimit(0.f, 1.f, normalised)));
    const juce::String text(s1plugin::formatValue(info, value, rateContext ? rateContext() : s1plugin::RateContext {}));
    return maximumLength > 0 ? text.substring(0, maximumLength) : text;
}

float S1HostParameter::getValueForText(const juce::String &text) const {
    const std::optional<float> value = s1plugin::parseValue(info, text.toStdString());
    return value ? range.convertTo0to1(range.snapToLegalValue(*value)) : getValue();
}

juce::StringArray S1HostParameter::getAllValueStrings() const {
    juce::StringArray strings;
    if (info.kind == s1plugin::ParameterKind::toggle) { strings = {"Off", "On"}; }
    for (const std::string &choice : info.choices) { strings.add(choice); }
    return strings;
}
