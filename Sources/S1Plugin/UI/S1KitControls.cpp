//
//  S1KitControls.cpp
//  Arcade Ruins
//
//  X3-2 (ADR-084). See the header.
//
#include "S1KitControls.h"

#include <algorithm>
#include <cmath>

#include "S1Rate.hpp"

namespace s1ui {
namespace {

float clampTo(const S1HostParameter &parameter, float plainValue) {
    const auto &info = parameter.description();
    return juce::jlimit(info.minimum, info.maximum, plainValue);
}

/// What assistive technology reads and sets: the parameter's plain value and the host's own text.
class ParameterValueInterface final : public juce::AccessibilityValueInterface {
public:
    explicit ParameterValueInterface(ParameterControl &c) : control(c) {}
    bool isReadOnly() const override { return false; }
    double getCurrentValue() const override { return double(control.plain()); }
    juce::String getCurrentValueAsString() const override { return control.parameter().getText(control.parameter().getValue(), 0); }
    void setValue(double newValue) override { control.setPlainAsOneEdit(float(newValue)); }
    void setValueAsString(const juce::String &text) override {
        control.setPlainAsOneEdit(control.parameter().convertFrom0to1(control.parameter().getValueForText(text)));
    }
    AccessibleValueRange getRange() const override {
        const auto &info = control.parameter().description();
        const double span = double(info.maximum) - double(info.minimum);
        if (span <= 0) { return {}; }
        return { { double(info.minimum), double(info.maximum) }, control.parameter().isDiscrete() ? 1.0 : span * 0.01 };
    }
private:
    ParameterControl &control;
};

class ParameterAccessibility final : public juce::AccessibilityHandler {
public:
    ParameterAccessibility(ParameterControl &c, bool toggle, juce::AccessibilityActions actions)
        : juce::AccessibilityHandler(c, toggle ? juce::AccessibilityRole::toggleButton : juce::AccessibilityRole::slider, std::move(actions),
                                     Interfaces { std::make_unique<ParameterValueInterface>(c) }),
          control(c), isToggle(toggle) {}
    juce::AccessibleState getCurrentState() const override {
        juce::AccessibleState state = juce::AccessibilityHandler::getCurrentState();
        if (!isToggle) { return state; }
        state = state.withCheckable();
        return control.position() >= 0.5f ? state.withChecked() : state;
    }
private:
    ParameterControl &control;
    const bool isToggle;
};

} // namespace

// MARK: - ParameterControl

ParameterControl::ParameterControl(S1HostParameter &p, const Style &s, juce::Colour a, juce::UndoManager *undo)
    : style(s), accent(a), hostParameter(p), attachment(p, [this](float) { valueChanged(); }, undo) {
    setWantsKeyboardFocus(true);
    setMouseClickGrabsKeyboardFocus(true);
    setTitle(p.description().name);
}

void ParameterControl::beginEdit() {
    if (editing) { return; }
    editing = true;
    attachment.beginGesture();
}

void ParameterControl::setPosition(float position01) {
    const float p = juce::jlimit(0.0f, 1.0f, position01);
    setPlain(map.toPlain ? map.toPlain(p) : hostParameter.convertFrom0to1(p));
}

void ParameterControl::setPlain(float plainValue) {
    const float value = clampTo(hostParameter, plainValue);
    if (editing) { attachment.setValueAsPartOfGesture(value); } else { attachment.setValueAsCompleteGesture(value); }
    repaint();
}

void ParameterControl::endEdit() {
    if (!editing) { return; }
    editing = false;
    attachment.endGesture();
}

void ParameterControl::setPlainAsOneEdit(float plainValue) {
    endEdit();
    attachment.setValueAsCompleteGesture(clampTo(hostParameter, plainValue));
    repaint();
}

void ParameterControl::resetToDefault() { setPlainAsOneEdit(hostParameter.description().defaultValue); }

void ParameterControl::nudge(float delta01) {
    if (hostParameter.isDiscrete()) {
        // Whole steps only: fractions add up until they make one
        const int steps = std::max(1, hostParameter.getNumSteps() - 1);
        wheelRemainder += delta01 * float(steps);
        const int whole = int(wheelRemainder >= 0 ? std::floor(wheelRemainder + 0.001f) : std::ceil(wheelRemainder - 0.001f));
        if (whole == 0) { return; }
        wheelRemainder -= float(whole);
        const auto &info = hostParameter.description();
        const float stepSize = (info.maximum - info.minimum) / float(steps);
        setPlainAsOneEdit(plain() + float(whole) * stepSize);
        return;
    }
    const float p = juce::jlimit(0.0f, 1.0f, position() + delta01);
    setPlainAsOneEdit(map.toPlain ? map.toPlain(p) : hostParameter.convertFrom0to1(p));
}

void ParameterControl::mouseDoubleClick(const juce::MouseEvent &) { resetToDefault(); }

void ParameterControl::mouseWheelMove(const juce::MouseEvent &event, const juce::MouseWheelDetails &wheel) {
    if (!isEnabled() || wheel.deltaY == 0.0f) { return; }
    const float direction = wheel.isReversed ? -1.0f : 1.0f;
    nudge(wheel.deltaY * direction * 0.15f * (event.mods.isAltDown() ? kFineFactor : 1.0f));
}

bool ParameterControl::keyPressed(const juce::KeyPress &key) {
    if (key == juce::KeyPress::returnKey || key == juce::KeyPress::spaceKey) { return activate(); }
    const int code = key.getKeyCode();
    float direction = 0;
    if (code == juce::KeyPress::upKey || code == juce::KeyPress::rightKey) { direction = 1; }
    if (code == juce::KeyPress::downKey || code == juce::KeyPress::leftKey) { direction = -1; }
    if (direction == 0.0f) { return false; }
    if (hostParameter.isDiscrete()) {
        nudge(direction / float(std::max(1, hostParameter.getNumSteps() - 1)));
    } else {
        const juce::ModifierKeys mods = key.getModifiers();
        nudge(direction * 0.01f * (mods.isShiftDown() ? 10.0f : 1.0f) * (mods.isAltDown() ? kFineFactor : 1.0f));
    }
    return true;
}

std::unique_ptr<juce::AccessibilityHandler> ParameterControl::createAccessibilityHandler() {
    juce::AccessibilityActions actions;
    if (isToggle()) { actions.addAction(juce::AccessibilityActionType::press, [this] { activate(); }); }
    return std::make_unique<ParameterAccessibility>(*this, isToggle(), std::move(actions));
}

void ParameterControl::paintFocusRing(juce::Graphics &g, float cornerRadius) const {
    if (hasKeyboardFocus(false)) { style.drawFocusRing(g, getLocalBounds().toFloat(), accent, cornerRadius); }
}

// MARK: - Knob

void Knob::paint(juce::Graphics &g) {
    style.drawKnob(g, getLocalBounds().toFloat(), position(), accent);
    paintFocusRing(g, float(getWidth()) / 2);
}

void Knob::dragBy(float dx, float dy, bool fine) {
    // Right and up increase, and the two add — the Mac knob's rule. The knob's own travel is kept
    // beside the parameter's, so a stepped parameter still answers a slow drag.
    dragPosition = juce::jlimit(0.0f, 1.0f, dragPosition + (dx - dy) * kDragSensitivity * (fine ? kFineFactor : 1.0f));
    setPosition(dragPosition);
}

void Knob::grab() {
    dragPosition = position();
    beginEdit();
}

void Knob::mouseDown(const juce::MouseEvent &event) {
    if (event.getNumberOfClicks() > 1) { return; }   // the double-click's own handler resets
    last = event.position;
    grab();
}

void Knob::mouseDrag(const juce::MouseEvent &event) {
    dragBy(event.position.x - last.x, event.position.y - last.y, event.mods.isAltDown());
    last = event.position;
}

// MARK: - Toggle, TwoWaySwitch

Toggle::Toggle(S1HostParameter &p, const Style &s, juce::Colour a, Look l, juce::UndoManager *undo) : ParameterControl(p, s, a, undo), look(l) {}

void Toggle::paint(juce::Graphics &g) {
    if (look == Look::pill) { style.drawSwitch(g, getLocalBounds().toFloat(), isOn(), accent); }
    else { style.drawStepButton(g, getLocalBounds().toFloat(), isOn(), accent); }
    paintFocusRing(g, look == Look::pill ? float(getHeight()) / 2 : 2.0f);
}

void Toggle::toggle() {
    const auto &info = parameter().description();
    setPlainAsOneEdit(isOn() ? info.minimum : info.maximum);
}

TwoWaySwitch::TwoWaySwitch(S1HostParameter &p, const Style &s, juce::Colour a, juce::String l, juce::String r, juce::UndoManager *undo)
    : ParameterControl(p, s, a, undo), left(std::move(l)), right(std::move(r)) {}

void TwoWaySwitch::paint(juce::Graphics &g) {
    style.drawTwoWaySwitch(g, getLocalBounds().toFloat(), position() >= 0.5f, left, right, accent);
    paintFocusRing(g, 5.0f);
}

void TwoWaySwitch::toggle() {
    const auto &info = parameter().description();
    setPlainAsOneEdit(position() >= 0.5f ? info.minimum : info.maximum);
}

// MARK: - LFOChip

LFOChip::LFOChip(S1HostParameter &p, const Style &s, juce::Colour a, juce::String t, juce::UndoManager *undo)
    : ParameterControl(p, s, a, undo), text(std::move(t)) {}

void LFOChip::paint(juce::Graphics &g) {
    const int bits = juce::roundToInt(plain());
    style.drawLFOChip(g, getLocalBounds().toFloat(), text, (bits & 1) != 0, (bits & 2) != 0, accent);
    paintFocusRing(g, 4.0f);
}

void LFOChip::pressAt(float x) {
    const int bits = juce::roundToInt(plain());
    setPlainAsOneEdit(float(bits ^ (x < float(getWidth()) / 2 ? 1 : 2)));
}

// MARK: - CellPicker

CellPicker::CellPicker(S1HostParameter &p, const Style &s, juce::Colour a, Look l, juce::StringArray t, juce::UndoManager *undo)
    : ParameterControl(p, s, a, undo), look(l), titles(std::move(t)) {}

int CellPicker::cellCount() const {
    return look == Look::waves ? 4 : look == Look::direction ? 3 : std::max(1, titles.size());
}

void CellPicker::paint(juce::Graphics &g) {
    const juce::Rectangle<float> bounds = getLocalBounds().toFloat();
    switch (look) {
    case Look::waves: style.drawWavePicker(g, bounds, selected(), accent); break;
    case Look::direction: style.drawDirection(g, bounds, selected(), accent); break;
    case Look::segmented: style.drawSegmented(g, bounds, titles, selected(), accent); break;
    }
    paintFocusRing(g, 5.0f);
}

void CellPicker::pressAt(float x) {
    const int count = cellCount();
    const int cell = juce::jlimit(0, count - 1, int(std::floor(x / std::max(1.0f, float(getWidth())) * float(count))));
    setPlainAsOneEdit(parameter().description().minimum + float(cell));
}

// MARK: - MorphSelector

void MorphSelector::paint(juce::Graphics &g) {
    style.drawMorphSelector(g, getLocalBounds().toFloat(), position());
    paintFocusRing(g, 4.0f);
}

void MorphSelector::mouseDown(const juce::MouseEvent &event) {
    if (event.getNumberOfClicks() > 1) { return; }
    beginEdit();
    // PORT: the Mac control ignores a touch's first point — a finger lands before it aims. A
    // pointer aims first, so a click goes where it is.
    setPosition(event.position.x / std::max(1.0f, float(getWidth())));
}

void MorphSelector::mouseDrag(const juce::MouseEvent &event) { setPosition(event.position.x / std::max(1.0f, float(getWidth()))); }

// MARK: - Stepper

Stepper::Stepper(S1HostParameter &p, const Style &s, juce::Colour a, Look l, juce::UndoManager *undo) : ParameterControl(p, s, a, undo), look(l) {}

juce::String Stepper::text() const {
    const juce::String number(juce::roundToInt(plain()));
    return look == Look::tempo ? number + " bpm" : number;
}

void Stepper::paint(juce::Graphics &g) {
    if (look == Look::tempo) { style.drawTempoStepper(g, getLocalBounds().toFloat(), text(), pressed, hostOwned); }
    else { style.drawStepper(g, getLocalBounds().toFloat(), text(), pressed); }
    paintFocusRing(g, 5.0f);
}

int Stepper::zoneAt(juce::Point<float> point) const {
    const juce::Rectangle<float> bounds = getLocalBounds().toFloat();
    if (look == Look::tempo) {
        const Style::TempoZones zones = Style::tempoZones(bounds);
        return zones.minus.contains(point) ? 1 : zones.plus.contains(point) ? 2 : 0;
    }
    const Style::StepperZones zones = Style::stepperZones(bounds);
    return zones.minus.contains(point) ? 1 : zones.plus.contains(point) ? 2 : 0;
}

void Stepper::press(int zone) {
    if (hostOwned || zone == 0) { return; }
    setPlainAsOneEdit(std::round(plain()) + (zone == 1 ? -1.0f : 1.0f));
}

void Stepper::grab() {
    if (hostOwned || look != Look::tempo) { return; }
    dragging = true;
    dragPosition = position();
    beginEdit();
}

void Stepper::letGo() {
    if (dragging) { endEdit(); }
    dragging = false;
}

void Stepper::dragBy(float dx, float dy, bool fine) {
    if (hostOwned || !dragging) { return; }
    dragPosition = juce::jlimit(0.0f, 1.0f, dragPosition + (dx - dy) * kDragSensitivity * (fine ? kFineFactor : 1.0f));
    setPosition(dragPosition);
}

void Stepper::mouseDown(const juce::MouseEvent &event) {
    if (hostOwned || event.getNumberOfClicks() > 1) { return; }
    pressed = zoneAt(event.position);
    if (pressed != 0) {
        press(pressed);
    } else if (look == Look::tempo && Style::tempoZones(getLocalBounds().toFloat()).display.contains(event.position)) {
        last = event.position;
        grab();
    }
    repaint();
}

void Stepper::mouseDrag(const juce::MouseEvent &event) {
    if (!dragging) { return; }
    dragBy(event.position.x - last.x, event.position.y - last.y, event.mods.isAltDown());
    last = event.position;
}

void Stepper::mouseUp(const juce::MouseEvent &) {
    letGo();
    pressed = 0;
    repaint();
}

void Stepper::setHostOwned(bool owned) {
    if (hostOwned == owned) { return; }
    hostOwned = owned;
    setEnabled(!owned);   // no clicks, no wheel, no focus: the host's tempo is the tempo (ADR-077)
    repaint();
}

// MARK: - StepOctave, StepFader

StepOctave::StepOctave(S1HostParameter &boost, S1HostParameter &pattern, const Style &s, juce::Colour a, juce::UndoManager *undo)
    : ParameterControl(boost, s, a, undo), patternParameter(pattern), patternAttachment(pattern, [this](float) { repaint(); }, nullptr) {}

juce::String StepOctave::text() const {
    // PORT: the Mac label adds the octave to a number it keeps; here it is what is shown, never stored
    int semitones = juce::roundToInt(patternParameter.plainValue());
    if (position() >= 0.5f) { semitones += semitones >= 0 ? 12 : -12; }
    return juce::String(semitones);
}

void StepOctave::paint(juce::Graphics &g) {
    style.drawNumberBox(g, getLocalBounds().toFloat(), text(), position() >= 0.5f, playing, accent);
    paintFocusRing(g, 4.0f);
}

void StepOctave::toggle() {
    const auto &info = parameter().description();
    setPlainAsOneEdit(position() >= 0.5f ? info.minimum : info.maximum);
}

void StepOctave::setPlaying(bool isPlaying) {
    if (playing == isPlaying) { return; }
    playing = isPlaying;
    repaint();
}

void StepFader::paint(juce::Graphics &g) {
    const juce::Rectangle<float> bounds = getLocalBounds().toFloat();
    style.drawFader(g, bounds, Style::faderCap(bounds, position()), accent);
    paintFocusRing(g, 4.0f);
}

void StepFader::moveTo(float y) {
    const float travel = std::max(1.0f, float(getHeight()) - Style::kFaderMargin * 2);
    setPosition((float(getHeight()) - Style::kFaderMargin - y) / travel);
}

void StepFader::mouseDown(const juce::MouseEvent &event) {
    if (event.getNumberOfClicks() > 1) { return; }
    beginEdit();
    moveTo(event.position.y);
}

// MARK: - XYPad

XYPad::XYPad(S1HostParameter &x, S1HostParameter &y, const Style &s, juce::UndoManager *undo)
    : style(s), xParameter(x), yParameter(y),
      xAttachment(x, [this](float) { repaint(); }, undo), yAttachment(y, [this](float) { repaint(); }, undo) {
    setWantsKeyboardFocus(true);
    setTitle(x.description().name + " and " + y.description().name);
}

void XYPad::paint(juce::Graphics &g) {
    const juce::Rectangle<float> bounds = getLocalBounds().toFloat();
    style.drawPad(g, bounds, xPosition(), yParameter.getValue());
    // X3-6: the particles a held pad throws, and the screen bezel a skin may frame it with.
    if (const float age = particleAge(); age > 0) { style.drawPadParticles(g, bounds, age, getComponentID().hashCode(), trail); }
    style.drawCRTFrame(g, bounds, 4.0f);
    if (hasKeyboardFocus(false)) { style.drawFocusRing(g, bounds, style.colour("accent")); }
}

void XYPad::grab() {
    if (held) { return; }
    held = true;
    // X3-6 (ADR-088): the starfield runs while the pad is held, so it needs a clock.
    heldSince = juce::Time::getMillisecondCounterHiRes() * 0.001;
    startTimerHz(30);
    // Until the touch says where it is, the stars leave from the target.
    trail.clear();
    trail.push_back({ 0.0f, { xPosition() * float(getWidth()), (1.0f - yParameter.getValue()) * float(getHeight()) } });
    grabbedX = xParameter.plainValue();
    grabbedY = yParameter.plainValue();
    xAttachment.beginGesture();
    yAttachment.beginGesture();
}

void XYPad::moveTo(juce::Point<float> point) {
    if (!held) { return; }
    const float x = juce::jlimit(0.0f, 1.0f, point.x / std::max(1.0f, float(getWidth())));
    const float y = juce::jlimit(0.0f, 1.0f, 1.0f - point.y / std::max(1.0f, float(getHeight())));
    xAttachment.setValueAsPartOfGesture(xMap.toPlain ? xMap.toPlain(x) : xParameter.convertFrom0to1(x));
    yAttachment.setValueAsPartOfGesture(yParameter.convertFrom0to1(y));
    // The starfield follows the CURSOR (held to the pad), not the target: on a tempo-synced pad
    // the target steps between note values and the hand does not. One entry is kept from before
    // the oldest living star, so that star still knows where it left from.
    const float now = particleAge();
    trail.push_back({ now, { x * float(getWidth()), (1.0f - y) * float(getHeight()) } });
    while (trail.size() > 2 && trail[1].at < now - Style::kPadParticleLifetime) { trail.erase(trail.begin()); }
    repaint();
}

void XYPad::letGo() {
    if (!held) { return; }
    stopTimer();                 // the starfield stops with the touch, as the emitters do
    trail.clear();
    if (snapsBack) {
        xAttachment.setValueAsPartOfGesture(grabbedX);
        yAttachment.setValueAsPartOfGesture(grabbedY);
    }
    xAttachment.endGesture();
    yAttachment.endGesture();
    held = false;
    repaint();
}

bool XYPad::keyPressed(const juce::KeyPress &key) {
    const int code = key.getKeyCode();
    const float step = 0.01f * (key.getModifiers().isShiftDown() ? 10.0f : 1.0f) * (key.getModifiers().isAltDown() ? kFineFactor : 1.0f);
    auto move = [](S1HostParameter &parameter, juce::ParameterAttachment &attachment, float delta) {
        attachment.setValueAsCompleteGesture(parameter.convertFrom0to1(juce::jlimit(0.0f, 1.0f, parameter.getValue() + delta)));
    };
    if (code == juce::KeyPress::rightKey) { move(xParameter, xAttachment, step); }
    else if (code == juce::KeyPress::leftKey) { move(xParameter, xAttachment, -step); }
    else if (code == juce::KeyPress::upKey) { move(yParameter, yAttachment, step); }
    else if (code == juce::KeyPress::downKey) { move(yParameter, yAttachment, -step); }
    else { return false; }
    repaint();
    return true;
}

// MARK: - EnvelopeView

EnvelopeView::EnvelopeView(Parameters p, const Style &s, juce::Colour curve, juce::Colour fill, juce::UndoManager *undo)
    : style(s), parameters(p),
      attack(p.attack, [this](float) { repaint(); }, undo), decay(p.decay, [this](float) { repaint(); }, undo),
      sustain(p.sustain, [this](float) { repaint(); }, undo), release(p.release, [this](float) { repaint(); }, undo),
      curveColour(curve), fillColour(fill) {
    setTitle("Envelope");
}

void EnvelopeView::setColours(juce::Colour line, juce::Colour under) {
    if (curveColour == line && fillColour == under) { return; }
    curveColour = line;
    fillColour = under;
    repaint();
}

void EnvelopeView::paint(juce::Graphics &g) {
    style.drawEnvelope(g, getLocalBounds().toFloat(), parameters.attack.plainValue(), parameters.decay.plainValue(),
                       parameters.sustain.plainValue(), parameters.release.plainValue(), curveColour, fillColour);
}

EnvelopeView::Area EnvelopeView::areaAt(juce::Point<float> point) const {
    const Style::EnvelopeAreas areas = Style::envelopeAreas(getLocalBounds().toFloat(), parameters.attack.plainValue(),
                                                            parameters.decay.plainValue(), parameters.release.plainValue());
    // AKADSRView's order: a later match wins
    Area area = Area::none;
    if (areas.decaySustain.contains(point)) { area = Area::decaySustain; }
    if (areas.attack.contains(point)) { area = Area::attack; }
    if (areas.release.contains(point)) { area = Area::release; }
    return area;
}

void EnvelopeView::grab(Area area) {
    letGo();
    held = area;
    if (held == Area::attack) { attack.beginGesture(); }
    if (held == Area::decaySustain) { decay.beginGesture(); sustain.beginGesture(); }
    if (held == Area::release) { release.beginGesture(); }
}

void EnvelopeView::dragBy(float dx, float dy, bool fine) {
    // A point is a millisecond, across or up; ten points up is one per cent of sustain
    const float scale = fine ? kFineFactor : 1.0f;
    const float milliseconds = (dx - dy) * scale * 0.001f;
    switch (held) {
    case Area::attack: attack.setValueAsPartOfGesture(clampTo(parameters.attack, parameters.attack.plainValue() + milliseconds)); break;
    case Area::release: release.setValueAsPartOfGesture(clampTo(parameters.release, parameters.release.plainValue() + milliseconds)); break;
    case Area::decaySustain:
        decay.setValueAsPartOfGesture(clampTo(parameters.decay, parameters.decay.plainValue() + dx * scale * 0.001f));
        sustain.setValueAsPartOfGesture(clampTo(parameters.sustain, parameters.sustain.plainValue() - dy * scale * 0.001f));
        break;
    case Area::none: return;
    }
    repaint();
}

void EnvelopeView::letGo() {
    if (held == Area::attack) { attack.endGesture(); }
    if (held == Area::decaySustain) { decay.endGesture(); sustain.endGesture(); }
    if (held == Area::release) { release.endGesture(); }
    held = Area::none;
}

void EnvelopeView::mouseDown(const juce::MouseEvent &event) {
    last = event.position;
    grab(areaAt(event.position));
}

void EnvelopeView::mouseDrag(const juce::MouseEvent &event) {
    dragBy(event.position.x - last.x, event.position.y - last.y, event.mods.isAltDown());
    last = event.position;
}

// MARK: - ValueReadout

ValueReadout::ValueReadout(S1HostParameter &p, const Style &s) : style(s), hostParameter(p), attachment(p, [this](float) { refresh(); }, nullptr) {
    setInterceptsMouseClicks(false, false);
    setAccessible(false);   // the control beside it speaks the same value
    refresh();
}

void ValueReadout::refresh() {
    const juce::String text = hostParameter.getText(hostParameter.getValue(), 0);
    if (text == shown) { return; }
    shown = text;
    repaint();
}

void ValueReadout::paint(juce::Graphics &g) {
    g.setColour(style.colour("value"));
    g.setFont(style.font(11.0f));
    g.drawText(shown, getLocalBounds(), juce::Justification::centred, false);
}

// MARK: - From the specification

PositionMap dependentPositionMap(S1Parameter parameter, const ParameterLookup &lookup) {
    const bool isRate = parameter == S1Parameter::lfo1Rate || parameter == S1Parameter::lfo2Rate || parameter == S1Parameter::autoPanFrequency;
    const bool isDelay = parameter == S1Parameter::delayTime, isStep = parameter == S1Parameter::arpSeqTempoMultiplier;
    if (!isRate && !isDelay && !isStep) { return {}; }
    S1HostParameter *sync = &lookup(S1Parameter::tempoSyncToArpRate), *tempo = &lookup(S1Parameter::arpRate);
    const float minimum = lookup(parameter).description().minimum, maximum = lookup(parameter).description().maximum;
    constexpr float kTaper = 0.4f;   // S1_DEPENDENT_PARAM_TAPER
    PositionMap map;
    map.toPosition = [=](float plainValue) {
        S1Rate rate;
        if (isStep) { return 1.0f - rate.nearestFactor(plainValue).value01; }
        if (sync->plainValue() > 0) {
            return isDelay ? 1.0f - rate.nearestTime(plainValue, tempo->plainValue(), minimum, maximum).value01
                           : rate.nearestFrequency(plainValue, tempo->plainValue(), minimum, maximum).value01;
        }
        return std::pow(juce::jlimit(0.0f, 1.0f, (plainValue - minimum) / std::max(1.0e-9f, maximum - minimum)), kTaper);
    };
    map.toPlain = [=](float position) {
        S1Rate rate;
        // The engine's own arithmetic, truncation included (rateFrom…01 cast to int)
        if (isStep) { return rate.factorForRate(rate.rateFromFactor01(1.0f - position)); }
        if (sync->plainValue() > 0) {
            const float value = isDelay ? rate.time(tempo->plainValue(), rate.rateFromTime01(1.0f - position))
                                        : rate.frequency(tempo->plainValue(), rate.rateFromFrequency01(position));
            return juce::jlimit(minimum, maximum, value);
        }
        return minimum + std::pow(position, 1.0f / kTaper) * (maximum - minimum);
    };
    return map;
}

std::unique_ptr<ParameterControl> makeControl(const s1plugin::LayoutControl &control, const Style &style, const ParameterLookup &lookup, juce::UndoManager *undo) {
    using Kind = s1plugin::LayoutControlKind;
    S1HostParameter &parameter = lookup(control.parameter);
    const juce::Colour accent = style.accentFor(control.section);
    juce::StringArray choices;
    for (const std::string &choice : control.choices) { choices.add(juce::String::fromUTF8(choice.c_str())); }
    const juce::String title = juce::String::fromUTF8(control.title.c_str());

    std::unique_ptr<ParameterControl> made;
    switch (control.kind) {
    case Kind::knob: made = std::make_unique<Knob>(parameter, style, accent, undo); break;
    case Kind::toggle: made = std::make_unique<Toggle>(parameter, style, accent, Toggle::Look::pill, undo); break;
    case Kind::stepOn: made = std::make_unique<Toggle>(parameter, style, accent, Toggle::Look::stepBar, undo); break;
    case Kind::twoWay:
        made = std::make_unique<TwoWaySwitch>(parameter, style, accent, choices.size() == 2 ? choices[0] : juce::String("Off"),
                                              choices.size() == 2 ? choices[1] : juce::String("On"), undo);
        break;
    case Kind::chip: made = std::make_unique<LFOChip>(parameter, style, accent, title, undo); break;
    case Kind::wavePicker: made = std::make_unique<CellPicker>(parameter, style, accent, CellPicker::Look::waves, juce::StringArray(), undo); break;
    case Kind::direction: made = std::make_unique<CellPicker>(parameter, style, accent, CellPicker::Look::direction, juce::StringArray(), undo); break;
    case Kind::segmented: made = std::make_unique<CellPicker>(parameter, style, accent, CellPicker::Look::segmented, choices, undo); break;
    case Kind::morphSelector: made = std::make_unique<MorphSelector>(parameter, style, accent, undo); break;
    case Kind::stepper: made = std::make_unique<Stepper>(parameter, style, accent, Stepper::Look::plain, undo); break;
    case Kind::tempo: made = std::make_unique<Stepper>(parameter, style, accent, Stepper::Look::tempo, undo); break;
    case Kind::stepFader: made = std::make_unique<StepFader>(parameter, style, accent, undo); break;
    case Kind::stepOctave: {
        // The box shows the same step's pattern value; the two lists run side by side in S1Parameter
        const int step = int(control.parameter) - int(S1Parameter::sequencerOctBoost00);
        if (step < 0 || step > 15) { return nullptr; }
        made = std::make_unique<StepOctave>(parameter, lookup(S1Parameter(int(S1Parameter::sequencerPattern00) + step)), style, accent, undo);
        break;
    }
    case Kind::other: return nullptr;
    }
    // The accessible name: "Filter Cutoff", "Mix Sub −24"; the host's name for the parameter when
    // the layout shows no words beside the control
    const bool inSection = !control.section.empty() && control.section != "playBar" && control.section != "toolbar";
    if (title.isNotEmpty()) { made->setTitle(inSection ? juce::String::fromUTF8(control.section.c_str()) + " " + title : title); }
    if (control.dependent) { made->setPositionMap(dependentPositionMap(control.parameter, lookup)); }
    made->setComponentID(juce::String::fromUTF8(control.id.c_str()));
    return made;
}

std::unique_ptr<juce::Component> makeDisplay(const s1plugin::LayoutDisplay &display, const Style &style, const ParameterLookup &lookup, juce::UndoManager *undo) {
    auto parameter = [&](const char *role) -> S1HostParameter * {
        const auto found = display.parameters.find(role);
        return found != display.parameters.end() ? &lookup(found->second) : nullptr;
    };
    auto colour = [](const std::optional<s1plugin::LayoutColour> &c) {
        return c ? juce::Colour(c->red, c->green, c->blue, c->alpha) : juce::Colours::transparentBlack;
    };
    std::unique_ptr<juce::Component> made;
    if (display.kind == "adsr") {
        S1HostParameter *a = parameter("attack"), *d = parameter("decay"), *s = parameter("sustain"), *r = parameter("release");
        if (a == nullptr || d == nullptr || s == nullptr || r == nullptr) { return nullptr; }
        made = std::make_unique<EnvelopeView>(EnvelopeView::Parameters { *a, *d, *s, *r }, style,
                                              display.curve ? colour(display.curve) : style.accentFor(display.section), colour(display.fill), undo);
        made->setTitle(juce::String::fromUTF8(display.section.c_str()) + " plot");
    } else if (display.kind == "xyPad") {
        S1HostParameter *x = parameter("x"), *y = parameter("y");
        if (x == nullptr || y == nullptr) { return nullptr; }
        auto pad = std::make_unique<XYPad>(*x, *y, style, undo);
        pad->setXPositionMap(dependentPositionMap(display.parameters.at("x"), lookup));
        made = std::move(pad);
    } else {
        return nullptr;
    }
    made->setComponentID(juce::String::fromUTF8(display.id.c_str()));
    return made;
}

} // namespace s1ui
