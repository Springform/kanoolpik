# WP-3.7 — Hidden collectibles

**Phase:** 3 · **Lane:** content/abilities · **Size:** M · **Status:** **done** (2026-09-14, wave 2) · **Depends on:** WP-3.0

## Goal
Four things are hidden on the island that nobody needs to find. Finding one is a small permanent gift: sunglasses, a headlamp, a trolley that carries three more, a whistle. They reward looking at the place rather than sorting it, and they give a second playthrough a reason to exist.

## Owns (may edit)
- `src/game/collectibles/`
- `data/catalog/collectibles.json` (new), `data/levels/island_01.json` — the placement block only
- `assets/i18n/` rows for `collectible.*`
- `tests/unit/core/test_collectibles.gd`, `tests/integration/test_collectibles.gd`

## Must not touch
- `src/core/command_processor.gd` beyond the agreed `collect` handling — coordinate in the WP thread before touching core at all
- The item catalog: a collectible is not an item and must never count toward completion

## Interfaces
**Consumes:** `WorldState`, `Progression`, `GameSession.container_position()` for placement sanity.

**Provides:** `collectible_found { collectible_id, player_id }` on the bus; effects declared as data, not code branches.

## Design notes
- **Placement is hand-authored, not generated.** A hiding place only reads as a hiding place if a person chose it — behind the collapsed tent, under the canoe, in the reeds. Put the four positions in the level JSON.
- Effects reuse what exists: the trolley is `capacity_bonus`, and must compose with `steady_hands` rather than replace it (3 + 2 + 3 = 8, and the arithmetic belongs in one function). Sunglasses and the headlamp are phase-5 hooks — declare them as found and let the shader read the flag later. The whistle is a phase-4 hook; store it, do nothing yet.
- Found state lives with progression, so it saves and replicates with everything else.
- They must be findable without being frustrating: visible from *somewhere* a player would stand, never inside geometry, never requiring a jump the controller cannot make.

## Acceptance criteria
- [ ] Four collectibles exist in the level data, each at a hand-chosen position on walkable ground.
- [ ] Finding one emits the event once; re-entering the area does nothing.
- [ ] The trolley composes with `steady_hands` — capacity is computed in one place and both bonuses apply.
- [ ] Found state survives save and resume.
- [ ] Collectibles never affect completion, accuracy or the island-clean check.
- [ ] Tests: the composition arithmetic, one-shot finding, save round-trip, and that `is_island_clean` ignores them.
- [ ] `tools/run_tests.sh` green; boot check green.

## Playtest checklist (human, 5 min)
- [ ] Find all four without knowing where they are. Time it. If one takes more than three minutes it is hidden badly, not cleverly.

## Decisions

Written by the world-side implementation (the core half — `Progression.COLLECTIBLES`,
`collect`, `capacity_bonus`, `Commands.collect`, `GameEvents.collectible_found` — was
already agreed and built, so this WP touched no core file and added no second place
where capacity is computed).

- **A collectible is not a node type that already exists.** `Collectible` extends
  `Node3D` and shares no code with `PickupItem`: no catalog entry, no collider, no
  name label. The collider is left out for the reason `Dressing` has none (a prop you
  can bump into pins the player, and reads as a 163rd object that refuses to be picked
  up); the label is left out because a floating name over a hiding place is a sign
  saying "here".
- **Finding is proximity, not interaction.** Walking within
  `CollectibleSpawner.FIND_RADIUS` (1.5 m, roughly the interact distance) of one finds
  it — no key, no aiming, no crosshair target. A collectible is a reward for looking at
  the place, so noticing it should be the whole puzzle. The test is a flat distance
  plus a 3 m vertical tolerance rather than an `Area3D`, because a trigger volume the
  player can be pushed through on a container edge is exactly the frustration the WP
  warns about.
- **Placement lives under `collectibles` in the level, as `{id, position, note}`.**
  `position` is flat like `player_spawns` (Y is presentation); the spawner drops each
  one onto the terrain with `Island.height_at`. The `note` is the sentence that says
  which hiding place it is — the only record of *why* a position is that position, and
  a test asserts every placement has one.
- **Two of the four hide behind a container rather than behind dressing.** The WP
  suggests "behind the collapsed tent". The collapsed tent's position is seeded from
  the *mess* seed (`Dressing` re-rolls it per run), so a placement relative to it would
  move under the feet of a hand-authored position. The stable landmarks are the
  containers, which is where the tent bag and the lost-and-found crate come in.
- **The three small ones are drawn bigger than life** (`Collectible.DISPLAY_SCALE`).
  A 14 cm pair of sunglasses on green grass is a smudge you walk past forever. Checked
  on screen under GL Compatibility, not by measuring.
- **The spawner is installed on `Main` next to the abilities**, with the same static
  idempotent `install(parent)`, so a restart cannot leave two sets behind and
  `Main._tear_down` frees it with everything else.

### Integration notes (wave 2)
- **The core half was done up front**, before the agents fanned out, so no one had to touch `src/core/` mid-wave: `Progression.COLLECTIBLES` holds the effects table, `Commands.collect` applies a find, and `capacity_bonus()` adds the trolley to Rolige hænder in the one place that arithmetic lives. Same trick as WP-3.0 owning the input actions.
- **Finding is proximity (1.5 m flat, 3 m vertical), not an `Area3D`** — a trigger volume you can be shoved through on a container edge is the frustration the WP warned about — and not a keypress, which would make a hidden thing need a prompt.
- **Hiding places anchor to containers, not to dressing.** The collapsed tent re-rolls its position from the mess seed, so a hand-authored spot relative to it would move under your feet. The tent bag and the lost-and-found crate are the stable stand-ins.
- The four sit in four distinct regions — shore, fire, tents, back corner — with a `note` field in the level data recording *why* each number is that number. A test asserts every placement has one.
- The three small ones are drawn 1.5–2.4× life size: at true scale they were unreadable smudges next to the furniture-sized trolley. Found by rendering them and looking, per the house rule.
