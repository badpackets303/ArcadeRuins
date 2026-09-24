//
//  S1PluginEditor.cpp
//  Arcade Ruins
//
//  X3-3 (ADR-085). See the header.
//
#include "S1PluginEditor.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>

#include "../S1LinkedLayoutSpec.h"
#include "../S1PluginProcessor.h"
#include "S1ArtData.h"

namespace {

juce::Rectangle<float> rectangle(const s1plugin::LayoutRect &r) { return { r.x, r.y, r.width, r.height }; }
juce::Rectangle<int> pixels(const s1plugin::LayoutRect &r) { return rectangle(r).toNearestInt(); }
juce::Colour toColour(const s1plugin::LayoutColour &c) { return juce::Colour(c.red, c.green, c.blue, c.alpha); }
juce::String text(const std::string &utf8) { return juce::String::fromUTF8(utf8.c_str()); }

/// The owner's artwork as the Mac app carries it, linked in under the file's own name.
juce::Image linkedImage(const char *fileName) {
    for (int i = 0; i < S1ArtData::namedResourceListSize; ++i) {
        if (std::strcmp(S1ArtData::originalFilenames[i], fileName) != 0) { continue; }
        int size = 0;
        const char *data = S1ArtData::getNamedResource(S1ArtData::namedResourceList[i], size);
        return juce::ImageFileFormat::loadFrom(data, size_t(size));
    }
    return {};
}

const char *const kHintPrefix = "Drag a knob";

} // namespace

// MARK: - The backdrop: everything that never moves, painted once

class S1PluginEditor::Backdrop final : public juce::Component {
public:
    Backdrop(const s1plugin::LayoutSpec &spec, const s1ui::Style &s) : layout(spec), style(s) {
        setOpaque(true);
        setInterceptsMouseClicks(false, false);
        setBufferedToImage(true);
        setAccessible(false);
        if (const auto &template_ = style.skin().painting) {
            // The painting the skin names: Cabinet's, or Dark Arcade's (2026-09-24)
            painting = linkedImage((template_->image + "@2x.jpg").c_str());
            // X3-9 (ADR-091): the grey copy the red buttons lay over a dead zone.
            if (template_->power) { dark = linkedImage((template_->power->darkImage + "@2x.jpg").c_str()); }
        }
        else {
            // The owner's wordmark, cut at the sizes it is shown at (generate.py's `plugin_wordmarks`)
            for (const char *cut : { "wordmark-180.png", "wordmark-270.png", "wordmark-360.png", "wordmark-540.png", "wordmark-720.png" }) {
                const juce::Image image = linkedImage(cut);
                if (image.isValid()) { wordmarks.push_back(image); }
            }
        }
    }

    /// X3-9: which zones have lost their power, 0 lit to 1 dead.
    void setZoneDim(const std::map<std::string, float> &dims) {
        if (dims == zoneDim) { return; }
        zoneDim = dims;
        repaint();
    }

    void paint(juce::Graphics &g) override {
        const s1plugin::LayoutSkin &skin = style.skin();
        g.fillAll(style.colour("windowBackground"));
        if (painting.isValid()) {
            g.drawImage(painting, getLocalBounds().toFloat(), juce::RectanglePlacement::stretchToFit);
        } else {
            paintBars(g, skin);
            for (const s1plugin::LayoutSection &section : skin.sections) { paintSection(g, section); }
            for (const s1plugin::LayoutItem &item : skin.items) {
                if (item.id == "wordmark" && !wordmarks.empty()) {
                    // The smallest cut that is at least as wide as the pixels it will cover: at the
                    // design size on a 1x or 2x display that is pixel for pixel, and in between it
                    // is a reduction of under 1.5, which every platform's resampler does cleanly.
                    // Half as big again as the Mac's (the owner, 2026-09-21: "a little bigger … it looks
                    // tiny" — its letters were 8 points tall). It grows to the RIGHT from where the
                    // specification starts it, about the same middle; the header is empty there as
                    // far as the preset's arrows. The Mac's layout, and so the specification, stand.
                    const juce::Rectangle<float> measured = rectangle(item.frame);
                    const juce::Rectangle<float> frame = measured.withSizeKeepingCentre(measured.getWidth(), measured.getHeight() * kWordmarkScale)
                                                                 .withWidth(measured.getWidth() * kWordmarkScale);
                    const float needed = frame.getWidth() * g.getInternalContext().getPhysicalPixelScaleFactor();
                    const juce::Image *cut = &wordmarks.back();
                    for (const juce::Image &candidate : wordmarks) {
                        if (float(candidate.getWidth()) >= needed - 0.5f) { cut = &candidate; break; }
                    }
                    // Placed by hand and ON THE PIXEL GRID: a cut with an odd number of rows, centred,
                    // starts on a half pixel and every row of it is resampled (the 360-pixel cut is
                    // 23 tall, and the check below caught it the first time it ran).
                    const float physical = g.getInternalContext().getPhysicalPixelScaleFactor();
                    const float width = std::min(frame.getWidth(), float(cut->getWidth()) / physical);
                    const float height = width * float(cut->getHeight()) / float(cut->getWidth());
                    const float top = float(juce::roundToInt((frame.getCentreY() - height * 0.5f) * physical)) / physical;
                    g.setImageResamplingQuality(juce::Graphics::highResamplingQuality);
                    g.drawImage(*cut, juce::Rectangle<float>(frame.getX(), top, width, height), juce::RectanglePlacement::stretchToFit);
                }
            }
        }
        // X3-9: the grey painting goes UNDER the words. Laid over them, a dead section lost its
        // captions altogether — the Mac greys them — which a mid-cycle render showed and no check had.
        paintDeadZones(g, skin);
        // The words beside the controls, and the free labels
        for (const s1plugin::LayoutControl &control : skin.controls) {
            if (!control.titleFrame || control.title.empty() || control.kind == s1plugin::LayoutControlKind::chip) { continue; }
            g.setColour(s1ui::Style::dimmedBy(style.colour(control.section == "playBar" ? "dim" : "label"), dimAt(skin, rectangle(*control.titleFrame).getCentre())));
            g.setFont(style.font(12.0f));
            // FITTED, not plain: `drawText` CURTAILS — Windows cut the k off "Pitch Track" at a
            // window scale of 1.10 while its own width check passed at 1x (ADR-096).
            g.drawFittedText(text(control.title), rectangle(*control.titleFrame).expanded(s1ui::Style::kCaptionRoom, 0.0f).toNearestInt(),
                             juce::Justification::centred, 1, s1ui::Style::kCaptionSqueeze);
        }
        for (const s1plugin::LayoutLabel &label : skin.labels) {
            if (label.text == "\xE2\x96\xBE" || label.text.rfind(kHintPrefix, 0) == 0) { continue; }   // the field's chevron and the hint are live
            if (isAReadout(label, skin)) { continue; }
            g.setColour(s1ui::Style::dimmedBy(toColour(label.colour), dimAt(skin, rectangle(label.frame).getCentre())));
            const bool isSectionTitle = label.font.find("DemiBold") != std::string::npos;
            juce::Font font = style.font(label.size, isSectionTitle ? s1ui::FontWeight::demiBold
                                                     : label.font.find("Medium") != std::string::npos ? s1ui::FontWeight::medium : s1ui::FontWeight::regular);
            if (isSectionTitle) {   // kerned, as S1SectionView sets it
                const auto titleFont = layout.fonts.find("sectionTitle");
                font.setExtraKerningFactor((titleFont != layout.fonts.end() ? titleFont->second.kern : 1.2f) / label.size);
            }
            g.setFont(font);
            const juce::Justification where = label.align == "left" ? juce::Justification::centredLeft
                                            : label.align == "right" ? juce::Justification::centredRight : juce::Justification::centred;
            // A measured frame is as wide as the Mac's text; a little room keeps another face from clipping
            g.drawFittedText(text(label.text), rectangle(label.frame).expanded(label.align == "centre" ? s1ui::Style::kCaptionRoom : 0.0f, 0.0f).withTrimmedRight(label.align == "left" ? -24.0f : 0.0f).toNearestInt(),
                             where, 1, s1ui::Style::kCaptionSqueeze);
        }
    }

    /// Where a zone is in the window: a chrome zone's own rectangle, a section's grown by the
    /// reach that takes its frame and glow.
    static std::optional<juce::Rectangle<float>> zoneInWindow(const s1plugin::LayoutSkin &skin, const std::string &zone) {
        if (!skin.painting || !skin.painting->power) { return std::nullopt; }
        const s1plugin::LayoutPower &power = *skin.painting->power;
        const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
        s1plugin::LayoutRect painted;
        if (const auto found = power.zones.find(zone); found != power.zones.end()) {
            painted = found->second;
        } else if (const auto section = skin.painting->sections.find(zone); section != skin.painting->sections.end()) {
            painted = { section->second.x - power.frameReach, section->second.y - power.frameReach,
                        section->second.width + 2 * power.frameReach, section->second.height + 2 * power.frameReach };
        } else {
            return std::nullopt;
        }
        return rectangle(skin.painting->inWindow(painted, spec.designWidth, spec.designHeight));
    }

    /// How dead the zone under a point is, for the words the backdrop paints there.
    float dimAt(const s1plugin::LayoutSkin &skin, juce::Point<float> point) const {
        float dim = 0.0f;
        for (const auto &entry : zoneDim) {
            if (entry.second <= dim) { continue; }
            if (const auto where = zoneInWindow(skin, entry.first); where && where->contains(point)) { dim = entry.second; }
        }
        return dim;
    }

    /// X3-9 (ADR-091): a zone whose power is cut. Under Cabinet the grey copy of the painting is
    /// laid over the zone's rectangle, reaching `frameReach` past a section's inner edge to take
    /// its frame and its glow, as the Mac's `contentsRect` crop does; under Studio, which paints
    /// its own panels, the section is simply drawn again with a dimmed style.
    void paintDeadZones(juce::Graphics &g, const s1plugin::LayoutSkin &skin) const {
        if (zoneDim.empty() || !skin.painting || !skin.painting->power) { return; }
        const s1plugin::LayoutPower &power = *skin.painting->power;
        const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
        for (const auto &entry : zoneDim) {
            if (entry.second <= 0.0f) { continue; }
            s1plugin::LayoutRect painted;
            if (const auto found = power.zones.find(entry.first); found != power.zones.end()) {
                painted = found->second;
            } else if (const auto section = skin.painting->sections.find(entry.first); section != skin.painting->sections.end()) {
                painted = { section->second.x - power.frameReach, section->second.y - power.frameReach,
                            section->second.width + 2 * power.frameReach, section->second.height + 2 * power.frameReach };
            } else {
                continue;
            }
            const juce::Rectangle<float> where = rectangle(skin.painting->inWindow(painted, spec.designWidth, spec.designHeight));
            if (dark.isValid()) {
                // The same crop of the grey painting, drawn where the lit one is.
                const float sx = float(dark.getWidth()) / skin.painting->width;
                const float sy = float(dark.getHeight()) / skin.painting->height;
                const juce::Rectangle<int> from(juce::roundToInt(painted.x * sx), juce::roundToInt(painted.y * sy),
                                                juce::roundToInt(painted.width * sx), juce::roundToInt(painted.height * sy));
                g.setOpacity(entry.second);
                g.drawImage(dark.getClippedImage(from), where, juce::RectanglePlacement::stretchToFit);
                g.setOpacity(1.0f);
            } else {
                g.setColour(style.colour("windowBackground").withAlpha(entry.second * 0.85f));
                g.fillRect(where);
            }
        }
    }

private:
    /// A readout the specification caught as a free label (a rate cell's value): the live
    /// `ValueReadout` on its control's `valueFrame` says it instead.
    static bool isAReadout(const s1plugin::LayoutLabel &label, const s1plugin::LayoutSkin &skin) {
        const juce::Rectangle<float> frame = rectangle(label.frame);
        for (const s1plugin::LayoutControl &control : skin.controls) {
            if (control.valueFrame && rectangle(*control.valueFrame).intersects(frame)) { return true; }
        }
        return false;
    }

