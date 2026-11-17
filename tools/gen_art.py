#!/usr/bin/env python3
"""產生遊戲美術素材（SVG）到 assets/art/。

所有圖以 128 單位的座標繪製（地形物件 256），輸出尺寸約為遊戲內顯示的 2 倍。
重新產生：python3 tools/gen_art.py   （或 make art）
"""
import math
import random
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "art"


def save(name, body, defs="", vb=128, size=96, vbh=None, sizeh=None):
    vbh = vbh or vb
    sizeh = sizeh or size
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{name}.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{sizeh}" viewBox="0 0 {vb} {vbh}">\n'
        f'<defs>{defs}</defs>\n{body}\n</svg>\n', encoding="utf-8")


def lin(id_, stops, x2=0, y2=1):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<linearGradient id="{id_}" x1="0" y1="0" x2="{x2}" y2="{y2}">{s}</linearGradient>'


def rad(id_, stops, cx=0.5, cy=0.5, r=0.5):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<radialGradient id="{id_}" cx="{cx}" cy="{cy}" r="{r}">{s}</radialGradient>'


def blob(cx, cy, r, jitter, n, rng):
    """不規則的圓滑封閉形狀。"""
    pts = []
    for i in range(n):
        a = math.tau * i / n
        rr = r * (1 + rng.uniform(-jitter, jitter))
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    mids = [((pts[i][0] + pts[(i + 1) % n][0]) / 2, (pts[i][1] + pts[(i + 1) % n][1]) / 2) for i in range(n)]
    d = f"M{mids[-1][0]:.1f} {mids[-1][1]:.1f}"
    for i in range(n):
        d += f" Q{pts[i][0]:.1f} {pts[i][1]:.1f} {mids[i][0]:.1f} {mids[i][1]:.1f}"
    return d + "Z"


# ════════════════════════════ 地圖（底圖由 tools/gen_bg.gd 烘焙） ════════════════════════════


def castle():
    defs = lin("st", [(0, "#c5cbdb", 1), (1, "#7c8499", 1)]) + lin("rf", [(0, "#6f8cf0", 1), (1, "#3a52b0", 1)])
    b = ['<ellipse cx="80" cy="140" rx="68" ry="14" fill="#000" opacity="0.35"/>']
    # 側塔
    for x in (16, 108):
        b.append(f'<rect x="{x}" y="56" width="36" height="86" fill="url(#st)" stroke="#3a3f4f" stroke-width="3"/>')
        b.append(f'<polygon points="{x - 6},58 {x + 18},16 {x + 42},58" fill="url(#rf)" stroke="#24306a" stroke-width="3"/>')
        b.append(f'<rect x="{x + 13}" y="76" width="10" height="18" rx="5" fill="#2a2233"/>')
    # 主樓
    b.append('<rect x="46" y="70" width="68" height="72" fill="url(#st)" stroke="#3a3f4f" stroke-width="3"/>')
    for i in range(4):
        b.append(f'<rect x="{46 + i * 18.6:.0f}" y="58" width="12" height="14" fill="#b4bbcc" stroke="#3a3f4f" stroke-width="3"/>')
    b.append('<path d="M64 142 V112 a16 16 0 0 1 32 0 V142Z" fill="#2a2233" stroke="#3a3f4f" stroke-width="3"/>')
    b.append('<path d="M72 142 V114 M80 142 V108 M88 142 V114" stroke="#5a4a3a" stroke-width="3"/>')
    for x, y in [(56, 84), (98, 84)]:
        b.append(f'<rect x="{x}" y="{y}" width="8" height="14" rx="4" fill="#ffd97a"/>')
    # 旗
    b.append('<line x1="80" y1="58" x2="80" y2="14" stroke="#3a3f4f" stroke-width="3"/>')
    b.append('<path d="M80 16 L108 24 L80 34Z" fill="#e0465a" stroke="#7a1f2c" stroke-width="2"/>')
    save("castle", "\n".join(b), defs, vb=160, size=128)


def portal():
    defs = rad("pg", [(0, "#f6d0ff", 1), (0.35, "#b060f0", 1), (0.75, "#4a1a80", 1), (1, "#1a0a30", 1)])
    defs += rad("ph", [(0, "#c070ff", 0.5), (1, "#c070ff", 0)])
    b = ['<circle cx="64" cy="64" r="62" fill="url(#ph)"/>',
         '<ellipse cx="64" cy="64" rx="40" ry="48" fill="url(#pg)" stroke="#2a1040" stroke-width="5"/>']
    for k in range(3):
        pts = []
        for i in range(18):
            a = k * math.tau / 3 + i * 0.32
            r = 4 + i * 1.9
            pts.append(f"{64 + math.cos(a) * r * 0.82:.1f},{64 + math.sin(a) * r:.1f}")
        b.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="#f0c8ff" stroke-width="3" stroke-linecap="round" opacity="0.7"/>')
    for a in range(0, 360, 45):
        x, y = 64 + math.cos(math.radians(a)) * 48, 64 + math.sin(math.radians(a)) * 56
        b.append(f'<rect x="{x - 7:.0f}" y="{y - 7:.0f}" width="14" height="14" rx="3" fill="#6a6f80" stroke="#2a2d38" stroke-width="2.5"/>')
    save("portal", "\n".join(b), defs, size=128)


# ════════════════════════════ 地圖裝飾（疊在烘焙背景上） ════════════════════════════

