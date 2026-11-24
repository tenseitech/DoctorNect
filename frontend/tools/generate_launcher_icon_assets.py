#!/usr/bin/env python3
"""Build 1024x1024 launcher masters for flutter_launcher_icons (DoctorNect)."""
from __future__ import annotations

import os
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC_FG = ROOT / "assets/images/adaptive_foreground.png"
OUT_DIR = ROOT / "assets/icon"
SIZE = 1024
BRAND_BLUE = (0x1E, 0x3F, 0xC0)
# Android adaptive safe zone: center 66% of canvas (~17% inset per edge).
SAFE_FRAC = 0.66
# iOS full square: ~20% padding each side → logo fits in 60%.
IOS_FRAC = 0.60


def _logo_bbox(im: Image.Image) -> tuple[int, int, int, int]:
    alpha = im.getchannel("A")
    return alpha.getbbox() or (0, 0, im.width, im.height)


def _scale_to_fit(im: Image.Image, max_side: float) -> Image.Image:
    w, h = im.size
    scale = min(max_side / w, max_side / h)
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    if nw == w and nh == h:
        return im.copy()
    return im.resize((nw, nh), Image.Resampling.LANCZOS)


def _paste_center(canvas: Image.Image, piece: Image.Image) -> None:
    x = (canvas.width - piece.width) // 2
    y = (canvas.height - piece.height) // 2
    canvas.paste(piece, (x, y), piece)


def main() -> None:
    if not SRC_FG.is_file():
        raise SystemExit(f"Missing source logo: {SRC_FG}")

    src = Image.open(SRC_FG).convert("RGBA")
    box = _logo_bbox(src)
    logo = src.crop(box)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    safe_side = SIZE * SAFE_FRAC
    fg_logo = _scale_to_fit(logo, safe_side)
    foreground = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    _paste_center(foreground, fg_logo)
    foreground.save(OUT_DIR / "icon_foreground.png", optimize=True)

    # Themed / monochrome: white mark on transparent (alpha from logo).
    alpha = logo.getchannel("A")
    white = Image.new("L", logo.size, 255)
    mono_logo = Image.merge("RGBA", (white, white, white, alpha))
    mono_scaled = _scale_to_fit(mono_logo, safe_side)
    monochrome = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    _paste_center(monochrome, mono_scaled)
    monochrome.save(OUT_DIR / "icon_monochrome.png", optimize=True)

    ios_side = SIZE * IOS_FRAC
    ios_logo = _scale_to_fit(logo, ios_side)
    full = Image.new("RGB", (SIZE, SIZE), BRAND_BLUE)
    full_rgba = full.convert("RGBA")
    _paste_center(full_rgba, ios_logo)
    full_rgb = Image.new("RGB", (SIZE, SIZE), BRAND_BLUE)
    full_rgb.paste(full_rgba, mask=full_rgba.split()[3])
    full_rgb.save(OUT_DIR / "icon_full.png", optimize=True)

    print(f"Wrote {OUT_DIR}/icon_foreground.png, icon_monochrome.png, icon_full.png")


if __name__ == "__main__":
    main()