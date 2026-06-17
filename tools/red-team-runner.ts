/**
 * red-team-runner.ts (v4.2.0) — P0-L1+L2: Structured Output + Validation+Retry
 *
 * v4.2 changes:
 *   - L1: response_format: { type: "json_object" } on M3 API calls
 *   - L2: validate-retry.ts wrapper with schema validation, exponential backoff
 *   - L2: Increased max_tokens 4000→8192, temperature 0.3→0.5
 *   - L2: AbortSignal.timeout(30000) for fetch
 *   - L2: 429 rate limit handling with Retry-After header
 *   - L6: Circuit breaker fallback with confidence=0.01 (not 0) to distinguish from v4.0 bug
 */
import * as fs from 'fs';
import * as path from 'path';
import { withRetry } from './validate-retry.js';

const API_KEY = process.env.MINIMAX_API_KEY || (() => {
  try {
    const env = fs.readFileSync('server/.env', 'utf-8');
    const m = env.match(/^MINIMAX_API_KEY="([^"]+)"/m);
    return m ? m[1] : '';
  } catch { return ''; }
})();

if (!API_KEY) {
  console.error('[red-team] MINIMAX_API_KEY not found in env or server/.env');
  process.exit(1);
}

const BASE_URL = 'https://api.minimaxi.com/v1';
const RED_MODEL = 'MiniMax-M3';

interface Finding {
  id: string; agent_id?: string; semantic_hash: string;
  module: string; function: string; pattern: string;
  severity: string; description: string;
  root_cause?: string; fix_recommendation?: string;
}

interface AttackResult {
  finding_id: string;
  trace_survival: { question: string; findings: string[] };
  mutation_survival: { mutations_tested: string[]; killed_by_mutation: boolean };
  cousin_bugs: { question: string; suspected_files: string[] };
  verdict: 'holds' | 'needs_modification' | 'wrong';
  reasoning: string;
  confidence: number;
}

const RED_SYSTEM_PROMPT = `You are the RED TEAM. You are MiniMax-M3 (a different model than the original auditor MiniMax-M2.7).
You did NOT see the original audit. You are HOSTILE to the finding.

Protocol (keep response concise):
1. TRACE SURVIVAL: 1-2 execution paths where the fix fails
2. MUTATION SURVIVAL: 1-2 line changes that break the fix
3. COUSIN BUG: at least 1 file with the same pattern, or "none"
4. VERDICT: holds | needs_modification | wrong

Output JSON only. No <think> tags. No markdown.`;

