"""Strict local JSONL evidence, independent of the optional image pipeline.

An archive validates metadata only. It never activates artwork, reconstructs
deleted resources, rewrites a manifest, or approves the archived visual style.
Rows retain the historical values verbatim; rejection belongs to the envelope.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import sys


ROOT = Path(__file__).resolve().parents[2]
RETIRED = {"rejected_style_v2", "retired"}


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _safe_path(workspace, value, suffix=None):
    _require(isinstance(value, str) and value and ":" not in value and "\\" not in value
             and not any(ord(character) < 32 for character in value)
             and not PurePosixPath(value).is_absolute() and not PureWindowsPath(value).is_absolute()
             and all(part not in ("", ".", "..") for part in value.split("/")),
             "unsafe workspace-relative audit path: " + str(value))
    _require(suffix is None or value.endswith(suffix), "audit path must end in " + str(suffix))
    root = Path(workspace).resolve()
    target = (root / value).resolve()
    _require(target != root and target.is_relative_to(root), "audit path escapes workspace: " + value)
    return target


def _hash(value, length=64):
    return isinstance(value, str) and re.fullmatch(r"[a-fA-F0-9]{" + str(length) + r"}", value) is not None


def _reason(value):
    return isinstance(value, str) and bool(value.strip()) and "\ufffd" not in value


def _json_value(value):
    if value is None or type(value) in (str, bool, int):
        return True
    if type(value) is float:
        return math.isfinite(value)
    if isinstance(value, list):
        return all(_json_value(item) for item in value)
    if isinstance(value, dict):
        return all(isinstance(key, str) and _json_value(item) for key, item in value.items())
    return False


def _unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        _require(key not in result, "duplicate JSON object key: " + key)
        result[key] = value
    return result


def _invalid_constant(value):
    raise ValueError("nonfinite JSON value: " + value)


def _parse(text):
    value = json.loads(text, object_pairs_hook=_unique_pairs, parse_constant=_invalid_constant)
    _require(_json_value(value), "JSON contains nonfinite or unsupported values")
    return value


def validate_records(workspace, records):
    """Validate envelopes and runtime metadata without opening archived PNGs."""
    _require(isinstance(records, list) and records, "audit JSONL must contain records")
    seen = set()
    for row in records:
        _require(isinstance(row, dict) and {"type", "key", "value"} <= row.keys()
                 and row.keys() <= {"type", "key", "value", "status", "reason"}
                 and _json_value(row), "invalid audit record envelope")
        kind, key = row["type"], row["key"]
        _require(kind in ("manifest_section", "runtime_copy") and isinstance(key, str) and bool(key),
                 "invalid audit record type/key")
        _require((kind, key) not in seen, "duplicate audit record identity: " + key)
        seen.add((kind, key))
        if "status" in row:
            _require(isinstance(row["status"], str) and row["status"] in RETIRED
                     and _reason(row.get("reason")), "retired audit record needs an intact reason")
        else:
            _require("reason" not in row, "audit reason requires an explicit retired status")
        if kind == "manifest_section":
            _require(re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", key), "invalid manifest section key")
            continue
        value = row["value"]
        _require(isinstance(value, dict) and value.get("path") == key, "runtime audit key/path mismatch")
        for field in ("path", "source_path"):
            _safe_path(workspace, value.get(field))
        for field in ("native_size", "runtime_size"):
            size = value.get(field)
            _require(isinstance(size, list) and len(size) == 2
                     and all(type(number) is int and number > 0 for number in size),
                     "invalid runtime audit dimensions: " + field)
        _require(_hash(value.get("sha256")), "invalid runtime audit SHA256")
        if "source_sha256" in value:
            _require(_hash(value["source_sha256"]), "invalid runtime audit source SHA256")
        _require(isinstance(value.get("method"), str) and value["method"].strip(), "missing runtime audit method")
    return records


def _decode_records(workspace, data):
    try:
        lines = data.decode("utf-8").splitlines()
    except UnicodeError as error:
        raise ValueError("audit JSONL is not valid UTF-8") from error
    rows = []
    for number, line in enumerate(lines, 1):
        _require(line.strip(), "blank audit JSONL line: " + str(number))
        try:
            rows.append(_parse(line))
        except ValueError as error:
            raise ValueError("invalid audit JSONL line " + str(number) + ": " + str(error)) from error
    return validate_records(workspace, rows)


def read_jsonl(workspace, path, *, expected_sha256=None):
    target = _safe_path(workspace, path, ".jsonl")
    data = target.read_bytes()
    if expected_sha256 is not None:
        _require(_hash(expected_sha256) and hashlib.sha256(data).hexdigest() == expected_sha256.lower(),
                 "local audit SHA256 mismatch: " + path)
    return _decode_records(workspace, data)


def write_jsonl(workspace, path, records):
    """Preflight all metadata, then create exclusively or accept identical bytes."""
    target = _safe_path(workspace, path, ".jsonl")
    validate_records(workspace, records)
    data = "".join(json.dumps(row, ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n"
                   for row in records).encode("utf-8")
    if target.exists():
        if not target.is_file() or target.read_bytes() != data:
            raise FileExistsError("local audit is immutable; choose a new path: " + path)
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as stream:
            stream.write(data)
    return {"path": path, "records": len(records), "sha256": hashlib.sha256(data).hexdigest()}


def validate_descriptor(workspace, descriptor):
    required = {"version", "kind", "path", "sha256", "source_commit", "optional", "status"}
    _require(isinstance(descriptor, dict) and required <= descriptor.keys()
             and descriptor.keys() <= required | {"reason"}, "invalid local audit descriptor fields")
    _require(type(descriptor["version"]) is int and descriptor["version"] == 1
             and descriptor["kind"] == "local_art_audit", "invalid local audit descriptor version/kind")
    _safe_path(workspace, descriptor["path"], ".jsonl")
    _require(_hash(descriptor["sha256"]) and _hash(descriptor["source_commit"], 40),
             "invalid local audit descriptor SHA256/source commit")
    _require(type(descriptor["optional"]) is bool and descriptor["status"] in ("local_only", "retired"),
             "invalid local audit descriptor optional/status")
    _require("reason" not in descriptor or isinstance(descriptor["reason"], str)
             and "\ufffd" not in descriptor["reason"], "invalid local audit descriptor reason")
    _require(descriptor["status"] != "retired" or _reason(descriptor.get("reason")),
             "retired local audit descriptor needs an intact reason")
    return descriptor


def inspect_audit(workspace, descriptor):
    """Missing optional evidence is SKIP; present corrupt evidence is an error."""
    validate_descriptor(workspace, descriptor)
    target = _safe_path(workspace, descriptor["path"], ".jsonl")
    report = {"path": descriptor["path"], "source_commit": descriptor["source_commit"],
              "active": False, "art_passed": False, "validated": False,
              "resource_validation": "not_requested", "missing": []}
    if not target.exists():
        if not descriptor["optional"]:
            raise FileNotFoundError("required local audit is missing: " + descriptor["path"])
        return {**report, "status": "skipped", "code": "SKIP_LOCAL_AUDIT_MISSING",
                "missing": [descriptor["path"]], "message": "SKIP: optional local audit JSONL is absent; no archived resource validation was performed."}
    rows = read_jsonl(workspace, descriptor["path"], expected_sha256=descriptor["sha256"])
    retired = [row for row in rows if row.get("status") in RETIRED]
    status = "retired" if descriptor["status"] == "retired" or retired else "available"
    reasons = {row["reason"] for row in retired}
    if descriptor["status"] == "retired":
        reasons.add(descriptor["reason"])
    return {**report, "status": status, "code": "LOCAL_AUDIT_" + status.upper(),
            "validated": True, "records": len(rows), "retired_records": len(retired),
            "types": dict(Counter(row["type"] for row in rows)), "reasons": sorted(reasons),
            "sha256": descriptor["sha256"].lower()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--descriptor", required=True, help="workspace-relative small JSON descriptor")
    args = parser.parse_args(argv)
    try:
        path = _safe_path(args.workspace, args.descriptor, ".json")
        descriptor = _parse(path.read_bytes().decode("utf-8"))
        print(json.dumps(inspect_audit(args.workspace, descriptor), ensure_ascii=True))
        return 0
    except (ValueError, OSError) as error:
        print("LOCAL ART AUDIT ERROR: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
