#!/usr/bin/env python3
"""Mockups for the QLab sample (iPhone app) and the QLab demo on the website.
Writes SVG and PNG to docs/design/. Needs rsvg-convert. Fictional data only."""
import base64, os, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'docs', 'design')
SHOTS = sys.argv[1] if len(sys.argv) > 1 else None  # folder with CI iPhone screenshots (optional)
JP = "Noto Sans CJK JP, Noto Sans JP, sans-serif"
MONO = "JetBrains Mono, DejaVu Sans Mono, monospace"

# A1 palette (iOS/Shared/Theme.swift)
BG, PANEL, STROKE, ACC, ACCS, READ, DIM, LABEL, RED, BLUE = '#000000', '#060606', '#2A2A2A', '#3DFF7A', '#9AF5B7', '#EDEDED', '#9A9A9A', '#6B6B6B', '#FF3B30', '#8AB4FF'

def esc(s): return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

def t(x, y, s, size=14, fill=READ, w=400, anchor='start', font=JP, ls=0):
    return f'<text x="{x}" y="{y}" font-family="{font}" font-size="{size}" font-weight="{w}" fill="{fill}" text-anchor="{anchor}" letter-spacing="{ls}">{esc(s)}</text>'

def r(x, y, w, h, rx=10, fill=PANEL, stroke=STROKE, sw=1.5, extra=''):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>'

def led(x, y, c=ACC, rad=4):
    return f'<circle cx="{x}" cy="{y}" r="{rad*2.2}" fill="{c}" opacity="0.18"/><circle cx="{x}" cy="{y}" r="{rad}" fill="{c}"/>'

def phone(x, y, w, h, inner):
    return (f'<g transform="translate({x},{y})">' + r(-10, -10, w + 20, h + 20, 56, '#1b1b1d', '#3a3a3e', 2) +
            f'<clipPath id="c{x}{y}"><rect x="0" y="0" width="{w}" height="{h}" rx="46"/></clipPath>'
            f'<g clip-path="url(#c{x}{y})"><rect width="{w}" height="{h}" fill="{BG}"/>{inner}</g>'
            + r(w / 2 - 62, 12, 124, 34, 17, '#000', '#000', 0) + '</g>')

def status_bar(w):
    return t(40, 34, '9:41', 16, READ, 600, font=JP) + r(w - 78, 22, 30, 14, 4, 'none', READ, 1.2) + f'<rect x="{w-75}" y="25" width="22" height="8" rx="2" fill="{READ}"/>'

def caption(x, y, num, title, sub):
    return (f'<circle cx="{x+14}" cy="{y-6}" r="14" fill="#1f6feb"/>' + t(x + 14, y - 1, num, 15, '#fff', 700, 'middle') +
            t(x + 38, y, title, 20, '#111', 700) + t(x + 38, y + 26, sub, 14, '#555'))