def decor():
    sh = '<ellipse cx="64" cy="{y}" rx="{rx}" ry="{ry}" fill="#000" opacity="0.28"/>'
    # 花叢 ×3 色
    for name, petal, core in [("a", "#fbf6e6", "#f0b030"), ("b", "#f5a8c8", "#fff0a0"), ("c", "#a8b8ff", "#fff4c0")]:
        rng = random.Random(ord(name))
        b = []
        for _ in range(6):
            x, y = rng.uniform(30, 98), rng.uniform(50, 100)
            a = rng.uniform(-0.6, 0.6)
            b.append(f'<path d="M{x:.0f} {y:.0f} q{-10 + a * 10:.0f} -10 {-16 + a * 8:.0f} -4 q8 10 16 4Z" fill="#3f8a3a" stroke="#1f4a22" stroke-width="2"/>')
        for _ in range(4):
            x, y, r = rng.uniform(36, 92), rng.uniform(40, 92), rng.uniform(7, 10)
            for k in range(5):
                aa = math.tau * k / 5 + rng.uniform(0, 1)
                b.append(f'<circle cx="{x + math.cos(aa) * r * 0.8:.1f}" cy="{y + math.sin(aa) * r * 0.8:.1f}" r="{r * 0.62:.1f}" '
                         f'fill="{petal}" stroke="#00000033" stroke-width="1.5"/>')
            b.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r * 0.45:.1f}" fill="{core}"/>')
        save(f"deco_flower_{name}", "\n".join(b), size=64)

    defs = rad("rk", [(0, "#c9ccd2", 1), (0.6, "#8a8f99", 1), (1, "#4a4e58", 1)], cx=0.35, cy=0.3, r=0.8)
    b = [sh.format(y=100, rx=46, ry=12),
         '<path d="M22 98 C16 70 34 44 60 42 C88 40 110 62 106 96 Z" fill="url(#rk)" stroke="#2a2d34" stroke-width="4"/>',
         '<path d="M70 44 C80 58 78 74 66 96" fill="none" stroke="#5a5e68" stroke-width="3"/>',
         '<path d="M30 70 C40 54 54 48 66 48 C56 56 50 60 44 72Z" fill="#6aa04a" opacity="0.85"/>',
         '<ellipse cx="48" cy="58" rx="9" ry="4" fill="#fff" opacity="0.35" transform="rotate(-25 48 58)"/>']
    save("deco_rock", "\n".join(b), defs, size=64)

    defs = rad("rk", [(0, "#b8b2a6", 1), (1, "#5a564e", 1)], cx=0.35, cy=0.3, r=0.8)
    b = [sh.format(y=96, rx=30, ry=8),
         '<ellipse cx="50" cy="86" rx="22" ry="14" fill="url(#rk)" stroke="#2a2824" stroke-width="3.5"/>',
         '<ellipse cx="82" cy="92" rx="14" ry="9" fill="url(#rk)" stroke="#2a2824" stroke-width="3.5"/>',
         '<ellipse cx="72" cy="74" rx="10" ry="7" fill="url(#rk)" stroke="#2a2824" stroke-width="3"/>']
    save("deco_pebbles", "\n".join(b), defs, size=64)

    rng = random.Random(7)
    b = []
    for i in range(11):
        x = 40 + i * 4.8 + rng.uniform(-3, 3)
        h = rng.uniform(26, 50)
        bend = rng.uniform(-16, 16)
        col = rng.choice(["#3f8a3a", "#4fa045", "#68b850", "#2f7030"])
        b.append(f'<path d="M{x - 4:.0f} 100 Q{x + bend * 0.3:.0f} {100 - h * 0.6:.0f} {x + bend:.0f} {100 - h:.0f} Q{x + bend * 0.2 + 2:.0f} {100 - h * 0.5:.0f} {x + 4:.0f} 100Z" '
                 f'fill="{col}" stroke="#1a3a1c" stroke-width="1.5"/>')
    save("deco_tuft", "\n".join(b), size=64)

    b = [sh.format(y=104, rx=36, ry=8)]
    for x, y, s_ in [(48, 76, 1.0), (82, 86, 0.75)]:
        b.append(f'<g transform="translate({x} {y}) scale({s_})">'
                 '<path d="M-8 24 L-6 -4 H6 L8 24Z" fill="#f2ead8" stroke="#3a2a1a" stroke-width="3"/>'
                 '<path d="M-26 0 C-26 -26 26 -26 26 0Z" fill="#d83a3a" stroke="#4a0f0f" stroke-width="3.5"/>'
                 '<circle cx="-12" cy="-8" r="4" fill="#fff"/><circle cx="6" cy="-14" r="3.5" fill="#fff"/><circle cx="14" cy="-4" r="3" fill="#fff"/>'
                 '</g>')
    save("deco_mush", "\n".join(b), size=64)

    rng = random.Random(9)
    defs = rad("bu", [(0, "#6fc05a", 1), (1, "#245a2a", 1)], cx=0.4, cy=0.3, r=0.75)
    b = [sh.format(y=104, rx=50, ry=12)]
    for x, y, r in [(42, 76, 28), (84, 78, 26), (62, 60, 30), (62, 86, 26)]:
        b.append(f'<path d="{blob(x, y, r, 0.12, 9, rng)}" fill="url(#bu)" stroke="#173a1c" stroke-width="3.5"/>')
    for x, y in [(50, 62), (76, 70), (58, 88), (88, 86)]:
        b.append(f'<circle cx="{x}" cy="{y}" r="4.5" fill="#e04a5a" stroke="#5a1020" stroke-width="1.5"/>')
    b.append('<ellipse cx="54" cy="50" rx="10" ry="5" fill="#fff" opacity="0.25" transform="rotate(-20 54 50)"/>')
    save("deco_bush", "\n".join(b), defs, size=64)

    defs = lin("bk", [(0, "#8a5a32", 1), (1, "#4a2e16", 1)], x2=1, y2=0)
    b = [sh.format(y=100, rx=40, ry=10),
         '<path d="M32 98 L36 62 H92 L96 98 Q64 106 32 98Z" fill="url(#bk)" stroke="#2a1808" stroke-width="4"/>',
         '<ellipse cx="64" cy="62" rx="28" ry="11" fill="#d8b07a" stroke="#2a1808" stroke-width="4"/>',
         '<ellipse cx="64" cy="62" rx="18" ry="7" fill="none" stroke="#a87a48" stroke-width="2.5"/>',
         '<ellipse cx="64" cy="62" rx="8" ry="3" fill="none" stroke="#a87a48" stroke-width="2.5"/>',
         '<path d="M30 96 C22 98 18 102 14 102 M98 96 C106 98 110 102 116 100" stroke="#4a2e16" stroke-width="6" stroke-linecap="round"/>']
    save("deco_stump", "\n".join(b), defs, size=64)


