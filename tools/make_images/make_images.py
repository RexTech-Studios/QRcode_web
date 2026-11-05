#!/usr/bin/env python3
"""Generates the landing page images from design-reference/product-design.png.

Run from the repo root:  python tools/make_images/make_images.py
Needs only Pillow. design-reference/ is not committed, the outputs are.
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, "design-reference", "product-design.png")
OUT = os.path.join(ROOT, "landing", "assets")
CREAM = (255, 253, 248)
MAX_BYTES = 200 * 1024


def flatten(path):
    source = Image.open(path).convert("RGBA")
    background = Image.new("RGBA", source.size, CREAM + (255,))
    background.alpha_composite(source)
    return background.convert("RGB")


def report(path):
    size = os.path.getsize(path)
    with Image.open(path) as image:
        print(f"{os.path.relpath(path, ROOT)}: {image.width}x{image.height}, {size // 1024} KB")
    if size > MAX_BYTES:
        raise SystemExit(f"{path} is over the {MAX_BYTES // 1024} KB limit")


def save_stand(source, width):
    height = round(source.height * width / source.width)
    resized = source.resize((width, height), Image.LANCZOS)

    webp = os.path.join(OUT, f"stand-{width}.webp")
    resized.save(webp, "WEBP", quality=86, method=6)
    report(webp)

    # A 128-colour palette keeps the fallback under budget. The artwork is a
    # handful of flat colours plus a gold gradient, so it survives well.
    png = os.path.join(OUT, f"stand-{width}.png")
    resized.quantize(colors=128, method=Image.MEDIANCUT, dither=Image.NONE).save(
        png, optimize=True
    )
    report(png)


def save_og_image(source):
    canvas = Image.new("RGB", (1200, 630), CREAM)
    height = 570
    width = round(source.width * height / source.height)
    stand = source.resize((width, height), Image.LANCZOS)
    left, top = (canvas.width - width) // 2, (canvas.height - height) // 2

    shadow = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(shadow).rectangle(
        [left, top + 10, left + width, top + height + 6], fill=46
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    canvas.paste((42, 35, 24), mask=shadow)
    canvas.paste(stand, (left, top))

    path = os.path.join(OUT, "og-image.png")
    canvas.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.NONE).save(
        path, optimize=True
    )
    report(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    source = flatten(SOURCE)
    save_stand(source, 600)
    save_stand(source, 1200)
    save_og_image(source)


if __name__ == "__main__":
    main()
