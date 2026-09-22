#!/bin/bash
# Writes, from the Mac product's own desktop layout built at its design size under each skin:
#   Sources/S1Plugin/Layout/layout-spec.json   sections, controls and their parameters, fonts, palettes
# which the JUCE interface is drawn from (X3-1, ADR-083). Run after any change to
# Sources/SynthOneCore/Desktop. The check-mode test (LayoutSpecFixtureTests, in the normal suite)
# fails until this has been run; Tests/Plugin/PluginLayoutSpecTests reads the file on every OS.
set -euo pipefail
cd "$(dirname "$0")/.."
unset SDKROOT
xcodegen generate > /dev/null
TEST_RUNNER_SYNTHONE_WRITE_LAYOUT_SPEC=1 xcodebuild \
    -project SynthOne.xcodeproj -scheme SynthOne \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath /tmp/SynthOneTestDD CODE_SIGNING_ALLOWED=NO \
    -only-testing:SynthOneTests/LayoutSpecFixtureTests \
    test | grep -E "SYNTHONE_WRITE_LAYOUT_SPEC|Test Case|error:|Executed"
git status --short Sources/S1Plugin/Layout || true
