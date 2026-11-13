#!/usr/bin/env python3
"""Clearer App Store header video (proposal): one message only.
GO on the iPhone -> both Macs play at once -> the main Mac stops -> the backup keeps playing.
Big captions, one big GO key, two Mac laptops with clear status chips. 12 s loop, 21:9 3840x1646."""
import os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make as M  # noqa: E402

G, R, MONO = "#3DFF7A", "#FF3B30", "JetBrains Mono"
CAP = {"ja": ["GO を押すと", "2台の Mac が同時に再生", "メインの Mac が止まっても", "バックアップは鳴り続ける"],
       "en": ["Tap GO", "Both Macs play at once", "If the main Mac stops", "the backup keeps playing"]}
MAC = {"ja": ("メイン", "バックアップ", "再生中", "停止"), "en": ("MAIN", "BACKUP", "PLAYING", "STOPPED")}


def defs():
    return ('<defs><filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="14"/></filter>'
            '<filter id="bloom" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="70"/></filter>'
            '<linearGradient id="key" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0E2416"/><stop offset="1" stop-color="#030805"/></linearGradient></defs>')


def phase(t):
    if t < 2.0: return 0          # "Tap GO"
    if t < 6.0: return 1          # both play
    if t < 7.4: return 2          # main stops
    return 3                      # backup keeps playing


def laptop(x, y, w, label, state, lang, glow):
    """state: 'idle' | 'play' | 'dead'"""
    h = w * 0.62
    col = {"idle": "#3A3A3A", "play": G, "dead": R}[state]
    scr = {"idle": "#0A0A0A", "play": "#0B2414", "dead": "#2A0806"}[state]
    o = []
    if state == "play" and glow:
        o.append(f'<rect x="{x - 30}" y="{y - 30}" width="{w + 60}" height="{h + 60}" rx="60" fill="{G}" opacity="{0.35 * glow:.3f}" filter="url(#bloom)"/>')
    o += [M.rect(x, y, w, h, 34, "#1C1D21", col, 8), M.rect(x + 28, y + 28, w - 56, h - 56, 18, scr),
          f'<path d="M{x - 40} {y + h + 6} H{x + w + 40} L{x + w + 10} {y + h + 46} H{x - 10} Z" fill="#2E3036"/>']
    cx, cy = x + w / 2, y + h / 2
    if state == "play":  # note + bars
        for i in range(7):
            bh = [60, 120, 180, 100, 160, 80, 140][i] * (0.6 + 0.4 * glow)
            o.append(M.rect(cx - 210 + i * 62, cy + 90 - bh, 36, bh, 8, G))
    elif state == "dead":
        o.append(M.txt(cx, cy + 60, "✕", 200, R, 800, "middle"))
    else:
        o.append(M.rect(cx - 180, cy + 60, 360, 16, 8, "#2A2A2A"))
    lab, sub = MAC[lang][0 if label == "main" else 1], {"idle": "", "play": MAC[lang][2], "dead": MAC[lang][3]}[state]
    o.append(M.txt(x + w + 90, cy - 10, lab, 84, "#FFFFFF", 800, family=M.FONT))
    if sub:
        o.append(M.txt(x + w + 90, cy + 80, sub, 64, col, 800))
    return "".join(o)


