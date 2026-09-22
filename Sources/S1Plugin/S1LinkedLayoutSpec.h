//
//  S1LinkedLayoutSpec.h
//  Arcade Ruins
//
//  X3-1 (ADR-083): the layout specification as this binary carries it — `Layout/layout-spec.json`,
//  linked in as JUCE binary data like the wavetables and the factory banks, parsed on first use
//  and then fixed. For the editor: nothing calls this while a host scans the plugin.
//
#pragma once

#include <string>

#include "S1LayoutSpec.hpp"

/// The file's text, byte for byte (a test holds it to the repository's).
std::string S1LinkedLayoutSpecText();

/// The parsed specification. A file that does not parse is a build fault, caught by
/// `PluginLayoutSpecTests`; here it would be an empty specification with no skins.
const s1plugin::LayoutSpec &S1LinkedLayoutSpec();
