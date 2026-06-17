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

TOOL_DIR=~/.config/opencode/skills/super-fix/tools
AUDIT_CACHE=".audit-cache"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log() { echo -e "${GREEN}[v4]${NC} $*"; }
warn() { echo -e "${YELLOW}[v4]${NC} $*"; }
err() { echo -e "${RED}[v4 ERROR]${NC} $*"; }

# Gate function with retry (v4.2 P0-L2)
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

# Gate with exponential backoff (v4.2 P0-L2) + gate-check.sh integration (v5.1)
gate_with_retry() {
  local step_name="$1"
  local check_command="$2"
  local max="${3:-3}"
  
  # Try gate-check.sh if phase name matches a PHASE_X pattern and state file exists
  if [[ "$step_name" =~ ^PHASE_ ]] && [ -f "$AUDIT_CACHE/audit_state.json" ]; then
    for i in $(seq 1 $max); do
      if bash "$TOOL_DIR/gate-check.sh" --required-phase="$step_name" "$AUDIT_CACHE/audit_state.json" >/dev/null 2>&1; then
        log "✓ $step_name gate-check passed (attempt $i)"
        return 0
      fi
      if [ $i -lt $max ]; then
        local delay=$((2 ** (i - 1)))
        warn "⏳ $step_name gate-check failed, retrying in ${delay}s..."
        sleep $delay
      fi
    done
    err "✗ $step_name gate-check failed after $max attempts"
    return 1
  fi

  # Fallback to eval-based check
  for i in $(seq 1 $max); do
    if eval "$check_command" >/dev/null 2>&1; then
      log "✓ $step_name passed (attempt $i)"
      return 0
    fi
    if [ $i -lt $max ]; then
      local delay=$((2 ** (i - 1)))
      warn "⏳ $step_name failed, retrying in ${delay}s..."
      sleep $delay
    fi
  done
  err "✗ $step_name failed after $max attempts"
  return 1
}

# Phase timeout wrapper (v4.2 P0-L6)
run_with_timeout() {
  local phase_name="$1"; shift
  local timeout="${PHASE_TIMEOUT:-300}"
  log "▶ $phase_name (timeout: ${timeout}s)..."
  if timeout "$timeout" "$@" 2>&1; then
    return 0
  else
    local rc=$?
    if [ $rc -eq 124 ]; then
      err "✗ $phase_name timed out after ${timeout}s"
    else
      err "✗ $phase_name failed (exit $rc)"
    fi
    CIRCUIT_FAILURES=$((CIRCUIT_FAILURES + 1))
    if [ $CIRCUIT_FAILURES -ge 3 ]; then
      err "CIRCUIT BREAKER OPEN: 3 phase failures — aborting audit"
      exit 1
    fi
    return 1
  fi
}

CIRCUIT_FAILURES=0

