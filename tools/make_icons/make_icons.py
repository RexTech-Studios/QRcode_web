#!/usr/bin/env python3
"""Generates the Full Star QR gold-star icon set.

Run from the repo root:  python tools/make_icons/make_icons.py
Needs only Pillow. The SVG and the PNGs are drawn from the same geometry below.
"""
import math
import os

from PIL import Image, ImageDraw

SIZE = 512
CORNER_RADIUS = 112
STOPS = [(0.0, "#D4AB6B"), (0.5, "#C69C5D"), (1.0, "#8B6A3A")]
STAR_COLOR = "#FFFDF8"

# The star is a sharp polygon stroked with round joins, which rounds its tips.
# Tip radius plus half the stroke gives the requested outer radius of 170.
STAR_TIP_RADIUS = 150
STAR_INNER_RATIO = 0.48
STAR_STROKE = 40

# Rendered large, then scaled down, because Pillow's shapes aren't antialiased.
SUPERSAMPLE = 2048

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def star_points():
    """Star vertices in 512-space, centred by bounding box rather than by the
    circle it sits on, since a star with a tip up otherwise looks too high."""
    drop = (STAR_TIP_RADIUS - STAR_TIP_RADIUS * math.cos(math.radians(36))) / 2
    centre_x, centre_y = SIZE / 2, SIZE / 2 + drop
    points = []
    for i in range(10):
        radius = STAR_TIP_RADIUS if i % 2 == 0 else STAR_TIP_RADIUS * STAR_INNER_RATIO
        angle = math.radians(-90 + i * 36)
        points.append(
            (centre_x + radius * math.cos(angle), centre_y + radius * math.sin(angle))
        )
    return points


def hex_to_rgb(value):
    return tuple(int(value[i : i + 2], 16) for i in (1, 3, 5))


def gradient_color(t):
    for (start, start_hex), (end, end_hex) in zip(STOPS, STOPS[1:]):
        if t <= end:
            mix = (t - start) / (end - start)
            first, second = hex_to_rgb(start_hex), hex_to_rgb(end_hex)
            return tuple(round(a + (b - a) * mix) for a, b in zip(first, second))
    return hex_to_rgb(STOPS[-1][1])


def diagonal_gradient(size):
    small = Image.new("RGB", (256, 256))
    pixels = small.load()
    for y in range(256):
        for x in range(256):
            pixels[x, y] = gradient_color((x + y) / 510)
    return small.resize((size, size), Image.BICUBIC)


def draw_star(image):
    scale = image.width / SIZE
    points = [(x * scale, y * scale) for x, y in star_points()]
    draw = ImageDraw.Draw(image)
    color = hex_to_rgb(STAR_COLOR)
    stroke = STAR_STROKE * scale

    draw.polygon(points, fill=color)
    for start, end in zip(points, points[1:] + points[:1]):
        draw.line([start, end], fill=color, width=round(stroke))
    half = stroke / 2
    for x, y in points:
        draw.ellipse([x - half, y - half, x + half, y + half], fill=color)


def master(rounded):
    image = diagonal_gradient(SUPERSAMPLE)
    draw_star(image)
    if not rounded:
        return image.convert("RGBA")

    mask = Image.new("L", image.size, 0)
    radius = CORNER_RADIUS * SUPERSAMPLE / SIZE
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, SUPERSAMPLE - 1, SUPERSAMPLE - 1], radius=radius, fill=255
    )
    rgba = image.convert("RGBA")
    rgba.putalpha(mask)
    return rgba


def svg():
    path = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in star_points()) + " Z"
    stops = "".join(
        f'<stop offset="{offset}" stop-color="{color}"/>' for offset, color in STOPS
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}">'
        f'<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">{stops}</linearGradient></defs>'
        f'<rect width="{SIZE}" height="{SIZE}" rx="{CORNER_RADIUS}" fill="url(#g)"/>'
        f'<path d="{path}" fill="{STAR_COLOR}" stroke="{STAR_COLOR}" '
        f'stroke-width="{STAR_STROKE}" stroke-linejoin="round"/>'
        "</svg>\n"
    )


def save_png(image, size, relative_path):
    path = os.path.join(ROOT, relative_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.resize((size, size), Image.LANCZOS).save(path, optimize=True)
    print(f"{relative_path}: {size}x{size}")


def main():
    rounded = master(rounded=True)
    full_bleed = master(rounded=False)

    save_png(rounded, 64, "web/favicon.png")
    save_png(rounded, 192, "web/icons/Icon-192.png")
    save_png(rounded, 512, "web/icons/Icon-512.png")
    save_png(full_bleed, 192, "web/icons/Icon-maskable-192.png")
    save_png(full_bleed, 512, "web/icons/Icon-maskable-512.png")
    # iOS masks this itself and shows black behind any transparent corners.
    save_png(full_bleed.convert("RGB"), 180, "landing/apple-touch-icon.png")

    ico_path = os.path.join(ROOT, "landing/favicon.ico")
    os.makedirs(os.path.dirname(ico_path), exist_ok=True)
    rounded.resize((256, 256), Image.LANCZOS).save(
        ico_path, sizes=[(16, 16), (32, 32), (48, 48)]
    )
    print("landing/favicon.ico: 16x16, 32x32, 48x48")

    with open(os.path.join(ROOT, "landing/favicon.svg"), "w", encoding="utf-8") as file:
        file.write(svg())
    print(f"landing/favicon.svg: viewBox {SIZE}x{SIZE}")


if __name__ == "__main__":
    main()
