#!/usr/bin/env -S deno run -A
/**
 * @module generate-html
 *
 * Reads the deciduous graph export, narratives, ADRs, and recent git history
 * to produce a single self-contained interactive HTML document.
 *
 * Usage:
 *   deno run -A .agents/skills/deciduous-viz/scripts/generate-html.ts [output-path]
 */

import { join } from "https://deno.land/std/path/mod.ts";

const ROOT = Deno.env.get("GARAZYK_ROOT") ?? Deno.cwd();
const GRAPH_PATH = join(ROOT, "docs", "graph-data.json");
const NARRATIVES_PATH = join(ROOT, ".deciduous", "narratives.md");
const ADR_DIR = join(ROOT, "docs", "adr");
const OUTPUT_DEFAULT = join(ROOT, "docs", "decision-graph.html");

/* ── Data loading ──────────────────────────────────────────────────────── */

interface GraphNode {
  id: number;
  change_id: string;
  node_type: string;
  title: string;
  description: string;
  status: string;
  created_at: string;
  updated_at: string;
  metadata_json: string | null;
  _meta?: Record<string, unknown>;
}

interface GraphEdge {
  id: number;
  from_node_id: number;
  to_node_id: number;
  edge_type: string;
  weight: number;
  rationale: string | null;
}

interface GraphData {
  nodes: GraphNode[];
  edges: GraphEdge[];
}

function loadGraph(): GraphData {
  const raw = Deno.readTextFileSync(GRAPH_PATH);
  const data = JSON.parse(raw);
  for (const n of data.nodes) {
    if (n.metadata_json) {
      try { n._meta = JSON.parse(n.metadata_json); } catch { /* skip */ }
    }
  }
  return data;
}

function loadNarratives(): string {
  try {
    return Deno.readTextFileSync(NARRATIVES_PATH);
  } catch {
    return "";
  }
}

function loadADRs(): { name: string; content: string }[] {
  const adrs: { name: string; content: string }[] = [];
  try {
    for (const entry of Deno.readDirSync(ADR_DIR)) {
      if (entry.isFile && entry.name.endsWith(".md")) {
        const content = Deno.readTextFileSync(join(ADR_DIR, entry.name));
        adrs.push({ name: entry.name, content });
      }
    }
  } catch { /* no ADR dir */ }
  return adrs.sort((a, b) => a.name.localeCompare(b.name));
}

function loadGitLog(): string {
  try {
    const cmd = new Deno.Command("git", { args: ["log", "--oneline", "-30"], cwd: ROOT, stdout: "piped", stderr: "null" });
    const output = cmd.outputSync();
    return new TextDecoder().decode(output.stdout).trim();
  } catch {
    return "";
  }
}

/* ── HTML generation ───────────────────────────────────────────────────── */