    void paintBars(juce::Graphics &g, const s1plugin::LayoutSkin &skin) const {
        auto region = [&](const char *name) -> juce::Rectangle<float> {
            const auto found = skin.regions.find(name);
            return found != skin.regions.end() ? rectangle(found->second) : juce::Rectangle<float>();
        };
        const juce::Rectangle<float> toolbar = region("toolbar"), playBar = region("playBar"), statusBar = region("statusBar");
        g.setGradientFill(juce::ColourGradient(style.colour("toolbarTop"), 0, toolbar.getY(), style.colour("toolbarBottom"), 0, toolbar.getBottom(), false));
        g.fillRect(toolbar);
        g.setColour(style.colour("hairline"));
        g.fillRect(toolbar.withTop(toolbar.getBottom() - 1));
        g.setGradientFill(juce::ColourGradient(style.colour("playBarTop"), 0, playBar.getY(), style.colour("playBarBottom"), 0, playBar.getBottom(), false));
        g.fillRect(playBar);
        g.setColour(style.colour("sectionBorder"));
        g.fillRect(juce::Rectangle<float>(0, playBar.getBottom(), float(getWidth()), statusBar.getY() - playBar.getBottom()));
        g.setColour(style.colour("statusBarBackground"));
        g.fillRect(statusBar);
    }

    /// S1SectionView: a gradient panel with a drop shadow, a header strip and a kerned title.
    void paintSection(juce::Graphics &g, const s1plugin::LayoutSection &section) const {
        const auto metric = [&](const char *name, float fallback) {
            const auto found = layout.metrics.find(name);
            return found != layout.metrics.end() ? found->second : fallback;
        };
        const float radius = metric("sectionCornerRadius", 7.0f);
        const juce::Rectangle<float> frame = rectangle(section.frame), header = rectangle(section.header);
        juce::Path outline;
        outline.addRoundedRectangle(frame, radius);
        juce::DropShadow(juce::Colours::black.withAlpha(0.55f), 3, { 0, 2 }).drawForPath(g, outline);
        g.setGradientFill(juce::ColourGradient(style.colour("sectionTop"), 0, frame.getY(), style.colour("sectionBottom"), 0, frame.getBottom(), false));
        g.fillPath(outline);
        {
            juce::Graphics::ScopedSaveState clip(g);
            g.reduceClipRegion(outline);
            g.setGradientFill(juce::ColourGradient(style.colour("sectionHeaderTop"), 0, header.getY(), style.colour("sectionHeaderBottom"), 0, header.getBottom(), false));
            g.fillRect(header);
            g.setColour(style.colour("hairline"));
            g.fillRect(header.withTop(header.getBottom() - 1));
        }
        g.setColour(style.colour("sectionBorder"));
        g.drawRoundedRectangle(frame.reduced(0.5f), radius, 1.0f);

        // The title is one of the specification's labels, measured where the Mac drew it
    }

    const s1plugin::LayoutSpec &layout;
    const s1ui::Style &style;
    juce::Image painting, dark;
    std::vector<juce::Image> wordmarks;   ///< smallest first
    static constexpr float kWordmarkScale = 1.5f;   ///< generate.py's PLUGIN_WORDMARK_POINTS is 120 times this
    std::map<std::string, float> zoneDim;
};

// MARK: - Toolbar and play-bar pieces

/// A button of the toolbar, the play bar or a header. Painted ones (Cabinet's header) draw nothing:
/// the painting has them, and this takes the click.
class S1PluginEditor::ItemButton final : public juce::Component {
public:
    enum class Look { dressed, painted, chevronLeft, chevronRight, dice, stepper, plain };
    ItemButton(const s1ui::Style &s, juce::String words, Look l, juce::Colour a) : style(s), label(std::move(words)), look(l), accent(a) {
        setTitle(label);
        setWantsKeyboardFocus(true);
    }
    std::function<void()> onPress;
    /// X3-8: a `Look::stepper` item steps instead of pressing — the half of it that was clicked
    /// says which way, as the kit's own stepper does. -1 or 1.
    std::function<void(int)> onStep;
    void setLit(bool isLit) { if (lit != isLit) { lit = isLit; repaint(); } }
    /// X3-9 (ADR-091): the power greys what a button holds, as it does a control's accent.
    void setAccent(juce::Colour c) { if (accent != c) { accent = c; repaint(); } }
    bool isLit() const { return lit; }
    void setWords(const juce::String &words) { if (label != words) { label = words; repaint(); } }
    void press() { if (onPress) { onPress(); } }

    void paint(juce::Graphics &g) override {
        const juce::Rectangle<float> bounds = getLocalBounds().toFloat();
        switch (look) {
        case Look::dressed: style.drawButton(g, bounds, label, lit, down, accent); break;
        case Look::stepper: style.drawStepper(g, bounds, label, 0); break;
        case Look::plain:
            g.setColour(style.colour("label"));
            g.setFont(style.font(11.0f, s1ui::FontWeight::medium));
            g.drawText(label, bounds, juce::Justification::centred, false);
            break;
        case Look::chevronLeft:
        case Look::chevronRight: {
            const float direction = look == Look::chevronLeft ? 1.0f : -1.0f;
            juce::Path chevron;
            chevron.startNewSubPath(bounds.getCentreX() + 3.5f * direction, bounds.getCentreY() - 7);
            chevron.lineTo(bounds.getCentreX() - 3.5f * direction, bounds.getCentreY());
            chevron.lineTo(bounds.getCentreX() + 3.5f * direction, bounds.getCentreY() + 7);
            g.setColour(style.colour(down ? "text" : "label"));
            g.strokePath(chevron, juce::PathStrokeType(2.0f, juce::PathStrokeType::curved, juce::PathStrokeType::rounded));
            break;
        }
        case Look::dice: {
            const juce::Rectangle<float> die = bounds.withSizeKeepingCentre(18, 18);
            g.setColour(style.colour("label"));
            g.drawRoundedRectangle(die, 3.5f, 1.4f);
            for (const juce::Point<float> pip : { juce::Point<float>(-4.5f, -4.5f), { 4.5f, -4.5f }, { 0, 0 }, { -4.5f, 4.5f }, { 4.5f, 4.5f } }) {
                g.fillEllipse(juce::Rectangle<float>(3, 3).withCentre(die.getCentre() + pip));
            }
            break;
        }
        case Look::painted: break;
        }
        if (ringed) { style.drawFocusRing(g, bounds, accent, 5.0f); }
    }
    void mouseDown(const juce::MouseEvent &) override { down = true; repaint(); }
    void mouseUp(const juce::MouseEvent &event) override {
        down = false;
        repaint();
        if (!getLocalBounds().contains(event.getPosition())) { return; }
        if (onStep) { onStep(event.position.x < float(getWidth()) * 0.5f ? -1 : 1); return; }
        press();
    }
    bool keyPressed(const juce::KeyPress &key) override {
        if (onStep && (key == juce::KeyPress::leftKey || key == juce::KeyPress::rightKey)) {
            onStep(key == juce::KeyPress::leftKey ? -1 : 1);
            return true;
        }
        if (key != juce::KeyPress::returnKey && key != juce::KeyPress::spaceKey) { return false; }
        press();
        return true;
    }
    /// The ring is for someone finding their way by KEYBOARD. A click takes the focus too — so
    /// Space and Return go on working — but it must not draw a rectangle round what was clicked:
    /// on the painting's console the owner saw one round each red button (2026-09-21). Nor must
    /// focus that is merely HANDED over: when a card closes JUCE gives the focus to the first
    /// thing in the window that will take it, which under Cabinet is the About button over the
    /// title — the owner saw a rectangle round the app's name after closing the presets. Tab only.
    void focusGained(FocusChangeType cause) override { ringed = cause == focusChangedByTabKey; repaint(); }
    void focusLost(FocusChangeType) override { ringed = false; repaint(); }
    std::unique_ptr<juce::AccessibilityHandler> createAccessibilityHandler() override {
        return std::make_unique<juce::AccessibilityHandler>(*this, juce::AccessibilityRole::button,
                                                            juce::AccessibilityActions().addAction(juce::AccessibilityActionType::press, [this] { press(); }));
    }

private:
    const s1ui::Style &style;
    juce::String label;
    const Look look;
    juce::Colour accent;   ///< X3-9: not const — the power greys it
    bool lit = false, down = false, ringed = false;
};

/// The preset's name. Under Studio a field; under Cabinet the painted display, in its cyan.
class S1PluginEditor::PresetField final : public juce::Component {
public:
    PresetField(const s1ui::Style &s, bool isPainted) : style(s), painted(isPainted) { setTitle("Preset"); }
    std::function<void()> onPress;
    void setPresetName(const juce::String &newName) { if (name != newName) { name = newName; repaint(); } }
    void press() { if (onPress) { onPress(); } }
    void mouseUp(const juce::MouseEvent &) override { press(); }
    void paint(juce::Graphics &g) override {
        const juce::Rectangle<float> bounds = getLocalBounds().toFloat();
        if (painted) {
            // The painting's own colour for its display: Cabinet's cyan, Dark Arcade's orange
            const auto &template_ = style.skin().painting;
            const juce::Colour cyan = template_ && template_->display ? style.dimmed(juce::Colour(template_->display->red, template_->display->green, template_->display->blue, template_->display->alpha))
                                                                     : style.colour("secondAccent");
            g.setFont(juce::Font(juce::FontOptions(juce::Font::getDefaultMonospacedFontName(), "Bold", 19.0f).withPointHeight(19.0f)));
            juce::GlyphArrangement glyphs;
            glyphs.addFittedText(g.getCurrentFont(), name, 8, 0, bounds.getWidth() - 28, bounds.getHeight(), juce::Justification::centred, 1, 0.6f);
            juce::Path outline;
            glyphs.createPath(outline);
            juce::DropShadow(cyan.withAlpha(0.9f), 5, {}).drawForPath(g, outline);
            g.setColour(cyan);
            g.fillPath(outline);
            g.setFont(style.font(15.0f, s1ui::FontWeight::medium));
            g.drawText(juce::String::fromUTF8("\xE2\x96\xBE"), bounds.withTrimmedRight(9).translated(0, -1), juce::Justification::centredRight, false);
            return;
        }
        g.setColour(style.colour("fieldBackground"));
        g.fillRoundedRectangle(bounds.reduced(0.5f), 7.0f);
        g.setColour(style.colour("sectionBorder"));
        g.drawRoundedRectangle(bounds.reduced(0.5f), 7.0f, 1.0f);
        g.setColour(style.colour("text"));
        g.setFont(style.font(15.0f, s1ui::FontWeight::medium));
        g.drawText(name, bounds.reduced(8, 0).withTrimmedRight(14), juce::Justification::centred, true);
        g.setColour(style.colour("dim"));
        g.drawText(juce::String::fromUTF8("\xE2\x96\xBE"), bounds.withTrimmedRight(9).translated(0, -1), juce::Justification::centredRight, false);
    }
private:
    const s1ui::Style &style;
    const bool painted;
    juce::String name;
};