# ---------- A: iPhone app ----------
def pair_screen(w=393, h=852):
    s = status_bar(w)
    s += led(92, 118, ACC, 4.5) + t(108, 127, 'TwinKeys Remote', 26, READ, 700, font=MONO)
    s += t(w / 2, 158, 'Mac の TwinKeys と同じ合言葉を入れてください', 14, DIM, 400, 'middle')
    s += r(20, 182, w - 40, 58, 10, BG, ACC, 1.5) + t(w / 2, 221, 'K7MQ2-WX9TP', 26, LABEL, 700, 'middle', MONO)
    s += r(w / 2 - 70, 258, 140, 50, 10, '#0b2a16', ACC, 1.5) + t(w / 2, 289, '保存', 17, ACC, 700, 'middle')
    s += t(w / 2, 348, '近くの Mac を探しています…', 15, DIM, 400, 'middle')
    # sample block
    y = 420
    s += f'<line x1="20" y1="{y-26}" x2="{w-20}" y2="{y-26}" stroke="{STROKE}" stroke-width="1"/>'
    s += t(20, y, 'MAC がなくても試せます', 12, LABEL, 500, font=MONO, ls=1.5)
    bw = (w - 52) / 2
    for i, (title, sub, icon) in enumerate([('Live のサンプル', 'シーンとクリップ', 'grid'), ('QLab のサンプル', 'キューの一覧と GO', 'list')]):
        bx = 20 + i * (bw + 12)
        hl = i == 1
        s += r(bx, y + 14, bw, 112, 12, '#07150c' if hl else PANEL, ACC if hl else STROKE, 2 if hl else 1.5)
        cx = bx + bw / 2
        if icon == 'grid':
            for gx in range(3):
                for gy in range(3):
                    s += f'<rect x="{cx-15+gx*11}" y="{y+32+gy*11}" width="8" height="8" rx="1.5" fill="{READ}"/>'
        else:
            for k in range(3):
                s += f'<rect x="{cx-16}" y="{y+33+k*11}" width="5" height="5" rx="1" fill="{ACC if k==1 else READ}"/>' + f'<rect x="{cx-7}" y="{y+33+k*11}" width="23" height="5" rx="1" fill="{ACC if k==1 else READ}"/>'
        s += t(cx, y + 90, title, 16, READ, 700, 'middle') + t(cx, y + 112, sub, 12, DIM, 400, 'middle')
    s += t(w / 2, y + 160, '架空のデータで画面を試せます。', 13, DIM, 400, 'middle')
    s += t(w / 2, y + 180, 'Mac には何も送りません。', 13, DIM, 400, 'middle')
    return s

def settings_screen(w=393, h=852):
    s = status_bar(w) + t(20, 110, '設定', 32, READ, 700)
    y = 140
    s += t(36, y + 10, 'サンプル', 13, DIM, 500)
    s += r(20, y + 22, w - 40, 152, 12, '#111', '#111', 0)
    s += t(36, y + 56, '見ているサンプル', 16, READ) + t(w - 36, y + 56, 'QLab', 16, DIM, 400, 'end')
    s += f'<line x1="36" y1="{y+74}" x2="{w-20}" y2="{y+74}" stroke="{STROKE}"/>'
    s += t(36, y + 108, 'Live のサンプルに切り替える', 16, ACC)
    s += f'<line x1="36" y1="{y+124}" x2="{w-20}" y2="{y+124}" stroke="{STROKE}"/>'
    s += t(36, y + 156, 'サンプルを終わって Mac につなぐ', 16, ACC)
    s += t(36, y + 196, '架空のデータを表示しています。Mac には何も', 12, DIM) + t(36, y + 214, '送っていません。', 12, DIM)
    y = 390
    s += t(36, y, '本番の安全', 13, DIM, 500)
    s += r(20, y + 12, w - 40, 100, 12, '#111', '#111', 0)
    s += t(36, y + 48, '本番ロック', 16, READ) + r(w - 88, y + 30, 51, 31, 15.5, '#333', '#333', 0) + f'<circle cx="{w-72}" cy="{y+45.5}" r="13.5" fill="#fff"/>'
    s += f'<line x1="36" y1="{y+62}" x2="{w-20}" y2="{y+62}" stroke="{STROKE}"/>'
    s += t(36, y + 94, '（このあとは今の設定と同じ）', 14, LABEL)
    # tab bar
    s += f'<rect x="0" y="{h-84}" width="{w}" height="84" fill="#0a0a0a"/>'
    for i, name in enumerate(['一覧', 'キュー', 'GO', '設定']):
        cx = w / 8 + i * w / 4
        s += t(cx, h - 40, name, 11, ACC if name == '設定' else DIM, 500, 'middle')
    return s

def img(path, x, y, w, h):
    with open(path, 'rb') as f: b = base64.b64encode(f.read()).decode()
    return f'<image x="{x}" y="{y}" width="{w}" height="{h}" href="data:image/png;base64,{b}" preserveAspectRatio="xMidYMid slice"/>'

