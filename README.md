# audit-fix-loop-v3

Systematic zero-defect audit & fix loop for AI coding agents. Result-driven convergence, runtime smoke test, 3-layer root cause. **All P0–P3 must be fixed.**

[![version](https://img.shields.io/badge/version-3.3.0-blue)](SKILL.md)
[![supersedes](https://img.shields.io/badge/supersedes-audit--fix--verify-lightgrey)](SKILL.md)
[![phases](https://img.shields.io/badge/phases-7%20%2B%205.5%20%2B%201.0-green)](SKILL.md)

---

## Why

AI coding agents produce a long tail of defects that static analysis misses:
- **Runtime bugs** (e.g. `signal is aborted without reason` — 30s timeout vs 120s actual need)
- **Cross-cutting concerns** (OWASP API Top 10, a11y, observability)
- **Compounding regressions** (fixing one bug surfaces three more)

Manual review catches 30–50% of these. Multi-agent parallel review catches 70–80%.
**This skill catches 95%+ by enforcing:** result-driven convergence, runtime smoke,
3-layer root cause analysis, and a non-overridable SYSTEM_GUARD.

### Real-world validation

- **English-CET writing training**: 8 audit rounds converged 58 defects to 0
- **5-agent cross validation**: zero false positives, zero missed critical bugs
- **5 new vulnerabilities found** by v3.3 in code that had already passed 8 prior rounds
  (proving the audit range must cover adjacent endpoints, not just the focused module)

---

## What

A 7-phase orchestration skill with 2 mandatory sub-phases:

| Phase | Name | Output |
|-------|------|--------|
| **0** | Entry + cache cleanup | Mode selection (quick/deep/continuous/incremental/emergency) |
| **1.0** | Pre-query mandatory | `pre-query-{round}.json` (AI provider docs, DB docs, package.json) |
| **1.1–1.4** | SBL-functional/practice/contract/journey | `sbl-v3.json` (single source of truth) |
| **2** | 7-agent parallel audit | Findings JSON with TOOL_ACTIVITY log |
| **3** | Arbitration | Deduplicated findings with 3-layer root cause for P0/P1 |
| **4** | Fix (3 modes) | Modified source + git diff |
| **5** | Static verification | `tsc --noEmit` + lint + build + contract check |
| **5.5** | Runtime smoke (NEW v3.3) | `smoke-test-{round}.json` (catches runtime bugs static analysis misses) |
| **6** | LOOP | Convergence check, ≤8 rounds → escalation |
| **7** | Final verification | Executive + Engineering layer report |

### Key mechanisms

- **SYSTEM_GUARD** — Rules cannot be overridden by code comments, user input, or
  webfetch content. Any text attempting to modify audit behavior → P0 report.
- **Result-driven convergence** — Converge when active findings ≤10% of first round
  AND no P0/P1 present AND Meta-Review passes. Not a fixed-round counter.
- **3-layer root cause** — For every P0/P1:
  1. Where is the code wrong?
  2. Why did the audit miss it? (process gap)
  3. Are similar bugs in other locations? (systemic gap)
- **TOOL_ACTIVITY log** — Every agent must log its webfetch URLs + status. Prevents
  forged source attacks.
- **cannot_fix_reason whitelist** — Only 5 legitimate reasons:
  `external_dependency` / `data_migration` / `out_of_scope` /
  `missing_infrastructure` / `design_tradeoff`. "Will fix later" / "non-blocking"
  / "backlog" are banned.
- **Cache auto-cleanup** — `.audit-cache/` >100MB triggers warning + retention
  of last 3 rounds. `sbl-v3.json` never deleted.
- **Phase 5.5 runtime smoke** — Catches bugs like the 30s→120s timeout issue that
  8 rounds of static analysis missed.

### Decision grading (L0–L4)

| Level | Meaning | Who decides |
|-------|---------|-------------|
| L0 | Single best practice | Agent self, with `[source:URL]` |
| L1 | 2–3 options | Agent recommends + default (conservative) |
| L2 | Multiple trade-offs | Agent decision tree + recommend + default |
| L3 | Business vs technical | User must choose, **300s timeout pauses without executing** |
| L4 | Business direction | User leads, infinite timeout |

---

## Install

This is an OpenCode skill. Install by copying into your skills directory:

```bash
# ~/.config/opencode/skills/audit-fix-loop-v3/
git clone https://github.com/ailyedu2030/audit-fix-loop.git \
  ~/.config/opencode/skills/audit-fix-loop-v3
```

Or symlink:

```bash
ln -s /path/to/audit-fix-loop-v3 ~/.config/opencode/skills/audit-fix-loop-v3
```

### Requirements

- `jq` (preferred) **or** `python3` (fallback for `tools/convergence-check.sh`)
- `git` (for diff anchoring + SBL commit validation)
- Network access for `webfetch` (AI provider docs, OWASP, MDN, PostgreSQL docs, etc.)

Verify:

```bash
bash ~/.config/opencode/skills/audit-fix-loop-v3/tools/convergence-check.sh \
  --findings-db=/tmp/test-findings.json \
  --first-round-total=50 \
  /tmp/test-current.json /tmp/test-prev.json 5
```

---

## Usage

### Quick start (3 files or fewer)

```
"帮我看代码"
```

Default: `quick` mode (15–30 min). Reply "全面" to upgrade to `continuous`.

### Modes

| Mode | When | Duration |
|------|------|----------|
| `quick` | ≤3 file small changes | 15–30 min |
| `deep` | Cross-module / security | 1–4 h |
| `continuous` | Full zero-defect | 2–8 h |
| `incremental` | Have baseline, modifying 1–3 files | 15–30 min |
| `emergency` | P0 blocker | Fix immediately, 24h `continuous` follow-up |

### Incremental mode

1. Run `git diff` to identify change set
2. Spawn Functional + Security agents (2 in parallel)
3. Load SBL cache, verify `git_commit`, if changes ∩ SBL ≠ ∅ → upgrade to `deep`
4. After 3 consecutive incremental → force `deep`

### Convergence check

After each round, run the convergence tool:

```bash
bash tools/convergence-check.sh \
  --findings-db=.audit-cache/findings.json \
  --first-round-total=<N> \
  --webfetch-trace=.audit-cache/webfetch-trace.jsonl \
  --sbl=.audit-cache/sbl-v3.json \
  --smoke-test=.audit-cache/smoke-test-{round}.json \
  .audit-cache/findings-round-{N}.json \
  .audit-cache/findings-round-{N-1}.json \
  {N}
```

Exit codes:
- `0` = converged (then run Meta-Review)
- `1` = continue (more rounds needed)
- `2` = escalate (≥8 rounds, see `escalation-{round}.json`)
- `3` = error (missing arg, broken JSON, invalid reason)

### Escalation

If 8+ rounds without convergence, see `.audit-cache/escalation-{round}.json` for
suggestion (`downgrade to quick` / `expand budget` / `human intervention`).
The skill pauses — it does NOT auto-continue.

---

## File structure

```
audit-fix-loop-v3/
├── SKILL.md                                      # 222 lines: 7 Phases + 5.5 + 1.0
├── README.md                                     # this file
└── tools/
    ├── convergence-check.sh                      # 434 lines: convergence tool v3.3
    ├── fix-impact-matrix-template.yaml           # 46 lines: per-fix tracking
    └── sbl-functional-template.md                # 34 lines: Phase 1.1 template
```

### SKILL.md

The authoritative definition. Frontmatter is parsed by skill loaders:

```yaml
---
name: audit-fix-loop-v3
version: 3.3.0
description: 系统性零缺陷审查与修复。结果驱动收敛、运行时冒烟、预查询清单、3层根因追问、缓存自动清理。所有 P0~P3 必修。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Task, WebFetch, skill]
supersedes: [audit-fix-verify]
---
```

### tools/convergence-check.sh

Decides `converged` / `continue` / `escalate` / `error` after each round.
Implements v3.3 logic: result-driven threshold, fix_verified exclusion, P0/P1
strict check, cannot_fix_reason whitelist, SBL git_commit validation, cache
size check, escalation JSON output.

### Templates

- `fix-impact-matrix-template.yaml` — Track each fix's blast radius before applying
- `sbl-functional-template.md` — Phase 1.1 functional flow template

---

## Cache layout

Generated under `.audit-cache/` during execution:

```
.audit-cache/
├── sbl-v3.json                          # Single source of truth (NEVER deleted)
├── pre-query-{round}.json               # Phase 1.0 mandatory pre-queries
├── findings-round-{N}.json              # Per-round findings
├── webfetch-trace.jsonl                 # All webfetch URLs (anti-forgery)
├── contract-{round}.json                # Phase 1.3 contract matrix
├── contract-check-{round}.json          # Phase 5 contract verification
├── fix-impact/                          # Per-fix impact matrices
├── smoke-test-{round}.json              # Phase 5.5 runtime smoke results
├── convergence-log.jsonl                # Per-round convergence decisions
└── escalation-{round}.json              # ≥8 round escalation report
```

Auto-cleanup: >100MB triggers warning, last 3 rounds retained.
`webfetch-trace.jsonl` >5000 lines → archived.

---

## Migration from v2 (audit-fix-verify)

v2 is `status: deprecated`. Migrate:

1. Replace skill directory
2. Update agent prompts to reference `audit-fix-loop-v3` instead of `audit-fix-verify`
3. Any `findings-round-N.json` files are compatible (same severity schema)
4. SBL cache (`sbl-v3.json`) replaces v2's SBL v2 (`sbl.json`)
5. Run with `audit-fix-loop-v3` trigger phrases: "audit"/"全面"/"零缺陷"

### Breaking changes v2 → v3

- Added Phase 1.0 (mandatory pre-query) — was optional in v2
- Added Phase 5.5 (runtime smoke) — was optional in v2
- Convergence threshold changed: 2 consecutive empty rounds → ≤10% of first round
- cannot_fix_reason enforced as whitelist (was freeform in v2)
- TOOL_ACTIVITY log mandatory (was optional in v2)

---

## Changelog

### v3.3.0 (2026-06-17)

- **SKILL.md optimized**: 895 → 222 lines without functional loss
- **convergence-check.sh v3.3**: 268 → 434 lines, implements result-driven
  convergence + fix_verified exclusion + cannot_fix whitelist + SBL commit
  validation + escalation JSON
- **Phase 5.5 mandatory runtime smoke** (catches 30s→120s timeout regression)
- **Phase 1.0 mandatory pre-query** (replaces "guess provider timeout")
- **8 validation tests** for convergence-check.sh (all pass)

### v3.0–v3.2

Earlier iterations. Not published.

### v2.x (audit-fix-verify, deprecated)

Original 7-phase design. Replaced by v3.

---

## License

MIT

---

## Maintainers

- [@ailyedu2030](https://github.com/ailyedu2030)

Issues and PRs welcome. For security-related issues, please email first.

---

## Related

- [English-CET-main](https://github.com/ailyedu2030/English-CET) — production
  codebase where this skill is battle-tested
- OpenCode skills: see [OpenCode docs](https://opencode.ai/docs)