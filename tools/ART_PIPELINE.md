# Round 2 offline art pipeline

## Clean branch and style v3

The picture-book pilot was rejected. Production now uses the reviewed v3
paintings with six accepted cutouts; other objects remain in their static C.
All 56 original v2 inputs remain unchanged. `scene_preview.json`, `scene_review.json`, and the old real-scene
registry reference `data/art/local_audit.json` as retired local history.
Detailed history lives only in ignored JSONL. Missing optional JSONL is an
explicit SKIP, while corrupt metadata fails; production source/runtime pixels
and synthetic renderer/pipeline tests remain mandatory.

The formal manifest uses `schema_version: 3`, a compact `assets` table and
explicit `runtime_copies`; it must remain below 500000 bytes. This metadata
version is independent of the rendering format and the art direction version.
`validate_formal_manifest.py` validates the current formal table. The legacy
work-manifest format remains supported for isolated processing fixtures.

`regen_art.ps1 -Style v3 -Only scenes` resolves `style_profiles.v3`. A profile
contains `status`, `reference: {path, sha256}`, optional `revision`, and
`templates: {edit, night, closed, item}` (portrait is required separately for A4).
Only the supplied new templates form generation
prompts. Missing pilot/reference/templates produces an honest pending queue;
it does not reactivate rejected art. An explicit `-Style <path>` records that
new reference's real SHA. Native inputs are read-only and outputs are versioned.
The script produces built-in imagegen tasks; it makes no API/model call itself.

Compact registration and runtime import write independent immutable proposals,
not central files. Per-layer work is a local JSONL sidecar; `geometry_passed`
never implies `art_passed`. A successful retained alternate attempt contributes
its own actual prompt/reference metadata. Only self-reviewed final images and
their runtime copies may be promoted to the formal manifest.

All raw captures go under `.tools`. Commit at most six quality-85 JPG review
frames per task. Keep candidates and intermediates under ignored
`assets/_incoming/`, with a local `.gdignore` so archived scripts/import files
cannot create duplicate Godot resource UIDs.

## Real scene processing and review

The current production configuration is `data/shop/visuals.json`, with 17 v3
scene/state/period combinations. Only S03 sofa, S04 closed door and S07 water
have accepted day/night cutouts. S04 open doors are rendered from complete C;
the hidden `door_open` alias is semantic compatibility, not a cutout. See
`docs/codex/results/A1R-v3-art-review.json` for actual review scores and limits.
The old engineering and real-art previews and registry are retired local
history, not current production approval. The commands below describe that
legacy processing contract; use each actual versioned v3 spec for new work.

```powershell
python -B tools/art/real_scene_layers.py --spec assets/_incoming/a1r_real/S02/day_layers.json
python -B tools/art/register_real_scenes.py --validate-only
python -B tools/art/register_real_scenes.py --output .tools/art/new-registration
```

For a new revision, edit only the versioned data paths, actual masks/anchors,
and style reference. Preserve original C/raw-B bytes. The layer processor
patches actual raw-B into C locally, extracts Li, and records both numerical
and unapproved artistic status. A six-pixel authorization image is not a claim
that a dedicated masked-inpainting API was used: actual reference paths and
`mask_usage_notice` distinguish instruction references from API masks.

Registration checks retained pixel equality to Lanczos(source), source
generation hashes, annotation/descriptor/recipe bindings, and every ROI. It
outputs a proposed manifest and preview only. C has its own original composite
prompt; B_all uses cleanplate instructions and C/masks; Li is never redrawn.
Local layer z stays inside the configured negative art-root budget so trees,
clouds, water, and seated portraits cannot cover the paper/chrome UI.

The detailed review and remaining edge/cleanplate defects are recorded in
`docs/codex/plans/A1R.md`. Do not treat static recomposition success as approval
of independent motion, or overwrite v2 with an engineering placeholder.

