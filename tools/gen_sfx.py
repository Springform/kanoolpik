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

# --- Snore (WP-2.7) ------------------------------------------------------------
# A seamless loop, for the mate who never made it into his tent. Built the same
# way as the ambience beds: every component completes a whole number of cycles
# over DURATION, so the end of the buffer is the same point on the same
# continuous waveform as the start. See tools/gen_ambience.py for why that is a
# guarantee rather than luck — and tests/integration/test_dressing.gd checks the
# seam rather than trusting anyone's ears.
SNORE_DURATION = 6.0  # one slow breath in, one out, twice
SNORE_N = int(SR * SNORE_DURATION)


def periodic_noise(rng, low_hz, high_hz, slope=-1.0):
    freqs = np.fft.rfftfreq(SNORE_N, 1.0 / SR)
    mag = np.zeros_like(freqs)
    band = (freqs >= low_hz) & (freqs <= high_hz)
    with np.errstate(divide="ignore"):
        mag[band] = np.where(freqs[band] > 0, freqs[band] ** slope, 0.0)
    phase = rng.uniform(0, 2 * np.pi, size=freqs.shape)
    sig = np.fft.irfft(mag * np.exp(1j * phase), n=SNORE_N)
    return sig / (np.max(np.abs(sig)) + 1e-9)


def snore():
    rng = np.random.default_rng(7)
    t = np.linspace(0, SNORE_DURATION, SNORE_N, endpoint=False)
    breaths = 2  # whole cycles over the loop, so the seam lands mid-silence
    phase = 2 * np.pi * breaths * t / SNORE_DURATION
    # In: long, loud, rattling. Out: shorter, softer, further down.
    inhale = np.clip(np.sin(phase), 0, None) ** 2.2
    exhale = np.clip(-np.sin(phase), 0, None) ** 3.0
    rattle = 0.5 + 0.5 * np.sin(2 * np.pi * 34 * breaths * t / SNORE_DURATION)
    body = periodic_noise(rng, 90, 1400, slope=-1.4)
    sig = body * (inhale * (0.55 + 0.45 * rattle) + 0.35 * exhale)
    # A little chest tone under the inhale so it reads as a person, not wind.
    sig += 0.25 * inhale * np.sin(2 * np.pi * 15 * breaths * t / SNORE_DURATION)
    return sig


write("snore", snore())

# --- Shout for a mate (WP-3.4) -------------------------------------------------
# "Råb på en kammerat": a hungover man yelling across a Swedish lake at 09:00,
# not a magic chime. So: a real voice model rather than a bell — a glottal pulse
# train with a shouted pitch contour (up fast, then sagging because he has no
# air left), pushed through gliding formants so the vowel opens from "haaa" to
# "loo", plus the breath and rasp that make it a person. A slap-back off the far
# shore puts him outdoors.
#
# One-shot, deliberately: it plays once per shout and never loops, so there is
# no seam to check (contrast the snore above, which is periodic on purpose).
SHOUT_DURATION = 0.95
SHOUT_N = int(SR * SHOUT_DURATION)


def resonator(sig, freqs, bw, gain=1.0):
    """One gliding two-pole formant. freqs is per-sample centre frequency in Hz."""
    r = np.exp(-np.pi * bw / SR)
    out = np.zeros(len(sig))
    y1 = y2 = 0.0
    two_pi_sr = 2 * np.pi / SR
    cosw = np.cos(two_pi_sr * freqs)
    a1 = 2.0 * r * cosw
    a2 = -(r * r)
    norm = (1.0 - r * r) * gain
    for i in range(len(sig)):
        y = norm * sig[i] + a1[i] * y1 + a2 * y2
        y2, y1 = y1, y
        out[i] = y
    return out


def glide(a, b, t, curve=1.0):
    """a -> b over the clip, following t (already 0..1), eased by curve."""
    return a + (b - a) * (t ** curve)


def shout():
    rng = np.random.default_rng(31)
    t = np.linspace(0, SHOUT_DURATION, SHOUT_N, endpoint=False)
    u = t / SHOUT_DURATION  # 0..1 through the shout

    # Pitch: a shove up to the top of his range, then a tired sag. Jitter and a
    # slow drift keep it off a synthesiser's perfect pitch.
    f0 = np.where(u < 0.12, 118 + 620 * u, 202 - 88 * (u - 0.12) / 0.88)
    f0 *= 1.0 + 0.012 * np.sin(2 * np.pi * 5.5 * t) + 0.02 * rng.normal(size=SHOUT_N).cumsum() / SHOUT_N**0.5

    # Glottal source: a pulse train, bright at the start (he is pushing) and
    # duller as he runs out, which is what tiredness sounds like.
    phase = 2 * np.pi * np.cumsum(f0) / SR
    openness = glide(0.86, 0.45, u)
    source = np.sin(phase) + openness * np.sin(2 * phase) + 0.55 * openness * np.sin(3 * phase) \
        + 0.3 * openness * np.sin(4 * phase)
    # Rasp: a hungover voice does not phonate cleanly.
    source *= 1.0 - 0.22 * np.abs(np.sin(2 * np.pi * 23 * t))
    source += 0.09 * rng.normal(size=SHOUT_N) * glide(1.0, 0.35, u)

    # Vowel: /a/ ("haaa") opening into /o/ ("looo") in the last third.
    v = np.clip((u - 0.45) / 0.45, 0, 1)
    body = resonator(source, glide(720, 430, v), 95, 1.0)
    body += resonator(source, glide(1180, 830, v), 120, 0.62)
    body += resonator(source, glide(2500, 2620, v), 190, 0.26)
    body += resonator(source, glide(3300, 3150, v), 260, 0.11)

    # Two syllables: "Hal-LOO" — a short push, a dip, then the long one he
    # leans on, dying away because there is nothing left in him.
    env = np.minimum(1.0, u / 0.02) * np.exp(-1.1 * u)
    env *= 0.75 + 0.25 * np.tanh(6 * np.sin(np.pi * np.clip(u / 0.3, 0, 1)))
    dip = 1.0 - 0.45 * np.exp(-((u - 0.33) / 0.05) ** 2)
    sig = body * env * dip

    # The far shore answers about 120 ms later, quieter and duller.
    echo = np.zeros(SHOUT_N)
    delay = int(0.12 * SR)
    echo[delay:] = sig[: SHOUT_N - delay] * 0.22
    k = 64  # crude low-pass: the lake eats the top end
    echo = np.convolve(echo, np.ones(k) / k, mode="same")
    # Fade the MIX out, not just the voice: the echo is the voice delayed, so
    # trimming only `sig` leaves the echo cut off mid-cycle — a click on the
    # last sample of every shout. Test asserts the file ends near silence.
    release = np.minimum(1.0, (1.0 - u) / 0.08)
    return (sig + echo) * release


write("shout_mate", shout())
print("wrote 6 files to", OUT)
