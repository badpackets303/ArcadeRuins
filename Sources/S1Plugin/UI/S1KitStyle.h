//
//  S1KitStyle.h
//  Arcade Ruins
//
//  X3-2 (ADR-084): how the controls kit draws. A port of the Mac desktop layout's drawing —
//  `Sources/SynthOneCore/Desktop/S1DesktopStyle.swift`, function for function, with the classic
//  MorphSelector, AKADSRView and touch point it does not cover — onto `juce::Graphics`.
//
//  Nothing here owns a colour or a size: every colour is the layout specification's palette
//  (`s1plugin::LayoutSkin`, S1Palette's field names), the dress decides how lit things are lit,
//  and each drawing takes the control's ACCENT — its section's under Cabinet, the palette's under
//  Studio (ADR-048). Drawing only: no component, no parameter. `PluginControlsKitTests` paints
//  every function into an image at 1x and 2x.
//
//  Geometry is in points, as the Mac's; a caller scales the Graphics, never the numbers.
//
#pragma once

#include <array>
#include <string>
#include <vector>

#include <juce_graphics/juce_graphics.h>
#include <juce_core/juce_core.h>

#include "../S1LayoutSpec.hpp"

namespace s1ui {

enum class FontWeight { regular, medium, demiBold };

class Style {
public:
    /// `skin` must outlive the style (the linked specification lives for the process).
    explicit Style(const s1plugin::LayoutSkin &skin);

    const s1plugin::LayoutSkin &skin() const noexcept { return layoutSkin; }

    /// A palette colour by S1Palette's field name.
    juce::Colour colour(const char *name) const;
    /// A section's accent (Cabinet), or the palette's (Studio; the toolbar and play bar anywhere).
    juce::Colour accentFor(const std::string &sectionKey) const;
    float glow() const noexcept { return dimAmount > 0 ? layoutSkin.glow * (1.0f - dimAmount) : layoutSkin.glow; }

    // MARK: X3-9 (ADR-091): the cabinet's power
    /// The Mac's `greyed()` factor: a dead colour is its luminance times this.
    static constexpr float kDeadLuminance = 0.72f;
    /// The room a centred caption or label is given each side of the frame the Mac measured for it:
    /// the frame is as wide as the text in Avenir, and another face runs a little wider. At 0 Linux
    /// drew "Pitch Trac" (seen in a render for the README, 2026-09-21; `PluginTypefaceTests` holds it).
    static constexpr float kCaptionRoom = 20.0f;
    /// How far a caption may be SQUEEZED before a glyph is dropped. `Graphics::drawText` curtails —
    /// it silently deletes the letters that do not fit — and it does so with the advances the
    /// renderer computes THROUGH the window's transform, which is not what `getStringWidth`
    /// answers at 1x. Windows drew "Pitch Trac" and "Transpos" at a scale of 1.10 while its own
    /// `PluginTypefaceTests` said both fitted (2026-09-21). `drawFittedText` with this scale
    /// squeezes instead, so no renderer at any scale can cut a letter off. ADR-096.
    static constexpr float kCaptionSqueeze = 0.7f;
    /// 0 lit, 1 dead. Every colour this style answers is blended toward its own luminance by it,
    /// and the glow goes out with it — so EVERY control drawn with this style goes grey, because
    /// they all draw with `colour()` and `accentFor()` and nothing else (ADR-084).
    void setDim(float amount) { dimAmount = juce::jlimit(0.0f, 1.0f, amount); }
    float dim() const noexcept { return dimAmount; }
    juce::Colour dimmed(juce::Colour) const;
    /// The same blend for a colour that is not this style's to answer — the backdrop's words. 0 lit, 1 dead.
    static juce::Colour dimmedBy(juce::Colour, float amount);
    bool litFromAccent() const noexcept { return dressFlag("litFromAccent"); }

