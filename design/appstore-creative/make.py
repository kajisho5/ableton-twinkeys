#!/usr/bin/env python3
"""App Store creative assets for TwinKeys Remote: the product page header (21:9 video, 3840x1646) and the
search results image (3:2, 3840x2560), in Japanese and English. Design: docs/design-appstore-creative.md.

One drawing makes both the design mockups and the final files, so they always match:
  python3 design/appstore-creative/make.py mockup   docs/design/appstore-*.svg/png (stills and storyboard)
  python3 design/appstore-creative/make.py final    deliverables/appstore-creative/ (PNG and 15 s MP4)

Apple's specifications (checked 2026-11-12):
  https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications
Needs rsvg-convert (librsvg), ffmpeg and the Noto Sans CJK JP font.
"""

import math
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT = "Noto Sans CJK JP"

BG1, BG2 = "#18223A", "#06090F"
GREEN, GREEN_D, RED, RED_D, BLUE, YELLOW = "#4CD366", "#0A2A12", "#C62A20", "#4A1512", "#4A9EFF", "#F5B83D"
CARD, CARD2, LINE, GRAY, WHITE = "#1C1C1E", "#2C2C2E", "#3A3A3C", "#8E8E93", "#FFFFFF"
CLIP_COLORS = ["#E5533D", "#F0A030", "#3FA34D", "#2F80ED", "#8E5BD9", "#D64F9C"]

T = {
    "ja": {
        "headline": "本番を、止めない。",
        "cap_fire": "GO を1回。メインとバックアップの Mac が同時に再生",
        "cap_lost": "メインの Mac が止まっても、バックアップは鳴り続ける",
        "cap_switch": "iPhone の操作の届け先をバックアップに切り替えて、そのまま続行",
        "search_head": "iPhone から、2台の Mac の Live を同時に",
        "search_sub": "2台が同時に鳴るので、メインの Mac が止まっても音は止まりません",
        "status_ok": "Main ✓ Backup ✓ Live ✓", "status_ms": "2 ms",
        "status_lost": "Main × Backup ✓", "status_lost2": "メイン切断中",
        "status_sw": "Backup（メイン）", "status_sw2": "Main：切断中",
        "notes_off": "全ノートオフ", "now": "いま再生中", "next": "次", "left": "残り",
        "go_sub": "次のシーンを再生", "go_lock": "本番ロック中も使えます", "prev": "◀ 前へ", "fwd": "次へ ▶",
        "live_sel": "Live で選んでいるシーン",
        "banner": "⚠ メインの Mac が応答しません（3 秒）", "banner_btn": "バックアップに切り替える",
        "dlg_title": "バックアップに切り替えますか？", "dlg_cancel": "やめる", "dlg_hold": "長押しで切り替え",
        "strip": "バックアップに切り替え中：Backup Stage Mac がメインです",
        "rail": ["セッション", "ミキサー", "キュー", "GO", "設定"],
        "main": "メイン", "backup": "バックアップ", "playing": "再生中", "noanswer": "応答なし",
        "nowmain": "鳴り続け・iPhone から操作", "scene3": "M1 イントロ", "scene4": "M1 本編", "scene5": "M2 オープニング",
    },
    "en": {
        "headline": "Keep the show running.",
        "cap_fire": "One GO plays on the main and the backup Mac at once",
        "cap_lost": "If the main Mac stops, the backup keeps playing…",
        "cap_switch": "…send your iPhone's controls to the backup and carry on",
        "search_head": "Control Live on two Macs from your iPhone",
        "search_sub": "Both Macs play at once: if the main stops, the sound does not",
        "status_ok": "Main ✓ Backup ✓ Live ✓", "status_ms": "2 ms",
        "status_lost": "Main × Backup ✓", "status_lost2": "Main disconnected",
        "status_sw": "Backup (main)", "status_sw2": "Main: disconnected",
        "notes_off": "All Notes Off", "now": "Now playing", "next": "Next", "left": "Left",
        "go_sub": "Play next scene", "go_lock": "Works while the show lock is on", "prev": "◀ Back", "fwd": "Next ▶",
        "live_sel": "Scene selected in Live",
        "banner": "⚠ The main Mac is not answering (3 s)", "banner_btn": "Switch to backup",
        "dlg_title": "Switch to the backup?", "dlg_cancel": "Cancel", "dlg_hold": "Hold to switch",
        "strip": "Switched to backup: Backup Stage Mac is now the main Mac",
        "rail": ["Session", "Mixer", "Cues", "GO", "Settings"],
        "main": "Main", "backup": "Backup", "playing": "Playing", "noanswer": "Not answering",
        "nowmain": "Still playing · iPhone controls it", "scene3": "M1 Intro", "scene4": "M1 Main", "scene5": "M2 Opening",
    },
}


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def txt(x, y, s, size, fill=WHITE, weight=400, anchor="start", opacity=1.0, family=FONT):
    op = f' opacity="{opacity:.3f}"' if opacity < 1 else ""
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-family="{family}" font-size="{size}" font-weight="{weight}" '
            f'fill="{fill}" text-anchor="{anchor}"{op}>{esc(s)}</text>')


