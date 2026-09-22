#!/bin/bash
# Runs INSIDE the container (Scripts/validate-linux.sh starts it). /src is the repository,
# read-only; /work is a Docker volume that keeps the build trees between runs.
set -euo pipefail
stage=${1:-all}

VST3SDK_TAG=v3.8.0_build_66
VST3SDK_COMMIT=9fad9770f2ae8542ab1a548a68c1ad1ac690abe0
PLUGINVAL_TAG=v1.0.4
PLUGINVAL_COMMIT=ed19c2c16b57a6d94db391bea3ef4a80b769d5bf
jobs=$(nproc)
plugin="/work/plugin/Sources/S1Plugin/ArcadeRuins_artefacts/Release/VST3/Arcade Ruins.vst3"
git config --global --add safe.directory '*'

fetch() {   # directory, url, tag, commit, extra clone arguments…
    local dir=$1 url=$2 tag=$3 commit=$4; shift 4
    if [ ! -d "$dir/.git" ]; then git clone --quiet --depth 1 --branch "$tag" "$@" "$url" "$dir"; fi
    test "$(git -C "$dir" rev-parse HEAD)" = "$commit" || { echo "❌ $dir is not at $commit"; exit 1; }
}

if [ "$stage" = all ] || [ "$stage" = tests ]; then
    echo "━━ GCC $(gcc -dumpversion) on $(uname -m): build, every CTest test"
    cmake -S /src -B /work/plugin -DS1_BUILD_PLUGIN=ON -DCMAKE_BUILD_TYPE=Release > /work/configure.log 2>&1 || { tail -30 /work/configure.log; exit 1; }
    cmake --build /work/plugin --parallel "$jobs" > /work/build.log 2>&1 || { grep -E "error|Error" /work/build.log | head -40; exit 1; }
    ctest --test-dir /work/plugin --output-on-failure 2>&1 | tail -30
    ctest --test-dir /work/plugin > /dev/null   # the exit status, after the tail above
fi

if [ "$stage" = all ] || [ "$stage" = validate ]; then
    echo "━━ Steinberg's validator (-e)"
    validator=$(find /work/vst3sdk-build -type f -name validator 2>/dev/null | head -1 || true)
    if [ -z "$validator" ]; then
        fetch /work/vst3sdk https://github.com/steinbergmedia/vst3sdk.git "$VST3SDK_TAG" "$VST3SDK_COMMIT"
        git -C /work/vst3sdk submodule update --quiet --init --depth 1 base cmake pluginterfaces public.sdk
        cmake -S /work/vst3sdk -B /work/vst3sdk-build -DCMAKE_BUILD_TYPE=Release -DSMTG_ENABLE_VSTGUI_SUPPORT=OFF \
            -DSMTG_ENABLE_VST3_PLUGIN_EXAMPLES=OFF -DSMTG_ENABLE_VST3_HOSTING_EXAMPLES=ON -DSMTG_RUN_VST_VALIDATOR=OFF > /work/vst3sdk-configure.log 2>&1 || { tail -40 /work/vst3sdk-configure.log; exit 1; }
        cmake --build /work/vst3sdk-build --target validator --parallel "$jobs" > /work/vst3sdk-build.log 2>&1 || { grep -E "error" /work/vst3sdk-build.log | head -30; tail -20 /work/vst3sdk-build.log; exit 1; }
        validator=$(find /work/vst3sdk-build -type f -name validator | head -1)
    fi
    "$validator" -e "$plugin" > /work/vst3-validator.txt 2>&1 || { grep -n -B8 "Failed\]" /work/vst3-validator.txt || tail -40 /work/vst3-validator.txt; echo "❌ the VST3 validator failed"; exit 1; }
    grep -E "^Result" /work/vst3-validator.txt

    echo "━━ pluginval $PLUGINVAL_TAG, strictness 10, under xvfb"
    pluginval=$(find /work/pluginval-build -type f -name pluginval -perm /111 2>/dev/null | head -1 || true)
    if [ -z "$pluginval" ]; then
        fetch /work/pluginval-src https://github.com/Tracktion/pluginval.git "$PLUGINVAL_TAG" "$PLUGINVAL_COMMIT" --recurse-submodules --shallow-submodules
        cmake -S /work/pluginval-src -B /work/pluginval-build -DCMAKE_BUILD_TYPE=Release > /work/pluginval-configure.log 2>&1 || { tail -40 /work/pluginval-configure.log; exit 1; }
        cmake --build /work/pluginval-build --parallel "$jobs" > /work/pluginval-build.log 2>&1 || { grep -E "error" /work/pluginval-build.log | head -30; exit 1; }
        pluginval=$(find /work/pluginval-build -type f -name pluginval -perm /111 | head -1)
    fi
    mkdir -p /work/pluginval-logs
    # No --vst3validator on Linux: pluginval 1.0.4 hands the validator the .so INSIDE the bundle,
    # which SDK 3.8's validator refuses for any plugin ("is not a module directory"). The
    # validator has just run by itself, above; pluginval's one skipped test is that one.
    xvfb-run -a "$pluginval" --strictness-level 10 --validate-in-process --verbose \
        --output-dir /work/pluginval-logs --validate "$plugin" > /work/pluginval-console.txt 2>&1 || {
        grep -n -B6 "!!!" /work/pluginval-console.txt | tail -60; tail -5 /work/pluginval-console.txt; echo "❌ pluginval failed"; exit 1; }
    if grep -n "Skipping" /work/pluginval-console.txt | grep -v -i -E "auval|vst3 validator"; then echo "❌ pluginval skipped a test"; exit 1; fi
    tail -1 /work/pluginval-console.txt
