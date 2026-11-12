#!/usr/bin/env python3
"""Style A1 (green LED) applied to the other screens of TwinKeys Remote 1.3 (not implemented yet):
Session, Mixer, Cues, the GO screen when the main Mac stops, and the three Apple Watch screens.
Writes docs/design/restyle-a1-{session,mixer,cues,lost,watch}.svg/png."""
import math, os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make import t, r, ROOT, JP, MONO  # noqa: E402
import make_a  # noqa: E402

T = make_a.THEMES["a1"]
G, RED, YEL, BLUE = "#3DFF7A", "#FF3B30", "#FFB020", "#8AB4FF"
BG, TOP, PANEL, ST, LAB = T["bg"], T["top"], T["panel"], T["stroke"], T["lab"]
CLIPS = ["#FF5A45", "#FFA530", "#3DD26A", "#3D8BFF", "#A06BFF", "#FF5AAE"]
DEFS = ('<defs><filter id="g" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6"/></filter>'
        '<linearGradient id="k" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0E2416"/><stop offset="1" stop-color="#050B07"/></linearGradient></defs>')


def led(x, y, col, rr=6):
    return f'<circle cx="{x}" cy="{y}" r="{rr + 3}" fill="{col}" filter="url(#g)"/><circle cx="{x}" cy="{y}" r="{rr}" fill="{col}"/>'


def topbar(state="ok"):
    o = [r(0, 0, 1688, 96, 0, TOP), f'<line x1="0" y1="96" x2="1688" y2="96" stroke="{ST}" stroke-width="2"/>']
    cols = {"ok": (G, G, G), "lost": (RED, G, G), "sw": ("#444", YEL, G)}[state]
    for i, (lab, col) in enumerate(zip(("MAIN", "BACKUP", "LIVE"), cols)):
        x = 40 + i * 150
        o += [led(x, 40, col), t(x + 18, 47, lab, 20, "#EDEDED" if col != "#444" else "#666", 700, fam=MONO, ls=2)]
    o.append(t(40, 80, {"ok": "LAT 2 ms", "lost": "MAIN 応答なし 3 s", "sw": "BACKUP がメイン"}[state], 17,
               {"ok": LAB, "lost": RED, "sw": YEL}[state], 700, fam=MONO if state == "ok" else JP, ls=2 if state == "ok" else 0))
    o += [r(520, 18, 92, 60, 10, PANEL, ST, 2), f'<path d="M554 34 L582 48 L554 62 Z" fill="{G}"/>',
          r(624, 18, 92, 60, 10, PANEL, ST, 2), r(658, 36, 24, 24, 3, "#DDD"),
          r(748, 16, 170, 66, 8, "#000", ST, 2), t(762, 40, "TEMPO", 13, LAB, 700, fam=MONO, ls=3), t(762, 74, "124.00", 32, "#EDEDED", 700, fam=MONO),
          r(930, 16, 190, 66, 8, "#000", ST, 2), t(944, 40, "POSITION", 13, LAB, 700, fam=MONO, ls=3), t(944, 74, "017.3.1", 32, "#EDEDED", 700, fam=MONO),
          r(1300, 18, 230, 60, 10, "#1A0605", RED, 2), t(1415, 57, "全ノートオフ", 24, RED, 700, "middle"),
          r(1546, 18, 60, 60, 10, PANEL, ST, 2), r(1564, 44, 24, 20, 4, "#9A9A9A"),
          '<path d="M1569 44 v-6 a7 7 0 0 1 14 0 v6" fill="none" stroke="#9A9A9A" stroke-width="4"/>']
    return "".join(o)


def rail(active):
    o = [r(1620, 96, 68, 684, 0, TOP)]
    names = ["SES", "MIX", "CUE", "GO", "SET"]
    for i, n in enumerate(names):
        cy = 170 + i * 128
        on = i == active
        o += [led(1654, cy - 14, G, 5) if on else f'<circle cx="1654" cy="{cy - 14}" r="5" fill="#3A3A3A"/>',
              t(1654, cy + 20, n, 15, G if on else "#666", 700, "middle", fam=MONO, ls=1)]
    return "".join(o)


def label(x, y, s, col=None):
    return t(x, y, s, 16, col or LAB, 700, fam=MONO, ls=4)


