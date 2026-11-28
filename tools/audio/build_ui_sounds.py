"""Build the R4 UI selection from original, hash-checked Kenney archives.

No download is performed. Keep --sources outside Git. Requires the packages
listed in requirements.txt and FFmpeg supplied by imageio-ffmpeg.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

import imageio_ffmpeg
import numpy as np
import pyloudnorm as pyln
import soundfile as sf
from scipy import signal

from analyze_ui_sounds import analyze, measure, read_audio, sha256

ROOT = Path(__file__).resolve().parents[2]


def process(samples, rate, selection, choice):
    if rate != selection["sample_rate"]:
        from math import gcd
        divisor = gcd(rate, selection["sample_rate"])
        samples = signal.resample_poly(samples, selection["sample_rate"] // divisor, rate // divisor)
        rate = selection["sample_rate"]
    samples = samples[:round(rate * selection["maximum_seconds"])].copy()
    if len(samples) < round(rate * .06):
        raise ValueError("Source is too short for the requested duration; choose another source.")
    samples = signal.sosfiltfilt(signal.butter(4, selection["lowpass_hz"], fs=rate, output="sos"), samples)
    # Metallic coin sources need additional declared softening. This preserves
    # the real coin recording; it does not substitute a synthesized beep.
    if choice.get("soft_lowpass_hz"):
        samples = signal.sosfiltfilt(signal.butter(2, choice["soft_lowpass_hz"], fs=rate, output="sos"), samples)
    fade = round(rate * selection["fade_seconds"])
    samples[:fade] *= np.linspace(0, 1, fade)
    samples[-fade:] *= np.linspace(1, 0, fade)
    meter = pyln.Meter(rate, block_size=selection["loudness_window_seconds"])
    loudness = meter.integrated_loudness(samples)
    samples *= 10 ** ((selection["target_lufs_short"] - loudness) / 20)
    if np.max(np.abs(samples)) >= .97:
        raise ValueError("Loudness normalization would clip; select a lower-crest source.")
    return samples, rate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, required=True)
    args = parser.parse_args()
    plan = json.loads(Path(__file__).with_name("r4_selection.json").read_text(encoding="utf-8"))
    for pack in plan["packs"].values():
        archive = args.sources / (pack["directory"] + ".zip")
        if sha256(archive) != pack["archive_sha256"]:
            raise ValueError(f"Source archive hash mismatch: {archive.name}")
        license_path = args.sources / pack["directory"] / "License.txt"
        if "Creative Commons Zero" not in license_path.read_text(encoding="utf-8-sig"):
            raise ValueError("Kenney archive license marker missing")

    destination = ROOT / "assets/audio/ui/r4"
    destination.mkdir(parents=True, exist_ok=True)
    config_path = ROOT / "data/ui/audio.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    config["defaults"]["ui"] = .45
    config["alternatives"] = {}
    config["sound_catalog"] = {}
    config["ui_policy"] = {
        "version": 1, "pitch_min": .96, "pitch_max": 1.04,
        "gain_db": {"cancel": -3, "notify": -2},
        "loudness_window_ms": 40, "loudness_target": -20,
        "measurement_note": "短音效采用40毫秒K加权门限窗口；不是广播节目400毫秒R128测量。",
        "centroid_method": "power_weighted_fft", "human_listened": False,
        "preview_title": "纸与木的声音 · 第四轮试听",
        "preview_notice": "正式播放音高随机±4%；此页固定音高比较。数值筛选不代替真人试听。",
        "preview_columns": ["用途", "主选", "候选一", "候选二"],
        "preview_metrics": "时长 {duration}ms · 重心 {centroid}Hz · 起音 {onset} · 响度 {loudness} LUFS（短窗）",
        "labels": {key: row["label"] for key, row in plan["selection"].items()},
    }
    encoded = {}
    for key, row in plan["selection"].items():
        candidates = []
        for index, (pack_id, filename, label) in enumerate(row["choices"]):
            pack = plan["packs"][pack_id]
            matches = list((args.sources / pack["directory"]).rglob(filename))
            if len(matches) != 1:
                raise ValueError(f"Expected one original source: {filename}")
            source = matches[0]
            output = destination / (key + ("" if index == 0 else f"_alt{index}") + ".ogg")
            identity = (sha256(source), row.get("soft_lowpass_hz", 0))
            samples, rate = process(*read_audio(source), plan, row)
            if identity not in encoded:
                with tempfile.TemporaryDirectory(prefix="r4-ui-") as temp:
                    wav = Path(temp) / "source.wav"
                    ogg = Path(temp) / "processed.ogg"
                    sf.write(wav, samples, rate, subtype="PCM_24")
                    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
                                    "-i", str(wav), "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", str(plan["vorbis_quality"]), str(ogg)], check=True)
                    encoded[identity] = ogg.read_bytes()
            output.write_bytes(encoded[identity])
            measured = analyze(output)
            if not measured["passes"] or abs(measured["lufs_short_40ms"] - plan["target_lufs_short"]) > 1:
                raise ValueError(f"Encoded candidate failed selection criteria: {output.name}: {measured}")
            path = "res://" + output.relative_to(ROOT).as_posix()
            candidates.append(path)
            config["sound_catalog"][path] = {
                "label": label, "key": key, "candidate": index,
                "author": pack["author"], "license": "CC0-1.0", "source_url": pack["page"],
                "source_file": filename, "source_archive_sha256": pack["archive_sha256"],
                "source_sha256": sha256(source), "sha256": measured.pop("sha256"),
                "metrics": {k: v for k, v in measured.items() if k != "path"},
                "processing": {"lowpass_hz": plan["lowpass_hz"], "soft_lowpass_hz": row.get("soft_lowpass_hz", 0),
                               "fade_ms": 5, "maximum_ms": 330, "mono_rate": rate, "vorbis_quality": plan["vorbis_quality"]},
            }
        config["sounds"][key] = candidates[0]
        config["alternatives"][key] = candidates[1:]
    # TITLE verifies this existing resource path before emitting its cue.
    # Its independent entry bell is outside the eleven replacement purposes.
    config["sounds"]["entry_chime"] = plan["retained_entry_chime"]
    for pack_id, pack in plan["packs"].items():
        (destination / ("LICENSE-" + pack_id + ".md")).write_text((args.sources / pack["directory"] / "License.txt").read_text(encoding="utf-8-sig"), encoding="utf-8", newline="\n")
    config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"keys": len(plan["selection"]), "candidates": len(config["sound_catalog"]),
                      "bytes": sum(path.stat().st_size for path in destination.glob("*.ogg"))}))


if __name__ == "__main__":
    main()
