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
        "cap_lost": "メインの Mac が止まっても",
        "cap_switch": "iPhone からバックアップに切り替えて、そのまま続行",
        "search_head": "iPhone から、2台の Mac の Live を同時に",
        "search_sub": "メインの Mac が止まっても、バックアップで続けられます",
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
        "nowmain": "メインに切り替え", "scene3": "M1 イントロ", "scene4": "M1 本編", "scene5": "M2 オープニング",
    },
    "en": {
        "headline": "Keep the show running.",
        "cap_fire": "One GO plays on the main and the backup Mac at once",
        "cap_lost": "If the main Mac stops…",
        "cap_switch": "…switch to the backup from your iPhone and carry on",
        "search_head": "Control Live on two Macs from your iPhone",
        "search_sub": "If the main Mac stops, carry on with the backup",
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
        "nowmain": "Now the main Mac", "scene3": "M1 Intro", "scene4": "M1 Main", "scene5": "M2 Opening",
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
    """st: dict with phase ('idle'|'press'|'fired'|'lost'|'hold'|'switched'), progress, hold, lang."""
    L = T[st["lang"]]
    ph = st["phase"]
    o = [rect(0, 0, 1688, 780, 0, "#000000"), rect(0, 0, 1688, 104, 0, "#121214"),
         f'<line x1="0" y1="104" x2="1688" y2="104" stroke="{LINE}" stroke-width="2"/>']
    # top bar
    if ph in ("lost", "hold"):
        dot, s1, s2, c1 = RED, L["status_lost"], L["status_lost2"], RED
    elif ph == "switched":
        dot, s1, s2, c1 = YELLOW, L["status_sw"], L["status_sw2"], YELLOW
    else:
        dot, s1, s2, c1 = GREEN, L["status_ok"], L["status_ms"], WHITE
    o += [f'<circle cx="40" cy="38" r="10" fill="{dot}"/>', txt(62, 46, s1, 24, c1, 700),
          txt(62, 82, s2, 21, GRAY)]
    o += [rect(400, 16, 104, 72, 14, GREEN), '<path d="M440 32 L476 52 L440 72 Z" fill="#FFFFFF"/>',
          rect(516, 16, 104, 72, 14, CARD2), rect(554, 38, 28, 28, 4, WHITE),
          txt(657, 68, "124.00", 38, WHITE, 700), txt(790, 68, "BPM", 22, GRAY),
          txt(857, 68, "17. 3. 1", 34, WHITE, 700),
          rect(1288, 16, 200, 72, 14, RED), txt(1388, 63, L["notes_off"], 26, WHITE, 700, "middle"),
          rect(1504, 16, 72, 72, 14, CARD2), rect(1524, 50, 32, 26, 5, "#AEAEB2"),
          '<path d="M1530 50 v-8 a10 10 0 0 1 20 0 v8" fill="none" stroke="#AEAEB2" stroke-width="5"/>']
    # side rail
    o.append(rect(1560, 104, 128, 676, 0, "#0E0E10"))
    for i, name in enumerate(L["rail"]):
        cy = 170 + i * 128
        active = name in ("GO",)
        if active:
            o.append(rect(1572, cy - 58, 104, 116, 18, "#1E1E22"))
        col = BLUE if active else "#AEAEB2"
        o.append(rect(1600, cy - 36, 48, 36, 9, "none", col, 3))
        o.append(txt(1624, cy + 34, name, 19 if st["lang"] == "en" else 20, col, 700 if active else 400, "middle"))
    # cards (before / after the GO)
    fired = ph not in ("idle", "press")
    n_num, n_name, x_num, x_name = ("4", L["scene4"], "5", L["scene5"]) if fired else ("3", L["scene3"], "4", L["scene4"])
    prog = st.get("progress", 0.55)
    o += [rect(32, 128, 920, 264, 24, CARD, GREEN, 3), txt(64, 176, L["now"], 22, GREEN, 700),
          txt(64, 262, n_num, 64, GRAY, 700), txt(140, 262, n_name, 54, WHITE, 700),
          txt(64, 316, L["left"], 22, GRAY), txt(126 if st["lang"] == "ja" else 116, 318,
                                                 f"-{int(42 * (1 - prog) + 6) // 60}:{int(42 * (1 - prog) + 6) % 60:02d}",
                                                 30, GREEN, 700, family="Noto Sans Mono CJK JP"),
          rect(240, 298, 680, 12, 6, "#333336"), rect(240, 298, 680 * clamp(prog), 12, 6, GREEN),
          txt(64, 362, "Intro ・ Pad", 22, GRAY),
          rect(32, 416, 920, 192, 24, CARD, LINE, 2), txt(64, 462, L["next"], 22, BLUE, 700),
          txt(64, 548, x_num, 52, GRAY, 700), txt(134, 548, x_name, 46, WHITE, 700),
          txt(64, 590, L["live_sel"], 22, GRAY),
          rect(32, 632, 296, 120, 20, CARD2), txt(180, 704, L["prev"], 30, WHITE, 700, "middle"),
          rect(344, 632, 296, 120, 20, CARD2), txt(492, 704, L["fwd"], 30, WHITE, 700, "middle")]
    # GO button
    press = st.get("press", 0.0)
    go_fill = "#7EE493" if press > 0 else GREEN
    o += [rect(984, 128, 552, 624, 36, go_fill), txt(1260, 402, "GO", 160, GREEN_D, 800, "middle"),
          txt(1260, 480, L["go_sub"], 30, GREEN_D, 700, "middle"),
          txt(1260, 535, f"{x_num} {x_name}", 30, GREEN_D, 700, "middle"),
          txt(1260, 706, L["go_lock"], 22, GREEN_D, 700, "middle")]
    if press > 0:  # finger tap ripple
        r = 40 + 180 * press
        o.append(f'<circle cx="1260" cy="560" r="{r:.1f}" fill="#FFFFFF" opacity="{0.45 * (1 - press):.3f}"/>')
        o.append(f'<circle cx="1260" cy="560" r="46" fill="#FFFFFF" opacity="{0.55 * (1 - press * 0.6):.3f}"/>')
    # overlays
    if ph == "lost":
        o += [rect(0, 106, 1560, 84, 0, RED_D), txt(32, 160, L["banner"], 30, "#FF8A80", 700),
              rect(1180, 116, 360, 64, 14, RED), txt(1360, 159, L["banner_btn"], 26, WHITE, 700, "middle")]
    if ph == "hold":
        o.append(rect(0, 104, 1560, 676, 0, "#000000", opacity=0.55))
        o += [rect(330, 230, 900, 380, 30, "#1C1C1E", LINE, 2),
              txt(780, 310, L["dlg_title"], 40, WHITE, 700, "middle"),
              rect(380, 440, 380, 110, 20, CARD2), txt(570, 508, L["dlg_cancel"], 30, WHITE, 700, "middle"),
              rect(800, 440, 380, 110, 20, "#7A1A14"),
              rect(800, 440, 380 * clamp(st.get("hold", 0)), 110, 20, RED),
              txt(990, 495, L["dlg_hold"], 32, WHITE, 700, "middle"),
              txt(990, 534, "1 秒" if st["lang"] == "ja" else "1 s", 22, WHITE, 700, "middle")]
        if st.get("hold", 0) > 0:
            o.append(f'<circle cx="990" cy="495" r="52" fill="#FFFFFF" opacity="0.28"/>')
    if ph == "switched":
        o += [rect(0, 106, 1560, 70, 0, "#1A2638"), txt(32, 152, L["strip"], 26, "#9CC8FF", 700)]
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
    w, h = size, size * 1.2
    x, y = cx - w / 2, cy - h / 2
    o = [rect(x + w * 0.18, y - h * 0.32, w * 0.64, h * 0.4, w * 0.12, "#2A2C31"),
         rect(x + w * 0.18, y + h * 0.92, w * 0.64, h * 0.4, w * 0.12, "#2A2C31"),
         rect(x, y, w, h, w * 0.3, "#3A3D44", "#5A5E66", 3),
         rect(x + w * 0.07, y + w * 0.07, w * 0.86, h - w * 0.14, w * 0.24, "#000000"),
         rect(x + w + 2, y + h * 0.28, w * 0.06, h * 0.16, w * 0.03, "#5A5E66")]
    o.append(f'<circle cx="{cx:.1f}" cy="{cy - h * 0.06:.1f}" r="{w * 0.3:.1f}" fill="{GREEN}"/>')
    o.append(txt(cx, cy + w * 0.03, "GO", w * 0.2, GREEN_D, 800, "middle"))
    o.append(txt(cx, cy + h * 0.36, T[lang]["scene4"] if lang else "", w * 0.085, WHITE, 700, "middle"))
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
    o.append(watch(wx, pcy, wsize, lang))
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
                    "メインが止まる → 上に赤い帯 → 長押しで切り替え", "バックアップがメインに。最後に暗くなって最初に戻る（ループ）"],
             "en": ["Waiting: the GO screen; both Macs on the same scene", "Tap GO: light reaches both Macs at once, the next scene plays",
                    "The main Mac stops: red banner, hold to switch", "The backup leads; fades back to the start (loop)"]}[lang]
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
            for i in range(fps * seconds):
                render(header_frame(i / fps, lang), os.path.join(tmp, f"f{i:04d}.png"))
            mp4 = os.path.join(out, f"header-{lang}-3840x1646-15s.mp4")
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(fps), "-i", os.path.join(tmp, "f%04d.png"),
                            "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
                            "-map", "0:v", "-map", "1:a", "-shortest", "-c:v", "libx264", "-profile:v", "high",
                            "-pix_fmt", "yuv420p", "-b:v", "12M", "-maxrate", "14M", "-bufsize", "24M", "-r", str(fps),
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
