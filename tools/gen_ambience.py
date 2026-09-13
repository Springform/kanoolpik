#!/usr/bin/env python3
"""Regenerate the ambience loop in assets/audio/ambience (CC0, synthesised).

Water and wind are built directly in the frequency domain as band-limited
noise made only of bins that are whole multiples of 1/DURATION. An inverse
FFT of a signal built that way is *exactly* periodic over N samples: sample 0
is the same point on the same continuous waveform as "sample N", so looping
it back to the start is not a click hidden by luck, it is mathematically the
same signal continuing. tests/integration/test_soundscape.gd checks the seam
programmatically instead of trusting anyone's ears (per WP-2.6).

Bird chirps are windowed to exactly zero well before the loop boundary, so
they never touch the seam either. Requires numpy. Follows the style of
tools/gen_sfx.py.
"""
import numpy as np, wave, pathlib

SR = 44100
DURATION = 18.0  # seconds; GameSession loops this forever once a level is up
N = int(SR * DURATION)
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets/audio/ambience"


def periodic_noise(rng: np.random.Generator, low_hz: float, high_hz: float, slope: float = -1.0) -> np.ndarray:
    """Band-limited noise that tiles seamlessly (see module docstring)."""
    freqs = np.fft.rfftfreq(N, 1.0 / SR)
    mag = np.zeros_like(freqs)
    band = (freqs >= low_hz) & (freqs <= high_hz)
    with np.errstate(divide="ignore"):
        mag[band] = np.where(freqs[band] > 0, freqs[band] ** slope, 0.0)
    phase = rng.uniform(0, 2 * np.pi, size=freqs.shape)
    sig = np.fft.irfft(mag * np.exp(1j * phase), n=N)
    return sig / (np.max(np.abs(sig)) + 1e-9)


def periodic_lfo(cycles: float, phase: float = 0.0) -> np.ndarray:
    """A slow 0..1 envelope with a whole number of cycles over DURATION —
    also exactly periodic, so multiplying it in keeps the seam intact."""
    t = np.linspace(0, DURATION, N, endpoint=False)
    return 0.5 + 0.5 * np.sin(2 * np.pi * cycles * t / DURATION + phase)


def chirp(t0: float, dur: float, f0: float, f1: float):
    """A short upward bird-chirp, windowed to zero at both ends so it never
    creates a discontinuity wherever it lands."""
    n = int(SR * dur)
    tt = np.linspace(0, dur, n, endpoint=False)
    freq = np.linspace(f0, f1, n)
    window = np.sin(np.pi * tt / dur) ** 2  # exactly 0 at t=0 and t=dur
    sig = window * np.sin(2 * np.pi * np.cumsum(freq) / SR)
    return int(SR * t0), sig


def write(name: str, sig: np.ndarray) -> None:
    sig = np.clip(sig / (np.max(np.abs(sig)) + 1e-9) * 0.55, -1, 1)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((sig * 32767).astype(np.int16).tobytes())


def main() -> None:
    rng = np.random.default_rng(2026)
    water = periodic_noise(rng, 250, 4500, slope=-0.8) * (0.55 + 0.45 * periodic_lfo(6))
    wind = periodic_noise(rng, 30, 500, slope=-1.4) * (0.5 + 0.5 * periodic_lfo(3, phase=1.7))
    mix = 0.55 * water + 0.30 * wind
    # A handful of bird chirps, kept well clear of both ends of the loop.
    for t0, dur, f0, f1 in [
        (2.3, 0.18, 2400, 3400), (2.55, 0.12, 3200, 2600),
        (7.1, 0.22, 1900, 3000),
        (11.6, 0.15, 2600, 3600), (11.85, 0.15, 3000, 2200),
        (15.0, 0.20, 2100, 3200),
    ]:
        start, sig = chirp(t0, dur, f0, f1)
        mix[start:start + len(sig)] += 0.18 * sig
    write("lake_morning", mix)
    print("wrote lake_morning.wav to", OUT)


if __name__ == "__main__":
    main()
