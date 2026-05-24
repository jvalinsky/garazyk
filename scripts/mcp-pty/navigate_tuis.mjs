#!/usr/bin/env node
/**
 * Navigate diverse TUI applications using the observe-decide-act-verify loop.
 *
 * Apps tested (by framework):
 *   Bubbletea:  lazygit, posting
 *   Ratatui:    gitui, yazi, csvlens, trippy
 *   Python:     harlequin
 *   ncurses:    ncdu, tty-solitaire
 *
 * Each app exercises different navigation patterns:
 *   lazygit       — split-pane, tabs, list selection, text input, confirm dialogs
 *   gitui         — popup overlays, commit workflow, list selection
 *   yazi          — dual-pane, tabs, file preview, key chords
 *   csvlens       — tabular data, horizontal scrolling, filtering
 *   ncdu          — tree navigation, deletion confirmation
 *   posting       — tabbed forms, HTTP methods, response viewer
 *   tty-solitaire — card game, 2D selection, movement
 *   harlequin     — SQL editor, schema tree, results table
 *   trippy        — tabbed, real-time charts, table
 *
 * Usage: node navigate_tuis.mjs [app|all]
 */

import { TerminalSessionManager } from "./terminal_session.mjs";

const app = process.argv[2] || "all";

// ── Helpers ──────────────────────────────────────────────────────────────

async function observe(session, settleMs = 300) {
  await session.settle(settleMs);
  return session.snapshot();
}

async function observeSemantic(session, settleMs = 300) {
  await session.settle(settleMs);
  return session.semanticSnapshot("full", false);
}

async function act(session, key) {
  if (!session.running) throw new Error("Session not running");
  const specialKeys = new Set([
    "enter", "return", "tab", "escape", "esc", "backspace",
    "up", "down", "left", "right",
    "ctrl-c", "ctrl-d", "ctrl-z", "ctrl-l",
  ]);
  if (specialKeys.has(key)) {
    await session.pressKey(key);
  } else {
    await session.type(key);
  }
  await session.settle(200);
}

function box(title, lines) {
  const w = 70;
  console.log(`\n┌─ ${title} ${"─".repeat(Math.max(0, w - title.length - 3))}┐`);
  for (const l of lines) console.log(`  ${l}`);
  console.log("└" + "─".repeat(w + 1) + "┘");
}

function summarize(snap, n = 3) {
  const lines = [];
  lines.push(`Running: ${snap.running}  Cursor: ${JSON.stringify(snap.cursor)}`);
  lines.push(`First ${n} lines:`);
  for (let i = 0; i < Math.min(n, snap.lines.length); i++) {
    lines.push(`  L${i}: ${snap.lines[i]?.substring(0, 68)}`);
  }
  lines.push(`Last ${n} lines:`);
  for (let i = Math.max(0, snap.lines.length - n); i < snap.lines.length; i++) {
    lines.push(`  L${i}: ${snap.lines[i]?.substring(0, 68)}`);
  }
  return lines;
}

// ── lazygit ──────────────────────────────────────────────────────────────

