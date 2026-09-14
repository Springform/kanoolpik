# WP-3.1 — Skill point UI and unlock menu (Tab)

**Phase:** 3 · **Lane:** hud · **Size:** M · **Status:** unclaimed · **Depends on:** WP-3.0

## Goal
Tab opens a panel listing the five abilities in Danish: name, cost, one line of what it does, and whether it is owned, affordable or out of reach. Spending a point is one click or one key. The HUD shows the available points at all times, so a player who has just packed a container sees the reward without opening anything.

## Owns (may edit)
- `src/game/hud/skills/`
- `src/game/hud/hud.gd` — **the only phase-3 WP that may touch it**
- `assets/i18n/` rows for `ability.*` and `skills.*`
- `tests/integration/test_skill_menu.gd`

## Must not touch
- `src/core/`, `src/autoload/`, `project.godot` (the `ui_skills` action arrives with WP-3.0)
- `src/game/abilities/` — the effects belong to their own WPs

## Interfaces
**Consumes:** `GameSession.progression` (`available_points()`, `has()`, `can_unlock()`, `ABILITIES`), `GameEvents.points_awarded`, `GameEvents.ability_unlocked`, `GameEvents.progress_changed`. Buying submits `Commands.unlock(GameSession.local_player_id(), ability_id)` — never call `progression.unlock()` directly, or multiplayer will disagree with itself.

**Provides:** `Hud.ability_layer() -> Control` — an empty, full-rect, mouse-ignoring container that ability WPs add their own overlays to (WP-3.3's arrow). This is the extension point that keeps three agents out of `hud.gd`.

## Design notes
- The panel pauses nothing. Standing still is the player's choice; a co-op game cannot stop the world because one person is shopping.
- Feed it from `ABILITIES` rather than hard-coding five entries — the dictionary is the source of truth, and phase 6 will add to it.
- An unaffordable ability is legible, not hidden: seeing that Autopilot costs 3 is what makes packing the next container feel like progress.
- `ability_unlocked` may arrive for another player in phase 4. Update from the event, never from the local click.
- Danish is the default; every string goes through the CSV with an English column.

## Acceptance criteria
- [ ] Tab opens and closes the panel; mouse capture behaves (pointer freed while open, recaptured on close) and the player cannot walk while it is open.
- [ ] Each ability shows name, cost and description from the i18n CSV, in Danish by default and in English after the toggle.
- [ ] Buying an affordable ability submits `unlock`, and the panel updates from `ability_unlocked`, not optimistically.
- [ ] An unaffordable ability cannot be bought, and says why.
- [ ] The HUD point counter tracks `points_awarded` and survives a save/resume.
- [ ] Tests: open/close, affordable vs not, that the click submits a command and that the UI reacts to a *received* `ability_unlocked` for a different player id.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist (human, 5 min)
- [ ] Pack a container, see the counter tick up without opening anything.
- [ ] Open Tab mid-carry: nothing is dropped, nothing is lost.
- [ ] Read every line at 1920×1080 and at a narrow window — no truncation, no missing glyphs (see the font lesson in CLAUDE.md).
