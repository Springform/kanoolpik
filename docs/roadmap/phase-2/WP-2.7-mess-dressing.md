# WP-2.7 — Mess dressing

**Phase:** 2 · **Lane:** island · **Size:** M · **Status:** ✅ done · **Depends on:** 2.1 (`Island.height_at()`), 2.5 (keep-out rules)

## Goal
Right now the island is a tidy place with 162 objects lying on it. It should look like somewhere six people had a very long night: a tent that went down and stayed down, a mate who never made it into his, the flattened grass where the party was. None of it is pickable — **it is the reason for the mess, not part of it.**

The test is simple: standing on the shore at 00:00, before touching anything, you should be able to guess what happened here.

## Owns (may edit)
- `src/game/island/dressing/`
- `assets/models/scenary/` (the tent KA already sourced), `assets/models/CREDITS.md` (append)
- `assets/audio/sfx/` — one snore loop, `tools/gen_sfx.py`
- `tests/integration/test_dressing.gd`

## Must not touch
- `src/core/`, `src/game/items/`, `src/game/containers/`, `data/` — dressing adds nothing to the catalog, by definition.
- `src/game/island/environment/` (that is WP-2.5's; reuse its keep-out rule rather than editing it).

## Design
Three props, each a sentence of the story:

| Prop | What it says | How |
|---|---|---|
| Collapsed tent | somebody pulled the wrong peg | `scenary/tent.glb`, tipped over, near the tents zone |
| Sleeping mate | he is still out here | a sleeping-bag lump, breathing, with a snore loop |
| Trampled ground | this is where they sat | a flattened, darker patch around the fire |

**Non-interactive means no collider.** A prop with collision can trap the player against a container, or hide an item behind something you cannot pick up, and the player has no way to tell dressing from a 163rd object. They are drawn and nothing else.

**Placement follows the level, not a seed alone.** The tent belongs by the tents zone and the trampled ground around the fire, because those are the places the level says things happened. Only the jitter is seeded.

## Acceptance criteria
- [x] Dressing never stands inside a container footprint, a spawn zone, or a player spawn.
- [x] No dressing prop has a `CollisionObject3D` anywhere under it.
- [x] The same seed produces the same dressing; a different seed moves it.
- [x] Every prop sits on the terrain (`Island.height_at()`), not at y = 0.
- [x] The snore is a local sound on the SFX bus, loops, and dies out well inside the island radius.
- [x] Credits row for the tent; `bash tools/run_tests.sh` green (272); boot check green.

## Playtest checklist
- [ ] From the spawn, the camp reads as a camp before you have picked anything up. *(the sleeping mate reads clearly from the air; not yet judged from standing height)*
- [ ] Nothing dressing-related is ever mistaken for something you can pick up. *(props are capsules and spheres rather than boxes, and carry no floating label — but only play will settle it)*

## Decisions

- **No colliders, deliberately, and enforced by a test** that walks every prop looking for `CollisionObject3D`. Imported `.glb` files can carry collision shapes without asking, so any that arrive are stripped rather than trusted not to exist. A prop you can walk through is strange for about two seconds; a prop that pins you against the cooler ruins a run.
- **Seeded from the mess, not the terrain.** `terrain_seed` is fixed — the island is the same place every time — so seeding dressing from it would have frozen last night in place while the litter moved. It uses `WorldState.rng_seed`.
- **The mate is a lump and a head, not a model.** At the distance you see him from, a capsule that rises and falls reads as a sleeping person more reliably than a badly-proportioned human model would, and it costs nothing to download.
- **The snore is generated, not sourced** (`tools/gen_sfx.py`), built exactly periodic over six seconds the same way the ambience beds are, so the loop has no click.
- **Found and fixed a test that could not fail.** WP-2.6's seam tests decoded `AudioStreamWAV.data` as PCM — but the import compresses to QOA, so they were measuring codec bytes, whose wrap-around delta always resembles their typical delta. They now read the source `.wav`. The loops turn out to be genuinely seamless; the test just was not proving it.
