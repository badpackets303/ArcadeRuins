// X3-1 (ADR-083): the layout specification — the file the Mac layout wrote, as this binary carries
// it and as the plugin's reader understands it: every control on a real parameter and inside its
// section, the rows and knob sizes the plan names, Cabinet's sections on the painting's
// rectangles, both palettes with the same colours, and which parameters have no control at all.
//
//   argv[1]  Sources/S1Plugin/Layout/layout-spec.json   written by the Swift test LayoutSpecFixtureTests
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "S1LayoutSpec.hpp"
#include "S1LinkedLayoutSpec.h"
#include "S1ParameterCatalog.hpp"

namespace {

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

std::string readFile(const std::string &path) {
    std::ifstream in(path, std::ios::binary);
    std::ostringstream text;
    text << in.rdbuf();
    return text.str();
}

std::string replaced(std::string text, const std::string &from, const std::string &to) {
    const size_t at = text.find(from);
    if (at != std::string::npos) { text.replace(at, from.size(), to); }
    return text;
}

/// The parameters the Mac desktop layout gives no control (26 of 150), and where each lives
/// there. X3-3's "every parameter reachable" starts from this list; it changes only with the Mac
/// layout, and then on purpose.
const std::set<std::string> kWithoutControl = {
    // The Dev panel — dropped from the JUCE build's scope (ADR-056)
    "filterMix", "detuningMultiplier", "bitCrushDepth",
    "compressorMasterRatio", "compressorReverbInputRatio", "compressorReverbWetRatio",
    "compressorMasterThreshold", "compressorReverbInputThreshold", "compressorReverbWetThreshold",
    "compressorMasterAttack", "compressorReverbInputAttack", "compressorReverbWetAttack",
    "compressorMasterRelease", "compressorReverbInputRelease", "compressorReverbWetRelease",
    "compressorMasterMakeupGain", "compressorReverbInputMakeupGain", "compressorReverbWetMakeupGain",
    "delayInputCutoffTrackingRatio", "delayInputResonance", "portamentoHalfTime", "oscBandlimitIndexOverride",
    // The wheels and the Wheels popover (X3-8)
    "pitchbend", "pitchbendMinSemitones", "pitchbendMaxSemitones",
    // The Tunings panel (X3-5)
    "frequencyA4"
};

} // namespace

