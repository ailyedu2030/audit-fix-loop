/**
 * gold-set.ts (v4.0.0)
 * Build gold set of known bugs from audit history
 *
 * Sources:
 *   1. v3.5: 73 AI module findings (commit 11e7ffb)
 *   2. v3.5: 53 grammar findings (commit f4e5854)
 *   3. v3.5: 21 grammar findings (commit 76e80d4)
 *   4. v3.6 retro: SRE-006 (commit b39af7b)
 *   5. v3.7: cross-run-dedup (commit f488302)
 *   6. v3.5 test pyramid: DEVIL-019, DEVIL-022 (commit 49453dc)
 *   7. SEC-007, SEC-008, SEC-002, SEC-005, SEC-006 (commits 69aa1b9, b790963)
 *
 * Output: .audit-cache/gold-set.json
 *   Each entry has: {id, file, line, description, severity, category, fixed_in_commit}
 *
 * Used to:
 *   - Measure v4 detection rate (P0 detection > 90% target)
 *   - Validate cross-subsystem finding discovery
 *   - Regression test (v3.7 audit must not regress on these)
 */
import * as fs from 'fs';
import * as path from 'path';

interface GoldBug {
  id: string;
  file: string;
  line?: number;
  description: string;
  severity: 'P0' | 'P1' | 'P2' | 'P3';
  category: 'concurrency' | 'data_flow' | 'error_handling' | 'security' | 'resource_lifecycle' | 'state_machine' | 'type_safety';
  fixed_in_commit: string;
  cross_subsystem: boolean;
  detectable_by_lens: string[];
  /** 【v4.2 AAR】Whether bug is still findable in current code (vs already patched) */
  detectable: boolean;
}

