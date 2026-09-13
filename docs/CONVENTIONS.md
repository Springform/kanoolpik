# Conventions

## GDScript

- Static typing everywhere: parameters, return types (`-> void`), member variables. `var x := expr` only when the type is obvious from a typed expression; `var x: float = dict["k"]` for anything coming out of a Dictionary/Array.
- One class per file. `class_name` for anything referenced from another file. File name is `snake_case` of the class (`PlacementRules` → `placement_rules.gd`).
- Order inside a file: `class_name` / `extends` / doc comment (`##`) → signals → enums → consts → `@export` vars → vars → `@onready` vars → `_init/_ready/_process` → public funcs → private funcs (`_prefixed`).
- Tabs for indentation (Godot default). Two blank lines between functions.
- No `print()` in committed code; use `push_warning`/`push_error` or a debug flag.
- Warnings are failures. Don't shadow built-ins (`seed`, `load`, `name`, `range`, `position` on non-Node classes…).
- Lambdas capture by value — collect results into an `Array` or member.
- Prefer `match` over `if/elif` chains on enums/strings.
- Doc-comment (`##`) every public class and any function whose behaviour isn't obvious from its signature. The doc comment says *what and why*, not *how*.

## Core layer (`src/core/`)

- `extends RefCounted`. No `Node`, `Input`, `tr()`, `preload`, `load`, autoloads, `Time`, `OS`, `Engine`.
- No `push_error` in hot paths; return error codes/verdicts.
- Deterministic: iterate sorted ids; randomness via injected `RandomNumberGenerator`; time via `Commands.tick`.
- Every public function has a test. Mirror path: `src/core/foo.gd` → `tests/unit/core/test_foo.gd`.

## Scenes (`src/game/`)

- One folder per feature: `feature/feature.tscn` + `feature/feature.gd`, plus private sub-scenes.
- The root node's script has `class_name` when other code needs to type-check it (`Player`, `PickupItem`, `ContainerNode`).
- Keep `.tscn` thin. Build repetitive structure in `_ready()` from data.
- Never hand-write `uid="uid://..."` — open the scene in the editor once and let it save, or omit uids.
- Features talk only via `GameEvents` signals and `GameSession` read-only access. Never `get_node("../../OtherFeature")`.
- Node names in code are `PascalCase` (`$Mesh`, `$Slots`); use `@onready var` with typed declarations.
- Input actions are declared in `project.godot` (`move_*`, `jump`, `sprint`, `interact`, `drop`, `ui_toggle_mouse`). New actions: list them in the WP; infra adds them.

## Data (`data/`)

- JSON, 2-space indent, arrays of objects, ids `snake_case`, never renamed.
- Every new item/container id needs a `name_key` row in `assets/i18n/strings.csv` (defaults `item.<id>` / `container.<id>`).
- Levels reference container ids; the data-integrity test enforces consistency.

## i18n

- `tr("ui.hud.progress") % [a, b]`. Keys namespaced by feature. CSV is append-only; never reorder rows.
- Danish is the source language; write English in the same commit.

## Tests

- Suite per source file. Test names read as sentences: `test_ordered_container_rejects_descending_sequence`.
- Use `TestFixtures` for the mini catalog; don't load the real JSON in unit tests (that's `test_data_integrity.gd`'s job).
- Integration tests instantiate real scenes via `auto_free(load(...).instantiate())` and drive them through `GameSession.submit`.

## Git

- Branch per WP: `wp/<id>-<slug>`. Small PRs. Squash-merge to `main`.
- Commit: `<type>(<scope>): <summary>` — `feat|fix|refactor|test|docs|chore|content`.
- Never commit `.godot/`, `build/`, editor binaries. Do commit `.import` files.
- `main` is always green and always deployable to Pages.

## Numbers that are decisions

| Constant | Value | Where |
|---|---|---|
| Base carry capacity | 3 | `GameSession.base_capacity()` |
| Sim ticks per second | 60 (physics step) | `Evaluation.TICKS_PER_SECOND` |
| Score weights | 60 / 25 / 15 | `Evaluation.score()` |
| Par / max time (Island 01) | 600 s / 1800 s | `data/levels/island_01.json` |
| Interact distance | 3.0 m | `Player.interact_distance` |
| Max players | 6 | `data/levels/*.player_spawns` (≥ 6) |
