import { green, red, yellow, cyan, bold, dim } from "@std/fmt/colors";
import {
  getBinaryServiceStatus,
  type BinaryServiceName,
  type BinaryServiceStatus,
} from "../binary_services.ts";
import { initRunDir, serviceUrl } from "@garazyk/schemat/runtime";
import type { RegisteredTopologyPreset, TopologyManifest, TopologyManifestV2 } from "@garazyk/schemat";
import { DEFAULT_PORTS, DEFAULT_SERVICE_NAMES } from "@garazyk/schemat";

export type ConnectionType = "firehose" | "xrpc" | "did" | "depends";

const CONNECTION_LABELS: Record<ConnectionType, string> = {
  firehose: "firehose",
  xrpc: "XRPC",
  did: "DID",
  depends: "depends",
};

const ROLE_CONNECTIONS: Record<string, ConnectionType> = {
  "plc→pds": "did",
  "pds→relay": "firehose",
  "relay→appview": "firehose",
  "pds→chat": "xrpc",
  "pds→video": "xrpc",
  "relay→mikrus": "firehose",
  "pds→germ": "xrpc",
  "pds→ui": "xrpc",
  "appview→ui": "xrpc",
  "pds→pds2": "xrpc",
};

function connectionType(from: string, to: string): ConnectionType {
  return ROLE_CONNECTIONS[`${from}→${to}`] ?? "depends";
}

export interface TopologyNode {
  role: string;
  binary: string;
  port: number;
  url: string;
  status: BinaryServiceStatus | null;
  children: { node: TopologyNode; connection: ConnectionType }[];
}

export interface TopologyTree {
  name: string;
  description: string;
  roots: TopologyNode[];
}

const BINARY_SERVICE_NAMES: BinaryServiceName[] = [
  "plc", "pds", "relay", "appview", "chat", "video",
];

const KNOWN_EDGES: [string, string][] = [
  ["plc", "pds"],
  ["pds", "relay"],
  ["relay", "appview"],
  ["pds", "chat"],
  ["pds", "video"],
  ["relay", "mikrus"],
  ["pds", "germ"],
  ["pds", "ui"],
  ["appview", "ui"],
  ["pds", "pds2"],
];

function statusForRole(
  role: string,
  statusMap: Record<string, BinaryServiceStatus>,
): BinaryServiceStatus | null {
  return statusMap[role] ?? null;
}

export async function buildBinaryTopology(): Promise<TopologyTree> {
  const ctx = initRunDir();
  const status = await getBinaryServiceStatus(ctx);

  const nodes = buildTree(BINARY_SERVICE_NAMES, status);
  const runningCount = BINARY_SERVICE_NAMES.filter(
    (r) => status[r]?.running,
  ).length;

  return {
    name: "binary-services",
    description:
      `Local ATProto binary services (${runningCount}/${BINARY_SERVICE_NAMES.length} running)`,
    roots: nodes,
  };
}

export async function buildManifestTopology(
  manifest: TopologyManifest,
): Promise<TopologyTree> {
  const ctx = initRunDir();
  const binStatus = await getBinaryServiceStatus(ctx);
  const manifestRoles = manifest.version === 2
    ? Object.keys(manifest.services)
    : [];
  const roles = manifestRoles.length > 0
    ? manifestRoles
    : Object.keys(manifest.serviceUrls);

  const nodes = buildTree(roles, binStatus, manifest);
  return {
    name: manifest.name,
    description: manifest.description,
    roots: nodes,
  };
}

export async function buildPresetTopology(
  preset: RegisteredTopologyPreset,
): Promise<TopologyTree> {
  const ctx = initRunDir();
  const binStatus = await getBinaryServiceStatus(ctx);
  const roles = Object.keys(preset.roles);

  const nodes = buildTree(roles, binStatus);
  return {
    name: preset.name,
    description: preset.description,
    roots: nodes,
  };
}

