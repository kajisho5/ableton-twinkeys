#!/usr/bin/env python3
"""Style proposals for TwinKeys Remote 1.3 (not implemented): the iPhone GO screen and the Apple Watch screen
in three directions. A = stage gear, B = glass (Liquid Glass-like), C = Twin Keys (the icon's colours).
Writes docs/design/restyle-{a,b,c}.svg/png. Run: python3 design/restyle/make.py
"""

import os
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
JP = "Noto Sans CJK JP"
MONO = "JetBrains Mono"


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def t(x, y, s, size, fill="#FFF", w=400, a="start", fam=JP, ls=0, op=1.0):
    extra = (f' letter-spacing="{ls}"' if ls else "") + (f' opacity="{op}"' if op < 1 else "")
    return (f'<text x="{x}" y="{y}" font-family="{fam}" font-size="{size}" font-weight="{w}" fill="{fill}" '
            f'text-anchor="{a}"{extra}>{esc(s)}</text>')


def r(x, y, w, h, rx, fill, stroke=None, sw=1, extra=""):
    st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"{st} {extra}/>'


# ----------------------------------------------------------------------------------------------
# A. Stage gear: black, hairlines, LED status, monospace readouts, a lit GO key


def a_phone():
    G, R, Y = "#3DFF7A", "#FF3B30", "#FFB020"
    o = [r(0, 0, 1688, 780, 0, "#000"),
         '<defs><filter id="ga" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6"/></filter>'
         '<linearGradient id="keyA" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0E2416"/>'
         '<stop offset="1" stop-color="#050B07"/></linearGradient></defs>']
    # top strip: LEDs + readouts
    o.append(r(0, 0, 1688, 96, 0, "#070707"))
    o.append('<line x1="0" y1="96" x2="1688" y2="96" stroke="#222" stroke-width="2"/>')
    for i, (lab, col) in enumerate((("MAIN", G), ("BACKUP", G), ("LIVE", G))):
        x = 40 + i * 150
        o.append(f'<circle cx="{x}" cy="40" r="9" fill="{col}" filter="url(#ga)"/><circle cx="{x}" cy="40" r="6" fill="{col}"/>')
        o.append(t(x + 18, 47, lab, 20, "#BDBDBD", 700, fam=MONO, ls=2))
    o.append(t(40, 80, "LAT 2 ms", 17, "#666", 400, fam=MONO, ls=2))
    o += [r(520, 18, 92, 60, 10, "#0B0B0B", "#2E2E2E", 2), '<path d="M554 34 L582 48 L554 62 Z" fill="#3DFF7A"/>',
          r(624, 18, 92, 60, 10, "#0B0B0B", "#2E2E2E", 2), r(658, 36, 24, 24, 3, "#DDD"),
          t(760, 44, "TEMPO", 15, "#666", 700, fam=MONO, ls=3), t(760, 78, "124.00", 34, "#EDEDED", 700, fam=MONO),
          t(940, 44, "POSITION", 15, "#666", 700, fam=MONO, ls=3), t(940, 78, "017.3.1", 34, "#EDEDED", 700, fam=MONO),
          r(1300, 18, 230, 60, 10, "#1A0605", R, 2), t(1415, 57, "全ノートオフ", 24, R, 700, "middle"),
          r(1546, 18, 60, 60, 10, "#0B0B0B", "#2E2E2E", 2)]
    # now / next panels with hairlines and small caps labels
    o += [r(32, 124, 930, 270, 14, "#060606", "#2A2A2A", 2),
          f'<rect x="32" y="124" width="6" height="270" fill="{G}"/>',
          t(64, 166, "NOW PLAYING", 18, G, 700, fam=MONO, ls=4),
          t(64, 250, "03", 64, "#5A5A5A", 700, fam=MONO), t(170, 250, "M1 イントロ", 56, "#F2F2F2", 700),
          t(64, 318, "REMAIN", 15, "#666", 700, fam=MONO, ls=3), t(64, 360, "-0:42", 40, G, 700, fam=MONO)]
    for i in range(40):  # segmented meter
        on = i < 22
        o.append(r(240 + i * 17.5, 330, 12, 26, 2, G if on else "#151515"))
    o += [r(32, 418, 930, 186, 14, "#060606", "#2A2A2A", 2), t(64, 460, "NEXT", 18, "#8AB4FF", 700, fam=MONO, ls=4),
          t(64, 546, "04", 56, "#5A5A5A", 700, fam=MONO), t(160, 546, "M1 本編", 48, "#F2F2F2", 700),
          t(64, 586, "Live で選んでいるシーン", 20, "#666")]
    o += [r(32, 628, 300, 124, 14, "#0A0A0A", "#2E2E2E", 2), t(182, 702, "◀  前へ", 30, "#DDD", 700, "middle"),
          r(348, 628, 300, 124, 14, "#0A0A0A", "#2E2E2E", 2), t(498, 702, "次へ  ▶", 30, "#DDD", 700, "middle")]
    # GO key: dark key, lit edge, glow
    o += [f'<rect x="990" y="124" width="560" height="628" rx="30" fill="{G}" opacity="0.35" filter="url(#ga)"/>',
          r(990, 124, 560, 628, 30, "url(#keyA)", G, 4),
          r(1010, 144, 520, 4, 2, G, extra='opacity="0.6"'),
          t(1270, 470, "GO", 190, G, 800, "middle", fam=MONO),
          t(1270, 540, "NEXT ▸ 04  M1 本編", 26, "#9AF5B7", 700, "middle", fam=JP),
          t(1270, 712, "SHOW LOCK OK", 18, "#4C8F63", 700, "middle", fam=MONO, ls=4)]
    # rail
    o.append(r(1620, 96, 68, 684, 0, "#050505"))
    for i in range(5):
        cy = 170 + i * 128
        act = i == 3
        o.append(f'<circle cx="1654" cy="{cy}" r="{7 if act else 5}" fill="{G if act else "#3A3A3A"}"/>')
    return "".join(o)


