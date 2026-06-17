#!/bin/bash
# cross-run-dedup.sh (v3.6.0)
# 跨 audit 周期去重
#
# 维护 .audit-cache/baseline.json: 所有已验证修复的 finding hashes
# 每次 audit Phase 2 输出 findings → 用此工具 filter:
#   - 在 baseline 中 → 跳过 (已修, 不再报)
#   - 不在 baseline 中 → 新 finding, 需处理
#   - baseline 中有, 但当前代码中 regression → 重新报警
#
# 用法:
#   cross-run-dedup.sh filter <findings.json>   # 过滤出新 findings
#   cross-run-dedup.sh commit <findings.json>   # 把已修 findings 加进 baseline
#   cross-run-dedup.sh show                     # 看 baseline 内容
#   cross-run-dedup.sh regression <findings.json> # 检查 baseline 中的 finding 是否回来了

set -uo pipefail

BASELINE=".audit-cache/baseline.json"

ACTION="${1:-show}"
INPUT="${2:-}"

ensure_baseline() {
  if [ ! -f "$BASELINE" ]; then
    mkdir -p "$(dirname "$BASELINE")"
    echo '{"version":1,"fixed_at":{},"hashes":[],"hash_to_finding":{}}' > "$BASELINE"
  fi
}

# Compute hash for each finding in JSON
# Expects input JSON: {"findings":[{"id":"F-001","module":"...","function":"...","pattern":"...","status":"fixed"}, ...]}
filter_new() {
  local input="$1"
  ensure_baseline
  local baseline_hashes
  baseline_hashes=$(jq -r '.hashes[]' "$BASELINE" 2>/dev/null | sort -u)
  
  # Temp files for separation
  local tmp_new
  tmp_new=$(mktemp)
  local tmp_dedup_log
  tmp_dedup_log=$(mktemp)
  local deduped=0
  
  # For each finding, compute hash. If hash in baseline → log dedup, else add to new.
  while IFS= read -r finding; do
    [ -z "$finding" ] && continue
    local module function pattern hash
    module=$(echo "$finding" | jq -r '.module // .file // ""')
    function=$(echo "$finding" | jq -r '.function // ""')
    pattern=$(echo "$finding" | jq -r '.pattern // .type // ""')
    
    if [ -z "$module" ] || [ -z "$pattern" ]; then
      echo "WARN: finding missing module/pattern, skipping" >&2
      continue
    fi
    
    hash=$(bash "$(dirname "$0")/finding-hash.sh" --module="$module" --function="$function" --pattern="$pattern")
    
    if echo "$baseline_hashes" | grep -qF "$hash"; then
      echo "DEDUP: $hash ($module/$function/$pattern)" >> "$tmp_dedup_log"
      deduped=$((deduped + 1))
    else
      echo "$finding" | jq -c ". + {semantic_hash:\"$hash\"}" >> "$tmp_new"
    fi
  done < <(jq -c '.findings[]' "$input")
  
  # Output: dedup log to stderr, JSON to stdout
  cat "$tmp_dedup_log" >&2
  
  # Wrap new findings in JSON envelope
  if [ -s "$tmp_new" ]; then
    jq -s '{findings: ., deduped_count: '"$deduped"'}' "$tmp_new"
  else
    echo '{"findings":[],"deduped_count":'"$deduped"'}'
  fi
  
  rm -f "$tmp_new" "$tmp_dedup_log"
}

# Add fixed findings to baseline
commit_fixed() {
  local input="$1"
  ensure_baseline
  
  # Backup baseline
  cp "$BASELINE" "${BASELINE}.bak"
  
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  # Get all fixed findings, compute hash, add to baseline
  jq -c '.findings[] | select(.status == "fixed" or .status == "verified")' "$input" | while read -r finding; do
    local module function pattern hash id
    module=$(echo "$finding" | jq -r '.module // .file // ""')
    function=$(echo "$finding" | jq -r '.function // ""')
    pattern=$(echo "$finding" | jq -r '.pattern // .type // ""')
    id=$(echo "$finding" | jq -r '.id // "unknown"')
    
    if [ -z "$module" ] || [ -z "$pattern" ]; then continue; fi
    
    hash=$(bash "$(dirname "$0")/finding-hash.sh" --module="$module" --function="$function" --pattern="$pattern")
    
    # Add to baseline (idempotent)
    local tmp
    tmp=$(mktemp)
    jq --arg hash "$hash" --arg id "$id" --arg now "$now" \
       '.hashes = (.hashes + [$hash] | unique) |
        .hash_to_finding[$hash] = $id |
        .fixed_at[$hash] = $now' \
       "$BASELINE" > "$tmp" && mv "$tmp" "$BASELINE"
    echo "BASELINE+: $hash ($id)"
  done
  
  echo "Baseline updated: $(jq '.hashes | length' "$BASELINE") total hashes"
}

# Show baseline
show() {
  ensure_baseline
  echo "=== Baseline: $(jq '.hashes | length' "$BASELINE") fixed findings ==="
  jq -r '.hashes[] as $h | "  \($h) → \(.hash_to_finding[$h] // "?")"' "$BASELINE" | head -20
}

case "$ACTION" in
  filter)
    [ -z "$INPUT" ] && { echo "ERROR: filter requires input file" >&2; exit 2; }
    filter_new "$INPUT"
    ;;
  commit)
    [ -z "$INPUT" ] && { echo "ERROR: commit requires input file" >&2; exit 2; }
    commit_fixed "$INPUT"
    ;;
  show)
    show
    ;;
  *)
    echo "Usage: $0 {show|filter|commit} [findings.json]"
    exit 2
    ;;
esac
