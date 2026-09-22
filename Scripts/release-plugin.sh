#!/bin/bash
# X4-1 / X4-2 (ADR-094): builds, signs with Developer ID, packages and notarises the JUCE products
# for macOS — "Arcade Ruins": the VST3, the AU (aumu/ArRu/BP03) and the standalone app — as ONE
# installer package. The counterpart of Scripts/release.sh, which does the same for the Catalyst
# app ("Arcade Ruins Classic"); the no-wait / poll / resume notarisation flow is that script's
# (ADR-053: Apple's service can take hours, and abandoning a wait loses nothing).
#
# Needs, once per machine (the owner's steps; nothing here handles a password):
#   - "Developer ID Application" AND "Developer ID Installer" certificates for team 8RSH7U3222
#     (Xcode → Settings → Accounts → Manage Certificates → +). The first signs the code, the
#     second the package: a package signed with the Application certificate is rejected.
#   - notarisation credentials in the keychain, as Scripts/release.sh uses:
#       xcrun notarytool store-credentials "ArcadeRuins" --apple-id <Apple ID> --team-id 8RSH7U3222
#
#   Scripts/release-plugin.sh                     # everything
#   NOTARISE=0 Scripts/release-plugin.sh          # build, sign, package, check — and stop
#   ALLOW_UNSIGNED_PKG=1 NOTARISE=0 …             # no Installer certificate yet: an UNSIGNED package,
#                                                 # for looking at what it would install. Never ship it.
#   RESUME_ID=<submission id> …                   # pick up a submission already at Apple
#
# Output: build/release-plugin/release/ArcadeRuins-<version>-macOS.pkg, its SHA-256, uninstall.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=8RSH7U3222
PROFILE=${NOTARY_PROFILE:-ArcadeRuins}
NOTARISE=${NOTARISE:-1}
VERSION=$(awk '/^project\(ArcadeRuins VERSION/ { print $3; exit }' CMakeLists.txt)
BUILD=build/release-plugin
ARTEFACTS="$BUILD/Sources/S1Plugin/ArcadeRuins_artefacts/Release"
OUT="$BUILD/release"
STAGE="$OUT/stage"
PKG="$OUT/ArcadeRuins-$VERSION-macOS.pkg"
MINIMUM_MACOS=11.0                       # the first macOS on Apple Silicon; JUCE 9 asks for 10.15

[ -n "$VERSION" ] || { echo "✋ no version in CMakeLists.txt" >&2; exit 1; }

# --- Preflight: fail before a long build, not after it.
identity() { security find-identity -v | sed -n "s/.*\"\($1: .*($TEAM)\)\".*/\1/p" | head -1; }
APPLICATION=$(identity "Developer ID Application")
INSTALLER=$(identity "Developer ID Installer")
if [ -z "$APPLICATION" ]; then
    echo "✋ No Developer ID Application certificate for team $TEAM in the keychain." >&2
    echo "   Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application" >&2
    exit 1
fi
if [ -z "$INSTALLER" ] && [ "${ALLOW_UNSIGNED_PKG:-0}" != 1 ]; then
    echo "✋ No Developer ID INSTALLER certificate for team $TEAM in the keychain. The code is signed" >&2
    echo "   with the Application certificate; the PACKAGE needs this one." >&2
    echo "   Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Installer" >&2
    echo "   (ALLOW_UNSIGNED_PKG=1 NOTARISE=0 builds an unsigned package to look at. Never ship it.)" >&2
    exit 1
fi
if [ -z "$INSTALLER" ] && [ "$NOTARISE" != 0 ]; then
    echo "✋ An unsigned package cannot be notarised: NOTARISE=0 with ALLOW_UNSIGNED_PKG=1." >&2; exit 1
fi
if [ "$NOTARISE" != 0 ] && ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "✋ No notarisation credentials stored as \"$PROFILE\"." >&2
    echo "   xcrun notarytool store-credentials \"$PROFILE\" --apple-id <Apple ID> --team-id $TEAM" >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    echo "⚠️  the working tree has uncommitted changes: this is not a release build of a commit." >&2
    [ "${ALLOW_DIRTY:-0}" = 1 ] || { echo "   (ALLOW_DIRTY=1 to go on anyway)" >&2; exit 1; }
