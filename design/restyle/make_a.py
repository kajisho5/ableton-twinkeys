#!/usr/bin/env python3
"""Three variations of style A (stage gear) for TwinKeys Remote 1.3 (not implemented):
A1 green LED, A2 amber display window, A3 metal console panel. Writes docs/design/restyle-a{1,2,3}.svg/png."""
import math, os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make import t, r, sheet, ROOT, JP, MONO  # noqa: E402

THEMES = {
    "a1": dict(title="A1 緑のランプ", note="黒に細い線。正常は緑に光る。GO は暗いキーのふちが光る",
               bg="#000", top="#070707", panel="#060606", stroke="#2A2A2A", acc="#3DFF7A", soft="#9AF5B7",
               read="#EDEDED", lab="#6B6B6B", key1="#0E2416", key2="#050B07", gotext="#3DFF7A", off="#151515",
               metal=False, led="#3DFF7A"),
    "a2": dict(title="A2 オレンジの表示窓", note="昔のラック機材の表示窓のような暖かいオレンジ。ランプの緑は正常のしるしだけ",
               bg="#050403", top="#0B0806", panel="#0A0705", stroke="#3A2A18", acc="#FFB020", soft="#FFD58A",
               read="#FFB020", lab="#8A6A3A", key1="#2A1A05", key2="#0E0802", gotext="#FFB020", off="#1E150A",
               metal=False, led="#3DFF7A"),
    "a3": dict(title="A3 金属パネルの卓", note="つや消しの金属パネルにネジ。白っぽい青のランプ。GO は光る輪のボタン",
               bg="#16171A", top="#202226", panel="#1B1D21", stroke="#3A3D44", acc="#7FE6FF", soft="#CFF6FF",
               read="#F2F4F7", lab="#7C828C", key1="#2A2D33", key2="#15171A", gotext="#FFFFFF", off="#25282E",
               metal=True, led="#7FE6FF"),
}


def screws(xs, ys):
    return "".join(f'<circle cx="{x}" cy="{y}" r="7" fill="#0D0E10" stroke="#4A4E56" stroke-width="2"/>'
                   f'<line x1="{x - 4}" y1="{y - 4}" x2="{x + 4}" y2="{y + 4}" stroke="#4A4E56" stroke-width="2"/>'
                   for x in xs for y in ys)


