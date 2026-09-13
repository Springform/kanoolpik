# WP-2.3 — Container models

**Phase:** 2 · **Lane:** containers · **Size:** M · **Status:** unclaimed · **Depends on:** 2.2 (uses `ItemVisual`)

## Goal
The pant bag looks like a bag, the cooler like a cooler, the canoe like a canoe. Containers are the destinations you navigate by, so they matter more per object than the items do — there are only twelve of them and you look at each one dozens of times.

## Owns (may edit)
- `src/game/containers/` · `assets/models/containers/` · `assets/models/CREDITS.md` (append rows)
- `data/catalog/containers.json` — only to populate `scene` / scale / rotation; no new containers
- `tests/integration/test_container_models.gd`

## Must not touch
- `src/game/items/` (you *use* `ItemVisual`, you do not change it), `src/game/island/`, `src/core/`, `src/autoload/`

## Acceptance criteria
- [ ] Uses `ItemVisual.build()` from WP-2.2 rather than a second loader.
- [ ] **The slots stay aimable and stay where the model's opening is.** This is the hard part: `SlotNode`s currently sit in a row above a box lid at `SLOT_HEIGHT`. With a real model they must follow its shape, and the interaction ray must still reach them before the body (see WP-1.3's notes — slots inside the container's own collision box are unreachable).
- [ ] Placement feedback still reads: flash, gold completion, `×` markers all visible against the model.
- [ ] Footprint still matches `ContainerDef.footprint_radius()`, which the level layout and the mess generator both depend on. If a model wants a different footprint, change the *data*, re-run the layout, and keep `test_island_layout.gd` green.
- [ ] No model → today's translucent box, exactly as now.
- [ ] Credits rows present; `bash tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] You can find the container you want from across the island by its silhouette.
- [ ] Aiming at a specific slot is no harder than it is with the boxes.
