#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function parseArgs(argv) {
  const args = {
    repoRoot: process.cwd(),
    coverageJson: null,
    outJson: null,
    outMd: null,
    testDir: null,
    scenarioDir: null,
    lexiconRoots: [],
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--repo-root") args.repoRoot = argv[++i];
    else if (arg === "--coverage-json") args.coverageJson = argv[++i];
    else if (arg === "--out-json") args.outJson = argv[++i];
    else if (arg === "--out-md") args.outMd = argv[++i];
    else if (arg === "--test-dir") args.testDir = argv[++i];
    else if (arg === "--scenario-dir") args.scenarioDir = argv[++i];
    else if (arg === "--lexicon-root") args.lexiconRoots.push(argv[++i]);
    else if (arg === "--help" || arg === "-h") {
      console.log(
        "Usage: node generate_xrpc_split_metrics.cjs [--repo-root <path>] [--coverage-json <path>]"
      );
      process.exit(0);
    }
  }

  args.coverageJson =
    args.coverageJson ||
    path.join(args.repoRoot, "reports", "xrpc_coverage.json");
  args.outJson =
    args.outJson ||
    path.join(args.repoRoot, "reports", "xrpc_split_metrics.json");
  args.outMd =
    args.outMd || path.join(args.repoRoot, "reports", "xrpc_split_metrics.md");
  args.testDir =
    args.testDir || path.join(args.repoRoot, "Garazyk", "Tests");
  args.scenarioDir =
    args.scenarioDir ||
    path.join(args.repoRoot, "scripts", "scenarios", "scenarios");
  if (args.lexiconRoots.length === 0) {
    args.lexiconRoots.push(
      path.join(args.repoRoot, "Garazyk", "Resources", "lexicons")
    );
  }

  return args;
}

function walkJsonFiles(rootDir) {
  const out = [];
  if (!fs.existsSync(rootDir)) return out;
  const stack = [rootDir];
  while (stack.length > 0) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) stack.push(fullPath);
      else if (entry.isFile() && entry.name.endsWith(".json"))
        out.push(fullPath);
    }
  }
  return out.sort();
}

function walkTextFiles(dir, exts) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  const stack = [dir];
  while (stack.length > 0) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) stack.push(fullPath);
      else if (entry.isFile() && exts.some((e) => entry.name.endsWith(e)))
        out.push(fullPath);
    }
  }
  return out.sort();
}

function extractLexiconSchemaDetails(lexiconRoots) {
  const byMethod = new Map();
  const errors = [];
  for (const root of lexiconRoots) {
    for (const filePath of walkJsonFiles(root)) {
      try {
        const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
        const main = parsed && parsed.defs && parsed.defs.main;
        if (!main) continue;
        if (
          main.type !== "query" &&
          main.type !== "procedure" &&
          main.type !== "subscription"
        )
          continue;
        if (typeof parsed.id !== "string" || parsed.id.length === 0) continue;

        const hasInput = !!(main.input && main.input.schema);
        const hasOutput = !!(main.output && main.output.schema);
        const hasParameters = !!main.parameters;
        const hasErrors =
          Array.isArray(main.errors) && main.errors.length > 0;
        const inputRequired = hasInput
          ? main.input.schema.required || []
          : [];
        const outputRequired = hasOutput
          ? main.output.schema.required || []
          : [];

        byMethod.set(parsed.id, {
          id: parsed.id,
          type: main.type,
          has_input: hasInput,
          has_output: hasOutput,
          has_parameters: hasParameters,
          has_errors: hasErrors,
          input_required_count: inputRequired.length,
          output_required_count: outputRequired.length,
          file: path.relative(path.join(root, "..", ".."), filePath),
        });
      } catch (err) {
        errors.push({
          file: filePath,
          message: String(err.message || err),
        });
      }
    }
  }
  return { byMethod, errors };
}

function isNsidLike(str) {
  if (!str || str.length < 5) return false;
  const parts = str.split(".");
  if (parts.length < 3) return false;
  if (!/^[a-z]/.test(str)) return false;
  if (str.includes("/") || str.includes(" ") || str.includes("\\"))
    return false;
  return true;
}

