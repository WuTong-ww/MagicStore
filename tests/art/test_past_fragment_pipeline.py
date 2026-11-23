"""Fresh past-memory art has exact provenance and measured runtime cover."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
def load(name, file):
    spec=importlib.util.spec_from_file_location(name,file); value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
common=load("past_test_common",ROOT/"tools/art_pipeline.py")

class PastFragmentTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.style="assets/styles/selected.png";self.image(self.style,(32,18))
        self.config={"version":1,"source_root":"assets/_incoming/g5_v3","formal_root":"assets/past_lives/v3",
          "runtime_size":[1920,1080],"maximum_generation_attempts":4,"processing_version":1,
          "style_reference":{"path":self.style,"sha256":common.sha256(self.root/self.style)},
          "generation":{"tool":"image_gen.imagegen","template":"Opaque poster colors, {setting}. No text. Style only.","target_size_prompt":"Actual maximum native landscape16:9."},
          "eras":[{"id":"era"+str(i),"setting":"authored ancient setting "+str(i)}for i in range(1,4)]}
        p=self.root/"data/art/past_fragment_pipeline.json";p.parent.mkdir(parents=True);p.write_text(json.dumps(self.config))
        self.manifest={"schema_version":3,"assets":[],"runtime_copies":[],"style_profiles":{"v3":{"status":"selected","reference":self.config["style_reference"],"revision":"g5test","templates":{}}}}
    def image(self,path,size):
        p=self.root/path;p.parent.mkdir(parents=True,exist_ok=True);Image.new("RGB",size,(80,100,120)).save(p)
    def pipeline(self):
        path=ROOT/"tools/art/past_fragment_pipeline.py"
        self.assertTrue(path.is_file(),"past fragment pipeline missing")
        return load("past_pipeline_under_test",path)
    def receipt(self,pipeline):
        queue=pipeline.build_queue(self.root,"test1",self.config)
        records=[]
        for index,task in enumerate(queue["tasks"]):
            raw=f"assets/_incoming/g5_v3/test1/{task['id']}_attempt1.png";self.image(raw,(400+index,225))
            records.append({"id":task["id"],"selected_attempt":1,"attempts":[{"attempt_number":1,"status":"generated","tool":"image_gen.imagegen","actual_prompt":task["arguments"]["prompt"],"inputs":[],"references":[self.config["style_reference"]],"source_path":raw,"source_sha256":common.sha256(self.root/raw),"source_native_size":[400+index,225]}]})
        return {"version":1,"kind":"past_fragment_generation","records":records}
    def test_compact_regeneration_has_three_fresh_style_only_tasks_not_scene_edits(self):
        queue=common.build_queue(self.root,self.manifest,"v3","past_fragments")
        self.assertEqual(len(queue["tasks"]),3);self.assertEqual(len(queue["offline_tasks"]),3)
        for task in queue["tasks"]:
            self.assertEqual(task["arguments"]["referenced_image_paths"],[str(common.safe_path(self.root,self.style))])
            self.assertEqual(task["depends_on"],[]);self.assertFalse(task["arguments"]["transparent_background"])
        self.assertFalse(queue["generation_performed"])
    def test_config_rejects_unsafe_paths_bad_dimensions_and_duplicate_eras(self):
        p=self.pipeline()
        for kind in ("path","dimension","duplicate","attempts"):
            config=copy.deepcopy(self.config)
            if kind=="path":config["formal_root"]="../escape"
            elif kind=="dimension":config["runtime_size"]=[True,1080]
            elif kind=="duplicate":config["eras"][1]["id"]="era1"
            else:config["maximum_generation_attempts"]=5
            with self.subTest(kind=kind),self.assertRaises(ValueError):p.validate_config(config)
    def test_measured_cover_receipt_three_native_rows_and_three_aliases(self):
        p=self.pipeline();receipt=self.receipt(p);before=copy.deepcopy(receipt)
        result=p.process_receipt(self.root,receipt,"test1",self.config)
        self.assertEqual(receipt,before);self.assertFalse(result["art_passed"]);self.assertFalse(result["manifest_modified"])
        fragment=result["manifest_fragment"];self.assertEqual(len(fragment["assets"]),3);self.assertEqual(len(fragment["runtime_copies"]),3)
        for row,alias in zip(fragment["assets"],fragment["runtime_copies"]):
            self.assertEqual(row["group"],"past_fragments");self.assertEqual(alias["source_path"],row["path"])
            self.assertEqual(alias["runtime_size"],[1920,1080]);self.assertEqual(alias["native_size"],row["dim"])
            self.assertEqual(alias["transform"]["filter"],"Lanczos")
            self.assertAlmostEqual(alias["transform"]["scale"],max(1920/row["dim"][0],1080/row["dim"][1]))
            text=fragment["templates"][row["prompt_template"]].format(**row["prompt_params"])
            self.assertEqual(hashlib.sha256(text.encode()).hexdigest(),row["actual_prompt_sha256"])
            self.assertFalse((self.root/row["path"]).exists(),"processing cannot silently promote formal art")
        self.assertEqual(len(result["candidate_files"]),6)
        for candidate in result["candidate_files"]:self.assertEqual(common.sha256(self.root/candidate["candidate_path"]),candidate["sha256"])
    def test_corrupt_or_incomplete_history_rejects_before_any_candidate_write(self):
        p=self.pipeline();base=self.receipt(p)
        for kind in ("sha","native_size","reference","gap","tool","prompt","inputs"):
            receipt=copy.deepcopy(base);a=receipt["records"][0]["attempts"][0]
            if kind=="sha":a["source_sha256"]="0"*64
            elif kind=="native_size":a["source_native_size"]=[1,1]
            elif kind=="reference":a["references"][0]["sha256"]="0"*64
            elif kind=="gap":a["attempt_number"]=2;receipt["records"][0]["selected_attempt"]=2
            elif kind=="tool":a["tool"]="fake_cli"
            elif kind=="prompt":a["actual_prompt"]=""
            else:a["inputs"]=["assets/old_scene.png"]
            with self.subTest(kind=kind),self.assertRaises(ValueError):p.process_receipt(self.root,receipt,"test1",self.config)
            self.assertFalse((self.root/"assets/_incoming/g5_v3/test1/processed").exists())
    def test_formal_queue_reuses_exact_actual_prompt_and_checks_present_source(self):
        p=self.pipeline();processed=p.process_receipt(self.root,self.receipt(p),"test1",self.config)
        fragment=processed["manifest_fragment"];manifest=copy.deepcopy(self.manifest);manifest["assets"]=fragment["assets"];manifest["runtime_copies"]=fragment["runtime_copies"]
        manifest["style_profiles"]["v3"]["templates"].update(fragment["templates"])
        queue=common.build_queue(self.root,manifest,"v3","past_fragments")
        self.assertEqual(len(queue["tasks"]),3);self.assertEqual(len(queue["offline_tasks"]),3)
        for task,row in zip(queue["tasks"],fragment["assets"]):
            self.assertEqual(hashlib.sha256(task["arguments"]["prompt"].encode()).hexdigest(),row["actual_prompt_sha256"])
            self.assertEqual(task["missing_previous_inputs"],[row["path"]])
        first=fragment["assets"][0];self.image(first["path"],(16,9))
        with self.assertRaises(ValueError):common.build_queue(self.root,manifest,"v3","past_fragments")
    def test_formal_native_cannot_disagree_with_its_original_raw_provenance(self):
        p=self.pipeline();fragment=p.process_receipt(self.root,self.receipt(p),"test1",self.config)["manifest_fragment"]
        manifest=copy.deepcopy(self.manifest);manifest["assets"]=fragment["assets"];manifest["runtime_copies"]=fragment["runtime_copies"]
        manifest["style_profiles"]["v3"]["templates"].update(fragment["templates"])
        for kind in ("raw_sha","raw_size","processing_version"):
            value=copy.deepcopy(manifest);row=value["assets"][0]
            if kind=="raw_sha":row["source_raw_sha256"]="0"*64
            elif kind=="raw_size":row["source_raw_native_size"]=[1,1]
            else:row["processing_version"]="1"
            with self.subTest(kind=kind),self.assertRaises(ValueError):common.validate_compact_manifest(self.root,value)
    def test_actual_prompt_literal_braces_roundtrip_without_rewriting_audit(self):
        p=self.pipeline();receipt=self.receipt(p)
        for record in receipt["records"]:record["attempts"][0]["actual_prompt"]+=' Keep {old mark} blank; {"contrast":"cool"}; literal {{mark}}.'
        before=copy.deepcopy(receipt);fragment=p.process_receipt(self.root,receipt,"test1",self.config)["manifest_fragment"]
        manifest=copy.deepcopy(self.manifest);manifest["assets"]=fragment["assets"];manifest["runtime_copies"]=fragment["runtime_copies"]
        manifest["style_profiles"]["v3"]["templates"].update(fragment["templates"])
        queue=common.build_queue(self.root,manifest,"v3","past_fragments")
        self.assertEqual([t["arguments"]["prompt"] for t in queue["tasks"]],[r["attempts"][0]["actual_prompt"]for r in receipt["records"]])
        self.assertEqual(receipt,before)
    def test_attempt_number_boolean_cannot_impersonate_integer_one(self):
        p=self.pipeline();receipt=self.receipt(p)
        receipt["records"][0]["attempts"][0]["attempt_number"]=True
        with self.assertRaises(ValueError):p.process_receipt(self.root,receipt,"test1",self.config)
        self.assertFalse((self.root/"assets/_incoming/g5_v3/test1/processed").exists())

if __name__=="__main__":unittest.main()
