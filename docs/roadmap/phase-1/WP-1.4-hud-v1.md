# WP-1.4 — HUD v1 (Danish)

**Phase:** 1 · **Lane:** hud · **Size:** M · **Status:** unclaimed

## Goal
Replace the placeholder HUD with a clean, readable one: top-left progress ("23 af 57 ting på plads" + a thin bar), bottom-left carrying ("Bærer 2/3" with tiny icons), centre-bottom context prompt ("[E] Læg i Pantpose"), top-centre toast for verdicts and completions, and a small elapsed timer. All strings via `tr()`; all layout in a `Theme` resource so phase 5 can restyle without touching code.

## Owns (may edit)
- `src/game/hud/` (everything; you may restructure `hud.tscn`)
- `assets/ui/theme.tres`, `assets/ui/fonts/` (a free font with Danish glyphs — check æøå render)
- `assets/i18n/strings.csv` — append `ui.hud.*` rows only
- `tests/integration/test_hud.gd`

## Must not touch
- `src/core/`, `src/autoload/`, other feature folders. Verdict colours come from `containers/verdict_style.gd` (WP-1.2) — if it isn't merged yet, define a local copy and leave a TODO to swap.

## Interfaces
**Consumes:** `GameEvents.progress_changed/item_placed/container_completed/island_clean/command_rejected/local_player_spawned`, `Player.aimed_target()`, `Player.carried_items()`, `GameSession.processor.carried_load()`, `Evaluation.progress()`.
**Provides:** `HUD.show_toast(text, seconds)` for other features.

## Acceptance criteria
- [ ] Every string in the CSV in both `da` and `en`; æ/ø/å render correctly.
- [ ] Prompt updates within one frame of aiming at a different target.
- [ ] Works at 1280×720 and at 1920×1080 and in a narrow browser window (anchors, not absolute pixels).
- [ ] Rejected `hands_full` shows "Hænderne er fulde" not the raw error id (map error ids → keys).
- [ ] Integration test: emit `progress_changed` → label text matches; emit `item_placed` wrong → toast contains the wrong-category text.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Nothing important sits under the crosshair.
- [ ] Toasts don't stack into a wall of text when placing quickly.