function extractTestCoverage(testDir, scenarioDir) {
  const testFiles = walkTextFiles(testDir, [".m", ".h"]);
  const scenarioFiles = walkTextFiles(scenarioDir, [".ts"]);

  // ObjC: @"com.atproto.server.describeServer"
  // Match all @"..."  strings and filter for NSID-like
  const testNsidRefs = new Set();
  for (const filePath of testFiles) {
    try {
      const content = fs.readFileSync(filePath, "utf8");
      for (const m of content.matchAll(/@\"([^\"]+)\"/g)) {
        if (isNsidLike(m[1])) testNsidRefs.add(m[1]);
      }
    } catch (_) {}
  }

  // TypeScript: "com.atproto.server.describeServer" or '...' or `...`
  const scenarioNsidRefs = new Set();
  for (const filePath of scenarioFiles) {
    try {
      const content = fs.readFileSync(filePath, "utf8");
      // String literals
      for (const m of content.matchAll(/["'`]([^"'`]+)["'`]/g)) {
        if (isNsidLike(m[1])) scenarioNsidRefs.add(m[1]);
      }
      // .api. property chains: client.api.com.atproto.server.getSession()
      for (const m of content.matchAll(
        /\.api\.((com|app|chat|tools)\.[a-z][a-z0-9.]*)/g
      )) {
        const nsid = m[0].slice(5); // skip ".api."
        if (isNsidLike(nsid)) scenarioNsidRefs.add(nsid);
      }
    } catch (_) {}
  }

  return {
    test_files_scanned: testFiles.length,
    scenario_files_scanned: scenarioFiles.length,
    test_nsid_refs: testNsidRefs,
    scenario_nsid_refs: scenarioNsidRefs,
    behavior_verified: new Set([...testNsidRefs, ...scenarioNsidRefs]),
  };
}

function classifyStaticVsDynamic(implementedSet, lexiconSchemaDetails) {
  const staticNamespaces = new Set([
    "com.atproto",
    "app.bsky",
    "chat.bsky",
    "tools.ozone",
  ]);
  const dynamicNamespaces = new Set();

  const staticRoutes = [];
  const dynamicRoutes = [];
  const garazykExtensions = [];

  for (const methodId of implementedSet) {
    const parts = methodId.split(".");
    const ns2 = `${parts[0]}.${parts[1]}`;

    if (methodId.startsWith("tools.garazyk.")) {
      garazykExtensions.push(methodId);
    }

    if (staticNamespaces.has(ns2)) {
      staticRoutes.push(methodId);
    } else {
      dynamicRoutes.push(methodId);
    }
  }

  return {
    static_routes: staticRoutes,
    dynamic_routes: dynamicRoutes,
    garazyk_extensions: garazykExtensions,
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!fs.existsSync(args.coverageJson)) {
    console.error(`Coverage JSON not found: ${args.coverageJson}`);
    console.error(
      "Run generate_xrpc_coverage_report.cjs first to produce the base report."
    );
    process.exit(1);
  }

  const coverage = JSON.parse(fs.readFileSync(args.coverageJson, "utf8"));
  const implementedUnique = new Set(
    coverage.missing_in_lexicons || []
  );
  // Reconstruct implemented set from coverage data
  // in_both_in_scope + missing_in_lexicons = implemented in scope
  // We need the full implemented list. Let's get it from the coverage report.
  // The coverage report has missing_in_code (lexicon -> not implemented)
  // and missing_in_lexicons (implemented -> not in lexicon)
  // We need the full implemented list. Let's extract it from the registration scope stats.
  const allImplemented = new Set();
  if (coverage.registration_scope_stats) {
    for (const scope of coverage.registration_scope_stats) {
      if (scope.methods) {
        for (const m of scope.methods) allImplemented.add(m);
      }
    }
  }

  // Also reconstruct from cross-scope duplicates
  if (coverage.cross_scope_duplicates) {
    for (const list of [
      coverage.cross_scope_duplicates.raw_methods,
      coverage.cross_scope_duplicates.expected_methods,
    ]) {
      if (Array.isArray(list)) {
        for (const m of list) allImplemented.add(m);
      }
    }
  }

  // Get the in-scope implemented set
  const scopeConfig = coverage.scope || {};
  const includes = scopeConfig.includes || ["com.atproto.*", "app.bsky.*"];
  const excludes = scopeConfig.excludes || ["app.bsky.unspecced.*"];

  function inScope(methodId) {
    for (const exc of excludes) {
      const pattern = exc.replace(/\*/g, ".*");
      if (new RegExp(`^${pattern}$`).test(methodId)) return false;
    }
    for (const inc of includes) {
      const pattern = inc.replace(/\*/g, ".*");
      if (new RegExp(`^${pattern}$`).test(methodId)) return true;
    }
    return false;
  }

  const implementedInScope = allImplemented.size > 0
    ? Array.from(allImplemented).filter((m) => inScope(m))
    : [];

  // 1. Schema-covered: Check lexicon files for input/output/parameters
  const lexiconDetails = extractLexiconSchemaDetails(args.lexiconRoots);

  // Count schema-covered in scope
  const schemaCoveredInScope = implementedInScope.filter((m) => {
    const detail = lexiconDetails.byMethod.get(m);
    return detail && (detail.has_input || detail.has_output || detail.has_parameters);
  });
  const schemaFullInScope = implementedInScope.filter((m) => {
    const detail = lexiconDetails.byMethod.get(m);
    return detail && detail.has_input && detail.has_output;
  });

  // 2. Behavior-verified: Extract NSID references from test and scenario files
  const testCoverage = extractTestCoverage(args.testDir, args.scenarioDir);
  const behaviorVerifiedInScope = implementedInScope.filter((m) =>
    testCoverage.behavior_verified.has(m)
  );

  // 3. Static vs dynamic routes
  const classification = classifyStaticVsDynamic(
    new Set(implementedInScope),
    lexiconDetails
  );

  // Build the report
  const implementedSet = new Set(implementedInScope);
  const schemaDetailEntries = [];
  for (const m of implementedInScope) {
    const detail = lexiconDetails.byMethod.get(m);
    if (detail) {
      schemaDetailEntries.push(detail);
    } else {
      schemaDetailEntries.push({
        id: m,
        type: "unknown",
        has_input: false,
        has_output: false,
        has_parameters: false,
        has_errors: false,
        input_required_count: 0,
        output_required_count: 0,
        file: null,
      });
    }
  }

  // Methods missing from lexicons entirely (schema-gap)
  const schemaGapInScope = implementedInScope.filter(
    (m) => !lexiconDetails.byMethod.has(m)
  );

  // Methods in lexicons but not schema-covered (no input/output)
  const schemaPartialInScope = implementedInScope.filter((m) => {
    const detail = lexiconDetails.byMethod.get(m);
    return detail && !detail.has_input && !detail.has_output && !detail.has_parameters;
  });

  const report = {
    generated_at: new Date().toISOString(),
    baseline_commit: coverage.generated_at
      ? `from coverage report at ${coverage.generated_at}`
      : "unknown",
    counts: {
      implemented_in_scope: implementedInScope.length,
      schema_covered: schemaCoveredInScope.length,
      schema_full: schemaFullInScope.length,
      schema_partial: schemaPartialInScope.length,
      schema_gap: schemaGapInScope.length,
      behavior_verified: behaviorVerifiedInScope.length,
      behavior_test_only: testCoverage.test_nsid_refs.size,
      behavior_scenario_only: testCoverage.scenario_nsid_refs.size,
      static_routes: classification.static_routes.length,
      dynamic_routes: classification.dynamic_routes.length,
      garazyk_extensions: classification.garazyk_extensions.length,
    },
    per_method: schemaDetailEntries.map((d) => ({
      id: d.id,
      type: d.type,
      has_input: d.has_input,
      has_output: d.has_output,
      has_parameters: d.has_parameters,
      has_errors: d.has_errors,
      behavior_verified:
        testCoverage.behavior_verified.has(d.id),
      in_test: testCoverage.test_nsid_refs.has(d.id),
      in_scenario: testCoverage.scenario_nsid_refs.has(d.id),
      is_static: classification.static_routes.includes(d.id),
      is_dynamic: classification.dynamic_routes.includes(d.id),
      is_garazyk_ext: classification.garazyk_extensions.includes(d.id),
    })),
    schema_gap: schemaGapInScope,
    schema_partial: schemaPartialInScope,
    garazyk_extensions: classification.garazyk_extensions,
    test_files_scanned: testCoverage.test_files_scanned,
    scenario_files_scanned: testCoverage.scenario_files_scanned,
    lexicon_parse_errors: lexiconDetails.errors,
  };

  fs.mkdirSync(path.dirname(args.outJson), { recursive: true });
  fs.writeFileSync(args.outJson, JSON.stringify(report, null, 2) + "\n", "utf8");
  fs.writeFileSync(args.outMd, createMarkdown(report), "utf8");

  console.log(`Wrote ${args.outJson}`);
  console.log(`Wrote ${args.outMd}`);

  // Print summary
  const c = report.counts;
  console.log(`\n=== Split Metrics Summary (in-scope) ===`);
  console.log(`Implemented:          ${c.implemented_in_scope}`);
  console.log(`Schema covered:       ${c.schema_covered} (${c.schema_full} full, ${c.schema_partial} partial)`);
  console.log(`Schema gap:           ${c.schema_gap} (no lexicon file)`);
  console.log(`Behavior verified:    ${c.behavior_verified}`);
  console.log(`  - test refs:        ${c.behavior_test_only}`);
  console.log(`  - scenario refs:    ${c.behavior_scenario_only}`);
  console.log(`Static routes:        ${c.static_routes}`);
  console.log(`Dynamic routes:       ${c.dynamic_routes}`);
  console.log(`Garazyk extensions:   ${c.garazyk_extensions}`);
}

function createMarkdown(report) {
  const c = report.counts;
  const lines = [
    "---",
    "title: XRPC Split Coverage Metrics",
    "status: report-only",
    `last_verified: ${new Date().toISOString().slice(0, 10)}`,
    `baseline: ${report.baseline_commit}`,
    "---",
    "",
    "# XRPC Split Coverage Metrics",
    "",
    "## Purpose",
    "",
    "Splits the single-number XRPC coverage into six separate metrics:",
    "registered, schema-covered, behavior-verified, static routes,",
    "dynamic routes, and Garazyk extensions.",
    "",
    "## Summary (in-scope)",
    "",
    `| Metric | Count |`,
    `|--------|-------|`,
    `| Implemented (registered) | ${c.implemented_in_scope} |`,
    `| Schema covered (has input or output) | ${c.schema_covered} |`,
    `|   full schema (input + output) | ${c.schema_full} |`,
    `|   partial schema (no input/output) | ${c.schema_partial} |`,
    `| Schema gap (no lexicon file) | ${c.schema_gap} |`,
    `| Behavior verified (test or scenario) | ${c.behavior_verified} |`,
    `|   referenced in XCTest | ${c.behavior_test_only} |`,
    `|   referenced in scenarios | ${c.behavior_scenario_only} |`,
    `| Static dispatcher routes | ${c.static_routes} |`,
    `| Dynamic AppView routes | ${c.dynamic_routes} |`,
    `| Garazyk extensions (tools.garazyk.*) | ${c.garazyk_extensions} |`,
    "",
    "## Schema Coverage Detail",
    "",
    "| NSID | Lexicon type | Input | Output | Parameters | Errors |",
    "|------|-------------|-------|--------|------------|--------|",
  ];

  const schemaFull = report.per_method.filter(
    (m) => m.has_input && m.has_output
  );
  const schemaPartial = report.per_method.filter(
    (m) => (!m.has_input || !m.has_output) && m.type !== "unknown"
  );
  const schemaGap = report.per_method.filter((m) => m.type === "unknown");

  for (const m of [...schemaFull, ...schemaPartial, ...schemaGap]) {
    lines.push(
      `| ${m.id} | ${m.type} | ${m.has_input ? "Y" : "N"} | ${
        m.has_output ? "Y" : "N"
      } | ${m.has_parameters ? "Y" : "N"} | ${m.has_errors ? "Y" : "N"} |`
    );
  }

  if (report.schema_gap.length > 0) {
    lines.push("", "### Schema gap (no lexicon file found)");
    lines.push("");
    for (const m of report.schema_gap) {
      lines.push(`- ${m}`);
    }
  }

  if (report.schema_partial.length > 0) {
    lines.push("", "### Partial schema (lexicon exists but missing input/output)");
    lines.push("");
    for (const m of report.schema_partial) {
      const detail = report.per_method.find((p) => p.id === m);
      const missing = [];
      if (!detail || !detail.has_input) missing.push("input");
      if (!detail || !detail.has_output) missing.push("output");
      lines.push(`- ${m} (missing: ${missing.join(", ")})`);
    }
  }

  if (report.garazyk_extensions.length > 0) {
    lines.push("", "## Garazyk Extensions", "");
    for (const m of report.garazyk_extensions) {
      lines.push(`- ${m}`);
    }
  }

  lines.push(
    "",
    "## Behavior Verification",
    "",
    `Test files scanned: ${report.test_files_scanned}`,
    `Scenario files scanned: ${report.scenario_files_scanned}`,
    ""
  );

  const verified = report.per_method.filter((m) => m.behavior_verified);
  const unverified = report.per_method.filter((m) => !m.behavior_verified);

  lines.push("### Behavior-verified endpoints");
  lines.push("");
  for (const m of verified) {
    const sources = [];
    if (m.in_test) sources.push("test");
    if (m.in_scenario) sources.push("scenario");
    lines.push(`- ${m.id} (${sources.join(", ")})`);
  }

  lines.push("", "### Endpoints without behavior verification", "");
  for (const m of unverified) {
    lines.push(`- ${m.id}`);
  }

  lines.push(
    "",
    "## Rollback",
    "",
    "Documentation-only report. No code changes to roll back.",
    ""
  );

  return lines.join("\n");
}

main();
