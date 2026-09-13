Container models go here; see `../items/README.md` for the naming convention and `../CREDITS.md` for the attribution rules.

## The shopping list

One `.glb` per container, named `<container_id>.glb`. Twelve in total:

| File | What it is | Slot layout |
|---|---|---|
| `pant_bag.glb` | Sack for deposit cans and bottles | grid |
| `glass_crate.glb` | Crate for glass | grid |
| `trash_bag.glb` | Bin bag | grid |
| `cooler.glb` | Cool box | grid |
| `tent_bag.glb` | Tent bag | grid |
| `dry_bag.glb` | Roll-top dry bag | grid |
| `canoe.glb` | Canoe (also used for `canoe_b`) | grid |
| `fire_pit.glb` ✅ | Stone ring / bonfire | ring |
| `sleeping_bag_sack.glb` | Stuff sack | grid |
| `lost_found.glb` | Box of everything left over | grid |
| `kitchen_box.glb` | Camp-kitchen crate | grid |

## Wiring one up

In `data/catalog/containers.json`, on that container:

```json
"scene": "res://assets/models/containers/cooler.glb",
"slot_layout": "grid",
"model_rotation": 90.0
```

- `scene` — the path. That is all a model needs; the size is measured and fitted automatically.
- `slot_layout` — `"grid"` (the default, so it can be left out) or `"ring"` for something you gather round. Slots are placed above the model either way; `SlotLayout` works out the spacing and stacks them upward when the footprint runs out of room.
- `model_scale` — a nudge on top of the automatic fit, if it reads too big or too small. `1.2` = a fifth bigger.
- `model_rotation` — degrees around Y, if the model faces the wrong way.

Then run `godot --headless --path . --import` once so the `.glb.import` file exists, add the CREDITS row, and run the tests.

**Footprints come from the data, not the model.** `ContainerDef.footprint_radius()` is what keeps containers apart and keeps items from spawning inside one, and it is derived from `slot_count`. If a model wants more room than that, the honest fix is to change the footprint constants and re-check `test_island_layout.gd` — not to shrink the model until it fits.