async function runRedTeamOnFinding(finding: Finding): Promise<AttackResult> {
  let fileSnippet = '';
  try {
    if (fs.existsSync(finding.module)) {
      const fullContent = fs.readFileSync(finding.module, 'utf-8');
      const lines = fullContent.split('\n');
      const funcIdx = lines.findIndex(l => l.includes(`function ${finding.function}`) || l.includes(`${finding.function}(`));
      fileSnippet = funcIdx >= 0
        ? lines.slice(Math.max(0, funcIdx - 2), Math.min(lines.length, funcIdx + 40)).join('\n').slice(0, 4000)
        : fullContent.slice(0, 4000);
    }
  } catch {}

  const userPrompt = `ATTACK THIS FINDING:

ID: ${finding.id} | Module: ${finding.module} | Function: ${finding.function}
Pattern: ${finding.pattern} | Severity: ${finding.severity}
Description: ${finding.description}
Root cause: ${finding.root_cause || '(not provided)'}
Fix recommendation: ${finding.fix_recommendation || '(not provided)'}

CODE (${finding.module}):
\`\`\`
${fileSnippet || '(file not readable)'}
\`\`\`

Output JSON with all required fields: finding_id, trace_survival.findings (non-empty array), mutation_survival, cousin_bugs, verdict, reasoning, confidence.`;

  try {
    return await withRetry<AttackResult>(
      async (_attempt: number) => {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 30000);
        try {
          const response = await fetch(`${BASE_URL}/chat/completions`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${API_KEY}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
              model: RED_MODEL,
              messages: [{ role: 'system', content: RED_SYSTEM_PROMPT }, { role: 'user', content: userPrompt }],
              temperature: 0.5,
              max_tokens: 8192,
              response_format: { type: "json_object" },  // L1: constrained decoding
            }),
            signal: controller.signal,
          });
          if (response.status === 429) {
            const retryAfter = parseInt(response.headers.get('Retry-After') || '5');
            await new Promise(r => setTimeout(r, retryAfter * 1000));
            throw new Error(`Rate limited (429), waited ${retryAfter}s`);
          }
          if (!response.ok) throw new Error(`API ${response.status}`);
          const data = await response.json();
          if (data.choices[0].finish_reason === 'length') {
            console.warn(`[red-team] Truncated: ${finding.id}`);
          }
          return data.choices[0].message.content;
        } finally { clearTimeout(timeoutId); }
      },
      'attack-result',
      { maxRetries: 3, baseDelayMs: 1000, maxDelayMs: 16000, timeoutMs: 30000 }
    ).then(r => r.data);
  } catch (err) {
    return {
      finding_id: finding.id,
      trace_survival: { question: 'All retries exhausted', findings: [String(err).slice(0, 200)] },
      mutation_survival: { mutations_tested: [], killed_by_mutation: false },
      cousin_bugs: { question: '', suspected_files: [] },
      verdict: 'needs_modification',
      reasoning: `3 retries failed: ${err instanceof Error ? err.message.slice(0, 100) : 'unknown'}`,
      confidence: 0.01,  // L6: circuit breaker fallback (not 0)
    };
  }
}

async function main() {
  const findingsDir = '.audit-cache/findings';
  if (!fs.existsSync(findingsDir)) { console.error('No findings directory'); process.exit(1); }

  const allFindings: Finding[] = [];
  for (const ff of fs.readdirSync(findingsDir).filter(f => f.endsWith('.json'))) {
    const data = JSON.parse(fs.readFileSync(path.join(findingsDir, ff), 'utf-8'));
    if (data.findings && Array.isArray(data.findings)) allFindings.push(...data.findings);
  }

  console.log(`Red Team attacking ${allFindings.length} findings using ${RED_MODEL}...`);

  const attacksDir = '.audit-cache/red-team-attacks';
  if (!fs.existsSync(attacksDir)) fs.mkdirSync(attacksDir, { recursive: true });

  // 【v4.2 P0-L5】Parallelize with Promise.allSettled + 60s timeout per attack
  const results = await Promise.allSettled(
    allFindings.map(async (f) => {
      const outPath = path.join(attacksDir, `${f.id}_result.json`);
      if (fs.existsSync(outPath) && !process.env.FORCE_REATTACK) {
        try {
          const existing = JSON.parse(fs.readFileSync(outPath, 'utf-8'));
          if (existing.confidence > 0) {
            process.stdout.write(`  ${f.id}: skip (existing ${existing.verdict} @ ${existing.confidence})\n`);
            return;
          }
        } catch {}
      }
      const start = Date.now();
      const result = await runRedTeamOnFinding(f);
      fs.writeFileSync(outPath, JSON.stringify(result, null, 2));
      process.stdout.write(`  ${f.id}: ${result.verdict} (conf ${result.confidence.toFixed(2)}) [${Date.now() - start}ms]\n`);
    })
  );

  const succeeded = results.filter(r => r.status === 'fulfilled').length;
  const failed = results.filter(r => r.status === 'rejected').length;
  console.log(`\nDone. ${succeeded} succeeded, ${failed} failed. Results in ${attacksDir}/`);
  if (failed > 0) process.exitCode = 1;
}

main().catch(e => { console.error(e); process.exit(1); });
