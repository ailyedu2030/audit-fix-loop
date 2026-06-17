#!/bin/bash
# arbitrate-findings.sh (v4.4.0) — Phase 3 Arbitration
# Merge 5 Blue agent outputs into single findings.json
set -uo pipefail

FINDINGS_DIR="${1:-.audit-cache/findings}"
OUTPUT="${2:-.audit-cache/findings.json}"

tmp=$(mktemp)
echo '{"merged_from":[],"findings":[],"stats":{"total":0,"by_severity":{},"by_agent":{}}}' > "$tmp"

count=0
for f in "$FINDINGS_DIR"/audit-blue-*.json; do
  [ -f "$f" ] || continue
  agent=$(basename "$f" .json)
  echo "  Merging: $agent"
  
  jq --arg agent "$agent" '
    .merged_from += [$agent] |
    .findings += [.findings[]? + {source_agent: $agent}] |
    .stats.total += (.findings | length) |
    .stats.by_agent[$agent] = (.findings | length)
  ' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"
  
  count=$((count + 1))
done

# Compute severity distribution
jq '(.findings | group_by(.severity) | map({key: .[0].severity, value: length}) | from_entries) as $sev |
    .stats.by_severity = $sev' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"

# Dedup: if 2+ agents report same module+pattern, keep highest severity
jq '.findings |= (group_by(.module + "|" + .pattern) | map(
  sort_by(.severity) | .[0] + {duplicate_sources: [.[].source_agent] | unique}
))' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"

mv "$tmp" "$OUTPUT"

echo ""
echo "=== Arbitration Complete ==="
jq -r '"  Agents merged: \(.merged_from | length)", "  Total findings: \(.findings | length)", "  By severity: \(.stats.by_severity | to_entries | map("\(.key): \(.value)") | join(", "))", "  Dedup applied: group by module+pattern, keep max severity"' "$OUTPUT"
echo "  Output: $OUTPUT"
