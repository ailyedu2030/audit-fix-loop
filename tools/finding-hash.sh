#!/bin/bash
# finding-hash.sh (v3.6.0)
# 给 finding 算 stable semantic hash，用于跨 audit 周期去重
#
# 设计: hash = sha256(module | function | pattern)
#   - module: 文件相对路径 (规范化)
#   - function: 函数名 (避免 line 漂移)
#   - pattern: 规范化的问题类型
#
# 用法:
#   finding-hash.sh --module=path --function=func_name --pattern=type
#   finding-hash.sh --module=path --line=N --pattern=type  # fallback: 用 10-行 bucket
#
# 输出: 64-char hex hash

set -uo pipefail

MODULE=""
FUNCTION=""
PATTERN=""
LINE="0"

while [ $# -gt 0 ]; do
  case "$1" in
    --module=*) MODULE="${1#*=}"; shift ;;
    --function=*) FUNCTION="${1#*=}"; shift ;;
    --pattern=*) PATTERN="${1#*=}"; shift ;;
    --line=*) LINE="${1#*=}"; shift ;;
    -h|--help) echo "Usage: $0 --module=path [--function=fn] --pattern=type [--line=N]"; exit 0 ;;
    *) shift ;;
  esac
done

if [ -z "$MODULE" ] || [ -z "$PATTERN" ]; then
  echo "ERROR: --module and --pattern required" >&2
  exit 2
fi

# Normalize module: strip leading ./, take last 3 path segments
NORM_MODULE=$(echo "$MODULE" | sed 's|^\./||' | rev | cut -d/ -f1-3 | rev)

# Normalize function
NORM_FUNCTION=$(echo "$FUNCTION" | tr -cs 'a-zA-Z0-9_' '_')

# Normalize pattern: lowercase + non-alnum → single space + collapse
# Caller is responsible for using canonical pattern names (e.g., "paper_lock_cleanup")
# This is intentional: similar-but-different patterns are different findings.
NORM_PATTERN=$(echo "$PATTERN" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' ' ' | awk '{$1=$1};1' | tr ' ' '_' | sed 's/^_\|_$//g')

# Compose location: prefer function, fallback to line bucket
if [ -n "$NORM_FUNCTION" ] && [ "$NORM_FUNCTION" != "_" ]; then
  LOCATION="$NORM_FUNCTION"
else
  LINE_NUM=$(echo "$LINE" | tr -dc '0-9')
  if [ -z "$LINE_NUM" ] || [ "$LINE_NUM" = "0" ]; then
    LOCATION="unknown"
  else
    BUCKET_START=$((LINE_NUM / 10 * 10))
    LOCATION="L${BUCKET_START}"
  fi
fi

# Compute hash
HASH_INPUT="${NORM_MODULE}|${LOCATION}|${NORM_PATTERN}"
HASH=$(echo -n "$HASH_INPUT" | shasum -a 256 | awk '{print $1}')

if [ "${VERBOSE:-0}" = "1" ]; then
  echo "[finding-hash] $HASH_INPUT" >&2
  echo "  → $HASH" >&2
fi

echo "$HASH"
