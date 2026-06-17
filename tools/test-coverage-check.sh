#!/bin/bash
# test-coverage-check.sh (v3.5)
# 验证每个 verified finding 都有 test_ids 覆盖
# 用法: test-coverage-check.sh --state=path
# 退出码: 0=全覆盖, 1=有 finding 缺 test, 2=error

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
test_cov = s.get('test_coverage', {})

errors = []
warnings = []

# Check verified/cannot_fix/deferred findings have test_ids
for fid, f in findings.items():
    status = f.get('status')
    if status not in ('verified', 'cannot_fix', 'deferred'):
        continue  # open/fixing/fixed don't need test yet
    
    cov = test_cov.get(fid, {})
    test_ids = cov.get('test_ids', [])
    test_na_reason = cov.get('test_na_reason')
    
    if not test_ids:
        if status == 'verified':
            # verified findings must have test_ids, OR a documented test_na_reason
            # Note: test_na_reason for verified means "test deferred to next cycle"
            if test_na_reason:
                warnings.append(f"{fid} verified but test deferred: {test_na_reason}")
            else:
                errors.append(f"{fid} status=verified but test_coverage.test_ids is empty")
        elif status == 'cannot_fix':
            if not test_na_reason:
                warnings.append(f"{fid} cannot_fix but no test_na_reason")
        # deferred (P3) doesn't strictly need test_ids
    
    # Check mutation_killed for verified
    if status == 'verified' and test_ids and not cov.get('mutation_killed', False):
        errors.append(f"{fid} verified but mutation_killed=false (test not validated)")

# Check test_id format: should be file:line or path/test.ts:line
import re
test_id_pattern = re.compile(r'^[a-zA-Z0-9_./-]+(?::\d+(?:-\d+)?)?$')
for fid, cov in test_cov.items():
    for tid in cov.get('test_ids', []):
        if not test_id_pattern.match(tid):
            warnings.append(f"{fid} test_id '{tid}' format suspect (expected file:line)")

# Summary
total_findings = len(findings)
verified = sum(1 for f in findings.values() if f.get('status') == 'verified')
covered = sum(1 for fid, c in test_cov.items() if c.get('test_ids') and c.get('mutation_killed'))
coverage_pct = (covered / verified * 100) if verified > 0 else 0

result = {
    "decision": "fail" if errors else "warn" if warnings else "pass",
    "summary": {
        "total_findings": total_findings,
        "verified": verified,
        "covered_with_tests": covered,
        "coverage_pct": round(coverage_pct, 1)
    },
    "errors": errors,
    "warnings": warnings
}
print(json.dumps(result, ensure_ascii=False))
sys.exit(1 if errors else 0)
PYEOF
