---
name: super-fix
version: 4.0.0
description: 系统性零信任审查与修复。v4 解决 4 大根因 (Bandwagon/File-local/Self-referential/Single-loop)。3 层系统 (Subsystem/Adversarial/Learning)：5 独立 lens Blue Team + 跨模型 M3 Red Team + AAR 双环学习。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Task, WebFetch, skill]
supersedes: [audit-fix-verify, audit-fix-loop-v3.3, audit-fix-loop-v3.4, audit-fix-loop-v3.5, audit-fix-loop-v3.6, audit-fix-loop-v3.7, audit-fix-loop-v3]
---

# Audit → Fix → Loop v4

Layered adversarial audit for AI coding agents. Three independent layers: Subsystem (manifest + flow trace), Adversarial Discovery (5 independent-lens Blue + cross-model M3 Red), Learning (AAR + blind spot registry).

**v3.7 lesson**: "clear-domain tool on complex-domain problem" — 15 phases skipped because the agent couldn't faithfully execute them. v4 = pipeline → system, with independent layers that genuinely run.

## Quick Start

```bash
bash tools/init-audit.sh --mode=deep      # Phase 0
bash tools/v4-audit.sh                     # Full v4 pipeline
bash tools/v4-audit.sh --v3.7 --deep       # Legacy v3.7
```

## Pipeline

| Phase | Action | Gate |
|-------|--------|------|
| 0 Entry | `init-audit.sh`, baseline load | `PHASE_0_ENTRY` |
| 1.0 Pre-query | Domain context → `pre-query.json` | — |
| 1.1–1.4 SBL | Single source of truth (`sbl-functional-template.md`) | `PHASE_1_SBL` |
| 1.5 Test Pyramid | Verify ≥4 test layers exist | — (check by tool) |
| 2 Review | 5-Blue-agent parallel (`run-blue-agent.ts` spawns audit sub-agents) | `PHASE_2_REVIEW` |
| 3 Arbitration | Merge 5 agent outputs (`arbitrate-findings.sh`), assign test_required | `PHASE_3_ARBITRATION` |
| 4 Fix | For each finding: `apply-fix.ts <findings.json> <id>` → read source → verify bug → fix → update state | `PHASE_4_FIX` |
| 4.5 Test Author | RED+GREEN+boundary (see `docs/templates/test-template.ts`) | — (check by `test-coverage-check.sh`) |
| 5 Static | `tsc --noEmit` / lint | `PHASE_5_STATIC` |
| 5.5 Smoke | Happy+error+boundary paths | `PHASE_5_5_SMOKE` |
| 5.6 Dynamic | Full test suite (`dynamic-test-runner.sh`) | — (check by tool) |
| 5.7 Chaos | Fault injection (`chaos-test.sh`) | — (check by tool) |
| 5.8 Mutation | Test effectiveness (`sed-mutation-test.sh`, ≥4/5 kill) | — (check by tool) |
| 6 Loop | Convergence (`convergence-check.sh`), max 8 rounds | `PHASE_6_LOOP` |
| 6.5 Devil's Advocate | Independent adversarial challenge | `PHASE_6_5_DEVIL_ADVOCATE` |
| 7 Final | Zero-defect cert (`verify-report.sh` + `regression-suite.sh`) | `PHASE_7_FINAL` |

### v4.3 Agent-Driven Execution (replaces manual Phase 2/4)

| Step | Tool | Agent |
|------|------|-------|
| Subsystem + Flow | `subsystem-manifest.sh` → `flow-trace.ts` | — |
| Blind Briefings | `generate-blind-briefings.ts` (5 lenses, round-robin) | — |
| Blue Team | `run-blue-agent.ts <agent> <briefing>` (5 agents parallel) | `audit-blue-security`, `audit-blue-concurrency`, `audit-blue-dataflow`, `audit-blue-error`, `audit-blue-resource` |
| Red Team | `red-team-runner.ts` (M3, parallel) | `audit-red-team` |
| AAR | `after-action-review.ts` | `audit-aar` |
| v3.7 Regression | `regression-suite.sh` (must pass) | — |

Each agent operates INDEPENDENTLY with its own `.md` prompt and briefing JSON.
No shared pre-query — no Bandwagon. Signals per lens in `agents/audit-blue-*.md`.

## Key Rules

1. **No verbal "zero defect"** — every finding must have `test_ids` + `mutation_killed=true`
2. **All phases + gates mandatory** — no skips; smoke ≠ full pyramid (1/6 layers); P0 regression must pass
3. **"Test already exists" is not self-validating** — `sed-mutation-test.sh` must confirm ≥4/5 kill rate
4. **P2 must fix; P3 deferral requires explicit user OK** (recorded in `cannot_fix_queue`)

