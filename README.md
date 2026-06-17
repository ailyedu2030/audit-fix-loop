# super-fix

Systematic zero-trust audit & fix loop for AI coding agents.
**28 tools, 5 independent lenses, 6-layer defense pipeline.**

[![version](https://img.shields.io/badge/version-5.3.0-blue)](SKILL.md)
[![tools](https://img.shields.io/badge/tools-28-orange)](tools/)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## What it does

Finds bugs that static analysis misses — concurrency races, state machine
violations, resource leaks — then **fixes them** and **proves the fix works**.

Three independent layers:

| Layer | How | Why it works |
|-------|-----|--------------|
| **Subsystem** | Auto-detect 14 code subsystems, trace 34 cross-file data flows | Root causes cross files; file-local audit misses them |
| **Adversarial** | 5 general agents (independent lens prompts) + Red Team (M3 cross-model attack) | No Bandwagon. Different perspectives catch different things |
| **Learning** | After-Action Review → blind spot registry → method updates | Each audit makes the next one smarter |

Backed by a 6-layer defense pipeline (constrained decoding → schema validation/retry →
tool standardization → depth gate → cross-model Red Team → circuit breaker).

## Quick Start

```bash
git clone https://github.com/ailyedu2030/audit-fix-loop.git ~/.config/opencode/skills/super-fix

# Run a full audit
bash ~/.config/opencode/skills/super-fix/tools/v4-audit.sh
```

## 5 Lenses (Blue Team)

The orchestrator spawns 5 **general** agents (Task subagent_type=general), each with a lens-specific prompt. No shared briefing = no Bandwagon.

| Lens | Focus |
|------|-------|
| `security` | Auth, authz, CSRF, injection, JWT, secrets |
| `concurrency` | Race conditions, deadlocks, TOCTOU, lost updates |
| `dataflow` | Type coercion, null propagation, cross-service validation |
| `error` | Swallowed errors, stack leaks, missing graceful degradation |
| `resource` | Connection/timer/handle leaks, shutdown cleanup, abort |

Red Team: M3 cross-model (4-step attack: trace survival → mutation → cousin → verdict).

## Key Tools

| Tool | What it does |
|------|-------------|
| `v4-audit.sh` | Full orchestrator: all phases in order with gate enforcement |
| `init-audit.sh` | Phase 0: create state machine, discover test layers, baseline check |
| `subsystem-manifest.sh` | Auto-partition codebase into 14 subsystems |
| `flow-trace.ts` | Build cross-subsystem data flow graph (34 flows, handles @/ alias) |
| `generate-blind-briefings.ts` | Create 5 lens-specific briefings (round-robin assignment) |
| `red-team-runner.ts` | M3 cross-model verification: `response_format: json_object`, 3x retry |
| `validate-retry.ts` | Schema validation + JSON repair + exponential backoff retry |
| `validate-causal-chain.sh` | Reject shallow findings (chain <3 steps, root_cause restating description) |
| `after-action-review.ts` | 4 mandatory questions → method updates → blind spot registry |
| `gate-check.sh` | Phase transition enforcement — no bypass |

Full list: `tools/README.md`.

## Real-world Results (English-CET, 30k LoC, v5.0 verified)

| Metric | Value |
|--------|-------|
| Findings discovered (v4.0 cycle) | 22 (1 P0, 7 P1, 14 P2) |
| Latest cycle (v5.0) | 35 findings, 16/16 pass causal chain depth gate |
| Depth validation | v5.0: 100% pass vs v4.0: 0% pass (proves gate effectiveness) |
| Red Team cousin bugs found | 14 (Blue Team missed) |
| Bugs fixed | 19 across 16 files |
| Detection rate improvement | 29% → 75% (+46% after AAR) |
| Tests passing | 489/489 |

## Requirements

- `jq` or `python3` (shell tools)
- `git` (diff anchoring, state machine persistence)
- MiniMax API key (for Red Team M3 cross-model attacks)

## Install

```bash
git clone https://github.com/ailyedu2030/audit-fix-loop.git \
  ~/.config/opencode/skills/super-fix
```

## Docs

| File | Purpose |
|------|---------|
| `SKILL.md` (115 lines) | Agent-callable skill definition |
| `CHANGELOG.md` | Full version history (v3.3 → v5.3) |
| `docs/v4-addendum.md` | v4 architecture, success criteria, gold set |
| `docs/templates/test-template.ts` | Phase 4.5 test authoring template |
| `tools/README.md` | Tool documentation (parameters, exit codes) |

## License

MIT © ailyedu2030