def phone(T):
    A, Rd = T["acc"], "#FF3B30"
    o = [r(0, 0, 1688, 780, 0, T["bg"]),
         '<defs><filter id="g" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6"/></filter>'
         f'<linearGradient id="k" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{T["key1"]}"/><stop offset="1" stop-color="{T["key2"]}"/></linearGradient>'
         '<linearGradient id="m" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2C2F35"/><stop offset="1" stop-color="#17181B"/></linearGradient></defs>']
    if T["metal"]:
        o.append(r(0, 0, 1688, 780, 0, "url(#m)"))
        for i in range(0, 780, 6):
            o.append(f'<line x1="0" y1="{i}" x2="1688" y2="{i}" stroke="#FFFFFF" stroke-opacity="0.015"/>')
    o += [r(0, 0, 1688, 96, 0, T["top"]), f'<line x1="0" y1="96" x2="1688" y2="96" stroke="{T["stroke"]}" stroke-width="2"/>']
    for i, lab in enumerate(("MAIN", "BACKUP", "LIVE")):
        x = 40 + i * 150
        o.append(f'<circle cx="{x}" cy="40" r="9" fill="{T["led"]}" filter="url(#g)"/><circle cx="{x}" cy="40" r="6" fill="{T["led"]}"/>')
        o.append(t(x + 18, 47, lab, 20, T["read"] if not T["metal"] else "#C9CED6", 700, fam=MONO, ls=2))
    o.append(t(40, 80, "LAT 2 ms", 17, T["lab"], 400, fam=MONO, ls=2))
    win = (lambda x, w: r(x, 16, w, 66, 8, "#000", T["stroke"], 2)) if not T["metal"] else (lambda x, w: r(x, 16, w, 66, 8, "#050607", "#000", 2))
    o += [r(520, 18, 92, 60, 10, T["panel"], T["stroke"], 2), f'<path d="M554 34 L582 48 L554 62 Z" fill="{T["led"] if T["metal"] else "#3DFF7A"}"/>',
          r(624, 18, 92, 60, 10, T["panel"], T["stroke"], 2), r(658, 36, 24, 24, 3, "#DDD"),
          win(748, 170), t(762, 40, "TEMPO", 13, T["lab"], 700, fam=MONO, ls=3), t(762, 74, "124.00", 32, T["read"], 700, fam=MONO),
          win(930, 190), t(944, 40, "POSITION", 13, T["lab"], 700, fam=MONO, ls=3), t(944, 74, "017.3.1", 32, T["read"], 700, fam=MONO),
          r(1300, 18, 230, 60, 10, "#1A0605", Rd, 2), t(1415, 57, "全ノートオフ", 24, Rd, 700, "middle"),
          r(1546, 18, 60, 60, 10, T["panel"], T["stroke"], 2)]
    o += [r(32, 124, 930, 270, 14, T["panel"], T["stroke"], 2), f'<rect x="32" y="124" width="6" height="270" fill="{A}"/>',
          t(64, 166, "NOW PLAYING", 18, A, 700, fam=MONO, ls=4),
          t(64, 250, "03", 64, T["lab"], 700, fam=MONO), t(170, 250, "M1 イントロ", 56, "#F2F2F2", 700),
          t(64, 318, "REMAIN", 15, T["lab"], 700, fam=MONO, ls=3), t(64, 360, "-0:42", 40, A, 700, fam=MONO)]
    for i in range(40):
        o.append(r(240 + i * 17.5, 330, 12, 26, 2, A if i < 22 else T["off"]))
    o += [r(32, 418, 930, 186, 14, T["panel"], T["stroke"], 2), t(64, 460, "NEXT", 18, T["soft"], 700, fam=MONO, ls=4),
          t(64, 546, "04", 56, T["lab"], 700, fam=MONO), t(160, 546, "M1 本編", 48, "#F2F2F2", 700),
          t(64, 586, "Live で選んでいるシーン", 20, T["lab"]),
          r(32, 628, 300, 124, 14, T["panel"], T["stroke"], 2), t(182, 702, "◀  前へ", 30, "#DDD", 700, "middle"),
          r(348, 628, 300, 124, 14, T["panel"], T["stroke"], 2), t(498, 702, "次へ  ▶", 30, "#DDD", 700, "middle")]
    if T["metal"]:  # GO: illuminated ring button
        cx, cy = 1270, 400
        o += [r(990, 124, 560, 628, 30, "#121316", "#000", 3), screws((1012, 1528), (146, 730)),
              f'<circle cx="{cx}" cy="{cy}" r="210" fill="{A}" opacity="0.35" filter="url(#g)"/>',
              f'<circle cx="{cx}" cy="{cy}" r="200" fill="url(#k)" stroke="{A}" stroke-width="14"/>',
              f'<circle cx="{cx}" cy="{cy}" r="178" fill="none" stroke="#FFFFFF" stroke-opacity="0.08" stroke-width="2"/>',
              t(cx, cy + 50, "GO", 140, T["gotext"], 800, "middle", fam=MONO),
              t(cx, 670, "NEXT ▸ 04  M1 本編", 26, T["soft"], 700, "middle"),
              t(cx, 716, "SHOW LOCK OK", 16, T["lab"], 700, "middle", fam=MONO, ls=4)]
    else:
        o += [f'<rect x="990" y="124" width="560" height="628" rx="30" fill="{A}" opacity="0.35" filter="url(#g)"/>',
              r(990, 124, 560, 628, 30, "url(#k)", A, 4), r(1010, 144, 520, 4, 2, A, extra='opacity="0.6"'),
              t(1270, 470, "GO", 190, T["gotext"], 800, "middle", fam=MONO),
              t(1270, 540, "NEXT ▸ 04  M1 本編", 26, T["soft"], 700, "middle"),
              t(1270, 712, "SHOW LOCK OK", 18, T["lab"], 700, "middle", fam=MONO, ls=4)]
    o.append(r(1620, 96, 68, 684, 0, T["top"]))
    for i in range(5):
        cy = 170 + i * 128
        o.append(f'<circle cx="1654" cy="{cy}" r="{7 if i == 3 else 5}" fill="{A if i == 3 else "#3A3A3A"}"/>')
    if T["metal"]:
        o.append(screws((14, 1674), (110, 766)))
    return "".join(o)


