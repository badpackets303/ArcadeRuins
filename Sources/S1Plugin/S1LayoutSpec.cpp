//
//  S1LayoutSpec.cpp
//  Arcade Ruins
//
//  X3-1 (ADR-083). See the header. The reader is strict: a specification with anything missing
//  or mistyped is refused whole, with the path of the first fault — a half-read layout would be
//  an interface with controls silently absent.
//
#include "S1LayoutSpec.hpp"

#include <cstdlib>
#include <stdexcept>
#include <tuple>
#include <utility>

#include "../S1Engine/third_party/nlohmann/json.hpp"
#include "S1ParameterCatalog.hpp"

namespace s1plugin {
namespace {

using Json = nlohmann::json;

struct Fault : std::runtime_error {
    using std::runtime_error::runtime_error;
};

const Json &field(const Json &object, const std::string &where, const char *name) {
    if (!object.is_object()) { throw Fault(where + " is not an object"); }
    const auto found = object.find(name);
    if (found == object.end()) { throw Fault(where + "." + name + " is missing"); }
    return *found;
}

std::string text(const Json &object, const std::string &where, const char *name) {
    const Json &value = field(object, where, name);
    if (!value.is_string()) { throw Fault(where + "." + name + " is not text"); }
    return value.get<std::string>();
}

/// Text, or nothing for null.
std::string textOrNone(const Json &object, const std::string &where, const char *name) {
    const Json &value = field(object, where, name);
    if (value.is_null()) { return {}; }
    if (!value.is_string()) { throw Fault(where + "." + name + " is not text"); }
    return value.get<std::string>();
}

float number(const Json &value, const std::string &where) {
    if (!value.is_number()) { throw Fault(where + " is not a number"); }
    return value.get<float>();
}

float number(const Json &object, const std::string &where, const char *name) {
    return number(field(object, where, name), where + "." + name);
}

bool flag(const Json &object, const std::string &where, const char *name) {
    const Json &value = field(object, where, name);
    if (!value.is_boolean()) { throw Fault(where + "." + name + " is not true or false"); }
    return value.get<bool>();
}

const Json &list(const Json &object, const std::string &where, const char *name) {
    const Json &value = field(object, where, name);
    if (!value.is_array()) { throw Fault(where + "." + name + " is not a list"); }
    return value;
}

LayoutRect rect(const Json &value, const std::string &where) {
    if (!value.is_array() || value.size() != 4) { throw Fault(where + " is not [x, y, width, height]"); }
    LayoutRect r;
    r.x = number(value[0], where);
    r.y = number(value[1], where);
    r.width = number(value[2], where);
    r.height = number(value[3], where);
    if (r.width < 0 || r.height < 0) { throw Fault(where + " has a negative size"); }
    return r;
}

LayoutRect rect(const Json &object, const std::string &where, const char *name) {
    return rect(field(object, where, name), where + "." + name);
}

std::optional<LayoutRect> rectIfPresent(const Json &object, const std::string &where, const char *name) {
    const auto found = object.find(name);
    if (found == object.end() || found->is_null()) { return std::nullopt; }
    return rect(*found, where + "." + name);
}

std::pair<float, float> pair(const Json &object, const std::string &where, const char *name) {
    const Json &value = field(object, where, name);
    if (!value.is_array() || value.size() != 2) { throw Fault(where + "." + name + " is not two numbers"); }
    return { number(value[0], where + "." + name), number(value[1], where + "." + name) };
}

/// "#rrggbbaa"
LayoutColour colour(const Json &value, const std::string &where) {
    if (!value.is_string()) { throw Fault(where + " is not a colour"); }
    const std::string hex = value.get<std::string>();
    if (hex.size() != 9 || hex[0] != '#' || hex.find_first_not_of("0123456789abcdefABCDEF", 1) != std::string::npos) {
        throw Fault(where + " is not #rrggbbaa: " + hex);
    }
    auto byte = [&](size_t at) { return std::uint8_t(std::strtoul(hex.substr(at, 2).c_str(), nullptr, 16)); };
    return { byte(1), byte(3), byte(5), byte(7) };
}

std::optional<LayoutColour> colourOrNone(const Json &object, const std::string &where, const char *name) {
    const Json &value = field(object, where, name);
    if (value.is_null()) { return std::nullopt; }
    return colour(value, where + "." + name);
}

S1Parameter parameterNamed(const std::string &name, const std::string &where) {
    for (int address = 0; address < int(S1Parameter::S1ParameterCount); ++address) {
        if (name == parameterID(address)) { return S1Parameter(address); }
    }
    throw Fault(where + ": \"" + name + "\" is not an S1Parameter");
}

LayoutControlKind kindNamed(const std::string &name) {
    for (int i = 0; i <= int(LayoutControlKind::other); ++i) {
        if (name == layoutControlKindName(LayoutControlKind(i))) { return LayoutControlKind(i); }
    }
    return LayoutControlKind::other;
}

LayoutTemplate readTemplate(const Json &json, const std::string &where) {
    LayoutTemplate painting;
    painting.image = text(json, where, "image");
    std::tie(painting.width, painting.height) = pair(json, where, "size");
    if (painting.width <= 0 || painting.height <= 0) { throw Fault(where + ".size is empty"); }
    const Json &sections = field(json, where, "sections");
    if (!sections.is_object()) { throw Fault(where + ".sections is not an object"); }
    for (const auto &[key, value] : sections.items()) { painting.sections[key] = rect(value, where + ".sections." + key); }
    for (const char *place : { "presetField", "previous", "next", "wordmark", "scope", "save", "record", "panic",
                               "settings", "presets", "playBar", "statusBar" }) {
        painting.places[place] = rect(json, where, place);
    }
    std::tie(painting.diceX, painting.diceY) = pair(json, where, "dice");
    if (const Json &stick = field(json, where, "joystick"); !stick.is_null()) {
        LayoutJoystick joystick;
        joystick.ballImage = text(stick, where + ".joystick", "ballImage");
        joystick.rodImage = text(stick, where + ".joystick", "rodImage");
        joystick.ballBox = rect(stick, where + ".joystick", "ballBox");
        joystick.rodBox = rect(stick, where + ".joystick", "rodBox");
        joystick.reach = rect(stick, where + ".joystick", "reach");
        std::tie(joystick.pivotX, joystick.pivotY) = pair(stick, where + ".joystick", "pivot");
        painting.joystick = joystick;
    }
    // X3-9 (ADR-091): the red buttons, the zones they darken and the grey painting.
    if (const Json &power = field(json, where, "power"); !power.is_null()) {
        LayoutPower cabinet;
        const std::string inside = where + ".power";
        cabinet.darkImage = text(power, inside, "darkImage");
        cabinet.off = rect(power, inside, "off");
        cabinet.on = rect(power, inside, "on");
        cabinet.frameReach = number(power, inside, "frameReach");
        const Json &zones = field(power, inside, "zones");
        if (zones.is_object()) {
            for (const auto &entry : zones.items()) { cabinet.zones[entry.key()] = rect(entry.value(), inside + ".zones." + entry.key()); }
        }
        painting.power = cabinet;
    }
    return painting;
}

LayoutSkin readSkin(const std::string &key, const Json &json, const std::string &where) {
    LayoutSkin skin;
    skin.key = key;
    skin.title = text(json, where, "title");
    skin.isDefault = flag(json, where, "isDefault");
    skin.glow = number(json, where, "glow");
    skin.frameAccent = colourOrNone(json, where, "frameAccent");
    skin.sectionGlow = colourOrNone(json, where, "sectionGlow");

    const Json &palette = field(json, where, "palette");
    if (!palette.is_object()) { throw Fault(where + ".palette is not an object"); }
    for (const auto &[name, value] : palette.items()) {
        const std::string at = where + ".palette." + name;
        if (value.is_array()) {
            if (name != "knobCap") { throw Fault(at + " is a list"); }
            for (const Json &stop : value) { skin.knobCap.push_back(colour(stop, at)); }
        } else if (!value.is_null()) {   // an optional colour the skin leaves to the accent
            skin.palette[name] = colour(value, at);
        }
    }
    if (skin.knobCap.size() != 4) { throw Fault(where + ".palette.knobCap is not four colours"); }

    const Json &dress = field(json, where, "dress");
    if (!dress.is_object()) { throw Fault(where + ".dress is not an object"); }
    for (const auto &[name, value] : dress.items()) {
        if (value.is_boolean()) { skin.dress[name] = value.get<bool>() ? 1.0f : 0.0f; }
        else if (value.is_number()) { skin.dress[name] = value.get<float>(); }
        else if (value.is_array() && value.size() == 2) {
            skin.dress[name + ".width"] = number(value[0], where + ".dress." + name);
            skin.dress[name + ".height"] = number(value[1], where + ".dress." + name);
        } else { throw Fault(where + ".dress." + name + " is neither a number, a switch nor a size"); }
    }

    if (const Json &painting = field(json, where, "template"); !painting.is_null()) {
        skin.painting = readTemplate(painting, where + ".template");
    }
    if (const auto rows = json.find("rowHeights"); rows != json.end()) {
        if (!rows->is_array()) { throw Fault(where + ".rowHeights is not a list"); }
        for (const Json &row : *rows) { skin.rowHeights.push_back(number(row, where + ".rowHeights")); }
    }
    for (const Json &size : list(json, where, "knobSizes")) { skin.knobSizes.push_back(number(size, where + ".knobSizes")); }

    const Json &regions = field(json, where, "regions");
    if (!regions.is_object()) { throw Fault(where + ".regions is not an object"); }
    for (const auto &[name, value] : regions.items()) {
        if (!value.is_null()) { skin.regions[name] = rect(value, where + ".regions." + name); }
    }

    for (const Json &entry : list(json, where, "sections")) {
        LayoutSection section;
        section.key = text(entry, where + ".sections[]", "key");
        const std::string at = where + ".sections." + section.key;
        section.title = text(entry, at, "title");
        section.frame = rect(entry, at, "frame");
        section.header = rect(entry, at, "header");
        section.body = rect(entry, at, "body");
        section.accent = colourOrNone(entry, at, "accent");
        skin.sections.push_back(std::move(section));
    }

    for (const Json &entry : list(json, where, "controls")) {
        LayoutControl control;
        control.id = text(entry, where + ".controls[]", "id");
        const std::string at = where + ".controls." + control.id;
        control.parameterID = text(entry, at, "parameter");
        control.parameter = parameterNamed(control.parameterID, at);
        control.kind = kindNamed(text(entry, at, "kind"));
        control.macClass = text(entry, at, "class");
        control.section = textOrNone(entry, at, "section");
        control.frame = rect(entry, at, "frame");
        if (const auto dependent = entry.find("dependent"); dependent != entry.end()) { control.dependent = flag(entry, at, "dependent"); }
        if (const auto title = entry.find("title"); title != entry.end()) { control.title = text(entry, at, "title"); }
        control.titleFrame = rectIfPresent(entry, at, "titleFrame");
        control.valueFrame = rectIfPresent(entry, at, "valueFrame");
        if (const auto choices = entry.find("choices"); choices != entry.end()) {
            for (const Json &choice : list(entry, at, "choices")) {
                if (!choice.is_string()) { throw Fault(at + ".choices holds something that is not text"); }
                control.choices.push_back(choice.get<std::string>());
            }
        }
        for (const LayoutControl &other : skin.controls) {
            if (other.id == control.id) { throw Fault(at + " appears twice"); }
        }
        skin.controls.push_back(std::move(control));
    }

    for (const Json &entry : list(json, where, "displays")) {
        LayoutDisplay display;
        display.id = text(entry, where + ".displays[]", "id");
        const std::string at = where + ".displays." + display.id;
        display.kind = text(entry, at, "kind");
        display.section = textOrNone(entry, at, "section");
        display.frame = rect(entry, at, "frame");
        if (entry.contains("curve")) { display.curve = colourOrNone(entry, at, "curve"); }
        if (entry.contains("fill")) { display.fill = colourOrNone(entry, at, "fill"); }
        const Json &parameters = field(entry, at, "parameters");
        if (!parameters.is_object()) { throw Fault(at + ".parameters is not an object"); }
        for (const auto &[role, name] : parameters.items()) {
            if (!name.is_string()) { throw Fault(at + ".parameters." + role + " is not text"); }
            display.parameters[role] = parameterNamed(name.get<std::string>(), at + ".parameters." + role);
        }
        skin.displays.push_back(std::move(display));
    }

    for (const Json &entry : list(json, where, "items")) {
        LayoutItem item;
        item.id = text(entry, where + ".items[]", "id");
        const std::string at = where + ".items." + item.id;
        item.kind = text(entry, at, "kind");
        item.region = textOrNone(entry, at, "region");
        item.frame = rect(entry, at, "frame");
        if (const auto title = entry.find("title"); title != entry.end()) { item.title = text(entry, at, "title"); }
        skin.items.push_back(std::move(item));
    }

    for (const Json &entry : list(json, where, "labels")) {
        LayoutLabel label;
        const std::string at = where + ".labels[]";
        label.text = text(entry, at, "text");
        label.region = textOrNone(entry, at, "region");
        label.frame = rect(entry, at, "frame");
        label.font = text(entry, at, "font");
        label.size = number(entry, at, "size");
        label.colour = colour(field(entry, at, "colour"), at + ".colour");
        label.align = text(entry, at, "align");
        skin.labels.push_back(std::move(label));
    }
    return skin;
}

LayoutSpec readSpec(const Json &root) {
    LayoutSpec spec;
    spec.version = int(number(root, "spec", "version"));
    if (spec.version != LayoutSpec::kVersion) { throw Fault("spec.version is " + std::to_string(spec.version) + ", not " + std::to_string(LayoutSpec::kVersion)); }
    std::tie(spec.designWidth, spec.designHeight) = pair(root, "spec", "designSize");
    std::tie(spec.minimumWidth, spec.minimumHeight) = pair(root, "spec", "minimumSize");
    if (spec.designWidth <= 0 || spec.designHeight <= 0) { throw Fault("spec.designSize is empty"); }

    const Json &metrics = field(root, "spec", "metrics");
    if (!metrics.is_object()) { throw Fault("spec.metrics is not an object"); }
    for (const auto &[name, value] : metrics.items()) { spec.metrics[name] = number(value, "spec.metrics." + name); }

    const Json &fonts = field(root, "spec", "fonts");
    if (!fonts.is_object()) { throw Fault("spec.fonts is not an object"); }
    for (const auto &[role, value] : fonts.items()) {
        const std::string at = "spec.fonts." + role;
        LayoutFont font;
        font.name = text(value, at, "name");
        font.family = text(value, at, "family");
        font.size = number(value, at, "size");
        font.kern = number(value, at, "kern");
        font.uppercase = flag(value, at, "uppercase");
        spec.fonts[role] = std::move(font);
    }

    const Json &skins = field(root, "spec", "skins");
    if (!skins.is_object() || skins.empty()) { throw Fault("spec.skins is not an object of skins"); }
    for (const auto &[key, value] : skins.items()) { spec.skins.push_back(readSkin(key, value, "spec.skins." + key)); }
    return spec;
}

} // namespace

const char *layoutControlKindName(LayoutControlKind kind) {
    switch (kind) {
    case LayoutControlKind::knob: return "knob";
    case LayoutControlKind::toggle: return "switch";
    case LayoutControlKind::twoWay: return "twoWay";
    case LayoutControlKind::chip: return "chip";
    case LayoutControlKind::wavePicker: return "wavePicker";
    case LayoutControlKind::morphSelector: return "morphSelector";
    case LayoutControlKind::stepper: return "stepper";
    case LayoutControlKind::tempo: return "tempo";
    case LayoutControlKind::direction: return "direction";
    case LayoutControlKind::stepOctave: return "stepOctave";
    case LayoutControlKind::stepFader: return "stepFader";
    case LayoutControlKind::stepOn: return "stepOn";
    case LayoutControlKind::segmented: return "segmented";
    case LayoutControlKind::other: return "other";
    }
    return "other";
}

LayoutRect LayoutTemplate::inWindow(const LayoutRect &painted, float designWidth, float designHeight) const {
    const float sx = designWidth / width, sy = designHeight / height;
    return { painted.x * sx, painted.y * sy, painted.width * sx, painted.height * sy };
}

const LayoutSection *LayoutSkin::section(const std::string &sectionKey) const {
    for (const LayoutSection &s : sections) { if (s.key == sectionKey) { return &s; } }
    return nullptr;
}

const LayoutControl *LayoutSkin::control(const std::string &controlID) const {
    for (const LayoutControl &c : controls) { if (c.id == controlID) { return &c; } }
    return nullptr;
}

LayoutColour LayoutSkin::colour(const std::string &name) const {
    const auto found = palette.find(name);
    return found != palette.end() ? found->second : LayoutColour { 255, 0, 255, 255 };
}

const LayoutSkin *LayoutSpec::skin(const std::string &skinKey) const {
    for (const LayoutSkin &s : skins) { if (s.key == skinKey) { return &s; } }
    return nullptr;
}

const LayoutSkin *LayoutSpec::defaultSkin() const {
    for (const LayoutSkin &s : skins) { if (s.isDefault) { return &s; } }
    return skins.empty() ? nullptr : &skins.front();
}

std::optional<LayoutSpec> LayoutSpec::parse(const std::string &json, std::string *error) {
    const Json root = Json::parse(json, nullptr, false);
    if (root.is_discarded()) {
        if (error != nullptr) { *error = "not JSON"; }
        return std::nullopt;
    }
    try {
        return readSpec(root);
    } catch (const Fault &fault) {
        if (error != nullptr) { *error = fault.what(); }
        return std::nullopt;
    }
}

} // namespace s1plugin
