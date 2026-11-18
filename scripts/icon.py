"""Draws the desktop shortcut icon: a pen lying across a ruled page, blue LED on and an ink stroke.
Writes `pen.ico` (16 to 256 px) next to this script.

    python scripts/icon.py
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

T = 1024  # drawn large, then downscaled (anti-aliasing)
OUTPUT = Path(__file__).with_name("pen.ico")


def _rot(points, angle, cx, cy):
    a = math.radians(angle)
    c, s = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in points]


def draw() -> Image.Image:
    img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Notebook page: white rounded square, pale blue lines, red margin
    d.rounded_rectangle((60, 60, T - 60, T - 60), radius=120, fill=(250, 250, 247, 255),
                        outline=(200, 205, 215, 255), width=14)
    for y in range(250, T - 120, 130):
        d.line((130, y, T - 130, y), fill=(170, 195, 235, 255), width=12)
    d.line((240, 110, 240, T - 110), fill=(235, 120, 120, 255), width=10)

    # Blue ink stroke coming out of the tip (writing)
    ink = [(250 + i * 6, 760 + 40 * math.sin(i / 9)) for i in range(0, 60)]
    d.line(ink, fill=(30, 80, 200, 255), width=26, joint="curve")

    # Pen, drawn upright then rotated by 45° around the centre
    cx, cy = T / 2, T / 2
    L, l = 360, 70  # half length, half width of the body
    angle = 45
    body = [(cx - l, cy - L), (cx + l, cy - L), (cx + l, cy + L - 60), (cx - l, cy + L - 60)]
    cone = [(cx - l, cy + L - 60), (cx + l, cy + L - 60), (cx, cy + L + 110)]
    tip = [(cx - 18, cy + L + 70), (cx + 18, cy + L + 70), (cx, cy + L + 110)]
    ring = [(cx - l, cy - L + 90), (cx + l, cy - L + 90), (cx + l, cy - L + 150), (cx - l, cy - L + 150)]
    highlight = [(cx - l + 22, cy - L + 170), (cx - l + 44, cy - L + 170),
              (cx - l + 44, cy + L - 90), (cx - l + 22, cy + L - 90)]

    def poly(p, colour):
        d.polygon(_rot(p, angle, cx, cy), fill=colour)

    # drop shadow
    shadow = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon(_rot([(x + 30, y + 30) for x, y in body + cone[1:]], angle, cx, cy),
                                  fill=(0, 0, 0, 90))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(25)))
    d = ImageDraw.Draw(img)

    poly(body, (45, 50, 60, 255))           # graphite body
    poly(cone, (150, 155, 165, 255))         # metal cone
    poly(tip, (30, 80, 200, 255))         # inked tip
    poly(ring, (60, 140, 255, 255))         # blue LED on
    poly(highlight, (110, 118, 132, 255))       # body highlight

    # LED glow
    halo = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    ImageDraw.Draw(halo).polygon(_rot(ring, angle, cx, cy), fill=(80, 160, 255, 200))
    img.alpha_composite(halo.filter(ImageFilter.GaussianBlur(30)))
    d = ImageDraw.Draw(img)
    poly(ring, (90, 170, 255, 255))
    return img


if __name__ == "__main__":
    large = draw().resize((256, 256), Image.LANCZOS)
    large.save(OUTPUT, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    large.save(OUTPUT.with_suffix(".png"))
    print(f"Icon written: {OUTPUT}")