def rect(x, y, w, h, rx, fill, stroke=None, sw=0, opacity=1.0):
    st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    op = f' opacity="{opacity:.3f}"' if opacity < 1 else ""
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{rx:.1f}" fill="{fill}"{st}{op}/>'


def clamp(v, a=0.0, b=1.0):
    return max(a, min(b, v))


def ease(v):
    v = clamp(v)
    return v * v * (3 - 2 * v)


# ------------------------------------------------------------------------------------------------
# TwinKeys Remote GO screen, drawn on its own 1688 x 780 canvas (the app's landscape layout)


def go_screen(st, t):
    """TwinKeys Remote 1.3 GO screen in the A1 "green LED" look (design/restyle/make_a1.py), on its 1688 x 780
    canvas. st: phase ('idle'|'press'|'fired'|'lost'|'hold'|'switched'), progress, press, hold, lang."""
    L = T[st["lang"]]
    ph = st["phase"]
    G, R, Y, TOP, PANEL, ST, LAB, MONO = "#3DFF7A", "#FF3B30", "#FFB020", "#070707", "#060606", "#2A2A2A", "#6B6B6B", "JetBrains Mono"

    def led(x, y, col, rr=6):
        return (f'<circle cx="{x}" cy="{y}" r="{rr + 3}" fill="{col}" filter="url(#ledglow)"/>'
                f'<circle cx="{x}" cy="{y}" r="{rr}" fill="{col}"/>')

    o = ['<defs><filter id="ledglow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6"/></filter>'
         '<linearGradient id="gokey" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0E2416"/>'
         '<stop offset="1" stop-color="#050B07"/></linearGradient></defs>',
         rect(0, 0, 1688, 780, 0, "#000000"), rect(0, 0, 1688, 96, 0, TOP),
         f'<line x1="0" y1="96" x2="1688" y2="96" stroke="{ST}" stroke-width="2"/>']
    cols = {"lost": (R, G, G), "hold": (R, G, G), "switched": ("#444444", Y, G)}.get(ph, (G, G, G))
    for i, (lab, col) in enumerate(zip(("MAIN", "BACKUP", "LIVE"), cols)):
        x = 40 + i * 150
        o += [led(x, 40, col), txt(x + 18, 47, lab, 20, "#EDEDED" if col != "#444444" else "#666666", 700, family=MONO)]
    sub = {"lost": (L["status_lost2"], R), "hold": (L["status_lost2"], R), "switched": (L["status_sw"], Y)}.get(ph, ("LAT 2 ms", LAB))
    o.append(txt(40, 80, sub[0], 17, sub[1], 700, family=MONO if sub[0].startswith("LAT") else FONT))
    o += [rect(520, 18, 92, 60, 10, "#0E2416", G, 2), f'<path d="M554 34 L582 48 L554 62 Z" fill="{G}"/>',
          rect(624, 18, 92, 60, 10, PANEL, ST, 2), rect(658, 36, 24, 24, 3, "#DDDDDD"),
          rect(748, 16, 190, 66, 8, "#000000", ST, 2), txt(762, 40, "TEMPO", 13, LAB, 700, family=MONO),
          txt(762, 74, "124.00", 32, "#EDEDED", 700, family=MONO), txt(888, 74, "BPM", 15, "#9A9A9A", 400),
          rect(950, 16, 170, 66, 8, "#000000", ST, 2), txt(964, 40, "POSITION", 13, LAB, 700, family=MONO),
          txt(964, 74, "17.3.1", 32, "#EDEDED", 700, family=MONO),
          rect(1300, 18, 230, 60, 10, "#1A0605", R, 2), txt(1415, 57, L["notes_off"], 24, R, 700, "middle"),
          rect(1546, 18, 60, 60, 10, PANEL, ST, 2)]
    # rail with LEDs
    o.append(rect(1620, 96, 68, 684, 0, TOP))
    for i in range(5):
        cy = 170 + i * 128
        o.append(led(1654, cy, G, 5) if i == 3 else f'<circle cx="1654" cy="{cy}" r="5" fill="#3A3A3A"/>')
    fired = ph not in ("idle", "press")
    n_num, n_name, x_num, x_name = ("04", L["scene4"], "05", L["scene5"]) if fired else ("03", L["scene3"], "04", L["scene4"])
    prog = clamp(st.get("progress", 0.55))
    left = int(42 * (1 - prog) + 6)
    o += [rect(32, 124, 930, 270, 14, PANEL, ST, 2), f'<rect x="32" y="124" width="6" height="270" fill="{G}"/>',
          txt(64, 166, "NOW PLAYING", 18, G, 700, family=MONO),
          txt(64, 250, n_num, 64, LAB, 700, family=MONO), txt(170, 250, n_name, 56, "#F2F2F2", 700),
          txt(64, 318, "REMAIN", 15, LAB, 700, family=MONO),
          txt(64, 360, f"-{left // 60}:{left % 60:02d}", 40, G, 700, family=MONO)]
    for i in range(40):
        o.append(rect(240 + i * 17.5, 330, 12, 26, 2, G if i < int(40 * prog) else "#151515"))
    o += [rect(32, 418, 930, 186, 14, PANEL, ST, 2), txt(64, 460, "NEXT", 18, "#9AF5B7", 700, family=MONO),
          txt(64, 546, x_num, 56, LAB, 700, family=MONO), txt(160, 546, x_name, 48, "#F2F2F2", 700),
          txt(64, 586, L["live_sel"], 20, "#9A9A9A"),
          rect(32, 628, 300, 124, 14, PANEL, ST, 2), txt(182, 702, L["prev"], 30, "#DDDDDD", 700, "middle"),
          rect(348, 628, 300, 124, 14, PANEL, ST, 2), txt(498, 702, L["fwd"], 30, "#DDDDDD", 700, "middle")]
    press = st.get("press", 0.0)
    o += [f'<rect x="990" y="124" width="560" height="628" rx="30" fill="{G}" opacity="{0.35 + 0.4 * press:.3f}" filter="url(#ledglow)"/>',
          rect(990, 124, 560, 628, 30, "url(#gokey)", G, 4), rect(1010, 144, 520, 4, 2, G),
          txt(1270, 470, "GO", 190, G, 800, "middle", family=MONO),
          txt(1270, 540, f"NEXT ▸ {x_num}  {x_name}", 26, "#9AF5B7", 700, "middle"),
          txt(1270, 712, L["go_lock"], 18, "#4C8F63", 700, "middle")]
    if press > 0:
        r_ = 40 + 180 * press
        o.append(f'<circle cx="1270" cy="560" r="{r_:.1f}" fill="{G}" opacity="{0.35 * (1 - press):.3f}"/>')
        o.append(f'<circle cx="1270" cy="560" r="46" fill="#FFFFFF" opacity="{0.45 * (1 - press * 0.6):.3f}"/>')
    if ph == "lost":
        o += [rect(0, 98, 1620, 84, 0, "#1A0605"), f'<line x1="0" y1="182" x2="1620" y2="182" stroke="{R}" stroke-width="2"/>',
              led(40, 140, R), txt(62, 150, L["banner"].replace("⚠ ", ""), 28, "#FF9A92", 700),
              rect(1180, 108, 420, 64, 10, "#D70015"), txt(1390, 151, L["banner_btn"], 26, WHITE, 700, "middle")]
    if ph == "hold":
        o.append(rect(0, 98, 1620, 682, 0, "#000000", opacity=0.6))
        o += [rect(330, 230, 900, 380, 20, "#060606", ST, 2), txt(780, 310, L["dlg_title"], 40, "#EDEDED", 700, "middle"),
              rect(380, 440, 380, 110, 14, PANEL, ST, 2), txt(570, 508, L["dlg_cancel"], 30, "#DDDDDD", 700, "middle"),
              rect(800, 440, 380, 110, 14, "#3A0A06", R, 2),
              rect(800, 440, 380 * clamp(st.get("hold", 0)), 110, 14, "#D70015"),
              txt(990, 495, L["dlg_hold"], 32, WHITE, 700, "middle"),
              txt(990, 534, "1 秒" if st["lang"] == "ja" else "1 s", 22, WHITE, 700, "middle")]
    if ph == "switched":
        o += [rect(0, 98, 1620, 70, 0, "#0B1626"), f'<line x1="0" y1="168" x2="1620" y2="168" stroke="#8AB4FF" stroke-width="2"/>',
              txt(32, 144, L["strip"], 24, "#9CC8FF", 700)]
    return "".join(o)


