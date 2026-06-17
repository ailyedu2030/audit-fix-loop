/**
 * after-action-review.ts (v4.0.0) — RESOLVES ROOT CAUSE 4: Single-Loop Learning
 *
 * The skill's biggest gap: it never asks "WHY did we miss this?"
 * v3.5: 73 findings, 49 missed. v3.6: same patterns re-discovered.
 *
 * AAR (After Action Review) is mandatory at end of every audit.
 * 4 questions, borrowed from US Army + Toyota Production:
 *
 *   Q1: WHAT was supposed to happen? (Plan)
 *   Q2: WHAT actually happened? (Outcome)
 *   Q3: WHY did it differ? (Root cause of divergence)
 *   Q4: What will we SUSTAIN / IMPROVE next time? (Learning)
 *
 * Output: .audit-cache/aar.json
 *   - Persists to history (.audit-cache/aar-history/)
 *   - Feeds back into next audit's blind briefings
 *   - Updates blind-spot-registry.json
 */
import * as fs from 'fs';
import * as path from 'path';

interface AAR {
  run_id: string;
  date: string;
  scope: string;
  q1_plan: {
    intended_findings: number;
    intended_subsystems: string[];
    intended_lenses: string[];
  };
  q2_outcome: {
    actual_findings: number;
    actual_subsystems: string[];
    actual_lenses: string[];
    actual_subsystem_coverage_pct: number;
  };
  q3_root_cause: {
    blind_spots: string[];
    why_we_missed: string;
    structural_issues: string[];
  };
  q4_learning: {
    sustain: string[];
    improve: string[];
    method_updates: {
      target: string;
      change: string;
      reason: string;
    }[];
  };
  blind_spots_to_register: { id: string; description: string; category: string }[];
  cross_run_observations: string;
}

const AAR_TEMPLATE = `
AFTER ACTION REVIEW (AAR) — 4 Mandatory Questions

Q1: WHAT was supposed to happen?
   - Intended findings count
   - Intended subsystem coverage
   - Intended lenses used

Q2: WHAT actually happened?
   - Actual findings count
   - Actual subsystem coverage (%)
   - Actual lenses used
   - What did we find that we didn't plan to find?
   - What did we miss that we planned to find?

Q3: WHY did it differ? (Root cause of divergence)
   - Blind spots: categories of bugs we never found
   - Why we missed: cognitive bias? tooling? time?
   - Structural issues in the audit process itself

Q4: What will we SUSTAIN and IMPROVE next time?
   - SUSTAIN: what worked, keep doing
   - IMPROVE: specific changes to next audit
   - Method updates: changes to SKILL/tools/process

OUTPUT: AAR JSON with all 4 sections + blind spots to register
`;

function loadPreviousAARs(): AAR[] {
  const historyDir = '.audit-cache/aar-history';
  if (!fs.existsSync(historyDir)) return [];
  return fs.readdirSync(historyDir)
    .filter(f => f.endsWith('.json'))
    .map(f => JSON.parse(fs.readFileSync(path.join(historyDir, f), 'utf-8')))
    .sort((a, b) => a.date.localeCompare(b.date));
}

function generateTemplate(): AAR {
  const previous = loadPreviousAARs();
  const lastAAR = previous[previous.length - 1];

  return {
    run_id: `aar-${Date.now()}`,
    date: new Date().toISOString(),
    scope: 'audit-cycle',
    q1_plan: {
      intended_findings: 0,
      intended_subsystems: [],
      intended_lenses: [],
    },
    q2_outcome: {
      actual_findings: 0,
      actual_subsystems: [],
      actual_lenses: [],
      actual_subsystem_coverage_pct: 0,
    },
    q3_root_cause: {
      blind_spots: [],
      why_we_missed: '',
      structural_issues: [],
    },
    q4_learning: {
      sustain: [],
      improve: [],
      method_updates: [],
    },
    blind_spots_to_register: [],
    cross_run_observations: lastAAR
      ? `Last run: ${lastAAR.q4_learning.method_updates.length} method updates. Carry forward: ${JSON.stringify(lastAAR.q4_learning.method_updates)}`
      : 'No previous AAR. This is the first.',
  };
}

