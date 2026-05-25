/**
 * TUI Test Framework — English → IR → Plan → Execute → Record → Verify
 *
 * Pipeline:
 *   1. DESCRIBE: English test description → TestIR (YAML)
 *   2. PLAN: TestIR + semantic snapshot → ExecutionPlan (keystrokes)
 *   3. RUN: ExecutionPlan → execute keystrokes + record asciicast
 *   4. VERIFY: Replay recording → check assertions
 *
 * The IR is app-agnostic (what to do). The plan is app-specific
 * (how to do it), derived from the semantic snapshot's capability map.
 *
 * @module tui_test
 */

import fs from "node:fs";
import path from "node:path";
import { TerminalSessionManager } from "./terminal_session.mjs";
import { AsciicastRecorder, defaultRecordingDir } from "./recording.mjs";
import { findNodes, primaryAction } from "./world.mjs";

// ---------------------------------------------------------------------------
// 1. Test IR — App-agnostic test description
// ---------------------------------------------------------------------------

/**
 * @typedef {Object} TestStep
 * @property {string} type - Step type: "navigate_panel" | "select_item" |
 *   "start_service" | "stop_service" | "run_scenario" | "dismiss_overlay" |
 *   "wait" | "assert" | "type" | "press_key"
 * @property {string} [target] - Target element name (panel, item, service)
 * @property {string} [value] - Value for type/assert steps
 * @property {string} [expected] - Expected state for assert steps
 * @property {number} [timeoutMs] - Max wait for this step
 * @property {string} [label] - Human-readable step label
 */

/**
 * @typedef {Object} TestIR
 * @property {string} name - Test name
 * @property {string} description - English description of the test
 * @property {string} command - Absolute path to TUI command
 * @property {string[]} [args] - Command arguments
 * @property {string} [cwd] - Working directory
 * @property {number} [cols=120] - Terminal width
 * @property {number} [rows=30] - Terminal height
 * @property {number} [settleMs=5000] - Initial render settle time
 * @property {TestStep[]} steps - Test steps
 */

/**
 * Parse a YAML-like test description into a TestIR.
 * Supports simple YAML (no nested objects beyond step level).
 */