function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function markdownToHtml(md: string): string {
  let html = esc(md);
  // Headers
  html = html.replace(/^#### (.+)$/gm, '<h4>$1</h4>');
  html = html.replace(/^### (.+)$/gm, '<h3>$1</h3>');
  html = html.replace(/^## (.+)$/gm, '<h2>$1</h2>');
  html = html.replace(/^# (.+)$/gm, '<h1>$1</h1>');
  // Bold and italic
  html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');
  // Inline code
  html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
  // Blockquotes
  html = html.replace(/^&gt; (.+)$/gm, '<blockquote>$1</blockquote>');
  // Lists
  html = html.replace(/^- (.+)$/gm, '<li>$1</li>');
  html = html.replace(/(<li>.*<\/li>\n?)+/g, (m) => `<ul>${m}</ul>`);
  // Horizontal rules
  html = html.replace(/^---$/gm, '<hr>');
  // Links
  html = html.replace(
    /\[([^\]]+)\]\(([^)]+)\)/g,
    '<a href="$2" target="_blank" rel="noopener">$1</a>'
  );
  // Paragraphs (lines not already wrapped)
  html = html.replace(/^(?!<[hluo]|<\/|<li|<hr|<blockquote|<code|<strong|<em)(.+)$/gm, '<p>$1</p>');
  return html;
}

function syntaxHighlight(code: string, lang: string): string {
  let highlighted = esc(code);
  if (lang === "objc" || lang === "m" || lang === "h") {
    // Objective-C keywords
    const kws = [
      "typedef", "struct", "enum", "const", "static", "extern",
      "if", "else", "for", "while", "do", "switch", "case", "return",
      "void", "int", "float", "double", "BOOL", "YES", "NO", "nil", "NULL",
      "self", "super", "_cmd", "@interface", "@implementation", "@end",
      "@property", "@selector", "@protocol", "@optional", "@required",
      "@import", "#import", "#define", "#ifdef", "#ifndef", "#endif",
      "NSArray", "NSDictionary", "NSString", "NSData", "NSError",
      "NSInteger", "NSUInteger", "CGFloat", "dispatch_queue_t",
    ];
    for (const kw of kws) {
      const re = new RegExp(`\\b(${kw})\\b`, "g");
      highlighted = highlighted.replace(re, '<span class="kw">$1</span>');
    }
    // Strings
    highlighted = highlighted.replace(/(&quot;[^&]*?&quot;)/g, '<span class="str">$1</span>');
    // Comments
    highlighted = highlighted.replace(/(\/\/.*$)/gm, '<span class="cmt">$1</span>');
    highlighted = highlighted.replace(/(\/\*[\s\S]*?\*\/)/g, '<span class="cmt">$1</span>');
  } else if (lang === "ts" || lang === "typescript" || lang === "js") {
    const kws = [
      "const", "let", "var", "function", "return", "if", "else", "for",
      "while", "do", "switch", "case", "break", "continue", "new", "this",
      "class", "extends", "implements", "interface", "type", "enum",
      "import", "from", "export", "default", "async", "await", "try",
      "catch", "throw", "typeof", "instanceof", "null", "undefined", "true",
      "false", "void", "readonly", "private", "public", "protected",
    ];
    for (const kw of kws) {
      const re = new RegExp(`\\b(${kw})\\b`, "g");
      highlighted = highlighted.replace(re, '<span class="kw">$1</span>');
    }
    highlighted = highlighted.replace(/(&#39;[^&#]*?&#39;|&quot;[^&]*?&quot;)/g, '<span class="str">$1</span>');
    highlighted = highlighted.replace(/(\/\/.*$)/gm, '<span class="cmt">$1</span>');
  } else if (lang === "sql") {
    const kws = [
      "SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "CREATE",
      "TABLE", "INDEX", "ALTER", "DROP", "JOIN", "LEFT", "RIGHT", "INNER",
      "ON", "AND", "OR", "NOT", "NULL", "PRIMARY", "KEY", "FOREIGN",
      "REFERENCES", "UNIQUE", "CHECK", "DEFAULT", "IF", "EXISTS", "VALUES",
      "SET", "INTO", "AS", "ORDER", "BY", "GROUP", "HAVING", "LIMIT",
      "OFFSET", "UNION", "ALL", "DISTINCT", "IN", "LIKE", "BETWEEN",
      "IS", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "PRAGMA",
    ];
    for (const kw of kws) {
      const re = new RegExp(`\\b(${kw})\\b`, "gi");
      highlighted = highlighted.replace(re, '<span class="kw">$1</span>');
    }
    highlighted = highlighted.replace(/(&#39;[^&#]*?&#39;)/g, '<span class="str">$1</span>');
    highlighted = highlighted.replace(/(--.*$)/gm, '<span class="cmt">$1</span>');
  }
  return highlighted;
}

function nodeTypeColour(type: string): string {
  switch (type) {
    case "goal": return "var(--clr-goal)";
    case "decision": return "var(--clr-decision)";
    case "action": return "var(--clr-action)";
    case "outcome": return "var(--clr-outcome)";
    case "observation": return "var(--clr-observation)";
    case "option": return "var(--clr-option)";
    default: return "var(--clr-muted)";
  }
}

function statusIcon(status: string): string {
  switch (status) {
    case "completed": case "done": return "&#10003;";
    case "pending": return "&#9679;";
    case "active": case "in_progress": return "&#9654;";
    case "rejected": return "&#10007;";
    default: return "&#8943;";
  }
}

/* ── Main ──────────────────────────────────────────────────────────────── */

function generate(): string {
  const graph = loadGraph();
  const narratives = loadNarratives();
  const adrs = loadADRs();
  const gitLog = loadGitLog();

  const nodes = graph.nodes;
  const edges = graph.edges;

  // Stats
  const typeCounts: Record<string, number> = {};
  const statusCounts: Record<string, number> = {};
  for (const n of nodes) {
    typeCounts[n.node_type] = (typeCounts[n.node_type] || 0) + 1;
    statusCounts[n.status] = (statusCounts[n.status] || 0) + 1;
  }

  const completedCount = (statusCounts["completed"] || 0) + (statusCounts["done"] || 0);
  const pendingCount = statusCounts["pending"] || 0;
  const totalNodes = nodes.length;
  const totalEdges = edges.length;

  // Build node JSON for JS
  const nodesJson = JSON.stringify(
    nodes.map((n) => ({
      id: n.id,
      type: n.node_type,
      title: n.title,
      desc: n.description,
      status: n.status,
      created: n.created_at,
      updated: n.updated_at,
      meta: n._meta,
    }))
  );
  const edgesJson = JSON.stringify(
    edges.map((e) => ({
      from: e.from_node_id,
      to: e.to_node_id,
      type: e.edge_type,
      rationale: e.rationale,
    }))
  );

  // Narratives HTML
  const narrativesHtml = narratives ? markdownToHtml(narratives) : "<p>No narratives recorded yet.</p>";

  // ADRs HTML
  const adrsHtml = adrs.length > 0
    ? adrs.map((a) => `<section class="adr"><h2>${esc(a.name.replace(/\.md$/, "").replace(/^\d{4}-/, ""))}</h2><div class="adr-body">${markdownToHtml(a.content)}</div></section>`).join("\n")
    : "<p>No ADRs found.</p>";

  // Git log HTML
  const gitLines = gitLog.split("\n").filter(Boolean);
  const gitHtml = gitLines.map((line) => {
    const match = line.match(/^([0-9a-f]+)\s+(.+)$/);
    if (match) {
      return `<li><code class="git-hash">${esc(match[1])}</code> ${esc(match[2])}</li>`;
    }
    return `<li>${esc(line)}</li>`;
  }).join("\n");

  // Type colour legend
  const typeLegend = Object.entries(typeCounts)
    .sort((a, b) => b[1] - a[1])
    .map(([t, c]) => `<span class="legend-item"><span class="legend-dot" style="background:${nodeTypeColour(t)}"></span>${t} (${c})</span>`)
    .join("");

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Decision Graph &mdash; Garazyk</title>
<style>
/* ── Reset & Tokens ─────────────────────────────────────────────── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --bg:        oklch(0.16 0.01 260);
  --surface:   oklch(0.20 0.012 260);
  --surface-2: oklch(0.24 0.014 260);
  --surface-3: oklch(0.28 0.016 260);
  --ink:       oklch(0.92 0.01 260);
  --ink-2:     oklch(0.72 0.01 260);
  --ink-3:     oklch(0.52 0.01 260);
  --border:    oklch(0.32 0.015 260);
  --accent:    oklch(0.72 0.16 250);
  --accent-dim:oklch(0.52 0.12 250);
  --link:      oklch(0.78 0.14 240);
  --clr-goal:       oklch(0.72 0.18 145);
  --clr-decision:   oklch(0.72 0.16 250);
  --clr-action:     oklch(0.72 0.14 55);
  --clr-outcome:    oklch(0.72 0.18 320);
  --clr-observation:oklch(0.68 0.10 80);
  --clr-option:     oklch(0.68 0.12 200);
  --clr-muted:      oklch(0.42 0.01 260);
  --clr-completed:  oklch(0.72 0.18 145);
  --clr-pending:    oklch(0.72 0.14 55);
  --clr-active:     oklch(0.72 0.16 250);
  --clr-rejected:   oklch(0.62 0.18 25);
  --radius:    8px;
  --radius-lg: 12px;
  --font:      "Inter", "SF Pro Text", -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  --mono:      "SF Mono", "Fira Code", "Cascadia Code", "JetBrains Mono", ui-monospace, monospace;
}

html { font-size: 15px; }
body {
  font-family: var(--font);
  background: var(--bg);
  color: var(--ink);
  line-height: 1.6;
  min-height: 100vh;
  overflow-x: hidden;
}

/* ── Layout ─────────────────────────────────────────────────────── */
.app { display: flex; flex-direction: column; min-height: 100vh; }

.header {
  padding: 1.25rem 1.5rem;
  border-bottom: 1px solid var(--border);
  background: var(--surface);
  display: flex;
  align-items: center;
  gap: 1.5rem;
  flex-wrap: wrap;
}
.header h1 {
  font-size: 1.15rem;
  font-weight: 600;
  letter-spacing: -0.01em;
  color: var(--ink);
  text-wrap: balance;
}
.header-stats {
  display: flex;
  gap: 1rem;
  font-size: 0.8rem;
  color: var(--ink-2);
}
.header-stats .stat { display: flex; align-items: center; gap: 0.3rem; }
.header-stats .stat-num {
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  color: var(--ink);
}

.tabs {
  display: flex;
  gap: 0;
  border-bottom: 1px solid var(--border);
  background: var(--surface);
  padding: 0 1.5rem;
}
.tab-btn {
  background: none;
  border: none;
  border-bottom: 2px solid transparent;
  color: var(--ink-3);
  font-family: var(--font);
  font-size: 0.82rem;
  font-weight: 500;
  padding: 0.7rem 1rem;
  cursor: pointer;
  transition: color 0.15s, border-color 0.15s;
}
.tab-btn:hover { color: var(--ink-2); }
.tab-btn.active {
  color: var(--ink);
  border-bottom-color: var(--accent);
}

.main { flex: 1; display: flex; position: relative; overflow: hidden; }

.panel-graph {
  flex: 1;
  position: relative;
  overflow: hidden;
}
.panel-graph svg {
  width: 100%;
  height: 100%;
  display: block;
}
.panel-details {
  width: 360px;
  border-left: 1px solid var(--border);
  background: var(--surface);
  overflow-y: auto;
  padding: 1.25rem;
  transition: transform 0.2s ease-out;
}
.panel-details.collapsed { transform: translateX(100%); width: 0; padding: 0; overflow: hidden; }

.tab-content { display: none; padding: 1.5rem; overflow-y: auto; flex: 1; }
.tab-content.active { display: block; }

/* ── Search ─────────────────────────────────────────────────────── */
.search-bar {
  padding: 0.5rem 1.5rem;
  background: var(--surface);
  border-bottom: 1px solid var(--border);
  display: flex;
  gap: 0.75rem;
  align-items: center;
}
.search-input {
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  color: var(--ink);
  font-family: var(--font);
  font-size: 0.82rem;
  padding: 0.4rem 0.75rem;
  width: 280px;
  outline: none;
  transition: border-color 0.15s;
}
.search-input:focus { border-color: var(--accent); }
.search-input::placeholder { color: var(--ink-3); }
.legend { display: flex; gap: 0.75rem; flex-wrap: wrap; font-size: 0.75rem; color: var(--ink-2); }
.legend-item { display: flex; align-items: center; gap: 0.3rem; }
.legend-dot { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }

/* ── Details panel ──────────────────────────────────────────────── */
.detail-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 1rem;
}
.detail-type {
  display: inline-block;
  font-size: 0.7rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  padding: 0.15rem 0.5rem;
  border-radius: 3px;
  color: var(--bg);
}
.detail-title {
  font-size: 1rem;
  font-weight: 600;
  line-height: 1.4;
  margin-bottom: 0.5rem;
  text-wrap: balance;
}
.detail-desc {
  font-size: 0.85rem;
  color: var(--ink-2);
  line-height: 1.6;
  margin-bottom: 1rem;
  text-wrap: pretty;
}
.detail-meta {
  font-size: 0.75rem;
  color: var(--ink-3);
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
  margin-bottom: 1rem;
}
.detail-meta span { display: flex; align-items: center; gap: 0.4rem; }
.detail-connections h3 {
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--ink-2);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  margin-bottom: 0.5rem;
}
.detail-conn {
  font-size: 0.8rem;
  padding: 0.35rem 0;
  border-bottom: 1px solid var(--border);
  color: var(--ink-2);
  cursor: pointer;
  transition: color 0.12s;
}
.detail-conn:hover { color: var(--link); }
.detail-conn .conn-type {
  font-size: 0.65rem;
  color: var(--ink-3);
  margin-left: 0.3rem;
}
.detail-empty {
  color: var(--ink-3);
  font-size: 0.85rem;
  font-style: italic;
  padding: 2rem 0;
  text-align: center;
}
.close-btn {
  background: none;
  border: none;
  color: var(--ink-3);
  cursor: pointer;
  font-size: 1.1rem;
  line-height: 1;
  padding: 0.2rem;
}
.close-btn:hover { color: var(--ink); }

/* ── Graph nodes ────────────────────────────────────────────────── */
.node-circle {
  cursor: pointer;
  transition: r 0.12s ease-out, opacity 0.12s;
}
.node-circle:hover { filter: brightness(1.2); }
.node-circle.dimmed { opacity: 0.15; }
.node-label {
  font-family: var(--font);
  font-size: 9px;
  fill: var(--ink-2);
  pointer-events: none;
  text-anchor: middle;
}
.node-label.dimmed { opacity: 0.1; }
.edge-line {
  stroke: var(--border);
  stroke-width: 0.8;
  opacity: 0.35;
}
.edge-line.dimmed { opacity: 0.04; }
.edge-line.highlighted {
  stroke: var(--accent);
  stroke-width: 1.5;
  opacity: 0.8;
}

/* ── Prose content ──────────────────────────────────────────────── */
.prose h1 { font-size: 1.5rem; font-weight: 700; margin: 0 0 1rem; letter-spacing: -0.02em; text-wrap: balance; }
.prose h2 { font-size: 1.15rem; font-weight: 600; margin: 2rem 0 0.75rem; letter-spacing: -0.01em; text-wrap: balance; color: var(--ink); }
.prose h3 { font-size: 1rem; font-weight: 600; margin: 1.5rem 0 0.5rem; color: var(--ink); }
.prose h4 { font-size: 0.88rem; font-weight: 600; margin: 1.2rem 0 0.4rem; color: var(--ink-2); }
.prose p { margin: 0 0 0.75rem; max-width: 72ch; color: var(--ink-2); }
.prose ul { margin: 0 0 0.75rem; padding-left: 1.25rem; }
.prose li { margin-bottom: 0.3rem; color: var(--ink-2); max-width: 72ch; }
.prose blockquote {
  border-left: 3px solid var(--accent-dim);
  padding: 0.5rem 1rem;
  margin: 0.75rem 0;
  background: var(--surface-2);
  border-radius: 0 var(--radius) var(--radius) 0;
  color: var(--ink-2);
  font-style: italic;
}
.prose code {
  font-family: var(--mono);
  font-size: 0.85em;
  background: var(--surface-3);
  padding: 0.1em 0.35em;
  border-radius: 3px;
}
.prose hr {
  border: none;
  border-top: 1px solid var(--border);
  margin: 2rem 0;
}
.prose a { color: var(--link); text-decoration: none; }
.prose a:hover { text-decoration: underline; }
.prose strong { color: var(--ink); font-weight: 600; }

.adr { margin-bottom: 2.5rem; }
.adr-body { margin-top: 0.75rem; }

/* ── Syntax highlighting ────────────────────────────────────────── */
.kw  { color: oklch(0.75 0.18 280); }
.str { color: oklch(0.72 0.16 145); }
.cmt { color: var(--ink-3); font-style: italic; }

/* ── Code blocks ────────────────────────────────────────────────── */
.code-block {
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 0.75rem 1rem;
  font-family: var(--mono);
  font-size: 0.8rem;
  line-height: 1.5;
  overflow-x: auto;
  margin: 0.75rem 0;
  white-space: pre;
}

/* ── Timeline ───────────────────────────────────────────────────── */
.timeline-day {
  margin-bottom: 1.5rem;
}
.timeline-date {
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--ink-3);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  margin-bottom: 0.5rem;
  padding-bottom: 0.3rem;
  border-bottom: 1px solid var(--border);
}
.timeline-item {
  display: flex;
  gap: 0.75rem;
  padding: 0.4rem 0;
  font-size: 0.85rem;
}
.timeline-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  margin-top: 0.35rem;
  flex-shrink: 0;
}
.timeline-item-title { color: var(--ink); }
.timeline-item-type {
  font-size: 0.7rem;
  color: var(--ink-3);
  margin-left: 0.4rem;
}

/* ── Stats ──────────────────────────────────────────────────────── */
.stats-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 1rem;
  margin-bottom: 2rem;
}
.stat-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: 1.25rem;
}
.stat-card .stat-label {
  font-size: 0.75rem;
  color: var(--ink-3);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  margin-bottom: 0.4rem;
}
.stat-card .stat-value {
  font-size: 1.75rem;
  font-weight: 700;
  color: var(--ink);
  font-variant-numeric: tabular-nums;
}
.stat-bar {
  height: 6px;
  background: var(--surface-3);
  border-radius: 3px;
  margin-top: 0.75rem;
  overflow: hidden;
  display: flex;
}
.stat-bar-seg {
  height: 100%;
  transition: width 0.3s ease-out;
}

.git-list {
  list-style: none;
  font-size: 0.85rem;
}
.git-list li {
  padding: 0.3rem 0;
  border-bottom: 1px solid var(--border);
  color: var(--ink-2);
}
.git-hash {
  font-family: var(--mono);
  font-size: 0.78rem;
  color: var(--accent);
}

/* ── Graph tooltip ──────────────────────────────────────────────── */
.graph-tooltip {
  position: absolute;
  background: var(--surface-3);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 0.5rem 0.75rem;
  font-size: 0.78rem;
  color: var(--ink);
  pointer-events: none;
  z-index: 100;
  max-width: 300px;
  box-shadow: 0 4px 16px oklch(0 0 0 / 0.4);
  opacity: 0;
  transition: opacity 0.12s;
}
.graph-tooltip.visible { opacity: 1; }

/* ── Responsive ─────────────────────────────────────────────────── */
@media (max-width: 768px) {
  .panel-details { position: absolute; right: 0; top: 0; bottom: 0; z-index: 50; width: 300px; }
  .header { padding: 1rem; }
  .search-bar { padding: 0.5rem 1rem; }
  .search-input { width: 100%; }
}

/* ── Reduced motion ─────────────────────────────────────────────── */
@media (prefers-reduced-motion: reduce) {
  * { transition-duration: 0s !important; animation-duration: 0s !important; }
}
</style>
</head>
<body>
<div class="app">

  <!-- Header -->
  <header class="header">
    <h1>Decision Graph</h1>
    <div class="header-stats">
      <span class="stat"><span class="stat-num">${totalNodes}</span> nodes</span>
      <span class="stat"><span class="stat-num">${totalEdges}</span> edges</span>
      <span class="stat"><span class="stat-num">${completedCount}</span> completed</span>
      <span class="stat"><span class="stat-num">${pendingCount}</span> pending</span>
    </div>
  </header>

  <!-- Tabs -->
  <nav class="tabs">
    <button class="tab-btn active" data-tab="graph">Graph</button>
    <button class="tab-btn" data-tab="timeline">Timeline</button>
    <button class="tab-btn" data-tab="adrs">ADRs</button>
    <button class="tab-btn" data-tab="narratives">Narratives</button>
    <button class="tab-btn" data-tab="stats">Stats</button>
  </nav>

  <!-- Graph tab -->
  <div class="main">
    <div class="tab-content active" id="tab-graph" style="padding:0; display:flex; flex-direction:column;">
      <div class="search-bar">
        <input class="search-input" id="search" type="text" placeholder="Search nodes\u2026" autocomplete="off">
        <div class="legend">${typeLegend}</div>
      </div>
      <div class="panel-graph" id="graph-container">
        <svg id="graph-svg"></svg>
      </div>
    </div>

    <!-- Details panel (shared) -->
    <aside class="panel-details collapsed" id="details-panel">
      <div class="detail-header">
        <span class="detail-type" id="detail-type"></span>
        <button class="close-btn" id="detail-close">&times;</button>
      </div>
      <div class="detail-title" id="detail-title"></div>
      <div class="detail-desc" id="detail-desc"></div>
      <div class="detail-meta" id="detail-meta"></div>
      <div class="detail-connections" id="detail-connections"></div>
    </aside>

    <!-- Timeline tab -->
    <div class="tab-content" id="tab-timeline">
      <div class="prose" id="timeline-content"></div>
    </div>

    <!-- ADRs tab -->
    <div class="tab-content" id="tab-adrs">
      <div class="prose" id="adrs-content">${adrsHtml}</div>
    </div>

    <!-- Narratives tab -->
    <div class="tab-content" id="tab-narratives">
      <div class="prose" id="narratives-content">${narrativesHtml}</div>
    </div>

    <!-- Stats tab -->
    <div class="tab-content" id="tab-stats">
      <div class="stats-grid">
        <div class="stat-card">
          <div class="stat-label">Total Nodes</div>
          <div class="stat-value">${totalNodes}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Total Edges</div>
          <div class="stat-value">${totalEdges}</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Completion</div>
          <div class="stat-value">${totalNodes > 0 ? Math.round((completedCount / totalNodes) * 100) : 0}%</div>
          <div class="stat-bar">
            <div class="stat-bar-seg" style="width:${totalNodes > 0 ? (completedCount / totalNodes) * 100 : 0}%; background:var(--clr-completed)"></div>
            <div class="stat-bar-seg" style="width:${totalNodes > 0 ? (pendingCount / totalNodes) * 100 : 0}%; background:var(--clr-pending)"></div>
          </div>
        </div>
        <div class="stat-card">
          <div class="stat-label">ADRs</div>
          <div class="stat-value">${adrs.length}</div>
        </div>
      </div>
      <h2 style="font-size:1rem;font-weight:600;margin-bottom:1rem;color:var(--ink)">By Type</h2>
      <div class="stats-grid">
        ${Object.entries(typeCounts).sort((a, b) => b[1] - a[1]).map(([t, c]) =>
          `<div class="stat-card">
            <div class="stat-label" style="display:flex;align-items:center;gap:0.4rem"><span class="legend-dot" style="background:${nodeTypeColour(t)}"></span>${t}</div>
            <div class="stat-value">${c}</div>
          </div>`
        ).join("\n")}
      </div>
      <h2 style="font-size:1rem;font-weight:600;margin:1.5rem 0 1rem;color:var(--ink)">By Status</h2>
      <div class="stats-grid">
        ${Object.entries(statusCounts).sort((a, b) => b[1] - a[1]).map(([s, c]) =>
          `<div class="stat-card">
            <div class="stat-label">${s}</div>
            <div class="stat-value">${c}</div>
          </div>`
        ).join("\n")}
      </div>
      <h2 style="font-size:1rem;font-weight:600;margin:1.5rem 0 1rem;color:var(--ink)">Recent Commits</h2>
      <ul class="git-list">${gitHtml}</ul>
    </div>
  </div>
</div>

<!-- Tooltip -->
<div class="graph-tooltip" id="tooltip"></div>

<script>
/* ── Data ─────────────────────────────────────────────────────────── */
const NODES = ${nodesJson};
const EDGES = ${edgesJson};

const NODE_MAP = new Map(NODES.map(n => [n.id, n]));
const CLR = {
  goal:        "oklch(0.72 0.18 145)",
  decision:    "oklch(0.72 0.16 250)",
  action:      "oklch(0.72 0.14 55)",
  outcome:     "oklch(0.72 0.18 320)",
  observation: "oklch(0.68 0.10 80)",
  option:      "oklch(0.68 0.12 200)",
};
const CLR_MUTED = "oklch(0.42 0.01 260)";

/* ── Tabs ─────────────────────────────────────────────────────────── */
document.querySelectorAll(".tab-btn").forEach(btn => {
  btn.addEventListener("click", () => {
    document.querySelectorAll(".tab-btn").forEach(b => b.classList.remove("active"));
    document.querySelectorAll(".tab-content").forEach(c => { c.classList.remove("active"); c.style.display = "none"; });
    btn.classList.add("active");
    const tab = document.getElementById("tab-" + btn.dataset.tab);
    if (tab) { tab.classList.add("active"); tab.style.display = "block"; }
  });
});

/* ── Timeline ─────────────────────────────────────────────────────── */
(function buildTimeline() {
  const byDate = {};
  for (const n of NODES) {
    const d = n.created?.slice(0, 10) || "unknown";
    if (!byDate[d]) byDate[d] = [];
    byDate[d].push(n);
  }
  const dates = Object.keys(byDate).sort().reverse();
  let html = "<h1>Timeline</h1>";
  for (const d of dates) {
    html += '<div class="timeline-day"><div class="timeline-date">' + d + "</div>";
    for (const n of byDate[d]) {
      const clr = CLR[n.type] || CLR_MUTED;
      html += '<div class="timeline-item" data-node="' + n.id + '" style="cursor:pointer">';
      html += '<div class="timeline-dot" style="background:' + clr + '"></div>';
      html += '<div><span class="timeline-item-title">' + escHtml(n.title) + '</span>';
      html += '<span class="timeline-item-type">' + n.type + " &middot; " + n.status + "</span></div></div>";
    }
    html += "</div>";
  }
  document.getElementById("timeline-content").innerHTML = html;

  document.querySelectorAll(".timeline-item[data-node]").forEach(el => {
    el.addEventListener("click", () => selectNode(parseInt(el.dataset.node)));
  });
})();

/* ── Force-directed graph ─────────────────────────────────────────── */
(function initGraph() {
  const container = document.getElementById("graph-container");
  const svg = document.getElementById("graph-svg");
  const W = container.clientWidth || 1200;
  const H = container.clientHeight || 700;
  svg.setAttribute("viewBox", "0 0 " + W + " " + H);

  // Build adjacency
  const adj = new Map();
  for (const e of EDGES) {
    if (!adj.has(e.from)) adj.set(e.from, []);
    if (!adj.has(e.to)) adj.set(e.to, []);
    adj.get(e.from).push(e.to);
    adj.get(e.to).push(e.from);
  }

  // Initialise positions in concentric rings by type
  const types = ["goal", "decision", "action", "outcome", "observation", "option"];
  const typeIdx = {};
  types.forEach((t, i) => typeIdx[t] = i);
  const byType = {};
  for (const n of NODES) {
    if (!byType[n.type]) byType[n.type] = [];
    byType[n.type].push(n);
  }
  const cx = W / 2, cy = H / 2;
  for (const [type, arr] of Object.entries(byType)) {
    const ti = typeIdx[type] ?? 3;
    const radius = 80 + ti * 70;
    arr.forEach((n, i) => {
      const angle = (i / arr.length) * Math.PI * 2 - Math.PI / 2;
      n.x = cx + Math.cos(angle) * radius + (Math.random() - 0.5) * 30;
      n.y = cy + Math.sin(angle) * radius + (Math.random() - 0.5) * 30;
      n.vx = 0;
      n.vy = 0;
    });
  }

  // Simple force simulation
  const ALPHA = 0.3;
  const REPULSION = 800;
  const ATTRACTION = 0.005;
  const CENTER_GRAVITY = 0.01;
  const DAMPING = 0.85;
  const ITERATIONS = 120;

  for (let iter = 0; iter < ITERATIONS; iter++) {
    const alpha = ALPHA * (1 - iter / ITERATIONS);
    // Repulsion
    for (let i = 0; i < NODES.length; i++) {
      for (let j = i + 1; j < NODES.length; j++) {
        const a = NODES[i], b = NODES[j];
        let dx = b.x - a.x, dy = b.y - a.y;
        let dist = Math.sqrt(dx * dx + dy * dy) || 1;
        let force = REPULSION / (dist * dist);
        let fx = (dx / dist) * force * alpha;
        let fy = (dy / dist) * force * alpha;
        a.vx -= fx; a.vy -= fy;
        b.vx += fx; b.vy += fy;
      }
    }
    // Attraction along edges
    for (const e of EDGES) {
      const a = NODE_MAP.get(e.from), b = NODE_MAP.get(e.to);
      if (!a || !b) continue;
      let dx = b.x - a.x, dy = b.y - a.y;
      let dist = Math.sqrt(dx * dx + dy * dy) || 1;
      let force = (dist - 120) * ATTRACTION * alpha;
      let fx = (dx / dist) * force;
      let fy = (dy / dist) * force;
      a.vx += fx; a.vy += fy;
      b.vx -= fx; b.vy -= fy;
    }
    // Center gravity
    for (const n of NODES) {
      n.vx += (cx - n.x) * CENTER_GRAVITY * alpha;
      n.vy += (cy - n.y) * CENTER_GRAVITY * alpha;
    }
    // Integrate
    for (const n of NODES) {
      n.vx *= DAMPING;
      n.vy *= DAMPING;
      n.x += n.vx;
      n.y += n.vy;
      n.x = Math.max(30, Math.min(W - 30, n.x));
      n.y = Math.max(30, Math.min(H - 30, n.y));
    }
  }

  // Draw edges
  const edgeGroup = document.createElementNS("http://www.w3.org/2000/svg", "g");
  svg.appendChild(edgeGroup);
  const edgeEls = [];
  for (const e of EDGES) {
    const a = NODE_MAP.get(e.from), b = NODE_MAP.get(e.to);
    if (!a || !b) continue;
    const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
    line.setAttribute("x1", a.x); line.setAttribute("y1", a.y);
    line.setAttribute("x2", b.x); line.setAttribute("y2", b.y);
    line.classList.add("edge-line");
    line.dataset.from = e.from;
    line.dataset.to = e.to;
    edgeGroup.appendChild(line);
    edgeEls.push(line);
  }

  // Draw nodes
  const nodeGroup = document.createElementNS("http://www.w3.org/2000/svg", "g");
  svg.appendChild(nodeGroup);
  const nodeEls = [];
  for (const n of NODES) {
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g");
    const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    const r = n.type === "goal" ? 7 : n.type === "decision" ? 6 : n.type === "outcome" ? 6 : 4.5;
    circle.setAttribute("cx", n.x);
    circle.setAttribute("cy", n.y);
    circle.setAttribute("r", r);
    circle.setAttribute("fill", CLR[n.type] || CLR_MUTED);
    circle.classList.add("node-circle");
    circle.dataset.nodeId = n.id;
    g.appendChild(circle);

    // Label for goals and decisions
    if (n.type === "goal" || n.type === "decision" || n.type === "outcome") {
      const text = document.createElementNS("http://www.w3.org/2000/svg", "text");
      text.setAttribute("x", n.x);
      text.setAttribute("y", n.y - r - 4);
      text.classList.add("node-label");
      text.dataset.nodeId = n.id;
      const label = n.title.length > 35 ? n.title.slice(0, 32) + "\u2026" : n.title;
      text.textContent = label;
      g.appendChild(text);
    }

    g.style.cursor = "pointer";
    g.dataset.nodeId = n.id;
    nodeGroup.appendChild(g);
    nodeEls.push({ g, circle, node: n });
  }

  // Interactions
  const tooltip = document.getElementById("tooltip");
  let selectedId = null;

  function highlightNode(id) {
    const connected = new Set();
    connected.add(id);
    for (const e of EDGES) {
      if (e.from === id) connected.add(e.to);
      if (e.to === id) connected.add(e.from);
    }
    for (const el of nodeEls) {
      el.circle.classList.toggle("dimmed", !connected.has(el.node.id));
    }
    document.querySelectorAll(".node-label").forEach(l => {
      l.classList.toggle("dimmed", !connected.has(parseInt(l.dataset.nodeId)));
    });
    for (const el of edgeEls) {
      const f = parseInt(el.dataset.from), t = parseInt(el.dataset.to);
      const hl = (f === id || t === id);
      el.classList.toggle("highlighted", hl);
      el.classList.toggle("dimmed", !hl);
    }
  }

  function clearHighlight() {
    for (const el of nodeEls) el.circle.classList.remove("dimmed");
    document.querySelectorAll(".node-label").forEach(l => l.classList.remove("dimmed"));
    for (const el of edgeEls) { el.classList.remove("highlighted", "dimmed"); }
  }

  function showDetails(node) {
    const panel = document.getElementById("details-panel");
    panel.classList.remove("collapsed");
    document.getElementById("detail-type").textContent = node.type;
    document.getElementById("detail-type").style.background = CLR[node.type] || CLR_MUTED;
    document.getElementById("detail-title").textContent = node.title;
    document.getElementById("detail-desc").textContent = node.desc || "";

    let metaHtml = "";
    if (node.status) metaHtml += "<span>Status: <strong>" + node.status + "</strong></span>";
    if (node.created) metaHtml += "<span>Created: " + node.created.slice(0, 19).replace("T", " ") + "</span>";
    if (node.updated) metaHtml += "<span>Updated: " + node.updated.slice(0, 19).replace("T", " ") + "</span>";
    if (node.meta?.branch) metaHtml += "<span>Branch: <code>" + escHtml(String(node.meta.branch)) + "</code></span>";
    if (node.meta?.confidence) metaHtml += "<span>Confidence: " + node.meta.confidence + "%</span>";
    if (node.meta?.files) metaHtml += "<span>Files: " + escHtml(String(node.meta.files)) + "</span>";
    if (node.meta?.commit) metaHtml += "<span>Commit: <code class='git-hash'>" + escHtml(String(node.meta.commit).slice(0, 8)) + "</code></span>";
    document.getElementById("detail-meta").innerHTML = metaHtml;

    // Connections
    const connDiv = document.getElementById("detail-connections");
    let connHtml = "<h3>Connections</h3>";
    const outEdges = EDGES.filter(e => e.from === node.id);
    const inEdges = EDGES.filter(e => e.to === node.id);
    for (const e of outEdges) {
      const target = NODE_MAP.get(e.to);
      if (target) {
        connHtml += '<div class="detail-conn" data-node="' + target.id + '">';
        connHtml += escHtml(target.title);
        connHtml += '<span class="conn-type">' + e.type + (e.rationale ? ": " + escHtml(e.rationale.slice(0, 60)) : "") + "</span></div>";
      }
    }
    for (const e of inEdges) {
      const source = NODE_MAP.get(e.from);
      if (source) {
        connHtml += '<div class="detail-conn" data-node="' + source.id + '">';
        connHtml += escHtml(source.title);
        connHtml += '<span class="conn-type">incoming &middot; ' + e.type + "</span></div>";
      }
    }
    if (outEdges.length === 0 && inEdges.length === 0) connHtml += '<div class="detail-empty">No connections</div>';
    connDiv.innerHTML = connHtml;

    connDiv.querySelectorAll(".detail-conn[data-node]").forEach(el => {
      el.addEventListener("click", () => selectNode(parseInt(el.dataset.node)));
    });
  }

  window.selectNode = function(id) {
    selectedId = id;
    const node = NODE_MAP.get(id);
    if (!node) return;
    highlightNode(id);
    showDetails(node);
    // Switch to graph tab
    document.querySelectorAll(".tab-btn").forEach(b => b.classList.remove("active"));
    document.querySelectorAll(".tab-content").forEach(c => { c.classList.remove("active"); c.style.display = "none"; });
    document.querySelector('[data-tab="graph"]').classList.add("active");
    const graphTab = document.getElementById("tab-graph");
    graphTab.classList.add("active");
    graphTab.style.display = "flex";
  };

  document.getElementById("detail-close").addEventListener("click", () => {
    document.getElementById("details-panel").classList.add("collapsed");
    selectedId = null;
    clearHighlight();
  });

  // Node click/hover
  for (const el of nodeEls) {
    el.circle.addEventListener("click", (ev) => {
      ev.stopPropagation();
      selectNode(el.node.id);
    });
    el.circle.addEventListener("mouseenter", (ev) => {
      if (selectedId !== null) return;
      highlightNode(el.node.id);
      tooltip.textContent = el.node.title;
      tooltip.classList.add("visible");
    });
    el.circle.addEventListener("mousemove", (ev) => {
      tooltip.style.left = (ev.clientX + 12) + "px";
      tooltip.style.top = (ev.clientY - 8) + "px";
    });
    el.circle.addEventListener("mouseleave", () => {
      if (selectedId === null) clearHighlight();
      tooltip.classList.remove("visible");
    });
  }

  svg.addEventListener("click", () => {
    selectedId = null;
    clearHighlight();
    document.getElementById("details-panel").classList.add("collapsed");
  });

  /* ── Search ──────────────────────────────────────────────────── */
  document.getElementById("search").addEventListener("input", (ev) => {
    const q = ev.target.value.toLowerCase().trim();
    if (!q) { clearHighlight(); return; }
    const matches = new Set();
    for (const n of NODES) {
      if (n.title.toLowerCase().includes(q) || (n.desc && n.desc.toLowerCase().includes(q))) {
        matches.add(n.id);
      }
    }
    for (const el of nodeEls) {
      el.circle.classList.toggle("dimmed", !matches.has(el.node.id));
    }
    document.querySelectorAll(".node-label").forEach(l => {
      l.classList.toggle("dimmed", !matches.has(parseInt(l.dataset.nodeId)));
    });
    for (const el of edgeEls) {
      const f = parseInt(el.dataset.from), t = parseInt(el.dataset.to);
      el.classList.toggle("dimmed", !(matches.has(f) && matches.has(t)));
    }
  });
})();

function escHtml(s) {
  return s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
}
</script>
</body>
</html>`;
}

/* ── Entry point ──────────────────────────────────────────────────── */

const outputPath = Deno.args[0] || OUTPUT_DEFAULT;
const html = generate();
Deno.writeTextFileSync(outputPath, html);
console.log(`Wrote ${html.length.toLocaleString()} bytes to ${outputPath}`);
