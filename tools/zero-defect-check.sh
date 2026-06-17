#!/bin/bash
# zero-defect-check.sh (v3.4)
# 严格零缺陷检查: 0 open + 0 fixing + all fixed verified
# 用法: zero-defect-check.sh --state=path/to/state.json
# 退出码: 0=zero-defect, 1=still has open, 2=error

set -uo pipefail

STATE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --state=*) STATE="${1#*=}"; shift ;;
    *) shift ;;
  esac
done

if [ -z "$STATE" ]; then
  echo '{"decision":"error","message":"--state required"}'
  exit 2
fi
if [ ! -f "$STATE" ]; then
  echo "{\"decision\":\"error\",\"message\":\"state not found: $STATE\"}"
  exit 2
fi

python3 <<PYEOF
import json, sys

with open("$STATE") as f:
    s = json.load(f)

findings = s.get('findings', {})

if not findings:
    print(json.dumps({
        "decision": "zero-defect",
        "message": "0 findings — trivial scope or no audit performed",
        "warning": "audit may not have run"
    }, ensure_ascii=False))
    sys.exit(0)

# Categorize
by_status = {}
for fid, f in findings.items():
    st = f.get('status', 'unknown')
    by_status[st] = by_status.get(st, 0) + 1

open_count = by_status.get('open', 0)
fixing_count = by_status.get('fixing', 0)
fixed_count = by_status.get('fixed', 0)
verified_count = by_status.get('verified', 0)
cannot_fix_count = by_status.get('cannot_fix', 0)
deferred_count = by_status.get('deferred', 0)

errors = []
if open_count > 0:
    errors.append(f"{open_count} findings still OPEN")
if fixing_count > 0:
    errors.append(f"{fixing_count} findings in FIXING state (not yet complete)")
if fixed_count > 0:
    errors.append(f"{fixed_count} findings in FIXED but not VERIFIED state (regression risk)")

# Whitelist check for cannot_fix
whitelist = {'external_dependency','data_migration','out_of_scope','missing_infrastructure','design_tradeoff'}
for fid, f in findings.items():
    if f.get('status') == 'cannot_fix':
        reason = f.get('cannot_fix_reason')
        if reason not in whitelist:
            errors.append(f"{fid} cannot_fix_reason='{reason}' not in whitelist")
    if f.get('status') == 'deferred':
        # P3 only allowed
        if f.get('severity') not in ('P3',):
            errors.append(f"{fid} severity={f.get('severity')} cannot be deferred (only P3 allowed)")
        # Must have user_confirm timestamp
        ev = f.get('fix_evidence', {})
        if not ev.get('user_confirm_at'):
            errors.append(f"{fid} deferred without user_confirm_at")

if errors:
    print(json.dumps({
        "decision": "not-zero-defect",
        "errors": errors,
        "counts": by_status
    }, ensure_ascii=False))
    sys.exit(1)
else:
    print(json.dumps({
        "decision": "zero-defect",
        "counts": by_status,
        "verified": verified_count,
        "cannot_fix": cannot_fix_count,
        "deferred": deferred_count
    }, ensure_ascii=False))
    sys.exit(0)
PYEOF
