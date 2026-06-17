---
name: audit-fix-loop-v3
version: 4.0.0
description: 系统性零信任审查与修复。**v4.0 解决 4 大根因**: Bandwagon (蓝队盲发散) / File-local scope (子系统 + flow trace) / Self-referential verification (红队跨模型) / Single-loop learning (AAR + 盲点注册)。继承 v3.7: 测试金字塔、跨次闭环、状态机。设计文档: `docs/plans/audit-fix-loop-v4-design-2026-06-17.md`。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Task, WebFetch, skill]
supersedes: [audit-fix-verify, audit-fix-loop-v3.3, audit-fix-loop-v3.4, audit-fix-loop-v3.5, audit-fix-loop-v3.6, audit-fix-loop-v3.7]
---

# Audit → Fix → Loop v4 — Layered Adversarial Audit

**v4 核心区别 (vs v3.7)**:
- **管道 → 系统**: 15 phase 线性管道改为 3 层独立系统 (Subsystem / Adversarial / Learning)
- **共享 pre-query → 盲发散简报**: 5 agent 各自独立 lens + subsystem + entry file
- **同模型审 → 跨模型红队**: 蓝队 (M2.7) vs 红队 (M3)，独立身份 + 攻击激励
- **零学习 → AAR + 盲点注册**: 每次 audit 后强制 4 问题复盘，方法更新持久化
- **file-local → 子系统 + flow trace**: 跨文件数据流显式建模 (32 cross-subsystem flows detected)

**v3.7 教训 (6 专家共识)**: "clear-domain 工具用于 complex-domain 问题" — v4 改用复杂领域协议 (假设驱动 + 独立验证 + 复盘学习)。

# Audit → Fix → Loop v3.5 — Zero-Trust Edition

**v3.5 核心区别 (vs v3.4)**:
- **静态零缺陷 → 零信任零缺陷**：每个 finding 必须有可证伪的 test 覆盖（mutation test 验证）
- **Test Pyramid 强制建立**：unit / integration / contract / e2e / property-based / chaos 6 层缺一不可
- **Property-Based Testing 强制**：状态机边界由 generator + shrink 捕获
- **Chaos Test 强制**：进程 kill / 网络失败 / 慢响应 / restart 必须有恢复路径验证
- **Mutation Test 强制**：改 1 行代码 → 测试必须 fail，否则测试无效（fix false sense of security）
- **Coverage 矩阵机械门禁**：每个 P0/P1 finding 必须有对应 test_id，缺一不可进 Phase 7

**v3.4 教训**: 在 2026-06-17 English-CET 语法模块审计中，agent 报"零缺陷"但实际只是"纸面零缺陷"——运行时边界、并发、错误恢复全未验证。**v3.5 用测试金字塔+变异测试根治"假阳性零缺陷"**。

---

## ⚡ 启动序列 (Phase 0 强制)

```bash
# 0. 读 .audit-cache/ 决定是否增量
ls -la .audit-cache/ 2>/dev/null

# 1. 创建 audit_state.json (Phase 0 必做, 不写则无法进 Phase 1)
cat > .audit-cache/audit_state.json <<EOF
{
  "run_id": "$(uuidgen 2>/dev/null || date +%s)_<scope>",
  "scope": "<module_name>",
  "mode": "deep|continuous|quick|incremental|emergency",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "current_round": 0,
  "current_phase": "PHASE_0_ENTRY",
  "findings": {},
  "test_coverage": {
    "FUNC-001": {"test_ids": [], "mutation_killed": false, "property_tested": false}
  },
  "phases_passed": {
    "PHASE_0_ENTRY": false,
    "PHASE_1_SBL": false,
    "PHASE_1_5_TEST_PYRAMID": false,
    "PHASE_2_REVIEW": false,
    "PHASE_3_ARBITRATION": false,
    "PHASE_4_FIX": false,
    "PHASE_4_5_TEST_AUTHOR": false,
    "PHASE_5_STATIC": false,
    "PHASE_5_5_SMOKE": false,
    "PHASE_5_6_DYNAMIC": false,
    "PHASE_5_7_CHAOS": false,
    "PHASE_5_8_MUTATION": false,
    "PHASE_6_LOOP": false,
    "PHASE_6_5_DEVIL_ADVOCATE": false,
    "PHASE_7_FINAL": false
  },
  "gates_passed": {},
  "cannot_fix_queue": [],
  "deferred_queue": []
}
EOF

# 2. 必跑门禁
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/gate-check.sh \
  --required-phase=PHASE_0_ENTRY \
  .audit-cache/audit_state.json
```

