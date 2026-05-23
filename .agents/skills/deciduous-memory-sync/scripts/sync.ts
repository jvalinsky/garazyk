#!/usr/bin/env -S deno run -A
/**
 * Bidirectional sync between Letta memory and deciduous decision graph.
 *
 * Usage:
 *   deno run -A sync.ts push    # Letta memory → deciduous
 *   deno run -A sync.ts pull    # deciduous → Letta memory
 *   deno run -A sync.ts status  # Show diff summary (dry run)
 *
 * Push reads $MEMORY_DIR/reference/*.md and $MEMORY_DIR/system/human/preferences.md,
 * extracts structured knowledge, and creates/updates deciduous nodes.
 *
 * Pull reads the deciduous graph and updates Letta memory reference docs
 * with current goal/decision/outcome state.
 */

import { join } from "@std/path";
import { parseArgs } from "@std/cli/parse-args";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const MEMORY_DIR = Deno.env.get("MEMORY_DIR") ??
  `${Deno.env.get("HOME")}/.letta/agents/current/memory`;

const DECIDUOUS = "deciduous";

// Theme for all synced nodes
const SYNC_THEME = "letta-sync";

// ---------------------------------------------------------------------------
// Deciduous CLI helpers
// ---------------------------------------------------------------------------

async function deciduous(...args: string[]): Promise<string> {
  const cmd = new Deno.Command(DECIDUOUS, { args, stdout: "piped", stderr: "piped" });
  const { code, stdout, stderr } = await cmd.output();
  const out = new TextDecoder().decode(stdout).trim();
  const err = new TextDecoder().decode(stderr).trim();
  if (code !== 0 && !err.includes("No nodes found")) {
    console.warn(`deciduous ${args.join(" ")}: ${err}`);
  }
  return out;
}

interface DeciduousNode {
  id: number;
  node_type: string;
  title: string;
  description: string | null;
  status: string;
  metadata_json: string | null;
}

interface DeciduousGraph {
  nodes: DeciduousNode[];
  edges: Array<{
    id: number;
    from_node_id: number;
    to_node_id: number;
    edge_type: string;
    rationale: string | null;
  }>;
}

async function getGraph(): Promise<DeciduousGraph> {
  // Try JSON output first (newer deciduous versions)
  let raw = "";
  try {
    raw = await deciduous("graph");
  } catch {
    // ignore
  }
  if (raw) {
    try {
      return JSON.parse(raw) as DeciduousGraph;
    } catch {
      // not JSON, fall through
    }
  }

  // Fall back to parsing `nodes` and `edges` text output
  const nodeText = await deciduous("nodes");
  const nodes: DeciduousNode[] = [];
  for (const line of nodeText.split("\n")) {
    const match = line.match(/^\s*(\d+)\s+(goal|decision|option|action|outcome|observation)\s+(\S+)\s+(.+)$/);
    if (match) {
      nodes.push({
        id: parseInt(match[1]),
        node_type: match[2],
        title: match[4].trim(),
        description: null,
        status: match[3],
        metadata_json: null,
      });
    }
  }

  const edgeText = await deciduous("edges");
  const edges: DeciduousGraph["edges"] = [];
  for (const line of edgeText.split("\n")) {
    const match = line.match(/^\s*(\d+)\s*─\[([^\]]*)\]\s*→\s*(\d+)/);
    if (match) {
      edges.push({
        id: edges.length + 1,
        from_node_id: parseInt(match[1]),
        to_node_id: parseInt(match[3]),
        edge_type: match[2] || "leads_to",
        rationale: null,
      });
    }
  }

  return { nodes, edges };
}

async function findNodeByTitleCached(title: string): Promise<DeciduousNode | undefined> {
  const graph = await getCachedGraph();
  return graph.nodes.find((n) => n.title === title);
}

async function addNode(
  type: string,
  title: string,
  opts: { description?: string; confidence?: number; branch?: string } = {},
): Promise<number> {
  const args = ["add", type, title];
  if (opts.description) args.push("-d", opts.description);
  if (opts.confidence) args.push("-c", String(opts.confidence));
  if (opts.branch) args.push("-b", opts.branch);
  const out = await deciduous(...args);
  const match = out.match(/Created node (\d+)/);
  if (match) {
    const id = parseInt(match[1]);
    // Tag with sync theme
    await deciduous("tag", "add", String(id), SYNC_THEME);
    graphCache = null; // Invalidate cache after mutation
    return id;
  }
  return -1;
}

