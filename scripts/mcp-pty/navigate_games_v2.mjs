#!/usr/bin/env node
/**
 * Navigate TUI games (fixed version) using the observe-decide-act-verify loop.
 * Fixes: nudoku key handling, nethack character creation, greed quit.
 */

import { TerminalSessionManager } from "./terminal_session.mjs";

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
  const w = 62;
  console.log(`\n┌─ ${title} ${"─".repeat(Math.max(0, w - title.length - 3))}┐`);
  for (const l of lines) console.log(`  ${l}`);
  console.log("└" + "─".repeat(w + 1) + "┘");
}

// ── nudoku ───────────────────────────────────────────────────────────────

async function navigateNudoku() {
  console.log("\n╔══════════════════════════════════════════════════════════════╗");
  console.log("║  NUDOKU — Menu-driven TUI game (fixed)                      ║");
  console.log("╚══════════════════════════════════════════════════════════════╝");

  const NUDOKU = "/opt/homebrew/bin/nudoku";
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: NUDOKU },
  });

  const session = await manager.create({ command: NUDOKU, cols: 80, rows: 24 });
  await new Promise(r => setTimeout(r, 1000));

  // Step 1: OBSERVE
  const snap1 = await observe(session);
  const sem1 = await observeSemantic(session);

  box("Step 1: OBSERVE", [
    `Running: ${snap1.running}  Cursor: ${JSON.stringify(snap1.cursor)}`,
    `Semantic app: ${sem1.snapshot.app} (conf: ${sem1.snapshot.confidence})`,
    `Semantic VDOM:`,
    sem1.snapshot.vdomViz,
    `Grid area (L3-5):`,
    ...snap1.lines.slice(3, 6).map((l, i) => `  L${3+i}: ${l.substring(0, 65)}`),
    `Status area (L20-23):`,
    ...snap1.lines.slice(20, 24).map((l, i) => `  L${20+i}: ${l.substring(0, 65)}`),
  ]);

  // Step 2: DECIDE
  box("Step 2: DECIDE", [
    "Goal: Navigate grid, place numbers, use features, quit",
    "nudoku keys: hjkl or arrows = move, 1-9 = place, x = delete",
    "  u = undo, H = hint, N = new game, q = quit",
    "nudoku starts directly with a puzzle — no menu needed",
  ]);

  // Step 3: Navigate grid with arrow keys
  console.log("\n┌─ Step 3: ACT ─ Navigate grid with arrow keys ─┐");
  const cursorBefore = { ...snap1.cursor };
  await act(session, "right");
  await act(session, "right");
  await act(session, "down");
  await act(session, "down");
  const snap3 = await observe(session);
  console.log(`  Cursor before: ${JSON.stringify(cursorBefore)}`);
  console.log(`  Cursor after: ${JSON.stringify(snap3.cursor)}`);
  console.log("└────────────────────────────────────────────────────────┘");

  // Step 4: Place a number
  console.log("\n┌─ Step 4: ACT ─ Place number 7 ─┐");
  await act(session, "7");
  const snap4 = await observe(session);
  // Check if the number appeared near the cursor
  const cursorLine = snap4.lines[snap4.cursor.y] || "";
  console.log(`  Cursor line: ${cursorLine.substring(0, 65)}`);
  console.log(`  '7' near cursor: ${cursorLine.includes("7")}`);
  console.log("└────────────────────────────────────────────────────────┘");

  // Step 5: Delete the number
  console.log("\n┌─ Step 5: ACT ─ Delete number (x) ─┐");
  await act(session, "x");
  const snap5 = await observe(session);
  const cursorLine5 = snap5.lines[snap5.cursor.y] || "";
  console.log(`  Cursor line: ${cursorLine5.substring(0, 65)}`);
  console.log("└────────────────────────────────────────────────────────┘");

  // Step 6: Undo
  console.log("\n┌─ Step 6: ACT ─ Undo (u) ─┐");
  await act(session, "u");
  const snap6 = await observe(session);
  console.log(`  After undo: cursor line = ${snap6.lines[snap6.cursor.y]?.substring(0, 65)}`);
  console.log("└────────────────────────────────────────────────────────┘");

  // Step 7: Try new game (N — uppercase)
  console.log("\n┌─ Step 7: ACT ─ New game (N) ─┐");
  await act(session, "N");
  const snap7 = await observe(session, 500);
  console.log(`  After 'N':`);
  console.log(`  Last 3 lines:`);
  for (let i = Math.max(0, snap7.lines.length - 3); i < snap7.lines.length; i++) {
    console.log(`  L${i}: ${snap7.lines[i]?.substring(0, 65)}`);
  }
  // Check if a difficulty prompt appeared
  const hasDiffPrompt = snap7.lines.some(l => /difficulty/i.test(l) || /easy.*normal.*hard/i.test(l));
  console.log(`  Difficulty prompt: ${hasDiffPrompt}`);
  if (hasDiffPrompt) {
    console.log("  Selecting easy (press 'e' or Enter for default)...");
    await act(session, "enter");
    await new Promise(r => setTimeout(r, 500));
    const snap7b = await observe(session);
    console.log(`  After selection: running=${snap7b.running}`);
  }
  console.log("└────────────────────────────────────────────────────────┘");

  // Step 8: CLEANUP — Quit
  console.log("\n┌─ Step 8: CLEANUP ─ Quit nudoku ─┐");
  if (session.running) {
    await act(session, "q");
    await new Promise(r => setTimeout(r, 500));
    const quitSnap = session.snapshot();
    console.log(`  Running after 'q': ${quitSnap.running}`);
    if (quitSnap.running) {
      await act(session, "ctrl-c");
      await new Promise(r => setTimeout(r, 500));
    }
  }
  console.log("└────────────────────────────────────────────────────────┘");

  await session.stop({ force: true });
  manager.dispose();
}