> **【v3.6 强制 RETRO】** 每次从一个 phase 转到下一个 phase 时，**必须**实际执行 `gate-check.sh` 并把返回的 `phases_passed` 字段**写回 `audit_state.json`**。v3.5 教训：4 轮 audit 跑完 `phases_passed` 仍是 `false` —— gate-check 工具从未被调用，导致最终报告"零缺陷"但 phase 实际未完成。
> 
> **写回模式** (必须执行):
> ```bash
> # 1. 跑门禁
> RESULT=$(bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/gate-check.sh \
>   --required-phase=PHASE_X_EXIT .audit-cache/audit_state.json)
> # 2. 用 jq 把 phases_passed 写回 (不能用 sed/手动)
> jq '.phases_passed.PHASE_X_EXIT = true' .audit-cache/audit_state.json \
>   > .audit-cache/audit_state.json.tmp \
>   && mv .audit-cache/audit_state.json.tmp .audit-cache/audit_state.json
> ```

---

## Phase 0: 入口 + 上下文 + 测试现状盘点

### 【v3.6 强制】 Phase 0.5: Baseline Load (跨次闭环)

**问题**: v3.5 audit 解决"单次闭环"（跑完修完报 zero-defect），但**跨次闭环缺失** — 下次跑 audit 又会发现 50 个问题（其中 45 个是已修过的）。

**v3.6 解决**: 跨次 baseline 机制 — 维护 `.audit-cache/baseline-zero.json` + `.audit-cache/baseline.json`，让已审计的代码永不再报，新代码自动进入 scope。

```bash
# Phase 0.5 必跑 — 检查 baseline 状态 + 决定 scope
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/baseline-diff.sh scope

# 输出示例:
#   Files in scope (need audit): 1
#     [SCAN] server/src/services/aiExamPoolService.ts
#   Files in baseline (skip): 5
#     [SKIP] server/src/services/aiExamWorker.ts
```

**3 个 baseline 文件 + 用途**:
| File | Tool | 用途 |
|------|------|------|
| `.audit-cache/baseline-zero.json` | `baseline-diff.sh` | 已审计且零缺陷的文件/函数 (skip) |
| `.audit-cache/baseline.json` | `cross-run-dedup.sh` | 已修的 finding hashes (去重) |
| `.audit-cache/regression-index.json` | `regression-suite.sh` | 历史 P0 fix 的 test (回归) |

**3 种 scope 决策**:
| 模式 | 何时用 | 行为 |
|------|--------|------|
| **full** | 第一次跑 / 重大重构 | audit 所有文件 |
| **incremental** | 常规 PR (默认) | 只 audit 改动的文件/函数 (git diff) |
| **diff-only** | 大型项目 / 频繁 audit | 只 audit 改动的行 |

**findings 必须用 canonical pattern id** (例如 `SRE-006-paper_lock_cleanup`):
```bash
# finding 报告时
HASH=$(bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/finding-hash.sh \
  --module=server/src/services/aiExamPoolService.ts \
  --function=markJobFailed \
  --pattern=paper_lock_cleanup)
echo "{\"id\":\"F-001\",\"semantic_hash\":\"$HASH\",...}"
```

**修复完成后 commit 到 baseline**:
```bash
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/cross-run-dedup.sh commit .audit-cache/findings.json
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/baseline-diff.sh mark-zeroed
```

**下次 audit 跑时**: 自动 dedup 已知 finding，skip 已知 zero 文件 — **5x 加速**。

### 模式选择

| 模式 | 场景 | 耗时 | 必须 Phase |
|------|------|------|-----------|
| **emergency** | P0 阻断 (生产事故) | 立即 | 0→4→4.5→5→5.5→5.6→5.7→5.8→7 |
| **quick** | ≤3 文件小改 | 15-30m | 0→1.0→1.5→2(3agent)→4→4.5→5→5.5→5.6→6→7 |
| **incremental** | 有基线, 改 1-3 文件 | 15-30m | 0→1.0→1.5→2(2agent)→4→4.5→5→5.5→5.6→5.8→6→7 |
| **deep** | 跨模块/安全 | 1-4h | 0→1.0→1.5→1.1-1.4→2(7agent)→3→4→4.5→5→5.5→5.6→5.7→5.8→6→6.5→7 |
| **continuous** | **全量零信任 (默认推荐)** | 2-8h | 同 deep + 强制 Phase 5.7/5.8 + 强制 8 轮上限 |