/// The output, as the render thread last left it in the processor's ring.
class S1PluginEditor::ScopeView final : public juce::Component {
public:
    ScopeView(S1PluginProcessor &p, const s1ui::Style &s, bool isPainted) : processor(p), style(s), painted(isPainted) {
        setInterceptsMouseClicks(false, false);
        setAccessible(false);
    }
    void paint(juce::Graphics &g) override {
        const juce::Rectangle<float> bounds = getLocalBounds().toFloat();
        if (!painted) {
            g.setColour(style.colour("fieldBackground"));
            g.fillRoundedRectangle(bounds, 4.0f);
        }
        std::array<float, S1PluginProcessor::kScopeLength> samples {};
        processor.readScope(samples);
        juce::Path trace;
        const juce::Rectangle<float> area = bounds.reduced(painted ? 10.0f : 3.0f);
        for (size_t i = 0; i < samples.size(); i += 2) {
            const float x = area.getX() + area.getWidth() * float(i) / float(samples.size() - 1);
            const float y = area.getCentreY() - juce::jlimit(-1.0f, 1.0f, samples[i]) * area.getHeight() * 0.5f;
            if (i == 0) { trace.startNewSubPath(x, y); } else { trace.lineTo(x, y); }
        }
        g.setColour(style.colour("accent"));
        g.strokePath(trace, juce::PathStrokeType(1.2f));
    }
private:
    S1PluginProcessor &processor;
    const s1ui::Style &style;
    const bool painted;
};

/// A card over the sections: every parameter, or About.
class S1PluginEditor::Panel final : public juce::Component {
public:
    Panel(const s1ui::Style &s, const juce::String &heading, std::unique_ptr<juce::Component> body, std::function<void()> close)
        : style(s), title(heading), content(std::move(body)), onClose(std::move(close)) {
        setTitle(heading);
        if (dynamic_cast<juce::GenericAudioProcessorEditor *>(content.get()) != nullptr) {
            viewport.setViewedComponent(content.get(), false);
            viewport.setScrollBarsShown(true, false);
            addAndMakeVisible(viewport);
        } else {
            addAndMakeVisible(*content);
        }
        closeButton.setButtonText("Close");
        closeButton.onClick = [this] { if (onClose) { onClose(); } };
        addAndMakeVisible(closeButton);
    }
    juce::Component *body() const { return content.get(); }
    void paint(juce::Graphics &g) override {
        g.fillAll(juce::Colours::black.withAlpha(0.55f));
        g.setColour(style.colour("panelBackground"));
        g.fillRoundedRectangle(card().toFloat(), 10.0f);
        g.setColour(style.colour("controlBorder"));
        g.drawRoundedRectangle(card().toFloat().reduced(0.5f), 10.0f, 1.0f);
        g.setColour(style.colour("text"));
        g.setFont(style.font(15.0f, s1ui::FontWeight::demiBold));
        g.drawText(title, card().removeFromTop(44).reduced(16, 0), juce::Justification::centredLeft, false);
    }
    void resized() override {
        juce::Rectangle<int> inside = card().reduced(12);
        juce::Rectangle<int> top = inside.removeFromTop(32);
        closeButton.setBounds(top.removeFromRight(80).reduced(0, 3));
        if (viewport.getViewedComponent() != nullptr) {
            viewport.setBounds(inside);
            content->setSize(inside.getWidth() - viewport.getScrollBarThickness(), content->getHeight());
        } else {
            content->setBounds(inside);
        }
    }
    void mouseUp(const juce::MouseEvent &event) override { if (!card().contains(event.getPosition()) && onClose) { onClose(); } }
private:
    juce::Rectangle<int> card() const { return getLocalBounds().withSizeKeepingCentre(std::min(720, getWidth() - 40), std::min(640, getHeight() - 40)); }
    const s1ui::Style &style;
    const juce::String title;
    std::unique_ptr<juce::Component> content;
    juce::Viewport viewport;
    juce::TextButton closeButton;
    std::function<void()> onClose;
};

// MARK: - The cabinet's joystick (X3-6, ADR-088)

/// A port of `S1CabinetJoystick`. The painting has the stick cut OUT of it (generate.py lifts it
/// and fills the hole from the console beside it), so without this the console is empty — which
/// is what the owner saw at X3-3. Two sprites, a ball on a rod: the rod turns about its socket,
/// the ball slides up the rod for a push and down for a pull, and NOTHING stretches (the owner,
/// 2026-09-17, of a first cut that scaled it).
///
/// Up is the mod wheel, sideways bends the pitch — what a synth's joystick does — and PULLING it
/// takes the bitcrusher's rate down with it, all the way down at the bottom of the travel (the
/// owner, 2026-09-21). It owns no parameter of its own: the wheel goes through the processor's
/// interface path (the same call CC 1 takes), the bend through the `pitchbend` host parameter and
/// the rate through `bitCrushSampleRate`, so a preset's routing, the bend range, the Bitrate knob
/// and anything else watching them all follow. Everything it moves springs back when it is let go.
class S1PluginEditor::Joystick final : public juce::Component, private juce::Timer {
public:
    Joystick(S1PluginProcessor &processor, const s1plugin::LayoutJoystick &parts, const s1plugin::LayoutTemplate &painting,
             float designWidth, float designHeight)
        : plugin(processor), stick(parts) {
        setTitle("Joystick");
        setAccessible(true);
        setDescription("Drag up for the mod wheel, sideways to bend the pitch");
        ball = linkedImage((parts.ballImage + "@2x.png").c_str());
        rod = linkedImage((parts.rodImage + "@2x.png").c_str());
        // Every box is in the painting's pixels; the sprites sit inside `reach` in the same
        // proportion they do there.
        const s1plugin::LayoutRect reachInWindow = painting.inWindow(parts.reach, designWidth, designHeight);
        scaleX = reachInWindow.width / parts.reach.width;
        scaleY = reachInWindow.height / parts.reach.height;
    }

    /// The component is WIDER than `reach`, by `kSwing` painting pixels on each side. A leaned
    /// ball swings up to 19 painting pixels past the reach box's right edge, and JUCE clips a
    /// component's painting to its own bounds where UIKit does not — so on the Mac the sprite
    /// simply draws outside its view, and here it was cut off against the console's buttons
    /// (the owner, 2026-09-20: "the joystick becomes obscured by the yellow buttons to its
    /// right"). The grab area stays `reach` itself, through `hitTest`.
    static constexpr float kSwing = 24.0f;
    /// The box the whole component covers, in the painting's pixels.
    static s1plugin::LayoutRect swungBox(const s1plugin::LayoutRect &reach) {
        return { reach.x - kSwing, reach.y, reach.width + 2 * kSwing, reach.height };
    }

    /// Where a box sits inside this view, in points.
    juce::Rectangle<float> placed(const s1plugin::LayoutRect &box) const {
        return { (box.x - stick.reach.x + kSwing) * scaleX, (box.y - stick.reach.y) * scaleY,
                 box.width * scaleX, box.height * scaleY };
    }

    /// Only the reach box takes the mouse; the swing margin is there to draw in, and whatever the
    /// painting has beside the stick keeps its clicks.
    bool hitTest(int x, int y) override {
        return float(x) >= kSwing * scaleX && float(x) <= (kSwing + stick.reach.width) * scaleX
               && y >= 0 && y <= getHeight();
    }

    void paint(juce::Graphics &g) override {
        const juce::Point<float> pivot((stick.pivotX - stick.reach.x + kSwing) * scaleX, (stick.pivotY - stick.reach.y) * scaleY);
        juce::Graphics::ScopedSaveState state(g);
        // The whole stick leans about the socket: `CGAffineTransform(rotationAngle: lean * 0.5)`,
        // on the RAW sideways position — the dead zone is the pitch value's, not the picture's.
        g.addTransform(juce::AffineTransform::rotation(lean * 0.5f, pivot.x, pivot.y));
        if (rod.isValid()) { g.drawImage(rod, placed(stick.rodBox), juce::RectanglePlacement::stretchToFit); }
        if (ball.isValid()) {
            // 7 painting pixels up for a push, 8 down for a pull. The ball is drawn over the rod,
            // so it covers it as it comes forward and shows more of it as it goes back.
            const float slide = (push >= 0 ? -push * 7.0f : -push * 8.0f) * scaleY;
            g.drawImage(ball, placed(stick.ballBox).translated(0.0f, slide), juce::RectanglePlacement::stretchToFit);
        }
    }

    void mouseDown(const juce::MouseEvent &event) override { grabbedAt = event.position; grab(); }
    void mouseDrag(const juce::MouseEvent &event) override { moveBy(event.position.x - grabbedAt.x, event.position.y - grabbedAt.y); }
    void mouseUp(const juce::MouseEvent &) override { letGo(); }

    // The behaviour, as plain methods: a test drives these with no window (ADR-084).
    void grab() {
        modAtGrab = wheel;
        // X3-10: pulling the stick towards you takes the bitcrusher's rate down with it, from
        // wherever the sound has it — so it is remembered here, as the mod wheel's position is.
        crushAtGrab = plugin.hostParameter(S1Parameter::bitCrushSampleRate).getValue();
        stopTimer();
    }

    /// `dx`, `dy` in points from where it was grabbed. Right and down are positive.
    void moveBy(float dx, float dy) {
        const float x = juce::jlimit(-1.0f, 1.0f, dx / kTravel);
        const float y = juce::jlimit(-1.0f, 1.0f, -dy / kTravel);
        lean = x;
        push = y;
        // The mod wheel rises from where it was when grabbed, never from zero: under the cutoff
        // routing zero is a fully open filter, and a preset may rest the wheel anywhere.
        wheel = modAtGrab + (1.0f - modAtGrab) * std::max(0.0f, y);
        plugin.setModWheelFromInterface(wheel);
        // X3-10 (the owner, 2026-09-21): and PULLING it drives the bitcrusher's rate down — all
        // the way down at the bottom of the travel. Measured where the KNOB sits, not in hertz, so
        // the fall is even to the eye and to the ear (the rate's own taper does the rest); from
        // where the sound had it, as the wheel rises from where it was.
        setBitcrush(crushAtGrab * (1.0f - std::max(0.0f, -y)));
        // Sideways, with upstream's 15% dead zone rescaled over what is left, so a push does not
        // bend the pitch.
        const float leaning = std::abs(x) <= kDeadZone ? 0.0f : (x - kDeadZone * (x < 0 ? -1.0f : 1.0f)) / (1.0f - kDeadZone);
        setBend(0.5f + leaning * 0.5f);
        repaint();
    }

    void letGo() {
        // It springs back: the bend centres, and the wheel and the bitcrusher's rate return to
        // where they were when it was grabbed.
        wheel = modAtGrab;
        plugin.setModWheelFromInterface(wheel);
        setBitcrush(crushAtGrab);
        setBend(0.5f);
        startTimerHz(60);
    }

