#!/usr/bin/env python3
# X3-3 (ADR-085): the JUCE editor's picture against the Mac app's, section by section — the mean
# absolute difference per colour channel (0-255) inside each section's frame, and a side-by-side
# image to look at. Both pictures must show the same preset (desktop_render.py's RENDER_SELECT and
# EditorSnapshot's --program). A number, not a verdict: type, glow softness and what a preset's
# tuning or tempo shows differ by design; a control missing or misplaced stands out at once.
#
#   compare_editor_render.py <layout-spec.json> <skin> <mac.png> <juce.png> <side-by-side.png>
import json, sys
from PIL import Image, ImageChops, ImageStat

spec_path, skin_key, mac_path, juce_path, out_path = sys.argv[1:6]
skin = json.load(open(spec_path))["skins"][skin_key]
mac = Image.open(mac_path).convert("RGB")
juce = Image.open(juce_path).convert("RGB").resize(mac.size, Image.LANCZOS)
scale = mac.size[0] / 1440.0
worst = (0.0, "")
print("%s: mean difference per channel, 0-255" % skin_key)
for section in skin["sections"]:
    x, y, w, h = section["frame"]
    box = tuple(int(round(v * scale)) for v in (x, y, x + w, y + h))
    difference = sum(ImageStat.Stat(ImageChops.difference(mac.crop(box), juce.crop(box))).mean) / 3.0
    print("  %-22s %5.1f" % (section["key"], difference))
    if difference > worst[0]:
        worst = (difference, section["key"])
whole = sum(ImageStat.Stat(ImageChops.difference(mac, juce)).mean) / 3.0
print("  %-22s %5.1f   (worst section: %s, %.1f)" % ("the whole window", whole, worst[1], worst[0]))
sheet = Image.new("RGB", (mac.size[0], mac.size[1] * 2 + 16), (255, 0, 255))
sheet.paste(mac, (0, 0))
sheet.paste(juce, (0, mac.size[1] + 16))
sheet.resize((sheet.size[0] // 2, sheet.size[1] // 2), Image.LANCZOS).save(out_path)