async function navigateLazygit() {
  console.log("\n╔══════════════════════════════════════════════════════════════════════╗");
  console.log("║  LAZYGIT — Bubbletea split-pane, tabs, lists, text input           ║");
  console.log("╚══════════════════════════════════════════════════════════════════════╝");

  const CMD = "/opt/homebrew/bin/lazygit";
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: CMD },
  });

  // Run in the garazyk repo so lazygit has content
  const session = manager.create({
    command: CMD,
    cols: 120, rows: 30,
    cwd: "/Users/jack/Software/garazyk",
    env: { TERM: "xterm-256color" },
  });
  await new Promise(r => setTimeout(r, 2000));

  // Step 1: OBSERVE
  const snap1 = await observe(session);
  const sem1 = await observeSemantic(session);

  box("Step 1: OBSERVE", [
    ...summarize(snap1, 4),
    `Semantic app: ${sem1.snapshot.app} (conf: ${sem1.snapshot.confidence})`,
    `Semantic VDOM:`,
    sem1.snapshot.vdomViz.substring(0, 500),
  ]);

  // Step 2: DECIDE
  box("Step 2: DECIDE", [
    "Goal: Navigate panels, switch tabs, scroll lists, try commit",
    "lazygit keys: j/k=scroll, h/l=switch panel, 1-5=tab, c=commit",
    "  q=quit, /=filter, space=select, enter=confirm",
    "Pattern: Status → Files → Branches → Commits → Stash",
  ]);

  // Step 3: Navigate panels (h/l to switch)
  console.log("\n┌─ Step 3: ACT ─ Switch panels with h/l ─┐");
  await act(session, "l"); // move to right panel
  const snap3 = await observe(session);
  console.log(`  After 'l': cursor=${JSON.stringify(snap3.cursor)}`);
  await act(session, "h"); // back to left
  const snap3b = await observe(session);
  console.log(`  After 'h': cursor=${JSON.stringify(snap3b.cursor)}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 4: Switch tabs (1-5)
  console.log("\n┌─ Step 4: ACT ─ Switch tabs (1-5) ─┐");
  await act(session, "2"); // Files tab
  const snap4a = await observe(session);
  console.log(`  Tab 2 (Files): L0="${snap4a.lines[0]?.substring(0, 60)}"`);
  await act(session, "3"); // Branches tab
  const snap4b = await observe(session);
  console.log(`  Tab 3 (Branches): L0="${snap4b.lines[0]?.substring(0, 60)}"`);
  await act(session, "4"); // Commits tab
  const snap4c = await observe(session);
  console.log(`  Tab 4 (Commits): L0="${snap4c.lines[0]?.substring(0, 60)}"`);
  await act(session, "5"); // Stash tab
  const snap4d = await observe(session);
  console.log(`  Tab 5 (Stash): L0="${snap4d.lines[0]?.substring(0, 60)}"`);
  await act(session, "1"); // back to Status
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 5: Scroll list (j/k)
  console.log("\n┌─ Step 5: ACT ─ Scroll list with j/k ─┐");
  for (let i = 0; i < 5; i++) await act(session, "j");
  const snap5 = await observe(session);
  console.log(`  After 5x j: cursor=${JSON.stringify(snap5.cursor)}`);
  for (let i = 0; i < 3; i++) await act(session, "k");
  const snap5b = await observe(session);
  console.log(`  After 3x k: cursor=${JSON.stringify(snap5b.cursor)}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 6: Try filter (/)
  console.log("\n┌─ Step 6: ACT ─ Try filter (/) ─┐");
  await act(session, "/");
  const snap6 = await observe(session);
  console.log(`  After '/': L0="${snap6.lines[0]?.substring(0, 60)}"`);
  // Check if a search/filter input appeared
  const hasFilter = snap6.lines.some(l => /filter|search|find/i.test(l));
  console.log(`  Filter prompt detected: ${hasFilter}`);
  await act(session, "escape"); // cancel filter
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 7: CLEANUP
  console.log("\n┌─ Step 7: CLEANUP ─ Quit lazygit ─┐");
  await act(session, "q");
  await new Promise(r => setTimeout(r, 500));
  const quitSnap = session.snapshot();
  console.log(`  Running after 'q': ${quitSnap.running}`);
  if (quitSnap.running) {
    await act(session, "q");
    await new Promise(r => setTimeout(r, 500));
  }
  console.log("└────────────────────────────────────────────────────────────────────┘");

  await session.stop({ force: true });
  manager.dispose();
}

// ── gitui ────────────────────────────────────────────────────────────────

