#!/usr/bin/env node
/**
 * Add maxMs timing bounds to YAML scenario steps that don't have them.
 *
 * Conventions (from existing curated scenarios):
 *   - wait steps:       maxMs = 3 × timeoutMs (min 1500)
 *   - quit steps:       maxMs = 2000 (or 3000 for unusual quit keys)
 *   - observe/assert:   maxMs = 500
 *   - press_key:        maxMs = 500
 *
 * Usage:
 *   node corpus/add_maxms.mjs              # process ALL YAML files in tests/
 *   node corpus/add_maxms.mjs --manifest   # process only manifest entries
 *   node corpus/add_maxms.mjs --dry-run    # preview without writing
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TESTS_DIR = path.join(__dirname, "..", "tests");
const MANIFEST_PATH = path.join(__dirname, "manifest.json");

// Files with unusual quit keys that need more time
const UNUSUAL_QUIT = {
  "mc.yaml": "F10",
  "nudoku.yaml": "Q",
  "nethack.yaml": "S",
  "cmus.yaml": ":q",
  "broot.yaml": ":q",
  "vim.yaml": ":q",
  "helix.yaml": ":q",
  "kakoune.yaml": ":q",
  "k9s.yaml": ":q",
  "htop.yaml": "F10",
  "irssi.yaml": "/quit",
  "tmux.yaml": "exit",
  "posting.yaml": "ctrl+c",
  "harlequin.yaml": "ctrl+q",
  "textual-paint.yaml": "ctrl+c",
  "nano.yaml": "F2",
  "micro.yaml": "ctrl+q",
  "ne.yaml": "ctrl+q",
  "fzf.yaml": "escape",
  "mcfly.yaml": "escape",
  "dolphie.yaml": "ctrl+q",
};

/**
 * Compute maxMs for a step based on its type, timeout, and scenario file.
 */
function computeMaxMs(stepType, timeoutMs, filename) {
  if (stepType === "wait") {
    const t = timeoutMs || 500;
    return Math.max(t * 3, 1500);
  }
  if (stepType === "quit") {
    const base = path.basename(filename);
    return base in UNUSUAL_QUIT ? 3000 : 2000;
  }
  if (
    [
      "observe",
      "assert_semantic",
      "assert_content_changed",
      "assert_cursor_moved",
      "press_key",
      "assert_semantic_role",
      "assert_text_present",
      "assert_element_count",
    ].includes(stepType)
  ) {
    return 500;
  }
  return 500; // default
}

/**
 * Add maxMs to all steps in a single YAML file that don't have it.
 * Returns true if the file was modified.
 */
function processFile(filePath, content) {
  content = content || fs.readFileSync(filePath, "utf-8");

  // Quick pre-check: skip if every step already has maxMs
  const stepLines = content.match(/^  - type:/gm);
  const maxMsLines = content.match(/^\s+maxMs:/gm);
  if (stepLines && maxMsLines && maxMsLines.length >= stepLines.length) {
    return false;
  }

  const lines = content.split("\n");
  const result = [];
  let currentStepType = null;
  let currentTimeout = null;
  let stepHasMaxMs = false;

  for (const line of lines) {
    // Detect step start
    const stepMatch = line.match(/^  - type:\s*(\w+)/);
    if (stepMatch) {
      currentStepType = stepMatch[1];
      currentTimeout = null;
      stepHasMaxMs = false;
    }

    // Track timeoutMs value
    const timeoutMatch = line.match(/^\s+timeoutMs:\s*(\d+)/);
    if (timeoutMatch) {
      currentTimeout = parseInt(timeoutMatch[1], 10);
    }

    // Check if maxMs already present in this step
    if (/^\s+maxMs:/.test(line)) {
      stepHasMaxMs = true;
    }

    // When we encounter label: as the last field and step has no maxMs, insert
    if (
      /^\s+label:/.test(line) &&
      !stepHasMaxMs &&
      currentStepType
    ) {
      const ms = computeMaxMs(currentStepType, currentTimeout, filePath);
      result.push(`    maxMs: ${ms}`);
    }

    result.push(line);
  }

  fs.writeFileSync(filePath, result.join("\n"));
  return true;
}

// ── Main ─────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
const manifestOnly = args.includes("--manifest");
const dryRun = args.includes("--dry-run");

let files = [];

if (manifestOnly) {
  const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, "utf-8"));
  const scenarioFiles = new Set();
  for (const app of manifest.apps) {
    if (app.scenario) scenarioFiles.add(app.scenario);
  }
  files = [...scenarioFiles].map((s) => path.join(TESTS_DIR, s));
} else {
  // Process all YAML files in tests/
  const dirents = fs.readdirSync(TESTS_DIR, { withFileTypes: true });
  files = dirents
    .filter((d) => d.isFile() && d.name.endsWith(".yaml"))
    .map((d) => path.join(TESTS_DIR, d.name))
    .sort();
}

let updated = 0;
let skipped = 0;

let wouldUpdate = 0;

for (const filePath of files) {
  const base = path.basename(filePath);

  if (!fs.existsSync(filePath)) {
    console.log(`SKIP (missing): ${base}`);
    skipped++;
    continue;
  }

  if (dryRun) {
    const content = fs.readFileSync(filePath, "utf-8");
    const stepCount = (content.match(/^  - type:/gm) || []).length;
    const maxMsCount = (content.match(/^\s+maxMs:/gm) || []).length;
    if (maxMsCount < stepCount) {
      console.log(`WOULD UPDATE: ${base} (${maxMsCount}/${stepCount} steps have maxMs)`);
      wouldUpdate++;
    } else {
      console.log(`  OK:          ${base}`);
      skipped++;
    }
    continue;
  }

  const content = fs.readFileSync(filePath, "utf-8");
  const changed = processFile(filePath, content);
  if (changed) {
    console.log(`UPDATED: ${base}`);
    updated++;
  } else {
    console.log(`  SKIP:  ${base} (complete)`);
    skipped++;
  }
}

if (dryRun) {
  console.log(`\nDone. Would update: ${wouldUpdate}, OK: ${skipped}`);
  console.log("(dry run — no files written)");
} else {
  console.log(`\nDone. Updated: ${updated}, Skipped: ${skipped}`);
}
