#!/usr/bin/env python3
"""Regenerate the placeholder SFX in assets/audio/sfx (CC0, synthesised). Requires numpy."""
import numpy as np, wave, pathlib
SR = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets/audio/sfx"

def tone(freq, dur, decay=6.0, harmonics=(1, 0.5, 0.25), amp=0.5, attack=0.005):
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    s = sum(h * np.sin(2 * np.pi * freq * (i + 1) * t) for i, h in enumerate(harmonics))
    return amp * s * np.exp(-decay * t) * np.minimum(1, t / attack)

def seq(notes, gap, dur, **kw):
    out = np.zeros(int(SR * (gap * (len(notes) - 1) + dur)) + 1)
    for i, f in enumerate(notes):
        s = tone(f, dur, **kw); st = int(SR * gap * i); out[st:st + len(s)] += s
    return out

def write(name, sig):
    sig = np.clip(sig / max(1e-6, np.max(np.abs(sig))) * 0.8, -1, 1)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((sig * 32767).astype(np.int16).tobytes())

OUT.mkdir(parents=True, exist_ok=True)
write("place_correct", seq([659.25, 987.77], 0.07, 0.5, decay=7, harmonics=(1, 0.6, 0.3, 0.1)))
t = np.linspace(0, 0.35, int(SR * 0.35), endpoint=False)
write("place_wrong", 0.6 * np.sin(2 * np.pi * (110 * np.exp(-6 * t)) * t) * np.exp(-10 * t)
      + 0.15 * np.random.default_rng(1).normal(size=len(t)) * np.exp(-25 * t))
write("container_complete", seq([523.25, 659.25, 783.99, 1046.5], 0.11, 0.7, decay=4, harmonics=(1, 0.5, 0.25, 0.12)))
write("island_clean", seq([523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98], 0.16, 1.6, decay=2.2, harmonics=(1, 0.5, 0.3, 0.15)))
print("wrote 4 files to", OUT)