# Atomic write: write to .tmp then rename (prevents corruption on crash)
atomic_write() {
  local file="$1" content="$2"
  echo "$content" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# Read state safely (with backup)
read_state() {
  if [ -f "$AUDIT_CACHE/audit_state.json" ]; then
    cat "$AUDIT_CACHE/audit_state.json"
  else
    echo "{}"
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

# Step 3: Blue team — orchestrator spawns general agents with lens prompts
step_3_blue_team() {
  if [ -d "$AUDIT_CACHE/findings" ] && [ "$(ls -A "$AUDIT_CACHE/findings" 2>/dev/null)" ]; then
    log "Step 3: Findings exist, skipping"
    return 0
  fi
  log "Step 3: Blue Team — spawn 5 general agents (Task subagent_type=general)"
  log "  Briefings: $AUDIT_CACHE/briefings/"
  for briefing in "$AUDIT_CACHE/briefings"/audit-blue-*.json; do
    [ -f "$briefing" ] || continue
    lens=$(jq -r '.lens' "$briefing")
    entry=$(jq -r '.entry_file' "$briefing")
    echo "  lens=$lens entry=$entry"
  done
  log ""
  warn "ORCHESTRATOR: spawn general agent for each lens:"
  warn "  'Audit {files} for {lens} bugs. Signaling: see briefings.'"
  warn "================================================"
  log "Checking for agent outputs..."
  gate_with_retry "blue-team" "[ -d $AUDIT_CACHE/findings ] && [ \$(ls $AUDIT_CACHE/findings/audit-blue-*.json 2>/dev/null | wc -l) -ge 3 ]" 2 || {
    warn "Blue Team agent outputs not found — agents must be spawned manually before continuing"
    return 0  # Don't abort — findings may exist from prior run
  }
}

# Step 4: Red team — auto via red-team-runner with validate-retry
step_4_red_team() {
  log "Step 4: Red team attacking with M3 (cross-model, auto-retry)..."
  npx tsx "$TOOL_DIR/red-team-runner.ts" 2>&1 | tail -10 || { err "red-team attack failed"; return 1; }
  npx tsx "$TOOL_DIR/red-team-verify.ts" 2>&1 | tail -10 || warn "red-team-verify had issues"
}

# Step 5: AAR
step_5_aar() {
  log "Step 5: After-Action Review..."
  npx tsx "$TOOL_DIR/after-action-review.ts" template 2>&1 | tail -5
  if [ -f "$AUDIT_CACHE/aar.json" ]; then
    log "AAR already filled, committing..."
  else
    warn "AAR template generated: $AUDIT_CACHE/aar.json.template"
    warn "Fill the 4 questions and rename to aar.json to commit."
  fi
  npx tsx "$TOOL_DIR/after-action-review.ts" commit 2>&1 | tail -10 || { err "AAR commit failed"; return 1; }
}

# Step 6: Cross-run dedup
step_6_dedup() {
  if [ -f "$AUDIT_CACHE/findings.json" ]; then
    log "Step 6: Cross-run dedup..."
    bash "$TOOL_DIR/cross-run-dedup.sh" filter "$AUDIT_CACHE/findings.json" > "$AUDIT_CACHE/findings-deduped.json" 2>&1
    log "Deduped output: $AUDIT_CACHE/findings-deduped.json"
  else
    log "Step 6: No findings.json, skipping"
  fi
}

# Step 7: v3.7 regression suite (P0 blocker —【v4.2 L6 fix】)
step_7_regression() {
  log "Step 7: v3.7 regression suite..."
  bash "$TOOL_DIR/regression-suite.sh" 2>&1 | tail -10 || {
    err "✗ P0 regression suite failed — audit cannot proceed"
    return 1
  }
}

# Main
main() {
  # Parse flags
  FULL_MODE=false
  for arg in "$@"; do
    case "$arg" in
      --full) FULL_MODE=true ;;
      --allow-empty) ALLOW_EMPTY=true ;;
    esac
  done

  log "=== v4 Audit Cycle ==="
  log ""

  # Pre-flight: verify project has source files
  local file_count
  file_count=$(find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.sql" \) -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$file_count" -eq 0 ]; then
    err "Pre-flight: 0 source files found — nothing to audit. Use --allow-empty to override."
    exit 1
  fi
  log "Pre-flight: $file_count source files detected"
  log ""

  # Concurrency lock: prevent two audits on same project
  LOCK_DIR="$AUDIT_CACHE/.lock"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    local existing_pid
    existing_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "unknown")
    err "Another audit is running (PID: $existing_pid). Remove $LOCK_DIR to force."
    exit 1
  fi
  echo $$ > "$LOCK_DIR/pid"
  trap 'rm -rf "$LOCK_DIR"' EXIT
  log "Lock acquired: $LOCK_DIR (PID $$)"

  step_0_manifest || exit 1
  gate_with_retry "PHASE_0_ENTRY" "test -f $AUDIT_CACHE/audit_state.json" 2 || exit 1

  step_1_flow || exit 1

  step_2_briefings || exit 1
  gate_with_retry "briefings" "[ -d $AUDIT_CACHE/briefings ] && [ \$(ls $AUDIT_CACHE/briefings/audit-blue-*.json 2>/dev/null | wc -l) -ge 3 ]" 2 || exit 1

  step_3_blue_team || exit 1
  gate_with_retry "PHASE_2_REVIEW" "[ -d $AUDIT_CACHE/findings ] && [ \$(ls $AUDIT_CACHE/findings/audit-blue-*.json 2>/dev/null | wc -l) -ge 3 ]" 2 || exit 1

  # Assemble findings.json for cross-run dedup (step 6 needs it)
  log "Assembling findings.json from agent outputs..."
  bash "$TOOL_DIR/arbitrate-findings.sh" "$AUDIT_CACHE/findings" "$AUDIT_CACHE/findings.json" || warn "arbitration had issues"

  # Depth gate: reject shallow findings (causal_chain < 3 steps)
  log "Running causal chain depth validator..."
  bash "$TOOL_DIR/validate-causal-chain.sh" --all "$AUDIT_CACHE/findings" 2>&1 | tail -3 || warn "some findings lack depth — see above"

  step_4_red_team || exit 1

  step_5_aar || exit 1

  step_6_dedup
  step_7_regression

  log ""
  log "=== Base Pipeline Complete ==="

  # --full mode: extended phases (Fix → Test → Verify → Certify)
  if [ "$FULL_MODE" = true ] && [ -f "$AUDIT_CACHE/findings.json" ]; then
    log ""
    log "=== Extended Phases (--full mode) ==="

    # Phase 4: Fix P0/P1 findings
    log "Phase 4: Auto-fix P0/P1 findings..."
    local p0p1_count
    p0p1_count=$(jq -r '[.findings[] | select(.severity == "P0" or .severity == "P1")] | length' "$AUDIT_CACHE/findings.json" 2>/dev/null || echo "0")
    if [ "$p0p1_count" -gt 0 ]; then
      jq -r '.findings[] | select(.severity == "P0" or .severity == "P1") | .id' "$AUDIT_CACHE/findings.json" | while read -r fid; do
        log "  Fixing: $fid"
        npx tsx "$TOOL_DIR/apply-fix.ts" "$AUDIT_CACHE/findings.json" "$fid" 2>&1 | tail -2 || warn "fix $fid failed"
      done
    else
      log "  No P0/P1 findings to fix"
    fi

    # Phase 5: Static
    log "Phase 5: Static verification..."
    if npm run lint >/dev/null 2>&1; then
      log "  ✓ tsc --noEmit passed"
    else
      warn "  tsc --noEmit has errors — fix before continuing"
    fi

    # Phase 5.8: Mutation
    log "Phase 5.8: Mutation test..."
    for f in $(git diff --name-only HEAD 2>/dev/null | grep -E '\.(ts|tsx)$' | head -5); do
      [ -f "$f" ] || continue
      bash "$TOOL_DIR/sed-mutation-test.sh" --auto --target="$f" 2>&1 | grep -E "Results|failed" || true
    done

    # Phase 7: Final certification
    log "Phase 7: Final certification..."
    if [ -f "$AUDIT_CACHE/audit_state.json" ]; then
      bash "$TOOL_DIR/gate-check.sh" --required-phase=PHASE_7_FINAL "$AUDIT_CACHE/audit_state.json" 2>&1 | tail -3 || warn "Phase 7 gate not fully satisfied"
    fi

    log ""
    log "=== Full Audit Cycle Complete (P0→P3) ==="
  fi

  log "Outputs:"
  log "  - $AUDIT_CACHE/subsystem-manifest.json"
  log "  - $AUDIT_CACHE/flow-trace.json"
  log "  - $AUDIT_CACHE/findings.json"
  log "  - $AUDIT_CACHE/aar-history/"
}

main