function main() {
  const args = process.argv.slice(2);
  const action = args[0] || 'template';

  const aarPath = '.audit-cache/aar.json';
  const historyDir = '.audit-cache/aar-history';

  if (action === 'template') {
    // Write a template AAR for human/LLM to fill
    if (!fs.existsSync(historyDir)) {
      fs.mkdirSync(historyDir, { recursive: true });
    }
    const template = generateTemplate();
    fs.writeFileSync(aarPath + '.template', JSON.stringify(template, null, 2));
    fs.writeFileSync('.audit-cache/aar-protocol.md', AAR_TEMPLATE.trim());
    console.log('=== AAR Template Generated ===');
    console.log(`Template: ${aarPath}.template`);
    console.log(`Protocol: .audit-cache/aar-protocol.md`);
    console.log('\nNext:');
    console.log('  1. Fill the 4 questions in aar.json.template');
    console.log('  2. Rename to aar.json');
    console.log('  3. Run: after-action-review.sh commit');
  } else if (action === 'commit') {
    if (!fs.existsSync(aarPath)) {
      console.error(`No AAR at ${aarPath}. Fill the template first.`);
      process.exit(1);
    }
    const aar: AAR = JSON.parse(fs.readFileSync(aarPath, 'utf-8'));

    // Save to history
    if (!fs.existsSync(historyDir)) {
      fs.mkdirSync(historyDir, { recursive: true });
    }
    fs.writeFileSync(
      path.join(historyDir, `${aar.run_id}.json`),
      JSON.stringify(aar, null, 2)
    );

    // Update blind spot registry
    const registryPath = '.audit-cache/blind-spot-registry.json';
    let registry: { entries: any[]; updated_at: string } = { entries: [], updated_at: '' };
    if (fs.existsSync(registryPath)) {
      registry = JSON.parse(fs.readFileSync(registryPath, 'utf-8'));
    }
    for (const bs of aar.blind_spots_to_register) {
      // Check if already exists
      if (!registry.entries.find(e => e.id === bs.id)) {
        registry.entries.push({
          ...bs,
          registered_at: aar.date,
          status: 'open',
        });
      }
    }
    registry.updated_at = aar.date;
    fs.writeFileSync(registryPath, JSON.stringify(registry, null, 2));

    // Apply method updates to next briefing
    const briefingDir = '.audit-cache/briefings';
    if (fs.existsSync(briefingDir) && aar.q4_learning.method_updates.length > 0) {
      console.log('Method updates to apply to next audit:');
      for (const update of aar.q4_learning.method_updates) {
        console.log(`  → ${update.target}: ${update.change}`);
      }
    }

    console.log(`\n=== AAR Committed ===`);
    console.log(`History: ${historyDir}/${aar.run_id}.json`);
    console.log(`Blind spots registered: ${aar.blind_spots_to_register.length}`);
    console.log(`Method updates queued: ${aar.q4_learning.method_updates.length}`);
  } else if (action === 'history') {
    const previous = loadPreviousAARs();
    console.log(`=== AAR History (${previous.length} runs) ===`);
    for (const a of previous.slice(-5)) {
      console.log(`\n${a.run_id} (${a.date}):`);
      console.log(`  Findings: ${a.q2_outcome.actual_findings}`);
      console.log(`  Coverage: ${a.q2_outcome.actual_subsystem_coverage_pct}%`);
      console.log(`  Blind spots: ${a.q3_root_cause.blind_spots.length}`);
      console.log(`  Method updates: ${a.q4_learning.method_updates.length}`);
    }
  } else {
    console.log('Usage: after-action-review.sh [template|commit|history]');
    process.exit(2);
  }
}

main();
