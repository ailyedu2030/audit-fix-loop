#!/bin/bash
# validate-causal-chain.sh (v4.2.0) — P1 Depth: Reject shallow findings
#
# Validates that each finding's root_cause is NOT a restatement of its description.
# Uses word overlap ratio to detect shallow findings.
#
# Usage:
#   validate-causal-chain.sh <findings.json>
#   validate-causal-chain.sh --all .audit-cache/findings/
#
# Exit: 0 = all findings have adequate depth
#       1 = shallow finding(s) detected (reject)

set -uo pipefail

INPUT="$1"
SHALLOW_COUNT=0
TOTAL=0

# Compute word overlap between two strings
word_overlap() {
  local a="$1" b="$2"
  # Normalize: lowercase, split on non-alnum, unique words
  local words_a words_b
  words_a=$(echo "$a" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '\n' | sort -u)
  words_b=$(echo "$b" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '\n' | sort -u)
  
  local intersection union
  intersection=$(comm -12 <(echo "$words_a") <(echo "$words_b") | wc -l | tr -d ' ')
  union=$(echo "$words_a" "$words_b" | sort -u | wc -l | tr -d ' ')
  
  if [ "$union" -eq 0 ]; then echo "1.0"; return; fi
  awk "BEGIN { printf \"%.3f\", $intersection / $union }"
}

check_finding() {
  local json="$1"
  local id description root_cause causal_chain_len
  id=$(echo "$json" | jq -r '.id // "unknown"')
  description=$(echo "$json" | jq -r '.description // ""')
  root_cause=$(echo "$json" | jq -r '.root_cause // ""')
  causal_chain_len=$(echo "$json" | jq -r '.causal_chain | length // 0')
  
  TOTAL=$((TOTAL + 1))
  
  # Check 1: root_cause minimum length
  if [ ${#root_cause} -lt 20 ]; then
    echo "  ✗ $id: root_cause too short (${#root_cause} < 20 chars)"
    SHALLOW_COUNT=$((SHALLOW_COUNT + 1))
    return
  fi
  
  # Check 2: causal_chain ≥ 3 steps
  if [ "$causal_chain_len" -lt 3 ]; then
    echo "  ✗ $id: causal_chain too short ($causal_chain_len < 3 steps)"
    SHALLOW_COUNT=$((SHALLOW_COUNT + 1))
    return
  fi
  
  # Check 3: word overlap between description and root_cause
  local overlap
  overlap=$(word_overlap "$description" "$root_cause")
  if awk "BEGIN { exit !($overlap > 0.7) }"; then
    echo "  ✗ $id: root_cause restates description (overlap=${overlap})"
    SHALLOW_COUNT=$((SHALLOW_COUNT + 1))
    return
  fi
  
  # Check 4: cross_subsystem_flows if marked cross_subsystem
  local cross_subsystem
  cross_subsystem=$(echo "$json" | jq -r '.cross_subsystem // false')
  if [ "$cross_subsystem" = "true" ]; then
    local flow_count
    flow_count=$(echo "$json" | jq -r '.cross_subsystem_flows | length // 0')
    if [ "$flow_count" -lt 1 ]; then
      echo "  ✗ $id: cross_subsystem=true but no cross_subsystem_flows"
      SHALLOW_COUNT=$((SHALLOW_COUNT + 1))
      return
    fi
  fi
  
  echo "  ✓ $id: depth OK (chain=$causal_chain_len, overlap=${overlap})"
}

if [ "$1" = "--all" ]; then
  dir="${2:-.audit-cache/findings}"
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    echo "Checking: $(basename $f)"
  tmp=$(mktemp)
  jq -c '.findings[]' "$f" 2>/dev/null > "$tmp"
  while IFS= read -r finding; do
    [ -z "$finding" ] && continue
    check_finding "$finding"
  done < "$tmp"
  rm -f "$tmp"
  done
elif [ -f "$INPUT" ]; then
  tmp=$(mktemp)
  jq -c '.findings[]' "$INPUT" 2>/dev/null > "$tmp"
  while IFS= read -r finding; do
    [ -z "$finding" ] && continue
    check_finding "$finding"
  done < "$tmp"
  rm -f "$tmp"
else
  echo "Usage: $0 <findings.json> | $0 --all [dir]"
  exit 2
fi

echo ""
echo "=== Depth Check: $SHALLOW_COUNT / $TOTAL shallow findings ==="
if [ $SHALLOW_COUNT -gt 0 ]; then
  echo "→ REJECT: $SHALLOW_COUNT findings need deeper root cause analysis"
  exit 1
fi
echo "→ ACCEPT: all findings have adequate depth"
exit 0