    float leanNow() const { return lean; }
    float pushNow() const { return push; }

private:
    static constexpr float kTravel = 36.0f, kDeadZone = 0.15f;

    /// The bitcrusher's rate, where its own knob would sit: 0 is 2,048 Hz, 1 is 48,000.
    void setBitcrush(float position01) {
        S1HostParameter &rate = plugin.hostParameter(S1Parameter::bitCrushSampleRate);
        const float clamped = juce::jlimit(0.0f, 1.0f, position01);
        rate.setPlainValueFromEngine(rate.getNormalisableRange().convertFrom0to1(clamped));
        rate.sendValueChangedMessageToListeners(clamped);
    }

    void setBend(float value01) {
        S1HostParameter &bend = plugin.hostParameter(S1Parameter::pitchbend);
        bend.setPlainValueFromEngine(bend.getNormalisableRange().convertFrom0to1(value01));
        bend.sendValueChangedMessageToListeners(value01);
    }

    /// The spring: 0.45 s, as the Mac's `usingSpringWithDamping: 0.45`.
    void timerCallback() override {
        lean *= 0.80f;
        push *= 0.80f;
        if (std::abs(lean) < 0.002f && std::abs(push) < 0.002f) { lean = push = 0; stopTimer(); }
        repaint();
    }

    S1PluginProcessor &plugin;
    const s1plugin::LayoutJoystick stick;
    juce::Image ball, rod;
    float scaleX = 1, scaleY = 1;
    juce::Point<float> grabbedAt;
    float lean = 0, push = 0, wheel = 0, modAtGrab = 0, crushAtGrab = 1.0f;
};

// MARK: - The editor

S1PluginEditor::S1PluginEditor(S1PluginProcessor &p, const std::string &skinKey) : juce::AudioProcessorEditor(p), plugin(p) {
    const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
    const std::string wanted = skinKey.empty() ? plugin.interfaceSkin().toStdString() : skinKey;
    const s1plugin::LayoutSkin *chosen = wanted.empty() ? spec.defaultSkin() : spec.skin(wanted);
    if (chosen == nullptr) { chosen = spec.defaultSkin(); }
    jassert(chosen != nullptr);   // PluginLayoutSpecTests holds the linked file to parse
    if (chosen == nullptr) { setSize(400, 120); return; }
    style = std::make_unique<s1ui::Style>(*chosen);

    // X3-7: everything lives on the stage, at the design size, whatever the window is.
    setOpaque(true);
    stage = std::make_unique<juce::Component>("interface");
    stage->setInterceptsMouseClicks(false, true);
    stage->setBounds(0, 0, juce::roundToInt(spec.designWidth), juce::roundToInt(spec.designHeight));
    addAndMakeVisible(*stage);

    backdrop = std::make_unique<Backdrop>(spec, *style);
    stage->addAndMakeVisible(*backdrop);
    buildControls();
    buildItems();

    // The window scales between 0.75x and 1.5x of the design size, keeping its shape: a host may
    // still hand us any size at all (pluginval does), and `resized` fits the interface into it.
    setResizable(true, true);
    setResizeLimits(juce::roundToInt(spec.designWidth * kMinScale), juce::roundToInt(spec.designHeight * kMinScale),
                    juce::roundToInt(spec.designWidth * kMaxScale), juce::roundToInt(spec.designHeight * kMaxScale));
    if (juce::ComponentBoundsConstrainer *constrainer = getConstrainer()) {
        constrainer->setFixedAspectRatio(double(spec.designWidth) / double(spec.designHeight));
    }
    setSize(juce::roundToInt(spec.designWidth), juce::roundToInt(spec.designHeight));
    // X3-8: musical typing and Command-K need the keys, and the drawer opens where this instance
    // left it (closed, unless its session says otherwise).
    setWantsKeyboardFocus(true);
    if (plugin.keyboardShown()) { showKeyboard(true); }
    refreshLiveState();
    startTimerHz(30);
}

S1PluginEditor::~S1PluginEditor() {
    stopTimer();
    panel.reset();
    joystick.reset();
    keyboard.reset();
    tuningsPanel.reset();     // it holds the tuning library and the style
    presetPanel.reset();      // it holds the browser and the style
    presetBackdrop.reset();
    browser.reset();
    owned.clear();   // the controls' attachments, before the processor's parameters can go
}

float S1PluginEditor::interfaceScale() const {
    const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
    if (spec.designWidth <= 0 || spec.designHeight <= 0 || getWidth() <= 0 || getHeight() <= 0) { return 1.0f; }
    // The smaller of the two: the whole interface fits, and is never cropped.
    return std::min(float(getWidth()) / spec.designWidth, float(getHeight()) / spec.designHeight);
}

void S1PluginEditor::paint(juce::Graphics &g) {
    // Only ever the letterbox: the stage's backdrop is opaque and covers the rest. A window whose
    // shape is not the design's keeps the interface centred in its own colour rather than
    // stretching it — the Mac does the same (ADR-019), because a stretch strands every control.
    g.fillAll(style != nullptr ? style->colour("windowBackground") : juce::Colours::black);
}

void S1PluginEditor::resized() {
    if (stage == nullptr) { return; }
    const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
    const float scale = interfaceScale();
    stage->setBounds(0, 0, juce::roundToInt(spec.designWidth), juce::roundToInt(spec.designHeight));
    stage->setTransform(juce::AffineTransform::scale(scale)
                            .translated(std::floor((float(getWidth()) - spec.designWidth * scale) * 0.5f),
                                        std::floor((float(getHeight()) - spec.designHeight * scale) * 0.5f)));
    layoutStage();
}

/// The design-size space itself never changes shape, so this only has to run when something in it
/// is made: the cards are placed in design points like everything else, and scale with the rest.
void S1PluginEditor::layoutStage() {
    if (stage == nullptr) { return; }
    const juce::Rectangle<int> inside = stage->getLocalBounds();
    if (backdrop != nullptr) { backdrop->setBounds(inside); }
    if (panel != nullptr) { panel->setBounds(inside); }
    if (presetBackdrop != nullptr) { presetBackdrop->setBounds(inside); }
    if (presetPanel != nullptr) { placePresetPanel(); }
    if (tuningsPanel != nullptr) { tuningsPanel->setBounds(juce::Rectangle<int>(s1ui::TuningsPanel::kWidth, s1ui::TuningsPanel::kHeight).withCentre(inside.getCentre())); }
    if (keyboard != nullptr) {
        // X3-8: the drawer sits over the lower sections and STOPS ABOVE THE PLAY BAR, because Hold,
        // Octave, Transpose and the wheels belong with the keys. Four octaves at the Mac's
        // proportions: its keyboard is 898 x 88 in a 1024-point window, which is this at 1440.
        const auto found = skin().regions.find("playBar");
        const int playBarTop = found != skin().regions.end() ? int(found->second.y) : 862;
        keyboard->setBounds(inside.getX() + 8, playBarTop - 6 - kKeyboardHeight, inside.getWidth() - 16, kKeyboardHeight);
    }
}

void S1PluginEditor::buildControls() {
    const s1ui::ParameterLookup lookup = [this](S1Parameter parameter) -> S1HostParameter & { return plugin.hostParameter(parameter); };
    auto place = [this](std::unique_ptr<juce::Component> component, const s1plugin::LayoutRect &frame) -> juce::Component * {
        if (component == nullptr) { return nullptr; }
        component->setBounds(pixels(frame));
        stage->addAndMakeVisible(*component);
        owned.push_back(std::move(component));
        return owned.back().get();
    };
    for (const s1plugin::LayoutControl &entry : skin().controls) {
        // X3-9: a control draws with its own ZONE's style, so cutting that zone's power greys it
        // and nothing else. Every drawing goes through `colour()` and `accentFor()` (ADR-084).
        s1ui::Style &zone = styleFor(zoneOfSection(entry.section));
        if (entry.valueFrame) {
            auto *readout = static_cast<s1ui::ValueReadout *>(place(std::make_unique<s1ui::ValueReadout>(lookup(entry.parameter), zone), *entry.valueFrame));
            // A rate's words depend on the tempo and the sync switch as well as on its own value
            if (entry.dependent) { rateReadouts.push_back(readout); }
        }
        juce::Component *made = place(s1ui::makeControl(entry, zone, lookup), entry.frame);
        if (entry.dependent && made != nullptr) { rateViews.push_back(made); }
        if (auto *box = dynamic_cast<s1ui::StepOctave *>(made)) { stepBoxes.push_back(box); }
        if (entry.kind == s1plugin::LayoutControlKind::tempo) { tempo = dynamic_cast<s1ui::Stepper *>(made); }
    }
    for (const s1plugin::LayoutDisplay &entry : skin().displays) {
        juce::Component *made = place(s1ui::makeDisplay(entry, styleFor(zoneOfSection(entry.section)), lookup), entry.frame);
        if (auto *pad = dynamic_cast<s1ui::XYPad *>(made)) { pads.push_back(pad); rateViews.push_back(pad); }
    }
}