function buildTree(
  availableRoles: string[],
  status: Record<string, BinaryServiceStatus>,
  manifest?: TopologyManifest,
): TopologyNode[] {
  const roleSet = new Set(availableRoles);
  const edges = KNOWN_EDGES.filter(([from, to]) =>
    roleSet.has(from) && roleSet.has(to)
  );

  const inbound = new Map<string, string[]>();
  const allNodes = new Set<string>();
  for (const [from, to] of edges) {
    allNodes.add(from);
    allNodes.add(to);
    if (!inbound.has(to)) inbound.set(to, []);
    inbound.get(to)!.push(from);
  }

  for (const role of availableRoles) allNodes.add(role);

  const roots: string[] = [];
  for (const role of allNodes) {
    if (!inbound.has(role) || inbound.get(role)!.length === 0) {
      if (roleSet.has(role)) roots.push(role);
    }
  }

  const children = new Map<string, string[]>();
  for (const [from, to] of edges) {
    if (!children.has(from)) children.set(from, []);
    children.get(from)!.push(to);
  }

  function serviceNameFor(role: string): string {
  const known = DEFAULT_SERVICE_NAMES[role as keyof typeof DEFAULT_SERVICE_NAMES];
  return known ?? `local-${role}`;
}

function portFor(role: string): number {
  const known = DEFAULT_PORTS[role as keyof typeof DEFAULT_PORTS];
  return known ? parseInt(known) : 8080;
}

function buildNode(role: string): TopologyNode {
    const s = statusForRole(role, status);
    const childRoles = children.get(role) ?? [];
    const filteredChildren = childRoles.filter((r) => roleSet.has(r));
    return {
      role,
      binary: manifest?.serviceNames?.[role] ?? serviceNameFor(role),
      port: portFor(role),
      url: manifest?.serviceUrls?.[role] ?? serviceUrl(role),
      status: s,
      children: filteredChildren.map((child) => ({
        node: buildNode(child),
        connection: connectionType(role, child),
      })),
    };
  }

  return roots.map((r) => buildNode(r));
}

function statusIcon(running: boolean, healthy: boolean | undefined): string {
  if (!running) return red("○");
  return healthy ? green("●") : yellow("●");
}

function statusText(running: boolean, healthy: boolean | undefined): string {
  if (!running) return red("Stopped");
  return healthy ? green("Healthy") : yellow("Unhealthy");
}

function roleLabel(role: string): string {
  return cyan(role.toUpperCase());
}

export function renderTree(
  tree: TopologyTree,
  verbose: boolean,
): string[] {
  const lines: string[] = [];
  lines.push(bold(`Active Topology: ${tree.name}`));
  if (tree.description) lines.push(dim(tree.description));
  lines.push(dim("─".repeat(60)));
  lines.push("");

  for (const root of tree.roots) {
    lines.push(formatNodeLine(root, verbose));
    lines.push(...renderChildren(root.children, "  ", verbose));
  }

  return lines;
}

function renderChildren(
  children: { node: TopologyNode; connection: ConnectionType }[],
  prefix: string,
  verbose: boolean,
): string[] {
  const lines: string[] = [];
  for (let i = 0; i < children.length; i++) {
    const { node, connection } = children[i];
    const isLast = i === children.length - 1;
    const connector = isLast ? "└── " : "├── ";
    const childPrefix = prefix + (isLast ? "    " : "│   ");

    const edgeLabel = connection !== "depends"
      ? `${dim("[" + CONNECTION_LABELS[connection] + "]")} `
      : "";

    lines.push(`${prefix}${connector}${edgeLabel}${formatNodeLine(node, verbose)}`);
    lines.push(...renderChildren(node.children, childPrefix, verbose));
  }
  return lines;
}

function formatNodeLine(
  node: TopologyNode,
  verbose: boolean,
): string {
  const label = roleLabel(node.role);
  const bin = dim(`(${node.binary})`);
  const port = dim(`:${node.port}`);

  if (node.status) {
    const icon = statusIcon(node.status.running, node.status.healthy);
    const st = statusText(node.status.running, node.status.healthy);
    const parts = [`${label} ${bin} ${port}  ${icon} ${st}`];
    if (verbose && node.status.pid) {
      parts.push(dim(` [pid ${node.status.pid}]`));
    }
    if (verbose) {
      parts.push(` ${dim(node.url)}`);
    }
    return parts.join("");
  }

  return `${label} ${bin} ${port}  ${dim("○ Unknown")}`;
}

// ---------------------------------------------------------------------------
// Mermaid renderer
// ---------------------------------------------------------------------------

function mermaidStatusLabel(node: TopologyNode): string {
  if (!node.status) return "Unknown";
  if (!node.status.running) return "Stopped";
  return node.status.healthy ? "Healthy" : "Unhealthy";
}

function mermaidStatusEmoji(node: TopologyNode): string {
  if (!node.status) return "○";
  if (!node.status.running) return "○";
  return node.status.healthy ? "●" : "●";
}

function mermaidNodeId(role: string): string {
  return role.toUpperCase().replace(/[^A-Z0-9]/g, "_");
}

function mermaidNodeDef(node: TopologyNode): string {
  const id = mermaidNodeId(node.role);
  const label = `${node.role.toUpperCase()}<br/>${node.binary} :${node.port}<br/>${mermaidStatusEmoji(node)} ${mermaidStatusLabel(node)}`;
  const status = node.status;
  let fill: string;
  let stroke: string;
  if (!status) {
    fill = "#f5f5f5";
    stroke = "#9e9e9e";
  } else if (!status.running) {
    fill = "#ffebee";
    stroke = "#c62828";
  } else if (!status.healthy) {
    fill = "#fff3e0";
    stroke = "#e65100";
  } else {
    fill = "#e8f5e9";
    stroke = "#2e7d32";
  }
  return `${id}["${label}"]\n  style ${id} fill:${fill},stroke:${stroke}`;
}

