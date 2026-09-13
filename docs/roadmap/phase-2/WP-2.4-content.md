# WP-2.4 — Content expansion to ~150 items

**Phase:** 2 · **Lane:** data · **Size:** L · **Status:** unclaimed

## Goal
Grow Island 01 from 57 items / 8 containers to roughly 150 items / 12 containers, so the island tells the story of the night: two canoes with their own paddle sets, sleeping bags that go in ordered, a firewood pile, a lost-and-found for one-offs. More series, more ordered containers, more "who has the fourth tent pole?".

## Owns (may edit)
- `data/catalog/items.json`, `data/catalog/containers.json`, `data/levels/island_01.json`
- `assets/i18n/strings.csv` (append only — never reorder or edit existing rows)
- `tests/unit/core/test_data_integrity.gd`

## Must not touch
- `src/` anything. If the content needs a new rule (a new verdict, a container that accepts a category conditionally), stop and write it in the PR — that is a core WP, not this one.
- `assets/audio/`, `src/game/island/`

## Interfaces
**Consumes:** the rules exactly as they are — category → series → sequence (`docs/GAME_DESIGN.md` §3).
**Provides:** a bigger catalog. Everything else reads it through `Catalog`.

## Acceptance criteria
- [ ] ~150 items, ~12 containers. Every item has a Danish **and** English name row.
- [ ] `test_data_integrity.gd` passes unchanged in spirit: catalog validates, every category has exactly one home (or the multi-home case is deliberate and tested), every container has slots for everything that belongs in it, no lone item can pack a container.
- [ ] Container footprints do not overlap and all sit on the island — `test_island_layout.gd` must stay green. Footprint radius comes from `ContainerDef.footprint_radius()`; do not hardcode sizes.
- [ ] Spawn zones tell a story: cans near the fire, tent parts by the tents, paddles at the shore. Weights tuned so nothing important lands in one unfindable corner.
- [ ] Ordered containers: at least two (tent bag, sleeping bags), with contiguous 1..n sequences.
- [ ] A full clean is still achievable in roughly 15–25 minutes solo. State your estimate and how you arrived at it in the PR — par/max seconds in the level file should match.
- [ ] `bash tools/run_tests.sh` green; boot check green.

## Notes
Item ids are permanent public identifiers (they appear in saves and network messages): **never rename an existing one**, only add. Keep the humour dry — the hangover is the punchline, not the drinking.

## Playtest checklist
- [ ] Nothing is so well hidden that you need luck rather than observation.
- [ ] 150 items does not turn the HUD counter into noise.
