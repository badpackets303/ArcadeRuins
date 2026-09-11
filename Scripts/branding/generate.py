#!/usr/bin/env python3
"""Regenerates every branded asset (P5-4). Idempotent — run it any time.

    python3 Scripts/branding/generate.py

Writes into `Sources/SynthOneCore/Assets/Assets.xcassets/`. The app icon is *generated*, not
drawn, so it can be adjusted in `appicon.py` rather than locked into a PNG nobody can edit.
Every wordmark — the header's, and the About and mailing-list logos — is the owner's own
artwork, `source/Arcade-Ruins.png`, fitted to each frame here. `wordmark.py`, the Futura
wordmark these replaced, is no longer used.
"""
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import appicon

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
ASSETS = os.path.join(ROOT, "Sources/SynthOneCore/Assets/Assets.xcassets")

# The wordmark's frame, in @2x pixels: the header's "Title Button" from
# `Header/Base.lproj/Header.storyboard`, which is `(7, 3, 200, 30)` in logical points
# and is the transparent hit area sitting over the wordmark (its action is
# `homePressed:`). **This is the rectangle the wordmark is centred in** — Synth One's
# own was neither centred nor aligned to it, sitting hard left and 22px from the frame's
# top against 8px from its bottom.
TITLE_FRAME = (7 * 2, 3 * 2, 200 * 2, 30 * 2)


def header_bar():
    """The main header. The wordmark is baked into the background image, so the old one
    is painted out with the surrounding colour first, sampled per row from a clean
    column to the right of it."""
    path = os.path.join(ASSETS, "headerback.imageset/headerback@2x.png")
    out = Image.open(path).convert("RGBA")
    px = out.load()

    frame_x, frame_y, frame_w, frame_h = TITLE_FRAME
    for y in range(out.size[1]):
        background = px[500, y]
        for x in range(0, frame_x + frame_w + 4):
            px[x, y] = background

    # The owner's wordmark (2026-09-10), shrunk to fit the title frame and centred in it
    # both ways. It replaces the Futura one `render` drew here.
    out.alpha_composite(*fit_centred(source_wordmark(), TITLE_FRAME))
    out.save(path)
    return path, out.size


SOURCE_WORDMARK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "source", "Arcade-Ruins.png")


def source_wordmark():
    """The owner's wordmark, trimmed to its letters.

    The PNG is already transparent, but carries faint noise — about 25,000 pixels at
    alpha 1–15, some of them pure red — scattered well outside the letters. Trimming by
    any alpha would keep the whole canvas, and the noise would survive the shrink as a
    haze. The letters' own anti-aliasing starts above that, and their interiors are
    alpha ~253, so they need no correction.
    """
    mark = Image.open(SOURCE_WORDMARK).convert("RGBA")
    alpha = mark.split()[3].point(lambda v: 0 if v < 16 else v)
    mark.putalpha(alpha)
    return mark.crop(alpha.getbbox())


def fit_centred(mark, frame):
    """`mark` shrunk to fit `frame` (x, y, width, height), and the point that centres it there."""
    x, y, width, height = frame
    scale = min(width / mark.size[0], height / mark.size[1])
    size = (round(mark.size[0] * scale), round(mark.size[1] * scale))
    # Resized premultiplied: the transparent pixels around the letters are black, and a
    # straight-alpha filter at this reduction would pull that black into every edge.
    mark = mark.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
    return mark, (x + (width - size[0]) // 2, y + (height - size[1]) // 2)


def fitted_logo(imageset, filename, size):
    """The owner's wordmark on transparency, fitted to an existing asset's box and centred.

    `ak1-logo` is the About panel's logo button and the mailing-list screens' image;
    `s1_logo` is the iPhone header's. The storyboards place them by frame, so each
    replacement has to be exactly the same pixel size or the layout shifts.
    """
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    out.alpha_composite(*fit_centred(source_wordmark(), (0, 0) + size))
    path = os.path.join(ASSETS, imageset, filename)
    out.save(path)
    return path, size


def app_icon():
    """All 18 sizes, downsampled from one 1024 master."""
    master = appicon.render()
    directory = os.path.join(ASSETS, "AppIcon.appiconset")
    manifest = json.load(open(os.path.join(directory, "Contents.json")))
    written = []
    for entry in manifest["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        points = float(entry["size"].split("x")[0])
        pixels = round(points * float(entry["scale"].rstrip("x")))
        icon = master.resize((pixels, pixels), Image.LANCZOS)
        # The marketing size must be fully opaque; the rest keep the rounded mask.
        if entry.get("idiom") == "ios-marketing":
            flat = Image.new("RGBA", icon.size, (0x0B, 0x04, 0x18, 255))
            flat.alpha_composite(icon)
            icon = flat
        icon.save(os.path.join(directory, filename))
        written.append((filename, pixels))
    return written


if __name__ == "__main__":
    print("%-52s %s" % header_bar())
    print("%-52s %s" % fitted_logo("ak1-logo.imageset", "ak1-logo2@2x.png", (376, 28)))
    print("%-52s %s" % fitted_logo("s1_logo.imageset", "s1_logo.png", (196, 28)))
    for filename, pixels in app_icon():
        print(f"  AppIcon.appiconset/{filename:22} {pixels}x{pixels}")