def session():
    o = [r(0, 0, 1688, 780, 0, BG), DEFS, topbar(), rail(0), label(32, 136, "SCENES"),
         r(1100, 108, 360, 48, 8, "#000", ST, 2), t(1120, 141, "ジャンプ（番号か名前）", 22, "#555"),
         r(1472, 108, 130, 48, 8, PANEL, G, 2), t(1537, 140, "FOLLOW", 18, G, 700, "middle", fam=MONO, ls=2)]
    names = ["Music", "SE", "Amb", "Click", "Pad", "FX"]
    cw, x0, y0 = 218, 84, 176
    for c, n in enumerate(names):
        o += [r(x0 + c * cw, y0, cw - 12, 40, 6, "#0A0A0A", CLIPS[c], 2), f'<rect x="{x0 + c * cw}" y="{y0}" width="6" height="40" fill="{CLIPS[c]}"/>',
              t(x0 + c * cw + 18, y0 + 28, n.upper(), 18, "#DDD", 700, fam=MONO, ls=2)]
    o.append(t(x0 + 6 * cw + 50, y0 + 28, "SCENE", 16, LAB, 700, "middle", fam=MONO, ls=2))
    clips = [["Intro", "Applause", "Pad", None, "Pad 2", "Riser"], [None, "Applause", "Pad", "Count", None, "Riser"],
             ["Intro", None, "Pad", "Count", "Pad 2", None], ["Intro", "Applause", None, "Count", "Pad 2", "Riser"]]
    for rI, row in enumerate(clips):
        y = 232 + rI * 132
        o.append(t(52, y + 70, f"{rI + 1:02d}", 24, LAB, 700, "middle", fam=MONO))
        playing = rI == 2
        for c, name in enumerate(row):
            x = x0 + c * cw
            if name is None:
                o += [r(x, y, cw - 12, 116, 10, "#000", "#1C1C1C", 2), r(x + cw / 2 - 16, y + 48, 18, 18, 2, "#2A2A2A")]
                continue
            o += [r(x, y, cw - 12, 116, 10, PANEL, G if playing else ST, 3 if playing else 2),
                  f'<rect x="{x}" y="{y + 108}" width="{cw - 12}" height="8" rx="3" fill="{CLIPS[c]}" opacity="0.85"/>',
                  t(x + 16, y + 42, name, 24, "#EDEDED", 700)]
            if playing:
                o += [t(x + cw - 28, y + 42, "-0:14" if c == 0 else "-0:26", 20, G, 700, "end", fam=MONO)]
                for k in range(10):
                    o.append(r(x + 16 + k * 17, y + 70, 12, 18, 2, G if k < (6 if c == 0 else 3) else "#151515"))
        sx = x0 + 6 * cw
        o += [r(sx, y, 100, 116, 10, "#0E2416" if playing else PANEL, G if playing else ST, 3 if playing else 2),
              f'<path d="M{sx + 40} {y + 40} L{sx + 68} {y + 58} L{sx + 40} {y + 76} Z" fill="{G if playing else "#DDD"}"/>']
        if playing:
            o.append(led(sx + 86, y + 16, G, 4))
    return "".join(o)


def mixer():
    o = [r(0, 0, 1688, 780, 0, BG), DEFS, topbar(), rail(1), label(32, 136, "MIXER  ·  VOLUME")]
    chans = [("MUSIC", -6, 0.62), ("SE", -10, 0.5), ("AMB", -16, 0.36), ("CLICK", None, 0.0), ("PAD", -12, 0.48), ("FX", -18, 0.3), ("MASTER", -3, 0.74)]
    x0, w, top, bot = 40, 182, 196, 690
    for i, (n, db, lvl) in enumerate(chans):
        x = x0 + i * (w + 14)
        col = "#EDEDED" if n == "MASTER" else (CLIPS[i] if i < 6 else "#EDEDED")
        o += [r(x, 160, w, 600, 12, PANEL, ST, 2),
              t(x + w / 2, 186, "-∞" if db is None else f"{db} dB", 22, "#EDEDED", 700, "middle", fam=MONO)]
        # fader track with scale
        tx = x + 60
        o.append(r(tx, top, 10, bot - top, 5, "#141414"))
        for k in range(11):
            yy = top + (bot - top) * k / 10
            o.append(f'<line x1="{tx - 18}" y1="{yy}" x2="{tx - 6}" y2="{yy}" stroke="#333" stroke-width="2"/>')
        cap_y = bot - (bot - top) * (lvl if db is not None else 0.02)
        o += [r(tx - 26, cap_y - 20, 62, 40, 6, "#1A1A1A", "#555", 2), f'<line x1="{tx - 20}" y1="{cap_y}" x2="{tx + 30}" y2="{cap_y}" stroke="#EDEDED" stroke-width="3"/>']
        # LED meter
        mx = x + 128
        segs = 24
        on = int(segs * lvl * 1.05)
        for s_ in range(segs):
            yy = bot - (s_ + 1) * ((bot - top) / segs)
            c2 = RED if s_ >= segs - 2 else (YEL if s_ >= segs - 6 else G)
            o.append(r(mx, yy + 2, 26, (bot - top) / segs - 5, 2, c2 if s_ < on else "#141414"))
        o += [r(x + 10, 712, w - 20, 36, 6, "#000", col, 2), t(x + w / 2, 737, n, 17, col, 700, "middle", fam=MONO, ls=2)]
    bx = 1416
    for i, n in enumerate(("VOLUME", "PAN", "SEND A", "SEND B")):
        on = i == 0
        o += [r(bx, 160 + i * 110, 188, 92, 12, "#0E2416" if on else PANEL, G if on else ST, 2),
              t(bx + 94, 214 + i * 110, n, 20, G if on else "#BDBDBD", 700, "middle", fam=MONO, ls=2)]
    return "".join(o)


