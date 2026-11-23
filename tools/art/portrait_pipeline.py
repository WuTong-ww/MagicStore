"""A4 offline masks/normalization and builtin-call declarations. No model client."""
from __future__ import annotations

import argparse
import copy
from collections import deque
import hashlib
import io
import json
import math
import re
from pathlib import Path
import sys

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import art_pipeline as common
import check_parts as checker

CONFIG = ROOT / "data/art/portrait_pipeline.json"
SCRIPT = "tools/art/portrait_pipeline.py"


def require(ok, message):
    if not ok: raise ValueError(message)


def identifier(value):
    return isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", value) is not None


def hash_value(value):
    return isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value) is not None


def png(image):
    stream = io.BytesIO()
    image.save(stream, "PNG")
    return stream.getvalue()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def config_digest(config):
    return digest(json.dumps(config, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))


def catalog_records(catalog):
    records = []
    for category in catalog["layer_order"]:
        for row in catalog["parts"][category]:
            if row.get("optional"):
                continue
            variants = row.get("paths", {None: row.get("path")})
            for mood, path in variants.items():
                records.append({"id": row["id"] + ("_" + mood if mood else ""), "category": category,
                                "part_id": row["id"], "mood": mood, "formal_path": path.removeprefix("res://")})
    return records


def validate_config(config, workspace=ROOT):
    checker.validate_config(config)
    require(config.get("expected_part_count") == 139 and len(config["assets"]) == 139, "A4 must enumerate exactly 139 parts")
    for field in ("catalog_path", "source_root", "formal_root"):
        common.safe_path(workspace, config.get(field))
    require(config["source_root"].startswith("assets/_incoming/") and config["formal_root"].startswith("assets/portraits/v3/"), "invalid portrait roots")
    catalog = common.read_json(common.safe_path(workspace, config["catalog_path"], must_exist=True))
    expected = {x["id"]: x for x in catalog_records(catalog)}
    require(len(expected) == 139 and catalog.get("canvas") == config["canvas"] and catalog.get("anchors") == config.get("anchors"), "portrait catalog/rig mismatch")
    actual = {x["id"]: {k: x.get(k) for k in ("id", "category", "part_id", "mood", "formal_path")} for x in config["assets"]}
    require(expected == actual, "portrait catalog exact identity/mood/path mismatch")
    for row in config["assets"]:
        common.safe_path(workspace, row["formal_path"])
        require(row["formal_path"].startswith(config["formal_root"] + "/parts/") and isinstance(row.get("description"), str) and row["description"].strip(), "invalid portrait part destination/description")
    require(type(config.get("maximum_generation_attempts")) is int and 1 <= config["maximum_generation_attempts"] <= 4, "portrait attempt cap exceeds four")
    require(type(config.get("maximum_manifest_bytes")) is int and config["maximum_manifest_bytes"] > 0, "missing compact manifest byte budget")
    require(type(config.get("maximum_pilot_batch")) is int and config["maximum_pilot_batch"] > 0, "invalid portrait pilot batch bound")
    generation = config.get("generation", {})
    require(generation.get("tool") == "image_gen.imagegen" and generation.get("mask_application") == "reference_only_no_dedicated_mask_api", "portrait generation requires builtin/reference mask")
    require(isinstance(generation.get("templates"), dict) and isinstance(generation.get("expression_labels"), dict) and set(generation["expression_labels"]) == set(catalog["moods"]), "invalid portrait templates/expressions")
    require(all(isinstance(value,str) and value.strip() for key,value in generation["templates"].items()
                if key.startswith("manifest_")), "invalid output-only portrait encoding template")
    require(type(generation.get("template_version",1)) is int and generation.get("template_version",1) in (1,2) and
            isinstance(generation.get("template_key"),str) and generation["template_key"].strip(), "invalid portrait generation template version/key")
    if generation.get("template_version",1)==2:
        suffixes = generation.get("family_suffixes",{})
        require(isinstance(suffixes,dict) and set(suffixes)<=set(catalog["layer_order"]) and all(isinstance(v,str) for v in suffixes.values()), "invalid detached family templates")
        expressions = generation.get("family_expression_labels",{})
        require(isinstance(expressions,dict) and set(expressions)<=set(catalog["layer_order"]) and all(isinstance(labels,dict) and set(labels)<=set(catalog["moods"]) and
                all(isinstance(v,str) for v in labels.values()) for labels in expressions.values()), "invalid family expression templates")
        overrides = generation.get("description_overrides",{})
        require(isinstance(overrides,dict) and set(overrides)<=set(expected) and all(isinstance(v,str) for v in overrides.values()), "invalid mood description override")
    for kind in ("style_reference", "mannequin"):
        ref = config.get(kind, {})
        common.safe_path(workspace, ref.get("path"))
        require(hash_value(ref.get("sha256")), "missing selected " + kind + " SHA")
    base = config["mannequin"]
    for field in ("source_path", "generation_receipt"):
        common.safe_path(workspace, base.get(field))
    require(hash_value(base.get("source_sha256")) and hash_value(base.get("generation_receipt_sha256")), "missing mannequin provenance SHA")
    native = base.get("source_native_size")
    require(isinstance(native, list) and len(native) == 2 and all(type(n) is int and n > 0 for n in native), "invalid mannequin native size")
    transform = base.get("transform", {})
    require(transform.get("method") == "full_canvas_resize_translate" and transform.get("filter") == "Lanczos" and
            transform.get("source_crop") == [0, 0, *native] and transform.get("resize_size") == config["canvas"] and
            transform.get("fill_rgb") == [255, 0, 255] and isinstance(transform.get("translation_px"), list) and
            len(transform["translation_px"]) == 2 and all(type(n) is int for n in transform["translation_px"]), "invalid mannequin actual transform")
    processing = config.get("processing", {})
    require(processing.get("crop_policy") == "full_canvas_only" and processing.get("resize_filter") == "Lanczos" and
            processing.get("grayscale_method") == "mean_rgb" and processing.get("output_mode") == "RGBA" and
            processing.get("translation_px") == [0, 0] and processing.get("magenta_rgb") == [255, 0, 255], "unsupported portrait normalization")
    require(type(processing.get("key_full_removal_excess")) is int and 0 < processing["key_full_removal_excess"] <= 255 and
            type(processing.get("key_minimum_background_pixels")) is int and processing["key_minimum_background_pixels"] > 0, "invalid portrait matte parameters")
    require(type(processing.get("version",1)) is int and processing.get("version",1) in (1,2), "unsupported portrait processing version")
    if processing.get("version",1) == 2:
        cleanup = processing.get("edge_cleanup",{})
        require(isinstance(cleanup,dict) and cleanup.get("method") == "category_inward_alpha_core_color_bleed", "missing portrait edge cleanup")
        profiles = cleanup.get("profiles",{})
        categories = cleanup.get("category_profiles",{})
        require(isinstance(profiles,dict) and set(profiles)=={"solid","fine"} and isinstance(categories,dict) and
                set(categories)==set(catalog["layer_order"]), "missing portrait category edge profile")
        for name,profile in profiles.items():
            require(isinstance(profile,dict) and type(profile.get("erode_pixels")) is int and 0 <= profile["erode_pixels"] <= 1 and
                    type(profile.get("color_bleed_pixels")) is int and 0 <= profile["color_bleed_pixels"] <= 16 and
                    type(profile.get("color_seed_alpha")) is int and 1 <= profile["color_seed_alpha"] <= 255, "invalid portrait edge pixel parameters")
            feather = profile.get("feather_pixels")
            require(type(feather) in (int,float) and math.isfinite(feather) and 0 <= feather <= 1, "invalid portrait edge feather")
            require(type(profile.get("keep_seeded_components_only")) is bool and profile["keep_seeded_components_only"]==(name=="solid"), "invalid portrait component policy")
            require(profile.get("color_bleed_policy","nearest_core") in ("nearest_core","reduce_bright_outliers_only"), "invalid portrait core color policy")
            require(name!="fine" or profile["erode_pixels"]==0 and feather==0, "fine portrait features must preserve alpha")
        require(all(categories[name]==("solid" if name in ("body","outfit","face_shape") else "fine") for name in categories), "portrait category erosion is not authorized")
    alignment = processing.get("fine_alignment")
    if alignment is not None:
        require(isinstance(alignment,dict) and alignment.get("version")==1 and alignment.get("bbox_alpha_threshold")==128 and
                alignment.get("resampling")=="Bicubic", "invalid fine alignment algorithm")
        limits = alignment.get("scale_limits")
        require(isinstance(limits,list) and len(limits)==2 and all(type(v) in (int,float) and math.isfinite(v) for v in limits) and
                0.5<=limits[0]<=limits[1]<=2 and type(alignment.get("support_margin_px")) is int and 0<=alignment["support_margin_px"]<=8,
                "fine alignment scale/margin exceeds authorized bounds")
        rules = alignment.get("rules")
        require(isinstance(rules,dict), "missing fine alignment rules")
        by_id = {r["id"]:r for r in config["assets"]}
        for asset_id,rule in rules.items():
            require(asset_id in by_id and by_id[asset_id]["category"] in ("features","eyes_expr","brows_expr","mouth_expr","accessory") and
                    isinstance(rule,dict) and rule.get("mode") in ("anchor","contain") and rule.get("reviewed_isolated") is True and
                    hash_value(rule.get("reviewed_source_sha256")), "fine alignment requires exact reviewed isolated source")
            common.safe_path(workspace,rule.get("isolation_evidence"))
            require(checker.rectangle(rule.get("fit_rect"),config["canvas"]), "invalid fine alignment rectangle")
            for field in ("min_extent","max_extent"):
                extent = rule.get(field)
                require(isinstance(extent,list) and len(extent)==2 and all(type(v) is int and v>=0 for v in extent), "invalid fine alignment extent")
            require(all(0<=lo<=hi and hi>0 for lo,hi in zip(rule["min_extent"],rule["max_extent"])), "fine alignment min/max extent mismatch")
            if rule["mode"]=="anchor":
                center = rule.get("target_center");rect = rule["fit_rect"]
                require(isinstance(center,list) and len(center)==2 and all(type(v) in (int,float) and math.isfinite(v) for v in center) and
                        rect[0]<center[0]<rect[2] and rect[1]<center[1]<rect[3], "fine alignment anchor outside rectangle")
            else:
                require("target_center" not in rule, "contain alignment does not accept a target center override")
    for asset_id,rule in processing.get("region_overrides",{}).items():
        row = next(r for r in config["assets"] if r["id"]==asset_id)
        require(row["category"] in ("hair_front","hair_back","outfit","face_shape","body","accessory"), "processing region expansion is not authorized for fine face parts")
        original = config["regions"][row["region"]]["shape"].get("rect")
        expanded = config["regions"][rule["region"]]["shape"].get("rect")
        require(original is not None and expanded is not None and expanded[0]<=original[0] and expanded[1]<=original[1] and
                expanded[2]>=original[2] and expanded[3]>=original[3], "processing region must preserve the entire original guide")
        common.safe_path(workspace,rule.get("isolation_evidence"))
        common.safe_path(workspace,rule.get("audit_mask_path"))
        require(rule["audit_mask_path"].startswith(config["source_root"]+"/masks/"), "processing mask audit must remain incoming")
    visibility = processing.get("processing_visibility")
    if visibility is not None:
        require(isinstance(visibility,dict) and type(visibility.get("version")) is int and visibility["version"]==1 and
                isinstance(visibility.get("rules"),dict), "invalid body processing visibility")
        by_id = {r["id"]:r for r in config["assets"]}
        outfit_ids = {r["id"] for r in catalog["parts"]["outfit"]}
        for asset_id,rule in visibility["rules"].items():
            require(asset_id in by_id and by_id[asset_id]["category"] in ("body","hair_back","outfit","accessory") and isinstance(rule,dict) and type(rule.get("enabled")) is bool and
                    hash_value(rule.get("reviewed_source_sha256")), "visibility requires an explicitly reviewed body, rear-hair, garment or accessory source")
            shape = rule.get("shape",{});polygon = shape.get("polygon") if isinstance(shape,dict) else None
            require(isinstance(shape,dict) and set(shape) in ({"rect"},{"polygon"}), "invalid visibility shape")
            if "rect" in shape: require(checker.rectangle(shape["rect"],config["canvas"]), "invalid visibility rectangle")
            else:
                require(isinstance(polygon,list) and len(polygon)>=3 and all(isinstance(point,list) and len(point)==2 and all(type(v) is int for v in point) and
                        0<=point[0]<config["canvas"][0] and 0<=point[1]<config["canvas"][1] for point in polygon), "invalid visibility polygon")
                require(sum(polygon[i][0]*polygon[(i+1)%len(polygon)][1]-polygon[(i+1)%len(polygon)][0]*polygon[i][1] for i in range(len(polygon)))!=0, "visibility polygon has no area")
            compatible = rule.get("compatible_outfit_ids",[])
            require(isinstance(compatible,list) and (compatible or by_id[asset_id]["category"]!="body") and all(isinstance(v,str) and v in outfit_ids for v in compatible) and len(set(compatible))==len(compatible),
                    "body visibility requires explicit valid outfit scope")
            require(isinstance(rule.get("preserve_rois"),list) and rule["preserve_rois"] and all(checker.rectangle(roi,config["canvas"]) for roi in rule["preserve_rois"]),
                    "missing visibility neck preservation region")
            require(isinstance(rule.get("expected_hidden_points"),list) and all(isinstance(point,list) and len(point)==2 and all(type(v) is int for v in point) and
                    0<=point[0]<config["canvas"][0] and 0<=point[1]<config["canvas"][1] for point in rule["expected_hidden_points"]), "invalid hidden visibility sample")
            require(isinstance(rule.get("expected_hidden_rects",[]),list) and all(checker.rectangle(rect,config["canvas"]) for rect in rule.get("expected_hidden_rects",[])), "invalid hidden visibility rectangle")
            reference_keys = ("preserve_reference_path","preserve_reference_sha256")
            require(all(key in rule for key in reference_keys) or not any(key in rule for key in reference_keys), "incomplete visibility preservation reference")
            if reference_keys[0] in rule:
                common.safe_path(workspace,rule[reference_keys[0]])
                require(hash_value(rule[reference_keys[1]]), "invalid visibility preservation SHA")
            common.safe_path(workspace,rule.get("audit_mask_path"))
            require(rule["audit_mask_path"].startswith(config["source_root"]+"/masks/"), "visibility audit mask must remain incoming")
            context_keys = ("audit_preserve_visible_row_band","audit_occluder_path","audit_occluder_sha256")
            require(all(key in rule for key in context_keys) or not any(key in rule for key in context_keys), "incomplete visibility row audit context")
            if context_keys[0] in rule:
                band = rule[context_keys[0]]
                require(isinstance(band,list) and len(band)==2 and all(type(v) is int for v in band) and 0<=band[0]<=band[1]<config["canvas"][1] and
                        hash_value(rule["audit_occluder_sha256"]), "invalid visibility row audit context")
                common.safe_path(workspace,rule["audit_occluder_path"])
    review = config.get("matte_review")
    if review is not None:
        require(isinstance(review,dict) and isinstance(review.get("backgrounds"),dict) and set(review["backgrounds"])=={"black","paper","scene"} and
                all(isinstance(rgb,list) and len(rgb)==3 and all(type(v) is int and 0<=v<=255 for v in rgb) for rgb in review["backgrounds"].values()), "invalid portrait comparison backgrounds")
        require(type(review.get("zoom")) is int and review["zoom"]>0 and isinstance(review.get("detail_rois"),dict) and
                all(checker.rectangle(roi,config["canvas"]) for roi in review["detail_rois"].values()) and
                checker.rectangle(review.get("body_empty_side_roi"),config["canvas"]), "invalid portrait matte diagnostic region")
    return config


