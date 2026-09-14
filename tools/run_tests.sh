#!/usr/bin/env bash
# Run the whole gdUnit4 suite headless. Exit code != 0 on any failure.
#   GODOT_BIN=/path/to/godot tools/run_tests.sh [res://tests/unit/]
#
# Two things here are load-bearing and were both learned the hard way:
#
#   grep -a   gdUnit4 occasionally writes a byte that trips grep's binary-file
#             heuristic. Plain grep then prints "binary file matches" INSTEAD OF
#             THE LINE, the failure check below sees no input, and the script
#             reports "all tests passed" on a red run. That is a green CI line
#             for a broken build, so every grep against the log forces text mode.
#
#   $LOG      The log path is overridable. Two copies of this repo running the
#             suite at once used to write the same file, so one run's verdict
#             could be read out of another's output.
#
# Note also that every copy shares one user:// directory (same config/name), so
# parallel runs still fight over save slots. Set XDG_DATA_HOME per run if you
# really must run two at once — or just run them one at a time.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GODOT_BIN:?Set GODOT_BIN to a Godot 4.7 binary}"
TARGET="${1:-res://tests/}"
LOG="${KANOOLPIK_TEST_LOG:-/tmp/kanoolpik_tests.log}"

# First run after clone: import assets so translations/resources exist.
if [ ! -d .godot/imported ]; then
  "$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true
fi

"$GODOT_BIN" --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a "$TARGET" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tee "$LOG" \
  | grep -a -E "Run Test Suite|FAILED|ERROR|Overall Summary|SCRIPT ERROR|Parse Error" | grep -a -v "Remote Debugger" || true

if grep -a -qE "SCRIPT ERROR|Parse Error|Script errors were detected" "$LOG"; then
  echo "❌ script errors"; exit 1
fi
# A callable connected to a signal with the wrong number of arguments fails at
# EMIT time, so the engine logs an error and the handler silently never runs.
# gdUnit does not fail on that, which is how Klarsyn spent a wave not clearing
# its highlight when an item was taken back out of a container. Always a bug.
if grep -a -q "Error calling from signal" "$LOG"; then
  echo "❌ a signal handler has the wrong signature — see $LOG"; exit 1
fi
# No summary at all means the run died before reporting — never a pass.
if ! grep -a -qE "Overall Summary" "$LOG"; then
  echo "❌ no test summary in $LOG — the run did not finish"; exit 1
fi
if grep -a -E "Overall Summary" "$LOG" | grep -a -qE "[1-9][0-9]* (errors|failures)"; then
  echo "❌ test failures"; exit 1
fi
echo "✅ all tests passed"
