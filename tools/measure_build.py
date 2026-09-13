#!/usr/bin/env python3
"""Measure what a player actually downloads, and fail the build if it grows too much.

    python3 tools/measure_build.py build/web

The number that matters is not the size on disk, it is the size **over the
wire**. GitHub Pages serves gzip, so a 39 MB wasm is really a 10 MB download —
measuring the uncompressed file would have us optimising the wrong thing, and
measuring nothing at all is how a project wakes up one day with a 60 MB page.

Budgets are deliberately a little above where we are, so ordinary work does not
trip them and a real regression does. Raise one only with a reason in the commit
message.
"""
import gzip
import pathlib
import sys

# Bytes, gzipped, as served.
BUDGET_TOTAL = 16 * 1024 * 1024
# The engine itself. We do not control this without a custom build; it is here so
# a Godot upgrade that adds 5 MB is visible rather than silent.
BUDGET_ENGINE = 12 * 1024 * 1024
# Everything that is ours: scenes, scripts, models, audio, content.
BUDGET_GAME = 4 * 1024 * 1024


def transfer_size(path: pathlib.Path) -> int:
    """Bytes on the wire: gzip at a level a static host would plausibly use."""
    return len(gzip.compress(path.read_bytes(), 6))


def human(n: int) -> str:
    return f"{n / 1048576:.2f} MB"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    root = pathlib.Path(argv[1])
    files = sorted((p for p in root.rglob("*") if p.is_file()), key=lambda p: p.name)
    if not files:
        print(f"no files in {root} — did the export run?")
        return 2

    engine = game = total = 0
    print(f"{'file':<36}{'on disk':>12}{'gzipped':>12}")
    for f in files:
        raw = f.stat().st_size
        wire = transfer_size(f)
        total += wire
        if f.suffix in (".wasm", ".js"):
            engine += wire
        else:
            game += wire
        print(f"{f.name:<36}{human(raw):>12}{human(wire):>12}")

    print()
    checks = [
        ("engine (wasm + js)", engine, BUDGET_ENGINE),
        ("game (pck + page)", game, BUDGET_GAME),
        ("total download", total, BUDGET_TOTAL),
    ]
    failed = False
    for label, value, budget in checks:
        state = "ok " if value <= budget else "OVER"
        if value > budget:
            failed = True
        print(f"[{state}] {label:<22}{human(value):>10}  budget {human(budget)}")

    # What that means for the exit criterion, at connection speeds friends have.
    print()
    for name, mbit in (("slow 4G", 5), ("home DSL", 25), ("fibre", 100)):
        print(f"  {name:<10} ~{total * 8 / (mbit * 1_000_000):.1f} s to download")
    print("\n(Download only — decompressing and starting the engine is on top of this.)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
