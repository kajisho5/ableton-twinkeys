#!/usr/bin/env python3
"""Keynote-style App Store header (proposal): black, huge type, real-looking devices, slow beats.
Beat 1: the real 1.3 GO screen on an iPhone, a tap.  Beat 2: two MacBooks, both playing — "2台が、同時に。"
Beat 3: the left one goes dark — "1台が止まっても。"  Beat 4: the right one keeps glowing — "音は、止まらない。" + icon."""
import base64, os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make as M  # noqa: E402

G, R = "#3DFF7A", "#FF3B30"
W, H = 3840, 1646
TXT = {"ja": ["ワンタップで、", "2台が、同時に。", "1台が止まっても。", "音は、止まらない。", "TwinKeys Remote"],
       "en": ["One tap.", "Two Macs. At once.", "If one stops,", "the show goes on.", "TwinKeys Remote"]}


def b64(path):
    return "data:image/png;base64," + base64.b64encode(open(path, "rb").read()).decode()


GO_SHOT = b64(os.path.join(M.ROOT, "docs", "appstore", "screenshots", "iphone", "02-go-landscape.png"))
ICON = b64(os.path.join(M.ROOT, "iOS", "Sources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png"))
CLIPS = ["#FF5A45", "#FFA530", "#3DD26A", "#3D8BFF", "#A06BFF", "#FF5AAE"]


def defs():
    return ('<defs><filter id="bloom" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="80"/></filter>'
            '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="16"/></filter>'
            '<linearGradient id="alu" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3A3D43"/><stop offset="1" stop-color="#16171A"/></linearGradient>'
            '<linearGradient id="refl" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFF" stop-opacity="0.07"/><stop offset="0.45" stop-color="#FFF" stop-opacity="0"/></linearGradient>'
            '<clipPath id="ph"><rect x="0" y="0" width="2622" height="1206" rx="150"/></clipPath></defs>')


