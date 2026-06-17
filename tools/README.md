# Tools

Mechanical enforcement utilities for audit-fix-loop-v3.

All tools exit with structured JSON to stderr/stdout for machine
parsing. Exit codes: `0` = pass, `1` = fail, `2` = error.

## Core (v3.3)

### `convergence-check.sh`

Decides `converged` / `continue` / `escalate` / `error` after each round.

Implements: result-driven threshold, `fix_verified` exclusion, P0/P1 strict
check, cannot_fix_reason whitelist, SBL git_commit validation, cache size
check, escalation JSON output.

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

Exit codes: `0`=converged, `1`=continue, `2`=escalate, `3`=error

## Mechanical Gates (v3.4)

### `gate-check.sh`

Phase transition enforcement. Replaces trust with verification.

```bash
bash tools/gate-check.sh --required-phase=PHASE_7_FINAL .audit-cache/audit_state.json
# exit 0 = PASS, 1 = FAIL, 2 = ERROR
```

Validates:
- `phases_passed` sequence (can't enter Phase N without Phases 0..N-1)
- `current_phase` matches required
- Phase-specific requirements:
  - PHASE_0: state machine initialized
  - PHASE_1: pre-query JSON + SBL files exist
  - PHASE_5: phases_passed[PHASE_4] = true
  - PHASE_5_5: smoke test results pass
  - PHASE_6: convergence-check.sh exit 0 recorded
  - PHASE_6_5: Devil's Advocate ran
  - PHASE_7: all findings in terminal state, cannot_fix whitelisted

### `verify-report.sh`

Final report reverse-validation. Catches fabricated "zero defect" claims.

```bash
bash tools/verify-report.sh \
  --report=.audit-cache/final-report.md \
  --state=.audit-cache/audit_state.json
```

Parses Executive Layer table:
| 严重度 | 发现 | 修复 | 验证 | cannot_fix | deferred |

Compares against `audit_state.json` counts. Returns FAIL if mismatch.

### `zero-defect-check.sh`

0 open + 0 fixing + all fixed verified + cannot_fix whitelisted.

```bash
bash tools/zero-defect-check.sh --state=.audit-cache/audit_state.json
```

## Test Pyramid (v3.5)

### `test-coverage-check.sh`

Every verified finding MUST have `test_ids` + `mutation_killed=true`.

```bash
bash tools/test-coverage-check.sh --state=.audit-cache/audit_state.json
```

Returns:
- `pass`: 0 errors
- `warn`: warnings (e.g. test deferred with `test_na_reason`)
- `fail`: verified finding without `test_ids` or with `mutation_killed=false`

### `chaos-test.sh`

Fault injection scenarios. Verifies recovery paths exist.

```bash
bash tools/chaos-test.sh \
  --target=<module> \
  --scenarios=kill_mid_request,restart_during_session,concurrent_feedback,ai_timeout,db_slow \
  .audit-cache/audit_state.json
```

Scenarios:
1. `kill_mid_request` — long-poll, kill process, check orphan state
2. `restart_during_session` — restart server, verify session recovery
3. `concurrent_feedback` — 20+ concurrent submissions, check DB consistency
4. `ai_timeout` — slow AI provider, verify fallback path
5. `db_slow` — slow DB response, verify timeout handling

### `mutation-test.sh`

Reverse-validate test effectiveness. Stub for real mutation framework.

```bash
bash tools/mutation-test.sh \
  --state=.audit-cache/audit_state.json \
  --test-command="npm run test:unit" \
  --mutation-scope=findings
```

Real mutation requires `npm install --save-dev @stryker-mutator/core`.
Tool detects and runs Stryker for each fix_evidence file.

### `dynamic-test-runner.sh`

Run full test suite (not just smoke).

```bash
bash tools/dynamic-test-runner.sh --state=.audit-cache/audit_state.json
```

Detects and runs:
- `test:unit`
- `test:integration`
- `test:property`
- `test:contract`
- `test:e2e`
- `test` (catch-all)

Writes `dynamic-test-{round}.json` with per-suite results.

## Templates

### `fix-impact-matrix-template.yaml`

Per-fix tracking matrix. Fill in before applying each fix.

```yaml
fix_id: "R{ROUND}-{CATEGORY}-{N}"
severity: P0
category: security
change:
  before: "..."
  after: "..."
  files:
    - path: "src/xxx.ts"
      lines: "123-125"
      diff: "+1 -2"
affected_paths:
  - description: "..."
    impact: "..."
regression_check:
  commands:
    - "npm run lint"
    - "npx tsc --noEmit"
test_command: "..."
```

### `sbl-functional-template.md`

Phase 1.1 functional flow template. Defines:

- Step-by-step data flow (user → frontend → backend → DB)
- State machine diagram
- Data flow diagram
- File mapping (SBL step ↔ source file)

## Common Patterns

### Phase transition sequence

```bash
# After Phase N work, before declaring "done":
bash tools/gate-check.sh --required-phase=PHASE_$N --action=exit .audit-cache/audit_state.json
# exit 0 = ready for Phase N+1
# exit 1 = blocked, fix issues
# exit 2 = broken state, debug

# Then for next phase:
bash tools/gate-check.sh --required-phase=PHASE_$((N+1)) --action=enter .audit-cache/audit_state.json
```

### Convergence check per round

```bash
# 1. Run convergence (v3.3 logic)
bash tools/convergence-check.sh \
  --findings-db=.audit-cache/audit_state.json \
  --first-round-total=21 \
  .audit-cache/findings-round-2.json \
  .audit-cache/findings-round-1.json \
  2

# 2. If exit 0 (converged), run v3.5 zero-trust gates:
bash tools/test-coverage-check.sh --state=.audit-cache/audit_state.json
bash tools/zero-defect-check.sh --state=.audit-cache/audit_state.json
bash tools/verify-report.sh --report=.audit-cache/final-report.md --state=.audit-cache/audit_state.json
bash tools/dynamic-test-runner.sh --state=.audit-cache/audit_state.json
bash tools/chaos-test.sh --state=.audit-cache/audit_state.json
bash tools/mutation-test.sh --state=.audit-cache/audit_state.json
```

### Final Phase 7 entry

```bash
bash tools/gate-check.sh --required-phase=PHASE_7_FINAL .audit-cache/audit_state.json
# All above must pass
```

## Dependencies

| Tool | jq | python3 | git | fast-check | Stryker |
|------|-----|---------|-----|------------|---------|
| convergence-check.sh | preferred | fallback | yes | - | - |
| gate-check.sh | - | yes | - | - | - |
| verify-report.sh | - | yes | - | - | - |
| zero-defect-check.sh | - | yes | - | - | - |
| test-coverage-check.sh | - | yes | - | - | - |
| chaos-test.sh | - | yes | - | - | - |
| mutation-test.sh | - | yes | - | - | optional |
| dynamic-test-runner.sh | - | yes | - | optional | - |

## Adding New Tools

When adding a new tool:

1. Follow the JSON-output convention (decision + reason on stdout)
2. Use exit codes: 0/1/2 (pass/fail/error) consistently
3. Be self-contained (don't depend on global state)
4. Add an entry to this README
5. Add to SKILL.md phase progression
6. Update gate-check.sh to call it
7. Add to test pyramid if applicable

## Versioning

Tools are versioned with the parent skill. Breaking changes require
major version bump.
