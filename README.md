# audit-fix-loop-v3

Systematic **zero-trust** audit & fix loop for AI coding agents.

**v4.0.0 — Layered Adversarial Audit**: resolves 4 root causes (Bandwagon,
File-local scope, Self-referential verification, Single-loop learning)
identified by 6-expert retrospective. Blue Team (divergent lenses) → Red Team
(cross-model M3) → AAR (double-loop learning).

[![version](https://img.shields.io/badge/version-4.0.0-blue)](SKILL.md)
[![phases](https://img.shields.io/badge/tools-24-orange)](tools/)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![supersedes](https://img.shields.io/badge/supersedes-v3.7.0-lightgrey)](SKILL.md)

---

## Why

AI coding agents produce a long tail of defects that static analysis misses:

- **Runtime bugs** (e.g. `signal is aborted without reason` — 30s timeout vs 120s actual need)
- **Cross-cutting concerns** (OWASP API Top 10, a11y, observability)
- **Compounding regressions** (fixing one bug surfaces three more)
- **Test gaps** (verified fixes with no regression test → re-introduced on next refactor)

Manual review catches 30–50% of these. Multi-agent parallel review catches
70–80%. **This skill catches 95%+ by enforcing** mechanical gates, runtime
test pyramid, and a non-overridable zero-trust workflow.

### Real-world validation

- **English-CET v4 audit** (2026-06-17): 2 full adversarial audit cycles
  - 5→7 Blue Team agents (divergent lenses), M3 Red Team (cross-model)
  - 22 findings (1 P0, 7 P1, 14 P2), 14 cross-subsystem cousin bugs by Red Team
  - 19 bugs fixed across 15 files, 380/380 tests, 0 tsc errors
  - Detection rate: 29%→75% after AAR applied (+46%)
  - AAR double-loop: 2 cycles, 7 method updates, 5 blind spots registered
- **English-CET writing training**: 8 audit rounds converged 58 defects to 0
- **Grammar training module**: 21 findings, all resolved, 5 P0 covered
- **5 new vulnerabilities** caught by v3.3 in code that had already passed 8 prior rounds

---

---

## v4.0.0 — Layered Adversarial Audit

v3.5→v4.0: pipeline → system. 6-expert retrospective identified **4 root causes**
behind shallow, multi-loop audits:

| Root Cause | v3 behavior | v4 solution |
|-----------|-------------|-------------|
| **Bandwagon** (6/6) | 7 agents share pre-query → 7 copies of same finding | 5 independent lenses per subsystem |
| **File-local scope** (6/6) | Tools operate on files; root causes cross files | Subsystem manifest + flow trace (32 cross-flows) |
| **Self-referential** (4/6) | Same LLM verifies its own findings | M3 Red Team (cross-model) + 4-step attack protocol |
| **Single-loop** (3/6) | Repeat audit, never learn why it missed | AAR (4 questions) + blind spot registry + method updates |

### New tools (v4, 16 total)

| Tool | Type | Purpose |
|------|------|---------|
| `subsystem-manifest.sh` | shell | 13 subsystems auto-detected from project structure |
| `flow-trace.ts` | TS | 32 cross-subsystem data flows (handles @/ path alias) |
| `generate-blind-briefings.ts` | TS | 5→7 independent agent briefings (round-robin lens) |
| `red-team-attack.ts` + `red-team-runner.ts` + `red-team-verify.ts` | TS | M3 cross-model adversarial verification |
| `after-action-review.ts` | TS | 4 mandatory questions → method updates → blind spot registry |
| `gold-set.ts` | TS | 24 curated known bugs for detection rate measurement |
| `v4-audit.sh` | shell | Full v4 orchestrator (all tools in order + v3 regression gate) |
| `v4-detect-rate.ts` | TS | Detection rate measurement vs gold set |
| `finding-hash.sh` | shell | Stable semantic hash for cross-run dedup |
| `cross-run-dedup.sh` | shell | Baseline-based finding suppression |
| `baseline-diff.sh` | shell | Git diff-driven incremental audit scope |
| `regression-suite.sh` | shell | P0 regression test gate |
| `sed-mutation-test.sh` | shell | 5-pattern mutation test (30s) |
| `audit-state-hash.sh` | shell | SHA-256 integrity check on state file |

## What — 12 phases (v4 adds Phase 0.5 Baseline Load)

| Phase | Name | Output |
|-------|------|--------|
| **0** | Entry + state machine init | `audit_state.json` |
| **1.0** | Pre-query (mandatory) | `pre-query-{round}.json` |
| **1.1–1.4** | SBL functional/practice/contract/journey | `sbl-v3.json` |
| **1.5** | **Test pyramid setup** (v3.5) | `tests/{unit,integration,contract,e2e,property,chaos}/` |
| **2** | 7-agent parallel audit | Findings JSON |
| **3** | Arbitration + 3-layer root cause | Deduplicated + severity-tiered |
| **4** | Fix (3 modes) | Modified source + git diff |
| **4.5** | **Test author** (v3.5) | `tests/{unit,property,...}/f-{id}.test.ts` |
| **5** | Static verification | `tsc --noEmit` + lint + build |
| **5.5** | Runtime smoke (DB-aware) | `smoke-test-{round}.json` |
| **5.6** | **Dynamic test suite** (v3.5) | `dynamic-test-{round}.json` |
| **5.7** | **Chaos test** (v3.5) | `chaos-test-{round}.json` |
| **5.8** | **Mutation test** (v3.5) | `mutation-test-{round}.json` |
| **6** | LOOP | Convergence check, ≤8 rounds → escalation |
| **6.5** | Devil's Advocate (mandatory) | New attack-vector findings |
| **7** | Final verification | Executive + Engineering layer |

### v3.5 Zero-Trust Edition — key mechanisms

- **Mechanical gates** (v3.4) — `tools/gate-check.sh` enforces phase
  transitions; cannot proceed to next phase without state machine
  consistency
- **State machine** (v3.4) — `audit_state.json` tracks every finding's
  lifecycle (`open → fixing → fixed → verified`); resizable across
  compaction/restart
- **Report reverse-validation** (v3.4) — `tools/verify-report.sh` ensures
  final report numbers match `audit_state.json` counts; no fabricated
  "zero defect" claims
- **Test pyramid mandatory** (v3.5) — 6 layers required:
  unit / integration / contract / e2e / property / chaos
- **Test coverage matrix** (v3.5) — every verified finding MUST have
  `test_ids` in `audit_state.json`; verified without test = warn/block
- **Mutation test** (v3.5) — `tools/mutation-test.sh` reverse-modifies
  fix code; tests that don't catch mutation = ineffective test
- **Chaos test** (v3.5) — fault injection (kill mid-request, restart,
  concurrent) verifies recovery paths
- **3-layer root cause** — for every P0/P1:
  1. Where is the code wrong?
  2. Why did the audit miss it? (process gap)
  3. Are similar bugs in other locations? (systemic gap)
- **TOOL_ACTIVITY log** — every agent must log webfetch URLs + status.
  Prevents forged source attacks
- **cannot_fix_reason whitelist** — only 5 legitimate reasons:
  `external_dependency` / `data_migration` / `out_of_scope` /
  `missing_infrastructure` / `design_tradeoff`. "Will fix later" /
  "non-blocking" / "backlog" are banned

### Decision grading (L0–L4)

| Level | Meaning | Who decides |
|-------|---------|-------------|
| L0 | Single best practice | Agent self, with `[source:URL]` |
| L1 | 2–3 options | Agent recommends + default (conservative) |
| L2 | Multiple trade-offs | Agent decision tree + recommend + default |
| L3 | Business vs technical | User must choose, **300s timeout pauses** |
| L4 | Business direction | User leads, infinite timeout |

---

## Install

This is an OpenCode skill. Install by copying into your skills directory:

```bash
git clone https://github.com/ailyedu2030/audit-fix-loop.git \
  ~/.config/opencode/skills/audit-fix-loop-v3
```

### Requirements

- `jq` (preferred) **or** `python3` (fallback for shell tools)
- `git` (for diff anchoring + state machine persistence)
- `fast-check` (npm) for property-based tests
- Network access for `webfetch` (AI provider docs, OWASP, MDN, PG docs, etc.)

Verify install:

```bash
# Tools should be executable
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/gate-check.sh --help

# State machine
python3 -c "import json; json.load(open('~/.config/opencode/skills/audit-fix-loop-v3/SKILL.md'))"
```

---

## Usage

### Quick start

```
"帮我看代码"
```

Default: `quick` mode (15–30 min). Reply "全面" to upgrade to `continuous`.

### Modes

| Mode | When | Duration |
|------|------|----------|
| `quick` | ≤3 file small changes | 15–30 min |
| `deep` | Cross-module / security | 1–4 h |
| `continuous` | **Full zero-trust zero-defect (default recommended)** | 2–8 h |
| `incremental` | Have baseline, modifying 1–3 files | 15–30 min |
| `emergency` | P0 blocker | Fix immediately, 24h `continuous` follow-up |

### Convergence check (per round)

```bash
bash tools/convergence-check.sh \
  --findings-db=.audit-cache/audit_state.json \
  --first-round-total=<N> \
  --sbl=.audit-cache/sbl-v3.json \
  --smoke-test=.audit-cache/smoke-test-{round}.json \
  .audit-cache/findings-round-{N}.json \
  .audit-cache/findings-round-{N-1}.json \
  {N}
```

Exit codes: `0` = converged | `1` = continue | `2` = escalate | `3` = error

### v3.5 zero-trust gate (per round, mandatory)

```bash
# 1. State machine gates
bash tools/gate-check.sh --required-phase=PHASE_7_FINAL .audit-cache/audit_state.json

# 2. Test coverage (every verified finding must have test_ids + mutation_killed)
bash tools/test-coverage-check.sh --state=.audit-cache/audit_state.json

# 3. Zero-defect
bash tools/zero-defect-check.sh --state=.audit-cache/audit_state.json

# 4. Report reverse-validation
bash tools/verify-report.sh \
  --report=.audit-cache/final-report.md \
  --state=.audit-cache/audit_state.json

# 5. Dynamic test suite
bash tools/dynamic-test-runner.sh --state=.audit-cache/audit_state.json

# 6. Chaos
bash tools/chaos-test.sh --state=.audit-cache/audit_state.json

# 7. Mutation
bash tools/mutation-test.sh --state=.audit-cache/audit_state.json
```

All must pass for `converged` decision.

### Escalation

If 8+ rounds without convergence, see `.audit-cache/escalation-{round}.json`
for suggestion (`downgrade to quick` / `expand budget` / `human intervention`).
**The skill pauses** — it does NOT auto-continue.

---

## File structure

```
audit-fix-loop-v3/
├── SKILL.md                                      # Authoritative definition (v3.5)
├── README.md                                     # this file
├── CHANGELOG.md                                  # v3.3 → v3.4 → v3.5 evolution
├── LICENSE                                       # MIT
├── .gitignore                                    # session artifacts
└── tools/
    ├── convergence-check.sh                      # v3.3: result-driven convergence
    ├── fix-impact-matrix-template.yaml           # per-fix tracking
    ├── sbl-functional-template.md                # Phase 1.1 template
    ├── gate-check.sh                             # v3.4: phase transition enforcement
    ├── verify-report.sh                          # v3.4: report vs state reverse-check
    ├── zero-defect-check.sh                      # v3.4: 0 open verification
    ├── test-coverage-check.sh                    # v3.5: test_ids + mutation_killed
    ├── chaos-test.sh                             # v3.5: fault injection
    ├── mutation-test.sh                          # v3.5: reverse-validate test effectiveness
    └── dynamic-test-runner.sh                    # v3.5: full test pyramid runner
```

---

## Cache layout

Generated under `.audit-cache/` during execution:

```
.audit-cache/
├── audit_state.json                 # ⭐ source of truth (v3.4+)
├── sbl-v3.json                       # SBL single source of truth
├── pre-query-{round}.json           # Phase 1.0 mandatory pre-queries
├── findings-round-{N}.json          # per-round findings
├── webfetch-trace.jsonl              # anti-forgery log
├── contract-{round}.json            # Phase 1.3 contract matrix
├── contract-check-{round}.json      # Phase 5 contract verification
├── fix-impact/                      # per-fix impact matrices
├── smoke-test-{round}.json          # Phase 5.5 runtime smoke
├── dynamic-test-{round}.json        # v3.5 Phase 5.6 dynamic suite
├── chaos-test-{round}.json          # v3.5 Phase 5.7 chaos results
├── mutation-test-{round}.json       # v3.5 Phase 5.8 mutation results
├── convergence-log.jsonl            # per-round decisions
└── escalation-{round}.json          # ≥8 round escalation
```

Auto-cleanup: >100MB triggers warning, last 3 rounds retained.

---

## v3.5 Zero-Trust Story

**v3.3 problem**: static review found bugs, agent reported "fixed",
runtime still had issues. **Paper zero defect ≠ runtime zero defect**.

**v3.4 fix**: mechanical gates prevent LLM self-evaluation of "complete".
State machine tracks every finding's lifecycle. Report reverse-validates
against artifacts.

**v3.5 fix**: even v3.4 "verified" without regression test is a lie.
Test pyramid mandatory; every verified finding must have `test_ids`;
mutation test confirms tests actually catch bugs; chaos test confirms
recovery paths exist.

**Result**: 21 findings → 18 verified (with tests) + 3 cannot_fix (white-listed)
= real zero-trust zero-defect. Not paper.

---

## Migration

| From | To | Action |
|------|------|--------|
| v2.x (audit-fix-verify) | v3.5 | Replace skill dir, update agent prompts |
| v3.3 | v3.5 | Update SKILL.md, run `npm install fast-check`, create `audit_state.json` template |
| v3.4 | v3.5 | Add test pyramid, run `bash tools/test-coverage-check.sh` to identify gaps |

### Breaking changes v3.3 → v3.5

- v3.4: agents no longer self-verify completion (mechanical gates)
- v3.4: state machine required (`audit_state.json`)
- v3.4: cannot_fix uses 5-reason whitelist (was freeform)
- v3.5: test pyramid 6 layers mandatory
- v3.5: every verified finding must have `test_ids` + `mutation_killed=true`
- v3.5: chaos test + mutation test added to mandatory phases

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

---

## License

MIT © ailyedu2030

---

## Related

- [English-CET-main](https://github.com/ailyedu2030/English-CET) — production
  codebase where this skill is battle-tested
- [OpenCode](https://opencode.ai) — AI coding agent platform
