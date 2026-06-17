#!/bin/bash
# subsystem-manifest.sh (v4.0.0)
# Generate subsystem manifest from project structure
#
# v3.7 vs v4:
#   v3.7: 7 agents split by file (Bandwagon effect, file-local scope)
#   v4:   agents split by SUBSYSTEM (Linux kernel style, multi-homing for shared)
#
# Design decisions (from Metis review):
#   - Multi-homing: files can belong to multiple subsystems
#   - shared/ category: cross-cutting files (utils, types, middleware)
#   - Path alias support: @/lib/utils handled
#   - Test files belong to same subsystem as their source
#   - Config files go to "infra" subsystem
#
# Usage:
#   subsystem-manifest.sh generate    # Generate manifest from project
#   subsystem-manifest.sh show        # Show current manifest
#   subsystem-manifest.sh validate    # Check manifest integrity
#   subsystem-manifest.sh stability   # Check dice coefficient across runs
#
# Output: .audit-cache/subsystem-manifest.json

set -uo pipefail

MANIFEST=".audit-cache/subsystem-manifest.json"
HISTORY_DIR=".audit-cache/subsystem-history"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# Known subsystem patterns (declarative + heuristic)
# Format: "name|path_pattern|category"
KNOWN_SUBSYSTEMS=(
  "ai_exam|server/src/services/aiExam|domain"
  "ai_exam|server/src/routes/exam_ai|domain"
  "ai_exam|server/src/routes/admin|domain"
  "migrations|server/src/db/migrations|infra"
  "tts|server/src/services/tts|domain"
  "tts|server/src/routes/tts|domain"
  "grammar|server/src/services/grammar|domain"
  "grammar|server/src/routes/grammar|domain"
  "auth|server/src/middleware/auth|infra"
  "auth|server/src/routes/auth|infra"
  "user|server/src/services/user|domain"
  "user|server/src/routes/user|domain"
  "course|server/src/services/course|domain"
  "course|server/src/routes/course|domain"
  "slidelesson|src/components/slidelesson|domain"
  "exam|src/components/exam|domain"
  "exam|src/components/exam-ai|domain"
)

# Cross-cutting files (shared, multi-homed)
SHARED_FILES=(
  "src/lib/utils.ts"
  "src/lib/apiBase.ts"
  "src/lib/audioCache.ts"
  "src/lib/eventBus.ts"
  "src/lib/audioContext.ts"
  "src/lib/audioCacheCleanup.ts"
  "src/types.ts"
  "server/src/utils/security.ts"
  "server/src/middleware/auth.ts"
  "server/src/middleware/rateLimit.ts"
  "server/src/middleware/error.ts"
  "server/src/middleware/csrf.ts"
  "server/src/db/index.ts"
  "server/src/db/schema.ts"
  "server/src/index.ts"
)