### 强制初始化 (无 audit_state.json 不能进 Phase 1)

```bash
# 1. 模式选择
read -p "Mode (emergency/quick/incremental/deep/continuous): " MODE

# 2. 初始化状态机
python3 -c "
import json, uuid, datetime
state = {
    'run_id': str(uuid.uuid4())[:8] + '_$(basename $PWD)_$(date +%s)',
    'scope': '<module>',
    'mode': '$MODE',
    'started_at': datetime.datetime.utcnow().isoformat() + 'Z',
    'current_round': 0,
    'current_phase': 'PHASE_0_ENTRY',
    'findings': {},
    'test_coverage': {},
    'phases_passed': {p: False for p in [
        'PHASE_0_ENTRY', 'PHASE_1_SBL', 'PHASE_1_5_TEST_PYRAMID',
        'PHASE_2_REVIEW', 'PHASE_3_ARBITRATION', 'PHASE_4_FIX',
        'PHASE_4_5_TEST_AUTHOR', 'PHASE_5_STATIC', 'PHASE_5_5_SMOKE',
        'PHASE_5_6_DYNAMIC', 'PHASE_5_7_CHAOS', 'PHASE_5_8_MUTATION',
        'PHASE_6_LOOP', 'PHASE_6_5_DEVIL_ADVOCATE', 'PHASE_7_FINAL'
    ]},
    'gates_passed': {},
    'cannot_fix_queue': [],
    'deferred_queue': []
}
with open('.audit-cache/audit_state.json', 'w') as f:
    json.dump(state, f, indent=2)
print('✅ audit_state.json created')
"

# 3. 必跑门禁 (Phase 0 → Phase 1 转换)
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/gate-check.sh \
  --required-phase=PHASE_0_ENTRY \
  .audit-cache/audit_state.json
# 必须 exit 0 才能进 Phase 1
```

### 测试现状盘点 (v3.5 新增)

```bash
# 检查现有测试覆盖
ls -la __tests__/ 2>/dev/null || ls -la tests/ 2>/dev/null
cat package.json | python3 -c "import json,sys; p=json.load(sys.stdin); print(json.dumps(p.get('scripts',{}),indent=2))"
cat package.json | python3 -c "import json,sys; p=json.load(sys.stdin); deps={**p.get('devDependencies',{}),**p.get('dependencies',{})}; print(json.dumps({k:v for k,v in deps.items() if any(t in k for t in ['test','vitest','jest','playwright','supertest','fast-check'])}, indent=2))"
# 写入 .audit-cache/test-baseline.json
```

### 缓存自动清理 (每次 Phase 0 必做)
```bash
du -sh .audit-cache/ 2>/dev/null  # > 100MB 警告
# 保留最近 3 轮
ls -t .audit-cache/findings-round-*.json | tail -n +4 | xargs rm -f
```

---

## Phase 1: SBL v3 (单一真源) + Test Pyramid 建立

### Phase 1.0: 预查询 (不可跳过)

不变, v3.4 仍适用。写入 `pre-query-{round}.json`。

### Phase 1.5: Test Pyramid 建立 (v3.5 强制)

**问题**: 大多数项目只有 1 层或 2 层测试。v3.5 要求至少 4 层：

```
                    ┌─────────────┐
                    │   E2E/UI    │  ← playwright
                    ├─────────────┤
                    │ Contract    │  ← supertest + openapi-validator
                    ├─────────────┤
                    │ Integration │  ← supertest + DB
                    ├─────────────┤
                    │   Unit      │  ← vitest
                    ├─────────────┤
                    │ Property-   │  ← fast-check
                    │   based     │
                    └─────────────┘
```

**Test Pyramid Gate 门禁** (`gate-check.sh` PHASE_1_5_TEST_PYRAMID):

```bash
# 1. 必须有 unit test runner 配置
# 2. 必须有 integration test 文件
# 3. 必须有 property-based test 至少 1 个
# 4. 现有测试覆盖率基线写入 .audit-cache/coverage-baseline.json

# 强制创建 (如果不存在):
mkdir -p tests/{unit,integration,contract,e2e,property}
echo "✓ test pyramid structure created"
```

`gate-check.sh --required-phase=PHASE_1_5_TEST_PYRAMID` 会检查:
- `package.json` 是否有 `test:unit`, `test:integration`, `test:property`, `test:e2e` scripts
- `tests/property/` 至少 1 个 *.test.ts
- `tests/integration/` 至少 1 个 *.test.ts