def load_config(path=CONFIG, workspace=ROOT):
    return validate_config(common.read_json(path), workspace)


def _selected(config, only):
    rows = {x["id"]: x for x in config["assets"]}
    rows["mannequin"] = {"id": "mannequin", "category": "mannequin", "part_id": None, "mood": "neutral", "region": "mannequin", "formal_path": config["mannequin"]["path"]}
    chosen = list(only) if only else list(rows)
    require(chosen and len(set(chosen)) == len(chosen) and all(x in rows for x in chosen), "unknown/duplicate portrait selection")
    return [rows[x] for x in chosen]


def _mask_path(config, revision, region):
    return config["source_root"] + "/masks/" + revision + "/" + region + ".png"


def prepare_masks(workspace, revision, only=None, config=None):
    config = validate_config(config or load_config(), workspace)
    require(identifier(revision), "invalid portrait revision")
    regions = sorted({x["region"] for x in _selected(config, only)})
    outputs = [(_mask_path(config, revision, region), png(checker.mask_image(config, region)), region) for region in regions]
    for path, data, _ in outputs:
        file = common.safe_path(workspace, path)
        require(not file.exists() or file.read_bytes() == data, "immutable mask already differs; use a new revision")
    for path, data, _ in outputs: common._write_new(common.safe_path(workspace, path), data)
    return {"version": 1, "kind": "portrait_reference_masks", "config_digest": config_digest(config), "mask_application": config["generation"]["mask_application"],
            "masks": [{"path": p, "sha256": digest(data), "region": name, "review_status": config["regions"][name]["review_status"]} for p, data, name in outputs], "art_passed": False}


