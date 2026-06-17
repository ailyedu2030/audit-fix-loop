/**
 * red-team-verify.ts (v4.0.0)
 * Verify findings against Red Team attack results
 *
 * Inputs:
 *   - .audit-cache/findings/*.json (Blue Team findings)
 *   - .audit-cache/red-team-attacks/*_result.json (Red Team verdicts)
 *
 * Output:
 *   - .audit-cache/red-team-summary.json
 *   - Console report showing which findings were upheld / rejected / need modification
 *
 * Logic:
 *   - verdict = "wrong" → REOPEN finding (back to Phase 4)
 *   - verdict = "needs_modification" → APPEND remediation, require re-fix
 *   - verdict = "holds" with confidence >= 0.7 → MARK as RED_TEAM_VERIFIED
 *   - verdict = "holds" with confidence < 0.7 → REJECT (lazy review)
 */
import * as fs from 'fs';
import * as path from 'path';

interface Finding {
  id: string;
  status: string;
}

interface AttackResult {
  finding_id: string;
  verdict: 'holds' | 'needs_modification' | 'wrong';
  reasoning: string;
  confidence: number;
  cousin_bugs?: {
    suspected_files: string[];
  };
}

interface Summary {
  total: number;
  verified: number;
  needs_modification: number;
  wrong: number;
  rejected_lazy: number;
  cousin_bugs_to_add: { finding_id: string; files: string[] }[];
  by_finding: Record<string, any>;
}

function main() {
  const findingsDir = '.audit-cache/findings';
  const attacksDir = '.audit-cache/red-team-attacks';
  const summaryPath = '.audit-cache/red-team-summary.json';

  if (!fs.existsSync(findingsDir) || !fs.existsSync(attacksDir)) {
    console.error('Missing findings or red-team-attacks directory. Run Blue Team and Red Team first.');
    process.exit(1);
  }

  const findingFiles = fs.readdirSync(findingsDir).filter(f => f.endsWith('.json'));
  const resultFiles = fs.readdirSync(attacksDir).filter(f => f.endsWith('_result.json'));

  // Index results by finding_id
  const results: Record<string, AttackResult> = {};
  for (const rf of resultFiles) {
    const result: AttackResult = JSON.parse(fs.readFileSync(path.join(attacksDir, rf), 'utf-8'));
    results[result.finding_id] = result;
  }

  // Flatten findings (each file may have nested findings array)
  const allFindings: { id: string; file: string }[] = [];
  for (const ff of findingFiles) {
    const data = JSON.parse(fs.readFileSync(path.join(findingsDir, ff), 'utf-8'));
    if (data.findings && Array.isArray(data.findings)) {
      for (const f of data.findings) {
        allFindings.push({ id: f.id, file: ff });
      }
    } else if (data.id) {
      allFindings.push({ id: data.id, file: ff });
    }
  }

  const summary: Summary = {
    total: allFindings.length,
    verified: 0,
    needs_modification: 0,
    wrong: 0,
    rejected_lazy: 0,
    cousin_bugs_to_add: [],
    by_finding: {},
  };

  for (const finding of allFindings) {
    const result = results[finding.id];

    if (!result) {
      console.warn(`⚠ No Red Team result for ${finding.id}`);
      summary.by_finding[finding.id] = { status: 'pending_red_team' };
      continue;
    }

    let finalStatus: string;
    if (result.verdict === 'wrong') {
      finalStatus = 'REOPEN';
      summary.wrong++;
    } else if (result.verdict === 'needs_modification') {
      finalStatus = 'NEEDS_MODIFICATION';
      summary.needs_modification++;
    } else if (result.verdict === 'holds' && result.confidence >= 0.7) {
      finalStatus = 'RED_TEAM_VERIFIED';
      summary.verified++;
    } else {
      finalStatus = 'REJECTED_LAZY_REVIEW';
      summary.rejected_lazy++;
    }

    if (result.cousin_bugs?.suspected_files?.length > 0) {
      summary.cousin_bugs_to_add.push({
        finding_id: finding.id,
        files: result.cousin_bugs.suspected_files,
      });
    }

    summary.by_finding[finding.id] = {
      verdict: result.verdict,
      confidence: result.confidence,
      reasoning: result.reasoning,
      final_status: finalStatus,
    };
  }

  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2));

  console.log(`\n=== Red Team Summary ===`);
  console.log(`Total findings:    ${summary.total}`);
  console.log(`✓ Verified:        ${summary.verified}`);
  console.log(`⚠ Needs mod:       ${summary.needs_modification}`);
  console.log(`✗ Wrong (reopen):  ${summary.wrong}`);
  console.log(`✗ Lazy review:     ${summary.rejected_lazy}`);
  console.log(`\nCousin bugs to add: ${summary.cousin_bugs_to_add.length}`);
  for (const cb of summary.cousin_bugs_to_add) {
    console.log(`  ${cb.finding_id}: ${cb.files.join(', ')}`);
  }
  console.log(`\nOutput: ${summaryPath}`);
}

main();