    /// The interface's type at a Mac point size. Avenir Next Condensed where the system has it
    /// (macOS); elsewhere the default sans narrowed to its width, until a face ships with the
    /// plugin (ADR-084: the owner's decision, it needs a font file in the repository).
    juce::Font font(float pointSize, FontWeight weight = FontWeight::regular) const;
    /// X3-6 (ADR-088): make every Style built after this use the LINKED face (Barlow Condensed)
    /// even where the system has Avenir Next Condensed — which is how a test, and
    /// `EditorSnapshot --linked-face`, see what Windows and Linux see. macOS is unaffected
    /// otherwise.
    /// The specification's text as the interface can actually DRAW it: two glyphs the Mac's own
    /// face has and few others do — the Option sign and a non-breaking hyphen — are replaced.
    /// The editor draws this, so anything measuring a label must measure this (ADR-088: Linux
    /// caught the test measuring the raw text instead, and two labels then did not fit).
    static juce::String drawable(const juce::String &specText);
    static void preferLinkedTypeface(bool);
    static bool prefersLinkedTypeface() { return preferLinked; }

    // MARK: S1DesktopStyle, function for function. `value` and positions are 0…1.
    void drawKnob(juce::Graphics &, juce::Rectangle<float>, float value, juce::Colour accent) const;
    void drawSwitch(juce::Graphics &, juce::Rectangle<float>, bool isOn, juce::Colour accent) const;
    void drawLFOChip(juce::Graphics &, juce::Rectangle<float>, const juce::String &text, bool lfo1, bool lfo2, juce::Colour accent) const;
    void drawWavePicker(juce::Graphics &, juce::Rectangle<float>, int selected, juce::Colour accent) const;
    /// `pressed`: 0 none, 1 minus, 2 plus.
    void drawStepper(juce::Graphics &, juce::Rectangle<float>, const juce::String &text, int pressed) const;
    void drawTempoStepper(juce::Graphics &, juce::Rectangle<float>, const juce::String &text, int pressed, bool dimmed) const;
    void drawTwoWaySwitch(juce::Graphics &, juce::Rectangle<float>, bool isOn, const juce::String &left, const juce::String &right, juce::Colour accent) const;
    void drawDirection(juce::Graphics &, juce::Rectangle<float>, int selected, juce::Colour accent) const;
    void drawFader(juce::Graphics &, juce::Rectangle<float>, juce::Rectangle<float> cap, juce::Colour accent) const;
    void drawStepButton(juce::Graphics &, juce::Rectangle<float>, bool isOn, juce::Colour accent) const;
    /// The step's number box (SliderTransposeButton): lit when the octave boost is on, ringed
    /// while its step plays.
    void drawNumberBox(juce::Graphics &, juce::Rectangle<float>, const juce::String &text, bool isOn, bool isPlaying, juce::Colour accent) const;
    /// S1SegmentedControl: a field with one raised segment.
    void drawSegmented(juce::Graphics &, juce::Rectangle<float>, const juce::StringArray &titles, int selected, juce::Colour accent) const;

    // MARK: the classic drawings the desktop layout keeps
    void drawMorphSelector(juce::Graphics &, juce::Rectangle<float>, float value) const;
    /// Times in seconds, sustain 0…1. `fill` transparent: no fill (the specification's word).
    void drawEnvelope(juce::Graphics &, juce::Rectangle<float>, float attack, float decay, float sustain, float release,
                      juce::Colour curve, juce::Colour fill) const;
    /// The XY pad's frame and its touch point at `x`, `y` (0…1, y up).
    void drawPad(juce::Graphics &, juce::Rectangle<float>, float x, float y) const;
    /// X3-6 (ADR-088): `S1CRTFrame` — the screen bezel a skin may put round a pad or a list:
    /// a one-point border in the frame accent at 0.9, its glow (0.45, radius 6, no offset), and
    /// scanlines over it, one dark line every three points at 16% black. Nothing when the skin
    /// has no frame accent (Studio). `radius` is 4 for a pad, 6 for a list, as on the Mac.
    void drawCRTFrame(juce::Graphics &, juce::Rectangle<float>, float radius = 6.0f) const;
    bool hasCRTFrame() const { return layoutSkin.frameAccent.has_value(); }
    /// Where a held pad's touch was, and when: `at` in seconds since the pad was grabbed.
    struct PadTouch { float at; juce::Point<float> where; };
    /// The starfield a pad throws while it is held (`particleEmitter1` / `2`): upstream's cell,
    /// drawn rather than animated by CoreAnimation. `age` in seconds since the pad was grabbed,
    /// `seed` keeps two pads apart. **Each star leaves from where the touch was when it was
    /// born** (`trail`, oldest first, in the pad's own coordinates), so the field follows the
    /// cursor and streams behind it — the owner's, 2026-09-21; the Mac emits from the pad's
    /// centre, and so does this with no trail. Small bright sparks, not the Mac's soft discs:
    /// theirs too ("barely visible … a little bolder with smaller particles").
    void drawPadParticles(juce::Graphics &, juce::Rectangle<float>, float age, int seed,
                          const std::vector<PadTouch> &trail = {}) const;
    /// How long a star lives, in seconds: a trail older than this is no use to anyone.
    static constexpr float kPadParticleLifetime = 1.70f;
    /// The pad's target is HALF TouchPointStyleKit's size (the owner, 2026-09-21).
    static constexpr float kPadTargetScale = 0.5f;

