#!/usr/bin/env python3
"""Three more stylish directions for the App Store header (21:9) and search image (3:2). Proposal only.
Writes docs/design/appstore-concept-{1,2,3}.png (header and search side by side). Uses the A1 GO screen
from make.py so the phone shows the 1.3 look."""
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make as M  # noqa: E402

G = "#3DFF7A"
MONO = "JetBrains Mono"
JP = M.FONT


def defs():
    return ('<defs>'
            '<filter id="soft" x="-10%" y="-10%" width="120%" height="140%"><feGaussianBlur stdDeviation="22"/></filter>'
            '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="9"/></filter>'
            '<filter id="bloom" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="90"/></filter>'
            '<radialGradient id="vig" cx="0.5" cy="0.5" r="0.75"><stop offset="0.55" stop-color="#000" stop-opacity="0"/>'
            '<stop offset="1" stop-color="#000" stop-opacity="0.85"/></radialGradient>'
            '<linearGradient id="beam" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#3DFF7A" stop-opacity="0"/>'
            '<stop offset="0.5" stop-color="#3DFF7A" stop-opacity="1"/><stop offset="1" stop-color="#3DFF7A" stop-opacity="0"/></linearGradient>'
            '<pattern id="grid" width="64" height="64" patternUnits="userSpaceOnUse"><path d="M64 0H0V64" fill="none" stroke="#FFFFFF" stroke-opacity="0.035" stroke-width="2"/></pattern>'
            '</defs>')


def st_idle(lang):
    return {"lang": lang, "phase": "idle", "progress": 0.55}


def led(x, y, col=G, r=10):
    return f'<circle cx="{x}" cy="{y}" r="{r * 2.2}" fill="{col}" opacity="0.55" filter="url(#glow)"/><circle cx="{x}" cy="{y}" r="{r}" fill="{col}"/>'


def mac_line(x, y, w, label, sub, col=G):
    """A Mac as a thin rack-style row: LED, name, status, a lit line."""
    return (f'<rect x="{x}" y="{y}" width="{w}" height="96" rx="14" fill="#060606" stroke="#2A2A2A" stroke-width="3"/>'
            + led(x + 52, y + 48, col, 11)
            + M.txt(x + 96, y + 60, label, 40, "#EDEDED", 700, family=MONO)
            + M.txt(x + w - 36, y + 60, sub, 30, col, 700, "end"))


# 1. HERO GO: one big glowing phone, a bold headline, nothing else ----------------------------------

def c1_header(lang):
    L = {"ja": ("本番を、", "止めない。", "2台の Mac を、iPhone ひとつで。"),
         "en": ("Keep the show", "running.", "Two Macs, one iPhone.")}[lang]
    ph, h = M.phone(1780, 250, 1820, st_idle(lang), 0)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="1646" viewBox="0 0 3840 1646">{defs()}'
            + M.rect(0, 0, 3840, 1646, 0, "#000") + M.rect(0, 0, 3840, 1646, 0, "url(#grid)")
            + f'<ellipse cx="2690" cy="1250" rx="1100" ry="300" fill="{G}" opacity="0.28" filter="url(#bloom)"/>'
            + ph
            + M.txt(300, 640, L[0], 190 if lang == "ja" else 170, "#FFFFFF", 800, family=JP if lang == "ja" else MONO)
            + M.txt(300, 860, L[1], 190 if lang == "ja" else 170, G, 800, family=JP if lang == "ja" else MONO)
            + M.txt(306, 1010, L[2], 56, "#9A9A9A", 700)
            + led(320, 1160) + M.txt(360, 1174, "MAIN", 40, "#EDEDED", 700, family=MONO)
            + led(600, 1160) + M.txt(640, 1174, "BACKUP", 40, "#EDEDED", 700, family=MONO)
            + M.rect(0, 0, 3840, 1646, 0, "url(#vig)") + "</svg>")


# 2. TWIN LINES: two light lines (main, backup) run through the phone -------------------------------

