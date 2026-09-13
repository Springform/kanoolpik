# WP-1.6 — Title screen, seed entry, pause, restart

**Phase:** 1 · **Lane:** flow · **Size:** M · **Status:** unclaimed

## Goal
The game opens on a title screen (`ui.title`, background = a slow camera drift over the island) with "Start oprydningen", an optional seed field, language toggle (da/en via `TranslationServer.set_locale`) and a settings stub. Esc in game opens a pause menu (resume / restart / title). `main.tscn` becomes a tiny state machine: TITLE → PLAYING → EVALUATION.

## Owns (may edit)
- `src/game/title/` (new), `src/game/main/` (state machine; keep it small)
- `assets/i18n/strings.csv` — append `ui.title.*`, `ui.pause.*`
- `tests/integration/test_flow.gd`

## Must not touch
- `src/core/`, `src/autoload/`, `src/game/player/` (the pause menu just toggles `get_tree().paused` and mouse mode)

## Interfaces
**Consumes:** `GameSession.start_level/stop_level`, `GameEvents.level_loaded`.
**Provides:** `Main.to_title()`, `Main.start_game(seed)`; `Main.state` enum for tests.

## Acceptance criteria
- [ ] Boot → title; Start → island; Esc → pause; restart from pause reproduces the same seed.
- [ ] Player scene is not instantiated on the title screen (no captured mouse).
- [ ] `process_mode` set so the pause menu works while the tree is paused.
- [ ] Language toggle swaps UI strings live.
- [ ] Integration test drives TITLE → PLAYING → TITLE through `Main` methods.
- [ ] `tools/run_tests.sh` green; boot check green (`--quit-after` on the title screen must still exit 0).

## Playtest checklist
- [ ] Mouse capture/release never gets stuck.
- [ ] Title reads well in both languages.
