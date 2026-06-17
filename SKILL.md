---
name: audit-fix-loop-v3
version: 4.0.0
description: 系统性零信任审查与修复。v4 解决 4 大根因 (Bandwagon/File-local/Self-referential/Single-loop)。3 层系统 (Subsystem/Adversarial/Learning)：5 独立 lens Blue Team + 跨模型 M3 Red Team + AAR 双环学习。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Task, WebFetch, skill]
supersedes: [audit-fix-verify, audit-fix-loop-v3.3, audit-fix-loop-v3.4, audit-fix-loop-v3.5, audit-fix-loop-v3.6, audit-fix-loop-v3.7]
---

# Audit → Fix → Loop v4

Layered adversarial audit for AI coding agents. Three independent layers: Subsystem (manifest + flow trace), Adversarial Discovery (5 independent-lens Blue + cross-model M3 Red), Learning (AAR + blind spot registry).

**v3.7 lesson**: "clear-domain tool on complex-domain problem" — 15 phases skipped because the agent couldn't faithfully execute them. v4 = pipeline → system, with independent layers that genuinely run.

## When to Use

| Situation | Mode |
|-----------|------|
| First audit / new project | `v3.7 deep` |
| Shallow findings, repeated cycles (v4 target) | **`v4`** |
| Single file / small change | `v3.7 incremental` |
| Emergency P0 | `v3.7 emergency` |
| Monthly deep dive / prove-it's-clean | **`v4`** |

## Quick Start

```bash
bash tools/init-audit.sh --mode=deep                  # Phase 0
bash tools/v4-audit.sh                                  # Full v4 pipeline
# Or v3.7:  bash tools/v4-audit.sh --v3.7 --deep
```

## Pipeline

| Phase | Action | Gate |
|-------|--------|------|
| 0 Entry | `init-audit.sh`, baseline load | `gate-check PHASE_0` |
| 1.0 Pre-query | Domain context → `pre-query.json` | — |
| 1.1–1.4 SBL | Single source of truth (`sbl-functional-template.md`) | `gate-check PHASE_1` |
| 1.5 Test Pyramid | Verify ≥4 test layers exist | `gate-check PHASE_1_5` |
| 2 Review | 7-agent parallel (v4: 5 blind-briefings) | — |
| 3 Arbitration | Merge findings, assign test_required | — |
| 4 Fix | Apply patches | — |
| 4.5 Test Author | RED+GREEN+boundary (see `docs/templates/test-template.ts`) | `gate-check PHASE_4_5` |
| 5 Static | `tsc --noEmit` / lint | `gate-check PHASE_5` |
| 5.5 Smoke | Happy+error+boundary paths | `gate-check PHASE_5_5` |
| 5.6 Dynamic | Full test suite (`dynamic-test-runner.sh`) | `gate-check PHASE_5_6` |
| 5.7 Chaos | Fault injection (`chaos-test.sh`) | `gate-check PHASE_5_7` |
| 5.8 Mutation | Test effectiveness (`sed-mutation-test.sh`, ≥4/5 kill) | `gate-check PHASE_5_8` |
| 6 Loop | Convergence (`convergence-check.sh`), max 8 rounds | — |
| 6.5 Devil's Advocate | Independent adversarial challenge | `gate-check PHASE_6_5` |
| 7 Final | Zero-defect cert (`verify-report.sh` + `regression-suite.sh`) | `gate-check PHASE_7` |

### v4-specific steps (auto via `v4-audit.sh`)

| Step | Tool |
|------|------|
| Subsystem + Flow | `subsystem-manifest.sh` → `flow-trace.ts` |
| Blind Briefings | `generate-blind-briefings.ts` (5 lenses, round-robin) |
| Blue Team | 5 agents, each reads 1 briefing |
| Red Team (M3) | `red-team-attack.ts` (4-step: trace→mutation→cousin→verdict) |
| AAR | `after-action-review.ts` (4 questions: plan/outcome/why/improve) |
| v3.7 Regression | `regression-suite.sh` (must pass) |

## Key Rules

1. **No verbal "zero defect"** — every verified finding must have `test_ids` + `mutation_killed=true`
2. **Gates are mandatory** — `gate-check.sh` at every phase transition; without it phases_passed stays false
3. **Phase 4.5/5.6/5.7/5.8 cannot be skipped** — all required for Phase 7 entry
4. **"Test already exists" is not self-validating** — `sed-mutation-test.sh` must prove tests catch bugs (≥4/5 kill)
5. **Smoke ≠ whole pyramid** — dynamic + chaos + mutation all required; smoke is 1/6 layers
6. **P0 regression suite** — every historical P0 bug has a regression test; all pass before Phase 7
7. **P2 must fix**; P3 can defer only with explicit user confirmation (recorded in `cannot_fix_queue`)

## Gate Reference

| Gate | Enforces |
|------|----------|
| `PHASE_0_ENTRY` | `audit_state.json` exists, mode set |
| `PHASE_1_SBL` | Pre-query + SBL files present |
| `PHASE_1_5` | ≥4 test layers with test files |
| `PHASE_4_5` | Every `status=fixed` finding has `test_ids.length > 0` |
| `PHASE_5_6` | Dynamic test pass, coverage > 80% |
| `PHASE_5_7` | Chaos scenarios pass (kill/restart/concurrent/timeout) |
| `PHASE_5_8` | Mutation kill ≥4/5 per file; all verified findings `mutation_killed=true` |
| `PHASE_7` | 0 open, 0 fixing, all verified, P0 regression pass |

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

## v4 Architecture (see `docs/v4-addendum.md` for full details)

- **Subsystem layer**: `subsystem-manifest.sh` (13 subsystems) → `flow-trace.ts` (32 cross-flows)
- **Adversarial layer**: Blue Team (5 independent lenses) → Red Team (M3, 4-step attack)
- **Learning layer**: After-Action Review → blind spot registry → method updates

## Tool Index

See `tools/README.md` for full documentation (parameters, exit codes, examples).

## Reference

- `docs/v4-addendum.md` — v4 detailed workflow, success criteria, gold set, schema
- `docs/templates/test-template.ts` — Phase 4.5 test authoring template
- `CHANGELOG.md` — all version history (v3.3→v4.0.0)
- `tools/README.md` — tool documentation (24 tools, all phases)