def phone(x, y, w, st, t):
    """iPhone in landscape: body, screen with the GO screen. (x, y) is the top-left corner."""
    b = w * 0.022
    sw = w - 2 * b
    ins = sw * 0.05  # the Dynamic Island side: the app keeps this strip free (safe area)
    s = (sw - ins) / 1688
    sh = 780 * s
    h = sh + 2 * b
    o = [f'<rect x="{x - 6:.1f}" y="{y + 18:.1f}" width="{w + 12:.1f}" height="{h:.1f}" rx="{h * 0.16:.1f}" '
         f'fill="#000000" opacity="0.45" filter="url(#soft)"/>',
         rect(x, y, w, h, h * 0.16, "#2A2C31", "#4A4D55", 3),
         f'<clipPath id="scr"><rect x="{x + b:.1f}" y="{y + b:.1f}" width="{sw:.1f}" height="{sh:.1f}" rx="{sh * 0.11:.1f}"/></clipPath>',
         f'<g clip-path="url(#scr)">' + rect(x + b, y + b, sw, sh, 0, "#000000")
         + f'<g transform="translate({x + b + ins:.1f} {y + b:.1f}) scale({s:.5f})">{go_screen(st, t)}</g></g>',
         rect(x + b + ins * 0.22, y + h / 2 - sh * 0.11, ins * 0.42, sh * 0.22, ins * 0.21, "#000000")]
    return "".join(o), h


