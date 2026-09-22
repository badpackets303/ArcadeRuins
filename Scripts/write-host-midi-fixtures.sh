#!/bin/bash
# Regenerates the engine's fixture of what the STANDALONE's Swift MIDI chain plays (X2-4, ADR-075):
#   Tests/Engine/Fixtures/host-midi.txt   7 scripted scenarios, 8 seeded random ones, the white-keys map
# Run after changing the standalone's MIDI chain (Manager+MIDIListener, KeyboardView, SDSustainer)
# or the scenarios in HostMIDIParityTests. The check-mode test in the normal suite fails until then —
# and Tests/Engine/HostMIDITests.cpp holds S1HostMIDI to the new file on three OSes.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_RUNNER_SYNTHONE_WRITE_HOST_MIDI_FIXTURES=1 xcodebuild \
    -project SynthOne.xcodeproj -scheme SynthOne \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath /tmp/SynthOneTestDD CODE_SIGNING_ALLOWED=NO \
    -only-testing:SynthOneTests/HostMIDIParityTests/testTheEngineFixtureIsWhatTheStandalonePlays \
    test | grep -E "SYNTHONE_WRITE_HOST_MIDI_FIXTURES|Test Case|error:"
git status --short Tests/Engine/Fixtures || true
