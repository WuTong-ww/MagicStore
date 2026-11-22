# A7 independent integration / renderer review

2026-11-22. Reviewed root's ShopScreen/SceneVisual/active visuals and workshop's explicitly frozen ShelfView renderer. I did not review my own shelf_layout implementation as an independent reviewer. No tests, engine, GUI, Git or production edits were performed; findings below are source-path analysis, not falsely claimed execution probes. Only this local report was written.

## Findings requiring root follow-up

### P2: selected drawer detail survives the last real unit being removed

`scripts/shop/shop_screen.gd:114` clears `selected_inventory_item` only when the dictionary no longer contains the ID. The business `_remove` writes the new count back into `player.items`, including zero, without deleting its key. ShelfView does clear its own `selected_item` at zero while rebuilding entries, but it does not emit an item_selected-empty notification. The root selection string therefore remains set.

Concrete path: click an on-shelf material/product, sell/use its last unit through the existing transaction, then the committed refresh. Its shelf node disappears; the drawer still enters the selected-details branch and renders that item's `×0` detail and active sell/use controls. Business validation prevents a second invalid settlement, but the selected presentation is stale. Minimal fix is to clear the root selection when actual quantity is <=0, not only when the key is absent. Add a real last-unit transaction / drawer refresh regression; this reviewer did not run it or edit the owning file.

### P2: a selected ID that becomes overflow is rendered twice in the drawer

`shop_screen.gd:116` renders selected details, then the overflow loop at approximately line 122 renders every overflow ID without excluding the already selected one. If a selected positive-quantity ID moves off the shelf after a quantity change or a narrow-shelf capacity fixture, the drawer receives two actionable rows for the same ID. Current broad four-shelf data seldom overflows nine IDs, but overflow is an explicit A7 branch and can be reached by its required capacity fixture.

Minimal fix: skip a separately displayed selected ID in the overflow loop, or establish one selection/overflow display rule and apply it once. Cover selected→overflow with actual ShopScreen controls, rather than only core overflow arrays. This is closely related to the previous selection-refresh finding and can be fixed in the same small owning-file pass.

### P2: the actual ShopScreen consumer is not gated by the new labels validator

`SceneVisual.config_valid` now safely rejects missing, non-Dictionary, incomplete, blank or non-string `shelf_layout.labels`. However, `shop_screen.gd:30` obtains its separate `visuals` through `ItemArt.load_config`, whose contract validates item metadata rather than the S04 scene block. SceneVisual.setup can reject the scene and leave its own config empty, while ShopScreen retains its original nonempty item-valid dictionary.

Concrete malformed-config shape: keep all nine valid item entries and replace only S04.shelf_layout.labels with a String. SceneVisual rejects it, but `_inventory` still reaches `var shelf_labels: Dictionary = visuals.scenes.S04.shelf_layout.labels`, producing a type error. A Dictionary missing one heading likewise reaches unchecked dotted access later. Thus testing only the SceneVisual validator's false return does not prove that the real consumer is safe.

Minimal fix: gate ShopScreen's A7 consumption on the validated scene/shelf contract before any shelf or label access, with a safe existing-config failure path. Add a real consumer regression for malformed labels and missing headings. This reviewer notified root immediately and did not expand the work into unrelated configuration validators.

## Checked integration paths without another blocker