def watch(cx, cy, size, lang, lost=False):
    """Apple Watch in the A1 look: M/B lamps, dark GO key in a glowing green ring."""
    G = "#3DFF7A"
    w, h = size, size * 1.2
    x, y = cx - w / 2, cy - h / 2
    o = [rect(x + w * 0.18, y - h * 0.32, w * 0.64, h * 0.4, w * 0.12, "#2A2C31"),
         rect(x + w * 0.18, y + h * 0.92, w * 0.64, h * 0.4, w * 0.12, "#2A2C31"),
         rect(x, y, w, h, w * 0.3, "#3A3D44", "#5A5E66", 3),
         rect(x + w * 0.07, y + w * 0.07, w * 0.86, h - w * 0.14, w * 0.24, "#000000"),
         rect(x + w + 2, y + h * 0.28, w * 0.06, h * 0.16, w * 0.03, "#5A5E66")]
    for i, lab in enumerate(("M", "B")):
        lx = cx - w * 0.18 + i * w * 0.3
        col = "#FF3B30" if (lost and i == 0) else G
        o.append(f'<circle cx="{lx:.1f}" cy="{y + h * 0.17:.1f}" r="{w * 0.025:.1f}" fill="{col}"/>')
        o.append(txt(lx + w * 0.05, y + h * 0.19, lab, w * 0.06, "#AAAAAA", 700, family="JetBrains Mono"))
    r_ = w * 0.27
    gy = cy + h * 0.03
    o += [f'<circle cx="{cx:.1f}" cy="{gy:.1f}" r="{r_ + w * 0.05:.1f}" fill="none" stroke="{G}" stroke-width="{w * 0.035:.1f}" opacity="0.9"/>',
          f'<circle cx="{cx:.1f}" cy="{gy:.1f}" r="{r_:.1f}" fill="#06140A" stroke="{G}" stroke-width="{w * 0.012:.1f}"/>',
          txt(cx, gy + w * 0.07, "GO", w * 0.2, G, 800, "middle", family="JetBrains Mono"),
          txt(cx, y + h * 0.9, T[lang]["scene4"], w * 0.075, WHITE, 700, "middle")]
    return "".join(o)