Native scene assets use `group: scenes`, `scene_id`, `period` and (for S04)
`state`. A night C depends on its matching new day C; S01 closed depends on
the new night C and requires the closed template. Derived B_all/Li use
`group: slices`, `operation: inpaint_cleanplate|extract_layer`,
`composite_source`, `processing_script`, and `local_spec`. They are never
independent image-generation tasks. `-Only slices` returns offline tasks
with `needs_mask_review` and `can_process:false` until the new C and reviewed
local masks exist. Original outputs are immutable and new outputs are
versioned. Missing ignored masks/specs on another checkout are explicitly
pending; they are not silently approved.

All 1099 rejected processing files were moved, with SHA verification, into
`assets/_incoming/a1r_v3_processing_evidence/`; its `relocation-index.jsonl`
maps historical paths to actual local paths. Processing receipts retain
their original paths and failure status. The ignored
`docs/codex/results/art_audit/v3-current.jsonl` preserves the full history;
the compact formal manifest contains only selected images and provenance.

The PowerShell entry point uses only an existing Python with Pillow. It does
not call a generator, require an API key, install packages, or change the live
manifest. `needs_builtin_generation` is a successful handoff status, not a
claim that images were generated.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/regen_art.ps1 `
  -Style assets/_incoming/a1r_pilot/engineering_2.png -Only all `
  -Output .tools/art/receipt-v1.json -Python D:/Downlode/anaconda/python.exe
```

`-Only` accepts `all` or a group actually declared in `round2_art.recipes`
(currently `scenes`, `layers`, and `pilot`). `-Manifest` selects a versioned
manifest copy for an independent import. All manifest/output/import-map paths
are workspace-relative POSIX paths. An absolute `-Style` is accepted only
inside the workspace. Symlink or junction escapes are rejected.

The required manifest fragment is:

```json
{"round2_art":{"version":1,"active_style":{"path":"assets/style.png","sha256":"64 hexadecimal characters","status":"placeholder"},"recipes":[],"recompositions":[]}}
```

Each recipe declares `id`, `group`, `prompt`, `version`, `style_reference`,
`source_path`, `runtime_path`, `status`, `operation`, and `attempts`.
Statuses are `placeholder`, `needs_builtin_generation`, `generation_failed`,
or `complete`. Each attempt has a unique integer `attempt` from 1 through 4
and a valid `status`; error text and reference/output paths can be retained.
Missing sources are legal only for the two pending/failed statuses. Optional
generator, requested prompt, processing script, and origin notes are retained.

Run `queue.tasks` with the conversation's built-in `image_gen.imagegen`, after
viewing the listed local references. Respect `can_generate:false`: check
`status`, `ready`, `missing_dependencies`, and `attempts_used` to distinguish
an already completed task, a waiting dependency, and the per-image attempt
cap. For layered scenes the queue
contains a whole-composite C task, local cleanplate tasks, and separate
`offline_tasks` for actual pixel extraction and mask preparation. Complete
dependencies before using a task's referenced paths. A Li is never sent to
imagegen as an independently redrawn replacement object.

`source_destination` is the new immutable output path. To preserve the old
composition while generating a new C, set a recomposition's optional
`reference_path` to the old C and `original_path` to the new versioned C path.
An explicit whole-C recipe can likewise provide its old `reference_path`.
Missing new destinations are legal: each task reports `ready` and
`missing_dependencies`; references to declared future C/mask outputs remain
deferred until those stages complete. Existing references are never silently
substituted for missing new outputs.

Copy the built-in output into the workspace and supply an import-map JSON:

```json
{"version":1,"outputs":{"S02_day":{"path":"assets/_incoming/new-output.png","status":"complete","generator":"builtin_imagegen"}}}
```

```powershell
tools/regen_art.ps1 -Style assets/style.png -Only scenes `
  -Manifest .tools/art/manifest-v4.json -ImportMap .tools/art/import-v4.json `
  -Output .tools/art/receipt-v4.json