def c2_header(lang):
    L = {"ja": ("ワンタップで、2台が同時に。", "MAIN と BACKUP、同じキューを同じ瞬間に。"),
         "en": ("One tap. Two Macs.", "Main and backup fire the same cue at the same moment.")}[lang]
    ph, h = M.phone(1260, 330, 1320, st_idle(lang), 0)
    lines = ""
    for y, lab in ((560, "MAIN"), (1090, "BACKUP")):
        lines += (f'<rect x="0" y="{y - 4}" width="3840" height="8" fill="url(#beam)"/>'
                  f'<rect x="0" y="{y - 30}" width="3840" height="60" fill="url(#beam)" opacity="0.25" filter="url(#glow)"/>'
                  + led(3080, y, G, 14) + M.txt(3130, y + 16, lab, 48, "#EDEDED", 700, family=MONO)
                  + led(760, y, G, 14) + M.txt(710, y + 16, lab, 48, "#EDEDED", 700, "end", family=MONO))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="1646" viewBox="0 0 3840 1646">{defs()}'
            + M.rect(0, 0, 3840, 1646, 0, "#000") + lines + ph
            + M.txt(1920, 190, L[0], 120, "#FFFFFF", 800, "middle")
            + M.txt(1920, 1480, L[1], 52, "#9A9A9A", 700, "middle")
            + M.rect(0, 0, 3840, 1646, 0, "url(#vig)") + "</svg>")


# 3. RACK: the GO key huge, like a lit button on stage gear, Macs as rack rows ----------------------

def c3_header(lang):
    L = {"ja": ("GO", "押すのは、ひとつだけ。", "メインが止まっても、バックアップは鳴り続ける。"),
         "en": ("GO", "Press one key.", "If the main Mac stops, the backup keeps playing.")}[lang]
    key = (f'<rect x="420" y="250" width="1150" height="1150" rx="90" fill="{G}" opacity="0.45" filter="url(#bloom)"/>'
           '<linearGradient id="k3" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0E2416"/><stop offset="1" stop-color="#030805"/></linearGradient>'
           f'<rect x="420" y="250" width="1150" height="1150" rx="90" fill="url(#k3)" stroke="{G}" stroke-width="10"/>'
           f'<rect x="470" y="300" width="1050" height="8" rx="4" fill="{G}" opacity="0.7"/>'
           + M.txt(995, 960, L[0], 520, G, 800, "middle", family=MONO))
    rows = (mac_line(2000, 820, 1420, "MAIN", "PLAYING" if lang == "en" else "再生中")
            + mac_line(2000, 950, 1420, "BACKUP", "PLAYING" if lang == "en" else "再生中")
            + mac_line(2000, 1080, 1420, "LIVE", "2 ms"))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="1646" viewBox="0 0 3840 1646">{defs()}'
            + M.rect(0, 0, 3840, 1646, 0, "#000") + M.rect(0, 0, 3840, 1646, 0, "url(#grid)") + key
            + M.txt(2000, 560, L[1], 150 if lang == "ja" else 140, "#FFFFFF", 800)
            + M.txt(2004, 680, L[2], 52, "#9A9A9A", 700) + rows
            + M.rect(0, 0, 3840, 1646, 0, "url(#vig)") + "</svg>")


def search_from(header_svg):
    """3:2 search image: the header art centred on a taller black canvas (proposal preview only)."""
    inner = header_svg.replace('<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="1646" viewBox="0 0 3840 1646">', "").replace("</svg>", "")
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="2560" viewBox="0 0 3840 2560">'
            + M.rect(0, 0, 3840, 2560, 0, "#000")
            + f'<svg x="0" y="457" width="3840" height="1646" viewBox="0 0 3840 1646">{inner}</svg></svg>')


def render(svg, out, width):
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "a.svg")
        open(src, "w", encoding="utf-8").write(svg)
        subprocess.run(["rsvg-convert", "-w", str(width), "-o", out, src], check=True)


def main():
    out = os.path.join(M.ROOT, "docs", "design")
    for i, fn in enumerate((c1_header, c2_header, c3_header), 1):
        for lang in ("ja", "en"):
            svg = fn(lang)
            open(os.path.join(out, f"appstore-concept-{i}-{lang}.svg"), "w", encoding="utf-8").write(svg + "\n")
            render(svg, os.path.join(out, f"appstore-concept-{i}-{lang}.png"), 1920)
    print("written")


if __name__ == "__main__":
    main()
