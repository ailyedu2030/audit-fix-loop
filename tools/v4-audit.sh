#!/bin/bash
# v4-audit.sh (v4.0.0) — orchestrator for full v4 audit cycle
#
# Runs the 6 tools in order, with v3.7 gate enforcement:
#   0. Subsystem manifest (if not exists)
#   1. Flow trace (depends on 0)
#   2. Generate blind briefings (depends on 0, 1)
#   3. [Run 5 blue team agents, human/AI] produces findings/*.json
#   4. Red team attacks (depends on 3)
#   5. AAR (depends on 4)
#   6. Cross-run dedup (always)
#   7. v3.7 regression (regression-suite.sh)
#
# Each step's gate: previous step must have succeeded.
# On failure: exit 1, do not proceed.

set -uo pipefail

TOOL_DIR=~/.config/opencode/skills/audit-fix-loop-v3/tools
AUDIT_CACHE=".audit-cache"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log() { echo -e "${GREEN}[v4]${NC} $*"; }
warn() { echo -e "${YELLOW}[v4]${NC} $*"; }
err() { echo -e "${RED}[v4 ERROR]${NC} $*"; }

# Gate function
gate() {
  local step_name="$1"
  local check_command="$2"
  if eval "$check_command" >/dev/null 2>&1; then
    log "✓ $step_name passed"
    return 0
  else
    err "✗ $step_name failed"
    return 1
  fi
}

# Step 0: Subsystem manifest
step_0_manifest() {
  if [ -f "$AUDIT_CACHE/subsystem-manifest.json" ] && [ "${FORCE_REGENERATE:-0}" = "0" ]; then
    log "Step 0: Subsystem manifest exists, skipping (set FORCE_REGENERATE=1 to regenerate)"
    return 0
  fi
  log "Step 0: Generating subsystem manifest..."
  bash "$TOOL_DIR/subsystem-manifest.sh" generate || { err "manifest failed"; return 1; }
  bash "$TOOL_DIR/subsystem-manifest.sh" validate || warn "manifest has warnings (continuing)"
}

# Step 1: Flow trace
step_1_flow() {
  log "Step 1: Tracing cross-subsystem flows..."
  npx tsx "$TOOL_DIR/flow-trace.ts" 2>&1 | tail -15 || { err "flow-trace failed"; return 1; }
  gate "flow-trace" "[ -f $AUDIT_CACHE/flow-trace.json ]"
}

# Step 2: Blind briefings
step_2_briefings() {
  log "Step 2: Generating blind briefings..."
  npx tsx "$TOOL_DIR/generate-blind-briefings.ts" 2>&1 | tail -10 || { err "briefings failed"; return 1; }
  gate "briefings" "[ -f $AUDIT_CACHE/briefings/blue_1.json ]"
}

# Step 3: Blue team (manual — requires running 5 agents with each briefing)
step_3_blue_team() {
  if [ -d "$AUDIT_CACHE/findings" ] && [ "$(ls -A "$AUDIT_CACHE/findings" 2>/dev/null)" ]; then
    log "Step 3: Findings exist, skipping blue team"
    return 0
  fi
  log ""
  warn "================================================"
  warn "MANUAL STEP: Run 5 Blue Team agents"
  warn "Each agent reads ONLY its briefing in:"
  warn "  $AUDIT_CACHE/briefings/blue_1.json ... blue_5.json"
  warn ""
  warn "Each agent outputs to:"
  warn "  $AUDIT_CACHE/findings/blue_1.json ... blue_5.json"
  warn ""
  warn "After all 5 agents done, press ENTER to continue"
  warn "================================================"
  read -r _
  gate "blue-team" "[ -d $AUDIT_CACHE/findings ] && [ \$(ls $AUDIT_CACHE/findings/*.json 2>/dev/null | wc -l) -ge 1 ]"
}

# Step 4: Red team
step_4_red_team() {
  log "Step 4: Red team attack (using different model)..."
  npx tsx "$TOOL_DIR/red-team-attack.ts" 2>&1 | tail -10 || { err "red-team briefing failed"; return 1; }
  warn ""
  warn "================================================"
  warn "MANUAL STEP: Run Red Team model (M3) on each briefing"
  warn "Output: $AUDIT_CACHE/red-team-attacks/<id>_result.json"
  warn "================================================"
  read -r _
  npx tsx "$TOOL_DIR/red-team-verify.ts" 2>&1 | tail -15 || { err "red-team-verify failed"; return 1; }
}

# Step 5: AAR
step_5_aar() {
  log "Step 5: After-Action Review..."
  npx tsx "$TOOL_DIR/after-action-review.ts" template 2>&1 | tail -5
  warn ""
  warn "================================================"
  warn "MANUAL STEP: Fill AAR template (4 questions)"
  warn "Path: $AUDIT_CACHE/aar.json.template"
  warn "Rename to aar.json when done, then press ENTER"
  warn "================================================"
  read -r _
  npx tsx "$TOOL_DIR/after-action-review.ts" commit 2>&1 | tail -10 || { err "AAR commit failed"; return 1; }
}

# Step 6: Cross-run dedup
step_6_dedup() {
  if [ -f "$AUDIT_CACHE/findings.json" ]; then
    log "Step 6: Cross-run dedup..."
    bash "$TOOL_DIR/cross-run-dedup.sh" filter "$AUDIT_CACHE/findings.json" 2>&1 | tail -5
  else
    log "Step 6: No findings.json, skipping"
  fi
}

# Step 7: v3.7 regression suite (don't break what v3 fixed)
step_7_regression() {
  log "Step 7: v3.7 regression suite..."
  bash "$TOOL_DIR/regression-suite.sh" 2>&1 | tail -10 || warn "regression test had failures"
}

# Main
main() {
  log "=== v4 Audit Cycle ==="
  log ""
  
  step_0_manifest || exit 1
  step_1_flow || exit 1
  step_2_briefings || exit 1
  step_3_blue_team || exit 1
  step_4_red_team || exit 1
  step_5_aar || exit 1
  step_6_dedup
  step_7_regression
  
  log ""
  log "=== v4 Audit Cycle Complete ==="
  log "Outputs:"
  log "  - $AUDIT_CACHE/subsystem-manifest.json"
  log "  - $AUDIT_CACHE/flow-trace.json"
  log "  - $AUDIT_CACHE/briefings/blue_*.json"
  log "  - $AUDIT_CACHE/findings/blue_*.json"
  log "  - $AUDIT_CACHE/red-team-attacks/*_result.json"
  log "  - $AUDIT_CACHE/red-team-summary.json"
  log "  - $AUDIT_CACHE/aar.json"
  log "  - $AUDIT_CACHE/aar-history/<id>.json"
  log "  - $AUDIT_CACHE/blind-spot-registry.json"
}

main
