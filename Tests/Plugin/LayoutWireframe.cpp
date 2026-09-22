// X3-1 (ADR-083): a wireframe drawn from the layout specification by the plugin's own reader —
// what the JUCE interface will be laid out from, as rectangles — alone or over a render of the
// Mac app, so the two can be compared by eye (Scripts/check-layout-spec.sh does both skins and
// also compares the numbers with frames measured in the running app).
//
//   LayoutWireframe <layout-spec.json> <studio|cabinet> <out.png> [--over <mac-render.png>] [--scale 2]
//
// Sections green, controls magenta (a knob is its circle), a cell's title and readout lines cyan,
// envelope plots and pads orange, toolbar and play-bar items yellow, free labels blue.
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>

#include <juce_graphics/juce_graphics.h>

#include "S1LayoutSpec.hpp"

namespace {

juce::Rectangle<float> rectangle(const s1plugin::LayoutRect &r) { return { r.x, r.y, r.width, r.height }; }

} // namespace

int main(int argc, char **argv) {
    if (argc < 4) {
        std::fprintf(stderr, "usage: LayoutWireframe <layout-spec.json> <skin> <out.png> [--over <render.png>] [--scale N]\n");
        return 2;
    }
    std::string over;
    float scale = 1;
    for (int i = 4; i + 1 < argc; i += 2) {
        if (std::string(argv[i]) == "--over") { over = argv[i + 1]; }
        if (std::string(argv[i]) == "--scale") { scale = float(std::atof(argv[i + 1])); }
    }

    std::ifstream in(argv[1], std::ios::binary);
    std::ostringstream text;
    text << in.rdbuf();
    std::string error;
    const auto spec = s1plugin::LayoutSpec::parse(text.str(), &error);
    if (!spec) { std::fprintf(stderr, "%s: %s\n", argv[1], error.c_str()); return 1; }
    const s1plugin::LayoutSkin *skin = spec->skin(argv[2]);
    if (skin == nullptr) { std::fprintf(stderr, "no skin \"%s\"\n", argv[2]); return 1; }

    juce::Image canvas;
    if (!over.empty()) {
        const juce::Image render = juce::ImageFileFormat::loadFrom(juce::File::getCurrentWorkingDirectory().getChildFile(over));
        if (!render.isValid()) { std::fprintf(stderr, "cannot read %s\n", over.c_str()); return 1; }
        scale = float(render.getWidth()) / spec->designWidth;
        canvas = juce::Image(juce::Image::ARGB, render.getWidth(), render.getHeight(), true, juce::SoftwareImageType());
        juce::Graphics(canvas).drawImageAt(render, 0, 0);
    } else {
        if (scale <= 0) { scale = 1; }
        canvas = juce::Image(juce::Image::ARGB, juce::roundToInt(spec->designWidth * scale), juce::roundToInt(spec->designHeight * scale), true, juce::SoftwareImageType());
        const s1plugin::LayoutColour background = skin->colour("windowBackground");
        juce::Graphics(canvas).fillAll(juce::Colour(background.red, background.green, background.blue));
    }

    {
        juce::Graphics g(canvas);
        g.addTransform(juce::AffineTransform::scale(scale));
        const float hair = 1.0f / scale;
        for (const auto &region : skin->regions) {
            g.setColour(juce::Colours::white.withAlpha(0.5f));
            g.drawRect(rectangle(region.second), hair);
        }
        for (const s1plugin::LayoutSection &section : skin->sections) {
            g.setColour(juce::Colours::lime);
            g.drawRect(rectangle(section.frame), hair * 2);
            g.setColour(juce::Colours::lime.withAlpha(0.6f));
            g.drawRect(rectangle(section.header), hair);
        }
        for (const s1plugin::LayoutLabel &label : skin->labels) {
            g.setColour(juce::Colours::dodgerblue);
            g.drawRect(rectangle(label.frame), hair);
        }
        for (const s1plugin::LayoutItem &item : skin->items) {
            g.setColour(juce::Colours::yellow);
            g.drawRect(rectangle(item.frame), hair);
        }
        for (const s1plugin::LayoutDisplay &display : skin->displays) {
            g.setColour(juce::Colours::orange);
            g.drawRect(rectangle(display.frame), hair * 2);
        }
        for (const s1plugin::LayoutControl &control : skin->controls) {
            g.setColour(juce::Colours::magenta);
            if (control.kind == s1plugin::LayoutControlKind::knob) { g.drawEllipse(rectangle(control.frame), hair * 2); }
            g.drawRect(rectangle(control.frame), hair);
            g.setColour(juce::Colours::cyan.withAlpha(0.8f));
            if (control.titleFrame) { g.drawRect(rectangle(*control.titleFrame), hair); }
            if (control.valueFrame) { g.drawRect(rectangle(*control.valueFrame), hair); }
        }
    }

    const juce::File out = juce::File::getCurrentWorkingDirectory().getChildFile(argv[3]);
    out.deleteFile();
    juce::FileOutputStream stream(out);
    if (!stream.openedOk() || !juce::PNGImageFormat().writeImageToStream(canvas, stream)) {
        std::fprintf(stderr, "cannot write %s\n", argv[3]);
        return 1;
    }
    std::printf("%s: %d sections, %d controls, %d displays, %d items, %d labels -> %s (%d x %d)\n", skin->key.c_str(),
                int(skin->sections.size()), int(skin->controls.size()), int(skin->displays.size()), int(skin->items.size()),
                int(skin->labels.size()), argv[3], canvas.getWidth(), canvas.getHeight());
    return 0;
}
