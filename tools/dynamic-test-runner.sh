#!/bin/bash
# dynamic-test-runner.sh (v3.5)
# 跑完整 test suite (不是只 smoke)
# 用法: dynamic-test-runner.sh --state=path [--rounds=N]
# 退出码: 0=全过, 1=有失败, 2=error

set -uo pipefail

STATE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --state=*) STATE="${1#*=}"; shift ;;
    *) shift ;;
  esac
done

if [ -z "$STATE" ] || [ ! -f "$STATE" ]; then
  echo '{"decision":"error","message":"--state required"}'
  exit 2
fi

# Try to run all test suites, but gracefully handle missing scripts
RESULTS="{}"
TESTS_FAILED=0
SUITES_RUN=0
SUITES_SKIPPED=0

run_suite() {
  local name="$1"
  local cmd="$2"
  
  if [ -z "$cmd" ]; then
    echo "{\"suite\":\"$name\",\"status\":\"skipped\",\"reason\":\"script not defined\"}"
    return
  fi
  
  # Check if the command would actually run
  local start=$(date +%s)
  local output
  output=$(eval "$cmd" 2>&1)
  local exit_code=$?
  local duration=$(($(date +%s) - start))
  
  SUITES_RUN=$((SUITES_RUN + 1))
  if [ $exit_code -ne 0 ]; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "{\"suite\":\"$name\",\"status\":\"fail\",\"exit_code\":$exit_code,\"duration_s\":$duration,\"output_excerpt\":\"$(echo "$output" | head -c 200 | tr -d '\n' | sed 's/"/\\"/g')\"}"
  else
    echo "{\"suite\":\"$name\",\"status\":\"pass\",\"exit_code\":0,\"duration_s\":$duration}"
  fi
}

# Detect available test scripts
detect_cmd() {
  local script_name="$1"
  node -e "
const p = require('./package.json');
const s = p.scripts || {};
process.stdout.write(s['$script_name'] || '');
" 2>/dev/null
}

UNIT_CMD=$(detect_cmd "test:unit")
INT_CMD=$(detect_cmd "test:integration")
PROP_CMD=$(detect_cmd "test:property")
CONT_CMD=$(detect_cmd "test:contract")
E2E_CMD=$(detect_cmd "test:e2e")
ALL_CMD=$(detect_cmd "test")

echo "Detected scripts:"
echo "  test:unit: ${UNIT_CMD:-(not defined)}"
echo "  test:integration: ${INT_CMD:-(not defined)}"
echo "  test:property: ${PROP_CMD:-(not defined)}"
echo "  test:contract: ${CONT_CMD:-(not defined)}"
echo "  test:e2e: ${E2E_CMD:-(not defined)}"
echo ""

ALL_RESULTS="["
FIRST=1

for entry in \
  "unit:$UNIT_CMD" \
  "integration:$INT_CMD" \
  "property:$PROP_CMD" \
  "contract:$CONT_CMD" \
  "e2e:$E2E_CMD"; do
  name="${entry%%:*}"
  cmd="${entry#*:}"
  result=$(run_suite "$name" "$cmd")
  if [ $FIRST -eq 0 ]; then ALL_RESULTS+=","; fi
  ALL_RESULTS+="$result"
  FIRST=0
done
ALL_RESULTS+="]"

# Write to cache
mkdir -p .audit-cache
TIMESTAMP=$(date +%s)
echo "{
  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
  \"suites_run\": $SUITES_RUN,
  \"suites_failed\": $TESTS_FAILED,
  \"results\": $ALL_RESULTS
}" > ".audit-cache/dynamic-test-${TIMESTAMP}.json"

# Final output
python3 -c "
import json
data = json.load(open('.audit-cache/dynamic-test-${TIMESTAMP}.json'))
failed = [r for r in data['results'] if r.get('status') == 'fail']
passed = [r for r in data['results'] if r.get('status') == 'pass']
skipped = [r for r in data['results'] if r.get('status') == 'skipped']
data['summary'] = {'passed': len(passed), 'failed': len(failed), 'skipped': len(skipped)}
data['decision'] = 'fail' if failed else 'pass'
print(json.dumps(data, ensure_ascii=False, indent=2))
" > ".audit-cache/dynamic-test-${TIMESTAMP}.json"

cat ".audit-cache/dynamic-test-${TIMESTAMP}.json"

[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