```

Original source files are immutable. For replacement art, first select new
versioned source/runtime paths in a manifest copy; then merge the validated
receipt into the live manifest and resource mapping. This changes data and
images, without changing game code. Existing differing output bytes are
rejected; an identical rerun is safe. Nothing is recursively deleted.

Import-map keys accept both declared recipe IDs and the exact derived task IDs
listed by the queue, such as `S02_day__composite` and
`S02_day_leaf__cleanplate`. They map only to the queue's declared destination;
an import map cannot choose another destination. Unknown IDs, unsafe paths,
unresolved dependencies, and conflicting existing source bytes are rejected
before any import or automatic helper writes. Related outputs can be imported
together; the tool schedules them in dependency order.

For staged generation, pass the previous receipt directly as the next
`-Manifest`; no manual extraction or code change is needed. For example:

```powershell
# import-c.json: S02_day__composite -> newly generated whole C
tools/regen_art.ps1 -Style assets/style.png -Only all `
  -Manifest .tools/art/manifest-v4.json -ImportMap .tools/art/import-c.json `
  -Output .tools/art/receipt-c.json
# import-bi.json: S02_day_leaf__cleanplate -> new B_i
tools/regen_art.ps1 -Style assets/style.png -Only all `
  -Manifest .tools/art/receipt-c.json -ImportMap .tools/art/import-bi.json `
  -Output .tools/art/receipt-bi.json
# import-base.json: S02_day -> new B_all
tools/regen_art.ps1 -Style assets/style.png -Only all `
  -Manifest .tools/art/receipt-bi.json -ImportMap .tools/art/import-base.json `
  -Output .tools/art/receipt-final.json
```

Available masks are prepared automatically. Li extraction runs once its new
C, mask, and B_i are present; then single-layer QA runs. Whole-layer QA waits
for the new C, B_all, and all Li. A partial receipt lists `pending_qa` and never
claims complete geometry. Both S04 open/closed composites can share a base and
lamp while retaining their separate C references and QA. The final queue/status
is rebuilt after import, so completed stages are no longer marked pending.

Receipts retain all recipes and recompositions even when `-Only` selects one
group. `round2_art.artifacts` records derived C/B_i IDs, paths, actual dimensions,
SHA256, source input paths, prompts, and style references. Declared
`preview_only` metadata is retained, and `art_passed` stays false. Source/runtime
records and artifact bytes are revalidated when continuing from a receipt.

The tool reads native dimensions and encoded source/runtime SHA256 itself.
It performs a single center-cover `resize(box=source_crop)` with Lanczos,
recording the exact floating crop and common scale. It preserves the source;
the 1920×1080 result is explicitly a runtime copy. `native_resolution_met`
describes source pixel dimensions, while `origin` separately identifies a
procedural placeholder; it never certifies AI origin or aesthetic quality.
`runtime_copies` includes the aliases required by the Godot visual catalog.

For a single layer, `original_path` is C, `source_path` is RGBA Li,
`mask_path` is Li's actual soft alpha mask, and `cleanplate_path` is B_i.
All four canvases must have identical dimensions. The core preserves C's
pixels exactly. Feather RGB can be decontaminated against a known cleanplate,
but must still meet the reconstruction bounds; the tool does not fake local
inpainting. Helpers are executable without a manifest:

```powershell
python tools/art_pipeline.py --prepare-masks hard.png soft.png inpaint.png
python tools/art_pipeline.py --prepare-inpaint-target soft.png inpaint.png
python tools/art_pipeline.py --extract-layer original.png soft.png layer.png
```

The first helper uses a 1-pixel box feather and a 6-pixel dilation of the hard
mask. The second recovers a hard region from an existing soft mask using the
configured alpha threshold before dilation. The cleanplate itself must come
from built-in inpainting or a clearly identified geometry placeholder.

Each single-layer Li+B_i and complete sorted-layer reconstruction over B_all
is compared against C. The receipt separately reports RGB byte error for the
opaque core, feather, dilation ring, and unedited region. Core/ring/unedited
require max error zero; feather requires MAE ≤3 and P95 ≤12. These are ROI
metrics, not full-canvas averages. Source/runtime hashes and all QA inputs are
recorded and the receipt is validated again against actual files.

`geometry_passed` is independent from `art_passed`. The offline pipeline always
leaves `art_passed:false` and `visual_review:not_evaluated`; a human/Codex visual
review of every image, style requirements, and AI artifacts remains necessary.
The current procedural resources can only serve as geometry evidence.

```powershell
python -m unittest discover -s tests/art -p test_art_pipeline.py -v
```
