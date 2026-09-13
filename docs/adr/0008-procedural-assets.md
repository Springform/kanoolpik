# ADR 0008 — Assets are generated in code, not downloaded

**Status:** Accepted · 2026-09-13 · **Amended by [ADR 0009](0009-third-party-models.md)**, which allows hand-sourced `.glb` models with tracked attribution. Everything an agent produces is still generated in code.

## Context
Phase 2 needs an island, item and container models, ambience and music. The development environment cannot fetch arbitrary files from asset sites, and even where it could, every downloaded asset carries a licence that has to be tracked, attributed and kept compatible with a repo we may open up later.

## Decision
All art and audio for phases 2–3 is **generated in code**: meshes composed from primitives or from seeded noise, audio synthesised by scripts under `tools/`. No binary asset is committed that a script in the repo cannot regenerate.

## Why
- No licensing surface at all: everything is ours, and the generator is the source of truth.
- Generators diff and review like code; a 200-line script replaces a 4 MB binary.
- The web build stays small, which ADR 0007 cares about.
- A seeded generator gives variation for free (rocks, trees, the shape of the island).
- The look is honest about what it is — stylised low-poly toy — rather than a mismatch of scavenged styles.

## Consequences
- The ceiling on visual fidelity is lower than hand-made models. Accepted: this is a game for six friends, and a coherent cheap look beats an incoherent expensive one.
- `ItemDef.model` and `ContainerDef.scene` already point at `res://` scenes, so swapping in real `.glb` files later is a data change, not a code change. If KA supplies models, they drop in without touching the systems.
- Generators must be deterministic and committed alongside their output, and a test should assert the output still matches what the generator produces.
- Audio generated this way is serviceable, not beautiful. Revisit before any public release.
