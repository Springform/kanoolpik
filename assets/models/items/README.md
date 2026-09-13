# Item models — what to source and what to call it

Drop `.glb` files here, then add a row to `../CREDITS.md` (required — see [ADR 0009](../../../docs/adr/0009-third-party-models.md)).

**Naming matters only as a convention, not a rule** — `ItemDef.model` in `data/catalog/items.json` is an explicit `res://` path, so any filename works. But if you follow the convention below, wiring 150 items to their models is a script rather than 150 hand edits.

## Convention

```
assets/models/items/<category>.glb              the default for that whole category
assets/models/items/<category>_<variant>.glb    when one shape cannot cover it
assets/models/containers/<container_id>.glb     containers use their id, not a category
```

One model serves a whole category, tinted per item. 21 cans are one `can.glb` in 21 colours, not 21 files.

## The list — 15 item categories

| File | Covers | Items | Notes |
|---|---|---|---|
| `can.glb` | `can` | 21 | A plain drinks can. Tinted per brand, so an unbranded one is ideal. |
| `bottle_plastic.glb` | `bottle_plastic` | 11 | Soft-drink bottle with a cap. |
| `bottle_glass.glb` | `bottle_glass` | 7 | Beer/wine bottle. A second `bottle_glass_wine.glb` would be nice but not needed. |
| `trash_*.glb` | `trash` | 18 | A grab bag — worth 3–4 files: `trash_bag.glb` (crisp packet), `trash_box.glb` (pizza box), `trash_cup.glb`, `trash_paper.glb`. |
| `food_*.glb` | `food` | 12 | Worth 3–4: `food_bread.glb`, `food_bottle.glb` (ketchup), `food_pack.glb`, `food_sausage.glb`. |
| `cookware_*.glb` | `cookware` | 12 | Worth 3: `cookware_pot.glb`, `cookware_pan.glb`, `cookware_utensil.glb`. |
| `clothing_*.glb` | `clothing` | 15 | Worth 3: `clothing_shirt.glb`, `clothing_sock.glb`, `clothing_cap.glb`. |
| `misc_*.glb` | `misc` | 20 | The lost-and-found. Whatever you find that reads clearly at 3 m — sunglasses, wallet, phone, torch. Anything without a model keeps its box, which is fine here. |
| `tent_pole.glb` | `tent_pole` | 4 | A pole or rod. |
| `tent_peg.glb` | `tent_peg` | 6 | A peg. A small rod will do. |
| `tent_canvas.glb` | `tent_canvas` | 1 | A rolled or folded tent. |
| `sleeping_bag.glb` | `sleeping_bag` | 6 | A rolled sleeping bag. |
| `paddle.glb` | `paddle` | 6 | Canoe paddle. |
| `life_vest.glb` | `life_vest` | 6 | Buoyancy aid. |
| `firewood.glb` | `firewood` | 5 | A log or a small bundle. |

## The list — 12 containers

`pant_bag` · `glass_crate` · `trash_bag` · `cooler` · `tent_bag` · `dry_bag` · `canoe` · `canoe_b` · `fire_pit` · `sleeping_bag_sack` · `lost_found` · `kitchen_box`

Both canoes share one `canoe.glb`. Containers matter more per object than items do — there are only twelve and you look at each one dozens of times, so spend the effort here.

## What the loader does for you

- **Scale is automatic.** The model's bounding box is measured and fitted to the item's size budget, then recentred on its base. A model that arrives 0.05 or 50 units tall both end up right. You never measure anything.
- **A missing model is not a bug.** Anything without a file keeps its generated box and stays fully playable. A half-populated kit is the normal state for a while.
- **Prefer one library, or one artist, over the best individual model of each object.** Mixed provenance means mixed styles, and a coherent cheap look beats an incoherent expensive one.

## Still boxes

Five categories have no model yet — `trash` (18 items), `misc` (20), `clothing` (15), `food` (12), `cookware` (12). Each is one `.glb`, one CREDITS row, and `model` set on those items in `data/catalog/items.json`; nothing else has to change and nothing breaks in the meantime.

**Size is stated, not measured.** A category's real-world length lives in `ItemPalette.CATEGORY_LENGTHS` (metres, longest axis) and the model is fitted to it. Add a row there when you add a category — without one it falls back to a guess derived from carry slots, which is how a paddle once ended up 34 cm long.
