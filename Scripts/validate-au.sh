#!/bin/bash
# Install the app to /Applications (required for the system to register the
# embedded AUv3), launch it once, then run auval.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="DerivedData/Build/Products/Debug-maccatalyst/ArcadeRuins.app"
[ -d "$APP" ] || { echo "Build first: Scripts/build.sh"; exit 1; }

# ADR-038: never install a plugin signed by `xcodebuild test`. For the test runner, Xcode adds
# entitlements to it, including read access to `/`, so the plugin reads the shared preset folder
# its real sandbox forbids. Installs made after a test run shipped that build, and hid a plugin
# that loaded no presets and crashed on ▶. A plain `xcodebuild build` that finds nothing to
# compile does not re-sign it, so check the signature rather than the order of commands.
PLUGIN_ENTITLEMENTS=$(codesign -d --entitlements - --xml "$APP/Contents/PlugIns/ArcadeRuinsAU.appex" 2>/dev/null || true)
if grep -q "testmanagerd" <<<"$PLUGIN_ENTITLEMENTS"; then
    echo "✋ The plugin in $APP is signed for testing: Xcode gave it test-runner entitlements," >&2
    echo "   including read access to /. Installed, it would not behave like the real plugin." >&2
    echo "   Change a source file or clean the product, build with 'xcodebuild ... build', then install." >&2
    exit 1
fi

# ADR-041: the plugin saves presets through the App Group, which only a build signed by the
# owner's team carries. An ad-hoc build installs and plays, but its plugin cannot save.
for BUNDLE in "$APP" "$APP/Contents/PlugIns/ArcadeRuinsAU.appex"; do
    SIGNATURE=$(codesign -dv "$BUNDLE" 2>&1 || true)
    BUNDLE_ENTITLEMENTS=$(codesign -d --entitlements - --xml "$BUNDLE" 2>/dev/null || true)
    if ! grep -q "TeamIdentifier=8RSH7U3222" <<<"$SIGNATURE" \
       || ! grep -q "8RSH7U3222.com.badpackets303.ArcadeRuins" <<<"$BUNDLE_ENTITLEMENTS"; then
        echo "✋ $BUNDLE is not signed by team 8RSH7U3222 with the App Group." >&2
        echo "   Build it signed: xcodebuild ... build -allowProvisioningUpdates -allowProvisioningDeviceRegistration" >&2
        exit 1
    fi
done

# A running host keeps the *old* extension. macOS registers the AUv3 from the app in
# /Applications, but a host that is already running has the previous build loaded and
# will not rescan — and a stale extension that crashed on load presents as **silence**,
# not as an error. That cost a session's false alarm on 2026-09-09: the plugin was
# fixed, reinstalled, and still silent, because Logic had been open throughout.
for host in "Logic Pro" "GarageBand" "Live" "Reaper" "Bitwig Studio"; do
    if pgrep -x "$host" >/dev/null 2>&1 || pgrep -f "/$host.app/" >/dev/null 2>&1; then
        echo "⚠️  $host is running. It is holding the PREVIOUS build of the plugin." >&2
        echo "   Quit and relaunch it, or you will be testing the old extension." >&2
    fi
done

osascript -e 'quit app "ArcadeRuins"' 2>/dev/null || true
sleep 1
rm -rf /Applications/ArcadeRuins.app
cp -R "$APP" /Applications/
open -a /Applications/ArcadeRuins.app

# Retry `auval -v` directly rather than polling `auval -a` first.
#
# `auval -a` scans every audio unit on the system, and on 2026-09-08 it wedged
# for 40 minutes with no output — the same environment where a plain
# AVAudioEngine.outputNode blocked for 90 seconds (ADR-015). `auval -v` on one
# component does not do the scan. Each attempt is bounded, so a hang here fails
# the check instead of hanging the session.
attempt_validate() {
    ( auval -v aumu ruin BP03 ) & local pid=$!
    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge 120 ]; then
            kill -9 "$pid" 2>/dev/null || true
            echo "auval did not finish within 120s — killed" >&2
            return 2
        fi
        sleep 2
        waited=$((waited + 2))
    done
    wait "$pid"
}

status=1
for attempt in 1 2 3 4 5 6; do
    sleep 5
    # `status=$?` after a plain `if … fi` reads the if's own status, 0, so every failure used to
    # exit 0 (found 2026-09-11, ADR-041). Take the status in the else branch.
    if attempt_validate; then status=0; break; else status=$?; fi
    [ "$status" -eq 2 ] && break     # a hang will not fix itself; do not retry
    echo "auval attempt $attempt failed, retrying..." >&2
done

osascript -e 'quit app "ArcadeRuins"' 2>/dev/null || true
exit "$status"