void S1PluginEditor::buildItems() {
    const bool painted = skin().painting.has_value();
    const juce::Colour accent = style->colour("accent");
    juce::Rectangle<int> fieldFrame;
    for (const s1plugin::LayoutItem &item : skin().items) { if (item.id == "presetField") { fieldFrame = pixels(item.frame); } }

    auto add = [this](std::unique_ptr<juce::Component> component, const s1plugin::LayoutRect &frame, const std::string &id) -> juce::Component * {
        component->setBounds(pixels(frame));
        component->setComponentID(text(id));
        stage->addAndMakeVisible(*component);
        owned.push_back(std::move(component));
        return owned.back().get();
    };
    auto button = [&](const s1plugin::LayoutItem &item, ItemButton::Look look, std::function<void()> action, juce::Colour buttonAccent) -> ItemButton * {
        // X3-9: each draws with ITS ZONE's style, so cutting that zone's power greys it
        const std::string zone = zoneOfItem(item);
        auto made = std::make_unique<ItemButton>(styleFor(zone), text(item.title), look, buttonAccent);
        made->onPress = std::move(action);
        auto *placed = static_cast<ItemButton *>(add(std::move(made), item.frame, item.id));
        itemButtons.push_back(placed);
        itemZones[placed] = zone;
        return placed;
    };
    const auto later = [this](const char *what, const char *task) {
        return [this, what, task] { say(juce::String(what) + " comes with " + task + " of the plan."); };
    };

    for (const s1plugin::LayoutItem &item : skin().items) {
        // Painted: Cabinet's header, where the painting has the button and this takes the click.
        // Dark Arcade's painting has the arrows but no buttons, so those are drawn (2026-09-24).
        const bool isPainted = painted && item.region.empty();
        const bool buttonIsPainted = isPainted && skin().painting->paintedButtons;
        const ItemButton::Look dressed = buttonIsPainted ? ItemButton::Look::painted : ItemButton::Look::dressed;
        const std::string &id = item.id;
        if (id == "presetField") {
            auto field = std::make_unique<PresetField>(styleFor(zoneOfItem(item)), painted);
            field->onPress = [this] { showPresets(!isShowingPresets()); };
            presetField = static_cast<PresetField *>(add(std::move(field), item.frame, id));
        } else if (id == "scope") {
            scope = static_cast<ScopeView *>(add(std::make_unique<ScopeView>(plugin, styleFor(zoneOfItem(item)), painted), item.frame, id));
        } else if (id == "button.Previous preset") {
            button(item, isPainted ? ItemButton::Look::painted : ItemButton::Look::chevronLeft, [this] { stepPreset(-1); }, accent);
        } else if (id == "button.Next preset") {
            button(item, isPainted ? ItemButton::Look::painted : ItemButton::Look::chevronRight, [this] { stepPreset(1); }, accent);
        } else if (id == "dice") {
            button(item, ItemButton::Look::dice, [this] {
                if (const s1::Preset *preset = presetBrowser().randomPreset()) { playPreset(*preset); say("\xF0\x9F\x8E\xB2 " + juce::String::fromUTF8(preset->name.c_str())); }
            }, accent);
        } else if (id == "button.Save") {
            // `savePresetPressed` on the Mac: the preset editor, on the sound as it stands.
            button(item, dressed, [this] { showPresets(true); if (presetPanel != nullptr) { presetPanel->editCurrentPreset(); } }, accent);
        } else if (id == "button.Panic") {
            button(item, dressed, [this] { plugin.requestAllNotesOff(); say("All notes off."); }, accent);
        } else if (id == "button.About" || id == "button.About Arcade Ruins") {
            // Over a painting this is the wordmark's click, never a drawn button
            button(item, isPainted ? ItemButton::Look::painted : ItemButton::Look::dressed, [this] { showAbout(); }, accent);
        } else if (id == "button.Settings") {
            button(item, dressed, [this] { showSettings(true); }, accent);
        } else if (id == "button.Presets" || id == "button.Presets.2") {
            if (pixels(item.frame) == fieldFrame) { continue; }   // the field itself is the way in
            button(item, dressed, [this] { showPresets(!isShowingPresets()); }, accent);
        } else if (id == "button.Mono") {
            monoButton = button(item, dressed, [this] {
                S1HostParameter &mono = plugin.hostParameter(S1Parameter::isMono);
                mono.beginChangeGesture();
                mono.setValueNotifyingHost(mono.getValue() >= 0.5f ? 0.0f : 1.0f);
                mono.endChangeGesture();
            }, accent);
        } else if (id == "button.Snap") {
            snapButton = button(item, dressed, [this] {
                snap = !snap;
                for (s1ui::XYPad *pad : pads) { pad->setSnapsBack(snap); }
            }, style->accentFor(item.region));
        } else if (id == "button.Hold") {
            // X3-8: `holdButton.setValueCallback` — the router latches, and releases every key
            // when it goes off. Nothing here touches a note.
            holdButton = button(item, dressed, [this] {
                plugin.setHolding(!plugin.isHolding());
                say(plugin.isHolding() ? "Hold: ON" : "Hold: OFF");
            }, accent);
        } else if (id == "button.Wheels") {
            button(item, dressed, [this] { showWheels(!isShowingWheels()); }, accent);
        } else if (id == "octave") {
            // One octave for everything, as the Mac settled it (the owner, 2026-09-09): the
            // drawer's keys, a typed note and a host's MIDI all move together.
            octaveButton = button(item, ItemButton::Look::stepper, [this] {}, accent);
            octaveButton->setWords("0");
            octaveButton->onStep = [this](int direction) {
                releaseTypedNotes();          // they belong to the octave they were played in
                plugin.setOctaveShift(plugin.octaveShift() + direction);
                if (keyboard != nullptr) { keyboard->setSoundingShift(plugin.octaveShift() * 12); }
                say("Keyboard Octave: " + juce::String(plugin.octaveShift()));
            };
        } else if (id == "tuning") {
            tuningButton = button(item, ItemButton::Look::plain, [this] { showTunings(!isShowingTunings()); }, accent);
            tuningButton->setWords("Tuning  12 ET");
        } else if (id == "record" && painted) {
            // The painting leaves this plate empty for the Mac app's recorder; a plugin has none, so —
            // as the Mac plugin does — it is About
            s1plugin::LayoutItem plate = item;
            if (skin().painting) {
                const auto found = skin().painting->places.find("record");
                if (found != skin().painting->places.end()) { plate.frame = skin().painting->inWindow(found->second, S1LinkedLayoutSpec().designWidth, S1LinkedLayoutSpec().designHeight); }
            }
            plate.title = "About";
            // On a painted plate the word alone; in a bare header, a button like its neighbours
            const ItemButton::Look look = skin().painting->paintedButtons ? ItemButton::Look::plain : ItemButton::Look::dressed;
            ItemButton *about = button(plate, look, [this] { showAbout(); }, accent);
            about->setComponentID("button.About");
        }
        // Not built, on purpose: `record` / `recordStatus` (the host records), `button.MIDI Learn`
        // (deferred for 1.0, ADR-056), `wordmark` and `presetName` (the backdrop's and the field's).
    }

    // X3-9 (ADR-091): the two red buttons on the console, as invisible hit areas over the painted
    // ones — the header's buttons are the same. Cabinet only; Studio has no console.
    if (skin().painting && skin().painting->power) {
        const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
        const s1plugin::LayoutPower &power = *skin().painting->power;
        const auto redButton = [&](const s1plugin::LayoutRect &box, const char *id, const char *words, bool powered) {
            auto made = std::make_unique<ItemButton>(*style, juce::String(), ItemButton::Look::painted, accent);
            made->onPress = [this, powered] { runPower(powered); };
            made->setBounds(pixels(skin().painting->inWindow(box, spec.designWidth, spec.designHeight)));
            made->setComponentID(id);
            made->setTitle(words);
            made->setAccessible(true);
            stage->addAndMakeVisible(*made);
            itemButtons.push_back(made.get());
            ItemButton *placed = made.get();
            owned.push_back(std::move(made));
            return placed;
        };
        powerOff = redButton(power.off, "power.off", "Cut the power", false);
        powerOn = redButton(power.on, "power.on", "Restore the power", true);
    }

    // X3-6: the cabinet's stick, over the console the painting leaves empty
    if (skin().painting && skin().painting->joystick) {
        const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
        joystick = std::make_unique<Joystick>(plugin, *skin().painting->joystick, *skin().painting, spec.designWidth, spec.designHeight);
        joystick->setBounds(pixels(skin().painting->inWindow(Joystick::swungBox(skin().painting->joystick->reach), spec.designWidth, spec.designHeight)));
        joystick->setComponentID("joystick");
        stage->addAndMakeVisible(*joystick);
    }

    // The status bar's hint doubles as the place the interface says things
    for (const s1plugin::LayoutLabel &label : skin().labels) {
        if (label.text.rfind(kHintPrefix, 0) != 0) { continue; }
        hint = s1ui::Style::drawable(text(label.text));
        status = std::make_unique<juce::Label>();
        status->setFont(style->font(11.0f));
        status->setColour(juce::Label::textColourId, style->colour("dim"));
        status->setJustificationType(juce::Justification::centredRight);
        status->setInterceptsMouseClicks(false, false);
        status->setText(hint, juce::dontSendNotification);
        status->setBounds(rectangle(label.frame).withLeft(label.frame.x - 420.0f).expanded(0, 2).toNearestInt());
        stage->addAndMakeVisible(*status);
    }
}

// MARK: - Live state

void S1PluginEditor::refreshLiveState() {
    // X3-9: the power cycle, while one is running.
    if (powerCycle != nullptr) { applyPower(); }
    // The playing step: lit while the sequencer's counter is moving
    const int beat = plugin.arpBeatCounter();
    if (beat != lastBeat) { lastBeat = beat; ticksSinceBeat = 0; } else if (ticksSinceBeat < 1000) { ++ticksSinceBeat; }
    const bool running = ticksSinceBeat < 20 && plugin.hostParameter(S1Parameter::arpIsOn).plainValue() >= 0.5f;
    const int steps = std::max(1, juce::roundToInt(plugin.hostParameter(S1Parameter::arpTotalSteps).plainValue()));
    for (size_t i = 0; i < stepBoxes.size(); ++i) { stepBoxes[i]->setPlaying(running && beat >= 0 && int(i) == beat % steps); }

    if (tempo != nullptr) { tempo->setHostOwned(plugin.isUsingHostTempo()); }
    for (s1ui::ValueReadout *readout : rateReadouts) { readout->refresh(); }
    const float sync = plugin.hostParameter(S1Parameter::tempoSyncToArpRate).plainValue(), bpm = plugin.hostParameter(S1Parameter::arpRate).plainValue();
    if (!juce::exactlyEqual(sync, lastSync) || !juce::exactlyEqual(bpm, lastTempo)) {
        lastSync = sync;
        lastTempo = bpm;
        for (juce::Component *view : rateViews) { view->repaint(); }
    }
    if (monoButton != nullptr) { monoButton->setLit(plugin.hostParameter(S1Parameter::isMono).plainValue() >= 0.5f); }
    if (snapButton != nullptr) { snapButton->setLit(snap); }
    // X3-8: Hold and the octave are the router's, and a host's automation or another window can
    // move them, so the play bar follows rather than remembers.
    if (holdButton != nullptr) { holdButton->setLit(plugin.isHolding()); }
    if (octaveButton != nullptr) { octaveButton->setWords(juce::String(plugin.octaveShift())); }
    if (keyboard != nullptr) {
        // Whoever played them: the drawer lights the notes the router is holding, as
        // `KeyboardView.hostOnKeys` does on the Mac.
        juce::uint64 low = 0, high = 0;
        plugin.heldKeys(low, high);
        std::set<int> held;
        for (int note = 0; note < 128; ++note) {
            const juce::uint64 bits = note < 64 ? low : high;
            if ((bits >> (note % 64)) & 1u) { held.insert(note); }
        }
        keyboard->setHostHeldKeys(held);
        keyboard->setSoundingShift(plugin.octaveShift() * 12);
    }

    if (tuningButton != nullptr) {
        const juce::String named = plugin.tuningLibrary().tuningName().empty()
                                       ? juce::String("12 ET")
                                       : juce::String::fromUTF8(plugin.tuningLibrary().tuningName().c_str());
        tuningButton->setWords("Tuning  " + named);
    }
    // A4 is a parameter, so a host or the Every-parameter list can move it: the table follows.
    const double a4 = double(plugin.hostParameter(S1Parameter::frequencyA4).plainValue());
    if (!juce::exactlyEqual(a4, plugin.tuningA4())) { plugin.retune(); if (tuningsPanel != nullptr) { tuningsPanel->refresh(); } }

    const juce::String title = presetTitle();
    if (presetField != nullptr && title != shownPreset) { shownPreset = title; presetField->setPresetName(title); }
    if (scope != nullptr && isShowing()) { scope->repaint(); }

    if (ticksOfMessage > 0 && --ticksOfMessage == 0 && status != nullptr) { status->setText(hint, juce::dontSendNotification); }
}

juce::String S1PluginEditor::presetTitle() const {
    const juce::String bank = plugin.currentPresetBank(), name = plugin.currentPresetName();
    return bank.isEmpty() ? name : bank + ": " + name;
}