def _actual(workspace, path, expected_sha=None, size=None):
    file = common.safe_path(workspace, path, must_exist=True)
    try:
        with Image.open(file) as source:
            require(source.format == "PNG", "portrait input is not actual PNG: " + path)
            source.load()
            image = source.copy()
    except OSError as error:
        raise ValueError("unreadable portrait image: " + path) from error
    require(expected_sha is None or common.sha256(file) == expected_sha, "portrait SHA mismatch: " + path)
    require(size is None or list(image.size) == size, "portrait native dimensions mismatch: " + path)
    return image


def _record_image(workspace, path, expected_sha, size):
    require(hash_value(expected_sha) and isinstance(size, list) and len(size) == 2 and
            all(type(n) is int and n > 0 for n in size), "portrait receipt requires actual SHA/native_size")
    return _actual(workspace, path, expected_sha, size)


def _baseline_pending(workspace, config, style, *, require_origin=False):
    base = config["mannequin"]
    refs = [(base["path"], base["sha256"], config["canvas"]),
            (style, config["style_reference"]["sha256"] if style == config["style_reference"]["path"] else None, None)]
    missing = []
    for path, expected, size in refs:
        if not common.safe_path(workspace, path).is_file(): missing.append(path)
        else: _actual(workspace, path, expected, size)
    native = common.safe_path(workspace,base["source_path"])
    if native.is_file(): _actual(workspace,base["source_path"],base["source_sha256"],base["source_native_size"])
    elif require_origin: missing.append(base["source_path"])
    history = common.safe_path(workspace, base["generation_receipt"])
    if not history.is_file():
        if require_origin: missing.append(base["generation_receipt"])
    else: require(common.sha256(history) == base["generation_receipt_sha256"], "mannequin generation history SHA mismatch")
    if native.is_file() and common.safe_path(workspace,base["path"]).is_file():
        source = _actual(workspace, base["source_path"]).convert("RGB")
        transform = base["transform"]
        normalized = source.resize(tuple(config["canvas"]), Image.Resampling.LANCZOS)
        shifted = Image.new("RGB", tuple(config["canvas"]), tuple(transform["fill_rgb"]))
        shifted.paste(normalized, tuple(transform["translation_px"]))
        require(ImageChops.difference(shifted, _actual(workspace, base["path"]).convert("RGB")).getbbox() is None,
                "mannequin actual pixels do not match registered native transform")
    return missing


def _baseline_origin_audit(workspace, config):
    """Describe optional origin checks already performed by _baseline_pending."""
    base = config["mannequin"]
    missing = [base[key] for key in ("source_path","generation_receipt") if not common.safe_path(workspace,base[key]).is_file()]
    return {"status":"skipped_missing_origin_evidence" if missing else "available_sha_verified", "missing_paths":missing,
            "native_transform_verified":base["source_path"] not in missing and common.safe_path(workspace,base["path"]).is_file(),
            "recorded_history_sha_verified":base["generation_receipt"] not in missing,
            "note":"Optional origin evidence is separate from actual new edit inputs. Missing history is not claimed verified; present evidence still must match its recorded SHA."}


def _prompt_definition(row, config):
    key = "mannequin" if row["id"] == "mannequin" else "part"
    template = config["generation"]["templates"].get(key)
    template_key = config["generation"]["template_key"]
    if key=="mannequin": template_key += "_mannequin"
    elif config["generation"].get("template_version",1)==2:
        template_key += "_"+row["category"]
        suffix = config["generation"].get("family_suffixes",{}).get(row["category"])
        if not isinstance(suffix,str) or not suffix.strip(): return None,template_key
        if isinstance(template,str): template += "\n"+suffix
    return template,template_key


def render_prompt(row, config):
    template,_ = _prompt_definition(row,config)
    if not isinstance(template, str) or not template.strip(): return None, {}
    generation = config["generation"]
    description = row.get("description", "")
    expression = generation["expression_labels"].get(row.get("mood"), "no expression features in this slot")
    if generation.get("template_version",1)==2:
        overrides = generation.get("description_overrides",{})
        description = overrides.get(row["id"],description)
        if row["category"]=="mouth_expr" and row.get("mood")=="surprised" and row["id"] not in overrides: return None,{}
        labels = generation.get("family_expression_labels",{}).get(row["category"])
        if labels is not None and row.get("mood") is not None: expression = labels.get(row["mood"])
        if not isinstance(expression,str) or not expression.strip() or row["id"]!="mannequin" and not description.strip(): return None,{}
    params = {"description": description, "category": row["category"], "expression": expression,
              "width": config["canvas"][0], "height": config["canvas"][1], **config["anchors"]}
    try: return template.format(**params), params
    except (KeyError, ValueError) as error: raise ValueError("invalid portrait prompt template") from error


