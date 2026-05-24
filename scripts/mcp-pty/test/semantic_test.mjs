import test from "node:test";
import assert from "node:assert";
import { guessApplication, detectStatusLines, detectTables, detectContainers, parseKeyHints, detectStatusBar } from "../semantic.mjs";

test("guessApplication", () => {
  const topGuess = guessApplication("/usr/bin/top", []);
  assert.strictEqual(topGuess.app, "top");
  assert.strictEqual(topGuess.confidence, 0.9);

  const vimGuess = guessApplication("/usr/bin/vim", []);
  assert.strictEqual(vimGuess.app, "vim");
  assert.strictEqual(vimGuess.confidence, 0.9);

  const lessGuess = guessApplication("/usr/bin/less", []);
  assert.strictEqual(lessGuess.app, "less");
  
  const htopGuess = guessApplication("/usr/bin/htop", []);
  assert.strictEqual(htopGuess.app, "htop");
  
  const btopGuess = guessApplication("/usr/bin/btop", []);
  assert.strictEqual(btopGuess.app, "btop");

  // Heuristic based guess
  const heuristicTop = guessApplication("/bin/cat", ["Tasks: 123 total", "Load avg: 0.00"]);
  assert.strictEqual(heuristicTop.app, "top");
  assert.strictEqual(heuristicTop.confidence, 0.7);
  
  const heuristicVim = guessApplication("/bin/cat", ["", "VIM - Vi IMproved", ""]);
  assert.strictEqual(heuristicVim.app, "vim");
  assert.strictEqual(heuristicVim.confidence, 0.7);

  const heuristicGit = guessApplication("/bin/cat", ["commit 2c3f8f0ab1c49b0e8d0e0", "Author: test", ""]);
  assert.strictEqual(heuristicGit.app, "git log");
  assert.strictEqual(heuristicGit.confidence, 0.8);

  const heuristicNano = guessApplication("/bin/cat", ["  GNU nano 6.2  "]);
  assert.strictEqual(heuristicNano.app, "nano");
  assert.strictEqual(heuristicNano.confidence, 0.8);

  const heuristicTmux = guessApplication("/bin/cat", ["", "[0] 0:bash*"]);
  assert.strictEqual(heuristicTmux.app, "tmux");
  assert.strictEqual(heuristicTmux.confidence, 0.7);
});

test("parseKeyHints descriptive phrases", () => {
  const text = "README.md: 136 lines  21%  Press ESC / q to exit, / to search, & to filter, h for help";
  const hints = parseKeyHints(text);
  assert.deepStrictEqual(
    hints.map(h => `${h.key}→${h.action}`),
    ["ESC→exit", "q→exit", "/→search", "&→filter", "h→help"],
  );
});

test("detectStatusBar detects descriptive status bars", () => {
  const cols = 120;
  const rows = 30;
  const line = "README.md: 136 lines  21%  Press ESC / q to exit, / to search, & to filter, h for help";
  const grid = Array.from({ length: rows }, () => Array.from({ length: cols }, () => ({ char: " ", bg: -1 })));
  grid[rows - 1] = Array.from({ length: cols }, (_, i) => ({ char: line[i] || " ", bg: -1 }));
  const lines = new Array(rows).fill("");
  lines[rows - 1] = line;

  const bars = detectStatusBar(grid, lines);
  assert.strictEqual(bars.length, 1);
  assert.deepStrictEqual(
    bars[0].keyActions.map(ka => `${ka.key}→${ka.action}`),
    ["ESC→exit", "q→exit", "/→search", "&→filter", "h→help"],
  );
});

test("detectStatusLines", () => {
  const grid = new Array(24).fill([]); // mock grid
  const lines = new Array(24).fill("");

  lines[23] = "-- INSERT --";
  const insertMode = detectStatusLines(grid, lines);
  const insertFact = insertMode.find(f => f.label === "Mode");
  assert.ok(insertFact);
  assert.strictEqual(insertFact.value, "Insert");

  lines[23] = ":";
  const cmdMode = detectStatusLines(grid, lines);
  const cmdFact = cmdMode.find(f => f.label === "Mode");
  assert.ok(cmdFact);
  assert.strictEqual(cmdFact.value, "Command");

  lines[23] = "";
  lines[0] = "top - 12:34:56 up 1 day,  1:23,  1 user,  load average: 0.00, 0.01, 0.05";
  const topHeader = detectStatusLines(grid, lines);
  const topFact = topHeader.find(f => f.label === "Header");
  assert.ok(topFact);
  assert.strictEqual(topFact.value, "System top");
});

