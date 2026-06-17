/**
 * generate-blind-briefings.ts (v4.0.0)
 * Generate N divergent blind briefings, one per Blue Team agent
 *
 * v3.7 vs v4:
 *   v3.7: 7 agents share pre-query.json (Bandwagon)
 *   v4:   each agent gets DIFFERENT briefing:
 *         - different entry file (random per subsystem)
 *         - different lens (dataflow, concurrency, security, error-handling, perf)
 *         - different model hint
 *
 * Key insight: divergent priors → independent findings → no Bandwagon
 *
 * Output: .audit-cache/briefings/{agent_id}.json
 *   Each briefing contains:
 *   - lens: which perspective to take
 *   - entry_file: where to start analysis
 *   - subsystem_focus: which subsystem to specialize in
 *   - known_issues: which issues the OTHER agents found (so this agent
 *     doesn't repeat, but can extend/deepen)
 *   - forbidden_priors: things explicitly OUT of scope (so this agent
 *     doesn't re-find what the others found)
 */
import * as fs from 'fs';
import * as path from 'path';

const MANIFEST_PATH = '.audit-cache/subsystem-manifest.json';
const FLOW_PATH = '.audit-cache/flow-trace.json';
const OUTPUT_DIR = '.audit-cache/briefings';

interface Manifest {
  files: Record<string, string[]>;
  subsystems: Record<string, { files: string[]; category: string; files_count: number }>;
}

interface Lens {
  name: string;
  description: string;
  focus_questions: string[];
  signals_to_look_for: string[];
}

const LENSES: Lens[] = [
  {
    name: 'data_flow',
    description: 'Trace data from entry to persistence. Focus on what happens BETWEEN read and write.',
    focus_questions: [
      'What data enters this subsystem from API/UI?',
      'Where is it validated, transformed, stored?',
      'What can go wrong between read and write (TOCTOU, lost update, etc.)?',
    ],
    signals_to_look_for: [
      'SELECT-then-UPDATE without FOR UPDATE',
      'Missing transaction boundaries',
      'Untyped external input flowing into SQL',
      'Cross-file data dependencies without test',
    ],
  },
  {
    name: 'concurrency',
    description: 'Find race conditions, deadlocks, and timing issues.',
    focus_questions: [
      'What state is shared between concurrent requests?',
      'Are there locks? Are they time-bounded?',
      'What happens if two requests arrive simultaneously?',
    ],
    signals_to_look_for: [
      'In-memory state mutation in request handler',
      'Missing async/await',
      'No timeout on long operations',
      'Lock without TTL',
    ],
  },
  {
    name: 'error_handling',
    description: 'Find error paths that swallow, leak, or cascade.',
    focus_questions: [
      'What errors are caught and discarded?',
      'What errors leak to users (stack traces, internal info)?',
      'What happens when external service is down?',
    ],
    signals_to_look_for: [
      'catch {} empty',
      'console.error without throw',
      'Promise rejection without handler',
      'Missing graceful degradation',
    ],
  },
  {
    name: 'security',
    description: 'Find auth, authz, input validation, and data leak issues.',
    focus_questions: [
      'Is every endpoint protected?',
      'Does the user own the data they access?',
      'Is user input sanitized before SQL/HTML/shell?',
    ],
    signals_to_look_for: [
      'Missing authMiddleware',
      'User-controlled data in SQL',
      'No CSRF protection',
      'Sensitive data in logs',
    ],
  },
  {
    name: 'resource_lifecycle',
    description: 'Find leaks, double-closes, unclosed resources.',
    focus_questions: [
      'Are connections released on error?',
      'Are timers cleared?',
      'Is the cleanup order correct on shutdown?',
    ],
    signals_to_look_for: [
      'setInterval without clearInterval',
      'Database connection without release',
      'SSE without cleanup',
      'File handle without close',
    ],
  },
];

function pickRandom<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

