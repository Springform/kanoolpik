# WP-2.8 — Web performance pass

**Phase:** 2 · **Lane:** infra · **Size:** M · **Status:** ✅ done · **Depends on:** everything else in phase 2 (there has to be something to measure)

## Goal
Phase 2's exit criterion is "it still loads in under 10 s on a normal connection". That is a claim, and nobody had checked it. Measure what a player actually downloads, put a budget on it that CI enforces, and fix whatever the measuring turns up.

## Owns (may edit)
- `tools/measure_build.py`, `.github/workflows/ci.yml`
- `tests/integration/test_performance_budget.gd`
- `src/game/items/pickup_item.gd` — only the per-frame label work

## What the numbers actually are

`python3 tools/measure_build.py <export dir>`, gzipped as a static host serves it:

| | on disk | gzipped |
|---|---|---|
| `index.wasm` (the engine) | 37.7 MB | **9.65 MB** |
| `index.pck` (the whole game) | 3.2 MB | **2.78 MB** |
| everything else | — | 0.10 MB |
| **total download** | | **12.53 MB** |

Which is, before decompressing and starting up:

- fibre ≈ 1 s · home DSL ≈ 4 s · **slow 4G ≈ 21 s**

**So the exit criterion is met on a normal home connection and not on mobile data.** Three quarters of the download is the Godot engine, which we do not control without a custom build. The half that is ours — models, audio, content, scripts — is 2.8 MB, and that is the half that grows one model at a time, which is why it has its own budget.

## Delivered

- **`tools/measure_build.py`** — per-file on-disk and gzipped size, three budgets (engine 12 MB, game 4 MB, total 16 MB), and download times at three connection speeds. Non-zero exit over budget.
- **CI step** after the web export, so a model that doubles the download fails the build rather than being noticed by a friend on a train.
- **`tests/integration/test_performance_budget.gd`** — the shape of the scene, which is what actually regresses: node count (~2260, budget 2800), `MeshInstance3D` count (~805, budget 1000), grass still one MultiMesh, shadows still off where they were turned off, source assets under 12 MB.
- **One real fix found by measuring:** all 162 items were doing a camera lookup and a distance test *every frame* to decide whether to draw their name. Now every sixth frame, staggered by instance id so the checks spread out instead of spiking together. A label cannot appear and disappear again in a tenth of a second of walking.

## What this WP could NOT measure, and who has to

**Frame rate.** Headless has no GPU; the software renderer on a CI runner produces a number that says nothing about a real machine. Everything above is about download size and scene shape — necessary, not sufficient.

KA: open the exported build on the oldest laptop the canoe crew owns and watch the frame rate while standing in the middle of the camp looking at the whole island. If it struggles, the levers in order of size are:

1. **Slot cubes on distant containers** — 178 of the ~805 draws. The catch is that a container's slot colours are how you see from across the island that it is finished, so hiding them costs real information. Fade rather than hide.
2. **Tree and bush counts** (`Scenery.TREE_COUNT`, `BUSH_COUNT`) — 60 nodes, each with a trunk and cones.
3. **Grass tufts** — already one MultiMesh and one draw call; raising or lowering `GRASS_TUFTS` moves vertex count, not draw calls.

## Acceptance criteria
- [x] Download size measured, gzipped, per file, with the engine separated from the content.
- [x] Budgets enforced in CI, with a failure that names which budget and by how much.
- [x] Scene-shape budgets covering the things that regress per item and per slot.
- [x] At least one measured problem actually fixed.
- [x] `bash tools/run_tests.sh` green (279); boot check green.
- [ ] Frame rate on real hardware. **Cannot be done from here** — see above.

## The CI step

`.github/workflows/ci.yml` cannot be written remotely, so this is for KA to paste after the web export step:

```yaml
      - name: Download budget
        run: python3 tools/measure_build.py build/web
```
