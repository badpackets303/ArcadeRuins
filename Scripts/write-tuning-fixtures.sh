#!/bin/bash
# Regenerates the engine's copies of the Swift tuning code's output (X1-4, ADR-068):
#   Tests/Engine/Fixtures/factory-tunings.txt      every factory tuning's 128 frequencies, and Scala cases
#   Sources/S1Engine/Tunings/S1FactoryTunings.cpp  the factory list as C++ data
# Run after editing Tunings+DefaultTunings.swift or the tuning-table code. The check-mode test
# (TuningFixtureTests, in the normal suite) fails until this has been run.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_RUNNER_SYNTHONE_WRITE_TUNING_FIXTURES=1 xcodebuild \
    -project SynthOne.xcodeproj -scheme SynthOne \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath /tmp/SynthOneTestDD CODE_SIGNING_ALLOWED=NO \
    -only-testing:SynthOneTests/TuningFixtureTests \
    test | grep -E "SYNTHONE_WRITE_TUNING_FIXTURES|Test Case|error:"
git status --short Tests/Engine/Fixtures Sources/S1Engine/Tunings || true
