"""Hand-built sample tables catch wrong track choice, timing and unsafe bounds."""
import importlib.util
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def atom(kind, payload=b"", *, large=False, to_end=False):
    if large:
        return struct.pack(">I4sQ", 1, kind, 16 + len(payload)) + payload
    return struct.pack(">I4s", 0 if to_end else 8 + len(payload), kind) + payload


def media_header(timescale, duration, *, version=0):
    if version == 1:
        body = b"\x01\0\0\0" + struct.pack(">QQIQ", 0, 0, timescale, duration)
    else:
        body = b"\0" * 4 + struct.pack(">IIII", 0, 0, timescale, duration)
    return atom(b"mdhd", body + b"\0" * 4)


def track(*, handler=b"vide", sizes=(11, 12, 13), runs=((2, 40), (1, 20)),
          timescale=100, duration=99, fixed=0, declared=None, version=0,
          extra_stsz=b"", stts_extra=b""):
    count = len(sizes) if declared is None else declared
    sample_sizes = b"\0" * 4 + struct.pack(">II", fixed, count)
    if not fixed:
        sample_sizes += b"".join(struct.pack(">I", value) for value in sizes)
    timing = b"\0" * 4 + struct.pack(">I", len(runs))
    timing += b"".join(struct.pack(">II", *run) for run in runs)
    stbl = atom(b"stbl", atom(b"stsz", sample_sizes + extra_stsz)
                + atom(b"stts", timing + stts_extra))
    mdia = media_header(timescale, duration, version=version)
    mdia += atom(b"hdlr", b"\0" * 8 + handler + b"\0" * 12)
    mdia += atom(b"minf", stbl)
    return atom(b"trak", atom(b"mdia", mdia))


def movie(*tracks, large=False, to_end=False):
    # A false stsz signature in mdat must never be counted as a sample table.
    return atom(b"ftyp", b"isom\0\0\0\0isom") + atom(b"mdat", b"fake stsz vide moov") + atom(
        b"moov", b"".join(tracks), large=large, to_end=to_end)


def implementation(test):
    path = ROOT / "tools/art/check_motion_video.py"
    test.assertTrue(path.is_file(), "independent MP4 sample-table parser missing")
    spec = importlib.util.spec_from_file_location("check_motion_video", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MotionVideoTests(unittest.TestCase):
    def test_video_track_selected_by_handler_not_order_or_audio_count(self):
        parser = implementation(self)
        audio = track(handler=b"soun", sizes=(8,) * 5, runs=((5, 20),), duration=100)
        result = parser.parse_bytes(movie(audio, track()))
        self.assertEqual(len(result["tracks"]), 2)
        video = result["video_tracks"][0]
        self.assertEqual(video["stsz_sample_count"], 3)
        self.assertEqual(video["stts_sample_count"], 3)
        self.assertEqual(video["total_sample_bytes"], 36)
        self.assertEqual(result["tracks"][0]["stsz_sample_count"], 5)

    def test_mixed_timing_runs_use_media_timescale_and_preserve_header_difference(self):
        video = implementation(self).parse_bytes(movie(track()))["video_tracks"][0]
        self.assertEqual(video["stts_duration_ticks"], 100)
        self.assertEqual(video["stts_duration_seconds"], 1)
        self.assertEqual(video["sample_rate"], 3)
        self.assertEqual(video["media_header_duration_ticks"], 99)
        self.assertEqual(video["media_header_duration_seconds"], 0.99)

    def test_fixed_sample_size_has_no_per_sample_array(self):
        video = implementation(self).parse_bytes(movie(track(fixed=7)))["video_tracks"][0]
        self.assertEqual(video["sample_size"], 7)
        self.assertEqual(video["total_sample_bytes"], 21)
        self.assertEqual(video["stsz_sample_count"], 3)

    def test_version_one_media_header_keeps_64_bit_duration(self):
        video = implementation(self).parse_bytes(movie(track(version=1, duration=4294967297)))["video_tracks"][0]
        self.assertEqual(video["mdhd_version"], 1)
        self.assertEqual(video["media_header_duration_ticks"], 4294967297)
        self.assertEqual(video["stts_duration_seconds"], 1)

    def test_large_box_and_parent_to_end_box_are_supported(self):
        parser = implementation(self)
        for options in ({"large": True}, {"to_end": True}):
            with self.subTest(options=options):
                self.assertEqual(parser.parse_bytes(movie(track(), **options))["video_tracks"][0]["stsz_sample_count"], 3)

    def test_disagreeing_size_and_timing_counts_rejected(self):
        with self.assertRaisesRegex(ValueError, "counts disagree"):
            implementation(self).parse_bytes(movie(track(runs=((2, 50),))))

    def test_truncated_sample_sizes_rejected_before_indexing(self):
        with self.assertRaisesRegex(ValueError, "sample size table"):
            implementation(self).parse_bytes(movie(track(declared=4)))

    def test_trailing_or_short_timing_entries_rejected(self):
        with self.assertRaisesRegex(ValueError, "time-to-sample table"):
            implementation(self).parse_bytes(movie(track(stts_extra=b"\0")))

    def test_zero_media_timescale_rejected(self):
        with self.assertRaisesRegex(ValueError, "timescale"):
            implementation(self).parse_bytes(movie(track(timescale=0)))

    def test_zero_total_sample_duration_rejected(self):
        with self.assertRaisesRegex(ValueError, "duration"):
            implementation(self).parse_bytes(movie(track(runs=((3, 0),))))

    def test_fragmented_video_rejected_instead_of_reporting_empty_moov_counts(self):
        with self.assertRaisesRegex(ValueError, "fragmented"):
            implementation(self).parse_bytes(movie(track()) + atom(b"moof"))

    def test_audio_only_movie_does_not_claim_video_evidence(self):
        with self.assertRaisesRegex(ValueError, "video track"):
            implementation(self).parse_bytes(movie(track(handler=b"soun")))

    def test_duplicate_required_movie_atom_rejected(self):
        with self.assertRaisesRegex(ValueError, "one.*moov"):
            implementation(self).parse_bytes(movie(track()) + atom(b"moov"))

    def test_malformed_box_bounds_fail_with_value_error(self):
        parser = implementation(self)
        for invalid in (b"123", struct.pack(">I4s", 4, b"moov"),
                        struct.pack(">I4s", 500, b"moov"),
                        struct.pack(">I4s", 1, b"moov")):
            with self.subTest(data=invalid):
                with self.assertRaises(ValueError):
                    parser.parse_bytes(invalid)

    def test_cli_refuses_to_overwrite_source_media(self):
        implementation(self)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "retained.mp4"
            original = movie(track())
            source.write_bytes(original)
            result = subprocess.run([sys.executable, str(ROOT / "tools/art/check_motion_video.py"),
                                     str(source), "--output", str(source)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("must not overwrite", result.stderr)
            self.assertEqual(source.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