def mac(x, y, w, role, state, row, lang):
    """MacBook with a Live-style session grid. state: 'ok' | 'lost' | 'main' (the backup now leads)."""
    L = T[lang]
    h = w * 0.64
    o = [f'<rect x="{x:.1f}" y="{y + 14:.1f}" width="{w:.1f}" height="{h:.1f}" rx="22" fill="#000" opacity="0.45" filter="url(#soft)"/>',
         rect(x, y, w, h, 22, "#2A2C31", "#4A4D55", 3), rect(x + 14, y + 14, w - 28, h - 28, 12, "#0D0F14")]
    # base
    bw, bh = w * 1.14, w * 0.05
    bx = x + w / 2 - bw / 2
    o.append(f'<path d="M{x - 4:.1f} {y + h:.1f} H{x + w + 4:.1f} L{bx + bw:.1f} {y + h + bh * 0.7:.1f} '
             f'Q{bx + bw:.1f} {y + h + bh:.1f} {bx + bw - 14:.1f} {y + h + bh:.1f} H{bx + 14:.1f} '
             f'Q{bx:.1f} {y + h + bh:.1f} {bx:.1f} {y + h + bh * 0.7:.1f} Z" fill="#43464E"/>')
    # session grid
    gx, gy, gw = x + 34, y + 70, w - 68
    o.append(txt(x + 34, y + 52, "Main Stage Mac" if role == "main" else "Backup Stage Mac", w * 0.034, GRAY, 700))
    cols, rows = 6, 4
    cw = (gw - 70) / cols
    ch = (h - 120) / (rows + 0.6)
    for c in range(cols):
        o.append(rect(gx + c * cw + 3, gy, cw - 6, ch * 0.5, 5, CLIP_COLORS[c]))
    for r in range(rows):
        ry = gy + ch * 0.62 + r * ch
        playing = (r == row)
        for c in range(cols):
            empty = (r + c * 2) % 5 == 3
            o.append(rect(gx + c * cw + 3, ry + 3, cw - 6, ch - 8, 6, "#000" if empty else "#1C1C1E",
                          GREEN if playing and not empty else "#2A2A2E", 3 if playing and not empty else 1.5))
            if not empty:
                o.append(rect(gx + c * cw + 3, ry + ch - 12, cw - 6, 4, 2, CLIP_COLORS[c]))
        o.append(rect(gx + cols * cw + 6, ry + 3, 58, ch - 8, 6, GREEN if playing else CARD2))
        cxp, cyp = gx + cols * cw + 35, ry + ch / 2 - 1
        o.append(f'<path d="M{cxp - 8:.1f} {cyp - 10:.1f} L{cxp + 10:.1f} {cyp:.1f} L{cxp - 8:.1f} {cyp + 10:.1f} Z" fill="#FFFFFF"/>')
    if state == "lost":
        o.append(rect(x + 14, y + 14, w - 28, h - 28, 12, "#2A0806", opacity=0.82))
        o.append(txt(x + w / 2, y + h / 2 + w * 0.03, L["noanswer"], w * 0.075, "#FF6B60", 800, "middle"))
    return "".join(o), h + bh


def caption_label(cx, y, name, sub, sub_col, badge):
    o = [txt(cx, y, name, 46, WHITE, 700, "middle"), txt(cx, y + 56, sub, 36, sub_col, 700, "middle")]
    if badge:
        bw = 46 * len(badge) * (0.95 if badge.isascii() else 1.05) + 60
        o.insert(0, rect(cx - bw / 2, y - 330 - 66, bw, 64, 32, GREEN))
    return "".join(o)


# ------------------------------------------------------------------------------------------------
# Scenes


def timeline(t):
    """Phase of the 15 s header video at time t (seconds)."""
    if t < 2.4:
        return "idle"
    if t < 2.9:
        return "press"
    if t < 5.6:
        return "fired"
    if t < 8.4:
        return "lost"
    if t < 10.6:
        return "hold"
    return "switched"