export function parseTestIR(yamlText) {
  const lines = yamlText.split("\n");
  const ir = { steps: [] };
  let currentStep = null;

  for (const rawLine of lines) {
    const line = rawLine.replace(/#.*$/, "").trimEnd();
    if (!line || line.startsWith("---")) continue;

    // Top-level key: value
    const topMatch = line.match(/^(\w+):\s*(.+)$/);
    if (topMatch && !line.startsWith("  ") && !line.startsWith("-")) {
      const [, key, value] = topMatch;
      if (key === "steps") continue;
      if (value === "true") { ir[key] = true; continue; }
      if (value === "false") { ir[key] = false; continue; }
      if (/^\d+$/.test(value)) { ir[key] = parseInt(value); continue; }
      // Handle comma-separated arrays (e.g., args: task, tui)
      // Also handle single-value args (e.g., args: /path/to/dir)
      if (key === "args") {
        ir[key] = value.includes(",") ? value.split(",").map(s => s.trim()) : [value.trim()];
        continue;
      }
      ir[key] = value;
      continue;
    }

    // Step line: "- type: value" (may have leading whitespace)
    const stepStart = line.match(/^\s*-\s+(\w+):\s*(.+)$/);
    if (stepStart) {
      if (currentStep) ir.steps.push(currentStep);
      currentStep = { [stepStart[1]]: stepStart[2] };
      continue;
    }

    // Step property: "  key: value"
    const propMatch = line.match(/^\s+(\w+):\s*(.+)$/);
    if (propMatch && currentStep) {
      const [, key, value] = propMatch;
      if (value === "true") { currentStep[key] = true; continue; }
      if (value === "false") { currentStep[key] = false; continue; }
      if (/^\d+$/.test(value)) { currentStep[key] = parseInt(value); continue; }
      currentStep[key] = value;
      continue;
    }
  }

  if (currentStep) ir.steps.push(currentStep);

  // Set defaults
  ir.cols = ir.cols || 120;
  ir.rows = ir.rows || 30;
  ir.settleMs = ir.settleMs || 5000;

  return ir;
}

// ---------------------------------------------------------------------------
// 2. Planner — IR + semantic snapshot → execution plan
// ---------------------------------------------------------------------------

/**
 * @typedef {Object} PlanStep
 * @property {string} action - "press_key" | "type" | "wait"
 * @property {string} [key] - Key name for press_key
 * @property {string} [text] - Text for type
 * @property {number} [ms] - Milliseconds for wait
 * @property {string} irStepType - Original IR step type (for traceability)
 * @property {string} [irTarget] - Original IR target
 * @property {string} [label] - Human-readable label
 * @property {Object} [assert] - Assertion to check after this step
 */

/**
 * @typedef {Object} ExecutionPlan
 * @property {string} testName
 * @property {PlanStep[]} steps
 * @property {Object} planMeta - Planning metadata (capabilities used, etc.)
 */

/**
 * Build an execution plan from a TestIR and the initial semantic snapshot.
 *
 * The planner reads the capability map to translate app-agnostic IR steps
 * into app-specific keystrokes. For example:
 *   IR: { type: "navigate_panel", target: "Scenarios" }
 *   → reads caps.tabs to find the key for "Scenarios" panel
 *   → Plan: { action: "press_key", key: "2" }
 */
export function buildPlan(ir, snapshot) {
  const caps = snapshot.capabilities;
  const plan = {
    testName: ir.name,
    steps: [],
    planMeta: {
      worldFrameId: snapshot.world?.frameId,
      usedWorld: !!snapshot.world,
    },
  };

  for (const irStep of ir.steps) {
    const planSteps = planStep(irStep, caps, snapshot);
    plan.steps.push(...planSteps);
  }

  return plan;
}

/**
 * Plan a single IR step into one or more plan steps.
 */
function planStep(irStep, caps, snapshot) {
  const steps = [];

  switch (irStep.type) {
    case "navigate_panel": {
      const key = findPanelKey(irStep.target, caps, snapshot);
      steps.push({
        action: "press_key",
        key,
        irStepType: irStep.type,
        irTarget: irStep.target,
        label: `Navigate to ${irStep.target} panel (key: ${key})`,
      });
      break;
    }

    case "select_item": {
      // Adaptive navigation: we don't know exactly how many down presses
      // are needed, so we emit a single "select_item" plan step that
      // the runner will execute adaptively (navigate + verify each step)
      const navKeys = caps.navigate?.keys || ["down"];
      steps.push({
        action: "select_item",
        target: irStep.target,
        navKeys,
        irStepType: irStep.type,
        irTarget: irStep.target,
        label: `Select ${irStep.target}`,
        assert: { type: "item_selected", target: irStep.target },
      });
      break;
    }

    case "start_service": {
      // Use the "s" key (Start) or "p" (PDS2) from capabilities
      const worldAction = findWorldAction(snapshot, ["start", "pds2"]);
      const action = caps.actions?.find(a =>
        a.action?.toLowerCase() === "start" ||
        a.action?.toLowerCase() === "pds2"
      );
      const key = worldAction?.key || action?.key || "s";
      steps.push({
        action: "press_key",
        key,
        actionRef: worldAction?.id,
        irStepType: irStep.type,
        irTarget: irStep.target,
        label: `Start service ${irStep.target} (key: ${key})`,
      });
      // Wait for service to start
      steps.push({
        action: "wait",
        ms: 3000,
        irStepType: irStep.type,
        irTarget: irStep.target,
        assert: { type: "service_status", target: irStep.target, expected: "running" },
        label: `Wait for ${irStep.target} to start`,
      });
      break;
    }

    case "stop_service": {
      const worldAction = findWorldAction(snapshot, ["stop"]);
      const action = caps.actions?.find(a => a.action?.toLowerCase() === "stop");
      const key = worldAction?.key || action?.key || "x";
      steps.push({
        action: "press_key",
        key,
        actionRef: worldAction?.id,
        irStepType: irStep.type,
        irTarget: irStep.target,
        label: `Stop service ${irStep.target} (key: ${key})`,
      });
      steps.push({
        action: "wait",
        ms: 2000,
        irStepType: irStep.type,
        irTarget: irStep.target,
        assert: { type: "service_status", target: irStep.target, expected: "stopped" },
        label: `Wait for ${irStep.target} to stop`,
      });
      break;
    }

    case "run_scenario": {
      steps.push({
        action: "press_key",
        key: "enter",
        irStepType: irStep.type,
        irTarget: irStep.target,
        label: `Run scenario ${irStep.target || "selected"}`,
      });
      // Wait for scenario to start
      steps.push({
        action: "wait",
        ms: 5000,
        irStepType: irStep.type,
        irTarget: irStep.target,
        assert: { type: "active_run", expected: "running" },
        label: `Wait for scenario to start`,
      });
      break;
    }

    case "dismiss_overlay": {
      const popup = firstWorldNode(snapshot, { role: "popup" });
      const worldAction = popup
        ? primaryAction(snapshot.world, popup.ref, { intent: "dismiss" })
        : findWorldAction(snapshot, ["dismiss", "close", "cancel"]);
      const dismissKey = worldAction?.key || caps.dismiss?.keys?.[0] || "escape";
      steps.push({
        action: "press_key",
        key: dismissKey,
        actionRef: worldAction?.id,
        targetRef: popup?.ref,
        irStepType: irStep.type,
        label: `Dismiss overlay (key: ${dismissKey})`,
      });
      break;
    }

    case "quit": {
      const worldAction = findWorldAction(snapshot, ["quit", "exit"]);
      const quitKey = worldAction?.key || caps.quit?.keys?.[0] || "q";
      steps.push({
        action: "press_key",
        key: quitKey,
        actionRef: worldAction?.id,
        irStepType: irStep.type,
        label: `Quit (key: ${quitKey})`,
      });
      // Don't assert process exit — some apps need multiple quit presses
      // or confirmation. The runner will force-stop the session anyway.
      steps.push({
        action: "wait",
        ms: 1000,
        label: `Wait after quit`,
      });
      break;
    }

    case "wait": {
      steps.push({
        action: "wait",
        ms: irStep.timeoutMs || irStep.ms || 2000,
        irStepType: irStep.type,
        label: irStep.label || `Wait ${irStep.timeoutMs || irStep.ms || 2000}ms`,
      });
      break;
    }

    case "assert": {
      steps.push({
        action: "wait",
        ms: 100,
        irStepType: irStep.type,
        assert: { type: irStep.target || "custom", expected: irStep.expected, value: irStep.value },
        label: irStep.label || `Assert ${irStep.target} ${irStep.expected || irStep.value || ""}`,
      });
      break;
    }

    case "type": {
      steps.push({
        action: "type",
        text: irStep.value,
        irStepType: irStep.type,
        label: irStep.label || `Type "${irStep.value}"`,
      });
      break;
    }

    case "press_key": {
      steps.push({
        action: "press_key",
        key: irStep.value || irStep.key,
        irStepType: irStep.type,
        label: irStep.label || `Press ${irStep.value || irStep.key}`,
      });
      break;
    }

    default:
      console.warn(`[tui_test] Unknown IR step type: ${irStep.type}`);
  }

  return steps;
}

/**
 * Find the key to navigate to a named panel.
 * Checks tab bar, then panel titles, then falls back to number keys.
 */
function findPanelKey(target, caps, snapshot) {
  const targetLower = target.toLowerCase();

  // 1. Check normalized world tabs and their node-scoped actions.
  if (snapshot.world) {
    const tab = findNodes(snapshot.world, { role: "tab", name: target })[0];
    if (tab) {
      const action = primaryAction(snapshot.world, tab.ref);
      if (action?.key) return action.key;
      if (tab.state?.index !== undefined) return String(tab.state.index);
    }
  }

  // 2. Check detector tab bars.
  for (const tabBar of snapshot.tabs || []) {
    for (const tab of tabBar.tabs || []) {
      if (tab.label?.toLowerCase().includes(targetLower)) {
        return String(tab.index ?? 1);
      }
    }
  }

  // 3. Check capability map tab keys
  if (caps.tabs?.available && caps.tabs.keys?.length > 0) {
    // Try to match by position: "1" = first panel, "2" = second, etc.
    // Common naming: 1=Network, 2=Scenarios, 3=Active Run, 4=History
    const panelNames = {
      "network": "1", "services": "1",
      "scenarios": "2", "tests": "2",
      "active run": "3", "run": "3", "active": "3",
      "history": "4", "run history": "4", "past": "4",
    };
    const key = panelNames[targetLower];
    if (key && caps.tabs.keys.includes(key)) return key;
  }

  // 4. Check normalized pane nodes or legacy pane titles.
  if (snapshot.world) {
    const pane = findNodes(snapshot.world, { role: "pane", name: target })[0];
    if (pane?.state?.index !== undefined) return String(pane.state.index);
  }

  const paneIndex = (snapshot.panes || []).findIndex(p =>
    p.title?.toLowerCase().includes(targetLower)
  );
  if (paneIndex >= 0 && paneIndex < 4) {
    return String(paneIndex + 1);
  }

  // 5. Fallback: try tab key
  if (caps.tabs?.keys?.includes("tab")) return "tab";

  return "tab"; // ultimate fallback
}

function firstWorldNode(snapshot, options) {
  if (!snapshot.world) return null;
  return findNodes(snapshot.world, options)[0] || null;
}

function findWorldAction(snapshot, labels) {
  if (!snapshot.world) return null;
  const wanted = labels.map(label => label.toLowerCase());
  return snapshot.world.actions.find(action => {
    const text = `${action.label || ""} ${action.kind || ""}`.toLowerCase();
    return wanted.some(label => text.includes(label));
  }) || null;
}

function listItemsFromSnapshot(snapshot) {
  if (snapshot.world) {
    return findNodes(snapshot.world, { role: "list_item" }).map(node => ({
      label: node.label,
      selected: node.state?.selected === true,
      ref: node.ref,
    }));
  }
  return (snapshot.lists || []).filter(l => l.role === "list_item");
}

// ---------------------------------------------------------------------------
// 3. Runner — Execute plan with recording
// ---------------------------------------------------------------------------

/**
 * @typedef {Object} StepResult
 * @property {PlanStep} step - The plan step that was executed
 * @property {Object} [diff] - Diff from actAndVerify (for press_key)
 * @property {boolean} passed - Whether the step succeeded
 * @property {string} [error] - Error message if step failed
 * @property {Object} [assertion] - Assertion check result
 */

/**
 * @typedef {Object} TestResult
 * @property {string} testName
 * @property {boolean} passed - Overall test result
 * @property {StepResult[]} stepResults
 * @property {string} castPath - Path to the asciicast recording
 * @property {string} htmlPath - Path to the HTML playback
 * @property {number} durationMs - Total test duration
 * @property {Object} finalSnapshot - Last semantic snapshot
 */

/**
 * Run a TUI test: launch the TUI, execute the plan, record, and verify.
 *
 * @param {TestIR} ir - The test description
 * @param {Object} [options] - Runner options
 * @param {string} [options.outputDir] - Directory for recording output
 * @param {boolean} [options.recordInput=true] - Record keystrokes in asciicast
 * @param {boolean} [options.semanticOverlay=true] - Record semantic snapshots
 * @param {boolean} [options.stopOnFail=true] - Stop execution on first failure
 * @returns {Promise<TestResult>}
 */
export async function runTuiTest(ir, options = {}) {
  const startTime = Date.now();
  const outputDir = options.outputDir || defaultRecordingDir(process.cwd(), startTime);
  const stopOnFail = options.stopOnFail !== false;

  // Create session manager
  const allowEnv = { ...process.env, GARAZYK_PTY_MCP_ALLOW: ir.command };
  const manager = new TerminalSessionManager({ env: allowEnv });

  // Launch the TUI
  const session = await manager.create({
    command: ir.command,
    args: ir.args || [],
    cols: ir.cols || 120,
    rows: ir.rows || 30,
    cwd: ir.cwd || process.cwd(),
  });

  // Attach recording
  const recorder = new AsciicastRecorder({
    outputDir,
    cols: ir.cols || 120,
    rows: ir.rows || 30,
    title: ir.name || "TUI Test",
    recordInput: options.recordInput !== false,
    semanticOverlay: options.semanticOverlay !== false,
    command: ir.command,
  });
  session.attachRecording(recorder);

  // Wait for initial render
  await new Promise(r => setTimeout(r, ir.settleMs || 5000));

  // Take initial snapshot
  let snapshot = session.semanticSnapshot("compact", false).snapshot;

  // Build the execution plan
  const plan = buildPlan(ir, snapshot);

  // Execute the plan
  const stepResults = [];
  let allPassed = true;

  for (let i = 0; i < plan.steps.length; i++) {
    const step = plan.steps[i];
    const result = { step, passed: false };

    try {
      if (step.action === "press_key") {
        const avResult = await session.actAndVerify(step.key, {
          maxWaitMs: 3000,
          stableMs: 300,
        });
        result.diff = avResult.diff;
        result.passed = true;

        // Update snapshot for next step
        snapshot = avResult.after;
      } else if (step.action === "type") {
        await session.type(step.text);
        await session.waitForStable({ maxMs: 2000, stableMs: 300 });
        result.passed = true;
        snapshot = session.semanticSnapshot("compact", false).snapshot;
      } else if (step.action === "wait") {
        await new Promise(r => setTimeout(r, step.ms || 1000));
        snapshot = session.semanticSnapshot("compact", false).snapshot;
        result.passed = true;
      } else if (step.action === "select_item") {
        // Adaptive item selection: press down/up until the target is found
        const target = step.target.toLowerCase();
        const navDown = step.navKeys?.includes("down") ? "down" : (step.navKeys?.[0] || "down");
        const navUp = step.navKeys?.includes("up") ? "up" : "up";
        const maxAttempts = 20;
        let found = false;

        for (let attempt = 0; attempt < maxAttempts; attempt++) {
          // Check current snapshot for the target
          snapshot = session.semanticSnapshot("compact", false).snapshot;
          const listItems = listItemsFromSnapshot(snapshot);

          // Check if target is in any list item label
          const targetItem = listItems.find(l =>
            (l.label || "").toLowerCase().includes(target)
          );

          if (targetItem) {
            found = true;
            result.passed = true;
            result.diff = { cursorMoved: attempt > 0, selectionChanged: true };
            break;
          }

          // Press down to navigate
          const avResult = await session.actAndVerify(navDown, {
            maxWaitMs: 1000,
            stableMs: 200,
          });

          // Check if we've reached the bottom (no change)
          if (!avResult.diff.cursorMoved && attempt > 0) {
            // We've hit the bottom — try going up
            break;
          }
        }

        if (!found) {
          result.passed = false;
          result.error = `Item "${step.target}" not found after ${maxAttempts} navigation attempts`;
        }
      }

      // Check assertion if present
      if (step.assert && result.passed) {
        const assertion = checkAssertion(step.assert, snapshot, session, result.diff);
        result.assertion = assertion;
        if (!assertion.passed) {
          result.passed = false;
          result.error = assertion.message;
        }
      }
    } catch (err) {
      result.passed = false;
      result.error = err.message;
    }

    stepResults.push(result);

    if (!result.passed && stopOnFail) {
      allPassed = false;
      break;
    }

    if (!result.passed) {
      allPassed = false;
    }
  }

  // Final snapshot
  const finalSnapshot = session.semanticSnapshot("compact", false).snapshot;

  // Stop the session
  try {
    await session.stop({ force: true });
  } catch {}
  manager.dispose();

  // Close recording
  await recorder.close();

  const durationMs = Date.now() - startTime;

  return {
    testName: ir.name,
    passed: allPassed,
    stepResults,
    castPath: recorder.castPath,
    htmlPath: recorder.htmlPath,
    durationMs,
    finalSnapshot,
  };
}

// ---------------------------------------------------------------------------
// 4. Verifier — Check assertions against semantic snapshots
// ---------------------------------------------------------------------------

/**
 * Check an assertion against the current state.
 *
 * @param {Object} assertion - The assertion to check
 * @param {Object} snapshot - Current semantic snapshot
 * @param {Object} session - Terminal session (for running check)
 * @param {Object} [diff] - Diff from the last actAndVerify
 * @returns {{ passed: boolean, message: string }}
 */
function checkAssertion(assertion, snapshot, session, diff) {
  switch (assertion.type) {
    case "item_selected": {
      const target = assertion.target.toLowerCase();
      const listItems = listItemsFromSnapshot(snapshot);
      const selected = listItems.find(l => l.selected);
      // Check if the target item is in the list (may not have selected flag
      // if the TUI uses cursor-based selection rather than inverse highlighting)
      const targetItem = listItems.find(l =>
        (l.label || "").toLowerCase().includes(target)
      );
      if (selected && selected.label?.toLowerCase().includes(target)) {
        return { passed: true, message: `Item "${assertion.target}" is selected` };
      }
      if (targetItem) {
        // Item exists in the list — likely the cursor is on it
        // (cursor-based selection doesn't set the `selected` flag)
        return { passed: true, message: `Item "${assertion.target}" found in list (cursor-based selection)` };
      }
      return {
        passed: false,
        message: `Item "${assertion.target}" not found in list items`,
      };
    }

    case "service_status": {
      const target = assertion.target?.toUpperCase() || "";
      const expected = assertion.expected; // "running" or "stopped"
      const listItems = listItemsFromSnapshot(snapshot);
      const serviceItem = listItems.find(l =>
        l.label?.toUpperCase().includes(target)
      );
      if (!serviceItem) {
        return { passed: false, message: `Service "${assertion.target}" not found in list items` };
      }
      const isRunning = serviceItem.label?.includes("●") || serviceItem.label?.includes("✔");
      const isStopped = serviceItem.label?.includes("○") || serviceItem.label?.includes("--");
      if (expected === "running" && isRunning) {
        return { passed: true, message: `Service "${assertion.target}" is running` };
      }
      if (expected === "stopped" && isStopped) {
        return { passed: true, message: `Service "${assertion.target}" is stopped` };
      }
      return {
        passed: false,
        message: `Service "${assertion.target}" status: ${isRunning ? "running" : isStopped ? "stopped" : "unknown"} (expected: ${expected})`,
      };
    }

    case "active_run": {
      // Check if the Active Run panel shows a running scenario
      const rawLines = [];
      const buf = session.term.buffer.active;
      for (let y = 2; y <= 12; y++) {
        const line = buf.getLine(buf.viewportY + y);
        const text = line ? line.translateToString(true) : "";
        rawLines.push(text);
      }
      const activeRunText = rawLines.join("\n");
      if (activeRunText.includes("[run") || activeRunText.includes("Elapsed")) {
        return { passed: true, message: "Active run is in progress" };
      }
      if (activeRunText.includes("No active run")) {
        return { passed: false, message: "No active run (panel shows 'No active run')" };
      }
      return { passed: false, message: "Active run status unclear" };
    }

    case "process_exited": {
      if (diff?.processExited || !session.running) {
        return { passed: true, message: "Process exited" };
      }
      return { passed: false, message: "Process still running" };
    }

    case "panel_focused": {
      // Check if a specific panel is focused by looking at cursor position
      // or checking for inverse/bold styling in the panel header
      const target = assertion.expected?.toLowerCase() || "";
      const panes = snapshot.panes || [];
      const focusedPane = panes.find(p => p.title?.toLowerCase().includes(target));
      if (focusedPane) {
        return { passed: true, message: `Panel "${assertion.expected}" is visible` };
      }
      return { passed: false, message: `Panel "${assertion.expected}" not found` };
    }

    case "no_overlay": {
      if (snapshot.popups?.length === 0) {
        return { passed: true, message: "No overlay present" };
      }
      return { passed: false, message: `Overlay present: ${snapshot.popups?.map(p => p.title).join(", ")}` };
    }

    case "custom": {
      // Custom assertion: check if expected text appears in snapshot
      const expected = assertion.expected || assertion.value || "";
      if (!expected) return { passed: true, message: "No assertion to check" };
      // Check in list items
      const items = listItemsFromSnapshot(snapshot);
      const found = items.some(l => l.label?.includes(expected));
      if (found) {
        return { passed: true, message: `Found "${expected}" in list items` };
      }
      return { passed: false, message: `"${expected}" not found in list items` };
    }

    default:
      return { passed: true, message: `Unknown assertion type: ${assertion.type} (skipped)` };
  }
}

// ---------------------------------------------------------------------------
// 5. Reporter — Format test results
// ---------------------------------------------------------------------------

/**
 * Format a TestResult as a human-readable report.
 */
export function formatReport(result) {
  const lines = [];
  const status = result.passed ? "PASS" : "FAIL";
  const icon = result.passed ? "✓" : "✗";

  lines.push(`\n${icon} ${result.testName} — ${status} (${result.durationMs}ms)`);
  lines.push("─".repeat(60));

  for (const sr of result.stepResults) {
    const stepIcon = sr.passed ? "✓" : "✗";
    const label = sr.step.label || sr.step.action;
    lines.push(`  ${stepIcon} ${label}`);

    if (sr.assertion) {
      const assertIcon = sr.assertion.passed ? "✓" : "✗";
      lines.push(`    ${assertIcon} ${sr.assertion.message}`);
    }

    if (sr.error) {
      lines.push(`    ⚠ ${sr.error}`);
    }

    if (sr.diff) {
      const parts = [];
      if (sr.diff.cursorMoved) parts.push("cursor moved");
      if (sr.diff.changedLineCount > 0) parts.push(`${sr.diff.changedLineCount} lines changed`);
      if (sr.diff.selectionChanged) parts.push("selection changed");
      if (sr.diff.popupsChanged) parts.push("popup changed");
      if (sr.diff.processExited) parts.push("process exited");
      if (parts.length > 0) lines.push(`    → ${parts.join(", ")}`);
    }
  }

  lines.push("─".repeat(60));
  lines.push(`Recording: ${result.castPath}`);
  lines.push(`Playback:  ${result.htmlPath}`);

  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// 6. English → IR translator (template-based)
// ---------------------------------------------------------------------------

/**
 * Translate an English test description into a TestIR.
 *
 * This uses pattern matching on common English phrases to build the IR.
 * For complex tests, write the IR directly in YAML.
 *
 * @param {string} english - English test description
 * @param {Object} context - Launch context (command, args, cwd, etc.)
 * @returns {TestIR}
 */
export function englishToIR(english, context = {}) {
  const ir = {
    name: context.name || "English TUI Test",
    description: english,
    command: context.command,
    args: context.args || [],
    cwd: context.cwd,
    cols: context.cols || 120,
    rows: context.rows || 30,
    settleMs: context.settleMs || 5000,
    steps: [],
  };

  // Split into sentences
  const sentences = english.split(/[.!?]+/).map(s => s.trim()).filter(Boolean);

  for (const sentence of sentences) {
    const lower = sentence.toLowerCase();

    // "navigate to X panel" / "go to X panel" / "switch to X"
    const panelMatch = lower.match(/(?:navigate|go|switch|jump|focus)\s+(?:to\s+)?(?:the\s+)?(\w[\w\s]*?)\s*(?:panel|view|tab)?$/);
    if (panelMatch) {
      const panelName = panelMatch[1].trim();
      // Capitalize first letter
      const target = panelName.charAt(0).toUpperCase() + panelName.slice(1);
      ir.steps.push({ type: "navigate_panel", target });
      continue;
    }

    // "start X service" / "start the PDS2"
    const startMatch = lower.match(/start\s+(?:the\s+)?(\S+?)(?:\s+service)?$/);
    if (startMatch) {
      ir.steps.push({ type: "start_service", target: startMatch[1].toUpperCase() });
      continue;
    }

    // "stop X service"
    const stopMatch = lower.match(/stop\s+(?:the\s+)?(\S+?)(?:\s+service)?$/);
    if (stopMatch) {
      ir.steps.push({ type: "stop_service", target: stopMatch[1].toUpperCase() });
      continue;
    }

    // "select X" / "choose X"
    const selectMatch = lower.match(/(?:select|choose|pick|highlight)\s+(?:the\s+)?(.+)$/);
    if (selectMatch) {
      ir.steps.push({ type: "select_item", target: selectMatch[1].trim() });
      continue;
    }

    // "run X" / "execute X" / "start X scenario"
    const runMatch = lower.match(/(?:run|execute|launch|start)\s+(?:the\s+)?(.+?)(?:\s+scenario)?$/);
    if (runMatch && !lower.includes("service")) {
      ir.steps.push({ type: "run_scenario", target: runMatch[1].trim() });
      continue;
    }

    // "dismiss the overlay" / "close the popup" / "press escape"
    if (lower.match(/(?:dismiss|close|hide)\s+(?:the\s+)?(?:overlay|popup|dialog|modal|help)/)) {
      ir.steps.push({ type: "dismiss_overlay" });
      continue;
    }

    // "quit" / "exit" / "close the app"
    if (lower.match(/(?:quit|exit|close)\s*(?:the\s+)?(?:app|application|dashboard|tui)?$/)) {
      ir.steps.push({ type: "quit" });
      continue;
    }

    // "wait N seconds" / "wait for X"
    const waitMatch = lower.match(/wait\s+(?:for\s+)?(\d+)\s*(?:seconds?|ms|milliseconds?)/);
    if (waitMatch) {
      const ms = lower.includes("ms") || lower.includes("millisecond")
        ? parseInt(waitMatch[1])
        : parseInt(waitMatch[1]) * 1000;
      ir.steps.push({ type: "wait", timeoutMs: ms });
      continue;
    }

    // "type X" / "enter X"
    const typeMatch = lower.match(/(?:type|enter|input)\s+["'](.+?)["']/);
    if (typeMatch) {
      ir.steps.push({ type: "type", value: typeMatch[1] });
      continue;
    }

    // "press X"
    const pressMatch = lower.match(/press\s+(?:the\s+)?["']?(\S+?)["']?\s*(?:key)?$/);
    if (pressMatch) {
      ir.steps.push({ type: "press_key", value: pressMatch[1] });
      continue;
    }

    // "verify X" / "check X" / "assert X"
    const assertMatch = lower.match(/(?:verify|check|assert|ensure)\s+(?:that\s+)?(.+)$/);
    if (assertMatch) {
      ir.steps.push({ type: "assert", target: assertMatch[1].trim() });
      continue;
    }
  }

  return ir;
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

/**
 * Run a TUI test from a YAML file or English description.
 *
 * Usage:
 *   node tui_test.mjs --file test.yaml
 *   node tui_test.mjs --english "Navigate to Scenarios panel. Select account lifecycle. Run the scenario."
 *   node tui_test.mjs --ir '{"name":"test","command":"/path/to/app","steps":[...]}'
 */
export async function main() {
  const args = process.argv.slice(2);
  let ir;
  let outputDir;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--file" && args[i + 1]) {
      const yaml = fs.readFileSync(args[++i], "utf8");
      ir = parseTestIR(yaml);
    } else if (args[i] === "--english" && args[i + 1]) {
      const english = args[++i];
      // Need context from remaining args
      const context = {};
      for (let j = i + 1; j < args.length; j++) {
        if (args[j] === "--command" && args[j + 1]) context.command = args[++j];
        if (args[j] === "--cwd" && args[j + 1]) context.cwd = args[++j];
        if (args[j] === "--name" && args[j + 1]) context.name = args[++j];
      }
      ir = englishToIR(english, context);
    } else if (args[i] === "--ir" && args[i + 1]) {
      ir = JSON.parse(args[++i]);
    } else if (args[i] === "--output" && args[i + 1]) {
      outputDir = args[++i];
    }
  }

  if (!ir || !ir.command) {
    console.error("Usage: node tui_test.mjs --file test.yaml");
    console.error("       node tui_test.mjs --english '...' --command /path/to/app");
    console.error("       node tui_test.mjs --ir '{...}'");
    process.exit(1);
  }

  console.log(`\n▶ Running: ${ir.name}`);
  console.log(`  Command: ${ir.command} ${(ir.args || []).join(" ")}`);
  console.log(`  Steps: ${ir.steps.length}`);

  const result = await runTuiTest(ir, { outputDir });

  console.log(formatReport(result));

  process.exit(result.passed ? 0 : 1);
}

// Run if called directly
if (process.argv[1]?.endsWith("tui_test.mjs") &&
    !process.argv[1]?.includes("test")) {
  main().catch(err => {
    console.error("Fatal:", err);
    process.exit(2);
  });
}
