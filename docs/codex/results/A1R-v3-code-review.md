# A1R v3 final code review

Reviewed current uncommitted `tools/art_pipeline.py`, compact tests, production `visuals.json`, formal manifest, both final `regen-*-final.json` queues and the new hidden-alias acceptance branch. This review did not open Godot or a graphical window, alter production files, or run the full suite. Root owns the running full test and graphics sessions. **Final review: no remaining blocker in the reviewed scope.** All four initial findings are corrected and independently rechecked as described below. Initial findings remain as historical evidence, not open defects.

## Initial actionable findings

1. **[P1] Per-scene repaint constraints were lost in queued prompts** (`tools/art_pipeline.py:335`). All new native sources are named `C.png`; the queue appended only `Resource identity: C` to the common room template. In the actual S04 day/open queue, `Remove every object...` was absent; neither the empty-shelf nor open/closed requirement survived. Repainting could therefore fill the cabinet or change its state. Root is adding explicit JSON `regeneration_constraints` to the four S04 native records; the adapter owner is adding validated prompt composition, retaining the new style template rather than copying a retired style prompt.
2. **[P2] Missing complete scene identity silently converted night into day repaint** (`tools/art_pipeline.py:253`). Read-only reproduction: deep-copy the actual manifest, remove `scene_id`, `period`, `state` from its S02/night/C row, then call `build_queue(root, copy, 'v3', 'scenes')`. The affected task was accepted with `can_generate=True`, `depends_on=[]`, using `templates.edit`. New formal C identities must be required, rather than falling back to the legacy filename heuristic when all metadata is absent.
3. **[P1] Invalid derived operation became independent image generation** (`tools/art_pipeline.py:250`). Read-only reproduction: deep-copy the manifest and change any selected `extract_layer` row's operation to `extract_layer_typo`; `build_queue(..., 'slices')` produced an immediately executable `image_gen.imagegen` / `generate` task with transparent background. Unknown operations on formal derived resources must fail validation, never fall through to a separately drawn Li. The adapter owner is correcting this with regression tests.
4. **[P2] Hidden-period aliases were checked after path deduplication** (`tests/integration/scene_asset_acceptance.gd`, formerly lines 82–90). Setting hidden `door_open.variants.night` to its day path would check day, then skip night because its PNG was already in `seen`. Root authorized this reviewer to fix only this issue. The semantic assertion is now before deduplication, while pixel/native/runtime/SHA IO remains deduplicated. The negative fixture `.tools/art/v3/hidden-alias-bad-night.json` was created first; it changes only that night alias, leaving the actual open/night background intact. No engine run was made during root's full test. Root should run the command below after its current engine session ends and expect exit 1 with an exact night alias mismatch; the unchanged production configuration must exit 0.

```powershell
& .tools/godot/Godot_v4.6.3-stable_win64_console.exe --headless --path D:/MagicStore --script res://tests/integration/scene_asset_acceptance.gd -- --config=res://.tools/art/v3/hidden-alias-bad-night.json
```

The initial semantic-mutation reproductions were run directly in Python against in-memory copies; no source/manifest mutation was used to create those failures. Adapter fixes 1–3 will receive a separate read-only follow-up below when the owner freezes them.

## Correct current-data behavior

- The actual scene queue has exactly **17** C generation tasks: **8** ready day tasks and **9** dependent night/closed tasks. All normal night identities pair with the same scene and state day; S01 closed depends on its new night. S04 open/closed dependencies are not cross-paired. Outputs are versioned and do not replace the current production image.
- The actual slices queue has **0** independent generation tasks, **6** `inpaint_cleanplate` and **6** `extract_layer` tasks, plus **12** runtime-copy tasks. All derived tasks require mask review and report `can_process=False`; their new C dependency and proposed processing/native/runtime roots remain explicit. New C is not approved by an old mask or old audit.
- The 17 production state/period backgrounds and six actual visible cutouts are reachable through the 151-record formal manifest. The new production config has no `local_audit_descriptor`, retired skip marker, or reference to failed Li/B artifacts. Hidden S04 open is a documented full-background API alias, not claimed as independent transparent art. Visible Li retain genuine-alpha checks.
- The actual regenerated queues verify selected native files by SHA and image size. Profile v3 points to the selected formal style reference with its actual SHA; unsafe paths, conflicting aliases, cycles and mismatched source hashes fail, rather than becoming local-audit skips.
- **139 raster dimension records** were initially read from actual files and all matched. All new **59 PNG** hashes and dimensions matched. The initial full SHA audit found two inherited newline discrepancies (`LXGWWenKai-OFL.txt`, `inventory-reference.svg`). Root corrected the recorded license bytes and SVG checkout policy (`-text` for the upstream license, explicit `eol=lf` for SVG). The final formal validator independently passed **all 151 retained sources** against exact SHA and raster dimensions. The inherited newline discrepancies are resolved, not outstanding image errors.
- Final reviewed manifest: **229,143 bytes**, below 500KB, with four explicit S04 regeneration-constraint fields present. No current PNG is treated as native 1920×1080: originals are 1672×941 and runtime copies record the equal-aspect Lanczos transform.

