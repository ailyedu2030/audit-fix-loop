#!/bin/bash
# sed-mutation-test.sh (v3.6.0)
# 零依赖 mutation test：用 sed 注入已知 buggy 变体，验证测试能否捕获
#
# v3.5 audit 发现 362 tests 99% 是 string-matching，0 mutation coverage。
# 完整 stryker 工具依赖大、启动慢；此工具用 sed 注入 5 个常见 mutation 模式，
# 跑测试，必须全部 FAIL，否则测试无效。
#
# 用法:
#   sed-mutation-test.sh --target=<file> --test="<vitest cmd>"
#   sed-mutation-test.sh --auto  # 用预定义 mutation suite
#
# 退出码: 0=全部 mutation 被 kill (测试有效), 1=有 mutation survive (测试无效)

set -uo pipefail

AUTO_MODE=false
TARGET=""
TEST_CMD="npx vitest run --reporter=basic"
MUTATION_DIR="/tmp/audit-mutations-$$"

while [ $# -gt 0 ]; do
  case "$1" in
    --auto) AUTO_MODE=true; shift ;;
    --target=*) TARGET="${1#*=}"; shift ;;
    --test=*) TEST_CMD="${1#*=}"; shift ;;
    -h|--help) echo "Usage: $0 [--auto|--target=F --test=CMD]"; exit 0 ;;
    *) shift ;;
  esac
done

if [ "$AUTO_MODE" != "true" ] && [ -z "$TARGET" ]; then
  echo "ERROR: --target=F or --auto required" >&2
  exit 2
fi

mkdir -p "$MUTATION_DIR"
trap "rm -rf $MUTATION_DIR" EXIT

# Predefined mutation operators (common bugs that survived v3.5)
run_auto_suite() {
  local target="${1:-server/src/services/aiExamPoolService.ts}"
  echo "=== sed-mutation-test: $target ==="

  local original_hash
  original_hash=$(shasum -a 256 "$target" | awk '{print $1}')
  cp "$target" "$MUTATION_DIR/original"

  local mutations_killed=0
  local mutations_total=0
  local survived=()

  # Mutation 1: && → ||  (boundary condition flip)
  echo "[mut] && → ||"
  sed 's/ && / || /g' "$target" > "$MUTATION_DIR/m1.ts"
  mutations_total=$((mutations_total + 1))
  if cp "$MUTATION_DIR/m1.ts" "$target" && ! eval "$TEST_CMD" >/dev/null 2>&1; then
    mutations_killed=$((mutations_killed + 1))
    echo "  KILLED ✓"
  else
    survived+=("M1: && → ||")
    echo "  SURVIVED ✗ (test still passes — weak coverage)"
  fi
  cp "$MUTATION_DIR/original" "$target"

  # Mutation 2: === → !==  (equality flip)
  echo "[mut] === → !=="
  sed 's/ === / !== /g' "$target" > "$MUTATION_DIR/m2.ts"
  mutations_total=$((mutations_total + 1))
  if cp "$MUTATION_DIR/m2.ts" "$target" && ! eval "$TEST_CMD" >/dev/null 2>&1; then
    mutations_killed=$((mutations_killed + 1))
    echo "  KILLED ✓"
  else
    survived+=("M2: === → !==")
    echo "  SURVIVED ✗"
  fi
  cp "$MUTATION_DIR/original" "$target"

  # Mutation 3: !status → status  (negation removal)
  echo "[mut] remove ! negation"
  sed 's/!status/status/g; s/!isMounted/isMounted/g' "$target" > "$MUTATION_DIR/m3.ts"
  mutations_total=$((mutations_total + 1))
  if cp "$MUTATION_DIR/m3.ts" "$target" && ! eval "$TEST_CMD" >/dev/null 2>&1; then
    mutations_killed=$((mutations_killed + 1))
    echo "  KILLED ✓"
  else
    survived+=("M3: ! negation")
    echo "  SURVIVED ✗"
  fi
  cp "$MUTATION_DIR/original" "$target"

  # Mutation 4: throw → console.error (silent error swallowing)
  echo "[mut] throw → console.error (silent error)"
  sed 's/throw new Error/console.error/g' "$target" > "$MUTATION_DIR/m4.ts"
  mutations_total=$((mutations_total + 1))
  if cp "$MUTATION_DIR/m4.ts" "$target" && ! eval "$TEST_CMD" >/dev/null 2>&1; then
    mutations_killed=$((mutations_killed + 1))
    echo "  KILLED ✓"
  else
    survived+=("M4: throw → console.error")
    echo "  SURVIVED ✗"
  fi
  cp "$MUTATION_DIR/original" "$target"

  # Mutation 5: 'failed' → 'ready'  (state machine bypass)
  echo "[mut] 'failed' → 'ready' (status corruption)"
  sed "s/'failed'/'ready'/g" "$target" > "$MUTATION_DIR/m5.ts"
  mutations_total=$((mutations_total + 1))
  if cp "$MUTATION_DIR/m5.ts" "$target" && ! eval "$TEST_CMD" >/dev/null 2>&1; then
    mutations_killed=$((mutations_killed + 1))
    echo "  KILLED ✓"
  else
    survived+=("M5: status corruption")
    echo "  SURVIVED ✗"
  fi
  cp "$MUTATION_DIR/original" "$target"

  # Verify file restored
  local final_hash
  final_hash=$(shasum -a 256 "$target" | awk '{print $1}')
  if [ "$original_hash" != "$final_hash" ]; then
    echo "ERROR: target file not restored properly!" >&2
    cp "$MUTATION_DIR/original" "$target"
    exit 2
  fi

  echo ""
  echo "=== Results: $mutations_killed/$mutations_total killed ==="
  if [ ${#survived[@]} -gt 0 ]; then
    echo "Survived mutations (test coverage gaps):"
    for m in "${survived[@]}"; do echo "  - $m"; done
    echo "→ Add tests that fail when these mutations are applied"
    exit 1
  fi
  exit 0
}

if [ "$AUTO_MODE" = "true" ]; then
  run_auto_suite
elif [ -n "$TARGET" ]; then
  run_auto_suite "$TARGET"
fi
