/**
 * flow-trace.ts (v4.0.0)
 * Build cross-file data flow graph for v4 audit
 *
 * v3.7 vs v4:
 *   v3.7: agents read file-by-file, miss cross-file flows
 *   v4:   build flow graph → agents see "this file receives from / sends to ..."
 *
 * This is a TypeScript tool (not shell) to handle:
 *   - Path alias (@/lib/utils) via tsconfig.json
 *   - Dynamic imports
 *   - Type-only imports
 *   - Barrel exports (re-exports)
 *   - Re-exports through index.ts
 *
 * Output: .audit-cache/flow-trace.json
 *   {
 *     nodes: {file: {imports: [], imported_by: [], exports: []}},
 *     cross_subsystem_flows: [{from: file, to: file, from_sub: sub, to_sub: sub, type: import|export}],
 *     subsystems_in_flow: {sub_name: {incoming_flows: N, outgoing_flows: N}}
 *   }
 */
import * as fs from 'fs';
import * as path from 'path';

const MANIFEST_PATH = '.audit-cache/subsystem-manifest.json';
const OUTPUT_PATH = '.audit-cache/flow-trace.json';
const PROJECT_ROOT = process.cwd();

interface Manifest {
  files: Record<string, string[]>;
  subsystems: Record<string, { files: string[]; category: string; files_count: number }>;
}

interface FlowNode {
  imports: string[];
  imported_by: string[];
  exports: string[];
  subsystem: string[];
}

interface CrossFlow {
  from: string;
  to: string;
  from_sub: string;
  to_sub: string;
  type: 'import' | 'export';
}

interface Output {
  generated_at: string;
  total_files: number;
  total_flows: number;
  cross_subsystem_flows: CrossFlow[];
  nodes: Record<string, FlowNode>;
  subsystem_stats: Record<string, { incoming: number; outgoing: number; internal: number }>;
}

function loadManifest(): Manifest {
  if (!fs.existsSync(MANIFEST_PATH)) {
    console.error(`No manifest at ${MANIFEST_PATH}. Run subsystem-manifest.sh generate first.`);
    process.exit(1);
  }
  return JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf-8'));
}

function loadTsConfigAliases(): Map<string, string> {
  // Read tsconfig.json path mappings
  const tsconfigPath = path.join(PROJECT_ROOT, 'tsconfig.json');
  if (!fs.existsSync(tsconfigPath)) return new Map();

  try {
    const tsconfig = JSON.parse(fs.readFileSync(tsconfigPath, 'utf-8'));
    const aliases = new Map<string, string>();
    const paths = tsconfig.compilerOptions?.paths || {};
    for (const [alias, targets] of Object.entries(paths)) {
      // alias like "@/*" → target like ["./src/*"]
      const cleanAlias = alias.replace(/\*$/, '');
      const cleanTarget = (targets as string[])[0]?.replace(/\*$/, '') || '';
      aliases.set(cleanAlias, cleanTarget);
    }
    return aliases;
  } catch {
    return new Map();
  }
}

function resolveImport(fromFile: string, importPath: string, aliases: Map<string, string>): string | null {
  // 1. Path alias?
  for (const [alias, target] of aliases) {
    if (importPath.startsWith(alias)) {
      const resolved = importPath.replace(alias, target);
      return resolveFile(resolved, fromFile);
    }
  }

  // 2. Relative import
  if (importPath.startsWith('.')) {
    const dir = path.dirname(fromFile);
    const abs = path.normalize(path.join(dir, importPath));
    return resolveFile(abs, fromFile);
  }

  // 3. Bare module (npm package) - ignore
  return null;
}

function resolveFile(absPath: string, fromFile: string): string | null {
  // Try various extensions
  const candidates = [
    absPath,
    absPath + '.ts',
    absPath + '.tsx',
    absPath + '/index.ts',
    absPath + '/index.tsx',
  ];
  for (const c of candidates) {
    if (fs.existsSync(path.join(PROJECT_ROOT, c))) {
      return c;
    }
  }
  return null;
}

function parseImports(content: string): string[] {
  // Match: import ... from '...'
  // Match: import ... from "..."
  // Match: import('...') (dynamic)
  // Match: export ... from '...'
  const imports: string[] = [];
  const patterns = [
    /(?:import|export)\s+(?:[\s\S]+?\s+from\s+)?['"]([^'"]+)['"]/g,
    /import\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
  ];
  for (const pattern of patterns) {
    let match;
    while ((match = pattern.exec(content)) !== null) {
      imports.push(match[1]);
    }
  }
  return [...new Set(imports)];
}

