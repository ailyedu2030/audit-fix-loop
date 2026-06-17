---
name: audit-fix-loop-v3
version: 3.4.0
description: 系统性零缺陷审查与修复。结果驱动收敛、运行时冒烟、预查询清单、3层根因、缓存清理、**机械门禁+状态机+报告反向验证**。所有 P0-P3 必修，P2/P3 强制入状态机追踪，禁止口头"已完成"。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Task, WebFetch, skill]
supersedes: [audit-fix-verify]
---

# Audit → Fix → Loop v3.4

**v3.4 核心区别 (vs v3.3)**:
- **机械门禁取代自觉** — 每 phase 出口必须跑 `gate-check.sh` 拿到 PASS
- **状态机持久化** — `audit_state.json` 跟踪每个 finding 生命周期
- **报告反向验证** — Phase 7 报告声明必须与 `audit_state.json` 工件一致
- **P2/P3 强制入队** — 不能口头"延后"，必须 explicit `defer` 决策
- **Devil's Advocate 独立 phase** — 不再是"建议"而是强制 phase

---

## Phase 0: 入口 + 状态机初始化

强制创建 `.audit-cache/audit_state.json` 含 `findings`, `phases_passed`, `gates_passed`, `cannot_fix_queue`, `deferred_queue` 五个核心字段。无 audit_state.json 不能进 Phase 1。

模式选择: emergency/quick/incremental/deep/continuous。

## Phase 1: SBL v3

不变: Phase 1.0 预查询 + Phase 1.1-1.4 完整 SBL。

## Phase 2: 7-Agent 并行审查

不变, 但每个 finding 必须写到 audit_state.json (不只是输出文件)。fix_verified 必须有 file:line + diff 摘录。

## Phase 3: 仲裁 + 三态生命周期

```
open → fixing → fixed → verified
                  ↘ cannot_fix (需 5 大理由之一)
                  ↘ deferred (P3 only, 需用户确认)
```

3 层根因 (P0/P1 强制): 代码错在哪 / 审查为何漏 / 同类在别处有吗。

cannot_fix_reason 严格白名单 (5 项): external_dependency / data_migration / out_of_scope / missing_infrastructure / design_tradeoff。

## Phase 4: 修复

修复后立即更新 audit_state.json: status='fixed' (不是 'verified') + fix_evidence。

## Phase 5: 静态验证

`tsc --noEmit` + lint + build。

## Phase 5.5: 运行时冒烟 (DB-Aware)

v3.3 不变 + DB schema 同步验证。

## Phase 6: LOOP (重大重写)

每轮结束必须跑 convergence-check.sh + audit_state.json 一致性。

零缺陷标准: 0 open + 0 fixing + all fixed verified + cannot_fix 都有合法 reason。

Phase 6.5 Devil's Advocate 强制独立 phase (派发找数据泄露/权限绕过/崩溃/注入的 agent)。

## Phase 7: 终验

必跑 verify-report.sh 反向验证 (报告 vs state 一致性)。

## 关键工具 (v3.4)

| 工具 | 作用 | 调用时机 |
|------|------|---------|
| gate-check.sh (v3.4 新) | phase 转下 phase 门禁 | 每个 phase 出口 |
| verify-report.sh (v3.4 新) | 报告与 state 反向验证 | Phase 5.2 + Phase 7.1 |
| zero-defect-check.sh (v3.4 新) | 0 open finding 检查 | Phase 6.2 + Phase 7.2 |
| convergence-check.sh (v3.3) | 结果驱动收敛判定 | 每轮 Phase 6.1 |

## v3.4 → v3.3 关键教训

2026-06-17 grammar 模块审计中 agent 报"全部修复"但实际跳过 P2/P3。
v3.4 用机械门禁杜绝此类行为。
