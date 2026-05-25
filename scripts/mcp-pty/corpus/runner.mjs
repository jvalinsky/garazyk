#!/usr/bin/env node
/**
 * Generic YAML Scenario Runner — executes observe-decide-act-verify scenarios
 * against TUI applications using the TerminalSessionManager.
 *
 * Usage: node corpus/runner.mjs <scenario.yaml> [--report report.json] [--record]
 *
 * Reads a YAML scenario file with steps and executes them sequentially,
 * producing a pass/fail JSON report.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  snapshotToYaml,
  TerminalSessionManager,
} from "../terminal_session.mjs";
import { AsciicastRecorder, defaultRecordingDir } from "../recording.mjs";
import { createSidecarPtyFactory } from "../sidecar.mjs";
import { worldQuery } from "../world.mjs";
import { resolveBinary, resolveSidecarBinary } from "./path_utils.mjs";

const SIDECAR_BINARY = resolveSidecarBinary(import.meta.url);

// ── Simple YAML Parser ───────────────────────────────────────────────────
// Minimal YAML parser for scenario files. Handles the subset we use:
// strings, integers, arrays, and simple key-value pairs.

function parseYaml(text) {
  const lines = text.split("\n").filter((l) =>
    !l.trimStart().startsWith("#") && l.trim() !== ""
  );
  if (lines.length === 0) return {};

  const doc = {};
  let currentKey = null;

  // Detect if this is a steps-based document
  const isStepsDoc = lines.some((l) => l.trimStart().startsWith("- type:"));

  if (isStepsDoc) {
    return parseStepsDoc(lines, doc);
  }
  return doc;
}

function parseStepsDoc(lines, doc) {
  let i = 0;
  // Parse top-level keys until we hit steps array
  while (i < lines.length && !lines[i].trimStart().startsWith("- type:")) {
    const line = lines[i];
    const colonIdx = line.indexOf(":");
    if (colonIdx !== -1 && !line.trimStart().startsWith("-")) {
      const key = line.substring(0, colonIdx).trim();
      const value = line.substring(colonIdx + 1).trim();
      doc[key] = parseYamlValue(value);
    }
    i++;
  }

  // Parse steps array
  doc.steps = [];
  let currentStep = null;

  for (; i < lines.length; i++) {
    const trimmed = lines[i].trimStart();
    if (trimmed.startsWith("- type:")) {
      if (currentStep) doc.steps.push(currentStep);
      currentStep = parseYamlMap(trimmed.substring(2));
    } else if (currentStep && trimmed.includes(":")) {
      const colonIdx = trimmed.indexOf(":");
      const key = trimmed.substring(0, colonIdx).trim();
      const value = trimmed.substring(colonIdx + 1).trim();
      currentStep[key] = parseYamlValue(value);
    }
  }

  if (currentStep) doc.steps.push(currentStep);
  return doc;
}

function parseYamlMap(str) {
  const map = {};
  const parts = splitYamlInline(str);
  for (let i = 0; i < parts.length - 1; i += 2) {
    const key = parts[i].replace(/:$/, "").trim();
    const value = (parts[i + 1] || "").trim();
    map[key] = parseYamlValue(value);
  }
  return map;
}

function splitYamlInline(str) {
  const parts = [];
  let current = "";
  let inQuotes = false;
  let quoteChar = null;

  for (let i = 0; i < str.length; i++) {
    const ch = str[i];
    if (inQuotes) {
      current += ch;
      if (ch === quoteChar) inQuotes = false;
    } else if (ch === '"' || ch === "'") {
      inQuotes = true;
      quoteChar = ch;
      current += ch;
    } else if (ch === ":" && str[i + 1] === " ") {
      parts.push(current);
      current = "";
      i++; // skip space
    } else if (ch === " " && current.includes(":") && str[i - 1] !== ":") {
      // Space after a key: value pair
      if (current) parts.push(current);
      current = "";
    } else {
      current += ch;
    }
  }
  if (current) parts.push(current);
  return parts;
}

function parseYamlValue(value) {
  if (!value) return value;
  if (value === "true") return true;
  if (value === "false") return false;
  if (value.startsWith("[") && value.endsWith("]")) {
    const inner = value.slice(1, -1).trim();
    if (!inner) return [];
    return splitArgsScalar(inner).map(parseYamlValue);
  }
  if (/^-?\d+$/.test(value)) return parseInt(value, 10);
  if (/^-?\d+\.?\d*$/.test(value)) return parseFloat(value);
  if (value.startsWith('"') && value.endsWith('"')) return value.slice(1, -1);
  if (value.startsWith("'") && value.endsWith("'")) return value.slice(1, -1);
  return value;
}

function splitArgsScalar(value) {
  const text = String(value || "").trim();
  if (!text) return [];
  const parts = [];
  let current = "";
  let quote = null;
  const hasComma = text.includes(",");

  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (quote) {
      if (ch === quote) {
        quote = null;
      } else {
        current += ch;
      }
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      continue;
    }
    if ((hasComma && ch === ",") || (!hasComma && /\s/.test(ch))) {
      if (current.trim()) parts.push(current.trim());
      current = "";
      continue;
    }
    current += ch;
  }
  if (current.trim()) parts.push(current.trim());
  return parts;
}

function shouldResolveRelativeArg(arg, options = {}) {
  if (!arg || path.isAbsolute(arg) || arg.startsWith("-")) return false;
  if (
    arg.startsWith("./") || arg.startsWith("../") || arg.startsWith("fixtures/")
  ) return true;
  return options.resolveArgsRelative === true;
}

function normalizeScenarioArgs(rawArgs, scenarioDir, options = {}) {
  let args = rawArgs ?? [];
  if (typeof args === "string") {
    args = splitArgsScalar(args);
  }
  if (!Array.isArray(args)) {
    args = [String(args)];
  }
  return args.map((arg) => String(arg)).filter((arg) => arg.length > 0).map(
    (arg) => {
      if (!shouldResolveRelativeArg(arg, options)) return arg;
      return path.resolve(scenarioDir, arg);
    },
  );
}

// ── Step Execution ──────────────────────────────────────────────────────

const STEP_TYPES = {
  wait: "Wait for a timeout",
  press_key: "Press a key (or key name like 'enter', 'tab', 'escape')",
  type: "Type literal text into the terminal",
  assert_semantic: "Verify semantic detection (app name, framework)",
  assert_capability: "Verify capability map contains expected keys",
  assert_cursor_moved: "Verify cursor position changed",
  assert_content_changed: "Verify screen content changed",
  assert_exited: "Verify the application exited",
  assert_world_node: "Verify a TuiWorld node query",
  assert_world_relation: "Verify a TuiWorld relation",
  assert_world_action: "Verify a TuiWorld action",
  assert_world_valid: "Verify TuiWorld diagnostics",
  activate_primary: "Execute the primary TuiWorld action for a node",
  select_by_role: "Resolve a node by role/name and activate it",
};

async function worldObserve(session, context) {
  const snap = await semanticObserve(session);
  context.lastSnapshot = snap;
  return snap.snapshot.world;
}

function worldNodeQuery(step, strict = true) {
  if (step.ref) {
    return { op: "getByRef", ref: step.ref, detail: "full" };
  }
  return {
    op: strict ? "getByRole" : "find",
    role: step.role,
    name: step.name || step.target,
    domain: step.domain,
    selected: step.selected,
    focused: step.focused,
    strict,
    detail: "full",
  };
}

function firstWorldNode(world, step) {
  const query = worldNodeQuery(step, step.strict !== false);
  const result = worldQuery(world, query);
  if (result.node) return result.node;
  if (result.nodes?.length > 0) return result.nodes[0];
  return null;
}

function severityRank(severity) {
  if (severity === "error") return 2;
  if (severity === "warning") return 1;
  return 0;
}

async function executeStep(step, session, context) {
  const type = step.type;
  const label = step.label || type;

  switch (type) {
    case "wait": {
      const timeoutMs = step.timeoutMs || step.timeout || 1000;
      await session.settle(timeoutMs);
      return { passed: true, label, detail: `Waited ${timeoutMs}ms` };
    }

    case "press_key": {
      const key = step.value;
      const times = step.times || 1;
      if (!key) {
        return {
          passed: false,
          label,
          error: "Missing 'value' for press_key step",
        };
      }

      for (let i = 0; i < times; i++) {
        await session.pressKey(key);
        if (i < times - 1) await session.settle(50);
      }
      await session.settle(200);
      return { passed: true, label, detail: `Pressed '${key}' ${times}x` };
    }

    case "type": {
      const text = step.value;
      if (!text) {
        return { passed: false, label, error: "Missing 'value' for type step" };
      }
      await session.type(text);
      await session.settle(200);
      return { passed: true, label, detail: `Typed '${text}'` };
    }

    case "observe": {
      const snap = await semanticObserve(session);
      context.lastSnapshot = snap;
      return {
        passed: true,
        label,
        detail: `App: ${snap.snapshot.app} (${snap.snapshot.framework})`,
        snapshot: {
          app: snap.snapshot.app,
          framework: snap.snapshot.framework,
          confidence: snap.snapshot.confidence,
        },
      };
    }

    case "assert_semantic": {
      const snap = await semanticObserve(session);
      const target = step.target || "app";
      const expected = step.expected;
      const actual = target === "framework"
        ? snap.snapshot.framework
        : snap.snapshot.app;
      const passed = actual === expected ||
        (step.contains && actual && actual.includes(step.contains));

      return {
        passed,
        label,
        detail: `Expected ${target}="${expected}", got "${actual}"`,
        actual,
        expected,
      };
    }

    case "assert_capability": {
      const snap = await semanticObserve(session);
      const caps = snap.snapshot.capabilities;
      if (!caps) {
        return { passed: false, label, error: "No capability map available" };
      }

      const target = step.target; // e.g., "navigate.keys", "quit.keys"
      const contains = step.contains;
      const keys = target.split(".");
      let value = caps;
      for (const k of keys) {
        value = value?.[k];
      }

      let passed = false;
      if (Array.isArray(value) && Array.isArray(contains)) {
        passed = contains.every((c) => value.some((v) => v === c));
      } else if (Array.isArray(value) && typeof contains === "string") {
        passed = value.includes(contains);
      }

      return {
        passed,
        label,
        detail: `${target} contains ${JSON.stringify(contains)}? Actual: ${
          JSON.stringify(value)
        }`,
        actual: value,
        expected: contains,
      };
    }

    case "assert_cursor_moved": {
      if (!context.lastSnapshot) {
        // Take an initial snapshot — but this step can't verify movement yet.
        // The scenario should include an 'observe' step before 'assert_cursor_moved'.
        context.lastSnapshot = await semanticObserve(session);
        return {
          passed: null,
          label,
          detail:
            "Initial cursor snapshot stored (preceding 'observe' step recommended)",
        };
      }
      const snap = await semanticObserve(session);
      const beforeCursor = context.lastSnapshot.snapshot.cursor;
      const afterCursor = snap.snapshot.cursor;
      const moved = beforeCursor.x !== afterCursor.x ||
        beforeCursor.y !== afterCursor.y;
      context.lastSnapshot = snap;
      return {
        passed: moved,
        label,
        detail:
          `Cursor: {x:${beforeCursor.x},y:${beforeCursor.y}} → {x:${afterCursor.x},y:${afterCursor.y}}`,
      };
    }

    case "assert_content_changed": {
      if (!context.lastSnapshot) {
        context.lastSnapshot = {
          snapshot: await session.snapshot(),
          lines: (await session.snapshot()).lines,
        };
        return {
          passed: null,
          label,
          detail:
            "Initial content snapshot stored (preceding 'observe' step recommended)",
        };
      }
      const snap = await session.snapshot();
      const beforeHash = (context.lastSnapshot.lines || []).join("\n");
      const afterHash = snap.lines.join("\n");
      context.lastSnapshot = { snapshot: snap, lines: snap.lines };
      const changed = beforeHash !== afterHash;
      return {
        passed: changed,
        label,
        detail: `Content ${changed ? "changed" : "unchanged"}`,
      };
    }

    case "assert_exited": {
      const snap = session.snapshot();
      return {
        passed: !snap.running,
        label,
        detail: `Process ${
          snap.running ? "still running" : "exited with code " + snap.exitCode
        }`,
        exitCode: snap.exitCode,
      };
    }

    case "assert_world_node": {
      const world = await worldObserve(session, context);
      if (!world) {
        return { passed: false, label, error: "No TuiWorld graph available" };
      }
      const result = worldQuery(world, {
        op: "find",
        role: step.role,
        name: step.name || step.target,
        domain: step.domain,
        selected: step.selected,
        focused: step.focused,
        visible: step.visible !== false,
      });
      const count = result.nodes.length;
      const min = Number.isFinite(step.minCount) ? step.minCount : 1;
      const max = Number.isFinite(step.maxCount) ? step.maxCount : Infinity;
      return {
        passed: count >= min && count <= max,
        label,
        detail: `Found ${count} world nodes for role=${step.role || "*"} name=${
          step.name || step.target || "*"
        }`,
        actual: count,
        expected: { min, max: max === Infinity ? null : max },
      };
    }

    case "assert_world_relation": {
      const world = await worldObserve(session, context);
      if (!world) {
        return { passed: false, label, error: "No TuiWorld graph available" };
      }
      const source = firstWorldNode(world, {
        ref: step.ref || step.sourceRef,
        role: step.role || step.sourceRole,
        name: step.name || step.sourceName,
        domain: step.domain || step.sourceDomain,
      });
      if (!source) {
        return { passed: false, label, error: "Source world node not found" };
      }
      const result = worldQuery(world, {
        op: "related",
        ref: source.ref,
        kind: step.kind,
        role: step.targetRole,
        direction: step.direction || "both",
      });
      const matches = result.entries.filter((entry) =>
        !step.targetName ||
        String(entry.node?.label || "").toLowerCase().includes(
          String(step.targetName).toLowerCase(),
        )
      );
      const min = Number.isFinite(step.minCount) ? step.minCount : 1;
      return {
        passed: matches.length >= min,
        label,
        detail: `Found ${matches.length} ${
          step.kind || "*"
        } relations from ${source.ref}`,
        actual: matches.length,
        expected: min,
      };
    }

    case "assert_world_action": {
      const world = await worldObserve(session, context);
      if (!world) {
        return { passed: false, label, error: "No TuiWorld graph available" };
      }
      const node = firstWorldNode(world, step);
      if (!node) {
        return { passed: false, label, error: "Target world node not found" };
      }
      const result = worldQuery(world, {
        op: "actionsFor",
        ref: node.ref,
        kind: step.kind,
        intent: step.intent,
      });
      const matches = result.actions.filter((action) =>
        (!step.key || action.key === step.key) &&
        (!step.labelContains ||
          String(action.label || "").includes(step.labelContains))
      );
      return {
        passed: matches.length > 0,
        label,
        detail: `Found ${matches.length} matching actions for ${node.ref}`,
        actual: matches,
      };
    }

    case "assert_world_valid": {
      const world = await worldObserve(session, context);
      if (!world) {
        return { passed: false, label, error: "No TuiWorld graph available" };
      }
      const result = worldQuery(world, { op: "validate" });
      const allowed = severityRank(step.maxSeverity || "warning");
      const failures = result.diagnostics.filter((diagnostic) =>
        severityRank(diagnostic.severity) > allowed
      );
      return {
        passed: failures.length === 0,
        label,
        detail: `${failures.length} diagnostics exceed maxSeverity=${
          step.maxSeverity || "warning"
        }`,
        actual: failures,
      };
    }

    case "activate_primary":
    case "select_by_role": {
      const world = await worldObserve(session, context);
      if (!world) {
        return { passed: false, label, error: "No TuiWorld graph available" };
      }
      const node = firstWorldNode(world, step);
      if (!node) {
        return { passed: false, label, error: "Target world node not found" };
      }
      const result = worldQuery(world, {
        op: "primaryAction",
        ref: node.ref,
        intent: step.intent,
      });
      const key = result.action?.key ||
        (type === "select_by_role" ? "enter" : null);
      if (!key) {
        return {
          passed: false,
          label,
          error: `No key-backed primary action for ${node.ref}`,
        };
      }
      await session.pressKey(key);
      await session.settle(step.timeoutMs || 300);
      return {
        passed: true,
        label,
        detail: `Pressed ${key} for ${node.ref}`,
        action: result.action,
      };
    }

    // ── High-level semantic steps (used by dashboard_navigate.yaml and similar) ──

    case "navigate_panel": {
      const target = step.target;
      if (!target) {
        return {
          passed: false,
          label,
          error: "Missing 'target' for navigate_panel step",
        };
      }
      // Navigate by pressing the tab number key (if tabs are numbered) or tab key
      const snap = await semanticObserve(session);
      if (snap.snapshot.world) {
        const matches = worldQuery(snap.snapshot.world, {
          op: "find",
          role: "tab",
          name: target,
          visible: true,
          detail: "full",
        }).nodes;
        if (matches.length > 0) {
          const action = worldQuery(snap.snapshot.world, {
            op: "primaryAction",
            ref: matches[0].ref,
          }).action;
          if (action?.key) {
            await session.pressKey(action.key);
            await session.settle(500);
            return {
              passed: true,
              label,
              detail: `Switched to tab "${
                matches[0].label
              }" (${action.key}) via TuiWorld`,
            };
          }
        }
      }
      const tabBar = snap.snapshot.tabs?.[0];
      if (!tabBar || !tabBar.tabs) {
        // No tabs detected — try pressing tab key repeatedly as fallback
        await session.pressKey("tab");
        await session.settle(300);
        return {
          passed: null,
          label,
          detail: `Pressed tab (no tab bar detected for "${target}")`,
        };
      }
      const matchingTab = tabBar.tabs.find((t) =>
        t.label && t.label.toLowerCase().includes(target.toLowerCase())
      );
      if (matchingTab && matchingTab.index != null) {
        const key = String(matchingTab.index);
        await session.pressKey(key);
        await session.settle(500);
        return {
          passed: true,
          label,
          detail: `Switched to tab "${matchingTab.label}" (${key})`,
        };
      }
      // Fallback: press tab N times to cycle
      await session.pressKey("tab");
      await session.settle(300);
      return {
        passed: null,
        label,
        detail: `Pressed tab (no numbered tab matching "${target}")`,
      };
    }

    case "select_item": {
      const target = step.target;
      if (!target) {
        return {
          passed: false,
          label,
          error: "Missing 'target' for select_item step",
        };
      }
      const snap = await semanticObserve(session);
      if (snap.snapshot.world) {
        const listItems = worldQuery(snap.snapshot.world, {
          op: "find",
          role: "list_item",
          visible: true,
          detail: "full",
        }).nodes;
        const matchIdx = listItems.findIndex((node) =>
          node.label && node.label.toLowerCase().includes(target.toLowerCase())
        );
        if (matchIdx >= 0) {
          const selectedIdx = Math.max(
            0,
            listItems.findIndex((node) => node.state?.selected === true),
          );
          const delta = matchIdx - selectedIdx;
          const key = delta >= 0 ? "j" : "k";
          for (let i = 0; i < Math.abs(delta); i++) {
            await session.pressKey(key);
            await session.settle(50);
          }
          await session.pressKey("enter");
          await session.settle(500);
          return {
            passed: true,
            label,
            detail: `Selected "${listItems[matchIdx].label}" via TuiWorld`,
          };
        }
      }
      const listItems =
        snap.snapshot.lists?.filter((l) => l.role === "list_item") || [];
      const matchIdx = listItems.findIndex((l) =>
        l.label && l.label.toLowerCase().includes(target.toLowerCase())
      );
      if (matchIdx >= 0) {
        // Navigate to the item with j/k, then press enter
        for (let i = 0; i < matchIdx; i++) {
          await session.pressKey("j");
          await session.settle(50);
        }
        await session.pressKey("enter");
        await session.settle(500);
        return {
          passed: true,
          label,
          detail: `Selected "${listItems[matchIdx].label}"`,
        };
      }
      return {
        passed: false,
        label,
        detail: `Item "${target}" not found in ${listItems.length} list items`,
      };
    }

    case "run_scenario": {
      const target = step.target;
      // Press enter to run the currently selected scenario
      await session.pressKey("enter");
      await session.settle(step.timeoutMs || 2000);
      return {
        passed: true,
        label,
        detail: target ? `Running scenario "${target}"` : "Running scenario",
      };
    }

    case "assert": {
      // Generic assertion on session state
      const snap = session.snapshot();
      const target = step.target;
      const expected = step.expected;

      if (target === "active_run" && expected === "running") {
        return {
          passed: !!snap.running,
          label,
          detail: `Active run is ${snap.running ? "running" : "not running"}`,
        };
      }
      if (target === "active_run" && expected === "stopped") {
        return {
          passed: !snap.running,
          label,
          detail: `Active run is ${snap.running ? "running" : "stopped"}`,
        };
      }
      return {
        passed: false,
        label,
        error: `Unknown assert target: ${target} = ${expected}`,
      };
    }

    case "resize": {
      const cols = step.cols;
      const rows = step.rows;
      if (!cols || !rows) {
        return {
          passed: false,
          label,
          error: "Missing 'cols' or 'rows' for resize step",
        };
      }
      session.resize(cols, rows);
      await session.settle(200);
      return { passed: true, label, detail: `Resized to ${cols}x${rows}` };
    }

    case "quit": {
      // Trigger quit via detected quit keys or q as fallback
      const snap = await semanticObserve(session);
      const worldQuitKeys = (snap.snapshot.world?.actions || [])
        .filter((action) =>
          action.key &&
          /quit|exit|close|dismiss/i.test(
            `${action.label || ""} ${action.kind || ""}`,
          )
        )
        .map((action) => action.key);
      if (worldQuitKeys.length > 0) {
        for (const key of [...new Set(worldQuitKeys)]) {
          await session.pressKey(key);
          await session.settle(300);
        }
        return {
          passed: true,
          label,
          detail: `Quit attempt with TuiWorld keys: ${
            [...new Set(worldQuitKeys)].join(", ")
          }`,
        };
      }
      const caps = snap.snapshot.capabilities;
      const quitKeys = caps?.quit?.keys?.length > 0 ? caps.quit.keys : ["q"];
      for (const key of quitKeys) {
        await session.pressKey(key);
        await session.settle(300);
      }
      return {
        passed: true,
        label,
        detail: `Quit attempt with keys: ${quitKeys.join(", ")}`,
      };
    }

    default:
      return { passed: false, label, error: `Unknown step type: ${type}` };
  }
}

async function semanticObserve(session) {
  await session.settle(300);
  return session.semanticSnapshot("compact", false);
}

// ── Main Runner ──────────────────────────────────────────────────────────

async function runScenario(scenarioPath, options = {}) {
  const fullPath = path.resolve(scenarioPath);
  if (!fs.existsSync(fullPath)) {
    throw new Error(`Scenario file not found: ${fullPath}`);
  }

  const yamlText = fs.readFileSync(fullPath, "utf-8");
  const scenario = parseYaml(yamlText);

  if (!scenario.command) {
    throw new Error("Scenario missing 'command' field");
  }

  // Resolve simple binary names to absolute paths (required by validateCommand)
  let resolvedCommand = scenario.command;
  if (!scenario.command.includes("/")) {
    resolvedCommand = resolveBinary(scenario.command);
    if (!resolvedCommand) {
      throw new Error(`Command not found in PATH: ${scenario.command}`);
    }
  }

  // Resolve args: support space-separated string, resolve relative to scenario dir
  const scenarioDir = path.dirname(fullPath);
  const scenarioArgs = normalizeScenarioArgs(scenario.args, scenarioDir, {
    resolveArgsRelative: scenario.resolveArgsRelative === true,
  });

  const useSidecar = options.sidecar === true;

  console.log(`\n┌─ Running: ${scenario.name || path.basename(scenarioPath)}`);
  console.log(`│  Description: ${scenario.description || "—"}`);
  console.log(`│  Command: ${resolvedCommand} ${scenarioArgs.join(" ")}`);
  console.log(`│  Steps: ${(scenario.steps || []).length}`);
  if (useSidecar) console.log(`│  PTY: garazyk-ptyd (sidecar)`);
  console.log("└" + "─".repeat(60));

  const manager = new TerminalSessionManager({
    env: {
      ...process.env,
      GARAZYK_PTY_MCP_ALLOW: resolvedCommand,
    },
    ptyFactory: useSidecar ? createSidecarPtyFactory(SIDECAR_BINARY) : null,
  });

  let recorder = null;
  let session = null;
  const results = [];
  const context = { lastSnapshot: null };
  const startTime = Date.now();

  try {
    // Create session (async when using sidecar ptyFactory)
    session = await manager.create({
      command: resolvedCommand,
      args: scenarioArgs,
      cols: scenario.cols || 80,
      rows: scenario.rows || 24,
      cwd: scenario.cwd || process.cwd(),
      env: { TERM: scenario.term || "xterm-256color" },
    });

    // Initial settle
    const settleMs = scenario.settleMs || 2000;
    await session.settle(settleMs);

    // Start recording if requested
    if (options.record) {
      const outputDir = defaultRecordingDir(process.cwd());
      recorder = new AsciicastRecorder({
        outputDir,
        cols: session.cols,
        rows: session.rows,
        title: scenario.name || path.basename(scenarioPath, ".yaml"),
        recordInput: true,
        semanticOverlay: true,
        command: [scenario.command, ...scenarioArgs].join(" "),
      });
      session.attachRecording(recorder);
    }

    // Execute steps
    for (let i = 0; i < (scenario.steps || []).length; i++) {
      const step = scenario.steps[i];
      console.log(
        `  [${i + 1}/${scenario.steps.length}] ${step.label || step.type}...`,
      );

      const stepStart = Date.now();
      try {
        const result = await executeStep(step, session, context);
        result.stepIndex = i;
        result.stepElapsedMs = Date.now() - stepStart;

        // Check optional timing bounds
        const minMs = step.minMs;
        const maxMs = step.maxMs;
        if ((minMs != null && result.stepElapsedMs < minMs) ||
            (maxMs != null && result.stepElapsedMs > maxMs)) {
          result.timingViolation = true;
        }

        results.push(result);

        if (!result.passed) {
          const timingNote = result.timingViolation
            ? ` ⚡ timing: ${result.stepElapsedMs}ms (bounds: ${minMs ?? "-"}-${maxMs ?? "-"}ms)`
            : "";
          console.log(`    ✗ FAILED: ${result.error || result.detail}${timingNote}`);
          if (options.stopOnFailure !== false) {
            console.log(
              `    Stopping on failure. Use --continue-on-failure to keep going.`,
            );
            break;
          }
        } else {
          const timingNote = result.timingViolation
            ? ` ⚡ ${result.stepElapsedMs}ms (bounds: ${minMs ?? "-"}-${maxMs ?? "-"}ms)`
            : "";
          console.log(`    ✓ ${result.detail || "ok"}${timingNote}`);
        }
      } catch (err) {
        results.push({
          stepIndex: i,
          label: step.label || step.type,
          passed: false,
          error: err.message,
          stepElapsedMs: Date.now() - stepStart,
        });
        console.log(`    ✗ ERROR: ${err.message}`);
        if (options.stopOnFailure !== false) break;
      }
    }
  } catch (err) {
    results.push({
      stepIndex: -1,
      label: "session_setup",
      passed: false,
      error: err.message,
    });
    console.log(`  ✗ SETUP ERROR: ${err.message}`);
  } finally {
    // Stop recording (guard against double-close from session.stop)
    if (recorder && !recorder._closed) {
      try {
        recorder.close();
      } catch { /* close may throw if already closed by session.stop */ }
      recorder._closed = true;
    }

    // Cleanup session
    if (session && session.running) {
      try {
        await session.stop({ force: true });
      } catch { /* ignore */ }
    }
    manager.dispose();
  }

  const elapsed = Date.now() - startTime;
  const passed = results.filter((r) => r.passed).length;
  const failed = results.filter((r) => !r.passed).length;

  // Build report
  const report = {
    scenario: scenario.name || path.basename(scenarioPath),
    command: scenario.command,
    framework: scenario.framework || "unknown",
    timestamp: new Date().toISOString(),
    elapsedMs: elapsed,
    stepsTotal: results.length,
    stepsPassed: passed,
    stepsFailed: failed,
    overall: failed === 0 ? "PASS" : "FAIL",
    results,
    recorder: recorder
      ? {
        castPath: recorder.castPath,
        htmlPath: recorder.htmlPath,
      }
      : null,
  };

  // Print summary
  console.log(
    `\n╔══════════════════════════════════════════════════════════════╗`,
  );
  console.log(`║  Result: ${report.overall.padEnd(55)}║`);
  console.log(
    `║  Steps:  ${String(passed).padStart(2)}/${results.length} passed, ${
      String(failed).padStart(2)
    } failed`.padEnd(62) + "║",
  );
  console.log(`║  Time:   ${(elapsed / 1000).toFixed(1)}s`.padEnd(62) + "║");
  if (recorder) {
    console.log(`║  Cast:   ${recorder.castPath}`.padEnd(62) + "║");
  }
  console.log(
    `╚══════════════════════════════════════════════════════════════╝`,
  );

  // Write report if requested
  if (options.reportPath) {
    fs.writeFileSync(
      options.reportPath,
      JSON.stringify(report, null, 2) + "\n",
    );
    console.log(`\nReport written to: ${options.reportPath}`);
  }

  return report;
}

// ── CLI Entry ────────────────────────────────────────────────────────────

if (import.meta.url === `file://${process.argv[1]}`) {
  const scenarioPath = process.argv[2];
  if (!scenarioPath) {
    console.log(
      "Usage: node corpus/runner.mjs <scenario.yaml> [--report report.json] [--record] [--sidecar] [--continue-on-failure]",
    );
    process.exit(1);
  }

  const options = {
    reportPath: process.argv.includes("--report")
      ? process.argv[process.argv.indexOf("--report") + 1]
      : null,
    record: process.argv.includes("--record"),
    sidecar: process.argv.includes("--sidecar"),
    stopOnFailure: !process.argv.includes("--continue-on-failure"),
  };

  runScenario(scenarioPath, options).then((report) => {
    if (report.overall === "FAIL") process.exit(1);
    else process.exit(0);
  }).catch((err) => {
    console.error("Fatal:", err.message);
    process.exit(1);
  });
}

export {
  executeStep,
  normalizeScenarioArgs,
  parseYaml,
  runScenario,
  splitArgsScalar,
};
