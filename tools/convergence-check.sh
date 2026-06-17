#!/bin/bash
# super-fix 收敛判定工具 v3.3
# 用法: ./convergence-check.sh [options] <current-round-json> <round-number> [first-round-json]
# 必传: --findings-db=<db.json> --first-round-total=<N>
# 可选: --webfetch-trace=<tr.jsonl> --spot-check=N
# 返回: {"decision":"converged|continue|escalate|error","round":N,"current":{...},"message":"..."}
# 退出码: 0=converged, 1=continue, 2=escalate, 3=error

set -uo pipefail

# ---- 依赖检查 ----
HAVE_JQ=false
HAVE_PYTHON=false
command -v jq >/dev/null 2>&1 && HAVE_JQ=true
command -v python3 >/dev/null 2>&1 && HAVE_PYTHON=true

if ! $HAVE_JQ && ! $HAVE_PYTHON; then
  echo '{"decision":"error","message":"Need jq or python3. Install: brew install jq (macOS) or apt install jq (Linux)"}'
  exit 3
fi

# ---- 参数解析 ----
FIRST_ROUND=false
FINDINGS_DB=""
WEBFETCH_TRACE=""
SPOT_CHECK="3"
FIRST_ROUND_TOTAL=""
SBL_FILE=""
SMOKE_TEST_FILE=""
CACHE_DIR=".audit-cache"

while [ $# -gt 0 ]; do
  case "$1" in
    --first-round) FIRST_ROUND=true; shift ;;
    --findings-db=*) FINDINGS_DB="${1#*=}"; shift ;;
    --webfetch-trace=*) WEBFETCH_TRACE="${1#*=}"; shift ;;
    --spot-check=*) SPOT_CHECK="${1#*=}"; shift ;;
    --first-round-total=*) FIRST_ROUND_TOTAL="${1#*=}"; shift ;;
    --sbl=*) SBL_FILE="${1#*=}"; shift ;;
    --smoke-test=*) SMOKE_TEST_FILE="${1#*=}"; shift ;;
    --cache-dir=*) CACHE_DIR="${1#*=}"; shift ;;
    *) break ;;
  esac
done

if [ -z "$FINDINGS_DB" ]; then
  echo '{"decision":"error","message":"--findings-db=<db.json> is required"}'
  exit 3
fi
if [ -z "$FIRST_ROUND_TOTAL" ]; then
  echo '{"decision":"error","message":"--first-round-total=<N> is required for result-driven convergence"}'
  exit 3
fi

CURRENT_FILE="$1"
PREV_FILE="$2"
ROUND_NUM="$3"

if [ -z "$CURRENT_FILE" ] || [ -z "$ROUND_NUM" ]; then
  echo '{"decision":"error","message":"Usage: convergence-check.sh --findings-db=<db.json> --first-round-total=<N> [options] <current.json> <prev.json> <round>"}'
  exit 3
fi

# ---- JSON 解析函数 ----
# 输入: <file>  输出: {"P0":N,"P1":N,"P2":N,"P3":N,"invalid":N,"cannot_fix":N,"valid":true/false}
count_severities() {
  local file="$1"
  local label="$2"

  if [ ! -f "$file" ]; then
    if [ "$label" = "prev" ] && $FIRST_ROUND; then
      echo '{"P0":0,"P1":0,"P2":0,"P3":0,"invalid":0,"cannot_fix":0,"valid":true}'
    else
      echo '{"valid":false}'
    fi
    return
  fi

  if $HAVE_JQ; then
    local result
    result=$(jq -c '{
      "P0": ([.[] | select(.severity == "P0")] | length),
      "P1": ([.[] | select(.severity == "P1")] | length),
      "P2": ([.[] | select(.severity == "P2")] | length),
      "P3": ([.[] | select(.severity == "P3")] | length),
      "invalid": ([.[] | select(.severity != null and (.severity != "P0" and .severity != "P1" and .severity != "P2" and .severity != "P3"))] | length),
      "cannot_fix": ([.[] | select(.cannot_fix_reason != null)] | length),
      "valid": true
    }' "$file" 2>/dev/null)
    if [ -z "$result" ] || [ "$result" = "null" ]; then
      echo '{"valid":false}'
    else
      echo "$result"
    fi
  elif $HAVE_PYTHON; then
    python3 -c "
import json
try:
    with open('$file') as f:
        data = json.load(f)
    p0 = sum(1 for x in data if x.get('severity') == 'P0')
    p1 = sum(1 for x in data if x.get('severity') == 'P1')
    p2 = sum(1 for x in data if x.get('severity') == 'P2')
    p3 = sum(1 for x in data if x.get('severity') == 'P3')
    inv = sum(1 for x in data if x.get('severity') not in ('P0','P1','P2','P3', None))
    cfx = sum(1 for x in data if x.get('cannot_fix_reason'))
    print(json.dumps({'P0':p0,'P1':p1,'P2':p2,'P3':p3,'invalid':inv,'cannot_fix':cfx,'valid':True}))
except Exception:
    print(json.dumps({'valid':False}))
" 2>/dev/null || echo '{"valid":false}'
  fi
}

