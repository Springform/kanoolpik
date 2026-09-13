# ADR 0005 — Content as JSON, validated by tests

**Status:** Accepted · 2026-09-13

## Context
Items, containers and levels will grow from 57 items to hundreds and be authored by several agents at once. Godot's native `Resource` (.tres) files are editor-friendly but verbose, uid-laden and conflict-prone in git.

## Decision
`data/catalog/items.json`, `data/catalog/containers.json`, `data/levels/<id>.json`. `Catalog.from_dicts()` builds the domain from plain arrays; `test_data_integrity.gd` validates every file on every test run (orphan categories, non-contiguous sequences, missing positions, missing i18n keys, insufficient slots).

## Consequences
- Adding content is a JSON edit plus an i18n row; no editor session needed; agents can do it blind and the tests tell them if it is wrong.
- 3D models are referenced by `res://` path in `ItemDef.model` / `ContainerDef.scene` — the JSON stays the source of truth, scenes are just skins.
- No editor tooling for content yet; if the catalog outgrows hand-editing, a WP can add a generator script or an editor plugin without changing the format.
- Ids are permanent public identifiers (they appear in saves and network messages): never rename, only add.
