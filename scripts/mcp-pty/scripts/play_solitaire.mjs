#!/usr/bin/env node
/**
 * AI-driven tty-solitaire player with beam search.
 *
 * Architecture:
 *   1. Screen parser — reads the terminal buffer to extract card positions
 *   2. Game model — represents Klondike state, generates legal moves
 *   3. Beam search — evaluates move sequences with heuristic scoring
 *   4. Move executor — translates best move to key presses
 *
 * Card rendering in tty-solitaire (60x30):
 *   Top row (y=1-5): Stock, Waste, gap, F0-F3
 *   Tableau (y=9+): 7 columns, face-up cards show rank+suit at left edge
 *   Face-down cards: ┌─────┐ / │     │ / └─────┘
 *   Stock asterisk at y=7
 *
 * Cursor moves in 8-column steps between stacks (cols 0-6).
 * h/l = left/right, j/k = down/up, space = select/deal/place
 * m = mark more cards, escape = cancel selection
 */
import { TerminalSessionManager } from "../terminal_session.mjs";
import { AsciicastRecorder } from "../recording.mjs";
import { buildAsciinemaOverlayHtml } from "../semantic_overlay_html.mjs";
import fs from "node:fs";
import path from "node:path";

// ── HTML player builder (delegates to the real overlay system) ──────────────

function buildPlayerHtml({ title }) {
  return buildAsciinemaOverlayHtml({
    title,
    castContent: "", // not used — we serve files via HTTP
    semanticOverlay: true,
    castFileName: "playback.cast",
    semanticFileName: "semantic-events.json",
  });
}

// ── Constants ──────────────────────────────────────────────────────────────

const COMMAND = "/opt/homebrew/bin/ttysolitaire";
const COLS = 60;
const ROWS = 30;
const OUTPUT_DIR = process.argv[2] || `/tmp/solitaire-capture`;

const SUITS = ["♠", "♣", "♥", "♦"];
const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];
const RED = new Set(["♥", "♦"]);
const BLACK = new Set(["♠", "♣"]);

function rankValue(r) { return RANKS.indexOf(r); }
function isRed(suit) { return RED.has(suit); }
function oppositeColor(s1, s2) { return isRed(s1) !== isRed(s2); }

// ── Card ──────────────────────────────────────────────────────────────────

class Card {
  constructor(rank, suit) {
    this.rank = rank; // "A".."K"
    this.suit = suit; // "♠"|"♣"|"♥"|"♦"
    this.faceUp = true;
  }
  get value() { return rankValue(this.rank); }
  get isRed() { return isRed(this.suit); }
  toString() { return this.rank + this.suit; }
}

// ── Game State ─────────────────────────────────────────────────────────────

class GameState {
  constructor() {
    this.stock = [];       // face-down cards in stock
    this.waste = [];       // face-up waste pile
    this.foundations = [[], [], [], []]; // 4 foundation piles
    this.tableau = [[], [], [], [], [], [], []]; // 7 tableau columns
    this.stockPasses = 0;  // how many times we've cycled through stock
  }

  clone() {
    const s = new GameState();
    s.stock = this.stock.map(c => { const cc = new Card(c.rank, c.suit); cc.faceUp = c.faceUp; return cc; });
    s.waste = this.waste.map(c => { const cc = new Card(c.rank, c.suit); cc.faceUp = c.faceUp; return cc; });
    s.foundations = this.foundations.map(f => f.map(c => { const cc = new Card(c.rank, c.suit); cc.faceUp = c.faceUp; return cc; }));
    s.tableau = this.tableau.map(t => t.map(c => { const cc = new Card(c.rank, c.suit); cc.faceUp = c.faceUp; return cc; }));
    s.stockPasses = this.stockPasses;
    return s;
  }

  /** Number of cards in foundations (score = how close to winning) */
  get foundationCount() {
    return this.foundations.reduce((sum, f) => sum + f.length, 0);
  }

  /** Number of face-down tableau cards */
  get faceDownCount() {
    return this.tableau.reduce((sum, col) => sum + col.filter(c => !c.faceUp).length, 0);
  }

  /** Check if a card can go on a foundation */
  canMoveToFoundation(card) {
    for (const f of this.foundations) {
      if (f.length === 0 && card.rank === "A") return this.foundations.indexOf(f);
      if (f.length > 0 && f[f.length - 1].suit === card.suit && card.value === f[f.length - 1].value + 1) {
        return this.foundations.indexOf(f);
      }
    }
    return -1;
  }

