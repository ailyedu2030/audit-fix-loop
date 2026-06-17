---
name: super-fix
version: 5.3.0
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
bash tools/init-audit.sh --mode=deep      # Phase 0: init state
bash tools/v4-audit.sh                     # Steps 0-7: full automated pipeline
```

## Automated Pipeline (v4-audit.sh)

| Step | Action | Tool |
|------|--------|------|
| 0 | Subsystem manifest + concurrency lock | `subsystem-manifest.sh` |
| 1 | Cross-subsystem flow trace | `flow-trace.ts` |
| 2 | Generate 5 lens briefings | `generate-blind-briefings.ts` |
| 3 | Blue Team (orchestrator spawns 5 general agents) | Task `general` ×5 |
| 4 | Red Team (M3 cross-model verification) | `red-team-runner.ts` → `red-team-verify.ts` |
| 5 | After-Action Review (4 questions) | `after-action-review.ts` |
| 6 | Cross-run dedup | `cross-run-dedup.sh` |
| 7 | P0 regression gate (must pass) | `regression-suite.sh` |

### Step 3: Blue Team (5 independent lenses)

`generate-blind-briefings.ts` produces 5 lens briefings at `.audit-cache/briefings/audit-blue-*.json`.
The **orchestrator** (LLM agent using Task tool) spawns 5 general agents, each with a lens-specific prompt:

```
general agent: "Audit files for {lens} bugs. Signals: {signals}.
  Write findings to .audit-cache/findings/audit-blue-{lens}.json"
```

Lenses: security, concurrency, dataflow, error, resource. No shared briefing = no Bandwagon.

After all 5 agents output findings, run: `bash tools/arbitrate-findings.sh .audit-cache/findings/ .audit-cache/findings.json`

### Extended Phases (manual, after automated pipeline)

| Phase | Action | Tool |
|-------|--------|------|
| 4 Fix | Apply patches for each finding | `apply-fix.ts <findings.json> <id>` |
| 4.5 Test Author | RED+GREEN+boundary tests | `docs/templates/test-template.ts` |
| 5 Static | TypeScript check | `tsc --noEmit` |
| 5.8 Mutation | Test effectiveness | `sed-mutation-test.sh` (≥4/5 kill) |
| 7 Final | Zero-defect certification | `gate-check.sh PHASE_7_FINAL` |

## Severity Classification

| Level | Criteria |
|-------|----------|
| **P0** | Security, data corruption, crash, irrecoverable state |
| **P1** | Functional bug with workaround, race condition, missing guard |
| **P2** | Minor functional, cosmetic, performance, dead code |
| **P3** | Enhancement, wishlist, "nice to have" |

P0/P1/P2 must be fixed. P3 can be deferred with explicit user confirmation (recorded in `cannot_fix_queue`).

## State File

The pipeline maintains `.audit-cache/audit_state.json` (created by `init-audit.sh --force`).
Gates check this file for phase progression. Schema reference: `schemas/finding.schema.json`.
Backup: committed changes use atomic write (`.tmp` → rename).

## Phase Failure Protocol

- Step failure: retry once. Still failing → log to `.audit-cache/phase-errors.json`, ask user.
- Circuit breaker: 3 step failures total → abort pipeline.
- Concurrency lock: `.audit-cache/.lock/pid` prevents dual audits.

## Key Rules

1. **No verbal "zero defect"** — every finding must have `test_ids` + `mutation_killed=true`
2. **All pipeline steps required** — no skips; smoke ≠ full test suite
3. **"Test already exists" is not self-validating** — `sed-mutation-test.sh` ≥4/5 kill
4. **P0/P1/P2 must fix** — P3 deferral requires user OK

## Cross-Run Baselines (`.audit-cache/`)

| File | Tool | Purpose |
|------|------|---------|
| `baseline-zero.json` | `baseline-diff.sh` | Zero-defect files (skip in incremental) |
| `baseline.json` | `cross-run-dedup.sh` | Known finding hashes (cross-run dedup) |
| `regression-index.json` | `regression-suite.sh` | P0 fix test index |

## Finding Format

```bash
hash=$(bash tools/finding-hash.sh --module=path --function=fn --pattern=canonical_id)
```
Schema: `schemas/finding.schema.json`. Cross-run dedup uses stable semantic hash.

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