def build_queue(workspace, revision, only=None, style=None, config=None, *, mask_revision=None, attempt=1, pilot=False):
    config = validate_config(config or load_config(), workspace)
    require(identifier(revision), "invalid portrait revision")
    mask_revision = mask_revision or revision
    require(identifier(mask_revision), "invalid portrait mask revision")
    require(type(attempt) is int and 1 <= attempt <= config["maximum_generation_attempts"], "portrait attempt exceeds configured cap")
    selected = _selected(config, only)
    require(type(pilot) is bool and (not pilot or only and len(selected) <= config["maximum_pilot_batch"]), "pilot requires an explicit bounded selection")
    style = style or config["style_reference"]["path"]
    common.safe_path(workspace, style)
    missing = _baseline_pending(workspace, config, style)
    tasks = []
    for row in selected:
        prompt, params = render_prompt(row, config)
        if prompt is None:
            return {"version": 1, "kind": "portrait_builtin_queue", "status": "pending_templates", "tasks": [], "offline_tasks": [], "pending": [{"reason": "missing_portrait_template", "id": row["id"]}], "generation_performed": False, "art_passed": False}
        mask_path = _mask_path(config, mask_revision, row["region"])
        mask_file = common.safe_path(workspace, mask_path)
        mask_sha = digest(png(checker.mask_image(config, row["region"])))
        if mask_file.is_file(): require(common.sha256(mask_file) == mask_sha, "portrait reference mask SHA mismatch")
        refs = [config["mannequin"]["path"], mask_path, style]
        dependencies = []
        reasons = (["source"] if missing else []) + (["mask"] if not mask_file.is_file() else [])
        review_status = config["regions"][row["region"]]["review_status"]
        if review_status == "provisional" and not pilot: reasons.append("mask_review")
        if row["id"] != "mannequin" and any(x["id"] == "mannequin" for x in selected):
            refs[0] = config["source_root"] + "/processed/" + revision + "/mannequin.png"
            dependencies.append(refs[0])
            reasons.append("new_mannequin_review")
        if style != config["style_reference"]["path"] and row["id"] != "mannequin": reasons.append("new_style_mask_review")
        destination = config["source_root"] + "/" + revision + "/" + row["id"] + "/source-attempt" + str(attempt) + ".png"
        if common.safe_path(workspace, destination).exists(): reasons.append("existing_raw_needs_receipt")
        bindings = {p: common.sha256(common.safe_path(workspace, p)) for p in refs if common.safe_path(workspace, p).is_file()}
        tasks.append({"id": row["id"], "recipe_id": "A4_" + row["id"], "group": "portraits", "art_pack": "A4_v3", "category": row["category"], "part_id": row["part_id"], "mood": row["mood"],
                      "operation": "portrait_mannequin" if row["id"] == "mannequin" else "portrait_part", "tool": config["generation"]["tool"],
                      "source_destination": destination, "processed_destination": config["source_root"] + "/processed/" + revision + "/" + row["id"] + ".png",
                      "ref_paths": refs, "reference_shas": bindings, "mask_path": mask_path, "mask_sha256": mask_sha,
                      "mask_application": config["generation"]["mask_application"], "template_key": _prompt_definition(row,config)[1], "prompt_parameters": params,
                      "template_version":config["generation"].get("template_version",1),
                      "prompt_sha256": digest(prompt.encode("utf-8")), "depends_on": dependencies, "pending_reasons": reasons,
                      "status": "pending_" + reasons[0] if reasons else "needs_builtin_generation", "can_generate": not reasons, "ready": not reasons,
                      "attempt_cap": config["maximum_generation_attempts"], "arguments": {"prompt": prompt, "referenced_image_paths": [str(common.safe_path(workspace, p)) for p in refs], "transparent_background": False}})
        tasks[-1].update(attempt_number=attempt, attempts_used=attempt-1, attempt_counter_source="explicit_operator_input", mask_revision=mask_revision)
        tasks[-1].update(pilot=pilot, mask_review_status=review_status,
                         review_required_after_generation=["actual_part_and_mask_outline_review"] if pilot else [])
    return {"version": 1, "kind": "portrait_builtin_queue", "revision": revision, "mask_revision":mask_revision, "status": "needs_builtin_generation" if any(x["can_generate"] for x in tasks) else "pending_portrait_inputs",
            "tasks": tasks, "offline_tasks": [{"operation": "portrait_part_normalize", "depends_on": [x["source_destination"]], "id": x["id"], "processing_script": SCRIPT, "can_process": False,
                "command_after_generation":["python",SCRIPT,"process","--workspace",str(Path(workspace).resolve()),"--receipt",config["source_root"]+"/"+revision+"/generation_receipt.json","--revision",revision,"--only",x["id"],"--output",config["source_root"]+"/processed/"+revision+"/"+x["id"]+"-receipt.json"]} for x in tasks],
            "style_reference": style, "config_digest": config_digest(config), "missing_paths": missing,
            "origin_audit":_baseline_origin_audit(workspace,config), "generation_performed": False, "manifest_modified": False, "art_passed": False}


def validate_generation_receipt(workspace, generation, config=None):
    config = validate_config(config or load_config(), workspace)
    require(isinstance(generation, dict) and generation.get("version") == 1, "invalid portrait generation receipt")
    style = generation.get("style_reference")
    _actual(workspace, style, generation.get("style_sha256"))
    require(generation.get("style_sha256") == config["style_reference"]["sha256"] and style == config["style_reference"]["path"], "generation style differs from selected portrait config")
    require(generation.get("mannequin_path") == config["mannequin"]["path"] and generation.get("mannequin_sha256") == config["mannequin"]["sha256"], "generation mannequin differs from selected rig")
    require(not _baseline_pending(workspace, config, style), "portrait baseline evidence missing")
    rows = generation.get("records")
    require(isinstance(rows, list) and rows, "missing portrait generation records")
    known = {x["id"]: x for x in _selected(config, None)}
    seen = set()
    for row in rows:
        require(isinstance(row, dict) and row.get("id") in known and row["id"] not in seen, "unknown/duplicate portrait record")
        seen.add(row["id"])
        require(row.get("status") == "complete", "portrait generation is not complete")
        source = row.get("source_path")
        require(isinstance(source, str) and source.startswith(config["source_root"] + "/"), "portrait source must remain incoming")
        _record_image(workspace, source, row.get("sha256"), row.get("native_size"))
        mask = row.get("mask_path")
        _actual(workspace, mask, row.get("mask_sha256"), config["canvas"])
        expected_mask = png(checker.mask_image(config, known[row["id"]]["region"]))
        require(row.get("mask_sha256") == digest(expected_mask), "portrait generation mask differs from registered region")
        refs = row.get("ref_paths")
        require(refs == [generation["mannequin_path"], mask, style], "portrait reference roles mismatch")
        require(isinstance(row.get("prompt"), str) and row["prompt"].strip(), "missing actual portrait prompt")
        bindings = row.get("reference_shas")
        require(isinstance(bindings, dict) and set(bindings) == set(refs) and all(hash_value(v) for v in bindings.values()), "missing actual portrait reference SHAs")
        for ref in refs: _actual(workspace, ref, bindings[ref])
        attempts = row.get("attempts")
        require(isinstance(attempts, list) and 1 <= len(attempts) <= config["maximum_generation_attempts"], "portrait generation attempt cap/missing attempts")
        require(type(row.get("selected_attempt")) is int, "selected portrait attempt must be an integer")
        indices = set()
        selected = []
        for attempt in attempts:
            require(isinstance(attempt, dict) and type(attempt.get("attempt")) is int and 1 <= attempt["attempt"] <= config["maximum_generation_attempts"] and attempt["attempt"] not in indices,
                    "invalid/duplicate portrait attempt")
            indices.add(attempt["attempt"])
            require(attempt.get("status") in ("complete", "failed"), "invalid portrait attempt status")
            require(isinstance(attempt.get("prompt"), str) and attempt["prompt"].strip() and isinstance(attempt.get("ref_paths"), list), "attempt lacks actual prompt/references")
            require(isinstance(attempt.get("reference_shas"), dict) and set(attempt["reference_shas"]) == set(attempt["ref_paths"]) and all(hash_value(v) for v in attempt["reference_shas"].values()), "attempt lacks actual reference SHAs")
            for ref in attempt["ref_paths"]: _actual(workspace, ref, attempt["reference_shas"][ref])
            if attempt["status"] == "complete" or attempt.get("output_path") is not None:
                _record_image(workspace, attempt.get("output_path"), attempt.get("sha256"), attempt.get("native_size"))
            else:
                require(isinstance(attempt.get("error"), str) and attempt["error"].strip(), "failed no-output attempt requires its actual error")
            if attempt["attempt"] == row.get("selected_attempt"): selected.append(attempt)
        require(indices == set(range(1,max(indices)+1)), "portrait attempt history must retain every actual attempt from one through the latest")
        require(len(selected) == 1 and selected[0]["status"] == "complete", "selected portrait attempt missing")
        picked = selected[0]
        require(picked.get("output_path") == source and all(picked.get(k) == row.get(k) for k in ("sha256", "native_size", "prompt", "ref_paths", "reference_shas")), "selected portrait attempt/record mismatch")
    return generation


