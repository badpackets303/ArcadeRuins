#!/bin/bash
# Builds, signs with Developer ID, notarises and packages Arcade Ruins for a GitHub release.
#
# One download holds both products: the AUv3 plugin is embedded in the app, and macOS registers it
# once the app is in /Applications and has been opened.
#
# Needs, once per machine (the owner's steps; nothing here handles a password):
#   - a "Developer ID Application" certificate for team 8RSH7U3222 (Xcode → Settings → Accounts →
#     Manage Certificates → + → Developer ID Application)
#   - notarisation credentials in the keychain:
#       xcrun notarytool store-credentials "ArcadeRuins" --apple-id <Apple ID> --team-id 8RSH7U3222
#
# Output: DerivedDataRelease/release/ArcadeRuins-<version>-macOS.zip and its SHA-256.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=8RSH7U3222
GROUP=8RSH7U3222.com.badpackets303.ArcadeRuins
PROFILE=${NOTARY_PROFILE:-ArcadeRuins}
VERSION=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
OUT=DerivedDataRelease/release
ARCHIVE="$OUT/ArcadeRuins.xcarchive"
EXPORT="$OUT/export"
ZIP="$OUT/ArcadeRuins-$VERSION-macOS.zip"

# --- Preflight: fail before a long build, not after it.
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application:.*($TEAM)"; then
    echo "✋ No Developer ID Application certificate for team $TEAM in the keychain." >&2
    echo "   Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application" >&2
    exit 1
fi
# NOTARISE=0 builds, exports and checks the signature, then stops: for trying the signing before the
# notarisation credentials exist.
NOTARISE=${NOTARISE:-1}
if [ "$NOTARISE" != 0 ] && ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "✋ No notarisation credentials stored as \"$PROFILE\"." >&2
    echo "   xcrun notarytool store-credentials \"$PROFILE\" --apple-id <Apple ID> --team-id $TEAM" >&2
    exit 1
fi

# RESUME_ID picks up a submission already at Apple: the export on disk is the thing it was made
# from, so rebuilding it would change the hashes the ticket is for.
if [ -z "${RESUME_ID:-}" ]; then
    rm -rf "$OUT"
    mkdir -p "$OUT"
fi

# --- Archive (Release) and export for Developer ID.
if [ -z "${RESUME_ID:-}" ]; then
xcodegen generate
xcodebuild -project SynthOne.xcodeproj -scheme SynthOne -configuration Release \
    -destination 'generic/platform=macOS,variant=Mac Catalyst' \
    -archivePath "$ARCHIVE" -allowProvisioningUpdates archive

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
    <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates
fi

APP="$EXPORT/ArcadeRuins.app"
PLUGIN="$APP/Contents/PlugIns/ArcadeRuinsAU.appex"

# --- Check the signature before sending it to Apple.
for BUNDLE in "$APP" "$PLUGIN"; do
    SIGNATURE=$(codesign -dvvv "$BUNDLE" 2>&1)
    ENTITLEMENTS=$(codesign -d --entitlements - --xml "$BUNDLE" 2>/dev/null)
    grep -q "Authority=Developer ID Application:" <<<"$SIGNATURE" || { echo "✋ $BUNDLE is not signed with Developer ID" >&2; exit 1; }
    grep -q "flags=.*runtime" <<<"$SIGNATURE" || { echo "✋ $BUNDLE lacks the hardened runtime, which notarisation requires" >&2; exit 1; }
    grep -q "$GROUP" <<<"$ENTITLEMENTS" || { echo "✋ $BUNDLE lacks the App Group $GROUP" >&2; exit 1; }
    if grep -q "get-task-allow" <<<"$ENTITLEMENTS"; then
        echo "✋ $BUNDLE carries get-task-allow, a debug entitlement notarisation rejects" >&2; exit 1
    fi
done
codesign --verify --deep --strict --verbose=2 "$APP"

if [ "$NOTARISE" = 0 ]; then
    echo "Signed and checked, not notarised (NOTARISE=0): $APP"
    exit 0
fi

# --- Notarise, staple, and confirm Gatekeeper accepts it.
#
# **Not `--wait`.** Apple's notary service takes hours, not the minutes `--wait` implies (ADR-053),
# and on 2026-09-14 a single status poll timed out at the network layer after an hour — `--wait`
# treats that as fatal, so the run was abandoned with the submission still queued and nothing
# stapled. The submission is server-side and outlives this script, so: take the id, write it down,
# and poll it here, forgiving a failed poll. `RESUME_ID=<id>` picks a submission up later without
# building or uploading anything again.
SUBMISSION_FILE="$OUT/submission-id"
if [ -n "${RESUME_ID:-}" ]; then
    SUBMISSION="$RESUME_ID"
    echo "Resuming submission $SUBMISSION"
else
    ditto -c -k --keepParent "$APP" "$OUT/notarise.zip"
    SUBMISSION=$(xcrun notarytool submit "$OUT/notarise.zip" --keychain-profile "$PROFILE" \
        --no-wait --output-format json | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
    echo "$SUBMISSION" > "$SUBMISSION_FILE"
    echo "Submitted: $SUBMISSION (also in $SUBMISSION_FILE)"
fi

# Poll for up to four hours. A failed poll is a network blip, not a verdict.
DEADLINE=$(( $(date +%s) + 4 * 60 * 60 ))
STATUS=""
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    INFO=$(xcrun notarytool info "$SUBMISSION" --keychain-profile "$PROFILE" --output-format json 2>/dev/null || true)
    STATUS=$(/usr/bin/python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("status", ""))
except Exception: print("")' <<<"$INFO")
    case "$STATUS" in
        Accepted) break ;;
        Invalid|Rejected)
            echo "✋ Notarisation returned $STATUS. The log:" >&2
            xcrun notarytool log "$SUBMISSION" --keychain-profile "$PROFILE" >&2 || true
            exit 1 ;;
    esac
    sleep 60
done
if [ "$STATUS" != Accepted ]; then
    echo "✋ Still $([ -n "$STATUS" ] && echo "$STATUS" || echo unknown) after four hours. Nothing is lost:" >&2
    echo "   the submission continues at Apple. Check it with" >&2
    echo "     xcrun notarytool info $SUBMISSION --keychain-profile $PROFILE" >&2
    echo "   and finish with  RESUME_ID=$SUBMISSION Scripts/release.sh" >&2
    exit 1
fi

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"

# --- The download. ditto, not zip: the framework's symlinks must survive (docs/04-build-and-test.md).
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Ready: $ZIP"