async function linkNodes(from: number, to: number, rationale: string, edgeType = "leads_to"): Promise<void> {
  await deciduous("link", String(from), String(to), "-r", rationale, "-t", edgeType);
  graphCache = null; // Invalidate cache after mutation
}

async function updateStatus(id: number, status: string): Promise<void> {
  await deciduous("status", String(id), status);
  graphCache = null; // Invalidate cache after mutation
}

async function ensureTheme(): Promise<void> {
  const themes = await deciduous("themes", "list");
  if (!themes.includes(SYNC_THEME)) {
    await deciduous("themes", "create", SYNC_THEME);
  }
}

// ---------------------------------------------------------------------------
// Memory file helpers
// ---------------------------------------------------------------------------

function readMemoryFile(relPath: string): string {
  const absPath = join(MEMORY_DIR, relPath);
  try {
    return Deno.readTextFileSync(absPath);
  } catch {
    return "";
  }
}

function writeMemoryFile(relPath: string, content: string): void {
  const absPath = join(MEMORY_DIR, relPath);
  Deno.mkdirSync(join(absPath, ".."), { recursive: true });
  Deno.writeTextFileSync(absPath, content);
}

// ---------------------------------------------------------------------------
// Knowledge extraction from memory
// ---------------------------------------------------------------------------

interface ExtractedKnowledge {
  goals: Array<{ title: string; description: string; status: string; childDecisions: string[] }>;
  decisions: Array<{ title: string; description: string; status: string; parentGoal?: string }>;
  outcomes: Array<{ title: string; description: string; status: string }>;
  referenceDocs: Array<{ path: string; description: string }>;
}

