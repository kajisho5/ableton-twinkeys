#!/usr/bin/env python3
"""Makes the MSIX logo PNGs (src/TwinKeys.App/Assets) from windows/assets-src/TwinKeys-windows.svg.

The files are committed; run this again only when the icon changes:
    python3 windows/scripts/make-msix-assets.py
Needs rsvg-convert (librsvg) and Pillow.

Names and sizes follow "App icons and logos" for packaged apps
(https://learn.microsoft.com/windows/apps/design/iconography/app-icon-construction):
a plain name is the scale-100 image, ".scale-200" and ".scale-400" the 200 % and 400 % ones, and the Square44x44Logo
".targetsize-N" images (with "_altform-unplated") are what the taskbar, Start and File Explorer use.
"""
import io
import pathlib
import subprocess
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
SVG = ROOT / "assets-src" / "TwinKeys-windows.svg"
OUT = ROOT / "src" / "TwinKeys.App" / "Assets"


def render(size: int) -> Image.Image:
    png = subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), str(SVG)],
        check=True, capture_output=True,
    ).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


def square(name: str, size: int) -> None:
    render(size).save(OUT / name, optimize=True)


def wide(name: str, w: int, h: int) -> None:
    # The icon in the middle of a transparent wide tile, about two thirds of its height.
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    icon = render(round(h * 0.66))
    canvas.paste(icon, ((w - icon.width) // 2, (h - icon.height) // 2), icon)
    canvas.save(OUT / name, optimize=True)


def main() -> int:
    for base, size in [("StoreLogo", 50), ("Square44x44Logo", 44), ("Square71x71Logo", 71),
                       ("Square150x150Logo", 150), ("Square310x310Logo", 310)]:
        square(f"{base}.png", size)
        square(f"{base}.scale-200.png", size * 2)
        square(f"{base}.scale-400.png", size * 4)
    wide("Wide310x150Logo.png", 310, 150)
    wide("Wide310x150Logo.scale-200.png", 620, 300)
    wide("Wide310x150Logo.scale-400.png", 1240, 600)
    for t in (16, 24, 32, 48, 256):
        square(f"Square44x44Logo.targetsize-{t}.png", t)
        square(f"Square44x44Logo.targetsize-{t}_altform-unplated.png", t)
    # Not in the package: the 1:1 Store logo for the Partner Center Store listing (300 x 300).
    render(300).save(ROOT / "store" / "StoreListing-Logo-300.png", optimize=True)
    for p in sorted(OUT.glob("*.png")):
        with Image.open(p) as im:
            print(f"{p.name}: {im.width}x{im.height}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