# ════════════════════════════ 技能動畫素材（白色 / 灰階，遊戲內染色） ════════════════════════════

def ability_fx():
    save("fx_drop", '<path d="M32 4 C32 4 12 32 12 44 a20 20 0 0 0 40 0 C52 32 32 4 32 4Z" fill="url(#g)"/>'
                    '<ellipse cx="24" cy="44" rx="5" ry="8" fill="#fff" opacity="0.9"/>',
         rad("g", [(0, "#fff", 1), (1, "#d8e8ff", 0.85)], cx=0.4, cy=0.6), vb=64, size=48)

    save("fx_flame", '<path d="M32 2 C40 18 56 26 54 44 C52 56 44 62 32 62 C20 62 12 56 10 44 C8 32 18 28 22 16 C26 26 28 28 30 26 C32 18 30 10 32 2Z" fill="url(#g)"/>',
         rad("g", [(0, "#fff", 1), (0.5, "#fff", 0.8), (1, "#fff", 0)], cx=0.5, cy=0.7, r=0.6), vb=64, size=64)

    save("fx_leaf", '<path d="M8 56 C4 26 26 6 58 6 C58 38 38 60 8 56Z" fill="#e8f2e0" stroke="#5a6a50" stroke-width="3"/>'
                    '<path d="M10 54 C26 40 40 26 54 10 M24 42 V30 M34 32 V20 M28 38 H40 M38 28 H48" stroke="#8a9a80" stroke-width="2.5" fill="none" stroke-linecap="round"/>',
         vb=64, size=40)

    defs = rad("g", [(0, "#ffffff", 1), (0.6, "#b0b0b0", 1), (1, "#5a5a5a", 1)], cx=0.35, cy=0.3, r=0.8)
    save("fx_rock", '<polygon points="10,30 22,10 44,8 58,26 52,52 28,58 12,48" fill="url(#g)" stroke="#2a2a2a" stroke-width="3.5" stroke-linejoin="round"/>'
                    '<polyline points="22,10 30,30 58,26 M30,30 28,58" fill="none" stroke="#6a6a6a" stroke-width="2"/>',
         defs, vb=64, size=40)

    defs = lin("g", [(0, "#ffffff", 1), (1, "#7a7a7a", 1)], x2=1, y2=0)
    save("fx_spike", '<path d="M32 4 L52 124 H12Z" fill="url(#g)" stroke="#2a2a2a" stroke-width="4" stroke-linejoin="round"/>'
                     '<path d="M32 4 L30 124" stroke="#5a5a5a" stroke-width="2"/>'
                     '<path d="M22 70 L8 56 L18 82Z M42 90 L58 74 L48 100Z" fill="#c8c8c8" stroke="#2a2a2a" stroke-width="3" stroke-linejoin="round"/>',
         defs, vb=64, vbh=128, size=32, sizeh=64)

    b = ['<circle cx="128" cy="128" r="120" fill="none" stroke="#fff" stroke-width="6"/>',
         '<circle cx="128" cy="128" r="104" fill="none" stroke="#fff" stroke-width="3"/>',
         '<circle cx="128" cy="128" r="58" fill="none" stroke="#fff" stroke-width="4"/>']
    tri = lambda off: " ".join(f"{128 + math.cos(off + k * math.tau / 3) * 104:.1f},{128 + math.sin(off + k * math.tau / 3) * 104:.1f}" for k in range(3))
    b.append(f'<polygon points="{tri(-math.pi / 2)}" fill="none" stroke="#fff" stroke-width="3.5"/>')
    b.append(f'<polygon points="{tri(math.pi / 2)}" fill="none" stroke="#fff" stroke-width="3.5"/>')
    for k in range(24):
        a = math.tau * k / 24
        x1, y1 = 128 + math.cos(a) * 106, 128 + math.sin(a) * 106
        x2, y2 = 128 + math.cos(a) * (118 if k % 2 else 112), 128 + math.sin(a) * (118 if k % 2 else 112)
        b.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="#fff" stroke-width="3"/>')
    for k in range(6):
        a = math.tau * k / 6 + math.pi / 6
        b.append(f'<circle cx="{128 + math.cos(a) * 82:.1f}" cy="{128 + math.sin(a) * 82:.1f}" r="7" fill="#fff"/>')
    save("fx_rune", "\n".join(b), vb=256, size=256)

    save("fx_column", '<rect x="0" y="0" width="64" height="256" fill="url(#h)"/>',
         lin("h", [(0, "#fff", 0), (0.3, "#fff", 0.85), (0.5, "#fff", 1), (0.7, "#fff", 0.85), (1, "#fff", 0)], x2=1, y2=0),
         vb=64, vbh=256, size=48, sizeh=192)

    rng = random.Random(31)
    b = []
    for k in range(9):
        a = math.tau * k / 9 + rng.uniform(-0.2, 0.2)
        x, y = 128.0, 128.0
        pts = [f"{x:.0f},{y:.0f}"]
        r = 0
        while r < 118:
            r += rng.uniform(14, 26)
            a += rng.uniform(-0.35, 0.35)
            pts.append(f"{128 + math.cos(a) * r:.0f},{128 + math.sin(a) * r:.0f}")
        w = rng.uniform(5, 8)
        b.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="#000" stroke-width="{w:.1f}" stroke-linejoin="round" stroke-linecap="round" opacity="0.75"/>')
        b.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="#fff" stroke-width="1.5" stroke-linejoin="round" opacity="0.25" transform="translate(2 2)"/>')
    b.insert(0, '<circle cx="128" cy="128" r="54" fill="url(#g)"/>')
    save("fx_crack", "\n".join(b), rad("g", [(0, "#000", 0.55), (1, "#000", 0)]), vb=256, size=192)

    save("fx_bubble", '<circle cx="32" cy="32" r="26" fill="#fff" fill-opacity="0.18" stroke="#fff" stroke-width="4"/>'
                      '<ellipse cx="22" cy="20" rx="7" ry="4" fill="#fff" transform="rotate(-35 22 20)"/>',
         vb=64, size=32)

    save("fx_streak", '<rect x="0" y="10" width="128" height="12" rx="6" fill="url(#h)"/>',
         lin("h", [(0, "#fff", 0), (0.7, "#fff", 0.8), (1, "#fff", 1)], x2=1, y2=0), vb=128, vbh=32, size=96, sizeh=24)

    defs = rad("g", [(0, "#fff6a0", 1), (0.7, "#ffc820", 1), (1, "#b07a00", 1)], cx=0.4, cy=0.35)
    save("fx_coin", '<circle cx="32" cy="32" r="26" fill="url(#g)" stroke="#6a4800" stroke-width="4"/>'
                    '<circle cx="32" cy="32" r="16" fill="none" stroke="#b07a00" stroke-width="3"/>'
                    '<ellipse cx="24" cy="22" rx="7" ry="4" fill="#fff" opacity="0.8" transform="rotate(-30 24 22)"/>',
         defs, vb=64, size=32)


