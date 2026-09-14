# WP-3.10 — Test mode and the admin panel

**Phase:** 3 · **Lane:** tooling · **Size:** M · **Status:** **done** (2026-09-14, session 3) — 397 tests green

## Goal
A build can be checked a piece at a time instead of played from the top. F1 opens a panel that hands out skill points, buys abilities, packs the whole island bar one item, jumps the clock, shows the evaluation and teleports to a container. The win condition stops costing a full tidy-up to reach.

It was built because the ending of the game had never been seen. 162 items is twenty minutes of honest play to verify one signal, so it never got verified.

## Owns
- `src/dev/` — `test_mode.gd`, `test_panel.gd`
- `src/core/commands.gd`, `command_processor.gd` — one gated command
- `src/autoload/game_session.gd` — sets the gate
- `src/game/main/main.gd`, `src/game/title/title_screen.gd` — installing it and offering it
- `project.godot` (`ui_test_panel`, F1), `assets/i18n/strings.csv`
- `tests/integration/test_test_mode.gd`, additions to `tests/unit/core/test_command_processor.gd`

## The rule the panel obeys
**Every world change is a submitted command, exactly like a keypress.** The panel never writes to `WorldState` or `Progression`. Two reasons, and the second is the one that matters:

1. A peer replaying the command list lands in the same place, cheats included, so test mode stays usable in phase 4 rather than desyncing the party.
2. **It exercises the real code paths.** A panel that poked the state directly would "pass" through code the game never runs, and a bug it missed would still be waiting for the first player. `pack_all_but_one()` issues 300-odd ordinary `pick_up` / `place` commands; that is why the win-condition test is worth anything.

Presentation-only conveniences — teleporting, opening the evaluation screen — are direct, because a camera position is not world state.

## The one new command
`Commands.grant_points(player_id, points)`, refused unless `CommandProcessor.allow_debug_commands` is set. The flag defaults to **false** and `GameSession` sets it from `TestMode.is_enabled()` at level start, which in multiplayer makes it the host's decision — a client cannot talk the authority into accepting a debug command it has not enabled itself.

Buying an ability from the panel grants only the shortfall and then submits an ordinary `unlock`, so the purchase path under test is the real one.

## Availability, which is separate from enablement
| | |
|---|---|
| `TestMode.is_available()` | a property of the build |
| `TestMode.is_enabled()` | a choice on the title screen, defaulting to on wherever it is available |

Available in: any debug build; any build launched with `--test-mode` (how the suite turns it on without pretending to be a debug build); and a **release web build only when the page is opened with `?test=1`**.

A release web build with a plain URL has no way in. The code still ships in it — that is the price of being able to debug the real browser build on the oldest laptop in the canoe crew — so this is a lock on the door, not a claim that the room is not there. If that stops being an acceptable trade, gate the whole `src/dev/` folder out of the export instead and lose web debugging with it.

## What it does
- **Pack all but one** — leaves the item *nearest the player*, so finishing it is a walk and not an expedition. Items already correctly placed are skipped, and anything with no correct slot free is left alone rather than forced somewhere wrong.
- **Points and abilities** — +1 / +3 / +10, and one button per ability.
- **Clock** — 5 / 15 / 25 / 45 minutes, straddling every grade boundary. Forward only: `tick` cannot express going back, and the panel does not pretend otherwise.
- **Show the evaluation now** — the score as the run stands, with the world untouched.
- **Containers** — how many items each is still waiting for, and a button to stand next to it.

## Acceptance criteria
- [x] The panel exists when test mode is on and does not when it is off — and with it off, `grant_points` is refused by the processor as well, not just hidden in the UI.
- [x] `grant_points` is refused by default, accepted with the flag, cannot be negative, and replays identically on two peers.
- [x] Packing all but one leaves exactly one item out, and the island does **not** count as clean.
- [x] Putting that last item away emits `island_clean` and brings up the evaluation screen. **This is the assertion the work package exists for.**
- [x] Buying an ability with no points tops up only the shortfall and goes through the ordinary unlock command.
- [x] The clock moves the speed score and never goes backwards.
- [x] `tools/run_tests.sh` green (397); boot check green.

## Playtest checklist (human, 5 min)
- [ ] F5, F1, "Pak alt på nær én ting", walk to the survivor, put it away — watch the canoes and the verdict.
- [ ] Buy each ability from the panel and try it: F, R, and Tab.
- [ ] Set the clock to 45 min with a clean island and check the grade copy at the bottom band.
- [ ] Turn test mode off on the title screen and confirm F1 does nothing.

## Notes / decisions
- **`src/dev/` is a new top-level folder.** Developer tooling is neither core nor game; keeping it separate makes "what would we strip from a release build" a one-line answer.
- **The panel is built in code, not as a `.tscn`.** Its contents follow `Progression.ABILITIES` and the container list, and a scene file would be one more thing to keep in step with them.
- **The title-screen toggle is also built in code**, because it exists only in builds where test mode is available. A node in the scene would have to be hidden in every other build, which is the same thing said less clearly.
- **The panel is freed in `Main._tear_down()`** along with the abilities — same reasoning as the wave-1 leak: it subscribes to `GameEvents`.
- **Mutation-checked.** Making `pack_all_but_one` pack everything, and forcing `allow_debug_commands` on, each turned the suite red on the guard written for it.
- The `?test=1` check goes through `JavaScriptBridge`, which only exists on the web export, so it is guarded by `OS.has_feature("web")`.
