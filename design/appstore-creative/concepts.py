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


if __name__ == "__main__" and len(sys.argv) == 1:
    main()


# ------------------------------------------------------------------------------------------------
# Chosen: 2. TWIN LINES, as the 15 s header video and the search image (approved 2026-11-13)

RED = "#FF3B30"
TXT2 = {
    "ja": {"head": "ワンタップで、2台が同時に。", "c1": "MAIN と BACKUP、同じキューを同じ瞬間に。",
           "c2": "メインの Mac が止まっても、バックアップは鳴り続ける。",
           "c3": "iPhone の操作をバックアップへ。そのまま続行。",
           "search_head": "ワンタップで、2台の Mac が同時に。",
           "search_sub": "iPhone・Apple Watch から、メインとバックアップの Live を操作"},
    "en": {"head": "One tap. Two Macs.", "c1": "Main and backup fire the same cue at the same moment.",
           "c2": "If the main Mac stops, the backup keeps playing.",
           "c3": "Send your iPhone's controls to the backup and carry on.",
           "search_head": "One tap. Two Macs at once.",
           "search_sub": "Control Live on the main and the backup Mac from iPhone and Apple Watch"},
}


def beam_defs():
    return ('<defs><linearGradient id="beamR" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#FF3B30" stop-opacity="0"/>'
            '<stop offset="0.5" stop-color="#FF3B30" stop-opacity="1"/><stop offset="1" stop-color="#FF3B30" stop-opacity="0"/></linearGradient></defs>')


def line_row(y, label, state, a=1.0, xl=760, xr=3080):
    """state: 'on' (green), 'dead' (red, dim), 'lead' (green, brighter)."""
    grad, col = ("url(#beamR)", RED) if state == "dead" else ("url(#beam)", G)
    op = (0.35 if state == "dead" else 1.0) * a
    thick = 12 if state == "lead" else 8
    return (f'<rect x="0" y="{y - thick / 2}" width="3840" height="{thick}" fill="{grad}" opacity="{op:.3f}"/>'
            f'<rect x="0" y="{y - 34}" width="3840" height="68" fill="{grad}" opacity="{(0.12 if state == "dead" else 0.3 if state == "lead" else 0.22) * a:.3f}" filter="url(#glow)"/>'
            + led(xl, y, col, 14) + M.txt(xl - 50, y + 16, label, 48, "#EDEDED", 700, "end", family=MONO)
            + led(xr, y, col, 14) + M.txt(xr + 50, y + 16, label + (" ✕" if state == "dead" else ""), 48, "#EDEDED" if state != "dead" else "#FF9A92", 700, family=MONO))


def c2_frame(t, lang, w=3840, h=1646, phone_xyw=(1260, 330, 1320), ys=(560, 1090), head_y=190, cap_y=1480, head=None, caption=None):
    L = TXT2[lang]
    ph = M.timeline(t)
    st = {"lang": lang, "phase": ph}
    if ph == "idle":
        st["progress"] = 0.5 + 0.02 * t
    elif ph == "press":
        st["progress"], st["press"] = 0.55, M.clamp((t - 2.4) / 0.5)
    else:
        st["progress"] = 0.04 + 0.02 * (t - 2.9)
    if ph == "hold":
        st["hold"] = M.clamp((t - 9.2) / 1.0)
    dead = ph in ("lost", "hold", "switched") or (ph == "fired" and t > 5.3)
    # the main line fades from green to red over 5.3-5.9 s
    k = M.clamp((t - 5.3) / 0.6)
    main_state = "dead" if dead and k >= 0.5 else "on"
    back_state = "lead" if ph == "switched" else "on"
    px, py, pw = phone_xyw
    phone_svg, _ = M.phone(px, py, pw, st, t)
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">', defs(), beam_defs(),
         M.rect(0, 0, w, h, 0, "#000"),
         line_row(ys[0], "MAIN", main_state, a=(1 - abs(k - 0.5) * 2 * 0.6) if 5.3 <= t < 5.9 else 1.0),
         line_row(ys[1], "BACKUP", back_state)]
    # GO pulses race from the phone to both ends of both lines
    if 2.9 <= t < 4.1:
        q = M.ease((t - 2.9) / 1.2)
        cx = px + pw / 2
        for y in ys:
            for x in (cx + (3080 - cx) * q, cx - (cx - 760) * q):
                o.append(f'<circle cx="{x:.1f}" cy="{y}" r="34" fill="{G}" filter="url(#glow)"/><circle cx="{x:.1f}" cy="{y}" r="16" fill="#EAFFEF"/>')
    if 4.0 <= t < 4.6:  # the four lamps flash when the cue arrives
        a = 1 - (t - 4.0) / 0.6
        for y in ys:
            for x in (760, 3080):
                o.append(f'<circle cx="{x}" cy="{y}" r="{40 + 60 * (1 - a):.1f}" fill="none" stroke="{G}" stroke-width="6" opacity="{a:.3f}"/>')
    o.append(phone_svg)
    cap = caption or (L["c1"] if t < 5.6 else L["c2"] if t < 10.6 else L["c3"])
    o += [M.txt(w / 2, head_y, head or L["head"], 120, "#FFFFFF", 800, "middle"),
          M.txt(w / 2, cap_y, cap, 56, "#C9D1E0", 700, "middle"),
          M.rect(0, 0, w, h, 0, "url(#vig)")]
    if t >= 13.9:  # loop: fade to black, then the first frame fades in
        fade = M.clamp((t - 13.9) / 0.5) if t < 14.4 else 1.0
        o.append(M.rect(0, 0, w, h, 0, "#000", opacity=fade))
    o.append("</svg>")
    svg = "".join(o)
    if t >= 14.4:
        base = c2_frame(0.0, lang, w, h, phone_xyw, ys, head_y, cap_y, head, caption)
        return base.replace("</svg>", M.rect(0, 0, w, h, 0, "#000", opacity=M.clamp(1 - (t - 14.4) / 0.6)) + "</svg>")
    return svg