  /** Check if a card can be placed on a tableau column */
  canMoveToTableau(card, colIdx) {
    const col = this.tableau[colIdx];
    if (col.length === 0) return card.rank === "K"; // only Kings on empty
    const top = col[col.length - 1];
    return top.faceUp && oppositeColor(card.suit, top.suit) && card.value === top.value - 1;
  }

  /** Generate all legal moves as { type, from, to, card?, count? } */
  legalMoves() {
    const moves = [];

    // 1. Waste → foundation
    if (this.waste.length > 0) {
      const card = this.waste[this.waste.length - 1];
      const fi = this.canMoveToFoundation(card);
      if (fi >= 0) moves.push({ type: "waste_to_foundation", to: fi, card });
    }

    // 2. Tableau → foundation
    for (let t = 0; t < 7; t++) {
      const col = this.tableau[t];
      if (col.length === 0) continue;
      const top = col[col.length - 1];
      if (!top.faceUp) continue;
      const fi = this.canMoveToFoundation(top);
      if (fi >= 0) moves.push({ type: "tableau_to_foundation", from: t, to: fi, card: top });
    }

    // 3. Tableau → tableau (move sequences of same-suit descending cards)
    for (let src = 0; src < 7; src++) {
      const col = this.tableau[src];
      if (col.length === 0) continue;

      // Find the first face-up card index (can move from here down)
      let firstFaceUp = col.findIndex(c => c.faceUp);
      if (firstFaceUp < 0) continue;

      // Try moving different-length sequences from the bottom
      for (let startIdx = firstFaceUp; startIdx < col.length; startIdx++) {
        const movingCard = col[startIdx];
        const count = col.length - startIdx;

        for (let dst = 0; dst < 7; dst++) {
          if (dst === src) continue;
          if (this.canMoveToTableau(movingCard, dst)) {
            // Don't move a King from an empty-base column to another empty column
            if (movingCard.rank === "K" && startIdx === 0 && this.tableau[dst].length === 0) continue;
            moves.push({ type: "tableau_to_tableau", from: src, to: dst, card: movingCard, count });
          }
        }
      }
    }

    // 4. Waste → tableau
    if (this.waste.length > 0) {
      const card = this.waste[this.waste.length - 1];
      for (let t = 0; t < 7; t++) {
        if (this.canMoveToTableau(card, t)) {
          moves.push({ type: "waste_to_tableau", to: t, card });
        }
      }
    }

    // 5. Deal from stock
    if (this.stock.length > 0) {
      moves.push({ type: "deal_stock" });
    } else if (this.waste.length > 0 && this.stockPasses < 3) {
      moves.push({ type: "recycle_stock" });
    }

    return moves;
  }

  /** Apply a move, returning a new state */
  applyMove(move) {
    const s = this.clone();

    switch (move.type) {
      case "waste_to_foundation": {
        const card = s.waste.pop();
        s.foundations[move.to].push(card);
        break;
      }
      case "tableau_to_foundation": {
        const card = s.tableau[move.from].pop();
        s.foundations[move.to].push(card);
        s.flipTopCard(move.from);
        break;
      }
      case "tableau_to_tableau": {
        const cards = s.tableau[move.from].splice(-move.count);
        s.tableau[move.to].push(...cards);
        s.flipTopCard(move.from);
        break;
      }
      case "waste_to_tableau": {
        const card = s.waste.pop();
        s.tableau[move.to].push(card);
        break;
      }
      case "deal_stock": {
        // Move top card from stock to waste
        const card = s.stock.pop();
        card.faceUp = true;
        s.waste.push(card);
        break;
      }
      case "recycle_stock": {
        // Move waste back to stock (reversed)
        s.stock = s.waste.reverse().map(c => { c.faceUp = false; return c; });
        s.waste = [];
        s.stockPasses++;
        break;
      }
    }

    return s;
  }

  /** Flip the top card of a tableau column if it's face-down */
  flipTopCard(colIdx) {
    const col = this.tableau[colIdx];
    if (col.length > 0 && !col[col.length - 1].faceUp) {
      col[col.length - 1].faceUp = true;
    }
  }

  /** Is the game won? (all 52 cards in foundations) */
  get isWon() { return this.foundationCount === 52; }

