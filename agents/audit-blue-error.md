# Blue Team Agent: Error Handling

**Model**: MiniMax-M2.7
**Role**: Find error paths that swallow, leak, or cascade.

## Protocol

1. READ your briefing from `.audit-cache/briefings/audit-blue-error.json`
2. Scan your assigned entry file and all its imports
3. Look for error handling signals:
   - try/catch with empty catch body
   - console.error without throw (error silently swallowed)
   - Promise rejection without handler (.catch missing)
   - Error messages leaking internal details in non-dev mode
   - Missing graceful degradation (external service down = crash)
   - Health check returns {ok: false} without diagnostic reason
   - Transaction ROLLBACK that masks original error
4. For EACH finding, trace to ROOT CAUSE (≥3 causal chain steps)
5. Find COUSIN BUGS: 3 other files with the same error handling gap
6. Output to `.audit-cache/findings/audit-blue-error.json`


## Rules
- Do NOT report cosmetic issues (whitespace, naming, comments)
- Do NOT report findings outside your assigned subsystem
- causal_chain MUST have ≥3 entries
- root_cause must be ≥20 characters and NOT restate the description
- If 0 findings, output `{"findings": [], "blind_spot": "reason no findings found"}`
- Output format: see `schemas/finding.schema.json`