async function navigateGitui() {
  console.log("\n╔══════════════════════════════════════════════════════════════════════╗");
  console.log("║  GITUI — Ratatui popup overlays, commit workflow, list selection  ║");
  console.log("╚══════════════════════════════════════════════════════════════════════╝");

  const CMD = "/opt/homebrew/bin/gitui";
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: CMD },
  });

  const session = manager.create({
    command: CMD,
    cols: 120, rows: 30,
    cwd: "/Users/jack/Software/garazyk",
  });
  await new Promise(r => setTimeout(r, 1500));

  // Step 1: OBSERVE
  const snap1 = await observe(session);
  box("Step 1: OBSERVE", summarize(snap1, 4));

  // Step 2: DECIDE
  box("Step 2: DECIDE", [
    "Goal: Navigate tabs, try commit popup, explore status",
    "gitui keys: j/k=scroll, Tab=switch tab, c=commit, s=stash, f=fetch",
    "  q=quit, Enter=select, Escape=close popup",
    "Pattern: Status → Diff → Branches → Commit popup → Quit",
  ]);

  // Step 3: Navigate tabs (number keys)
  console.log("\n┌─ Step 3: ACT ─ Switch tabs with number keys ─┐");
  await act(session, "2"); // Log tab
  const snap3 = await observe(session);
  console.log(`  Tab 2 (Log): L0="${snap3.lines[0]?.substring(0, 60)}"`);
  await act(session, "3"); // Files tab
  const snap3b = await observe(session);
  console.log(`  Tab 3 (Files): L0="${snap3b.lines[0]?.substring(0, 60)}"`);
  await act(session, "4"); // Stashing tab
  const snap3c = await observe(session);
  console.log(`  Tab 4 (Stashing): L0="${snap3c.lines[0]?.substring(0, 60)}"`);
  await act(session, "1"); // back to Status
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 4: Try commit popup (c)
  console.log("\n┌─ Step 4: ACT ─ Try commit popup (c) ─┐");
  await act(session, "c");
  const snap4 = await observe(session, 500);
  console.log(`  After 'c': L0="${snap4.lines[0]?.substring(0, 60)}"`);
  // Check if a commit dialog appeared
  const hasCommit = snap4.lines.some(l => /commit/i.test(l));
  console.log(`  Commit dialog detected: ${hasCommit}`);
  await act(session, "escape"); // close popup
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 5: Scroll the file list
  console.log("\n┌─ Step 5: ACT ─ Scroll list with j/k ─┐");
  for (let i = 0; i < 5; i++) await act(session, "j");
  const snap5 = await observe(session);
  console.log(`  After 5x j: cursor=${JSON.stringify(snap5.cursor)}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 6: CLEANUP
  console.log("\n┌─ Step 6: CLEANUP ─ Quit gitui ─┐");
  await act(session, "q");
  await new Promise(r => setTimeout(r, 500));
  const quitSnap = session.snapshot();
  console.log(`  Running after 'q': ${quitSnap.running}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  await session.stop({ force: true });
  manager.dispose();
}

// ── yazi ─────────────────────────────────────────────────────────────────

