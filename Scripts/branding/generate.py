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

from PIL import Image, ImageDraw, ImageFilter, ImageOps

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
SOURCE_ICON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "source", "Arcade-Ruins-Icon.png")

# The app's icon (P7-8, ADR-052). The app had no icon of any kind before this: ADR-029's
# generated one went into SynthOneCore's iOS set, which a Catalyst app never reads.
#
# **Icon Composer, not an icon set.** macOS 26 draws every app icon in the system's rounded
# shape, and a legacy `.icns` or `.appiconset` is composited *inside* it on a light plate —
# measured, not assumed: the first pass shipped a mac-idiom icon set and the owner's rounded
# square came out nested in a white one. An `.icon` bundle is the artwork the system shapes
# itself, so it fills the icon. `actool` still emits a legacy `.icns` from it for older systems.
ICON_BUNDLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                           "Sources", "SynthOne", "ArcadeRuins.icon", "Assets")

# Apple's macOS icon grid, for the iOS set: the body fills 824 of a 1024 canvas, centred, and
# whatever glow the artwork carries lives in the margin.
MAC_ICON_BODY = 824 / 1024


def source_icon():
    """The owner's icon artwork, and the bounds of its body.

    The body is the opaque rounded square; the neon glow around it is semi-transparent and
    reaches the edge of the canvas, so thresholding the alpha is what separates them.
    """
    icon = Image.open(SOURCE_ICON).convert("RGBA")
    body = icon.split()[3].point(lambda v: 255 if v > 220 else 0).getbbox()
    return icon, body


def mac_icon_image(pixels):
    """The artwork at `pixels` square, its body on Apple's grid and centred."""
    icon, body = source_icon()
    scale = (pixels * MAC_ICON_BODY) / max(body[2] - body[0], body[3] - body[1])
    size = (round(icon.width * scale), round(icon.height * scale))
    # Premultiplied, as the wordmark is: a straight-alpha filter pulls the black behind the
    # transparent pixels into every edge at this reduction.
    scaled = icon.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
    centre = ((body[0] + body[2]) / 2 * scale, (body[1] + body[3]) / 2 * scale)
    out = Image.new("RGBA", (pixels, pixels), (0, 0, 0, 0))
    out.alpha_composite(scaled, (round(pixels / 2 - centre[0]), round(pixels / 2 - centre[1])))
    return out


def icon_bundle_art(pixels=1024):
    """The layer inside `ArcadeRuins.icon`: the artwork's body, full bleed.

    The system supplies the shape and the margin, so the body is cropped out of its canvas and
    fills the square. The glow around it goes: it lives outside the body, where the system's
    own shadow now is. `icon.json` beside this is hand-written and is not generated.
    """
    icon, body = source_icon()
    cropped = icon.crop(body)
    side = max(cropped.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.alpha_composite(cropped, ((side - cropped.width) // 2, (side - cropped.height) // 2))
    os.makedirs(ICON_BUNDLE, exist_ok=True)
    path = os.path.join(ICON_BUNDLE, "art.png")
    square.convert("RGBa").resize((pixels, pixels), Image.LANCZOS).convert("RGBA").save(path)
    return path, pixels


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


def feather_mask(w,h,f=5):
    m=Image.new('L',(w,h),0)
    ImageDraw.Draw(m).rectangle([f,f,w-f-1,h-f-1],fill=255)
    return m.filter(ImageFilter.GaussianBlur(f/2))
def clone(im,dst,src,f=5):
    x0,y0,x1,y1=dst; w,h=x1-x0,y1-y0
    patch=im.crop((src[0],src[1],src[0]+w,src[1]+h))
    im.paste(patch,(x0,y0),feather_mask(w,h,f))
def rowfill(im,dst,refx,f=3):
    """Each row takes the colour of the clean columns at refx."""
    x0,y0,x1,y1=dst; w,h=x1-x0,y1-y0
    col=im.crop((refx,y0,refx+6,y1)).resize((1,h),Image.BOX).resize((w,h),Image.NEAREST)
    im.paste(col,(x0,y0),feather_mask(w,h,f))
def clean_template(im):
    """Takes the mock's painted controls off the owner's template (P7-9, ADR-059): the live
    controls sit where they were. Frames, titles, the header and its buttons stay."""
    rowfill(im,(570,24,902,70),534)                 # the preset name
    clone(im,(1416,302,1553,334),(900,302))        # Tempo sync
    clone(im,(1116,421,1555,491),(1116,340))        # mod-target chips
    clone(im,(406,497,484,530),(306,497))           # Reverb On
    clone(im,(694,497,779,530),(594,497))           # Delay On
    clone(im,(1446,539,1554,640),(1120,539))        # Master switches
    clone(im,(1378,620,1445,648),(1120,560))        # Volume
    clone(im,(1480,674,1553,711),(1400,674))        # Snap
    clone(im,(1212,728,1551,920),(700,725))         # the pads and their captions
    rowfill(im,(1244,68,1314,97),1174)      # Record: a plugin has none, and the label counts
    bar=im.crop((1010,950,1560,992))
    im.paste(bar,(6,950)); im.paste(ImageOps.mirror(bar),(556,950),feather_mask(550,42,4))
    clone(im,(980,950,1106,992),(1300,950),8)
    return im


def cabinet_template():
    """The Cabinet skin's window, at twice the painting's size so a 1440-point window is not
    drawn from fewer pixels than it has."""
    source = os.path.join(os.path.dirname(os.path.abspath(__file__)), "source", "ar-template.png")
    image = clean_template(Image.open(source).convert("RGB"))
    image = image.resize((image.width * 2, image.height * 2), Image.LANCZOS)
    folder = os.path.join(ASSETS, "s1_template_cabinet.imageset")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "s1_template_cabinet@2x.jpg")
    image.save(path, quality=90)
    with open(os.path.join(folder, "Contents.json"), "w") as contents:
        json.dump({"images": [{"filename": "s1_template_cabinet@2x.jpg", "idiom": "universal", "scale": "2x"}],
                   "info": {"author": "xcode", "version": 1}}, contents, indent=2)
    return path, image.size


def app_icon():
    """SynthOneCore's iOS icon set: all 18 sizes, from the owner's artwork.

    A Catalyst app never reads this set — the app target's own (`mac_app_icon`) is what ships —
    but it is in the framework, so it is kept in step rather than left showing ADR-029's
    code-drawn sunset. P7-8 (ADR-052).
    """
    master = mac_icon_image(1024)
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
    # P7-4 (ADR-048): the Neon Ruins skin's wordmark, a 220×24-point frame (@2x)
    print("%-52s %s" % fitted_logo("s1_wordmark_neon.imageset", "s1_wordmark_neon@2x.png", (440, 48)))
    print("%-52s %s" % cabinet_template())
    for filename, pixels in app_icon():
        print(f"  SynthOneCore AppIcon.appiconset/{filename:22} {pixels}x{pixels}")
    path, pixels = icon_bundle_art()
    print("%-52s %s" % (path, f"{pixels}x{pixels}"))
