#!/bin/bash
# audit-state-hash.sh (v3.6.0)
# 维护 audit_state.json 的 SHA-256 完整性 hash
# 用法:
#   audit-state-hash.sh seal <state.json>  # 计算并写入 .sha256 sidecar
#   audit-state-hash.sh verify <state.json> # 验证 .sha256 是否匹配
#
# 设计：sidecar hash 文件**不进 git**（在 .gitignore），用于：
#   1. 防止 agent 误改 audit_state.json（CI 时 verify 必过）
#   2. 给 review 一个 diff 点（如果 hash 变化 → state 变化）
#   3. 比 HMAC 简单 100x，无 key 管理问题
#
# 退出码: 0=OK, 1=hash 不匹配, 2=文件不存在

set -uo pipefail

ACTION="${1:-verify}"
STATE_FILE="${2:-.audit-cache/audit_state.json}"
HASH_FILE="${STATE_FILE}.sha256"

case "$ACTION" in
  seal)
    if [ ! -f "$STATE_FILE" ]; then
      echo "[hash] ERROR: $STATE_FILE not found" >&2
      exit 2
    fi
    HASH=$(shasum -a 256 "$STATE_FILE" | awk '{print $1}')
    echo "$HASH  $STATE_FILE" > "$HASH_FILE"
    echo "[hash] sealed: $HASH"
    ;;
  verify)
    if [ ! -f "$STATE_FILE" ]; then
      echo "[hash] ERROR: $STATE_FILE not found" >&2
      exit 2
    fi
    if [ ! -f "$HASH_FILE" ]; then
      echo "[hash] WARN: $HASH_FILE not found, skipping verify (first run?)"
      exit 0
    fi
    EXPECTED=$(awk '{print $1}' "$HASH_FILE")
    ACTUAL=$(shasum -a 256 "$STATE_FILE" | awk '{print $1}')
    if [ "$EXPECTED" = "$ACTUAL" ]; then
      echo "[hash] OK: $STATE_FILE unmodified"
      exit 0
    else
      echo "[hash] MISMATCH: $STATE_FILE" >&2
      echo "  expected: $EXPECTED" >&2
      echo "  actual:   $ACTUAL" >&2
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 {seal|verify} [state.json]" >&2
    exit 2
    ;;
esac
