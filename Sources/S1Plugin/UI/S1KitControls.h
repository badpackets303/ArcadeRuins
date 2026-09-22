//
//  S1KitControls.h
//  Arcade Ruins
//
//  X3-2 (ADR-084): the controls kit — one component per `kind` of the layout specification, drawn
//  by `s1ui::Style`, each bound to its `S1HostParameter` through a `juce::ParameterAttachment`.
//
//  What every parameter control does, because `ParameterControl` does it:
//    - an edit is a GESTURE (begin / set … / end), so a host records it, its undo sees one step,
//      and the generic view and automation stay in step (ADR-073: a write from the message thread
//      is an edit; what the engine reports back arrives here through the same attachment);
//    - a double-click puts the parameter's default back; the scroll wheel and the arrow keys
//      nudge it; Alt (⌥) makes a drag, the wheel and the keys fine;
//    - it takes the keyboard focus and shows it, and it has an accessible name, role and value.
//
//  The mouse handlers only translate events: what they do is in plain methods (`dragBy`,
//  `pressAt`, `nudge`, `resetToDefault` …), which is what `PluginControlsKitTests` drives — no
//  window, no desktop, on every OS.
//
//  No layout in here: X3-3 places these on the specification's frames. `makeControl` /
//  `makeDisplay` build the right one for a specification entry.
//
#pragma once

#include <functional>
#include <memory>

#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_gui_basics/juce_gui_basics.h>

#include "../S1HostParameter.h"
#include "../S1LayoutSpec.hpp"
#include "S1KitStyle.h"

namespace s1ui {

/// How much Alt slows a drag, the wheel and the keys (the Mac knob's ⌥).
constexpr float kFineFactor = 0.2f;
/// A knob's travel: 200 points of drag, right or up, is its whole range (the Mac knob's).
constexpr float kDragSensitivity = 0.005f;

/// Where a control points for a value, when that is not the parameter's own range: the five
/// tempo-syncable "dependent parameters" sit by NOTE VALUE while tempo sync is on (ADR-022), as
/// the Mac's knobs do — a quarter note is the same place at every tempo.
struct PositionMap {
    std::function<float(float plain)> toPosition;
    std::function<float(float position01)> toPlain;
};

class ParameterControl : public juce::Component {
public:
    ParameterControl(S1HostParameter &, const Style &, juce::Colour accent, juce::UndoManager * = nullptr);

    S1HostParameter &parameter() const noexcept { return hostParameter; }
    /// 0…1 along the parameter's own (tapered) range — where a knob points.
    float position() const { return map.toPosition ? map.toPosition(hostParameter.plainValue()) : hostParameter.getValue(); }
    void setPositionMap(PositionMap newMap) { map = std::move(newMap); repaint(); }
    float plain() const { return hostParameter.plainValue(); }

    // An edit, as a host sees it
    void beginEdit();
    void setPosition(float position01);
    void setPlain(float plainValue);
    void endEdit();
    void setPlainAsOneEdit(float plainValue);
    void resetToDefault();
    /// The wheel and the keys: a fraction of the range, or whole steps of a stepped parameter.
    void nudge(float delta01);

    // juce::Component
    void mouseDoubleClick(const juce::MouseEvent &) override;
    void mouseWheelMove(const juce::MouseEvent &, const juce::MouseWheelDetails &) override;
    bool keyPressed(const juce::KeyPress &) override;
    void focusGained(FocusChangeType) override { repaint(); }
    void focusLost(FocusChangeType) override { repaint(); }
    std::unique_ptr<juce::AccessibilityHandler> createAccessibilityHandler() override;

protected:
    /// The parameter moved, whoever moved it.
    virtual void valueChanged() { repaint(); }
    /// Return or space. Toggles toggle; nothing else answers.
    virtual bool activate() { return false; }
    virtual bool isToggle() const { return false; }
    void paintFocusRing(juce::Graphics &, float cornerRadius = 4.0f) const;