def frame(t, lang, w=3840, h=1646):
    p = phase(t)
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">', defs(), M.rect(0, 0, w, h, 0, "#000")]
    # big GO key on the left (the iPhone's GO)
    press = M.clamp((t - 1.4) / 0.5) if 1.4 <= t < 1.9 else 0
    kx, ky, ks = 360, 380, 900
    o += [f'<rect x="{kx}" y="{ky}" width="{ks}" height="{ks}" rx="90" fill="{G}" opacity="{0.3 + 0.5 * press:.3f}" filter="url(#bloom)"/>',
          M.rect(kx, ky, ks, ks, 90, "url(#key)", G, 12), M.txt(kx + ks / 2, ky + ks / 2 + 130, "GO", 380, G, 800, "middle", family=MONO)]
    if 1.4 <= t < 2.4:  # finger tap
        q = M.clamp((t - 1.4) / 1.0)
        o.append(f'<circle cx="{kx + ks / 2}" cy="{ky + ks / 2}" r="{80 + 400 * q:.1f}" fill="none" stroke="#FFFFFF" stroke-width="10" opacity="{1 - q:.3f}"/>')
        o.append(f'<circle cx="{kx + ks / 2}" cy="{ky + ks / 2}" r="70" fill="#FFFFFF" opacity="{0.6 * (1 - q):.3f}"/>')
    # lines to the two Macs
    mx, mw = 2100, 760
    tops = (330, 1010)
    sx, sy = kx + ks, ky + ks / 2
    main_dead = p >= 2
    for i, ty in enumerate(tops):
        ey = ty + mw * 0.62 / 2
        dead = main_dead and i == 0
        lit = p >= 1 and not dead
        col = R if dead else (G if lit else "#2A2A2A")
        path = f'M{sx} {sy} C {sx + 300} {sy}, {mx - 400} {ey}, {mx - 50} {ey}'
        o.append(f'<path d="{path}" fill="none" stroke="{col}" stroke-width="{14 if lit else 8}" opacity="{0.35 if dead else 1}"' + (' stroke-dasharray="30 26"' if dead else '') + '/>')
        if lit:
            o.append(f'<path d="{path}" fill="none" stroke="{G}" stroke-width="40" opacity="0.25" filter="url(#glow)"/>')
        if 1.9 <= t < 2.9:  # pulse travelling
            q = M.ease((t - 1.9) / 1.0)
            # point on cubic bezier
            x0, y0, x1, y1, x2, y2, x3, y3 = sx, sy, sx + 300, sy, mx - 400, ey, mx - 50, ey
            u = 1 - q
            bx = u**3 * x0 + 3 * u * u * q * x1 + 3 * u * q * q * x2 + q**3 * x3
            by = u**3 * y0 + 3 * u * u * q * y1 + 3 * u * q * q * y2 + q**3 * y3
            o.append(f'<circle cx="{bx:.1f}" cy="{by:.1f}" r="46" fill="{G}" filter="url(#glow)"/><circle cx="{bx:.1f}" cy="{by:.1f}" r="22" fill="#EAFFEF"/>')
    pulse = 0.5 + 0.5 * abs(((t * 1.6) % 2) - 1)
    o.append(laptop(mx, tops[0], mw, "main", "dead" if main_dead else ("play" if p >= 1 and t >= 2.9 else "idle"), lang, pulse))
    o.append(laptop(mx, tops[1], mw, "backup", "play" if p >= 1 and t >= 2.9 else "idle", lang, pulse * (1.3 if p == 3 else 1)))
    # one big caption at the top
    cap = CAP[lang][p]
    o.append(M.txt(w / 2, 220, cap, 150, R if p == 2 else (G if p == 3 else "#FFFFFF"), 800, "middle"))
    # loop fade
    if t >= 11.0:
        o.append(M.rect(0, 0, w, h, 0, "#000", opacity=M.clamp((t - 11.0) / 0.5) if t < 11.5 else M.clamp(1 - (t - 11.5) / 0.5)))
    o.append("</svg>")
    s = "".join(o)
    if t >= 11.5:  # fade the first frame back in
        return frame(0.0, lang, w, h).replace("</svg>", M.rect(0, 0, w, h, 0, "#000", opacity=M.clamp(1 - (t - 11.5) / 0.5)) + "</svg>")
    return s


def storyboard(lang):
    ts = [1.6, 4.0, 6.6, 9.0]
    sw, sh = 1880, 1880 * 1646 / 3840
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="{2 * sh + 120:.0f}" viewBox="0 0 3840 {2 * sh + 120:.0f}">', M.rect(0, 0, 3840, 2 * sh + 120, 0, "#14161B")]
    for i, t in enumerate(ts):
        cx, cy = 40 + (i % 2) * (sw + 40), 40 + (i // 2) * (sh + 40)
        inner = frame(t, lang).split(">", 1)[1].rsplit("</svg>", 1)[0]
        o.append(f'<svg x="{cx}" y="{cy}" width="{sw}" height="{sh:.1f}" viewBox="0 0 3840 1646">{inner}</svg>')
    o.append("</svg>")
    return "".join(o)


if __name__ == "__main__":
    d = os.path.join(M.ROOT, "docs", "design")
    for lang in ("ja", "en"):
        svg = storyboard(lang)
        open(os.path.join(d, f"appstore-simple-storyboard-{lang}.svg"), "w", encoding="utf-8").write(svg + "\n")
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "a.svg"); open(src, "w", encoding="utf-8").write(svg)
            subprocess.run(["rsvg-convert", "-w", "1920", "-o", os.path.join(d, f"appstore-simple-storyboard-{lang}.png"), src], check=True)
    print("written")
