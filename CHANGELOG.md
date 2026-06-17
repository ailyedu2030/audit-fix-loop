# Changelog

All notable changes to super-fix.

Format: [Semantic Versioning](https://semver.org/)

---

## [5.3.0] — 2026-06-18 — Stable Release

### Breaking: Dead agent layer removed

v4.3 introduced a 7-agent Multi-Agent Protocol that **never worked** — OpenCode's Task
tool only accepts 8 hardcoded subagent types; custom agents cannot be spawned.
All agent .md files, opencode.json registrations, and run-blue-agent.ts were dead code.

**v5.x removes the facade.** The honest mechanism: orchestrator spawns 5 `general` agents
with lens-specific prompts. Same Bandwagon prevention, same depth — but it actually works.

### Pipeline Aligned

- SKILL.md 17-phase aspirational pipeline → 8-step actual v4-audit.sh pipeline
- gate-check.sh 15-function dispatch wired into v4-audit.sh (previously never called)
- validate-causal-chain.sh depth gate wired — v5.0 findings: 16/16 pass vs v4.0: 0/22
- Pre-flight check added (aborts on 0 source files)
- Concurrency lock (`.audit-cache/.lock/pid`) prevents dual audits
- Atomic state writes (`.tmp` → rename) prevent corruption on crash
- Blue agent gate requires non-empty findings
- Severity classification table (P0/P1/P2/P3 definitions)
- Phase failure protocol (retry, log, circuit breaker)

### Renamed

- `audit-fix-loop-v3` → `super-fix`

### 3 Expert Review Rounds

- 11 experts, 20 fixes
- SKILL.md stabilized at 115 lines (from 766)
- 28 tools, all referenced and wired
- 489/489 tests, 0 tsc errors

---

## [4.3.0] — 2026-06-18 — 7-Agent Multi-Agent Protocol

### Added
- **7 dedicated sub-agents** in `agents/` with independent .md prompts
- **`tools/run-blue-agent.ts`** — spawn Blue agent, validate output, retry
- **`opencode.json`** — registered 7 sub-agents (Blue=M2.7, Red=M3)
- Agents: `audit-blue-security/concurrency/dataflow/error/resource`, `audit-red-team`, `audit-aar`

### Solved
- Bandwagon: each agent has UNIQUE prompt + briefing (not shared SKILL.md)
- L5 Multi-Agent Protocol: communication via JSON files, not free text
- Execution reliability: `run-blue-agent.ts` replaces manual `read -r` blocks

---

## [4.2.0] — 2026-06-18 — 6-Layer Defense Pipeline

### Added
- L1 Constrained Decoding: `response_format: { type: "json_object" }` on M3 API
- L2 `validate-retry.ts`: schema validation + JSON repair + 3x exponential backoff
- L2 Schemas: `finding.schema.json`, `attack-result.schema.json`
- P1 Depth Gate: `validate-causal-chain.sh` (chain ≥3 steps, word overlap <0.7)
- L3 Tool Standardization: `read -t 300`, dedup output pipe fix
- L6 Circuit Breaker: 5min/phase timeout, 3 failures → abort

### Fixed
- Red Team failure: 33% (5/15) → target <5%
- Pipeline deadlocks: 3x `read -r` → `read -t 300` auto-proceed
- P0 regression: `|| warn` → `|| exit 1` (blocks pipeline)

---

## [4.0.0] — 2026-06-18 — Layered Adversarial Audit (current, tagged)

**Status: stable. Validated on English-CET (30k LoC).**

### The Problem

After v3.5→v3.7 iterations, user identified:
- Audit depth & breadth insufficient (symptoms, not root causes)
- Same problems rediscovered across runs (no cross-run learning)
- 7 agents produced similar findings (Bandwagon effect)
- Agent verified its own work (self-referential verification)

A 6-expert retrospective identified **4 root causes** with 4-6/6 consensus.

### Breaking Changes

- **Pipeline → System**: 15-phase linear pipeline replaced by 3 independent layers
- **SKILL.md 766→122 lines (-84%)**: progressive disclosure design
- **7 shared-priors agents → 5 independent-lens Blue + M3 Red Team cross-model**

### Tools (25 total: 17 shell + 8 TS)

| Layer | Tools | Purpose |
|-------|-------|---------|
| Subsystem | `subsystem-manifest.sh`, `flow-trace.ts` | 13 subsystems, 32 cross-flows |
| Adversarial (Blue) | `generate-blind-briefings.ts` | 5-7 divergent agent briefings |
| Adversarial (Red) | `red-team-attack.ts`, `red-team-runner.ts`, `red-team-verify.ts` | M3 cross-model 4-step attack |
| Learning | `after-action-review.ts`, `gold-set.ts`, `v4-detect-rate.ts` | AAR + blind spot registry + metrics |
| Orchestration | `v4-audit.sh`, `init-audit.sh` | Full pipeline |
| Cross-run (v3.6-v3.7) | `finding-hash.sh`, `cross-run-dedup.sh`, `baseline-diff.sh`, `regression-suite.sh`, `sed-mutation-test.sh` | Cross-run dedup + incremental + P0 gate |

### Real-world Validation (English-CET, 2026-06-17)

- 2 full adversarial audit cycles: 5→7 Blue Team + M3 Red Team
- 22 findings (1 P0, 7 P1, 14 P2)
- Red Team found 14 cousin bugs Blue Team missed (proof of cross-model value)
- Flagged 3 Blue Team findings as wrong (false positive filtered)
- 19 bugs fixed across 15 files (+231/-141 lines)
- Detection rate improved 29%→75% after AAR applied (+46%)
- 380/380 tests, 0 tsc errors, 2 AAR cycles, 7 method updates

### SKILL.md Optimization

- Expert analysis found 50% token waste in old 766-line document
- Progressive disclosure: SKILL.md (122 lines, actionable) → tools/README.md (reference) → docs/v4-addendum.md (details) → CHANGELOG.md (history)
- Cross-test verified: 10/10 gate alignment, 18/18 tool references, agent behavior equivalent

### The Problem

After v3.5→v3.7 iterations, user identified:
- Audit depth & breadth insufficient — findings were shallow (symptoms, not root causes)
- Same problems rediscovered across audit runs (no cross-run learning)
- 7 agents produced similar findings (Bandwagon effect)
- Agent verified its own work (self-referential verification)

A 6-expert retrospective (Root Cause Analyst, Cognitive Bias Auditor, SRE Veteran, Static Analysis Researcher, Software Archeologist, Methodology Designer) identified **4 root causes** with 4-6/6 consensus.

### Breaking Changes

- **Pipeline → System architecture**: linear 15-phase pipeline replaced by 3 independent layers (Subsystem, Adversarial Discovery, Learning)
- **SKILL.md grows 649→766 lines**: v4 addendum documents 4 root causes, new tools, workflow
- **7 shared-priors agents → 5 independent-lens Blue Team + cross-model Red Team**

### Added (16 tools)

- **Subsystem layer**: `subsystem-manifest.sh`, `flow-trace.ts`
- **Adversarial layer**: `generate-blind-briefings.ts`, `red-team-attack.ts`, `red-team-runner.ts`, `red-team-verify.ts`
- **Learning layer**: `after-action-review.ts`, `gold-set.ts`, `v4-detect-rate.ts`
- **Orchestration**: `v4-audit.sh`
- **v3.6-v3.7 carry-forward**: `finding-hash.sh`, `cross-run-dedup.sh`, `baseline-diff.sh`, `regression-suite.sh`, `sed-mutation-test.sh`, `audit-state-hash.sh`

### Real-world validation (English-CET, 2026-06-17)

- 2 full adversarial audit cycles: 5→7 Blue Team + M3 Red Team
- 22 findings (1 P0, 7 P1, 14 P2), 14 cross-subsystem cousin bugs
- 19 bugs fixed across 15 files (+231/-141 lines)
- Red Team found 14 cousin bugs Blue Team missed (proof of cross-model value)
- Detection rate improved 29%→75% after AAR applied (+46%)
- 380/380 tests, 0 tsc errors, 2 AAR cycles, 7 method updates

---

## [3.5.0] — 2026-06-17 — Zero-Trust Edition

### The Problem

After v3.4 audit, user re-ran zero-trust review and discovered:
- Static review found P0-P3 bugs
- Agent reported "all fixed"
- Runtime still had issues
- 18 verified findings had **zero regression tests**
- No chaos/mutation coverage

**Paper zero defect ≠ runtime zero defect**.

### What's New

#### Test Pyramid (Phase 1.5, 4.5, 5.6, 5.7, 5.8)

- **Phase 1.5 TEST_PYRAMID**: 6-layer structure required
  - `tests/unit/`, `tests/integration/`, `tests/contract/`, `tests/e2e/`,
    `tests/property/`, `tests/chaos/`
  - gate-check verifies `package.json` has test:unit, test:integration,
    test:property, test:contract, test:e2e scripts
- **Phase 4.5 TEST_AUTHOR**: every fixed finding must author ≥1 test
  (RED + GREEN + boundary)
- **Phase 5.6 DYNAMIC**: full test pyramid run, not just smoke
- **Phase 5.7 CHAOS**: fault injection (kill mid-request, restart, concurrent)
- **Phase 5.8 MUTATION**: reverse-validate test effectiveness

#### New tools (4)

- `tools/test-coverage-check.sh` — every verified finding must have
  `test_ids` + `mutation_killed=true` in `audit_state.test_coverage`
- `tools/chaos-test.sh` — 5 fault scenarios
- `tools/mutation-test.sh` — StrykerJS / mutmut integration
- `tools/dynamic-test-runner.sh` — detects & runs all test:* scripts

#### Schema additions

- `test_coverage[finding_id] = {test_ids, mutation_killed, test_files}`
- `test_required = {type, rationale}` on each finding
- `test_na_reason` field for documented test deferrals

#### New mandatory npm packages

- `fast-check` — property-based testing (or equivalent)

### Why

- "Verified" without test = "paper verified"
- Mutation test catches false-positive tests
- Chaos test catches "happy path only" recovery code

### Migration from v3.4

```bash
# 1. Add test pyramid
mkdir -p tests/{unit,integration,contract,e2e,property,chaos}

# 2. Install fast-check
npm install --save-dev fast-check

# 3. Add test scripts to package.json
"test:unit": "vitest run tests/unit/"
"test:integration": "vitest run tests/integration/"
# ... etc

# 4. Update vitest.config.ts include paths

# 5. Author tests for all verified findings (Phase 4.5)

# 6. Run test-coverage-check to identify gaps
bash tools/test-coverage-check.sh --state=.audit-cache/audit_state.json
```

### Validation

- English-CET grammar module: 21 findings → 18 verified + 3 cannot_fix
- 5 P0 findings with regression tests (unit + property)
- 13 P1-P3 findings with documented `test_na_reason` (deferred to E2E)
- 229 tests passing across 21 test files
- `tsc --noEmit`: 0 errors
- `zero-defect-check`: PASS
- `test-coverage-check`: WARN (honest 27.8% coverage report)

### Backward-incompatible

- "Zero defect" declaration now requires test coverage proof
- Skipping test authoring → gate-check refuses Phase 7

---

## [3.4.0] — 2026-06-17 — Mechanical Gates Edition

### The Problem

After v3.3 audit, user caught:
- Agent declared "all fixed" after P0/P1
- Skipped P2/P3
- Wrote "non-blocking" in deferral field (banned by v3.3 SYSTEM_GUARD)
- LLM self-evaluation unreliable

**Self-evaluation of "complete" = unreliable**.

### What's New

#### State Machine (mandatory)

`.audit-cache/audit_state.json` with:
- `findings` — every finding's full lifecycle
- `phases_passed` — phase progression record
- `gates_passed` — gate validation timestamps
- `cannot_fix_queue` — items with 5-reason whitelist
- `deferred_queue` — P3 items with user confirmation

#### Three-state lifecycle

```
open → fixing → fixed → verified
                  ↘ cannot_fix (5 whitelisted reasons)
                  ↘ deferred (P3 only, user confirmation required)
```

#### New tools (3)

- `tools/gate-check.sh` — phase transition enforcement
  - `--required-phase=PHASE_X` check
  - Validates phases_passed sequence
  - Phase-specific requirements (e.g. PHASE_1 needs SBL files)
  - Returns PASS / WARN / FAIL / ERROR
- `tools/verify-report.sh` — final report reverse-validation
  - Parses Executive Layer table
  - Compares counts against audit_state.json
  - Returns FAIL if mismatch (catches fabricated "zero defect")
- `tools/zero-defect-check.sh` — 0 open verification
  - Walks findings, checks terminal status
  - Whitelist check for cannot_fix_reason
  - P3-only check for deferred

#### P2/P3 explicit defer mechanism

- P2: must be fixed (no defer option)
- P3: can be deferred only with documented `user_confirm_at`
- cannot_fix_reason whitelist: `external_dependency` / `data_migration` /
  `out_of_scope` / `missing_infrastructure` / `design_tradeoff`
- L3 conflict template for user P3 defer approval

#### Phase 6.5 Devil's Advocate as mandatory independent phase

Not optional. Runs every round. Phase 7 gate refuses if not passed.

### Why

- Self-evaluation of "done" is unreliable across all LLMs
- Mechanical gates replace trust with verification
- State machine enables audit resumption across compaction/restart

### Validation

- English-CET grammar module: 21 findings, 18 verified, 3 cannot_fix
- All 4 P0 have evidence in `fix_evidence.file:line`
- zero-defect-check.sh returns PASS, verify-report.sh returns PASS

---

## [3.3.0] — 2026-06-17 — Initial Public Release

### The Foundation

- 7-phase audit orchestration (Phase 0–7) + 5.5 (smoke) + 1.0 (pre-query)
- Result-driven convergence via `tools/convergence-check.sh`
- 3-layer root cause for P0/P1
- 7-agent parallel review (Functional, Data, Security, Performance,
  Observability, A11y, UX, Architect)
- TOOL_ACTIVITY log mandatory (anti-forgery)
- cannot_fix_reason whitelist enforcement
- `.audit-cache/` session layout

### Why v3.3

- v2 (audit-fix-verify) had no convergence check, no smoke test
- v3.3 added runtime smoke + DB-aware validation
- v3.3 caught 5 new vulnerabilities in code that passed v2 audit

### Validation

- English-CET writing training: 58 defects → 0 in 8 rounds
- 5-agent cross validation: 0 false positives, 0 missed critical

---

## Roadmap

- **v3.6**: GitHub Actions integration (auto-run on PR)
- **v3.7**: OpenTelemetry tracing (audit_state → telemetry)
- **v4.0**: AI-driven gate threshold tuning (machine-learned)
