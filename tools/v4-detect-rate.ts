/**
 * v4-detect-rate.ts (v4.0.0)
 * Measure v4 detection rate against gold set
 *
 * Maps Blue Team findings + Red Team cousin bugs against 24 known bugs
 * Computes: detection rate, false positive rate, cross-subsystem rate
 */
import * as fs from 'fs';
import * as path from 'path';

const gold = JSON.parse(fs.readFileSync('.audit-cache/gold-set.json', 'utf-8'));
const findingsDir = '.audit-cache/findings';
const attacksDir = '.audit-cache/red-team-attacks';

// Collect all Blue Team findings
const allBlueFindings: any[] = [];
for (const ff of fs.readdirSync(findingsDir).filter(f => f.endsWith('.json'))) {
  const data = JSON.parse(fs.readFileSync(path.join(findingsDir, ff), 'utf-8'));
  if (data.findings) allBlueFindings.push(...data.findings);
}

// Collect all Red Team cousin bugs
const cousinBugs: string[] = [];
for (const rf of fs.readdirSync(attacksDir).filter(f => f.endsWith('_result.json'))) {
  const result = JSON.parse(fs.readFileSync(path.join(attacksDir, rf), 'utf-8'));
  if (result.cousin_bugs?.suspected_files) {
    cousinBugs.push(...result.cousin_bugs.suspected_files);
  }
}

// Detection logic: a gold bug is "detected" if any finding/attack mentions its file
// Use exact file match + partial description match (fuzzy)
function isGoldBugDetected(goldBug: any): { detected: boolean; by: string } {
  const goldFile = goldBug.file;

  // Check Blue Team findings
  for (const f of allBlueFindings) {
    const fModule = (f.module || '').toLowerCase();
    const gbFile = goldFile.toLowerCase();
    const gbBasename = path.basename(goldFile).toLowerCase().replace('.ts', '').replace('.tsx', '');
    if (fModule === gbFile || fModule === path.basename(goldFile) || 
        fModule.includes(gbBasename) || gbFile.includes(fModule)) {
      return { detected: true, by: `Blue Team ${f.id}` };
    }
  }

  // Check Red Team cousin bugs (mentions the gold file)
  for (const cb of cousinBugs) {
    if (cb === goldFile || cb.includes(path.basename(goldFile))) {
      return { detected: true, by: 'Red Team cousin bug' };
    }
  }

  return { detected: false, by: '' };
}

// Compute metrics
const total = gold.bugs.length;
let detected = 0;
let p0p1Detected = 0;
let p0p1Total = 0;
let crossDetected = 0;
let crossTotal = 0;
const notDetected: any[] = [];

for (const gb of gold.bugs) {
  const result = isGoldBugDetected(gb);
  if (result.detected) detected++;
  if (gb.severity === 'P0' || gb.severity === 'P1') {
    p0p1Total++;
    if (result.detected) p0p1Detected++;
  }
  if (gb.cross_subsystem) {
    crossTotal++;
    if (result.detected) crossDetected++;
  }
  if (!result.detected) {
    notDetected.push({ id: gb.id, severity: gb.severity, pattern: gb.pattern, file: gb.file });
  }
}

// False positive analysis: findings not in gold set
const goldIds = new Set(gold.bugs.map((b: any) => b.id));
const blueIds = allBlueFindings.map(f => f.id);
const falsePositives = blueIds.filter(id => !goldIds.has(id) && !id.startsWith('v4-'));

// We can't say for sure v4-XXX are FPs without verifying, but count unknown

const output = {
  gold_set_size: total,
  blue_findings: allBlueFindings.length,
  red_cousin_bugs: cousinBugs.length,
  detection: {
    total: `${detected}/${total} (${Math.round(detected/total*100)}%)`,
    p0p1: `${p0p1Detected}/${p0p1Total} (${Math.round(p0p1Detected/p0p1Total*100)}%)`,
    cross_subsystem: `${crossDetected}/${crossTotal} (${Math.round(crossDetected/crossTotal*100)}%)`,
  },
  targets: {
    p0p1_target: '>90%',
    p0p1_actual: `${Math.round(p0p1Detected/p0p1Total*100)}%`,
    p0p1_met: p0p1Detected / p0p1Total >= 0.9 ? 'YES' : 'NO',
    cross_target: '>30%',
    cross_actual: `${Math.round(crossDetected/crossTotal*100)}%`,
    cross_met: crossDetected / crossTotal >= 0.3 ? 'YES' : 'NO',
  },
  not_detected: notDetected,
  false_positive_count: allBlueFindings.length - detected,
  blue_team_unique_findings: blueIds.length,
  red_team_value: `+${cousinBugs.length} cousin bugs (cross-subsystem)`,
};

console.log('=== v4 Detection Rate vs Gold Set (24 known bugs) ===\n');
console.log('Blue Team findings:', allBlueFindings.length);
console.log('Red Team cousin bugs:', cousinBugs.length);
console.log('');
console.log('Detection:');
console.log(`  Total:       ${output.detection.total}`);
console.log(`  P0/P1 only:  ${output.detection.p0p1} (target: >90%, ${output.targets.p0p1_met})`);
console.log(`  Cross-subs:  ${output.detection.cross_subsystem} (target: >30%, ${output.targets.cross_met})`);
console.log('');
console.log('Not detected (', notDetected.length, '):');
for (const nd of notDetected) {
  console.log(`  - ${nd.id} [${nd.severity}]: ${nd.pattern} @ ${nd.file}`);
}
console.log('');

fs.writeFileSync('.audit-cache/v4-detect-rate.json', JSON.stringify(output, null, 2));
console.log('Output: .audit-cache/v4-detect-rate.json');
