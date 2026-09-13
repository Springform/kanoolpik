# WP-2.2 — Item model kit

**Phase:** 2 · **Lane:** items · **Size:** L · **Status:** unclaimed · **Depends on:** 2.1 (uses `Island.height_at()`, already merged)

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
| `model_scale` | float | `0.0` | Manual override multiplier. `0.0` means "fit automatically" (see below). |
| `tint` | String | `""` | Optional `#rrggbb`. Lets one model serve many items. |
| `model_rotation` | float | `0.0` | Degrees around Y, for models that face the wrong way. |

**Auto-fit is the important one.** Models from asset libraries arrive in arbitrary units — a can may be 0.05 or 50 units tall. On load, read the mesh AABB and scale so its longest axis matches `ItemPalette.box_size(def)`, then recentre so the model sits on its base at the origin. `model_scale` only exists for the cases where auto-fit reads badly. This means KA can drop in a file without measuring anything.

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
- [ ] With **no model files at all**, everything looks and behaves exactly as it does today. Prove it with a test that clears `model` on every item and asserts the island still builds and the vertical slice still passes.
- [ ] A missing, corrupt or non-`.glb` path logs one warning and falls back — never a crash, never an invisible item.
- [ ] Auto-fit: a test loads a deliberately wrong-scaled model (generate one in the test, e.g. a 40-unit cube exported as glTF, or fabricate the AABB) and asserts the instance ends up within the item's size budget.
- [ ] One model, many items: at least one model is shared by several items with different tints, and a test asserts they render differently. **Say in the PR what tint actually does to a textured model** — modulating albedo on a glTF material is not the same as colouring a flat box, and if it looks wrong, say so rather than shipping muddy colours.
- [ ] The same visual is used in the world and in `HeldItems` (what you pick up is what you were looking at).
- [ ] Collision stays a simple box sized to the fitted model. Do **not** generate trimesh collision — the interaction ray only needs something to hit.
- [ ] A model is loaded once and instanced many times; 21 cans do not load 21 resources.
- [ ] `assets/models/CREDITS.md` has a row for every file in `assets/models/`, enforced by `test_model_credits.gd`: walk the folder, parse the table, fail naming any file with no row and any row with no file. Licence field must be `CC0-*` or `CC-BY-*`.
- [ ] Total `assets/models/` size asserted under 8 MB. Today the whole `.pck` is ~2 MB against a 39 MB engine wasm; models are the one thing that can change that.
- [ ] `bash tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Standing in the middle of the island, you can tell what most things are without reading a label.
- [ ] Mixed models and placeholder boxes do not look broken together — a half-populated kit is the normal state for a while.
- [ ] Items still read clearly against the grass at 3–4 m, which is the distance you actually play at.

## Notes for whoever picks this up
- Read ADR 0009 before touching `assets/models/`.
- `.glb` files load as `PackedScene`: `load(path).instantiate()`.
- Godot's default font, `SurfaceTool` tangents and `Label3D` visibility ranges have all bitten this project — see the gotchas list in `CLAUDE.md`, and look at the result on screen before calling it done.