def a_watch():
    G = "#3DFF7A"
    o = [r(0, 0, 416, 496, 0, "#000"),
         '<defs><filter id="gw" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="5"/></filter></defs>']
    for i, lab in enumerate(("M", "B")):
        x = 150 + i * 116
        o.append(f'<circle cx="{x}" cy="44" r="8" fill="{G}" filter="url(#gw)"/><circle cx="{x}" cy="44" r="5" fill="{G}"/>')
        o.append(t(x + 14, 51, lab, 20, "#AAA", 700, fam=MONO))
    # remaining ring
    cx, cy, rr = 208, 262, 150
    import math
    frac = 0.58
    end = -math.pi / 2 + 2 * math.pi * frac
    ex, ey = cx + rr * math.cos(end), cy + rr * math.sin(end)
    o += [f'<circle cx="{cx}" cy="{cy}" r="{rr}" fill="none" stroke="#141414" stroke-width="14"/>',
          f'<path d="M{cx} {cy - rr} A{rr} {rr} 0 {1 if frac > 0.5 else 0} 1 {ex:.1f} {ey:.1f}" fill="none" stroke="{G}" stroke-width="14" stroke-linecap="round"/>',
          f'<circle cx="{cx}" cy="{cy}" r="118" fill="#06140A" stroke="{G}" stroke-width="3"/>',
          t(cx, cy + 22, "GO", 84, G, 800, "middle", fam=MONO),
          t(cx, cy + 66, "-0:42", 26, "#9AF5B7", 700, "middle", fam=MONO),
          t(cx, 466, "NEXT 04  M1 本編", 24, "#DDD", 700, "middle")]
    return "".join(o)


# ----------------------------------------------------------------------------------------------
# B. Glass: colourful blurred light behind frosted panels


def b_bg(w, h, idd):
    return (f'<defs><filter id="blur{idd}" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="{w * 0.06:.0f}"/></filter>'
            f'<linearGradient id="edge{idd}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFF" stop-opacity="0.55"/>'
            f'<stop offset="0.5" stop-color="#FFF" stop-opacity="0.08"/><stop offset="1" stop-color="#FFF" stop-opacity="0.25"/></linearGradient></defs>'
            + r(0, 0, w, h, 0, "#07070D")
            + f'<g filter="url(#blur{idd})"><circle cx="{w * 0.18:.0f}" cy="{h * 0.3:.0f}" r="{h * 0.45:.0f}" fill="#3B2BFF" opacity="0.75"/>'
              f'<circle cx="{w * 0.62:.0f}" cy="{h * 0.85:.0f}" r="{h * 0.5:.0f}" fill="#00C2A8" opacity="0.55"/>'
              f'<circle cx="{w * 0.9:.0f}" cy="{h * 0.15:.0f}" r="{h * 0.35:.0f}" fill="#C2339B" opacity="0.55"/></g>')