def mock_app():
    W, H = 1500, 1150
    s = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><rect width="{W}" height="{H}" fill="#f4f5f7"/>'
    s += t(60, 70, 'A. iPhone アプリ：「サンプルで試す」で Live か QLab を選ぶ（1.4.0）', 28, '#111', 700)
    s += t(60, 104, '最初の画面のボタンを2つに分けます。サンプルの中では、設定から切り替えと終了ができます。', 16, '#444')
    pw, ph, py = 393, 852, 250
    xs = [60, 560, 1060]
    s += caption(xs[0], 170, '1', '最初の画面', 'ボタンが2つ（今は「サンプルで試す」1つ）')
    s += phone(xs[0], py, pw, ph, pair_screen())
    s += caption(xs[1], 170, '2', '「QLab のサンプル」を押す', 'QLab の GO 画面が開く（中身は今の QLab 画面のまま）')
    if SHOTS and os.path.exists(os.path.join(SHOTS, 'iPhone-17-Pro-portrait-qlab-go.png')):
        inner = img(os.path.join(SHOTS, 'iPhone-17-Pro-portrait-qlab-go.png'), 0, 0, pw, ph)
    else:
        inner = t(pw / 2, ph / 2, '（QLab の GO 画面）', 18, DIM, 400, 'middle')
    s += phone(xs[1], py, pw, ph, inner)
    s += caption(xs[2], 170, '3', 'サンプル中の設定', '切り替え・終了の行（今は「終了」だけ）')
    s += phone(xs[2], py, pw, ph, settings_screen())
    # arrows
    for ax in (480, 980):
        s += f'<path d="M{ax} 670 h50" stroke="#1f6feb" stroke-width="4" fill="none"/><path d="M{ax+50} 660 l14 10 l-14 10z" fill="#1f6feb"/>'
    return s + '</svg>'

# ---------- B: website ----------
SG, SGD, SBG, SCARD, SBORDER, SINK, SMUTE, SBLUE, SRED = '#4cd964', '#1f8a3a', '#f4f5f7', '#ffffff', '#dcdfe4', '#111111', '#5f6368', '#1a5fd0', '#d93025'