def clean_matte_edges(image, category, config):
    cleanup = config["processing"]["edge_cleanup"]
    profile_name = cleanup["category_profiles"][category]
    params = cleanup["profiles"][profile_name]
    original = image.convert("RGBA")
    original_alpha = original.getchannel("A")
    alpha = original_alpha
    if params["erode_pixels"]:
        alpha = alpha.filter(ImageFilter.MinFilter(params["erode_pixels"]*2+1))
    if params["feather_pixels"]:
        alpha = alpha.filter(ImageFilter.GaussianBlur(params["feather_pixels"]))
    # Feather may soften inward; it must not invent alpha outside original support.
    alpha = ImageChops.darker(alpha,original_alpha)
    unseeded_removed = 0
    if params["keep_seeded_components_only"]:
        values = bytes(alpha.getdata());width,height = alpha.size
        retained = bytearray(len(values));pending = deque()
        for i,value in enumerate(values):
            if value >= params["color_seed_alpha"]:
                retained[i] = 1;pending.append(i)
        # Keep an entire connected feather, rather than thresholding faint edges.
        while pending:
            i = pending.popleft();y,x = divmod(i,width)
            for dy in (-1,0,1):
                for dx in (-1,0,1):
                    nx,ny = x+dx,y+dy
                    if 0<=nx<width and 0<=ny<height:
                        j = ny*width+nx
                        if values[j] and not retained[j]: retained[j]=1;pending.append(j)
        unseeded_removed = sum(value>0 and not retained[i] for i,value in enumerate(values))
        alpha.putdata([value if retained[i] else 0 for i,value in enumerate(values)])
    source = original.load();target = alpha.load();result = Image.new("RGBA",image.size);output = result.load()
    radius = params["color_bleed_pixels"]
    offsets = sorted((dx*dx+dy*dy,dy,dx) for dy in range(-radius,radius+1) for dx in range(-radius,radius+1))
    replaced = no_seed = 0
    for y in range(image.height):
        for x in range(image.width):
            if not target[x,y]: continue
            color = source[x,y][:3]
            if source[x,y][3] < params["color_seed_alpha"]:
                found = False
                for _distance,dy,dx in offsets:
                    nx,ny = x+dx,y+dy
                    if 0<=nx<image.width and 0<=ny<image.height and source[nx,ny][3] >= params["color_seed_alpha"]:
                        nearest = source[nx,ny][:3]
                        if params.get("color_bleed_policy","nearest_core")!="reduce_bright_outliers_only" or sum(nearest)<sum(color):
                            replaced += nearest != color
                            color = nearest
                        found = True;break
                no_seed += not found
            output[x,y] = (*color,target[x,y])
    return result,{"method":cleanup["method"],"profile":profile_name,"parameters":copy.deepcopy(params),
                   "color_replaced_pixels":replaced,"low_alpha_without_nearby_seed":no_seed,
                   "unseeded_removed_pixels":unseeded_removed,
                   "alpha_changed_pixels":sum(a!=b for a,b in zip(original_alpha.getdata(),alpha.getdata())),
                   "alpha_expanded_pixels":sum(b>a for a,b in zip(original_alpha.getdata(),alpha.getdata()))}


def align_fine_part(image, row, config, source_sha256):
    alignment = config["processing"].get("fine_alignment",{})
    rule = alignment.get("rules",{}).get(row["id"])
    if rule is None: return image,None
    require(rule["reviewed_isolated"] is True and source_sha256==rule["reviewed_source_sha256"], "fine alignment source lacks exact isolation review")
    threshold = alignment["bbox_alpha_threshold"]
    bbox = image.getchannel("A").point(lambda value:255 if value>=threshold else 0).getbbox()
    require(bbox is not None, "fine alignment source has no substantial component")
    extent = [bbox[2]-bbox[0],bbox[3]-bbox[1]]
    source_center = [(bbox[0]+bbox[2])/2,(bbox[1]+bbox[3])/2]
    rect = rule["fit_rect"];margin = alignment["support_margin_px"]
    maximum = [min(rule["max_extent"][i],rect[i+2]-rect[i]-2*margin) for i in range(2)]
    target = list(rule.get("target_center",source_center))
    if rule["mode"]=="anchor":
        maximum = [min(maximum[i],2*min(target[i]-rect[i],rect[i+2]-target[i])-2*margin) for i in range(2)]
    ceiling = min(maximum[i]/extent[i] for i in range(2))
    required = max(rule["min_extent"][i]/extent[i] for i in range(2))
    scale = max(required,min(1.0,ceiling))
    require(scale<=ceiling and alignment["scale_limits"][0]<=scale<=alignment["scale_limits"][1], "fine alignment scale outside authorized range; never shrink a complete person into a part")
    if rule["mode"]=="contain":
        target = [min(max(target[i],rect[i]+margin+extent[i]*scale/2),rect[i+2]-margin-extent[i]*scale/2) for i in range(2)]
    translation = [target[i]-source_center[i]*scale for i in range(2)]
    inverse = [1/scale,0,-translation[0]/scale,0,1/scale,-translation[1]/scale]
    result = image.transform(image.size,Image.Transform.AFFINE,inverse,resample=Image.Resampling.BICUBIC,fillcolor=(0,0,0,0))
    core = result.getchannel("A").point(lambda value:255 if value>=threshold else 0)
    mask = checker.processing_mask(config,row)
    outside = sum(a>0 and m==0 for a,m in zip(core.getdata(),mask.getdata()))
    require(outside==0, "fine affine still clips substantial component pixels")
    return result,{"method":"full_canvas_uniform_affine","source_full_canvas":[0,0,image.width,image.height],
                   "source_alpha_bbox":list(bbox),"bbox_alpha_threshold":threshold,"source_sha256":source_sha256,
                   "reviewed_isolated":True,"isolation_evidence":rule["isolation_evidence"],"scale":scale,
                   "translation_px":translation,"inverse_affine":inverse,"target_center":target,
                   "fit_rect":rect,"support_margin_px":margin,"resampling":alignment["resampling"],
                   "output_alpha_bbox":list(core.getbbox()) if core.getbbox() else None,"outside_mask_core_pixels":outside}


def apply_processing_visibility(image, row, config, source_sha256):
    rule = config["processing"].get("processing_visibility",{}).get("rules",{}).get(row["id"])
    if rule is None or not rule["enabled"]: return image,None
    require(source_sha256==rule["reviewed_source_sha256"], "body visibility requires review of this exact source")
    mask = checker.mask_image({"canvas":config["canvas"],"regions":{"visibility":{"shape":rule["shape"]}}},"visibility")
    before = image.getchannel("A");after = ImageChops.multiply(before,mask)
    for roi in rule["preserve_rois"]:
        require(before.crop(tuple(roi)).tobytes()==after.crop(tuple(roi)).tobytes(), "visibility mask clips approved neck pixels")
    require(all(after.getpixel(tuple(point))==0 for point in rule["expected_hidden_points"]), "visibility leaves known outer-shoulder exposure")
    require(all(after.crop(tuple(rect)).getbbox() is None for rect in rule.get("expected_hidden_rects",[])), "visibility leaves declared background residue")
    result = image.copy();result.putalpha(after)
    result.putdata([(r,g,b,a) if a else (0,0,0,0) for r,g,b,a in result.getdata()])
    audit = {"method":"reversible_full_canvas_display_visibility","enabled":True,"source_sha256":source_sha256,
                   "shape":copy.deepcopy(rule["shape"]),"mask_sha256":digest(png(mask)),"audit_mask_path":rule["audit_mask_path"],
                   "compatible_outfit_ids":rule.get("compatible_outfit_ids",[]),"preserve_rois":rule["preserve_rois"],
                   "preserved_roi_alpha_identical":True,"expected_hidden_points":rule["expected_hidden_points"],
                   "hidden_sample_alpha_zero":True,"changed_alpha_pixels":sum(a!=b for a,b in zip(before.getdata(),after.getdata())),
                   "note":rule.get("display_scope_note","Display-only occlusion for listed full-sleeve outfit; disabling restores full processed body, not any arbitrary exposed-shoulder outfit.")}
    for key in ("expected_hidden_rects","preserve_reference_path","preserve_reference_sha256"):
        if key in rule: audit[key] = copy.deepcopy(rule[key])
    if "audit_preserve_visible_row_band" in rule:
        audit["row_validation_scope"] = {"inclusive_y_band":rule["audit_preserve_visible_row_band"],"occluder_path":rule["audit_occluder_path"],
                                         "occluder_sha256":rule["audit_occluder_sha256"],"visible_alpha_threshold":config["qa"]["visible_alpha_threshold"]}
    return result,audit


def _check_visibility_reference(workspace, image, transform, config):
    visibility = transform.get("processing_visibility",{})
    if "preserve_reference_path" in visibility:
        reference = _actual(workspace,visibility["preserve_reference_path"],visibility["preserve_reference_sha256"],config["canvas"]).convert("RGBA")
        require(all(image.crop(tuple(roi)).tobytes()==reference.crop(tuple(roi)).tobytes() for roi in visibility["preserve_rois"]),
                "visibility changed the recorded preserved subject; use its exact base processing configuration")


