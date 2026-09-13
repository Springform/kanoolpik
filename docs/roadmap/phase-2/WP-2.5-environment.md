# WP-2.5 — Environment: trees, grass, reeds

**Phase:** 2 · **Lane:** island/environment · **Size:** M · **Status:** done (Claude, 2026-09-13)

## Goal
The island should look like somewhere you would actually camp — pines, grass underfoot, reeds where the land meets the lake — **without making the litter harder to find.** This game is about spotting objects; scenery that competes for attention makes it worse, not better.

## Owns
- `src/game/island/environment/` · `tests/integration/test_scenery.gd`
- `src/game/island/island.gd` — two lines to build the scenery and to enlarge the water plane

## What was built
All generated from `Island.terrain_seed` (ADR 0008), placed through `Island.height_at()`:

- **Grass:** ~4 000 tufts in a single `MultiMesh` (one draw call). Three crossed blades each, 0.17 m tall.
- **Trees:** ~34 low-poly pines — tapered trunk, three stacked cones. Trunks collide; foliage does not, so a branch can never trap the player.
- **Bushes:** ~26 mounds of three overlapping spheres, no collision — you walk straight through them.
- **Reeds:** ~90 taller clumps in a 2.2 m band inside the shoreline.
- Water plane grown from 400 m to 2 000 m: its edge was visible from the title camera at 26 m.

## The rule that matters
**Scenery never stands where the game happens.** Solid things keep clear of container footprints (+2.5 m), of the spawn zones where items land (+1 m), and of player spawns (4 m). Grass is exempt from the zone rule — it is ankle-high and may grow among the litter — but still keeps a smaller distance from containers. Tests assert all of it, including that no item spawns inside a tree.

## Acceptance criteria
- [x] Deterministic for a seed (test builds two islands and compares tree positions).
- [x] Grass is one `MultiMesh`, not thousands of nodes.
- [x] Nothing solid stands on a container, in a spawn zone, or on a player spawn.
- [x] No item spawns inside a tree.
- [x] Trees block the player; bushes do not.
- [x] `bash tools/run_tests.sh` green (229); boot check green. `.pck` still 2.1 MB.

## Notes / decisions
- **The grass came out as a field of near-black spikes on the first attempt.** Blades are vertical, so shading them by their own face normals lit them like walls. Every grass normal now points straight **up**, borrowing the ground's normal, which is the standard trick for stylised foliage — it makes grass catch the same light as the terrain and read as part of it. There is a test pinning this, because it is invisible to every other kind of check. (Godot compresses mesh normals, so the test compares direction, not equality.)
- Blades were also shortened (0.26 → 0.17 m) and lightened to just above the terrain colour. Grass should read as texture on the ground, not as objects competing with the litter you are hunting for.
- Meshes are built by hand from arrays rather than with `SurfaceTool`, which bakes a zero tangent array and silently kills lighting under GL Compatibility (see `CLAUDE.md`).
- Not done here: sky and water shaders, wind sway. Wind needs a vertex shader and is worth doing when someone is looking at the whole environment; the current still grass is calm rather than dead.

## Playtest checklist
- [ ] Walk a full lap. No tree you get stuck on, no bush that hides an item.
- [ ] Grass does not make small items (socks, pegs) harder to spot at 3–4 m.