function main() {
  if (!fs.existsSync(MANIFEST_PATH)) {
    console.error(`No manifest at ${MANIFEST_PATH}. Run subsystem-manifest.sh generate first.`);
    process.exit(1);
  }

  const manifest: Manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf-8'));
  const flow = fs.existsSync(FLOW_PATH)
    ? JSON.parse(fs.readFileSync(FLOW_PATH, 'utf-8'))
    : null;

  if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  }

  // Get all subsystem names with ≥ 2 files
  const subsystems = Object.entries(manifest.subsystems)
    .filter(([name, info]) => info.files_count >= 2 && name !== 'unassigned')
    .map(([name]) => name);

  // 【AAR method update】Round-robin lens assignment (not random).
  // v4.0 used random shuffle → some lenses could be duplicated.
  // v4.1 uses round-robin to guarantee all 6 lenses used when N ≥ 6.
  const N = Math.min(7, subsystems.length); // 7 agents (v4.1)
  const briefings: any[] = [];

  for (let i = 0; i < N; i++) {
    const lens = LENSES[i % LENSES.length]; // round-robin
    const sub = subsystems[i % subsystems.length];
    const subFiles = manifest.subsystems[sub]?.files || [];
    const entryFile = subFiles[0] || 'unknown';

    // Get the cross-subsystem flows for this subsystem
    const flowsForSub = flow?.cross_subsystem_flows.filter(
      (f: any) => f.from_sub === sub || f.to_sub === sub
    ) || [];

    const briefing = {
      agent_id: `blue_${i + 1}`,
      lens: lens.name,
      lens_description: lens.description,
      focus_questions: lens.focus_questions,
      signals_to_look_for: lens.signals_to_look_for,
      subsystem_focus: sub,
      entry_file: entryFile,
      cross_subsystem_flows: flowsForSub.slice(0, 20), // Top 20
      forbidden_priors: [
        'Do NOT report findings about other subsystems (out of scope for this agent)',
        'Do NOT report findings already in v3.5/v3.6 reports (already fixed)',
        'Do NOT repeat findings from previous agents (use cross_run_dedup)',
        'Focus on DEEP root cause, not surface symptoms',
      ],
      instructions: [
        `You are Blue Team Agent ${i + 1}, specializing in subsystem "${sub}".`,
        `Your lens is: ${lens.name}`,
        `Your entry file is: ${entryFile}`,
        '',
        'PROTOCOL:',
        '1. Read the entry file thoroughly',
        '2. Trace the data flow from entry to all its imports/exports',
        '3. Look for issues matching your lens\'s signals',
        '4. For each finding, trace to ROOT CAUSE (3+ causal chains)',
        '5. 【v4.1 AAR update】COUSIN BUG SCAN: After finding root cause, ',
        '   list 3 other files that may share the same pattern (different modules).',
        '   Check: same function shape, same data flow, same anti-pattern.',
        '6. Report findings with: id, semantic_hash (module/function/pattern), root_cause, evidence, cousin_files',
        '',
        'Your unique value: independent perspective. Do NOT converge with other agents.',
        'If you cannot find issues in your lens, REPORT BLIND SPOT, not zero findings.',
      ],
    };

    const filePath = path.join(OUTPUT_DIR, `blue_${i + 1}.json`);
    fs.writeFileSync(filePath, JSON.stringify(briefing, null, 2));
  }

  console.log(`=== Generated ${N} Blind Briefings ===`);
  for (let i = 1; i <= N; i++) {
    const b = JSON.parse(fs.readFileSync(path.join(OUTPUT_DIR, `blue_${i}.json`), 'utf-8'));
    console.log(`  blue_${i}: lens=${b.lens}, subsystem=${b.subsystem_focus}, entry=${b.entry_file}`);
  }
  console.log(`\nOutput: ${OUTPUT_DIR}/`);
  console.log(`\nNext: each agent reads ONLY its briefing (Bandwagon avoided)`);
}

main();
