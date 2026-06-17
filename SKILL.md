---
name: super-fix
version: 5.0.0
description: 系统性零信任审查与修复。6 层防御 (L1-L6)，5 独立 lens 审查 + 跨模型 Red Team + AAR 学习。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Task, WebFetch, skill]
supersedes: [audit-fix-verify, audit-fix-loop-v3, audit-fix-loop-v4]
---

# Super-Fix — Zero-Trust Audit & Fix Loop

6-layer defense: L1 constrained decoding → L2 schema validation/retry →
L3 tool standardization → depth gate → L5 cross-model Red Team →
L6 circuit breaker. 5 independent lenses → Red Team (M3) → AAR learning.

## Quick Start

```bash
bash tools/init-audit.sh --mode=deep
bash tools/v4-audit.sh
```

## Pipeline

| Phase | Action | Gate |
|-------|--------|------|
| 0 Entry | `init-audit.sh`, baseline load, concurrency lock | `PHASE_0_ENTRY` |
| 1.0 Pre-query | Domain context → `pre-query.json` | — |
| 1.1–1.4 SBL | Single source of truth | `PHASE_1_SBL` |
| 1.5 Test Pyramid | Verify ≥4 test layers | `PHASE_1_5_TEST_PYRAMID` |
| 2 Review | Spawn general agents: security, concurrency, dataflow, error, resource | `PHASE_2_REVIEW` |
| 3 Arbitration | `arbitrate-findings.sh` merge + dedup | `PHASE_3_ARBITRATION` |
| 4 Fix | `apply-fix.ts`: read → fix → verify → update state | `PHASE_4_FIX` |
| 4.5 Test Author | RED+GREEN+boundary | `PHASE_4_5_TEST_AUTHOR` |
| 5 Static | `tsc --noEmit` / lint | `PHASE_5_STATIC` |
| 5.5 Smoke | Happy+error+boundary | `PHASE_5_5_SMOKE` |
| 5.6 Dynamic | Full test suite | `PHASE_5_6_DYNAMIC` |
| 5.7 Chaos | Fault injection | `PHASE_5_7_CHAOS` |
| 5.8 Mutation | `sed-mutation-test.sh` ≥4/5 kill | `PHASE_5_8_MUTATION` |
| 6 Loop | `convergence-check.sh`, max 8 rounds | `PHASE_6_LOOP` |
| 6.5 Devil's Advocate | Independent adversarial challenge | `PHASE_6_5_DEVIL_ADVOCATE` |
| 7 Final | Zero-defect cert + P0 regression | `PHASE_7_FINAL` |

### Phase 2: Blue Team (5 independent lenses)

`generate-blind-briefings.ts` produces 5 lens-specific briefings. The orchestrator spawns 5 **general** agents (Task subagent_type=general), each with a lens-specific prompt. No shared briefing = no Bandwagon.

Lenses: security, concurrency, dataflow, error, resource. Each agent scans its assigned files for lens-specific signals. Output to `.audit-cache/findings/audit-blue-{lens}.json`.

### Phase 4: Red Team (M3 cross-model)

```bash
npx tsx tools/red-team-runner.ts    # L1 json_object, L2 3x retry, L6 fallback
npx tsx tools/red-team-verify.ts    # aggregate verdicts
```

## Phase Failure Protocol

- **gate-check exit 1**: retry once. Still failing → log, ask user. Do NOT advance.
- **gate-check exit 2**: re-init state (`init-audit.sh --force`).
- **Circuit breaker**: 3 phase failures → abort.

## Key Rules

1. **No verbal "zero defect"** — every finding must have `test_ids` + `mutation_killed=true`
2. **All phases + gates mandatory** — no skips; smoke ≠ full pyramid; P0 regression must pass
3. **"Test already exists" is not self-validating** — `sed-mutation-test.sh` ≥4/5 kill
4. **P2 must fix; P3 deferral requires explicit user OK** (recorded in `cannot_fix_queue`)

## Gate Reference

| Gate | Enforces |
|------|----------|
| `PHASE_0_ENTRY` | State exists, mode set |
| `PHASE_1_SBL` | Pre-query + SBL files |
| `PHASE_1_5_TEST_PYRAMID` | ≥4 test layers |
| `PHASE_2_REVIEW` | ≥3 non-empty findings |
| `PHASE_3_ARBITRATION` | Merged + deduped |
| `PHASE_4_FIX` | All P0/P1/P2 patched |
| `PHASE_4_5_TEST_AUTHOR` | Fixed findings have test_ids |
| `PHASE_5_STATIC` | tsc passes |
| `PHASE_5_5_SMOKE` | Smoke endpoints 200 |
| `PHASE_5_6_DYNAMIC` | Dynamic suite passes |
| `PHASE_5_7_CHAOS` | Chaos scenarios pass |
| `PHASE_5_8_MUTATION` | ≥4/5 kill |
| `PHASE_6_LOOP` | Convergence |
| `PHASE_6_5_DEVIL_ADVOCATE` | Independent attack |
| `PHASE_7_FINAL` | 0 open, P0 regression pass |

## Cross-Run Baselines (`.audit-cache/`)

| File | Tool | Purpose |
|------|------|---------|
| `baseline-zero.json` | `baseline-diff.sh` | Zero-defect files (skip) |
| `baseline.json` | `cross-run-dedup.sh` | Known finding hashes (dedup) |
| `regression-index.json` | `regression-suite.sh` | P0 fix tests |

## Finding Format

```bash
hash=$(bash tools/finding-hash.sh --module=path --function=fn --pattern=canonical_id)
```
Schema: `schemas/finding.schema.json`. Cross-run dedup uses this hash.

## Tool Index

| Layer | Tools |
|-------|-------|
| Subsystem | `subsystem-manifest.sh`, `flow-trace.ts` |
| Audit | `generate-blind-briefings.ts`, `red-team-runner.ts`, `red-team-verify.ts`, `arbitrate-findings.sh`, `apply-fix.ts` |
| Stability | `validate-retry.ts`, `validate-causal-chain.sh` |
| Orchestration | `v4-audit.sh`, `init-audit.sh`, `gate-check.sh` |
| Cross-run | `finding-hash.sh`, `cross-run-dedup.sh`, `baseline-diff.sh`, `regression-suite.sh` |
| Schemas | `schemas/finding.schema.json`, `schemas/attack-result.schema.json` |

Full docs: `tools/README.md`, `docs/v4-addendum.md`, `CHANGELOG.md`.
