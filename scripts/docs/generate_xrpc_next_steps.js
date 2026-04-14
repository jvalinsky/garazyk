#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function parseArgs(argv) {
  const args = {
    repoRoot: process.cwd(),
    coveragePath: null,
    planPath: null,
    issuesPath: null,
    top: 30,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--repo-root") {
      args.repoRoot = argv[++index];
    } else if (arg === "--coverage-path") {
      args.coveragePath = argv[++index];
    } else if (arg === "--plan-path") {
      args.planPath = argv[++index];
    } else if (arg === "--issues-path") {
      args.issuesPath = argv[++index];
    } else if (arg === "--top") {
      args.top = Number(argv[++index]);
    } else if (arg === "--help" || arg === "-h") {
      printUsageAndExit(0);
    } else {
      console.error(`Unknown argument: ${arg}`);
      printUsageAndExit(1);
    }
  }

  args.coveragePath = args.coveragePath || path.join(args.repoRoot, "reports", "xrpc_coverage.json");
  args.planPath = args.planPath || path.join(args.repoRoot, "reports", "xrpc_next_steps_plan.md");
  args.issuesPath = args.issuesPath || path.join(args.repoRoot, "reports", "xrpc_issue_candidates.md");
  return args;
}

function printUsageAndExit(code) {
  const usage = [
    "Usage:",
    "  node scripts/generate_xrpc_next_steps.js [options]",
    "",
    "Options:",
    "  --repo-root <path>       Repository root (default: cwd)",
    "  --coverage-path <path>   Input coverage JSON",
    "  --plan-path <path>       Output plan markdown",
    "  --issues-path <path>     Output issue candidates markdown",
    "  --top <n>                Number of issue candidates (default: 30)",
  ].join("\n");
  console.error(usage);
  process.exit(code);
}

function readJson(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`File not found: ${filePath}`);
  }
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function namespaceOf(methodId) {
  const parts = methodId.split(".");
  if (parts.length < 2) {
    return "unknown";
  }
  return `${parts[0]}.${parts[1]}`;
}

function methodGroup(methodId) {
  if (methodId.startsWith("com.atproto.server.") || methodId.startsWith("com.atproto.identity.")) {
    return "phase_1_identity_account";
  }
  if (methodId.startsWith("com.atproto.repo.") || methodId.startsWith("com.atproto.sync.")) {
    return "phase_2_repo_sync";
  }
  if (methodId.startsWith("com.atproto.admin.")
      || methodId.startsWith("com.atproto.label.")
      || methodId.startsWith("com.atproto.temp.")
      || methodId.startsWith("com.atproto.lexicon.")) {
    return "phase_3_admin_label_temp";
  }
  return "phase_4_non_core_namespaces";
}

function scoreMethod(methodId) {
  let score = 0;

  if (methodId.startsWith("com.atproto.server.") || methodId.startsWith("com.atproto.repo.") || methodId.startsWith("com.atproto.sync.") || methodId.startsWith("com.atproto.identity.")) {
    score += 100;
  } else if (methodId.startsWith("com.atproto.admin.")
      || methodId.startsWith("com.atproto.label.")
      || methodId.startsWith("com.atproto.lexicon.")) {
    score += 80;
  } else if (methodId.startsWith("com.atproto.temp.")) {
    score += 70;
  } else if (methodId.startsWith("app.bsky.")) {
    score += 40;
  } else {
    score += 20;
  }

  const urgentKeywords = [
    "requestPasswordReset",
    "resetPassword",
    "requestAccountDelete",
    "confirmEmail",
    "updateEmail",
    "reserveSigningKey",
    "submitPlcOperation",
    "signPlcOperation",
    "requestPlcOperationSignature",
    "updateHandle",
    "importRepo",
    "requestCrawl",
    "listReposByCollection",
    "listMissingBlobs",
    "getRepoStatus",
    "subscribeLabels",
    "revokeAccountCredentials",
  ];

  for (const keyword of urgentKeywords) {
    if (methodId.includes(keyword)) {
      score += 20;
      break;
    }
  }

  if (methodId.includes(".get") || methodId.includes(".list")) {
    score += 5;
  }

  return score;
}

function priorityLabel(score) {
  if (score >= 120) {
    return "P0";
  }
  if (score >= 95) {
    return "P1";
  }
  if (score >= 70) {
    return "P2";
  }
  return "P3";
}

