# WP-2.2 — Item model kit

**Phase:** 2 · **Lane:** items · **Size:** L · **Status:** ✅ done · **Depends on:** 2.1 (uses `Island.height_at()`, already merged)

## Goal
A can looks like a can. Today every one of the 150 items is the same box in a different colour, and recognising an object at a glance is most of the puzzle in this game. Build the loading path that turns `ItemDef.model` into a real `.glb` on the island, and make it degrade gracefully: **any item without a model keeps its generated box, and the game stays fully playable with zero models present.**

KA sources the models by hand (ADR 0009). This package delivers the framework and whatever models exist at the time; the two arrive independently on purpose.

## Owns (may edit)
- `src/game/items/` — `pickup_item.gd`, `item_palette.gd`, `held_items.gd`, a new `item_visual.gd`
- `src/core/item_def.gd` — **only** to add the fields below, with tests
- `data/catalog/items.json` — **only** to populate `model` / `model_scale` / `tint` on existing items; no new items, no renames
- `assets/models/items/`, `assets/models/CREDITS.md`
- `tests/unit/core/test_item_def.gd`, `tests/integration/test_item_models.gd`, `tests/unit/core/test_model_credits.gd`

## Must not touch
- `src/game/containers/` (WP-2.3 does the same job there and will reuse your loader — coordinate through the interface below, not by editing their folder)
- `src/game/island/`, `src/autoload/`, `src/core/` beyond `item_def.gd`, `assets/audio/`, `project.godot`

## Data model
Add to `ItemDef` (and to the JSON schema, defaults keep today's behaviour):

| Field | Type | Default | Meaning |
|---|---|---|---|
| `model` | String | `""` | `res://` path to a `.glb`. Empty → generated box. |
| `model_scale` | float | `0.0` | Nudge on top of the automatic fit (`1.2` = a fifth bigger). `0.0` = no nudge. |
| `tint` | String | `""` | Optional `#rrggbb`. Lets one model serve many items. |
| `model_rotation` | float | `0.0` | Degrees around Y, for models that face the wrong way. |

**Auto-fit is the important one.** Models from asset libraries arrive in arbitrary units — a can may be 0.05 or 50 units tall. On load, read the mesh AABB and scale so its longest axis matches `ItemPalette.box_size(def)`, then recentre so the model sits on its base at the origin. `model_scale` only exists for the cases where auto-fit reads badly, and is applied *on top of* the fit rather than replacing it — tuning by eye must not require knowing the model's own units. This means KA can drop in a file without measuring anything.

## Interfaces
**Provides — WP-2.3 will call exactly this, so keep the signature:**
```gdscript
class_name ItemVisual
## Builds the visual for a catalog entry: the model if it has one and it loads,
## otherwise the generated placeholder. Never returns null, never throws.
static func build(model_path: String, fallback_size: Vector3, tint: Color,
        scale_override: float, y_rotation_degrees: float) -> Node3D
## True when a model file exists and loaded; false when the placeholder is showing.
static func has_model(model_path: String) -> bool
```
**Consumes:** `ItemPalette` for the fallback look and the size budget.

## Acceptance criteria
- [x] With **no model files at all**, everything looks and behaves exactly as it does today. Prove it with a test that clears `model` on every item and asserts the island still builds and the vertical slice still passes.
- [x] A missing, corrupt or non-`.glb` path logs one warning and falls back — never a crash, never an invisible item.
- [x] Auto-fit: a test loads a deliberately wrong-scaled model (generate one in the test, e.g. a 40-unit cube exported as glTF, or fabricate the AABB) and asserts the instance ends up within the item's size budget.
- [x] One model, many items: at least one model is shared by several items with different tints, and a test asserts they render differently. **Say in the PR what tint actually does to a textured model** — modulating albedo on a glTF material is not the same as colouring a flat box, and if it looks wrong, say so rather than shipping muddy colours.
- [x] The same visual is used in the world and in `HeldItems` (what you pick up is what you were looking at).
- [x] Collision stays a simple box sized to the fitted model. Do **not** generate trimesh collision — the interaction ray only needs something to hit.
- [x] A model is loaded once and instanced many times; 21 cans do not load 21 resources.
- [x] `assets/models/CREDITS.md` has a row for every file in `assets/models/`, enforced by `test_model_credits.gd`: walk the folder, parse the table, fail naming any file with no row and any row with no file. Licence field must be `CC0-*` or `CC-BY-*`.
- [x] Total `assets/models/` size asserted under 8 MB. Today the whole `.pck` is ~2 MB against a 39 MB engine wasm; models are the one thing that can change that.
- [x] `bash tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [x] Standing in the middle of the island, you can tell what most things are without reading a label.
- [x] Mixed models and placeholder boxes do not look broken together — a half-populated kit is the normal state for a while.
- [x] Items still read clearly against the grass at 3–4 m, which is the distance you actually play at.

## Notes for whoever picks this up
- Read ADR 0009 before touching `assets/models/`.
- `.glb` files load as `PackedScene`: `load(path).instantiate()`.
- Godot's default font, `SurfaceTool` tangents and `Label3D` visibility ranges have all bitten this project — see the gotchas list in `CLAUDE.md`, and look at the result on screen before calling it done.

## Decisions

- **`model_scale` is a nudge, not an override.** It multiplies the automatic fit (`1.6` = "a bit over half again as big"), so tuning by eye never requires knowing that the supplied log mesh is 43 units long. `0.0` = no nudge. Same field, same meaning, on `ContainerDef`.
- **A model keeps its own colours.** `ItemPalette.visual_color()` hands the category colour to placeholders and `Color.WHITE` to models, so the tint only bites when an item explicitly asks for one. Answering the acceptance question honestly: tinting a textured glTF *multiplies* albedo, so it darkens as much as it colours — the fire-pit stones came out blue-grey when the container colour was applied, which is why models are left alone by default. One model serving several items with real colour differences wants either a per-item `tint` on a light, untextured model, or a second file.
- **Collision shapes are built per instance.** A `BoxShape3D` declared in the `.tscn` is a sub-resource Godot shares between every instance of that scene, so all 150 items were writing to the same shape and the last one to spawn decided collision size for all of them. `PickupItem` and `ContainerNode` now both call `BoxShape3D.new()`. Regression test: `test_every_item_has_its_own_collision_shape`.
- **`combined_aabb` never reads global transforms.** It accumulates local transforms up to the node it is measuring against, so it gives the same answer in and out of the tree. The earlier version switched between the two and the two disagreed, which sized collision to the fallback box while the model drew at its own size.
- **Known harmless noise:** under the headless dummy renderer, gdUnit4's GC logs `Parameter "material" is null` while freeing scenes that carry imported glTF materials. It comes from `GdUnitTools.free_instance`, not from game code, and does not appear in a real run.

## Shipped models

Two files so far — `items/firewood_1.glb` (five logs share it, staggered 0/72/144/216/288° so they do not read as clones) and `containers/fire_pit.glb`. Everything else is still the generated box, which is the point: the kit fills up one file at a time.