def site_phone(x, y, pane='go'):
    w, h = 720, 330
    s = f'<g transform="translate({x},{y})">' + r(0, 0, w + 20, h + 20, 44, '#111', '#2b2b2b', 2)
    s += f'<rect x="10" y="10" width="{w}" height="{h}" rx="34" fill="#0b0b0c"/>'
    # top bar
    s += led(36, 40, SG, 3.5) + t(46, 38, 'Main Stage Mac', 12, '#fff', 700) + t(46, 52, 'バックアップ ✓ · QLab ✓ · 2 ms', 9, '#9a9a9a')
    for i, (lab, val) in enumerate([('ワークスペース', 'sample-show'), ('動いている', '2 キュー'), ('リスト', 'Main')]):
        bx = 200 + i * 112
        s += r(bx, 22, 104, 34, 6, '#151515', '#2c2c2c', 1) + t(bx + 8, 34, lab, 8, '#8a8a8a') + t(bx + 8, 50, val, 13, '#fff', 700)
    s += r(560, 24, 104, 30, 7, '#c62828', '#c62828', 0) + t(612, 44, 'PANIC（2台）', 11, '#fff', 700, 'middle')
    s += r(676, 24, 30, 30, 7, '#222', '#333', 1)
    s += f'<line x1="10" y1="66" x2="{w+10}" y2="66" stroke="#222"/>'
    if pane == 'go':
        s += r(24, 78, 386, 92, 10, '#111', SG, 1.2) + t(36, 96, 'いま鳴っている', 9, SG, 700) + t(36, 124, '12  雨の音（遠く）', 18, '#fff', 700)
        s += t(36, 156, '残り', 9, '#9a9a9a') + t(58, 157, '-1:03', 11, SG, 700) + f'<rect x="100" y="151" width="296" height="5" rx="2.5" fill="#333"/><rect x="100" y="151" width="190" height="5" rx="2.5" fill="{SG}"/>'
        s += t(36, 186, '・11.5 夜の環境音（ループ）  -3:35', 10, '#bbb') if False else ''
        s += r(24, 180, 386, 72, 10, '#111', '#3d5f9e', 1.2) + t(36, 198, '次', 9, '#8ab4ff', 700) + t(36, 224, '13  雷鳴 1', 18, '#fff', 700)
        s += t(36, 243, '● バックアップも 13 で待機中', 10, SG)
        for i, (a, b) in enumerate([('▲ 前へ', '再生位置'), ('次へ ▼', '再生位置'), ('STOP', '長押し')]):
            bx = 24 + i * 130
            s += r(bx, 270, 122, 48, 8, '#222', '#222', 0) + t(bx + 61, 290, a, 13, '#fff', 700, 'middle') + t(bx + 61, 308, b, 9, '#9a9a9a', 400, 'middle')
        s += r(424, 78, 244, 240, 12, SG, SG, 0) + t(546, 104, 'QLAB', 11, '#0b3d1a', 700, 'middle', MONO, 2)
        s += t(546, 190, 'GO', 64, '#0b3d1a', 800, 'middle', JP) + t(546, 220, '次のキューを鳴らす', 11, '#0b3d1a', 700, 'middle') + t(546, 240, '13 雷鳴 1', 12, '#0b3d1a', 700, 'middle')
        s += t(546, 304, '直前の GO：12 メイン ✓ バックアップ ✓', 9, '#0b3d1a', 700, 'middle')
    else:
        s += t(30, 90, '16 キュー', 10, '#9a9a9a', 700) + r(420, 76, 170, 24, 6, '#151515', '#2c2c2c') + t(430, 92, '番号か名前で探す', 10, '#777') + r(598, 76, 70, 24, 6, '#0d2a16', SG) + t(633, 92, '追従', 10, SG, 700, 'middle')
        rows = [('10', 'GRP', '第1場', '', ''), ('11', 'AUD', '鳥の声（朝）', '', '1:30'), ('11.5', 'AUD', '夜の環境音（ループ）', '-3:35', '∞'),
                ('12', 'AUD', '雨の音（遠く）', '-1:03', '3:20'), ('13', 'AUD', '雷鳴 1', '次', '0:12'), ('14', 'FADE', '雨 フェードアウト', '', '0:05'), ('15', 'NET', '映像へ合図', '', '')]
        for i, (n, ty, name, st, d) in enumerate(rows):
            ry = 108 + i * 30
            run, nxt = st.startswith('-'), st == '次'
            s += r(24, ry, 644, 26, 6, '#0f2416' if run else ('#0d1730' if nxt else '#111'), SG if run else ('#3d5f9e' if nxt else '#222'), 1)
            s += t(38, ry + 18, ('▶ ' if nxt else ('● ' if run else '   ')) + n, 11, '#fff', 700) + r(100, ry + 5, 40, 16, 4, 'none', '#6d7fae' if ty != 'NET' else '#d9a12b', 1) + t(120, ry + 17, ty, 8, '#cfd8ff' if ty != 'NET' else '#ffcf6b', 700, 'middle')
            s += t(150, ry + 18, name, 12, '#fff', 600) + t(560, ry + 18, st, 11, SG if run else '#8ab4ff', 700, 'end') + t(656, ry + 18, d, 11, '#ddd', 700, 'end')
        s += t(30, 330, 'タップで2台の再生位置をそこへ移します（鳴らしません）', 10, '#9a9a9a')
    # rail
    s += f'<rect x="684" y="66" width="46" height="{h-56}" fill="#0b0b0c"/><line x1="684" y1="66" x2="684" y2="{h+10}" stroke="#222"/>'
    for i, name in enumerate(['一覧', 'キュー', 'GO', '設定']):
        cy = 96 + i * 60
        on = (name == 'GO' and pane == 'go') or (name == '一覧' and pane == 'list')
        if on: s += r(689, cy - 22, 38, 48, 8, '#1d2a40', '#1d2a40', 0)
        s += f'<circle cx="708" cy="{cy-4}" r="7" fill="none" stroke="{"#8ab4ff" if on else "#888"}" stroke-width="1.6"/>' + t(708, cy + 18, name, 7, '#8ab4ff' if on else '#888', 400, 'middle')
    return s + '</g>'