  /** Is the game stuck? (no legal moves) */
  get isStuck() { return this.legalMoves().length === 0; }
}

// ── Heuristic Evaluation ──────────────────────────────────────────────────

function evaluate(state) {
  let score = 0;

  // Foundation progress (primary goal)
  score += state.foundationCount * 1000;

  // Expose face-down cards (secondary goal)
  score -= state.faceDownCount * 50;

  // Empty tableau columns (useful for Kings)
  score += state.tableau.filter(c => c.length === 0).length * 30;

  // Waste pile size (smaller is better — cards are in play)
  score -= state.waste.length * 5;

  // Stock remaining (fewer is better — cards are accessible)
  score -= state.stock.length * 3;

  // Bonus for long same-suit runs in tableau (easier to move)
  for (const col of state.tableau) {
    let runLen = 0;
    for (let i = col.length - 1; i > 0; i--) {
      if (col[i].faceUp && col[i - 1].faceUp &&
          oppositeColor(col[i].suit, col[i - 1].suit) &&
          col[i].value === col[i - 1].value - 1) {
        runLen++;
      } else break;
    }
    score += runLen * 15;
  }

  // Penalty for stock passes (diminishing returns)
  score -= state.stockPasses * 200;

  return score;
}

// ── Beam Search ────────────────────────────────────────────────────────────

/**
 * Beam search: explore the top-K move sequences up to depth D.
 * Unlike minimax/alpha-beta (for adversarial games), solitaire is
 * single-player, so we just maximize our own heuristic.
 *
 * Beam search is the right technique here because:
 * - The branching factor is ~10-30 moves per state
 * - We need to look several moves ahead to see the benefit of
 *   exposing face-down cards
 * - Full search is intractable (52! states)
 * - Beam keeps only the top-K states at each depth level
 */
function beamSearch(state, { beamWidth = 5, depth = 5 } = {}) {
  // Each beam entry: { state, moves, score }
  let beam = [{ state, moves: [], score: evaluate(state) }];

  for (let d = 0; d < depth; d++) {
    const candidates = [];

    for (const entry of beam) {
      const legalMoves = entry.state.legalMoves();

      // If won, return immediately
      if (entry.state.isWon) return entry.moves;

      // If stuck, this branch is dead
      if (legalMoves.length === 0) {
        candidates.push(entry);
        continue;
      }

      for (const move of legalMoves) {
        // Skip deal/recycle unless no other moves (prefer playing cards first)
        if ((move.type === "deal_stock" || move.type === "recycle_stock") && legalMoves.length > 1) continue;

        const newState = entry.state.applyMove(move);
        const newScore = evaluate(newState);
        candidates.push({
          state: newState,
          moves: [...entry.moves, move],
          score: newScore,
        });
      }
    }

    // Keep only top-K by score
    candidates.sort((a, b) => b.score - a.score);
    beam = candidates.slice(0, beamWidth);

    if (beam.length === 0) break;
  }

  // Return the best move sequence found
  return beam.length > 0 ? beam[0].moves : [];
}

// ── Screen Parser ──────────────────────────────────────────────────────────

/**
 * Parse the terminal buffer to build a GameState.
 *
 * Takes the lines array from session.snapshot().lines.
 *
 * Observed card rendering (from actual tty-solitaire output):
 *
 * Top row (y=1-5): Stock, Waste, gap, F0-F3
 *   ┌─────┐ ┌─────┐         ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
 *   │     │ │     │         │     │ │     │ │     │ │     │
 *   │     │ │     │         │     │ │     │ │     │ │     │
 *   │     │ │     │         │     │ │     │ │     │ │     │
 *   └─────┘ └─────┘         └─────┘ └─────┘ └─────┘ └─────┘
 *
 * Stock indicator (y=7):    *
 *
 * Tableau (y=9+): face-up cards show rank+suit at the LEFT of the row
 *   5♥      ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
 *           5♣      ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
 *                   K♣      ┌─────┐ ┌─────┐ ┌─────┐
 *
 * Card positions (x-coordinates):
 *   Col 0: x=1  (Stock / Tableau 0)
 *   Col 1: x=9  (Waste / Tableau 1)
 *   Col 2: x=17 (Gap / Tableau 2)
 *   Col 3: x=25 (F0 / Tableau 3)
 *   Col 4: x=33 (F1 / Tableau 4)
 *   Col 5: x=41 (F2 / Tableau 5)
 *   Col 6: x=49 (F3 / Tableau 6)
 */
