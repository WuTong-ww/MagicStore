"""Read nonfragmented MP4 video sample counts and timing without a decoder.

Python standard library only. This measures actual container tables, accepts no
expected frame count, and does not certify H264 decoding or visual playback.
Field references:
https://developer.apple.com/documentation/quicktime-file-format/time-to-sample_atom
https://developer.apple.com/documentation/quicktime-file-format/sample_size_atom
"""
import argparse
import hashlib
import json
from fractions import Fraction
from pathlib import Path
import struct


def _boxes(data, start, end):
    while start < end:
        if end - start < 8:
            raise ValueError("truncated box header")
        size, kind = struct.unpack_from(">I4s", data, start)
        header = 8
        if size == 1:
            if end - start < 16:
                raise ValueError("truncated large-size box header")
            size = struct.unpack_from(">Q", data, start + 8)[0]
            header = 16
        elif size == 0:
            size = end - start
        if size < header or start + size > end:
            raise ValueError("invalid box bounds")
        yield {"kind": kind.decode("ascii", errors="replace"), "offset": start,
               "payload": start + header, "end": start + size, "bytes": size}
        start += size


def _one(data, parent, kind):
    found = [box for box in _boxes(data, parent["payload"], parent["end"])
             if box["kind"] == kind]
    if len(found) != 1:
        raise ValueError("expected exactly one " + kind + " box")
    return found[0]


def _need(box, length):
    if box["end"] - box["payload"] < length:
        raise ValueError("truncated " + box["kind"] + " payload")


def _u32(data, position):
    return struct.unpack_from(">I", data, position)[0]


def _track(data, trak):
    mdia = _one(data, trak, "mdia")
    handler = _one(data, mdia, "hdlr")
    _need(handler, 12)
    p = handler["payload"]
    handler_kind = data[p + 8:p + 12].decode("ascii", errors="replace")
    mdhd = _one(data, mdia, "mdhd")
    _need(mdhd, 4)
    p = mdhd["payload"]
    version = data[p]
    if version == 0:
        _need(mdhd, 20)
        timescale, media_duration = struct.unpack_from(">II", data, p + 12)
    elif version == 1:
        _need(mdhd, 32)
        timescale = _u32(data, p + 20)
        media_duration = struct.unpack_from(">Q", data, p + 24)[0]
    else:
        raise ValueError("unsupported media header version")
    if not timescale:
        raise ValueError("zero media timescale")

    stbl = _one(data, _one(data, mdia, "minf"), "stbl")
    stsz = _one(data, stbl, "stsz")
    _need(stsz, 12)
    p = stsz["payload"]
    if data[p] != 0:
        raise ValueError("unsupported sample size table version")
    sample_size, sample_count = struct.unpack_from(">II", data, p + 4)
    if stsz["end"] - p != 12 + (0 if sample_size else sample_count * 4):
        raise ValueError("sample size table length mismatch")
    total_sample_bytes = sample_size * sample_count if sample_size else sum(
        value[0] for value in struct.iter_unpack(">I", data[p + 12:stsz["end"]]))

    stts = _one(data, stbl, "stts")
    _need(stts, 8)
    p = stts["payload"]
    if data[p] != 0:
        raise ValueError("unsupported time-to-sample table version")
    entry_count = _u32(data, p + 4)
    if stts["end"] - p != 8 + entry_count * 8:
        raise ValueError("time-to-sample table length mismatch")
    timing = [{"sample_count": count, "sample_delta": delta}
              for count, delta in struct.iter_unpack(">II", data[p + 8:stts["end"]])]
    timing_count = sum(entry["sample_count"] for entry in timing)
    duration_ticks = sum(entry["sample_count"] * entry["sample_delta"] for entry in timing)
    if timing_count != sample_count:
        raise ValueError("independent sample size/timing counts disagree")
    if not sample_count or not duration_ticks:
        raise ValueError("empty samples or zero total sample duration")
    seconds = Fraction(duration_ticks, timescale)
    return {"handler": handler_kind, "track_offset": trak["offset"],
            "mdhd_version": version, "media_timescale": timescale,
            "media_header_duration_ticks": media_duration,
            "media_header_duration_seconds": media_duration / timescale,
            "stsz_sample_count": sample_count, "sample_size": sample_size,
            "total_sample_bytes": total_sample_bytes,
            "stts_entry_count": entry_count, "stts_entries": timing,
            "stts_sample_count": timing_count, "stts_duration_ticks": duration_ticks,
            "stts_duration_seconds": float(seconds), "stts_duration_fraction": str(seconds),
            "sample_rate": float(Fraction(sample_count, 1) / seconds)}


def parse_bytes(data):
    top = list(_boxes(data, 0, len(data)))
    if any(box["kind"] == "moof" for box in top):
        raise ValueError("fragmented MP4 needs fragment sample-table support")
    moov = [box for box in top if box["kind"] == "moov"]
    if len(moov) != 1:
        raise ValueError("expected exactly one moov box")
    movie_children = list(_boxes(data, moov[0]["payload"], moov[0]["end"]))
    if any(box["kind"] == "mvex" for box in movie_children):
        raise ValueError("fragmented MP4 movie extensions are unsupported")
    tracks = [_track(data, box) for box in movie_children if box["kind"] == "trak"]
    video = [track for track in tracks if track["handler"] == "vide"]
    if not video:
        raise ValueError("no video track with an actual sample table")
    return {"top_level_boxes": [{key: box[key] for key in ("kind", "offset", "bytes")}
                                for box in top],
            "tracks": tracks, "video_tracks": video,
            "measurement": "Actual stsz and stts tables under hdlr=vide; no expected frame count input.",
            "full_decode_performed": False,
            "limitation": "Container sample count and decode timeline only; no H264 decoding or visual/playback acceptance; edit-list presentation mapping not evaluated."}


def probe(path):
    path = Path(path).resolve()
    data = path.read_bytes()
    result = parse_bytes(data)
    return {"path": str(path), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), **result}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="existing nonfragmented MP4 to read")
    parser.add_argument("--output", type=Path, help="new JSON evidence path, separate from input")
    args = parser.parse_args()
    if args.output and args.output.resolve() == args.input.resolve():
        parser.error("output must not overwrite the source media")
    try:
        result = probe(args.input)
        text = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(text, encoding="utf-8")
        print(text, end="")
    except (OSError, ValueError, struct.error) as error:
        parser.exit(2, "MP4 container probe failed: " + str(error) + "\n")


if __name__ == "__main__":
    main()