function parseExports(content: string): string[] {
  // Match: export { name1, name2 }
  // Match: export const/function/class/interface name
  const exports: string[] = [];
  const patterns = [
    /export\s+\{([^}]+)\}/g,
    /export\s+(?:const|function|class|interface|type)\s+(\w+)/g,
  ];
  for (const pattern of patterns) {
    let match;
    while ((match = pattern.exec(content)) !== null) {
      const names = match[1].split(',').map(s => s.trim().split(/\s+as\s+/)[0]);
      exports.push(...names);
    }
  }
  return [...new Set(exports)];
}

function main() {
  const manifest = loadManifest();
  const aliases = loadTsConfigAliases();
  const allFiles = Object.keys(manifest.files);
  const fileToSubs = manifest.files;

  const nodes: Record<string, FlowNode> = {};
  const crossFlows: CrossFlow[] = [];

  // Initialize nodes
  for (const f of allFiles) {
    nodes[f] = { imports: [], imported_by: [], exports: [], subsystem: fileToSubs[f] || [] };
  }

  // Parse imports for each file
  for (const f of allFiles) {
    const absPath = path.join(PROJECT_ROOT, f);
    if (!fs.existsSync(absPath)) continue;

    const content = fs.readFileSync(absPath, 'utf-8');
    const imports = parseImports(content);
    const exports = parseExports(content);

    nodes[f].exports = exports;

    for (const imp of imports) {
      const resolved = resolveImport(f, imp, aliases);
      if (resolved && nodes[resolved]) {
        nodes[f].imports.push(resolved);
        nodes[resolved].imported_by.push(f);

        // Check if cross-subsystem
        const fromSubs = fileToSubs[f] || [];
        const toSubs = fileToSubs[resolved] || [];
        const fromNonShared = fromSubs.filter(s => s !== 'shared');
        const toNonShared = toSubs.filter(s => s !== 'shared');

        if (fromNonShared.length > 0 && toNonShared.length > 0) {
          const fromSet = new Set(fromNonShared);
          const toSet = new Set(toNonShared);
          const shared = [...fromSet].filter(x => toSet.has(x));
          if (shared.length === 0) {
            // Cross-subsystem flow
            crossFlows.push({
              from: f,
              to: resolved,
              from_sub: fromNonShared[0],
              to_sub: toNonShared[0],
              type: 'import',
            });
          }
        }
      }
    }
  }

  // Compute subsystem stats
  const subsystemStats: Record<string, { incoming: number; outgoing: number; internal: number }> = {};
  for (const sub of Object.keys(manifest.subsystems)) {
    subsystemStats[sub] = { incoming: 0, outgoing: 0, internal: 0 };
  }
  for (const flow of crossFlows) {
    subsystemStats[flow.from_sub].outgoing++;
    subsystemStats[flow.to_sub].incoming++;
  }
  for (const f of allFiles) {
    const subs = fileToSubs[f] || [];
    for (const sub of subs) {
      if (subsystemStats[sub]) {
        // Count internal flows
        for (const imp of nodes[f].imports) {
          const impSubs = fileToSubs[imp] || [];
          if (impSubs.includes(sub)) {
            subsystemStats[sub].internal++;
          }
        }
      }
    }
  }

  const output: Output = {
    generated_at: new Date().toISOString(),
    total_files: allFiles.length,
    total_flows: crossFlows.length,
    cross_subsystem_flows: crossFlows,
    nodes,
    subsystem_stats: subsystemStats,
  };

  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(output, null, 2));

  console.log(`=== Flow Trace Generated ===`);
  console.log(`Total files: ${allFiles.length}`);
  console.log(`Cross-subsystem flows: ${crossFlows.length}`);
  console.log(`Top cross-subsystem flows (by frequency):`);
  
  // Aggregate by subsystem pair
  const pairCounts = new Map<string, number>();
  for (const flow of crossFlows) {
    const key = `${flow.from_sub} → ${flow.to_sub}`;
    pairCounts.set(key, (pairCounts.get(key) || 0) + 1);
  }
  const sorted = [...pairCounts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10);
  for (const [pair, count] of sorted) {
    console.log(`  ${pair}: ${count} flows`);
  }
  console.log(`\nOutput: ${OUTPUT_PATH}`);
}

main();