function parseScreen(lines, cols) {
  const state = new GameState();
  const rows = lines.length;

  // Split lines into code-point arrays for correct Unicode indexing
  // (suit chars like ♥ are multi-byte UTF-8 but single code points)
  const codeLines = lines.map(l => [...l]);

  function cell(x, y) {
    if (y < 0 || y >= rows || x < 0) return " ";
    const line = codeLines[y] || [];
    return x < line.length ? line[x] : " ";
  }

  // Parse rank+suit starting at position (x, y)
  function parseRankSuit(x, y) {
    const c1 = cell(x, y);
    const c2 = cell(x + 1, y);
    const c3 = cell(x + 2, y);

    // Try 2-char rank "10"
    if (c1 === "1" && c2 === "0" && SUITS.includes(c3)) {
      return new Card("10", c3);
    }

    // Try 1-char rank
    if (RANKS.includes(c1) && SUITS.includes(c2)) {
      return new Card(c1, c2);
    }

    return null;
  }

  // Card column x-positions (for top border ┌ and tableau rank+suit)
  const colX = [1, 9, 17, 25, 33, 41, 49];

  // ── Parse top row (lines[1]-lines[5]) ──

  // Stock: col 0, x=1. Face-down if we see ┌ at x=1 on line[1]
  const hasStock = cell(1, 1) === "┌";

  // Waste: col 1, x=9. When a card is face-up in the waste,
  // it replaces the ┌─────┐ box with rank+suit at x=9 on line[1]
  // When empty, x=9 shows ┌ (face-down card back)
  const wasteChar = cell(9, 1);
  let wasteCard = null;
  if (wasteChar !== "┌" && wasteChar !== "│" && wasteChar !== " ") {
    wasteCard = parseRankSuit(9, 1);
  }
  // Also try line[2] inside the box (x=11)
  if (!wasteCard) wasteCard = parseRankSuit(11, 2);
  if (wasteCard) state.waste.push(wasteCard);

  // Foundations: cols 3-6. When a card is face-up in a foundation,
  // it replaces the ┌─────┐ box with rank+suit at the column x on line[1]
  // (same as the waste card — appears on the top border row)
  // Foundation x positions: F0=25, F1=33, F2=41, F3=49
  const foundX = [25, 33, 41, 49];
  for (let fi = 0; fi < 4; fi++) {
    const fx = foundX[fi];
    // Check if there's a card (not a ┌ box) at this position on line[1]
    const ch = cell(fx, 1);
    let card = null;
    if (ch !== "┌" && ch !== "│" && ch !== " " && ch !== "└") {
      card = parseRankSuit(fx, 1);
    }
    // Also try inside the box at line[2]
    if (!card) card = parseRankSuit(fx + 2, 2);
    if (card) {
      // Infer full foundation stack from the top card
      const suit = card.suit;
      for (let v = 0; v <= card.value; v++) {
        state.foundations[fi].push(new Card(RANKS[v], suit));
      }
    }
  }

  // Stock indicator at line[7]
  const line7 = lines[7] || "";
  if (line7.includes("*") || hasStock) {
    state.stock.push(Object.assign(new Card("?", "?"), { faceUp: false }));
  }

  // ── Parse tableau (line[9]+) ──
  // Cards cascade down by 1 row each. Each row shows either:
  //   - "┌─────┐" for a face-down card (at the column x position)
  //   - rank+suit for a face-up card (at the column x position)
  // We scan each column line by line.

  for (let t = 0; t < 7; t++) {
    const x = colX[t];
    let y = 9; // tableau starts at line[9]
    let emptyCount = 0;

    while (y < rows && emptyCount < 3) {
      const ch = cell(x, y);

      // Face-down card: "┌" at x
      if (ch === "┌") {
        state.tableau[t].push(Object.assign(new Card("?", "?"), { faceUp: false }));
        y += 1;
        emptyCount = 0;
        continue;
      }

      // Face-up card: rank+suit at x, y
      const card = parseRankSuit(x, y);
      if (card) {
        state.tableau[t].push(card);
        y += 1;
        emptyCount = 0;
        continue;
      }

      // Empty row in this column — skip
      y += 1;
      emptyCount++;
    }
  }

  return state;
}

// ── Move Executor ─────────────────────────────────────────────────────────

