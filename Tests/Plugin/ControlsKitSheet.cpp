// X3-2 (ADR-084): every control of the kit painted where the layout specification puts it — a
// picture to hold beside the Mac app's render (Scripts/check-layout-spec.sh writes those). Not the
// editor: no section frames worth the name, no titles, no toolbar. X3-3 builds that.
//
//   ControlsKitSheet <studio|cabinet> <out.png> [--background <painting.png>] [--scale 2]
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "S1LinkedLayoutSpec.h"
#include "S1PluginProcessor.h"
#include "UI/S1KitControls.h"

int main(int argc, char **argv) {
    if (argc < 3) { std::fprintf(stderr, "usage: ControlsKitSheet <skin> <out.png> [--background <png>] [--scale N]\n"); return 2; }
    const juce::ScopedJuceInitialiser_GUI gui;
    std::string background;
    float scale = 2;
    for (int i = 3; i + 1 < argc; i += 2) {
        if (std::string(argv[i]) == "--background") { background = argv[i + 1]; }
        if (std::string(argv[i]) == "--scale") { scale = float(std::atof(argv[i + 1])); }
    }
    const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
    const s1plugin::LayoutSkin *skin = spec.skin(argv[1]);
    if (skin == nullptr) { std::fprintf(stderr, "no skin \"%s\"\n", argv[1]); return 1; }
    const s1ui::Style style(*skin);
    S1PluginProcessor processor;
    const s1ui::ParameterLookup lookup = [&](S1Parameter p) -> S1HostParameter & { return processor.hostParameter(p); };

    juce::Component sheet;
    sheet.setSize(juce::roundToInt(spec.designWidth), juce::roundToInt(spec.designHeight));
    std::vector<std::unique_ptr<juce::Component>> children;
    auto place = [&](std::unique_ptr<juce::Component> child, const s1plugin::LayoutRect &frame) {
        if (child == nullptr) { return; }
        child->setBounds(juce::Rectangle<float>(frame.x, frame.y, frame.width, frame.height).toNearestInt());
        sheet.addAndMakeVisible(*child);
        children.push_back(std::move(child));
    };
    for (const s1plugin::LayoutControl &control : skin->controls) {
        if (control.valueFrame) {
            auto readout = std::make_unique<s1ui::ValueReadout>(lookup(control.parameter), style);
            place(std::move(readout), *control.valueFrame);
        }
        place(s1ui::makeControl(control, style, lookup), control.frame);
    }
    for (const s1plugin::LayoutDisplay &display : skin->displays) { place(s1ui::makeDisplay(display, style, lookup), display.frame); }

    juce::Image canvas(juce::Image::ARGB, juce::roundToInt(spec.designWidth * scale), juce::roundToInt(spec.designHeight * scale), true, juce::SoftwareImageType());
    {
        juce::Graphics g(canvas);
        g.addTransform(juce::AffineTransform::scale(scale));
        g.fillAll(style.colour("windowBackground"));
        if (!background.empty()) {
            const juce::Image painting = juce::ImageFileFormat::loadFrom(juce::File::getCurrentWorkingDirectory().getChildFile(background));
            if (painting.isValid()) { g.drawImage(painting, { 0, 0, spec.designWidth, spec.designHeight }, juce::RectanglePlacement::stretchToFit); }
        } else {
            for (const s1plugin::LayoutSection &section : skin->sections) {
                const juce::Rectangle<float> frame(section.frame.x, section.frame.y, section.frame.width, section.frame.height);
                g.setGradientFill(juce::ColourGradient(style.colour("sectionTop"), 0, frame.getY(), style.colour("sectionBottom"), 0, frame.getBottom(), false));
                g.fillRoundedRectangle(frame, 7.0f);
                g.setColour(style.colour("sectionBorder"));
                g.drawRoundedRectangle(frame.reduced(0.5f), 7.0f, 1.0f);
            }
        }
        for (const s1plugin::LayoutControl &control : skin->controls) {
            if (!control.titleFrame || control.title.empty()) { continue; }
            g.setColour(style.colour("label"));
            g.setFont(style.font(12.0f));
            g.drawText(juce::String::fromUTF8(control.title.c_str()),
                       juce::Rectangle<float>(control.titleFrame->x, control.titleFrame->y, control.titleFrame->width, control.titleFrame->height),
                       juce::Justification::centred, false);
        }
        sheet.paintEntireComponent(g, true);
    }
    const juce::File out = juce::File::getCurrentWorkingDirectory().getChildFile(argv[2]);
    out.deleteFile();
    juce::FileOutputStream stream(out);
    if (!stream.openedOk() || !juce::PNGImageFormat().writeImageToStream(canvas, stream)) { std::fprintf(stderr, "cannot write %s\n", argv[2]); return 1; }
    std::printf("%s: %d components -> %s\n", skin->key.c_str(), int(children.size()), argv[2]);
    return 0;
}
