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
  lines.push(`- Lexicon XRPC methods (unique): ${report.counts.lexicon_unique}`);
  lines.push(`- Implemented and in lexicons: ${report.counts.in_both}`);
  lines.push(`- Missing in code: ${report.counts.missing_in_code}`);
  lines.push(`- Implemented but missing lexicon: ${report.counts.missing_in_lexicons}`);
  lines.push(`- Overall coverage (implemented / lexicon): ${report.counts.coverage_pct}%`);
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
  lines.push("## Missing In Code (Top 60)");
  lines.push("");
  report.missing_in_code.slice(0, 60).forEach((methodId) => {
    lines.push(`- \`${methodId}\``);
  });
  lines.push("");
  lines.push("## Implemented But Missing Lexicon");
  lines.push("");
  report.missing_in_lexicons.forEach((methodId) => {
    lines.push(`- \`${methodId}\``);
  });
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
  lines.push(`- \`${report.inputs.methods_tsv}\``);
  lines.push(`- \`${report.inputs.lexicons_tsv}\``);
  lines.push(`- \`${report.inputs.diff_json}\``);
  lines.push(`- \`${report.inputs.stubs_json}\``);
  lines.push("");
  return `${lines.join("\n")}\n`;
}

function main() {
  const args = parseArgs(process.argv.slice(2));

  const methodsTsv = path.join(args.xrpcDir, "methods.tsv");
  const lexiconsTsv = path.join(args.xrpcDir, "lexicons.tsv");
  const diffJson = path.join(args.xrpcDir, "diff.json");

  const methodRows = parseTsv(methodsTsv);
  const lexiconRows = parseTsv(lexiconsTsv);
  const diff = readJson(diffJson);
  const stubs = readJson(args.stubPath);

  const implementedRaw = methodRows.map((row) => row.method_id).filter(Boolean);
  const unknownRegistryEntries = implementedRaw.filter((methodId) => methodId === "unknown").length;
  const implementedFiltered = implementedRaw.filter((methodId) => methodId !== "unknown");
  const implementedUnique = uniqueSorted(implementedFiltered);
  const duplicateRegistrations = implementedFiltered.length - implementedUnique.length;
  const lexiconUnique = uniqueSorted(lexiconRows.map((row) => row.method_id).filter(Boolean));

  const implementedSet = new Set(implementedUnique);
  const lexiconSet = new Set(lexiconUnique);

  let inBoth = 0;
  lexiconSet.forEach((methodId) => {
    if (implementedSet.has(methodId)) {
      inBoth += 1;
    }
  });

  const missingInCode = uniqueSorted((diff.missing_in_code || []).filter((methodId) => methodId !== "unknown"));
  const missingInLexicons = uniqueSorted((diff.missing_in_lexicons || []).filter((methodId) => methodId !== "unknown"));

  const stubMarkers = Array.isArray(stubs.stub_markers) ? stubs.stub_markers : [];
  const xrpcRelatedStubMarkers = stubMarkers.filter((hit) => {
    const text = `${hit.file || ""} ${hit.match || ""}`;
    return /XrpcMethodRegistry|com\.atproto|app\.bsky|chat\.bsky|tools\.ozone/.test(text);
  });

  const report = {
    generated_at: new Date().toISOString(),
    inputs: {
      methods_tsv: methodsTsv,
      lexicons_tsv: lexiconsTsv,
      diff_json: diffJson,
      stubs_json: args.stubPath,
    },
    counts: {
      implemented_unique: implementedUnique.length,
      lexicon_unique: lexiconUnique.length,
      in_both: inBoth,
      missing_in_code: missingInCode.length,
      missing_in_lexicons: missingInLexicons.length,
      coverage_pct: toPercent(inBoth, lexiconUnique.length),
      unknown_registry_entries: unknownRegistryEntries,
      duplicate_registry_registrations: duplicateRegistrations,
    },
    namespace_coverage: makeNamespaceCoverage(implementedSet, lexiconSet),
    missing_in_code: missingInCode,
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