/**
 * Translate a move to key presses, tracking cursor position.
 *
 * Cursor columns (0-6) map to stack positions:
 *   0: Stock    1: Waste    2: Gap/Tab2
 *   3: F0/Tab3  4: F1/Tab4  5: F2/Tab5  6: F3/Tab6
 */
class MoveExecutor {
  constructor(keyFn) {
    this.key = keyFn;
    this.curCol = 0;
    this.curRow = 0; // 0=top, 1=tableau
  }

  // Navigate to a specific column on the top row (no card selected)
  async goToTopCol(col) {
    await this.key("escape");
    // Smash left to reach x=4 (stock/col 0)
    for (let i = 0; i < 7; i++) await this.key("h");
    // k sets cursor->y = CURSOR_BEGIN_Y (7) if y > 7
    await this.key("k");
    this.curCol = 0;
    this.curRow = 0;
    // Move right to target column
    for (let i = 0; i < col; i++) { await this.key("l"); this.curCol++; }
  }

  // Navigate to the bottom of a tableau column (no card selected)
  async goToTabBot(col) {
    await this.goToTopCol(col);
    // j from top row goes to bottom of current maneuvre column
    await this.key("j"); this.curRow = 1;
  }

  // Move cursor from current column to target column (card selected, no escape)
  // In card movement mode, h/l move between columns, k goes to top row
  async moveToCol(targetCol) {
    // Go to top row first (k sets y = CURSOR_BEGIN_Y)
    await this.key("k");
    this.curRow = 0;
    // Move horizontally: smash left then move right
    for (let i = 0; i < 7; i++) await this.key("h");
    this.curCol = 0;
    for (let i = 0; i < targetCol; i++) { await this.key("l"); this.curCol++; }
  }

  async executeMove(move) {
    switch (move.type) {
      case "deal_stock": {
        // Stock is at column 0 on the top row
        await this.goToTopCol(0);
        await this.key("space");
        break;
      }
      case "recycle_stock": {
        // Stock is at column 0 on the top row
        await this.goToTopCol(0);
        await this.key("space");
        break;
      }
      case "waste_to_foundation": {
        // Auto-move: select waste card, then press space again to auto-move
        await this.goToTopCol(1); // waste is col 1
        await this.key("space"); // select
        await this.key("space"); // auto-move to foundation
        break;
      }
      case "waste_to_tableau": {
        // Select waste card, navigate to destination, place
        await this.goToTopCol(1); // waste is col 1
        await this.key("space"); // select
        // Move to destination column (no escape!)
        await this.moveToCol(move.to);
        await this.key("j"); // go to bottom of tableau
        await this.key("space"); // place
        await this.key("escape"); // cancel selection if invalid
        break;
      }
      case "tableau_to_foundation": {
        // Auto-move: select card, then press space again to auto-move
        await this.goToTabBot(move.from);
        await this.key("space"); // select
        await this.key("space"); // auto-move to foundation
        break;
      }
      case "tableau_to_tableau": {
        // Select card(s), navigate to destination, place
        await this.goToTabBot(move.from);
        // If moving multiple cards, mark them
        if (move.count > 1) {
          for (let i = 1; i < move.count; i++) {
            await this.key("m"); // mark more cards
          }
        }
        await this.key("space"); // select
        // Move to destination column (no escape!)
        await this.moveToCol(move.to);
        await this.key("j"); // go to bottom of tableau
        await this.key("space"); // place
        await this.key("escape"); // cancel selection if invalid
        break;
      }
    }
  }
}

