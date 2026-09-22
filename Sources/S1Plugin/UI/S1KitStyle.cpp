//
//  S1KitStyle.cpp
//  Arcade Ruins
//
//  X3-2 (ADR-084). See the header. Each function follows its Swift original line by line; the
//  places a port has to decide something are marked `PORT:`.
//
#include "S1KitStyle.h"

#include <array>
#include <cstring>
#include <mutex>

#include "S1FontData.h"

#include <algorithm>
#include <cmath>

namespace s1ui {
namespace {

constexpr float kPi = juce::MathConstants<float>::pi;

juce::Colour toColour(const s1plugin::LayoutColour &c) { return juce::Colour(c.red, c.green, c.blue, c.alpha); }

/// `UIColor.mixed(with:_:)`: every component, alpha included, moved `t` of the way.
juce::Colour mixed(juce::Colour a, juce::Colour b, float t) { return a.interpolatedWith(b, juce::jlimit(0.0f, 1.0f, t)); }

/// The knob's arc runs from 7:30 round to 4:30. Core Graphics measures from 3 o'clock, clockwise
/// on a y-down canvas; `Path::addCentredArc` from 12 o'clock — a quarter turn apart.
constexpr float kArcStart = kPi * 0.75f, kArcSweep = kPi * 1.5f;
float toJuceAngle(float coreGraphicsAngle) { return coreGraphicsAngle + kPi * 0.5f; }

juce::Path arc(juce::Point<float> centre, float radius, float fromCG, float toCG) {
    juce::Path path;
    path.addCentredArc(centre.x, centre.y, radius, radius, 0.0f, toJuceAngle(fromCG), toJuceAngle(toCG), true);
    return path;
}

juce::Point<float> onCircle(juce::Point<float> centre, float radius, float angleCG) {
    return { centre.x + std::cos(angleCG) * radius, centre.y + std::sin(angleCG) * radius };
}

void strokeRound(juce::Graphics &g, const juce::Path &path, float width) {
    g.strokePath(path, juce::PathStrokeType(width, juce::PathStrokeType::curved, juce::PathStrokeType::rounded));
}

juce::Path strokedRound(const juce::Path &path, float width) {
    juce::Path out;
    juce::PathStrokeType(width, juce::PathStrokeType::curved, juce::PathStrokeType::rounded).createStrokedPath(out, path);
    return out;
}

juce::Path rounded(juce::Rectangle<float> r, float radius) {
    juce::Path path;
    path.addRoundedRectangle(r, radius);
    return path;
}

} // namespace

/// Barlow Condensed as the binary carries it (ADR-088). Held by `juce::SharedResourcePointer`, so
/// it is made once for however many Styles exist and **destroyed with the last of them** — a
/// function-local static held these, and the typefaces were then freed after JUCE had shut down,
/// which ends a test run in "mutex lock failed: Invalid argument".
struct Style::LinkedFaces {
    std::array<juce::Typeface::Ptr, 3> faces;
    LinkedFaces() {
        const char *names[3] = { "BarlowCondensed-Regular.ttf", "BarlowCondensed-Medium.ttf", "BarlowCondensed-SemiBold.ttf" };
        for (int i = 0; i < 3; ++i) {
            for (int r = 0; r < S1FontData::namedResourceListSize; ++r) {
                if (std::strcmp(S1FontData::originalFilenames[r], names[i]) != 0) { continue; }
                int size = 0;
                const char *data = S1FontData::getNamedResource(S1FontData::namedResourceList[r], size);
                faces[size_t(i)] = juce::Typeface::createSystemTypefaceFor(data, size_t(size));
            }
        }
    }
    juce::Typeface::Ptr forWeight(FontWeight weight) const {
        const size_t index = weight == FontWeight::demiBold ? 2 : weight == FontWeight::medium ? 1 : 0;
        return faces[index] != nullptr ? faces[index] : faces[0];
    }
};

namespace {

bool systemHasAvenirNextCondensed() {
    static const bool has = juce::Font::findAllTypefaceNames().contains("Avenir Next Condensed");
    return has;
}

} // namespace

juce::String Style::drawable(const juce::String &specText) {
    return specText.replace(juce::String::fromUTF8("\xE2\x80\x91"), "-")        // a non-breaking hyphen
                   .replace(juce::String::fromUTF8("\xE2\x8C\xA5"), "Alt");     // the Option sign
}

bool Style::preferLinked = false;
void Style::preferLinkedTypeface(bool yes) { preferLinked = yes; }

Style::Style(const s1plugin::LayoutSkin &skin)
    : layoutSkin(skin), hasAvenir(!preferLinked && systemHasAvenirNextCondensed()) {}

juce::Colour Style::colour(const char *name) const { return dimmed(toColour(layoutSkin.colour(name))); }

juce::Colour Style::accentFor(const std::string &sectionKey) const {
    if (const s1plugin::LayoutSection *section = layoutSkin.section(sectionKey); section != nullptr && section->accent) {
        return dimmed(toColour(*section->accent));
    }
    return colour("accent");
}

/// X3-9 (ADR-091): a zone whose power is cut. Every colour this style answers is blended toward
/// its own luminance — the Mac's `greyed()`, whose factor is 0.72 — so a control that draws with
/// `style.colour(...)` or `style.accentFor(...)` goes grey without knowing anything about it.
juce::Colour Style::dimmed(juce::Colour c) const { return dimmedBy(c, dimAmount); }

juce::Colour Style::dimmedBy(juce::Colour c, float dimAmount) {
    if (dimAmount <= 0.0f) { return c; }
    const float grey = 0.299f * c.getFloatRed() + 0.587f * c.getFloatGreen() + 0.114f * c.getFloatBlue();
    const juce::Colour dead = juce::Colour::fromFloatRGBA(grey * kDeadLuminance, grey * kDeadLuminance,
                                                          grey * kDeadLuminance, c.getFloatAlpha());
    return c.interpolatedWith(dead, juce::jlimit(0.0f, 1.0f, dimAmount));
}

bool Style::dressFlag(const char *name) const { return dressNumber(name, 0.0f) != 0.0f; }

float Style::dressNumber(const char *name, float fallback) const {
    const auto found = layoutSkin.dress.find(name);
    return found != layoutSkin.dress.end() ? found->second : fallback;
}

juce::Font Style::font(float pointSize, FontWeight weight) const {
    if (hasAvenir) {
        const char *style = weight == FontWeight::demiBold ? "Demi Bold" : weight == FontWeight::medium ? "Medium" : "Regular";
        return juce::Font(juce::FontOptions("Avenir Next Condensed", style, pointSize).withPointHeight(pointSize));
    }
    // X3-6 (ADR-088): everywhere else, Barlow Condensed, linked into the plugin — the owner's
    // choice, and the nearest free condensed face to the Mac's. No horizontal squeeze any more:
    // this face IS condensed, so a label is the shape the specification measured, not a narrowed
    // copy of something else.
    if (const juce::Typeface::Ptr face = linkedFaces->forWeight(weight)) {
        return juce::Font(juce::FontOptions(face)).withPointHeight(pointSize);
    }
    // Nothing linked in (a build without the fonts): the old fallback, the default sans narrowed.
    return juce::Font(juce::FontOptions(juce::Font::getDefaultSansSerifFontName(), weight == FontWeight::regular ? "Regular" : "Bold", pointSize)
                          .withPointHeight(pointSize).withHorizontalScale(0.82f));
}

// MARK: - Colours from an accent (P7-4)

Style::Lit Style::lit(juce::Colour accent) const {
    if (litFromAccent()) { return { mixed(accent, juce::Colours::black, 0.38f), mixed(accent, juce::Colours::black, 0.64f), mixed(accent, juce::Colours::white, 0.45f) }; }
    return { colour("litTop"), colour("litBottom"), colour("litBorder") };
}

juce::Colour Style::accentLight(juce::Colour accent) const { return litFromAccent() ? mixed(accent, juce::Colours::white, 0.35f) : colour("accentLight"); }
juce::Colour Style::accentBorder(juce::Colour accent) const { return litFromAccent() ? mixed(accent, juce::Colours::white, 0.45f) : colour("accentBorder"); }
juce::Colour Style::accentOnTop(juce::Colour accent) const { return litFromAccent() ? mixed(accent, juce::Colours::white, 0.3f) : colour("accentOnTop"); }

// MARK: - Shared pieces

void Style::glowUnder(juce::Graphics &g, const juce::Path &path, juce::Colour glowColour, float blur, juce::Point<float> offset) const {
    // PORT: Core Graphics' blur is softer than a JUCE drop shadow of the same radius; four fifths of
    // it matched the Mac render side by side.
    const int radius = juce::roundToInt(blur * 0.8f);
    if (radius < 1 || glowColour.isTransparent()) { return; }
    juce::DropShadow(glowColour, radius, { juce::roundToInt(offset.x), juce::roundToInt(offset.y) }).drawForPath(g, path);
}

void Style::fillRounded(juce::Graphics &g, juce::Rectangle<float> rect, float radius, juce::Colour top, juce::Colour bottom, juce::Colour border) const {
    const juce::Rectangle<float> body = rect.reduced(0.5f);
    g.setGradientFill(juce::ColourGradient(top, body.getCentreX(), rect.getY(), bottom, body.getCentreX(), rect.getBottom(), false));
    g.fillRoundedRectangle(body, radius);
    g.setColour(border);
    g.drawRoundedRectangle(body, radius, 1.0f);
}

void Style::drawButtonFace(juce::Graphics &g, juce::Rectangle<float> rect, bool pressed) const {
    fillRounded(g, rect, 4.0f, colour(pressed ? "buttonPressedTop" : "buttonTop"), colour("buttonBottom"), colour("buttonBorder"));
}

void Style::drawText(juce::Graphics &g, const juce::String &text, juce::Rectangle<float> rect, float size, FontWeight weight, juce::Colour textColour) const {
    g.setColour(textColour);
    g.setFont(font(size, weight));
    g.drawText(text, rect.translated(0.0f, -0.5f), juce::Justification::centred, false);
}

void Style::drawPlusMinus(juce::Graphics &g, juce::Rectangle<float> minus, juce::Rectangle<float> plus) const {
    g.setColour(colour("label"));
    juce::Path glyphs;
    glyphs.startNewSubPath(minus.getCentreX() - 4, minus.getCentreY());
    glyphs.lineTo(minus.getCentreX() + 4, minus.getCentreY());
    glyphs.startNewSubPath(plus.getCentreX() - 4, plus.getCentreY());
    glyphs.lineTo(plus.getCentreX() + 4, plus.getCentreY());
    glyphs.startNewSubPath(plus.getCentreX(), plus.getCentreY() - 4);
    glyphs.lineTo(plus.getCentreX(), plus.getCentreY() + 4);
    strokeRound(g, glyphs, 1.6f);
}

void Style::drawButton(juce::Graphics &g, juce::Rectangle<float> rect, const juce::String &text, bool isLit, bool pressed, juce::Colour accent) const {
    const juce::Rectangle<float> body = rect.reduced(0.5f);
    g.setColour(pressed ? colour("controlFace").darker(0.25f) : colour("controlFace"));
    g.fillRoundedRectangle(body, 5.0f);
    g.setColour(isLit ? accent : colour("controlBorder"));
    g.drawRoundedRectangle(body, 5.0f, 1.0f);
    drawText(g, text, rect, 12.0f, FontWeight::medium, isLit ? accentLight(accent) : colour("text"));
}

void Style::drawFocusRing(juce::Graphics &g, juce::Rectangle<float> rect, juce::Colour accent, float cornerRadius) const {
    g.setColour(accentLight(accent).withAlpha(0.9f));
    g.drawRoundedRectangle(rect.reduced(0.75f), cornerRadius, 1.5f);
}

// MARK: - Knob

void Style::drawKnob(juce::Graphics &g, juce::Rectangle<float> rect, float value, juce::Colour accent) const {
    const float side = std::min(rect.getWidth(), rect.getHeight());
    const juce::Point<float> centre = rect.getCentre();
    const float ringWidth = std::max(2.5f, side * 0.07f) * dressNumber("knobRingScale", 1.0f);
    const float ringRadius = side / 2 - ringWidth / 2 - 0.5f;
    const float clamped = juce::jlimit(0.0f, 1.0f, value);
    const bool halo = dressFlag("knobHalo");
    const float glowScale = glow();

    // Halo (P7-4): a soft disc of the accent round the whole knob
    if (halo) {
        const juce::Path ring = arc(centre, ringRadius, 0.0f, kPi * 2);
        glowUnder(g, strokedRound(ring, ringWidth), accent.withAlpha(0.7f), 5 * glowScale);
        g.setColour(accent.withAlpha(0.18f));
        strokeRound(g, ring, ringWidth);
    }

    // Track
    g.setColour(litFromAccent() ? accent.withAlpha(0.26f) : colour("knobTrack"));
    strokeRound(g, arc(centre, ringRadius, kArcStart, kArcStart + kArcSweep), ringWidth);

    // Value arc, with a glow
    if (clamped > 0.001f) {
        const juce::Path valueArc = arc(centre, ringRadius, kArcStart, kArcStart + kArcSweep * clamped);
        glowUnder(g, strokedRound(valueArc, ringWidth), accent.withAlpha(0.55f), 4 * glowScale);
        g.setColour(accent);
        strokeRound(g, valueArc, ringWidth);
        if (halo) {   // a bright core along the tube
            g.setColour(mixed(accent, juce::Colours::white, 0.45f).withAlpha(0.85f));
            strokeRound(g, valueArc, ringWidth * 0.35f);
        }
    }

    // Cap: drop shadow, radial gradient, hairline border
    const float capRadius = ringRadius - ringWidth / 2 - std::max(3.0f, side * 0.09f);
    if (capRadius <= 1) { return; }
    const juce::Rectangle<float> capRect(centre.x - capRadius, centre.y - capRadius, capRadius * 2, capRadius * 2);
    juce::Path cap;
    cap.addEllipse(capRect);
    glowUnder(g, cap, juce::Colours::black.withAlpha(0.7f), capRadius * 0.3f, { 0.0f, capRadius * 0.12f });
    g.setColour(colour("knobCapFill"));
    g.fillPath(cap);

    {
        juce::Graphics::ScopedSaveState clip(g);
        g.reduceClipRegion(cap);
        // PORT: Core Graphics draws a two-circle radial gradient from the highlight out to a circle
        // round the centre; JUCE's is concentric, so it is centred on the highlight and reaches the
        // far rim.
        const juce::Point<float> highlight(capRect.getX() + capRect.getWidth() * 0.38f, capRect.getY() + capRect.getHeight() * 0.30f);
        const float reach = capRadius * 1.05f + highlight.getDistanceFrom(centre);
        const auto &stops = layoutSkin.knobCap;
        juce::ColourGradient gradient(toColour(stops[0]), highlight.x, highlight.y, toColour(stops[3]), highlight.x + reach, highlight.y, true);
        gradient.addColour(0.45, toColour(stops[1]));
        gradient.addColour(0.75, toColour(stops[2]));
        g.setGradientFill(gradient);
        g.fillEllipse(capRect);
        // Brushed grain: faint spokes
        juce::Path spokes;
        for (int degrees = 0; degrees < 360; degrees += 3) {
            const float a = float(degrees) * kPi / 180.0f;
            spokes.startNewSubPath(onCircle(centre, capRadius * 0.35f, a));
            spokes.lineTo(onCircle(centre, capRadius, a));
        }
        g.setColour(juce::Colours::white.withAlpha(0.035f));
        g.strokePath(spokes, juce::PathStrokeType(0.5f));
        // Top highlight
        g.setColour(juce::Colours::white.withAlpha(0.16f));
        g.strokePath(arc(centre, capRadius - 1, kPi * 1.15f, kPi * 1.85f), juce::PathStrokeType(1.0f));
    }
    g.setColour(colour("knobCapBorder"));
    g.drawEllipse(capRect.reduced(0.5f), 1.0f);

    // Indicator
    const float angle = kArcStart + kArcSweep * clamped;
    juce::Path pointer;
    pointer.startNewSubPath(onCircle(centre, capRadius * 0.55f, angle));
    pointer.lineTo(onCircle(centre, capRadius - std::max(2.0f, side * 0.05f), angle));
    const float pointerWidth = std::max(2.0f, side * 0.06f);
    glowUnder(g, strokedRound(pointer, pointerWidth), accent.withAlpha(0.7f), 3 * glowScale);
    g.setColour(layoutSkin.palette.count("knobPointer") != 0 ? colour("knobPointer") : accent);
    strokeRound(g, pointer, pointerWidth);
}

// MARK: - Switch

void Style::drawSwitch(juce::Graphics &g, juce::Rectangle<float> rect, bool isOn, juce::Colour accent) const {
    // A pill at 26 : 14, centred: a square view draws a pill, not a stretched one
    const float width = std::min(rect.getWidth(), rect.getHeight() * 26 / 14);
    const float height = width * 14 / 26;
    const juce::Rectangle<float> track(rect.getCentreX() - width / 2, rect.getCentreY() - height / 2, width, height);
    const float radius = height / 2;

    if (isOn && glow() > 1) { glowUnder(g, rounded(track, radius), accent.withAlpha(0.6f), 5 * glow()); }
    g.setGradientFill(isOn ? juce::ColourGradient(accentOnTop(accent), track.getCentreX(), track.getY(), accent, track.getCentreX(), track.getBottom(), false)
                           : juce::ColourGradient(colour("switchOffTop"), track.getCentreX(), track.getY(), colour("switchOffBottom"), track.getCentreX(), track.getBottom(), false));
    g.fillRoundedRectangle(track, radius);
    g.setColour(isOn ? accentBorder(accent) : colour("wellBorder"));
    g.drawRoundedRectangle(track.reduced(0.5f), radius, 1.0f);

    const float thumbDiameter = height - 4;
    const float thumbX = isOn ? track.getRight() - 2 - thumbDiameter : track.getX() + 2;
    juce::Path thumb;
    thumb.addEllipse(thumbX, track.getY() + 2, thumbDiameter, thumbDiameter);
    glowUnder(g, thumb, juce::Colours::black.withAlpha(0.6f), 2.0f, { 0.0f, 1.0f });
    g.setColour(colour(isOn ? "thumbOn" : "thumbOff"));
    g.fillPath(thumb);
}

// MARK: - LFO target chip

void Style::drawLFOChip(juce::Graphics &g, juce::Rectangle<float> rect, const juce::String &text, bool lfo1, bool lfo2, juce::Colour accent) const {
    const juce::Rectangle<float> body = rect.reduced(0.5f);
    const bool active = lfo1 || lfo2;
    const juce::Colour top = active ? (litFromAccent() ? lit(accent).top : colour("chipActiveTop")) : colour("chipTop");
    const juce::Colour bottom = active ? (litFromAccent() ? lit(accent).bottom : colour("chipActiveBottom")) : colour("chipBottom");
    {
        juce::Graphics::ScopedSaveState clip(g);
        g.reduceClipRegion(rounded(body, 4.0f));
        g.setGradientFill(juce::ColourGradient(top, body.getCentreX(), body.getY(), bottom, body.getCentreX(), body.getBottom(), false));
        g.fillRect(body);
        // Its left half is LFO 1, its right half LFO 2: an active half shows a bar in its colour
        const juce::Rectangle<float> bar(body.getX(), body.getBottom() - 3, body.getWidth() / 2, 3.0f);
        if (lfo1) { g.setColour(accent); g.fillRect(bar); }
        if (lfo2) { g.setColour(colour("secondAccent")); g.fillRect(bar.translated(body.getWidth() / 2, 0.0f)); }
    }
    g.setColour(active ? accentBorder(accent) : colour("chipBorder"));
    g.drawRoundedRectangle(body, 4.0f, 1.0f);
    drawText(g, text, body.translated(0.0f, -0.5f), 10.5f, active ? FontWeight::medium : FontWeight::regular, active ? colour("text") : colour("chipText"));
}

// MARK: - LFO wave picker

void Style::drawWavePicker(juce::Graphics &g, juce::Rectangle<float> rect, int selected, juce::Colour accent) const {
    const float cellWidth = rect.getWidth() / 4;
    for (int index = 0; index < 4; ++index) {
        const juce::Rectangle<float> cell = juce::Rectangle<float>(rect.getX() + float(index) * cellWidth, rect.getY(), cellWidth, rect.getHeight()).reduced(1.0f, 0.0f);
        const bool on = index == selected;
        if (on) {
            const juce::Colour top = litFromAccent() ? lit(accent).top : colour("plateTop");
            const juce::Colour bottom = litFromAccent() ? lit(accent).bottom : colour("plateBottom");
            g.setGradientFill(juce::ColourGradient(top, cell.getCentreX(), cell.getY(), bottom, cell.getCentreX(), cell.getBottom(), false));
            g.fillRoundedRectangle(cell, 4.0f);
            g.setColour(litFromAccent() ? accentBorder(accent) : colour("chipBorder"));
            g.drawRoundedRectangle(cell.reduced(0.5f), 4.0f, 1.0f);
        }
        const juce::Rectangle<float> glyph = cell.reduced(cellWidth * 0.22f, rect.getHeight() * 0.28f);
        const float x0 = glyph.getX(), x1 = glyph.getRight(), xm = glyph.getCentreX(), y0 = glyph.getY(), y1 = glyph.getBottom(), ym = glyph.getCentreY();
        juce::Path path;
        switch (index) {
        case 0:   // sine
            path.startNewSubPath(x0, ym);
            path.cubicTo(x0 + glyph.getWidth() * 0.25f, y0 - glyph.getHeight() * 0.4f, xm - glyph.getWidth() * 0.25f, y0 - glyph.getHeight() * 0.4f, xm, ym);
            path.cubicTo(xm + glyph.getWidth() * 0.25f, y1 + glyph.getHeight() * 0.4f, x1 - glyph.getWidth() * 0.25f, y1 + glyph.getHeight() * 0.4f, x1, ym);
            break;
        case 1:   // square
            path.startNewSubPath(x0, y1); path.lineTo(x0, y0); path.lineTo(xm, y0); path.lineTo(xm, y1); path.lineTo(x1, y1); path.lineTo(x1, y0);
            break;
        case 2:   // ramp up
            path.startNewSubPath(x0, y1); path.lineTo(x1, y0); path.lineTo(x1, y1);
            break;
        default:  // ramp down
            path.startNewSubPath(x0, y0); path.lineTo(x0, y1); path.lineTo(x1, y0);
            break;
        }
        if (on) { glowUnder(g, strokedRound(path, 1.6f), accent.withAlpha(0.5f), 4 * glow()); }
        g.setColour(on ? (litFromAccent() ? juce::Colours::white : accent) : colour("glyph"));
        strokeRound(g, path, 1.6f);
    }
}

// MARK: - Sequencer

Style::StepperZones Style::stepperZones(juce::Rectangle<float> rect) {
    const float button = std::min(rect.getHeight(), rect.getWidth() * 0.3f);
    return { { rect.getX(), rect.getY(), button, rect.getHeight() },
             { rect.getX() + button, rect.getY(), rect.getWidth() - button * 2, rect.getHeight() },
             { rect.getRight() - button, rect.getY(), button, rect.getHeight() } };
}

void Style::drawStepper(juce::Graphics &g, juce::Rectangle<float> rect, const juce::String &text, int pressed) const {
    const StepperZones zones = stepperZones(rect);
    fillRounded(g, rect, 5.0f, colour("wellTop"), colour("wellBottom"), colour("wellBorder"));
    drawButtonFace(g, zones.minus.reduced(2.0f), pressed == 1);
    drawButtonFace(g, zones.plus.reduced(2.0f), pressed == 2);
    drawPlusMinus(g, zones.minus, zones.plus);
    drawText(g, text, zones.value, 13.0f, FontWeight::medium, colour("text"));
}

Style::TempoZones Style::tempoZones(juce::Rectangle<float> rect) {
    const float displayHeight = std::round(rect.getHeight() * 0.55f);
    const float gap = 4;
    const juce::Rectangle<float> buttons(rect.getX(), rect.getY() + displayHeight + gap, rect.getWidth(), rect.getHeight() - displayHeight - gap);
    return { { rect.getX(), rect.getY(), rect.getWidth(), displayHeight },
             { buttons.getX(), buttons.getY(), (buttons.getWidth() - gap) / 2, buttons.getHeight() },
             { buttons.getCentreX() + gap / 2, buttons.getY(), (buttons.getWidth() - gap) / 2, buttons.getHeight() } };
}

void Style::drawTempoStepper(juce::Graphics &g, juce::Rectangle<float> rect, const juce::String &text, int pressed, bool dimmed) const {
    const TempoZones zones = tempoZones(rect);
    fillRounded(g, zones.display, 5.0f, colour("wellTop"), colour("wellBottom"), colour("wellBorder"));
    drawText(g, text, zones.display, 14.0f, FontWeight::medium, colour(dimmed ? "dim" : "text"));
    drawButtonFace(g, zones.minus, pressed == 1);
    drawButtonFace(g, zones.plus, pressed == 2);
    drawPlusMinus(g, zones.minus, zones.plus);
}

void Style::drawTwoWaySwitch(juce::Graphics &g, juce::Rectangle<float> rect, bool isOn, const juce::String &left, const juce::String &right, juce::Colour accent) const {
    fillRounded(g, rect, 5.0f, colour("wellTop"), colour("wellBottom"), colour("wellBorder"));
    const juce::Rectangle<float> half(rect.getX() + 2, rect.getY() + 2, rect.getWidth() / 2 - 2, rect.getHeight() - 4);
    const juce::Rectangle<float> other = half.translated(rect.getWidth() / 2 - 2, 0.0f);
    const Lit colours = lit(accent);
    fillRounded(g, isOn ? other : half, 4.0f, colours.top, colours.bottom, colours.border);
    drawText(g, left, half, 12.0f, isOn ? FontWeight::regular : FontWeight::medium, colour(isOn ? "label" : "text"));
    drawText(g, right, other, 12.0f, isOn ? FontWeight::medium : FontWeight::regular, colour(isOn ? "text" : "label"));
}

void Style::drawDirection(juce::Graphics &g, juce::Rectangle<float> rect, int selected, juce::Colour accent) const {
    fillRounded(g, rect, 5.0f, colour("wellTop"), colour("wellBottom"), colour("wellBorder"));
    const float cellWidth = rect.getWidth() / 3;
    const Lit colours = lit(accent);
    for (int index = 0; index < 3; ++index) {
        const juce::Rectangle<float> cell = juce::Rectangle<float>(rect.getX() + float(index) * cellWidth, rect.getY(), cellWidth, rect.getHeight()).reduced(2.0f);
        const bool on = index == selected;
        if (on) { fillRounded(g, cell, 4.0f, colours.top, colours.bottom, colours.border); }
        const juce::Point<float> c = cell.getCentre();
        const float h = std::min(cell.getHeight(), 14.0f) / 2;
        juce::Path arrows;
        auto arrow = [&](bool up, float x) {
            const float tipY = up ? c.y - h : c.y + h, tailY = up ? c.y + h : c.y - h, headY = up ? tipY + 3.5f : tipY - 3.5f;
            arrows.startNewSubPath(x, tailY); arrows.lineTo(x, tipY);
            arrows.startNewSubPath(x - 3.5f, headY); arrows.lineTo(x, tipY); arrows.lineTo(x + 3.5f, headY);
        };
        if (index == 0) { arrow(true, c.x); } else if (index == 1) { arrow(true, c.x - 4); arrow(false, c.x + 4); } else { arrow(false, c.x); }
        g.setColour(on ? (litFromAccent() ? juce::Colours::white : accent) : colour("glyph"));
        strokeRound(g, arrows, 1.6f);
    }
}

juce::Rectangle<float> Style::faderCap(juce::Rectangle<float> bounds, float position) {
    // VerticalSlider: value 0 at `height - margin`, 1 at `margin`; the cap is drawn round that line
    const float travel = bounds.getHeight() - kFaderMargin * 2;
    const float y = bounds.getBottom() - kFaderMargin - juce::jlimit(0.0f, 1.0f, position) * travel;
    return { bounds.getCentreX() - kFaderCapWidth / 2, y - kFaderCapHeight / 2, kFaderCapWidth, kFaderCapHeight };
}

void Style::drawFader(juce::Graphics &g, juce::Rectangle<float> rect, juce::Rectangle<float> cap, juce::Colour accent) const {
    const float midX = rect.getCentreX();
    const float top = rect.getY() + cap.getHeight() / 2, bottom = rect.getBottom() - cap.getHeight() / 2;
    // Ticks
    juce::Path ticks;
    for (int i = 0; i <= 12; ++i) {
        const float y = std::round(top + (bottom - top) * float(i) / 12.0f) + 0.5f;
        const float reach = i % 6 == 0 ? 12.0f : 8.0f;
        ticks.startNewSubPath(midX - reach, y); ticks.lineTo(midX - 5, y);
        ticks.startNewSubPath(midX + 5, y); ticks.lineTo(midX + reach, y);
    }
    g.setColour(litFromAccent() ? accent.withAlpha(0.5f) : colour("faderTick"));
    g.strokePath(ticks, juce::PathStrokeType(1.0f));
    // Groove
    const juce::Rectangle<float> groove(midX - 2.5f, top, 5.0f, bottom - top);
    juce::ColourGradient grooveFill(colour("grooveEdge"), groove.getX(), groove.getCentreY(), colour("grooveEdge"), groove.getRight(), groove.getCentreY(), false);
    grooveFill.addColour(0.5, colour("grooveMid"));
    g.setGradientFill(grooveFill);
    g.fillRoundedRectangle(groove, 2.5f);
    // Lit track (P7-4): the groove below the cap, in the accent
    const bool litTrack = dressFlag("faderLitTrack");
    if (litTrack && cap.getCentreY() < bottom - 1) {
        const juce::Path track = rounded({ midX - 1.5f, cap.getCentreY(), 3.0f, bottom - cap.getCentreY() }, 1.5f);
        glowUnder(g, track, accent.withAlpha(0.7f), 3 * glow());
        g.setColour(accent);
        g.fillPath(track);
    }
    // Cap
    const juce::Colour capTop = litFromAccent() ? mixed(accent, juce::Colours::white, 0.35f) : colour("faderCapTop");
    const juce::Colour capBottom = litFromAccent() ? mixed(accent, juce::Colours::black, 0.3f) : colour("faderCapBottom");
    const juce::Colour capBorder = litFromAccent() ? mixed(accent, juce::Colours::white, 0.7f) : colour("faderCapBorder");
    const juce::Path capPath = rounded(cap, 3.0f);
    glowUnder(g, capPath, juce::Colours::black.withAlpha(0.7f), 4.0f, { 0.0f, 2.0f });
    if (litTrack) { glowUnder(g, capPath, accent.withAlpha(0.8f), 4 * glow()); }
    fillRounded(g, cap, 3.0f, capTop, capBottom, capBorder);
    const juce::Path stripe = rounded({ cap.getX() + 5, cap.getCentreY() - 1.5f, cap.getWidth() - 10, 3.0f }, 0.0f);
    glowUnder(g, stripe, accent.withAlpha(0.8f), 3 * glow());
    g.setColour(litFromAccent() ? mixed(accent, juce::Colours::black, 0.55f) : accent);
    g.fillPath(stripe);
}

void Style::drawStepButton(juce::Graphics &g, juce::Rectangle<float> rect, bool isOn, juce::Colour accent) const {
    if (isOn) {
        glowUnder(g, rounded(rect.reduced(0.5f), 2.0f), accent.withAlpha(0.6f), 5 * glow());
        fillRounded(g, rect, 2.0f, accentLight(accent), accent, accentBorder(accent));
    } else {
        fillRounded(g, rect, 2.0f, colour("stepOffTop"), colour("stepOffBottom"), colour("stepOffBorder"));
    }
}

void Style::drawNumberBox(juce::Graphics &g, juce::Rectangle<float> rect, const juce::String &text, bool isOn, bool isPlaying, juce::Colour accent) const {
    juce::Colour face, border = juce::Colours::transparentBlack;
    if (litFromAccent()) {
        face = isOn ? mixed(accent, juce::Colours::black, 0.2f) : mixed(colour("stepOffTop"), colour("stepOffBottom"), 0.5f);
        border = isOn ? mixed(accent, juce::Colours::white, 0.45f) : accent;
    } else {
        face = juce::Colour(isOn ? 0xff4a3410u : 0xff333336u);
    }
    g.setColour(face);
    g.fillRoundedRectangle(rect, 4.0f);
    if (isPlaying) {   // the playhead's ring, the classic control's orange
        g.setColour(dimmed(juce::Colour::fromFloatRGBA(0.881f, 0.426f, 0.0f, 1.0f)));
        g.drawRoundedRectangle(rect.reduced(1.0f), 4.0f, 2.0f);
    } else if (!border.isTransparent()) {
        g.setColour(border);
        g.drawRoundedRectangle(rect.reduced(0.5f), 4.0f, 1.0f);
    }
    drawText(g, text, rect, 12.0f, FontWeight::medium, colour("text"));
}

void Style::drawSegmented(juce::Graphics &g, juce::Rectangle<float> rect, const juce::StringArray &titles, int selected, juce::Colour accent) const {
    const juce::Colour face = litFromAccent() ? lit(accent).top : colour("buttonTop");
    const juce::Colour border = litFromAccent() ? accent : colour("wellBorder");
    g.setColour(colour("fieldBackground"));
    g.fillRoundedRectangle(rect.reduced(0.5f), 5.0f);
    g.setColour(border);
    g.drawRoundedRectangle(rect.reduced(0.5f), 5.0f, 1.0f);
    const int count = std::max(1, titles.size());
    const juce::Rectangle<float> inner = rect.reduced(2.0f);
    const float width = (inner.getWidth() - 2.0f * float(count - 1)) / float(count);   // PORT: equal segments; UIKit sizes each to its word
    for (int index = 0; index < titles.size(); ++index) {
        const juce::Rectangle<float> cell(inner.getX() + float(index) * (width + 2.0f), inner.getY(), width, inner.getHeight());
        if (index == selected) { g.setColour(face); g.fillRoundedRectangle(cell, 4.0f); }
        drawText(g, titles[index], cell, 11.0f, FontWeight::medium, colour(index == selected ? "text" : "label"));
    }
}

// MARK: - The classic drawings the desktop layout keeps

void Style::drawMorphSelector(juce::Graphics &g, juce::Rectangle<float> rect, float value) const {
    // MorphSelectorStyleKit, designed at 240 x 53. Its colours are the kit's own under every skin.
    // X3-9: PaintCode's own colours, so they are greyed here — the Mac renders this control to an
    // image and greys that (`S1Power.draw(in:)`)
    const juce::Colour selected = dimmed(juce::Colour::fromFloatRGBA(0.929f, 0.533f, 0.0f, 1.0f));
    const juce::Colour unselected = dimmed(juce::Colour::fromFloatRGBA(0.533f, 0.533f, 0.533f, 1.0f));
    const float w = rect.getWidth(), h = rect.getHeight(), v = juce::jlimit(0.0f, 1.0f, value);
    juce::Graphics::ScopedSaveState clip(g);
    g.reduceClipRegion(rect.toNearestIntEdges());
    // The highlight: 39 x 36 points at any size, as the kit draws it
    g.setColour(juce::Colour::fromFloatRGBA(0.275f, 0.271f, 0.278f, 0.5f));
    g.fillRect(juce::Rectangle<float>(rect.getX() + v * 0.79f * w + 6.0f / 260.0f * w - 0.14f, rect.getY() + 7, 39, 36));

    const float top = rect.getY() + 0.33962f * h, bottom = rect.getY() + 0.64151f * h, mid = rect.getY() + 0.49057f * h;
    auto x = [&](float fraction) { return rect.getX() + fraction * w; };
    auto stroke = [&](const juce::Path &path, bool on) {
        g.setColour(on ? selected : unselected);
        g.strokePath(path, juce::PathStrokeType(2.0f, juce::PathStrokeType::mitered, juce::PathStrokeType::butt));
    };
    juce::Path triangle;
    triangle.startNewSubPath(x(0.04309f), mid); triangle.lineTo(x(0.06625f), top); triangle.lineTo(x(0.11258f), bottom);
    triangle.lineTo(x(0.15120f), top); triangle.lineTo(x(0.17822f), mid);
    stroke(triangle, v <= 0.25f);
    juce::Path square;
    square.startNewSubPath(x(0.31246f), mid); square.lineTo(x(0.31246f), top); square.lineTo(x(0.35493f), top); square.lineTo(x(0.35493f), bottom);
    square.lineTo(x(0.39740f), bottom); square.lineTo(x(0.39740f), top); square.lineTo(x(0.43987f), top); square.lineTo(x(0.43987f), mid);
    stroke(square, v > 0.25f && v <= 0.5f);
    juce::Path pulse;
    pulse.startNewSubPath(x(0.59591f), mid); pulse.lineTo(x(0.59591f), top); pulse.lineTo(x(0.61908f), top); pulse.lineTo(x(0.61908f), bottom);
    pulse.lineTo(x(0.66155f), bottom); pulse.lineTo(x(0.66155f), top); pulse.lineTo(x(0.68471f), top); pulse.lineTo(x(0.68471f), mid);
    stroke(pulse, v > 0.5f && v <= 0.75f);
    juce::Path saw;
    saw.startNewSubPath(x(0.82504f), mid); saw.lineTo(x(0.85979f), top); saw.lineTo(x(0.85979f), bottom);
    saw.lineTo(x(0.92542f), top); saw.lineTo(x(0.92542f), bottom); saw.lineTo(x(0.96635f), mid);
    stroke(saw, v > 0.75f);
}

namespace {

/// AKADSRView.drawCurveCanvas's points, in the plot's own coordinates.
struct EnvelopeGeometry {
    juce::Point<float> initial, high, sustain, release, end;
    float height = 0, width = 0;

