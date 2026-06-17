/**
 * red-team-runner.ts (v4.0.0)
 * ACTUALLY RUN the Red Team attacks using MiniMax M3 (vs M2.7)
 *
 * This is the live integration of the red team protocol.
 * For each finding, run 4-step attack with M3.
 */
import * as fs from 'fs';
import * as path from 'path';

const API_KEY = process.env.MINIMAX_API_KEY || (() => {
  const env = fs.readFileSync('server/.env', 'utf-8');
  const m = env.match(/^MINIMAX_API_KEY="([^"]+)"/m);
  return m ? m[1] : '';
})();
const BASE_URL = 'https://api.minimaxi.com/v1';
const RED_MODEL = 'MiniMax-M3'; // Different from Blue Team (M2.7)

interface Finding {
  id: string;
  agent_id?: string;
  semantic_hash: string;
  module: string;
  function: string;
  pattern: string;
  severity: string;
  description: string;
  root_cause?: string;
  fix_recommendation?: string;
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

Your job: ATTACK the finding, not validate it. If you cannot find flaws, SAY SO EXPLICITLY.

Protocol (keep response under 150 words total):
1. TRACE SURVIVAL: 1-2 short paths
2. MUTATION SURVIVAL: 1-2 mutations
3. COUSIN BUG: 1 file or "none"
4. VERDICT: holds | needs_modification | wrong

Output JSON only, no markdown, no prose outside JSON. BE CONCISE.`;

async function runRedTeamOnFinding(finding: Finding): Promise<AttackResult> {
  // Read the file content to inject into the prompt (truncated to 2000 chars)
  let fileSnippet = '';
  try {
    if (fs.existsSync(finding.module)) {
      const fullContent = fs.readFileSync(finding.module, 'utf-8');
      const lines = fullContent.split('\n');
      const funcIdx = lines.findIndex(l => l.includes(`function ${finding.function}`) || l.includes(`${finding.function}(`));
      let snippet: string;
      if (funcIdx >= 0) {
        const start = Math.max(0, funcIdx - 2);
        const end = Math.min(lines.length, funcIdx + 40);
        snippet = lines.slice(start, end).join('\n');
      } else {
        snippet = fullContent.slice(0, 2000);
      }
      // Truncate to 4000 chars max (increased per AAR method update)
      fileSnippet = snippet.slice(0, 4000);
    }
  } catch (e) {
    // file not readable
  }

  const userPrompt = `ATTACK THIS FINDING:

ID: ${finding.id}
Module: ${finding.module}
Function: ${finding.function}
Pattern: ${finding.pattern}
Severity: ${finding.severity}
Description: ${finding.description}
Root cause claim: ${finding.root_cause || '(not provided)'}
Fix recommendation: ${finding.fix_recommendation || '(not provided)'}

CODE SNIPPET (from ${finding.module}):
\`\`\`
${fileSnippet || '(file not readable)'}
\`\`\`

You do NOT have file access. Use the code above to run the 4-step attack.
Be adversarial. If you cannot find flaws, SAY SO EXPLICITLY (don't pad with "looks good").

OUTPUT (JSON only):
{
  "finding_id": "${finding.id}",
  "trace_survival": {
    "question": "Under what execution path does the bug STILL occur after the fix?",
    "findings": ["path 1", "path 2"]
  },
  "mutation_survival": {
    "mutations_tested": ["mutation 1", "mutation 2"],
    "killed_by_mutation": true|false
  },
  "cousin_bugs": {
    "question": "What adjacent code shares this root cause?",
    "suspected_files": ["file1.ts", "file2.ts"]
  },
  "verdict": "holds" | "needs_modification" | "wrong",
  "reasoning": "Why this verdict",
  "confidence": 0.0-1.0
}`;

  try {
    const response = await fetch(`${BASE_URL}/chat/completions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: RED_MODEL,
        messages: [
          { role: 'system', content: RED_SYSTEM_PROMPT },
          { role: 'user', content: userPrompt },
        ],
        temperature: 0.3,
        max_tokens: 4000,
      }),
    });

    if (!response.ok) {
      throw new Error(`API ${response.status}: ${await response.text()}`);
    }

    const data = await response.json();
    let content = data.choices[0].message.content;

    // Strip <think>...</think> blocks (M3 uses chain-of-thought)
    content = content.replace(/<think>[\s\S]*?<\/think>/g, '');
    // Strip markdown code fences
    content = content.replace(/```json\s*/g, '').replace(/```\s*/g, '');

    // Find the outermost { ... } and try to parse
    const firstBrace = content.indexOf('{');
    if (firstBrace === -1) {
      throw new Error('No JSON in response: ' + content.slice(0, 200));
    }
    let candidate = content.slice(firstBrace);
    // Find matching close brace with string-awareness
    let depth = 0;
    let endIdx = -1;
    let inString = false;
    let escape = false;
    for (let i = 0; i < candidate.length; i++) {
      const c = candidate[i];
      if (escape) { escape = false; continue; }
      if (c === '\\') { escape = true; continue; }
      if (c === '"') { inString = !inString; continue; }
      if (inString) continue;
      if (c === '{') depth++;
      if (c === '}') {
        depth--;
        if (depth === 0) { endIdx = i + 1; break; }
      }
    }
    if (endIdx === -1) {
      throw new Error('No matching close brace: ' + content.slice(0, 500));
    }
    const jsonStr = candidate.slice(0, endIdx);
    try {
      return JSON.parse(jsonStr);
    } catch (e) {
      // Try to repair common issues (trailing comma, unescaped quotes)
      const repaired = jsonStr
        .replace(/,(\s*[}\]])/g, '$1');
      return JSON.parse(repaired);
    }
  } catch (err) {
    return {
      finding_id: finding.id,
      trace_survival: { question: 'API error', findings: [String(err).slice(0, 200)] },
      mutation_survival: { mutations_tested: [], killed_by_mutation: false },
      cousin_bugs: { question: '', suspected_files: [] },
      verdict: 'needs_modification',
      reasoning: 'Red team API call failed; treating as needs_modification (manual review needed)',
      confidence: 0,
    };
  }
}

async function main() {
  const findingsDir = '.audit-cache/findings';
  if (!fs.existsSync(findingsDir)) {
    console.error('No findings directory');
    process.exit(1);
  }

  const findingFiles = fs.readdirSync(findingsDir).filter(f => f.endsWith('.json'));
  const allFindings: Finding[] = [];
  for (const ff of findingFiles) {
    const data = JSON.parse(fs.readFileSync(path.join(findingsDir, ff), 'utf-8'));
    if (data.findings && Array.isArray(data.findings)) {
      allFindings.push(...data.findings);
    }
  }

  console.log(`Red Team attacking ${allFindings.length} findings using ${RED_MODEL}...`);

  const attacksDir = '.audit-cache/red-team-attacks';
  if (!fs.existsSync(attacksDir)) {
    fs.mkdirSync(attacksDir, { recursive: true });
  }

  for (const f of allFindings) {
    const outPath = path.join(attacksDir, `${f.id}_result.json`);
    if (fs.existsSync(outPath) && !process.env.FORCE_REATTACK) {
      const existing = JSON.parse(fs.readFileSync(outPath, 'utf-8'));
      // Skip if we have a real verdict (not API error)
      if (existing.verdict && existing.confidence !== 0 && existing.reasoning !== 'Red team API call failed; treating as needs_modification (manual review needed)') {
        process.stdout.write(`  ${f.id}: skip (existing ${existing.verdict} @ ${existing.confidence})\n`);
        continue;
      }
    }
    process.stdout.write(`  ${f.id}: `);
    const result = await runRedTeamOnFinding(f);
    fs.writeFileSync(outPath, JSON.stringify(result, null, 2));
    console.log(`${result.verdict} (confidence ${result.confidence})`);
  }

  console.log(`\nDone. Results in ${attacksDir}/`);
}

main().catch(e => { console.error(e); process.exit(1); });
