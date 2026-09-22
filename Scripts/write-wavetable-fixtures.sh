#!/bin/bash
# Regenerates the engine's fixture of the oscillator tables as the Swift loader decodes them (X1-6, ADR-070):
#   Tests/Engine/Fixtures/wavetables.txt   13 band frequencies, and a size + checksum per table, 52 tables
# Run after editing S1Wavetables.swift, AKTable decoding or a table JSON. The check-mode test
# (WavetableFixtureTests, in the normal suite) fails until this has been run.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_RUNNER_SYNTHONE_WRITE_WAVETABLE_FIXTURES=1 xcodebuild \
    -project SynthOne.xcodeproj -scheme SynthOne \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath /tmp/SynthOneTestDD CODE_SIGNING_ALLOWED=NO \
    -only-testing:SynthOneTests/WavetableFixtureTests \
    test | grep -E "SYNTHONE_WRITE_WAVETABLE_FIXTURES|Test Case|error:"
git status --short Tests/Engine/Fixtures || true
