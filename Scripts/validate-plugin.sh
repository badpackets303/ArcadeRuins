#!/bin/bash
# X2-8 (ADR-079): validate the JUCE plugin on this machine — Steinberg's VST3 validator, then
# pluginval at strictness 10 with that validator handed to it. The counterpart of
# Scripts/validate-au.sh for the VST3; the `plugin` workflow does the same on three OSes.
#
# Both tools are BUILT HERE from their authors' repositories, pinned by tag and commit, into
# build/validation (ignored by git): nothing precompiled is downloaded and run. The first run
# takes some minutes; later ones seconds.
#
#   Scripts/validate-plugin.sh            # build the plugin if needed, then validate it
#   Scripts/validate-plugin.sh --au       # …and the AU (macOS, ADR-093): INSTALLS it for this user in
#                                         # ~/Library/Audio/Plug-Ins/Components — auval only sees a
#                                         # registered component — then Apple's auval and pluginval on it.
#                                         # Logic will not load an AU that fails auval. Quit and reopen a
#                                         # running host afterwards: it holds the old one (CLAUDE.md).
#
set -euo pipefail
cd "$(dirname "$0")/.."

VST3SDK_TAG=v3.8.0_build_66           # the SDK version JUCE 9.0.2 bundles (3.8.0, MIT)
VST3SDK_COMMIT=9fad9770f2ae8542ab1a548a68c1ad1ac690abe0
PLUGINVAL_TAG=v1.0.4
PLUGINVAL_COMMIT=ed19c2c16b57a6d94db391bea3ef4a80b769d5bf

# CMake cannot link with the Command Line Tools SDK on this Mac (CLAUDE.md).
if [ "$(uname)" = "Darwin" ]; then export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"; fi

plugin="build/plugin/Sources/S1Plugin/ArcadeRuins_artefacts/Release/VST3/Arcade Ruins.vst3"
cmake -S . -B build/plugin -DS1_BUILD_PLUGIN=ON -DCMAKE_BUILD_TYPE=Release > /dev/null
cmake --build build/plugin --config Release --target ArcadeRuins_VST3 --parallel 8 | tail -1
with_au=no; if [ "${1:-}" = "--au" ]; then with_au=yes; fi
if [ "$with_au" = yes ]; then cmake --build build/plugin --config Release --target ArcadeRuins_AU --parallel 8 | tail -1; fi

mkdir -p build/validation
cd build/validation

fetch() {   # directory, url, tag, commit, extra clone arguments…
    local dir=$1 url=$2 tag=$3 commit=$4; shift 4
    if [ ! -d "$dir/.git" ]; then git clone --quiet --depth 1 --branch "$tag" "$@" "$url" "$dir"; fi
    if [ "$(git -C "$dir" rev-parse HEAD)" != "$commit" ]; then
        echo "❌ $dir is not at $commit (tag $tag moved, or a stale checkout: delete build/validation/$dir)" >&2; exit 1
    fi
}

validator=$(find vst3sdk-build -type f -name validator 2>/dev/null | head -1 || true)
if [ -z "$validator" ]; then
    fetch vst3sdk https://github.com/steinbergmedia/vst3sdk.git "$VST3SDK_TAG" "$VST3SDK_COMMIT"
    git -C vst3sdk submodule update --quiet --init --depth 1 base cmake pluginterfaces public.sdk
    cmake -S vst3sdk -B vst3sdk-build -DCMAKE_BUILD_TYPE=Release -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF \
        -DSMTG_ENABLE_VST3_PLUGIN_EXAMPLES=OFF -DSMTG_ENABLE_VST3_HOSTING_EXAMPLES=ON -DSMTG_RUN_VST_VALIDATOR=OFF > vst3sdk-configure.log 2>&1
    cmake --build vst3sdk-build --config Release --target validator --parallel 8 > vst3sdk-build.log 2>&1
    validator=$(find vst3sdk-build -type f -name validator | head -1)
fi

pluginval=$(find pluginval-build -type f -name pluginval -perm +111 2>/dev/null | head -1 || true)
if [ -z "$pluginval" ]; then
    fetch pluginval-src https://github.com/Tracktion/pluginval.git "$PLUGINVAL_TAG" "$PLUGINVAL_COMMIT" --recurse-submodules --shallow-submodules
    cmake -S pluginval-src -B pluginval-build -DCMAKE_BUILD_TYPE=Release > pluginval-configure.log 2>&1
    cmake --build pluginval-build --config Release --parallel 8 > pluginval-build.log 2>&1
    pluginval=$(find pluginval-build -type f -name pluginval -perm +111 | head -1)
fi

echo "— Steinberg's validator (-e)"
if ! "$validator" -e "../../$plugin" > vst3-validator.txt 2>&1; then
    grep -n -B8 "Failed\]" vst3-validator.txt || tail -40 vst3-validator.txt
    echo "❌ the VST3 validator failed — build/validation/vst3-validator.txt" >&2; exit 1
fi
grep -E "^Result" vst3-validator.txt

echo "— pluginval, strictness 10"
mkdir -p pluginval-logs
"$pluginval" --strictness-level 10 --validate-in-process --verbose --vst3validator "$PWD/$validator" \
    --output-dir pluginval-logs --validate "$PWD/../../$plugin" > pluginval-console.txt 2>&1 || {
    grep -n -B6 "!!!" pluginval-console.txt | tail -60; echo "❌ pluginval failed — build/validation/pluginval-console.txt" >&2; exit 1; }
# A skipped test is not a passed one: without a validator path pluginval skips that test and
# still prints SUCCESS. (Its auval test has nothing to do for a VST3.)
if grep -n "Skipping" pluginval-console.txt | grep -v -i "auval"; then echo "❌ pluginval skipped a test" >&2; exit 1; fi
tail -1 pluginval-console.txt
echo "✅ validated: $plugin"

if [ "$with_au" = yes ]; then
    # `aumu` / `ArRu` / `BP03` — the JUCE build's own AU. Classic's is `ruin`, and is not touched.
    component="build/plugin/Sources/S1Plugin/ArcadeRuins_artefacts/Release/AU/Arcade Ruins.component"
    installed="$HOME/Library/Audio/Plug-Ins/Components/Arcade Ruins.component"
    echo "— the AU: installed for this user, then Apple's auval"
    rm -rf "$installed"
    ditto "../../$component" "$installed"
    killall -9 AudioComponentRegistrar 2>/dev/null || true      # or auval validates the copy it cached
    if ! auval -v aumu ArRu BP03 > auval.txt 2>&1 || ! grep -q "AU VALIDATION SUCCEEDED" auval.txt; then
        grep -n "ERROR\|FAIL" auval.txt | grep -v "should fail" | head -20
        echo "❌ auval failed — build/validation/auval.txt" >&2; exit 1
    fi
    grep "AU VALIDATION" auval.txt
    echo "— pluginval on the AU, strictness 10"
    "$pluginval" --strictness-level 10 --validate-in-process --verbose \
        --output-dir pluginval-logs --validate "$installed" > pluginval-au-console.txt 2>&1 || {
        grep -n -B6 "!!!" pluginval-au-console.txt | tail -60; echo "❌ pluginval failed on the AU — build/validation/pluginval-au-console.txt" >&2; exit 1; }
    tail -1 pluginval-au-console.txt
    echo "✅ validated and installed: $installed"
fi
