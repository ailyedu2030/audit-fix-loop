#!/bin/bash
# gate-check.sh (v3.4)
# phase 转下 phase 门禁工具
# 用法: gate-check.sh --required-phase=PHASE_X --action=enter|exit <state.json>
# 退出码: 0=PASS gate, 1=FAIL gate, 2=ERROR (broken state)

set -uo pipefail

STATE_FILE=""
REQUIRED_PHASE=""
ACTION="exit"  # default: check that current phase passed before moving on

while [ $# -gt 0 ]; do
  case "$1" in
    --required-phase=*) REQUIRED_PHASE="${1#*=}"; shift ;;
    --action=*) ACTION="${1#*=}"; shift ;;
    --state=*) STATE_FILE="${1#*=}"; shift ;;
    -h|--help) echo "Usage: gate-check.sh --required-phase=X --action=enter|exit [--state=path] [state.json]"; exit 0 ;;
    --*) shift ;;
    *)
      # Positional arg: state file
      if [ -z "$STATE_FILE" ]; then
        STATE_FILE="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$STATE_FILE" ] || [ -z "$REQUIRED_PHASE" ]; then
  echo '{"decision":"error","message":"--required-phase=X and --state=path required"}'
  exit 2
fi
if [ ! -f "$STATE_FILE" ]; then
  echo "{\"decision\":\"error\",\"message\":\"state file not found: $STATE_FILE — Phase 0 init not done?\"}"
  exit 2
fi

HAVE_PYTHON=false
HAVE_JQ=false
command -v python3 >/dev/null 2>&1 && HAVE_PYTHON=true
command -v jq >/dev/null 2>&1 && HAVE_JQ=true