def cues():
    o = [r(0, 0, 1688, 780, 0, BG), DEFS, topbar(), rail(2), label(32, 136, "LAST CUE"),
         r(32, 152, 560, 190, 14, PANEL, ST, 2), r(56, 178, 120, 120, 12, "#000", ST, 2), t(116, 262, "↓", 64, "#EDEDED", 700, "middle"),
         t(200, 222, "次のシーン", 36, "#EDEDED", 700), t(200, 264, "#12", 22, LAB, 700, fam=MONO, ls=2),
         led(214, 304, G, 5), t(232, 311, "BACKUP にも届きました", 20, G, 700),
         label(32, 386, "CUE KEYS")]
    keys = [("↑", "前のシーン"), ("↓", "次のシーン"), ("←", "—"), ("→", "—"), ("SPACE", "再生"), ("RETURN", "選んだシーン"), ("ESC", "停止"), ("A", "SE 拍手"), ("B", "SE 歓声")]
    for i, (k, d) in enumerate(keys):
        cx, cy = 32 + (i % 3) * 190, 404 + (i // 3) * 122
        o += [r(cx, cy, 178, 110, 12, PANEL, ST, 2), t(cx + 89, cy + 52, k, 30 if len(k) < 3 else 22, "#EDEDED", 700, "middle", fam=MONO),
              t(cx + 89, cy + 90, d, 18, LAB, 400, "middle")]
    o += [label(640, 136, "MACS"), r(640, 152, 950, 190, 14, PANEL, ST, 2),
          led(680, 206, G), t(704, 214, "MAIN", 24, "#EDEDED", 700, fam=MONO, ls=2), t(830, 214, "Main Stage Mac ・ Live 接続済み", 22, LAB),
          led(680, 290, G), t(704, 298, "BACKUP", 24, "#EDEDED", 700, fam=MONO, ls=2), t(830, 298, "Backup Stage Mac ・ セット一致", 22, LAB),
          r(640, 404, 950, 350, 18, "#1A0605", RED, 4),
          f'<rect x="640" y="404" width="950" height="350" rx="18" fill="{RED}" opacity="0.12"/>',
          t(1115, 560, "ALL NOTES OFF", 64, RED, 800, "middle", fam=MONO, ls=4),
          t(1115, 630, "全ノートオフ（2台とも）", 32, "#FF9A92", 700, "middle")]
    return "".join(o)


def lost():
    # GO screen of A1 with the main Mac lost: red LED, red strip with the switch button
    base = make_a.phone(T)
    strip = (r(0, 98, 1620, 84, 0, "#1A0605") + f'<line x1="0" y1="182" x2="1620" y2="182" stroke="{RED}" stroke-width="2"/>'
             + led(40, 140, RED) + t(62, 150, "MAIN が応答しません（3 秒）", 30, "#FF9A92", 700)
             + r(1180, 108, 420, 64, 10, RED) + t(1390, 151, "長押しでバックアップへ", 26, "#FFF", 700, "middle"))
    return base.replace('</svg>', '') + topbar("lost") + strip


def frame(svg_inner, idd):
    return (f'<rect x="40" y="0" width="1808" height="900" rx="120" fill="#2A2C31" stroke="#4A4D55" stroke-width="3"/>'
            f'<clipPath id="s{idd}"><rect x="100" y="60" width="1688" height="780" rx="80"/></clipPath>'
            f'<g clip-path="url(#s{idd})"><g transform="translate(100 60)">{svg_inner}</g></g>'
            f'<rect x="104" y="380" width="20" height="140" rx="10" fill="#000"/>')


def phone_sheet(title, note, inner, idd):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1888" height="1100" viewBox="0 0 1888 1100">'
            + r(0, 0, 1888, 1100, 0, "#101114") + t(40, 80, title, 48, "#FFF", 800) + t(40, 136, note, 28, "#A0A4AD")
            + f'<g transform="translate(0 180)">{frame(inner, idd)}</g></svg>')


