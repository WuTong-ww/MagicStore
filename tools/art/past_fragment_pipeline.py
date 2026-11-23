"""Fresh builtin-only memory art and measured, immutable local cover candidates."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import art_pipeline as common
CONFIG = "data/art/past_fragment_pipeline.json"
SCRIPT = "tools/art/past_fragment_pipeline.py"
need = common._require


def validate_config(value):
    need(isinstance(value, dict) and type(value.get("version")) is int and value["version"] == 1, "invalid past art config")
    for field, prefix in (("source_root", "assets/_incoming/"), ("formal_root", "assets/past_lives/")):
        common.safe_path(ROOT, value.get(field)); need(value[field].startswith(prefix), "invalid past art root")
    size = value.get("runtime_size")
    need(isinstance(size, list) and len(size) == 2 and all(common._integer(n, 1) for n in size), "invalid runtime size")
    need(common._integer(value.get("maximum_generation_attempts"), 1, 4) and common._integer(value.get("processing_version"), 1), "invalid past processing limits")
    ref = value.get("style_reference", {}); common.safe_path(ROOT, ref.get("path"))
    need(isinstance(ref.get("sha256"), str) and re.fullmatch(r"[a-f0-9]{64}", ref["sha256"]), "invalid style SHA")
    generation = value.get("generation", {})
    need(generation.get("tool") == "image_gen.imagegen" and all(isinstance(generation.get(k), str) and generation[k].strip() for k in ("template", "target_size_prompt")), "invalid builtin generation recipe")
    need("{setting}" in generation["template"], "missing setting placeholder")
    try: generation["template"].format(setting="test")
    except (KeyError, ValueError, IndexError) as error: raise ValueError("invalid past prompt template") from error
    eras = value.get("eras")
    need(isinstance(eras, list) and len(eras) == 3 and all(isinstance(e, dict) and isinstance(e.get("setting"), str) and e["setting"].strip() for e in eras) and
         [e.get("id") for e in eras] == ["era1", "era2", "era3"], "require exactly the three ordered eras")
    return value


def load_config(workspace):
    return validate_config(common.read_json(common.safe_path(workspace, CONFIG, must_exist=True)))


def _style(workspace, ref):
    file = common.safe_path(workspace, ref["path"], must_exist=True)
    common.read_image(file); need(common.sha256(file) == ref["sha256"], "past style SHA mismatch")
    return file


def _revision(value):
    need(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", value), "invalid revision")


def build_queue(workspace, revision, config=None, style_reference=None, records=None, templates=None):
    config = validate_config(config) if config is not None else load_config(workspace)
    _revision(revision); ref = style_reference or config["style_reference"]; file = _style(workspace, ref)
    previous = {row["era_id"]:row for row in (records or [])}
    need(len(previous) == len(records or []), "duplicate formal past era")
    tasks, offline = [], []
    for era in config["eras"]:
        identifier = era["id"]; row = previous.get(identifier)
        if records is not None and not row: continue
        prompt = config["generation"]["template"].format(setting=era["setting"]) + "\n" + config["generation"]["target_size_prompt"]
        missing = []
        if row:
            try: prompt = templates[row["prompt_template"]].format(**row["prompt_params"])
            except (KeyError, ValueError, TypeError, IndexError) as error: raise ValueError("missing exact past prompt recipe") from error
            need(hashlib.sha256(prompt.encode()).hexdigest() == row["actual_prompt_sha256"], "past actual prompt SHA mismatch")
            old = common.safe_path(workspace, row["path"])
            if old.is_file(): need(common.sha256(old) == row["sha256"] and list(common.read_image(old).size) == row["dim"], "past formal source SHA/size mismatch")
            else: missing.append(row["path"])
        source = f"{config['source_root']}/{revision}/{identifier}_source_attempt1.png"
        need(not common.safe_path(workspace, source).exists(), "select a fresh generation revision")
        task = {"id":identifier,"recipe_id":"G5_"+identifier,"group":"past_fragments","operation":"generate","tool":config["generation"]["tool"],
                "version":revision,"source_destination":source,"depends_on":[],"missing_dependencies":[],"missing_previous_inputs":missing,
                "ready":True,"can_generate":True,"status":"needs_builtin_generation","attempts_used":0,"maximum_attempts":config["maximum_generation_attempts"],
                "style_reference":ref["path"],"style_sha256":ref["sha256"],
                "arguments":{"prompt":prompt,"referenced_image_paths":[str(file)],"transparent_background":False}}
        if row: task.update(previous_source_path=row["path"], previous_source_sha256=row["sha256"])
        tasks.append(task)
        offline.append({"operation":"runtime_copy","performed_with":"past_fragment_process","era_id":identifier,"source_path":source,
                        "source_destination":f"{config['source_root']}/{revision}/processed/{identifier}.png","depends_on":[source],"runtime_size":config["runtime_size"],
                        "processing_script":SCRIPT,"local_config":CONFIG,"can_process":False,
                        "command_after_generation":["python",SCRIPT,"process","--workspace",str(Path(workspace).resolve()),"--receipt",f"{config['source_root']}/{revision}/generation_receipt.json","--revision",revision,"--output",f".tools/g5/{revision}-processing.json"]})
    return {"version":1,"kind":"past_fragment_builtin_queue","status":"needs_builtin_generation","style_profile":"v3","active_style":copy.deepcopy(ref),
            "tasks":tasks,"offline_tasks":offline,"generation_performed":False,"manifest_modified":False,"art_passed":False,"canonical_resource_count":len(tasks)}


def _selected(workspace, receipt, config):
    need(isinstance(receipt, dict) and receipt.get("version") == 1 and receipt.get("kind") == "past_fragment_generation", "invalid actual generation receipt")
    records = receipt.get("records"); ids = [e["id"] for e in config["eras"]]
    need(isinstance(records, list) and sorted(r.get("id", "") for r in records if isinstance(r, dict)) == sorted(ids), "receipt requires all three unique eras")
    result = {}
    for record in records:
        attempts = record.get("attempts")
        need(isinstance(attempts, list) and 1 <= len(attempts) <= config["maximum_generation_attempts"] and
             all(isinstance(a,dict) and type(a.get("attempt_number")) is int for a in attempts) and
             [a.get("attempt_number") for a in attempts] == list(range(1,len(attempts)+1)), "incomplete actual attempt history")
        chosen = record.get("selected_attempt"); need(common._integer(chosen,1,len(attempts)), "invalid selected attempt")
        for attempt in attempts:
            need(attempt.get("tool") == config["generation"]["tool"] and isinstance(attempt.get("actual_prompt"),str) and attempt["actual_prompt"].strip(), "missing actual builtin prompt")
            need(attempt.get("inputs") == [] and attempt.get("references") == [config["style_reference"]], "fresh generation must use only the exact style reference")
            if attempt.get("status") == "failed":
                need(isinstance(attempt.get("error"),str) and attempt["error"].strip(), "failed attempt needs actual error"); continue
            need(attempt.get("status") == "generated", "unknown attempt status")
            source = common.safe_path(workspace, attempt.get("source_path"), must_exist=True)
            need(attempt["source_path"].startswith(config["source_root"]+"/"), "raw must remain in configured incoming root")
            need(common.sha256(source) == attempt.get("source_sha256") and list(common.read_image(source).size) == attempt.get("source_native_size"), "actual raw SHA/native dimensions mismatch")
        selected = attempts[chosen-1]; need(selected["status"] == "generated", "selected attempt did not generate")
        result[record["id"]] = selected
    return result


def process_receipt(workspace, generation_receipt, revision, config=None):
    config = validate_config(config) if config is not None else load_config(workspace)
    _revision(revision); _style(workspace,config["style_reference"])
    selected = _selected(workspace,generation_receipt,config)
    assets, aliases, templates, files, payloads = [], [], {}, [], []
    for era in config["eras"]:
        identifier = era["id"]; attempt = selected[identifier]
        source = common.safe_path(workspace,attempt["source_path"],must_exist=True); raw = source.read_bytes()
        image = common.read_image(source); width,height=image.size; out_width,out_height=config["runtime_size"]
        scale=max(out_width/width,out_height/height); crop_width,crop_height=out_width/scale,out_height/scale
        crop=[(width-crop_width)/2,(height-crop_height)/2,(width+crop_width)/2,(height+crop_height)/2]
        runtime=image.convert("RGB").resize((out_width,out_height),Image.Resampling.LANCZOS,box=tuple(crop)); data=common._png(runtime)
        native=f"{config['formal_root']}/{identifier}_native.png"; target=f"{config['formal_root']}/{identifier}.png"
        sha=hashlib.sha256(raw).hexdigest(); runtime_sha=hashlib.sha256(data).hexdigest(); prompt_sha=hashlib.sha256(attempt["actual_prompt"].encode()).hexdigest()
        key="G5_past_"+identifier+"_"+prompt_sha[:12]; templates[key]=attempt["actual_prompt"].replace("{","{{").replace("}","}}")
        assets.append({"path":native,"dim":[width,height],"sha256":sha,"group":"past_fragments","operation":"past_fragment_native","version":3,"era_id":identifier,
                       "prompt_template":key,"prompt_params":{},"actual_prompt_sha256":prompt_sha,"inputs":[],"references":[config["style_reference"]["path"]],
                       "reference_sha256":config["style_reference"]["sha256"],"source_raw":attempt["source_path"],"source_raw_sha256":sha,
                       "source_raw_native_size":[width,height],"processing_script":SCRIPT,"processing_version":config["processing_version"],"local_config":CONFIG})
        transform={"method":"equal_aspect_cover","filter":"Lanczos","scale":scale,"source_crop":crop,"runtime_size":list(runtime.size)}
        aliases.append({"path":target,"source_path":native,"native_size":[width,height],"runtime_size":list(runtime.size),"source_sha256":sha,"sha256":runtime_sha,
                        "scale_x":scale,"scale_y":scale,"transform":transform,"processing_script":SCRIPT,"processing_version":config["processing_version"]})
        for formal,png,dim in ((native,raw,[width,height]),(target,data,list(runtime.size))):
            candidate=f"{config['source_root']}/{revision}/processed/"+Path(formal).name
            file=common.safe_path(workspace,candidate); need(not file.exists() or file.read_bytes()==png,"immutable candidate already differs")
            files.append({"candidate_path":candidate,"formal_path":formal,"sha256":hashlib.sha256(png).hexdigest(),"dim":dim}); payloads.append((file,png))
    for file,payload in payloads: common._write_new(file,payload)
    return {"version":1,"kind":"past_fragment_processing_receipt","revision":revision,"art_passed":False,"manifest_modified":False,"visual_review":"not_evaluated",
            "generation_audit":copy.deepcopy(generation_receipt),"candidate_files":files,"manifest_fragment":{"assets":assets,"runtime_copies":aliases,"templates":templates}}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("operation",choices=("queue","process"));parser.add_argument("--workspace",default=str(ROOT))
    parser.add_argument("--revision",required=True);parser.add_argument("--receipt");parser.add_argument("--output",required=True);args=parser.parse_args()
    try:
        output=common.safe_path(args.workspace,args.output)
        need(args.output.startswith((".tools/","assets/_incoming/")) and args.output.endswith(".json") and not output.exists(),"output must be a fresh local JSON proposal")
        if args.operation=="queue": result=build_queue(args.workspace,args.revision)
        else:
            receipt=common.read_json(common.safe_path(args.workspace,args.receipt,must_exist=True)); result=process_receipt(args.workspace,receipt,args.revision)
        common._write_new(output,(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+"\n").encode())
        print(json.dumps({"output":args.output,"art_passed":False,"manifest_modified":False}));return 0
    except (ValueError,OSError,KeyError,TypeError)as error: print("PAST ART ERROR: "+str(error),file=sys.stderr);return 1

if __name__=="__main__":raise SystemExit(main())