def normalize_part(source, row, config, source_sha256=None):
    width, height = source.size
    canvas = config["canvas"]
    require(width * canvas[1] == height * canvas[0], "portrait source must preserve 3:4 full-canvas aspect, never squash/crop")
    rgba = source.convert("RGBA")
    output = []
    removed = 0
    raw_non_gray = 0
    key = config["processing"]
    for red, green, blue, opacity in rgba.getdata():
        excess = max(0.0, (red + blue) / 2.0 - green)
        fraction = 0.0 if excess >= key["key_full_removal_excess"] else 1.0 - excess / 255.0
        removed += opacity > 0 and fraction == 0
        if fraction <= 0 or opacity == 0:
            output.append((0, 0, 0, 0))
            continue
        raw_non_gray += max(red, green, blue) != min(red, green, blue)
        recovered = [(red - (1.0 - fraction) * 255.0) / fraction, green / fraction, (blue - (1.0 - fraction) * 255.0) / fraction]
        gray = max(0, min(255, int(sum(recovered) / 3.0 + 0.5)))
        alpha = max(0, min(255, int(opacity * fraction + 0.5)))
        output.append((gray, gray, gray, alpha) if alpha else (0, 0, 0, 0))
    require(removed >= key["key_minimum_background_pixels"], "portrait raw has no declared magenta background")
    rgba.putdata(output)
    rgba = rgba.resize(tuple(canvas), Image.Resampling.LANCZOS)
    rgba,alignment = align_fine_part(rgba,row,config,source_sha256)
    alpha = rgba.getchannel("A")
    override = key.get("region_overrides",{}).get(row["id"])
    if override:
        require(source_sha256==override["reviewed_source_sha256"], "processing mask requires review of this exact source")
    mask = checker.processing_mask(config,row)
    if key.get("prevent_core_clipping",False):
        threshold = key["source_core_alpha_threshold"]
        core_outside = sum(a>=threshold and m==0 for a,m in zip(alpha.getdata(),mask.getdata()))
        require(core_outside==0, "source core would be clipped by processing mask; review the actual source region")
    discarded = sum(a > 0 and m == 0 for a, m in zip(alpha.getdata(), mask.getdata()))
    alpha = ImageChops.multiply(alpha, mask)
    rgba.putalpha(alpha)
    rgba.putdata([(r, g, b, a) if a else (0, 0, 0, 0) for r, g, b, a in rgba.getdata()])
    transform = {"method": "full_canvas_magenta_matte_region_grayscale", "source_size": [width, height], "source_crop": [0, 0, width, height],
                 "output_size": canvas, "filter": "Lanczos", "translation_px": [0, 0], "grayscale_method": "mean_rgb",
                 "source_non_gray_foreground_pixels": raw_non_gray, "magenta_removed_pixels": removed, "source_foreground_outside_region_pixels": discarded,
                 "mask_extraction": key["mask_extraction"], "region": row["region"]}
    if key.get("prevent_core_clipping",False):
        transform.update(source_core_outside_region_pixels=core_outside,source_core_alpha_threshold=threshold)
    if override:
        transform["processing_region_override"] = {"method":"exact_source_processing_mask_not_generation_reference","source_sha256":source_sha256,
            "generation_region":row["region"],"processing_region":override["region"],"shape":copy.deepcopy(config["regions"][override["region"]]["shape"]),
            "audit_mask_path":override["audit_mask_path"],"mask_sha256":digest(png(mask)),"isolation_evidence":override["isolation_evidence"]}
    if key.get("version",1) == 2:
        rgba,transform["edge_cleanup"] = clean_matte_edges(rgba,row["category"],config)
    if alignment is not None: transform["fine_alignment"] = alignment
    rgba,visibility = apply_processing_visibility(rgba,row,config,source_sha256)
    if visibility is not None: transform["processing_visibility"] = visibility
    return rgba, transform


def normalize_mannequin(source, config, translation=None):
    width, height = source.size
    canvas = config["canvas"]
    require(width * canvas[1] == height * canvas[0], "mannequin must preserve full-canvas 3:4 aspect")
    translation = translation if translation is not None else [0, 0]
    require(isinstance(translation, list) and len(translation) == 2 and all(type(n) is int for n in translation), "invalid explicit mannequin translation")
    require(abs(translation[0]) < canvas[0] and abs(translation[1]) < canvas[1], "mannequin translation leaves canvas")
    resized = source.convert("RGB").resize(tuple(canvas), Image.Resampling.LANCZOS)
    result = Image.new("RGB", tuple(canvas), tuple(config["processing"]["magenta_rgb"]))
    result.paste(resized, tuple(translation))
    return result, {"method":"full_canvas_resize_translate","source_size":[width,height],"source_crop":[0,0,width,height],
                    "output_size":canvas,"filter":"Lanczos","translation_px":translation,"fill_rgb":config["processing"]["magenta_rgb"],
                    "grayscale_method":"reference_original_rgb_retained","alpha_conversion":"not_applied_to_magenta_reference"}


def process_parts(workspace, generation, revision, only=None, config=None):
    config = validate_config(config or load_config(), workspace)
    require(identifier(revision), "invalid portrait revision")
    validate_generation_receipt(workspace, generation, config)
    wanted = {x["id"] for x in _selected(config, only or [r["id"] for r in generation["records"]])}
    require(wanted <= {r["id"] for r in generation["records"]}, "selected portrait lacks a complete generation record")
    catalog = {x["id"]: x for x in _selected(config, None)}
    prepared = []
    for row in generation["records"]:
        if row["id"] not in wanted: continue
        slot = catalog[row["id"]]
        source = _actual(workspace, row["source_path"])
        image, transform = normalize_mannequin(source, config, row.get("normalization_translation_px")) if row["id"] == "mannequin" else normalize_part(source, slot, config,row["sha256"])
        _check_visibility_reference(workspace,image,transform,config)
        qa = checker.report_image(image, row["id"], config)
        require(qa["passed"], "portrait actual pixel QA failed: " + json.dumps(qa))
        data = png(image)
        path = config["source_root"] + "/processed/" + revision + "/" + row["id"] + ".png"
        prepared.append({"id": row["id"], "category": slot["category"], "part_id": slot["part_id"], "mood": slot["mood"], "path": path,
                         "formal_path": slot["formal_path"], "sha256": digest(data), "size": list(image.size), "source_path": row["source_path"], "source_sha256": row["sha256"],
                         "source_native_size": row["native_size"], "prompt": row["prompt"], "ref_paths": row["ref_paths"], "reference_shas": row["reference_shas"],
                         "mask_path": row["mask_path"], "mask_sha256": row["mask_sha256"], "transform": transform, "qa": qa, "data": data})
    protected = {common.safe_path(workspace, r["source_path"]) for r in generation["records"]}
    protected |= {common.safe_path(workspace, p) for r in generation["records"] for p in r["ref_paths"]}
    protected |= {common.safe_path(workspace,entry["transform"]["processing_visibility"]["preserve_reference_path"]) for entry in prepared
                  if entry["transform"].get("processing_visibility",{}).get("preserve_reference_path")}
    visibility_masks = {}
    for entry in prepared:
        for field in ("processing_visibility","processing_region_override"):
            visibility = entry["transform"].get(field)
            if visibility:
                mask = checker.mask_image({"canvas":config["canvas"],"regions":{"visibility":{"shape":visibility["shape"]}}},"visibility")
                file = common.safe_path(workspace,visibility["audit_mask_path"]);data = png(mask)
                require(file not in protected and (not file.exists() or file.read_bytes()==data), "processing audit mask is immutable/protected")
                require(file not in visibility_masks or visibility_masks[file]==data, "processing audit masks cannot disagree at one path")
                visibility_masks[file] = data
    for entry in prepared:
        file = common.safe_path(workspace, entry["path"])
        require(file not in protected and (not file.exists() or file.read_bytes() == entry["data"]), "portrait output is immutable/protected")
    for file,data in visibility_masks.items(): common._write_new(file,data)
    for entry in prepared: common._write_new(common.safe_path(workspace, entry["path"]), entry.pop("data"))
    return {"version": 1, "kind": "portrait_processing_receipt", "revision": revision, "entries": prepared,
            "config_digest": config_digest(config), "processing_script": SCRIPT, "selected_mannequin": copy.deepcopy(config["mannequin"]),
            "processing_config": copy.deepcopy(config),
            "generation_receipt": copy.deepcopy(generation),
            "style_reference": copy.deepcopy(config["style_reference"]), "generation_performed": False, "art_passed": False,
            "note": "仅技术归一化/像素QA；产物留incoming，主parts status与formal选择由实际人工审图后处理。"}


