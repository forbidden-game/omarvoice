#!/usr/bin/env python3
"""Generate macOS app icon (.icns) for OhMyVoice.

Produces a 1024x1024 master PNG, creates an .iconset with all required
sizes, converts to .icns via iconutil, and cleans up.

Design: macOS squircle background with a teal-to-indigo gradient,
white filled microphone silhouette with subtle shadow for depth.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

RESOURCES = Path(__file__).resolve().parent.parent / "resources"
ICONSET_DIR = RESOURCES / "AppIcon.iconset"
ICNS_PATH = RESOURCES / "AppIcon.icns"

# Master canvas size
SIZE = 1024

# Gradient colors — warm teal top to deep indigo bottom
COLOR_TOP = (78, 205, 196)      # #4ECDC4
COLOR_BOTTOM = (72, 52, 212)    # #4834D4

# Microphone color
WHITE = (255, 255, 255, 255)
SHADOW_COLOR = (0, 0, 0, 50)

# macOS squircle corner radius ≈ 22.37% of icon size
CORNER_RATIO = 0.2237


def _lerp_color(
    c1: tuple[int, int, int],
    c2: tuple[int, int, int],
    t: float,
) -> tuple[int, int, int]:
    """Linear interpolate between two RGB colors."""
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))  # type: ignore[return-value]


def _draw_squircle_mask(size: int) -> Image.Image:
    """Create an alpha mask approximating the macOS squircle.

    Uses a rounded rectangle with the standard corner radius, drawn at
    4x then downsampled for smooth anti-aliased edges.
    """
    ss = 4
    big = Image.new("L", (size * ss, size * ss), 0)
    draw = ImageDraw.Draw(big)
    radius = size * CORNER_RATIO * ss
    # Slight inset so the edges don't clip
    inset = size * 0.02 * ss
    draw.rounded_rectangle(
        [inset, inset, size * ss - inset, size * ss - inset],
        radius=radius,
        fill=255,
    )
    return big.resize((size, size), Image.LANCZOS)


def _draw_gradient(size: int) -> Image.Image:
    """Create a top-to-bottom linear gradient image."""
    img = Image.new("RGB", (size, size))
    pixels = img.load()
    for y in range(size):
        t = y / (size - 1)
        color = _lerp_color(COLOR_TOP, COLOR_BOTTOM, t)
        for x in range(size):
            pixels[x, y] = color
    return img


def _draw_microphone(size: int) -> Image.Image:
    """Draw a filled white microphone silhouette at the given size.

    The mic consists of:
      - Capsule body (rounded rectangle, filled)
      - Cradle arc (thick arc under the body)
      - Vertical stem
      - Horizontal base
    """
    ss = 4  # supersample factor
    big = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(big)
    s = size  # shorthand for proportions

    # --- Capsule body ---
    body_w = s * 0.28
    body_h = s * 0.38
    body_x0 = (s - body_w) / 2
    body_y0 = s * 0.14
    body_x1 = body_x0 + body_w
    body_y1 = body_y0 + body_h
    body_r = body_w / 2  # fully rounded ends

    draw.rounded_rectangle(
        [body_x0 * ss, body_y0 * ss, body_x1 * ss, body_y1 * ss],
        radius=body_r * ss,
        fill=WHITE,
    )

    # --- Cradle arc ---
    cradle_w = s * 0.40
    cradle_h = s * 0.30
    cradle_x0 = (s - cradle_w) / 2
    cradle_y0 = body_y0 + body_h * 0.35
    cradle_x1 = cradle_x0 + cradle_w
    cradle_y1 = cradle_y0 + cradle_h

    stroke = s * 0.040
    draw.arc(
        [cradle_x0 * ss, cradle_y0 * ss, cradle_x1 * ss, cradle_y1 * ss],
        start=0,
        end=180,
        fill=WHITE,
        width=max(1, round(stroke * ss)),
    )

    # --- Stem ---
    stem_x = s / 2
    stem_top_y = cradle_y1 - stroke / 2
    stem_bot_y = s * 0.74

    draw.line(
        [stem_x * ss, stem_top_y * ss, stem_x * ss, stem_bot_y * ss],
        fill=WHITE,
        width=max(1, round(stroke * ss)),
    )

    # --- Base ---
    base_w = s * 0.22
    base_x0 = (s - base_w) / 2
    base_x1 = base_x0 + base_w
    base_y = stem_bot_y

    draw.line(
        [base_x0 * ss, base_y * ss, base_x1 * ss, base_y * ss],
        fill=WHITE,
        width=max(1, round(stroke * ss)),
    )

    # Downsample
    return big.resize((size, size), Image.LANCZOS)


def generate_master(size: int = SIZE) -> Image.Image:
    """Compose the full app icon at the given size."""
    # Background gradient
    gradient = _draw_gradient(size)

    # Squircle mask
    mask = _draw_squircle_mask(size)

    # Apply mask to gradient
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gradient_rgba = gradient.convert("RGBA")
    icon.paste(gradient_rgba, (0, 0), mask)

    # Add a subtle inner highlight at the top for depth
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hl_draw = ImageDraw.Draw(highlight)
    # Soft white ellipse near the top
    hl_w = size * 0.7
    hl_h = size * 0.35
    hl_x0 = (size - hl_w) / 2
    hl_y0 = size * 0.02
    hl_draw.ellipse(
        [hl_x0, hl_y0, hl_x0 + hl_w, hl_y0 + hl_h],
        fill=(255, 255, 255, 30),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(radius=size * 0.08))
    # Clip highlight to squircle
    hl_mask_arr = highlight.split()[3]
    # Combine with squircle mask
    from PIL import ImageChops
    clipped_alpha = ImageChops.multiply(hl_mask_arr, mask)
    highlight.putalpha(clipped_alpha)
    icon = Image.alpha_composite(icon, highlight)

    # Microphone shadow (offset down-right, blurred)
    mic = _draw_microphone(size)
    shadow_offset = int(size * 0.008)
    shadow_blur = size * 0.015

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # Extract mic alpha, tint it dark
    mic_alpha = mic.split()[3]
    shadow_layer = Image.new("RGBA", (size, size), SHADOW_COLOR)
    shadow_layer.putalpha(mic_alpha)
    shadow.paste(shadow_layer, (shadow_offset, shadow_offset), shadow_layer)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=shadow_blur))
    # Clip shadow to squircle
    shadow_alpha = shadow.split()[3]
    clipped_shadow = ImageChops.multiply(shadow_alpha, mask)
    shadow.putalpha(clipped_shadow)
    icon = Image.alpha_composite(icon, shadow)

    # Microphone foreground
    icon = Image.alpha_composite(icon, mic)

    return icon


def create_iconset(master: Image.Image) -> None:
    """Create the .iconset directory with all required sizes."""
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)

    # (filename, pixel_size)
    entries = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for name, px in entries:
        resized = master.resize((px, px), Image.LANCZOS)
        path = ICONSET_DIR / name
        resized.save(path, "PNG")
        print(f"  {name:30s}  {px}x{px}")


def build_icns() -> None:
    """Run iconutil to convert .iconset to .icns."""
    cmd = [
        "iconutil",
        "-c", "icns",
        str(ICONSET_DIR),
        "-o", str(ICNS_PATH),
    ]
    subprocess.run(cmd, check=True)
    print(f"\nCreated {ICNS_PATH}")


def cleanup() -> None:
    """Remove the .iconset directory."""
    if ICONSET_DIR.exists():
        shutil.rmtree(ICONSET_DIR)
        print(f"Cleaned up {ICONSET_DIR}")


def main() -> None:
    print("Generating 1024x1024 master icon...")
    master = generate_master()

    print("Creating iconset...")
    create_iconset(master)

    print("Building .icns...")
    build_icns()

    cleanup()
    print("Done.")


if __name__ == "__main__":
    main()