def watch(T):
    A = T["acc"]
    o = [r(0, 0, 416, 496, 0, T["bg"]),
         '<defs><filter id="gw" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="5"/></filter>'
         f'<linearGradient id="kw" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{T["key1"]}"/><stop offset="1" stop-color="{T["key2"]}"/></linearGradient></defs>']
    for i, lab in enumerate(("M", "B")):
        x = 150 + i * 116
        o.append(f'<circle cx="{x}" cy="44" r="8" fill="{T["led"]}" filter="url(#gw)"/><circle cx="{x}" cy="44" r="5" fill="{T["led"]}"/>')
        o.append(t(x + 14, 51, lab, 20, "#AAA", 700, fam=MONO))
    cx, cy, rr, frac = 208, 262, 150, 0.58
    end = -math.pi / 2 + 2 * math.pi * frac
    ex, ey = cx + rr * math.cos(end), cy + rr * math.sin(end)
    if T["metal"]:
        o += [f'<circle cx="{cx}" cy="{cy}" r="{rr}" fill="none" stroke="#25282E" stroke-width="10"/>']
        for i in range(60):
            a = -math.pi / 2 + 2 * math.pi * i / 60
            on = i / 60 < frac
            o.append(f'<line x1="{cx + 140 * math.cos(a):.1f}" y1="{cy + 140 * math.sin(a):.1f}" x2="{cx + 160 * math.cos(a):.1f}" '
                     f'y2="{cy + 160 * math.sin(a):.1f}" stroke="{A if on else "#2E3238"}" stroke-width="4"/>')
        o += [f'<circle cx="{cx}" cy="{cy}" r="118" fill="url(#kw)" stroke="{A}" stroke-width="8"/>']
    else:
        o += [f'<circle cx="{cx}" cy="{cy}" r="{rr}" fill="none" stroke="{T["off"]}" stroke-width="14"/>',
              f'<path d="M{cx} {cy - rr} A{rr} {rr} 0 1 1 {ex:.1f} {ey:.1f}" fill="none" stroke="{A}" stroke-width="14" stroke-linecap="round"/>',
              f'<circle cx="{cx}" cy="{cy}" r="118" fill="url(#kw)" stroke="{A}" stroke-width="3"/>']
    o += [t(cx, cy + 22, "GO", 84, T["gotext"], 800, "middle", fam=MONO),
          t(cx, cy + 66, "-0:42", 26, T["soft"], 700, "middle", fam=MONO),
          t(cx, 466, "NEXT 04  M1 本編", 24, "#DDD", 700, "middle")]
    return "".join(o)


def main():
    out = os.path.join(ROOT, "docs", "design")
    for k, T in THEMES.items():
        svg = sheet(T["title"].split()[0], " ".join(T["title"].split()[1:]), T["note"], phone(T), watch(T), k)
        open(os.path.join(out, f"restyle-{k}.svg"), "w", encoding="utf-8").write(svg + "\n")
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "a.svg")
            open(src, "w", encoding="utf-8").write(svg)
            subprocess.run(["rsvg-convert", "-w", "1680", "-o", os.path.join(out, f"restyle-{k}.png"), src], check=True)
    print("written")


if __name__ == "__main__":
    main()