### Phase 1.1-1.4: 完整 SBL

不变, v3.4 仍适用。

---

## Phase 2: 7-Agent 并行审查

不变, v3.4 仍适用。但每个 agent 现在必须额外报告:
- 哪些 finding 需要 property-based test
- 哪些 finding 需要 chaos test

---

## Phase 3: 仲裁 (v3.5 加 test_coverage 要求)

### v3.4 → v3.5 升级

每个 finding 现在强制带 `test_required` 字段:

```yaml
- id: "FUNC-001"
  severity: "P0"
  file: "src/x.ts:123"
  test_required:
    type: "unit|integration|property|chaos|contract"
    rationale: "state machine boundary; need property-based test for questionIndex"
  cannot_fix_reason: null
```

Orchestrator 收到后写入 `state.test_coverage[fid] = {test_ids: [], mutation_killed: false, property_tested: false}`。

---

## Phase 4: 修复

不变, v3.4 仍适用。

---

## Phase 4.5: Test Author (v3.5 强制)

**问题**: v3.4 修复后没写 test，修复无"防止回归"机制。

**v3.5 强制**: 每个 finding 修复后必须 author 至少 1 个 test:

```bash
# 1. 列出所有 status=fixed 的 finding
python3 -c "
import json
s = json.load(open('.audit-cache/audit_state.json'))
todo = [(fid, f) for fid, f in s['findings'].items() if f.get('status') == 'fixed']
for fid, f in todo:
    print(f'{fid}: {f.get(\"file\")}:{f.get(\"line\")} - needs {f.get(\"test_required\", {}).get(\"type\", \"unit\")} test')
"

# 2. 必须 author test 才能进 Phase 5
# 每个 finding 写入 state.test_coverage[fid].test_ids
```

**Test 必须包含**:
1. **正向**: 触发原 bug 的最小复现 (RED)
2. **反向**: 验证修复确实生效 (GREEN)
3. **边界**: 至少 1 个相邻边界用例

**Test 模板** (`tools/test-template.ts`):
```typescript
// F-XXX test: 描述
// Given: 前置条件
// When: 操作
// Then: 期望结果

describe('FUNC-001: selectedIndex validation', () => {
  // RED: 原 bug 复现
  it('returns 400 when selectedIndex is NaN', () => { ... });
  // GREEN: 修复验证
  it('returns 200 when selectedIndex is valid number', () => { ... });
  // 边界
  it.each([0, -1, 999])('handles boundary index %i', (idx) => { ... });
});
```

`gate-check PHASE_4_5_TEST_AUTHOR`: 所有 `status=fixed` 的 finding 必须有 `test_coverage[fid].test_ids.length > 0`。

---

## Phase 5: 静态验证

不变, v3.4 仍适用。

---

## Phase 5.5: 运行时冒烟 (v3.5 扩展)

不变, 但增加：
- happy_path + error_path + boundary_path 三类都跑
- 写端点必须 POST 真实 payload (不是空 body)

---

## Phase 5.6: Dynamic Test (v3.5 新)

**新增**: 跑完整 test suite (不是只 smoke)

```bash
# 1. 跑 unit tests
npm run test:unit 2>&1 | tee .audit-cache/dynamic-unit.log
# 期望: 100% pass

# 2. 跑 integration tests
npm run test:integration 2>&1 | tee .audit-cache/dynamic-integration.log
# 期望: 100% pass, 覆盖率 > 80%

# 3. 跑 property-based tests
npm run test:property 2>&1 | tee .audit-cache/dynamic-property.log
# 期望: 100% pass, 至少 100 iterations per property

# 4. 跑 contract tests
npm run test:contract 2>&1 | tee .audit-cache/dynamic-contract.log
# 期望: 0 contract violations

# 5. 跑 e2e (如果存在)
npm run test:e2e 2>&1 | tee .audit-cache/dynamic-e2e.log || echo "e2e skipped"
```

写入 `dynamic-test-{round}.json`:
```json
{
  "round": 1,
  "unit": {"total": 50, "passed": 50, "failed": 0, "coverage_pct": 85.3},
  "integration": {"total": 12, "passed": 12, "failed": 0, "coverage_pct": 90.1},
  "property": {"total": 8, "passed": 8, "failed": 0, "iterations": 800},
  "contract": {"total": 5, "passed": 5, "violations": 0},
  "e2e": {"total": 3, "passed": 3, "skipped": 0}
}
```

