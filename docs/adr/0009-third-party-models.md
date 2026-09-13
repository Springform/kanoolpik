# ADR 0009 — Third-party models are allowed, with tracked attribution

**Status:** Accepted · 2026-09-13 · **Amends [ADR 0008](0008-procedural-assets.md)**

## Context
ADR 0008 said all art and audio is generated in code, because the build environment cannot fetch assets and because every download carries a licence that has to be tracked. The first reason still holds for anything an agent produces. The second does not have to: KA can source models by hand from libraries such as poly.pizza, where the licence for each model is stated on its page.

The procedural look got us a playable island, but a can and a sock are currently the same box in different colours. Recognising an object at a glance is most of the puzzle in this game, so the models are worth real fidelity.

## Decision
Hand-sourced 3D models may be committed, in **glTF binary (`.glb`)**, provided that:

1. **Every model is listed in `assets/models/CREDITS.md`** with its name, author, source URL and licence, before or in the same commit as the file itself. A model with no row does not ship.
2. **CC0 and CC-BY are acceptable; anything more restrictive is not** — no non-commercial, no no-derivatives, no "free for personal use". If the licence is unclear, the model does not come in.
3. **Attribution reaches the player**, not just the repo: CC-BY requires it. A credits screen is a phase-5 item; until it exists, `CREDITS.md` shipping with the source is the minimum.
4. **Agents still generate rather than download.** Nothing in the build pipeline fetches assets; a human puts files in the folder.

Anything without a model keeps its generated placeholder. The game must never require a model to be playable.

## Why `.glb`
One binary file carrying geometry, materials and textures, natively imported by Godot 4 with no plugin and no conversion step. `.gltf` is the same format split across several files for no gain; `.obj` loses materials and animation; `.fbx` is proprietary and needs FBX2glTF wired up alongside the editor.

## Consequences
- A licence audit becomes possible at any time by diffing the model folder against `CREDITS.md` — a test enforces that they agree.
- Reuse is mandatory rather than optional: ~150 items map to roughly 25 model files, tinted and scaled per item. One model per item would blow both the download budget and the sourcing effort.
- Mixed provenance means mixed styles. Prefer models from one library, or one artist, over the best individual model of each object.
- If the repo is ever opened up or the game published, the attribution obligation travels with it. That is the cost of the fidelity, and it is why this is a separate, explicit decision rather than a quiet exception to ADR 0008.
