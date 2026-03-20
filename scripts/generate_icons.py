#!/usr/bin/env python3
"""Generate refined menu-bar microphone icons for OhMyVoice.

Produces 4 states × 2 resolutions = 8 PNG files in ``resources/icons/``.

Visual language:
  idle       — monochrome template icon with a lighter outline body
  recording  — warm red filled microphone
  processing — cool blue filled microphone
  done       — muted green filled microphone

Sizes: @1x = 18×18, @2x = 36×36.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ICON_DIR = Path(__file__).resolve().parent.parent / "resources" / "icons"
BASE_SIZE = 18
SUPERSAMPLE = 4
TRANSPARENT = (0, 0, 0, 0)

BLACK = (0, 0, 0, 255)
RECORDING_RED = (0xD9, 0x4B, 0x45, 255)
PROCESSING_BLUE = (0x4A, 0x7C, 0xF3, 255)
DONE_GREEN = (0x3F, 0xA3, 0x6B, 255)


def _scaled(size: int, *values: float) -> list[float]:
    factor = size / BASE_SIZE
    return [value * factor for value in values]


def _rounded_rect(
    draw: ImageDraw.ImageDraw,
    xy: tuple[float, float, float, float],
    radius: float,
    fill: tuple[int, int, int, int],
) -> None:
    if hasattr(draw, "rounded_rectangle"):
        draw.rounded_rectangle(xy, radius=radius, fill=fill)
        return

    x0, y0, x1, y1 = xy
    r = min(radius, (x1 - x0) / 2, (y1 - y0) / 2)
    draw.rectangle([x0 + r, y0, x1 - r, y1], fill=fill)
    draw.rectangle([x0, y0 + r, x1, y1 - r], fill=fill)
    draw.pieslice([x0, y0, x0 + 2 * r, y0 + 2 * r], 180, 270, fill=fill)
    draw.pieslice([x1 - 2 * r, y0, x1, y0 + 2 * r], 270, 360, fill=fill)
    draw.pieslice([x0, y1 - 2 * r, x0 + 2 * r, y1], 90, 180, fill=fill)
    draw.pieslice([x1 - 2 * r, y1 - 2 * r, x1, y1], 0, 90, fill=fill)


def _new_supersampled_canvas(size: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new(
        "RGBA",
        (size * SUPERSAMPLE, size * SUPERSAMPLE),
        TRANSPARENT,
    )
    return image, ImageDraw.Draw(image)


def _downsample(canvas: Image.Image, size: int) -> Image.Image:
    return canvas.resize((size, size), Image.LANCZOS)


def _draw_body(
    draw: ImageDraw.ImageDraw,
    size: int,
    color: tuple[int, int, int, int],
    filled: bool,
) -> None:
    x0, y0, x1, y1 = _scaled(size, 5.25, 1.5, 12.75, 9.75)
    radius = _scaled(size, 3.75)[0]
    if filled:
        _rounded_rect(draw, (x0, y0, x1, y1), radius, color)
        return

    inset = _scaled(size, 1.75)[0]
    _rounded_rect(draw, (x0, y0, x1, y1), radius, color)
    _rounded_rect(
        draw,
        (x0 + inset, y0 + inset, x1 - inset, y1 - inset),
        max(radius - inset, 0),
        TRANSPARENT,
    )


def _draw_support(
    draw: ImageDraw.ImageDraw,
    size: int,
    color: tuple[int, int, int, int],
) -> None:
    left_leg = tuple(_scaled(size, 4.75, 7.75, 6.25, 11.75))
    right_leg = tuple(_scaled(size, 11.75, 7.75, 13.25, 11.75))
    bridge = tuple(_scaled(size, 6.0, 10.75, 12.0, 12.25))
    stem = tuple(_scaled(size, 8.0, 12.0, 10.0, 14.5))
    base = tuple(_scaled(size, 6.5, 14.5, 11.5, 16.0))

    radius = _scaled(size, 0.75)[0]
    for rect in (left_leg, right_leg, bridge, stem, base):
        _rounded_rect(draw, rect, radius, color)


def _draw_icon(
    size: int,
    color: tuple[int, int, int, int],
    filled_body: bool,
) -> Image.Image:
    canvas, draw = _new_supersampled_canvas(size)
    scaled_size = size * SUPERSAMPLE
    scaled_color = color

    _draw_body(draw, scaled_size, scaled_color, filled_body)
    _draw_support(draw, scaled_size, scaled_color)

    return _downsample(canvas, size)


def generate_icon(state: str, size: int) -> Image.Image:
    if state == "idle":
        return _draw_icon(size, BLACK, filled_body=False)
    if state == "recording":
        return _draw_icon(size, RECORDING_RED, filled_body=True)
    if state == "processing":
        return _draw_icon(size, PROCESSING_BLUE, filled_body=True)
    if state == "done":
        return _draw_icon(size, DONE_GREEN, filled_body=True)
    raise ValueError(f"Unknown state: {state}")


def main() -> None:
    ICON_DIR.mkdir(parents=True, exist_ok=True)

    states = ["idle", "recording", "processing", "done"]
    sizes = {"": 18, "@2x": 36}

    for state in states:
        for suffix, size in sizes.items():
            icon = generate_icon(state, size)
            path = ICON_DIR / f"mic_{state}{suffix}.png"
            icon.save(path)
            print(f"{path.name:22s} {icon.size[0]}x{icon.size[1]}")

    print(f"\nSaved icons to {ICON_DIR}")


if __name__ == "__main__":
    main()