void S1PluginEditor::stepPreset(int direction) {
    // The list the browser is showing — a bank, a category, the search's matches — not the
    // host's program order (X3-4). What the browser holds is the person's own banks.
    if (const s1::Preset *preset = presetBrowser().step(direction)) { playPreset(*preset); }
}

// MARK: - The preset browser (X3-4, ADR-086)

s1plugin::PresetBrowser &S1PluginEditor::presetBrowser() {
    if (browser == nullptr) {
        browser = std::make_unique<s1plugin::PresetBrowser>(plugin.presetLibrary());
        // The first load writes the banks the Mac starts with into the shared folder: 2 MB once,
        // and only when a person asks for a preset — never when a host scans or opens the window.
        browser->load();
        browser->setCurrent(soundNow().uid);
        // `PresetsViewController.viewDidLoad` chooses row 0, All: previous and next walk the
        // whole library until a person picks a bank or a category.
    }
    return *browser;
}

s1::Preset S1PluginEditor::soundNow() const { return plugin.currentState().capturedPreset(); }

void S1PluginEditor::playPreset(const s1::Preset &preset) {
    plugin.loadPreset(preset, true);
    presetBrowser().setCurrent(preset.uid);
    refreshLiveState();
}

void S1PluginEditor::placePresetPanel() {
    if (presetPanel == nullptr) { return; }
    // The Mac hangs the card under the preset name itself, centred on it (P7-9).
    const juce::Rectangle<int> field = presetField != nullptr ? presetField->getBounds() : juce::Rectangle<int>(0, 0, 200, 30);
    const int top = field.getBottom() + 10;
    // In the stage's design points, as the field's own frame is: the window's scale is not its business.
    const int height = std::min(s1ui::PresetPanel::kHeight, stage->getHeight() - top - 12);
    const int left = juce::jlimit(8, std::max(8, stage->getWidth() - s1ui::PresetPanel::kWidth - 8),
                                  field.getCentreX() - s1ui::PresetPanel::kWidth / 2);
    presetPanel->setBounds(left, top, s1ui::PresetPanel::kWidth, std::max(200, height));
}

void S1PluginEditor::showPresets(bool show) {
    if (!show) { presetPanel.reset(); presetBackdrop.reset(); return; }
    if (presetPanel != nullptr) { return; }

    /// A click anywhere else puts the card away, as the Mac's backdrop does.
    class Backstop final : public juce::Component {
    public:
        explicit Backstop(std::function<void()> close) : onPress(std::move(close)) {
            setAccessible(true);
            setTitle("Close the preset browser");
        }
        void mouseUp(const juce::MouseEvent &) override { if (onPress) { onPress(); } }
    private:
        std::function<void()> onPress;
    };
    // MSVC cannot compile an init-capture inside a lambda that is itself inside a lambda, when the
    // initialiser uses the outer lambda's `this` (the owner's Windows fix, 2026-09-20): the
    // SafePointer is made here and captured by copy instead. Clang and GCC accept either.
    juce::Component::SafePointer<S1PluginEditor> safe(this);
    presetBackdrop = std::make_unique<Backstop>([safe] {
        juce::MessageManager::callAsync([safe] { if (safe != nullptr) { safe->showPresets(false); } });
    });
    presetBackdrop->setBounds(stage->getLocalBounds());
    stage->addAndMakeVisible(*presetBackdrop);

    presetPanel = std::make_unique<s1ui::PresetPanel>(presetBrowser(), *style);
    presetPanel->onChoose = [this](const s1::Preset &preset) { playPreset(preset); };
    presetPanel->onSay = [this](const juce::String &message) { say(message); };
    presetPanel->soundNow = [this] { return soundNow(); };
    presetPanel->onClose = [safe] {
        juce::MessageManager::callAsync([safe] { if (safe != nullptr) { safe->showPresets(false); } });
    };
    stage->addAndMakeVisible(*presetPanel);
    placePresetPanel();
    presetPanel->toFront(true);
}

// MARK: - The cabinet's power (X3-9, ADR-091)

/// The zone a section belongs to. The fifteen sections are their own; the play bar and the status
/// bar are one "bar", as the Mac's zones are (ADR-062).
std::string S1PluginEditor::zoneOfSection(const std::string &section) {
    if (section == "playBar" || section == "statusBar") { return "bar"; }
    if (section == "toolbar") { return "buttons"; }
    return section.empty() ? "buttons" : section;
}

/// …and the zone of a toolbar, header or bar item. The painting goes grey under these by its
/// rectangle; what is DRAWN over it — the preset's name, the scope's line, the bar's buttons, Snap —
/// has to be drawn grey too, which is what stayed lit in the first cut (seen in a render).
std::string S1PluginEditor::zoneOfItem(const s1plugin::LayoutItem &item) {
    const std::string &id = item.id;
    if (id == "presetField" || id == "presetName" || id == "dice" || id == "button.Previous preset"
        || id == "button.Next preset" || id == "button.Presets.2") { return "display"; }
    if (id == "scope") { return "screen"; }
    return zoneOfSection(item.region);
}

s1ui::Style &S1PluginEditor::styleFor(const std::string &zone) {
    auto found = zoneStyles.find(zone);
    if (found != zoneStyles.end()) { return *found->second; }
    auto made = std::make_unique<s1ui::Style>(skin());
    s1ui::Style &ref = *made;
    zoneStyles[zone] = std::move(made);
    return ref;
}

std::vector<std::string> S1PluginEditor::powerZones() const {
    std::vector<std::string> zones;
    for (const s1plugin::LayoutSection &section : skin().sections) { zones.push_back(section.key); }
    if (skin().painting && skin().painting->power) {
        for (const auto &entry : skin().painting->power->zones) { zones.push_back(entry.first); }
    }
    return zones;
}

float S1PluginEditor::zoneDim(const std::string &zone) const {
    const auto found = zoneStyles.find(zone);
    return found != zoneStyles.end() ? found->second->dim() : 0.0f;
}

void S1PluginEditor::runPower(bool powered) {
    // Pressing the button for the way it is ALREADY going does nothing: it used to start the
    // eight seconds again, so a person pressing once a second — which is what a person does, since
    // the first zone does not settle for a second — held the interface dark indefinitely. The
    // owner, 2026-09-22: "neither of them turn them back on again" (ADR-099).
    if (powerCycle != nullptr && powerCycle->towardsPowered() == powered) { return; }
    // Only the zones that still have to change are planned, from where they are NOW: pressing the
    // other button part way through must not black out the half that is still lit.
    std::vector<std::string> remaining;
    for (const std::string &zone : powerZones()) {
        const bool isLit = zoneDim(zone) < 0.5f;
        if (isLit != powered) { remaining.push_back(zone); }
    }
    powerCycle = std::make_unique<s1plugin::PowerCycle>(remaining, powered,
                                                        juce::uint32(juce::Random::getSystemRandom().nextInt()));
    powerStartedAt = juce::Time::getMillisecondCounterHiRes();
    applyPower();
    say(powered ? "Power restored." : "Power cut.");
}

void S1PluginEditor::restorePower() {
    powerCycle.reset();
    for (auto &entry : zoneStyles) { entry.second->setDim(0.0f); }
    if (backdrop != nullptr) { backdrop->setZoneDim({}); }
    if (stage != nullptr) { stage->repaint(); }
}

/// The cycle's state, on the editor's own 30 Hz timer — no clock of its own.
void S1PluginEditor::applyPower() {
    if (powerCycle == nullptr) { return; }
    applyPower((juce::Time::getMillisecondCounterHiRes() - powerStartedAt) / 1000.0);
}

void S1PluginEditor::applyPower(double seconds) {
    if (powerCycle == nullptr) { return; }
    std::map<std::string, float> dims;
    for (const std::string &zone : powerZones()) {
        const float dim = powerCycle->isLit(zone, seconds) ? 0.0f : 1.0f;
        dims[zone] = dim;
        s1ui::Style &zoneStyle = styleFor(zone);
        if (!juce::exactlyEqual(zoneStyle.dim(), dim)) { zoneStyle.setDim(dim); }
    }
    if (backdrop != nullptr) { backdrop->setZoneDim(dims); }
    // A control keeps the accent it was built with rather than asking its style at each paint, so
    // the dead colour is handed to it — the Mac swaps held colours the same way (ADR-062).
    for (s1ui::ParameterControl *control : parameterControls()) {
        const s1plugin::LayoutControl *entry = skin().control(control->getComponentID().toStdString());
        if (entry == nullptr) { continue; }
        const std::string zone = zoneOfSection(entry->section);
        control->setAccent(styleFor(zone).dimmed(style->accentFor(entry->section)));
    }
    // …and the same for what the toolbar's and play bar's buttons hold, and for the envelope
    // plots' line and fill, which are handed to them from the specification.
    for (ItemButton *item : itemButtons) {
        const auto zone = itemZones.find(item);
        if (zone == itemZones.end()) { continue; }  // the red buttons themselves never go grey
        item->setAccent(styleFor(zone->second).dimmed(style->colour("accent")));
    }
    // The bar's words are a label, which holds its colour as the buttons hold their accent.
    if (status != nullptr) { status->setColour(juce::Label::textColourId, styleFor("bar").dimmed(style->colour("dim"))); }
    for (const s1plugin::LayoutDisplay &display : skin().displays) {
        if (!display.curve || !display.fill) { continue; }
        juce::Component *found = nullptr;
        for (auto &owned2 : owned) { if (owned2->getComponentID() == text(display.id)) { found = owned2.get(); } }
        if (auto *plot = dynamic_cast<s1ui::EnvelopeView *>(found)) {
            s1ui::Style &zone = styleFor(zoneOfSection(display.section));
            plot->setColours(zone.dimmed(toColour(*display.curve)), zone.dimmed(toColour(*display.fill)));
        }
    }
    if (stage != nullptr) { stage->repaint(); }
    if (powerCycle->isFinished(seconds)) { powerCycle.reset(); }
}

// MARK: - The keyboard drawer (X3-8, ADR-090)

void S1PluginEditor::showKeyboard(bool show) {
    if (!show) {
        releaseTypedNotes();
        if (keyboard != nullptr) { keyboard->releaseAll(); }
        keyboard.reset();
        plugin.setKeyboardShown(false);
        return;
    }
    if (keyboard != nullptr) { return; }
    keyboard = std::make_unique<s1ui::Keyboard>(*style, 4, 2);
    keyboard->setSoundingShift(plugin.octaveShift() * 12);
    keyboard->setComponentID("keyboard");
    // It sounds nothing itself: the note goes to the processor, which plays it through the router
    // at the top of the next block — the host's own route (ADR-031).
    keyboard->onNoteOn = [this](int note, int velocity) {
        plugin.sendMIDIFromInterface(0x90, juce::uint8(note), juce::uint8(velocity));
    };
    keyboard->onNoteOff = [this](int note) { plugin.sendMIDIFromInterface(0x80, juce::uint8(note), 0); };
    stage->addAndMakeVisible(*keyboard);
    layoutStage();
    keyboard->toFront(false);
    plugin.setKeyboardShown(true);
}

int S1PluginEditor::typedOctave() const { return plugin.octaveShift(); }

void S1PluginEditor::releaseTypedNotes() {
    for (const auto &typed : typedNotes) { plugin.sendMIDIFromInterface(0x80, juce::uint8(typed.second), 0); }
    typedNotes.clear();
    if (keyboard != nullptr) { keyboard->repaint(); }
}