function lexiconPath(repoRoot, methodId) {
  const parts = methodId.split(".");
  const methodName = parts.pop();
  return path.join(repoRoot, "Garazyk", "Resources", "lexicons", ...parts, `${methodName}.json`);
}

function phaseTitle(phaseKey) {
  switch (phaseKey) {
    case "phase_1_identity_account":
      return "Phase 1: Identity and Account Safety";
    case "phase_2_repo_sync":
      return "Phase 2: Repository and Sync Completeness";
    case "phase_3_admin_label_temp":
      return "Phase 3: Admin, Label, and Temp APIs";
    case "phase_4_non_core_namespaces":
      return "Phase 4: Non-core Namespaces";
    default:
      return "Unclassified";
  }
}

function createPlanMarkdown(payload) {
  const lines = [];
  lines.push("# XRPC Next Steps Plan");
  lines.push("");
  lines.push(`Generated: ${payload.generated_at}`);
  lines.push("");
  lines.push("## Baseline");
  lines.push("");
  lines.push(`- Missing in code: ${payload.coverage.missing_in_code}`);
  lines.push(`- Coverage: ${payload.coverage.coverage_pct}%`);
  lines.push(`- Unknown registry entries: ${payload.coverage.unknown_registry_entries}`);
  lines.push(`- Duplicate registry registrations: ${payload.coverage.duplicate_registry_registrations}`);
  if (typeof payload.coverage.duplicate_registry_registrations_cross_scope === "number") {
    lines.push(`- Duplicate registry registrations (cross-scope, actionable): ${payload.coverage.duplicate_registry_registrations_cross_scope}`);
  }
  if (typeof payload.coverage.duplicate_registry_registrations_cross_scope_expected === "number") {
    lines.push(`- Cross-scope overlap (expected controller/application dual-path): ${payload.coverage.duplicate_registry_registrations_cross_scope_expected}`);
  }
  if (typeof payload.coverage.duplicate_registry_registrations_cross_scope_raw === "number") {
    lines.push(`- Cross-scope overlap (raw total): ${payload.coverage.duplicate_registry_registrations_cross_scope_raw}`);
  }
  lines.push("");
  lines.push("## Priority Rubric");
  lines.push("");
  lines.push("- P0: Critical PDS identity/account/repo/sync gaps with security or federation impact.");
  lines.push("- P1: High-value protocol completeness for core `com.atproto.*` flows.");
  lines.push("- P2: Admin/label/temp and useful adjacent functionality.");
  lines.push("- P3: Non-core namespaces for appview/chat/custom extensions.");
  lines.push("");
  lines.push("## Phased Queue");
  lines.push("");

  for (const phase of payload.phases) {
    lines.push(`### ${phaseTitle(phase.key)}`);
    lines.push("");
    lines.push(`- Endpoint count: ${phase.count}`);
    lines.push(`- P0: ${phase.by_priority.P0}, P1: ${phase.by_priority.P1}, P2: ${phase.by_priority.P2}, P3: ${phase.by_priority.P3}`);
    lines.push("- Next batch:");
    if (phase.next_batch.length === 0) {
      lines.push("  - none");
    } else {
      for (const method of phase.next_batch) {
        lines.push(`  - ${method.priority} \`${method.method_id}\``);
      }
    }
    lines.push("");
  }

  lines.push("## Recommended Work Order");
  lines.push("");
  if (payload.coverage.missing_in_code === 0) {
    lines.push("1. No in-scope endpoint implementation backlog remains.");
    lines.push("2. Keep `scripts/docs/generate_xrpc_coverage_report.js --source-only --fail-on-duplicates` in CI.");
    lines.push("3. Re-run coverage and next-steps generation after registry or lexicon changes.");
  } else {
    lines.push("1. Implement all Phase 1 P0/P1 endpoints.");
    lines.push("2. Implement Phase 2 P0/P1 endpoints, then run interop/sync tests.");
    lines.push("3. Implement Phase 3 P1/P2 endpoints needed for moderation/admin workflows.");
    lines.push("4. Re-run `scripts/docs/generate_xrpc_coverage_report.js` after each batch.");
  }
  lines.push("");
  return `${lines.join("\n")}\n`;
}