`gate-check PHASE_5_6_DYNAMIC`:
- 任何 failed > 0 → exit 1
- 单元/集成覆盖率 < 80% → warning
- property iterations < 50 per property → warning

---

## Phase 5.7: Chaos Test (v3.5 新)

**新增**: 故障注入测试，验证恢复路径

```bash
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/chaos-test.sh \
  --target=grammar \
  --scenarios=kill_mid_request,restart_during_session,concurrent_feedback,ai_timeout,db_slow \
  .audit-cache/audit_state.json
```

工具执行 5 类故障场景:
1. **kill_mid_request**: 启动 1 个 long-running 请求, 杀进程, 验证无 orphan state
2. **restart_during_session**: 中途重启 server, 验证 session 状态恢复
3. **concurrent_feedback**: 100 并发 feedback 提交, 验证 DB 一致性 (FOR UPDATE 验证)
4. **ai_timeout**: 模拟 AI provider 30s 超时, 验证 fallback
5. **db_slow**: 模拟 DB 慢响应, 验证超时处理

每类场景期望:
- 不崩 (exit 0)
- 数据一致 (无 orphan records, 无 duplicate updates)
- 错误有恢复路径 (用户看到友好错误)

---

## Phase 5.8: Mutation Test (v3.5 新)

**问题**: 测试可能"假阳性"通过。改 bug 修复行，测试应该 fail。

```bash
# 完整版 (stryker) — 慢
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/mutation-test.sh \
  --state=.audit-cache/audit_state.json \
  --test-command="npm run test:unit" \
  --mutation-scope=findings

# 快速版 (sed-based, v3.6 新增) — 30秒内出结果，5 个常见 mutation 模式
# 【RETRO-TEST-011】v3.5 audit 验证：5/5 mutation survive 在 aiExamPoolService.ts
#   说明 string-matching test 几乎无 coverage
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/sed-mutation-test.sh \
  --auto --target=server/src/services/<module>.ts
```

工具执行:
1. 读取 state 中所有 `status=verified` 的 finding
2. 对每个 finding 的 `fix_evidence.file:line` 范围
3. **反向修改** (mutation):
   - 把 `===` 改成 `!==`
   - 把 `if` 改成 `if(!true)`
   - 把 `await` 删掉
   - 把 `+1` 改成 `-1`
4. 跑 test, **期望至少 1 个 fail**
5. 如果测试还 pass → **测试无效**, 回到 Phase 4.5 加强 test
6. 恢复原代码

**【v3.6 强制的 sed mutation 套件**】 — 5 个常见 mutation:
- `&&` → `||` (边界条件)
- `===` → `!==` (相等)
- 移除 `!` 取反 (状态守卫)
- `throw` → `console.error` (静默错误)
- `'failed'` → `'ready'` (状态机绕过)

如果 ≥1/5 survive → 该文件**测试覆盖不足** → Phase 4.5 加强

`gate-check PHASE_5_8_MUTATION`:
- 每个 verified finding 的 mutation_killed 必须 = true
- **【v3.6 新】** sed 套件必须 ≥4/5 killed (允许 1 survive)
- 不通过的 finding 必须重新 Phase 4.5 → Phase 4 → Phase 5.8

---

## Phase 6: LOOP (v3.5 强化)

不变 v3.4 + Phase 5.6/5.7/5.8 必跑。

---

## Phase 6.5: Devil's Advocate

不变 v3.4 强制 phase。

---

## Phase 7: 终验 (v3.5 加 test_coverage 报告)

### 7.1 报告必含

| 字段 | 来源 | 验证 |
|------|------|------|
| 总 finding | state.findings | verify-report.sh |
| 验证 | state.findings[verified] | verify-report.sh |
| cannot_fix | state.cannot_fix_queue | verify-report.sh |
| 0 open | state.findings[open] | zero-defect-check.sh |
| **test_ids 覆盖** | state.test_coverage[*].test_ids.length | **test-coverage-check.sh** |
| **mutation killed** | state.test_coverage[*].mutation_killed=true | **mutation-test.sh** |
| unit pass | dynamic-test.json | gate-check PHASE_5_6 |
| chaos pass | chaos-test.json | gate-check PHASE_5_7 |
| mutation pass | mutation-test.json | gate-check PHASE_5_8 |
| 报告与 state 一致 | - | verify-report.sh |

### 7.2 终验门禁 (v3.5 强化)