bool S1PluginEditor::typedKeyDown(int keyCode, const juce::ModifierKeys &modifiers) {
    // `pressesBegan`: a key carrying a modifier belongs to a menu, not to the keyboard —
    // otherwise Command-S would play a D.
    if (modifiers.isCommandDown() || modifiers.isCtrlDown() || modifiers.isAltDown()) { return false; }
    // `Manager.musicalTypingMap`, semitones from the base note.
    static const std::map<int, int> kTyping {
        { 'A', 0 }, { 'W', 1 }, { 'S', 2 }, { 'E', 3 }, { 'D', 4 }, { 'F', 5 }, { 'T', 6 },
        { 'G', 7 }, { 'Y', 8 }, { 'H', 9 }, { 'U', 10 }, { 'J', 11 }, { 'K', 12 }, { 'O', 13 },
        { 'L', 14 }, { 'P', 15 }, { ';', 16 }, { '\'', 17 }
    };
    const int key = keyCode >= 'a' && keyCode <= 'z' ? keyCode - 'a' + 'A' : keyCode;
    if (key == 'Z' || key == 'X') {
        // The sounding notes belong to the old octave: their key-up would compute another note.
        releaseTypedNotes();
        plugin.setOctaveShift(plugin.octaveShift() + (key == 'X' ? 1 : -1));
        if (keyboard != nullptr) { keyboard->setSoundingShift(plugin.octaveShift() * 12); }
        say("Keyboard Octave: " + juce::String(plugin.octaveShift()));
        return true;
    }
    if (key == 'C' || key == 'V') {
        velocityOfTypedNotes = juce::jlimit(1, 127, velocityOfTypedNotes + (key == 'V' ? 16 : -16));
        say("Typing velocity: " + juce::String(velocityOfTypedNotes));
        return true;
    }
    const auto found = kTyping.find(key);
    if (found == kTyping.end()) { return false; }
    if (typedNotes.count(key) > 0) { return true; }   // auto-repeat, or every one retriggers the envelope
    const int note = juce::jlimit(0, 127, 60 + plugin.octaveShift() * 12 + found->second);
    typedNotes[key] = note;
    plugin.sendMIDIFromInterface(0x90, juce::uint8(note), juce::uint8(velocityOfTypedNotes));
    if (keyboard != nullptr) { keyboard->repaint(); }
    return true;
}

bool S1PluginEditor::keyPressed(const juce::KeyPress &key) {
    // The design's Command-K (Control-K where there is no Command): the drawer. A key code is
    // upper case when it comes from a keystroke and whatever was written when it comes from a test.
    const int code = key.getKeyCode() >= 'a' && key.getKeyCode() <= 'z' ? key.getKeyCode() - 'a' + 'A' : key.getKeyCode();
    if (code == 'K' && (key.getModifiers().isCommandDown() || key.getModifiers().isCtrlDown())) {
        showKeyboard(!isShowingKeyboard());
        say(isShowingKeyboard() ? "Keyboard shown." : "Keyboard hidden.");
        return true;
    }
    return typedKeyDown(key.getKeyCode(), key.getModifiers());
}

bool S1PluginEditor::keyStateChanged(bool) {
    // JUCE reports that SOMETHING changed, not what: the notes still down are the ones whose key
    // is still down. This is how a typed note is let go.
    std::vector<int> lifted;
    for (const auto &typed : typedNotes) {
        if (!juce::KeyPress::isKeyCurrentlyDown(typed.first)) { lifted.push_back(typed.first); }
    }
    for (const int key : lifted) {
        plugin.sendMIDIFromInterface(0x80, juce::uint8(typedNotes[key]), 0);
        typedNotes.erase(key);
    }
    if (!lifted.empty() && keyboard != nullptr) { keyboard->repaint(); }
    return !lifted.empty();
}

void S1PluginEditor::focusLost(FocusChangeType) { releaseTypedNotes(); }

juce::Rectangle<int> S1PluginEditor::joystickBounds() const { return joystick != nullptr ? joystick->getBounds() : juce::Rectangle<int>(); }
void S1PluginEditor::joystickGrab() { if (joystick != nullptr) { joystick->grab(); } }
void S1PluginEditor::joystickMoveBy(float dx, float dy) { if (joystick != nullptr) { joystick->moveBy(dx, dy); } }
void S1PluginEditor::joystickLetGo() { if (joystick != nullptr) { joystick->letGo(); } }
float S1PluginEditor::joystickLean() const { return joystick != nullptr ? joystick->leanNow() : 0.0f; }
float S1PluginEditor::joystickPush() const { return joystick != nullptr ? joystick->pushNow() : 0.0f; }

// MARK: - Settings and the skin (X3-6, ADR-088)

void S1PluginEditor::tearDownSkin() {
    // The cards hold the style and the browser; they go first.
    panel.reset();
    tuningsPanel.reset();
    presetPanel.reset();
    presetBackdrop.reset();
    status.reset();
    joystick.reset();
    keyboard.reset();          // it holds the style
    backdrop.reset();
    owned.clear();                      // the controls' attachments, before anything else
    itemButtons.clear();
    powerCycle.reset();
    powerOff = powerOn = nullptr;
    zoneStyles.clear();      // they hold the skin, and a new skin needs new ones
    itemZones.clear();
    rateReadouts.clear();
    rateViews.clear();
    stepBoxes.clear();
    pads.clear();
    tempo = nullptr;
    presetField = nullptr;
    scope = nullptr;
    monoButton = snapButton = tuningButton = nullptr;
    holdButton = octaveButton = nullptr;
    shownPreset = {};
    lastSync = lastTempo = -1;
}

void S1PluginEditor::applySkin(const std::string &skinKey) {
    const s1plugin::LayoutSpec &spec = S1LinkedLayoutSpec();
    const s1plugin::LayoutSkin *chosen = spec.skin(skinKey);
    if (chosen == nullptr || chosen->key == skin().key) { return; }
    tearDownSkin();
    style = std::make_unique<s1ui::Style>(*chosen);
    backdrop = std::make_unique<Backdrop>(spec, *style);
    stage->addAndMakeVisible(*backdrop);
    buildControls();
    buildItems();
    if (plugin.keyboardShown()) { showKeyboard(true); }
    resized();
    refreshLiveState();
    plugin.setInterfaceSkin(juce::String(skinKey));
    say(juce::String::fromUTF8(chosen->title.c_str()) + ".");
}

/// The Settings card: what the interface is, rather than what the sound is. The list of all 150
/// parameters is one entry in it now, as ADR-085 said it would be.
class S1PluginEditor::SettingsBody final : public juce::Component {
public:
    SettingsBody(S1PluginEditor &owner, const s1ui::Style &s) : editor(owner), style(s) {
        heading.setText("Skin", juce::dontSendNotification);
        subheading.setText("The sound is the same in every one.", juce::dontSendNotification);
        for (juce::Label *label : { &heading, &subheading }) {
            label->setFont(style.font(label == &heading ? 13.0f : 11.0f,
                                      label == &heading ? s1ui::FontWeight::demiBold : s1ui::FontWeight::regular));
            label->setColour(juce::Label::textColourId, style.colour(label == &heading ? "text" : "dim"));
            addAndMakeVisible(*label);
        }
        for (const char *key : { "cabinet", "darkArcade", "studio" }) {
            const s1plugin::LayoutSkin *listed = S1LinkedLayoutSpec().skin(key);
            if (listed == nullptr) { continue; }
            auto made = std::make_unique<juce::TextButton>(juce::String::fromUTF8(listed->title.c_str()));
            made->setComponentID(juce::String("skin.") + key);
            made->setColour(juce::TextButton::buttonColourId, style.colour("controlFace"));
            made->setColour(juce::TextButton::buttonOnColourId, style.colour("accent"));
            made->setColour(juce::TextButton::textColourOffId, style.colour("text"));
            made->setColour(juce::TextButton::textColourOnId, style.colour("accentOnTop"));
            made->setClickingTogglesState(false);
            made->setToggleState(editor.skin().key == key, juce::dontSendNotification);
            const std::string wanted = key;
            // The SafePointer is a LOCAL, captured by copy: an init-capture here would be inside
            // two lambdas, which MSVC cannot compile (ADR-088, and the owner's fix at X3-5).
            const juce::Component::SafePointer<SettingsBody> safe(this);
            made->onClick = [safe, wanted] {
                juce::MessageManager::callAsync([safe, wanted] {
                    if (safe != nullptr) { safe->editor.applySkin(wanted); }
                });
            };
            addAndMakeVisible(*made);
            skinButtons.push_back(std::move(made));
        }
        tuningWithPreset.setButtonText("A preset carries its own tuning");
        tuningWithPreset.setToggleState(editor.plugin.savesTuningWithPreset(), juce::dontSendNotification);
        tuningWithPreset.setColour(juce::ToggleButton::textColourId, style.colour("text"));
        tuningWithPreset.setColour(juce::ToggleButton::tickColourId, style.colour("accent"));
        tuningWithPreset.onClick = [this] { editor.plugin.setSavesTuningWithPreset(tuningWithPreset.getToggleState()); };
        addAndMakeVisible(tuningWithPreset);

        everyParameter.setButtonText(juce::String::fromUTF8("Every parameter\xe2\x80\xa6"));
        everyParameter.setColour(juce::TextButton::buttonColourId, style.colour("controlFace"));
        everyParameter.setColour(juce::TextButton::textColourOffId, style.colour("text"));
        const juce::Component::SafePointer<SettingsBody> safeForList(this);   // a local, as above
        everyParameter.onClick = [safeForList] {
            juce::MessageManager::callAsync([safeForList] {
                if (safeForList != nullptr) { safeForList->editor.showAllParameters(true); }
            });
        };
        addAndMakeVisible(everyParameter);
    }

    void resized() override {
        juce::Rectangle<int> inside = getLocalBounds();
        heading.setBounds(inside.removeFromTop(18));
        subheading.setBounds(inside.removeFromTop(16));
        inside.removeFromTop(8);
        juce::Rectangle<int> row = inside.removeFromTop(30);
        for (auto &button : skinButtons) { button->setBounds(row.removeFromLeft(120)); row.removeFromLeft(8); }
        inside.removeFromTop(20);
        tuningWithPreset.setBounds(inside.removeFromTop(26));
        inside.removeFromTop(16);
        everyParameter.setBounds(inside.removeFromTop(28).removeFromLeft(180));
    }

private:
    S1PluginEditor &editor;
    const s1ui::Style &style;
    juce::Label heading, subheading;
    std::vector<std::unique_ptr<juce::TextButton>> skinButtons;
    juce::ToggleButton tuningWithPreset;
    juce::TextButton everyParameter;
};