def site_watch(x, y):
    s = f'<g transform="translate({x},{y})">' + r(0, 0, 170, 206, 44, '#111', '#2b2b2b', 2) + f'<rect x="168" y="62" width="9" height="28" rx="3" fill="#333"/><rect x="168" y="102" width="9" height="28" rx="3" fill="#333"/>'
    s += led(52, 32, SG, 3) + t(60, 36, 'M', 10, '#fff', 700) + led(82, 32, SG, 3) + t(90, 36, 'B', 10, '#fff', 700) + led(112, 32, SG, 3) + t(120, 36, 'Q', 10, '#fff', 700)
    s += t(85, 54, '12 雨の音（遠く）', 10, '#fff', 700, 'middle')
    s += r(24, 62, 122, 106, 26, SG, SG, 0) + t(85, 120, 'GO', 34, '#0b3d1a', 800, 'middle') + t(85, 146, '-1:03', 12, '#0b3d1a', 700, 'middle', MONO)
    s += t(85, 188, '次：13 雷鳴 1', 10, '#bbb', 400, 'middle')
    return s + '</g>'

def mac_card(x, y, name, main):
    s = r(x, y, 346, 136, 14, SCARD, SBORDER, 1)
    s += f'<rect x="{x+16}" y="{y+18}" width="20" height="14" rx="2" fill="none" stroke="#555" stroke-width="1.6"/>' + t(x + 46, y + 31, name, 13, SINK, 700)
    s += f'<circle cx="{x+21}" cy="{y+61}" r="5" fill="{SGD}"/>' + t(x + 31, y + 66, 'QLab ✓', 13, SGD, 700)
    if main: s += r(x + 280, y + 50, 52, 22, 11, SBLUE, SBLUE, 0) + t(x + 306, y + 66, 'メイン', 11, '#fff', 700, 'middle')
    s += t(x + 16, y + 94, '▶ 12 雨の音（遠く）', 13, SINK, 700) + t(x + 16, y + 118, '待機：13 雷鳴 1', 12, SMUTE)
    return s

def node(x, y, label, sub, icon='mac', badge=None):
    s = f'<circle cx="{x}" cy="{y}" r="25" fill="#fff" stroke="{SGD}" stroke-width="3"/>'
    if icon == 'mac': s += f'<rect x="{x-13}" y="{y-11}" width="26" height="17" rx="2" fill="none" stroke="{SINK}" stroke-width="2"/><rect x="{x-6}" y="{y+8}" width="12" height="3" fill="{SINK}"/>'
    elif icon == 'phone': s += f'<rect x="{x-7}" y="{y-13}" width="14" height="26" rx="3" fill="none" stroke="{SINK}" stroke-width="2"/>'
    elif icon == 'watch': s += f'<rect x="{x-9}" y="{y-11}" width="18" height="22" rx="5" fill="none" stroke="{SINK}" stroke-width="2.4"/>'
    else: s += t(x, y + 6, 'Q', 18, SINK, 800, 'middle', MONO)
    if badge: s += r(x - 24, y - 50, 48, 18, 9, SBLUE, SBLUE, 0) + t(x, y - 37, badge, 10, '#fff', 700, 'middle')
    s += t(x, y + 46, label, 12, SINK, 700, 'middle') + t(x, y + 62, sub, 10, SGD, 400, 'middle')
    return s

