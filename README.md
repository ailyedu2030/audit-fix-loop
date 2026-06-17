# super-fix

Systematic zero-trust audit & fix loop for AI coding agents.
**30 tools, 7 specialized agents, 6-layer defense pipeline.**

[![version](https://img.shields.io/badge/version-4.3.0-blue)](SKILL.md)
[![tools](https://img.shields.io/badge/tools-30-orange)](tools/)
[![agents](https://img.shields.io/badge/agents-7-green)](agents/)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## What it does

Finds bugs that static analysis misses — concurrency races, state machine
violations, resource leaks — then **fixes them** and **proves the fix works**.

Three independent layers:

| Layer | How | Why it works |
|-------|-----|--------------|
| **Subsystem** | Auto-detect 13 code subsystems, trace 32 cross-file data flows | Root causes cross files; file-local audit misses them |
| **Adversarial** | 5 Blue Team agents (independent lenses) + Red Team (M3 cross-model attack) | No Bandwagon. Different models catch different things |
| **Learning** | After-Action Review → blind spot registry → method updates | Each audit makes the next one smarter |

Backed by a 6-layer defense pipeline (constrained decoding → schema validation/retry →
tool standardization → logit guard → multi-agent protocol → circuit breaker).

## Quick Start

```bash
git clone https://github.com/ailyedu2030/audit-fix-loop.git ~/.config/opencode/skills/super-fix

# Run a full audit
bash ~/.config/opencode/skills/super-fix/tools/v4-audit.sh
```

## Agents

| Agent | Model | Specializes in |
|-------|-------|---------------|
| `audit-blue-security` | M2.7 | Auth, authz, CSRF, injection, secrets |
| `audit-blue-concurrency` | M2.7 | Race conditions, deadlocks, TOCTOU, lost updates |
| `audit-blue-dataflow` | M2.7 | Type coercion, null propagation, cross-service validation |
| `audit-blue-error` | M2.7 | Swallowed errors, stack leaks, missing graceful degradation |
| `audit-blue-resource` | M2.7 | Connection/timer/handle leaks, shutdown cleanup |
| `audit-red-team` | **M3** (cross-model) | Attacks Blue findings: trace survival → mutation → cousin → verdict |
| `audit-aar` | M2.7 | After-action review: what worked, what missed, what to improve |

Each agent runs independently with its own prompt and briefing JSON.
No shared context — no Bandwagon effect.

## Key Tools

| Tool | What it does |
|------|-------------|
| `v4-audit.sh` | Full orchestrator: all phases in order with gate enforcement |
| `init-audit.sh` | Phase 0: create state machine, discover test layers, baseline check |
| `subsystem-manifest.sh` | Auto-partition codebase into 13 subsystems |
| `flow-trace.ts` | Build cross-subsystem data flow graph (32 flows, handles @/ alias) |
| `generate-blind-briefings.ts` | Create 5-7 independent agent briefings (round-robin lens assignment) |
| `run-blue-agent.ts` | Spawn a Blue Team agent, validate output, retry |
| `red-team-runner.ts` | M3 cross-model verification: `response_format: json_object`, 3x retry |
| `validate-retry.ts` | Schema validation + JSON repair + exponential backoff retry |
| `validate-causal-chain.sh` | Reject shallow findings (chain <3 steps, root_cause restating description) |
| `after-action-review.ts` | 4 mandatory questions → method updates → blind spot registry |
| `gate-check.sh` | Phase transition enforcement — no bypass |

Full list: `tools/README.md`.

## Real-world Results (English-CET, 30k LoC)

| Metric | Value |
|--------|-------|
| Findings discovered | 22 (1 P0, 7 P1, 14 P2) |
| Red Team cousin bugs found | 14 (Blue Team missed) |
| Blue Team false positives filtered | 3 |
| Bugs fixed | 19 across 15 files |
| Detection rate improvement | 29% → 75% (+46% after AAR) |
| Tests passing | 489/489 |
| Cross-subsystem detection | 77% (target 30%) |

## Requirements

- `jq` or `python3` (shell tools)
- `git` (diff anchoring, state machine persistence)
- MiniMax API key (for Red Team M3 cross-model attacks; Blue Team runs on M2.7)

## Install

```bash
git clone https://github.com/ailyedu2030/audit-fix-loop.git \
  ~/.config/opencode/skills/super-fix
```

## Docs

| File | Purpose |
|------|---------|
| `SKILL.md` (122 lines) | Agent-callable skill definition |
| `CHANGELOG.md` | Full version history (v3.3 → v4.3.0) |
| `docs/v4-addendum.md` | v4 architecture, success criteria, gold set |
| `docs/templates/test-template.ts` | Phase 4.5 test authoring template |
| `tools/README.md` | Tool documentation (parameters, exit codes) |

## License

MIT © ailyedu2030