# ════════════════════════════ 塔 ════════════════════════════

def towers():
    defs = rad("bs", [(0, "#9aa2b5", 1), (1, "#4b5263", 1)])
    b = ['<ellipse cx="66" cy="72" rx="56" ry="52" fill="#000" opacity="0.35"/>',
         '<circle cx="64" cy="64" r="52" fill="url(#bs)" stroke="#262a33" stroke-width="5"/>',
         '<circle cx="64" cy="64" r="38" fill="#5a6274" stroke="#343946" stroke-width="4"/>']
    for a in range(0, 360, 45):
        x, y = 64 + math.cos(math.radians(a + 22)) * 45, 64 + math.sin(math.radians(a + 22)) * 45
        b.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="3.5" fill="#2d323d"/>')
    save("tower_base", "\n".join(b), defs)

    # 箭塔：俯視的弩砲，朝上
    defs = lin("wd", [(0, "#a8703a", 1), (1, "#6b4423", 1)], x2=1, y2=0)
    b = ['<path d="M18 62 Q64 6 110 62" fill="none" stroke="#3a2412" stroke-width="15" stroke-linecap="round"/>',
         '<path d="M18 62 Q64 6 110 62" fill="none" stroke="#b07a40" stroke-width="9" stroke-linecap="round"/>',
         '<polyline points="18,62 64,84 110,62" fill="none" stroke="#efe6cc" stroke-width="3"/>',
         '<rect x="53" y="26" width="22" height="84" rx="7" fill="url(#wd)" stroke="#3a2412" stroke-width="4"/>',
         '<line x1="64" y1="20" x2="64" y2="88" stroke="#dfe3ec" stroke-width="5"/>',
         '<polygon points="64,2 53,24 75,24" fill="#eef2f8" stroke="#5a6070" stroke-width="3"/>',
         '<rect x="56" y="92" width="16" height="10" rx="3" fill="#3a2412"/>']
    save("tower_arrow", "\n".join(b), defs)

    # 大砲：俯視砲管，朝上
    defs = lin("mt", [(0, "#22252c", 1), (0.45, "#7a8292", 1), (1, "#22252c", 1)], x2=1, y2=0)
    defs += rad("br", [(0, "#6a7180", 1), (1, "#2a2e36", 1)], cx=0.4, cy=0.35)
    b = ['<rect x="26" y="70" width="12" height="40" rx="5" fill="#3a2a1c" stroke="#1c140c" stroke-width="3"/>',
         '<rect x="90" y="70" width="12" height="40" rx="5" fill="#3a2a1c" stroke="#1c140c" stroke-width="3"/>',
         '<rect x="45" y="8" width="38" height="84" rx="10" fill="url(#mt)" stroke="#111318" stroke-width="4"/>',
         '<rect x="40" y="4" width="48" height="16" rx="7" fill="#2a2e36" stroke="#111318" stroke-width="4"/>',
         '<rect x="45" y="44" width="38" height="8" fill="#15171c"/>',
         '<circle cx="64" cy="90" r="27" fill="url(#br)" stroke="#111318" stroke-width="4"/>']
    save("tower_cannon", "\n".join(b), defs)

    # 光環塔：水晶（白色，遊戲內依融合顏色染色）
    b = ['<polygon points="64,6 100,64 64,122 28,64" fill="#f4f6fa" stroke="#2a2d38" stroke-width="5" stroke-linejoin="round"/>',
         '<polygon points="64,6 64,122 28,64" fill="#ffffff"/>',
         '<polygon points="64,6 100,64 64,64" fill="#c9cfdb"/>',
         '<polygon points="64,64 100,64 64,122" fill="#9aa2b3"/>',
         '<polygon points="64,6 100,64 64,122 28,64" fill="none" stroke="#2a2d38" stroke-width="5" stroke-linejoin="round"/>',
         '<polyline points="46,58 60,30" fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" opacity="0.9"/>']
    for x, y in [(20, 20), (108, 20), (20, 108), (108, 108)]:
        b.append(f'<polygon points="{x},{y - 10} {x + 8},{y} {x},{y + 10} {x - 8},{y}" fill="#e6e9f0" stroke="#2a2d38" stroke-width="3"/>')
    save("tower_aura", "\n".join(b))

    defs = rad("gm", [(0, "#ffffff", 1), (0.6, "#e4e7ee", 1), (1, "#9aa0ad", 1)], cx=0.38, cy=0.35)
    b = ['<circle cx="32" cy="32" r="24" fill="url(#gm)" stroke="#1c1f26" stroke-width="5"/>',
         '<ellipse cx="24" cy="22" rx="7" ry="4" fill="#fff" opacity="0.9" transform="rotate(-30 24 22)"/>']
    save("gem", "\n".join(b), defs, vb=64, size=48)