// Curated gold set: 20+ known bugs from audit history
const KNOWN_BUGS: GoldBug[] = [
  // v3.6 retro
  {
    id: 'SRE-006',
    file: 'server/src/services/aiExamPoolService.ts',
    line: 438,
    description: 'markJobFailed does not release paper-level lock_token / lock_expires_at',
    severity: 'P0',
    category: 'resource_lifecycle',
    fixed_in_commit: 'b39af7b',
    cross_subsystem: true,
    detectable_by_lens: ['resource_lifecycle', 'data_flow'],
  },
  {
    id: 'LIVE-DRIFT-001',
    file: 'server/src/db/migrations/030_add_missing_indexes.sql',
    description: 'Migration 030 dropped lock_token + lock_expires_at columns from ai_exam_papers (P0 runtime crash)',
    severity: 'P0',
    category: 'state_machine',
    fixed_in_commit: '8f4c3f3',
    cross_subsystem: true,
    detectable_by_lens: ['data_flow', 'state_machine'],
  },
  // v3.5 test pyramid
  {
    id: 'DEVIL-019',
    file: 'server/src/services/aiExamGenerator.ts',
    description: 'lock_token uses Math.random() (predictable) — security/collision risk',
    severity: 'P1',
    category: 'security',
    fixed_in_commit: '49453dc',
    cross_subsystem: false,
    detectable_by_lens: ['security', 'data_flow'],
  },
  {
    id: 'DEVIL-022',
    file: 'server/src/routes/ai.ts',
    description: 'extractJson cannot parse JSON arrays ([...]-bracket) or <reasoning>/<thinking> tags',
    severity: 'P1',
    category: 'error_handling',
    fixed_in_commit: '49453dc',
    cross_subsystem: false,
    detectable_by_lens: ['error_handling'],
  },
  {
    id: 'SSE-CLEANUP',
    file: 'server/src/routes/ai.ts',
    description: 'SSE cleanup order: cleanup registered AFTER await, may miss disconnect',
    severity: 'P1',
    category: 'resource_lifecycle',
    fixed_in_commit: '11e7ffb',
    cross_subsystem: false,
    detectable_by_lens: ['resource_lifecycle', 'error_handling'],
  },
  // SEC findings
  {
    id: 'SEC-002',
    file: 'server/src/routes/ai.ts',
    description: 'Translation persistence race condition',
    severity: 'P1',
    category: 'concurrency',
    fixed_in_commit: 'b790963',
    cross_subsystem: true,
    detectable_by_lens: ['concurrency', 'data_flow'],
  },
  {
    id: 'SEC-005',
    file: 'server/src/routes/admin.ts',
    description: 'Admin error message sanitization — leaks internal info to client',
    severity: 'P1',
    category: 'security',
    fixed_in_commit: 'b790963',
    cross_subsystem: false,
    detectable_by_lens: ['security', 'error_handling'],
  },
  {
    id: 'SEC-006',
    file: 'server/src/routes/ai.ts',
    description: 'Translation prompt injection guard missing',
    severity: 'P1',
    category: 'security',
    fixed_in_commit: 'b790963',
    cross_subsystem: true,
    detectable_by_lens: ['security'],
  },
  {
    id: 'SEC-007',
    file: 'server/src/services/adaptiveExerciseService.ts',
    description: 'Difficulty input validation missing (negative numbers, NaN)',
    severity: 'P1',
    category: 'type_safety',
    fixed_in_commit: '69aa1b9',
    cross_subsystem: false,
    detectable_by_lens: ['security', 'data_flow'],
  },
  {
    id: 'SEC-008',
    file: 'server/src/services/adaptiveExerciseService.ts',
    description: 'Cached question session scoping — user A can see user B questions',
    severity: 'P0',
    category: 'security',
    fixed_in_commit: '69aa1b9',
    cross_subsystem: true,
    detectable_by_lens: ['security', 'data_flow'],
  },
  // AI exam state machine
  {
    id: 'AI-STATE-001',
    file: 'server/src/services/aiExamPool.ts',
    description: 'Pool status CHECK constraint does not allow "generating" state — fix is to use "pending"',
    severity: 'P1',
    category: 'state_machine',
    fixed_in_commit: '0f27ec3',
    cross_subsystem: true,
    detectable_by_lens: ['state_machine', 'data_flow'],
  },
  {
    id: 'AI-QUEUE-001',
    file: 'server/src/services/aiExamWorker.ts',
    description: 'Worker does not handle AbortController properly — memory leak on cancel',
    severity: 'P1',
    category: 'resource_lifecycle',
    fixed_in_commit: '11e7ffb',
    cross_subsystem: false,
    detectable_by_lens: ['resource_lifecycle'],
  },
  {
    id: 'AI-RACE-001',
    file: 'server/src/services/aiExamPoolService.ts',
    description: 'claimNextPendingJob race: concurrent claims can both succeed without FOR UPDATE SKIP LOCKED',
    severity: 'P0',
    category: 'concurrency',
    fixed_in_commit: '11e7ffb',
    cross_subsystem: true,
    detectable_by_lens: ['concurrency', 'data_flow'],
  },
  {
    id: 'AI-DUP-001',
    file: 'server/src/services/aiExamPoolService.ts',
    description: 'duplicateTopicCheck missing FOR UPDATE — TOCTOU race on user_id',
    severity: 'P1',
    category: 'concurrency',
    fixed_in_commit: '11e7ffb',
    cross_subsystem: true,
    detectable_by_lens: ['concurrency', 'data_flow'],
  },
  // Grammar module (v3.5 round 3)
  {
    id: 'GRAM-001',
    file: 'server/src/services/grammarAdaptiveService.ts',
    description: 'Grammar difficulty progression: no FOR UPDATE on user progress read',
    severity: 'P1',
    category: 'concurrency',
    fixed_in_commit: 'f4e5854',
    cross_subsystem: true,
    detectable_by_lens: ['concurrency'],
  },
  {
    id: 'GRAM-002',
    file: 'server/src/services/grammarAdaptiveService.ts',
    description: 'Update proficiency without transaction — lost update on concurrent submissions',
    severity: 'P1',
    category: 'data_flow',
    fixed_in_commit: 'f4e5854',
    cross_subsystem: true,
    detectable_by_lens: ['data_flow', 'concurrency'],
  },
  {
    id: 'GRAM-003',
    file: 'server/src/services/grammarAdaptiveService.ts',
    description: 'Rate limiter allows burst (5 in 60s) but doesn\'t reset properly',
    severity: 'P2',
    category: 'state_machine',
    fixed_in_commit: 'f4e5854',
    cross_subsystem: false,
    detectable_by_lens: ['state_machine', 'data_flow'],
  },
  // Listening module (v3.5)
  {
    id: 'LIST-001',
    file: 'server/src/services/listeningAdaptiveService.ts',
    description: 'Session timeout not enforced — abandoned sessions hold DB locks',
    severity: 'P2',
    category: 'resource_lifecycle',
    fixed_in_commit: 'f4e5854',
    cross_subsystem: true,
    detectable_by_lens: ['resource_lifecycle', 'data_flow'],
  },
  {
    id: 'LIST-002',
    file: 'server/src/services/listeningAdaptiveService.ts',
    description: 'Same FOR UPDATE pattern missing as grammar (cross-module systemic bug)',
    severity: 'P1',
    category: 'concurrency',
    fixed_in_commit: 'f4e5854',
    cross_subsystem: true,
    detectable_by_lens: ['concurrency', 'data_flow'],
  },
  // TTS module
  {
    id: 'TTS-001',
    file: 'server/src/services/tts/lazyTtsWorker.ts',
    description: 'Worker recovery: stuck pending > 5min not auto-reset on startup',
    severity: 'P1',
    category: 'state_machine',
    fixed_in_commit: 'f4e5854',
    cross_subsystem: false,
    detectable_by_lens: ['state_machine', 'resource_lifecycle'],
  },
  {
    id: 'TTS-002',
    file: 'server/src/services/tts/cacheService.ts',
    description: 'Cache LRU cleanup: never runs because interval is set but not started',
    severity: 'P2',
    category: 'resource_lifecycle',
    fixed_in_commit: '11e7ffb',
    cross_subsystem: false,
    detectable_by_lens: ['resource_lifecycle'],
  },
  // Misc
  {
    id: 'A11Y-001',
    file: 'src/components/Layout.tsx',
    description: 'Loading state missing role="status" / role="alert" for screen readers',
    severity: 'P2',
    category: 'error_handling',
    fixed_in_commit: 'ed71386',
    cross_subsystem: false,
    detectable_by_lens: ['error_handling'],
  },
  {
    id: 'AUTH-001',
    file: 'server/src/middleware/auth.ts',
    description: 'JWT validation: no check for token expiration on cache hit',
    severity: 'P1',
    category: 'security',
    fixed_in_commit: '11e7ffb',
    cross_subsystem: true,
    detectable_by_lens: ['security', 'data_flow'],
  },
  {
    id: 'FEED-001',
    file: 'server/src/routes/feedback.ts',
    description: 'Feedback ALLOWED_KEYS check missing in some endpoints',
    severity: 'P1',
    category: 'security',
    fixed_in_commit: '49453dc',
    cross_subsystem: false,
    detectable_by_lens: ['security'],
  },
];