def iphone(cx, cy, scale, tap=0.0):
    w, h = 2622 * scale, 1206 * scale
    x, y = cx - w / 2, cy - h / 2
    b = 34 * scale
    o = [f'<rect x="{x - b}" y="{y - b}" width="{w + 2 * b}" height="{h + 2 * b}" rx="{190 * scale}" fill="url(#alu)"/>',
         f'<rect x="{x - b + 6}" y="{y - b + 6}" width="{w + 2 * b - 12}" height="{h + 2 * b - 12}" rx="{186 * scale}" fill="#050505"/>',
         f'<g transform="translate({x} {y}) scale({scale})"><g clip-path="url(#ph)"><image href="{GO_SHOT}" width="2622" height="1206"/></g></g>',
         f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{150 * scale}" fill="url(#refl)"/>']
    if tap > 0:  # tap on the GO key (right side of the screenshot)
        tx, ty = x + w * 0.735, y + h * 0.58
        o.append(f'<circle cx="{tx}" cy="{ty}" r="{(60 + 420 * tap) * scale * 2}" fill="none" stroke="#FFF" stroke-width="{10 * scale * 2}" opacity="{1 - tap:.3f}"/>')
        o.append(f'<circle cx="{tx}" cy="{ty}" r="{900 * scale}" fill="{G}" opacity="{0.25 * (1 - tap):.3f}" filter="url(#bloom)"/>')
    return "".join(o)


def macbook(cx, cy, w, state, glow=1.0):
    """state 'play' | 'dead'. A MacBook Pro silhouette with a Live-like clip grid on screen."""
    h = w * 0.63
    x, y = cx - w / 2, cy - h / 2
    o = []
    if state == "play":
        o.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{w * 0.62}" ry="{h * 0.62}" fill="{G}" opacity="{0.22 * glow:.3f}" filter="url(#bloom)"/>')
    o += [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{w * 0.035}" fill="#0B0B0C" stroke="#3A3D43" stroke-width="{w * 0.006}"/>',
          f'<rect x="{x + w * 0.025}" y="{y + w * 0.025}" width="{w * 0.95}" height="{h - w * 0.05}" rx="{w * 0.012}" fill="{"#06100A" if state == "play" else "#020202"}"/>']
    if state == "play":
        gx, gy, gw, gh = x + w * 0.06, y + h * 0.12, w * 0.88, h * 0.76
        cols, rows = 6, 5
        cw, ch = gw / cols, gh / rows
        for c in range(cols):
            for r in range(rows):
                lit = r == 2
                fill = CLIPS[c] if lit else "#1A1A1C"
                o.append(f'<rect x="{gx + c * cw + 6}" y="{gy + r * ch + 6}" width="{cw - 12}" height="{ch - 12}" rx="8" fill="{fill}" opacity="{0.95 if lit else 1}"/>')
                if lit:
                    o.append(f'<rect x="{gx + c * cw + 6}" y="{gy + r * ch + 6}" width="{cw - 12}" height="{ch - 12}" rx="8" fill="none" stroke="{G}" stroke-width="6"/>')
    else:
        o.append(f'<rect x="{x + w * 0.025}" y="{y + w * 0.025}" width="{w * 0.95}" height="{h - w * 0.05}" rx="{w * 0.012}" fill="none" stroke="{R}" stroke-width="{w * 0.006}" opacity="0.6"/>')
    o += [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{w * 0.035}" fill="url(#refl)"/>',
          f'<path d="M{x - w * 0.06} {y + h} H{x + w * 1.06} L{x + w * 1.02} {y + h + w * 0.045} Q{cx} {y + h + w * 0.06} {x - w * 0.02} {y + h + w * 0.045} Z" fill="url(#alu)"/>']
    return "".join(o)


def title(s, y, size, col="#FFFFFF", op=1.0):
    return M.txt(W / 2, y, s, size, col, 800, "middle", opacity=op)


def beat(i, lang, k=1.0):
    """Key frame i (0..3); k = 0..1 for in-beat animation (fades)."""
    L = TXT[lang]
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">', defs(), M.rect(0, 0, W, H, 0, "#000")]
    if i == 0:
        o += [iphone(W / 2, H / 2 + 120, 0.56, tap=0.35), title(L[0], 250, 150)]
    elif i == 1:
        o += [macbook(1290, 880, 1060, "play"), macbook(2550, 880, 1060, "play"), title(L[1], 250, 150)]
    elif i == 2:
        o += [macbook(1290, 880, 1060, "dead"), macbook(2550, 880, 1060, "play", 0.7), title(L[2], 250, 150, "#FFFFFF")]
    else:
        o += [macbook(1290, 880, 1060, "dead"), macbook(2550, 880, 1060, "play", 1.4), title(L[3], 250, 150, G),
              f'<image href="{ICON}" x="{W / 2 - 230}" y="1330" width="96" height="96" clip-path="inset(0 round 22)"/>',
              M.txt(W / 2 - 110, 1398, L[4], 64, "#FFFFFF", 700)]
    o.append("</svg>")
    return "".join(o)


def storyboard(lang):
    sw, sh = 1880, 1880 * H / W
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="{2 * sh + 120:.0f}" viewBox="0 0 3840 {2 * sh + 120:.0f}">', M.rect(0, 0, 3840, 2 * sh + 120, 0, "#1A1C22")]
    for i in range(4):
        cx, cy = 40 + (i % 2) * (sw + 40), 40 + (i // 2) * (sh + 40)
        inner = beat(i, lang).split(">", 1)[1].rsplit("</svg>", 1)[0]
        o.append(f'<svg x="{cx}" y="{cy}" width="{sw}" height="{sh:.1f}" viewBox="0 0 {W} {H}">{inner}</svg>')
    o.append("</svg>")
    return "".join(o)


if __name__ == "__main__":
    d = os.path.join(M.ROOT, "docs", "design")
    for lang in ("ja", "en"):
        svg = storyboard(lang)
        open(os.path.join(d, f"appstore-keynote-storyboard-{lang}.svg"), "w", encoding="utf-8").write(svg + "\n")
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "a.svg"); open(src, "w", encoding="utf-8").write(svg)
            subprocess.run(["rsvg-convert", "-w", "1920", "-o", os.path.join(d, f"appstore-keynote-storyboard-{lang}.png"), src], check=True)
    print("written")