int main(int argc, char **argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: PluginLayoutSpecTests <layout-spec.json>\n");
        return 2;
    }
    using namespace s1plugin;

    // The binary carries the repository's file
    const std::string onDisk = readFile(argv[1]);
    check(!onDisk.empty(), "the repository's layout-spec.json was read", double(onDisk.size()));
    check(S1LinkedLayoutSpecText() == onDisk, "the linked-in specification is the repository's file, byte for byte", double(S1LinkedLayoutSpecText().size()));

    std::string error;
    const std::optional<LayoutSpec> parsed = LayoutSpec::parse(onDisk, &error);
    check(parsed.has_value(), "it parses" + (error.empty() ? std::string() : ": " + error), parsed ? 1 : 0);
    if (!parsed) { return 1; }
    const LayoutSpec &spec = *parsed;
    check(S1LinkedLayoutSpec().skins.size() == spec.skins.size(), "S1LinkedLayoutSpec() is the same specification", double(S1LinkedLayoutSpec().skins.size()));

    check(spec.version == 1, "version 1", spec.version);
    check(spec.designWidth == 1440 && spec.designHeight == 900, "designed at 1440 x 900", spec.designWidth);
    for (const char *role : { "sectionTitle", "controlTitle", "controlValue", "caption", "button", "presetName", "hint" }) {
        const auto font = spec.fonts.find(role);
        check(font != spec.fonts.end() && font->second.size >= 11 && !font->second.name.empty(), std::string("a font for ") + role,
              font != spec.fonts.end() ? font->second.size : 0);
    }
    for (const char *metric : { "toolbarHeight", "playBarHeight", "statusBarHeight", "sectionHeaderHeight", "sectionCornerRadius", "editorPadding", "rowGap" }) {
        check(spec.metrics.count(metric) == 1, std::string("metric ") + metric, spec.metrics.count(metric) ? spec.metrics.at(metric) : -1);
    }

    const LayoutSkin *studio = spec.skin("studio");
    const LayoutSkin *cabinet = spec.skin("cabinet");
    check(studio != nullptr && cabinet != nullptr && spec.skins.size() == 2, "two skins: studio and cabinet", double(spec.skins.size()));
    if (studio == nullptr || cabinet == nullptr) { return 1; }
    check(spec.defaultSkin() == cabinet, "Cabinet is the default (ADR-064)", spec.defaultSkin() == cabinet);

    const LayoutRect window { 0, 0, spec.designWidth, spec.designHeight };
    for (const LayoutSkin *skin : { studio, cabinet }) {
        const std::string name = skin->key + ": ";
        check(skin->sections.size() == 15, name + "fifteen sections", double(skin->sections.size()));
        check(skin->palette.size() == cabinet->palette.size() || skin->palette.size() + 1 == cabinet->palette.size(),
              name + "the palette has every colour (knobPointer is Cabinet's alone)", double(skin->palette.size()));

        // Every control: a real parameter (the reader refuses others), inside its section, inside the window
        int outside = 0, outsideWindow = 0, unknownKind = 0, untitledKnobs = 0;
        std::set<std::string> covered;
        for (const LayoutControl &control : skin->controls) {
            covered.insert(control.parameterID);
            if (std::string(parameterID(int(control.parameter))) != control.parameterID) { ++outside; }
            if (!window.contains(control.frame, 0.5f)) { ++outsideWindow; std::printf("      outside the window: %s\n", control.id.c_str()); }
            if (control.kind == LayoutControlKind::other) { ++unknownKind; std::printf("      no kind for %s (%s)\n", control.id.c_str(), control.macClass.c_str()); }
            if (control.kind == LayoutControlKind::knob && (control.title.empty() || !control.titleFrame || !control.valueFrame)) { ++untitledKnobs; }
            if (const LayoutSection *section = skin->section(control.section)) {
                // A header accessory sits in the header strip; everything else in the body
                if (!section->frame.contains(control.frame, 0.5f)) { ++outside; std::printf("      outside its section: %s\n", control.id.c_str()); }
            } else if (control.section != "playBar" && control.section != "toolbar") {
                ++outside;
                std::printf("      no such section: %s in \"%s\"\n", control.id.c_str(), control.section.c_str());
            }
        }
        for (const LayoutDisplay &display : skin->displays) {
            for (const auto &entry : display.parameters) { covered.insert(parameterID(int(entry.second))); }
            const LayoutSection *section = skin->section(display.section);
            if (section == nullptr || !section->body.contains(display.frame, 0.5f)) { ++outside; }
        }
        check(skin->controls.size() == 125, name + "125 controls", double(skin->controls.size()));
        check(outside == 0, name + "every control and display sits inside its section", outside);
        check(outsideWindow == 0, name + "and inside the window", outsideWindow);
        check(unknownKind == 0, name + "every control's Mac class has a kind the controls kit knows", unknownKind);
        check(untitledKnobs == 0, name + "every knob has its title line and its readout line", untitledKnobs);
        check(skin->displays.size() == 4, name + "two envelope plots and two XY pads", double(skin->displays.size()));

        std::set<std::string> without;
        for (int address = 0; address < int(S1Parameter::S1ParameterCount); ++address) {
            if (covered.count(parameterID(address)) == 0) { without.insert(parameterID(address)); }
        }
        for (const std::string &parameter : without) { if (kWithoutControl.count(parameter) == 0) { std::printf("      lost its control: %s\n", parameter.c_str()); } }
        for (const std::string &parameter : kWithoutControl) { if (without.count(parameter) == 0) { std::printf("      has a control now: %s\n", parameter.c_str()); } }
        check(without == kWithoutControl, name + "124 of 150 parameters have a control; the other 26 are the known list", double(covered.size()));

        for (const LayoutSection &section : skin->sections) {
            const bool whole = window.contains(section.frame, 0.5f) && section.frame.contains(section.header, 0.5f) && section.frame.contains(section.body, 0.5f)
                && std::fabs(section.header.height + section.body.height - section.frame.height) < 0.75f;
            if (!whole) { check(false, name + section.key + " is a header over a body, in the window", section.frame.height); }
        }
        for (const char *item : { "presetField", "presetName", "dice", "scope", "button.Save", "button.Panic", "button.Settings",
                                  "button.Previous preset", "button.Next preset", "button.Hold", "button.Mono", "octave", "tuning", "button.Snap" }) {
            const bool found = std::any_of(skin->items.begin(), skin->items.end(), [&](const LayoutItem &i) { return i.id == item; });
            if (!found) { check(false, name + "item " + item, 0); }
        }
        // Not in the specification (docs/private; X3-6 scopes them)
        const bool extras = std::any_of(skin->items.begin(), skin->items.end(), [](const LayoutItem &i) { return i.title.find("power") != std::string::npos; });
        check(!extras, name + "nothing the specification leaves to X3-6", extras);
    }

    // Studio: the rows and knob sizes the plan names (158 / 220 / 122 / the rest; 44 / 46 / 48 / 52 / 68)
    check(studio->rowHeights.size() == 4 && studio->rowHeights[0] == 158 && studio->rowHeights[1] == 220 && studio->rowHeights[2] == 122,
          "Studio's rows are 158, 220 and 122 points", studio->rowHeights.empty() ? 0 : studio->rowHeights[0]);
    check(studio->rowHeights.size() == 4 && studio->rowHeights[3] == 247, "and the fourth takes the rest: 247 at 900 tall", studio->rowHeights.size() == 4 ? studio->rowHeights[3] : 0);
    for (float size : { 44.0f, 46.0f, 48.0f, 52.0f, 68.0f }) {
        check(std::find(studio->knobSizes.begin(), studio->knobSizes.end(), size) != studio->knobSizes.end(), "Studio has knobs of this diameter", size);
    }
    check(studio->knobSizes == std::vector<float>({ 30, 40, 44, 46, 48, 52, 68 }), "and the LFOs' 40 and the sequencer's 30: seven sizes in all", double(studio->knobSizes.size()));
    check(!studio->painting.has_value() && studio->regions.count("toolbar") == 1 && studio->regions.count("editor") == 1, "Studio lays out in rows under a toolbar", double(studio->regions.size()));
    const LayoutControl *cutoff = studio->control("Filter.cutoff");
    check(cutoff != nullptr && cutoff->frame.width == 68 && cutoff->frame.height == 68 && cutoff->parameter == S1Parameter::cutoff && cutoff->title == "Cutoff",
          "Studio's cutoff is a 68-point knob on the cutoff parameter", cutoff ? cutoff->frame.width : 0);
    int accented = 0;
    for (const LayoutSection &section : studio->sections) { if (section.accent) { ++accented; } }
    check(accented == 0, "Studio gives no section an accent of its own", accented);

    // Cabinet: the painting's rectangle table as it is, and the sections on it
    check(cabinet->painting.has_value(), "Cabinet has the painting's rectangle table", cabinet->painting.has_value());
    if (cabinet->painting) {
        const LayoutTemplate &painting = *cabinet->painting;
        check(painting.width == 1585 && painting.height == 992, "the painting is 1585 x 992", painting.width);
        check(painting.sections.size() == 15 && painting.places.size() == 12, "fifteen section rectangles and twelve places", double(painting.sections.size()));
        float worst = 0;
        for (const LayoutSection &section : cabinet->sections) {
            const auto painted = painting.sections.find(section.key);
            if (painted == painting.sections.end()) { check(false, "the painting has a rectangle for " + section.key, 0); continue; }
            const LayoutRect expected = painting.inWindow(painted->second, spec.designWidth, spec.designHeight);
            worst = std::max({ worst, std::fabs(expected.x - section.frame.x), std::fabs(expected.y - section.frame.y),
                               std::fabs(expected.right() - section.frame.right()), std::fabs(expected.bottom() - section.frame.bottom()) });
        }
        // Auto Layout puts each edge on the display's half-point grid, so an edge is up to 0.25 off
        // the fraction and a rounded pair a little more: 0.61 measured.
        check(worst <= 0.75f, "every Cabinet section sits on its painted rectangle, to three quarters of a point", worst);
        const LayoutRect mix = painting.sections.at("Mix");
        check(mix.x == 643 && mix.y == 118 && mix.width == 478 && mix.height == 168, "Mix is painted at 643, 118 to 1121, 286 (S1Skin.swift)", mix.x);
    }
    accented = 0;
    for (const LayoutSection &section : cabinet->sections) { if (section.accent) { ++accented; } }
    check(accented == 15, "Cabinet gives every section its neon (ADR-048)", accented);
    const LayoutSection *mixSection = cabinet->section("Mix");
    check(mixSection != nullptr && mixSection->accent && mixSection->accent->red == 0x3d && mixSection->accent->green == 0xff && mixSection->accent->blue == 0xb4,
          "Mix is mint, #3dffb4", mixSection && mixSection->accent ? mixSection->accent->green : 0);
    const LayoutColour studioAccent = studio->colour("accent"), cabinetAccent = cabinet->colour("accent");
    check(studioAccent.red == 230 && studioAccent.green == 136 && studioAccent.blue == 2, "Studio's accent is upstream's orange, #e68802", studioAccent.red);
    check(cabinetAccent.red == 0xff && cabinetAccent.green == 0x7a && cabinetAccent.blue == 0x1a, "Cabinet's is #ff7a1a", cabinetAccent.green);
    check(studio->palette.count("knobPointer") == 0 && cabinet->palette.count("knobPointer") == 1, "a knob's pointer is the accent under Studio, white under Cabinet", double(cabinet->palette.count("knobPointer")));
    check(cabinet->dress.count("knobRingScale") == 1 && cabinet->dress.at("knobRingScale") == 1.5f && cabinet->dress.at("bareSections") == 1.0f
              && studio->dress.at("bareSections") == 0.0f, "the dress came through: Cabinet's ring is 1.5x and its sections are bare", cabinet->dress.count("knobRingScale") ? cabinet->dress.at("knobRingScale") : 0);

    // The same controls under both skins, by id and parameter
    int unmatched = 0;
    for (const LayoutControl &control : studio->controls) {
        const LayoutControl *other = cabinet->control(control.id);
        if (other == nullptr || other->parameter != control.parameter || other->kind != control.kind) { ++unmatched; }
    }
    check(unmatched == 0 && studio->controls.size() == cabinet->controls.size(), "both skins hold the same controls on the same parameters", unmatched);

    // What is not a specification is refused, and says where
    struct Bad { const char *what; std::string json; const char *mention; };
    const std::vector<Bad> bad = {
        { "an empty file", "", "JSON" },
        { "JSON that is not a specification", "[1, 2, 3]", "spec" },
        { "another version", replaced(onDisk, "\"version\": 1", "\"version\": 2"), "version" },
        { "a parameter that does not exist", replaced(onDisk, "\"parameter\": \"cutoff\"", "\"parameter\": \"cutOff\""), "cutOff" },
        { "a frame of three numbers", replaced(onDisk, "\"frame\": [10, 58, 184, 158]", "\"frame\": [10, 58, 184]"), "frame" },
        { "a colour that is not one", replaced(onDisk, "\"accent\": \"#e68802ff\"", "\"accent\": \"orange\""), "accent" },
        { "a control listed twice", replaced(onDisk, "\"id\": \"OSC 2.index2\"", "\"id\": \"OSC 1.index1\""), "twice" }
    };
    for (const Bad &entry : bad) {
        std::string why;
        const bool refused = !LayoutSpec::parse(entry.json, &why).has_value();
        check(refused && why.find(entry.mention) != std::string::npos, std::string("refused: ") + entry.what + ": \"" + why + "\"", refused);
    }

    std::printf("%s\n", failures == 0 ? "PASSED" : "FAILED");
    return failures == 0 ? 0 : 1;
}
