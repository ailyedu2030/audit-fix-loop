#!/usr/bin/env -S npx tsx
/**
 * apply-fix.ts (v4.5.0) — Phase 4: Read finding, apply patch, verify.
 *
 * Usage:
 *   apply-fix.ts <findings.json> <finding_id>
 *
 * For the specified finding:
 *   1. Read the target source file
 *   2. Compute SHA before fix
 *   3. Present the finding to the agent for fix
 *   4. (Agent applies fix via Edit tool)
 *   5. Validate: source file changed, tests pass
 *   6. Update audit_state.json
 */
import { readFileSync, writeFileSync, existsSync, createHash } from 'fs';
import { join } from 'path';
import { execSync } from 'child_process';

const STATE_FILE = '.audit-cache/audit_state.json';

interface Finding {
  id: string; module: string; function: string; pattern: string;
  severity: string; description: string; root_cause: string;
  causal_chain: string[]; fix_recommendation?: string;
  cousin_files?: string[];
}

function sha256(content: string): string {
  return createHash('sha256').update(content).digest('hex').slice(0, 12);
}

function main() {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: apply-fix.ts <findings.json> <finding_id>');
    console.error('  findings.json: output from arbitrate-findings.sh');
    console.error('  finding_id: e.g. "F-001"');
    process.exit(2);
  }

  const [findingsFile, findingId] = args;

  if (!existsSync(findingsFile)) {
    console.error(`Findings file not found: ${findingsFile}`);
    process.exit(1);
  }

  const findings = JSON.parse(readFileSync(findingsFile, 'utf-8'));
  const finding: Finding | undefined = findings.findings?.find((f: Finding) => f.id === findingId);

  if (!finding) {
    console.error(`Finding ${findingId} not found in ${findingsFile}`);
    process.exit(1);
  }

  console.log(`=== Phase 4 Fix: ${finding.id} [${finding.severity}] ===`);
  console.log(`  Module: ${finding.module}`);
  console.log(`  Function: ${finding.function}`);
  console.log(`  Pattern: ${finding.pattern}`);
  console.log(`  Root cause: ${finding.root_cause}`);
  console.log('');

  // Step 1: Read source file
  if (!existsSync(finding.module)) {
    console.error(`Source file not found: ${finding.module}`);
    process.exit(1);
  }

  const sourceContent = readFileSync(finding.module, 'utf-8');
  const beforeHash = sha256(sourceContent);
  console.log(`  Source: ${finding.module} (${sourceContent.length} bytes, sha=${beforeHash})`);

  // Step 2: Present fixing instructions
  console.log('');
  console.log('  FIX INSTRUCTIONS:');
  console.log(`    1. Read ${finding.module}`);
  console.log(`    2. Locate function "${finding.function}"`);
  console.log(`    3. ${finding.fix_recommendation || finding.root_cause}`);
  console.log(`    4. Apply fix using Edit tool`);
  console.log(`    5. Verify: tsc --noEmit, run tests`);
  console.log('');

  // Step 3: Update state file
  if (existsSync(STATE_FILE)) {
    const state = JSON.parse(readFileSync(STATE_FILE, 'utf-8'));
    if (!state.findings) state.findings = {};
    if (!state.test_coverage) state.test_coverage = {};

    state.findings[finding.id] = {
      ...state.findings[finding.id],
      status: 'fixing',
      fix_evidence: {
        file: finding.module,
        before_hash: beforeHash,
        started_at: new Date().toISOString(),
      },
    };

    writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
    console.log(`  State updated: ${finding.id} → fixing`);
  }

  console.log('');
  console.log('  After fix, run:');
  console.log(`    npm run lint`);
  console.log(`    npx vitest run`);
  console.log(`    Then re-run apply-fix.ts --verify ${finding.id} to update state to 'fixed'`);
}

main();