## Fresh-clone and validation limits

Production asset acceptance reads tracked image bytes, dimensions, crop, scale and source/runtime SHA directly; it does not require ignored audit JSONL. Root additionally strengthened the mandatory formal-manifest CLI to check **every retained asset's exact bytes**, and Pillow dimensions for raster formats. This includes retained C originals, style reference, historical/UI/text resources, not only the active runtime backgrounds. Missing files, stale hashes, line-ending changes and incorrect raster dimensions fail. SVG is hashed as exact bytes without pretending Pillow can parse vector pixels. Its independent five-case regression suite passed. Ignored audit files are not inputs to this validation. This review verified these code paths and the actual worktree, not a separate physical fresh clone.

Ignored local specs/masks/raw cleanplates/audits are intentionally not needed to run the game. A fresh clone can validate and display the tracked formal images, but derived regeneration will list absent local processing inputs and remain `needs_mask_review`; it cannot automatically recover an omitted manually traced mask. That is an explicit workflow boundary, not a successful regeneration claim. The compact adapter is queue-only; a reviewer executes the built-in generation tasks and updates local masks/specs before the existing processing CLI runs.

## Checks run by this reviewer

- Before adapter-owner follow-up: `python -m unittest discover -s tests/art -p test_compact_regen.py -v`: **25/25**, exit 0; log `final-review-python.log`.
- In-memory actual-manifest mutation probes reproduced findings 1–3, as recorded above.
- Direct image/hash checks described above; first all-dimension attempt stopped on a legacy SVG that Pillow cannot parse, then the correctly bounded raster-only check completed all 139 raster records.
- `git diff --check` on owned integration files passed.
- No GUI, no Godot, no full test, no Git mutation or push by this reviewer in this review turn.

## Follow-up

The adapter owner first supplied 65/65 passing tests after fixes. Independent actual-manifest retesting confirmed:

- All four S04 task prompts contain their exact JSON constraints; empty shelves and each open/closed state are retained.
- A misspelled formal slice operation now raises `ValueError: unsupported formal slice operation`, rather than producing independent image generation.
- Final normal queues still have 17 C tasks (eight ready, nine dependent). This reviewer independently matched **all nine** night/closed dependencies against the exact preceding period of the same scene/state: zero failures. All **12** derived tasks remain `needs_mask_review` with `can_process=False`; all **12** runtime-copy dependencies point to their own processed native output, not to C; there are zero independent slice generation tasks.
- Root separately ran the hidden night/day counterexample: **461 checks / 1 expected failure**, exit 1. Formal production configuration: **478 / 478**, exit 0. This reviewer did not open an engine to reproduce those root-owned results.
- The final actual formal-manifest CLI passed all 151 source byte/dimension checks. This reviewer independently reran its five regression tests: **5 / 5**, exit 0, log `final-review-formal-tests.log`.

Independent review caught one further defect in the first identity fix: the validator reused variable `path` inside `for path in asset['inputs']`, so its new `C.png` check looked at the last input filename. On the actual S02/night row (`inputs=['.../style_reference.png']`), deleting all identity fields was still accepted as an immediately ready EDIT task. The owner added that realistic regression case, observed **31 tests / 1 failure** before the two-line variable rename, then **31 / 31** after correction.

This reviewer then independently reran the exact actual-manifest probes against the frozen correction, **exit 0** (`final-independent-probes.log`):

- Actual S02/night C with its real `inputs`, deleting all scene identity fields, now raises `ValueError: native C requires complete formal scene identity metadata`.
- A typo in a real Li operation raises `ValueError: unsupported formal slice operation`.
- All four real S04 prompt strings contain their full empty-shelf rule and explicit correct OPEN/CLOSED state text, taken from JSON rather than code constants.
- All nine dependent tasks still resolve the exact corresponding same-scene/state prior period; 17 tasks total.

All initial findings are therefore closed in the reviewed snapshot. This is a code/provenance review, not a claim that rejected art layers or incomplete A1R motion assets have become complete. Full-suite and 34-frame visual acceptance remain root-owned.
