/**
 * run-blue-agent.ts (v4.4.0) — Fixed: agent dispatch through orchestrator.
 *
 * v4.3 BUG: called `opencode task` CLI — never worked (no OpenCode context in batch).
 * v4.4 FIX: produces a ready-to-use Task prompt that the ORCHESTRATOR sends via Task tool.
 *
 * The orchestrator (using super-fix SKILL.md with Task permission) must:
 *   1. Run this tool to generate the agent prompt
 *   2. Use Task tool to spawn the sub-agent with that prompt
 *   3. Run validate-finding.ts on the output
 *
 * Also runs causal chain validator post-agent.
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';

const AGENTS_DIR = join(dirname(__dirname), 'agents');
const OUTPUT_DIR = '.audit-cache/findings';

function main() {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: run-blue-agent.ts <agent_name> <briefing_file>');
    console.error('  agent_name: audit-blue-security | audit-blue-concurrency | ...');
    console.error('  briefing_file: .audit-cache/briefings/audit-blue-security.json');
    process.exit(2);
  }

  const [agentName, briefingFile] = args;
  const agentFile = join(AGENTS_DIR, `${agentName}.md`);
  const outputFile = join(OUTPUT_DIR, `${agentName}.json`);

  if (!existsSync(agentFile)) {
    console.error(`Agent file not found: ${agentFile}`);
    process.exit(1);
  }
  if (!existsSync(briefingFile)) {
    console.error(`Briefing not found: ${briefingFile}`);
    process.exit(1);
  }

  if (!existsSync(OUTPUT_DIR)) mkdirSync(OUTPUT_DIR, { recursive: true });

  const agentPrompt = readFileSync(agentFile, 'utf-8');
  const briefing = JSON.parse(readFileSync(briefingFile, 'utf-8'));

  // Build the Task prompt for the orchestrator
  const task = {
    agent: agentName,
    prompt: `${agentPrompt}

## YOUR BRIEFING (from ${briefingFile})

${JSON.stringify(briefing, null, 2)}

## EXECUTION INSTRUCTIONS

1. READ the entry file: ${briefing.entry_file}
2. SCAN for signals matching your lens: ${agentName}
3. For each finding, trace to ROOT CAUSE (≥3 causal chain steps)
4. OUTPUT findings to: ${outputFile} (use Write tool)

## OUTPUT FORMAT

Write a JSON file to ${outputFile}:
{
  "agent": "${agentName}",
  "lens": "${briefing.lens}",
  "findings": [
    {
      "id": "F-XXX",
      "module": "path/to/file.ts",
      "function": "functionName",
      "pattern": "issue_pattern",
      "severity": "P0|P1|P2|P3",
      "description": "What the bug is",
      "root_cause": "Why the architecture allowed it (≥20 chars)",
      "causal_chain": ["step1", "step2", "step3"],
      "cousin_files": ["file1.ts", "file2.ts", "file3.ts"],
      "fix_recommendation": "How to fix it"
    }
  ],
  "blind_spot": "Reason if no findings found (optional)"
}

Do NOT output anything except the findings file.`,
    output: outputFile,
  };

  // Write task instructions for orchestrator
  const taskFile = join(OUTPUT_DIR, `task-${agentName}.json`);
  writeFileSync(taskFile, JSON.stringify(task, null, 2));

  console.log(`Task prepared: ${taskFile}`);
  console.log(`Output expected: ${outputFile}`);
  console.log('');
  console.log(`ORCHESTRATOR: Use Task tool to spawn "${agentName}" sub-agent:`);
  console.log(`  subagent_type: "${agentName}"`);
  console.log(`  prompt: read task from ${taskFile}`);
  console.log(`  Expected output: ${outputFile}`);
}

main();
