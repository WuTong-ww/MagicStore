# A2R final independent read-only review

2026-11-22. No blocking code, asset-provenance or forced-validation issue found in the current snapshot. Scope was code reading plus actual file SHA/dimension and queue probes. This review made no production mutation, image processing/generation, relocation, engine/Godot call, Git call, unit-test repeat or full-suite run. Only this local report, hashes, probes and one unique local queue were written.

## Findings

No blocking findings. One small metadata inconsistency remains: all 18 formal item rows retain `art_review_status: pending_root_18_transparent_review`, whereas the manifest top-level records `root_reviewed_18_transparent_outputs` and active visuals records `root_reviewed_alpha_passed_pending_gui`. This does not bypass validation or select a wrong image. Root can synchronize the per-row wording with its final GUI/full acceptance state during final documentation freeze. This review changed none of these values.

## ItemVisual missing-local-source boundary

`scripts/shop/item_visual.gd:183` first requires a safe PNG workspace/resource path, a 64-digit hash and positive native-size pair. `_png_path` rejects absolute/drive paths, backslashes, empty/dot/dot-dot components and embedded schemes. An existing directory is rejected. Only a nonexistent file strictly under `assets/_incoming/a2r_v3/` is passed as `skipped_missing_local_source`; the slash prevents similarly named sibling directories inheriting the exception. This status explicitly differs from verified provenance.

An existing raw is never skipped: it must match SHA, decode as PNG and match native dimensions. `verify_entry_files` still requires the actual 256, 64 and reference PNGs, verifies formal hashes/size/alpha and recomputes support. Missing local raw cannot excuse missing or altered formal artwork. Integration source-audit cases cover the designated missing raw, missing formal/reference files, outside/similar prefixes, existing directory, malformed original SHA/dimensions, existing damaged raw and actual size mismatch. This conclusion is static code/test review; the GDScript test was not re-executed here.

## Badge layout after container updates

`scripts/shop/item_visual.gd:290` connects badge placement to wrapper ready, wrapper resized and picture resized, plus an immediate placement. `_place_badges` uses the actual `KEEP_ASPECT_CENTERED` square inside the possibly stretched picture control, then places the badges in the wrapper coordinate system. If a container's wrapper resize precedes the anchored picture resize, the picture's own later resize signal recomputes the positions using the new size.

`tests/integration/item_visuals.gd:126` covers actual 64/128/256 rendered squares in 224/360-wide VBox cells, waits three process frames, compares real global badge/canvas rectangles, reparents the control, widens it asynchronously and waits/compares again. This exercises the delayed geometry that caused the earlier visually found drift. An independent read-only code reviewer separately checked this path and the raw-source boundary and found no remaining blocker. Root owns the actual second GUI round and full run; this report does not claim those results.

## Current formal manifest, legacy paths and A1R preservation

The actual central manifest has 169 rows and 62 provenance rows. All 169 retained files exist and their actual SHA match the central table. All 157 PNGs were opened and their actual dimensions checked; the retained SVG's 768×256 viewport was also checked. Text, OGG and font rows have no declared raster dimensions. The 18 selected item PNGs independently match active visuals' main/icon SHA and exact 256×256 / 64×64 sizes. The final generation IDs/raw SHA agree with active item entries.

Every current formal asset row compares equal to the earlier current-base merge proposal; the only additional central top-level field is root's item review evidence. The old 44 provenance rows remain equal and the complete 62-row set matches the proposed actual raw-to-256 / same-ID 256-to-64 records. The A1R `scene_settings`, `scene_pages` and `scenes` blocks in active visuals remain identical to the pre-application proposal, and all 59 A1R PNG hashes match the frozen whitelist.

Count clarification for the native v2 directory: `assets/generated_scenes/v2` contains 56 physical files, comprising 28 native PNGs plus 28 import sidecars. All 28 native PNG bytes match their pre-A2R formal SHA and their existing manifest rows are unchanged. All 28 sidecars are present. There is no independent pre-A2R sidecar SHA index available to this review, so this report does not turn their current existence into a claim that historical sidecar bytes were independently proven unchanged.

The old atlas PNG, reference PNG/SVG and three import sidecars are now at exactly the six planned `assets/_legacy/a2` paths, and the old locations are absent. The three native asset hashes match the archive plan; each import's current `source_file` names its new resource path. Other than these three legacy item rows/references and the 18 appended item rows, the existing A1R formal records remain unchanged. The actual engine import was root's work, not rerun by this reviewer.

Evidence: `final-independent-manifest-probes.json` contains all actual formal paths/SHA/dimensions, archive evidence and comparison results. `final-independent-code-hashes.json` binds this review to the files read.

## Actual final regeneration queue

Ran the existing `tools/regen_art.ps1 -Style v3 -Only items` once against the actual current central manifest, with a new unique output path `final-independent-items-queue-1795306081285213300.json`. Exit 0, nine canonical jobs: lavender, spring_water, quartz, moon_dust, calming_incense, restorative_draught, clarity_crystal, bookmark and silver_leaf.

All previous formal sources are the actual v3r1 256 PNGs, not the old atlas or 64 icons. The queue has nine new native-magenta raw generation jobs, nine `item_chromakey` tasks depending on each corresponding new raw, and nine `item_icon_derivation` markers depending on the corresponding new processed 256. Icon destinations match the processor outputs. Each future generation prompt expands the correct object description, has no `{object}` residue and references only the selected style. There is no independent 64 generation task. `generation_performed` and `manifest_modified` are both false. `final-independent-queue-probes.json` and `final-independent-queue-cli.log` preserve the actual evidence.

## Forced production validation entry

`scripts/dev/run.ps1:95` always invokes item_visuals integration under `-Test`. The production formal-manifest validator at line 138 and `tools/check_alpha.py --visuals data/shop/visuals.json` at line 140 are unconditional; a nonzero exit throws. The optional-local-audit helper is used only for retired scene audit descriptors and does not guard or skip the production item checks.

`tools/check_alpha.py:23` requires selected_version 3 and the exact configured nine-ID set. For every ID it requires unique, existing independent main/icon PNGs, measures exact configured sizes and calls actual alpha checks, yielding 18 reports. Missing files, v2/empty mappings or invalid paths fail instead of returning an all-skipped success. Existing unit coverage asserts checked=18 and makes the final silver_leaf 64 file opaque RGB to demonstrate a failure at the last file. I read this entry and its negative regression; I did not rerun the already-completed unit/alpha suites or process the accepted images again.

## Snapshot and limits

- Actual manifest SHA256: `f39f00cd4c01269dd3a38bf0d2acee94e2f44a211b3b9edb2a2f226e5e3c0297`.
- Active visuals SHA256: `6b6e4dcdbef5ba6dab18605a4d8a0cd7ebdd515e33b98f9f7a2ba7e059ca4461`.
- ItemVisual code SHA256: see `final-independent-code-hashes.json`.

No new game screenshots were taken. Root's GUI round2, full test results, any final metadata wording update and integration/commit freeze remain outside this read-only review. This report confirms code and actual-source consistency at the stated hashes; it does not replace visual acceptance or assert a later engine run has passed.
