#!/usr/bin/env python3
"""Builds the scene sound loops in app/assets/sounds/.

Sources (licences in app/assets/sounds/CREDITS.md):
  - Field recordings from the Blanket project's sound set
    (github.com/rafaelmardojai/blanket, data/resources/sounds). Each file
    there is public domain, CC0 or CC BY according to the project's
    SOUNDS_LICENSING.md, and already loops seamlessly.
  - Brown "focus" noise for the plain paper theme, generated here (ours).

Every file is decoded, levelled to the same loudness (so the per-scene mix
volumes in lib/services/scene_sound.dart mean the same thing), and encoded as
Ogg Vorbis, which keeps the exact sample count so loops stay seamless.

Usage: python3 tool/build_scene_sounds.py [--src DIR]   (needs ffmpeg and numpy)
"""

import argparse
import os
import subprocess
import tempfile
import urllib.request

import numpy as np

RATE = 44100
BLANKET = "https://raw.githubusercontent.com/rafaelmardojai/blanket/master/data/resources/sounds/"

# asset name -> Blanket file
RECORDINGS = {
    "rain": "rain.ogg",
    "wind": "wind.ogg",
    "waves": "waves.ogg",
    "birds": "birds.ogg",
    "crickets": "summer-night.ogg",
    "city": "city.ogg",
    "cafe": "coffee-shop.ogg",
    "fireplace": "fireplace.ogg",
}

TARGET_RMS_DB = -24.0  # every loop at the same loudness
PEAK_DB = -1.5  # never louder than this

# Recordings that do not loop cleanly as published (silence at the start, or
# a click at the seam): trimmed and made into crossfaded loops here.
# name -> crossfade seconds
CROSSFADE = {"cafe": 1.5, "wind": 1.5, "crickets": 2.5, "fireplace": 2.0}

# Sounds with sharp transients (crackles) are softly limited so they can sit
# at the same loudness as the rest.
SOFT_CLIP = {"fireplace"}


def decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(RATE), "-"],
        check=True,
        capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)


def trim_silence(x, floor_db=-55.0, window=441):
    """Drops near-silent lead-in and tail (10 ms windows below floor_db)."""
    frames = len(x) // window
    rms = np.sqrt(np.mean(x[: frames * window].reshape(frames, window, 2) ** 2, axis=(1, 2)))
    loud = np.nonzero(rms > 10 ** (floor_db / 20))[0]
    if len(loud) == 0:
        return x
    return x[loud[0] * window : (loud[-1] + 1) * window]


def crossfade_loop(x, seconds):
    """Makes x loop without a seam: its last part fades into its first part
    (equal-power), and the loop restarts just after the faded-in section."""
    f = int(seconds * RATE)
    n = len(x)
    t = np.linspace(0, np.pi / 2, f)[:, None]
    blend = x[n - f :] * np.cos(t) + x[:f] * np.sin(t)
    return np.concatenate([x[f : n - f], blend])


def level(x, soft_clip=False):
    rms = np.sqrt(np.mean(x**2))
    gain = 10 ** (TARGET_RMS_DB / 20) / max(rms, 1e-9)
    limit = 10 ** (PEAK_DB / 20)
    if soft_clip:
        # Round off the crackle peaks, lowering the knee until the loop
        # reaches the target loudness without going over the peak limit.
        target = 10 ** (TARGET_RMS_DB / 20)
        knee = limit
        for _ in range(40):
            y = knee * np.tanh(x * gain / knee)
            y *= target / np.sqrt(np.mean(y**2))
            if np.max(np.abs(y)) <= limit:
                return y
            knee *= 0.9
        return y * (limit / np.max(np.abs(y)))
    peak = np.max(np.abs(x)) * gain
    if peak > limit:
        gain *= limit / peak  # keep drops and gusts from clipping
    return x * gain


def encode(x, out_path, quality=2):
    with tempfile.NamedTemporaryFile(suffix=".f32") as tmp:
        tmp.write(x.astype(np.float32).tobytes())
        tmp.flush()
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", "2", "-ar", str(RATE), "-i", tmp.name,
             "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", out_path],
            check=True,
        )


def brown_noise(seconds=40, seed=7):
    """Warm brown noise built in the frequency domain, so the loop is perfectly
    seamless (an inverse FFT is periodic). Rolled off below 30 Hz (no rumble)
    and above ~2.5 kHz (no hiss)."""
    n = seconds * RATE
    rng = np.random.default_rng(seed)
    f = np.fft.rfftfreq(n, 1 / RATE)
    shape = np.zeros_like(f)
    nz = f > 0
    shape[nz] = 1 / f[nz]  # brown: power ~ 1/f^2
    shape *= 1 / (1 + (30 / np.maximum(f, 1e-9)) ** 4)  # high-pass
    shape *= 1 / (1 + (f / 2500) ** 2)  # gentle low-pass
    chans = []
    for _ in range(2):
        spectrum = shape * np.exp(2j * np.pi * rng.random(len(f)))
        chans.append(np.fft.irfft(spectrum, n))
    left, right = chans
    # A little shared signal so it sounds wide but not split in two.
    mid = (left + right) / 2
    stereo = np.stack([0.7 * left + 0.3 * mid, 0.7 * right + 0.3 * mid], axis=1)
    return stereo / np.max(np.abs(stereo))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", help="folder with the Blanket .ogg files (downloaded when absent)")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "assets", "sounds"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for name, file in RECORDINGS.items():
            src = os.path.join(args.src, file) if args.src else os.path.join(tmp, file)
            if not args.src:
                urllib.request.urlretrieve(BLANKET + file, src)
            x = decode(src)
            if name in CROSSFADE:
                x = crossfade_loop(trim_silence(x), CROSSFADE[name])
            x = level(x, soft_clip=name in SOFT_CLIP)
            out = os.path.join(args.out, f"{name}.ogg")
            encode(x, out)
            print(f"{name:10s} {len(x) / RATE:6.1f} s  {os.path.getsize(out) / 1024:6.0f} KB")
    x = level(brown_noise())
    out = os.path.join(args.out, "brown-noise.ogg")
    encode(x, out)
    print(f"{'brown-noise':10s} {len(x) / RATE:6.1f} s  {os.path.getsize(out) / 1024:6.0f} KB")


if __name__ == "__main__":
    main()