- **Unified crop:** `SceneVisual.native_point` subtracts source_crop origin and scales crop dimensions into the logical canvas before calling the existing cover projection. Actual source_crop `[0,0.25,1672,940.75]` has width 1672 and height 940.5, exactly matching the 16:9 2560×1440 canvas ratio. ShelfView places its native root at native_point(0) with native_scale; its items, shadows, hit rectangles and debug lines share that root. Current data therefore does not mix native, runtime or logical coordinates.
- **Renderer transform:** front sprite position is `-support*scale`, each rear sprite adds native `stack_offset_px*i` outside sprite scale, and the parent applies the item's micro-rotation. The group pivot is projected once. This matches the published producer/consumer contract; it is a renderer integration check, not an independent audit of core's packing algorithm.
- **Parent/child z:** ShelfView is above scene foreground layers at interaction_z_index. Relative to its native art children, shadows are below item pivot z=1, paper z=3 is above artwork, and quantity paper has item z1+tag z4=5; hover name is z5. With the active negative art_root_z the floating drawer/UI remains above this art group. Paper and tag controls use MOUSE_FILTER_IGNORE; actual item targets accept the left click and call selection once.
- **Paper/closed state:** paper covers the projected scene rectangle and uses a multiply shader at configured 8%; shadows use the configured 35% multiply gradient. Closing the cabinet hides the whole ShelfView subtree, including sprites, targets, tags, paper and debug overlay. The renderer retains contact shadows at the unlifted native pivot while selection raises only the item/target by six native pixels.
- **Selection refresh:** reselecting the same ID returns before re-emitting item_selected, preventing a refresh recursion. Ordinary repeated root refresh does not rebuild unchanged quantities, so the active selection tween/node survives. The last-unit and overflow root-state gaps are listed above rather than hidden by this otherwise-correct renderer path.
- **Successful-version signals:** update_inventory compares save_id/state_version with its baseline, establishes a silent first/switch-save baseline, emits only for a newer version, and updates the baseline before emitting. Duplicate/replayed versions do not emit again, and older same-save versions cannot roll the displayed view back. Deltas prefer actual snapshot.player.items/shop.batches when present, so render-only fixtures do not corrupt committed baselines. Batch-key comparison retains same-total add/remove events and falls back to count deltas when batch evidence does not agree. Removed signals are emitted before the outgoing node is queued for deletion.
- **Production source of snapshots:** ShopScreen passes `GameState.shop_view()` plus `GameState.player_snapshot()`. GameState publishes state_changed only after write_save succeeds. Main's state_changed refresh and subsequent action-end refresh therefore see the same committed version and do not double-emit. A same-version alternate display view is intentionally permitted for render-only fixtures; no production caller in this reviewed path supplies an uncommitted candidate view.
- **Labels validator itself:** the new SceneVisual code checks options and labels Dictionary types before reading keys; each required heading must be a nonblank String before strip_edges, and wrong-scene shelf blocks reject. The remaining labels issue is its separate ShopScreen consumer gate, not the validation predicate itself.

Workshop reports its focused renderer target at 38/38 with no errors/warnings. I only read its test file, including actual mouse/F3 events, resize/native stack checks, same-version preview vs actual-snapshot baselines, batch replacement and live-last-removal-node coverage. I did not rerun those checks, the core target, or any full/GUI acceptance.

The renderer directly sets the current day/night tint; this review verifies selected-period consistency and the saved-clock source, not the artistic appearance during the background's 0.6s fade. Root's GUI round remains responsible for that visual judgment and for the paper/shadow look at 200%.

## Reviewed snapshot hashes

- ShopScreen: `82f2fe8fd90aa89d90f74b9b4524f8a1022a8d4fb07a094b9f58c68b4a24f4b6`.
- SceneVisual: `5febf189c66035ee361d48c042be9ce4160c38dd4f1f2868b9ab8ffb4319ada3`.
- Frozen ShelfView: `db031b866ff96234ea90f88fdb9dcb643bac25328444d3dac9fce4fe1da2eb04`.
- Frozen renderer test: `e5d5ccda13dd95739565968e5604e9cf462dc931662d6e50f194f97b6ff284f4`.
- Active visuals: `48476d089a6211502eef48f380a746a37b7ffd295a62aa43f51a3f8d8597e2c9`.

Status: three closely scoped P2 findings sent immediately to root, pending the owning agent's fix and regression evidence. No production change or test execution by this reviewer. Re-read the changed owner files after root's fix; do not treat this pre-fix snapshot as a clean final approval.
