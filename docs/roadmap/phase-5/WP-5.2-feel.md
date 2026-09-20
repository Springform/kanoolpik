# WP-5.2 — How it feels to walk

**Phase:** 5 · **Lane:** player · **Size:** S · **Status:** unclaimed · **Depends on:** [5.1](WP-5.1-settings.md)
> **Supersedes the motion half of [WP-1.7](../phase-1/WP-1.7-controller-feel.md).** The settings half is WP-5.1.

## Goal
Walking stops feeling like a debug camera. Acceleration and deceleration instead of velocity appearing and vanishing in one frame, a short coyote time so a jump at the edge of a rock still fires, a small FOV kick while sprinting, and head bob for whoever wants it — off by default, because it is the one option that makes some people feel ill.

## Owns (may edit)
- `src/game/player/player.gd` (not `interact_with*` — WP-1.3's functions; coordinate)
- `tests/integration/test_player_motion.gd`

## Must not touch
`src/core/` · `src/game/player/remote/` (a remote player's position arrives on the wire and is never simulated — WP-4.5) · `src/game/settings/`.

## Interfaces
**Consumes:** `Settings.get_float("look.sensitivity")`, `look.fov`, `look.head_bob` (WP-5.1), and `Settings.changed` to apply them live.
**Provides:** a local `signal footstep(position)` on `Player`, for audio to pick up later. **Do not add a `GameEvents` signal for it** — a footstep is not a core event, it fires several times a second, and `GameEvents` is the bus every peer's presentation listens on.

## Design notes
- **Frame-rate independence is the acceptance criterion, not a nicety.** The web export's frame rate varies with the tab, and `move_toward(velocity, 0, speed)` without a delta is a speed that depends on the machine.
- **Head bob defaults to off.** The reference game offers it as a comfort option for a reason.
- **Sprint FOV kick is small and fast in, slow out.** A big one reads as a bug.
- The local player is the only one this touches: `is_local = false` already disables input and physics, and WP-4.5 made remote players a different node entirely.
- Coyote time is a number — say what it is and why, in a named constant, the way `PresenceSender.RATE_HZ` does.

## Acceptance criteria
- [ ] Stepping `_physics_process` at 30 fps and at 144 fps covers the same distance per second within 2 %.
- [ ] Head bob off by default; the toggle takes effect without a restart.
- [ ] Sensitivity and FOV read from `Settings` and update live.
- [ ] Jumping onto a 0.5 m rock works; onto a 1.2 m rock does not.
- [ ] A remote avatar is unaffected — no acceleration, no bob, no FOV.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist (human, 5 min)
- [ ] Stopping feels responsive — no ice-skating, no instant halt.
- [ ] Sprinting feels roughly 1.6× walking and you can tell without looking at the HUD.
- [ ] Walk a lap with head bob on, then off. Does either make anybody uncomfortable?

## Notes / decisions