// ── nethack ──────────────────────────────────────────────────────────────

async function navigateNethack() {
  console.log("\n╔══════════════════════════════════════════════════════════════╗");
  console.log("║  NETHACK — Deeply modal roguelike (fixed)                   ║");
  console.log("╚══════════════════════════════════════════════════════════════╝");

  const NETHACK = "/opt/homebrew/bin/nethack";
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: NETHACK },
  });

  const session = await manager.create({ command: NETHACK, cols: 80, rows: 24 });
  await new Promise(r => setTimeout(r, 2000));

  // Step 1: OBSERVE
  const snap1 = await observe(session);

  box("Step 1: OBSERVE", [
    `Running: ${snap1.running}  Cursor: ${JSON.stringify(snap1.cursor)}`,
    `First 3 lines:`,
    ...snap1.lines.slice(0, 3).map((l, i) => `  L${i}: ${l.substring(0, 65)}`),
    `Last 3 lines:`,
    ...snap1.lines.slice(-3).map((l, i) => `  L${snap1.lines.length - 3 + i}: ${l.substring(0, 65)}`),
  ]);

  // Step 2: DECIDE
  box("Step 2: DECIDE", [
    "Goal: Handle character creation carefully, then explore",
    "NetHack character creation: role → race → gender → alignment",
    "Each prompt needs a specific response, not just Enter",
    "Strategy: Read each prompt, respond with appropriate key",
  ]);

  // Step 3: Handle character creation step by step
  console.log("\n┌─ Step 3: ACT ─ Character creation ─┐");

  // Check current prompt
  let snap = await observe(session);
  let promptLine = snap.lines[0] || "";
  console.log(`  Current prompt: "${promptLine.substring(0, 65)}"`);

  // If "Shall I pick..." prompt, press 'y' to pick manually
  if (/shall i/i.test(promptLine)) {
    console.log("  Pressing 'y' to pick manually...");
    await act(session, "y");
    await new Promise(r => setTimeout(r, 500));
    snap = await observe(session);
    promptLine = snap.lines[0] || "";
    console.log(`  After 'y': "${promptLine.substring(0, 65)}"`);
  }

  // Now we should see role selection
  // Press 'b' for Barbarian (or just Enter for default)
  if (/role/i.test(promptLine) || /pick.*character/i.test(promptLine) || /warrior|barbarian|caveman|healer/i.test(promptLine)) {
    console.log("  Role selection detected, pressing Enter for default...");
    await act(session, "enter");
    await new Promise(r => setTimeout(r, 500));
    snap = await observe(session);
    promptLine = snap.lines[0] || "";
    console.log(`  After role: "${promptLine.substring(0, 65)}"`);
  }

  // Race selection
  if (/race/i.test(promptLine) || /human|elf|dwarf|gnome|orc/i.test(promptLine)) {
    console.log("  Race selection detected, pressing Enter for default...");
    await act(session, "enter");
    await new Promise(r => setTimeout(r, 500));
    snap = await observe(session);
    promptLine = snap.lines[0] || "";
    console.log(`  After race: "${promptLine.substring(0, 65)}"`);
  }

  // Gender selection
  if (/gender/i.test(promptLine) || /male|female/i.test(promptLine)) {
    console.log("  Gender selection detected, pressing Enter for default...");
    await act(session, "enter");
    await new Promise(r => setTimeout(r, 500));
    snap = await observe(session);
    promptLine = snap.lines[0] || "";
    console.log(`  After gender: "${promptLine.substring(0, 65)}"`);
  }

  // Alignment selection
  if (/align/i.test(promptLine) || /lawful|neutral|chaotic/i.test(promptLine)) {
    console.log("  Alignment selection detected, pressing Enter for default...");
    await act(session, "enter");
    await new Promise(r => setTimeout(r, 500));
    snap = await observe(session);
    promptLine = snap.lines[0] || "";
    console.log(`  After alignment: "${promptLine.substring(0, 65)}"`);
  }

  // Confirmation
  if (/is this ok/i.test(promptLine) || /\[ynq\]/i.test(promptLine)) {
    console.log("  Confirmation detected, pressing 'y'...");
    await act(session, "y");
    await new Promise(r => setTimeout(r, 1000));
    snap = await observe(session);
    console.log(`  After confirmation: running=${snap.running}`);
  }

  // Step 4: VERIFY — Check if we're in the game
  console.log("\n┌─ Step 4: VERIFY ─ Check game state ─┐");
  snap = await observe(session);
  const hasDungeon = snap.lines.some(l => /dungeon/i.test(l) || /[.|#|@|<|>]/.test(l));
  const hasMessageLine = snap.lines.some(l => /--.*--/.test(l) || /more/i.test(l));
  const bottomLine = snap.lines[snap.lines.length - 2] || "";
  const statusLine = snap.lines[snap.lines.length - 1] || "";
  console.log(`  Dungeon elements: ${hasDungeon}`);
  console.log(`  Status line: "${statusLine.substring(0, 65)}"`);
  console.log(`  Bottom-2: "${bottomLine.substring(0, 65)}"`);
  console.log("└────────────────────────────────────────────────────────┘");

  // Step 5: Move around
  console.log("\n┌─ Step 5: ACT ─ Move with hjkl ─┐");
  await act(session, "j");
  await act(session, "j");
  await act(session, "l");
  await act(session, "l");
  await act(session, "k"); // back up
  const snap5 = await observe(session);
  console.log(`  After j,j,l,l,k:`);
  console.log(`  Status line: "${snap5.lines[snap5.lines.length - 1]?.substring(0, 65)}"`);
  console.log("└────────────────────────────────────────────────────────┘");

  // Step 6: Open inventory
  console.log("\n┌─ Step 6: ACT ─ Open inventory (i) ─┐");
  await act(session, "i");
  const snap6 = await observe(session);
  console.log(`  After 'i':`);
  console.log(`  First line: ${snap6.lines[0]?.substring(0, 65)}`);
  console.log(`  Status line: "${snap6.lines[snap6.lines.length - 1]?.substring(0, 65)}"`);
  const hasInventory = snap6.lines.some(l => /inventory/i.test(l) || /weapon/i.test(l) || /armor/i.test(l) || /--/i.test(l.substring(0, 10)));
  console.log(`  Inventory detected: ${hasInventory}`);
  console.log("└────────────────────────────────────────────────────────┘");

  // Step 7: Close inventory
  console.log("\n┌─ Step 7: ACT ─ Close inventory ─┐");
  // NetHack uses space or Enter to close inventory
  await act(session, " ");
  const snap7 = await observe(session);
  console.log(`  After space: running=${snap7.running}`);
  console.log(`  Status line: "${snap7.lines[snap7.lines.length - 1]?.substring(0, 65)}"`);
  console.log("└────────────────────────────────────────────────────────┘");

  // Step 8: Try to look at something
  console.log("\n┌─ Step 8: ACT ─ Look around (;) ─┐");
  await act(session, ";");
  const snap8 = await observe(session);
  console.log(`  After ';':`);
  console.log(`  First line: ${snap8.lines[0]?.substring(0, 65)}`);
  console.log(`  Status line: "${snap8.lines[snap8.lines.length - 1]?.substring(0, 65)}"`);
  await act(session, "escape"); // Cancel look
  console.log("└────────────────────────────────────────────────────────┘");

  // Step 9: CLEANUP — Quit NetHack
  console.log("\n┌─ Step 9: CLEANUP ─ Quit nethack ─┐");
  // NetHack quit: type "#quit" then Enter, then confirm with 'y' twice
  await act(session, "escape"); // Ensure we're in normal mode
  await session.type("#quit");
  await act(session, "enter");
  await new Promise(r => setTimeout(r, 500));
  snap = await observe(session);
  console.log(`  After #quit: "${snap.lines[snap.lines.length - 1]?.substring(0, 65)}"`);

  // Confirm quit (may need multiple y's)
  for (let attempt = 0; attempt < 4; attempt++) {
    if (!session.running) break;
    snap = await observe(session);
    const lastLine = snap.lines[snap.lines.length - 1] || "";
    if (/really/i.test(lastLine) || /confirm/i.test(lastLine) || /\[yn\]/i.test(lastLine)) {
      console.log(`  Confirm: "${lastLine.substring(0, 65)}"`);
      await act(session, "y");
      await new Promise(r => setTimeout(r, 500));
    } else break;
  }

  await new Promise(r => setTimeout(r, 1000));
  const quitSnap = session.snapshot();
  console.log(`  Running: ${quitSnap.running}`);
  if (quitSnap.running) {
    console.log("  Force stopping...");
    await session.stop({ force: true });
  }
  console.log("└────────────────────────────────────────────────────────┘");

  await session.stop({ force: true });
  manager.dispose();
}

// ── greed ────────────────────────────────────────────────────────────────

async function navigateGreed() {
  console.log("\n╔══════════════════════════════════════════════════════════════╗");
  console.log("║  GREED — Simple movement TUI game (fixed)                    ║");
  console.log("╚══════════════════════════════════════════════════════════════╝");

  const GREED = "/opt/homebrew/bin/greed";
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: GREED },
  });

  const session = await manager.create({ command: GREED, cols: 80, rows: 24 });
  await new Promise(r => setTimeout(r, 1000));

  // Step 1: OBSERVE
  const snap1 = await observe(session);
  const sem1 = await observeSemantic(session);

  box("Step 1: OBSERVE", [
    `Running: ${snap1.running}  Cursor: ${JSON.stringify(snap1.cursor)}`,
    `Semantic app: ${sem1.snapshot.app} (conf: ${sem1.snapshot.confidence})`,
    `Semantic VDOM:`,
    sem1.snapshot.vdomViz,
    `Grid area (L0-2):`,
    ...snap1.lines.slice(0, 3).map((l, i) => `  L${i}: ${l.substring(0, 65)}`),
    `Status line (L23):`,
    `  L23: ${snap1.lines[23]?.substring(0, 65)}`,
  ]);

  // Step 2: DECIDE
  box("Step 2: DECIDE", [
    "Goal: Navigate grid, make moves, observe score changes",
    "Arrow keys or hjkl to move, number = jump distance",
    "q = quit, p = toggle highlights, Ctrl-L = redraw",
    "Pattern: Move → Observe score → Move → Quit",
  ]);

  // Step 3: Move and track score
  console.log("\n┌─ Step 3: ACT ─ Move and track score ─┐");
  const scoreBefore = snap1.lines[23]?.match(/Score:\s*(\d+)/)?.[1] || "0";
  console.log(`  Score before: ${scoreBefore}`);

  await act(session, "right");
  const snap3a = await observe(session);
  const scoreAfter1 = snap3a.lines[23]?.match(/Score:\s*(\d+)/)?.[1] || "?";
  console.log(`  After right: Score = ${scoreAfter1}`);

  await act(session, "down");
  const snap3b = await observe(session);
  const scoreAfter2 = snap3b.lines[23]?.match(/Score:\s*(\d+)/)?.[1] || "?";
  console.log(`  After down: Score = ${scoreAfter2}`);

  await act(session, "left");
  const snap3c = await observe(session);
  const scoreAfter3 = snap3c.lines[23]?.match(/Score:\s*(\d+)/)?.[1] || "?";
  console.log(`  After left: Score = ${scoreAfter3}`);

  // Step 4: Toggle highlights
  console.log("\n┌─ Step 4: ACT ─ Toggle highlights (p) ─┐");
  await act(session, "p");
  const snap4 = await observe(session);
  console.log(`  After 'p': running=${snap4.running}`);
  console.log(`  Status: ${snap4.lines[23]?.substring(0, 65)}`);
  console.log("└────────────────────────────────────────────────────────┘");

  // Step 5: More moves
  console.log("\n┌─ Step 5: ACT ─ More moves ─┐");
  for (const dir of ["up", "right", "right", "down", "down"]) {
    await act(session, dir);
    await new Promise(r => setTimeout(r, 100));
  }
  const snap5 = await observe(session);
  const finalScore = snap5.lines[23]?.match(/Score:\s*(\d+)/)?.[1] || "?";
  const percent = snap5.lines[23]?.match(/(\d+\.\d+)%/)?.[1] || "?";
  console.log(`  Final score: ${finalScore} (${percent}%)`);
  console.log("└────────────────────────────────────────────────────────┘");

  // Step 6: CLEANUP — Quit
  console.log("\n┌─ Step 6: CLEANUP ─ Quit greed ─┐");
  await act(session, "q");
  await new Promise(r => setTimeout(r, 500));
  let quitSnap = session.snapshot();
  console.log(`  Running after 'q': ${quitSnap.running}`);
  if (quitSnap.running) {
    // Greed might need a confirmation
    const lastLine = quitSnap.lines[quitSnap.lines.length - 1] || "";
    console.log(`  Last line: "${lastLine.substring(0, 65)}"`);
    await act(session, "y");
    await new Promise(r => setTimeout(r, 500));
    quitSnap = session.snapshot();
    console.log(`  Running after 'y': ${quitSnap.running}`);
  }
  if (quitSnap.running) {
    await act(session, "ctrl-c");
    await new Promise(r => setTimeout(r, 500));
    quitSnap = session.snapshot();
    console.log(`  Running after Ctrl+C: ${quitSnap.running}`);
  }
  console.log("└────────────────────────────────────────────────────────┘");

  await session.stop({ force: true });
  manager.dispose();
}

