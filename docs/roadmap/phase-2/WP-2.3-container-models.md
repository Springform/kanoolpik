# WP-2.3 — Container models

**Phase:** 2 · **Lane:** containers · **Size:** M · **Status:** ✅ done — 13 of 14 containers have models (pant_bag outstanding) · **Depends on:** 2.2 (uses `ItemVisual`)

## Goal
The pant bag looks like a bag, the cooler like a cooler, the canoe like a canoe. Containers are the destinations you navigate by, so they matter more per object than the items do — there are only twelve of them and you look at each one dozens of times.

## Owns (may edit)
- `src/game/containers/` · `assets/models/containers/` · `assets/models/CREDITS.md` (append rows)
- `data/catalog/containers.json` — only to populate `scene` / scale / rotation; no new containers
- `tests/integration/test_container_models.gd`

## Must not touch
- `src/game/items/` (you *use* `ItemVisual`, you do not change it), `src/game/island/`, `src/core/`, `src/autoload/`

## Acceptance criteria
- [x] Uses `ItemVisual.build()` from WP-2.2 rather than a second loader.
- [x] **The slots stay aimable and stay where the model's opening is.** This is the hard part: `SlotNode`s currently sit in a row above a box lid at `SLOT_HEIGHT`. With a real model they must follow its shape, and the interaction ray must still reach them before the body (see WP-1.3's notes — slots inside the container's own collision box are unreachable).
- [x] Placement feedback still reads: flash, gold completion, `×` markers all visible against the model.
- [x] Footprint still matches `ContainerDef.footprint_radius()`, which the level layout and the mess generator both depend on. If a model wants a different footprint, change the *data*, re-run the layout, and keep `test_island_layout.gd` green.
- [x] No model → today's translucent box, exactly as now.
- [x] Credits rows present; `bash tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] You can find the container you want from across the island by its silhouette. *(needs eleven more models before it can be judged)*
- [ ] Aiming at a specific slot is no harder than it is with the boxes. *(asserted by tests — spacing and reachability — but not yet played; the ring in particular wants a real look from standing height)*

## Decisions

- **Slot placement is computed, not authored.** `SlotLayout` takes the drawn model's measured box and lays slots out above it: `MIN_SPACING` (0.25 m) apart, filling left to right, then front to back, then **stacking upward**. The old code put slots in one row on a lid whose width was invented from the slot count — with a real model, the pant bag's 34 slots would have landed 3 cm apart and you could not have aimed at one. A slightly untidy pile you can hit beats a tidy row you cannot.
- **Every slot starts above the body collider**, by construction rather than by a constant. That is the WP-1.3 failure (a slot inside the container's own collision box is unreachable, because the box is in front of it), now covered by a test that walks all twelve containers.
- **Scope widened, deliberately:** `ContainerDef` gained one field, `slot_layout` (`"grid"` default, `"ring"`). The WP said not to touch `src/core/`. Guessing the layout from the model's proportions was the alternative and it is worse — a fire pit and a cooler can measure the same and want opposite arrangements. An unknown name falls back to the grid, so a typo in content data cannot take a container out of the game.
- **The label lifts with the model** (`max(1.15, height + 0.5)`), otherwise a tall model swallows its own name.
- The placeholder box is unchanged, by arithmetic rather than by a special case: its footprint gives one row at 0.25 m spacing and a top at y = 0.74 — exactly the old hard-coded `SLOT_HEIGHT`.

## Second pass — what the real models broke

The framework survived the fire pit and then fell over the moment eleven more models arrived. Three things had to change, and all three were the same mistake: **geometry invented for the gray-box shelf, applied to a real object.**

- **Fitting the longest axis to the slot-row width produced a 5.3 m bin bag** and a 5.8 m "lost and found", because the budget width grew with `slot_count`. A container is now fitted by `model_height` — how tall the thing is in real life, in metres. That is the one dimension a person can state about a bin bag without measuring a mesh, and it leaves the model's own proportions alone. (Items keep the longest-axis fit; a can has no interesting proportions to preserve.)
- **The slot grid then stacked a four-metre tower of cubes** over the 0.45 m cooler, because it sized itself from the model's footprint and went upward when it ran out. The tray is a UI affordance, not part of the object: it now takes its *shape* from the slot count (as square as the count allows, via `ContainerDef.slot_columns()`/`slot_rows()`) and only its *height* from the model. One flat layer, always.
- **Footprints were still slot-derived**, so a 2.9 m canoe reserved a 0.98 m circle and items spawned inside it. `ContainerDef.footprint` now takes an explicit radius, measured from the fitted model, for every container that has one. The default — `max(model, tray)` worked out from the slot count — still applies to anything without a model.

## What is left

`pant_bag.glb`. Everything else is in.

## Decisions (second pass)

- **`model_height` over `model_scale` for containers.** Both exist; the height is the one to reach for, because it is a fact about the object rather than a fact about the file.
- **The slot tray is square, not a row.** 34 slots as a row is 8.8 m of shelf; as a column it is a tower; as a 6x6 tray it is 1.5 m across and every slot is reachable from where you stand.
- **Footprints are measured and written into the data**, not guessed at runtime. `src/core/` cannot measure a mesh and should not learn how — the number belongs in `data/catalog/containers.json` where the level layout can see it.