/// The Wheels card: upstream's `WheelSettingsViewController` — what the mod wheel moves, and how
/// far the pitch wheel bends. Its popover is 300 x 290 on the Mac; this is the same three things.
class S1PluginEditor::WheelsBody final : public juce::Component {
public:
    WheelsBody(S1PluginEditor &owner, const s1ui::Style &s) : editor(owner), style(s) {
        heading.setText("The mod wheel moves", juce::dontSendNotification);
        pitchHeading.setText("The pitch wheel bends", juce::dontSendNotification);
        for (juce::Label *label : { &heading, &pitchHeading }) {
            label->setFont(style.font(13.0f, s1ui::FontWeight::demiBold));
            label->setColour(juce::Label::textColourId, style.colour("text"));
            addAndMakeVisible(*label);
        }
        // `modWheelSegment`: Cutoff / LFO 1 / LFO 2, which is `Preset.modWheelRouting`.
        int index = 0;
        for (const char *words : { "Cutoff", "LFO 1 Rate", "LFO 2 Rate" }) {
            auto made = std::make_unique<juce::TextButton>(words);
            made->setComponentID(juce::String("wheel.") + juce::String(index));
            made->setColour(juce::TextButton::buttonColourId, style.colour("controlFace"));
            made->setColour(juce::TextButton::buttonOnColourId, style.colour("accent"));
            made->setColour(juce::TextButton::textColourOffId, style.colour("text"));
            made->setColour(juce::TextButton::textColourOnId, style.colour("accentOnTop"));
            made->setToggleState(int(editor.plugin.getModWheelRouting()) == index, juce::dontSendNotification);
            const int chosen = index;
            const juce::Component::SafePointer<WheelsBody> safe(this);   // a LOCAL, captured by copy (ADR-088)
            made->onClick = [safe, chosen] {
                if (safe == nullptr) { return; }
                safe->editor.plugin.setModWheelRouting(s1plugin::ModWheelRouting(chosen));
                safe->refresh();
                safe->editor.say(juce::String("The mod wheel moves ") + (chosen == 0 ? "the cutoff." : chosen == 1 ? "LFO 1's rate." : "LFO 2's rate."));
            };
            addAndMakeVisible(*made);
            routing.push_back(std::move(made));
            ++index;
        }
        // `pitchUpperRange` / `pitchLowerRange`, the two parameters the desktop layout gives no
        // control of their own (ADR-083, ADR-085): here they have one.
        const s1ui::ParameterLookup lookup = [&owner](S1Parameter parameter) -> S1HostParameter & { return owner.plugin.hostParameter(parameter); };
        for (const S1Parameter parameter : { S1Parameter::pitchbendMinSemitones, S1Parameter::pitchbendMaxSemitones }) {
            auto made = std::make_unique<s1ui::Stepper>(lookup(parameter), style, style.colour("accent"), s1ui::Stepper::Look::plain);
            addAndMakeVisible(*made);
            steppers.push_back(std::move(made));
            auto caption = std::make_unique<juce::Label>();
            caption->setText(parameter == S1Parameter::pitchbendMinSemitones ? "Down, semitones" : "Up, semitones", juce::dontSendNotification);
            caption->setFont(style.font(11.0f));
            caption->setColour(juce::Label::textColourId, style.colour("dim"));
            addAndMakeVisible(*caption);
            captions.push_back(std::move(caption));
        }
    }

    void refresh() {
        for (size_t i = 0; i < routing.size(); ++i) {
            routing[i]->setToggleState(size_t(editor.plugin.getModWheelRouting()) == i, juce::dontSendNotification);
        }
    }

    void resized() override {
        juce::Rectangle<int> inside = getLocalBounds();
        heading.setBounds(inside.removeFromTop(20));
        juce::Rectangle<int> row = inside.removeFromTop(30);
        for (auto &button : routing) { button->setBounds(row.removeFromLeft(110)); row.removeFromLeft(8); }
        inside.removeFromTop(24);
        pitchHeading.setBounds(inside.removeFromTop(20));
        juce::Rectangle<int> wheels = inside.removeFromTop(52);
        for (size_t i = 0; i < steppers.size(); ++i) {
            juce::Rectangle<int> cell = wheels.removeFromLeft(140);
            captions[i]->setBounds(cell.removeFromBottom(16));
            steppers[i]->setBounds(cell.removeFromTop(26));
            wheels.removeFromLeft(12);
        }
    }

private:
    S1PluginEditor &editor;
    const s1ui::Style &style;
    juce::Label heading, pitchHeading;
    std::vector<std::unique_ptr<juce::TextButton>> routing;
    std::vector<std::unique_ptr<s1ui::Stepper>> steppers;
    std::vector<std::unique_ptr<juce::Label>> captions;
};

void S1PluginEditor::showWheels(bool show) {
    if (!show) { panel.reset(); return; }
    const juce::Component::SafePointer<S1PluginEditor> safe(this);
    panel = std::make_unique<Panel>(*style, "Wheels", std::make_unique<WheelsBody>(*this, *style),
                                    [safe] { juce::MessageManager::callAsync([safe] { if (safe != nullptr) { safe->panel.reset(); } }); });
    panel->setBounds(stage->getLocalBounds());
    stage->addAndMakeVisible(*panel);
    panel->toFront(false);
}

bool S1PluginEditor::isShowingWheels() const {
    return panel != nullptr && dynamic_cast<WheelsBody *>(panel->body()) != nullptr;
}

void S1PluginEditor::showSettings(bool show) {
    if (!show) { panel.reset(); return; }
    juce::Component::SafePointer<S1PluginEditor> safe(this);
    panel = std::make_unique<Panel>(*style, "Settings", std::make_unique<SettingsBody>(*this, *style),
                                    [safe] { juce::MessageManager::callAsync([safe] { if (safe != nullptr) { safe->panel.reset(); } }); });
    panel->setBounds(stage->getLocalBounds());
    stage->addAndMakeVisible(*panel);
    panel->toFront(false);
}

bool S1PluginEditor::isShowingSettings() const {
    return panel != nullptr && dynamic_cast<SettingsBody *>(panel->body()) != nullptr;
}

void S1PluginEditor::showTunings(bool show) {
    if (!show) { tuningsPanel.reset(); refreshLiveState(); return; }
    if (tuningsPanel != nullptr) { return; }
    const s1ui::ParameterLookup lookup = [this](S1Parameter parameter) -> S1HostParameter & { return plugin.hostParameter(parameter); };
    tuningsPanel = std::make_unique<s1ui::TuningsPanel>(plugin.tuningLibrary(), *style, lookup);
    tuningsPanel->onTuningChanged = [this] { plugin.retune(); refreshLiveState(); };
    tuningsPanel->onSay = [this](const juce::String &message) { say(message); };
    juce::Component::SafePointer<S1PluginEditor> safe(this);          // MSVC: see showPresets
    tuningsPanel->onClose = [safe] {
        juce::MessageManager::callAsync([safe] { if (safe != nullptr) { safe->showTunings(false); } });
    };
    tuningsPanel->setBounds(juce::Rectangle<int>(s1ui::TuningsPanel::kWidth, s1ui::TuningsPanel::kHeight).withCentre(stage->getLocalBounds().getCentre()));
    stage->addAndMakeVisible(*tuningsPanel);
    tuningsPanel->toFront(true);
    refreshLiveState();
}

void S1PluginEditor::say(const juce::String &message) {
    if (status == nullptr) { return; }
    status->setText(message, juce::dontSendNotification);
    ticksOfMessage = 120;   // four seconds
}

juce::String S1PluginEditor::statusMessage() const { return status != nullptr ? status->getText() : juce::String(); }

void S1PluginEditor::showAllParameters(bool show) {
    if (!show) { panel.reset(); return; }
    auto list = std::make_unique<juce::GenericAudioProcessorEditor>(plugin);
    juce::Component::SafePointer<S1PluginEditor> safe(this);          // MSVC: see showPresets
    panel = std::make_unique<Panel>(*style, "Every parameter", std::move(list), [safe] { juce::MessageManager::callAsync([safe] { if (safe != nullptr) { safe->showAllParameters(false); } }); });
    panel->setBounds(stage->getLocalBounds());
    stage->addAndMakeVisible(*panel);
    panel->toFront(false);
}

bool S1PluginEditor::isShowingAllParameters() const { return allParametersList() != nullptr; }

juce::Component *S1PluginEditor::allParametersList() const {
    return panel != nullptr ? dynamic_cast<juce::GenericAudioProcessorEditor *>(panel->body()) : nullptr;
}

void S1PluginEditor::showAbout() {
    auto words = std::make_unique<juce::Label>();
    words->setJustificationType(juce::Justification::topLeft);
    words->setFont(style->font(15.0f));
    words->setColour(juce::Label::textColourId, style->colour("label"));
    words->setText(juce::String("Arcade Ruins ") + JucePlugin_VersionString
                       + "\n\nAn unofficial port of AudioKit Synth One, under the MIT licence. Not affiliated with AudioKit."
                         "\n\nBuilt with JUCE. The licences of everything inside are in NOTICE.md.",
                   juce::dontSendNotification);
    juce::Component::SafePointer<S1PluginEditor> safe(this);          // MSVC: see showPresets
    panel = std::make_unique<Panel>(*style, "About Arcade Ruins", std::move(words), [safe] { juce::MessageManager::callAsync([safe] { if (safe != nullptr) { safe->panel.reset(); } }); });
    panel->setBounds(stage->getLocalBounds());
    stage->addAndMakeVisible(*panel);
    panel->toFront(false);
}

// MARK: - For tests

std::vector<s1ui::ParameterControl *> S1PluginEditor::parameterControls() {
    std::vector<s1ui::ParameterControl *> found;
    std::vector<juce::Component *> queue { this };
    while (!queue.empty()) {
        juce::Component *component = queue.back();
        queue.pop_back();
        if (auto *control = dynamic_cast<s1ui::ParameterControl *>(component)) { found.push_back(control); }
        for (juce::Component *child : component->getChildren()) { queue.push_back(child); }
    }
    return found;
}

std::vector<S1Parameter> S1PluginEditor::parametersWithAControl() {
    std::vector<bool> has(size_t(S1Parameter::S1ParameterCount), false);
    for (s1ui::ParameterControl *control : parameterControls()) { has[size_t(control->parameter().description().address)] = true; }
    // The plots and pads are in the tree too; what they show is the specification's word
    std::vector<juce::Component *> queue { this };
    while (!queue.empty()) {
        juce::Component *component = queue.back();
        queue.pop_back();
        if (dynamic_cast<s1ui::XYPad *>(component) != nullptr || dynamic_cast<s1ui::EnvelopeView *>(component) != nullptr) {
            for (const s1plugin::LayoutDisplay &display : skin().displays) {
                if (text(display.id) != component->getComponentID()) { continue; }
                for (const auto &entry : display.parameters) { has[size_t(entry.second)] = true; }
            }
        }
        for (juce::Component *child : component->getChildren()) { queue.push_back(child); }
    }
    std::vector<S1Parameter> parameters;
    for (size_t i = 0; i < has.size(); ++i) { if (has[i]) { parameters.push_back(S1Parameter(int(i))); } }
    return parameters;
}

bool S1PluginEditor::stepItem(const juce::String &itemID, int direction) {
    for (ItemButton *item : itemButtons) {
        if (item->getComponentID() != itemID || !item->onStep) { continue; }
        item->onStep(direction);
        return true;
    }
    return false;
}

bool S1PluginEditor::pressItem(const juce::String &itemID) {
    for (ItemButton *item : itemButtons) {
        if (item->getComponentID() == itemID) { item->press(); return true; }
    }
    // The preset name is not a button, it is the way into the browser (X3-4).
    if (presetField != nullptr && presetField->getComponentID() == itemID) { presetField->press(); return true; }
    return false;
}
