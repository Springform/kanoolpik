#!/usr/bin/env bash
# Run the whole gdUnit4 suite headless. Exit code != 0 on any failure.
#   GODOT_BIN=/path/to/godot tools/run_tests.sh [res://tests/unit/]
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GODOT_BIN:?Set GODOT_BIN to a Godot 4.7 binary}"
TARGET="${1:-res://tests/}"

# First run after clone: import assets so translations/resources exist.
if [ ! -d .godot/imported ]; then
  "$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true
fi

"$GODOT_BIN" --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a "$TARGET" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tee /tmp/kanoolpik_tests.log \
  | grep -E "Run Test Suite|FAILED|ERROR|Overall Summary|SCRIPT ERROR|Parse Error" | grep -v "Remote Debugger" || true

if grep -qE "SCRIPT ERROR|Parse Error|Script errors were detected" /tmp/kanoolpik_tests.log; then
  echo "❌ script errors"; exit 1
fi
if grep -E "Overall Summary" /tmp/kanoolpik_tests.log | grep -qE "[1-9][0-9]* (errors|failures)"; then
  echo "❌ test failures"; exit 1
fi
echo "✅ all tests passed"
