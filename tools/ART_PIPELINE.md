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

## A2R v3 square items

Production uses nine independent items under `assets/items/v3/v3r1/`: a
canonical 256×256 PNG and its derived 64×64 icon for each ID. The selected
native images in this batch are actually 1254×1254; neither runtime size is
described as native generation. The seven catalog items plus bookmark and
silver_leaf retain their existing IDs and gameplay. V3_ITEM from
`docs/art/style_v3.md` uses the selected S02 v3 style reference. The rejected
picture-book item images are local history and are not reused as final art.

`tools/art/item_pipeline.py` uses only stdlib and the existing Pillow.
`data/art/item_pipeline.json` validates all roots, IDs and processing
parameters. Native bytes are retained under `assets/_incoming/a2r_v3/`.
The processor removes the magenta key, contains the foreground with Lanczos
on a 256 canvas, erodes/feathers alpha by one pixel, aligns measured support
near the bottom, and derives the 64 icon with Lanczos and contour darkening.
The icon is never generated separately and contains no text, purpose badge
or cast shadow. New revisions and receipt outputs must have distinct paths;
different existing output bytes are rejected.

Each successful generation attempt must retain its actual output path,
SHA256 and native dimensions, together with the actual prompt/references.
The final nine sources retain all fourteen attempts, including unselected
outputs. Processing receipts bind the immutable generation snapshot, raw
and runtime bytes, actual crop/scale, support and both derivation stages.
New `paste_xy` recipes contain exactly two coordinates; the earlier batch1
four-coordinate audit is retained unchanged as history. Do not rewrite a
receipt after changing its inputs or relabel rejected art with a new style.

After the built-in queue's new raw files and matching generation receipt
exist, use its `command_after_generation`, which calls this processor with
`--receipt`, `--revision`, `--only` and a new `--output-receipt` path.
The registered local config is `data/art/item_pipeline.json`; there is no
item CLI `--config` flag. Current retained receipt validation and forced
production checks are:

```powershell
python -B tools/art/item_pipeline.py --workspace . --receipt assets/_incoming/a2r_v3/processing_receipt.json --validate-only
python -B tools/check_alpha.py --workspace . --visuals data/shop/visuals.json
python -B tools/art/validate_formal_manifest.py --workspace .
tools/regen_art.ps1 -Style v3 -Only items -Output .tools/art/new-items-queue.json
```

The first command requires the retained local audit inputs. It is not a
fresh-clone prerequisite when those ignored inputs are absent. The other
production checks still require every formal file. `run.ps1 -Test` always
runs item_visuals, formal SHA/dimension validation and the 18-file alpha
check; optional retired audit skips cannot disable them.

Alpha QA uses only `0 < alpha < 255` as its denominator. Saturation >0.6 in
the configured red/yellow hue ranges fails above 2%; exactly 2% may pass.
Visible magenta must be zero. Missing alpha, empty or fully opaque output
fails. Both 256 and 64 are checked, without discarding alpha-1/2 pixels,
desaturating edges or weakening the limits. Support uses alpha≥128 and
zero-based coordinates: bbox right/bottom are exclusive, bottom_y is
bbox.bottom−1, and bottom_left/width span the last three contact rows rather
than count occupied pixels. Actual flat-base recognition remains a visual
check even when these numbers pass.

Canonical formal rows use `group: items`, `operation: item_chromakey`,
`item_id`, `object_description`, actual `source_raw`/SHA/native size,
`processing_script` and `local_config`. The 64 row aliases its own 256.
Raw→256 records are processing provenance, not aliases that would turn a
canonical formal image into an ignored raw. `-Only items` queues nine new
native-magenta jobs, nine dependent chromakey tasks and nine icon derivation
markers. Each chromakey invocation already creates its icon; the marker
does not generate a tenth-to-eighteenth image. The queue expands the actual
object description, references only the selected style and never submits
`{object}` or the old atlas. Missing new raw/receipt/script dependencies
remain explicit; the wrapper performs no image generation or central write.

`ItemVisual.source_status()` distinguishes verified raw from
`skipped_missing_local_source`. Only a safe missing PNG strictly below
`assets/_incoming/a2r_v3/` can be skipped; its recorded raw path, SHA and
native size remain required. An existing raw must match SHA, decode and
match native dimensions. Directories, similar prefixes and missing sources
elsewhere fail. Tests print each skipped source explicitly; UI refreshes do
not print repeatedly. Formal 256/64 and the style reference must still
exist; formal SHA/dimensions and actual item alpha/support remain mandatory.
Missing local history never means that its source bytes were verified.