# ---- 跨轮次 Finding 生命周期验证 ----
# 验证上一轮所有 finding 在本轮有明确归宿（重新报告或标记 fix_verified）
check_findings_lifecycle() {
  local current_file="$1"
  local prev_file="$2"

  [ ! -f "$prev_file" ] && return 0
  [ ! -f "$current_file" ] && return 0

  local prev_ids
  if $HAVE_JQ; then
    prev_ids=$(jq -r '.[] | .id // empty' "$prev_file" 2>/dev/null)
  else
    prev_ids=$(python3 -c "import json; d=json.load(open('$prev_file')); [print(x['id']) for x in d if 'id' in x]" 2>/dev/null)
  fi

  local current_ids
  if $HAVE_JQ; then
    current_ids=$(jq -r '.[] | select(.fix_verified == true) | .id // empty' "$current_file" 2>/dev/null)
  else
    current_ids=$(python3 -c "import json; d=json.load(open('$current_file')); [print(x['id']) for x in d if x.get('fix_verified')]" 2>/dev/null)
  fi

  local lost=0
  local total_prev=0
  for pid in $prev_ids; do
    [ -z "$pid" ] && continue
    total_prev=$((total_prev + 1))
    local found=0
    for cid in $current_ids; do
      [ "$cid" = "$pid" ] && found=1 && break
    done
    [ "$found" -eq 0 ] && lost=$((lost + 1))
  done

  [ "$total_prev" -eq 0 ] && return 0
  echo "$lost"
}