fi

if [ -z "${RESUME_ID:-}" ]; then
    # --- Build: universal, Release, and every test on the commit being released.
    export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"      # CMake cannot link with the CLT's SDK here (CLAUDE.md)
    cmake -S . -B "$BUILD" -DS1_BUILD_PLUGIN=ON -DCMAKE_BUILD_TYPE=Release \
        "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64" -DCMAKE_OSX_DEPLOYMENT_TARGET=$MINIMUM_MACOS ${CMAKE_ARGS:-} > /dev/null
    cmake --build "$BUILD" --config Release --parallel 10 | tail -1
    echo "— every test, on the binaries being released (the goldens bit-exact on Apple Silicon)"
    (cd "$BUILD" && ctest --output-on-failure | tail -3)

    rm -rf "$OUT"
    mkdir -p "$STAGE/vst3" "$STAGE/au" "$STAGE/app"
    ditto "$ARTEFACTS/VST3/Arcade Ruins.vst3" "$STAGE/vst3/Arcade Ruins.vst3"
    ditto "$ARTEFACTS/AU/Arcade Ruins.component" "$STAGE/au/Arcade Ruins.component"
    ditto "$ARTEFACTS/Standalone/Arcade Ruins.app" "$STAGE/app/Arcade Ruins.app"

    # --- Sign: Developer ID, hardened runtime, a secure timestamp — what notarisation requires.
    # No entitlements: nothing here records, JITs or loads unsigned code.
    for bundle in "$STAGE/vst3/Arcade Ruins.vst3" "$STAGE/au/Arcade Ruins.component" "$STAGE/app/Arcade Ruins.app"; do
        for arch in arm64 x86_64; do
            lipo -archs "$bundle/Contents/MacOS/Arcade Ruins" | grep -qw "$arch" || { echo "❌ $bundle has no $arch half" >&2; exit 1; }
        done
        codesign --force --options runtime --timestamp --sign "$APPLICATION" "$bundle"
        codesign --verify --strict --deep "$bundle"
    done

    # --- Package: one component package per product, then one installer over the three.
    # BundleIsRelocatable is FALSE for each: by default the installer looks for a bundle with the
    # same identifier anywhere on the disk — a developer's build folder, say — and installs THERE.
    component() {   # name, staged folder, install location, identifier
        pkgbuild --analyze --root "$2" "$OUT/$1.plist" > /dev/null
        # (only an .app's analysis carries the key, so it is added where it is missing; and a
        # version check would refuse to put an older release back over a newer one)
        for key in BundleIsRelocatable BundleIsVersionChecked; do
            /usr/libexec/PlistBuddy -c "Set :0:$key false" "$OUT/$1.plist" > /dev/null 2>&1 \
                || /usr/libexec/PlistBuddy -c "Add :0:$key bool false" "$OUT/$1.plist"
        done
        pkgbuild --root "$2" --component-plist "$OUT/$1.plist" --install-location "$3" \
            --identifier "$4" --version "$VERSION" --min-os-version $MINIMUM_MACOS "$OUT/$1.pkg" > /dev/null
    }
    # (pkgbuild prints a few "write: Permission denied" lines here and still writes the package
    # correctly — its own noise about the staged bundles' ownership, not an error of ours.)
    component vst3 "$STAGE/vst3" "/Library/Audio/Plug-Ins/VST3"       com.badpackets303.ArcadeRuins.pkg.vst3
    component au   "$STAGE/au"   "/Library/Audio/Plug-Ins/Components" com.badpackets303.ArcadeRuins.pkg.au
    component app  "$STAGE/app"  "/Applications"                      com.badpackets303.ArcadeRuins.pkg.app

    cat > "$OUT/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Arcade Ruins $VERSION</title>
    <options customize="always" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <volume-check><allowed-os-versions><os-version min="$MINIMUM_MACOS"/></allowed-os-versions></volume-check>
    <choices-outline><line choice="vst3"/><line choice="au"/><line choice="app"/></choices-outline>
    <choice id="vst3" title="VST3 plugin" description="For Live, Reaper, Bitwig, Cubase and other VST3 hosts. /Library/Audio/Plug-Ins/VST3"><pkg-ref id="com.badpackets303.ArcadeRuins.pkg.vst3"/></choice>
    <choice id="au" title="Audio Unit plugin" description="For Logic Pro, GarageBand and other Audio Unit hosts. /Library/Audio/Plug-Ins/Components"><pkg-ref id="com.badpackets303.ArcadeRuins.pkg.au"/></choice>
    <choice id="app" title="Standalone application" description="Arcade Ruins on its own, with a MIDI keyboard or the computer's. /Applications"><pkg-ref id="com.badpackets303.ArcadeRuins.pkg.app"/></choice>
    <pkg-ref id="com.badpackets303.ArcadeRuins.pkg.vst3" version="$VERSION">vst3.pkg</pkg-ref>
    <pkg-ref id="com.badpackets303.ArcadeRuins.pkg.au" version="$VERSION">au.pkg</pkg-ref>
    <pkg-ref id="com.badpackets303.ArcadeRuins.pkg.app" version="$VERSION">app.pkg</pkg-ref>
