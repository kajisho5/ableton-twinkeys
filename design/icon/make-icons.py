#!/usr/bin/env python3
"""TwinKeys icons (concept A "Twin Keys"): two keycaps side by side, one down-arrow across both.
Left key = the main Mac (white), right key = the backup Mac (blue). Design: docs/design/icon-a/.

Writes every icon file from one drawing, so they always match:
  design/icon/src/key-main.svg, key-backup.svg      layers for Apple Icon Composer (design/icon/TwinKeys.icon)
  Resources/AppIcon-1024.png, Resources/AppIcon.icns Mac app (rounded tile with margins, as macOS draws icons)
  deliverables/icon/AppIcon-1024-{light,dark}.png    Mac icon, light and dark ground
  iOS/Sources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png   iPhone/iPad (full square, no alpha)
  iOS/Watch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png     Apple Watch (full square, cut to a circle)
  design/remote-icon/appicon.svg                     iPhone icon source
  site/public/favicon-32.png, apple-touch-icon.png, images/icon-512.png, images/icon-{light,dark}-64.png

Needs rsvg-convert (librsvg) and ffmpeg. Run from the repository root: python3 design/icon/make-icons.py
"""

import os
import shutil
import struct
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# The mark on a 256 grid: keycaps 86 wide with a 12 gap and radius 22; the arrow's arms are about 30 thick.
KEY_L = "M60 58h42a22 22 0 0 1 22 22v96a22 22 0 0 1-22 22h-42a22 22 0 0 1-22-22V80a22 22 0 0 1 22-22z"
KEY_R = "M154 58h42a22 22 0 0 1 22 22v96a22 22 0 0 1-22 22h-42a22 22 0 0 1-22-22V80a22 22 0 0 1 22-22z"
CHEV_L = "M74 112L95 91L122 118V160z"
CHEV_R = "M182 112L161 91L134 118V160z"
MAIN = KEY_L + CHEV_L
BACKUP = KEY_R + CHEV_R

WHITE = "#FFFFFF"
MAC_BLUE = "#6FB1FF"          # the blue of the old "K", kept for the Mac app
NAVY = "#0F1522"
MAC_GROUND = ("#2E3D5C", "#0F1522")
MAC_GROUND_DARK = ("#1B2335", "#06090F")
REMOTE_GROUND = ("#3D8BE8", "#1A4F9C")  # TwinKeys Remote: a lighter blue, told apart from the Mac app


def grad(c1, c2):
    return (f'<linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{c1}"/>'
            f'<stop offset="1" stop-color="{c2}"/></linearGradient>')


def mark(tx, ty, scale, left, right):
    return (f'<g transform="translate({tx} {ty}) scale({scale})"><path fill-rule="evenodd" fill="{left}" d="{MAIN}"/>'
            f'<path fill-rule="evenodd" fill="{right}" d="{BACKUP}"/></g>')


def mac_icon(ground):
    # macOS: an 824 rounded tile at 100 on a transparent 1024 canvas; the mark at 2.5x.
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><defs>{grad(*ground)}</defs>'
            f'<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#g)"/>'
            f'{mark(192, 182, 2.5, WHITE, MAC_BLUE)}</svg>')


def square_icon(ground, tx, ty, scale):
    # iOS / watchOS: full-bleed square (the system rounds or circles it).
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><defs>{grad(*ground)}</defs>'
            f'<rect width="1024" height="1024" fill="url(#g)"/>{mark(tx, ty, scale, WHITE, NAVY)}</svg>')


def layer(path, fill):
    # Icon Composer layer: one shape on the 1024 canvas, same placement as the iPhone icon.
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<g transform="translate(112 100) scale(3.1)"><path fill-rule="evenodd" fill="{fill}" d="{path}"/></g></svg>\n')


def render(svg_text, size, out_png, opaque=False):
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "icon.svg")
        with open(src, "w") as f:
            f.write(svg_text)
        png = os.path.join(tmp, "icon.png")
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), "-o", png, src], check=True)
        if opaque:
            # App Store icons must not have an alpha channel.
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", png, "-pix_fmt", "rgb24", out_png], check=True)
        else:
            shutil.copyfile(png, out_png)


def icns(svg_text, out_path):
    """Apple icon file: PNG entries for 16-1024 px (icp4..ic14)."""
    entries = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512),
               ("ic10", 1024), ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]
    chunks = b""
    with tempfile.TemporaryDirectory() as tmp:
        for kind, size in entries:
            png = os.path.join(tmp, f"{kind}.png")
            render(svg_text, size, png)
            data = open(png, "rb").read()
            chunks += kind.encode() + struct.pack(">I", 8 + len(data)) + data
    with open(out_path, "wb") as f:
        f.write(b"icns" + struct.pack(">I", 8 + len(chunks)) + chunks)


def p(*parts):
    return os.path.join(ROOT, *parts)


def main():
    mac = mac_icon(MAC_GROUND)
    mac_dark = mac_icon(MAC_GROUND_DARK)
    ios = square_icon(REMOTE_GROUND, 112, 100, 3.1)
    watch = square_icon(REMOTE_GROUND, 179, 166, 2.6)

    # Icon Composer source (layers; the ground gradient stays in icon.json)
    for name, path, fill in (("key-main.svg", MAIN, WHITE), ("key-backup.svg", BACKUP, MAC_BLUE)):
        text = layer(path, fill)
        for folder in (p("design", "icon", "src"), p("design", "icon", "TwinKeys.icon", "Assets")):
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, name), "w") as f:
                f.write(text)

    render(mac, 1024, p("Resources", "AppIcon-1024.png"))
    icns(mac, p("Resources", "AppIcon.icns"))
    render(mac, 1024, p("deliverables", "icon", "AppIcon-1024-light.png"))
    render(mac_dark, 1024, p("deliverables", "icon", "AppIcon-1024-dark.png"))
    render(ios, 1024, p("iOS", "Sources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png"), opaque=True)
    render(watch, 1024, p("iOS", "Watch", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png"), opaque=True)
    with open(p("design", "remote-icon", "appicon.svg"), "w") as f:
        f.write(ios + "\n")

    render(mac, 32, p("site", "public", "favicon-32.png"))
    render(mac, 180, p("site", "public", "apple-touch-icon.png"))
    render(mac, 512, p("site", "public", "images", "icon-512.png"))
    render(mac, 64, p("site", "public", "images", "icon-light-64.png"))
    render(mac_dark, 64, p("site", "public", "images", "icon-dark-64.png"))
    print("icons written")


if __name__ == "__main__":
    main()
