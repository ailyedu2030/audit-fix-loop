#!/bin/bash
# arbitrate-findings.sh (v4.4.0) — Phase 3 Arbitration
# Merge 5 Blue agent outputs into single findings.json
set -uo pipefail

FINDINGS_DIR="${1:-.audit-cache/findings}"
OUTPUT="${2:-.audit-cache/findings.json}"

tmp=$(mktemp)
echo '{"merged_from":[],"findings":[]}' > "$tmp"

count=0
for f in "$FINDINGS_DIR"/audit-blue-*.json; do
  [ -f "$f" ] || continue
  agent=$(basename "$f" .json)
  # 【v4.10】Validate findings is an array before merging
  local is_array
  is_array=$(jq -r 'if .findings | type == "array" then "true" else "false" end' < "$f")
  if [ "$is_array" != "true" ]; then
    echo "  ⚠ SKIP $agent: findings is not an array (type=$(jq -r '.findings | type' < "$f"))"
    continue
  fi
  local found_count
  found_count=$(jq -r '.findings | length' < "$f")
  echo "  Merging: $agent ($found_count findings)"
  
  jq --arg agent "$agent" --slurpfile acc "$tmp" '
    ($acc[0]) as $a |
    {
      merged_from: ($a.merged_from + [$agent]),
      findings: ($a.findings + [.["findings"][]?] | map(. + {source_agent: $agent}))
    }
  ' < "$f" > "${tmp}.new" && mv "${tmp}.new" "$tmp"
  
  count=$((count + 1))
done

# Compute stats
jq '.stats = {
    total: (.findings | length),
    by_severity: (.findings | group_by(.severity) | map({key: .[0].severity, value: length}) | from_entries),
    by_agent: (.findings | group_by(.source_agent) | map({key: .[0].source_agent, value: length}) | from_entries)
  }' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"

# Dedup: group by module+pattern, keep highest severity
jq '.findings |= (group_by(.module + "|" + (.pattern // "")) | map(
  sort_by(.severity) | .[0] + {duplicate_sources: [.[].source_agent] | unique}
))' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"

mv "$tmp" "$OUTPUT"

echo ""
echo "=== Arbitration Complete ==="
jq -r '"  Agents merged: \(.merged_from | length)", "  Total findings: \(.findings | length)", "  By severity: \(.stats.by_severity | to_entries | map("\(.key): \(.value)") | join(", "))", "  Dedup applied: group by module+pattern, keep max severity"' "$OUTPUT"
echo "  Output: $OUTPUT"