| 检查 | 来源 | 失败处理 |
|------|------|---------|
| 0 open finding | state | exit 1 |
| 0 fixing finding | state | exit 1 |
| all fixed 都 verified | state | exit 1 |
| cannot_fix 都有白名单 reason | state | exit 1 |
| **每个 verified 都有 test_ids** | test_coverage | **exit 1** |
| **每个 verified mutation_killed=true** | test_coverage | **exit 1** |
| dynamic test pass | dynamic-test.json | exit 1 |
| chaos test pass | chaos-test.json | exit 1 |
| mutation test pass | mutation-test.json | exit 1 |
| **【v3.6 新】P0 regression suite pass** | regression-index.json | **exit 1 (P0 复现！)** |

### 7.3 v3.6 新增: P0 Regression Suite (替代 canary injection)

**why**: canary bug 注入有自指悖论（无法保证 agent 一定找到）。**改用历史 P0 regression suite**: 历次 audit 找到的 P0 bug 都有专属 regression test，每次 audit 必跑。

```bash
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/regression-suite.sh
# 维护: 每次 fix P0 时:
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/regression-suite.sh add <test_file> "<finding desc>" <commit_hash>
```

如果 P0 regression fail → **不要报告 audit 成功** → 立即 fix。
| convergence-check.sh 上一轮 exit 0 | tools log | exit 1 |
| Phase 6.5 Devil's Advocate 跑过 | phases_passed | exit 1 |
| 报告与 state 一致 | verify-report.sh | exit 1 |

**任一失败 → Phase 7 输出 `❌ NOT READY`, 列出失败项**。

---

## 关键工具清单 (v3.5)

| 工具 | 作用 | 调用时机 |
|------|------|---------|
| `gate-check.sh` (v3.4) | phase 转下 phase 门禁 | 每个 phase 出口 |
| `verify-report.sh` (v3.4) | 报告与 state 反向验证 | Phase 5.2 + Phase 7.1 |
| `zero-defect-check.sh` (v3.4) | 0 open finding 检查 | Phase 6.2 + Phase 7.2 |
| `convergence-check.sh` (v3.3) | 结果驱动收敛判定 | 每轮 Phase 6.1 |
| **`test-coverage-check.sh` (v3.5 新)** | 验证 test_coverage 完整性 | Phase 4.5 + Phase 7.2 |
| **`chaos-test.sh` (v3.5 新)** | 故障注入测试 | Phase 5.7 |
| **`mutation-test.sh` (v3.5 新)** | 变异测试验证 test 有效性 | Phase 5.8 |
| **`dynamic-test-runner.sh` (v3.5 新)** | 跑完整 test suite | Phase 5.6 |

---

## 附录 A: audit_state.json Schema (v3.5)

```json
{
  "run_id": "string",
  "scope": "string",
  "mode": "emergency|quick|incremental|deep|continuous",
  "started_at": "ISO8601",
  "current_round": "int",
  "current_phase": "PHASE_X_NAME",
  "findings": {
    "FUNC-001": {
      "id": "FUNC-001",
      "severity": "P0|P1|P2|P3",
      "category": "...",
      "file": "src/x.ts",
      "line": 123,
      "description": "...",
      "fix_code": "...",
      "discovered_round": 1,
      "status": "open|fixing|fixed|verified|cannot_fix|deferred",
      "fix_evidence": {...},
      "test_required": {
        "type": "unit|integration|property|chaos|contract",
        "rationale": "..."
      }
    }
  },
  "test_coverage": {
    "FUNC-001": {
      "test_ids": ["tests/unit/feedback.test.ts:15", "tests/integration/api.test.ts:42"],
      "mutation_killed": true,
      "property_tested": false,
      "test_files": ["tests/unit/feedback.test.ts"]
    }
  },
  "phases_passed": {...},
  "gates_passed": {...},
  "cannot_fix_queue": [...],
  "deferred_queue": [...]
}
```

---

## 附录 B: Test Pyramid 6 层定义

| 层 | 工具 | 数量 | 速度 | 测什么 |
|----|------|------|------|--------|
| **Unit** | vitest | 多 (100+) | ms | 纯函数、组件 props |
| **Integration** | supertest + real DB | 中 (10-30) | s | API endpoint + DB 真实交互 |
| **Contract** | openapi-validator | 中 (5-20) | s | request/response shape 与 OpenAPI 一致 |
| **E2E/UI** | playwright | 少 (3-10) | s-min | 真实浏览器, 完整用户流程 |
| **Property-Based** | fast-check | 少 (5-20) | s | 状态机边界、输入域全覆盖 |
| **Chaos** | 自定义 | 少 (3-10) | s | 故障恢复路径 |

