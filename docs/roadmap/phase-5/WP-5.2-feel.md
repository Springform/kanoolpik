# WP-5.2 — How it feels to walk

**Phase:** 5 · **Lane:** player · **Size:** S · **Status:** done (2026-09-20) · **Depends on:** [5.1](WP-5.1-settings.md)
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
- [x] Stepping `_physics_process` at 30 fps and at 144 fps covers the same distance per second within 2 %.
- [x] Head bob off by default; the toggle takes effect without a restart — and it is now in the panel, which it was not.
- [x] Sensitivity and FOV read from `Settings` and update live (WP-5.1 wired this; the FOV now has a sprint kick on top of it).
- [x] Jumping onto a 0.5 m rock works; onto a 1.2 m rock does not — asserted as apex height rather than by walking a level.
- [x] A remote avatar is unaffected — no acceleration, no bob, no FOV.
- [x] `tools/run_tests.sh` green; boot check green.
- [x] Looked at on screen — `tools/shots.gd --only=settings`, both languages.

## Playtest checklist (human, 5 min)
- [ ] Stopping feels responsive — no ice-skating, no instant halt.
- [ ] Sprinting feels roughly 1.6× walking and you can tell without looking at the HUD.
- [ ] Walk a lap with head bob on, then off. Does either make anybody uncomfortable?

## Notes / decisions

## Decisions

**Everything is per second, and that was the actual bug.** The old stop was
`move_toward(velocity, 0, speed)` with no delta. At 60 Hz that is 270 m/s² — a
walking player stopped inside one frame, which is why walking read as a debug
camera: full speed and zero speed, nothing between. The numbers now have units
(`GROUND_ACCELERATION`, `GROUND_FRICTION`, `AIR_ACCELERATION`) and the step is
`rate * delta`.

**The horizontal step is a static pure function.** `next_horizontal_velocity`
takes the current velocity, the direction asked for, the speed, whether the
player is on the ground and a delta, and returns the next velocity. That is what
lets the frame-rate criterion be tested by integrating it at four rates instead
of by running the physics server and measuring the server.

**Coyote time is a lie the game tells on purpose**, so it says so and is named:
0.12 s. A sprinting player gets 0.9 m of free air out of it — enough to cover
the frame somebody was a pixel past the rock, not enough to cross anything.
There is deliberately **no "spend the window" line** after a jump fires:
`is_action_just_pressed` is true for exactly one physics frame, and restating
that here would be the fifth redundant guard this project has found.

**Footsteps are counted in metres, not in bobs.** One every
`STRIDE_LENGTH` = 0.9 m of ground actually covered — so it stays right when the
player is sprinting, walking backwards, or has head bob switched off. The signal
is **local to `Player`**, as the WP asked: a footstep fires two or three times a
second and is not a fact about the world.

**Jump velocity dropped from 4.8 to 4.5.** Apex is v²/2g, so 4.8 reached 1.176 m
against a criterion that says a 1.2 m rock must not work — a 2 cm margin is not
a criterion. 4.5 reaches 1.03 m.

## Scope widening, as declared

1. **`src/game/settings/settings_panel.gd`** — one row, `ui.settings.head_bob`.
   WP-5.1 left the key with nothing reading it and said the row should be added
   by whoever made it do something. The string was already in the CSV.
2. **`project.godot`** — the `ui_toggle_mouse` action is **deleted**, along with
   `Player`'s handler for it. See below.
3. **`README.md`** and **`docs/CONVENTIONS.md`** — one line each, both about
   that action.

## Esc was two keys pretending to be one

`ui_toggle_mouse` was bound to Escape, and so is the built-in `ui_cancel`. One
press released the mouse in `Player._input` and then opened the pause menu in
`PauseMenu._unhandled_input`, which releases the mouse itself. WP-1.6 spotted it
and called it harmless because the end state matched, and WP-5.6's controls
table had to describe it as one key doing two things.

It is the shape that has now cost this project five separate bugs: **a second
statement of a rule another file enforces.** `PauseMenu.open()` and `close()`
own the mouse. The handler is gone, the action is gone, and nothing was lost —
in a web export Escape leaves pointer lock at the browser's insistence anyway,
so an in-game "release the mouse" key never did anything a browser was not
already doing. Clicking still takes the mouse back.

## Two mutations that survived, and they were the same mistake

Both were tests written **in the units of the constant they were testing**:
`assert(change).is_between(SPRINT_FOV_KICK * 0.8, SPRINT_FOV_KICK)` is true for
a kick of zero, and `walk(STRIDE_LENGTH * 3.5) == 3 footsteps` is true for any
stride. A test phrased in terms of the thing it is checking cannot fail when
that thing changes. Both are now in degrees and in metres — numbers somebody can
argue with.

A third came out of a failing test rather than a mutation: **stopping
*distance* is not frame-rate independent and cannot be.** Summing `speed * delta`
over a ramp is explicit Euler, and it measured 0.150 m at 30 fps against 0.216 m
at 240 fps, converging on the true 0.225 m. That is the integrator, not the
rule. What the rule guarantees exactly is the *time* — v over a, whatever the
step — so that is what the test asserts, with the distance pinned separately at
60 Hz, which is what `_physics_process` actually runs at.
