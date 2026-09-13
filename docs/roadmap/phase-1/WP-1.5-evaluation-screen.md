# WP-1.5 — End-of-level evaluation screen + restart

**Phase:** 1 · **Lane:** hud / flow · **Size:** M · **Status:** done (Claude, 2026-09-13) · **Depends on:** 1.4

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
- [x] Screen appears only on `island_clean`; player input is disabled behind it.
- [x] Shows the same numbers a unit test computes from the same state (integration test compares).
- [x] "Igen" restarts with the same seed → identical mess (assert via `state.to_dict()` equality of ground positions).
- [x] "Ny rodebutik" uses `randi()` seed and shows the seed so friends can share it.
- [x] `tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Count-up animation is skippable with a click.
- [ ] The grade text lands as a punchline, not a spreadsheet.

## Notes / decisions
- **Not `get_tree().paused`.** The first attempt paused the tree and hung the whole test suite, because a global pause also freezes the timers gdUnit4 (and the count-up) rely on. The level is *finished*, not suspended, so the screen calls `GameSession.stop_level()` instead: the clock stops, `submit()` is blocked, and `Player` returns early from `_input`/`_physics_process` while `GameSession.is_running()` is false. A real pause belongs to WP-1.6's pause menu.
- `Main` is now a real class that owns island/player/hud/evaluation and rebuilds them. Teardown uses `free()`, not `queue_free()`: a queued node is still connected to `GameEvents` and would react to the next level's events (there is a test for this). Restart is called deferred from the button signal, since it frees the node handling that signal.
- `Main.restart_same_island()` / `restart_new_mess()` replace the sketched `restart(seed)`; `to_title()` waits for WP-1.6, so the third button ("Til start") is not there yet.
- `Evaluation.grade_key(grade)` added to core (one small pure function) so presentation never assembles i18n keys itself.
- Static labels and button captions are set in `_ready()` via `tr()` rather than typed into the `.tscn`, otherwise they would not translate.
- **Scoring observation worth keeping:** accuracy is 25 % of the score, so a single wrong placement in a ~58-placement run costs under half a point and rounds away to 100. That is the intended forgiveness; there is a test naming it so nobody "fixes" it by accident. Verified on screen: 98 % accuracy still reads 100 point.
