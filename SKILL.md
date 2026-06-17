---
name: audit-fix-loop-v3
version: 3.3.0
description: 系统性零缺陷审查与修复。结果驱动收敛、运行时冒烟、预查询清单、3层根因追问、缓存自动清理。所有 P0~P3 必修。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Task, WebFetch, skill]
supersedes: [audit-fix-verify]
---

# Audit → Fix → Loop v3.3

**核心区别**: P0-P3 全部必修 | 结果驱动收敛 | Phase 5.5 DB-aware 运行时冒烟 | Phase 1.0 预查询 | 3层根因

---

## Phase 0: 入口 + 上下文 + 缓存清理

### 模式

| 模式 | 场景 | 耗时 |
|------|------|------|
| quick | ≤3文件小改 | 15-30m |
| deep | 跨模块/安全 | 1-4h |
| continuous | 全量零缺陷 | 2-8h |
| incremental | 有基线,改1-3文件 | 15-30m |
| emergency | P0阻断 | 立即修,24h补continuous |

### quick-start
说"帮我看代码"→默认quick模式(15-30m)。回复"全面"升级continuous。

### 增量模式
`git diff`→确定变更集→派Functional+Security 2agent→SBL缓存加载（校验git_commit, 变更∩SBL关联≠∅→升级deep）→连续3次后强制deep。

### 自动清理（每次Phase 0执行）
.audit-cache/ >100MB→警告 | 保留最近3轮 | webfetch-trace >5000行→归档 | sbl-v3.json不删

---

## Phase 1: SBL v3（唯一真源）

### Phase 1.0: 预查询（不可跳过）
```
① webfetch AI provider docs → 超时/速率限制（如MiniMax API典型响应时间）
② webfetch DB docs → 事务隔离级别 + statement_timeout
③ 读 package.json → dev server端口和启动命令
④ 输出: .audit-cache/pre-query-{round}.json
```

### Phase 1.1: 功能流程 SBL-functional
画出用户→前端→后端→DB完整数据路径。

### Phase 1.2: 行业最佳实践 SBL-practice
| 域 | 必查源 | 关键Checklist |
|----|--------|--------------|
| 安全 | OWASP API Top 10 | API1-BOLA/API2-认证/API3-批量分配/API4-资源/API5-功能权限/API6-敏感操作/API7-SSRF/API8-配置/API9-资产/API10-第三方消毒 |
| a11y | WCAG 2.1 AA | aria-label/focus trap/对比度4.5:1/键盘导航/role语义 |
| DB | PostgreSQL docs | UUID gen_random/FK ON DELETE明确/复合索引覆盖WHERE+JOIN/JSONB字段白名单/多表写入事务包裹 |
| React | react.dev | cleanup完整/mountedRef/ErrorBoundary/Suspense |
| Express | expressjs.com | asyncHandler/全局error/CORS/secure headers |
| 可观测 | OpenTelemetry | 埋点/traceId/结构化日志/错误上报 |

### Phase 1.3: 契约矩阵 SBL-contract
grep后端路由提取端点→grep前端fetch提取消费者→比对字段→输出契约矩阵。

### Phase 1.4: 用户旅程 SBL-journey
happy_path + error_path。

---

## Phase 2: 7-Agent 并行审查

| # | Agent | 依据 | 关注点 |
|---|-------|------|--------|
| 1 | Functional | SBL-functional | 功能正确性/状态机/边界 |
| 2 | Data | SBL-func+DB | 事务/FK/索引/并发 |
| 3 | Security | OWASP | API1-10逐条 |
| 4 | Performance | SBL-practice | 索引/N+1/memo/泄漏 |
| 5 | Observability | OTel | 埋点/日志/traceId |
| 6 | A11y | WCAG | 键盘/aria/对比度 |
| 7 | UX | SBL-journey | 空/加载/错误状态 |

### 输出约束（每个agent必须）
```yaml
- id(全局唯一)+file:line+severity(P0-P3)+category+fix_code(≤20行)
- [source:URL]+[excerpt:"引文"] 标签（安全/数据决策）
- 输出末尾附TOOL_ACTIVITY日志
- severity缺失或非P0-P3→视为invalid
- fix_verified:true标记已修复的prior轮次finding
- cannot_fix_reason仅限: external_dependency/data_migration/out_of_scope/missing_infrastructure/design_tradeoff
```

---

## Phase 3: 仲裁

去重: 所有agent一致/2+确认→计入 | 仅1agent→计入 | 矛盾→取最高severity
修复: P0-P3全部必修。每个P0/P1必须附**3层根因**:
1. 代码错在哪 2. 为什么审查没发现(流程缺陷) 3. 同类错误是否在其他位置重复(系统缺陷)

---

## Phase 4: 修复

### 防竞态
agent输出是"建议"(不直接写磁盘)。Orchestrator按文件分组，同文件≥2修复→单agent合并→统一apply。

### 修复后立即
tsc --noEmit + lint + build

---

## Phase 5: 静态验证
tsc --noEmit + lint + build + 契约检查。

### Phase 5.5: 运行时冒烟（v3.3 + v3.4 DB-Aware）

```
① DB schema 同步（如适用）
② npm run dev 启动服务(后台)
③ curl POST核心API→验证可用(≤5s)
④ curl POST写端点(匿名/最小 payload)→验证不 500
⑤ 检查console.error→AbortError/超时/relation.*does not exist→P1+
⑥ 记录响应时间到.audit-cache/smoke-test-{round}.json
⑦ 清理dev进程
```

---

## Phase 6: LOOP（结果驱动收敛）

### 收敛条件（同时满足）
① 最近一轮发现数 ≤ 首轮的10% | ② 无P0/P1新发现 | ③ Meta-Review通过

### 魔鬼代言人
每轮收敛前追问: "你是恶意攻击者。找:①数据泄露 ②权限绕过 ③系统崩溃 ④代码注入"。

### 超限诊断（≥8轮）
输出超限诊断报告到 .audit-cache/escalation-{round}.json。

禁止: LLM自评"已完成"/"记录到backlog"/跳过Phase 6/仅1agent快速检查

---

## Phase 7: 终验（双层报告）

### Executive Layer
```markdown
## 🎯 一句话结论: ✅/⚠️/❌ [发布建议] — [理由]
## 📊 风险: 安全🟢 体验🟢 性能🟢 可维护🟢 | 整体🟢
## 📋 缺陷速览: # | 对用户影响(人话) | 严重度(🔴严重/🟡中等/🟢轻微) | 状态
```

---

## 参考
- 实战: English-CET写作训练58项缺陷+114项历史修复
- 相关: review/fix/qa/investigate
- 废除: audit-fix-verify