def c2_search(lang):
    L = TXT2[lang]
    return c2_frame(1.0, lang, 3840, 2560, (1110, 860, 1620), (1090, 1760), 380, 2300,
                    head=L["search_head"], caption=L["search_sub"])


def storyboard2(lang):
    frames = [1.0, 3.6, 9.6, 12.0]
    sw, sh = 1880, 1880 * 1646 / 3840
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="{2 * sh + 120:.0f}" viewBox="0 0 3840 {2 * sh + 120:.0f}">',
         M.rect(0, 0, 3840, 2 * sh + 120, 0, "#0B0D12")]
    for i, t in enumerate(frames):
        cx, cy = 40 + (i % 2) * (sw + 40), 40 + (i // 2) * (sh + 40)
        inner = c2_frame(t, lang).split(">", 1)[1].rsplit("</svg>", 1)[0].replace('id="scr"', f'id="scr{i}"').replace("url(#scr)", f"url(#scr{i})")
        o.append(f'<svg x="{cx}" y="{cy}" width="{sw}" height="{sh:.1f}" viewBox="0 0 3840 1646">{inner}</svg>')
    o.append("</svg>")
    return "".join(o)


def final2():
    out = os.path.join(M.ROOT, "deliverables", "appstore-creative")
    os.makedirs(out, exist_ok=True)
    from concurrent.futures import ThreadPoolExecutor
    fps, seconds = 30, 15
    for lang in ("ja", "en"):
        M.render(c2_search(lang), os.path.join(out, f"search-results-{lang}-3840x2560.png"))
        M.render(c2_frame(0.0, lang), os.path.join(out, f"header-poster-{lang}-3840x1646.png"))
        with tempfile.TemporaryDirectory() as tmp:
            with ThreadPoolExecutor(max_workers=os.cpu_count() or 2) as pool:
                list(pool.map(lambda i: M.render(c2_frame(i / fps, lang), os.path.join(tmp, f"f{i:04d}.png")), range(fps * seconds)))
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", str(fps), "-i", os.path.join(tmp, "f%04d.png"),
                            "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
                            "-map", "0:v", "-map", "1:a", "-shortest", "-c:v", "libx264", "-profile:v", "high",
                            "-pix_fmt", "yuv420p", "-crf", "16", "-maxrate", "20M", "-bufsize", "40M", "-r", str(fps),
                            "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart",
                            os.path.join(out, f"header-{lang}-3840x1646-15s.mp4")], check=True)
        print(f"{lang}: written")
    for name in os.listdir(out):
        if name.endswith(".png"):
            p = os.path.join(out, name)
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", p, "-pix_fmt", "rgb24", p + ".tmp.png"], check=True)
            os.replace(p + ".tmp.png", p)


if __name__ == "__main__" and len(sys.argv) > 1:
    if sys.argv[1] == "preview2":
        d = os.path.join(M.ROOT, "docs", "design")
        for lang in ("ja", "en"):
            for name, svg in ((f"appstore-twinlines-storyboard-{lang}", storyboard2(lang)), (f"appstore-twinlines-search-{lang}", c2_search(lang))):
                open(os.path.join(d, name + ".svg"), "w", encoding="utf-8").write(svg + "\n")
                render(svg, os.path.join(d, name + ".png"), 1920)
        print("preview written")
    elif sys.argv[1] == "final2":
        final2()
