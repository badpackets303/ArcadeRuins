#!/bin/bash
# X3-1 (ADR-083): the layout specification against the Mac app itself, for both skins —
#   1. renders the DerivedData app's window (Scripts/debug/desktop_render.py) and measures the
#      frame of every view in it;
#   2. compares the specification's sections, controls and displays with those frames
#      (Scripts/debug/compare_layout_frames.py: every edge within 1 point = 2 px of the render);
#   3. draws the wireframe from the specification, with the plugin's own reader, over the render:
#      <out>/<skin>-overlay.png, to look at.
# Needs the Debug app (Scripts/build.sh) and the plugin tests built (build/plugin, LayoutWireframe).
# Opens the app for some seconds per skin; it reads the owner's library and writes nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/arcade-ruins-layout-spec}"
SPEC=Sources/S1Plugin/Layout/layout-spec.json
WIREFRAME=$(find build/plugin/Tests/Plugin/LayoutWireframe_artefacts -type f -name LayoutWireframe | head -1)
[ -x "$WIREFRAME" ] || { echo "Build LayoutWireframe first: cmake --build build/plugin --target LayoutWireframe" >&2; exit 1; }
mkdir -p "$OUT"
status=0
for skin in studio cabinet; do
    rm -f "$OUT/$skin.png" "$OUT/$skin.frames.txt"
    DRIVER_OUT="$OUT" RENDER_TAG=$skin RENDER_FRAMES=1 RENDER_SETTLE="${RENDER_SETTLE:-8}" \
        RENDER_ARGS="-S1Skin $skin -S1ClassicLayout NO" \
        xcrun lldb -b -o "command script import Scripts/debug/desktop_render.py" 2>&1 | grep -E "^\[render\] (render 0|frames|launch failed)" || true
    [ -s "$OUT/$skin.frames.txt" ] || { echo "$skin: no frames were measured" >&2; exit 1; }
    python3 Scripts/debug/compare_layout_frames.py "$SPEC" $skin "$OUT/$skin.frames.txt" || status=1
    "$WIREFRAME" "$SPEC" $skin "$OUT/$skin-overlay.png" --over "$OUT/$skin.png"
done
exit $status
