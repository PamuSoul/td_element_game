#!/usr/bin/env python3
"""合成遊戲 BGM（純 Python，無外部套件）→ assets/audio/bgm.ogg（需要 ffmpeg 編碼）。

D 小調奇幻風：弦樂墊音 + 豎琴琶音 + 低音 + 長笛旋律 + 輕打擊，32 小節無縫循環（約 80 秒）。
重新產生：python3 tools/gen_bgm.py   （或 make art）
"""
import math
import random
import struct
import subprocess
import tempfile
from array import array
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "bgm.ogg"
SR = 32000
BPM = 96
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = 32
N = int(round(BAR * BARS * SR))
TAU = math.tau

rng = random.Random(42)
L = array("f", bytes(4 * N))
R = array("f", bytes(4 * N))


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def note(name):
    """'D5' / 'C#5' / 'Bb4' → MIDI"""
    base = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}[name[0]]
    rest = name[1:]
    if rest[0] == "#":
        base += 1
        rest = rest[1:]
    elif rest[0] == "b":
        base -= 1
        rest = rest[1:]
    return base + 12 * (int(rest) + 1)


def add(buf, t0, pan=0.0, gain=1.0):
    """把單聲道 buf 混到 t0 秒處（循環包回開頭，讓尾音接上下一圈）。"""
    i0 = int(t0 * SR)
    gl = gain * math.cos((pan + 1) * math.pi / 4)
    gr = gain * math.sin((pan + 1) * math.pi / 4)
    for k, v in enumerate(buf):
        j = (i0 + k) % N
        L[j] += v * gl
        R[j] += v * gr


def env(i, n, a, r):
    """線性 attack / release（樣本數）"""
    e = 1.0
    if i < a:
        e = i / a
    if i > n - r:
        e = min(e, max(0.0, (n - i) / r))
    return e


# ── 波表 ──
TBL = 2048


def table(harm):
    t = array("f", [0.0] * TBL)
    for k in range(TBL):
        t[k] = sum(a * math.sin(TAU * h * k / TBL) for h, a in harm)
    m = max(abs(x) for x in t)
    return array("f", [x / m for x in t])


SAW_SOFT = table([(h, 1.0 / h ** 1.3) for h in range(1, 9)])
FLUTE = table([(1, 1.0), (2, 0.28), (3, 0.12), (4, 0.04)])
BELL = table([(1, 1.0), (2.0, 0.0), (3, 0.25), (4.2, 0.0)])


def osc(tbl, f, n, phase=0.0, vib=0.0, vib_rate=5.0, vib_delay=0.0):
    out = array("f", [0.0] * n)
    p = phase * TBL
    inc = f * TBL / SR
    for i in range(n):
        if vib:
            t = i / SR
            depth = vib * min(1.0, max(0.0, (t - vib_delay) / 0.3))
            p += inc * (1.0 + depth * math.sin(TAU * vib_rate * t))
        else:
            p += inc
        out[i] = tbl[int(p) % TBL]
    return out


# ── 樂器 ──
_cache = {}


def pad(chord, dur):
    key = ("pad", tuple(chord), dur)
    if key in _cache:
        return _cache[key]
    n = int(dur * SR)
    out = array("f", [0.0] * n)
    for m in chord:
        for det in (-0.12, 0.12):
            w = osc(SAW_SOFT, hz(m + det), n, phase=rng.random())
            for i in range(n):
                out[i] += w[i]
    a, r = int(0.5 * SR), int(0.6 * SR)
    lp = 0.0
    for i in range(n):
        lp += 0.12 * (out[i] - lp)  # 一階低通，讓音色柔和
        out[i] = lp * env(i, n, a, r) / (len(chord) * 2)
    _cache[key] = out
    return out


def pluck(m, dur=1.6, bright=0.5):
    """豎琴：加法合成，高次泛音衰減得更快。"""
    key = ("pluck", m, dur, bright)
    if key in _cache:
        return _cache[key]
    n = int(dur * SR)
    f = hz(m)
    parts = [(h, (1.0 / h ** (1.6 - bright)), 2.2 + h * 1.6) for h in range(1, 7)]
    norm = sum(a for _, a, _ in parts)
    out = array("f", [0.0] * n)
    for i in range(n):
        t = i / SR
        v = 0.0
        for h, a, d in parts:
            v += a * math.sin(TAU * f * h * t) * math.exp(-t * d)
        out[i] = v / norm * min(1.0, i / 24)
    _cache[key] = out
    return out


def bass(m, dur):
    key = ("bass", m, dur)
    if key in _cache:
        return _cache[key]
    n = int(dur * SR)
    f = hz(m)
    out = array("f", [0.0] * n)
    a, r = int(0.01 * SR), int(0.12 * SR)
    for i in range(n):
        t = i / SR
        ph = TAU * f * t
        dec = 0.6 + 0.4 * math.exp(-t * 3.0)
        out[i] = (math.sin(ph) + 0.35 * math.sin(2 * ph) + 0.12 * math.sin(3 * ph)) * env(i, n, a, r) * dec
    _cache[key] = out
    return out


