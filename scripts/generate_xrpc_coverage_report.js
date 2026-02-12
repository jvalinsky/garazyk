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
    lexiconRoots: [],
    sourceOnly: false,
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
    } else if (arg === "--lexicon-root") {
      args.lexiconRoots.push(argv[++index]);
    } else if (arg === "--source-only") {
      args.sourceOnly = true;
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
    "  --lexicon-root <p>   Lexicon root directory (repeatable)",
    "  --source-only        Ignore xrpcDir input files and parse from source",
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

function extractImplementedMethodsFromSource(registryPath, handlerPath) {
  ensureFileExists(registryPath);
  const source = fs.readFileSync(registryPath, "utf8");
  const methodMap = parseDispatcherMethodMap(handlerPath);
  const implementedRaw = [];
  const unresolvedTyped = [];

  const typedRegex = /\[dispatcher\s+(register[A-Za-z0-9]+)\s*:\s*\^\(/g;
  for (const match of source.matchAll(typedRegex)) {
    const registrationName = match[1];
    const methodId = methodMap.get(registrationName);
    if (methodId) {
      implementedRaw.push(methodId);
    } else {
      implementedRaw.push("unknown");
      unresolvedTyped.push(registrationName);
    }
  }

  const rawRegex = /\[dispatcher\s+registerMethod:\s*@"([^"]+)"\s+handler:\s*\^\(/g;
  for (const match of source.matchAll(rawRegex)) {
    implementedRaw.push(match[1]);
  }

  return {
    implementedRaw,
    unresolvedTyped: uniqueSorted(unresolvedTyped),
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

    const extracted = extractImplementedMethodsFromSource(args.registryPath, args.handlerPath);
    implementedRaw = extracted.implementedRaw;
    unresolvedTypedRegistrations = extracted.unresolvedTyped;

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
  const duplicateRegistrations = implementedFiltered.length - implementedUnique.length;
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
      lexicon_roots: inputMode === "source-parsed" ? args.lexiconRoots : null,
      unresolved_typed_registrations: unresolvedTypedRegistrations,
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
    },
    namespace_coverage: makeNamespaceCoverage(new Set(implementedInScope), new Set(lexiconUniqueInScope)),
    missing_in_code: missingInCode,
    missing_in_code_out_of_scope: missingInCodeOutOfScope,
    missing_in_lexicons: missingInLexicons,
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
}

main();