def validate_processing_receipt(workspace, receipt, config=None):
    config = validate_config(config or load_config(), workspace)
    require(isinstance(receipt, dict) and receipt.get("kind") == "portrait_processing_receipt" and receipt.get("config_digest") == config_digest(config), "portrait processing receipt/config mismatch")
    generation = validate_generation_receipt(workspace, receipt.get("generation_receipt"), config)
    source_rows = {r["id"]: r for r in generation["records"]}
    catalog = {r["id"]: r for r in _selected(config, None)}
    seen = set()
    for entry in receipt.get("entries", []):
        require(entry.get("id") in source_rows and entry["id"] not in seen, "unknown/duplicate processed portrait")
        seen.add(entry["id"])
        source = source_rows[entry["id"]]
        require(entry.get("source_path") == source["source_path"] and entry.get("source_sha256") == source["sha256"] and
                entry.get("source_native_size") == source["native_size"] and all(entry.get(k) == source.get(k) for k in
                ("prompt", "ref_paths", "reference_shas", "mask_path", "mask_sha256")), "processed portrait source provenance mismatch")
        raw = _actual(workspace, source["source_path"])
        expected, transform = normalize_mannequin(raw, config, source.get("normalization_translation_px")) if entry["id"] == "mannequin" else normalize_part(raw, catalog[entry["id"]], config,source["sha256"])
        _check_visibility_reference(workspace,expected,transform,config)
        require(entry.get("sha256") == digest(png(expected)) and entry.get("transform") == transform, "portrait actual normalization differs from processing receipt")
        if transform.get("processing_region_override"):
            processing_mask = transform["processing_region_override"]
            _actual(workspace,processing_mask["audit_mask_path"],processing_mask["mask_sha256"],config["canvas"])
        if transform.get("processing_visibility"):
            visibility = transform["processing_visibility"]
            _actual(workspace,visibility["audit_mask_path"],visibility["mask_sha256"],config["canvas"])
            if visibility.get("row_validation_scope"):
                scope = visibility["row_validation_scope"]
                _actual(workspace,scope["occluder_path"],scope["occluder_sha256"],config["canvas"])
        _actual(workspace, entry["path"], entry["sha256"], config["canvas"])
        require(checker.check_part(workspace, entry["id"], entry["path"], config)["passed"], "processed portrait no longer passes actual pixel QA")
    return receipt


def build_manifest_fragment(workspace, receipt, config=None, *, encoding_templates=None):
    config = validate_config(config or load_config(), workspace)
    validate_processing_receipt(workspace, receipt, config)
    encoding_templates = encoding_templates if encoding_templates is not None else {
        key:value for key,value in config["generation"]["templates"].items() if key.startswith("manifest_")}
    require(isinstance(encoding_templates,dict) and all(isinstance(key,str) and identifier(key) and isinstance(value,str) and value.strip()
            for key,value in encoding_templates.items()), "invalid output-only portrait encoding templates")
    rows, pending, templates = [], [], {}
    known = {x["id"]: x for x in _selected(config, None)}
    for entry in receipt.get("entries", []):
        require(entry.get("id") in known, "unknown processed portrait ID")
        slot = known[entry["id"]]
        _actual(workspace, entry["path"], entry["sha256"], config["canvas"])
        formal = common.safe_path(workspace, slot["formal_path"])
        if not formal.is_file():
            pending.append({"id": entry["id"], "reason": "awaiting_formal_selection", "staged_path": entry["path"], "proposed_path": slot["formal_path"]})
            continue
        if common.sha256(formal) != entry["sha256"]:
            pending.append({"id":entry["id"],"reason":"formal_path_immutable_select_new_revision","staged_path":entry["path"],"existing_path":slot["formal_path"]})
            continue
        _actual(workspace, slot["formal_path"], entry["sha256"], config["canvas"])
        require(checker.check_part(workspace, entry["id"], slot["formal_path"], config)["passed"], "formal portrait pixel QA failed")
        planned, params = render_prompt(slot, config)
        template,template_key = _prompt_definition(slot,config)
        output_only = False
        primary_matches = isinstance(planned,str) and entry["prompt"].count(planned)==1
        for key,candidate in encoding_templates.items():
            marker = "{actual_middle}"
            if primary_matches and marker not in candidate: continue
            candidate_params = dict(params)
            try:
                if marker in candidate:
                    bounded = candidate.format(**{**params,"actual_middle":marker})
                    if bounded.count(marker)!=1: continue
                    head,tail = bounded.split(marker)
                    if not head or not tail or not entry["prompt"].startswith(head) or not entry["prompt"].endswith(tail): continue
                    if entry["prompt"].count(head)!=1 or entry["prompt"].count(tail)!=1: continue
                    candidate_params["actual_middle"] = entry["prompt"][len(head):-len(tail)]
                actual_candidate = candidate.format(**candidate_params)
            except (KeyError,IndexError,TypeError,ValueError): continue
            if actual_candidate and entry["prompt"].count(actual_candidate)==1:
                planned,template,params = actual_candidate,candidate,candidate_params
                template_key = "A4_"+key+"_"+digest(candidate.encode("utf-8"))[:12]
                output_only = True
                break
        if planned == entry["prompt"] or isinstance(planned,str) and entry["prompt"].count(planned)==1:
            for key in ("width", "height", "center_x", "eye_y", "shoulder_y"):
                template = template.replace("{" + key + "}", str(params.pop(key)))
            if output_only:
                params = {key:value for key,value in params.items() if "{"+key+"}" in template}
            if planned != entry["prompt"]:
                prefix,suffix = entry["prompt"].split(planned,1)
                # Values are inserted once; literal braces in actual annotations
                # must never be reformatted or rewritten as rig constants.
                template = "{actual_prefix}"+template+"{actual_suffix}"
                template_key = "A4_wrapped_"+digest(template.encode("utf-8"))[:16]
                params.update(actual_prefix=prefix,actual_suffix=suffix)
            require(template.format(**params) == entry["prompt"], "compact portrait prompt does not reproduce actual generation")
            require(template_key not in templates or templates[template_key]==template, "portrait compact template key collision")
            templates[template_key] = template
        else:
            template_key = "A4_actual_" + digest(entry["prompt"].encode("utf-8"))[:16]
            templates[template_key] = entry["prompt"].replace("{", "{{").replace("}", "}}")
            params = {}
        rows.append({"path": slot["formal_path"], "sha256": entry["sha256"], "dim": config["canvas"], "group": "portraits", "art_pack": "A4_v3",
                     "operation": "portrait_mannequin" if entry["id"] == "mannequin" else "portrait_part", "part_id": slot["part_id"], "category": slot["category"], "mood": slot["mood"], "portrait_asset_id": entry["id"],
                     "prompt_template": template_key, "prompt_params": params, "actual_prompt_sha256":digest(entry["prompt"].encode("utf-8")), "source_raw": entry["source_path"], "source_raw_sha256": entry["source_sha256"],
                     "source_raw_native_size": entry["source_native_size"], "inputs": entry["ref_paths"], "mask_path": entry["mask_path"], "mask_sha256": entry["mask_sha256"],
                     "processing_script": SCRIPT, "local_config": "data/art/portrait_pipeline.json", "processing_config_digest":receipt["config_digest"]})
        processing_mask = entry["transform"].get("processing_region_override")
        if processing_mask:
            rows[-1].update(processing_mask_path=processing_mask["audit_mask_path"],processing_mask_sha256=processing_mask["mask_sha256"])
    fragment = {"version": 1, "kind": "portrait_manifest_fragment", "assets": rows, "pending": pending,
                "templates": templates, "manifest_modified": False, "art_passed": False}
    fragment["budget"] = manifest_budget(workspace, fragment, config)
    require(fragment["budget"]["within_limit"], "proposed compact manifest exceeds configured byte budget")
    return fragment