def glass(x, y, w, h, rx, idd, tint="#FFFFFF", op=0.10):
    return (r(x, y, w, h, rx, tint, extra=f'fill-opacity="{op}"')
            + f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="none" stroke="url(#edge{idd})" stroke-width="2"/>')


def b_phone():
    o = [b_bg(1688, 780, "p")]
    o += [glass(24, 14, 1640, 76, 38, "p"),
          '<circle cx="64" cy="52" r="9" fill="#5CFF95"/>', t(84, 60, "Main ✓  Backup ✓  Live ✓", 24, "#FFF", 700),
          glass(480, 22, 96, 60, 30, "p", "#5CFF95", 0.30), '<path d="M516 38 L544 52 L516 66 Z" fill="#FFF"/>',
          glass(590, 22, 96, 60, 30, "p"), r(626, 40, 24, 24, 4, "#FFF"),
          t(720, 66, "124.00", 36, "#FFF", 600), t(850, 66, "BPM", 20, "#FFF", 400, op=0.6), t(920, 66, "17.3.1", 32, "#FFF", 600),
          glass(1290, 22, 240, 60, 30, "p", "#FF4D4D", 0.35), t(1410, 61, "全ノートオフ", 24, "#FFF", 700, "middle"),
          glass(1546, 22, 96, 60, 30, "p")]
    o += [glass(32, 116, 930, 276, 36, "p"), t(68, 166, "いま再生中", 22, "#9BFFC0", 700),
          t(68, 252, "3", 66, "#FFF", 300, op=0.6), t(130, 252, "M1 イントロ", 56, "#FFF", 700),
          t(68, 318, "残り  -0:42", 28, "#FFF", 600, op=0.9),
          r(260, 300, 660, 14, 7, "#FFF", extra='fill-opacity="0.15"'), r(260, 300, 370, 14, 7, "#5CFF95"),
          t(68, 364, "Intro ・ Pad", 22, "#FFF", 400, op=0.6),
          glass(32, 412, 930, 196, 36, "p"), t(68, 458, "次", 22, "#9CC8FF", 700),
          t(68, 546, "4", 56, "#FFF", 300, op=0.6), t(124, 546, "M1 本編", 48, "#FFF", 700),
          t(68, 588, "Live で選んでいるシーン", 22, "#FFF", 400, op=0.6),
          glass(32, 628, 300, 124, 40, "p"), t(182, 702, "◀ 前へ", 30, "#FFF", 700, "middle"),
          glass(348, 628, 300, 124, 40, "p"), t(498, 702, "次へ ▶", 30, "#FFF", 700, "middle")]
    o += [glass(990, 116, 560, 636, 60, "p", "#33E37A", 0.55),
          t(1270, 450, "GO", 170, "#FFF", 800, "middle"), t(1270, 520, "次のシーンを再生", 30, "#FFF", 700, "middle"),
          t(1270, 570, "4 M1 本編", 30, "#FFF", 600, "middle", op=0.9),
          t(1270, 712, "本番ロック中も使えます", 22, "#FFF", 600, "middle", op=0.8)]
    o.append(glass(1572, 116, 92, 636, 46, "p"))
    for i in range(5):
        cy = 180 + i * 124
        o.append(r(1596, cy - 22, 44, 44, 14, "#FFF", extra=f'fill-opacity="{0.9 if i == 3 else 0.25}"'))
    return "".join(o)


def b_watch():
    o = [b_bg(416, 496, "w")]
    o += [glass(24, 22, 368, 56, 28, "w"), '<circle cx="60" cy="50" r="8" fill="#5CFF95"/>',
          t(80, 58, "Main・Backup", 22, "#FFF", 700),
          glass(48, 104, 320, 300, 150, "w", "#33E37A", 0.55),
          t(208, 268, "GO", 100, "#FFF", 800, "middle"), t(208, 318, "-0:42", 28, "#FFF", 600, "middle", op=0.9),
          glass(24, 420, 368, 56, 28, "w"), t(208, 458, "次  4 M1 本編", 24, "#FFF", 700, "middle")]
    return "".join(o)


# ----------------------------------------------------------------------------------------------
# C. Twin Keys: the icon's navy, white and blue; buttons as keycaps


def key(x, y, w, h, rx, top, side, stroke=None):
    depth = max(6, h * 0.05)
    return (r(x, y + depth, w, h - depth, rx, side)
            + r(x, y, w, h - depth, rx, top, stroke, 2 if stroke else 1))


def c_defs(idd):
    return (f'<defs><linearGradient id="nav{idd}" x1="0" y1="0" x2="0.3" y2="1"><stop offset="0" stop-color="#1D2A46"/>'
            f'<stop offset="1" stop-color="#070B14"/></linearGradient></defs>')


CHEV = "M74 112L95 91L122 118V160z"


def c_phone():
    W, B, N = "#FFFFFF", "#6FB1FF", "#0F1522"
    o = [c_defs("p"), r(0, 0, 1688, 780, 0, "url(#navp)")]
    o += [r(0, 0, 1688, 96, 0, "#0B1120"), '<line x1="0" y1="96" x2="1688" y2="96" stroke="#24304A" stroke-width="2"/>',
          '<circle cx="44" cy="40" r="9" fill="#4CD366"/>', t(64, 48, "Main ✓ Backup ✓ Live ✓", 24, W, 700),
          t(64, 80, "2 ms", 19, "#7F8BA3"),
          key(470, 14, 100, 70, 16, B, "#2E5E9C"), '<path d="M506 30 L536 46 L506 62 Z" fill="#0F1522"/>',
          key(582, 14, 100, 70, 16, "#26324D", "#141B2B"), r(620, 34, 24, 24, 4, W),
          t(720, 64, "124.00", 36, W, 700), t(852, 64, "BPM", 20, "#7F8BA3"), t(920, 64, "17. 3. 1", 32, W, 700),
          key(1290, 14, 240, 70, 16, "#E04A3F", "#8E241C"), t(1410, 56, "全ノートオフ", 26, W, 700, "middle"),
          key(1546, 14, 74, 70, 16, "#26324D", "#141B2B")]
    o += [r(32, 120, 930, 276, 26, "#16213A", "#2C3A5A", 2),
          f'<rect x="32" y="120" width="10" height="276" rx="5" fill="{B}"/>',
          t(68, 168, "いま再生中", 22, B, 700), t(68, 254, "3", 64, "#7F8BA3", 700), t(140, 254, "M1 イントロ", 56, W, 700),
          t(68, 320, "残り", 22, "#7F8BA3"), t(130, 322, "-0:42", 32, B, 700, fam=MONO),
          r(270, 304, 650, 14, 7, "#24304A"), r(270, 304, 370, 14, 7, B),
          t(68, 368, "Intro ・ Pad", 22, "#7F8BA3"),
          r(32, 416, 930, 192, 26, "#121B30", "#24304A", 2), t(68, 462, "次", 22, "#AFC8EA", 700),
          t(68, 548, "4", 54, "#7F8BA3", 700), t(130, 548, "M1 本編", 48, W, 700),
          t(68, 590, "Live で選んでいるシーン", 22, "#7F8BA3"),
          key(32, 628, 300, 126, 22, "#26324D", "#141B2B"), t(182, 700, "◀ 前へ", 30, W, 700, "middle"),
          key(348, 628, 300, 126, 22, "#26324D", "#141B2B"), t(498, 700, "次へ ▶", 30, W, 700, "middle")]
    # GO as the white keycap of the icon, with the icon's chevron
    o += [key(990, 120, 560, 640, 48, W, "#A9B7CF"),
          r(1222, 190, 44, 60, 10, N), r(1274, 190, 44, 60, 10, B),
          t(1270, 470, "GO", 160, N, 800, "middle"), t(1270, 540, "次のシーンを再生", 30, N, 700, "middle"),
          t(1270, 590, "4 M1 本編", 30, "#3D5A8A", 700, "middle"),
          t(1270, 708, "本番ロック中も使えます", 22, "#5A6E92", 700, "middle")]
    o.append(r(1620, 96, 68, 684, 0, "#0B1120"))
    for i in range(5):
        cy = 170 + i * 128
        o.append(r(1636, cy - 18, 36, 36, 10, B if i == 3 else "#26324D"))
    return "".join(o)


def c_watch():
    W, B, N = "#FFFFFF", "#6FB1FF", "#0F1522"
    o = [c_defs("w"), r(0, 0, 416, 496, 0, "url(#navw)"),
         '<circle cx="140" cy="44" r="8" fill="#4CD366"/>', t(156, 51, "M", 20, W, 700),
         '<circle cx="250" cy="44" r="8" fill="#4CD366"/>', t(266, 51, "B", 20, W, 700),
         key(48, 86, 320, 320, 70, W, "#A9B7CF"),
         t(208, 262, "GO", 104, N, 800, "middle"), t(208, 316, "-0:42", 28, "#3D5A8A", 700, "middle", fam=MONO),
         t(208, 462, "次  4 M1 本編", 26, W, 700, "middle")]
    return "".join(o)


# ----------------------------------------------------------------------------------------------


def sheet(label, title, notes, phone_svg, watch_svg, idd):
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="2520" height="1180" viewBox="0 0 2520 1180">',
         r(0, 0, 2520, 1180, 0, "#101114"),
         t(60, 90, f"{label}. {title}", 52, "#FFF", 800), t(60, 150, notes, 30, "#A0A4AD", 400)]
    # iPhone body
    o += [r(40, 200, 1808, 900, 120, "#2A2C31", "#4A4D55", 3),
          f'<clipPath id="s{idd}"><rect x="100" y="260" width="1688" height="780" rx="80"/></clipPath>',
          f'<g clip-path="url(#s{idd})" transform="translate(100 260)">{phone_svg}</g>'.replace(
              f'<g clip-path="url(#s{idd})" transform="translate(100 260)">',
              f'<g clip-path="url(#s{idd})"><g transform="translate(100 260)">') + "</g>",
          r(104, 580, 20, 140, 10, "#000")]
    # Apple Watch
    wx, wy = 1960, 330
    o += [r(wx + 70, wy - 150, 336, 170, 50, "#2A2C31"), r(wx + 70, wy + 556, 336, 170, 50, "#2A2C31"),
          r(wx - 20, wy - 20, 516, 636, 130, "#3A3D44", "#5A5E66", 3),
          f'<clipPath id="w{idd}"><rect x="{wx + 30}" y="{wy + 50}" width="416" height="496" rx="90"/></clipPath>',
          f'<g clip-path="url(#w{idd})"><g transform="translate({wx + 30} {wy + 50})">{watch_svg}</g></g>',
          r(wx + 496, wy + 150, 22, 90, 11, "#5A5E66")]
    o.append("</svg>")
    return "".join(o)


def main():
    out = os.path.join(ROOT, "docs", "design")
    sheets = [
        ("a", "A", "音響機材ふう", "真っ黒・細い線・機材のランプ・桁のそろう数字・光る GO キー", a_phone(), a_watch()),
        ("b", "B", "ガラス（Liquid Glass ふう）", "後ろの色がすりガラスごしに見える。Apple の新しいアプリに近い", b_phone(), b_watch()),
        ("c", "C", "Twin Keys", "アイコンの紺・白・青。ボタンはキーの形で、GO はアイコンの白いキー", c_phone(), c_watch()),
    ]
    for idd, label, title, notes, ph, wa in sheets:
        svg = sheet(label, title, notes, ph, wa, idd)
        with open(os.path.join(out, f"restyle-{idd}.svg"), "w", encoding="utf-8") as f:
            f.write(svg + "\n")
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "a.svg")
            open(src, "w", encoding="utf-8").write(svg)
            subprocess.run(["rsvg-convert", "-w", "1680", "-o", os.path.join(out, f"restyle-{idd}.png"), src], check=True)
    print("written docs/design/restyle-{a,b,c}.svg/png")


if __name__ == "__main__":
    main()
