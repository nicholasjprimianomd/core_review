"""Generate favicon and app icons from the source hero image.

Crops the squircle icon from the generated hero image (removes white padding),
then writes the standard Flutter web icon sizes.
"""

from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(
    os.environ.get(
        "ICON_SOURCE",
        str(ROOT.parent / ".cursor/projects/c-Users-nprim-core-review/assets/core-review-icon-dark-512.png"),
    )
)
WEB = ROOT / "web"
ICONS = WEB / "icons"


def _logo_center(im: Image.Image) -> tuple[int, int, int, int]:
    """Return bounding box of the bright teal logo region."""
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    minx, miny, maxx, maxy = w, h, 0, 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y]
            if g > 120 and b > 140 and r < g:
                if x < minx:
                    minx = x
                if y < miny:
                    miny = y
                if x > maxx:
                    maxx = x
                if y > maxy:
                    maxy = y
    return minx, miny, maxx, maxy


def crop_square_around_logo(im: Image.Image, padding_ratio: float = 0.32) -> Image.Image:
    """Center-crop a square around the detected logo, with generous padding."""
    w, h = im.size
    minx, miny, maxx, maxy = _logo_center(im)
    if maxx <= minx or maxy <= miny:
        side = min(w, h)
        left = (w - side) // 2
        top = (h - side) // 2
        return im.crop((left, top, left + side, top + side))
    cx = (minx + maxx) // 2
    cy = (miny + maxy) // 2
    logo_w = maxx - minx
    logo_h = maxy - miny
    side = int(max(logo_w, logo_h) * (1 + padding_ratio * 2))
    side = max(side, min(w, h) // 2)
    side = min(side, min(w, h))
    left = max(0, min(w - side, cx - side // 2))
    top = max(0, min(h - side, cy - side // 2))
    return im.crop((left, top, left + side, top + side))


def rounded_mask(size: int, radius_ratio: float = 0.22) -> Image.Image:
    r = int(size * radius_ratio)
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    return mask


def maskable(im: Image.Image, padding_ratio: float = 0.12) -> Image.Image:
    """Create a maskable-safe version: center content within safe zone, solid bg."""
    size = im.size[0]
    bg_color = im.getpixel((size // 2, 4))
    canvas = Image.new("RGB", (size, size), bg_color)
    inner = int(size * (1 - 2 * padding_ratio))
    resized = im.resize((inner, inner), Image.LANCZOS)
    canvas.paste(resized, ((size - inner) // 2, (size - inner) // 2))
    return canvas


def main() -> None:
    im = Image.open(SRC).convert("RGB")
    im = crop_square_around_logo(im)
    base = im.resize((1024, 1024), Image.LANCZOS)

    sizes = {
        WEB / "favicon.png": 64,
        ICONS / "Icon-192.png": 192,
        ICONS / "Icon-512.png": 512,
    }
    for path, s in sizes.items():
        img = base.resize((s, s), Image.LANCZOS)
        mask = rounded_mask(s, 0.22)
        out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        out.paste(img, (0, 0), mask)
        out.save(path, format="PNG", optimize=True)
        print(f"wrote {path} ({s}x{s})")

    for path, s in [
        (ICONS / "Icon-maskable-192.png", 192),
        (ICONS / "Icon-maskable-512.png", 512),
    ]:
        img = base.resize((s, s), Image.LANCZOS)
        m = maskable(img)
        m.save(path, format="PNG", optimize=True)
        print(f"wrote {path} ({s}x{s}) maskable")


if __name__ == "__main__":
    main()
