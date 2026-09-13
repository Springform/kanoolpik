# ADR 0004 — gdUnit4 for tests, run headless in CI

**Status:** Accepted · 2026-09-13

## Context
Godot has no built-in test framework. Options: GUT, gdUnit4, hand-rolled asserts.

## Decision
gdUnit4 (v6.x), vendored under `addons/gdUnit4/` (tests folder stripped), run via `tools/run_tests.sh` locally and in GitHub Actions.

## Why
Fluent assertions, parameterised tests, mocking, a Scene Runner for integration tests, JUnit/HTML reports, and a maintained GitHub Action. Editor integration for humans; CLI for agents and CI.

## Consequences
- Test files live in `tests/unit/core/` (mirroring `src/core/`) and `tests/integration/`. Suites extend `GdUnitTestSuite`.
- Vendoring means upgrades are a deliberate PR; the addon is ~2 MB and excluded from web export.
- The CLI needs `--ignoreHeadlessMode` and `--remote-debug tcp://127.0.0.1:0` (prevents the interactive debugger from hanging CI on a script error). Encapsulated in `tools/run_tests.sh` so nobody has to remember.