## Gate Reference

| Gate | Enforces |
|------|----------|
| `PHASE_0_ENTRY` | `audit_state.json` exists, mode set |
| `PHASE_1_SBL` | Pre-query + SBL files present |
| `PHASE_2_REVIEW` | 7-agent (or v4 blue team) findings produced |
| `PHASE_3_ARBITRATION` | Findings merged, test_required assigned |
| `PHASE_4_FIX` | All P0/P1/P2 patches applied |
| `PHASE_5_STATIC` | `tsc --noEmit` passes, no build errors |
| `PHASE_5_5_SMOKE` | Smoke endpoints return 200 |
| `PHASE_6_LOOP` | Convergence check (<1 new finding or round cap) |
| `PHASE_6_5_DEVIL_ADVOCATE` | Independent adversarial attack on each finding |
| `PHASE_7_FINAL` | 0 open, 0 fixing, all verified, P0 regression pass |
| (tool gates) | `test-coverage-check.sh`, `dynamic-test-runner.sh`, `chaos-test.sh`, `sed-mutation-test.sh` enforce their own phase-specific gates |

## Phase Failure Protocol

- **gate-check.sh exit 1 (fail)**: retry the phase once. If still failing, log to `.audit-cache/phase-errors.json`, ask user for guidance. Do NOT advance to next phase.
- **gate-check.sh exit 2 (error)**: check `.audit-cache/audit_state.json` exists and is valid JSON. Re-run `init-audit.sh --force` if corrupted.
- **Circuit breaker**: after 3 phase failures total, abort the audit. Reason logged to `.audit-cache/escalation.json`.
- **Tool timeout**: each phase has 5min max. On timeout, phase is marked incomplete, audit pauses.

## Phase 4: Apply Patches — Explicit Instructions

For each finding with `status='open'` and `file+line`:
1. READ the target file at `.module` path
2. VERIFY the bug reproduces (understand the code path)
3. FIX using Edit tool — apply the patch from `.fix_recommendation`
4. UPDATE `audit_state.json`: set `finding.status='fixed'`, add `fix_evidence={file, lines_changed, before_hash, after_hash}`
5. PROCEED to Phase 4.5 for test authoring

## Cross-Run Baselines (`.audit-cache/`)

| File | Tool | Purpose |
|------|------|---------|
| `baseline-zero.json` | `baseline-diff.sh` | Zero-defect files (skip in incremental) |
| `baseline.json` | `cross-run-dedup.sh` | Known finding hashes (cross-run dedup) |
| `regression-index.json` | `regression-suite.sh` | Historical P0 fix test index |

## Finding Format

Findings use **canonical pattern IDs** (stable semantic hash):
```bash
hash=$(bash tools/finding-hash.sh --module=path/to/file.ts --function=funcName --pattern=canonical_id)
```
Cross-run dedup uses this hash. See `docs/v4-addendum.md` for full schema.

## Tool Index

See `tools/README.md` for full documentation. Key tools by layer:

| Layer | Tools |
|-------|-------|
| Subsystem | `subsystem-manifest.sh`, `flow-trace.ts` |
| Adversarial | `generate-blind-briefings.ts`, `red-team-attack.ts`, `red-team-runner.ts`, `red-team-verify.ts`, `run-blue-agent.ts`, `arbitrate-findings.sh`, `apply-fix.ts` |
| Agents (v4.3) | `agents/audit-blue-security.md`, `agents/audit-blue-concurrency.md`, `agents/audit-blue-dataflow.md`, `agents/audit-blue-error.md`, `agents/audit-blue-resource.md`, `agents/audit-red-team.md`, `agents/audit-aar.md` |
| Learning | `after-action-review.ts`, `gold-set.ts`, `v4-detect-rate.ts` |
| Stability (v4.2) | `validate-retry.ts`, `validate-causal-chain.sh` |
| Orchestration | `v4-audit.sh`, `init-audit.sh`, `gate-check.sh`, `advance-phase.ts` |
| Cross-run | `finding-hash.sh`, `cross-run-dedup.sh`, `baseline-diff.sh`, `regression-suite.sh` |
| Schemas | `schemas/finding.schema.json`, `schemas/attack-result.schema.json` |

## Reference

- `docs/v4-addendum.md` — v4 detailed workflow, success criteria, gold set, schema
- `docs/templates/test-template.ts` — Phase 4.5 test authoring template
- `CHANGELOG.md` — all version history (v3.3→v4.0.0)
- `tools/README.md` — tool documentation (24 tools, all phases)
