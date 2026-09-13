#!/usr/bin/env python3
"""Regenerate the music stems in assets/audio/music (CC0, synthesised).

Three stems, all the same length (DURATION), so they stay phase-locked when
Soundscape plays and loops them together, crossfading their volume as
completion rises (see src/game/audio/music_mix.gd):

  stem_pad      a sustained open chord, present (quietly) from the very start.
  stem_melody   a few unhurried notes that join once things stop looking hopeless.
  stem_shimmer  a little high bell sparkle for the last few containers.

Pad frequencies are snapped to complete a whole number of cycles over
DURATION, so the pad loops with zero phase discontinuity. Melody/shimmer are
short decaying notes placed with margin from both ends of the loop, so they
are silent at the seam regardless. Requires numpy. Follows the style of
tools/gen_sfx.py.
"""
import numpy as np, wave, pathlib

SR = 44100
DURATION = 12.0
N = int(SR * DURATION)
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets/audio/music"


def snap(freq: float) -> float:
    """Nearest frequency that completes a whole number of cycles over DURATION
    (so a sustained tone at this frequency loops with no phase jump)."""
    return round(freq * DURATION) / DURATION


def pad_tone(freqs, harmonics=(1.0, 0.35, 0.12), swell_cycles=1, swell_depth=0.3) -> np.ndarray:
    t = np.linspace(0, DURATION, N, endpoint=False)
    sig = np.zeros(N)
    for f in freqs:
        f = snap(f)
        for i, h in enumerate(harmonics):
            sig += h * np.sin(2 * np.pi * f * (i + 1) * t)
    swell = 1.0 - swell_depth + swell_depth * np.sin(2 * np.pi * swell_cycles * t / DURATION)
    return sig * swell / len(freqs)


def note(t0: float, freq: float, dur: float, decay: float, harmonics, amp: float, attack: float = 0.01) -> np.ndarray:
    n = int(SR * dur)
    t = np.linspace(0, dur, n, endpoint=False)
    s = sum(h * np.sin(2 * np.pi * freq * (i + 1) * t) for i, h in enumerate(harmonics))
    s *= amp * np.exp(-decay * t) * np.minimum(1, t / attack)
    out = np.zeros(N)
    start = int(SR * t0)
    end = min(N, start + n)
    out[start:end] += s[: end - start]
    return out


def write(name: str, sig: np.ndarray, peak: float) -> None:
    sig = np.clip(sig / (np.max(np.abs(sig)) + 1e-9) * peak, -1, 1)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((sig * 32767).astype(np.int16).tobytes())


def main() -> None:
    # Open, spare chord: root - fifth - ninth, no third. Calm and a little ambiguous.
    pad = pad_tone([130.81, 196.00, 293.66])
    write("stem_pad", pad, peak=0.45)

    rng = np.random.default_rng(7)
    scale = [293.66, 349.23, 392.00, 440.00, 523.25]  # D minor pentatonic: D4 F4 G4 A4 C5
    melody = np.zeros(N)
    t0 = 1.5
    while t0 <= DURATION - 1.9:
        f = float(rng.choice(scale))
        melody += note(t0, f, 1.6, decay=3.2, harmonics=(1, 0.5, 0.25), amp=0.4)
        t0 += rng.uniform(1.3, 2.4)
    write("stem_melody", melody, peak=0.4)

    bells = [1046.5, 1318.5, 1567.98, 2093.0]  # C6 E6 G6 C7
    shimmer = np.zeros(N)
    t0 = 2.0
    while t0 <= DURATION - 1.5:
        f = float(rng.choice(bells))
        shimmer += note(t0, f, 1.1, decay=4.2, harmonics=(1, 0.6, 0.3, 0.1), amp=0.3, attack=0.005)
        t0 += rng.uniform(1.8, 3.0)
    write("stem_shimmer", shimmer, peak=0.35)

    print("wrote 3 stems to", OUT)


if __name__ == "__main__":
    main()