// ── Main ─────────────────────────────────────────────────────────────────

async function main() {
  const game = process.argv[2] || "all";
  const games = { nudoku: navigateNudoku, nethack: navigateNethack, greed: navigateGreed };

  if (game === "all") {
    for (const [name, fn] of Object.entries(games)) {
      try { await fn(); } catch (e) { console.error(`\nError in ${name}:`, e.message); }
    }
  } else if (games[game]) {
    await games[game]();
  } else {
    console.error(`Unknown game: ${game}. Use: nudoku, nethack, greed, or all`);
    process.exit(1);
  }

  console.log("\n\n╔══════════════════════════════════════════════════════════════╗");
  console.log("║                    TUI GAME NAVIGATION — FINAL REPORT        ║");
  console.log("╠══════════════════════════════════════════════════════════════╣");
  console.log("║                                                              ║");
  console.log("║  GAMES TESTED (across both runs)                             ║");
  console.log("║    nudoku  — Grid navigation, number input, new game dialog  ║");
  console.log("║    nsnake  — Real-time, menu, direction changes, clean quit ║");
  console.log("║    nethack — Multi-step character creation, modal depth      ║");
  console.log("║    greed   — Grid movement, score tracking, highlights       ║");
  console.log("║                                                              ║");
  console.log("║  KEY FINDINGS                                                ║");
  console.log("║    1. Semantic extractor returns 'unknown' for all games     ║");
  console.log("║       — guessApplication only checks command name            ║");
  console.log("║    2. Games need app-specific parsing (like btop)            ║");
  console.log("║    3. Multi-step dialogs (nethack) need careful handling      ║");
  console.log("║    4. Real-time games (nsnake) work with PTY settle          ║");
  console.log("║    5. Score/status lines are the most parseable part          ║");
  console.log("║    6. Quit sequences vary: q, q+y, #quit+y+y, Ctrl+C        ║");
  console.log("║                                                              ║");
  console.log("╚══════════════════════════════════════════════════════════════╝");
}

main().catch(err => { console.error("Fatal:", err); process.exit(1); });
