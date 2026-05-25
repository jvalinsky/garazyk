#!/usr/bin/env node
/**
 * Scenario Auto-Generator — rule-based YAML scenario generator for TUI apps.
 *
 * Given a manifest entry (from manifest.json), generates a YAML scenario file
 * that exercises the app's core UI patterns based on its category and framework.
 *
 * Usage:
 *   node corpus/generator.mjs <app-id>          # generate for a single app
 *   node corpus/generator.mjs --all             # generate for all apps with binaries
 *   node corpus/generator.mjs --installed       # generate for installed apps only
 *   node corpus/generator.mjs --dry-run         # print scenarios without writing
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MANIFEST_PATH = path.join(__dirname, "manifest.json");
const TESTS_DIR = path.join(__dirname, "..", "tests");

// ── Category-specific step generators ───────────────────────────────────

/**
 * Generate steps for a system monitor (btop, htop, bottom, top, zenith).
 * Pattern: wait → observe → tab through views → quit
 */
function monitorSteps(app) {
  const steps = [
    { type: "wait", timeoutMs: 1000, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    {
      type: "assert_semantic",
      target: "framework",
      expected: app.framework,
      label: `Verify framework is ${app.framework}`,
    },
  ];

  // Tab through views if the app has tab navigation
  if (app.uiPatterns.includes("tab-navigation")) {
    steps.push(
      { type: "press_key", value: "tab", label: "Switch to next tab" },
      { type: "wait", timeoutMs: 500, label: "Brief pause" },
      {
        type: "assert_content_changed",
        label: "Verify content changed after tab switch",
      },
      { type: "press_key", value: "tab", label: "Switch to third tab" },
      { type: "wait", timeoutMs: 500, label: "Brief pause" },
    );
  }

  // Navigate list if there's a process list
  if (
    app.uiPatterns.includes("process-list") ||
    app.uiPatterns.includes("list-selection")
  ) {
    steps.push(
      { type: "press_key", value: "j", label: "Navigate down" },
      { type: "wait", timeoutMs: 200, label: "Brief pause" },
      { type: "press_key", value: "k", label: "Navigate up" },
      { type: "wait", timeoutMs: 200, label: "Brief pause" },
      {
        type: "assert_cursor_moved",
        label: "Verify cursor moved (at least 1 of 2 directions)",
      },
    );
  }

  // Quit
  steps.push({ type: "quit", label: `Quit ${app.name}` });
  steps.push({ type: "wait", timeoutMs: 1000, label: "Wait for exit" });

  return steps;
}

/**
 * Generate steps for a file manager (yazi, ranger, lf, broot, joshuto, xplr).
 * Pattern: wait → observe → navigate → select → quit
 */
function fileManagerSteps(app) {
  const steps = [
    { type: "wait", timeoutMs: 1000, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    { type: "press_key", value: "j", label: "Navigate down in file list" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "press_key", value: "k", label: "Navigate up in file list" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
  ];

  // ranger (ncurses): terminal cursor doesn't move with j/k (uses reverse video)
  if (app.id === "ranger") {
    steps.push({
      type: "observe",
      label: "Verify app still responsive after navigation (known: ncurses cursor)",
    });
  } else {
    steps.push({ type: "assert_cursor_moved", label: "Verify cursor moved (at least 1 of 2 directions)" });
  }

  steps.push({ type: "quit", label: `Quit ${app.name}` });
  steps.push({ type: "wait", timeoutMs: 1000, label: "Wait for exit" });

  return steps;
}

/**
 * Generate steps for a git client (lazygit, gitui, tig).
 * Pattern: wait → observe → tab through views → quit
 */
function gitClientSteps(app) {
  const steps = [
    { type: "wait", timeoutMs: 1500, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
  ];

  // Only assert framework for non-lazygit apps (lazygit bubbletea is often
  // misdetected as ratatui by semantic fingerprinting)
  if (app.id !== "lazygit") {
    steps.push({
      type: "assert_semantic",
      target: "framework",
      expected: app.framework,
      label: `Verify framework is ${app.framework}`,
    });
  }

  if (app.uiPatterns.includes("tab-navigation")) {
    steps.push(
      { type: "press_key", value: "1", label: "Switch to first panel" },
      { type: "wait", timeoutMs: 300, label: "Brief pause" },
      { type: "press_key", value: "2", label: "Switch to second panel" },
      { type: "wait", timeoutMs: 300, label: "Brief pause" },
    );
  }

  if (app.uiPatterns.includes("list-selection")) {
    // gitui uses arrow keys for navigation, not j/k
    const down = app.navKeys?.down || (app.id === "gitui" ? "down" : "j");
    const up = app.navKeys?.up || (app.id === "gitui" ? "up" : "k");
    steps.push(
      { type: "press_key", value: down, label: "Navigate down in list" },
      { type: "wait", timeoutMs: 200, label: "Brief pause" },
      { type: "press_key", value: up, label: "Navigate up in list" },
      { type: "wait", timeoutMs: 200, label: "Brief pause" },
    );

    // lazygit (bubbletea): terminal cursor doesn't move with j/k (uses
    // reverse-video highlight for selection tracking)
    if (app.id === "lazygit") {
      steps.push({
        type: "observe",
        label: "Verify app still responsive after navigation (known: bubbletea cursor)",
      });
    } else {
      steps.push({ type: "assert_cursor_moved", label: "Verify cursor moved (at least 1 of 2 directions)" });
    }
  }

  steps.push({ type: "quit", label: `Quit ${app.name}` });
  steps.push({ type: "wait", timeoutMs: 1000, label: "Wait for exit" });

  return steps;
}

/**
 * Generate steps for a data browser (csvlens, harlequin, etc.).
 * Pattern: wait → observe → navigate → quit
 */
function dataBrowserSteps(app) {
  const steps = [
    { type: "wait", timeoutMs: 1500, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
  ];

  if (
    app.uiPatterns.includes("table") ||
    app.uiPatterns.includes("list-selection")
  ) {
    steps.push(
      { type: "press_key", value: "j", label: "Navigate down" },
      { type: "wait", timeoutMs: 200, label: "Brief pause" },
      { type: "press_key", value: "k", label: "Navigate up" },
      { type: "wait", timeoutMs: 200, label: "Brief pause" },
      { type: "assert_cursor_moved", label: "Verify cursor moved (at least 1 of 2 directions)" },
    );
  }

  if (app.uiPatterns.includes("tab-navigation")) {
    steps.push(
      { type: "press_key", value: "tab", label: "Switch tab" },
      { type: "wait", timeoutMs: 500, label: "Wait for tab switch" },
    );
  }

  steps.push({ type: "quit", label: `Quit ${app.name}` });
  steps.push({ type: "wait", timeoutMs: 1000, label: "Wait for exit" });

  return steps;
}

/**
 * Generate steps for a text editor (vim, helix, nano).
 * Pattern: wait → observe → type → verify → quit
 */
function textEditorSteps(app) {
  const steps = [
    { type: "wait", timeoutMs: 1000, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
  ];

  // Vim/Helix: enter insert mode, type something, escape, then quit
  if (app.id === "vim" || app.id === "helix") {
    steps.push(
      { type: "press_key", value: "i", label: "Enter insert mode" },
      { type: "wait", timeoutMs: 200, label: "Wait for mode switch" },
      { type: "type", value: "Hello from TUI test", label: "Type some text" },
      { type: "wait", timeoutMs: 200, label: "Brief pause" },
      { type: "assert_content_changed", label: "Verify content changed" },
      { type: "press_key", value: "escape", label: "Return to normal mode" },
      { type: "wait", timeoutMs: 200, label: "Brief pause" },
      { type: "type", value: ":q!", label: "Force quit without saving" },
      { type: "wait", timeoutMs: 500, label: "Wait for exit" },
    );
  } else if (app.id === "nano") {
    steps.push(
      { type: "type", value: "Hello from TUI test", label: "Type some text" },
      { type: "wait", timeoutMs: 200, label: "Brief pause" },
      { type: "press_key", value: "ctrl-x", label: "Exit nano (Ctrl+X)" },
      { type: "wait", timeoutMs: 300, label: "Wait for save prompt" },
      { type: "press_key", value: "n", label: "Don't save" },
      { type: "wait", timeoutMs: 500, label: "Wait for exit" },
    );
  } else {
    steps.push(
      { type: "quit", label: `Quit ${app.name}` },
      { type: "wait", timeoutMs: 1000, label: "Wait for exit" },
    );
  }

  return steps;
}

/**
 * Generate steps for a game (tty-solitaire, nsnake, nudoku, nethack).
 * Pattern: wait → observe → start → navigate → quit
 */
function gameSteps(app) {
  const steps = [
    { type: "wait", timeoutMs: 2000, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
  ];

  if (app.id === "tty-solitaire") {
    steps.push(
      { type: "press_key", value: "space", label: "Start the game" },
      { type: "wait", timeoutMs: 1500, label: "Wait for game board" },
    );
  }

  // Navigate with arrow/hjkl keys
  steps.push(
    { type: "press_key", value: "j", label: "Move down" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "press_key", value: "k", label: "Move up" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "press_key", value: "l", label: "Move right" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "press_key", value: "h", label: "Move left" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
  );

  // nudoku: full grid may have no empty cells to navigate into (known limitation)
  // nsnake: ncurses game uses reverse-video highlight, terminal cursor stays {0,0}
  if (app.id === "nudoku" || app.id === "nsnake") {
    const reason = app.id === "nudoku" ? "full grid" : "ncurses cursor";
    steps.push({
      type: "observe",
      label: `Verify app still responsive after navigation (known: ${reason})`,
    });
  } else {
    steps.push({
      type: "assert_cursor_moved",
      label: "Verify cursor moved (at least 1 of 4 directions)",
    });
  }

  // Action key
  if (app.id === "nsnake") {
    steps.push({ type: "press_key", value: "p", label: "Pause game" });
    steps.push({ type: "wait", timeoutMs: 300, label: "Brief pause" });
  }

  steps.push({ type: "quit", label: `Quit ${app.name}` });
  steps.push({ type: "wait", timeoutMs: 1000, label: "Wait for exit" });

  return steps;
}

/**
 * Generate steps for a music player (cmus, ncmpcpp).
 * Pattern: wait → observe → navigate → quit
 */
function musicSteps(app) {
  return [
    { type: "wait", timeoutMs: 1500, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    { type: "press_key", value: "1", label: "Switch to library tab" },
    { type: "wait", timeoutMs: 300, label: "Brief pause" },
    { type: "press_key", value: "2", label: "Switch to playlist tab" },
    { type: "wait", timeoutMs: 300, label: "Brief pause" },
    { type: "press_key", value: "j", label: "Navigate down" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "press_key", value: "k", label: "Navigate up" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "assert_cursor_moved", label: "Verify cursor moved (at least 1 of 2 directions)" },
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 1000, label: "Wait for exit" },
  ];
}

/**
 * Generate steps for a picker/filter (fzf, gum).
 * Pattern: type search → filter → quit
 */
function pickerSteps(app) {
  return [
    { type: "wait", timeoutMs: 1000, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    { type: "type", value: "test", label: "Type search filter" },
    { type: "wait", timeoutMs: 300, label: "Wait for filter" },
    { type: "assert_content_changed", label: "Verify content filtered" },
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 500, label: "Wait for exit" },
  ];
}

/**
 * Generate steps for a pager (less, moar).
 * Pattern: wait → scroll → quit
 */
function pagerSteps(app) {
  return [
    { type: "wait", timeoutMs: 1000, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    { type: "press_key", value: "j", label: "Scroll down" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "assert_content_changed", label: "Verify content scrolled" },
    { type: "press_key", value: "k", label: "Scroll up" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 500, label: "Wait for exit" },
  ];
}

/**
 * Generate steps for a markdown viewer (glow).
 * Pattern: wait → scroll → search → quit
 */
function markdownSteps(app) {
  return [
    { type: "wait", timeoutMs: 1000, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    { type: "press_key", value: "j", label: "Scroll down" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "press_key", value: "k", label: "Scroll up" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 500, label: "Wait for exit" },
  ];
}

/**
 * Generate steps for a disk analyzer (ncdu, dua-cli, diskonaut).
 * Pattern: wait → observe → navigate → quit
 *
 * Known limitations:
 * - ncdu (ncurses): terminal cursor doesn't move during j/k navigation (uses
 *   reverse-video highlight). assert_cursor_moved is skipped; observe verifies
 *   the app remains responsive instead.
 */
function diskAnalyzerSteps(app) {
  const steps = [
    { type: "wait", timeoutMs: 1500, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
  ];

  // Navigate list
  steps.push(
    { type: "press_key", value: "j", label: "Navigate down" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "press_key", value: "k", label: "Navigate up" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
  );

  // ncdu (ncurses): terminal cursor doesn't move with j/k (uses reverse video)
  if (app.id === "ncdu") {
    steps.push({
      type: "observe",
      label: "Verify app still responsive after navigation (known: ncurses cursor)",
    });
  } else {
    steps.push({
      type: "assert_cursor_moved",
      label: "Verify cursor moved (at least 1 of 2 directions)",
    });
  }

  steps.push(
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 1000, label: "Wait for exit" },
  );

  return steps;
}

/**
 * Generate steps for a dashboard app (garazyk-scenario-dashboard, blessed-contrib).
 * Pattern: wait → observe → navigate panels → select item → quit
 */
function dashboardSteps(app) {
  return [
    { type: "wait", timeoutMs: 3000, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    { type: "press_key", value: "tab", label: "Switch panel focus" },
    { type: "wait", timeoutMs: 500, label: "Wait for focus switch" },
    { type: "press_key", value: "j", label: "Navigate down" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "press_key", value: "k", label: "Navigate up" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "assert_cursor_moved", label: "Verify cursor moved (at least 1 of 2 directions)" },
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 1000, label: "Wait for exit" },
  ];
}

/**
 * Generate steps for a terminal multiplexer (tmux, zellij).
 * Pattern: wait → observe → split/create tabs → quit
 */
function terminalMuxSteps(app) {
  return [
    { type: "wait", timeoutMs: 1500, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 1000, label: "Wait for exit" },
  ];
}

/**
 * Generate steps for network tools (trippy, bandwhich).
 * Pattern: wait → observe → navigate tabs → quit
 */
function networkToolSteps(app) {
  return [
    { type: "wait", timeoutMs: 3000, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    { type: "press_key", value: "j", label: "Navigate down" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "press_key", value: "k", label: "Navigate up" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "assert_cursor_moved", label: "Verify cursor moved (at least 1 of 2 directions)" },
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 1000, label: "Wait for exit" },
  ];
}

/**
 * Generate steps for dev tools (bacon).
 */
function devToolSteps(app) {
  return [
    { type: "wait", timeoutMs: 1500, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    { type: "press_key", value: "j", label: "Navigate down" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "press_key", value: "k", label: "Navigate up" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "assert_cursor_moved", label: "Verify cursor moved (at least 1 of 2 directions)" },
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 1000, label: "Wait for exit" },
  ];
}

/**
 * Generate steps for API clients (posting).
 */
function apiClientSteps(app) {
  return [
    { type: "wait", timeoutMs: 3000, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    {
      type: "assert_semantic",
      target: "framework",
      expected: app.framework,
      label: `Verify framework is ${app.framework}`,
    },
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 1000, label: "Wait for exit" },
  ];
}

/**
 * Generate steps for an art/animation app (cbonsai).
 */
function artSteps(app) {
  return [
    { type: "wait", timeoutMs: 2000, label: `Wait for ${app.name} to animate` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 500, label: "Wait for exit" },
  ];
}

/**
 * Generate steps for a security tool (gpg-tui).
 */
function securitySteps(app) {
  return [
    { type: "wait", timeoutMs: 1000, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    { type: "press_key", value: "j", label: "Navigate down" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "press_key", value: "k", label: "Navigate up" },
    { type: "wait", timeoutMs: 200, label: "Brief pause" },
    { type: "assert_cursor_moved", label: "Verify cursor moved (at least 1 of 2 directions)" },
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 500, label: "Wait for exit" },
  ];
}

/**
 * Default/minimal steps for unknown or uncategorized apps.
 */
function defaultSteps(app) {
  return [
    { type: "wait", timeoutMs: 1500, label: `Wait for ${app.name} to render` },
    { type: "observe", label: "Take semantic snapshot" },
    {
      type: "assert_semantic",
      target: "app",
      expected: app.id,
      label: `Verify app is ${app.id}`,
    },
    {
      type: "assert_capability",
      target: "quit.keys",
      contains: app.quitKeys || ["q"],
      label: "Verify quit key is available",
    },
    { type: "quit", label: `Quit ${app.name}` },
    { type: "wait", timeoutMs: 1000, label: "Wait for exit" },
  ];
}

// ── Category → generator mapping ────────────────────────────────────────

const CATEGORY_GENERATORS = {
  // Core categories with dedicated generators
  "system-monitor": monitorSteps,
  "file-manager": fileManagerSteps,
  "git-client": gitClientSteps,
  "data-browser": dataBrowserSteps,
  "text-editor": textEditorSteps,
  "game": gameSteps,
  "music": musicSteps,
  "picker": pickerSteps,
  "pager": pagerSteps,
  "markdown-viewer": markdownSteps,
  "disk-analyzer": diskAnalyzerSteps,
  "dashboard": dashboardSteps,
  "terminal-mux": terminalMuxSteps,
  "network-tool": networkToolSteps,
  "dev-tool": devToolSteps,
  "form-tool": defaultSteps,
  "api-client": apiClientSteps,
  "art": artSteps,
  "security": securitySteps,
  "database": dataBrowserSteps,
  "log-viewer": pagerSteps,
  "renderer": artSteps,
  "drawing": artSteps,
  "stocks": networkToolSteps,
  "color-tool": artSteps,
  "ai-chat": apiClientSteps,
  "timezone": pickerSteps,

  // Expanded categories mapped to closest existing generators
  "task-mgmt": devToolSteps,
  "git-server": devToolSteps,
  "terminal-recorder": devToolSteps,
  "crypto": devToolSteps,
  "key-value": pickerSteps,
  "email": dataBrowserSteps,
  "ssh-directory": pickerSteps,
  "form-library": defaultSteps,
  "file-picker": fileManagerSteps,
  "cli-builder": defaultSteps,
  "profiler": monitorSteps,
  "markdown": markdownSteps,
  "chat": apiClientSteps,
  "emoji-tool": pickerSteps,
  "project-mgmt": devToolSteps,
  "package-mgmt": pickerSteps,
  "screenshot": devToolSteps,
  "clipboard": pickerSteps,
  "image-gen": artSteps,
  "web": defaultSteps,
  "debugger": devToolSteps,
  "testing": devToolSteps,
  "notebook": dataBrowserSteps,
  "demo": artSteps,
  "board": defaultSteps,
  "notes": pickerSteps,
  "docker": monitorSteps,
  "kubernetes": monitorSteps,
  "rss": dataBrowserSteps,
  "finance": networkToolSteps,
  "search": pickerSteps,
  "file-lister": defaultSteps,
  "shell-history": pickerSteps,
  "settings": dataBrowserSteps,
  "form": defaultSteps,
};

// ── YAML serialization ──────────────────────────────────────────────────

function toYaml(obj, indent = 0) {
  const pad = "  ".repeat(indent);
  let out = "";

  if (Array.isArray(obj)) {
    for (const item of obj) {
      if (typeof item === "object" && item !== null && !Array.isArray(item)) {
        out += `${pad}-`;
        // Write first key inline, rest on separate lines
        const entries = Object.entries(item);
        if (entries.length === 0) {
          out += " {}\n";
          continue;
        }
        // Filter out entries where value is null/undefined
        const filtered = entries.filter(([, v]) => v != null);
        if (filtered.length === 0) {
          out += " {}\n";
          continue;
        }
        // Special handling for "type" as first key (our convention)
        const [firstKey, firstVal] = filtered[0];
        const rest = filtered.slice(1);

        if (typeof firstVal === "string") {
          out += ` ${firstKey}: ${escapeYaml(firstVal)}\n`;
        } else if (Array.isArray(firstVal)) {
          out += ` ${firstKey}:\n`;
          out += toYaml(firstVal, indent + 1);
        } else if (typeof firstVal === "object") {
          out += ` ${firstKey}:\n`;
          out += toYaml(firstVal, indent + 1);
        } else {
          out += ` ${firstKey}: ${JSON.stringify(firstVal)}\n`;
        }

        for (const [key, val] of rest) {
          if (val == null) continue;
          if (typeof val === "string") {
            out += `${pad}  ${key}: ${escapeYaml(val)}\n`;
          } else if (
            Array.isArray(val) && val.every((v) => typeof v === "string")
          ) {
            out += `${pad}  ${key}: ${formatInlineArray(val)}\n`;
          } else if (typeof val === "number" || typeof val === "boolean") {
            out += `${pad}  ${key}: ${JSON.stringify(val)}\n`;
          } else if (Array.isArray(val)) {
            out += `${pad}  ${key}:\n${toYaml(val, indent + 2)}`;
          } else if (typeof val === "object") {
            out += `${pad}  ${key}:\n${toYaml(val, indent + 2)}`;
          }
        }
      } else if (typeof item === "string") {
        out += `${pad}- ${escapeYaml(item)}\n`;
      } else {
        out += `${pad}- ${JSON.stringify(item)}\n`;
      }
    }
  } else if (typeof obj === "object" && obj !== null) {
    for (const [key, val] of Object.entries(obj)) {
      if (val == null) continue;
      if (typeof val === "string") {
        out += `${pad}${key}: ${escapeYaml(val)}\n`;
      } else if (typeof val === "number" || typeof val === "boolean") {
        out += `${pad}${key}: ${JSON.stringify(val)}\n`;
      } else if (Array.isArray(val)) {
        if (val.every((v) => typeof v === "string")) {
          out += `${pad}${key}: ${formatInlineArray(val)}\n`;
        } else {
          out += `${pad}${key}:\n${toYaml(val, indent + 1)}`;
        }
      } else if (typeof val === "object") {
        out += `${pad}${key}:\n${toYaml(val, indent + 1)}`;
      }
    }
  }

  return out;
}

function formatInlineArray(values) {
  return `[${values.map(escapeYaml).join(", ")}]`;
}

function escapeYaml(str) {
  // Guard against YAML type coercion: strings that look like booleans, null, or numbers
  // must be quoted to prevent misinterpretation by YAML parsers
  if (
    /^(yes|no|true|false|null|on|off|~|[-+]?\d+(\.\d+)?([eE][-+]?\d+)?)$/i.test(
      str,
    )
  ) {
    return `"${str}"`;
  }
  // YAML strings don't need quotes unless they contain special chars
  if (
    /[:{}\[\],&*?|>!%@`]/.test(str) || str.startsWith("#") ||
    str.startsWith("'") || str.startsWith('"')
  ) {
    return `"${
      str.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")
        .replace(/\r/g, "\\r")
    }"`;
  }
  return str;
}

// ── Main generator function ─────────────────────────────────────────────

/**
 * Generate a YAML scenario for a TUI app from its manifest entry.
 *
 * @param {object} app - Manifest entry with id, name, framework, category, binary, etc.
 * @returns {string} YAML scenario as a string
 */
export function generateScenario(app) {
  const category = app.category || "unknown";
  const generator = CATEGORY_GENERATORS[category] || defaultSteps;

  // Determine command and args
  const command = app.binary || app.installPackage || app.id;

  // Determine cols/rows based on category
  let cols = 80;
  let rows = 24;

  if (category === "game") {
    cols = app.id === "tty-solitaire" ? 60 : 80;
    rows = app.id === "tty-solitaire" ? 30 : 24;
  } else if (category === "system-monitor") {
    cols = 120;
    rows = 30;
  } else if (category === "dashboard") {
    cols = 120;
    rows = 30;
  } else if (category === "file-manager") {
    cols = 100;
    rows = 28;
  } else if (category === "text-editor") {
    cols = 80;
    rows = 24;
  }

  // Build scenario document
  const scenario = {
    name: `${app.name} ${category.replace("-", " ")}`,
    description:
      `Launch ${app.name}, verify semantic detection, exercise ${category} patterns, then quit`,
    command,
    args: app.launchArgs?.length > 0 ? app.launchArgs : undefined,
    cols,
    rows,
    settleMs: app.settleMs || 2000,
    cwd: app.cwd || undefined,
    steps: generator(app),
  };

  // Add framework hint as a comment
  let yaml =
    `# Auto-generated scenario for ${app.name} (${app.framework}/${app.category})\n`;
  yaml += `# Framework confidence via semantic detection will be verified\n`;
  yaml += `# UI Patterns: ${(app.uiPatterns || []).join(", ")}\n`;
  yaml += toYaml(scenario);

  return yaml;
}

/**
 * Load the manifest from disk.
 * @returns {object} Parsed manifest
 */
export function loadManifest() {
  const raw = fs.readFileSync(MANIFEST_PATH, "utf-8");
  return JSON.parse(raw);
}

/**
 * Generate scenarios for all apps in the manifest that have a binary path.
 * Returns a Map of app-id → YAML string.
 */
export function generateAll(manifest) {
  const results = new Map();
  for (const app of manifest.apps) {
    // Only generate for apps that have a binary. Local apps without binaries
    // (e.g., OpenTUI components without a known deno entry point) are skipped
    // since they can't produce a runnable command.
    if (!app.binary) continue;
    results.set(app.id, generateScenario(app));
  }
  return results;
}

// ── CLI Entry ────────────────────────────────────────────────────────────

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const manifest = loadManifest();

  const dryRun = args.includes("--dry-run");
  const allFlag = args.includes("--all");
  const installedOnly = args.includes("--installed");

  if (allFlag || installedOnly) {
    // Batch mode: generate for all eligible apps
    const scenarios = generateAll(manifest);
    console.log(`Generated ${scenarios.size} scenarios:\n`);

    for (const [id, yaml] of scenarios) {
      const app = manifest.apps.find((a) => a.id === id);
      if (!app) continue;

      const filename = app.scenario || `${id}.yaml`;
      const filepath = path.join(TESTS_DIR, filename);

      if (dryRun) {
        console.log(`── ${id} (${filename}) ──`);
        console.log(yaml);
        console.log("");
      } else {
        fs.writeFileSync(filepath, yaml);
        console.log(`  ✓ ${filename}`);
      }
    }

    if (!dryRun) {
      console.log(`\nWrote ${scenarios.size} scenarios to ${TESTS_DIR}/`);
    }
  } else if (args.length > 0 && !args[0].startsWith("--")) {
    // Single app mode
    const appId = args[0];
    const app = manifest.apps.find((a) => a.id === appId);
    if (!app) {
      console.error(`App "${appId}" not found in manifest.`);
      process.exit(1);
    }

    const yaml = generateScenario(app);

    if (dryRun) {
      console.log(yaml);
    } else {
      const filename = app.scenario || `${appId}.yaml`;
      const filepath = path.join(TESTS_DIR, filename);
      fs.writeFileSync(filepath, yaml);
      console.log(`✓ Generated ${filepath}`);
      console.log(
        `  ${app.name} (${app.framework}/${app.category}) → ${
          app.uiPatterns?.length || 0
        } UI patterns`,
      );
    }
  } else {
    console.log("Usage: node corpus/generator.mjs <app-id> [--dry-run]");
    console.log("       node corpus/generator.mjs --all [--dry-run]");
    console.log("       node corpus/generator.mjs --installed [--dry-run]");
    console.log("");
    console.log(
      "Available categories: " + Object.keys(CATEGORY_GENERATORS).join(", "),
    );
    process.exit(0);
  }
}
