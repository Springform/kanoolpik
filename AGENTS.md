# Agent guide — Kanoølpik

You are one of several agents working in parallel on a Godot 4.7 game. Read this whole file before touching anything. `AGENTS.md` is identical.

## The one rule that keeps parallel work safe

**Every task is a work package (WP) in `docs/roadmap/phase-N/`. A WP lists the folders it *owns*. Edit only those folders.** If you must touch something outside them (a shared scene, `project.godot`, `src/autoload/`), stop and say so in the PR description — do not silently widen scope. Two agents editing the same `.tscn` file is the only merge conflict Godot cannot resolve cleanly.

## Architecture in 30 seconds

```
Input/scene  →  GameSession.submit(Commands.x(...))  →  Transport  →  CommandProcessor.apply(state, cmd)
                                                                              │
Scenes react ←  GameEvents.<signal>  ←  GameSession publishes events  ←  result.events
```

- `src/core/` is **pure GDScript**: `RefCounted` classes, no `Node`, no `Input`, no `tr()`, no scene paths, no autoload access. Everything there must be deterministic and unit tested. This is what makes multiplayer possible later; guard it jealously.
- `WorldState` is the only truth. **Nothing mutates it except `CommandProcessor`.** Scenes never call `state.set_*`.
- Presentation (`src/game/*`) subscribes to `GameEvents` and reads `GameSession.state`/`catalog` read-only.
- Content lives in `data/*.json`. Adding an item = editing JSON + one i18n row. `tests/unit/core/test_data_integrity.gd` will tell you if you broke it.
- Full detail: `docs/ARCHITECTURE.md`. Decisions and their reasons: `docs/adr/`.

## Definition of done (every PR)

1. `GODOT_BIN=... tools/run_tests.sh` → `✅ all tests passed`. Paste the `Overall Summary` line in the PR.
2. New logic in `src/core/` has tests in `tests/unit/core/` (mirror the file name: `foo.gd` → `test_foo.gd`).
3. New scene behaviour is covered by, or at least does not break, `tests/integration/test_vertical_slice.gd`.
4. The project boots: `godot --headless --path . --quit-after 120` exits 0 with no `SCRIPT ERROR`.
5. Zero new GDScript warnings. Static types everywhere (`var x: int`, `-> void`).
6. User-facing strings go through `tr("key")` with a row in `assets/i18n/strings.csv` (Danish + English).
7. WP acceptance criteria ticked in the PR body (`.github/pull_request_template.md`).

## Godot-specific gotchas (learned the hard way)

- Invoke scripts as `bash tools/run_tests.sh` — the repo is edited from Windows, so executable bits are not reliable.
- Run `godot --headless --path . --import` once after cloning or after adding assets; otherwise translations and imports are missing and tests fail confusingly.
- Don't name variables `seed`, `load`, `range`, `name` etc. — they shadow built-ins and produce warnings (we treat warnings as failures).
- Untyped `Dictionary` values can't be inferred: `var x := d["k"]` fails to parse. Write `var x: float = d["k"]`.
- Lambdas capture locals **by value**. Collect results into an `Array` or use a member variable.
- `.tscn` files are text. Keep them thin — build node trees in `_ready()` from data where reasonable — and never hand-write `uid=` attributes (let Godot generate them).
- Web export uses the **GL Compatibility** renderer and **no threads** (so GitHub Pages works without COOP/COEP headers). Don't use `Thread`, `WorkerThreadPool` or Forward+-only features.
- Use `Array[String]`/typed arrays in signatures; pass `Array` literals directly (Godot infers). A `.map()` result is untyped: annotate as `Array`.
- **Look at it on screen before calling it done.** This has caught real bugs three times: Godot's default font has no Dingbats/Geometric Shapes glyphs, so ▶ ✓ ✕ drew as *nothing* while string assertions passed (use Latin-1: × » –); `Label3D` ignores `visibility_range_end` under GL Compatibility — the property sets fine and changes nothing; and 150 item labels turned the island into a wall of text that no test would ever flag.
- Building a custom `ArrayMesh` via `SurfaceTool.commit_to_arrays()` bakes in an all-zero `ARRAY_TANGENT`, which **silently breaks lighting** under GL Compatibility (the mesh renders flat black despite correct normals). Build the arrays by hand and omit tangents.
- Freeing a node from inside its own signal fails with "Attempted to free a locked object" — connect anything that rebuilds a screen with `CONNECT_DEFERRED`.
- A `Shape3D` (or any resource) declared inside a `.tscn` is a **sub-resource shared by every instance** of that scene. 150 items all wrote to one `BoxShape3D` and the last to spawn decided collision for all of them. Build per-instance resources in `_ready()` with `.new()`.
- Measure meshes with local transforms accumulated up to the node, never `global_transform` — the answer must not depend on whether the node is in the tree yet.
- Tinting an imported glTF *multiplies* its albedo, so it darkens as much as it colours. Placeholders get the category colour; models keep their own unless the item asks for a tint.
- **A panel whose height is typed into the `.tscn` outgrows its own background.** Adding two buttons to the title screen pushed three controls past the panel art and onto the island, with every string assertion green; the screenshot pass caught it. Use `set_anchors_and_offsets_preset(PRESET_CENTER, PRESET_MODE_MINSIZE)` and let the container measure itself.
- `get_tree().paused` is right for a pause menu and wrong for "level finished". **No test may `await` while the tree is paused** — the awaited timer never fires and the suite hangs.

## How to pick up work

1. Read `docs/ROADMAP.md`, choose an unclaimed WP whose dependencies are done.
2. Branch `wp/<id>-<slug>` (e.g. `wp/1.2-placement-feedback`).
3. Read the WP file fully; note *Owns*, *Must not touch*, *Interfaces*.
4. Implement, test, run DoD, open PR with the template. Small PRs beat big ones.
5. If the WP turned out to be under-specified, write what you decided in the WP file under a `## Decisions` heading — that's documentation for the next agent.

## Commit messages

`<type>(<scope>): <summary>` — types: feat, fix, refactor, test, docs, chore, content. Scope = the folder or WP id. Example: `feat(items): show carried items stacked in hand (WP-1.1)`.
