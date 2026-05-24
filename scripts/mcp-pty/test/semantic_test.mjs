import test from "node:test";
import assert from "node:assert";
import { guessApplication, detectStatusLines, detectTables, detectContainers } from "../semantic.mjs";

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

test("detectStatusLines", () => {
  const grid = new Array(24).fill([]); // mock grid
  const lines = new Array(24).fill("");

  lines[23] = "-- INSERT --";
  const insertMode = detectStatusLines(grid, lines);
  assert.strictEqual(insertMode.length, 1);
  assert.strictEqual(insertMode[0].value, "Insert");

  lines[23] = ":";
  const cmdMode = detectStatusLines(grid, lines);
  assert.strictEqual(cmdMode.length, 1);
  assert.strictEqual(cmdMode[0].value, "Command");

  lines[23] = "";
  lines[0] = "top - 12:34:56 up 1 day,  1:23,  1 user,  load average: 0.00, 0.01, 0.05";
  const topHeader = detectStatusLines(grid, lines);
  assert.strictEqual(topHeader.length, 1);
  assert.strictEqual(topHeader[0].value, "System top");
});

test("detectTables", () => {
  const grid = new Array(24).fill([]); // mock grid
  const lines = new Array(24).fill("");
  lines[5] = "  PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND";
  const tables = detectTables(grid, lines);
  assert.strictEqual(tables.length, 1);
  assert.strictEqual(tables[0].role, "table");
  assert.deepStrictEqual(tables[0].columns.slice(0, 3), ["PID", "USER", "PR"]);
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