// ── Main ───────────────────────────────────────────────────────────────────

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function main() {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  const manager = new TerminalSessionManager({ env: { ...process.env, TERM: "xterm-256color" } });
  const session = await manager.create({ command: COMMAND, args: ["--no-background-color"], cols: COLS, rows: ROWS, title: "tty-solitaire" });
  await session.settle(500);

  const recorder = new AsciicastRecorder({ outputDir: OUTPUT_DIR, cols: session.cols, rows: session.rows, title: "tty-solitaire", semanticOverlay: true, recordInput: false, command: COMMAND + " --no-background-color" });
  session.attachRecording(recorder);
  session.startScreenCapture(500); // 2 fps — less data, still smooth
  recorder.recordSemanticSnapshot(session.semanticSnapshot("full", false).snapshot);

  let moves = 0;
  const key = async (k) => { await session.pressKey(k); await session.settle(100); moves++; };
  const snap = () => recorder.recordSemanticSnapshot(session.semanticSnapshot("full", false).snapshot);

  // ── SIGINT handler: Ctrl+C dumps current session to HTML ──
  let interrupted = false;
  let shutdownPromise = null;

  const shutdown = async () => {
    if (interrupted) return; // prevent double-shutdown
    interrupted = true;
    process.stderr.write("\n  SIGINT received — dumping session to HTML...\n");

    try {
      // Take final semantic snapshot
      snap();

      // Detach recording BEFORE stopping session to prevent race condition
      session.detachRecording();

      // Try to quit the game gracefully
      if (session.running) {
        try {
          await session.pressKey("q");
          await sleep(200);
          if (session.running) await session.stop({ force: true });
        } catch {
          try { await session.stop({ force: true }); } catch {}
        }
      }

      // Close recording — try recorder.close(), fall back to manual HTML
      try {
        await recorder.close();
        process.stderr.write(`  Session dumped to: ${OUTPUT_DIR}\n`);
        process.stderr.write(`  Open: file://${OUTPUT_DIR}/index.html\n`);
      } catch (err) {
        process.stderr.write(`  recorder.close() failed: ${err.message}\n`);
        // Fallback: write HTML manually
        try {
          const castContent = fs.readFileSync(recorder.castPath, "utf8");
          const lines = castContent.trimEnd().split("\n").filter(Boolean);
          const header = JSON.parse(lines[0]);
          const standardLines = [JSON.stringify(header)];
          const semanticEvents = [];
          for (const line of lines.slice(1)) {
            try { const e = JSON.parse(line); if (e[1] === "s") semanticEvents.push(e); else standardLines.push(JSON.stringify(e)); } catch { continue; }
          }
          const standardCast = standardLines.join("\n") + "\n";
          fs.writeFileSync(path.join(OUTPUT_DIR, "playback.cast"), standardCast);
          // Write semantic-events.json in the format the overlay HTML expects: {time, snapshot}
          if (semanticEvents.length > 0) {
            const events = semanticEvents.map(e => ({
              time: e[0],
              snapshot: e[2] || {},
            }));
            fs.writeFileSync(path.join(OUTPUT_DIR, "semantic-events.json"), JSON.stringify(events));
          }
          const html = buildPlayerHtml({ title: "tty-solitaire" });
          fs.writeFileSync(recorder.htmlPath, html);
          process.stderr.write(`  Fallback HTML: ${OUTPUT_DIR}/index.html\n`);
        } catch (e2) {
          process.stderr.write(`  Fallback also failed: ${e2.message}\n`);
        }
      }
      try { manager.dispose(); } catch {}
    } catch (err) {
      process.stderr.write(`  Error during shutdown: ${err.message}\n`);
    }

    process.exit(0);
  };

  // Node.js signal handlers: async handlers aren't awaited.
  // We set interrupted=true synchronously so the game loop breaks,
  // then kick off the async cleanup. If it takes >3s, force exit.
  const handleSignal = () => {
    interrupted = true; // break the game loop immediately
    if (!shutdownPromise) {
      shutdownPromise = shutdown();
      // Safety: force exit after 3 seconds if cleanup hangs
      setTimeout(() => process.exit(0), 3000);
    }
  };

  process.on("SIGINT", handleSignal);
  process.on("SIGTERM", handleSignal);

  const executor = new MoveExecutor(key);
  let consecutiveFailedMoves = 0;
  const failedMoveTypes = new Set();

  // Press space to start the game
  await sleep(800);
  await key("space");
  await sleep(500);

  // Main game loop
  let consecutiveNoProgress = 0;
  let lastFoundationCount = 0;

  const startTime = Date.now();
  const MAX_TIME_MS = 120000; // 2 minutes max

  for (let turn = 0; turn < 200 && !interrupted; turn++) {
    if (Date.now() - startTime > MAX_TIME_MS) {
      process.stderr.write("\n  Time limit reached.\n");
      break;
    }
    // Parse the screen using snapshot().lines
    const { lines } = session.snapshot();
    const state = parseScreen(lines, COLS);

    // Debug: dump parsed state on first turn and every 20 turns
    if (turn === 0 || turn % 20 === 0) {
      process.stderr.write("\n  --- Parsed state ---\n");
      process.stderr.write(`  Waste: ${state.waste.map(c => c.toString()).join(", ") || "empty"}\n`);
      for (let fi = 0; fi < 4; fi++) {
        const f = state.foundations[fi];
        process.stderr.write(`  F${fi}: ${f.length > 0 ? f[f.length-1].toString() : "empty"}\n`);
      }
      for (let t = 0; t < 7; t++) {
        const col = state.tableau[t];
        const faceUp = col.filter(c => c.faceUp).map(c => c.toString());
        const faceDown = col.filter(c => !c.faceUp).length;
        process.stderr.write(`  T${t}: ${faceDown}d [${faceUp.join(" ")}]\n`);
      }
      process.stderr.write(`  Stock: ${state.stock.length > 0 ? "has cards" : "empty"}\n`);
    }

    // Check if we won
    if (state.isWon) {
      process.stderr.write("\n  WON! All 52 cards in foundations!\n");
      break;
    }

    // Run beam search
    const bestMoves = beamSearch(state, { beamWidth: 8, depth: 6 });

    if (bestMoves.length === 0) {
      process.stderr.write("\n  No moves found. Game stuck.\n");
      break;
    }

    // Execute just the first move from the best sequence, skipping blacklisted moves
    let move = bestMoves[0];
    let moveIdx = 0;
    const moveKey = (m) => m.type + ":" + m.from + ":" + m.to;
    while (moveIdx < bestMoves.length && failedMoveTypes.has(moveKey(move))) {
      moveIdx++;
      move = bestMoves[moveIdx];
    }
    if (!move) {
      process.stderr.write("\n  All moves blacklisted. Game stuck.\n");
      break;
    }
    process.stderr.write(`\r  Turn ${turn+1}: ${move.type} ${move.card || ""} ${move.from !== undefined ? "col" + move.from : ""} ${move.to !== undefined ? "-> " + move.to : ""}   (moves: ${moves})  `);

    await executor.executeMove(move);

    // Verify the move actually changed the screen
    await sleep(200);
    const { lines: postLines } = session.snapshot();
    const screenChanged = postLines.some((l, i) => l !== (lines[i] || ""));
    if (!screenChanged) {
      process.stderr.write(" [FAILED - no change]");
      // Try pressing escape to clear any stuck state
      await key("escape");
      await sleep(100);
      consecutiveFailedMoves++;
      // If same move type fails 3 times in a row, skip it next time
      if (consecutiveFailedMoves >= 3) {
        process.stderr.write(" [skipping stuck move]");
        // Add to a blacklist for this turn
        failedMoveTypes.add(move.type + ":" + move.from + ":" + move.to);
        consecutiveFailedMoves = 0;
      }
    } else {
      consecutiveFailedMoves = 0;
      failedMoveTypes.clear();
    }

    // Take semantic snapshot periodically
    if (turn % 10 === 0) await snap();

    // Track progress
    const { lines: newLines } = session.snapshot();
    const newState = parseScreen(newLines, COLS);
    if (newState.foundationCount > lastFoundationCount) {
      lastFoundationCount = newState.foundationCount;
      consecutiveNoProgress = 0;
    } else {
      consecutiveNoProgress++;
    }

    // If no progress for 30 turns, try dealing more aggressively
    if (consecutiveNoProgress > 30) {
      process.stderr.write("\n  No progress, cycling stock...\n");
      for (let i = 0; i < 3; i++) {
        await executor.goToTopCol(0);
        await key("space");
      }
      consecutiveNoProgress = 0;
    }
  }

  // Normal shutdown (same path as SIGINT)
  if (!interrupted) {
    await snap();
    // Detach recording BEFORE stopping session to prevent race condition
    // (session exit handler also calls recorder.close())
    try {
      const detached = session.detachRecording();
      process.stderr.write(`  Detached recording: ${detached ? "yes" : "no"}\n`);
    } catch (err) {
      process.stderr.write(`  detachRecording error: ${err.message}\n`);
    }
    try { await key("q"); } catch {}
    await sleep(500);
    if (session.running) { try { await session.stop({ force: true }); } catch {} }
    try {
      // Check cast file before trying to close
      const fs = await import("fs");
      const castStat = fs.default.statSync(recorder.castPath);
      process.stderr.write(`  Cast file: ${recorder.castPath} (${castStat.size} bytes)\n`);
      process.stderr.write(`  Recorder closed: ${recorder.closed}\n`);

      // Timeout for recorder.close() — it can hang on large files
      const closePromise = recorder.close();
      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error("recorder.close() timed out after 15s")), 15000)
      );
      await Promise.race([closePromise, timeoutPromise]);
      process.stderr.write(`  HTML written to: ${recorder.htmlPath}\n`);
    } catch (err) {
      process.stderr.write(`  recorder.close() error: ${err.message}\n`);
      // Fallback: write a working HTML player manually
      try {
        const fs = await import("fs");
        const path = await import("path");
        // Read the cast file and split it ourselves
        const castContent = fs.default.readFileSync(recorder.castPath, "utf8");
        const lines = castContent.trimEnd().split("\n").filter(Boolean);
        const header = JSON.parse(lines[0]);
        const standardLines = [JSON.stringify(header)];
        const semanticEvents = [];
        for (const line of lines.slice(1)) {
          try {
            const event = JSON.parse(line);
            if (event[1] === "s") {
              semanticEvents.push(event);
            } else {
              standardLines.push(JSON.stringify(event));
            }
          } catch { continue; }
        }
        const standardCast = standardLines.join("\n") + "\n";

        // Write playback.cast
        const playbackPath = path.default.join(OUTPUT_DIR, "playback.cast");
        fs.default.writeFileSync(playbackPath, standardCast);

        // Write semantic-events.json in the format the overlay HTML expects
        if (semanticEvents.length > 0) {
          const events = semanticEvents.map(e => ({
            time: e[0],
            snapshot: e[2] || {},
          }));
          const semanticPath = path.default.join(OUTPUT_DIR, "semantic-events.json");
          fs.default.writeFileSync(semanticPath, JSON.stringify(events));
        }

        // Write HTML (uses relative URLs — serve via HTTP)
        const html = buildPlayerHtml({ title: "tty-solitaire" });
        fs.default.writeFileSync(recorder.htmlPath, html);
        process.stderr.write(`  Fallback HTML written to: ${recorder.htmlPath}\n`);
      } catch (e2) {
        process.stderr.write(`  Fallback HTML also failed: ${e2.message}\n`);
      }
    }
    try { manager.dispose(); } catch {}
  }

  console.log(JSON.stringify({ castPath: recorder.castPath, htmlPath: recorder.htmlPath, outputDir: OUTPUT_DIR, totalMoves: moves }, null, 2));
  process.stderr.write("\n  Done! " + moves + " moves.\n");

  // Start a local HTTP server so the HTML player works (file:// has CORS issues)
  const serveMode = process.argv.includes("--serve");
  const http = await import("node:http");
  const server = http.createServer((req, res) => {
    // Ignore favicon requests
    if (req.url === "/favicon.ico") { res.writeHead(204); res.end(); return; }
    const urlPath = req.url === "/" ? "/index.html" : req.url;
    // Prevent path traversal
    const safePath = urlPath.replace(/\.\./g, "").replace(/\/\//g, "/");
    const filePath = path.join(OUTPUT_DIR, safePath);
    try {
      const data = fs.readFileSync(filePath);
      const ext = path.extname(filePath);
      const mimeTypes = { ".html": "text/html; charset=utf-8", ".js": "application/javascript", ".css": "text/css", ".json": "application/json", ".cast": "application/x-asciicast", ".wasm": "application/wasm" };
      res.writeHead(200, { "Content-Type": mimeTypes[ext] || "application/octet-stream", "Access-Control-Allow-Origin": "*" });
      res.end(data);
    } catch {
      res.writeHead(404);
      res.end("Not found");
    }
  });

  const port = 3000;
  await new Promise(resolve => server.listen(port, resolve));
  const url = `http://localhost:${port}/index.html`;
  process.stderr.write(`\n  Player: ${url}\n`);

  // Auto-open in browser (macOS)
  try { const { exec } = await import("node:child_process"); exec(`open "${url}"`); } catch {}

  if (serveMode) {
    process.stderr.write(`  Press Ctrl+C to stop server\n`);
    await new Promise(resolve => {
      process.on("SIGINT", () => { server.close(); resolve(); });
    });
    process.stderr.write("\n  Server stopped.\n");
  } else {
    process.stderr.write(`  (Use --serve flag to keep server running, or: cd ${OUTPUT_DIR} && python3 -m http.server 3000)\n`);
    // Auto-close after 60 seconds
    setTimeout(() => { server.close(); process.exit(0); }, 60000);
  }
}

main().catch(err => { console.error("Error:", err.message, err.stack); process.exit(1); });