# ---- cannot_fix_reason 白名单验证 (v3.3) ----
# 仅接受: external_dependency/data_migration/out_of_scope/missing_infrastructure/design_tradeoff
ALLOWED_REASONS="external_dependency data_migration out_of_scope missing_infrastructure design_tradeoff"
validate_cannot_fix_reasons() {
  local file="$1"
  [ ! -f "$file" ] && return 0

  local invalid_reasons
  if $HAVE_JQ; then
    invalid_reasons=$(jq -r '.[] | select(.cannot_fix_reason != null) | .cannot_fix_reason' "$file" 2>/dev/null | sort -u)
  else
    invalid_reasons=$(python3 -c "
import json
d = json.load(open('$file'))
seen = sorted(set(x['cannot_fix_reason'] for x in d if x.get('cannot_fix_reason')))
print('\n'.join(seen))
" 2>/dev/null)
  fi

  local bad=0
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    if ! echo " $ALLOWED_REASONS " | grep -qF " $r "; then
      bad=$((bad + 1))
      echo "INVALID_REASON: $r" >&2
    fi
  done <<< "$invalid_reasons"

  [ "$bad" -eq 0 ] && return 0
  return 1
}

# ---- 增量模式 SBL git_commit 校验 (v3.3) ----
# 如启用 SBL 校验,确保当前轮次的 git_commit 在 SBL 关联文件中存在
validate_sbl_git_commit() {
  local findings_file="$1"
  local sbl_file="$2"
  [ ! -f "$sbl_file" ] && return 0
  [ ! -f "$findings_file" ] && return 0

  local current_commit
  current_commit=$(git rev-parse HEAD 2>/dev/null)
  [ -z "$current_commit" ] && return 0

  if $HAVE_JQ; then
    sbl_commit=$(jq -r '.git_commit // empty' "$sbl_file" 2>/dev/null)
  else
    sbl_commit=$(python3 -c "import json; print(json.load(open('$sbl_file')).get('git_commit',''))" 2>/dev/null)
  fi

  [ -z "$sbl_commit" ] && return 0
  [ "$sbl_commit" = "$current_commit" ] && return 0

  # SBL commit 不匹配 → 检查是否有相关文件被修改
  local changed_files
  changed_files=$(git diff --name-only "$sbl_commit"..HEAD 2>/dev/null | head -20)
  if [ -n "$changed_files" ]; then
    echo "STALE_SBL: sbl_file=$sbl_file sbl_commit=$sbl_commit current_commit=$current_commit"
    return 1
  fi
  return 0
}

# ---- 缓存大小检查 (v3.3) ----
# >100MB 警告,保留最近 3 轮
check_cache_size() {
  local cache_dir="$1"
  [ ! -d "$cache_dir" ] && return 0

  local size_mb
  if command -v du >/dev/null 2>&1; then
    size_mb=$(du -sm "$cache_dir" 2>/dev/null | awk '{print $1}')
  else
    size_mb=0
  fi

  [ "$size_mb" -gt 100 ] && echo "CACHE_OVERSIZE:${size_mb}MB"
  return 0
}

# ---- Phase 5.5 冒烟测试读取 (v3.3) ----
# 冒烟测试结果有效则计入收敛判定
check_smoke_test() {
  local smoke_file="$1"
  [ ! -f "$smoke_file" ] && echo "NO_SMOKE_TEST"
  return 0
}

# git diff 锚定检测: 修复轮次应有 git 变更 (用 active 数,排除已 fix_verified)
check_git_anchor() {
  local prev_active="$1"
  local current_active="$2"
  local round_num="$3"
  [ "$round_num" -le 1 ] && return 0
  [ "$prev_active" -eq 0 ] && return 0
  [ "$current_active" -ne 0 ] && return 0
  # 非 git 仓库或无变更暂存区 → 跳过 (CI 场景)
  git rev-parse --git-dir >/dev/null 2>&1 || return 0
  local changes
  changes=$(git diff --name-only HEAD 2>/dev/null | head -5 | wc -l | tr -d ' ')
  [ "$changes" -gt 0 ] && return 0
  echo "SUSPICIOUS"
}

# ---- 执行计数 ----
current=$(count_severities "$CURRENT_FILE" "current")
prev=$(count_severities "$PREV_FILE" "prev")

# ---- 验证结果有效性 ----
current_valid=$(echo "$current" | tr -d ' \n' | grep -oE '"valid":[a-z]+' | head -1 | cut -d: -f2)
prev_valid=$(echo "$prev" | tr -d ' \n' | grep -oE '"valid":[a-z]+' | head -1 | cut -d: -f2)

if [ "$current_valid" != "true" ]; then
  echo "{\"decision\":\"error\",\"message\":\"Current file unparseable or missing: $CURRENT_FILE\"}"
  exit 3
fi

if [ "$prev_valid" != "true" ] && [ "$ROUND_NUM" -gt 1 ]; then
  echo "{\"decision\":\"continue\",\"round\":$ROUND_NUM,\"message\":\"Prev file unreadable, continuing but will check next round\"}"
  exit 1
fi

# ---- cannot_fix_reason 白名单校验 ----
if ! validate_cannot_fix_reasons "$CURRENT_FILE"; then
  echo "{\"decision\":\"continue\",\"round\":$ROUND_NUM,\"message\":\"Invalid cannot_fix_reason values found. Only allowed: $ALLOWED_REASONS\"}"
  exit 1
fi

# ---- 增量模式 SBL 校验 ----
SBL_WARN=$(validate_sbl_git_commit "$CURRENT_FILE" "$SBL_FILE")
if [ -n "$SBL_WARN" ]; then
  echo "{\"decision\":\"continue\",\"round\":$ROUND_NUM,\"sbl_warn\":\"$SBL_WARN\",\"message\":\"SBL git_commit mismatch, related files changed. Upgrade to deep mode.\"}"
  exit 1
fi

# ---- 缓存大小警告 (非阻塞,仅提示) ----
CACHE_WARN=$(check_cache_size "$CACHE_DIR")

# ---- 计算总数 (v3.3: 排除 fix_verified=true 的已修复 finding) ----
compute_totals() {
  # 使用环境变量传递,避免 heredoc 内嵌引号问题
  export _CUR="$current" _PREV="$prev" _CUR_FILE="$CURRENT_FILE" _PREV_FILE="${PREV_FILE:-}"
  python3 <<'PYEOF'
import json, os
def active_total(path):
    if not path or not os.path.exists(path):
        return 0
    with open(path) as f:
        data = json.load(f)
    return sum(1 for x in data if not x.get('fix_verified'))

EMPTY_PREV = {"P0":0,"P1":0,"P2":0,"P3":0,"invalid":0,"cannot_fix":0,"valid":True}

ct = active_total(os.environ['_CUR_FILE'])
pt = active_total(os.environ.get('_PREV_FILE',''))
c = json.loads(os.environ['_CUR'])
prev_str = os.environ.get('_PREV','')
p = json.loads(prev_str) if prev_str and prev_str != '{"valid":false}' else EMPTY_PREV
cfx = c.get('cannot_fix',0)
print(json.dumps({'c':ct,'p':pt,'cfx':cfx,'current':c,'previous':p}))
PYEOF
}

if $HAVE_JQ || $HAVE_PYTHON; then
  totals=$(compute_totals 2>/dev/null)
  if [ -z "$totals" ]; then
    echo "{\"decision\":\"error\",\"message\":\"compute_totals failed; check JSON syntax in findings files\"}"
    exit 3
  fi
fi

current_total=$(echo "$totals" | tr -d ' \n' | grep -oE '"c":-?[0-9]+' | head -1 | cut -d: -f2)
prev_total=$(echo "$totals" | tr -d ' \n' | grep -oE '"p":-?[0-9]+' | head -1 | cut -d: -f2)
current_cfx=$(echo "$totals" | tr -d ' \n' | grep -oE '"cfx":-?[0-9]+' | head -1 | cut -d: -f2)
[ -z "$current_total" ] && current_total=0
[ -z "$prev_total" ] && prev_total=0
[ -z "$current_cfx" ] && current_cfx=0

# ---- 跨轮次校验：未归宿的 finding 阻止收敛 ----
if [ -n "$FINDINGS_DB" ] && [ -f "$PREV_FILE" ] && [ "$ROUND_NUM" -gt 1 ]; then
  LOST=$(check_findings_lifecycle "$CURRENT_FILE" "$PREV_FILE")
  if [ -n "$LOST" ] && [ "$LOST" -gt 0 ]; then
    echo "{\"decision\":\"continue\",\"round\":$ROUND_NUM,\"lost\":$LOST,\"message\":\"$LOST findings from round $((ROUND_NUM - 1)) unaccounted for (not re-reported, not fix_verified). Refusing convergence.\"}"
    exit 1
  fi
fi

# ---- git diff 锚定：修复轮次应有变更 ----
SUS=$(check_git_anchor "$prev_total" "$current_total" "$ROUND_NUM")
if [ "$SUS" = "SUSPICIOUS" ]; then
  echo "{\"decision\":\"continue\",\"round\":$ROUND_NUM,\"message\":\"SUSPICIOUS: $prev_total findings in prev round but zero git changes. Findings may have been dropped rather than fixed.\"}"
  exit 1
fi

# ---- webfetch 交叉验证：agent 声称调用的 URL 必须在真实 trace 中出现 ----
if [ -n "$WEBFETCH_TRACE" ] && [ -f "$WEBFETCH_TRACE" ]; then
  AGENT_URLS=$(grep -oP '"url":"[^"]+"' "$CURRENT_FILE" 2>/dev/null | sed 's/"url":"//;s/"$//' | sort -u)
  TRACE_URLS=$(cat "$WEBFETCH_TRACE" | sort -u)
  FORGED=0
  for url in $AGENT_URLS; do
    echo "$TRACE_URLS" | grep -qF "$url" || FORGED=$((FORGED + 1))
  done
  if [ "$FORGED" -gt 0 ]; then
    echo "{\"decision\":\"continue\",\"round\":$ROUND_NUM,\"forged_sources\":$FORGED,\"message\":\"$FORGED agent-claimed webfetch URLs not found in trace log. Convergence blocked.\"}"
    exit 1
  fi
fi

# ---- 抽样验证: 重新 webfetch 并比对 excerpt (orchestrator 执行实际比对) ----
if [ -f "$CURRENT_FILE" ] && [ "$SPOT_CHECK" -gt 0 ] 2>/dev/null; then
  EXCERPTS=$(grep -oP '"excerpt":"[^"]*"' "$CURRENT_FILE" 2>/dev/null | head -"$SPOT_CHECK")
  if [ -n "$EXCERPTS" ]; then
    # 标记 spot-check 已发起(由 orchestrator 完成实际比对)
    :
  fi
fi

# ---- Phase 5.5 冒烟测试检查 (v3.3) ----
SMOKE_STATUS=$(check_smoke_test "$SMOKE_TEST_FILE")

# ---- 决策逻辑 (v3.3 结果驱动收敛) ----
# 收敛条件(同时满足):
#  ① 最近一轮发现数 ≤ 首轮的 10%
#  ② 无 P0/P1 新发现
#  ③ Meta-Review 通过(由 orchestrator 把控,脚本仅做数据准备)

# 提取 P0/P1 数量
current_p0=$(echo "$current" | tr -d ' \n' | grep -oE '"P0":-?[0-9]+' | head -1 | cut -d: -f2)
current_p1=$(echo "$current" | tr -d ' \n' | grep -oE '"P1":-?[0-9]+' | head -1 | cut -d: -f2)
[ -z "$current_p0" ] && current_p0=0
[ -z "$current_p1" ] && current_p1=0

# 计算 10% 阈值
FIRST_TOTAL=$FIRST_ROUND_TOTAL
if [ "$FIRST_TOTAL" -lt 1 ]; then FIRST_TOTAL=1; fi
THRESHOLD=$(python3 -c "import math; print(math.ceil($FIRST_TOTAL * 0.1))" 2>/dev/null || echo "0")
[ -z "$THRESHOLD" ] && THRESHOLD=0

# 有 P0/P1 → 必须继续
if [ "$current_p0" -gt 0 ] || [ "$current_p1" -gt 0 ]; then
  echo "{\"decision\":\"continue\",\"round\":$ROUND_NUM,\"current\":$current,\"current_p0\":$current_p0,\"current_p1\":$current_p1,\"message\":\"P0/P1 still present (P0=$current_p0, P1=$current_p1). Must fix all.\"}"
  exit 1
fi

# 发现数 > 阈值 → 继续
if [ "$current_total" -gt "$THRESHOLD" ]; then
  echo "{\"decision\":\"continue\",\"round\":$ROUND_NUM,\"current\":$current,\"threshold\":$THRESHOLD,\"message\":\"Found $current_total findings in round $ROUND_NUM (threshold ≤10% of first round = $THRESHOLD). Continue fixing.\"}"
  exit 1
fi

# 已达结果驱动阈值但需检查冒烟测试
if [ "$SMOKE_STATUS" = "NO_SMOKE_TEST" ] && [ "$ROUND_NUM" -gt 1 ]; then
  echo "{\"decision\":\"continue\",\"round\":$ROUND_NUM,\"current\":$current,\"message\":\"No smoke test result found. Phase 5.5 must run before convergence check.\"}"
  exit 1
fi

# 达到阈值 → 收敛,但需 Meta-Review (orchestrator 决定)
if [ "$current_total" -le "$THRESHOLD" ]; then
  echo "{\"decision\":\"converged\",\"round\":$ROUND_NUM,\"current\":$current,\"previous\":$prev,\"first_round_total\":$FIRST_TOTAL,\"threshold\":$THRESHOLD,\"cannot_fix\":$current_cfx,\"smoke\":\"$SMOKE_STATUS\",\"cache_warn\":\"$CACHE_WARN\",\"message\":\"Result-driven convergence: round $ROUND_NUM found $current_total ≤ 10% of first round ($THRESHOLD). Awaiting Meta-Review.\"}"
  exit 0
fi

# 超限诊断 (≥8 轮, v3.3)
if [ "$ROUND_NUM" -ge 8 ]; then
  ESCALATION_FILE="$CACHE_DIR/escalation-${ROUND_NUM}.json"
  cat > "$ESCALATION_FILE" 2>/dev/null <<EOF
{
  "round": ${ROUND_NUM},
  "current_total": ${current_total},
  "first_round_total": ${FIRST_TOTAL},
  "threshold": ${THRESHOLD},
  "current": ${current},
  "previous": ${prev},
  "suggestion": "8+ rounds without convergence. Options: (1) downgrade to quick mode and ship what we have; (2) expand cache/budget for next round; (3) request human intervention to identify blind spots in SBL.",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  echo "{\"decision\":\"escalate\",\"round\":$ROUND_NUM,\"current\":$current,\"previous\":$prev,\"escalation_file\":\"$ESCALATION_FILE\",\"message\":\"EMERGENCY: 8+ rounds without convergence. Escalation written to $ESCALATION_FILE. Pausing for human decision.\"}"
  exit 2
fi

echo "{\"decision\":\"error\",\"round\":$ROUND_NUM,\"message\":\"Decision logic did not match any branch. Check threshold/first_round_total.\"}"
exit 3