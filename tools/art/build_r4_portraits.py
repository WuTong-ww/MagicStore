"""Register selected v3 accessory paintings and fit them to native face anchors.

Generation is external (image_gen); this deterministic step only removes faint
alpha specks, resamples and mounts the selected transparent sprites. Raw
generations stay ignored. Never changes saved identity part IDs or the old PNGs.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
ANCHORS = {
    "face_01": [[398,129],[236,404],[563,400],[386,754],[387,592]],
    "face_02": [[398,126],[236,404],[561,400],[386,754],[387,594]],
    "face_03": [[398,130],[238,404],[560,400],[386,754],[390,592]],
    "face_04": [[398,129],[236,404],[558,400],[386,754],[390,596]],
    "face_05": [[398,130],[236,403],[562,399],[386,754],[389,594]],
    "face_06": [[397,130],[232,408],[560,403],[386,754],[388,598]],
}
KEYS = ("crown", "ear_l", "ear_r", "neck_base", "chin")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def clean(path):
    image = Image.open(path).convert("RGBA")
    pixels = np.array(image)
    labels, count = ndimage.label(pixels[:,:,3] > 8)
    if not count:
        raise ValueError("Generated source has no visible alpha")
    sizes = np.bincount(labels.ravel()); sizes[0] = 0
    pixels[labels != sizes.argmax()] = 0
    return Image.fromarray(pixels, "RGBA")


def center(image, box):
    x0,y0,x1,y1 = box
    alpha = np.asarray(image)[:,:,3].astype(float)[y0:y1,x0:x1]
    y,x = np.indices(alpha.shape)
    if np.count_nonzero(alpha) < 1000:
        raise ValueError("Empty cushion measurement region")
    return [(x*alpha).sum()/alpha.sum()+x0, (y*alpha).sum()/alpha.sum()+y0]


def fit_box(image, target):
    source_box = image.getbbox()
    crop = image.crop(source_box)
    x0,y0,x1,y1 = target
    crop = crop.resize((x1-x0,y1-y0), Image.Resampling.LANCZOS)
    result = Image.new("RGBA", (768,1024))
    result.paste(crop, (x0,y0))
    return result, source_box


def main(args):
    config_path = ROOT / "data/people/appearance_parts.json"
    config = load(config_path)
    output = ROOT / "assets/portraits/r4"
    output.mkdir(parents=True, exist_ok=True)
    manifest_path = ROOT / "assets/ART_ASSET_MANIFEST.json"
    manifest = load(manifest_path)
    manifest["assets"] = [r for r in manifest["assets"] if not r["path"].startswith("assets/portraits/r4/")]
    sources = {k: Path(getattr(args,k)).resolve() for k in ("headphones","scarf_front","scarf_back")}
    prompts = load(args.prompts)
    paintings = {k: clean(p) for k,p in sources.items()}
    records = []

    def save(image, name, source, geometry):
        path = output / (name+".png")
        image.save(path, optimize=True)
        rel = path.relative_to(ROOT).as_posix()
        row = dict(path=rel,sha256=sha(path),dim=[768,1024],group="portraits",art_pack="R4_B_v3",
                   operation="anchor_mount",version=1,style="v3",generation_tool="image_gen.imagegen",
                   attempt=1,selected_attempt=1,style_score=8,prompt=prompts[source],
                   source_raw=sources[source].relative_to(ROOT).as_posix(),source_raw_sha256=sha(sources[source]),
                   source_raw_native_size=list(Image.open(sources[source]).size),
                   processing_script="tools/art/build_r4_portraits.py",geometry=geometry,
                   alpha_cleanup="largest connected component above alpha 8; preserve remaining edge alpha")
        manifest["assets"].append(row)
        records.append(row)
        return dict(path="res://"+rel,sha256=row["sha256"])

    # Complete cushion regions, deliberately much larger than the allowed 6px
    # tolerance. Centers below are alpha-weighted measurements of the painting.
    regions = {"ear_l":[264,568,414,756],"ear_r":[675,568,824,756]}
    source_centers = {k:center(paintings["headphones"],v) for k,v in regions.items()}
    source_crown = [543,235]
    points = np.array([source_crown,source_centers["ear_l"],source_centers["ear_r"]])
    variants = {}
    for face, values in ANCHORS.items():
        target = np.array(values[:3],dtype=float)
        forward = np.linalg.solve(np.column_stack([points,np.ones(3)]),target).T
        matrix = np.vstack([forward,[0,0,1]])
        inverse = np.linalg.inv(matrix)[:2].ravel()
        image = paintings["headphones"].transform((768,1024),Image.Transform.AFFINE,inverse,Image.Resampling.BICUBIC)
        transformed = {}
        for key,box in regions.items():
            corners = np.array([[box[0],box[1],1],[box[2],box[1],1],[box[0],box[3],1],[box[2],box[3],1]]) @ forward.T
            transformed[key] = [int(np.floor(corners[:,0].min())),int(np.floor(corners[:,1].min())),int(np.ceil(corners[:,0].max())),int(np.ceil(corners[:,1].max()))]
        variants[face] = save(image,"headphones-"+face,"headphones",dict(affine=forward.tolist(),cushion_regions=transformed))
        variants[face]["cushion_regions"] = transformed
        variants[face]["crown"] = values[0]

    front, front_box = fit_box(paintings["scarf_front"], [250,660,536,998])
    back, back_box = fit_box(paintings["scarf_back"], [266,680,512,735])
    front_record = save(front,"scarf-front","scarf_front",dict(source_box=front_box,target_box=[250,660,536,998]))
    back_record = save(back,"scarf-back","scarf_back",dict(source_box=back_box,target_box=[266,680,512,735]))
    # Knot center visually marked in the generated original, mapped by the same
    # fit as its pixels. Store an enclosing region for independent alpha checks.
    def front_point(x,y):
        return [250+(x-front_box[0])*286/(front_box[2]-front_box[0]),660+(y-front_box[1])*338/(front_box[3]-front_box[1])]
    knot = front_point(648,1053)
    a,b = front_point(601,1003),front_point(699,1103)
    front_record.update(knot=knot,knot_region=[int(a[0]),int(a[1]),int(b[0])+1,int(b[1])+1])
    config["anchors"]["faces"] = {face:dict(zip(KEYS,values)) for face,values in ANCHORS.items()}
    policy = config["rendering"]
    policy["version"] = 3
    policy["render_order"] = ["hair_back","scarf_back","body","outfit","scarf_front"]+config["layer_order"][3:]
    policy['render_order'].insert(policy['render_order'].index('hair_front'),'headband')
    policy["accessories"]["accessory_07"]["layer"] = "scarf_front"
    policy["accessories"]["accessory_14"]["hides"] = []
    # Headphones never compress/replace hair: the rear headband is occluded by
    # the original fringe, while front cushions cover the ears naturally.
    policy["attachments"] = dict(version=1,headphones=dict(accessory_id="accessory_14",variants=variants,split_y=300),
                                scarf=dict(accessory_id="accessory_07",front=front_record,back=back_record),
                                limits=dict(ear_distance_px=6,back_visible_fraction=0.05))
    config_path.write_text(json.dumps(config,ensure_ascii=False,indent=2)+"\n",encoding="utf-8",newline="\n")
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':'))+"\n",encoding="utf-8",newline="\n")
    print(json.dumps(dict(assets=len(records),bytes=sum((ROOT/r['path']).stat().st_size for r in records),knot=knot,source_centers=source_centers)))


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ("headphones","scarf-front","scarf-back","prompts"):
        parser.add_argument("--"+name,type=Path,required=True)
    main(parser.parse_args())
