#!/bin/bash
# regression-suite.sh (v3.6.0)
# 历次 P0 fix 的 regression test 集合
# 每次 audit 必跑 — 如果有 P0 regression 失败 → audit 立即停
#
# 维护方法: 每次 fix P0 bug 时，add_regression <test_file> "<description>"
# 退出码: 0=全部通过, 1=有 regression fail (P0 重新出现)

set -uo pipefail

REG_FILE=".audit-cache/regression-index.json"
TEST_FILES=(
  "tests/unit/ai-migration-034-regression.test.ts"
  "tests/integration/ai-integration.test.ts"
  "tests/integration/live-db-drift.test.ts"
)

# Initialize registry
if [ ! -f "$REG_FILE" ]; then
  mkdir -p "$(dirname "$REG_FILE")"
  cat > "$REG_FILE" <<'EOF'
{
  "regressions": [
    {
      "id": "P0-001",
      "test_file": "tests/unit/ai-migration-034-regression.test.ts",
      "original_finding": "Migration 030 dropped lock_token + lock_expires_at columns (AI module runtime P0)",
      "introduced_at": "2026-06-17",
      "commit": "8f4c3f3"
    },
    {
      "id": "P0-002",
      "test_file": "tests/integration/live-db-drift.test.ts",
      "original_finding": "v3.5 audit had 0 live-DB tests (schema/code drift undetectable)",
      "introduced_at": "2026-06-17",
      "commit": "b39af7b"
    },
    {
      "id": "P0-003",
      "test_file": "tests/integration/live-db-drift.test.ts",
      "original_finding": "SRE-006: markJobFailed did not release paper-level lock (zombie rows blocking 5min)",
      "introduced_at": "2026-06-17",
      "commit": "b39af7b"
    }
  ]
}
EOF
  echo "[regression] initialized: $REG_FILE"
fi

echo "=== P0 regression suite (must all pass) ==="
FAIL=0
for f in "${TEST_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "SKIP: $f (not found)"
    continue
  fi
  echo "Running: $f"
  if npx vitest run "$f" --reporter=basic 2>&1 | tail -5; then
    :
  else
    echo "FAIL: $f"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "=== RESULT: $FAIL regression(s) FAILED — P0 bug has returned! ==="
  echo "DO NOT report audit success. Fix immediately."
  exit 1
fi
echo "=== RESULT: all P0 regressions held ==="
exit 0
