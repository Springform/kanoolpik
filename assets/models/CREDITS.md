# Model credits

Every `.glb` under `assets/models/` must have a row here **before or in the same commit as the file**. A model with no row does not ship — `tests/unit/core/test_model_credits.gd` fails the build if the folder and this table disagree (see [ADR 0009](../../docs/adr/0009-third-party-models.md)).

## Rules

- **CC0** and **CC-BY** only. Anything more restrictive — non-commercial, no-derivatives, "free for personal use" — does not come in. If the licence is unclear on the source page, the model does not come in either.
- CC-BY means attribution must reach the **player**, not just this file. Until the credits screen exists (phase 5), this file shipping with the source is the minimum.
- Record the licence as it is stated on the page, with a version if one is given (`CC-BY-4.0`, not "CC-BY-ish").
- Fill the row while you are downloading. Reconstructing provenance afterwards is miserable.
- One model serves many items: 21 cans are one `can.glb` tinted 21 ways. Add the row once.

## How to fill a row

| Column | What goes in it |
|---|---|
| File | Path relative to `assets/models/`, e.g. `items/can.glb` |
| Title | The model's name on the source page |
| Author | The creator as credited there — the name CC-BY obliges us to print |
| Source | Direct URL to the model's page, not the search result |
| Licence | `CC0-1.0`, `CC-BY-3.0`, `CC-BY-4.0`, … exactly as stated |
| Changes | Any modification we made (rescaled, recentred, materials replaced). CC-BY asks that changes be indicated. |

## Items

| File | Title | Author | Source | Licence | Changes |
|---|---|---|---|---|---|
| `items/firewood_1.glb` | Log | J-Toastie | https://poly.pizza/m/ncDQNqeOFj | CC-BY-3.0 | Auto-fitted to the item size budget at load |
| `items/bottle_glass.glb` | Molotov | CreativeTrio | https://poly.pizza/m/jsmWZYqVlM | CC0 | Beer and schnapps bottles |
| `items/bottle_glass_wine.glb` | Bottle of wine | Poly by Google | https://poly.pizza/m/1ZqK8HQ8w65 | CC-BY |  |
| `items/bottle_plastic.glb` | TIME HOTEL 2.9 | S. Paul Michael | https://poly.pizza/m/fOzuRm1Pm-7 | CC-BY |  |
| `items/can_1.glb` | Crushed Soda Can | Thermo_DynAmics | https://poly.pizza/m/F9RZE7EnWl | CC-BY | All 21 empties |
| `items/can_sealed.glb` | Soda can | Poly by Google | https://poly.pizza/m/4kj0P496sYF | CC-BY | The twelve unopened ones |
| `items/life_vest_1.glb` | Life preserver | Poly by Google | https://poly.pizza/m/7n1vrlFN0GH | CC-BY |  |
| `items/paddle_1.glb` | Oar | Poly by Google | https://poly.pizza/m/7qsTvFaVMBY | CC-BY |  |
| `items/sleeping_bag_1.glb` | Bedroll | Kenney | https://poly.pizza/m/efwd5fjuMU | CC0 | Crew A |
| `items/sleeping_bag_2.glb` | Bag | Quaternius | https://poly.pizza/m/VRfAODZ0Xk | CC0 | Crew B |
| `items/tent_canvas.glb` | Wool Carpet | Zsky | https://poly.pizza/m/BEvHkYyR0C | CC-BY |  |
| `items/tent_peg.glb` | Twig | Kenney | https://poly.pizza/m/xApCbtFYP8 | CC0 |  |
| `items/tent_pole.glb` | Tent Frame | Kenney | https://poly.pizza/m/NBUHcJckRV | CC0 |  |

Every model is auto-fitted and set on its own base at load, and repeated models
are rotated by a different angle per item so twenty-one cans do not read as
twenty-one copies of one can. "Changes" records anything beyond that.

## Containers

| File | Title | Author | Source | Licence | Changes |
|---|---|---|---|---|---|
| `containers/can_cooler_1.glb` | Red Cooler, Open with Beer | S. Paul Michael | https://poly.pizza/m/0Hu2-paoIgp | CC-BY |  |
| `containers/can_cooler_2.glb` | Blue Cooler, Open with Beer | S. Paul Michael | https://poly.pizza/m/fkNjLeS1BML | CC-BY |  |
| `containers/canoe.glb` | Canoe | Poly by Google | https://poly.pizza/m/0ciipfLS8Nf | CC-BY | Used for both canoes |
| `containers/cooler.glb` | Ice Box | Bruno Oliveira | https://poly.pizza/m/aahEv9xt6tQ | CC-BY |  |
| `containers/dry_bag.glb` | Backpack | Quaternius | https://poly.pizza/m/2g9Jm7kvIU | CC0 |  |
| `containers/fire_pit.glb` | Bonfire | Quaternius | https://poly.pizza/m/Azj9hJwwwG | CC0-1.0 |  |
| `containers/glass_crate.glb` | Bottles | Quaternius | https://poly.pizza/m/UpU7H3QbAR | CC0 | Texture extracted on import to `glass_crate_Sushi_Atlas.png` |
| `containers/kitchen_box.glb` | Cauldron | Quaternius | https://poly.pizza/m/QaWJOPa6Gt | CC0 |  |
| `containers/pant_bag.glb` | trah bag grey | Jens Kull | https://poly.pizza/m/axTuG36RXnN | CC-BY |  |
| `containers/lost_found.glb` | Floor Hole | J-Toastie | https://poly.pizza/m/FbJAtOQ8pb | CC-BY |  |
| `containers/sleeping_bag_sack.glb` | Backpack | Emmett "TawpShelf" Baber | https://poly.pizza/m/ems9KHrB_4x | CC-BY |  |
| `containers/tent_bag.glb` | Duffel Bag | accidentallyc | https://poly.pizza/m/rysPhwuIP4 | CC0 |  |
| `containers/trash_bag.glb` | Garbage | Poly by Google | https://poly.pizza/m/0QdIPYIA_qe | CC-BY |  |

## Island and scenery

| File | Title | Author | Source | Licence | Changes |
|---|---|---|---|---|---|
| `scenary/tent.glb` | Tent | Quaternius | https://poly.pizza/m/5Q7qIrfDxA | CC0 | The collapsed tent in the camp (WP-2.7). Folder is spelled "scenary"; rename when convenient |

## Generated in this repo

These are ours; no attribution is owed, but they are listed so the folder is fully accounted for.

| File | Generated by |
|---|---|
| `containers/glass_crate_Sushi_Atlas.png` | Extracted by Godot from `glass_crate.glb` on import; same CC0 licence as the model |
| _the island terrain, rocks, trees and grass_ | Built at runtime by `src/game/island/`, not stored as files |
