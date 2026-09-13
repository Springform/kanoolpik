# Contributing

Humans and agents follow the same flow; the agent-specific detail is in `CLAUDE.md`.

1. **Pick a WP** from `docs/ROADMAP.md` whose dependencies are done. Mark it `in progress (@you)` in the WP file in your first commit so nobody else takes it.
2. **Branch** `wp/<id>-<slug>` from `main`.
3. **Stay in your lane** — edit only the folders the WP owns. Need something else? Say so in the PR; infra changes (`project.godot`, `src/autoload/`, new `GameEvents` signals) go in a separate small PR that lands first.
4. **Test** — `GODOT_BIN=... tools/run_tests.sh` must print `✅ all tests passed`. Add tests for what you built.
5. **Boot check** — `godot --headless --path . --quit-after 120` exits 0 without `SCRIPT ERROR`.
6. **PR** using the template. Paste the `Overall Summary` line. Attach a screenshot/GIF for anything visual.
7. **Merge** — squash to `main`. CI exports web and deploys Pages automatically.
8. **Close the loop** — set the WP status to `done`, record decisions under `## Notes / decisions`.

Local setup: Godot 4.7.x standard build. First run `godot --headless --path . --import`. Optional: enable the gdUnit4 panel in the editor (already enabled in project settings) to run tests with a click.

Content contributions (items, containers, levels) need no editor: edit `data/*.json`, add i18n rows, run the tests.