def proposed_manifest(workspace, fragment):
    """Merge and losslessly pack a review candidate without changing inputs.

    Existing shared profiles must be expanded before they are rebuilt: a partial
    replacement can leave other formal rows referring to the same profile.
    """
    file = common.safe_path(workspace, "assets/ART_ASSET_MANIFEST.json")
    base = common.read_json(file) if file.is_file() else {"schema_version":3,"assets":[],"style_profiles":{"v3":{}}}
    merged = copy.deepcopy(base)
    by_path = {row["path"]: row for row in merged["assets"]}
    by_path.update({row["path"]: copy.deepcopy(row) for row in fragment["assets"]})
    merged["assets"] = list(by_path.values())
    merged.setdefault("style_profiles",{}).setdefault("v3",{}).setdefault("templates",{}).update(copy.deepcopy(fragment["templates"]))
    expected = common.expand_compact_metadata(merged)
    packed = common.compact_formal_metadata(merged)
    require(common.expand_compact_metadata(packed) == expected, "portrait packing changed formal provenance")
    return packed


def _manifest_bytes(manifest):
    return (json.dumps(manifest,ensure_ascii=False,separators=(",",":"),allow_nan=False)+"\n").encode("utf-8")


def manifest_budget(workspace, fragment, config):
    file = common.safe_path(workspace, "assets/ART_ASSET_MANIFEST.json")
    merged = proposed_manifest(workspace,fragment)
    compact = lambda value: json.dumps(value,ensure_ascii=False,separators=(",",":"),allow_nan=False)
    size = len(_manifest_bytes(merged))
    pretty_size = len((json.dumps(merged,ensure_ascii=False,indent=2,allow_nan=False)+"\n").encode("utf-8"))
    asset_lines = "{\n" + ",\n".join(compact(key)+":"+("[\n"+",\n".join(compact(row) for row in value)+"\n]" if key=="assets" else compact(value)) for key,value in merged.items()) + "\n}\n"
    return {"proposed_bytes":size,"encoding":"utf8_compact_separators_comma_colon_final_lf","pretty_bytes":pretty_size,
            "asset_per_line_bytes":len(asset_lines.encode("utf-8")),"limit_bytes":config["maximum_manifest_bytes"],"within_limit":size<=config["maximum_manifest_bytes"],
            "current_manifest_bytes":file.stat().st_size if file.is_file() else None,"asset_count":len(merged["assets"])}


def selected_mannequin_fragment(workspace, config=None):
    """Register the already selected initial reference using its actual manual prompt."""
    config = validate_config(config or load_config(), workspace)
    base = config["mannequin"]
    require(not _baseline_pending(workspace, config, config["style_reference"]["path"],require_origin=True), "selected mannequin evidence is missing")
    history = common.read_json(common.safe_path(workspace, base["generation_receipt"], must_exist=True))
    attempts = history.get("prompts")
    require(isinstance(attempts,list) and 1 <= len(attempts) <= config["maximum_generation_attempts"], "selected initial mannequin lacks actual attempts")
    selected = [a for a in attempts if a.get("attempt") == base["selected_attempt"]]
    require(len(selected)==1 and isinstance(selected[0].get("prompt"),str) and selected[0]["prompt"].strip() and isinstance(selected[0].get("ref_paths"),list), "selected mannequin actual prompt/input roles missing")
    actual = selected[0]
    for path in actual["ref_paths"]: _actual(workspace,path)
    template_key = "A4_actual_"+digest(actual["prompt"].encode("utf-8"))[:16]
    row={"path":base["path"],"sha256":base["sha256"],"dim":config["canvas"],"group":"portraits","art_pack":"A4_v3",
         "operation":"portrait_mannequin","portrait_asset_id":"mannequin","category":"mannequin","part_id":None,"mood":"neutral",
         "prompt_template":template_key,"prompt_params":{},"actual_prompt_sha256":digest(actual["prompt"].encode("utf-8")),
         "source_raw":base["source_path"],"source_raw_sha256":base["source_sha256"],"source_raw_native_size":base["source_native_size"],
         "inputs":actual["ref_paths"],"input_sha256":{p:common.sha256(common.safe_path(workspace,p,must_exist=True)) for p in actual["ref_paths"]},
         "source_generation_receipt":base["generation_receipt"],"source_generation_receipt_sha256":base["generation_receipt_sha256"],
         "normalization_transform":base["transform"],"processing_script":SCRIPT,"local_config":"data/art/portrait_pipeline.json",
         "reference_background":"magenta","is_transparent_part":False}
    fragment={"version":1,"kind":"portrait_manifest_fragment","assets":[row],"templates":{template_key:actual["prompt"].replace("{","{{").replace("}","}}")},
              "pending":[],"manifest_modified":False,"art_passed":False,"selected_attempt":base["selected_attempt"],
              "selection_evidence":"configured selected reference; exact native resize/translation reconstructed independently"}
    fragment["budget"]=manifest_budget(workspace,fragment,config)
    require(fragment["budget"]["within_limit"],"selected mannequin manifest budget exceeded")
    return fragment


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("masks", "queue", "process", "fragment", "selected-mannequin", "proposal"))
    parser.add_argument("--workspace", default=str(ROOT))
    parser.add_argument("--config", default="data/art/portrait_pipeline.json")
    parser.add_argument("--revision", default="v3r1")
    parser.add_argument("--mask-revision")
    parser.add_argument("--attempt",type=int,default=1)
    parser.add_argument("--pilot",action="store_true")
    parser.add_argument("--only")
    parser.add_argument("--style")
    parser.add_argument("--receipt")
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    try:
        config = load_config(common.safe_path(args.workspace, args.config, must_exist=True), args.workspace)
        output = common.safe_path(args.workspace, args.output)
        require(args.output.endswith(".json") and (args.output.startswith(config["source_root"] + "/") or args.output.startswith(".tools/")), "portrait audit output must be a local/incoming JSON")
        require(not output.exists(), "audit output already exists; choose a new path")
        require(args.output != args.config and args.output != args.receipt, "audit output cannot replace an input")
        selected = args.only.split(",") if args.only else None
        if args.operation == "masks": result = prepare_masks(args.workspace, args.revision, selected, config)
        elif args.operation == "queue": result = build_queue(args.workspace, args.revision, selected, args.style, config,mask_revision=args.mask_revision,attempt=args.attempt,pilot=args.pilot)
        elif args.operation == "selected-mannequin": result = selected_mannequin_fragment(args.workspace,config)
        elif args.operation == "proposal":
            fragment = common.read_json(common.safe_path(args.workspace,args.receipt,must_exist=True))
            require(isinstance(fragment,dict) and fragment.get("version") == 1 and fragment.get("kind") == "portrait_manifest_fragment", "expected a portrait manifest fragment")
            result = proposed_manifest(args.workspace,fragment)
        else:
            receipt = common.read_json(common.safe_path(args.workspace, args.receipt, must_exist=True))
            result = process_parts(args.workspace, receipt, args.revision, selected, config) if args.operation == "process" else build_manifest_fragment(args.workspace, receipt, config)
        encoded = _manifest_bytes(result) if args.operation == "proposal" else (json.dumps(result, ensure_ascii=False, indent=2,allow_nan=False) + "\n").encode("utf-8")
        if args.operation == "proposal":
            require(len(encoded) <= config["maximum_manifest_bytes"], "proposed compact manifest exceeds configured byte budget")
        common._write_new(output,encoded)
        summary = {"output": args.output, "status": result.get("status"), "entries": len(result.get("entries", [])), "tasks": len(result.get("tasks", [])), "art_passed": False}
        if args.operation == "proposal":
            summary.update(status="proposal",assets=len(result["assets"]),proposed_bytes=len(encoded),manifest_modified=False)
        print(json.dumps(summary))
        return 0
    except (ValueError, OSError) as error:
        print(json.dumps({"error": str(error), "generation_performed": False}, ensure_ascii=False))
        return 2


if __name__ == "__main__": raise SystemExit(main())