def defs():
    return (f'<defs><linearGradient id="bg" x1="0" y1="0" x2="0.3" y2="1"><stop offset="0" stop-color="{BG1}"/>'
            f'<stop offset="1" stop-color="{BG2}"/></linearGradient>'
            '<filter id="soft" x="-10%" y="-10%" width="120%" height="140%"><feGaussianBlur stdDeviation="22"/></filter>'
            '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="9"/></filter>'
            '</defs>')


def stage(t, lang, layout):
    """The scene: Watch - iPhone - bracket to Main (top) and Backup (bottom). layout: geometry dict."""
    L = T[lang]
    ph = timeline(t)
    g = layout
    o = []
    st = {"lang": lang, "phase": ph}
    if ph == "idle":
        st["progress"] = 0.5 + 0.02 * t
    elif ph == "press":
        st["progress"] = 0.55
        st["press"] = clamp((t - 2.4) / 0.5)
    else:
        st["progress"] = 0.04 + 0.02 * (t - 2.9)
    if ph == "hold":
        st["hold"] = clamp((t - 9.2) / 1.0)
    row = 2 if ph in ("idle", "press") else 3
    main_state = "lost" if ph in ("lost", "hold", "switched") or (ph == "fired" and t > 5.3) else "ok"
    # links
    px, py, pw = g["phone"]
    ph_svg, phh = phone(px, py, pw, st, t)
    pcy = py + phh / 2
    xj = g["xj"]
    mx, my_top, my_bot, mw = g["macs"]
    mh = mw * 0.64
    y_main, y_back = my_top + mh / 2, my_bot + mh / 2
    wx, wsize = g["watch"]
    link_ok = "#3E8E58"
    main_col = "#7A2A24" if main_state == "lost" else link_ok
    back_w = 10 if ph == "switched" else 7
    o.append(f'<line x1="{wx + wsize * 0.5 + 14:.1f}" y1="{pcy:.1f}" x2="{px - 14:.1f}" y2="{pcy:.1f}" stroke="{link_ok}" stroke-width="7" stroke-linecap="round"/>')
    o.append(f'<path d="M{px + pw + 14:.1f} {pcy:.1f} H{xj:.1f}" stroke="{link_ok}" stroke-width="7" fill="none"/>')
    o.append(f'<path d="M{xj:.1f} {pcy:.1f} V{y_main:.1f} H{mx - 16:.1f}" stroke="{main_col}" stroke-width="7" fill="none"'
             + (' stroke-dasharray="22 18"' if main_state == "lost" else "") + '/>')
    o.append(f'<path d="M{xj:.1f} {pcy:.1f} V{y_back:.1f} H{mx - 16:.1f}" stroke="{GREEN if ph == "switched" else link_ok}" stroke-width="{back_w}" fill="none"/>')
    if main_state == "lost":
        cx_, cy_ = (xj + mx) / 2, y_main
        o.append(f'<circle cx="{cx_:.1f}" cy="{cy_:.1f}" r="30" fill="{RED}"/>' + txt(cx_, cy_ + 13, "✕", 38, WHITE, 800, "middle"))
    # GO pulses travelling from the iPhone to both Macs at once
    if 2.9 <= t < 4.0:
        k = ease((t - 2.9) / 1.0)
        seg1 = xj - (px + pw + 14)
        for (ty_, alive) in ((y_main, True), (y_back, True)):
            seg2 = abs(ty_ - pcy)
            seg3 = mx - 16 - xj
            total = seg1 + seg2 + seg3
            d = k * total
            if d <= seg1:
                qx, qy = px + pw + 14 + d, pcy
            elif d <= seg1 + seg2:
                qx, qy = xj, pcy + math.copysign(d - seg1, ty_ - pcy)
            else:
                qx, qy = xj + (d - seg1 - seg2), ty_
            o.append(f'<circle cx="{qx:.1f}" cy="{qy:.1f}" r="26" fill="{GREEN}" filter="url(#glow)"/>'
                     f'<circle cx="{qx:.1f}" cy="{qy:.1f}" r="14" fill="#E9FFE9"/>')
    # devices
    o.append(watch(wx, pcy, wsize, lang, lost=main_state == "lost"))
    o.append(ph_svg)
    m_svg, _ = mac(mx, my_top, mw, "main", main_state, row, lang)
    b_svg, _ = mac(mx, my_bot, mw, "backup", "ok", row, lang)
    flash = 3.75 <= t < 4.4
    o += [m_svg, b_svg]
    if flash:
        a = 1 - (t - 3.75) / 0.65
        for yy in (my_top, my_bot):
            if yy == my_top and main_state == "lost":
                continue
            o.append(rect(mx - 10, yy - 10, mw + 20, mh + 20, 30, "none", GREEN, 10, opacity=0.9 * a))
    # labels to the right of the Macs
    lx = mx + mw + 50
    main_sub = (L["noanswer"], "#FF6B60") if main_state == "lost" else (L["playing"], GREEN)
    back_sub = (L["nowmain"], GREEN) if ph == "switched" else (L["playing"], GREEN)
    o.append(txt(lx, y_main - 6, L["main"], 50, WHITE, 700) + txt(lx, y_main + 52, main_sub[0], 38, main_sub[1], 700))
    o.append(txt(lx, y_back - 6, L["backup"], 50, WHITE, 700) + txt(lx, y_back + 52, back_sub[0], 38, back_sub[1], 700))
    return "".join(o)