function collectEdges(
  children: { node: TopologyNode; connection: ConnectionType }[],
  prefix: string,
): { from: string; to: string; label: string }[] {
  const edges: { from: string; to: string; label: string }[] = [];
  for (const child of children) {
    edges.push({
      from: prefix,
      to: mermaidNodeId(child.node.role),
      label: CONNECTION_LABELS[child.connection],
    });
    edges.push(...collectEdges(child.node.children, mermaidNodeId(child.node.role)));
  }
  return edges;
}

export function renderMermaid(tree: TopologyTree): string[] {
  const lines: string[] = [];
  lines.push("graph TB");
  lines.push(`  title ${tree.name}`);

  const allNodes = new Map<string, TopologyNode>();
  function collectNodes(nodes: TopologyNode[]) {
    for (const n of nodes) {
      allNodes.set(mermaidNodeId(n.role), n);
      collectNodes(n.children.map((c) => c.node));
    }
  }
  collectNodes(tree.roots);

  const edges: { from: string; to: string; label: string }[] = [];
  for (const root of tree.roots) {
    edges.push(
      ...collectEdges(root.children, mermaidNodeId(root.role)),
    );
  }

  for (const node of allNodes.values()) {
    lines.push(`  ${mermaidNodeDef(node)}`);
  }

  lines.push("");
  for (const edge of edges) {
    lines.push(`  ${edge.from} -->|${edge.label}| ${edge.to}`);
  }

  return lines;
}

// ---------------------------------------------------------------------------
// DOT (Graphviz) renderer
// ---------------------------------------------------------------------------

function dotNodeId(role: string): string {
  return role.replace(/[^a-zA-Z0-9_]/g, "_");
}

function dotColor(node: TopologyNode): string {
  const status = node.status;
  if (!status) return "#f5f5f5";
  if (!status.running) return "#ffebee";
  if (!status.healthy) return "#fff3e0";
  return "#e8f5e9";
}

function dotNodeDef(node: TopologyNode): string {
  const id = dotNodeId(node.role);
  const status = node.status;
  const label = !status
    ? `${node.role.toUpperCase()}\\n${node.binary} :${node.port}\\n○ Unknown`
    : !status.running
    ? `${node.role.toUpperCase()}\\n${node.binary} :${node.port}\\n○ Stopped`
    : status.healthy
    ? `${node.role.toUpperCase()}\\n${node.binary} :${node.port}\\n● Healthy`
    : `${node.role.toUpperCase()}\\n${node.binary} :${node.port}\\n● Unhealthy`;
  return `  "${id}" [label="${label}", fillcolor="${dotColor(node)}"];`;
}

function collectDotEdges(
  children: { node: TopologyNode; connection: ConnectionType }[],
  parentId: string,
): string[] {
  const edges: string[] = [];
  for (const child of children) {
    const childId = dotNodeId(child.node.role);
    const label = CONNECTION_LABELS[child.connection];
    edges.push(`  "${parentId}" -> "${childId}" [label="${label}"];`);
    edges.push(...collectDotEdges(child.node.children, childId));
  }
  return edges;
}

function collectAllDotNodes(
  nodes: TopologyNode[],
): Map<string, TopologyNode> {
  const map = new Map<string, TopologyNode>();
  for (const n of nodes) {
    map.set(dotNodeId(n.role), n);
    const childMap = collectAllDotNodes(
      n.children.map((c) => c.node),
    );
    for (const [k, v] of childMap) map.set(k, v);
  }
  return map;
}