---

## 附录 C: 关键变更日志

### v3.5.0 (2026-06-17) — Zero-Trust Edition

**问题**: v3.4 报"零缺陷"但运行时一堆 bug。**静态零缺陷 ≠ 运行时零缺陷**。

**修复**:
1. **Test Pyramid 强制建立** (Phase 1.5) — 4 层缺一不可
2. **Test Author 强制** (Phase 4.5) — 每个 finding 必须 author test
3. **Dynamic Test Suite** (Phase 5.6) — 不只 smoke, 跑完整 test suite
4. **Chaos Test** (Phase 5.7) — 故障注入 + 恢复路径验证
5. **Mutation Test** (Phase 5.8) — 改 1 行看 test 是否捕获
6. **test_coverage 字段** 加入 audit_state.json
7. **零信任门禁**: 每个 verified finding 必须 mutation_killed=true

### v3.4.0 (2026-06-17)
- audit_state.json 状态机
- gate-check.sh, verify-report.sh, zero-defect-check.sh
- Phase 6.5 强制 Devil's Advocate

### v3.3.0 (2026-06-17)
- convergence-check.sh
- Phase 1.0 / 5.5 强制

### v2.x (audit-fix-verify, deprecated)
原始 7-phase 设计。

---

## ⚠️ 关键警告 (LLM Agent 必读)

1. **禁止口头"零缺陷"** — 必须 test_coverage[*].test_ids 非空 + mutation_killed=true
2. **禁止跳过 Phase 4.5/5.6/5.7/5.8** — test author / dynamic / chaos / mutation 必跑
3. **禁止"测试已存在"自评** — 必须跑 mutation-test.sh 验证
4. **禁止跳过 P2/P3** — 必须 fix 或显式 defer (P3 only, 用户确认)
5. **禁止"记录到 backlog"** — 任何此类语言 = P0 报告 (自身违规)
6. **禁止"smoke 通过 = 零缺陷"** — smoke 是 6 层之一, 不是全部
7. **必须建立 Test Pyramid** — 缺一层 → gate-check 拒绝进 Phase 7

---

# v4 Addendum: Layered Adversarial Audit (2026-06-17)

**适用场景**: 当 v3.7 仍然发现浅层 finding, 或需要解决"为什么漏"问题时，使用 v4 模式。

## v4 vs v3.7 — 4 大根因解决方案

| 根因 | v3.7 行为 | v4 解决方案 |
|------|----------|------------|
| **Bandwagon (6/6 共识)** | 7 agent 共享 pre-query.json, 输出 7 份相似 finding | 5 agent 各自不同 lens + subsystem + entry file |
| **File-local scope (6/6 共识)** | 工具按文件切, root cause 按数据流跨文件 | subsystem-manifest + flow-trace (32 cross-subsystem flows) |
| **Self-referential (4/6 共识)** | agent 写 test → 跑 test → 审 test (自我验证) | Red Team 用 M3 (vs 蓝队 M2.7) + 4-step attack protocol |
| **Single-loop (3/6 共识)** | 重复 audit, 从不学"为什么漏" | AAR 4 questions + blind-spot-registry + method updates |

## v4 工具 (7 个新工具 + 1 orchestrator)

| 工具 | 类型 | 解决哪个根因 | 关键输出 |
|------|------|-------------|---------|
| `subsystem-manifest.sh` | shell | File-local | `.audit-cache/subsystem-manifest.json` (13 subsystems, multi-homing) |
| `flow-trace.ts` | ts | File-local | `.audit-cache/flow-trace.json` (32 cross-subsystem flows, handles path alias) |
| `generate-blind-briefings.ts` | ts | Bandwagon | `.audit-cache/briefings/blue_1..5.json` (5 distinct lens × subsystem) |
| `red-team-attack.ts` | ts | Self-referential | `.audit-cache/red-team-attacks/*_briefing.json` (4-step attack protocol) |
| `red-team-verify.ts` | ts | Self-referential | `.audit-cache/red-team-summary.json` (verdicts aggregated) |
| `after-action-review.ts` | ts | Single-loop | `.audit-cache/aar.json` + `aar-history/` + `blind-spot-registry.json` |
| `gold-set.ts` | ts | (validation) | `.audit-cache/gold-set.json` (24 known bugs from audit history) |
| `v4-audit.sh` | shell | orchestrator | All tools in order with v3.7 regression gate |

