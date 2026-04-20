#!/usr/bin/env python3
"""
Regenerate Assets.xcassets/AppIcon.appiconset from a source PNG:
- Trim near-black outer border (screenshot frame)
- Tighten to visible artwork (not flat white)
- Aspect-fill to 1024×1024 (fills square like a typical macOS icon)
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image


def trim_black_frame(im: Image.Image, black_thresh: int = 50, row_frac: float = 0.35) -> Image.Image:
    """Remove rows/cols at edges that are mostly near-black (the thick outline)."""
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = rgb.load()

    def row_black_frac(y: int) -> float:
        black = 0
        for x in range(w):
            r, g, b = px[x, y]
            if (r + g + b) / 3 < black_thresh:
                black += 1
        return black / max(w, 1)

    def col_black_frac(x: int) -> float:
        black = 0
        for y in range(h):
            r, g, b = px[x, y]
            if (r + g + b) / 3 < black_thresh:
                black += 1
        return black / max(h, 1)

    t = 0
    while t < h and row_black_frac(t) >= row_frac:
        t += 1
    b = h - 1
    while b > t and row_black_frac(b) >= row_frac:
        b -= 1
    l = 0
    while l < w and col_black_frac(l) >= row_frac:
        l += 1
    r = w - 1
    while r > l and col_black_frac(r) >= row_frac:
        r -= 1
    if r <= l or b <= t:
        return im
    return im.crop((l, t, r + 1, b + 1))


def tight_artwork_bbox(im: Image.Image) -> Image.Image:
    """Crop to content: exclude flat white margins inside the card."""
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    x0, y0 = w, h
    x1, y1 = -1, -1
    for yy in range(h):
        for xx in range(w):
            r, g, b = px[xx, yy]
            mx = max(r, g, b)
            mn = min(r, g, b)
            sat = (mx - mn) / (mx + 1e-6)
            not_white = (r < 248) or (g < 248) or (b < 248)
            if not_white and (sat > 0.06 or mx < 245):
                if xx < x0:
                    x0 = xx
                if xx > x1:
                    x1 = xx
                if yy < y0:
                    y0 = yy
                if yy > y1:
                    y1 = yy
    if x1 < x0 or y1 < y0:
        return im
    pad = int(max(x1 - x0, y1 - y0) * 0.03) + 2
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(w - 1, x1 + pad)
    y1 = min(h - 1, y1 + pad)
    return im.crop((x0, y0, x1 + 1, y1 + 1))


def cover_square(im: Image.Image, size: int = 1024) -> Image.Image:
    """Scale up so the shorter side becomes `size`, then center-crop square."""
    w, h = im.size
    scale = size / min(w, h)
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    im2 = im.resize((nw, nh), Image.Resampling.LANCZOS)
    left = (nw - size) // 2
    top = (nh - size) // 2
    return im2.crop((left, top, left + size, top + size))


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if source is None or not source.is_file():
        print("Usage: generate_app_icon.py <source.png>", file=sys.stderr)
        return 1

    out_dir = repo / "Assets.xcassets" / "AppIcon.appiconset"
    out_dir.mkdir(parents=True, exist_ok=True)

    im = Image.open(source).convert("RGBA")
    im = trim_black_frame(im)
    im = tight_artwork_bbox(im)
    square = cover_square(im, 1024)
    if square.mode == "RGBA":
        bg = Image.new("RGB", square.size, (255, 255, 255))
        bg.paste(square, mask=square.split()[3])
        square = bg
    else:
        square = square.convert("RGB")
    master = out_dir / "_master1024.png"
    square.save(master, "PNG")

    sizes = [
        ("icon_16x16.png", 16, 16),
        ("icon_16x16@2x.png", 32, 32),
        ("icon_32x32.png", 32, 32),
        ("icon_32x32@2x.png", 64, 64),
        ("icon_128x128.png", 128, 128),
        ("icon_128x128@2x.png", 256, 256),
        ("icon_256x256.png", 256, 256),
        ("icon_256x256@2x.png", 512, 512),
        ("icon_512x512.png", 512, 512),
        ("icon_512x512@2x.png", 1024, 1024),
    ]
    for name, height, width in sizes:
        dest = out_dir / name
        subprocess.run(
            ["sips", "-z", str(height), str(width), str(master), "--out", str(dest)],
            check=True,
            capture_output=True,
        )
    master.unlink(missing_ok=True)
    print(f"Wrote {len(sizes)} icons to {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