function extractFromPreferences(md: string): ExtractedKnowledge {
  const result: ExtractedKnowledge = { goals: [], decisions: [], outcomes: [], referenceDocs: [] };

  // Parse section by section: "### Title (status)" followed by bullet points
  const sections = md.split(/(?=### )/);
  for (const section of sections) {
    const headerMatch = section.match(/### (.+?) \((completed|in progress|pending)\)/);
    if (!headerMatch) continue;

    const goalTitle = headerMatch[1].trim();
    const goalStatus = headerMatch[2].trim() === "completed" ? "completed"
      : headerMatch[2].trim() === "in progress" ? "active"
      : "pending";

    // Extract phase/action bullets under this section
    const childDecisions: string[] = [];
    const phaseRegex = /- \*\*(?:Phase \d+(?:\s*\(\w+\))?|P\d+)\*\*: (.+)/g;
    let match;
    while ((match = phaseRegex.exec(section)) !== null) {
      const decTitle = match[1].trim();
      childDecisions.push(decTitle);
      result.decisions.push({
        title: decTitle,
        description: `From Letta memory: ${goalTitle}`,
        status: "completed",
        parentGoal: goalTitle,
      });
    }

    // Also extract "- **Category X**: ..." patterns
    const catRegex = /- \*\*Category (\w+)\*\*: (.+)/g;
    while ((match = catRegex.exec(section)) !== null) {
      const decTitle = `Category ${match[1]}: ${match[2].trim()}`;
      childDecisions.push(decTitle);
      result.decisions.push({
        title: decTitle,
        description: `From Letta memory: ${goalTitle}`,
        status: "completed",
        parentGoal: goalTitle,
      });
    }

    result.goals.push({
      title: goalTitle,
      description: `From Letta memory: ${goalTitle}`,
      status: goalStatus,
      childDecisions,
    });
  }

  return result;
}

function extractFromReferenceDoc(path: string, md: string): ExtractedKnowledge {
  const result: ExtractedKnowledge = { goals: [], decisions: [], outcomes: [], referenceDocs: [] };

  // Extract from markdown headers
  const headerRegex = /^## (.+)$/gm;
  let match;
  while ((match = headerRegex.exec(md)) !== null) {
    const title = match[1].trim();
    if (title.toLowerCase().includes("problem") || title.toLowerCase().includes("remaining")) {
      result.goals.push({ title, description: `From reference doc: ${path}`, status: "pending", childDecisions: [] });
    } else if (title.toLowerCase().includes("remediation") || title.toLowerCase().includes("fix") ||
               title.toLowerCase().includes("change")) {
      result.decisions.push({ title, description: `From reference doc: ${path}`, status: "completed" });
    }
  }

  // Extract from "### Category X: ..." patterns
  const catRegex = /### Category (\w+): (.+?) — (.+)/g;
  while ((match = catRegex.exec(md)) !== null) {
    const cat = match[1];
    const title = match[2].trim();
    const action = match[3].trim();
    result.decisions.push({
      title: `Category ${cat}: ${title}`,
      description: action,
      status: action.toLowerCase().includes("pending") ? "pending" : "completed",
    });
  }

  // Extract from priority tables
  const priorityRegex = /\|\s*\*\*P(\d+)\*\*\s*\|(.+?)\|(.+?)\|/g;
  while ((match = priorityRegex.exec(md)) !== null) {
    const title = match[2].trim();
    const action = match[3].trim();
    result.goals.push({
      title: `P${match[1]}: ${title}`,
      description: action,
      status: "pending",
      childDecisions: [],
    });
  }

  result.referenceDocs.push({ path, description: `Reference doc synced from Letta memory` });
  return result;
}

// ---------------------------------------------------------------------------
// Push: Letta memory → deciduous
// ---------------------------------------------------------------------------

async function push(dryRun = false): Promise<void> {
  await ensureTheme();
  console.log("=== Push: Letta memory → deciduous ===\n");

  // 1. Extract from preferences
  const prefs = readMemoryFile("system/human/preferences.md");
  const prefsKnowledge = extractFromPreferences(prefs);

  // 2. Extract from reference docs
  const refKnowledge: ExtractedKnowledge = { goals: [], decisions: [], outcomes: [], referenceDocs: [] };
  for (const refFile of findReferenceFiles()) {
    const content = readMemoryFile(refFile);
    const extracted = extractFromReferenceDoc(refFile, content);
    mergeKnowledge(refKnowledge, extracted);
  }

  // 3. Combine
  const allKnowledge = mergeKnowledge(prefsKnowledge, refKnowledge);

  // 4. Sync to deciduous
  let created = 0;
  let updated = 0;
  let skipped = 0;

  // Track created node IDs for linking
  const goalNodeIdMap = new Map<string, number>();

  for (const goal of allKnowledge.goals) {
    const existing = await findNodeByTitleCached(goal.title);
    if (existing) {
      goalNodeIdMap.set(goal.title, existing.id);
      if (existing.status !== goal.status && goal.status !== "pending") {
        if (!dryRun) await updateStatus(existing.id, goal.status);
        console.log(`  ✓ Updated status: [${existing.id}] ${goal.title} → ${goal.status}`);
        updated++;
      } else {
        skipped++;
      }
    } else {
      if (!dryRun) {
        const id = await addNode("goal", goal.title, {
          description: goal.description,
          confidence: 80,
        });
        goalNodeIdMap.set(goal.title, id);
        console.log(`  + Created goal: [${id}] ${goal.title}`);
      } else {
        console.log(`  + Would create goal: ${goal.title}`);
      }
      created++;
    }
  }

  for (const decision of allKnowledge.decisions) {
    const existing = await findNodeByTitleCached(decision.title);
    if (existing) {
      // Check if we need to link to parent goal
      if (decision.parentGoal && !dryRun) {
        const parentId = goalNodeIdMap.get(decision.parentGoal);
        if (parentId) {
          // Check if edge already exists
          const graph = await getCachedGraph();
          const edgeExists = graph.edges.some(
            (e) => e.from_node_id === parentId && e.to_node_id === existing.id,
          );
          if (!edgeExists) {
            await linkNodes(parentId, existing.id, "decision under this goal");
            console.log(`  ↔ Linked goal [${parentId}] → decision [${existing.id}]`);
          }
        }
      }
      skipped++;
    } else {
      if (!dryRun) {
        const id = await addNode("decision", decision.title, {
          description: decision.description,
          confidence: 85,
        });
        console.log(`  + Created decision: [${id}] ${decision.title}`);

        // Link to parent goal if known
        if (decision.parentGoal) {
          const parentId = goalNodeIdMap.get(decision.parentGoal);
          if (parentId) {
            await linkNodes(parentId, id, "decision under this goal");
            console.log(`  ↔ Linked goal [${parentId}] → decision [${id}]`);
          }
        }
      } else {
        console.log(`  + Would create decision: ${decision.title}`);
      }
      created++;
    }
  }

  for (const outcome of allKnowledge.outcomes) {
    const existing = await findNodeByTitleCached(outcome.title);
    if (existing) {
      skipped++;
    } else {
      if (!dryRun) {
        const id = await addNode("outcome", outcome.title, {
          description: outcome.description,
          confidence: 90,
        });
        console.log(`  + Created outcome: [${id}] ${outcome.title}`);
      } else {
        console.log(`  + Would create outcome: ${outcome.title}`);
      }
      created++;
    }
  }

  // 5. Attach reference docs to relevant nodes
  for (const ref of allKnowledge.referenceDocs) {
    if (!dryRun) {
      // Find nodes that mention the reference doc topic
      const graph = await getCachedGraph();
      const topic = ref.path.replace("reference/", "").replace(".md", "").replace(/[-_]/g, " ");
      for (const node of graph.nodes) {
        if (node.title.toLowerCase().includes(topic.split("/").pop()!.toLowerCase()) ||
            (node.description && node.description.toLowerCase().includes(topic.split("/").pop()!.toLowerCase()))) {
          try {
            const absPath = join(MEMORY_DIR, ref.path);
            await deciduous("doc", "attach", String(node.id), absPath, "-d", ref.description);
            console.log(`  📎 Attached ${ref.path} to node [${node.id}]`);
          } catch {
            // attachment may already exist
          }
        }
      }
    }
  }

  console.log(`\nPush summary: ${created} created, ${updated} updated, ${skipped} skipped`);
}

// ---------------------------------------------------------------------------
// Pull: deciduous → Letta memory
// ---------------------------------------------------------------------------

async function pull(dryRun = false): Promise<void> {
  console.log("=== Pull: deciduous → Letta memory ===\n");

  const graph = await getCachedGraph();

  // 1. Build a summary of active/completed goals and decisions
  const activeGoals = graph.nodes.filter(
    (n) => n.node_type === "goal" && (n.status === "active" || n.status === "pending"),
  );
  const completedGoals = graph.nodes.filter(
    (n) => n.node_type === "goal" && n.status === "completed",
  );
  const recentDecisions = graph.nodes.filter(
    (n) => n.node_type === "decision",
  ).slice(-20);
  const recentOutcomes = graph.nodes.filter(
    (n) => n.node_type === "outcome",
  ).slice(-10);

  // 2. Generate a reference doc with the current graph state
  const lines: string[] = [
    "---",
    "description: Current deciduous decision graph state synced from the project. Auto-generated by deciduous-memory-sync skill.",
    "---",
    "",
    `# Deciduous Graph State`,
    "",
    `**Last synced**: ${new Date().toISOString()}`,
    `**Total nodes**: ${graph.nodes.length}`,
    `**Total edges**: ${graph.edges.length}`,
    "",
    "## Active Goals",
    "",
  ];

  if (activeGoals.length === 0) {
    lines.push("No active goals.");
  } else {
    for (const g of activeGoals) {
      lines.push(`- [${g.id}] **${g.title}** ${g.description ? `— ${g.description.slice(0, 100)}` : ""}`);
      // Find linked decisions
      const linked = graph.edges.filter((e) => e.from_node_id === g.id);
      for (const edge of linked) {
        const target = graph.nodes.find((n) => n.id === edge.to_node_id);
        if (target && target.node_type === "decision") {
          lines.push(`  - Decision: [${target.id}] ${target.title} (${target.status})`);
        }
      }
    }
  }

  lines.push("", "## Recent Decisions", "");
  for (const d of recentDecisions) {
    lines.push(`- [${d.id}] **${d.title}** (${d.status})`);
  }

  lines.push("", "## Recent Outcomes", "");
  for (const o of recentOutcomes) {
    lines.push(`- [${o.id}] **${o.title}** (${o.status})`);
  }

  lines.push("", "## Completed Goals", "");
  for (const g of completedGoals.slice(-10)) {
    lines.push(`- [${g.id}] ${g.title}`);
  }

  if (!dryRun) {
    writeMemoryFile("reference/deciduous-graph-state.md", lines.join("\n") + "\n");
    console.log("  ✓ Updated reference/deciduous-graph-state.md");
  } else {
    console.log("  Would update reference/deciduous-graph-state.md");
    console.log(`  (${activeGoals.length} active goals, ${recentDecisions.length} recent decisions, ${recentOutcomes.length} recent outcomes)`);
  }

  // 3. Generate a pulse summary
  const pulseOut = await deciduous("pulse", "--summary");
  if (pulseOut && !dryRun) {
    writeMemoryFile("reference/deciduous-pulse.md", [
      "---",
      "description: Deciduous pulse summary — active state, gaps, and health of the decision graph. Auto-generated.",
      "---",
      "",
      "# Deciduous Pulse",
      "",
      `**Generated**: ${new Date().toISOString()}`,
      "",
      "```",
      pulseOut,
      "```",
      "",
    ].join("\n") + "\n");
    console.log("  ✓ Updated reference/deciduous-pulse.md");
  }

  console.log("\nPull complete.");
}

// ---------------------------------------------------------------------------
// Status: dry-run comparison
// ---------------------------------------------------------------------------

async function status(): Promise<void> {
  console.log("=== Sync Status ===\n");

  const prefs = readMemoryFile("system/human/preferences.md");
  const prefsKnowledge = extractFromPreferences(prefs);

  const graph = await getCachedGraph();
  const syncedNodes = graph.nodes; // In a full impl, filter by SYNC_THEME tag

  let newInMemory = 0;
  let alreadySynced = 0;

  for (const goal of prefsKnowledge.goals) {
    const existing = syncedNodes.find((n) => n.title === goal.title);
    if (existing) {
      alreadySynced++;
    } else {
      console.log(`  [new] goal: ${goal.title}`);
      newInMemory++;
    }
  }

  for (const decision of prefsKnowledge.decisions) {
    const existing = syncedNodes.find((n) => n.title === decision.title);
    if (existing) {
      alreadySynced++;
    } else {
      console.log(`  [new] decision: ${decision.title}`);
      newInMemory++;
    }
  }

  console.log(`\nMemory knowledge: ${prefsKnowledge.goals.length + prefsKnowledge.decisions.length} items`);
  console.log(`Already in deciduous: ${alreadySynced}`);
  console.log(`New (would be created): ${newInMemory}`);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function findReferenceFiles(): string[] {
  const refDir = join(MEMORY_DIR, "reference");
  const files: string[] = [];
  try {
    for (const entry of Deno.readDirSync(refDir)) {
      if (entry.isFile && entry.name.endsWith(".md")) {
        files.push(`reference/${entry.name}`);
      }
    }
  } catch {
    // reference dir may not exist
  }
  return files;
}

function mergeKnowledge(a: ExtractedKnowledge, b: ExtractedKnowledge): ExtractedKnowledge {
  return {
    goals: [...a.goals, ...b.goals],
    decisions: [...a.decisions, ...b.decisions],
    outcomes: [...a.outcomes, ...b.outcomes],
    referenceDocs: [...a.referenceDocs, ...b.referenceDocs],
  };
}

// Cache the graph to avoid repeated CLI calls
let graphCache: DeciduousGraph | null = null;

async function getCachedGraph(): Promise<DeciduousGraph> {
  if (!graphCache) {
    graphCache = await getGraph();
  }
  return graphCache;
}

async function findNodeByTitleCachedCached(title: string): Promise<DeciduousNode | undefined> {
  const graph = await getCachedGraph();
  return graph.nodes.find((n) => n.title === title);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const args = parseArgs(Deno.args, {
  boolean: ["dry-run"],
  alias: { "dry-run": "d" },
});

const command = args._[0] as string;

switch (command) {
  case "push":
    await push(args["dry-run"]);
    break;
  case "pull":
    await pull(args["dry-run"]);
    break;
  case "status":
    await status();
    break;
  default:
    console.log("Usage: deno run -A sync.ts <push|pull|status> [--dry-run]");
    console.log("");
    console.log("  push    Letta memory → deciduous (create/update nodes from memory files)");
    console.log("  pull    deciduous → Letta memory (update reference docs from graph state)");
    console.log("  status  Show what would be synced (dry run)");
    Deno.exit(1);
}