generate() {
  local tmp
  tmp=$(mktemp)
  
  # Build manifest: { files: { file_path: [subsystem_names] }, subsystems: { name: { files: [], files_count: 0, category: "" } } }
  local files_obj="{}"
  local subs_obj="{}"
  local unassigned=()
  
  # Find all source files (include .sql for migration drift detection per AAR v4.1)
  local source_files
  source_files=$(find "$PROJECT_ROOT" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.sql" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" \
    -not -path "*/.audit-cache/*" -not -path "*/tests/*" 2>/dev/null \
    | sed "s|^$PROJECT_ROOT/||" | sort)
  
  # Find test files separately
  local test_files
  test_files=$(find "$PROJECT_ROOT/tests" -type f \( -name "*.ts" -o -name "*.tsx" \) 2>/dev/null \
    | sed "s|^$PROJECT_ROOT/||" | sort)
  
  # Process source files
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    
    # Check if shared/cross-cutting
    local is_shared=false
    for shared in "${SHARED_FILES[@]}"; do
      if [ "$f" = "$shared" ] || [[ "$f" == *"$shared"* ]]; then
        is_shared=true
        break
      fi
    done
    
    if [ "$is_shared" = true ]; then
      # Shared file: belongs to "shared" subsystem
      files_obj=$(echo "$files_obj" | jq --arg f "$f" --arg sub "shared" \
        '.[$f] = (.[$f] + ["shared"] | unique)')
      subs_obj=$(echo "$subs_obj" | jq --arg sub "shared" \
        '. + {($sub): {files: [], category: "shared"}}')
      continue
    fi
    
    # Check known subsystem patterns
    local matched_subs=()
    for pattern_def in "${KNOWN_SUBSYSTEMS[@]}"; do
      local sub_name="${pattern_def%%|*}"
      local pattern="${pattern_def#*|}"
      pattern="${pattern%|*}"
      
      if [[ "$f" == *"$pattern"* ]]; then
        matched_subs+=("$sub_name")
      fi
    done
    
    if [ ${#matched_subs[@]} -eq 0 ]; then
      # Try filename-based heuristic (extract domain from filename)
      local basename
      basename=$(basename "$f" .ts)
      basename=$(basename "$basename" .tsx)
      basename=$(basename "$basename" .sql)
      local lower_base
      lower_base=$(echo "$basename" | tr '[:upper:]' '[:lower:]')
      
      # Match filename patterns: e.g., aiExamPoolService → ai_exam
      local filename_match=""
      for pattern_def in "${KNOWN_SUBSYSTEMS[@]}"; do
        local sub_name="${pattern_def%%|*}"
        local pattern="${pattern_def#*|}"
        pattern="${pattern%|*}"
        # Extract just the subsystem keyword from path
        local keyword
        keyword=$(basename "$pattern")
        if [[ "$lower_base" == *"$keyword"* ]]; then
          filename_match="$sub_name"
          break
        fi
      done
      
      if [ -n "$filename_match" ]; then
        matched_subs+=("$filename_match")
        continue
      fi
      
      # Unassigned - try dir heuristic
      local dir
      dir=$(dirname "$f")
      local first_dir
      first_dir=$(echo "$dir" | cut -d/ -f1)
      local second_dir
      second_dir=$(echo "$dir" | cut -d/ -f2)
      local third_dir
      third_dir=$(echo "$dir" | cut -d/ -f3)
      
      # Generic dirs that don't constitute subsystems
      local generic_dirs=("services" "routes" "components" "middleware" "hooks" "pages" "lib" "utils" "contexts" "jobs" "db" "types" "scripts" "server" "src" "config" "test" "tests" "__tests__" "charts" "context")
      
      if [ "$first_dir" = "src" ] && [ -n "$second_dir" ] && [[ ! " ${generic_dirs[@]} " =~ " $second_dir " ]]; then
        matched_subs+=("$second_dir")
      elif [ "$first_dir" = "src" ] && [ "$second_dir" = "components" ]; then
        # Top-level UI components (Layout, AITeacher etc.) → ui_components
        matched_subs+=("ui_components")
      elif [ "$first_dir" = "server" ] && [ "$second_dir" = "src" ] && [ -n "$third_dir" ] && [[ ! " ${generic_dirs[@]} " =~ " $third_dir " ]]; then
        matched_subs+=("$third_dir")
      elif [ "$first_dir" = "server" ]; then
        matched_subs+=("server_infra")
      else
        unassigned+=("$f")
        matched_subs+=("unassigned")
      fi
    fi
    
    # Add file to each matched subsystem
    for sub in "${matched_subs[@]}"; do
      files_obj=$(echo "$files_obj" | jq --arg f "$f" --arg sub "$sub" \
        '.[$f] = (.[$f] + [$sub] | unique)')
      subs_obj=$(echo "$subs_obj" | jq --arg sub "$sub" --arg f "$f" \
        '.[$sub].files = (.[$sub].files + [$f] | unique)')
    done
  done <<< "$source_files"
  
  # Process test files: assign to same subsystem as source file (strip "tests/" prefix and "/__tests__/")
  while IFS= read -r tf; do
    [ -z "$tf" ] && continue
    # Map test file to source
    # tests/integration/foo.test.ts → look for src/integration/foo.ts or server/src/...
    # Simple heuristic: assign to first matched subsystem by path
    local matched_subs=()
    for pattern_def in "${KNOWN_SUBSYSTEMS[@]}"; do
      local sub_name="${pattern_def%%|*}"
      local pattern="${pattern_def#*|}"
      pattern="${pattern%|*}"
      if [[ "$tf" == *"$pattern"* ]]; then
        matched_subs+=("$sub_name")
      fi
    done
    if [ ${#matched_subs[@]} -eq 0 ]; then
      matched_subs+=("testing")
    fi
    for sub in "${matched_subs[@]}"; do
      files_obj=$(echo "$files_obj" | jq --arg f "$tf" --arg sub "$sub" \
        '.[$f] = (.[$f] + [$sub] | unique)')
      subs_obj=$(echo "$subs_obj" | jq --arg sub "$sub" --arg f "$tf" \
        '.[$sub].files = (.[$sub].files + [$f] | unique)')
    done
  done <<< "$test_files"
  
  # Finalize: add files_count and category, mark unassigned
  subs_obj=$(echo "$subs_obj" | jq '
    to_entries | map(.value.files_count = (.value.files | length)) |
    from_entries')
  
  # Add unassigned subsystem if any
  if [ ${#unassigned[@]} -gt 0 ]; then
    printf '%s\n' "${unassigned[@]}" | jq -R . | jq -s 'map(select(length > 0))' > /tmp/unassigned.json
    subs_obj=$(jq --slurpfile ua /tmp/unassigned.json '
      .unassigned = {files: $ua[0], files_count: ($ua[0] | length), category: "unknown"}' \
      <(echo "$subs_obj"))
    rm -f /tmp/unassigned.json
  fi
  
  # Add shared subsystem files count
  # Note: subs_obj is being built incrementally. Re-derive files from .files for accuracy
  subs_obj=$(echo "$files_obj" "$subs_obj" | jq -s '
    .[1] as $subs | .[0] as $files |
    $subs | to_entries | map(
      .key as $sub |
      .value.files = ($files | to_entries | map(select(.value | index($sub))) | map(.key)) |
      .value.files_count = (.value.files | length)
    ) | from_entries
  ')
  
  # Final manifest
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local source_count
  source_count=$(echo "$source_files" | grep -c '.' || true)
  local test_count
  test_count=$(echo "$test_files" | grep -c '.' || true)
  
  jq -n \
    --argjson files "$files_obj" \
    --argjson subs "$subs_obj" \
    --arg now "$now" \
    --argjson sourceFiles "$source_count" \
    --argjson testFiles "$test_count" \
    '{
      version: 1,
      generated_at: $now,
      source_files_count: $sourceFiles,
      test_files_count: $testFiles,
      subsystems: $subs,
      files: $files
    }' > "$MANIFEST"
  
  # Save to history (for stability check)
  mkdir -p "$HISTORY_DIR"
  cp "$MANIFEST" "$HISTORY_DIR/$(date +%s).json"
  
  echo "=== Subsystem Manifest Generated ==="
  echo "Total subsystems: $(echo "$subs_obj" | jq 'keys | length')"
  echo "Total files: $(echo "$source_files" | wc -l | tr -d ' ')"
  echo ""
  echo "Subsystem summary:"
  echo "$subs_obj" | jq -r 'to_entries[] | "  \(.key): \(.value.files_count) files [\(.value.category)]"'
  if [ ${#unassigned[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  Unassigned files (need manual review): ${#unassigned[@]}"
    for f in "${unassigned[@]:0:5}"; do echo "    - $f"; done
    if [ ${#unassigned[@]} -gt 5 ]; then echo "    ... and $(( ${#unassigned[@]} - 5 )) more"; fi
  fi
}

show() {
  if [ ! -f "$MANIFEST" ]; then
    echo "No manifest found. Run: subsystem-manifest.sh generate"
    exit 1
  fi
  echo "=== Current Subsystem Manifest ==="
  jq -r '
    "Generated: \(.generated_at)\n" +
    "Files: \(.source_files_count) source, \(.test_files_count) test\n" +
    "Subsystems: \(.subsystems | keys | length)\n" +
    "\nDetails:\n" +
    (.subsystems | to_entries[] | "  \(.key) [\(.value.category)]: \(.value.files_count) files\n")
  ' "$MANIFEST"
}

validate() {
  if [ ! -f "$MANIFEST" ]; then
    echo "No manifest. Run generate first."
    exit 1
  fi
  local errors=0
  
  # Check 1: every file has at least 1 subsystem
  local orphans
  orphans=$(jq -r '.files | to_entries[] | select(.value | length == 0) | .key' "$MANIFEST")
  if [ -n "$orphans" ]; then
    echo "ERROR: $orphans" | head -5
    echo "  Files with no subsystem assignment"
    errors=$((errors + 1))
  fi
  
  # Check 2: shared subsystem has files
  local shared_count
  shared_count=$(jq '.subsystems.shared.files_count // 0' "$MANIFEST")
  if [ "$shared_count" = "0" ]; then
    echo "INFO: shared subsystem empty (no cross-cutting files detected)"
  fi
  
  # Check 3: unassigned subsystem should be small
  local unassigned_count
  unassigned_count=$(jq '.subsystems.unassigned.files_count // 0' "$MANIFEST")
  if [ "$unassigned_count" -gt 5 ]; then
    echo "WARN: $unassigned_count unassigned files (>5, may need manual mapping)"
  fi
  
  # Check 4: subsystems should have ≥ 2 files (Metis concern: trivial subsystems)
  local tiny_subs
  tiny_subs=$(jq -r '.subsystems | to_entries[] | select(.value.files_count < 2) | .key' "$MANIFEST")
  if [ -n "$tiny_subs" ]; then
    echo "WARN: trivial subsystems (< 2 files):"
    echo "$tiny_subs" | head -5 | sed 's/^/    - /'
  fi
  
  if [ $errors -eq 0 ]; then
    echo "✓ Manifest validation passed"
    exit 0
  fi
  exit 1
}

# Check stability: dice coefficient between current and previous manifest
stability() {
  if [ ! -d "$HISTORY_DIR" ] || [ -z "$(ls "$HISTORY_DIR")" ]; then
    echo "No history. Need ≥ 2 runs to compute stability."
    exit 1
  fi
  local current
  current=$(jq -S '.subsystems | keys' "$MANIFEST" | sort -u)
  local previous
  previous=$(ls -t "$HISTORY_DIR" | head -2 | tail -1)
  if [ -z "$previous" ]; then
    echo "Need ≥ 2 runs to compute stability."
    exit 1
  fi
  local prev_keys
  prev_keys=$(jq -S '.subsystems | keys' "$HISTORY_DIR/$previous" | sort -u)
  
  # Dice coefficient: 2 * |A ∩ B| / (|A| + |B|)
  local intersection
  intersection=$(comm -12 <(echo "$current") <(echo "$prev_keys") | wc -l | tr -d ' ')
  local current_count
  current_count=$(echo "$current" | wc -l | tr -d ' ')
  local prev_count
  prev_count=$(echo "$prev_keys" | wc -l | tr -d ' ')
  
  if [ $((current_count + prev_count)) -eq 0 ]; then
    echo "Stability: undefined (no subsystems)"
    exit 1
  fi
  
  local dice=$(awk "BEGIN { printf \"%.3f\", 2 * $intersection / ($current_count + $prev_count) }")
  echo "Stability (dice coefficient): $dice"
  echo "Current: $current_count subsystems, Previous: $prev_count, Intersection: $intersection"
  
  if awk "BEGIN { exit !($dice >= 0.9) }"; then
    echo "✓ Stable (≥ 0.9)"
    exit 0
  else
    echo "✗ Unstable (< 0.9, subsystems changed significantly)"
    exit 1
  fi
}

case "${1:-show}" in
  generate) generate ;;
  show) show ;;
  validate) validate ;;
  stability) stability ;;
  *) echo "Usage: $0 {generate|show|validate|stability}"; exit 2 ;;
esac