# ════════════════════════════ 元素徽章 ════════════════════════════

def elements():
    icons = {
        "water": ("#7cc4ff", "#1d5fa8",
                  '<path d="M48 14 C48 14 22 46 22 60 a26 26 0 0 0 52 0 C74 46 48 14 48 14Z" fill="#eaf6ff" stroke="#0f3a6a" stroke-width="3"/>'
                  '<path d="M34 60 a14 14 0 0 0 10 14" fill="none" stroke="#7cc4ff" stroke-width="5" stroke-linecap="round"/>'),
        "fire": ("#ff9a6a", "#a8300f",
                 '<path d="M48 10 C60 30 78 40 73 63 C70 79 58 87 48 87 C36 87 24 79 23 63 C21 50 30 44 34 33 C38 44 42 46 44 44 C47 34 44 22 48 10Z" '
                 'fill="#fff3c8" stroke="#6a1a05" stroke-width="3"/>'
                 '<path d="M48 44 C56 54 62 60 59 70 C57 78 52 81 48 81 C42 81 37 77 37 69 C37 62 44 56 48 44Z" fill="#ff8a3a"/>'),
        "wood": ("#8fe09a", "#1f7a35",
                 '<path d="M22 74 C16 40 42 16 78 18 C80 54 58 80 22 74Z" fill="#effff0" stroke="#0f4a1f" stroke-width="3"/>'
                 '<path d="M26 70 C40 54 56 38 72 24 M40 56 L40 42 M52 45 L52 32 M44 53 L58 54 M55 42 L68 43" fill="none" '
                 'stroke="#3fae5a" stroke-width="4" stroke-linecap="round"/>'),
        "thunder": ("#ffe97a", "#a8860a",
                    '<polygon points="56,8 24,52 44,52 36,88 72,40 52,40" fill="#fffde8" stroke="#5a4500" stroke-width="3" stroke-linejoin="round"/>'),
        "earth": ("#d8ab7c", "#6f4a24",
                  '<polygon points="18,66 30,36 52,22 74,36 80,64 62,80 34,80" fill="#f6ebdd" stroke="#3f2810" stroke-width="3" stroke-linejoin="round"/>'
                  '<polyline points="30,36 46,52 52,22 M46,52 74,36 M46,52 62,80 M46,52 18,66" fill="none" stroke="#b98a5a" stroke-width="3"/>'
                  '<path d="M46 52 L74 36 M46 52 L62 80 M46 52 L18 66" stroke="#b98a5a" stroke-width="3"/>'),
    }
    for name, (c1, c2, icon) in icons.items():
        defs = rad("bg", [(0, c1, 1), (1, c2, 1)], cx=0.4, cy=0.35, r=0.7)
        b = (f'<circle cx="48" cy="48" r="44" fill="url(#bg)" stroke="#14161a" stroke-width="5"/>'
             f'<path d="M14 40 a36 36 0 0 1 50 -26" fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" opacity="0.45"/>{icon}')
        save(f"elem_{name}", b, defs, vb=96, size=96)


# ════════════════════════════ 敵人 ════════════════════════════

def eyes(lx, rx, y, r, look=2, angry=False):
    s = ""
    for x in (lx, rx):
        s += f'<circle cx="{x}" cy="{y}" r="{r}" fill="#fff" stroke="#1a1a1a" stroke-width="2.5"/>'
        s += f'<circle cx="{x + look}" cy="{y + 1}" r="{r * 0.5:.1f}" fill="#1a1a1a"/>'
    if angry:
        s += (f'<path d="M{lx - r - 3} {y - r - 5} L{lx + r} {y - r + 3} M{rx + r + 3} {y - r - 5} L{rx - r} {y - r + 3}" '
              'stroke="#1a1a1a" stroke-width="5" stroke-linecap="round"/>')
    return s


