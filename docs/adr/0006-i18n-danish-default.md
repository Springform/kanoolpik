# ADR 0006 — Danish default UI, all strings via tr() and a CSV

**Status:** Accepted · 2026-09-13

## Context
The players are Danish; the code, docs and comments are English; an English UI should be trivial to add.

## Decision
`assets/i18n/strings.csv` with columns `keys,da,en`, imported by Godot as translations. Fallback locale `da`. Every user-visible string goes through `tr("key")`; item/container names default to `item.<id>` / `container.<id>`.

## Consequences
- The data-integrity test fails when an item or container lacks a name row, so content and translation move together.
- Keys are namespaced (`ui.*`, `item.*`, `container.*`, `ability.*`, `grade.*`) so parallel WPs rarely touch the same rows; the file is append-only by convention.
- Format strings use `%d`/`%s` placeholders and `tr(key) % [args]`.
- A language toggle in settings is a phase 5 item; the plumbing is already there (`TranslationServer.set_locale`).