test("detectTables", () => {
  const grid = new Array(24).fill([]); // mock grid
  const lines = new Array(24).fill("");
  lines[5] = "  PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND";
  const tables = detectTables(grid, lines);
  assert.strictEqual(tables.length, 1);
  assert.strictEqual(tables[0].role, "table");
  // Column parsing groups by multi-space gaps; "PID USER" is one group
  assert.ok(tables[0].columns.length >= 3);
  assert.ok(tables[0].columns.includes("PR"));
});

test("detectContainers", () => {
  const grid = new Array(24).fill([]); // mock grid
  const lines = new Array(24).fill("");
  lines[10] = "~";
  lines[11] = "~";
  lines[12] = "~";
  const containers = detectContainers(grid, lines);
  assert.strictEqual(containers.length, 1);
  assert.strictEqual(containers[0].role, "empty_space");
  assert.strictEqual(containers[0].bounds.startY, 10);
  assert.strictEqual(containers[0].bounds.endY, 12);
});

import { detectControls } from "../semantic.mjs";

test("detectControls", () => {
  const grid = new Array(24).fill([]); 
  const lines = new Array(24).fill("");
  
  lines[5] = "  [x] Enable feature   < Save >  ";
  lines[6] = "  ( ) Option A ";

  const controls = detectControls(grid, lines);
  assert.strictEqual(controls.length, 3);
  
  const checkbox = controls.find(c => c.role === "checkbox" && c.label.includes("Enable feature"));
  assert.ok(checkbox);
  
  const radio = controls.find(c => c.role === "checkbox" && c.label.includes("Option A"));
  assert.ok(radio);
  
  const button = controls.find(c => c.role === "button");
  assert.ok(button);
  assert.strictEqual(button.label, "< Save >");
});

test("parseKeyHints Textual ^key notation", () => {
  const text = "^c Quit  ^j Send  ^t Method  ^s Save  ^n New  ^P Search  ^p Commands  f1 Help";
  const hints = parseKeyHints(text);
  const map = hints.map(h => `${h.key}→${h.action}`);
  assert.ok(map.includes("ctrl+c→Quit"));
  assert.ok(map.includes("ctrl+j→Send"));
  assert.ok(map.includes("ctrl+shift+p→Search"));
  assert.ok(map.includes("ctrl+p→Commands"));
  assert.ok(map.includes("f1→Help"));
});

test("parseKeyHints ^key with or separator", () => {
  const text = "^q Quit  ^⏎ or ^j Run Query  ^s Save";
  const hints = parseKeyHints(text);
  const map = hints.map(h => `${h.key}→${h.action}`);
  assert.ok(map.includes("ctrl+q→Quit"));
  assert.ok(map.includes("ctrl+enter→Run Query"));
  assert.ok(map.includes("ctrl+j→Run Query"));
  assert.ok(map.includes("ctrl+s→Save"));
});

test("parseKeyHints rejects non-key words in descriptive pattern", () => {
  // "letters to search" should NOT produce "letters→search"
  const text = "Hit enter to go up, ? for help, or a few letters to search";
  const hints = parseKeyHints(text);
  const map = hints.map(h => `${h.key}→${h.action}`);
  assert.ok(!map.some(m => m.includes("letters")));
  assert.ok(map.includes("enter→go up"));
});

test("parseKeyHints rejects pure numeric keys from colon pattern", () => {
  // "1:1" cursor position should NOT produce "1→1"
  const text = " NOR   README.md   1 sel  1:1";
  const hints = parseKeyHints(text);
  const map = hints.map(h => `${h.key}→${h.action}`);
  assert.ok(!map.some(m => m === "1→1"));
});
