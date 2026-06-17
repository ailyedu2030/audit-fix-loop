/**
 * red-team-attack.ts (v4.0.0)
 * Red Team: independent model attacks the findings
 *
 * v3.7 vs v4:
 *   v3.7: Phase 6.5 "Devil's Advocate" = same LLM reviewing itself
 *   v4:   Red Team uses DIFFERENT MODEL (e.g., M3) + different prompt
 *         + blind briefing (sees only the diff, not the reasoning)
 *
 * Protocol:
 *   1. Red Team gets a finding + diff (no context)
 *   2. Red Team runs 4-step attack:
 *      a. Trace survival: under what execution does this fix still fail?
 *      b. Mutation survival: what 1-line change to the fix breaks it?
 *      c. Cousin bug: what adjacent bug shares this root cause but is not caught?
 *      d. Verdict: holds | needs_modification | wrong
 *   3. If "wrong" → reopen finding, return to Phase 4
 *   4. If "needs_modification" → append remediation, return to Phase 4.5
 *   5. If "holds" → mark as RED_TEAM_VERIFIED
 *
 * This is a SCRIPT (not yet integrated with API). It produces:
 *   - The protocol
 *   - The expected output format
 *   - Sample attacks for known finding types
 *
 * Full integration requires API client (see TODO at bottom).
 */
import * as fs from 'fs';
import * as path from 'path';

interface Finding {
  id: string;
  module: string;
  function: string;
  pattern: string;
  status: string;
  description?: string;
  fix_diff?: string;
}

interface RedTeamAttack {
  finding_id: string;
  trace_survival: {
    question: string;
    findings: string[];
  };
  mutation_survival: {
    mutations_tested: string[];
    killed_by_mutation: boolean;
  };
  cousin_bugs: {
    question: string;
    suspected_files: string[];
  };
  verdict: 'holds' | 'needs_modification' | 'wrong';
  reasoning: string;
  confidence: number;
}

const RED_TEAM_PROTOCOL = `
=== RED TEAM ATTACK PROTOCOL ===

You are the RED TEAM. You are a DIFFERENT model (M3) than the Blue Team (M2.7).
You did NOT see the original audit. You are hostile to the finding.

INPUT: A finding (id, module, function, pattern, fix diff)
GOAL: Prove the finding is wrong, incomplete, or has a hidden flaw.

STEP 1: TRACE SURVIVAL
  Question: "Under what execution path does the bug STILL occur after the fix?"
  Method:
    - Read the fix diff carefully
    - Identify all branches, error paths, async paths
    - For each path, ask: "Does the fix cover this path?"
  Output: List of paths the fix does NOT cover

STEP 2: MUTATION SURVIVAL
  Question: "What single-line change to the fix makes it stop working?"
  Method:
    - Mentally apply mutations:
      - Remove a guard
      - Flip a condition
      - Remove a lock
      - Swap a type
    - For each, does the test catch it?
  Output: Mutations that survive (i.e., test still passes)

STEP 3: COUSIN BUG
  Question: "What adjacent code shares this root cause but is not caught?"
  Method:
    - Identify the root cause
    - Search for similar patterns: same function shape, same data flow, same anti-pattern
    - List suspect files
  Output: Suspected files that may have the same bug

STEP 4: VERDICT
  Based on steps 1-3, classify:
  - "holds" — fix is correct AND no cousin bugs found
  - "needs_modification" — fix has gaps (specify which)
  - "wrong" — fix doesn't address root cause (reopen)

OUTPUT FORMAT (strict JSON):
{
  "finding_id": "F-001",
  "trace_survival": {
    "question": "...",
    "findings": ["path 1 not covered", "path 2 not covered"]
  },
  "mutation_survival": {
    "mutations_tested": ["remove guard", "flip condition"],
    "killed_by_mutation": true
  },
  "cousin_bugs": {
    "question": "...",
    "suspected_files": ["file1.ts", "file2.ts"]
  },
  "verdict": "holds",
  "reasoning": "Why this verdict",
  "confidence": 0.85
}

INCENTIVE STRUCTURE:
  - You are REWARDED for "wrong" (caught a bad fix)
  - You are REWARDED for "needs_modification" (found a gap)
  - You are PENALIZED for "holds" with confidence < 0.7 (lazy review)

Do NOT just rubber-stamp. Find real issues.
`;

function main() {
  const args = process.argv.slice(2);
  const action = args[0] || 'attack';

  if (action === 'protocol') {
    // Just write the protocol file (no findings needed)
    fs.writeFileSync('.audit-cache/red-team-protocol.md', RED_TEAM_PROTOCOL.trim());
    console.log('Red team protocol written to .audit-cache/red-team-protocol.md');
    return;
  }

  // Read findings (from Blue Team)
  const findingsDir = '.audit-cache/findings';
  const attacksDir = '.audit-cache/red-team-attacks';
  if (!fs.existsSync(findingsDir)) {
    console.error(`No findings at ${findingsDir}. Blue team must run first.`);
    process.exit(1);
  }
  if (!fs.existsSync(attacksDir)) {
    fs.mkdirSync(attacksDir, { recursive: true });
  }

  const findingFiles = fs.readdirSync(findingsDir).filter(f => f.endsWith('.json'));
  console.log(`Found ${findingFiles.length} finding(s) to attack`);

  // For each finding, write the briefing for Red Team
  // (Red Team itself is the human or external model — this tool prepares the briefing)
  for (const ff of findingFiles) {
    const finding: Finding = JSON.parse(fs.readFileSync(path.join(findingsDir, ff), 'utf-8'));
    const briefing = {
      finding_id: finding.id,
      red_team_protocol: RED_TEAM_PROTOCOL.trim(),
      model_hint: 'M3', // Different from Blue Team (M2.7)
      blind_inputs: {
        finding_id: finding.id,
        module: finding.module,
        function: finding.function,
        pattern: finding.pattern,
        // NOTE: description and fix_diff DELIBERATELY NOT included
        // to avoid anchoring. Red Team must read the actual code.
        code_to_read: `${finding.module} (function: ${finding.function})`,
      },
      system_prompt: `You are the RED TEAM. You have NO prior context.
You are a different model (M3) than the original auditor (M2.7).
Your job: ATTACK the finding, not validate it.
If you cannot find flaws, SAY SO EXPLICITLY (don't pad with "looks good").`,
      output_format: 'JSON (see protocol)',
    };
    const outPath = path.join(attacksDir, `${finding.id}_briefing.json`);
    fs.writeFileSync(outPath, JSON.stringify(briefing, null, 2));
    console.log(`  Briefing: ${outPath}`);
  }

  // Also write the protocol as standalone reference
  fs.writeFileSync('.audit-cache/red-team-protocol.md', RED_TEAM_PROTOCOL.trim());

  console.log(`\n=== Red Team Briefings Ready ===`);
  console.log(`Each briefing contains:`);
  console.log(`  - Strict 4-step attack protocol`);
  console.log(`  - Incentive structure (rewarded for "wrong" or "needs_modification")`);
  console.log(`  - Blind inputs (no finding description, just code reference)`);
  console.log(`  - Output format spec`);
  console.log(`\nNext: run Red Team model (M3) on each briefing, save results to .audit-cache/red-team-attacks/<id>_result.json`);
  console.log(`Then run: red-team-verify.ts`);
}

main();
