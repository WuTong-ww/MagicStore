# A7 independent integration review — post-fix

2026-11-22. Re-read only the three owning-file fixes, the new actual UI regressions, the data-backed fallback setting and root's recorded target output. No tests, engine, GUI, Git or production edits were performed by this reviewer. This does not independently audit the author's own shelf_layout core.

Conclusion: all three P2 findings in `independent-integration-review.md` are addressed in the reviewed snapshot. No remaining blocker found within these fixes. The previously frozen renderer is unchanged, so the earlier crop/z/paper/mouse/committed-version signal analysis still applies.

## 1. Last-unit selection and zero-stock rows

`scripts/shop/shop_screen.gd` now clears `selected_inventory_item` when `int(view.items.get(id,0)) <= 0`, before constructing selected details. The ordinary inventory loop also skips zero-count IDs. This matches the existing business behavior that retains an ID with amount zero, and agrees with ShelfView's own zero-count selection clearing. A missing key and an existing zero key now have the same no-selection result.

The new `check_shelf_selection_edges` in `tests/integration/scene_visuals.gd:418` selects genuine loaded lavender through an actual mouse target, reads its positive committed quantity, sells the full amount through `main.run_action("sell_material",...)`, waits for refresh, then checks both renderer/root selections are empty. It also verifies no actionable lavender ×0 row and no invisible shelf target remain. Its wrapper helper excludes historical ledger icons rather than mistakenly deleting or counting those as current inventory.

## 2. Selected ID appearing in overflow

The overflow loop now excludes `overflow_id == selected_inventory_item`; the all-items loop already excludes both the selected ID and overflow IDs. Therefore a positive selection gets exactly one detail row even if its display group moves into overflow.

The new regression uses genuine positive incense selected by actual mouse input, then narrows only the instance's display calibration to one source pixel. It verifies the actual renderer result contains the selected overflow ID, exactly one actionable wrapper and one matching sale button. It compares the complete game snapshot, restores production display configuration and verifies both the placement restoration and unchanged production JSON hash. This exercises the actual consumer and keeps the capacity fixture distinct from saved business inventory.

## 3. Malformed labels rejected before actual UI consumption

`ShopScreen._inventory` now starts with `SceneArt.config_valid(visuals)`. On failure it hides/clears shelf presentation, creates the named `ShelfUnavailable` label and returns before any shelf_layout.labels typed assignment or dotted heading access. The fallback Chinese string comes from `data/ui/item_visuals.json.shelf_unavailable`, not a new code literal. `ItemArt.settings_valid` requires that field to be a nonblank String. The registered current data contains `货架资料暂不可用，请稍后查看。`.

SceneVisual also checks `data.items is Dictionary` before its typed core call. Its existing labels checks reject non-Dictionary blocks, missing headings and nonblank/non-string violations before accessing them.

`check_invalid_shelf_ui` in `scene_visuals.gd:479` now assigns null, Array, String, empty Dictionary and an empty-heading Dictionary to the live screen's labels block. Each case calls the actual `main.screen.refresh`, waits, inspects the displayed error label text and hidden shelf, and compares the committed snapshot. It finally restores valid data and verifies the same shelf view becomes visible without changing the save. This closes the earlier gap where a validator-only false return left the separate ShopScreen consumer unprotected.

## Recorded verification evidence reviewed

- `selection-edges-red.log` contains the four explicit selection/overflow assertion failures from the pre-fix code. It also contains the unrelated test's incorrect `Control.to_global` runtime errors, so that run is not described as a clean verification. A printed zero-failure result in an erroring attempt is not treated as a pass.
- Current projection assertion uses `visual.get_global_transform() * visual.projected_rect(...).position`, removing the invalid Control.to_global call.
- `.tools/art/a7/target-round2-scene_visuals.log` records `SCENE VISUALS: 915 checks, 0 failures, 0 graphical captures` and no ERROR/WARNING lines. This is root's actual target output, read here; it was not rerun by the reviewer and is not a GUI/full-suite claim.

## Reviewed snapshot SHA256

| File | SHA256 |
|---|---|
| scripts/shop/shop_screen.gd | ee9eda601b5250848db6c8941f2fa076f9652d45c463c2e77cf17b2b552f3409 |
| scripts/shop/scene_visual.gd | 87885097d62bd667bb22765894f8d40231a11eb76059a204970487affe103b7f |
| scripts/shop/shelf_view.gd | db031b866ff96234ea90f88fdb9dcb643bac25328444d3dac9fce4fe1da2eb04 |
| scripts/shop/item_visual.gd | bb2b262f591ab176ea766240d7ca4cd3aff093a8559143b1d29e500ba410834d |
| data/ui/item_visuals.json | 3d0b48059ba383e4281203e440202a6eb97b3525b6d453272d230d823f76eb95 |
| data/shop/visuals.json | 48476d089a6211502eef48f380a746a37b7ffd295a62aa43f51a3f8d8597e2c9 |
| tests/integration/scene_visuals.gd | dfff90bbe128ab756998e1833257cdf14875a6a07ff2b0a06f3d27d5872b421b |

The three prior P2s are closed by this read-only source/evidence review. Remaining combined full-suite, actual GUI/200% art acceptance and integration freeze belong to root; no later result is inferred here.