## v4 Workflow (5 steps)

```bash
# 1. Generate manifest + flow trace (auto, no LLM)
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/subsystem-manifest.sh generate
npx tsx ~/.config/opencode/skills/audit-fix-loop-v3/tools/flow-trace.ts
npx tsx ~/.config/opencode/skills/audit-fix-loop-v3/tools/generate-blind-briefings.ts

# 2. Run 5 Blue Team agents (each reads ONLY its briefing)
#    - blue_1: concurrency lens, server_infra subsystem
#    - blue_2: data_flow lens, shared subsystem
#    - blue_3: error_handling lens, ai_exam subsystem
#    - blue_4: resource_lifecycle lens, tts subsystem
#    - blue_5: security lens, user subsystem
# Each agent outputs to .audit-cache/findings/blue_<N>.json

# 3. Run Red Team (M3, blind to blue team reasoning)
#    Use cross-run-dedup first to skip known issues
npx tsx ~/.config/opencode/skills/audit-fix-loop-v3/tools/red-team-attack.ts protocol
# Then for each finding, run M3 with 4-step attack
# Save to .audit-cache/red-team-attacks/<id>_result.json
npx tsx ~/.config/opencode/skills/audit-fix-loop-v3/tools/red-team-verify.ts

# 4. AAR (4 mandatory questions, by human or LLM)
npx tsx ~/.config/opencode/skills/audit-fix-loop-v3/tools/after-action-review.ts template
# Fill in the 4 questions, rename to aar.json
npx tsx ~/.config/opencode/skills/audit-fix-loop-v3/tools/after-action-review.ts commit

# 5. v3.7 regression (must still pass)
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/regression-suite.sh
```

Or run all in one:
```bash
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/v4-audit.sh
```

## v4 Success Criteria (from design doc)

| Metric | v3.7 | v4 target | How to measure |
|--------|------|-----------|----------------|
| Cross-subsystem findings / total | < 5% | > 30% | Count findings tagged with `flow_id` |
| Findings rediscovered across runs | ~40% | < 10% | `cross-run-dedup.sh filter` |
| P0/P1 detection rate | ~60% | > 90% | Gold set test (24 known bugs) |
| Mutation test kill rate | ~60% | > 85% | `sed-mutation-test.sh` on all files |
| Time to convergence | ~4 rounds | ≤ 3 rounds | `convergence-check.sh` logs |
| Blind spot coverage | N/A | > 80% after 5 runs | `blind-spot-registry.sh` metric |

## Gold Set (24 known bugs)

The gold set is built from past audit history:
- v3.5 73 AI findings + 53 grammar findings + 21 grammar findings
- v3.6 retro SRE-006
- v3.5 DEVIL-019, DEVIL-022
- SEC-002, 005, 006, 007, 008 (commits 69aa1b9, b790963)
- A11Y-001, AUTH-001, FEED-001, TTS-001, TTS-002

Distribution: 4 P0, 16 P1, 4 P2; 13 cross-subsystem (54%); covers 7 categories and 6 lenses.

## When to use v4 vs v3.7

| 情况 | 用 |
|------|---|
| 第一次 audit 这个项目 | v3.7 (建立 baseline) |
| Audit 反复发现浅层 finding | **v4** (这是设计目标场景) |
| 单文件 / 小改动 | v3.7 (incremental mode) |
| 紧急 P0 阻断 | v3.7 (emergency mode) |
| 月度 / 季度深度审计 | **v4** |
| v3.7 跑出 zero-defect 但用户怀疑 | **v4** (红队会找出) |

## v4 当前状态 (2026-06-17)

- ✅ 7 工具 + 1 orchestrator 已实现
- ✅ 9/9 v4 integration test 通过
- ✅ 380/380 全部 test 通过 (含 9 v3.7 regression tests)
- ✅ 24 gold bugs 已 curated (足够 v4 验证)
- ⏳ 蓝队 + 红队 agent prompt 模板待 v4 实战验证
- ⏳ 第一次 v4 全 cycle 跑通待执行

## 设计文档

完整设计 (984 行) 在 `docs/plans/audit-fix-loop-v4-design-2026-06-17.md`，含:
- 8 个 section (架构 + 4 根因 + roadmap + 风险 + 成功标准)
- Mermaid 架构图
- 6 步 14 天实施 roadmap (实际压缩到 1 session)
- 4 成功标准量化
- 7 个 explicit tradeoffs

