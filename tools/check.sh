#!/usr/bin/env bash
# Everything CI runs, on your own machine, before you push.
#
#   GODOT_BIN=/c/godot/godot.exe tools/check.sh
#
# Runs in Git Bash on Windows as well as in a Linux shell. Takes about two
# minutes against CI's eight, and — unlike CI — tells you before a broken build
# has already deployed itself to Pages.
#
# The steps mirror .github/workflows/ci.yml one for one. If you change one,
# change the other, or this stops being a check and becomes a comfort.
#
# NOTHING HERE SKIPS QUIETLY. A missing toolchain fails the run. A check that
# cannot fail is worse than no check, and a check that shrugs and passes when it
# could not do its job is the same thing wearing a hat. If you genuinely mean to
# leave a step out, say so:
#
#   KANOOLPIK_SKIP_RELAY=1   node/npm not installed, or you did not touch infra/
#   KANOOLPIK_SKIP_EXPORT=1  export templates not installed locally
set -euo pipefail
cd "$(dirname "$0")/.."

: "${GODOT_BIN:?Set GODOT_BIN to a Godot 4.7.1 binary, e.g. /c/godot/godot.exe}"

step() { printf '\n\033[1m── %s\033[0m\n' "$1"; }
fail() { printf '\033[31m❌ %s\033[0m\n' "$1"; exit 1; }

step "Godot version"
"$GODOT_BIN" --version

step "Import (assets, translations, .godot/)"
# CI tolerates a non-zero exit here because a first import reports missing
# dependencies it then resolves on the second pass. Same bargain locally.
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true

step "Godot suite"
GODOT_BIN="$GODOT_BIN" bash tools/run_tests.sh

step "Relay suite"
if [ "${KANOOLPIK_SKIP_RELAY:-0}" = "1" ]; then
  echo "skipped by KANOOLPIK_SKIP_RELAY=1"
elif ! command -v npm >/dev/null 2>&1; then
  fail "npm not on PATH. Install Node ≥ 20, or set KANOOLPIK_SKIP_RELAY=1 if you meant to."
else
  relay_log="${TMPDIR:-/tmp}/kanoolpik_relay.log"
  (
    cd infra/relay
    [ -d node_modules ] || npm ci --no-audit --no-fund
    set +e
    npm test 2>&1 | tee "$relay_log"
    exit "${PIPESTATUS[0]}"
  ) || fail "relay tests"
  # The compatibility date in wrangler.toml is what a deploy runs on. If the
  # pinned wrangler ships an older workerd, miniflare falls back to what it has
  # — and the suite goes GREEN while proving things about a runtime nobody
  # ships. It is a warning, not an error, so nothing else catches it. Verified
  # by mutation: with the date set forward, 17 tests still passed.
  if grep -q "Falling back to" "$relay_log"; then
    grep -B1 "Falling back to" "$relay_log"
    fail "the tests did not run on production's runtime — upgrade wrangler, or lower compatibility_date in infra/relay/wrangler.toml"
  fi
fi

step "Web export"
if [ "${KANOOLPIK_SKIP_EXPORT:-0}" = "1" ]; then
  echo "skipped by KANOOLPIK_SKIP_EXPORT=1"
else
  mkdir -p build/web
  # --export-release writes the build; a missing export template is the usual
  # first-run failure and says so plainly in the output.
  if ! "$GODOT_BIN" --headless --path . --export-release "Web" build/web/index.html; then
    fail "export failed — install the 4.7.1 export templates (Editor → Manage Export Templates), or set KANOOLPIK_SKIP_EXPORT=1"
  fi
  [ -s build/web/index.html ] || fail "export produced no index.html"
  # Phase 2's budget, enforced in CI: the whole thing gzipped under 15 MB.
  total=0
  while IFS= read -r -d '' f; do
    size=$(gzip -c "$f" | wc -c)
    total=$((total + size))
  done < <(find build/web -type f -print0)
  printf 'gzipped total: %s MB\n' "$(awk "BEGIN{printf \"%.1f\", $total/1048576}")"
  [ "$total" -lt 15728640 ] || fail "web build over the 15 MB gzipped budget"
fi

step "Play it"
cat <<'EOF'
  python -m http.server 8000 --directory build/web
  → http://localhost:8000

Not file:// — the Godot web export needs real HTTP. Both the page and
`wrangler dev` on localhost are plain http, so wss/mixed-content does not
bite here; it only bites once the page is on Pages.
EOF

printf '\n\033[32m✅ everything CI would run is green\033[0m\n'
