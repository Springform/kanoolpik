# WP-1.7 — Controller feel

**Phase:** 1 · **Lane:** player · **Size:** S · **Status:** unclaimed

## Goal
Walking around the island feels good: acceleration/deceleration curves instead of instant velocity, optional head bob (off by default, per the reference game's comfort option), FOV and sensitivity exported and read from a `Settings` resource (`user://settings.cfg`), coyote-time jump, sprint FOV kick, footstep events on the bus for audio later.

## Owns (may edit)
- `src/game/player/` (not `_interact()` — WP-1.3 owns that function; coordinate)
- `src/game/settings/settings.gd` (new: load/save `user://settings.cfg`, exposes typed getters)
- `tests/unit/game/test_settings.gd`, `tests/integration/test_player_motion.gd`

## Interfaces
**Consumes:** input actions in `project.godot` (no new actions needed).
**Provides:** `Settings` autoload-free singleton (static `Settings.get()`), `GameEvents.footstep(player_id)` — request the signal in an infra PR first, or emit a local signal on `Player` for now.

## Acceptance criteria
- [ ] Movement is frame-rate independent (test: step `_physics_process` with different deltas → same distance per second within 2 %).
- [ ] Head bob off by default, toggle persists.
- [ ] Sensitivity/FOV changes apply live.
- [ ] Remote-player mode (`is_local = false`) still disables all input processing.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist
- [ ] Stopping feels responsive (no ice-skating). Sprinting feels ~1.6× walk.
- [ ] Jumping onto a 0.5 m rock works; onto a 1.2 m rock doesn't.