function createIssueMarkdown(payload, topN) {
  const lines = [];
  lines.push("# XRPC Issue Candidates");
  lines.push("");
  lines.push(`Generated: ${payload.generated_at}`);
  lines.push("");
  if (payload.top_candidates.length === 0) {
    lines.push("No in-scope missing endpoints.");
    lines.push("");
    lines.push("- Coverage is currently 100% for configured scope.");
    lines.push("- Track maintenance work separately (duplicate registration checks, schema drift, and test hardening).");
    lines.push("");
    return `${lines.join("\n")}\n`;
  }
  lines.push(`Top ${topN} missing endpoints by priority score.`);
  lines.push("");

  payload.top_candidates.slice(0, topN).forEach((candidate, index) => {
    lines.push(`## ${index + 1}. [${candidate.priority}] Implement \`${candidate.method_id}\``);
    lines.push("");
    lines.push(`- Namespace: \`${candidate.namespace}\``);
    lines.push(`- Score: ${candidate.score}`);
    lines.push(`- Phase: ${phaseTitle(candidate.phase_key)}`);
    lines.push(`- Lexicon: \`${candidate.lexicon_path}\``);
    lines.push("- Suggested implementation files:");
    lines.push("  - `Garazyk/Sources/Network/XrpcMethodRegistry.m`");
    lines.push("  - `Garazyk/Sources/App/PDSController.m`");
    lines.push("  - `Garazyk/Sources/App/Services/` (new or existing service)");
    lines.push("- Acceptance criteria:");
    lines.push(`  - Register and route \`${candidate.method_id}\` through XRPC registry.`);
    lines.push("  - Enforce auth/session checks and input validation.");
    lines.push("  - Add successful path test and at least one failure path test.");
    lines.push("  - Add/update lexicon conformance assertions for request/response fields.");
    lines.push("");
  });

  return `${lines.join("\n")}\n`;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const coverage = readJson(args.coveragePath);
  const missing = coverage.missing_in_code || [];

  const scored = missing.map((methodId) => {
    const score = scoreMethod(methodId);
    const priority = priorityLabel(score);
    const phaseKey = methodGroup(methodId);
    return {
      method_id: methodId,
      namespace: namespaceOf(methodId),
      score,
      priority,
      phase_key: phaseKey,
      lexicon_path: lexiconPath(args.repoRoot, methodId),
    };
  }).sort((left, right) => {
    if (right.score !== left.score) {
      return right.score - left.score;
    }
    return left.method_id.localeCompare(right.method_id);
  });

  const phaseKeys = [
    "phase_1_identity_account",
    "phase_2_repo_sync",
    "phase_3_admin_label_temp",
    "phase_4_non_core_namespaces",
  ];

  const phases = phaseKeys.map((phaseKey) => {
    const methods = scored.filter((item) => item.phase_key === phaseKey);
    const byPriority = { P0: 0, P1: 0, P2: 0, P3: 0 };
    methods.forEach((method) => {
      byPriority[method.priority] += 1;
    });
    return {
      key: phaseKey,
      count: methods.length,
      by_priority: byPriority,
      next_batch: methods.slice(0, 12),
    };
  });

  const payload = {
    generated_at: new Date().toISOString(),
    coverage: {
      missing_in_code: coverage.counts.missing_in_code,
      coverage_pct: coverage.counts.coverage_pct,
      unknown_registry_entries: coverage.counts.unknown_registry_entries,
      duplicate_registry_registrations: coverage.counts.duplicate_registry_registrations,
      duplicate_registry_registrations_cross_scope: coverage.counts.duplicate_registry_registrations_cross_scope,
      duplicate_registry_registrations_cross_scope_expected: coverage.counts.duplicate_registry_registrations_cross_scope_expected,
      duplicate_registry_registrations_cross_scope_raw: coverage.counts.duplicate_registry_registrations_cross_scope_raw,
    },
    phases,
    top_candidates: scored,
  };

  fs.mkdirSync(path.dirname(args.planPath), { recursive: true });
  fs.writeFileSync(args.planPath, createPlanMarkdown(payload), "utf8");
  fs.writeFileSync(args.issuesPath, createIssueMarkdown(payload, args.top), "utf8");

  console.log(`Wrote ${args.planPath}`);
  console.log(`Wrote ${args.issuesPath}`);
}

main();
