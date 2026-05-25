#!/usr/bin/env node
/**
 * Corpus CLI — Manage the TUI app testing corpus.
 *
 * Commands:
 *   node corpus/cli.mjs scan        — Scan PATH for known TUIs, update installed.json
 *   node corpus/cli.mjs list        — List apps with filters
 *   node corpus/cli.mjs coverage    — Show coverage matrix (framework × UI pattern)
 *   node corpus/cli.mjs audit       — Cross-reference manifest with actual binaries
 *
 * Usage: node scripts/mcp-pty/corpus/cli.mjs <command> [options]
 */

import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MANIFEST_PATH = path.join(__dirname, "manifest.json");
const INSTALLED_PATH = path.join(__dirname, "installed.json");
const TESTS_DIR = path.join(__dirname, "..", "tests");

// ── Helpers ──────────────────────────────────────────────────────────────

function loadManifest() {
  const raw = fs.readFileSync(MANIFEST_PATH, "utf-8");
  return JSON.parse(raw);
}

function loadInstalled() {
  try {
    const raw = fs.readFileSync(INSTALLED_PATH, "utf-8");
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

function saveInstalled(data) {
  fs.writeFileSync(INSTALLED_PATH, JSON.stringify(data, null, 2) + "\n");
}

/** Check if a binary exists in PATH */
function which(binaryName) {
  try {
    return execSync(`which "${binaryName}"`, { stdio: "pipe" }).toString()
      .trim();
  } catch {
    return null;
  }
}

/** Check if a binary exists at a specific path */
function exists(filePath) {
  try {
    fs.accessSync(filePath, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

// ── Table formatting ─────────────────────────────────────────────────────

function pad(str, len) {
  return (str || "").padEnd(len);
}

function table(headers, rows) {
  const colWidths = headers.map((h, i) =>
    Math.max(h.length, ...rows.map((r) => String(r[i] || "").length))
  );
  const sep = colWidths.map((w) => "─".repeat(w));
  const lines = [];
  lines.push(headers.map((h, i) => pad(h, colWidths[i])).join(" │ "));
  lines.push(sep.join("─┼─"));
  for (const row of rows) {
    lines.push(
      row.map((c, i) => pad(String(c || ""), colWidths[i])).join(" │ "),
    );
  }
  return lines.join("\n");
}

// ── Commands ─────────────────────────────────────────────────────────────

function cmdScan() {
  const manifest = loadManifest();
  const installed = loadInstalled();
  let found = 0, missing = 0;

  for (const app of manifest.apps) {
    let resolvedPath = null;
    if (app.binary) {
      if (exists(app.binary)) {
        resolvedPath = app.binary;
      }
    } else if (app.installPackage) {
      resolvedPath = which(app.installPackage);
    }

    installed[app.id] = {
      found: !!resolvedPath,
      path: resolvedPath,
      checkedAt: new Date().toISOString(),
    };

    if (resolvedPath) found++;
    else missing++;
  }

  saveInstalled(installed);
  console.log(
    `Scanned ${manifest.apps.length} apps: ${found} found, ${missing} missing`,
  );
  if (missing > 0) {
    const installMethods = [
      ...new Set(
        manifest.apps.filter((a) => !installed[a.id]?.found).map((a) =>
          a.installMethod
        ),
      ),
    ].join(", ");
    console.log(`\nMissing apps use install methods: ${installMethods}`);
    console.log(
      `Install them manually (e.g., brew install, pip install, cargo install).`,
    );
  }
}

function cmdList(args) {
  const manifest = loadManifest();
  const installed = loadInstalled();

  const filterFramework = args.find((a) => a.startsWith("--framework="))?.split(
    "=",
  )[1];
  const filterCategory = args.find((a) => a.startsWith("--category="))?.split(
    "=",
  )[1];
  const filterInstalled = args.includes("--installed");
  const filterMissing = args.includes("--missing");
  const filterTested = args.includes("--tested");
  const filterUntested = args.includes("--untested");

  let apps = [...manifest.apps];

  if (filterFramework) {
    apps = apps.filter((a) => a.framework === filterFramework);
  }
  if (filterCategory) {
    apps = apps.filter((a) => a.category === filterCategory);
  }
  if (filterInstalled) {
    apps = apps.filter((a) => installed[a.id]?.found);
  }
  if (filterMissing) {
    apps = apps.filter((a) => !installed[a.id]?.found);
  }
  if (filterTested) {
    apps = apps.filter((a) =>
      a.scenario && fs.existsSync(path.join(TESTS_DIR, a.scenario))
    );
  }
  if (filterUntested) {
    apps = apps.filter((a) =>
      !a.scenario || !fs.existsSync(path.join(TESTS_DIR, a.scenario))
    );
  }

  console.log(`\n${apps.length} apps matching filters:\n`);
  const headers = ["ID", "Framework", "Category", "Installed", "Tested"];
  const rows = apps.map((a) => {
    const ins = installed[a.id];
    const tested = a.scenario &&
      fs.existsSync(path.join(TESTS_DIR, a.scenario));
    return [
      a.id,
      a.framework,
      a.category,
      ins?.found ? "✓" : "✗",
      tested ? "✓" : "—",
    ];
  });
  console.log(table(headers, rows));
}

function cmdCoverage() {
  const manifest = loadManifest();
  const installed = loadInstalled();

  // Build coverage matrix: framework × UI pattern
  const frameworks = [...new Set(manifest.apps.map((a) => a.framework))].sort();
  const allPatterns = [...new Set(manifest.apps.flatMap((a) => a.uiPatterns))]
    .sort();

  // Framework summary
  console.log("\n═══ Framework Coverage ═══\n");
  const fwRows = frameworks.map((fw) => {
    const apps = manifest.apps.filter((a) => a.framework === fw);
    const installedCount = apps.filter((a) => installed[a.id]?.found).length;
    return [
      fw,
      String(apps.length),
      String(installedCount),
      apps.map((a) => a.id).join(", "),
    ];
  });
  console.log(table(["Framework", "Total", "Installed", "Apps"], fwRows));

  // Pattern coverage
  console.log("\n═══ UI Pattern Coverage ═══\n");
  const patternRows = allPatterns.map((pattern) => {
    const apps = manifest.apps.filter((a) => a.uiPatterns.includes(pattern));
    const frameworks = [...new Set(apps.map((a) => a.framework))];
    return [
      pattern,
      String(apps.length),
      String(frameworks.length),
      frameworks.join(", "),
    ];
  });
  console.log(
    table(["UI Pattern", "Apps", "Framework Count", "Frameworks"], patternRows),
  );

  // Category coverage
  console.log("\n═══ Category Coverage ═══\n");
  const categories = [...new Set(manifest.apps.map((a) => a.category))].sort();
  const catRows = categories.map((cat) => {
    const apps = manifest.apps.filter((a) => a.category === cat);
    return [cat, String(apps.length), apps.map((a) => a.id).join(", ")];
  });
  console.log(table(["Category", "Apps", "IDs"], catRows));

  console.log(
    `\nTotal apps: ${manifest.apps.length} | Frameworks: ${frameworks.length} | Patterns: ${allPatterns.length} | Categories: ${categories.length}`,
  );
}

function scenarioExists(app) {
  if (!app.scenario) return false;
  return fs.existsSync(path.join(TESTS_DIR, app.scenario));
}

function cmdAudit(args) {
  const manifest = loadManifest();
  const installed = loadInstalled();
  const issues = [];
  const schemaOnly = args.includes("--schema-only");

  for (const app of manifest.apps) {
    const ins = installed[app.id] || { found: false, path: null };

    // Check required fields
    if (!app.framework) {
      issues.push({ app: app.id, issue: "Missing framework" });
    }
    if (!app.uiPatterns || app.uiPatterns.length === 0) {
      issues.push({ app: app.id, issue: "No UI patterns" });
    }
    if (!app.quitKeys || app.quitKeys.length === 0) {
      issues.push({ app: app.id, issue: "No quit keys" });
    }

    // Check binary resolvability
    if (
      !schemaOnly && app.binary && !exists(app.binary) &&
      !which(path.basename(app.binary))
    ) {
      issues.push({ app: app.id, issue: `Binary not found: ${app.binary}` });
    }

    // Check scenario file
    if (app.scenario) {
      if (!scenarioExists(app)) {
        issues.push({
          app: app.id,
          issue: `Scenario not found: ${app.scenario}`,
        });
      }
    }
  }

  // Check duplicates
  const ids = manifest.apps.map((a) => a.id);
  const dups = ids.filter((id, i) => ids.indexOf(id) !== i);
  for (const dup of [...new Set(dups)]) {
    issues.push({ app: dup, issue: "Duplicate ID" });
  }

  if (issues.length === 0) {
    console.log("✓ Audit passed — no issues found in manifest.");
  } else {
    console.log(`${issues.length} issues found:\n`);
    const rows = issues.map((i) => [i.app, i.issue]);
    console.log(table(["App", "Issue"], rows));
  }
}

// ── Main ─────────────────────────────────────────────────────────────────

function usage() {
  console.log(`Usage: node corpus/cli.mjs <command> [options]

Commands:
  scan              Scan PATH for known TUIs, update installed.json
  list [filters]    List apps (--framework=X, --category=X, --installed, --missing, --tested, --untested)
  coverage          Show coverage matrix (framework × UI pattern × category)
  audit             Cross-reference manifest with binaries and scenarios
  audit --schema-only
                    Validate manifest/scenario shape without checking installed binaries
`);
}

const cmd = process.argv[2];
const args = process.argv.slice(3);

switch (cmd) {
  case "scan":
    cmdScan();
    break;
  case "list":
    cmdList(args);
    break;
  case "coverage":
    cmdCoverage();
    break;
  case "audit":
    cmdAudit(args);
    break;
  default:
    usage();
    process.exit(1);
}
