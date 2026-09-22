#!/bin/bash
# Writes, from the Mac product's own S1FactoryPresets:
#   Tests/Plugin/Fixtures/factory-programs.txt   the 695 factory preset names in the AUv3's order
# which Tests/Plugin/PluginPresetTests holds the JUCE plugin's host programs to (X2-9, ADR-080).
# Run after adding a bank or a preset (only ever at the END: a host stores the numbers). The
# check-mode test (FactoryProgramFixtureTests, in the normal suite) fails until this has been run.
set -euo pipefail
cd "$(dirname "$0")/.."
unset SDKROOT
xcodegen generate > /dev/null
TEST_RUNNER_SYNTHONE_WRITE_FACTORY_PROGRAM_FIXTURES=1 xcodebuild \
    -project SynthOne.xcodeproj -scheme SynthOne \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath /tmp/SynthOneTestDD CODE_SIGNING_ALLOWED=NO \
    -only-testing:SynthOneTests/FactoryProgramFixtureTests \
    test | grep -E "SYNTHONE_WRITE_FACTORY_PROGRAM_FIXTURES|Test Case|error:"
git status --short Tests/Plugin/Fixtures || true