`tests/integration/item_visual_preview.gd` reads the local processing receipt
and writes `.tools/art/previews/A2R/v3/` using an instance-only override.
1280×720 and 1920×1080 produce sixteen frames: three real pages per size,
64/128 nine-item comparisons, and 256 comparisons paginated three per page.
The comparison paper and 64 gallery use paper colors and dynamic labels.
Purpose badges follow the actual centered rendered square on ready/resize,
including stretched 224/360-wide cells, rather than the wrapper's far edge.
The old atlas/reference PNG/SVG and their import sidecars now live under
`assets/_legacy/a2/` for compatibility; current regeneration does not select
them. Detailed receipts, candidates, raw images and audit JSONL stay local;
the compact formal table remains below 500000 bytes.

A2R full round1 exited 0: Godot 8292 + gateway 94 + art 169 = **8555/8555**,
with zero ERROR/WARNING. Final Windows Compatibility GUI round2 recorded
255 checks and sixteen item frames; the main shop run recorded 718 checks
and twenty-three frames. Visual review covered six production pages and eight
changed shop frames; fourteen other shop frames matched the already-reviewed
A1R SHA. Round1's numerical pass did not catch badge drift, so the fix has
actual stretched-layout regression and a second graphical run. Bookmark's
paper-strip identity and the grey-brown resin's material remain weak at
small sizes. A7 now consumes the measured support for native shelf placement
and contact shadows; alpha success alone does not certify that visual fit
or any A6 motion.

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

`register_real_scenes.py` accepts two baseline S04 presentation contracts:
an explicitly legacy `layers.slot` with `legacy: true` and `display: cell`,
or nonempty `shelves` and `shelf_layout`. It restores a slot only when that
valid legacy slot was actually in the baseline. An A7 baseline keeps its
native shelf geometry and nested layout parameters without resurrecting
slot/grid presentation when the generated scene layers are merged. Missing
both contracts, or a missing/empty half of the shelf contract, fails before
proposal output. The registry target covers these cases and the original
legacy-slot path (29/29); this contract check does not replace ShelfLayout's
full geometry/configuration validation. Registration still requires its
real local processing evidence; an old registry is not a current production
approval or a reason to overwrite the production manifest/visuals.

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

### Legacy scene work-manifest contract

The commands and `round2_art` fragment below describe retained legacy work
manifests. Current compact schema-3 queues accept `scenes`, `slices`, `items`,
`portraits` and `all`; use the A2R item receipt flow above for square items.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/regen_art.ps1 `
  -Style assets/_incoming/a1r_pilot/engineering_2.png -Only all `
  -Output .tools/art/receipt-v1.json -Python D:/Downlode/anaconda/python.exe
```

For these legacy manifests, `-Only` accepts `all` or a group actually declared
in `round2_art.recipes` (`scenes`, `layers`, and `pilot`). `-Manifest` selects a versioned
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
The legacy procedural resources can only serve as geometry evidence.

```powershell
python -m unittest discover -s tests/art -p test_art_pipeline.py -v
```

## A7 native shelf calibration

Active S04 uses `scenes.S04.shelves` and `shelf_layout`, not the old slot or
GridContainer. Calibration uses the unchanged 1672×941 A1R scene and crop
`[0, 0.25, 1672, 940.75]` (edge coordinates). The four source shelf lines span
x=278–1045 at y=238/375/486/626. The third line was corrected from 521 after
an actual F3 overlay review showed a 35-source-pixel error. Do not copy
coordinates from the 1920 runtime or window pixels back into this data.
Night tints are `#858D88`, `#9A9E8D`, `#C6B99A`, `#DEC496` from top to bottom;
they follow the displayed scene period and retain the lower warm lamp light.

The 256 item support is `(bottom_left + (bottom_width - 1) / 2, bottom_y)`
in zero-based texture pixels. Each group rotates around this bottom contact,
not the PNG center. Its depth-scaled texture is positioned in native scene
pixels, then mapped through the same source crop, 2560×1440 logical canvas
and SceneVisual cover projection as the background. Gap 16–24, contact inset
2, stack offset 10, shadow height 12 and selection lift 6 are native scene
pixels. Stack offsets sit outside the individual texture scale and rotate
with the group. Actual rotated alpha bounds for all copies participate in
packing, with explicit overflow rather than overlapping a full shelf.