def watch_screen(kind):
    o = [r(0, 0, 416, 496, 0, "#000"),
         '<defs><filter id="gw" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="5"/></filter></defs>']
    def wled(x, y, c):
        return f'<circle cx="{x}" cy="{y}" r="8" fill="{c}" filter="url(#gw)"/><circle cx="{x}" cy="{y}" r="5" fill="{c}"/>'
    if kind == "go":
        return make_a.watch(T)
    if kind == "scenes":
        o += [t(208, 56, "SCENES", 22, G, 700, "middle", fam=MONO, ls=4)]
        rows = [("02", "SE 拍手", None), ("03", "M1 イントロ", "play"), ("04", "M1 本編", "next"), ("05", "暗転", None)]
        for i, (n, name, st) in enumerate(rows):
            y = 84 + i * 92
            o += [r(24, y, 368, 80, 14, "#0E2416" if st == "play" else "#060606", G if st == "play" else (BLUE if st == "next" else "#2A2A2A"), 3 if st else 2),
                  t(48, y + 52, n, 26, LAB, 700, fam=MONO), t(104, y + 52, name, 28, "#EDEDED", 700)]
            if st == "play":
                o.append(wled(366, y + 40, G))
            if st == "next":
                o.append(t(370, y + 50, "NEXT", 16, BLUE, 700, "end", fam=MONO, ls=2))
        o.append(t(208, 470, "タップで「次」に選ぶ", 20, LAB, 400, "middle"))
        return "".join(o)
    # all notes off
    o += [wled(150, 44, G), t(164, 51, "M", 20, "#AAA", 700, fam=MONO), wled(266, 44, G), t(280, 51, "B", 20, "#AAA", 700, fam=MONO),
          r(32, 90, 352, 300, 40, "#1A0605", RED, 5), f'<rect x="32" y="90" width="352" height="300" rx="40" fill="{RED}" opacity="0.14"/>',
          t(208, 230, "ALL", 56, RED, 800, "middle", fam=MONO, ls=4), t(208, 296, "NOTES OFF", 40, RED, 800, "middle", fam=MONO, ls=2),
          t(208, 348, "全ノートオフ", 24, "#FF9A92", 700, "middle"),
          t(208, 440, "直前：次のシーン ✓", 22, "#DDD", 700, "middle")]
    return "".join(o)


def watch_sheet():
    o = ['<svg xmlns="http://www.w3.org/2000/svg" width="1888" height="1100" viewBox="0 0 1888 1100">',
         r(0, 0, 1888, 1100, 0, "#101114"), t(40, 80, "A1 Apple Watch", 48, "#FFF", 800),
         t(40, 136, "左右のスワイプで3画面。M・B は2台の Mac のランプ", 28, "#A0A4AD")]
    for i, (kind, cap) in enumerate((("go", "1. GO（残り時間の輪）"), ("scenes", "2. シーンを選ぶ"), ("off", "3. 全ノートオフ"))):
        wx, wy = 110 + i * 600, 330
        o += [r(wx + 70, wy - 150, 336, 170, 50, "#2A2C31"), r(wx + 70, wy + 556, 336, 170, 50, "#2A2C31"),
              r(wx - 20, wy - 20, 516, 636, 130, "#3A3D44", "#5A5E66", 3),
              f'<clipPath id="w{i}"><rect x="{wx + 30}" y="{wy + 50}" width="416" height="496" rx="90"/></clipPath>',
              f'<g clip-path="url(#w{i})"><g transform="translate({wx + 30} {wy + 50})">{watch_screen(kind)}</g></g>',
              r(wx + 496, wy + 150, 22, 90, 11, "#5A5E66"),
              t(wx + 238, wy + 760, cap, 30, "#DDD", 700, "middle")]
    o.append("</svg>")
    return "".join(o)


def render(svg, name):
    out = os.path.join(ROOT, "docs", "design")
    open(os.path.join(out, name + ".svg"), "w", encoding="utf-8").write(svg + "\n")
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "a.svg")
        open(src, "w", encoding="utf-8").write(svg)
        subprocess.run(["rsvg-convert", "-w", "1600", "-o", os.path.join(out, name + ".png"), src], check=True)


def main():
    render(phone_sheet("A1 セッション", "クリップは細い線の枠。再生中は緑の枠とメーター。シーンの再生ボタンに緑のランプ", session(), "s"), "restyle-a1-session")
    render(phone_sheet("A1 ミキサー", "卓のようなフェーダーと、緑・黄・赤の LED メーター", mixer(), "m"), "restyle-a1-mixer")
    render(phone_sheet("A1 キュー", "直前のキュー、キュー用のキー、2台の Mac のランプ、大きな全ノートオフ", cues(), "c"), "restyle-a1-cues")
    render(phone_sheet("A1 メインの Mac が止まったとき", "MAIN のランプが赤。上に赤い帯と「長押しでバックアップへ」", lost(), "l"), "restyle-a1-lost")
    render(watch_sheet(), "restyle-a1-watch")
    print("written")


if __name__ == "__main__":
    main()
