// X3-6 (ADR-088): the interface's typeface where the system has no Avenir Next Condensed — that
// is, on Windows and Linux. Barlow Condensed is linked into the plugin (SIL OFL 1.1, the owner's
// choice of 2026-09-20), and what has to be true of it is not "it loads" but **every label the
// specification measured on the Mac still fits the frame it was measured in**.
//
// This runs on macOS too, where Avenir Next Condensed exists: `Style::preferLinkedTypeface(true)`
// makes a Style take the linked face anyway, so the check cannot quietly pass by testing Avenir.
#if defined(__clang__) || defined(__GNUC__)
#pragma GCC diagnostic ignored "-Wfloat-equal"
#endif
#include <cstdio>
#include <string>
#include <vector>

#include "S1LinkedLayoutSpec.h"
#include "UI/S1KitStyle.h"

namespace {

int failures = 0;
void check(bool ok, const std::string &what, double measured) {
    std::printf("%s  %s (measured %.6g)\n", ok ? "ok  " : "FAIL", what.c_str(), measured);
    if (!ok) { ++failures; }
}

/// JUCE 9 took `Font::getStringWidthFloat` away; this is its replacement.
float widthOf(const juce::Font &font, const juce::String &text) {
    return juce::GlyphArrangement::getStringWidth(font, text);
}

s1ui::FontWeight weightOf(const std::string &font) {
    // The specification records the Mac face's own style name.
    if (font.find("DemiBold") != std::string::npos || font.find("Demi Bold") != std::string::npos) { return s1ui::FontWeight::demiBold; }
    if (font.find("Medium") != std::string::npos) { return s1ui::FontWeight::medium; }
    return s1ui::FontWeight::regular;
}

} // namespace

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);
    const juce::ScopedJuceInitialiser_GUI gui;
    const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();

    // MARK: the face is there, and it is the one that was chosen
    {
        s1ui::Style::preferLinkedTypeface(true);
        const s1plugin::LayoutSkin *skin = spec.defaultSkin();
        check(skin != nullptr, "the specification has a skin to dress", 0);
        if (skin == nullptr) { return 1; }
        const s1ui::Style style(*skin);
        int named = 0;
        for (const s1ui::FontWeight weight : { s1ui::FontWeight::regular, s1ui::FontWeight::medium, s1ui::FontWeight::demiBold }) {
            const juce::Font font = style.font(13.0f, weight);
            if (font.getTypefaceName().containsIgnoreCase("Barlow")) { ++named; }
        }
        check(named == 3, "all three weights are Barlow Condensed, from the binary and not the system", named);
        const juce::Font regular = style.font(13.0f), demi = style.font(13.0f, s1ui::FontWeight::demiBold);
        check(widthOf(regular, "Cutoff") > 0, "it measures text", widthOf(regular, "Cutoff"));
        check(widthOf(demi, "CUTOFF") > widthOf(regular, "CUTOFF") * 0.98f,
              "and the demi-bold weight is not narrower than the regular", widthOf(demi, "CUTOFF"));
        // No squeeze: the old fallback narrowed the default sans to 0.82 to fit. This face is
        // condensed already, so a label is its own shape.
        check(regular.getHorizontalScale() == 1.0f, "no horizontal squeeze is applied to it", regular.getHorizontalScale());
    }

    // MARK: EVERY label of EVERY skin fits the frame the Mac measured for it
    {
        int labels = 0, tooWide = 0;
        float worst = 0;
        std::string worstLabel;
        for (const s1plugin::LayoutSkin &skin : spec.skins) {
            const s1ui::Style style(skin);
            for (const s1plugin::LayoutLabel &label : skin.labels) {
                if (label.text.empty() || label.frame.width <= 0) { continue; }
                ++labels;
                const juce::Font font = style.font(label.size, weightOf(label.font));
                // What the interface DRAWS, not the raw specification text: the Option sign and
                // the non-breaking hyphen are replaced before anything is painted.
                const float wide = widthOf(font, s1ui::Style::drawable(juce::String::fromUTF8(label.text.c_str())));
                const float room = label.frame.width;
                if (wide > room) {
                    ++tooWide;
                    std::printf("note  too wide by %.0f%%: \"%s\"\n", (wide / room - 1.0f) * 100.0f, label.text.c_str());
                    if (wide / room > worst) { worst = wide / room; worstLabel = label.text; }
                }
            }
        }
        check(labels == 33, "the specification's 33 labels are measured", labels);
        std::printf("note  %d labels measured in Barlow Condensed; %d wider than their frame%s\n",
                    labels, tooWide, tooWide > 0 ? (", worst \"" + worstLabel + "\"").c_str() : "");
        check(tooWide == 0, "every one of them fits the frame the Mac measured for it", tooWide);
    }

    // MARK: and every CAPTION beside a control — 62 a skin, which the labels above are not. Two
    // things are asked of each, because `Graphics::drawText` CURTAILS (it deletes the letters that
    // do not fit, silently): that it fits the room the backdrop gives it, and — since the backdrop
    // draws it FITTED — that it could be squeezed into that room at every scale the window has.
    // Windows cut the k off "Pitch Track" at a scale of 1.10 while this check passed there at 1x
    // (ADR-096), so the second half is measured at the scales the window actually uses.
    {
        int captions = 0, tooWide = 0, uncuttable = 0;
        float worst = 0;
        std::string worstCaption;
        for (const s1plugin::LayoutSkin &skin : spec.skins) {
            const s1ui::Style style(skin);
            for (const s1plugin::LayoutControl &control : skin.controls) {
                if (!control.titleFrame || control.title.empty() || control.kind == s1plugin::LayoutControlKind::chip) { continue; }
                ++captions;
                const juce::String drawn = s1ui::Style::drawable(juce::String::fromUTF8(control.title.c_str()));
                const float room = control.titleFrame->width + 2.0f * s1ui::Style::kCaptionRoom;
                if (widthOf(style.font(12.0f), drawn) > room) { ++tooWide; }
                // …and at 0.75x, 1x, 1.1x and 1.5x: what a renderer measures at one size is not
                // what it measures at another, which is the whole of ADR-096.
                for (const float scale : { 0.75f, 1.0f, 1.1f, 1.5f }) {
                    const float needed = widthOf(style.font(12.0f * scale), drawn);
                    const float have = room * scale;
                    if (needed / have > worst) { worst = needed / have; worstCaption = control.title + " at " + std::to_string(scale).substr(0, 4) + "x"; }
                    if (needed > have / s1ui::Style::kCaptionSqueeze) { ++uncuttable; }
                }
            }
        }
        check(captions > 100, "both skins' captions are measured", captions);
        check(tooWide == 0, "every caption fits the room the backdrop gives it, in Barlow Condensed", tooWide);
        std::printf("note  the tightest caption needs %.0f%% of its room (%s); a letter is dropped past %.0f%%\n",
                    worst * 100.0f, worstCaption.c_str(), 100.0f / s1ui::Style::kCaptionSqueeze);
        check(uncuttable == 0, "…and none could lose a letter at any scale the window has, drawn fitted", uncuttable);
    }

    // MARK: and the toolbar's and sections' words fit too, at the sizes the interface uses
    {
        const s1plugin::LayoutSkin *skin = spec.defaultSkin();
        const s1ui::Style style(*skin);
        int tooWide = 0;
        for (const s1plugin::LayoutSection &section : skin->sections) {
            if (section.title.empty()) { continue; }
            const juce::Font font = style.font(11.0f, s1ui::FontWeight::demiBold);
            // A section's header band is its own width less the padding the editor draws with.
            if (widthOf(font, juce::String::fromUTF8(section.title.c_str())) > section.frame.width - 16.0f) { ++tooWide; }
        }
        check(tooWide == 0, "every section's title fits its header", tooWide);
    }

    s1ui::Style::preferLinkedTypeface(false);
    std::printf("\n%s: PluginTypefaceTests\n", failures == 0 ? "PASSED" : "FAILED");
    return failures == 0 ? 0 : 1;
}
