"""Read-only, reproducible measurements for short UI sounds.

Requires numpy, scipy, soundfile and pyloudnorm. Short effects use a declared
40 ms K-weighted gated loudness window; this is not a 400 ms broadcast R128
programme measurement. Tonality is a sustained narrow-band energy heuristic,
not a claim that objective metrics replace a human listening session.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
import soundfile as sf
from scipy import signal


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_audio(path: Path) -> tuple[np.ndarray, int]:
    samples, rate = sf.read(path, dtype="float64", always_2d=True)
    if not len(samples) or not np.isfinite(samples).all():
        raise ValueError(f"Empty or nonfinite audio: {path.name}")
    return samples.mean(axis=1), rate


def measure(samples: np.ndarray, rate: int) -> dict:
    samples = np.asarray(samples, dtype=np.float64)
    duration = len(samples) / rate
    peak = float(np.max(np.abs(samples))) if len(samples) else 0.0
    spectrum = np.abs(np.fft.rfft(samples * np.hanning(len(samples)))) ** 2
    frequencies = np.fft.rfftfreq(len(samples), 1 / rate)
    centroid = float(np.sum(spectrum * frequencies) / max(float(spectrum.sum()), 1e-30))
    onset = float(np.max(np.abs(samples[:max(1, round(rate * .005))])))
    nperseg = min(1024, len(samples))
    _, _, stft = signal.stft(samples, rate, nperseg=nperseg,
                            noverlap=nperseg // 2, boundary=None, padded=False)
    powers = np.abs(stft) ** 2
    frame_energy = powers.sum(axis=0)
    active = frame_energy > max(float(frame_energy.max(initial=0)) * .01, 1e-20)
    shares = np.zeros_like(frame_energy)
    if active.any():
        # Include a tone's adjacent bins, avoiding FFT-bin alignment artefacts.
        bands = powers[:-2] + powers[1:-1] + powers[2:]
        shares[active] = bands[:, active].max(axis=0) / frame_energy[active]
    tonal_fraction = float(np.mean(shares[active] > .82)) if active.any() else 0.0
    loudness = float(pyln.Meter(rate, block_size=.04).integrated_loudness(samples)) if duration >= .04 and peak else -120.0
    result = {
        "duration_ms": round(duration * 1000, 3),
        "centroid_hz": round(centroid, 3),
        "onset_peak_ratio": round(onset / peak if peak else 1, 6),
        "tonal_frame_fraction": round(tonal_fraction, 6),
        "lufs_short_40ms": round(loudness, 3),
        "peak_dbfs": round(20 * np.log10(max(peak, 1e-12)), 3),
    }
    result["passes"] = bool(60 <= result["duration_ms"] <= 350
                            and centroid < 2500 and onset <= peak * .8
                            and tonal_fraction < .6 and peak > 0)
    return result


def analyze(path: Path) -> dict:
    samples, rate = read_audio(path)
    return {"path": path.as_posix(), "sample_rate": rate,
            "sha256": sha256(path), **measure(samples, rate)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--csv", type=Path)
    args = parser.parse_args()
    paths = set()
    for path in args.paths:
        paths.update(p for p in path.rglob("*") if p.suffix.lower() in {".ogg", ".wav", ".flac"}) if path.is_dir() else paths.add(path)
    rows = [analyze(path) for path in sorted(paths) if path.name.lower() != "preview.ogg"]
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps({"version": 1, "loudness_window_ms": 40,
                                        "sounds": rows}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.csv and rows:
        args.csv.parent.mkdir(parents=True, exist_ok=True)
        with args.csv.open("w", newline="", encoding="utf-8-sig") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    print(json.dumps({"analyzed": len(rows), "passed": sum(row["passes"] for row in rows)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
