#!/usr/bin/env python3
"""Generate menu-bar microphone icons for OhMyVoice.

Produces 4 states × 2 resolutions = 8 PNG files in resources/icons/.

States:
  idle       — pure black on transparent (macOS template image)
  recording  — red (#FF3B30) with recording dot
  processing — purple (#AF52DE) with processing indicator
  done       — green (#34C759) with checkmark indicator

Sizes: @1x = 18×18, @2x = 36×36.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ICON_DIR = Path(__file__).resolve().parent.parent / "resources" / "icons"

# Colors
BLACK = (0, 0, 0, 255)
RED = (0xFF, 0x3B, 0x30, 255)
PURPLE = (0xAF, 0x52, 0xDE, 255)
GREEN = (0x34, 0xC7, 0x59, 255)
TRANSPARENT = (0, 0, 0, 0)


def _draw_rounded_rect(
    draw: ImageDraw.ImageDraw,
    xy: tuple[float, float, float, float],
    radius: float,
    fill: tuple[int, int, int, int],
):
    """Draw a filled rounded rectangle (compatible with older Pillow too)."""
    x0, y0, x1, y1 = xy
    r = min(radius, (x1 - x0) / 2, (y1 - y0) / 2)
    # Use built-in rounded_rectangle if available (Pillow ≥ 9.0)
    if hasattr(draw, "rounded_rectangle"):
        draw.rounded_rectangle(xy, radius=r, fill=fill)
    else:
        # Fallback: rectangles + circles at corners
        draw.rectangle([x0 + r, y0, x1 - r, y1], fill=fill)
        draw.rectangle([x0, y0 + r, x1, y1 - r], fill=fill)
        draw.pieslice([x0, y0, x0 + 2 * r, y0 + 2 * r], 180, 270, fill=fill)
        draw.pieslice([x1 - 2 * r, y0, x1, y0 + 2 * r], 270, 360, fill=fill)
        draw.pieslice([x0, y1 - 2 * r, x0 + 2 * r, y1], 90, 180, fill=fill)
        draw.pieslice([x1 - 2 * r, y1 - 2 * r, x1, y1], 0, 90, fill=fill)


def _draw_mic(
    img: Image.Image,
    color: tuple[int, int, int, int],
    size: int,
) -> None:
    """Draw a microphone outline centered in *img*.

    The mic is drawn as:
      - Rounded-rect body (the capsule)
      - Small gap
      - Curved cradle arc beneath the body
      - Vertical stem from the arc down
      - Horizontal base line
    """
    draw = ImageDraw.Draw(img)
    s = size  # shorthand

    # --- Proportions (all relative to size) ---
    # We use a supersampled coordinate space: draw at 4× then downsample for AA.
    # But Pillow's anti-alias on line/arc is limited, so we supersample the whole
    # image externally. Here we just draw at the target resolution and rely on
    # Pillow's built-in AA where possible.

    stroke = max(1.5, s / 12)  # line thickness

    # Mic body (capsule) — centered horizontally
    body_w = s * 0.38
    body_h = s * 0.48
    body_x0 = (s - body_w) / 2
    body_y0 = s * 0.06
    body_x1 = body_x0 + body_w
    body_y1 = body_y0 + body_h
    body_r = body_w / 2  # fully rounded top/bottom → capsule

    # Cradle arc
    cradle_w = s * 0.52
    cradle_x0 = (s - cradle_w) / 2
    cradle_y0 = body_y0 + body_h * 0.28  # overlaps lower portion of body
    cradle_x1 = cradle_x0 + cradle_w
    cradle_y1 = body_y1 + s * 0.12

    # Stem
    stem_x = s / 2
    stem_top = cradle_y1 - stroke / 2
    stem_bot = s * 0.82

    # Base
    base_w = s * 0.28
    base_x0 = (s - base_w) / 2
    base_x1 = base_x0 + base_w
    base_y = stem_bot

    # --- Supersampled drawing ---
    ss = 4  # supersample factor
    big = Image.new("RGBA", (s * ss, s * ss), TRANSPARENT)
    bd = ImageDraw.Draw(big)

    def sc(*vals: float) -> list[float]:
        return [v * ss for v in vals]

    # Mic body — filled rounded rect then hollow out interior
    outer = sc(body_x0, body_y0, body_x1, body_y1)
    inner_inset = stroke
    inner = sc(
        body_x0 + inner_inset,
        body_y0 + inner_inset,
        body_x1 - inner_inset,
        body_y1 - inner_inset,
    )
    _draw_rounded_rect(bd, outer, body_r * ss, fill=color)
    _draw_rounded_rect(
        bd, inner, max(0, (body_r - inner_inset) * ss), fill=TRANSPARENT
    )

    # Cradle arc — draw as thick arc
    arc_bbox = sc(cradle_x0, cradle_y0, cradle_x1, cradle_y1)
    sw = stroke * ss
    bd.arc(arc_bbox, start=0, end=180, fill=color, width=max(1, round(sw)))

    # Stem
    stem_coords = sc(stem_x, stem_top, stem_x, stem_bot)
    bd.line(stem_coords, fill=color, width=max(1, round(sw)))

    # Base
    base_coords = sc(base_x0, base_y, base_x1, base_y)
    bd.line(base_coords, fill=color, width=max(1, round(sw)))

    # Downsample with LANCZOS for anti-aliasing
    small = big.resize((s, s), Image.LANCZOS)
    img.paste(small, (0, 0), small)


def _draw_recording_dot(
    img: Image.Image,
    size: int,
) -> None:
    """Small red dot at top-right of the icon to indicate recording."""
    ss = 4
    big = Image.new("RGBA", (size * ss, size * ss), TRANSPARENT)
    bd = ImageDraw.Draw(big)

    dot_r = size * 0.12
    cx = size * 0.78
    cy = size * 0.16
    bbox = [(cx - dot_r) * ss, (cy - dot_r) * ss, (cx + dot_r) * ss, (cy + dot_r) * ss]
    bd.ellipse(bbox, fill=RED)

    small = big.resize((size, size), Image.LANCZOS)
    img.paste(small, (0, 0), small)


def _draw_processing_dots(
    img: Image.Image,
    color: tuple[int, int, int, int],
    size: int,
) -> None:
    """Three small dots below the mic to hint at processing."""
    ss = 4
    big = Image.new("RGBA", (size * ss, size * ss), TRANSPARENT)
    bd = ImageDraw.Draw(big)

    dot_r = size * 0.055
    cy = size * 0.93
    spacing = size * 0.14
    cx_center = size / 2
    for offset in (-spacing, 0, spacing):
        cx = cx_center + offset
        bbox = [
            (cx - dot_r) * ss,
            (cy - dot_r) * ss,
            (cx + dot_r) * ss,
            (cy + dot_r) * ss,
        ]
        bd.ellipse(bbox, fill=color)

    small = big.resize((size, size), Image.LANCZOS)
    img.paste(small, (0, 0), small)


def _draw_checkmark(
    img: Image.Image,
    color: tuple[int, int, int, int],
    size: int,
) -> None:
    """Small checkmark at bottom-right of the icon."""
    ss = 4
    big = Image.new("RGBA", (size * ss, size * ss), TRANSPARENT)
    bd = ImageDraw.Draw(big)

    sw = max(1, round(size / 10 * ss))
    # Checkmark anchored at bottom-right area
    x0 = size * 0.62
    y0 = size * 0.68
    x1 = size * 0.74
    y1 = size * 0.82
    x2 = size * 0.92
    y2 = size * 0.58
    points = [(x0 * ss, y0 * ss), (x1 * ss, y1 * ss), (x2 * ss, y2 * ss)]
    bd.line(points, fill=color, width=sw, joint="curve")

    small = big.resize((size, size), Image.LANCZOS)
    img.paste(small, (0, 0), small)


def generate_icon(
    state: str,
    size: int,
) -> Image.Image:
    """Return an RGBA Image for the given state and pixel size."""
    img = Image.new("RGBA", (size, size), TRANSPARENT)

    if state == "idle":
        _draw_mic(img, BLACK, size)
    elif state == "recording":
        _draw_mic(img, RED, size)
        _draw_recording_dot(img, size)
    elif state == "processing":
        _draw_mic(img, PURPLE, size)
        _draw_processing_dots(img, PURPLE, size)
    elif state == "done":
        _draw_mic(img, GREEN, size)
        _draw_checkmark(img, GREEN, size)
    else:
        raise ValueError(f"Unknown state: {state}")

    return img


def main() -> None:
    ICON_DIR.mkdir(parents=True, exist_ok=True)

    states = ["idle", "recording", "processing", "done"]
    sizes = {"": 18, "@2x": 36}

    for state in states:
        for suffix, px in sizes.items():
            icon = generate_icon(state, px)
            name = f"mic_{state}{suffix}.png"
            path = ICON_DIR / name
            icon.save(path)
            print(f"  {name:30s}  {icon.size}  {icon.mode}")

    print(f"\nAll icons saved to {ICON_DIR}")


if __name__ == "__main__":
    main()