def flute(m, dur):
    n = int((dur + 0.15) * SR)
    w = osc(FLUTE, hz(m), n, vib=0.006, vib_rate=5.2, vib_delay=0.18)
    a, r = int(0.06 * SR), int(0.18 * SR)
    noise_lp = 0.0
    for i in range(n):
        noise_lp += 0.08 * (rng.uniform(-1, 1) - noise_lp)
        w[i] = (w[i] + noise_lp * 0.6) * env(i, n, a, r)
    return w


def bell(m, dur=1.4):
    key = ("bell", m)
    if key in _cache:
        return _cache[key]
    n = int(dur * SR)
    f = hz(m)
    out = array("f", [0.0] * n)
    for i in range(n):
        t = i / SR
        out[i] = (math.sin(TAU * f * t) + 0.4 * math.sin(TAU * f * 2.76 * t) * math.exp(-t * 6)
                  + 0.2 * math.sin(TAU * f * 5.4 * t) * math.exp(-t * 10)) * math.exp(-t * 3.2) * min(1.0, i / 40)
    _cache[key] = out
    return out


def kick():
    if "kick" in _cache:
        return _cache["kick"]
    n = int(0.4 * SR)
    out = array("f", [0.0] * n)
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 45 + 90 * math.exp(-t * 28)
        ph += TAU * f / SR
        out[i] = math.sin(ph) * math.exp(-t * 7.5)
    _cache["kick"] = out
    return out


def drum(tone=180.0, noise=0.6, decay=14.0):
    key = ("drum", tone, noise, decay)
    if key in _cache:
        return _cache[key]
    n = int(0.35 * SR)
    out = array("f", [0.0] * n)
    lp = 0.0
    for i in range(n):
        t = i / SR
        lp += 0.35 * (rng.uniform(-1, 1) - lp)
        out[i] = (math.sin(TAU * tone * t) * (1 - noise) + lp * noise * 1.6) * math.exp(-t * decay)
    _cache[key] = out
    return out


def shaker():
    if "shaker" in _cache:
        return _cache["shaker"]
    n = int(0.08 * SR)
    out = array("f", [0.0] * n)
    prev = 0.0
    for i in range(n):
        x = rng.uniform(-1, 1)
        out[i] = (x - prev) * 0.5 * math.sin(math.pi * i / n) ** 2  # 一階高通
        prev = x
    _cache["shaker"] = out
    return out


