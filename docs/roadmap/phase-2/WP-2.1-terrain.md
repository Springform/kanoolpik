# WP-2.1 — Procedural island terrain

**Phase:** 2 · **Lane:** island · **Size:** L · **Status:** done (Claude, 2026-09-13)

## Goal
Replace the gray-box cylinder with an island that reads as a *place*: a low-poly landmass with a beach that meets the water, gentle height variation, and a few rocks. Generated in code from a seed (ADR 0008: no downloaded assets), so it is deterministic, diffable and weighs nothing in the web build. Walking over it must feel the same as the flat version — no invisible walls, nothing you can get stuck on.

## Owns (may edit)
- `src/game/island/` (all of it, including `island.gd` and `island.tscn`)
- `tests/integration/test_terrain.gd` (new)

## Must not touch
- `data/` — WP-2.4 owns every data file this wave. Terrain shape parameters go in `@export` vars on `Island` for now, with a `# TODO(2.4): move to level data` comment.
- `src/core/`, `src/autoload/`, `src/game/items/`, `src/game/containers/`, `assets/i18n/`, `project.godot`

## Interfaces
**Consumes:** `GameSession.island_radius()`, `GameSession.ground_y()`, `GameSession.state.location(id)["position"]`, `GameSession.container_position(cid)`.
**Provides — other WPs depend on this, keep the signature:**
```gdscript
## Ground height at a point on the island, in world units.
func height_at(x: float, z: float) -> float
## True when the point is on walkable land (inside the shoreline).
func is_on_land(x: float, z: float) -> bool
```
Items and containers keep their XZ from the world state; `Island` lifts them to `height_at()` when spawning them. The Y in `WorldState` stays flat — height is presentation, not world state.

## Acceptance criteria
- [x] Terrain is generated from a seed; the same seed gives the same mesh (test it).
- [x] `height_at()` agrees with the collision surface: drop a body from above at 20 sampled points and it comes to rest within 0.15 m of `height_at()`.
- [x] Every container position and every generated item position is on land and reachable — extend/keep the guarantees in `test_island_layout.gd` (do not weaken that file; if a container would now sit on a slope too steep to walk, say so in the PR rather than moving it yourself — that is 2.4's file).
- [x] Slopes stay walkable: no face steeper than ~40°, verified by sampling normals.
- [x] The player still spawns on solid ground and the fall-in-the-lake respawn still triggers only over water.
- [x] Vertex count is budgeted and asserted (< 20 000 for the island mesh) — the web build has to stay small.
- [x] `bash tools/run_tests.sh` green; `godot --headless --path . --quit-after 150` exits 0 with no SCRIPT ERROR.

## Playtest checklist
- [ ] Walk the whole shoreline: no place where you fall through, stick, or climb something you shouldn't.
- [ ] The island reads as a place, not a disc. You can tell roughly where you are without the HUD.

## Decisions

Things the WP text didn't spell out, decided while implementing:

- **Shape.** A radial "dome" (higher near the centre, tapering to zero at
  `island_radius`) plus low-frequency Perlin noise (`FastNoiseLite`, seeded
  from `terrain_seed`), clamped to a `min_land_height` above sea level. This
  guarantees every point with `r <= island_radius` is land by construction —
  the existing radius-based guarantees in `test_island_layout.gd` keep
  working untouched. Beyond `island_radius` the height is smoothstep-blended
  down to a flat sea floor over `beach_width` metres, giving the "beach that
  meets the water" the goal asks for.
- **`is_on_land(x, z)`** is defined as `height_at(x, z) > ground_y()` (i.e.
  physically "above sea level"), not a bare radius check. It agrees with the
  radius check everywhere inside `island_radius` (guaranteed by
  `min_land_height`), but also gives a physically meaningful answer out in
  the beach band, which a future WP walking the literal shoreline may want.
- **Grid + `HeightMapShape3D`.** `cell_size = 1.0` so the render mesh and the
  `HeightMapShape3D` collision are built from the exact same height grid,
  centred at the origin the same way — this is what keeps `height_at()`
  and collision in agreement (measured max error ≈ 0.02 m in testing, well
  inside the 0.15 m budget). Grid extends `island_radius + beach_width +
  terrain_margin`; with the current level's `island_radius = 16`, that's a
  45×45 grid (2025 vertices, budget is 20000).
- **Container/item slopes.** Checked every container position and every
  currently-generated item position in `island_01` against the new terrain:
  the steepest container sits on a 6° slope (`dry_bag`), and no item spawns
  on anything over ~10°. Nothing needed to move; `test_island_layout.gd` is
  unchanged and still green.
- **Rocks are visual only** (no collision). They're small, sparsely placed
  away from containers, and the WP only asked for the island to "read as a
  place" — giving them collision felt like scope creep for an L-sized WP.
  Worth revisiting if playtesting finds them lets you \"hide\" behind one.
- **Gotcha worth flagging for later terrain/mesh work:** building a custom
  `ArrayMesh` via `SurfaceTool.commit_to_arrays()` includes an all-zero
  `ARRAY_TANGENT`, which silently breaks all lighting on that surface under
  the GL Compatibility renderer (confirmed by an xvfb screenshot: the mesh
  rendered as flat black despite correct normals). Fix was to build the
  vertex arrays by hand and only set `ARRAY_VERTEX`/`ARRAY_NORMAL`/
  `ARRAY_COLOR`/`ARRAY_TEX_UV`/`ARRAY_INDEX`, leaving tangents unset.
- **Vertex-color terrain shading** (sand/grass/rock by height+slope)
  over-exposed badly under the default `Environment` (ACES tonemap + a
  fairly bright default `DirectionalLight3D`) — colours are toned down
  (`Color(0.62, 0.54, 0.36)` sand, etc.) accordingly; this environment is
  scoped to `island.tscn` only.
