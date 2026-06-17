#!/bin/bash
# init-audit.sh (v4.0.0)
# Phase 0 initializer: creates audit_state.json, validates baseline, discovers tests
#
# Usage:
#   init-audit.sh --mode=deep [--scope=<module>] [--force]
#
# Modes: emergency | quick | incremental | deep | continuous
# Default: deep (recommended for first audit)

set -uo pipefail

MODE="${AUDIT_MODE:-deep}"
SCOPE="${AUDIT_SCOPE:-$(basename "$PWD")}"
CACHE=".audit-cache"
FORCE="${FORCE_REINIT:-0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode=*) MODE="${1#*=}"; shift ;;
    --scope=*) SCOPE="${1#*=}"; shift ;;
    --force) FORCE=1; shift ;;
    *) shift ;;
  esac
done

STATE_FILE="$CACHE/audit_state.json"

# Skip if exists and not forced
if [ -f "$STATE_FILE" ] && [ "$FORCE" != "1" ]; then
  echo "[init] State exists: $STATE_FILE (use --force to recreate)"
  echo "[init] Current phase: $(jq -r '.current_phase' "$STATE_FILE")"
  exit 0
fi

mkdir -p "$CACHE"

# Generate audit_state.json
cat > "$STATE_FILE" <<STATEEOF
{
  "run_id": "$(uuidgen 2>/dev/null || date +%s)_${SCOPE}",
  "scope": "$SCOPE",
  "mode": "$MODE",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "current_round": 0,
  "current_phase": "PHASE_0_ENTRY",
  "findings": {},
  "test_coverage": {},
  "phases_passed": {
    "PHASE_0_ENTRY": false,
    "PHASE_1_SBL": false,
    "PHASE_1_5_TEST_PYRAMID": false,
    "PHASE_2_REVIEW": false,
    "PHASE_3_ARBITRATION": false,
    "PHASE_4_FIX": false,
    "PHASE_4_5_TEST_AUTHOR": false,
    "PHASE_5_STATIC": false,
    "PHASE_5_5_SMOKE": false,
    "PHASE_5_6_DYNAMIC": false,
    "PHASE_5_7_CHAOS": false,
    "PHASE_5_8_MUTATION": false,
    "PHASE_6_LOOP": false,
    "PHASE_6_5_DEVIL_ADVOCATE": false,
    "PHASE_7_FINAL": false
  },
  "gates_passed": {},
  "cannot_fix_queue": [],
  "deferred_queue": []
}
STATEEOF

# Discover existing tests
echo "[init] State created: $STATE_FILE"
echo "[init] Mode: $MODE"
echo "[init] Scope: $SCOPE"

# Discover existing test structure
TEST_DIRS="tests/unit tests/integration tests/contract tests/e2e tests/property tests/chaos"
found=0
for d in $TEST_DIRS; do
  if [ -d "$d" ]; then
    count=$(find "$d" -name "*.test.*" 2>/dev/null | wc -l | tr -d ' ')
    echo "[init]   $d: $count test files"
    found=$((found + 1))
  fi
done
echo "[init] Test layers found: $found (need ≥4 for Phase 1.5)"

# Run baseline check (Phase 0.5 prep)
if [ -x "$(dirname "$0")/baseline-diff.sh" ]; then
  echo "[init] Running baseline-diff.sh scope..."
  bash "$(dirname "$0")/baseline-diff.sh" scope 2>/dev/null || true
fi

echo "[init] Phase 0 complete. Next: gate-check PHASE_0_ENTRY"
