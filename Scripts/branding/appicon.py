#!/usr/bin/env python3
"""Renders the Arcade Ruins app icon (P5-4).

Replaces Synth One's icon — three grey waveforms and an orange smiley — which is that
app's own visual identity and not ours to ship.

The design is the synthwave horizon: a banded sun setting behind a perspective grid, in
the genre's magenta-to-cyan palette, with one waveform crossing the sky as a nod to what
the thing actually is. Drawn at 4x and downsampled, which is cheaper than antialiasing
by hand and gives clean edges at 20pt.
"""
from PIL import Image, ImageDraw, ImageFilter

S = 1024          # master size
SS = 4            # supersample factor
R = S * SS

SKY_TOP     = (0x1A, 0x0B, 0x2E)     # deep violet
SKY_HORIZON = (0x3B, 0x0F, 0x52)
SUN_TOP     = (0xFF, 0xE0, 0x57)     # yellow
SUN_MID     = (0xFF, 0x4E, 0x8A)     # magenta
SUN_BOT     = (0xB4, 0x2E, 0xC8)     # violet
GRID        = (0x3A, 0xE7, 0xFF)     # cyan
WAVE        = (0x8B, 0xF7, 0xFF)
GROUND      = (0x0B, 0x04, 0x18)

HORIZON = 0.62    # fraction of the height


def _lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def _vgrad(size, stops):
    """Vertical gradient. `stops` is [(t, rgb), ...] with t in [0,1]."""
    w, h = size
    col = Image.new("RGB", (1, h))
    px = col.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                px[0, y] = _lerp(c0, c1, (t - t0) / (t1 - t0))
                break
        else:
            px[0, y] = stops[-1][1]
    return col.resize((w, h), Image.NEAREST)


def render():
    horizon = round(R * HORIZON)

    img = Image.new("RGB", (R, R), SKY_TOP)
    img.paste(_vgrad((R, horizon), [(0, SKY_TOP), (1, SKY_HORIZON)]), (0, 0))
    img.paste(Image.new("RGB", (R, R - horizon), GROUND), (0, horizon))

    # --- The sun, clipped to the sky ------------------------------------------
    radius = round(R * 0.30)
    cx, cy = R // 2, horizon
    sun_box = (cx - radius, cy - radius, cx + radius, cy + radius)

    disc = Image.new("L", (R, R), 0)
    ImageDraw.Draw(disc).ellipse(sun_box, fill=255)

    # Bands: horizontal slits cut out of the disc, thin high up and widening as they
    # approach the horizon. Only the top half of the disc is visible — it is centred
    # *on* the horizon — so they are walked upward from the horizon, not down from the
    # top, or they all land in the half that gets clipped away.
    bands = ImageDraw.Draw(disc)
    y = cy - radius * 0.06
    slit = radius * 0.085
    while y > cy - radius * 0.72:
        bands.rectangle((0, round(y - slit), R, round(y)), fill=0)
        y -= slit * 2.5
        slit *= 0.72

    # Everything below the horizon is ground.
    bands.rectangle((0, horizon, R, R), fill=0)

    # The gradient is mapped to the disc's own box, not the canvas, so the yellow
    # really does land at the top of the sun.
    sun = Image.new("RGB", (R, R), SUN_BOT)
    sun.paste(_vgrad((R, radius * 2), [(0, SUN_TOP), (0.55, SUN_MID), (1, SUN_BOT)]),
              (0, cy - radius))
    img.paste(sun, (0, 0), disc)

    # Glow around the sun, added over the sky.
    glow = disc.filter(ImageFilter.GaussianBlur(R // 40)).point(lambda v: v // 3)
    img.paste(Image.new("RGB", (R, R), SUN_MID), (0, 0), glow)

    # --- Perspective grid on the ground ---------------------------------------
    grid = Image.new("RGBA", (R, R), (0, 0, 0, 0))
    g = ImageDraw.Draw(grid)
    line = max(2, R // 340)

    # Verticals converging on the vanishing point.
    for i in range(-4, 5):
        x_bottom = cx + i * R * 0.30
        g.line([(cx, horizon), (x_bottom, R)], fill=GRID + (190,), width=line)
    # Horizontals, spaced so they crowd toward the horizon.
    t = 0.055
    y = horizon
    while y < R:
        g.line([(0, y), (R, y)], fill=GRID + (215,), width=line)
        y += (R - horizon) * t
        t *= 1.55
    img.paste(Image.alpha_composite(
        Image.new("RGBA", (R, R), (0, 0, 0, 0)), grid).convert("RGB"),
        (0, 0), grid.split()[3])

    # --- One waveform across the sky ------------------------------------------
    wave = Image.new("RGBA", (R, R), (0, 0, 0, 0))
    w = ImageDraw.Draw(wave)
    amp = R * 0.055
    mid = round(R * 0.235)
    thickness = max(3, R // 150)
    points = []
    # A triangle wave, drawn as line segments — square-ish geometry reads better
    # small than a sine does.
    period = R * 0.26
    x = -period * 0.25
    up = True
    while x < R + period:
        points.append((x, mid - amp if up else mid + amp))
        up = not up
        x += period / 2
    w.line(points, fill=WAVE + (235,), width=thickness, joint="curve")
    wave = wave.filter(ImageFilter.GaussianBlur(R // 900))
    img.paste(wave.convert("RGB"), (0, 0), wave.split()[3])

    img = img.resize((S, S), Image.LANCZOS)

    # --- Rounded corners, matching the icon this replaces ---------------------
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = Image.new("L", (S * SS, S * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, S * SS - 1, S * SS - 1), radius=round(S * SS * 0.2237), fill=255)
    out.paste(img, (0, 0), mask.resize((S, S), Image.LANCZOS))
    return out


if __name__ == "__main__":
    render().save("/tmp/appicon_master.png")
    print("wrote /tmp/appicon_master.png")