def enemies():
    shadow = '<ellipse cx="64" cy="110" rx="{}" ry="10" fill="#000" opacity="0.35"/>'

    defs = lin("b", [(0, "#ff8a94", 1), (1, "#b23344", 1)])
    b = [shadow.format(42),
         '<path d="M20 92 C12 50 40 22 64 22 C88 22 116 50 108 92 C106 108 22 108 20 92Z" fill="url(#b)" stroke="#5a1522" stroke-width="5"/>',
         '<ellipse cx="46" cy="40" rx="12" ry="7" fill="#fff" opacity="0.5" transform="rotate(-25 46 40)"/>',
         eyes(48, 80, 66, 11),
         '<path d="M54 86 Q64 94 74 86" fill="none" stroke="#5a1522" stroke-width="4" stroke-linecap="round"/>']
    save("enemy_normal", "\n".join(b), defs)

    defs = rad("b", [(0, "#ffd27a", 1), (1, "#d0721a", 1)], cx=0.4, cy=0.35)
    wing = 'M46 64 C30 26 8 34 2 58 C12 54 18 60 22 70 C28 64 36 68 40 80Z'
    b = [shadow.format(30),
         f'<path d="{wing}" fill="#7a3a12" stroke="#3a1a05" stroke-width="4" stroke-linejoin="round"/>',
         f'<path d="{wing}" fill="#7a3a12" stroke="#3a1a05" stroke-width="4" stroke-linejoin="round" transform="translate(128 0) scale(-1 1)"/>',
         '<polygon points="42,48 40,22 58,42" fill="#d0721a" stroke="#3a1a05" stroke-width="4" stroke-linejoin="round"/>',
         '<polygon points="86,48 88,22 70,42" fill="#d0721a" stroke="#3a1a05" stroke-width="4" stroke-linejoin="round"/>',
         '<circle cx="64" cy="68" r="27" fill="url(#b)" stroke="#3a1a05" stroke-width="5"/>',
         eyes(54, 74, 64, 8, angry=True),
         '<polygon points="56,80 60,90 64,80" fill="#fff"/><polygon points="64,80 68,90 72,80" fill="#fff"/>']
    save("enemy_fast", "\n".join(b), defs)

    defs = lin("b", [(0, "#a98ad0", 1), (1, "#57397a", 1)]) + lin("pl", [(0, "#d6dbe6", 1), (1, "#7d8596", 1)])
    b = [shadow.format(48),
         '<polygon points="20,44 6,26 30,32" fill="#c9cfdb" stroke="#22252c" stroke-width="4" stroke-linejoin="round"/>',
         '<polygon points="108,44 122,26 98,32" fill="#c9cfdb" stroke="#22252c" stroke-width="4" stroke-linejoin="round"/>',
         '<rect x="18" y="26" width="92" height="84" rx="28" fill="url(#b)" stroke="#2a1840" stroke-width="5"/>',
         '<path d="M26 44 Q64 10 102 44 L102 58 Q64 40 26 58Z" fill="url(#pl)" stroke="#22252c" stroke-width="4" stroke-linejoin="round"/>',
         '<rect x="30" y="60" width="68" height="18" rx="8" fill="#1a1422"/>',
         '<circle cx="48" cy="69" r="6" fill="#ffe14a"/><circle cx="80" cy="69" r="6" fill="#ffe14a"/>',
         '<path d="M30 88 H98 M40 98 H88" stroke="#2a1840" stroke-width="4" stroke-linecap="round"/>']
    for x in (34, 64, 94):
        b.append(f'<circle cx="{x}" cy="36" r="3.5" fill="#22252c"/>')
    save("enemy_tank", "\n".join(b), defs)

    defs = rad("b", [(0, "#d23a5a", 1), (1, "#4f0c20", 1)], cx=0.45, cy=0.35, r=0.7)
    defs += rad("au", [(0, "#ff3a6a", 0.45), (1, "#ff3a6a", 0)])
    b = ['<circle cx="64" cy="66" r="62" fill="url(#au)"/>', shadow.format(50),
         '<path d="M30 44 C10 36 6 14 16 4 C18 22 30 28 44 32Z" fill="#f1e6cc" stroke="#3a2a1a" stroke-width="4" stroke-linejoin="round"/>',
         '<path d="M98 44 C118 36 122 14 112 4 C110 22 98 28 84 32Z" fill="#f1e6cc" stroke="#3a2a1a" stroke-width="4" stroke-linejoin="round"/>',
         '<path d="M14 84 C8 44 36 22 64 22 C92 22 120 44 114 84 C110 112 18 112 14 84Z" fill="url(#b)" stroke="#2a0510" stroke-width="5"/>',
         '<polygon points="32,58 56,66 54,76 34,72" fill="#ffe14a" stroke="#2a0510" stroke-width="3"/>',
         '<polygon points="96,58 72,66 74,76 94,72" fill="#ffe14a" stroke="#2a0510" stroke-width="3"/>',
         '<path d="M26 52 L58 62 M102 52 L70 62" stroke="#2a0510" stroke-width="6" stroke-linecap="round"/>',
         '<path d="M36 88 H92 L86 100 H42Z" fill="#1a0308" stroke="#2a0510" stroke-width="3"/>',
         '<polygon points="42,88 47,98 52,88 57,98 62,88 67,98 72,88 77,98 82,88 86,98 90,88" fill="#fff"/>']
    save("enemy_boss", "\n".join(b), defs, size=128)


# ════════════════════════════ 投射物 / 特效 ════════════════════════════

