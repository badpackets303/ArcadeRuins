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


# The cabinet's joystick (P7-11, ADR-061), in the painting's pixels: the ball, the stick down to
# its socket, and the box the sprite is cut from. `S1CabinetSkin.template.joystick` has the same box.
JOYSTICK_BOX = (86, 832, 128, 898)
JOYSTICK_BALL = (107, 853, 15)
JOYSTICK_STICK = [(99, 864), (110, 864), (108, 895), (98, 895)]


def joystick_mask(scale=1, grow=0):
    """White where the painted joystick is, in the box's own coordinates."""
    x0, y0, x1, y1 = JOYSTICK_BOX
    mask = Image.new("L", ((x1 - x0) * scale, (y1 - y0) * scale), 0)
    draw = ImageDraw.Draw(mask)
    cx, cy, r = JOYSTICK_BALL
    r += grow
    draw.ellipse([(cx - r - x0) * scale, (cy - r - y0) * scale, (cx + r - x0) * scale, (cy + r - y0) * scale], fill=255)
    draw.polygon([((x - x0 + (grow if i in (1, 2) else -grow)) * scale, (y - y0) * scale)
                  for i, (x, y) in enumerate(JOYSTICK_STICK)], fill=255)
    return mask.filter(ImageFilter.GaussianBlur(0.8 * scale))


def lift_joystick(im):
    """Takes the joystick off the painting — the live one is drawn over the hole. Each row of
    the hole is blended across from the pixels at its two ends: the console behind the stick is
    horizontal bands (the screen's sill, the panel's edge), and this carries them through. A
    patch copied from beside it brought the cabinet's orange edge or the ball's own rim along;
    a diffusion fill smeared the bands away."""
    x0, y0, x1, y1 = JOYSTICK_BOX
    hole = joystick_mask(grow=3).point(lambda v: 255 if v > 40 else 0)
    inside = hole.load()
    pixels = im.load()
    for y in range(y1 - y0):
        columns = [x for x in range(x1 - x0) if inside[x, y]]
        if not columns:
            continue
        left, right = x0 + columns[0] - 1, x0 + columns[-1] + 1
        def ends(x):   # a short average, so one odd pixel does not streak the row
            return [sum(pixels[x + d, y0 + y][c] for d in (-1, 0, 1)) / 3 for c in range(3)]
        a, b = ends(left - 1), ends(right + 1)
        for x in range(left, right + 1):
            t = (x - left) / max(1, right - left)
            pixels[x, y0 + y] = tuple(int(a[c] + (b[c] - a[c]) * t) for c in range(3))
    # soften the rows into each other a touch, only inside the hole
    box = (x0 - 2, y0 - 2, x1 + 2, y1 + 2)
    soft = im.crop(box).filter(ImageFilter.GaussianBlur(1.2))
    mask = Image.new("L", soft.size, 0)
    mask.paste(hole, (2, 2))
    im.paste(soft, box[:2], mask)
    return im


JOYSTICK_BALL_BOX = (88, 834, 126, 872)
JOYSTICK_ROD_BOX = (94, 846, 114, 898)


def _sprite(image, name):
    folder = os.path.join(ASSETS, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, name + "@2x.png")
    image.save(path)
    with open(os.path.join(folder, "Contents.json"), "w") as contents:
        json.dump({"images": [{"filename": name + "@2x.png", "idiom": "universal", "scale": "2x"}],
                   "info": {"author": "xcode", "version": 1}}, contents, indent=2)
    return path, image.size


def cabinet_joystick(source):
    """The joystick as two sprites at the template's 2x: the ball, and the rod. Nothing is ever
    stretched (owner, 2026-09-17): the ball slides along the rod, up to show more of it and down
    to cover it, so the rod is painted on up behind the ball from its own top row."""
    cx, cy, r = JOYSTICK_BALL
    x0, y0, x1, y1 = JOYSTICK_BALL_BOX
    ball = source.crop(JOYSTICK_BALL_BOX).resize(((x1 - x0) * 2, (y1 - y0) * 2), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", ball.size, 0)
    ImageDraw.Draw(mask).ellipse([(cx - r - x0) * 2, (cy - r - y0) * 2, (cx + r - x0) * 2, (cy + r - y0) * 2], fill=255)
    ball.putalpha(mask.filter(ImageFilter.GaussianBlur(1.6)))

    x0, y0, x1, y1 = JOYSTICK_ROD_BOX
    rod = source.crop(JOYSTICK_ROD_BOX)
    top = cy + r + 2                                    # the first row of rod clear of the ball
    row = rod.crop((0, top - y0, x1 - x0, top - y0 + 1))
    for y in range(0, top - y0):
        rod.paste(row, (0, y))
    rod = rod.resize(((x1 - x0) * 2, (y1 - y0) * 2), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", rod.size, 0)
    left, right = JOYSTICK_STICK[0][0], JOYSTICK_STICK[1][0]
    shape = [(left, y0 + 2), (right, y0 + 2)] + JOYSTICK_STICK[2:]
    ImageDraw.Draw(mask).polygon([((x - x0) * 2, (y - y0) * 2) for x, y in shape], fill=255)
    rod.putalpha(mask.filter(ImageFilter.GaussianBlur(1.2)))
    _sprite(ball, "s1_template_joystick_ball")
    return _sprite(rod, "s1_template_joystick_rod")


def cabinet_template():
    """The Cabinet skin's window, at twice the painting's size so a 1440-point window is not
    drawn from fewer pixels than it has."""
    source = os.path.join(os.path.dirname(os.path.abspath(__file__)), "source", "ar-template.png")
    original = Image.open(source).convert("RGB")
    print("%-52s %s" % cabinet_joystick(original))
    image = lift_joystick(clean_template(original.copy()))
    image = image.resize((image.width * 2, image.height * 2), Image.LANCZOS)
    # P7-12 (ADR-062): the same window with the power out — grey, and dimmer
    dark = ImageOps.grayscale(image).point(lambda v: int(v * 0.62))
    folder = os.path.join(ASSETS, "s1_template_cabinet_dark.imageset")
    os.makedirs(folder, exist_ok=True)
    dark.save(os.path.join(folder, "s1_template_cabinet_dark@2x.jpg"), quality=88)
    with open(os.path.join(folder, "Contents.json"), "w") as contents:
        json.dump({"images": [{"filename": "s1_template_cabinet_dark@2x.jpg", "idiom": "universal", "scale": "2x"}],
                   "info": {"author": "xcode", "version": 1}}, contents, indent=2)
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
    print("%-52s %s" % cabinet_template())
    for filename, pixels in app_icon():
        print(f"  SynthOneCore AppIcon.appiconset/{filename:22} {pixels}x{pixels}")
    path, pixels = icon_bundle_art()
    print("%-52s %s" % (path, f"{pixels}x{pixels}"))