    const Style &style;
    /// X3-9 (ADR-091): not const any more — the cabinet's power greys a zone by handing every
    /// control in it the dead colour, because a control keeps its accent rather than asking the
    /// style at each paint.
    juce::Colour accent;

public:
    void setAccent(juce::Colour newAccent) { if (accent != newAccent) { accent = newAccent; repaint(); } }
    juce::Colour currentAccent() const noexcept { return accent; }

protected:

private:
    S1HostParameter &hostParameter;
    juce::ParameterAttachment attachment;
    PositionMap map;
    bool editing = false;
    float wheelRemainder = 0;
};

// MARK: - One per kind

class Knob final : public ParameterControl {
public:
    using ParameterControl::ParameterControl;
    void paint(juce::Graphics &) override;
    /// A press begins the edit; then a drag of `dx`, `dy` points since the last call — right and
    /// up increase — and letting go ends it.
    void grab();
    void dragBy(float dx, float dy, bool fine);
    void letGo() { endEdit(); }
    void mouseDown(const juce::MouseEvent &) override;
    void mouseDrag(const juce::MouseEvent &) override;
    void mouseUp(const juce::MouseEvent &) override { letGo(); }
private:
    float dragPosition = 0;
    juce::Point<float> last;
};

/// The pill switch, and the sequencer's note-on bar: a click anywhere toggles.
class Toggle final : public ParameterControl {
public:
    enum class Look { pill, stepBar };
    Toggle(S1HostParameter &, const Style &, juce::Colour accent, Look, juce::UndoManager * = nullptr);
    void paint(juce::Graphics &) override;
    void mouseDown(const juce::MouseEvent &) override { toggle(); }
    void toggle();
    bool isOn() const { return position() >= 0.5f; }
protected:
    bool activate() override { toggle(); return true; }
    bool isToggle() const override { return true; }
private:
    const Look look;
};

/// Two words, the lit one is the value ("Arp" / "Seq"). A click anywhere changes sides.
class TwoWaySwitch final : public ParameterControl {
public:
    TwoWaySwitch(S1HostParameter &, const Style &, juce::Colour accent, juce::String left, juce::String right, juce::UndoManager * = nullptr);
    void paint(juce::Graphics &) override;
    void mouseDown(const juce::MouseEvent &) override { toggle(); }
    void toggle();
protected:
    bool activate() override { toggle(); return true; }
    bool isToggle() const override { return true; }
private:
    const juce::String left, right;
};

/// An LFO target: 0 neither, 1 LFO 1, 2 LFO 2, 3 both. Its left half is LFO 1's, its right LFO 2's.
class LFOChip final : public ParameterControl {
public:
    LFOChip(S1HostParameter &, const Style &, juce::Colour accent, juce::String text, juce::UndoManager * = nullptr);
    void paint(juce::Graphics &) override;
    void pressAt(float x);
    void mouseDown(const juce::MouseEvent &e) override { pressAt(e.position.x); }
private:
    const juce::String text;
};

/// A row of cells, one of which is the value: the LFO wave picker (4), the arpeggiator's
/// direction (3), the filter's type (the specification's words).
class CellPicker final : public ParameterControl {
public:
    enum class Look { waves, direction, segmented };
    CellPicker(S1HostParameter &, const Style &, juce::Colour accent, Look, juce::StringArray titles, juce::UndoManager * = nullptr);
    void paint(juce::Graphics &) override;
    void pressAt(float x);
    void mouseDown(const juce::MouseEvent &e) override { pressAt(e.position.x); }
    int selected() const { return juce::roundToInt(plain() - parameter().description().minimum); }
private:
    int cellCount() const;
    const Look look;
    const juce::StringArray titles;
};

/// The oscillator's waveform: a continuous morph, 0…1 across the four shapes — not a four-way switch.
class MorphSelector final : public ParameterControl {
public:
    using ParameterControl::ParameterControl;
    void paint(juce::Graphics &) override;
    void mouseDown(const juce::MouseEvent &) override;
    void mouseDrag(const juce::MouseEvent &) override;
    void mouseUp(const juce::MouseEvent &) override { endEdit(); }
};

/// `[−] value [+]`, and the tempo's taller form whose display also drags.
class Stepper final : public ParameterControl {
public:
    enum class Look { plain, tempo };
    Stepper(S1HostParameter &, const Style &, juce::Colour accent, Look, juce::UndoManager * = nullptr);
    void paint(juce::Graphics &) override;
    /// 1 minus, 2 plus, 0 neither — as the drawing's `pressed`.
    int zoneAt(juce::Point<float>) const;
    void press(int zone);
    /// The tempo's display drags like a knob: grab, dragBy …, letGo.
    void grab();
    void dragBy(float dx, float dy, bool fine);
    void letGo();
    void mouseDown(const juce::MouseEvent &) override;
    void mouseDrag(const juce::MouseEvent &) override;
    void mouseUp(const juce::MouseEvent &) override;
    /// The host has a tempo (ADR-077): the display shows it and takes no edits.
    void setHostOwned(bool owned);
    juce::String text() const;
private:
    const Look look;
    int pressed = 0;
    bool dragging = false, hostOwned = false;
    float dragPosition = 0;
    juce::Point<float> last;
};

/// A sequencer step's number box: bound to the step's octave boost, showing the step's pattern
/// value — moved an octave outward while the boost is on.
class StepOctave final : public ParameterControl {
public:
    StepOctave(S1HostParameter &boost, S1HostParameter &pattern, const Style &, juce::Colour accent, juce::UndoManager * = nullptr);
    void paint(juce::Graphics &) override;
    void mouseDown(const juce::MouseEvent &) override { toggle(); }
    void toggle();
    juce::String text() const;
    /// The playhead is on this step (the processor's `arpBeatCounter`; X3-3 drives it).
    void setPlaying(bool);
protected:
    bool activate() override { toggle(); return true; }
    bool isToggle() const override { return true; }
private:
    S1HostParameter &patternParameter;
    juce::ParameterAttachment patternAttachment;
    bool playing = false;
};

/// A sequencer step's fader: the cap goes where the pointer is.
class StepFader final : public ParameterControl {
public:
    using ParameterControl::ParameterControl;
    void paint(juce::Graphics &) override;
    void moveTo(float y);
    void mouseDown(const juce::MouseEvent &) override;
    void mouseDrag(const juce::MouseEvent &e) override { moveTo(e.position.y); }
    void mouseUp(const juce::MouseEvent &) override { endEdit(); }
};

// MARK: - Views of several parameters

/// An XY pad: x and y are two parameters' positions. With snap on, letting go puts both back
/// where they were when grabbed.
class XYPad final : public juce::Component, private juce::Timer {
public:
    XYPad(S1HostParameter &x, S1HostParameter &y, const Style &, juce::UndoManager * = nullptr);
    void paint(juce::Graphics &) override;
    void grab();
    void moveTo(juce::Point<float>);
    void letGo();
    void setSnapsBack(bool snaps) { snapsBack = snaps; }
    /// For a pad whose x is a dependent parameter (LFO 1's rate).
    void setXPositionMap(PositionMap newMap) { xMap = std::move(newMap); repaint(); }
    float xPosition() const { return xMap.toPosition ? xMap.toPosition(xParameter.plainValue()) : xParameter.getValue(); }
    void mouseDown(const juce::MouseEvent &e) override { grab(); moveTo(e.position); }
    void mouseDrag(const juce::MouseEvent &e) override { moveTo(e.position); }
    void mouseUp(const juce::MouseEvent &) override { letGo(); }
    bool keyPressed(const juce::KeyPress &) override;
    void focusGained(FocusChangeType) override { repaint(); }
    void focusLost(FocusChangeType) override { repaint(); }
    /// X3-6 (ADR-088): how long the starfield has been running, in seconds; 0 when it is not.
    float particleAge() const { return held ? float(juce::Time::getMillisecondCounterHiRes() * 0.001 - heldSince) : 0.0f; }
    /// Where the touch has been while held, oldest first — the starfield leaves from it.
    const std::vector<Style::PadTouch> &touchTrail() const { return trail; }
private:
    void timerCallback() override { repaint(); }
    std::vector<Style::PadTouch> trail;
    const Style &style;
    S1HostParameter &xParameter, &yParameter;
    juce::ParameterAttachment xAttachment, yAttachment;
    PositionMap xMap;
    bool snapsBack = false, held = false;
    double heldSince = 0;
    float grabbedX = 0, grabbedY = 0;
};

/// An envelope's plot. Dragging its left part sets the attack, its middle the decay (across) and
/// the sustain (up and down), its right the release — AKADSRView's areas and rates.
class EnvelopeView final : public juce::Component {
public:
    struct Parameters { S1HostParameter &attack, &decay, &sustain, &release; };
    EnvelopeView(Parameters, const Style &, juce::Colour curve, juce::Colour fill, juce::UndoManager * = nullptr);
    /// X3-9 (ADR-091): the plot's line and fill are handed to it, so the power cuts them here too.
    void setColours(juce::Colour line, juce::Colour under);
    void paint(juce::Graphics &) override;
    enum class Area { none, attack, decaySustain, release };
    Area areaAt(juce::Point<float>) const;
    void grab(Area);
    void dragBy(float dx, float dy, bool fine);
    void letGo();
    void mouseDown(const juce::MouseEvent &) override;
    void mouseDrag(const juce::MouseEvent &) override;
    void mouseUp(const juce::MouseEvent &) override { letGo(); }
private:
    const Style &style;
    Parameters parameters;
    juce::ParameterAttachment attack, decay, sustain, release;
    juce::Colour curveColour, fillColour;   ///< X3-9: not const — the power greys them
    Area held = Area::none;
    juce::Point<float> last;
};

/// The line under a knob: the parameter's value as the host's list shows it ("3.70 kHz",
/// "1/8 note"). `refresh` when something it depends on besides its own value moves — the tempo,
/// the sync switch.
class ValueReadout final : public juce::Component {
public:
    ValueReadout(S1HostParameter &, const Style &);
    void paint(juce::Graphics &) override;
    void refresh();
    juce::String text() const { return shown; }
private:
    const Style &style;
    S1HostParameter &hostParameter;
    juce::ParameterAttachment attachment;
    juce::String shown;
};

// MARK: - From the specification

using ParameterLookup = std::function<S1HostParameter &(S1Parameter)>;

/// The engine's own mapping for a dependent parameter (S1DSPKernel+getSetDependentParameters),
/// reading the sync switch and the tempo from their host parameters; nothing for any other.
PositionMap dependentPositionMap(S1Parameter, const ParameterLookup &);

/// The control for one entry of the specification's `controls`, titled for accessibility
/// ("Filter Cutoff"). Nothing for a kind the kit does not know (`other`).
std::unique_ptr<ParameterControl> makeControl(const s1plugin::LayoutControl &, const Style &, const ParameterLookup &, juce::UndoManager * = nullptr);
/// The view for one entry of `displays`: an envelope plot or an XY pad.
std::unique_ptr<juce::Component> makeDisplay(const s1plugin::LayoutDisplay &, const Style &, const ParameterLookup &, juce::UndoManager * = nullptr);

} // namespace s1ui
