#!/bin/bash
# Regenerate the project and build. Pass a scheme name; defaults to SynthOne.
#
# ADR-041: the app and the plugin are signed by team 8RSH7U3222 so they can share an App
# Group. The two flags let automatic signing register their app IDs, the group and this Mac
# with the team, using the account Xcode is signed in to. Tests do not need either: see
# CLAUDE.md for the unsigned test command.
set -euo pipefail
cd "$(dirname "$0")/.."
SCHEME="${1:-SynthOne}"
xcodegen generate
xcodebuild -project SynthOne.xcodeproj -scheme "$SCHEME" \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath ./DerivedData \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    "${2:-build}"