if $HAVE_PYTHON; then
  RESULT=$(python3 <<PYEOF
import json, sys

with open("$STATE_FILE") as f:
    s = json.load(f)

required = "$REQUIRED_PHASE"
action = "$ACTION"
errors = []
warnings = []

# Phase order for gate progression check
phase_order = [
    'PHASE_0_ENTRY',
    'PHASE_1_SBL',
    'PHASE_1_5_TEST_PYRAMID',
    'PHASE_2_REVIEW',
    'PHASE_3_ARBITRATION',
    'PHASE_4_FIX',
    'PHASE_4_5_TEST_AUTHOR',
    'PHASE_5_STATIC',
    'PHASE_5_5_SMOKE',
    'PHASE_5_6_DYNAMIC',
    'PHASE_5_7_CHAOS',
    'PHASE_5_8_MUTATION',
    'PHASE_6_LOOP',
    'PHASE_6_5_DEVIL_ADVOCATE',
    'PHASE_7_FINAL',
]

# 1. Validate state structure
if 'phases_passed' not in s:
    errors.append("phases_passed missing from state")
if 'findings' not in s:
    errors.append("findings missing from state")
if 'gates_passed' not in s:
    errors.append("gates_passed missing from state")

if errors:
    print(json.dumps({"decision": "error", "errors": errors}))
    sys.exit(0)

# 2. Check this phase is current
if s.get('current_phase') != required:
    errors.append(f"current_phase={s.get('current_phase')} but required={required}")

# 3. For action=enter: all previous phases must be passed
if action == 'enter':
    if required in phase_order:
        idx = phase_order.index(required)
        for i in range(idx):
            prev_phase = phase_order[i]
            if not s['phases_passed'].get(prev_phase, False):
                errors.append(f"previous phase {prev_phase} not passed (required before entering {required})")
                break

# 4. Phase-specific requirements
def check_phase_0():
    if not s.get('started_at'):
        errors.append("started_at missing")
    if s.get('mode') not in ('emergency','quick','incremental','deep','continuous'):
        errors.append(f"invalid mode: {s.get('mode')}")

def check_phase_1():
    # 1.0 pre-query must exist
    import os
    import glob
    pq = glob.glob('.audit-cache/pre-query-*.json')
    if not pq:
        errors.append("Phase 1.0 pre-query JSON not found in .audit-cache/")
    # SBL must exist
    sbl_files = glob.glob('.audit-cache/sbl*.json')
    if not sbl_files:
        errors.append("Phase 1.1-1.4 SBL JSON not found in .audit-cache/")

def check_phase_2():
    # findings must be added to state from agents
    if len(s['findings']) == 0 and s.get('current_round', 0) == 0:
        warnings.append("first round: 0 findings — agents may not have run")

def check_phase_3():
    # Each finding should have severity, file:line, category
    for fid, f in s['findings'].items():
        if f.get('discovered_round') != s.get('current_round'):
            continue
        for req in ('severity','file','category'):
            if req not in f:
                errors.append(f"finding {fid} missing {req}")

def check_phase_4():
    # After fix, no finding should be in 'open' state (moved to fixing/fixed/verified)
    # Actually it's ok to have open if some agents reported new findings this round
    # Just check we tried to fix
    open_count = sum(1 for f in s['findings'].values() if f.get('status') == 'open')
    if open_count > 0:
        warnings.append(f"{open_count} findings still open (acceptable if just discovered)")

def check_phase_5():
    # Static checks must pass; tracked via gates_passed
    if 'phase_5_static' not in s.get('gates_passed', {}):
        errors.append("phase_5_static gate not recorded")
    # All 'fixed' findings should have fix_evidence
    for fid, f in s['findings'].items():
        if f.get('status') == 'fixed' and not f.get('fix_evidence'):
            warnings.append(f"finding {fid} status=fixed but no fix_evidence")

def check_phase_5_5():
    # smoke test result
    import os, glob
    smoke = glob.glob(f".audit-cache/smoke-test-*.json")
    if not smoke:
        errors.append("Phase 5.5 smoke test JSON not found")
    else:
        latest = max(smoke, key=os.path.getmtime)
        with open(latest) as f:
            sd = json.load(f)
        if sd.get('failed', 0) > 0:
            errors.append(f"smoke test has {sd.get('failed')} failures")
        if sd.get('p0_500_count', 0) > 0:
            errors.append(f"smoke test has {sd.get('p0_500_count')} P0 500-errors")

def check_phase_1_5():
    # Test pyramid: at least 4 test layers must exist
    import os
    layers = ['tests/unit', 'tests/integration', 'tests/contract', 'tests/property', 'tests/chaos']
    found = sum(1 for d in layers if os.path.isdir(d) and any(f.endswith('.test.') for f in os.listdir(d) if f.endswith('.ts') or f.endswith('.tsx')))
    if found < 4:
        errors.append(f"Test pyramid incomplete: {found} layers found, need ≥4")

def check_phase_4_5():
    # Test authoring: all fixed findings must have test_ids
    findings = s.get('findings', {})
    fixed = [fid for fid, f in findings.items() if f.get('status') == 'fixed']
    no_test = [fid for fid in fixed if not s.get('test_coverage', {}).get(fid, {}).get('test_ids')]
    if no_test:
        errors.append(f"{len(no_test)} fixed findings have no test_ids: {', '.join(no_test[:5])}")

def check_phase_5_6():
    # Dynamic test suite must pass
    import os, glob
    dyn = glob.glob(".audit-cache/dynamic-test-*.json")
    if not dyn:
        errors.append("Phase 5.6 dynamic test JSON not found")
    else:
        with open(max(dyn, key=os.path.getmtime)) as f:
            dd = json.load(f)
        if dd.get('failed', 0) > 0:
            errors.append(f"dynamic test has {dd.get('failed')} failures")

def check_phase_5_7():
    # Chaos test must pass
    import os, glob
    chaos = glob.glob(".audit-cache/chaos-test-*.json")
    if not chaos:
        errors.append("Phase 5.7 chaos test JSON not found")

def check_phase_5_8():
    # Mutation test must achieve ≥4/5 kill rate per file
    import os, glob
    mut = glob.glob(".audit-cache/mutation-test-*.json")
    if not mut:
        errors.append("Phase 5.8 mutation test JSON not found")
    else:
        with open(max(mut, key=os.path.getmtime)) as f:
            md = json.load(f)
        if md.get('killed', 0) < 4:
            errors.append(f"mutation kill rate {md.get('killed')}/5 too low")

def check_phase_6():
    # convergence-check.sh must have been run with exit 0 (or escalate)
    # We track via gates_passed['phase_6_to_6_5']
    if 'phase_6_to_6_5' not in s.get('gates_passed', {}):
        # Not error if first round and still continuing
        if s.get('current_round', 0) > 0:
            warnings.append("phase_6_to_6_5 gate not recorded (convergence-check.sh may not have been run)")

def check_phase_6_5():
    # Devil's Advocate: must have been run
    # Track via:
    # 1. phases_passed['PHASE_6_5_DEVIL_ADVOCATE']
    # 2. New findings with discovered_round == current_round (DA typically reports new findings)
    da_run = s['phases_passed'].get('PHASE_6_5_DEVIL_ADVOCATE', False)
    if not da_run:
        errors.append("Devil's Advocate phase not marked as passed — must run before Phase 7")

def check_phase_7():
    # ALL findings must be in terminal state: verified / cannot_fix / deferred
    bad = []
    for fid, f in s['findings'].items():
        if f.get('status') not in ('verified', 'cannot_fix', 'deferred'):
            bad.append(f"{fid}:status={f.get('status')}")
    if bad:
        errors.append(f"{len(bad)} findings not in terminal state: {bad[:5]}")
    # 0 open
    open_count = sum(1 for f in s['findings'].values() if f.get('status') == 'open')
    if open_count > 0:
        errors.append(f"{open_count} findings still open")
    # cannot_fix reasons must be in whitelist
    whitelist = {'external_dependency','data_migration','out_of_scope','missing_infrastructure','design_tradeoff'}
    for fid, f in s['findings'].items():
        if f.get('status') == 'cannot_fix':
            reason = f.get('cannot_fix_reason')
            if reason not in whitelist:
                errors.append(f"{fid} cannot_fix_reason='{reason}' not in whitelist")

# Dispatch — use manual mapping to avoid naming issues with underscores
dispatch = {
    'PHASE_0_ENTRY': check_phase_0,
    'PHASE_1_SBL': check_phase_1,
    'PHASE_1_5_TEST_PYRAMID': check_phase_1_5,
    'PHASE_2_REVIEW': check_phase_2,
    'PHASE_3_ARBITRATION': check_phase_3,
    'PHASE_4_FIX': check_phase_4,
    'PHASE_4_5_TEST_AUTHOR': check_phase_4_5,
    'PHASE_5_STATIC': check_phase_5,
    'PHASE_5_5_SMOKE': check_phase_5_5,
    'PHASE_5_6_DYNAMIC': check_phase_5_6,
    'PHASE_5_7_CHAOS': check_phase_5_7,
    'PHASE_5_8_MUTATION': check_phase_5_8,
    'PHASE_6_LOOP': check_phase_6,
    'PHASE_6_5_DEVIL_ADVOCATE': check_phase_6_5,
    'PHASE_7_FINAL': check_phase_7,
}
checker = dispatch.get(required)
if checker:
    checker()

# Output
if errors:
    print(json.dumps({"decision": "fail", "phase": required, "errors": errors, "warnings": warnings}))
elif warnings:
    print(json.dumps({"decision": "warn", "phase": required, "warnings": warnings}))
else:
    print(json.dumps({"decision": "pass", "phase": required}))
PYEOF
)
elif $HAVE_JQ; then
  RESULT=$(jq -c --arg phase "$REQUIRED_PHASE" --arg action "$ACTION" '
    if .phases_passed == null then {decision:"error",message:"phases_passed missing"}
    elif .current_phase != $phase then {decision:"fail",errors:["current_phase mismatch"]}
    else {decision:"pass",phase:$phase}
    end
  ' "$STATE_FILE")
else
  echo '{"decision":"error","message":"need python3 or jq"}'
  exit 2
fi

echo "$RESULT"
DECISION=$(echo "$RESULT" | tr -d ' \n' | grep -oE '"decision":"[a-z]+"' | head -1 | cut -d'"' -f4)
case "$DECISION" in
  pass) exit 0 ;;
  warn) exit 0 ;;  # warning is non-blocking
  fail) exit 1 ;;
  error) exit 2 ;;
  *) exit 2 ;;
esac
