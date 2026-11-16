"""Synthesises the game's SFX pack into assets/sfx/*.ogg (and .wav).

    pip install numpy scipy && python3 tools/make_sfx.py

Every sound is generated from code: no samples, no licensing questions.
Loops (*_loop) are crossfaded so they repeat with no click. Variants (_1, _2...)
exist so repeated sounds don't feel robotic; pick one at random in game AND
randomise PlaybackSpeed a little.

Upload: Creator Hub > Development Items > Audio (or Asset Manager > Bulk Import),
then paste ids into the Sounds config.
"""
import math
import os
import subprocess
import sys

import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
rng = np.random.default_rng(7)
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sfx")


# ------------------------------------------------------------------ helpers
def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def phase(freq):
    """Integrate an instantaneous-frequency array into phase."""
    return 2 * np.pi * np.cumsum(freq) / SR


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def lp(x, f, order=2):
    return sosfilt(butter(order, f, btype="low", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return sosfilt(butter(order, f, btype="high", fs=SR, output="sos"), x)


def sweep_bp(x, f0, f1, width=0.6, steps=48):
    """Band-pass whose centre glides f0 -> f1 (exponential), done in blocks."""
    out = np.zeros_like(x)
    n = len(x)
    edges = np.linspace(0, n, steps + 1).astype(int)
    win = np.hanning(2 * (edges[1] - edges[0]) + 2)
    for k in range(steps):
        a, b = edges[k], edges[k + 1]
        c = f0 * (f1 / f0) ** (k / max(1, steps - 1))
        lo, hi = max(30, c * (1 - width / 2)), min(SR / 2 - 100, c * (1 + width / 2))
        seg_a, seg_b = max(0, a - (b - a) // 2), min(n, b + (b - a) // 2)
        y = bp(x[seg_a:seg_b], lo, hi)
        w = np.hanning(len(y))
        out[seg_a:seg_b] += y * w
    return out / 1.0


def env_adsr(n, a=0.005, d=0.05, s=0.6, r=0.1, dur=None):
    dur = dur or n / SR
    t = np.arange(n) / SR
    e = np.ones(n) * s
    e[t < a] = t[t < a] / max(a, 1e-6)
    m = (t >= a) & (t < a + d)
    e[m] = 1 - (1 - s) * (t[m] - a) / max(d, 1e-6)
    rel = t > dur - r
    e[rel] *= np.clip((dur - t[rel]) / max(r, 1e-6), 0, 1)
    return e


def exp_decay(n, tau):
    return np.exp(-np.arange(n) / SR / tau)


def fade(x, fin=0.003, fout=0.01):
    n_in, n_out = int(SR * fin), int(SR * fout)
    if n_in:
        x[:n_in] *= np.linspace(0, 1, n_in)
    if n_out:
        x[-n_out:] *= np.linspace(1, 0, n_out)
    return x


def norm(x, peak_db=-1.0):
    p = np.max(np.abs(x)) or 1
    return x / p * (10 ** (peak_db / 20))


def soft_clip(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def make_loop(fn, dur, xfade=0.4):
    """Render dur+xfade and crossfade the tail into the head: seamless loop."""
    x = fn(dur + xfade)
    n, nx = int(SR * dur), int(SR * xfade)
    head, tail = x[:nx], x[n : n + nx]
    w = np.sin(np.linspace(0, np.pi / 2, nx)) ** 2
    out = x[:n].copy()
    out[:nx] = head * w + tail * (1 - w)
    return out


def noise(n):
    return rng.standard_normal(n)


def pink(n):
    w = noise(n)
    f = np.fft.rfft(w)
    f /= np.maximum(1, np.sqrt(np.arange(len(f))))
    return np.fft.irfft(f, n)


def reverb(x, wet=0.18):
    """Tiny feedback-free room: a few diffused taps. Makes synthetic sounds less dry."""
    out = x.copy()
    for ms, g in ((23, 0.5), (37, 0.4), (53, 0.33), (71, 0.25), (97, 0.18), (131, 0.12)):
        d = int(SR * ms / 1000)
        tap = np.zeros_like(x)
        tap[d:] = x[:-d] * g
        out += lp(tap, 5000) * wet
    return out


# ------------------------------------------------------------------ sounds
def hover_loop(dur):
    t = t_axis(dur)
    wob = 1 + 0.004 * np.sin(2 * np.pi * 0.5 * t)
    f = 92 * wob
    p = phase(f)
    hum = 0.55 * np.sin(p) + 0.28 * np.sin(2 * p) + 0.14 * np.sin(3 * p + 0.3) + 0.06 * np.sin(4 * p)
    hum = soft_clip(hum, 1.2)
    shimmer = 0.035 * np.sin(phase(np.full_like(t, 1840))) * (0.6 + 0.4 * np.sin(2 * np.pi * 6 * t))
    air = bp(pink(len(t)), 300, 1600) * 0.6 * (0.8 + 0.2 * np.sin(2 * np.pi * 0.5 * t))
    x = hum + shimmer + air / (np.max(np.abs(air)) + 1e-9) * 0.18
    return lp(x, 2600)


def hover_start(dur=0.7):
    t = t_axis(dur)
    f = 55 + (92 - 55) * (1 - np.exp(-t * 6))
    hum = 0.6 * np.sin(phase(f)) + 0.25 * np.sin(2 * phase(f))
    whoosh = sweep_bp(noise(len(t)), 350, 2600, 0.7)
    whoosh /= np.max(np.abs(whoosh)) + 1e-9
    e = env_adsr(len(t), a=0.03, d=0.25, s=0.55, r=0.2)
    return (hum * np.clip(t * 4, 0, 1) + whoosh * 0.5 * np.exp(-((t - 0.25) ** 2) / 0.02)) * e


def hover_stop(dur=0.55):
    t = t_axis(dur)
    f = 92 * np.exp(-t * 1.6)
    hum = 0.6 * np.sin(phase(f)) + 0.2 * np.sin(2 * phase(f))
    whoosh = sweep_bp(noise(len(t)), 2200, 300, 0.7)
    whoosh /= np.max(np.abs(whoosh)) + 1e-9
    return (hum * exp_decay(len(t), 0.18) + whoosh * 0.45 * exp_decay(len(t), 0.15)) * env_adsr(len(t), a=0.005, d=0.1, s=0.9, r=0.15)


def vac_loop(dur):
    t = t_axis(dur)
    n = len(t)
    wind = bp(noise(n), 700, 4200, 2)
    wind /= np.max(np.abs(wind)) + 1e-9
    flutter = 0.85 + 0.15 * np.sin(2 * np.pi * 9 * t) * np.sin(2 * np.pi * 0.7 * t)
    whistle = bp(noise(n), 1150, 1350, 2)
    whistle /= np.max(np.abs(whistle)) + 1e-9
    rumble = 0.25 * np.sin(phase(np.full(n, 68))) + 0.12 * np.sin(phase(np.full(n, 136)))
    motor = 0.05 * np.sin(phase(np.full(n, 410)))
    return wind * 0.55 * flutter + whistle * 0.2 + rumble + motor


def vac_start(dur=0.45):
    t = t_axis(dur)
    w = sweep_bp(noise(len(t)), 300, 3200, 0.8)
    w /= np.max(np.abs(w)) + 1e-9
    rumble = 0.3 * np.sin(phase(40 + 30 * t / dur))
    return (w * 0.7 + rumble) * (t / dur) ** 0.7 * env_adsr(len(t), a=0.01, d=0.0, s=1, r=0.03)


def vac_stop(dur=0.4):
    t = t_axis(dur)
    w = sweep_bp(noise(len(t)), 3000, 250, 0.8)
    w /= np.max(np.abs(w)) + 1e-9
    thup = np.sin(phase(160 * np.exp(-t * 10))) * exp_decay(len(t), 0.05) * 0.5
    return w * 0.6 * exp_decay(len(t), 0.12) + thup


def slurp_pop(pitch=1.0, dur=0.32):
    t = t_axis(dur)
    n = len(t)
    # wet "gloop": descending tone with a vowel-ish second partial
    f = 950 * pitch * np.exp(-t * 11) + 220 * pitch
    g = np.sin(phase(f)) + 0.45 * np.sin(phase(f * 2.02)) + 0.2 * np.sin(phase(f * 3.1))
    g *= np.exp(-((t - 0.06) ** 2) / 0.0025) * (t < 0.16)
    gurgle = bp(noise(n), 400 * pitch, 1800 * pitch) * 0.25 * np.exp(-((t - 0.07) ** 2) / 0.002)
    # the pop when it lands in the tank
    tp = np.clip(t - 0.13, 0, None)
    pf = 1500 * pitch * np.exp(-tp * 60) + 500 * pitch
    pop = np.sin(phase(pf)) * np.exp(-tp / 0.03) * (t >= 0.13)
    click = hp(noise(n), 3000) * np.exp(-tp / 0.003) * (t >= 0.13) * 0.4
    return reverb(g * 0.8 + gurgle + pop * 0.9 + click)


def shoot(pitch=1.0, dur=0.32):
    t = t_axis(dur)
    n = len(t)
    thump = np.sin(phase(130 * pitch * np.exp(-t * 14) + 50)) * exp_decay(n, 0.06)
    sq_f = 280 * pitch + 900 * pitch * (1 - np.exp(-t * 18))
    squish = (np.sin(phase(sq_f + 18 * np.sin(2 * np.pi * 35 * t))) * 0.5) * np.exp(-((t - 0.07) ** 2) / 0.003)
    air = sweep_bp(noise(n), 600, 2400, 0.9)
    air = air / (np.max(np.abs(air)) + 1e-9) * 0.3 * exp_decay(n, 0.08)
    return reverb(soft_clip(thump * 1.1 + squish + air, 1.3))


def squeak(f0, rise=1.35, dur=0.16, vib=24):
    t = t_axis(dur)
    shape = np.sin(np.pi * t / dur)  # up then down
    f = f0 * (1 + (rise - 1) * shape) * (1 + 0.02 * np.sin(2 * np.pi * vib * t))
    x = np.sin(phase(f)) + 0.3 * np.sin(2 * phase(f)) + 0.08 * np.sin(3 * phase(f))
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.6
    return reverb(lp(x * e, 5000), wet=0.12)


def boing(f0, dur=0.38):
    t = t_axis(dur)
    f = f0 * (1 + 0.45 * np.exp(-t * 9) * np.sin(2 * np.pi * 11 * t)) * (1 + 0.25 * np.exp(-t * 20))
    x = np.sin(phase(f)) + 0.25 * np.sin(2 * phase(f))
    return reverb(x * exp_decay(len(t), 0.11) * env_adsr(len(t), a=0.004, d=0, s=1, r=0.05))


def nom(f0=330, dur=0.22):
    t = t_axis(dur)
    out = np.zeros(len(t))
    for start, ff in ((0.0, f0), (0.1, f0 * 0.8)):
        tt = np.clip(t - start, 0, None)
        f = ff * np.exp(-tt * 5)
        blip = (np.sin(phase(f)) + 0.35 * np.sin(2 * phase(f))) * np.exp(-tt / 0.03) * (t >= start)
        out += blip
    return reverb(out, wet=0.1)


def chime(notes, dur=0.7, gap=0.06):
    t = t_axis(dur)
    out = np.zeros(len(t))
    for i, fr in enumerate(notes):
        tt = np.clip(t - i * gap, 0, None)
        on = t >= i * gap
        tone = np.sin(2 * np.pi * fr * tt) + 0.4 * np.sin(2 * np.pi * fr * 2.76 * tt) * np.exp(-tt / 0.05) + 0.2 * np.sin(2 * np.pi * fr * 5.4 * tt) * np.exp(-tt / 0.02)
        out += tone * np.exp(-tt / 0.22) * on
    return reverb(out, wet=0.25)


def sparkle_arp(dur=0.9):
    notes = [1046.5, 1318.5, 1568.0, 2093.0]
    out = chime(notes, dur, gap=0.07)
    t = t_axis(dur)
    glitter = hp(noise(len(t)), 6000) * 0.08 * np.exp(-((t - 0.3) ** 2) / 0.03)
    return out + glitter


def click(dur=0.06):
    t = t_axis(dur)
    x = np.sin(phase(2200 * np.exp(-t * 40) + 900)) * exp_decay(len(t), 0.012)
    return x + hp(noise(len(t)), 4000) * exp_decay(len(t), 0.002) * 0.3


def wall_rise(dur=1.3):
    t = t_axis(dur)
    f = 110 * (1 + 1.2 * (t / dur) ** 1.5)
    hum = np.sin(phase(f)) * 0.5 + np.sin(phase(f * 1.5)) * 0.25 + np.sin(phase(f * 2)) * 0.15
    w = sweep_bp(noise(len(t)), 400, 3000, 0.6)
    w /= np.max(np.abs(w)) + 1e-9
    e = env_adsr(len(t), a=0.15, d=0.0, s=1, r=0.35)
    ding = np.zeros(len(t))
    c = chime([784, 1175, 1568], 0.6)
    start = int(SR * 0.7)
    ding[start : start + len(c)] = c[: len(t) - start]
    return reverb((hum + w * 0.35) * e + ding * 0.5)


def alarm(dur=0.9):
    t = t_axis(dur)
    f = np.where((t * 6).astype(int) % 2 == 0, 880, 660)
    x = np.sin(phase(f)) + 0.3 * np.sin(3 * phase(f))
    return lp(x, 3500) * env_adsr(len(t), a=0.01, d=0, s=1, r=0.1)


def denied(dur=0.18):
    t = t_axis(dur)
    x = np.sin(phase(220 * np.exp(-t * 3))) + 0.5 * np.sin(phase(233 * np.exp(-t * 3)))
    return x * exp_decay(len(t), 0.07)


# ------------------------------------------------------------------ export
def export(name, x, peak_db, loop=False):
    x = norm(x, peak_db).astype(np.float64)
    if not loop:  # fading a loop's ends would cause a dip every repeat
        x = fade(x)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    wav = os.path.join(OUT, name + ".wav")
    import wave
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    ogg = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "6", ogg], check=True)
    print(f"{name:22s} {len(x) / SR:5.2f}s  peak {peak_db} dB")


def main():
    os.makedirs(OUT, exist_ok=True)
    # loops: export at a moderate level; in-game Volume does the rest
    export("hover_loop", make_loop(hover_loop, 2.0), -4, loop=True)
    export("vac_loop", make_loop(vac_loop, 2.0), -4, loop=True)
    export("hover_start", hover_start(), -3)
    export("hover_stop", hover_stop(), -4)
    export("vac_start", vac_start(), -4)
    export("vac_stop", vac_stop(), -5)
    for i, p in enumerate((0.92, 1.0, 1.08, 1.17), 1):
        export(f"slurp_pop_{i}", slurp_pop(p), -2)
    for i, p in enumerate((0.9, 1.0, 1.12), 1):
        export(f"shoot_{i}", shoot(p), -2)
    # slime voices: kept quiet on purpose (peak -10 dB)
    for i, (f0, rise, dur) in enumerate(((760, 1.35, 0.15), (900, 1.25, 0.12), (640, 1.5, 0.2), (1050, 1.2, 0.1), (820, 0.8, 0.16), (700, 1.6, 0.22)), 1):
        export(f"slime_squeak_{i}", squeak(f0, rise, dur), -10)
    for i, f0 in enumerate((300, 360, 420), 1):
        export(f"slime_boing_{i}", boing(f0), -11)
    for i, f0 in enumerate((330, 400), 1):
        export(f"slime_nom_{i}", nom(f0), -10)
    export("coin_1", chime([1568.0, 2093.0]), -4)
    export("coin_2", chime([1760.0, 2349.3]), -4)
    export("coin_3", chime([1396.9, 1864.7, 2793.8], gap=0.05), -4)
    export("slot_unlock", sparkle_arp(), -3)
    export("ui_click", click(), -6)
    export("wall_rise", wall_rise(), -3)
    export("alarm", alarm(), -5)
    export("denied", denied(), -6)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        OUT = sys.argv[1]
    main()
