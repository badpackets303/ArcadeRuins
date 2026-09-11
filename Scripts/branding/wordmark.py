#!/usr/bin/env python3
"""Renders the Arcade Ruins wordmark (P5-4).

Kept in the repo because these are *generated* assets. The originals were flat PNGs
someone drew once; regenerating from a script means the tracking, the gradient and the
glow can be adjusted without redrawing, and means the next person can see how the
wordmark was made instead of guessing.

Palette: the interface's accent orange fading to the grey Synth One's wordmark used,
left to right, with a soft orange glow. Two weights, echoing the layout it replaces —
a heavy word and a light one.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FUTURA = "/System/Library/Fonts/Supplemental/Futura.ttc"
MEDIUM, BOLD = 0, 2

# Left to right across the whole wordmark: the interface's own accent orange fading to
# the grey Synth One's wordmark used.
#
# **Both ends are sampled, not chosen.** `#E68800` is the orange that appears twelve
# times across the panels — the most-used accent in the UI — and `#DEE3E2` is the
# brightest ink in the wordmark this replaces. The first synthwave pass used magenta
# through cyan, which read as a different product bolted onto the header; the owner
# called the clash and asked for orange and grey instead.
#
# The midpoint is warm rather than a straight interpolation: orange and light grey
# lerped directly pass through a muddy brown whose luminance dips below both ends, and
# the ramp needs to climb evenly (146 → 174 → 226) or the middle of the word looks
# dirty.
GRADIENT = [(0.00, (0xE6, 0x88, 0x00)),    # accent orange, from the panels
            (0.55, (0xD9, 0xA9, 0x68)),    # warm tan, keeping the ramp monotonic
            (1.00, (0xDE, 0xE3, 0xE2))]    # the original wordmark's grey
GLOW = (0xE6, 0x88, 0x00)


def _lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def _gradient(size):
    """A horizontal gradient image of `size`."""
    width, height = size
    row = Image.new("RGB", (width, 1))
    px = row.load()
    for x in range(width):
        t = x / max(width - 1, 1)
        for i in range(len(GRADIENT) - 1):
            t0, c0 = GRADIENT[i]
            t1, c1 = GRADIENT[i + 1]
            if t0 <= t <= t1:
                px[x, 0] = _lerp(c0, c1, (t - t0) / (t1 - t0))
                break
        else:
            px[x, 0] = GRADIENT[-1][1]
    return row.resize((width, height), Image.NEAREST)


def _tracked(draw, xy, runs, tracking):
    """Draws `runs` of (text, font) with `tracking` px between glyphs. Returns width."""
    x, y = xy
    for text, font in runs:
        for character in text:
            if draw is not None:
                draw.text((x, y), character, font=font, fill=255)
            x += font.getlength(character) + tracking
    return x - xy[0] - tracking


def render(text_runs, cap_height, tracking, glow_radius=6, glow_gain=1.5, padding=24):
    """Renders a wordmark to an RGBA image, trimmed to its ink plus `padding`.

    `text_runs` is a list of (text, weight) where weight is MEDIUM or BOLD.
    `cap_height` is the target height of a capital letter, in pixels.
    """
    # Futura's cap height is ~0.70 em; solve for the point size that hits the target.
    probe = ImageFont.truetype(FUTURA, 100, index=BOLD)
    cap = probe.getbbox("H")[3] - probe.getbbox("H")[1]
    size = round(100 * cap_height / cap)
    runs = [(t, ImageFont.truetype(FUTURA, size, index=w)) for t, w in text_runs]

    width = round(_tracked(None, (0, 0), runs, tracking)) + padding * 2
    height = size * 2 + padding * 2

    mask = Image.new("L", (width, height), 0)
    _tracked(ImageDraw.Draw(mask), (padding, padding), runs, tracking)

    box = mask.getbbox()
    mask = mask.crop((box[0] - padding, box[1] - padding, box[2] + padding, box[3] + padding))

    out = Image.new("RGBA", mask.size, (0, 0, 0, 0))

    # Glow first, so the letterforms sit on top of their own halo.
    glow = mask.filter(ImageFilter.GaussianBlur(glow_radius)).point(
        lambda v: min(255, round(v * glow_gain)))
    out.paste(Image.new("RGBA", mask.size, GLOW + (255,)), (0, 0), glow)

    fill = _gradient(mask.size).convert("RGBA")
    out.paste(fill, (0, 0), mask)
    return out
