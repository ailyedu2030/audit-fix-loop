#!/bin/bash
# baseline-diff.sh (v3.6.0)
# 增量 audit: 只 audit 改动的文件/函数，其余走 baseline
#
# 原理:
#   1. git diff main..HEAD (or working tree) → changed files
#   2. 对每个 changed file，提取 changed functions (基于 @@ hunk)
#   3. 加载 baseline: 已知 zero-defect 的 (file, function) 集合
#   4. 输出"待 audit 范围" = changed - baseline_zero
#
# 用法:
#   baseline-diff.sh scope          # 列出本次需 audit 的范围
#   baseline-diff.sh mark-zeroed   # 把当前 diff 标记为已 audit (无 finding)
#   baseline-diff.sh expand <files> # 手动加文件进 audit 范围
#   baseline-diff.sh show-baseline # 看 zero-defect 范围
#
# 退出码: 0=有范围/操作成功, 1=无 git 范围

set -uo pipefail

BASELINE=".audit-cache/baseline-zero.json"
DIFF_RANGE="${AUDIT_DIFF_RANGE:-main..HEAD}"

ensure_baseline() {
  if [ ! -f "$BASELINE" ]; then
    mkdir -p "$(dirname "$BASELINE")"
    echo '{"version":1,"zero_defect_files":[],"zero_defect_functions":[],"updated_at":""}' > "$BASELINE"
  fi
}

# Get changed files in current diff
# Use working tree (vs HEAD) + committed-but-not-in-base (vs main)
get_changed_files() {
  {
    git diff --name-only HEAD 2>/dev/null
    git diff --name-only main..HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | grep -E '\.(ts|tsx|js|jsx|py|go|rs)$' | sort -u
}

# Get changed functions per file (simple heuristic: grep for hunk headers)
get_changed_functions() {
  local file="$1"
  {
    git diff HEAD -- "$file" 2>/dev/null
    git diff main..HEAD -- "$file" 2>/dev/null
  } | grep -oE '^\+[a-zA-Z_][a-zA-Z0-9_]*\s*[\(=<>]' | \
    sed 's/^+//;s/[[:space:]]*[(=<>].*//' | \
    sort -u | head -20
}

# Show audit scope (what to look at this run)
scope() {
  ensure_baseline
  local zeroed_files
  zeroed_files=$(jq -r '.zero_defect_files[]' "$BASELINE" 2>/dev/null)
  
  echo "=== Audit scope (diff: working tree + main..HEAD) ==="
  local changed
  changed=$(get_changed_files)
  
  if [ -z "$changed" ]; then
    echo "No file changes detected"
    echo "→ Recommend: run full audit anyway (no diff = stale state check)"
    return 1
  fi
  
  local in_scope=()
  local in_baseline=()
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if echo "$zeroed_files" | grep -qF "$f"; then
      in_baseline+=("$f")
    else
      in_scope+=("$f")
    fi
  done <<< "$changed"
  
  echo "Files in scope (need audit): ${#in_scope[@]}"
  for f in "${in_scope[@]}"; do
    echo "  [SCAN] $f"
    local funcs
    funcs=$(get_changed_functions "$f")
    if [ -n "$funcs" ]; then
      echo "$funcs" | while read -r fn; do
        echo "    → function: $fn"
      done
    fi
  done
  
  echo ""
  echo "Files in baseline (skip): ${#in_baseline[@]}"
  for f in "${in_baseline[@]}"; do
    echo "  [SKIP] $f"
  done
  
  if [ ${#in_scope[@]} -eq 0 ]; then
    echo ""
    echo "→ All changes are in baseline. No audit needed."
    echo "→ To re-audit baseline files: baseline-diff.sh expand <file>"
  fi
}

# Mark current diff as zero-defect (no findings)
mark_zeroed() {
  ensure_baseline
  local changed
  changed=$(get_changed_files)
  
  if [ -z "$changed" ]; then
    echo "No changes to mark"
    return 0
  fi
  
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local tmp
  tmp=$(mktemp)
  
  # Add files to zero_defect_files
  echo "$changed" | jq -R . | jq -s 'map(select(length > 0))' > /tmp/new_files.json
  
  jq --slurpfile newfiles /tmp/new_files.json --arg now "$now" \
     '.zero_defect_files = ((.zero_defect_files + $newfiles[0]) | unique) |
      .updated_at = $now' \
     "$BASELINE" > "$tmp" && mv "$tmp" "$BASELINE"
  
  rm -f /tmp/new_files.json
  echo "Marked $(echo "$changed" | wc -l | tr -d ' ') files as zero-defect"
  echo "Total zero-defect files: $(jq '.zero_defect_files | length' "$BASELINE")"
}

# Manually expand audit scope
expand() {
  local files=("$@")
  ensure_baseline
  local tmp
  tmp=$(mktemp)
  
  printf '%s\n' "${files[@]}" | jq -R . | jq -s 'map(select(length > 0))' > /tmp/expand.json
  
  jq --slurpfile expandfiles /tmp/expand.json \
     '.zero_defect_files = (.zero_defect_files - $expandfiles[0])' \
     "$BASELINE" > "$tmp" && mv "$tmp" "$BASELINE"
  
  rm -f /tmp/expand.json
  echo "Expanded (removed from baseline): ${files[*]}"
}

# Show baseline
show_baseline() {
  ensure_baseline
  echo "=== Zero-defect baseline ($(jq '.zero_defect_files | length' "$BASELINE") files) ==="
  jq -r '.zero_defect_files[]' "$BASELINE" | head -30
  echo ""
  echo "Updated: $(jq -r '.updated_at' "$BASELINE")"
}

case "${1:-show-baseline}" in
  scope) scope ;;
  mark-zeroed) mark_zeroed ;;
  expand) shift; expand "$@" ;;
  show-baseline) show_baseline ;;
  *) echo "Usage: $0 {scope|mark-zeroed|expand <file>|show-baseline}"; exit 2 ;;
esac
