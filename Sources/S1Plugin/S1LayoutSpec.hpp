//
//  S1LayoutSpec.hpp
//  Arcade Ruins
//
//  X3-1 (ADR-083): where everything in the interface sits, what each control is bound to, the
//  type and both skins' colours — read from `Layout/layout-spec.json`. No JUCE in here.
//
//  The file is MEASURED, not typed: `Tests/SynthOneTests/LayoutSpecFixtureTests.swift` builds the
//  Mac desktop layout at its design size (1440 × 900) under each skin and writes down where Auto
//  Layout put every section, control, button and label, with the parameter each control drives
//  (`Scripts/write-layout-spec.sh`; the same test fails in the normal suite when the file is
//  stale). Cabinet's rectangle table (`S1SkinTemplate`, the painting's pixels) is carried as it is.
//  Change the Mac layout and regenerate; never edit the JSON, and never type a frame in C++.
//
//  Every frame is in points at the design size, origin top-left, in the window. The interface
//  scales uniformly from there (X3-7), so nothing here is a fraction or a constraint.
//
#pragma once

#include <array>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <vector>

#include "S1Parameter.h"

namespace s1plugin {

struct LayoutRect {
    float x = 0, y = 0, width = 0, height = 0;
    float right() const { return x + width; }
    float bottom() const { return y + height; }
    bool contains(const LayoutRect &other, float slack = 0) const {
        return other.x >= x - slack && other.y >= y - slack && other.right() <= right() + slack && other.bottom() <= bottom() + slack;
    }
};

struct LayoutColour {
    std::uint8_t red = 0, green = 0, blue = 0, alpha = 255;
};

enum class LayoutControlKind {
    knob, toggle, twoWay, chip, wavePicker, morphSelector, stepper, tempo, direction,
    stepOctave, stepFader, stepOn, segmented, other
};

struct LayoutSection {
    std::string key;                     ///< "OSC 1", "Mix", "Sequencer", "Pads" … — the Mac layout's keys
    std::string title;                   ///< as drawn: "BITCRUSHER & AUTO PAN"
    LayoutRect frame, header, body;
    std::optional<LayoutColour> accent;  ///< Cabinet's neon for this section (ADR-048); none under Studio
};

/// One control and the parameter it drives.
struct LayoutControl {
    std::string id;                      ///< unique within a skin: "<section>.<parameter>"
    S1Parameter parameter = S1Parameter::index1;
    std::string parameterID;             ///< the enum case's name — S1ParameterCatalog's id
    LayoutControlKind kind = LayoutControlKind::other;
    std::string macClass;                ///< the Mac control's class, for whoever ports its drawing
    std::string section;                 ///< a section's key, or "toolbar" / "playBar" / "statusBar"
    LayoutRect frame;                    ///< a knob's is its square: the diameter is the width
    /// The Mac knob holds a 0…1 position of a tempo-syncable rate (ADR-022); the JUCE control
    /// attaches to the host parameter's plain value like any other.
    bool dependent = false;
    std::string title;
    std::optional<LayoutRect> titleFrame, valueFrame;   ///< a cell's lines, the cell's full width; text centred
    std::vector<std::string> choices;
};

/// A view that shows parameters without being one control: an envelope plot, an XY pad.
struct LayoutDisplay {
    std::string id, kind, section;       ///< kind: "adsr" | "xyPad"
    LayoutRect frame;
    std::map<std::string, S1Parameter> parameters;   ///< by role: attack/decay/sustain/release, x/y
    /// An envelope plot's line and the fill under it, as the Mac view has them under this skin
    /// (the storyboard's under Studio, the section's accent under Cabinet). No fill: not drawn.
    std::optional<LayoutColour> curve, fill;
};

/// Everything else a person sees or presses: the preset name, toolbar and play-bar buttons, the scope.
struct LayoutItem {
    std::string id, kind, region, title;
    LayoutRect frame;
};

struct LayoutLabel {
    std::string text, region, font, align;
    float size = 0;
    LayoutColour colour;
    LayoutRect frame;
};

struct LayoutFont {
    std::string name, family;
    float size = 0, kern = 0;
    bool uppercase = false;
};

/// Cabinet's painted window (ADR-059): rectangles in the painting's own pixels.
/// X3-6 (ADR-088): the cabinet's stick, which the painting has cut out of it. Two sprites and
/// where they sit, in the painting's own pixels; the view is `reach` and the rod turns about
/// `pivot`. Measured by the Swift writer from `S1TemplateJoystick`, never typed here.
struct LayoutJoystick {
    std::string ballImage, rodImage;
    LayoutRect ballBox, rodBox, reach;
    float pivotX = 0, pivotY = 0;
};

/// X3-9 (ADR-091): the cabinet's two red buttons and what they darken. In the painting's pixels,
/// measured by the Swift writer from `S1TemplatePower` (ADR-062), never typed here.
struct LayoutPower {
    std::string darkImage;                       ///< the grey copy of the painting
    LayoutRect off, on;                          ///< the left button cuts the power, the right restores it
    float frameReach = 11;                       ///< how far a section's frame and its glow reach past its inner edge
    std::map<std::string, LayoutRect> zones;     ///< the four pieces of the chrome: display, buttons, screen, bar
};

struct LayoutTemplate {
    std::string image;
    float width = 0, height = 0;
    std::map<std::string, LayoutRect> sections;   ///< by section key
    std::map<std::string, LayoutRect> places;     ///< presetField, previous, next, wordmark, scope, save, record, panic, settings, presets, playBar, statusBar
    float diceX = 0, diceY = 0;
    std::optional<LayoutJoystick> joystick;
    std::optional<LayoutPower> power;
    /// A painting rectangle in window points at `designWidth` × `designHeight`.
    LayoutRect inWindow(const LayoutRect &painted, float designWidth, float designHeight) const;
};

struct LayoutSkin {
    std::string key, title;              ///< "studio" / "cabinet"
    bool isDefault = false;
    float glow = 1;
    std::map<std::string, LayoutColour> palette;   ///< S1Palette's fields by name
    std::vector<LayoutColour> knobCap;             ///< four stops, highlight to rim
    std::map<std::string, float> dress;            ///< S1SkinDress's numbers and switches (0 / 1)
    std::optional<LayoutColour> frameAccent, sectionGlow;
    std::optional<LayoutTemplate> painting;
    std::vector<float> rowHeights;       ///< Studio: 158 / 220 / 122 / the rest
    std::vector<float> knobSizes;
    std::map<std::string, LayoutRect> regions;     ///< toolbar, editor (Studio), playBar, statusBar
    std::vector<LayoutSection> sections;
    std::vector<LayoutControl> controls;
    std::vector<LayoutDisplay> displays;
    std::vector<LayoutItem> items;
    std::vector<LayoutLabel> labels;

    const LayoutSection *section(const std::string &sectionKey) const;
    const LayoutControl *control(const std::string &controlID) const;
    /// A palette colour by S1Palette's field name; opaque magenta when there is none, to be seen.
    LayoutColour colour(const std::string &name) const;
};

struct LayoutSpec {
    static constexpr int kVersion = 1;

    int version = 0;
    float designWidth = 0, designHeight = 0, minimumWidth = 0, minimumHeight = 0;
    std::map<std::string, float> metrics;
    std::map<std::string, LayoutFont> fonts;       ///< by role: sectionTitle, controlTitle, controlValue, caption, button, presetName, hint
    std::vector<LayoutSkin> skins;

    const LayoutSkin *skin(const std::string &skinKey) const;
    const LayoutSkin *defaultSkin() const;

    /// Nothing, and `error` says why, for text that is not a version-1 specification: not JSON, a
    /// missing field, a frame that is not four numbers, a parameter that is not an S1Parameter.
    static std::optional<LayoutSpec> parse(const std::string &json, std::string *error = nullptr);
};

const char *layoutControlKindName(LayoutControlKind);

} // namespace s1plugin
