#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function parseArgs(argv) {
  const args = {
    repoRoot: process.cwd(),
    xrpcDir: null,
    stubPath: null,
    outJson: null,
    outMd: null,
    scopeFile: null,
    registryPath: null,
    handlerPath: null,
    networkDir: null,
    lexiconRoots: [],
    sourceOnly: false,
    failOnDuplicates: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--repo-root") {
      args.repoRoot = argv[++index];
    } else if (arg === "--xrpc-dir") {
      args.xrpcDir = argv[++index];
    } else if (arg === "--stub-path") {
      args.stubPath = argv[++index];
    } else if (arg === "--out-json") {
      args.outJson = argv[++index];
    } else if (arg === "--out-md") {
      args.outMd = argv[++index];
    } else if (arg === "--scope-file") {
      args.scopeFile = argv[++index];
    } else if (arg === "--registry-path") {
      args.registryPath = argv[++index];
    } else if (arg === "--handler-path") {
      args.handlerPath = argv[++index];
    } else if (arg === "--network-dir") {
      args.networkDir = argv[++index];
    } else if (arg === "--lexicon-root") {
      args.lexiconRoots.push(argv[++index]);
    } else if (arg === "--source-only") {
      args.sourceOnly = true;
    } else if (arg === "--fail-on-duplicates") {
      args.failOnDuplicates = true;
    } else if (arg === "--help" || arg === "-h") {
      printUsageAndExit(0);
    } else {
      console.error(`Unknown argument: ${arg}`);
      printUsageAndExit(1);
    }
  }

  args.xrpcDir = args.xrpcDir || path.join(args.repoRoot, "reports", "xrpc_sync_raw");
  args.stubPath = args.stubPath || path.join(args.repoRoot, "reports", "stub_scan_raw", "stubs.json");
  args.outJson = args.outJson || path.join(args.repoRoot, "reports", "xrpc_coverage.json");
  args.outMd = args.outMd || path.join(args.repoRoot, "reports", "xrpc_coverage.md");
  args.scopeFile = args.scopeFile || path.join(args.repoRoot, "scripts", "xrpc_coverage_scope.txt");
  args.registryPath = args.registryPath || path.join(args.repoRoot, "ATProtoPDS", "Sources", "Network", "XrpcMethodRegistry.m");
  args.handlerPath = args.handlerPath || path.join(args.repoRoot, "ATProtoPDS", "Sources", "Network", "XrpcHandler.m");
  args.networkDir = args.networkDir || path.join(args.repoRoot, "ATProtoPDS", "Sources", "Network");
  if (args.lexiconRoots.length === 0) {
    args.lexiconRoots.push(path.join(args.repoRoot, "ATProtoPDS", "Resources", "lexicons"));
  }

  return args;
}

function printUsageAndExit(code) {
  const usage = [
    "Usage:",
    "  node scripts/generate_xrpc_coverage_report.js [options]",
    "",
    "Options:",
    "  --repo-root <path>   Repository root (default: cwd)",
    "  --xrpc-dir <path>    Directory with methods.tsv, lexicons.tsv, diff.json",
    "  --stub-path <path>   Path to stubs.json",
    "  --out-json <path>    Output JSON file path",
    "  --out-md <path>      Output Markdown file path",
    "  --scope-file <path>  Scope rules file (default: scripts/xrpc_coverage_scope.txt)",
    "  --registry-path <p>  XrpcMethodRegistry.m path",
    "  --handler-path <p>   XrpcHandler.m path",
    "  --network-dir <path> Network source directory for modular registrars",
    "  --lexicon-root <p>   Lexicon root directory (repeatable)",
    "  --source-only        Ignore xrpcDir input files and parse from source",
    "  --fail-on-duplicates Exit non-zero when scoped duplicate registrations are found",
  ].join("\n");
  console.error(usage);
  process.exit(code);
}