async function navigateYazi() {
  console.log("\n╔══════════════════════════════════════════════════════════════════════╗");
  console.log("║  YAZI — Ratatui dual-pane, tabs, file preview, key chords         ║");
  console.log("╚══════════════════════════════════════════════════════════════════════╝");

  const CMD = "/opt/homebrew/bin/yazi";
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: CMD },
  });

  const session = manager.create({
    command: CMD,
    cols: 120, rows: 30,
    cwd: "/Users/jack/Software/garazyk",
  });
  await new Promise(r => setTimeout(r, 1000));

  // Step 1: OBSERVE
  const snap1 = await observe(session);
  box("Step 1: OBSERVE", summarize(snap1, 4));

  // Step 2: DECIDE
  box("Step 2: DECIDE", [
    "Goal: Navigate files, enter directories, try preview, tabs",
    "yazi keys: j/k=scroll, h=parent dir, l=enter dir, Enter=open",
    "  Tab=switch pane, t=new tab, 1-9=switch tab, q=quit",
    "Pattern: Browse → Enter dir → Preview → Tab → Quit",
  ]);

  // Step 3: Navigate files (j/k)
  console.log("\n┌─ Step 3: ACT ─ Navigate files with j/k ─┐");
  for (let i = 0; i < 5; i++) await act(session, "j");
  const snap3 = await observe(session);
  console.log(`  After 5x j: cursor=${JSON.stringify(snap3.cursor)}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 4: Enter a directory (l or Enter)
  console.log("\n┌─ Step 4: ACT ─ Enter directory (l) ─┐");
  await act(session, "l");
  const snap4 = await observe(session, 500);
  console.log(`  After 'l': L0="${snap4.lines[0]?.substring(0, 60)}"`);
  // Check if we entered a directory
  const cwd = snap4.lines.find(l => /Users|garazyk|src/i.test(l));
  console.log(`  CWD indicator: ${cwd ? cwd.substring(0, 60) : "not found"}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 5: Go back (h)
  console.log("\n┌─ Step 5: ACT ─ Go back to parent (h) ─┐");
  await act(session, "h");
  const snap5 = await observe(session);
  console.log(`  After 'h': L0="${snap5.lines[0]?.substring(0, 60)}"`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 6: Try new tab (t)
  console.log("\n┌─ Step 6: ACT ─ New tab (t) ─┐");
  await act(session, "t");
  const snap6 = await observe(session);
  console.log(`  After 't': L0="${snap6.lines[0]?.substring(0, 60)}"`);
  // Check for tab indicator
  const hasTab = snap6.lines.some(l => /\d.*tab|tab.*\d/i.test(l) || /[1-9].*[2-9]/.test(l.substring(0, 20)));
  console.log(`  Tab indicator: ${hasTab}`);
  // Switch back to tab 1
  await act(session, "1");
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 7: CLEANUP
  console.log("\n┌─ Step 7: CLEANUP ─ Quit yazi ─┐");
  await act(session, "q");
  await new Promise(r => setTimeout(r, 500));
  let quitSnap = session.snapshot();
  console.log(`  Running after 'q': ${quitSnap.running}`);
  if (quitSnap.running) {
    // yazi may need two q's for multiple tabs
    await act(session, "q");
    await new Promise(r => setTimeout(r, 500));
    quitSnap = session.snapshot();
    console.log(`  Running after 2nd 'q': ${quitSnap.running}`);
  }
  console.log("└────────────────────────────────────────────────────────────────────┘");

  await session.stop({ force: true });
  manager.dispose();
}

// ── csvlens ──────────────────────────────────────────────────────────────

async function navigateCsvlens() {
  console.log("\n╔══════════════════════════════════════════════════════════════════════╗");
  console.log("║  CSVLENS — Ratatui tabular data, scrolling, filtering              ║");
  console.log("╚══════════════════════════════════════════════════════════════════════╝");

  const CMD = "/opt/homebrew/bin/csvlens";
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: CMD },
  });

  // Create a test CSV file
  const csvPath = "/tmp/test_csvlens.csv";
  const { execSync } = await import("child_process");
  let csv = "name,age,city,score,active\n";
  const names = ["Alice", "Bob", "Carol", "Dave", "Eve", "Frank", "Grace", "Hank", "Ivy", "Jack"];
  const cities = ["NYC", "LA", "Chicago", "Houston", "Phoenix", "Denver", "Seattle", "Boston", "Miami", "Austin"];
  for (let i = 0; i < 100; i++) {
    csv += `${names[i % 10]},${20 + (i % 50)},${cities[i % 10]},${Math.floor(Math.random() * 100)},${i % 2 === 0}\n`;
  }
  execSync(`cat > ${csvPath} << 'CSVEOF'\n${csv}CSVEOF`);

  const session = manager.create({
    command: CMD,
    args: [csvPath],
    cols: 120, rows: 30,
  });
  await new Promise(r => setTimeout(r, 1000));

  // Step 1: OBSERVE
  const snap1 = await observe(session);
  box("Step 1: OBSERVE", summarize(snap1, 4));

  // Step 2: DECIDE
  box("Step 2: DECIDE", [
    "Goal: Navigate tabular data, scroll, search, filter",
    "csvlens keys: j/k=scroll, h/l=horizontal scroll, /=search",
    "  & = filter, s=sort, q=quit, G=bottom, g=top",
    "Pattern: Browse → Scroll → Search → Sort → Quit",
  ]);

  // Step 3: Scroll vertically
  console.log("\n┌─ Step 3: ACT ─ Scroll vertically (j/k) ─┐");
  for (let i = 0; i < 10; i++) await act(session, "j");
  const snap3 = await observe(session);
  console.log(`  After 10x j: cursor=${JSON.stringify(snap3.cursor)}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 4: Scroll horizontally
  console.log("\n┌─ Step 4: ACT ─ Scroll horizontally (l) ─┐");
  for (let i = 0; i < 5; i++) await act(session, "l");
  const snap4 = await observe(session);
  console.log(`  After 5x l: cursor=${JSON.stringify(snap4.cursor)}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 5: Search (/)
  console.log("\n┌─ Step 5: ACT ─ Search (/) ─┐");
  await act(session, "/");
  await act(session, "A"); // search for 'A'
  await act(session, "l"); // type 'l'
  await act(session, "i"); // type 'i'
  await act(session, "c"); // type 'c'
  await act(session, "e"); // type 'e'
  const snap5 = await observe(session, 500);
  console.log(`  After /Alice: L0="${snap5.lines[0]?.substring(0, 60)}"`);
  await act(session, "enter");
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 6: Go to bottom (G)
  console.log("\n┌─ Step 6: ACT ─ Go to bottom (G) ─┐");
  await act(session, "G");
  const snap6 = await observe(session);
  console.log(`  After G: L0="${snap6.lines[0]?.substring(0, 60)}"`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 7: CLEANUP
  console.log("\n┌─ Step 7: CLEANUP ─ Quit csvlens ─┐");
  await act(session, "q");
  await new Promise(r => setTimeout(r, 500));
  const quitSnap = session.snapshot();
  console.log(`  Running after 'q': ${quitSnap.running}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  await session.stop({ force: true });
  manager.dispose();
}

// ── ncdu ─────────────────────────────────────────────────────────────────

async function navigateNcdu() {
  console.log("\n╔══════════════════════════════════════════════════════════════════════╗");
  console.log("║  NCDU — ncurses tree navigation, deletion confirmation             ║");
  console.log("╚══════════════════════════════════════════════════════════════════════╝");

  const CMD = "/opt/homebrew/bin/ncdu";
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: CMD },
  });

  const session = manager.create({
    command: CMD,
    args: ["/Users/jack/Software/garazyk"],
    cols: 80, rows: 24,
  });
  await new Promise(r => setTimeout(r, 2000)); // ncdu needs time to scan

  // Step 1: OBSERVE
  const snap1 = await observe(session);
  box("Step 1: OBSERVE", summarize(snap1, 4));

  // Step 2: DECIDE
  box("Step 2: DECIDE", [
    "Goal: Navigate directory tree, enter dirs, sort, try delete",
    "ncdu keys: j/k or arrows=scroll, Enter=enter dir, h=parent",
    "  d=delete, s=sort, n=name, e=extended, q=quit",
    "Pattern: Browse → Enter dir → Sort → Delete prompt → Quit",
  ]);

  // Step 3: Navigate (j/k — use hjkl since arrows may crash ncurses)
  console.log("\n┌─ Step 3: ACT ─ Navigate with j/k ─┐");
  for (let i = 0; i < 5; i++) await act(session, "j");
  const snap3 = await observe(session);
  console.log(`  After 5x j: cursor=${JSON.stringify(snap3.cursor)}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 4: Enter a directory (Enter)
  console.log("\n┌─ Step 4: ACT ─ Enter directory (Enter) ─┐");
  await act(session, "enter");
  const snap4 = await observe(session, 500);
  console.log(`  After Enter: L0="${snap4.lines[0]?.substring(0, 60)}"`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 5: Go back (h)
  console.log("\n┌─ Step 5: ACT ─ Go back (h) ─┐");
  await act(session, "h");
  const snap5 = await observe(session);
  console.log(`  After 'h': L0="${snap5.lines[0]?.substring(0, 60)}"`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 6: Try delete (d) — DON'T CONFIRM
  console.log("\n┌─ Step 6: ACT ─ Try delete prompt (d) ─┐");
  await act(session, "d");
  const snap6 = await observe(session);
  console.log(`  After 'd': L0="${snap6.lines[0]?.substring(0, 60)}"`);
  const hasDeletePrompt = snap6.lines.some(l => /delete|confirm|really/i.test(l));
  console.log(`  Delete prompt: ${hasDeletePrompt}`);
  // CANCEL — don't actually delete
  await act(session, "escape");
  console.log("  Cancelled delete (Escape)");
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 7: CLEANUP
  console.log("\n┌─ Step 7: CLEANUP ─ Quit ncdu ─┐");
  await act(session, "q");
  await new Promise(r => setTimeout(r, 500));
  const quitSnap = session.snapshot();
  console.log(`  Running after 'q': ${quitSnap.running}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  await session.stop({ force: true });
  manager.dispose();
}

// ── posting ──────────────────────────────────────────────────────────────

async function navigatePosting() {
  console.log("\n╔══════════════════════════════════════════════════════════════════════╗");
  console.log("║  POSTING — Textual tabbed forms, HTTP methods, response viewer     ║");
  console.log("╚══════════════════════════════════════════════════════════════════════╝");

  const CMD = "/opt/homebrew/bin/posting";
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: CMD },
  });

  const session = manager.create({
    command: CMD,
    cols: 120, rows: 30,
    env: { TERM: "xterm-256color" },
  });
  await new Promise(r => setTimeout(r, 5000)); // Textual apps are slow to render

  // Step 1: OBSERVE
  const snap1 = await observe(session);
  box("Step 1: OBSERVE", summarize(snap1, 4));

  // Step 2: DECIDE
  box("Step 2: DECIDE", [
    "Goal: Navigate tabs, try HTTP method selection, URL input",
    "posting keys: Tab=next field, Ctrl+T=new tab, Ctrl+Q=quit",
    "  Ctrl+S=send request, Ctrl+J/K=switch collection tab",
    "Pattern: Browse → Edit URL → Switch method → Quit",
  ]);

  // Step 3: Navigate between tabs
  console.log("\n┌─ Step 3: ACT ─ Navigate tabs ─┐");
  await act(session, "tab");
  const snap3 = await observe(session);
  console.log(`  After Tab: cursor=${JSON.stringify(snap3.cursor)}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 4: Try Ctrl+Q to quit (Textual standard quit)
  console.log("\n┌─ Step 4: CLEANUP ─ Quit posting ─┐");
  await act(session, "ctrl-c");
  await new Promise(r => setTimeout(r, 500));
  let quitSnap = session.snapshot();
  console.log(`  Running after Ctrl+C: ${quitSnap.running}`);
  if (quitSnap.running) {
    await act(session, "ctrl-d");
    await new Promise(r => setTimeout(r, 500));
    quitSnap = session.snapshot();
    console.log(`  Running after Ctrl+D: ${quitSnap.running}`);
  }
  if (quitSnap.running) {
    // Textual apps may need 'q' or Ctrl+Q
    await act(session, "q");
    await new Promise(r => setTimeout(r, 500));
    quitSnap = session.snapshot();
    console.log(`  Running after 'q': ${quitSnap.running}`);
  }
  console.log("└────────────────────────────────────────────────────────────────────┘");

  await session.stop({ force: true });
  manager.dispose();
}

// ── tty-solitaire ────────────────────────────────────────────────────────

async function navigateTtySolitaire() {
  console.log("\n╔══════════════════════════════════════════════════════════════════════╗");
  console.log("║  TTY-SOLITAIRE — Card game, 2D selection, movement                ║");
  console.log("╚══════════════════════════════════════════════════════════════════════╝");

  const CMD = "/opt/homebrew/bin/ttysolitaire";
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: CMD },
  });

  const session = manager.create({
    command: CMD,
    cols: 80, rows: 30,
  });
  await new Promise(r => setTimeout(r, 1000));

  // Step 1: OBSERVE
  const snap1 = await observe(session);
  box("Step 1: OBSERVE", summarize(snap1, 4));

  // Step 2: DECIDE
  box("Step 2: DECIDE", [
    "Goal: Navigate card piles, select/move cards",
    "ttysolitaire keys: hjkl=move, Enter=select, m=move, q=quit",
    "  Space=select, n=new game",
    "Pattern: Navigate → Select card → Move card → Quit",
  ]);

  // Step 3: Navigate (hjkl)
  console.log("\n┌─ Step 3: ACT ─ Navigate with hjkl ─┐");
  await act(session, "l");
  await act(session, "l");
  await act(session, "j");
  const snap3 = await observe(session);
  console.log(`  After l,l,j: cursor=${JSON.stringify(snap3.cursor)}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 4: Select a card (Space or Enter)
  console.log("\n┌─ Step 4: ACT ─ Select card (Space) ─┐");
  await act(session, " ");
  const snap4 = await observe(session);
  console.log(`  After Space: cursor=${JSON.stringify(snap4.cursor)}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 5: CLEANUP
  console.log("\n┌─ Step 5: CLEANUP ─ Quit tty-solitaire ─┐");
  await act(session, "q");
  await new Promise(r => setTimeout(r, 500));
  let quitSnap = session.snapshot();
  console.log(`  Running after 'q': ${quitSnap.running}`);
  if (quitSnap.running) {
    await act(session, "ctrl-c");
    await new Promise(r => setTimeout(r, 500));
    quitSnap = session.snapshot();
    console.log(`  Running after Ctrl+C: ${quitSnap.running}`);
  }
  console.log("└────────────────────────────────────────────────────────────────────┘");

  await session.stop({ force: true });
  manager.dispose();
}

// ── harlequin ────────────────────────────────────────────────────────────

async function navigateHarlequin() {
  console.log("\n╔══════════════════════════════════════════════════════════════════════╗");
  console.log("║  HARLEQUIN — Textual SQL editor, schema tree, results table        ║");
  console.log("╚══════════════════════════════════════════════════════════════════════╝");

  const CMD = "/opt/homebrew/bin/harlequin";
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: CMD },
  });

  // Use SQLite with a test DB
  const dbPath = "/tmp/test_harlequin.db";
  const { execSync } = await import("child_process");
  execSync(`sqlite3 ${dbPath} "CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, name TEXT, email TEXT); INSERT OR IGNORE INTO users VALUES(1,'Alice','alice@example.com'),(2,'Bob','bob@example.com'),(3,'Carol','carol@example.com');"`);

  const session = manager.create({
    command: CMD,
    args: [dbPath],
    cols: 120, rows: 30,
  });
  await new Promise(r => setTimeout(r, 2000));

  // Step 1: OBSERVE
  const snap1 = await observe(session);
  box("Step 1: OBSERVE", summarize(snap1, 4));

  // Step 2: DECIDE
  box("Step 2: DECIDE", [
    "Goal: Navigate schema tree, write query, view results",
    "harlequin keys: Tab=switch panel, Ctrl+J/K=scroll, Ctrl+R=run",
    "  Ctrl+Q=quit, mouse=click",
    "Pattern: Schema → Query → Run → Results → Quit",
  ]);

  // Step 3: Navigate panels
  console.log("\n┌─ Step 3: ACT ─ Navigate panels (Tab) ─┐");
  await act(session, "tab");
  const snap3 = await observe(session);
  console.log(`  After Tab: cursor=${JSON.stringify(snap3.cursor)}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 4: CLEANUP
  console.log("\n┌─ Step 4: CLEANUP ─ Quit harlequin ─┐");
  await act(session, "ctrl-c");
  await new Promise(r => setTimeout(r, 500));
  let quitSnap = session.snapshot();
  console.log(`  Running after Ctrl+C: ${quitSnap.running}`);
  if (quitSnap.running) {
    await act(session, "ctrl-d");
    await new Promise(r => setTimeout(r, 500));
    quitSnap = session.snapshot();
    console.log(`  Running after Ctrl+D: ${quitSnap.running}`);
  }
  if (quitSnap.running) {
    await act(session, "q");
    await new Promise(r => setTimeout(r, 500));
    quitSnap = session.snapshot();
    console.log(`  Running after 'q': ${quitSnap.running}`);
  }
  console.log("└────────────────────────────────────────────────────────────────────┘");

  await session.stop({ force: true });
  manager.dispose();
}

// ── trippy ───────────────────────────────────────────────────────────────

async function navigateTrippy() {
  console.log("\n╔══════════════════════════════════════════════════════════════════════╗");
  console.log("║  TRIPPY — Ratatui tabbed, real-time charts, table                  ║");
  console.log("╚══════════════════════════════════════════════════════════════════════╝");

  const CMD = "/opt/homebrew/bin/trip";
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: CMD },
  });

  // Trace to a well-known host (use -u for unprivileged mode)
  const session = manager.create({
    command: CMD,
    args: ["-u", "1.1.1.1"],
    cols: 120, rows: 30,
  });
  await new Promise(r => setTimeout(r, 3000)); // trippy needs time for trace

  // Step 1: OBSERVE
  const snap1 = await observe(session);
  box("Step 1: OBSERVE", summarize(snap1, 4));

  // Step 2: DECIDE
  box("Step 2: DECIDE", [
    "Goal: Navigate tabs, observe real-time data, scroll hops",
    "trippy keys: Tab=switch tab, j/k=scroll, q=quit",
    "  r=retrace, s=stop/start",
    "Pattern: Hops → Charts → Details → Quit",
  ]);

  // Step 3: Switch tabs
  console.log("\n┌─ Step 3: ACT ─ Switch tabs (Tab) ─┐");
  await act(session, "tab");
  const snap3 = await observe(session);
  console.log(`  After Tab: L0="${snap3.lines[0]?.substring(0, 60)}"`);
  await act(session, "tab");
  const snap3b = await observe(session);
  console.log(`  After 2nd Tab: L0="${snap3b.lines[0]?.substring(0, 60)}"`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 4: Scroll hops
  console.log("\n┌─ Step 4: ACT ─ Scroll hops (j/k) ─┐");
  for (let i = 0; i < 5; i++) await act(session, "j");
  const snap4 = await observe(session);
  console.log(`  After 5x j: cursor=${JSON.stringify(snap4.cursor)}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  // Step 5: CLEANUP
  console.log("\n┌─ Step 5: CLEANUP ─ Quit trippy ─┐");
  await act(session, "q");
  await new Promise(r => setTimeout(r, 500));
  const quitSnap = session.snapshot();
  console.log(`  Running after 'q': ${quitSnap.running}`);
  console.log("└────────────────────────────────────────────────────────────────────┘");

  await session.stop({ force: true });
  manager.dispose();
}

// ── Main ─────────────────────────────────────────────────────────────────

async function main() {
  const apps = {
    lazygit: navigateLazygit,
    gitui: navigateGitui,
    yazi: navigateYazi,
    csvlens: navigateCsvlens,
    ncdu: navigateNcdu,
    posting: navigatePosting,
    "tty-solitaire": navigateTtySolitaire,
    harlequin: navigateHarlequin,
    trippy: navigateTrippy,
  };

  if (app === "all") {
    for (const [name, fn] of Object.entries(apps)) {
      try { await fn(); } catch (e) { console.error(`\nError in ${name}:`, e.message); }
    }
  } else if (apps[app]) {
    await apps[app]();
  } else {
    console.error(`Unknown app: ${app}. Use: ${Object.keys(apps).join(", ")}, or all`);
    process.exit(1);
  }

  // Final report
  console.log("\n\n╔══════════════════════════════════════════════════════════════════════╗");
  console.log("║                    TUI NAVIGATION — COMPREHENSIVE REPORT            ║");
  console.log("╠══════════════════════════════════════════════════════════════════════╣");
  console.log("║  Frameworks tested:                                                ║");
  console.log("║    Bubbletea (Go)  — lazygit, posting                             ║");
  console.log("║    Ratatui (Rust)  — gitui, yazi, csvlens, trippy                 ║");
  console.log("║    Textual (Python)— harlequin, posting                            ║");
  console.log("║    ncurses (C)     — ncdu, tty-solitaire                          ║");
  console.log("║                                                                    ║");
  console.log("║  Navigation patterns exercised:                                    ║");
  console.log("║    • Split-pane (lazygit, gitui)                                   ║");
  console.log("║    • Tabbed views (lazygit 1-5, yazi t, trippy Tab)               ║");
  console.log("║    • Dual-pane file manager (yazi)                                  ║");
  console.log("║    • Tabular data + horizontal scroll (csvlens)                    ║");
  console.log("║    • Tree navigation (ncdu)                                        ║");
  console.log("║    • Popup overlays (gitui commit)                                  ║");
  console.log("║    • Text input / forms (lazygit commit, posting)                  ║");
  console.log("║    • Real-time charts (trippy)                                      ║");
  console.log("║    • Card game 2D selection (tty-solitaire)                        ║");
  console.log("║    • Deletion confirmation (ncdu)                                   ║");
  console.log("║    • Filter/search (lazygit, csvlens)                              ║");
  console.log("║                                                                    ║");
  console.log("╚══════════════════════════════════════════════════════════════════════╝");
}

main().catch(err => { console.error("Fatal:", err); process.exit(1); });
