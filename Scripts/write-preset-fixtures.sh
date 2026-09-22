#!/bin/bash
# Regenerates the engine's fixture of what the Swift preset code does with every factory preset (X1-5, ADR-069):
#   Tests/Engine/Fixtures/factory-presets.txt   decoded fields and the 150 values after apply, 695 presets
# Run after editing Preset.swift, Preset+Synth.swift or a factory bank. The check-mode test
# (PresetFixtureTests, in the normal suite) fails until this has been run.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_RUNNER_SYNTHONE_WRITE_PRESET_FIXTURES=1 xcodebuild \
    -project SynthOne.xcodeproj -scheme SynthOne \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath /tmp/SynthOneTestDD CODE_SIGNING_ALLOWED=NO \
    -only-testing:SynthOneTests/PresetFixtureTests \
    test | grep -E "SYNTHONE_WRITE_PRESET_FIXTURES|Test Case|error:"
git status --short Tests/Engine/Fixtures || true
