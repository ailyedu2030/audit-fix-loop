#!/bin/bash
# verify-report.sh (v3.4)
# 反向验证: 报告中的数字必须与 audit_state.json 一致
# 用法: verify-report.sh --report=path/to/report.md --state=path/to/state.json
# 退出码: 0=consistent, 1=inconsistency found, 2=error

set -uo pipefail

REPORT=""
STATE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --report=*) REPORT="${1#*=}"; shift ;;
    --state=*) STATE="${1#*=}"; shift ;;
    *) shift ;;
  esac
done

if [ -z "$REPORT" ] || [ -z "$STATE" ]; then
  echo '{"decision":"error","message":"--report and --state required"}'
  exit 2
fi
if [ ! -f "$REPORT" ]; then
  echo "{\"decision\":\"error\",\"message\":\"report not found: $REPORT\"}"
  exit 2
fi
if [ ! -f "$STATE" ]; then
  echo "{\"decision\":\"error\",\"message\":\"state not found: $STATE\"}"
  exit 2
fi

python3 <<PYEOF
import json, re, sys

with open("$STATE") as f:
    s = json.load(f)

with open("$REPORT") as f:
    report = f.read()

# Count findings by severity and status
counts = {'P0': {'open':0,'fixing':0,'fixed':0,'verified':0,'cannot_fix':0,'deferred':0,'total':0},
          'P1': {'open':0,'fixing':0,'fixed':0,'verified':0,'cannot_fix':0,'deferred':0,'total':0},
          'P2': {'open':0,'fixing':0,'fixed':0,'verified':0,'cannot_fix':0,'deferred':0,'total':0},
          'P3': {'open':0,'fixing':0,'fixed':0,'verified':0,'cannot_fix':0,'deferred':0,'total':0}}

for fid, f in s.get('findings', {}).items():
    sev = f.get('severity', 'P0')
    status = f.get('status', 'open')
    if sev in counts and status in counts[sev]:
        counts[sev][status] += 1
    if sev in counts:
        counts[sev]['total'] += 1

# Parse report for "P0: N", "已修: N" etc.
# Look for executive layer table
errors = []
warnings = []

# Look for explicit "已修" / "已验证" claims
# Patterns: "P0\n| N | N | N | N | N | N" (executive table)

# Search for table rows with severity labels
# The standard executive table has columns: 严重度 | 发现 | 修复 | 验证 | cannot_fix | deferred
exec_pattern = re.compile(
    r'\|\s*(P[0-3])\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|',
    re.MULTILINE
)

matches = exec_pattern.findall(report)
for sev, total_reported, fixed_reported, verified_reported, cfx_reported, def_reported in matches:
    if sev not in counts:
        warnings.append(f"Report row for {sev} but state has no {sev} findings")
        continue
    actual = counts[sev]
    
    # "发现" = total
    if int(total_reported) != actual['total']:
        errors.append(f"{sev} 发现 reported={total_reported} actual={actual['total']}")
    # "修复" = fixed + verified
    fix_actual = actual['fixed'] + actual['verified']
    if int(fixed_reported) != fix_actual:
        errors.append(f"{sev} 修复 reported={fixed_reported} actual={fix_actual}")
    # "验证" = verified
    if int(verified_reported) != actual['verified']:
        errors.append(f"{sev} 验证 reported={verified_reported} actual={actual['verified']}")
    # "cannot_fix"
    if int(cfx_reported) != actual['cannot_fix']:
        errors.append(f"{sev} cannot_fix reported={cfx_reported} actual={actual['cannot_fix']}")
    # "deferred"
    if int(def_reported) != actual['deferred']:
        errors.append(f"{sev} deferred reported={def_reported} actual={actual['deferred']}")

# Check 0 open claim
if '0 open' in report.lower() or '0 个' in report:
    open_count = sum(c['open'] for c in counts.values())
    if open_count > 0:
        errors.append(f"Report claims 0 open findings but state has {open_count}")

# Check 'all fixed' claim
if '全部' in report and '修复' in report:
    if s.get('phases_passed', {}).get('PHASE_4_FIX'):
        unverified = sum(c['fixed'] for c in counts.values())
        if unverified > 0:
            warnings.append(f"Report says 全部修复 but {unverified} fixed-not-verified in state")

if errors:
    print(json.dumps({"decision":"fail","errors":errors,"warnings":warnings,"counts":counts}, ensure_ascii=False))
    sys.exit(1)
elif warnings:
    print(json.dumps({"decision":"warn","warnings":warnings,"counts":counts}, ensure_ascii=False))
    sys.exit(0)
else:
    print(json.dumps({"decision":"pass","counts":counts,"verified":sum(c['verified'] for c in counts.values())}, ensure_ascii=False))
    sys.exit(0)
PYEOF