</installer-gui-script>
XML
    if [ -n "$INSTALLER" ]; then
        productbuild --distribution "$OUT/distribution.xml" --package-path "$OUT" --sign "$INSTALLER" --timestamp "$PKG" > /dev/null
        pkgutil --check-signature "$PKG" | sed -n '1,4p'
    else
        productbuild --distribution "$OUT/distribution.xml" --package-path "$OUT" "$PKG" > /dev/null
        echo "⚠️  UNSIGNED package (no Developer ID Installer certificate): for looking at, never for shipping."
    fi

    # --- What takes it off again: the three things the package places, and the receipts. What a
    # person made — their banks, tunings and settings — is theirs and stays (X4-1's acceptance).
    cat > "$OUT/uninstall.sh" <<'UNINSTALL'
#!/bin/bash
# Removes Arcade Ruins (the VST3, the Audio Unit and the standalone application) from this Mac.
# Your presets, tunings and settings are NOT touched:
#   ~/Library/Application Support/BadPackets/Arcade Ruins
# Run it with:  sudo bash uninstall.sh
set -u
rm -rf "/Library/Audio/Plug-Ins/VST3/Arcade Ruins.vst3" \
       "/Library/Audio/Plug-Ins/Components/Arcade Ruins.component" \
       "/Applications/Arcade Ruins.app"
for receipt in vst3 au app; do pkgutil --forget "com.badpackets303.ArcadeRuins.pkg.$receipt" > /dev/null 2>&1; done
killall -9 AudioComponentRegistrar 2> /dev/null
echo "Arcade Ruins is removed. Your presets are still in ~/Library/Application Support/BadPackets/Arcade Ruins"
UNINSTALL
fi

# --- Notarise: submit without waiting, then poll. A wait that is abandoned loses nothing —
# RESUME_ID=<id> picks the submission up again, against the package still on disk.
if [ "$NOTARISE" != 0 ]; then
    if [ -z "${RESUME_ID:-}" ]; then
        RESUME_ID=$(xcrun notarytool submit "$PKG" --keychain-profile "$PROFILE" --no-wait --output-format json \
            | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
        echo "submitted: $RESUME_ID   (RESUME_ID=$RESUME_ID $0 picks it up again)"
    fi
    while :; do
        status=$(xcrun notarytool info "$RESUME_ID" --keychain-profile "$PROFILE" --output-format json \
            | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')
        echo "$(date +%H:%M:%S)  $status"
        case "$status" in
            Accepted) break ;;
            "In Progress") sleep 60 ;;
            *) xcrun notarytool log "$RESUME_ID" --keychain-profile "$PROFILE"; echo "❌ notarisation: $status" >&2; exit 1 ;;
        esac
    done
    xcrun stapler staple "$PKG"
    spctl -a -vv -t install "$PKG"
fi

(cd "$OUT" && shasum -a 256 "$(basename "$PKG")" | tee "$(basename "$PKG").sha256")
echo "✅ $PKG"