ShelfLayout sorts product/material/keepsake, then the first historical batch
array position (including exhausted batches), then item ID; IDs without a
batch fall back to ID order. One ID occupies one group. Quantities 1–3 show
that many copies, while larger quantities show three and a dynamic ×N paper
tag. Rear copies move left/up and darken. ShelfView takes the canonical 256
texture directly; purpose badges remain in the drawer, names appear only on
hover, and clicking opens the existing detail/action flow. Drawer filtering
does not reposition shelf groups. Unchanged quantities preserve placement.

Contact shadows are built-in soft ellipse gradients, width 1.1×scaled measured
bottom width, height 12, with 35% multiply opacity. Paper is built-in low-amplitude
noise at 8% multiply, covering the artwork rather than UI. These are procedural
rendering textures, not external images or new generated source art. Shadow
and paper parameters live in JSON. Selection lifts the item and its mouse
target while its shadow stays at the shelf contact; closing the cabinet hides
the whole presentation, labels and targets included.

For calibration, inspect open S04 by day and night at both 1280×720 and
1920×1080, toggle F3, and compare each line with the actual painted contact
edge. Check 200% contact crops as well as the full scene: a numerical layout
pass cannot detect a line on the wrong painted board. Resize, hover and click
must use the same projection. Keep 0/1/9/30-total-quantity fixtures render-only;
they do not create 30 item IDs or persist fake stock. No schema change is
needed. Added/removed presentation signals use committed save_id/state_version
baselines: initial load/save switching is silent, failed saves and repeated
refresh/action replay do not emit twice. Batch replacement can emit real
same-total changes. Bottom-pivot nodes/signals are available to A6; no wind or
spring motion is implemented by A7.

Recorded targets are layout 74/74, renderer 38/38 and scene_visuals 915/915.
The independent integration review's three P2 findings were fixed and reread
as closed. GUI round1 failed on the metadata Control.to_global call and is
not GREEN evidence. Round2 recorded shelf 940 checks/19 frames and shop 710
checks/23 frames, but its F3 review exposed the third-line calibration error.
Round3 passed shelf 940/940 (19 frames) and shop 710/710 (23 writes).
The final post-calibration full run passed 9154/9154 (Godot 8888, gateway 94,
art 172), exit 0 with no engine errors/warnings. Root's 47-frame review passed
225/235 general checks and 12/12 enlarged contact checks; unrelated old
people art/UI remain partial. See `docs/codex/plans/A7.md`. Bookmark/resin identity limits
remain, and future taller items need a fresh shelf-clearance visual review.

The original `assets/generated_scenes/v2/slices/S04_slot.png` is unchanged.
`assets/_legacy/a7/S04_slot.png` is a same-SHA archival copy with a local
`.gdignore`; neither is used by active shelf rendering. Calibration changes
do not regenerate these images or the eighteen accepted A2R item PNGs.

A7最终复验：第三轮GUI940/940、19帧及shop710/710；标定后完整第2轮9154/9154（Godot8888+gateway94+art172），exit0、0错误警告。47窗口帧通用225/235，12组200%接触通过；A7专项完成，全站旧人物十项未过按部分完成，详见docs/codex/plans/A7.md。

A6 adds runtime-only WindField/Spring/SceneMotion and shader dispatch for actual aligned layers; no new raster. Static/legacy/hidden backgrounds stay static. Missing production Li/chime/particle regions remain partial. Final shader is inlined for the headless compiler with the same algorithm. Final preview508/508 and strict4-pair/8-control pixel checks pass; all34 PNGs equal root-reviewed round2. Full round3 passed9653/9653; both hardware performance observations remain false. Never use headless SKIP or non-realtime Movie Maker as hardware PASS. tools/capture_motion.ps1 -Mode front-day keeps AVI ignored; tools/transcode_motion.ps1 uses built-in WinRT when FFmpeg is absent. Only15.3MB MP4 and six quality85 JPGs committed. Container probe verifies600 video samples, not full H264 decoding. Exact limits in A6 plan/results.
