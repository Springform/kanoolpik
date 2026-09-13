# WP-1.5 — End-of-level evaluation screen + restart

**Phase:** 1 · **Lane:** hud / flow · **Size:** M · **Status:** unclaimed · **Depends on:** 1.4

## Goal
On `island_clean`: release the mouse, fade in "Lejrlederens vurdering" with completion, accuracy, time, total points and the grade text (`grade.*` keys), animated count-up, then buttons "Igen (samme ø)", "Ny rodebutik (nyt seed)", "Til start". Numbers come from `Evaluation.score(catalog, state, par, max)` using the level's `par_seconds`/`max_seconds`.

## Owns (may edit)
- `src/game/hud/evaluation/` (new)
- `src/game/main/main.gd` — only to add `restart(seed)` and `to_title()` helpers
- `tests/integration/test_evaluation_screen.gd`

## Interfaces
**Consumes:** `GameEvents.island_clean`, `Evaluation.score`, `GameSession.level` (par/max), `GameSession.start_level`.
**Provides:** `Main.restart(seed: int)`; the title WP (1.6) will call `Main.to_title()`.

## Acceptance criteria
- [ ] Screen appears only on `island_clean`; player input is disabled behind it.
- [ ] Shows the same numbers a unit test computes from the same state (integration test compares).
- [ ] "Igen" restarts with the same seed → identical mess (assert via `state.to_dict()` equality of ground positions).
- [ ] "Ny rodebutik" uses `randi()` seed and shows the seed so friends can share it.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Count-up animation is skippable with a click.
- [ ] The grade text lands as a punchline, not a spreadsheet.