export function renderDot(tree: TopologyTree): string[] {
  const lines: string[] = [];
  const escapedName = tree.name.replace(/"/g, '\\"');
  lines.push(`digraph "${escapedName}" {`);
  lines.push("  rankdir=TB;");
  lines.push(
    `  graph [label="${tree.description.replace(/"/g, '\\"')}", fontsize=12];`,
  );
  lines.push('  node [shape=box, style="rounded,filled"];');
  lines.push("");

  const allNodes = collectAllDotNodes(tree.roots);
  for (const node of allNodes.values()) {
    lines.push(dotNodeDef(node));
  }

  lines.push("");
  for (const root of tree.roots) {
    const rootId = dotNodeId(root.role);
    lines.push(...collectDotEdges(root.children, rootId));
  }

  lines.push("}");
  return lines;
}

// ---------------------------------------------------------------------------
// LaTeX (TikZ) renderer
// ---------------------------------------------------------------------------

function latexStyle(node: TopologyNode): string {
  const status = node.status;
  if (!status) return "node-unknown";
  if (!status.running) return "node-stopped";
  if (!status.healthy) return "node-unhealthy";
  return "node-healthy";
}

function latexNodeLabel(node: TopologyNode): string {
  const role = node.role.toUpperCase();
  const bin = node.binary;
  const port = node.port;
  const status = node.status;
  if (!status) return `${role}\\\\${bin} :${port}\\\\○ Unknown`;
  if (!status.running) return `${role}\\\\${bin} :${port}\\\\○ Stopped`;
  if (status.healthy) return `${role}\\\\${bin} :${port}\\\\● Healthy`;
  return `${role}\\\\${bin} :${port}\\\\● Unhealthy`;
}

function latexChildLines(
  node: TopologyNode,
  connection: ConnectionType,
  indent: string,
): string[] {
  const lines: string[] = [];
  const edgeLabel = CONNECTION_LABELS[connection];
  lines.push(`${indent}child {`);
  lines.push(`${indent}  node[${latexStyle(node)}] {${latexNodeLabel(node)}}`);
  for (const child of node.children) {
    lines.push(
      ...latexChildLines(child.node, child.connection, indent + "    "),
    );
  }
  lines.push(`${indent}  edge from parent node[midway, font=\\tiny] {${edgeLabel}}`);
  lines.push(`${indent}}`);
  return lines;
}

export function renderLatex(tree: TopologyTree): string[] {
  const lines: string[] = [];

  const desc = tree.description.replace(/&/g, "\\&").replace(/%/g, "\\%")
    .replace(/_/g, "\\_");

  lines.push("%% LaTeX document generated by `hamownia service topology --format latex`");
  lines.push("\\documentclass[tikz,border=5pt]{standalone}");
  lines.push("\\usepackage{tikz}");
  lines.push("\\usetikzlibrary{shapes}");
  lines.push("");
  lines.push("\\tikzstyle{node-healthy}=[rectangle, rounded corners, fill=green!10, draw=green!50!black, text centered, minimum width=2.2cm]");
  lines.push("\\tikzstyle{node-unhealthy}=[rectangle, rounded corners, fill=yellow!10, draw=orange!50!black, text centered, minimum width=2.2cm]");
  lines.push("\\tikzstyle{node-stopped}=[rectangle, rounded corners, fill=red!10, draw=red!50!black, text centered, minimum width=2.2cm]");
  lines.push("\\tikzstyle{node-unknown}=[rectangle, rounded corners, fill=gray!10, draw=gray!50!black, text centered, minimum width=2.2cm]");
  lines.push("");
  lines.push("\\begin{document}");
  lines.push("\\begin{tikzpicture}[");
  lines.push("  every node/.style={font=\\footnotesize},");
  lines.push("  level 1/.style={level distance=2.5cm, sibling distance=8cm},");
  lines.push("  level 2/.style={level distance=2.5cm, sibling distance=5cm},");
  lines.push("  level 3/.style={level distance=2.5cm, sibling distance=3cm},");
  lines.push("  edge from parent/.style={draw, ->, thick},");
  lines.push("  edge from parent path={");
  lines.push("    (\\tikzparentnode.south) -- (\\tikzchildnode.north)");
  lines.push("  },");
  lines.push("]");

  const roots = tree.roots;
  if (roots.length === 1) {
    const root = roots[0];
    lines.push(`  \\node[${latexStyle(root)}] {${latexNodeLabel(root)}}`);
    for (const child of root.children) {
      lines.push(
        ...latexChildLines(child.node, child.connection, "    "),
      );
    }
    lines.push("  ;");
  } else {
    for (let i = 0; i < roots.length; i++) {
      const root = roots[i];
      const pos = i === 0 ? "" : `, right=of ${roots[i - 1].role}`;
      lines.push(`  \\node[${latexStyle(root)}${pos}] (${root.role}) {${latexNodeLabel(root)}};`);
    }
  }

  lines.push("\\end{tikzpicture}");
  lines.push(`\\begin{center}${desc}\\end{center}`);
  lines.push("\\end{document}");

  return lines;
}

// ---------------------------------------------------------------------------
// Output format
// ---------------------------------------------------------------------------

export type OutputFormat = "text" | "mermaid" | "dot" | "latex";

export function renderTopology(
  tree: TopologyTree,
  format: OutputFormat,
  verbose: boolean,
): string[] {
  switch (format) {
    case "mermaid":
      return renderMermaid(tree);
    case "dot":
      return renderDot(tree);
    case "latex":
      return renderLatex(tree);
    default:
      return renderTree(tree, verbose);
  }
}
