#!/bin/bash
# Regenerate the P2-4 golden WAVs in Tests/Goldens/.
#
# ONLY run this for a change you intend to hear. Listen to the result before
# committing it — the goldens are the record of what Synth One sounds like.
#
# The TEST_RUNNER_ prefix is required: xcodebuild does not pass the shell
# environment to the test runner, and without it the variable never arrives.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_RUNNER_SYNTHONE_WRITE_GOLDENS=1 xcodebuild \
    -project SynthOne.xcodeproj -scheme SynthOne \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath ./DerivedData \
    -only-testing:SynthOneTests/GoldenRenderTests/testPresetsMatchTheirGoldens \
    test | grep -E "SYNTHONE_WRITE_GOLDENS|Test Case|error:"
echo
echo "Now listen to them:  open Tests/Goldens"
git -C . status --short Tests/Goldens || true