HEADER = {"w": 3840, "h": 1646, "phone": (1020, 520, 1380), "xj": 2530, "macs": (2660, 330, 1010, 500),
          "watch": (780, 230)}


def header_svg(t, lang):
    L = T[lang]
    ph = timeline(t)
    cap = L["cap_fire"] if ph in ("idle", "press", "fired") else L["cap_lost"] if ph in ("lost", "hold") else L["cap_switch"]
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="1646" viewBox="0 0 3840 1646">', defs(),
         rect(0, 0, 3840, 1646, 0, "url(#bg)"), txt(1920, 230, L["headline"], 120, WHITE, 800, "middle")]
    o.append(stage(t, lang, HEADER))
    o.append(txt(1920, 1530, cap, 64, "#C9D1E0", 700, "middle"))
    # loop: fade to the background and back in to the first frame
    fade = clamp((t - 13.9) / 0.5) if t < 14.4 else clamp(1 - (t - 14.4) / 0.6)
    if t >= 13.9:
        o.append(rect(0, 0, 3840, 1646, 0, BG2, opacity=fade))
        if t >= 14.4:  # fading in the first frame: drawn underneath by the caller
            pass
    o.append("</svg>")
    return "".join(o)


def header_frame(t, lang):
    """The frame at t, with the loop's fade back into frame 0 for 14.4-15 s."""
    if t >= 14.4:
        base = header_svg(0.0, lang)
        a = clamp(1 - (t - 14.4) / 0.6)
        return base.replace("</svg>", rect(0, 0, 3840, 1646, 0, BG2, opacity=a) + "</svg>")
    return header_svg(t, lang)


SEARCH = {"w": 3840, "h": 2560, "phone": (540, 1090, 1960), "xj": 2660, "macs": (2790, 880, 1840, 600),
          "watch": (290, 270)}


def search_svg(lang):
    L = T[lang]
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="2560" viewBox="0 0 3840 2560">', defs(),
         rect(0, 0, 3840, 2560, 0, "url(#bg)"),
         txt(1920, 420, L["search_head"], 150 if lang == "ja" else 140, WHITE, 800, "middle"),
         txt(1920, 600, L["search_sub"], 80, "#C9D1E0", 700, "middle")]
    o.append(stage(1.0, lang, SEARCH))
    o.append("</svg>")
    return "".join(o)


# ------------------------------------------------------------------------------------------------


def render(svg_text, out_png, width=None):
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "a.svg")
        with open(src, "w", encoding="utf-8") as f:
            f.write(svg_text)
        cmd = ["rsvg-convert", "-o", out_png, src]
        if width:
            cmd[1:1] = ["-w", str(width)]
        subprocess.run(cmd, check=True)