fi

if [ "$stage" = all ] || [ "$stage" = rtsan ]; then
    echo "━━ RealtimeSanitizer, $(clang++-20 --version | head -1)"
    CC=clang-20 CXX=clang++-20 cmake -S /src -B /work/rtsan -DS1_BUILD_PLUGIN=ON -DS1_RTSAN=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo > /work/rtsan-configure.log 2>&1 || { tail -30 /work/rtsan-configure.log; exit 1; }
    cmake --build /work/rtsan --parallel "$jobs" --target S1AllTests > /work/rtsan-build.log 2>&1 || { grep -E "error" /work/rtsan-build.log | head -30; exit 1; }
    # Every finding in one run, each stack once: a first finding otherwise hides the rest.
    # Without the test "Goldens": Clang on Linux is not a toolchain the product is built with, and
    # on arm64 it puts one preset of twenty just outside the tolerance (relative RMS 0.0042 against
    # 0.0032; 10 of 20 bit-exact) — a measurement for ADR-079, not this job's question. The same
    # twenty presets still render under the sanitizer in GoldensBlockIndependence and GoldensReject-*.
    RTSAN_OPTIONS=halt_on_error=false:suppress_equal_stacks=true ctest --test-dir /work/rtsan -E '^Goldens$' --output-on-failure > /work/rtsan-tests.txt 2>&1 || true
    grep -E "tests passed|\*\*\*Failed" /work/rtsan-tests.txt || true
    # The frames that are ours, under each finding: where it is, not which test met it.
    grep -E "Intercepted call|^ +#[0-9]+ .* in (S1|s1|sp_|juce::)" /work/rtsan-tests.txt | sed -E 's/0x[0-9a-f]+ //; s/\(BuildId.*//' | awk '/Intercepted/ { kind=$0; n=0; next } n < 3 { print kind " <- " $0; n++ }' | sort | uniq -c | sort -rn | head -30 || true
    if grep -q "RealtimeSanitizer: " /work/rtsan-tests.txt; then echo "❌ the RealtimeSanitizer found something — /work/rtsan-tests.txt"; exit 1; fi
    grep -q "100% tests passed" /work/rtsan-tests.txt
fi
echo "✅ Linux ($stage)"