function ensureFileExists(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Required file not found: ${filePath}`);
  }
}

function readJson(filePath) {
  ensureFileExists(filePath);
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readJsonIfExists(filePath, fallbackValue) {
  if (!filePath || !fs.existsSync(filePath)) {
    return fallbackValue;
  }
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function parseTsv(filePath) {
  ensureFileExists(filePath);
  const content = fs.readFileSync(filePath, "utf8").trim();
  if (!content) {
    return [];
  }

  const lines = content.split(/\r?\n/);
  const headers = lines[0].split("\t");
  return lines.slice(1).filter(Boolean).map((line) => {
    const columns = line.split("\t");
    const row = {};
    headers.forEach((header, index) => {
      row[header] = columns[index] || "";
    });
    return row;
  });
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function globToRegExp(glob) {
  const escaped = escapeRegExp(glob).replace(/\\\*/g, ".*");
  return new RegExp(`^${escaped}$`);
}

function loadScopeConfig(scopeFilePath) {
  const defaultConfig = {
    source: "default",
    includes: ["com.atproto.*"],
    excludes: [],
  };

  if (!scopeFilePath || !fs.existsSync(scopeFilePath)) {
    return defaultConfig;
  }

  const content = fs.readFileSync(scopeFilePath, "utf8");
  const lines = content.split(/\r?\n/);
  const includes = [];
  const excludes = [];

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }
    if (line.startsWith("+")) {
      includes.push(line.slice(1).trim());
      continue;
    }
    if (line.startsWith("-")) {
      excludes.push(line.slice(1).trim());
      continue;
    }
    includes.push(line);
  }

  return {
    source: scopeFilePath,
    includes: includes.length > 0 ? includes : ["com.atproto.*"],
    excludes,
  };
}

function methodInScope(methodId, scopeConfig, includeRegexes, excludeRegexes) {
  const included = includeRegexes.length === 0
    ? true
    : includeRegexes.some((regex) => regex.test(methodId));
  if (!included) {
    return false;
  }
  return !excludeRegexes.some((regex) => regex.test(methodId));
}

function walkJsonFiles(rootDir) {
  if (!fs.existsSync(rootDir)) {
    return [];
  }
  const out = [];
  const stack = [rootDir];
  while (stack.length > 0) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
      } else if (entry.isFile() && entry.name.endsWith(".json")) {
        out.push(fullPath);
      }
    }
  }
  return out.sort();
}

function extractLexiconMethodsFromRoots(roots) {
  const methodIds = [];
  const errors = [];
  const filesScanned = [];
  for (const root of roots) {
    const files = walkJsonFiles(root);
    filesScanned.push(...files);
    for (const filePath of files) {
      try {
        const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
        const mainType = parsed && parsed.defs && parsed.defs.main && parsed.defs.main.type;
        if (mainType === "query" || mainType === "procedure" || mainType === "subscription") {
          if (typeof parsed.id === "string" && parsed.id.length > 0) {
            methodIds.push(parsed.id);
          }
        }
      } catch (error) {
        errors.push({ file: filePath, message: String(error && error.message ? error.message : error) });
      }
    }
  }
  return { methodIds, errors, filesScanned };
}

function parseDispatcherMethodMap(handlerPath) {
  ensureFileExists(handlerPath);
  const source = fs.readFileSync(handlerPath, "utf8");
  const map = new Map();
  const regex = /-\s*\(void\)\s*(register[A-Za-z0-9]+)\s*:\s*\(XrpcMethodHandler\)handler\s*\{\s*\[self registerMethod:@"([^"]+)" handler:handler\];\s*\}/gms;
  for (const match of source.matchAll(regex)) {
    map.set(match[1], match[2]);
  }
  return map;
}

function findMatchingBrace(source, openIndex) {
  let depth = 0;
  for (let index = openIndex; index < source.length; index += 1) {
    const ch = source[index];
    if (ch === "{") {
      depth += 1;
    } else if (ch === "}") {
      depth -= 1;
      if (depth === 0) {
        return index;
      }
    }
  }
  return -1;
}

function extractMethodIdsFromSourceSnippet(sourceSnippet, methodMap) {
  const methods = [];
  const unresolvedTyped = [];

  const typedRegex = /\[dispatcher\s+(register[A-Za-z0-9]+)\s*:\s*\^\(/g;
  for (const match of sourceSnippet.matchAll(typedRegex)) {
    const registrationName = match[1];
    const methodId = methodMap.get(registrationName);
    if (methodId) {
      methods.push(methodId);
    } else {
      methods.push("unknown");
      unresolvedTyped.push(registrationName);
    }
  }

  const rawRegex = /\[dispatcher\s+registerMethod:\s*@"([^"]+)"\s+handler:\s*\^\(/g;
  for (const match of sourceSnippet.matchAll(rawRegex)) {
    methods.push(match[1]);
  }

  return {
    methods,
    unresolvedTyped: uniqueSorted(unresolvedTyped),
  };
}

function duplicateMethodsForList(methods) {
  const counts = new Map();
  for (const methodId of methods) {
    if (methodId === "unknown") {
      continue;
    }
    counts.set(methodId, (counts.get(methodId) || 0) + 1);
  }
  return Array.from(counts.entries())
    .filter((entry) => entry[1] > 1)
    .sort((left, right) => {
      if (right[1] !== left[1]) {
        return right[1] - left[1];
      }
      return left[0].localeCompare(right[0]);
    })
    .map((entry) => ({ method_id: entry[0], count: entry[1] }));
}

function normalizeScopePair(leftScope, rightScope) {
  return [leftScope, rightScope].sort().join("|");
}

function computeCrossScopeDuplicateStats(scopeStats) {
  const methodScopes = new Map();
  for (const scopeStat of scopeStats) {
    const scopeName = scopeStat.scope;
    const methods = Array.isArray(scopeStat.methods) ? scopeStat.methods : [];
    for (const methodId of methods) {
      if (methodId === "unknown") {
        continue;
      }
      if (!methodScopes.has(methodId)) {
        methodScopes.set(methodId, new Set());
      }
      methodScopes.get(methodId).add(scopeName);
    }
  }

  const expectedScopePairSet = new Set([
    normalizeScopePair("class.registerMethodsWithDispatcher:controller", "class.registerMethodsWithDispatcher:application"),
  ]);

  const rawMethods = [];
  const expectedMethods = [];
  const unexpectedMethods = [];
  let rawCount = 0;
  let expectedCount = 0;
  let unexpectedCount = 0;

  for (const [methodId, scopesSet] of methodScopes.entries()) {
    const scopes = Array.from(scopesSet).sort();
    if (scopes.length <= 1) {
      continue;
    }

    const registrations = scopes.length - 1;
    const methodEntry = { method_id: methodId, count: scopes.length, scopes };
    rawMethods.push(methodEntry);
    rawCount += registrations;

    const expectedPairOnly = scopes.length === 2
      && expectedScopePairSet.has(normalizeScopePair(scopes[0], scopes[1]));
    if (expectedPairOnly) {
      expectedMethods.push(methodEntry);
      expectedCount += registrations;
    } else {
      unexpectedMethods.push(methodEntry);
      unexpectedCount += registrations;
    }
  }

  const sortByCountThenMethod = (left, right) => {
    if (right.count !== left.count) {
      return right.count - left.count;
    }
    return left.method_id.localeCompare(right.method_id);
  };

  rawMethods.sort(sortByCountThenMethod);
  expectedMethods.sort(sortByCountThenMethod);
  unexpectedMethods.sort(sortByCountThenMethod);

  return {
    raw_count: rawCount,
    expected_overlap_count: expectedCount,
    unexpected_duplicate_count: unexpectedCount,
    raw_methods: rawMethods,
    expected_methods: expectedMethods,
    unexpected_methods: unexpectedMethods,
  };
}

function registrarModuleFilesFromRegistry(registrySource, networkDir) {
  const moduleNames = new Set();
  const moduleRegex = /\[(Xrpc[A-Za-z0-9_]+)\s+registerWithDispatcher:/g;
  for (const match of registrySource.matchAll(moduleRegex)) {
    moduleNames.add(match[1]);
  }

  return Array.from(moduleNames)
    .sort()
    .map((moduleName) => path.join(networkDir, `${moduleName}.m`))
    .filter((candidatePath) => fs.existsSync(candidatePath));
}

function extractScopeStatsFromSources(sourceFiles, methodMap, rootDir) {
  const scopes = [];
  const implementedRaw = [];
  const unresolvedTyped = [];

  for (const sourcePath of sourceFiles) {
    ensureFileExists(sourcePath);
    const source = fs.readFileSync(sourcePath, "utf8");
    const extracted = extractMethodIdsFromSourceSnippet(source, methodMap);
    const filteredMethods = extracted.methods.filter((methodId) => methodId !== "unknown");
    const uniqueMethods = uniqueSorted(filteredMethods);
    const duplicateMethods = duplicateMethodsForList(extracted.methods);
    const duplicateRegistrations = duplicateMethods.reduce((sum, entry) => sum + (entry.count - 1), 0);
    const scopeName = path.relative(rootDir, sourcePath).replace(/\\/g, "/");

    scopes.push({
      scope: scopeName,
      registrations_total: filteredMethods.length,
      registrations_unique: uniqueMethods.length,
      methods: uniqueMethods,
      unknown_registry_entries: extracted.methods.filter((methodId) => methodId === "unknown").length,
      duplicate_registrations: duplicateRegistrations,
      duplicate_methods: duplicateMethods,
      unresolved_typed_registrations: extracted.unresolvedTyped,
    });

    implementedRaw.push(...extracted.methods);
    unresolvedTyped.push(...extracted.unresolvedTyped);
  }

  return {
    scopes,
    implementedRaw,
    unresolvedTyped: uniqueSorted(unresolvedTyped),
  };
}

function extractImplementedMethodsFromSource(registryPath, handlerPath, networkDir) {
  ensureFileExists(registryPath);
  const registrySource = fs.readFileSync(registryPath, "utf8");
  const methodMap = parseDispatcherMethodMap(handlerPath);
  const moduleFiles = registrarModuleFilesFromRegistry(registrySource, networkDir);
  const sourceFiles = [registryPath, ...moduleFiles];
  const extracted = extractScopeStatsFromSources(sourceFiles, methodMap, path.dirname(registryPath));
  const scopedDuplicateRegistrations = extracted.scopes.reduce((sum, scope) => sum + scope.duplicate_registrations, 0);
  const crossScopeDuplicateStats = computeCrossScopeDuplicateStats(extracted.scopes);

  return {
    implementedRaw: extracted.implementedRaw,
    unresolvedTyped: extracted.unresolvedTyped,
    registrationScopeStats: extracted.scopes,
    parsedSourceFiles: sourceFiles,
    scopedDuplicateRegistrations,
    crossScopeDuplicateStats,
  };
}

function uniqueSorted(values) {
  return Array.from(new Set(values)).sort();
}

function toPercent(numerator, denominator) {
  if (denominator === 0) {
    return null;
  }
  return Number(((numerator / denominator) * 100).toFixed(2));
}

function namespaceForMethod(methodId) {
  if (!methodId || methodId === "unknown") {
    return "unknown";
  }
  const parts = methodId.split(".");
  if (parts.length < 2) {
    return "unknown";
  }
  return `${parts[0]}.${parts[1]}`;
}

function methodsByNamespace(methodIds) {
  const map = new Map();
  methodIds.forEach((methodId) => {
    const namespace = namespaceForMethod(methodId);
    if (!map.has(namespace)) {
      map.set(namespace, new Set());
    }
    map.get(namespace).add(methodId);
  });
  return map;
}

function makeNamespaceCoverage(implementedSet, lexiconSet) {
  const implementedByNs = methodsByNamespace(Array.from(implementedSet));
  const lexiconByNs = methodsByNamespace(Array.from(lexiconSet));

  const namespaces = uniqueSorted([
    ...Array.from(implementedByNs.keys()),
    ...Array.from(lexiconByNs.keys()),
  ]);

  return namespaces.map((namespace) => {
    const implemented = implementedByNs.get(namespace) || new Set();
    const lexicon = lexiconByNs.get(namespace) || new Set();

    let inBoth = 0;
    lexicon.forEach((methodId) => {
      if (implemented.has(methodId)) {
        inBoth += 1;
      }
    });

    const missingInCode = Array.from(lexicon).filter((methodId) => !implemented.has(methodId)).sort();
    const missingInLexicons = Array.from(implemented).filter((methodId) => !lexicon.has(methodId)).sort();

    return {
      namespace,
      lexicon_methods: lexicon.size,
      implemented_methods: implemented.size,
      in_both: inBoth,
      missing_in_code_count: missingInCode.length,
      missing_in_lexicons_count: missingInLexicons.length,
      coverage_pct: toPercent(inBoth, lexicon.size),
    };
  }).sort((left, right) => {
    if (right.missing_in_code_count !== left.missing_in_code_count) {
      return right.missing_in_code_count - left.missing_in_code_count;
    }
    return left.namespace.localeCompare(right.namespace);
  });
}

function createMarkdown(report) {
  const lines = [];
  lines.push("# XRPC Coverage Report");
  lines.push("");
  lines.push(`Generated: ${report.generated_at}`);
  lines.push("");
  lines.push("## Summary");
  lines.push("");
  lines.push(`- Implemented methods (unique, excluding \`unknown\`): ${report.counts.implemented_unique}`);
  lines.push(`- Lexicon XRPC methods (unique, all scopes): ${report.counts.lexicon_unique_total}`);
  lines.push(`- Lexicon XRPC methods (in scope): ${report.counts.lexicon_unique_in_scope}`);
  lines.push(`- Implemented and in lexicons (in scope): ${report.counts.in_both_in_scope}`);
  lines.push(`- Missing in code (in scope): ${report.counts.missing_in_code}`);
  lines.push(`- Implemented but missing lexicon (in scope): ${report.counts.missing_in_lexicons}`);
  lines.push(`- Coverage (in scope, implemented / lexicon): ${report.counts.coverage_pct}%`);
  lines.push(`- Missing in code (out of scope): ${report.counts.missing_in_code_out_of_scope}`);
  lines.push(`- Unknown registry entries: ${report.counts.unknown_registry_entries}`);
  lines.push(`- Duplicate registry registrations: ${report.counts.duplicate_registry_registrations}`);
  if (typeof report.counts.duplicate_registry_registrations_cross_scope === "number") {
    lines.push(`- Duplicate registry registrations (cross-scope, actionable): ${report.counts.duplicate_registry_registrations_cross_scope}`);
  }
  if (typeof report.counts.duplicate_registry_registrations_cross_scope_expected === "number") {
    lines.push(`- Cross-scope overlap (expected controller/application dual-path): ${report.counts.duplicate_registry_registrations_cross_scope_expected}`);
  }
  if (typeof report.counts.duplicate_registry_registrations_cross_scope_raw === "number") {
    lines.push(`- Cross-scope overlap (raw total): ${report.counts.duplicate_registry_registrations_cross_scope_raw}`);
  }
  lines.push("");
  lines.push("## Namespace Coverage");
  lines.push("");
  lines.push("| Namespace | Lexicon | Implemented | In Both | Coverage | Missing In Code |");
  lines.push("|---|---:|---:|---:|---:|---:|");
  report.namespace_coverage.forEach((entry) => {
    const coverage = entry.coverage_pct === null ? "n/a" : `${entry.coverage_pct}%`;
    lines.push(`| ${entry.namespace} | ${entry.lexicon_methods} | ${entry.implemented_methods} | ${entry.in_both} | ${coverage} | ${entry.missing_in_code_count} |`);
  });
  lines.push("");
  lines.push("## Missing In Code (Top 60, In Scope)");
  lines.push("");
  report.missing_in_code.slice(0, 60).forEach((methodId) => {
    lines.push(`- \`${methodId}\``);
  });
  lines.push("");
  lines.push("## Missing In Code (Top 40, Out Of Scope)");
  lines.push("");
  report.missing_in_code_out_of_scope.slice(0, 40).forEach((methodId) => {
    lines.push(`- \`${methodId}\``);
  });
  lines.push("");
  lines.push("## Implemented But Missing Lexicon");
  lines.push("");
  report.missing_in_lexicons.forEach((methodId) => {
    lines.push(`- \`${methodId}\``);
  });
  lines.push("");
  lines.push("## Scope");
  lines.push("");
  lines.push(`- Scope config source: \`${report.scope.source}\``);
  lines.push(`- Include globs: ${report.scope.includes.map((glob) => `\`${glob}\``).join(", ") || "(none)"}`);
  lines.push(`- Exclude globs: ${report.scope.excludes.map((glob) => `\`${glob}\``).join(", ") || "(none)"}`);
  lines.push("");
  lines.push("## Stub Scan");
  lines.push("");
  lines.push(`- \`not_implemented\` hits: ${report.stub_scan.not_implemented_count}`);
  lines.push(`- \`todo_fixme\` hits: ${report.stub_scan.todo_fixme_count}`);
  lines.push(`- \`stub_markers\` hits: ${report.stub_scan.stub_markers_count}`);
  lines.push(`- XRPC-related stub markers: ${report.stub_scan.xrpc_related_stub_markers_count}`);
  lines.push("");
  lines.push("## Inputs");
  lines.push("");
  lines.push(`- Input mode: \`${report.inputs.mode}\``);
  if (report.inputs.methods_tsv) {
    lines.push(`- \`${report.inputs.methods_tsv}\``);
  }
  if (report.inputs.lexicons_tsv) {
    lines.push(`- \`${report.inputs.lexicons_tsv}\``);
  }
  if (report.inputs.diff_json) {
    lines.push(`- \`${report.inputs.diff_json}\``);
  }
  if (report.inputs.registry_source) {
    lines.push(`- \`${report.inputs.registry_source}\``);
  }
  if (report.inputs.handler_source) {
    lines.push(`- \`${report.inputs.handler_source}\``);
  }
  if (report.inputs.network_source_dir) {
    lines.push(`- \`${report.inputs.network_source_dir}\``);
  }
  if (Array.isArray(report.inputs.parsed_source_files)) {
    report.inputs.parsed_source_files.forEach((sourcePath) => {
      lines.push(`- \`${sourcePath}\``);
    });
  }
  if (Array.isArray(report.inputs.lexicon_roots)) {
    report.inputs.lexicon_roots.forEach((root) => {
      lines.push(`- \`${root}\``);
    });
  }
  lines.push(`- \`${report.inputs.stubs_json}\``);
  lines.push("");
  if (Array.isArray(report.inputs.unresolved_typed_registrations) && report.inputs.unresolved_typed_registrations.length > 0) {
    lines.push("## Unresolved Typed Registrations");
    lines.push("");
    report.inputs.unresolved_typed_registrations.forEach((entry) => {
      lines.push(`- \`${entry}\``);
    });
    lines.push("");
  }
  if (Array.isArray(report.registration_scope_stats) && report.registration_scope_stats.length > 0) {
    lines.push("## Registration Scope Duplicates");
    lines.push("");
    report.registration_scope_stats.forEach((scopeStat) => {
      lines.push(`### ${scopeStat.scope}`);
      lines.push("");
      lines.push(`- Duplicate registrations: ${scopeStat.duplicate_registrations}`);
      lines.push(`- Unknown registrations: ${scopeStat.unknown_registry_entries}`);
      const topMethods = (scopeStat.duplicate_methods || []).slice(0, 8);
      if (topMethods.length > 0) {
        lines.push("- Top duplicate methods:");
        topMethods.forEach((entry) => {
          lines.push(`  - \`${entry.method_id}\` (${entry.count}x)`);
        });
      }
      lines.push("");
    });
  }
  if (report.cross_scope_duplicates && Array.isArray(report.cross_scope_duplicates.unexpected_methods)) {
    lines.push("## Cross-Scope Duplicate Methods (Actionable)");
    lines.push("");
    if (report.cross_scope_duplicates.unexpected_methods.length === 0) {
      lines.push("- none");
    } else {
      report.cross_scope_duplicates.unexpected_methods.slice(0, 20).forEach((entry) => {
        lines.push(`- \`${entry.method_id}\` (${entry.count} scopes: ${entry.scopes.join(", ")})`);
      });
    }
    lines.push("");
  }
  if (report.cross_scope_duplicates && Array.isArray(report.cross_scope_duplicates.expected_methods)) {
    lines.push("## Cross-Scope Overlap (Expected)");
    lines.push("");
    lines.push(`- Methods overlapping between controller/application registrations: ${report.cross_scope_duplicates.expected_methods.length}`);
    lines.push("");
  }
  return `${lines.join("\n")}\n`;
}