    /// A toolbar / play-bar button in the desktop's dress (`S1DesktopLayout.restyle`): a flat face,
    /// a one-point border, 12-point medium words. `lit`: on (Mono, Snap) — border and words in the accent.
    void drawButton(juce::Graphics &, juce::Rectangle<float>, const juce::String &text, bool lit, bool pressed, juce::Colour accent) const;

    /// The ring every control draws while it has the keyboard focus.
    void drawFocusRing(juce::Graphics &, juce::Rectangle<float>, juce::Colour accent, float cornerRadius = 4.0f) const;

    // MARK: zones, shared by drawing and hit-testing
    struct StepperZones { juce::Rectangle<float> minus, value, plus; };
    static StepperZones stepperZones(juce::Rectangle<float>);
    struct TempoZones { juce::Rectangle<float> display, minus, plus; };
    static TempoZones tempoZones(juce::Rectangle<float>);
    /// The fader's cap for a position 0…1: 32 x 14, its centre 10 points inside each end.
    static juce::Rectangle<float> faderCap(juce::Rectangle<float> bounds, float position);
    static constexpr float kFaderCapWidth = 32, kFaderCapHeight = 14, kFaderMargin = 10;

    /// The envelope plot's three drag areas for the same arguments as `drawEnvelope`.
    struct EnvelopeAreas { juce::Rectangle<float> attack, decaySustain, release; };
    static EnvelopeAreas envelopeAreas(juce::Rectangle<float>, float attack, float decay, float release);

private:
    bool dressFlag(const char *name) const;
    float dressNumber(const char *name, float fallback) const;

    struct Lit { juce::Colour top, bottom, border; };
    Lit lit(juce::Colour accent) const;
    juce::Colour accentLight(juce::Colour accent) const;
    juce::Colour accentBorder(juce::Colour accent) const;
    juce::Colour accentOnTop(juce::Colour accent) const;

    void fillRounded(juce::Graphics &, juce::Rectangle<float>, float radius, juce::Colour top, juce::Colour bottom, juce::Colour border) const;
    void drawButtonFace(juce::Graphics &, juce::Rectangle<float>, bool pressed) const;
    void drawText(juce::Graphics &, const juce::String &, juce::Rectangle<float>, float size, FontWeight, juce::Colour) const;
    void drawPlusMinus(juce::Graphics &, juce::Rectangle<float> minus, juce::Rectangle<float> plus) const;
    /// Core Graphics' `setShadow(offset: .zero, blur:)` under a shape: a blurred copy in `colour`.
    void glowUnder(juce::Graphics &, const juce::Path &, juce::Colour colour, float blur, juce::Point<float> offset = {}) const;

    struct LinkedFaces;
    static bool preferLinked;
    float dimAmount = 0.0f;
    /// The linked typefaces, made once and freed with the last Style (never after JUCE shuts down).
    juce::SharedResourcePointer<LinkedFaces> linkedFaces;
    const s1plugin::LayoutSkin &layoutSkin;
    bool hasAvenir = false;
};

} // namespace s1ui