def mock_site(pane='go'):
    W, H = 1280, 1330
    s = f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><rect width="{W}" height="{H}" fill="{SBG}"/>'
    s += t(80, 90, '触って試す', 30, SINK, 800) + t(80, 124, '架空のデータで動く見本です。この画面は Mac にも Live・QLab にもつながっていません。', 14, SMUTE)
    # segmented control
    s += r(820, 62, 380, 44, 22, '#e6e8ec', '#e6e8ec', 0) + r(1012, 66, 184, 36, 18, '#fff', SBORDER, 1)
    s += t(916, 90, 'Ableton Live', 14, SMUTE, 600, 'middle') + t(1104, 90, 'QLab', 14, SINK, 800, 'middle')
    s += t(1200, 140, '切り替えると、見本の中身が変わります', 11, SMUTE, 400, 'end')
    s += site_phone(80, 160, pane)
    s += site_watch(852, 160) + t(1042, 188, 'Apple Watch', 14, SINK, 700) + t(1042, 212, 'GO・キューの一覧・PANIC', 12, SMUTE) + t(1042, 234, '点を押すと画面が切り替わります', 12, SMUTE)
    s += r(1042, 254, 64, 40, 8, '#fff', SBORDER) + t(1074, 279, '▲ 前', 12, SINK, 700, 'middle') + r(1116, 254, 64, 40, 8, '#fff', SBORDER) + t(1148, 279, '次 ▼', 12, SINK, 700, 'middle')
    for i in range(3): s += f'<circle cx="{907+i*30}" cy="384" r="4" fill="{"#1a73e8" if i==0 else "#888"}"/>'
    s += mac_card(852, 420, 'Main Stage Mac', True) + mac_card(852, 568, 'Backup Stage Mac', False)
    # map
    s += r(80, 734, 1120, 300, 14, SCARD, SBORDER, 1) + t(102, 770, 'つながり', 14, SINK, 700)
    s += f'<g stroke="{SGD}" stroke-width="3" fill="none"><path d="M200 890 H412"/><path d="M438 890 H640 V830 H722"/><path d="M640 890 V952 H722"/><path d="M772 830 H960"/><path d="M772 952 H960"/></g>'
    s += t(306, 880, 'Bluetooth / Wi-Fi', 10, SMUTE, 500, 'middle') + t(540, 880, 'Wi-Fi', 10, SMUTE, 500, 'middle') + t(620, 822, '直接', 10, SMUTE, 500, 'end') + t(620, 968, 'メイン経由（LAN）', 10, SMUTE, 500, 'end')
    s += t(866, 820, 'この Mac の中だけ', 10, SMUTE, 500, 'middle') + t(866, 942, 'この Mac の中だけ', 10, SMUTE, 500, 'middle')
    s += node(176, 890, 'Apple Watch', 'つながっています', 'watch') + node(414, 890, 'iPhone', 'メインに接続中', 'phone')
    s += node(747, 830, 'Main Stage Mac', 'QLab ✓', 'mac', 'メイン') + node(747, 952, 'Backup Stage Mac', 'QLab ✓', 'mac')
    s += node(985, 830, 'QLab（メイン）', '▶ 12 雨の音', 'q') + node(985, 952, 'QLab（バックアップ）', '▶ 12 雨の音', 'q')
    s += r(80, 1060, 230, 46, 10, '#fff', SRED, 2) + t(195, 1090, 'メインの Mac を止めてみる', 14, SRED, 700, 'middle') + r(322, 1060, 134, 46, 10, '#fff', SBORDER) + t(389, 1090, 'はじめに戻す', 14, SINK, 700, 'middle')
    s += t(472, 1080, '止めても、バックアップの Mac の QLab はずっと鳴り続けます。iPhone には、操作の届け先を切り替える案内が出ます。', 12, SMUTE)
    s += t(80, 1150, '見本で動くのは GO と一覧です。キューのキー・設定はアプリで使えます。', 12, SMUTE)
    s += t(80, 1172, '音は鳴りません。代わりに、2台の QLab が同時に受け取ったことを表示します。', 12, SMUTE)
    s += t(80, 1230, '※ 絵はデザイン案です。サイトの見本は今の色（白い地・緑の GO）のまま、中身だけを QLab に替えます。', 12, '#a15c00')
    return s + '</svg>'

def write(name, svg):
    p = os.path.join(OUT, name)
    open(p + '.svg', 'w', encoding='utf-8').write(svg)
    subprocess.run(['rsvg-convert', '-z', '1', '-o', p + '.png', p + '.svg'], check=True)
    print(p + '.png')

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    write('qlab-demo-app', mock_app())
    write('qlab-demo-site-go', mock_site('go'))
    write('qlab-demo-site-list', mock_site('list'))
