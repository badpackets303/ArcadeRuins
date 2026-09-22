//
//  S1LinkedLayoutSpec.cpp
//  Arcade Ruins
//
//  X3-1 (ADR-083). See the header.
//
#include "S1LinkedLayoutSpec.h"

#include "S1LayoutData.h"

std::string S1LinkedLayoutSpecText() {
    return std::string(S1LayoutData::layoutspec_json, size_t(S1LayoutData::layoutspec_jsonSize));
}

const s1plugin::LayoutSpec &S1LinkedLayoutSpec() {
    static const s1plugin::LayoutSpec spec = s1plugin::LayoutSpec::parse(S1LinkedLayoutSpecText()).value_or(s1plugin::LayoutSpec {});
    return spec;
}
