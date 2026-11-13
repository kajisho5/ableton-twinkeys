#!/usr/bin/env python3
"""QLab mode (design only, not implemented): mockups in the A1 "green LED" style of TwinKeys Remote 1.3.
iPhone GO screen, iPhone cue list, Apple Watch, Mac settings panel and the system diagram.
All cue names and the workspace are made up. Writes docs/design/qlab-*.svg/png.
Run: python3 design/qlab/make_qlab.py   (needs rsvg-convert, Noto Sans CJK JP, JetBrains Mono)"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "restyle"))
from make import t, r, JP, MONO  # noqa: E402
import make_a1  # noqa: E402
from make_a1 import led, label, phone_sheet, DEFS, G, RED, YEL, BLUE, BG, TOP, PANEL, ST, LAB  # noqa: E402

DIM = "#9A9A9A"
TYPES = {"AUD": "#3D8BFF", "FADE": "#A06BFF", "GRP": "#9A9A9A", "MEMO": "#6B6B6B", "NET": "#FFA530", "WAIT": "#6B6B6B"}


def qtopbar(backup_ok=True):
    """Top strip in QLab mode: LEDs for both Macs and QLab, workspace, running count, PANIC, lock."""
    o = [r(0, 0, 1688, 96, 0, TOP), f'<line x1="0" y1="96" x2="1688" y2="96" stroke="{ST}" stroke-width="2"/>']
    for i, (lab, col) in enumerate((("MAIN", G), ("BACKUP", G if backup_ok else YEL), ("QLAB", G))):
        x = 40 + i * 150
        o += [led(x, 40, col), t(x + 18, 47, lab, 20, "#EDEDED", 700, fam=MONO, ls=2)]
    o.append(t(40, 80, "LAT 2 ms" if backup_ok else "BACKUP 位置 12 ≠ 13", 17, LAB if backup_ok else YEL, 700,
               fam=MONO if backup_ok else JP, ls=2 if backup_ok else 0))
    o += [r(520, 16, 330, 66, 8, "#000", ST, 2), t(534, 40, "WORKSPACE", 13, LAB, 700, fam=MONO, ls=3),
          t(534, 74, "sample-show", 30, "#EDEDED", 700, fam=MONO),
          r(862, 16, 200, 66, 8, "#000", ST, 2), t(876, 40, "RUNNING", 13, LAB, 700, fam=MONO, ls=3),
          t(876, 74, "2", 32, G, 700, fam=MONO), t(910, 74, "cues", 22, DIM, 700, fam=MONO),
          r(1074, 16, 210, 66, 8, "#000", ST, 2), t(1088, 40, "LIST", 13, LAB, 700, fam=MONO, ls=3),
          t(1088, 74, "Main", 30, "#EDEDED", 700, fam=MONO),
          r(1300, 18, 230, 60, 10, "#1A0605", RED, 2), t(1415, 57, "PANIC（2台）", 24, RED, 700, "middle"),
          r(1546, 18, 60, 60, 10, PANEL, ST, 2), r(1564, 44, 24, 20, 4, "#9A9A9A"),
          '<path d="M1569 44 v-6 a7 7 0 0 1 14 0 v6" fill="none" stroke="#9A9A9A" stroke-width="4"/>']
    return "".join(o)


def qrail(active):
    """Right rail in QLab mode: the Session and Mixer tabs are replaced by the cue list."""
    o = [r(1620, 96, 68, 684, 0, TOP)]
    for i, n in enumerate(["LIST", "KEYS", "GO", "SET"]):
        cy = 190 + i * 150
        on = i == active
        o += [led(1654, cy - 14, G, 5) if on else f'<circle cx="1654" cy="{cy - 14}" r="5" fill="#3A3A3A"/>',
              t(1654, cy + 20, n, 15, G if on else "#666", 700, "middle", fam=MONO, ls=1)]
    return "".join(o)


def go_screen():
    o = [r(0, 0, 1688, 780, 0, BG), DEFS, qtopbar(), qrail(2)]
    # NOW: the newest running cue, plus a second running cue in a small line
    o += [r(32, 124, 930, 300, 14, PANEL, ST, 2), f'<rect x="32" y="124" width="6" height="300" fill="{G}"/>',
          t(64, 166, "NOW PLAYING", 18, G, 700, fam=MONO, ls=4),
          r(780, 144, 70, 30, 6, "#000", TYPES["AUD"], 2), t(815, 166, "AUD", 16, TYPES["AUD"], 700, "middle", fam=MONO),
          r(860, 144, 80, 30, 6, "#000", ST, 2), t(900, 166, "3:20", 16, DIM, 700, "middle", fam=MONO),
          t(64, 246, "12", 64, LAB, 700, fam=MONO), t(160, 246, "雨の音（遠く）", 54, "#F2F2F2", 700),
          t(64, 304, "REMAIN", 15, LAB, 700, fam=MONO, ls=3), t(64, 346, "-1:08", 40, G, 700, fam=MONO)]
    for i in range(40):
        o.append(r(240 + i * 17.5, 316, 12, 26, 2, G if i < 14 else "#151515"))
    o += [f'<line x1="64" y1="368" x2="930" y2="368" stroke="{ST}" stroke-width="2"/>',
          led(72, 398, G, 4), t(90, 405, "11.5", 22, LAB, 700, fam=MONO), t(160, 405, "夜の環境音（ループ）", 24, "#DDD", 700),
          t(930, 405, "-3:40", 22, G, 700, "end", fam=MONO)]
    # NEXT: QLab's playhead (standing by), checked against the backup
    o += [r(32, 440, 930, 170, 14, PANEL, BLUE, 2), t(64, 480, "NEXT  ·  STANDING BY", 18, BLUE, 700, fam=MONO, ls=4),
          t(64, 556, "13", 56, LAB, 700, fam=MONO), t(150, 556, "雷鳴 1", 48, "#F2F2F2", 700),
          r(780, 456, 70, 30, 6, "#000", TYPES["AUD"], 2), t(815, 478, "AUD", 16, TYPES["AUD"], 700, "middle", fam=MONO),
          r(860, 456, 80, 30, 6, "#000", ST, 2), t(900, 478, "0:12", 16, DIM, 700, "middle", fam=MONO),
          led(72, 590, G, 4), t(88, 597, "BACKUP も 13 で待機中", 20, G, 700)]
    o += [r(32, 628, 300, 124, 14, PANEL, ST, 2), t(182, 690, "▲  前へ", 30, "#DDD", 700, "middle"),
          t(182, 726, "再生位置（2台）", 18, LAB, 400, "middle"),
          r(348, 628, 300, 124, 14, PANEL, ST, 2), t(498, 690, "次へ  ▼", 30, "#DDD", 700, "middle"),
          t(498, 726, "再生位置（2台）", 18, LAB, 400, "middle"),
          r(664, 628, 298, 124, 14, PANEL, ST, 2), t(813, 690, "STOP", 30, "#DDD", 700, "middle", fam=MONO, ls=2),
          t(813, 726, "長押し・2台", 18, LAB, 400, "middle")]
    # GO key (same as the Live GO key)
    o += [f'<rect x="990" y="124" width="560" height="628" rx="30" fill="{G}" opacity="0.35" filter="url(#g)"/>',
          r(990, 124, 560, 628, 30, "url(#k)", G, 4), r(1010, 144, 520, 4, 2, G, extra='opacity="0.6"'),
          t(1270, 200, "QLAB", 22, "#9AF5B7", 700, "middle", fam=MONO, ls=6),
          t(1270, 470, "GO", 190, G, 800, "middle", fam=MONO),
          t(1270, 540, "NEXT ▸ 13  雷鳴 1", 26, "#9AF5B7", 700, "middle"),
          t(1270, 670, "LAST GO 12   MAIN ✓  BACKUP ✓", 18, "#9AF5B7", 700, "middle", fam=MONO, ls=1),
          t(1270, 712, "SHOW LOCK OK", 18, LAB, 700, "middle", fam=MONO, ls=4)]
    return "".join(o)


CUES = [  # number, type, name, duration, state
    ("1", "MEMO", "開演前の確認", "", None),
    ("2", "AUD", "客入れ BGM", "18:00", "done"),
    ("3", "FADE", "客入れ BGM フェードアウト", "0:08", "done"),
    ("4", "AUD", "開演ベル", "0:06", "done"),
    ("10", "GRP", "第1場", "", "done"),
    ("11", "AUD", "鳥の声（朝）", "1:30", "done"),
    ("11.5", "AUD", "夜の環境音（ループ）", "∞", "run2"),
    ("12", "AUD", "雨の音（遠く）", "3:20", "run"),
    ("13", "AUD", "雷鳴 1", "0:12", "next"),
    ("14", "FADE", "雨 フェードアウト", "0:05", None),
    ("15", "NET", "映像へ合図", "", None),
]


def cuelist_screen():
    o = [r(0, 0, 1688, 780, 0, BG), DEFS, qtopbar(), qrail(0), label(32, 136, "CUE LIST  ·  MAIN  ·  48 CUES"),
         r(760, 108, 380, 48, 8, "#000", ST, 2), t(780, 141, "番号か名前で探す", 22, "#555"),
         r(1152, 108, 150, 48, 8, PANEL, G, 2), t(1227, 140, "FOLLOW", 18, G, 700, "middle", fam=MONO, ls=2)]
    y0, h = 164, 54
    o += [t(60, y0 + 4, "#", 14, LAB, 700, fam=MONO, ls=2), t(150, y0 + 4, "TYPE", 14, LAB, 700, fam=MONO, ls=2),
          t(260, y0 + 4, "NAME", 14, LAB, 700, fam=MONO, ls=2), t(1290, y0 + 4, "DUR", 14, LAB, 700, "end", fam=MONO, ls=2)]
    for i, (num, ty, name, dur, st) in enumerate(CUES):
        y = y0 + 16 + i * h
        stroke = {"run": G, "run2": G, "next": BLUE}.get(st, "#1C1C1C")
        fill = {"run": "#0E2416", "run2": "#08140C", "next": "#0A1220"}.get(st, PANEL)
        indent = 24 if num in ("11", "11.5", "12", "13", "14") else 0
        o += [r(32, y, 1270, h - 8, 8, fill, stroke, 2 if st in ("run", "run2", "next") else 1)]
        if st == "next":
            o.append(f'<path d="M40 {y + 12} L58 {y + 23} L40 {y + 34} Z" fill="{BLUE}"/>')
        if st in ("run", "run2"):
            o.append(led(49, y + 23, G, 5))
        col = "#5A5A5A" if st == "done" else "#EDEDED"
        o += [t(70, y + 32, num, 22, LAB if st == "done" else DIM, 700, fam=MONO),
              r(150 + indent, y + 9, 70, 28, 5, "#000", TYPES[ty], 2), t(185 + indent, y + 29, ty, 15, TYPES[ty], 700, "middle", fam=MONO),
              t(240 + indent + 10, y + 33, name, 24, col, 700),
              t(1290, y + 32, dur, 20, DIM if st != "done" else "#4A4A4A", 700, "end", fam=MONO)]
        if st in ("run", "run2"):
            left = "-1:08" if st == "run" else "-3:40"
            o.append(t(1150, y + 32, left, 20, G, 700, "end", fam=MONO))
            for k in range(12):
                o.append(r(800 + k * 14, y + 16, 10, 16, 2, G if k < (5 if st == "run" else 9) else "#151515"))
        if st == "next":
            o.append(t(1150, y + 32, "NEXT", 18, BLUE, 700, "end", fam=MONO, ls=2))
    # right side: what a tap does, and the backup check
    x = 1320
    o += [r(x, 108, 286, 330, 14, PANEL, ST, 2), label(x + 20, 146, "TAP A CUE"),
          t(x + 20, 190, "タップ：そこに", 22, "#EDEDED", 700), t(x + 20, 222, "再生位置を移す", 22, "#EDEDED", 700),
          t(x + 20, 254, "（2台とも）", 20, DIM), t(x + 20, 300, "GO はしません。", 20, DIM),
          t(x + 20, 332, "本番ロック中は", 20, DIM), t(x + 20, 362, "長押し 0.5 秒", 20, DIM),
          r(x, 456, 286, 296, 14, PANEL, ST, 2), label(x + 20, 494, "BACKUP"),
          led(x + 30, 532, G, 5), t(x + 48, 540, "48 キュー・同じ", 22, G, 700),
          led(x + 30, 578, G, 5), t(x + 48, 586, "位置 13・同じ", 22, G, 700),
          t(x + 20, 640, "違うときは黄色で", 20, DIM), t(x + 20, 670, "「バックアップの", 20, DIM),
          t(x + 20, 700, "キューが違います」", 20, DIM)]
    return "".join(o)


def watch_screen(kind):
    o = [r(0, 0, 416, 496, 0, "#000"),
         '<defs><filter id="gw" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="5"/></filter>'
         '<linearGradient id="kw" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0E2416"/><stop offset="1" stop-color="#050B07"/></linearGradient></defs>']

    def wled(x, y, c):
        return f'<circle cx="{x}" cy="{y}" r="8" fill="{c}" filter="url(#gw)"/><circle cx="{x}" cy="{y}" r="5" fill="{c}"/>'
    if kind == "go":
        for i, lab in enumerate(("M", "B", "Q")):
            x = 120 + i * 88
            o += [wled(x, 40, G), t(x + 14, 47, lab, 20, "#AAA", 700, fam=MONO)]
        o.append(t(208, 84, "12 雨の音（遠く）", 22, "#DDD", 700, "middle"))
        cx, cy, rr, frac = 208, 268, 132, 0.66
        end = -math.pi / 2 + 2 * math.pi * frac
        ex, ey = cx + rr * math.cos(end), cy + rr * math.sin(end)
        o += [f'<circle cx="{cx}" cy="{cy}" r="{rr}" fill="none" stroke="#151515" stroke-width="14"/>',
              f'<path d="M{cx} {cy - rr} A{rr} {rr} 0 1 1 {ex:.1f} {ey:.1f}" fill="none" stroke="{G}" stroke-width="14" stroke-linecap="round"/>',
              f'<circle cx="{cx}" cy="{cy}" r="104" fill="url(#kw)" stroke="{G}" stroke-width="3"/>',
              t(cx, cy + 20, "GO", 76, G, 800, "middle", fam=MONO),
              t(cx, cy + 60, "-1:08", 24, "#9AF5B7", 700, "middle", fam=MONO),
              t(cx, 470, "NEXT 13 雷鳴 1", 24, "#DDD", 700, "middle")]
        return "".join(o)
    if kind == "list":
        o += [t(208, 56, "CUES", 22, G, 700, "middle", fam=MONO, ls=4)]
        rows = [("11.5", "夜の環境音", "run"), ("12", "雨の音（遠く）", "run"), ("13", "雷鳴 1", "next"), ("14", "雨 F.O.", None)]
        for i, (n, name, st) in enumerate(rows):
            y = 80 + i * 90
            o += [r(20, y, 376, 78, 14, "#0E2416" if st == "run" else "#060606",
                    G if st == "run" else (BLUE if st == "next" else "#2A2A2A"), 3 if st else 2),
                  t(40, y + 50, n, 24, LAB, 700, fam=MONO), t(118, y + 50, name, 26, "#EDEDED", 700)]
            if st == "run":
                o.append(wled(372, y + 39, G))
            if st == "next":
                o.append(t(380, y + 48, "NEXT", 15, BLUE, 700, "end", fam=MONO, ls=2))
        o.append(t(208, 470, "タップで再生位置を移す", 20, LAB, 400, "middle"))
        return "".join(o)
    # panic
    o += [wled(150, 44, G), t(164, 51, "M", 20, "#AAA", 700, fam=MONO), wled(266, 44, G), t(280, 51, "B", 20, "#AAA", 700, fam=MONO),
          r(32, 90, 352, 300, 40, "#1A0605", RED, 5), f'<rect x="32" y="90" width="352" height="300" rx="40" fill="{RED}" opacity="0.14"/>',
          t(208, 250, "PANIC", 72, RED, 800, "middle", fam=MONO, ls=4),
          t(208, 330, "QLab を2台とも止める", 24, "#FF9A92", 700, "middle"),
          t(208, 440, "もう一度で即停止", 22, "#DDD", 700, "middle")]
    return "".join(o)


def watch_sheet():
    o = ['<svg xmlns="http://www.w3.org/2000/svg" width="1888" height="1100" viewBox="0 0 1888 1100">',
         r(0, 0, 1888, 1100, 0, "#101114"), t(40, 80, "QLab モード：Apple Watch", 48, "#FFF", 800),
         t(40, 136, "左右のスワイプで3画面。M・B は2台の Mac、Q は QLab。輪は今のキューの残り時間", 28, "#A0A4AD")]
    for i, (kind, cap) in enumerate((("go", "1. GO（今と次のキュー名）"), ("list", "2. キューの一覧"), ("off", "3. PANIC（2台）"))):
        wx, wy = 110 + i * 600, 330
        o += [r(wx + 70, wy - 150, 336, 170, 50, "#2A2C31"), r(wx + 70, wy + 556, 336, 170, 50, "#2A2C31"),
              r(wx - 20, wy - 20, 516, 636, 130, "#3A3D44", "#5A5E66", 3),
              f'<clipPath id="w{i}"><rect x="{wx + 30}" y="{wy + 50}" width="416" height="496" rx="90"/></clipPath>',
              f'<g clip-path="url(#w{i})"><g transform="translate({wx + 30} {wy + 50})">{watch_screen(kind)}</g></g>',
              r(wx + 496, wy + 150, 22, 90, 11, "#5A5E66"),
              t(wx + 238, wy + 760, cap, 30, "#DDD", 700, "middle")]
    o.append("</svg>")
    return "".join(o)


# ---- Mac settings panel (the Mac app's own dark settings look, with the A1 green for "OK") ----
MBG, MPANEL, MLINE, MTEXT, MDIM, MBLUE = "#1E1F23", "#2A2B30", "#3A3B41", "#EDEDED", "#A0A4AD", "#5AA9FF"
MG = "#3DD26A"


def box(x, y, w, h, rx=14, fill=MPANEL, stroke=MLINE):
    return r(x, y, w, h, rx, fill, stroke, 2)


def check(x, y, on=True, s="", col=MTEXT, size=24):
    o = r(x, y - 22, 28, 28, 6, MBLUE if on else "#1A1B1F", None if on else "#6A6D75", 2)
    if on:
        o += f'<path d="M{x + 6} {y - 8} l6 6 l11 -13" fill="none" stroke="#FFF" stroke-width="4"/>'
    return o + t(x + 42, y, s, size, col, 400)


def dot(x, y, col):
    return f'<circle cx="{x}" cy="{y}" r="8" fill="{col}"/>'


def mac_settings():
    W, H = 2480, 1640
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">', r(0, 0, W, H, 0, "#141518")]
    # left: the settings tab
    x0, y0 = 40, 40
    o += [box(x0, y0, 1220, 1560, 24, MBG), t(x0 + 40, y0 + 70, "設定 — QLab", 40, MTEXT, 800),
          t(x0 + 40, y0 + 118, "両方の Mac が、それぞれ自分の QLab に OSC で命令します（この Mac の中だけ、TCP 53000）", 24, MDIM),
          t(x0 + 40, y0 + 186, "TwinKeys が動かすもの", 26, MTEXT, 700)]
    seg = [("Ableton Live", False), ("QLab", True), ("両方", False)]
    for i, (s, on) in enumerate(seg):
        o += [r(x0 + 40 + i * 230, y0 + 206, 222, 58, 10, MBLUE if on else MPANEL, None if on else MLINE, 2),
              t(x0 + 151 + i * 230, y0 + 244, s, 26, "#FFF" if on else MTEXT, 700, "middle")]
    o += [t(x0 + 760, y0 + 244, "「両方」：Live と QLab の両方へ", 22, MDIM)]
    # connection
    y = y0 + 320
    o += [t(x0 + 40, y, "この Mac の QLab", 26, MTEXT, 700), box(x0 + 40, y + 20, 1140, 210),
          dot(x0 + 80, y + 70, MG), t(x0 + 104, y + 79, "QLab 5.6.5 に接続済み（TCP 127.0.0.1:53000）", 26, MG, 700),
          t(x0 + 80, y + 132, "ワークスペース", 22, MDIM), r(x0 + 80, y + 146, 420, 56, 10, "#1A1B1F", MLINE, 2),
          t(x0 + 100, y + 184, "sample-show", 26, MTEXT, 700, fam=MONO), t(x0 + 478, y + 184, "▾", 24, MDIM, 400, "end"),
          t(x0 + 540, y + 132, "パスコード（4桁）", 22, MDIM), r(x0 + 540, y + 146, 200, 56, 10, "#1A1B1F", MLINE, 2),
          t(x0 + 560, y + 184, "● ● ● ●", 24, MTEXT, 700, fam=MONO),
          t(x0 + 780, y + 132, "使える権限", 22, MDIM),
          dot(x0 + 790, y + 174, MG), t(x0 + 808, y + 182, "見る", 22, MTEXT),
          dot(x0 + 890, y + 174, MG), t(x0 + 908, y + 182, "操作", 22, MTEXT),
          dot(x0 + 990, y + 174, "#555"), t(x0 + 1008, y + 182, "編集（不要）", 22, MDIM)]
    o += [t(x0 + 40, y + 268, "パスコードはこの Mac のキーチェーンに保存します（もう片方の Mac には送りません）。", 22, MDIM),
          t(x0 + 40, y + 302, "「操作（control）」の権限がないと GO できません。QLab の 設定 → Network → OSC Access で付けます。", 22, MDIM)]
    # cue keys mapping
    y = y0 + 680
    o += [t(x0 + 40, y, "キューのキー → QLab の動き", 26, MTEXT, 700), box(x0 + 40, y + 20, 1140, 380)]
    rows = [("Space", "GO", "次のキューを GO（2台）"), ("↓", "次へ", "再生位置を1つ下へ"), ("↑", "前へ", "再生位置を1つ上へ"),
            ("Esc", "Panic", "2台とも Panic（もう一度で即停止）"), ("A", "キュー 90 を GO", "番号のキューへ移って GO"), ("Return", "なし", "（Live だけ）")]
    o += [t(x0 + 80, y + 64, "キー", 20, MDIM), t(x0 + 300, y + 64, "QLab の動き", 20, MDIM), t(x0 + 640, y + 64, "説明", 20, MDIM)]
    for i, (k, a, d) in enumerate(rows):
        yy = y + 112 + i * 48
        o += [r(x0 + 80, yy - 30, 150, 40, 8, "#1A1B1F", MLINE, 2), t(x0 + 155, yy - 2, k, 22, MTEXT, 700, "middle", fam=MONO),
              r(x0 + 300, yy - 30, 300, 40, 8, "#1A1B1F", MLINE, 2), t(x0 + 316, yy - 2, a, 22, MTEXT if a != "なし" else MDIM, 700),
              t(x0 + 578, yy - 2, "▾", 20, MDIM, 400, "end"), t(x0 + 640, yy - 2, d, 22, MDIM)]
    # options
    y = y0 + 1130
    o += [t(x0 + 40, y, "2台をそろえる", 26, MTEXT, 700),
          check(x0 + 50, y + 54, True, "バックアップの再生位置をメインに合わせる（おすすめ）"),
          t(x0 + 92, y + 88, "メインで再生位置が動くたび、バックアップの QLab も同じ番号のキューへ", 20, MDIM),
          check(x0 + 50, y + 140, True, "iPhone で見ていた「次」と違うときは GO しない"),
          t(x0 + 92, y + 174, "Mac の前で誰かが再生位置を動かした直後の、思わぬ GO を防ぎます", 20, MDIM),
          check(x0 + 50, y + 226, False, "MIDI ノートも出す（QLab だけのとき）"),
          t(x0 + 92, y + 260, "QLab の Workspace MIDI に TwinKeys を割り当てていると、2回動きます", 20, YEL),
          t(x0 + 40, y + 330, "キューの番号で2台を対応させます。番号のないキューは「次へ・前へ」だけで動かせます。", 20, MDIM)]
    # right top: both Macs
    x1 = 1300
    o += [box(x1, 40, 1140, 560, 24, MBG), t(x1 + 40, 110, "2台の QLab", 36, MTEXT, 800)]
    hdr = ["", "Main Stage Mac", "Backup Stage Mac"]
    for i, h_ in enumerate(hdr):
        o.append(t(x1 + 40 + i * 360, 170, h_, 24, MDIM, 700))
    lines = [("QLab", ("5.6.5 接続済み", MG), ("5.6.5 接続済み", MG)),
             ("ワークスペース", ("sample-show", MTEXT), ("sample-show", MTEXT)),
             ("権限", ("見る・操作", MG), ("見る・操作", MG)),
             ("キューの数", ("48", MTEXT), ("48 同じ", MG)),
             ("再生位置", ("13 雷鳴 1", MTEXT), ("13 同じ", MG)),
             ("動いているキュー", ("2", MTEXT), ("2", MTEXT)),
             ("本番モード", ("オン", MG), ("オフ", YEL))]
    for j, (k, a, b) in enumerate(lines):
        yy = 218 + j * 44
        o += [f'<line x1="{x1 + 40}" y1="{yy - 30}" x2="{x1 + 1100}" y2="{yy - 30}" stroke="{MLINE}"/>',
              t(x1 + 40, yy, k, 24, MDIM), t(x1 + 400, yy, a[0], 24, a[1], 700), t(x1 + 760, yy, b[0], 24, b[1], 700)]
    o += [r(x1 + 40, 560 - 34, 1060, 56, 10, "#2A2210", YEL, 2),
          t(x1 + 60, 563, "Backup Stage Mac の QLab が本番モード（Show Mode）ではありません", 22, YEL, 700)]
    # right middle: what happens on GO
    o += [box(x1, 630, 1140, 520, 24, MBG), t(x1 + 40, 700, "GO のとき（iPhone・キューのキー）", 36, MTEXT, 800)]
    steps = ["1. メインの QLab の再生位置が、iPhone で見ていた「13」か確かめる",
             "2. メインの QLab に /workspace/{id}/go（返事を受け取る設定で）",
             "3. 同時にバックアップの Mac へ「13 で GO」を送る（暗号化、0.1 秒ごとに送り直し）",
             "4. バックアップは自分の再生位置が 13 なら GO。違えば 13 へ移して GO",
             "5. 両方の返事と、再生位置が 14 に進んだことで「届いた ✓」",
             "   0.3 秒たっても返事がなければ赤で「バックアップから返事がありません」"]
    for i, s in enumerate(steps):
        o.append(t(x1 + 40, 770 + i * 58, s, 24, MTEXT if i < 5 else RED, 400))
    o += [t(x1 + 40, 1120, "GO 以外：次へ・前へ・Panic・Stop も同じ道で2台に届けます", 22, MDIM)]
    # right bottom: problems
    o += [box(x1, 1180, 1140, 420, 24, MBG), t(x1 + 40, 1250, "困ったときの表示", 36, MTEXT, 800)]
    probs = [(RED, "QLab が開いていません（TCP 53000 につながらない）"),
             (RED, "パスコードが違います（QLab は間違いが続くと待たせます）"),
             (YEL, "権限が「見る」だけ：表示はできますが GO できません"),
             (YEL, "ワークスペースが2つ開いています：使うものを選んでください"),
             (YEL, "バックアップのキューが違います（48 と 47）　［違いを見る］")]
    for i, (c, s) in enumerate(probs):
        yy = 1320 + i * 56
        o += [dot(x1 + 56, yy - 8, c), t(x1 + 80, yy, s, 24, MTEXT)]
    o.append("</svg>")
    return "".join(o)


# ---- system diagram ----
def system():
    W, H = 2480, 1400
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">', r(0, 0, W, H, 0, "#000"),
         '<defs><filter id="g" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6"/></filter>'
         '<marker id="ar" markerWidth="22" markerHeight="22" refX="18" refY="11" orient="auto" markerUnits="userSpaceOnUse"><path d="M0 0 L22 11 L0 22 Z" fill="#3DFF7A"/></marker>'
         '<marker id="ab" markerWidth="22" markerHeight="22" refX="18" refY="11" orient="auto" markerUnits="userSpaceOnUse"><path d="M0 0 L22 11 L0 22 Z" fill="#8AB4FF"/></marker>'
         '<marker id="ay" markerWidth="22" markerHeight="22" refX="18" refY="11" orient="auto" markerUnits="userSpaceOnUse"><path d="M0 0 L22 11 L0 22 Z" fill="#FFB020"/></marker></defs>',
         t(60, 90, "QLab モードのつながり", 52, "#FFF", 800),
         t(60, 146, "どちらの Mac も、自分の QLab にだけ OSC を送ります。Mac どうしは今の暗号化した回線のまま", 28, "#A0A4AD")]

    def mac(x, y, title, role, col):
        p = [r(x, y, 820, 760, 26, "#060606", ST, 3), led(x + 40, y + 50, col), t(x + 64, y + 60, role, 24, "#EDEDED", 700, fam=MONO, ls=3),
             t(x + 40, y + 110, title, 34, "#EDEDED", 700),
             r(x + 40, y + 150, 740, 170, 16, PANEL, G, 2), t(x + 70, y + 205, "TwinKeys", 32, G, 700, fam=MONO),
             t(x + 70, y + 250, "キューのキー・iPhone の受け口・2台の確認", 22, DIM),
             t(x + 70, y + 290, "QLab 接続（OSC/TCP、この Mac の中だけ）", 22, DIM),
             r(x + 40, y + 460, 740, 250, 16, PANEL, TYPES["AUD"], 2), t(x + 70, y + 515, "QLab 5", 32, TYPES["AUD"], 700, fam=MONO),
             t(x + 70, y + 560, "ワークスペース sample-show（同じファイル）", 22, DIM),
             t(x + 70, y + 600, "OSC Access：パスコード（見る・操作）", 22, DIM),
             t(x + 70, y + 640, "再生位置 13  ·  動いているキュー 2", 22, "#EDEDED", 700),
             f'<line x1="{x + 300}" y1="{y + 322}" x2="{x + 300}" y2="{y + 452}" stroke="{G}" stroke-width="4" marker-end="url(#ar)"/>',
             f'<line x1="{x + 520}" y1="{y + 456}" x2="{x + 520}" y2="{y + 328}" stroke="{BLUE}" stroke-width="4" marker-end="url(#ab)"/>',
             t(x + 330, y + 380, "/go など", 22, G, 700, fam=MONO), t(x + 330, y + 412, "127.0.0.1:53000", 20, G, 400, fam=MONO),
             t(x + 550, y + 380, "返事・/update", 22, BLUE, 700, fam=MONO), t(x + 550, y + 412, "（同じ TCP）", 20, BLUE, 400)]
        return "".join(p)
    o += [mac(80, 380, "Main Stage Mac", "MAIN", G), mac(1580, 380, "Backup Stage Mac", "BACKUP", G)]
    # link
    o += [f'<line x1="904" y1="600" x2="1572" y2="600" stroke="{G}" stroke-width="5" marker-end="url(#ar)"/>',
          f'<line x1="1576" y1="660" x2="908" y2="660" stroke="{BLUE}" stroke-width="5" marker-end="url(#ab)"/>',
          t(1240, 580, "「13 で GO」「再生位置 13」など", 26, G, 700, "middle"),
          t(1240, 712, "返事（✓）・バックアップの再生位置とキューの一覧の要約", 24, BLUE, 700, "middle"),
          t(1240, 752, "UDP 47801・合言葉の鍵で暗号化（今と同じ）", 22, DIM, 400, "middle")]
    # iPhone + watch
    px, py = 990, 200
    o += [r(px, py, 500, 150, 30, "#2A2C31", "#4A4D55", 3), r(px + 20, py + 18, 460, 114, 18, "#000"),
          t(px + 150, py + 86, "GO", 50, G, 800, "middle", fam=MONO), t(px + 300, py + 70, "NOW 12", 22, "#EDEDED", 700, fam=MONO),
          t(px + 300, py + 104, "NEXT 13", 22, BLUE, 700, fam=MONO),
          r(px + 560, py + 10, 130, 150, 34, "#3A3D44", "#5A5E66", 3), r(px + 576, py + 26, 98, 118, 22, "#000"),
          t(px + 625, py + 98, "GO", 30, G, 800, "middle", fam=MONO),
          t(px + 720, py + 70, "iPhone・Apple Watch", 26, "#EDEDED", 700), t(px + 720, py + 106, "（TwinKeys Remote）", 22, DIM),
          f'<path d="M{px + 120} {py + 152} C {px + 40} {py + 260}, 760 {py + 230}, 640 {py + 330}" fill="none" stroke="{G}" stroke-width="4" marker-end="url(#ar)"/>',
          t(px - 330, py + 230, "メインの Mac にだけつなぐ", 22, G, 700)]
    # outputs
    o += [r(80, 1190, 2320, 150, 20, "#060606", ST, 2),
          t(120, 1250, "音の出口：どちらの QLab の音も卓へ。切り替えは卓で（TwinKeys は音を切り替えない。Yamaha 卓の引き継ぎは 2.4 の試験機能）", 24, "#EDEDED", 700),
          t(120, 1300, "メインが止まったら：iPhone で「バックアップに切り替える」→ バックアップの Mac の TwinKeys が受け口になる（今と同じ）", 24, DIM)]
    o.append("</svg>")
    return "".join(o)


def render(svg, name, width=1600):
    import subprocess
    import tempfile
    out = os.path.join(make_a1.ROOT, "docs", "design")
    open(os.path.join(out, name + ".svg"), "w", encoding="utf-8").write(svg + "\n")
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "a.svg")
        open(src, "w", encoding="utf-8").write(svg)
        subprocess.run(["rsvg-convert", "-w", str(width), "-o", os.path.join(out, name + ".png"), src], check=True)


def main():
    render(phone_sheet("QLab モード：GO 画面", "今のキュー（残り時間）と次のキュー（QLab の再生位置）。バックアップも同じ位置かをランプで", go_screen(), "qg"), "qlab-iphone-go")
    render(phone_sheet("QLab モード：キューの一覧", "セッションとミキサーの代わり。動いているキューは緑、次（再生位置）は青", cuelist_screen(), "qc"), "qlab-iphone-cuelist")
    render(watch_sheet(), "qlab-watch")
    render(mac_settings(), "qlab-mac-settings", 2480)
    render(system(), "qlab-system", 2480)
    print("written")


if __name__ == "__main__":
    main()