function main() {
  // Validate gold set
  if (KNOWN_BUGS.length < 20) {
    console.error(`Only ${KNOWN_BUGS.length} bugs, need ≥ 20`);
    process.exit(1);
  }

  // Category breakdown
  const byCat: Record<string, number> = {};
  const bySev: Record<string, number> = {};
  const byLens: Record<string, number> = {};
  let crossCount = 0;

  for (const bug of KNOWN_BUGS) {
    byCat[bug.category] = (byCat[bug.category] || 0) + 1;
    bySev[bug.severity] = (bySev[bug.severity] || 0) + 1;
    if (bug.cross_subsystem) crossCount++;
    for (const lens of bug.detectable_by_lens) {
      byLens[lens] = (byLens[lens] || 0) + 1;
    }
  }

  const output = {
    version: 1,
    generated_at: new Date().toISOString(),
    total: KNOWN_BUGS.length,
    by_category: byCat,
    by_severity: bySev,
    cross_subsystem_count: crossCount,
    bugs_by_lens: byLens,
    bugs: KNOWN_BUGS,
  };

  fs.writeFileSync('.audit-cache/gold-set.json', JSON.stringify(output, null, 2));

  console.log('=== Gold Set Built ===');
  console.log(`Total: ${KNOWN_BUGS.length} known bugs`);
  console.log(`By severity: ${JSON.stringify(bySev)}`);
  console.log(`By category: ${JSON.stringify(byCat)}`);
  console.log(`Cross-subsystem: ${crossCount}/${KNOWN_BUGS.length} (${Math.round(crossCount / KNOWN_BUGS.length * 100)}%)`);
  console.log(`\nLens coverage: ${JSON.stringify(byLens)}`);
  console.log(`\nOutput: .audit-cache/gold-set.json`);
  console.log(`\nUse:`);
  console.log(`  v4 detection rate = found_in_v4_audit / total_gold_bugs (target > 90% for P0/P1)`);
  console.log(`  Cross-subsystem rate = found_cross_subsystem / total_cross_subsystem (target > 30%)`);
}

main();
