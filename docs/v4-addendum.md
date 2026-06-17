# v4 Addendum — Layered Adversarial Audit

**Extracted from SKILL.md v4.0.0 (2026-06-17) to reduce agent context overhead.**

---

## Why v4

6-expert retrospective identified 4 root causes behind shallow, multi-loop audits in v3.5–v3.7:

| Root Cause | v3 Behavior | v4 Solution |
|-----------|-------------|-------------|
| **Bandwagon** | 7 agents share pre-query → 7 copies of same finding | 5 independent lenses (data_flow, concurrency, security, error_handling, resource_lifecycle) per subsystem |
| **File-local scope** | Tools operate on files; root causes cross files | Subsystem manifest + flow trace (32 cross-subsystem flows detected) |
| **Self-referential** | Same LLM verifies its own findings | M3 Red Team (cross-model) + 4-step attack protocol |
| **Single-loop** | Repeat audit, never learn why it missed | AAR (4 questions) + blind spot registry + method updates |

## v4 Workflow (detailed)

```bash
# 1. Generate manifest + flow trace
bash tools/subsystem-manifest.sh generate
npx tsx tools/flow-trace.ts

# 2. Generate 5 divergent briefings (Bandwagon avoidance)
npx tsx tools/generate-blind-briefings.ts

# 3. Run 5 Blue Team agents (each reads ONLY its briefing)
#    Output: .audit-cache/findings/blue_*.json

# 4. Red Team (M3, cross-model, blind to Blue Team reasoning)
npx tsx tools/red-team-attack.ts protocol
#    For each finding, run M3 with 4-step attack
#    Save to .audit-cache/red-team-attacks/<id>_result.json
npx tsx tools/red-team-verify.ts

# 5. After-Action Review (4 mandatory questions)
npx tsx tools/after-action-review.ts template
npx tsx tools/after-action-review.ts commit

# 6. v3.7 Regression (must still pass)
bash tools/regression-suite.sh

# Or run all at once:
bash tools/v4-audit.sh
```

## v4 Tools

| Tool | Type | Purpose |
|------|------|---------|
| `subsystem-manifest.sh` | shell | 13 subsystems auto-detected |
| `flow-trace.ts` | TS | 32 cross-subsystem flows (@/ path alias support) |
| `generate-blind-briefings.ts` | TS | 5–7 independent agent briefings (round-robin lens) |
| `red-team-attack.ts` | TS | 4-step attack protocol |
| `red-team-runner.ts` | TS | Live M3 API integration |
| `red-team-verify.ts` | TS | Verdict aggregation |
| `after-action-review.ts` | TS | AAR + blind spot registry |
| `gold-set.ts` | TS | 24 curated known bugs |
| `v4-detect-rate.ts` | TS | Detection rate vs gold set |
| `v4-audit.sh` | shell | Full v4 orchestrator |

## Cross-Run Baselines

| File (in `.audit-cache/`) | Tool | Purpose |
|------|------|---------|
| `baseline-zero.json` | `baseline-diff.sh` | Files already audited (skip) |
| `baseline.json` | `cross-run-dedup.sh` | Known finding hashes (cross-run dedup) |
| `regression-index.json` | `regression-suite.sh` | Historical P0 fix tests |

## Success Criteria

| Metric | v3.7 | v4 Target | Achieved |
|--------|------|-----------|----------|
| Cross-subsystem findings / total | <5% | >30% | 77% ✅ |
| Findings rediscovered across runs | ~40% | <10% | TBD |
| P0/P1 detection rate (gold set) | ~60% | >90% | 80% |
| Mutation kill rate | ~60% | >85% | TBD |
| Time to convergence | ~4 rounds | ≤3 rounds | 2 ✅ |

## Gold Set (24 known bugs)

Curated from v3.5/v3.6 audit history. Distribution: 4 P0, 16 P1, 4 P2; 13 cross-subsystem (54%). Used to measure detection rate improvement across audit runs.

## audit_state.json Schema

```json
{
  "run_id": "uuid+scope",
  "scope": "module_name",
  "mode": "deep|continuous|quick|incremental|emergency",
  "current_round": 0,
  "current_phase": "PHASE_0_ENTRY",
  "findings": { "FUNC-001": { "status": "open|fixing|fixed|verified", "test_ids": [] } },
  "test_coverage": { "FUNC-001": { "test_ids": [], "mutation_killed": false } },
  "phases_passed": {},
  "gates_passed": {},
  "cannot_fix_queue": [],
  "deferred_queue": []
}
```

## Test Pyramid Definitions

| Layer | Directory | Catches |
|-------|----------|---------|
| Unit | `tests/unit/` | Single-function correctness |
| Integration | `tests/integration/` | Module interactions, schema alignment |
| Contract | `tests/contract/` | API shapes, error formats |
| Property | `tests/property/` | Invariant violations across random inputs |
| Chaos | `tests/chaos/` | Recovery from faults (kill, timeout, concurrency) |
| E2E | `tests/e2e/` | Full user journeys |