    EnvelopeGeometry(float w, float h, float attack, float decay, float sustainLevel, float releaseTime) : height(h), width(w) {
        const float clickRoom = 30;          // a zero attack is still grabbable
        const float oneSecond = 0.65f * w;   // one second is 65% of the width, whatever the times
        const float ceiling = 10;            // the envelope's peak
        const float sustainY = (1.0f - juce::jlimit(0.0f, 1.0f, sustainLevel)) * (h - ceiling) + ceiling;
        initial = { clickRoom, h };
        release = { clickRoom + oneSecond, sustainY };
        end = { release.x + std::max(0.0f, releaseTime) * oneSecond, h };
        high = { clickRoom + std::min(oneSecond * 0.75f, std::max(0.0f, attack) * oneSecond), ceiling };
        const float attackAndDecay = std::min(oneSecond * 0.75f, (std::max(0.0f, attack) + std::max(0.0f, decay)) * oneSecond);
        sustain = { std::max(high.x, clickRoom + attackAndDecay), sustainY };
    }
};

} // namespace

Style::EnvelopeAreas Style::envelopeAreas(juce::Rectangle<float> rect, float attack, float decay, float release) {
    const EnvelopeGeometry e(rect.getWidth(), rect.getHeight(), attack, decay, 0.5f, release);
    const float x = rect.getX(), y = rect.getY(), h = rect.getHeight();
    return { { x, y, e.high.x, h }, { x + e.high.x, y, e.release.x - e.high.x, h }, { x + e.release.x, y, rect.getWidth() - e.release.x, h } };
}

void Style::drawEnvelope(juce::Graphics &g, juce::Rectangle<float> rect, float attack, float decay, float sustain, float release,
                         juce::Colour curveColour, juce::Colour fill) const {
    {
        juce::Graphics::ScopedSaveState state(g);
        g.reduceClipRegion(rounded(rect, 4.0f));
        g.addTransform(juce::AffineTransform::translation(rect.getX(), rect.getY()));
        const EnvelopeGeometry e(rect.getWidth(), rect.getHeight(), attack, decay, sustain, release);

        juce::Path curve;
        curve.startNewSubPath(e.initial);
        curve.cubicTo(e.initial, { e.initial.x, e.high.y }, e.high);        // the attack bows up
        curve.cubicTo(e.high, { e.high.x, e.sustain.y }, e.sustain);        // the decay falls away
        curve.lineTo(e.release);                                            // the sustain is flat
        curve.cubicTo(e.release, { e.release.x, e.end.y }, e.end);          // the release

        if (!fill.isTransparent()) {
            juce::Path area = curve;
            area.lineTo(e.initial);
            area.closeSubPath();
            g.setColour(fill);
            g.fillPath(area);
        }
        g.setColour(curveColour);
        g.strokePath(curve, juce::PathStrokeType(1.0f));
    }
    g.setColour(colour("plotBorder"));
    g.drawRoundedRectangle(rect.reduced(0.5f), 4.0f, 1.0f);
}

void Style::drawCRTFrame(juce::Graphics &g, juce::Rectangle<float> rect, float radius) const {
    if (!layoutSkin.frameAccent) { return; }
    const juce::Colour accent = dimmed(toColour(*layoutSkin.frameAccent));   // X3-9: the screen goes grey with its zone
    // The glow, at CALayer's opacity 0.45, radius 6, offset zero — and OUTSIDE the frame only.
    // A layer's shadow falls behind opaque content; a JUCE drop shadow is painted, so without
    // this it tints the pad it is meant to be framing (seen, on the first cut).
    const juce::Path shape = rounded(rect, radius);
    {
        juce::Path outside;
        outside.addRectangle(rect.expanded(10.0f));
        outside.addRoundedRectangle(rect, radius);
        outside.setUsingNonZeroWinding(false);           // the frame's inside is a hole
        juce::Graphics::ScopedSaveState clip(g);
        g.reduceClipRegion(outside);
        glowUnder(g, shape, accent.withAlpha(0.45f), 6.0f);
    }
    // The scanlines: a 4 x 3 point tile, black at 16% on its third row, over the content.
    {
        juce::Graphics::ScopedSaveState clip(g);
        g.reduceClipRegion(shape);
        g.setColour(juce::Colours::black.withAlpha(0.16f));
        for (float line = rect.getY() + 2.0f; line < rect.getBottom(); line += 3.0f) {
            g.fillRect(rect.getX(), line, rect.getWidth(), 1.0f);
        }
    }
    g.setColour(accent.withAlpha(0.9f));
    g.drawRoundedRectangle(rect.reduced(0.5f), radius, 1.0f);
}

void Style::drawPadParticles(juce::Graphics &g, juce::Rectangle<float> rect, float age, int seed,
                             const std::vector<PadTouch> &trail) const {
    if (age <= 0) { return; }
    // Upstream's CAEmitterCell for the MOTION: birthRate 80/s, lifetime 1.70 s, velocity 190 +/- 60,
    // emissionRange 2*pi. The LOOK is the owner's (2026-09-21): upstream's spark is a soft 64-point
    // disc at a fraction of its size and under a quarter opaque at its brightest, which on this
    // pad was "barely visible". These are one to three points across with a hot core, nearly
    // opaque while young. And the emitter is the TOUCH, not the pad's centre.
    const juce::Colour orange = juce::Colour::fromFloatRGBA(0.902f, 0.533f, 0.008f, 1.0f);
    const juce::Colour core = orange.interpolatedWith(juce::Colours::white, 0.65f);
    const float lifetime = kPadParticleLifetime, birthRate = 80.0f;
    const int alive = int(lifetime * birthRate);
    // Where the touch was `life` seconds ago: the last place it was seen at or before then.
    const auto origin = [&trail, &rect, age](float life) {
        if (trail.empty()) { return rect.getCentre(); }
        const float born = age - life;
        for (auto touch = trail.rbegin(); touch != trail.rend(); ++touch) {
            if (touch->at <= born) { return rect.getPosition() + touch->where; }
        }
        return rect.getPosition() + trail.front().where;
    };
    juce::Random random(seed * 7919 + 13);
    juce::Graphics::ScopedSaveState clip(g);
    g.reduceClipRegion(rounded(rect, 4.0f));
    for (int i = 0; i < alive; ++i) {
        // Each particle was born one 80th of a second apart; the oldest is `lifetime` old.
        const float born = age - float(i) / birthRate;
        // drawn in the same order whatever is skipped, so a star keeps its heading as it ages
        const float angle = random.nextFloat() * juce::MathConstants<float>::twoPi;
        const float speed = 190.0f + (random.nextFloat() * 2.0f - 1.0f) * 60.0f;
        const float grain = random.nextFloat();
        if (born < 0) { continue; }
        const float life = std::fmod(born, lifetime);
        const float size = 1.0f + grain * 1.4f + 0.5f * life;
        const juce::Point<float> at = origin(life).getPointOnCircumference(speed * life, angle);
        if (!rect.contains(at)) { continue; }
        // In over a fifth of a second, then out over the rest of its life.
        const float alpha = juce::jlimit(0.0f, 1.0f, life * 5.0f) * std::sqrt(1.0f - life / lifetime);
        g.setColour(dimmed(orange).withAlpha(alpha));
        g.fillEllipse(juce::Rectangle<float>(size, size).withCentre(at));
        g.setColour(dimmed(core).withAlpha(alpha));
        g.fillEllipse(juce::Rectangle<float>(size * 0.5f, size * 0.5f).withCentre(at));
    }
}

void Style::drawPad(juce::Graphics &g, juce::Rectangle<float> rect, float x, float y) const {
    g.setColour(colour("fieldBackground"));
    g.fillRoundedRectangle(rect, 4.0f);
    {
        juce::Graphics::ScopedSaveState clip(g);
        g.reduceClipRegion(rounded(rect, 4.0f));
        // TouchPointStyleKit, designed at 61 x 61 and shown at 63; its orange is the kit's own
        const juce::Colour orange = dimmed(juce::Colour::fromFloatRGBA(0.902f, 0.533f, 0.008f, 1.0f));   // X3-9: grey with the power out
        // …at HALF that, at the owner's word (2026-09-21): ring, block, stroke and glow alike
        const float scale = 63.0f / 61.0f * kPadTargetScale;
        const juce::Point<float> centre(rect.getX() + juce::jlimit(0.0f, 1.0f, x) * rect.getWidth(),
                                        rect.getY() + (1.0f - juce::jlimit(0.0f, 1.0f, y)) * rect.getHeight());
        const juce::Path ring = rounded(juce::Rectangle<float>(39 * scale, 39 * scale).withCentre(centre), 8 * scale);
        const juce::Path block = rounded(juce::Rectangle<float>(23 * scale, 23 * scale).withCentre(centre), 4 * scale);
        glowUnder(g, strokedRound(ring, 4 * scale), orange.withAlpha(0.6f), 12 * scale);
        g.setColour(orange.withAlpha(0.5f));
        g.strokePath(ring, juce::PathStrokeType(4 * scale));
        glowUnder(g, block, orange.withAlpha(0.8f), 12 * scale);
        g.setColour(orange);
        g.fillPath(block);
    }
    g.setColour(colour("plotBorder"));
    g.drawRoundedRectangle(rect.reduced(0.5f), 4.0f, 1.0f);
}

} // namespace s1ui