function main() {
  const args = parseArgs(process.argv.slice(2));

  const methodsTsv = path.join(args.xrpcDir, "methods.tsv");
  const lexiconsTsv = path.join(args.xrpcDir, "lexicons.tsv");
  const diffJson = path.join(args.xrpcDir, "diff.json");

  let inputMode = "legacy-tsv";
  let implementedRaw = [];
  let lexiconUniqueAll = [];
  let unresolvedTypedRegistrations = [];
  let registrationScopeStats = [];
  let parsedSourceFiles = [];
  let scopedDuplicateRegistrations = null;
  let crossScopeDuplicateStats = null;
  const lexiconParseErrors = [];
  let methodsTsvUsed = methodsTsv;
  let lexiconsTsvUsed = lexiconsTsv;
  let diffJsonUsed = diffJson;

  const canUseLegacy = !args.sourceOnly
    && fs.existsSync(methodsTsv)
    && fs.existsSync(lexiconsTsv)
    && fs.existsSync(diffJson);

  if (canUseLegacy) {
    const methodRows = parseTsv(methodsTsv);
    const lexiconRows = parseTsv(lexiconsTsv);
    implementedRaw = methodRows.map((row) => row.method_id).filter(Boolean);
    lexiconUniqueAll = uniqueSorted(lexiconRows.map((row) => row.method_id).filter(Boolean));
  } else {
    inputMode = "source-parsed";
    methodsTsvUsed = null;
    lexiconsTsvUsed = null;
    diffJsonUsed = null;

    const extracted = extractImplementedMethodsFromSource(args.registryPath, args.handlerPath, args.networkDir);
    implementedRaw = extracted.implementedRaw;
    unresolvedTypedRegistrations = extracted.unresolvedTyped;
    registrationScopeStats = extracted.registrationScopeStats;
    parsedSourceFiles = extracted.parsedSourceFiles;
    scopedDuplicateRegistrations = extracted.scopedDuplicateRegistrations;
    crossScopeDuplicateStats = extracted.crossScopeDuplicateStats;

    const lexiconExtract = extractLexiconMethodsFromRoots(args.lexiconRoots);
    lexiconUniqueAll = uniqueSorted(lexiconExtract.methodIds);
    lexiconParseErrors.push(...lexiconExtract.errors);
  }

  const scopeConfig = loadScopeConfig(args.scopeFile);
  const includeRegexes = scopeConfig.includes.map(globToRegExp);
  const excludeRegexes = scopeConfig.excludes.map(globToRegExp);
  const inScope = (methodId) => methodInScope(methodId, scopeConfig, includeRegexes, excludeRegexes);

  const stubs = readJsonIfExists(args.stubPath, {});
  const unknownRegistryEntries = implementedRaw.filter((methodId) => methodId === "unknown").length;
  const implementedFiltered = implementedRaw.filter((methodId) => methodId !== "unknown");
  const implementedUnique = uniqueSorted(implementedFiltered);
  const duplicateRegistrationsCrossScopeRaw = implementedFiltered.length - implementedUnique.length;
  const duplicateRegistrationsCrossScopeExpected = crossScopeDuplicateStats
    ? crossScopeDuplicateStats.expected_overlap_count
    : null;
  const duplicateRegistrationsCrossScope = crossScopeDuplicateStats
    ? crossScopeDuplicateStats.unexpected_duplicate_count
    : duplicateRegistrationsCrossScopeRaw;
  const duplicateRegistrations = typeof scopedDuplicateRegistrations === "number"
    ? scopedDuplicateRegistrations
    : duplicateRegistrationsCrossScopeRaw;
  const implementedInScope = uniqueSorted(implementedUnique.filter(inScope));
  const lexiconUniqueInScope = uniqueSorted(lexiconUniqueAll.filter(inScope));

  const implementedSetInScope = new Set(implementedInScope);
  const lexiconSetInScope = new Set(lexiconUniqueInScope);

  let inBothInScope = 0;
  lexiconSetInScope.forEach((methodId) => {
    if (implementedSetInScope.has(methodId)) {
      inBothInScope += 1;
    }
  });

  const missingInCode = lexiconUniqueInScope.filter((methodId) => !implementedSetInScope.has(methodId));
  const missingInLexicons = implementedInScope.filter((methodId) => !lexiconSetInScope.has(methodId));

  const lexiconOutOfScope = lexiconUniqueAll.filter((methodId) => !inScope(methodId));
  const implementedOutOfScope = implementedUnique.filter((methodId) => !inScope(methodId));
  const implementedOutOfScopeSet = new Set(implementedOutOfScope);
  const missingInCodeOutOfScope = lexiconOutOfScope.filter((methodId) => !implementedOutOfScopeSet.has(methodId));

  const stubMarkers = Array.isArray(stubs.stub_markers) ? stubs.stub_markers : [];
  const xrpcRelatedStubMarkers = stubMarkers.filter((hit) => {
    const text = `${hit.file || ""} ${hit.match || ""}`;
    return /XrpcMethodRegistry|com\.atproto|app\.bsky|chat\.bsky|tools\.ozone/.test(text);
  });

  const report = {
    generated_at: new Date().toISOString(),
    inputs: {
      mode: inputMode,
      methods_tsv: methodsTsvUsed,
      lexicons_tsv: lexiconsTsvUsed,
      diff_json: diffJsonUsed,
      registry_source: inputMode === "source-parsed" ? args.registryPath : null,
      handler_source: inputMode === "source-parsed" ? args.handlerPath : null,
      network_source_dir: inputMode === "source-parsed" ? args.networkDir : null,
      parsed_source_files: inputMode === "source-parsed" ? parsedSourceFiles : null,
      lexicon_roots: inputMode === "source-parsed" ? args.lexiconRoots : null,
      unresolved_typed_registrations: unresolvedTypedRegistrations,
      registration_scopes: inputMode === "source-parsed" ? registrationScopeStats.map((entry) => entry.scope) : null,
      lexicon_parse_errors: lexiconParseErrors,
      stubs_json: args.stubPath,
    },
    scope: scopeConfig,
    counts: {
      implemented_unique: implementedUnique.length,
      lexicon_unique_total: lexiconUniqueAll.length,
      lexicon_unique_in_scope: lexiconUniqueInScope.length,
      in_both_in_scope: inBothInScope,
      missing_in_code: missingInCode.length,
      missing_in_lexicons: missingInLexicons.length,
      missing_in_code_out_of_scope: missingInCodeOutOfScope.length,
      coverage_pct: toPercent(inBothInScope, lexiconUniqueInScope.length),
      unknown_registry_entries: unknownRegistryEntries,
      duplicate_registry_registrations: duplicateRegistrations,
      duplicate_registry_registrations_cross_scope: duplicateRegistrationsCrossScope,
      duplicate_registry_registrations_cross_scope_expected: duplicateRegistrationsCrossScopeExpected,
      duplicate_registry_registrations_cross_scope_raw: duplicateRegistrationsCrossScopeRaw,
    },
    namespace_coverage: makeNamespaceCoverage(new Set(implementedInScope), new Set(lexiconUniqueInScope)),
    missing_in_code: missingInCode,
    missing_in_code_out_of_scope: missingInCodeOutOfScope,
    missing_in_lexicons: missingInLexicons,
    registration_scope_stats: registrationScopeStats,
    cross_scope_duplicates: crossScopeDuplicateStats,
    stub_scan: {
      not_implemented_count: Array.isArray(stubs.not_implemented) ? stubs.not_implemented.length : 0,
      todo_fixme_count: Array.isArray(stubs.todo_fixme) ? stubs.todo_fixme.length : 0,
      stub_markers_count: stubMarkers.length,
      xrpc_related_stub_markers_count: xrpcRelatedStubMarkers.length,
      xrpc_related_stub_markers: xrpcRelatedStubMarkers,
    },
  };

  fs.mkdirSync(path.dirname(args.outJson), { recursive: true });
  fs.writeFileSync(args.outJson, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  fs.writeFileSync(args.outMd, createMarkdown(report), "utf8");

  console.log(`Wrote ${args.outJson}`);
  console.log(`Wrote ${args.outMd}`);

  if (args.failOnDuplicates && duplicateRegistrations > 0) {
    console.error(`Scoped duplicate XRPC registrations found: ${duplicateRegistrations}`);
    process.exitCode = 2;
  }
}

main();
