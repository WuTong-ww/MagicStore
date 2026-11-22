"""Scan real PNG alpha edges with the shared, validated A2R data contract."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/art"))
import item_pipeline


def check_file(path, config=None, expected_size=None):
    image = item_pipeline.common.read_image(path)
    report = item_pipeline.alpha_report(image, config)
    report["path"] = str(path)
    if expected_size is not None and report["size"] != expected_size:
        report["errors"].append("unexpected_size")
        report["passed"] = False
    return report


def check_visuals(workspace, relative, config):
    """Check the actual production selection, including every derived icon."""
    common = item_pipeline.common
    data = common.read_json(common.safe_path(workspace, relative, must_exist=True))
    item_pipeline.require(isinstance(data, dict) and data.get("selected_version") == 3,
                          "production item alpha requires selected_version 3 independent PNGs")
    items = data.get("items")
    item_pipeline.require(isinstance(items, dict) and set(items) == set(config["required_ids"]),
                          "production item mapping must cover every required item ID")
    paths, reports = set(), []
    for item_id in config["required_ids"]:
        row = items[item_id]
        item_pipeline.require(isinstance(row, dict) and row.get("item_id") == item_id,
                              "invalid production item identity: " + item_id)
        for field, size in (("path", config["runtime_size"]), ("icon_path", config["icon_size"])):
            value = row.get(field)
            item_pipeline.require(isinstance(value, str) and value.startswith("res://") and value.endswith(".png"),
                                  "missing independent production item PNG: " + item_id + "/" + field)
            path = common.safe_path(workspace, value[6:], must_exist=True)
            item_pipeline.require(str(path).casefold() not in paths, "duplicate production item PNG: " + value)
            paths.add(str(path).casefold())
            reports.append(check_file(path, config, size))
    return reports


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="PNG files or directories (nonrecursive)")
    parser.add_argument("--config", default=str(item_pipeline.CONFIG))
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--visuals", help="workspace-relative production item mapping; checks all large/small PNGs")
    args = parser.parse_args(argv)
    try:
        config = item_pipeline.load_config(args.config)
        item_pipeline.require(not (args.paths and args.visuals), "select paths or --visuals, not both")
        if args.visuals:
            reports = check_visuals(Path(args.workspace).resolve(), args.visuals, config)
        else:
            paths = []
            for value in args.paths:
                path = Path(value)
                paths.extend(sorted(path.glob("*.png")) if path.is_dir() else [path])
            item_pipeline.require(paths, "no PNGs selected")
            reports = [check_file(path, config) for path in paths]
        print(json.dumps({"passed": all(row["passed"] for row in reports), "checked": len(reports), "reports": reports}, ensure_ascii=False))
        return 0 if all(row["passed"] for row in reports) else 1
    except (ValueError, OSError) as error:
        print("A2R ALPHA ERROR: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