def projectiles_fx():
    b = ['<line x1="32" y1="14" x2="32" y2="54" stroke="#c9a070" stroke-width="5" stroke-linecap="round"/>',
         '<polygon points="32,2 23,20 41,20" fill="#f2f5fa" stroke="#4a5060" stroke-width="2.5"/>',
         '<polygon points="32,44 22,60 32,54 42,60" fill="#e0465a" stroke="#6a1f2c" stroke-width="2"/>']
    save("arrow", "\n".join(b), vb=64, size=48)

    defs = rad("cb", [(0, "#8a92a3", 1), (0.5, "#3a3f4a", 1), (1, "#14161a", 1)], cx=0.35, cy=0.3, r=0.75)
    save("ball", '<circle cx="32" cy="32" r="24" fill="url(#cb)" stroke="#0a0b0e" stroke-width="4"/>'
                 '<ellipse cx="23" cy="21" rx="7" ry="4" fill="#fff" opacity="0.6" transform="rotate(-30 23 21)"/>',
         defs, vb=64, size=48)

    save("fx_glow", '<circle cx="64" cy="64" r="64" fill="url(#g)"/>',
         rad("g", [(0, "#fff", 1), (0.25, "#fff", 0.6), (0.6, "#fff", 0.15), (1, "#fff", 0)]), size=128)

    save("fx_spark", '<circle cx="32" cy="32" r="30" fill="url(#g)"/>'
                     '<path d="M32 0 L36 28 L64 32 L36 36 L32 64 L28 36 L0 32 L28 28Z" fill="#fff"/>',
         rad("g", [(0, "#fff", 0.8), (1, "#fff", 0)]), vb=64, size=64)

    save("fx_ring", '<circle cx="128" cy="128" r="128" fill="url(#g)"/>',
         rad("g", [(0, "#fff", 0), (0.55, "#fff", 0.05), (0.8, "#fff", 0.35), (0.9, "#fff", 1), (1, "#fff", 0)]),
         vb=256, size=256)

    rng = random.Random(5)
    defs = rad("g", [(0, "#fff", 0.9), (0.6, "#fff", 0.5), (1, "#fff", 0)])
    b = []
    for _ in range(7):
        x, y, r = rng.uniform(40, 88), rng.uniform(40, 88), rng.uniform(22, 36)
        b.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r:.0f}" fill="url(#g)"/>')
    save("fx_smoke", "\n".join(b), defs, size=96)

    # 隕石：由右上往左下墜落
    defs = lin("tl", [(0, "#ffe9a0", 0), (0.6, "#ff8a2a", 0.8), (1, "#ffe9a0", 1)], x2=-1, y2=1)
    defs += rad("rk", [(0, "#8a5a3a", 1), (1, "#2a1810", 1)], cx=0.6, cy=0.35)
    b = ['<polygon points="126,2 16,70 58,112" fill="#ff8a2a" opacity="0.45"/>',
         '<polygon points="110,18 22,76 52,106" fill="#ffd060" opacity="0.6"/>',
         '<circle cx="38" cy="90" r="34" fill="#ff9a2a" opacity="0.7"/>',
         '<circle cx="38" cy="90" r="26" fill="url(#rk)" stroke="#1a0c06" stroke-width="4"/>',
         '<circle cx="30" cy="84" r="6" fill="#1f120a"/><circle cx="46" cy="98" r="4" fill="#1f120a"/>',
         '<path d="M16 100 a26 26 0 0 0 34 14" fill="none" stroke="#ffd060" stroke-width="5" stroke-linecap="round"/>']
    save("meteor", "\n".join(b), defs, size=128)


# ════════════════════════════ 地形物件 ════════════════════════════

def zones():
    def z(name, body, defs=""):
        save(f"zone_{name}", body, defs, vb=256, size=256)

    rng = random.Random(21)
    z("puddle",
      f'<path d="{blob(128, 128, 112, 0.14, 11, rng)}" fill="#2f7fd8" opacity="0.55"/>'
      f'<path d="{blob(128, 128, 92, 0.16, 9, rng)}" fill="url(#g)"/>'
      '<path d="M70 96 q30 -26 66 -18 M96 176 q40 16 76 -8" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" opacity="0.6"/>'
      '<ellipse cx="170" cy="100" rx="16" ry="7" fill="#fff" opacity="0.5"/>',
      rad("g", [(0, "#bfe6ff", 0.85), (1, "#4aa8ff", 0.55)]))

    rng = random.Random(22)
    b = [f'<path d="{blob(128, 128, 114, 0.13, 12, rng)}" fill="#4a3c28" opacity="0.9"/>',
         f'<path d="{blob(128, 128, 96, 0.15, 10, rng)}" fill="#6b5a3e"/>',
         f'<path d="{blob(118, 120, 56, 0.25, 8, rng)}" fill="#7d6a49"/>']
    for _ in range(9):
        x, y, r = rng.uniform(64, 192), rng.uniform(64, 192), rng.uniform(5, 11)
        b.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r:.0f}" fill="#8f7a55" stroke="#3a2e1c" stroke-width="3"/>'
                 f'<circle cx="{x - r * 0.3:.0f}" cy="{y - r * 0.3:.0f}" r="{r * 0.3:.1f}" fill="#c8b48a"/>')
    z("mud", "\n".join(b))

    rng = random.Random(23)
    b = [f'<path d="{blob(128, 128, 116, 0.12, 12, rng)}" fill="#2a120a" opacity="0.9"/>',
         f'<path d="{blob(128, 128, 102, 0.13, 11, rng)}" fill="url(#g)"/>']
    for _ in range(8):
        x, y = rng.uniform(60, 196), rng.uniform(60, 196)
        b.append(f'<path d="{blob(x, y, rng.uniform(12, 24), 0.35, 7, rng)}" fill="#3a1a10" opacity="0.8"/>')
    z("lava", "\n".join(b), rad("g", [(0, "#fff0a0", 1), (0.45, "#ff9a2a", 1), (1, "#d8300c", 1)]))

    rng = random.Random(24)
    defs = rad("g", [(0, "#fff", 0.75), (0.6, "#fff", 0.4), (1, "#fff", 0)])
    b = []
    for i in range(11):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, 70)
        b.append(f'<circle cx="{128 + math.cos(a) * d:.0f}" cy="{128 + math.sin(a) * d:.0f}" r="{rng.uniform(36, 56):.0f}" fill="url(#g)"/>')
    z("cloud", "\n".join(b), defs)

    rng = random.Random(25)
    b = ['<circle cx="128" cy="128" r="118" fill="#1f5a3a" opacity="0.35"/>']
    for i in range(10):
        a = math.tau * i / 10
        x2, y2 = 128 + math.cos(a) * 112, 128 + math.sin(a) * 112
        cx, cy = 128 + math.cos(a + 0.7) * 70, 128 + math.sin(a + 0.7) * 70
        b.append(f'<path d="M128 128 Q{cx:.0f} {cy:.0f} {x2:.0f} {y2:.0f}" fill="none" stroke="#5a3a1c" stroke-width="9" stroke-linecap="round"/>'
                 f'<path d="M128 128 Q{cx:.0f} {cy:.0f} {x2:.0f} {y2:.0f}" fill="none" stroke="#3f9a5a" stroke-width="4" stroke-linecap="round"/>')
    for i in range(9):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(20, 70)
        x, y = 128 + math.cos(a) * d, 128 + math.sin(a) * d
        b.append(f'<path d="{blob(x, y, rng.uniform(24, 36), 0.2, 8, rng)}" fill="{rng.choice(["#2f8a55", "#3fae6a", "#57c97e"])}" '
                 'stroke="#14402a" stroke-width="4"/>')
    b.append(f'<path d="{blob(128, 128, 30, 0.15, 8, rng)}" fill="#6fdc8e" stroke="#14402a" stroke-width="4"/>')
    z("vines", "\n".join(b))

    rng = random.Random(26)
    b = ['<circle cx="128" cy="128" r="118" fill="#4a5a1c" opacity="0.3"/>']
    for i in range(15):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, 96) if i else 0
        x, y = 128 + math.cos(a) * d, 128 + math.sin(a) * d
        n, r1, r0 = 7, rng.uniform(18, 28), 7
        pts = []
        off = rng.uniform(0, 1)
        for k in range(n * 2):
            rr = r1 if k % 2 == 0 else r0
            aa = off + math.pi * k / n
            pts.append(f"{x + math.cos(aa) * rr:.0f},{y + math.sin(aa) * rr:.0f}")
        b.append(f'<polygon points="{" ".join(pts)}" fill="{rng.choice(["#7a8a2a", "#93a53a", "#6a7a22"])}" stroke="#2a3208" stroke-width="3" stroke-linejoin="round"/>'
                 f'<circle cx="{x:.0f}" cy="{y:.0f}" r="4" fill="#c8d86a"/>')
    z("thorns", "\n".join(b))

    b = ['<circle cx="128" cy="128" r="124" fill="url(#g)"/>']
    for k in range(4):
        pts = []
        for i in range(34):
            a = k * math.tau / 4 + i * 0.16
            r = 8 + i * 3.4
            pts.append(f"{128 + math.cos(a) * r:.1f},{128 + math.sin(a) * r:.1f}")
        b.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="#fff" stroke-width="9" stroke-linecap="round" opacity="0.75"/>')
    z("vortex", "\n".join(b), rad("g", [(0, "#fff", 0.7), (0.5, "#fff", 0.25), (1, "#fff", 0)]))

    z("warn",
      '<circle cx="128" cy="128" r="118" fill="#fff" opacity="0.12"/>'
      '<circle cx="128" cy="128" r="118" fill="none" stroke="#fff" stroke-width="7" stroke-dasharray="28 18"/>'
      '<circle cx="128" cy="128" r="60" fill="none" stroke="#fff" stroke-width="5" opacity="0.8"/>'
      '<path d="M128 20 V84 M128 172 V236 M20 128 H84 M172 128 H236" stroke="#fff" stroke-width="7" stroke-linecap="round"/>'
      '<circle cx="128" cy="128" r="10" fill="#fff"/>')

    defs = lin("wd", [(0, "#a8703a", 1), (1, "#5a3a1c", 1)], x2=1, y2=0)
    b = ['<ellipse cx="64" cy="176" rx="40" ry="10" fill="#000" opacity="0.4"/>',
         '<polygon points="64,2 56,30 72,30" fill="#ffe97a" stroke="#5a4500" stroke-width="3"/>',
         '<path d="M40 60 L4 44 L14 70 L40 78Z" fill="#8fbf3a" stroke="#2a3a0a" stroke-width="4" stroke-linejoin="round"/>',
         '<path d="M88 60 L124 44 L114 70 L88 78Z" fill="#8fbf3a" stroke="#2a3a0a" stroke-width="4" stroke-linejoin="round"/>',
         '<rect x="38" y="28" width="52" height="150" rx="10" fill="url(#wd)" stroke="#2a1808" stroke-width="5"/>',
         '<path d="M38 80 H90 M38 130 H90" stroke="#2a1808" stroke-width="5"/>']
    for y in (54, 104, 154):
        b.append(f'<circle cx="52" cy="{y - 4}" r="6" fill="#ffe14a" stroke="#2a1808" stroke-width="3"/>'
                 f'<circle cx="76" cy="{y - 4}" r="6" fill="#ffe14a" stroke="#2a1808" stroke-width="3"/>'
                 f'<path d="M50 {y + 12} H78" stroke="#2a1808" stroke-width="5" stroke-linecap="round"/>')
    save("totem", "\n".join(b), defs, vb=128, vbh=192, size=96, sizeh=144)


if __name__ == "__main__":
    decor()
    ability_fx()
    castle()
    portal()
    towers()
    elements()
    enemies()
    projectiles_fx()
    zones()
    print(f"wrote {len(list(OUT.glob('*.svg')))} svg files to {OUT}")
