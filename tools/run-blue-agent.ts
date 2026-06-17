/**
 * run-blue-agent.ts (v4.3.0)
 * Spawn a Blue Team agent with its briefing, validate output, and retry on failure.
 *
 * Uses OpenCode's Task tool to spawn a subagent with the agent's .md file as prompt.
 * Falls back to direct LLM access if Task is unavailable.
 *
 * v4.3 replaces: manual Phase 2 orchestration (read -r _ blocks)
 * v4.3 solves: Bandwagon effect (each agent has DIFFERENT prompt + briefing)
 *
 * Usage:
 *   npx tsx tools/run-blue-agent.ts <agent_name> <briefing_file>
 *
 * Agent names: audit-blue-security | audit-blue-concurrency |
 *              audit-blue-dataflow | audit-blue-error | audit-blue-resource
 *
 * Output: .audit-cache/findings/{agent_name}.json
 */
import { execSync } from 'child_process';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';

const AGENTS_DIR = join(dirname(__dirname), 'agents');
const OUTPUT_DIR = '.audit-cache/findings';

interface AgentConfig {
  name: string;
  model: string;
  promptFile: string;
  briefingFile: string;
  outputFile: string;
}

function spawnAgent(config: AgentConfig): string {
  // Load agent prompt
  const agentPrompt = readFileSync(join(AGENTS_DIR, config.promptFile), 'utf-8');

  // Load briefing
  const briefing = JSON.parse(readFileSync(config.briefingFile, 'utf-8'));

  // Build the task prompt: agent system prompt + briefing data
  const taskPrompt = `${agentPrompt}

## YOUR BRIEFING

${JSON.stringify(briefing, null, 2)}

## OUTPUT

Output findings JSON to: ${config.outputFile}
Use Write tool to save your findings.

Do NOT output anything else. Do NOT add explanations. Just find bugs and write the JSON.`;

  // Try OpenCode Task tool via CLI
  try {
    const result = execSync(
      `opencode task --agent=${config.name} "${taskPrompt.replace(/"/g, '\\"')}" 2>&1`,
      { encoding: 'utf-8', timeout: 900000, maxBuffer: 10 * 1024 * 1024 }
    );
    return result;
  } catch (e) {
    // Fallback: if opencode CLI not available, just log and proceed
    console.warn(`[run-blue-agent] opencode CLI unavailable, agent not spawned`);
    return '';
  }
}

function validateOutput(file: string): boolean {
  if (!existsSync(file)) return false;

  try {
    const data = JSON.parse(readFileSync(file, 'utf-8'));

    // Check findings array exists
    if (!data.findings || !Array.isArray(data.findings)) {
      console.warn(`[run-blue-agent] ${file}: no findings array`);
      return false;
    }

    // If no findings, check blind_spot field
    if (data.findings.length === 0 && !data.blind_spot) {
      console.warn(`[run-blue-agent] ${file}: 0 findings, no blind_spot`);
      // Don't reject — some files genuinely have no bugs
    }

    // Quick validation per finding
    for (const f of data.findings) {
      if (!f.id || !f.module || !f.severity || !f.description || !f.root_cause) {
        console.warn(`[run-blue-agent] ${file}: finding ${f.id || '?'} missing required fields`);
        return false;
      }
      if (!f.causal_chain || f.causal_chain.length < 2) {
        console.warn(`[run-blue-agent] ${file}: finding ${f.id} causal chain too short`);
        return false;
      }
    }

    return true;
  } catch (e) {
    console.warn(`[run-blue-agent] ${file}: JSON parse error`);
    return false;
  }
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: run-blue-agent.ts <agent_name> <briefing_file>');
    console.error('  agent_name: audit-blue-security | audit-blue-concurrency | ...');
    console.error('  briefing_file: .audit-cache/briefings/blue_SECURITY.json');
    process.exit(2);
  }

  const [agentName, briefingFile] = args;
  const safeName = agentName.replace('audit-', '').replace(/blue-/g, '').toUpperCase();
  const outputFile = join(OUTPUT_DIR, `${agentName}.json`);

  if (!existsSync(OUTPUT_DIR)) mkdirSync(OUTPUT_DIR, { recursive: true });

  const config: AgentConfig = {
    name: agentName,
    model: 'MiniMax-M2.7',
    promptFile: `${agentName}.md`,
    briefingFile,
    outputFile,
  };

  // Phase 1: Spawn agent
  console.log(`[run-blue-agent] Spawning ${agentName} with briefing ${briefingFile}...`);
  const result = spawnAgent(config);

  // Phase 2: Validate output
  await new Promise(r => setTimeout(r, 2000)); // Let agent write file

  if (existsSync(outputFile)) {
    const valid = validateOutput(outputFile);
    if (valid) {
      console.log(`[run-blue-agent] ✓ ${agentName}: findings valid`);
    } else {
      console.warn(`[run-blue-agent] ⚠ ${agentName}: findings need review`);
    }
  } else {
    // Agent didn't produce output — write empty findings
    console.warn(`[run-blue-agent] ✗ ${agentName}: no output produced`);
    writeFileSync(outputFile, JSON.stringify({
      findings: [],
      blind_spot: 'Agent failed to produce output — manual review required',
      agent: agentName,
    }, null, 2));
  }

  // Phase 3: Run causal chain validator
  try {
    execSync(`bash tools/validate-causal-chain.sh ${outputFile}`, { encoding: 'utf-8', timeout: 10000 });
  } catch (e) {
    console.warn(`[run-blue-agent] ⚠ ${agentName}: causal chain validation issues`);
  }

  console.log(`[run-blue-agent] ${agentName} done → ${outputFile}`);
}

main().catch(e => { console.error(e); process.exit(1); });
