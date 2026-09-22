#!/usr/bin/env python3
# X3-1 (ADR-083): holds the layout specification to the RUNNING Mac app. The specification is
# written by a test that builds the layout with no window; this compares it with the frames
# `desktop_render.py` measured in the real one (RENDER_FRAMES=1), class by class: every section,
# control and display of the skin must have a view of its Mac class within TOLERANCE points on
# every edge, each view used once. 1 point is 2 pixels of the 2x render — the plan's criterion.
#
#   compare_layout_frames.py <layout-spec.json> <studio|cabinet> <tag.frames.txt>
import json, sys

TOLERANCE = 1.0

def main():
    spec_path, skin_key, frames_path = sys.argv[1:4]
    skin = json.load(open(spec_path))["skins"][skin_key]
    measured = {}
    for line in open(frames_path):
        parts = line.split()
        if len(parts) != 5:
            continue
        cls = parts[0].split(".")[-1]
        measured.setdefault(cls, []).append([float(v) for v in parts[1:]])

    wanted = [("section " + s["key"], "S1SectionView", s["frame"]) for s in skin["sections"]]
    wanted += [(c["id"], c["class"], c["frame"]) for c in skin["controls"]]
    display_class = {"adsr": "AKADSRView", "xyPad": "AKTouchPadView"}
    wanted += [(d["id"], display_class[d["kind"]], d["frame"]) for d in skin["displays"]]

    def deviation(a, b):
        return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[0] + a[2] - b[0] - b[2]), abs(a[1] + a[3] - b[1] - b[3]))

    worst, failures = (0.0, ""), []
    for name, cls, frame in wanted:
        candidates = measured.get(cls, [])
        if not candidates:
            failures.append("%s: the running app has no visible %s" % (name, cls))
            continue
        best = min(candidates, key=lambda m: deviation(frame, m))
        off = deviation(frame, best)
        if off > TOLERANCE:
            failures.append("%s: %.2f points off (specified %s, nearest %s in the app %s)" % (name, off, frame, cls, best))
        else:
            candidates.remove(best)
        if off > worst[0]:
            worst = (off, name)
    print("%s: %d frames compared with the running app; worst %.2f points (%s); tolerance %.1f point = 2 px of the render"
          % (skin_key, len(wanted), worst[0], worst[1] or "-", TOLERANCE))
    for failure in failures:
        print("  FAIL " + failure)
    sys.exit(1 if failures else 0)

main()