# ── 樂曲 ──
CHORDS = {
    "Dm": ([50, 53, 57, 62], 38), "Bb": ([50, 53, 58, 62], 34), "F": ([48, 53, 57, 60], 41),
    "C": ([48, 52, 55, 60], 36), "Gm": ([50, 55, 58, 62], 43), "A": ([49, 52, 57, 61], 45),
    "Am": ([48, 52, 57, 60], 45),
}
PROG_A = ["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "A"]
PROG_B = ["Bb", "C", "Am", "Dm", "Bb", "C", "Gm", "A"]

MEL_A = [
    [("A4", 1), ("D5", 1), ("E5", .5), ("F5", 1.5)],
    [("E5", .5), ("D5", .5), ("F5", 1), ("D5", 2)],
    [("C5", 1), ("A4", 1), ("C5", .5), ("F5", 1.5)],
    [("E5", 1), ("G5", 1), ("E5", .5), ("C5", 1.5)],
    [("D5", 1), ("F5", 1), ("A5", 1), ("G5", .5), ("F5", .5)],
    [("F5", 1.5), ("D5", .5), ("Bb4", 1), ("D5", 1)],
    [("G5", 1), ("F5", .5), ("E5", .5), ("D5", 1), ("Bb4", 1)],
    [("C#5", 2), ("E5", 1), ("A4", 1)],
]
MEL_B = [
    [("F5", 1.5), ("G5", .5), ("F5", 1), ("D5", 1)],
    [("E5", 1.5), ("F5", .5), ("G5", 2)],
    [("A5", 1), ("G5", .5), ("E5", .5), ("C5", 1), ("E5", 1)],
    [("D5", 3), ("A4", 1)],
    [("Bb4", .5), ("D5", .5), ("F5", 1), ("Bb5", 1.5), ("A5", .5)],
    [("G5", 1), ("E5", 1), ("C5", 1), ("E5", 1)],
    [("D5", 1), ("G5", 1), ("Bb5", 1), ("A5", .5), ("G5", .5)],
    [("A5", 2), ("G5", .5), ("E5", .5), ("C#5", 1)],
]
ARP = [0, 1, 2, 3, 2, 1, 2, 1]

# 段落：(和弦進行, 旋律, 鼓組強度, 是否加鐘聲)
SECTIONS = [(PROG_A, None, 0, False), (PROG_A, MEL_A, 1, False), (PROG_B, MEL_B, 2, False), (PROG_A, MEL_A, 2, True)]


def compose():
    for s_i, (prog, mel, drums, bells) in enumerate(SECTIONS):
        for b_i, name in enumerate(prog):
            bar = s_i * 8 + b_i
            t0 = bar * BAR
            tones, root = CHORDS[name]
            add(pad(tones, BAR + 0.5), t0, gain=0.55)
            # 豎琴琶音（八分音符，左右輕微擺盪）
            arp_tones = [m + 12 for m in tones]
            for k in range(8):
                m = arp_tones[ARP[k]]
                add(pluck(m, 1.4, 0.55), t0 + k * BEAT / 2, pan=-0.35 + 0.1 * (k % 4), gain=0.32 if k % 2 == 0 else 0.24)
            # 低音：1、3 拍 + 第 4 拍後半的經過音
            add(bass(root, BEAT * 1.9), t0, gain=0.5)
            add(bass(root, BEAT * 1.4), t0 + 2 * BEAT, gain=0.45)
            add(bass(root + 7, BEAT * 0.45), t0 + 3.5 * BEAT, gain=0.35)
            # 打擊
            add(kick(), t0, gain=0.55 if drums else 0.35)
            if drums >= 1:
                add(kick(), t0 + 2 * BEAT, gain=0.45)
                for k in range(8):
                    add(shaker(), t0 + k * BEAT / 2, pan=0.4, gain=0.22 if k % 2 else 0.12)
            if drums >= 2:
                add(kick(), t0 + 2.5 * BEAT, gain=0.3)
                add(drum(190, 0.65, 16), t0 + BEAT, pan=-0.1, gain=0.32)
                add(drum(190, 0.65, 16), t0 + 3 * BEAT, pan=-0.1, gain=0.32)
                if b_i == 7:  # 段落尾的太鼓過門
                    for k, x in enumerate([2.5, 3.0, 3.25, 3.5, 3.75]):
                        add(drum(95 + k * 8, 0.3, 9), t0 + x * BEAT, pan=0.15, gain=0.4)
            # 旋律
            if mel:
                t = t0
                for nm, d in mel[b_i]:
                    m = note(nm)
                    add(flute(m, d * BEAT), t, pan=0.15, gain=0.3)
                    if bells:
                        add(bell(m + 12), t, pan=-0.3, gain=0.1)
                    t += d * BEAT
        print(f"section {s_i + 1}/{len(SECTIONS)} done")


def reverb():
    """Schroeder 殘響：從曲尾接到曲頭，讓循環接縫也有殘響。"""
    combs = [(1116, 1188, 1277, 1356), (1139, 1211, 1300, 1379)]
    aps = [(556, 441), (579, 464)]
    scale = SR / 44100
    for ch, buf in enumerate((L, R)):
        src = buf[-SR * 3:] + buf  # 前接 3 秒曲尾
        n = len(src)
        wet = array("f", [0.0] * n)
        for d0 in combs[ch]:
            d = int(d0 * scale)
            line = [0.0] * d
            lp = 0.0
            k = 0
            for i in range(n):
                y = line[k]
                lp = y * 0.7 + lp * 0.3
                line[k] = src[i] * 0.015 + lp * 0.84
                wet[i] += y
                k += 1
                if k == d:
                    k = 0
        for d0 in aps[ch]:
            d = int(d0 * scale)
            line = [0.0] * d
            k = 0
            for i in range(n):
                y = line[k]
                x = wet[i]
                line[k] = x + y * 0.5
                wet[i] = y - x * 0.5
                k += 1
                if k == d:
                    k = 0
        off = SR * 3
        for i in range(N):
            buf[i] += wet[off + i] * 1.1


def main():
    compose()
    print("reverb…")
    reverb()
    peak = max(max(abs(x) for x in L), max(abs(x) for x in R))
    g = 0.95 / peak
    data = bytearray()
    for i in range(N):
        l = math.tanh(L[i] * g * 1.1)
        r = math.tanh(R[i] * g * 1.1)
        data += struct.pack("<hh", int(l * 30000), int(r * 30000))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        hdr = struct.pack("<4sI4s4sIHHIIHH4sI", b"RIFF", 36 + len(data), b"WAVE", b"fmt ", 16, 1, 2, SR, SR * 4, 4, 16,
                          b"data", len(data))
        tmp.write(hdr + data)
        tmp.flush()
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "4", str(OUT)],
                       check=True)
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB, {N / SR:.1f}s)")


if __name__ == "__main__":
    main()