def storyboard(lang):
    frames = [(1.0, "0–2.4 秒" if lang == "ja" else "0–2.4 s"), (3.5, "2.4–5.6 秒" if lang == "ja" else "2.4–5.6 s"),
              (9.6, "5.6–10.6 秒" if lang == "ja" else "5.6–10.6 s"), (12.0, "10.6–15 秒" if lang == "ja" else "10.6–15 s")]
    notes = {"ja": ["待機：GO の画面。2台の Mac は同じシーン", "GO を押す → 光が2台へ同時に届き、次のシーンが再生",
                    "メインが止まる（バックアップは鳴り続ける）→ 赤い帯 → 長押しで操作の届け先を切り替え", "iPhone からバックアップを操作して続行。最後に暗くなって最初に戻る（ループ）"],
             "en": ["Waiting: the GO screen; both Macs on the same scene", "Tap GO: light reaches both Macs at once, the next scene plays",
                    "The main Mac stops (the backup keeps playing): red banner, hold to switch the controls", "The iPhone controls the backup; fades back to the start (loop)"]}[lang]
    sw, sh = 1880, 1880 * 1646 / 3840
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="{2 * sh + 360:.0f}" viewBox="0 0 3840 {2 * sh + 360:.0f}">',
         rect(0, 0, 3840, 2 * sh + 360, 0, "#0B0D12")]
    for i, (t, label) in enumerate(frames):
        cx, cy = 40 + (i % 2) * (sw + 40), 40 + (i // 2) * (sh + 140)
        inner = header_frame(t, lang).replace('<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="1646" viewBox="0 0 3840 1646">', "")
        inner = inner.replace("</svg>", "").replace('id="scr"', f'id="scr{i}"').replace("url(#scr)", f"url(#scr{i})")
        o.append(f'<svg x="{cx}" y="{cy}" width="{sw}" height="{sh:.1f}" viewBox="0 0 3840 1646">{inner}</svg>')
        o.append(txt(cx, cy + sh + 60, f"{i + 1}. {label}　{notes[i]}", 40, WHITE, 700))
    o.append("</svg>")
    return "".join(o)


def mockup():
    out = os.path.join(ROOT, "docs", "design")
    for lang in ("ja", "en"):
        for name, svg in ((f"appstore-header-{lang}", header_frame(1.0, lang)),
                          (f"appstore-search-{lang}", search_svg(lang)),
                          (f"appstore-header-storyboard-{lang}", storyboard(lang))):
            with open(os.path.join(out, name + ".svg"), "w", encoding="utf-8") as f:
                f.write(svg + "\n")
            render(svg, os.path.join(out, name + ".png"), 1920)
    print("mockups written to docs/design/appstore-*")


def final():
    out = os.path.join(ROOT, "deliverables", "appstore-creative")
    os.makedirs(out, exist_ok=True)
    fps, seconds = 30, 15
    for lang in ("ja", "en"):
        render(search_svg(lang), os.path.join(out, f"search-results-{lang}-3840x2560.png"))
        render(header_frame(0.0, lang), os.path.join(out, f"header-poster-{lang}-3840x1646.png"))
        with tempfile.TemporaryDirectory() as tmp:
            from concurrent.futures import ThreadPoolExecutor
            with ThreadPoolExecutor(max_workers=os.cpu_count() or 2) as pool:
                list(pool.map(lambda i: render(header_frame(i / fps, lang), os.path.join(tmp, f"f{i:04d}.png")),
                              range(fps * seconds)))
            mp4 = os.path.join(out, f"header-{lang}-3840x1646-15s.mp4")
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(fps), "-i", os.path.join(tmp, "f%04d.png"),
                            "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
                            "-map", "0:v", "-map", "1:a", "-shortest", "-c:v", "libx264", "-profile:v", "high",
                            "-pix_fmt", "yuv420p", "-crf", "16", "-maxrate", "20M", "-bufsize", "40M", "-r", str(fps),
                            "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", mp4], check=True)
        print(f"{lang}: written")
    # flatten PNGs (no alpha) as Apple asks
    for name in os.listdir(out):
        if name.endswith(".png"):
            p = os.path.join(out, name)
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", p, "-pix_fmt", "rgb24", p + ".tmp.png"], check=True)
            shutil.move(p + ".tmp.png", p)


if __name__ == "__main__":
    {"mockup": mockup, "final": final}[sys.argv[1] if len(sys.argv) > 1 else "mockup"]()
