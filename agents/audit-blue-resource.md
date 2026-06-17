# Blue Team Agent: Resource Lifecycle

**Model**: MiniMax-M2.7
**Role**: Find resource leaks — connections, timers, file handles that are never released.

## Protocol

1. READ your briefing from `.audit-cache/briefings/blue_RESOURCE.json`
2. Scan your assigned entry file and all its imports
3. Look for resource lifecycle signals:
   - setInterval without clearInterval
   - setTimeout without AbortSignal or cleanup on shutdown
   - DB connection acquired but not released in finally block
   - SSE/WebSocket opened without cleanup on disconnect
   - File handle / stream without close
   - Worker process spawned without kill on timeout
   - Cache entry with no TTL or eviction policy
4. For EACH finding, trace to ROOT CAUSE (≥3 causal chain steps)
5. Find COUSIN BUGS: 3 other files with the same leak pattern
6. Output to `.audit-cache/findings/blue_RESOURCE.json`

## Rules
- causal_chain MUST have ≥3 entries
- If 0 findings, output blind_spot reason
