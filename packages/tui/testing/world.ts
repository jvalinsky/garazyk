/**
 * Shared TuiWorld JSON contract and deterministic query helpers.
 *
 * This mirrors the PTY-side world shape without importing the Node/MJS
 * implementation from Deno package code.
 *
 * @module tui/testing/world
 */

export interface TuiRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface TuiEvidence {
  source: string;
  index: number | string;
  kind: string;
  text?: string;
  bounds?: unknown;
}

export interface TuiNode {
  id: string;
  ref: string;
  source: string;
  sourceIndex: number | string;
  domain: string;
  role: string;
  label?: string;
  bounds: TuiRect;
  boundsAccuracy: "exact" | "row" | "estimated";
  state: Record<string, unknown>;
  confidence: number;
  evidence: TuiEvidence[];
}

export interface TuiEdge {
  id: string;
  kind: string;
  from: string;
  to: string;
  confidence: number;
  evidence?: TuiEvidence[];
}

export interface TuiAction {
  id: string;
  kind: string;
  key?: string;
  label?: string;
  source?: string;
  sourceRef?: string;
  targetRef?: string;
  confidence: number;
}

export interface TuiDiagnostic {
  id: string;
  severity: "info" | "warning" | "error";
  code: string;
  message: string;
  refs?: string[];
}

export interface TuiWorld {
  frameId: string;
  viewport: { width: number; height: number };
  sources: Array<{ id: string; kind: string; count: number }>;
  nodes: TuiNode[];
  edges: TuiEdge[];
  actions: TuiAction[];
  diagnostics: TuiDiagnostic[];
}

export interface WorldElementInput {
  ref?: string;
  source?: string;
  sourceIndex?: number | string;
  domain?: string;
  role: string;
  label?: string;
  content?: string;
  bounds: {
    x: number;
    y: number;
    width?: number;
    height?: number;
    w?: number;
    h?: number;
  };
  state?: Record<string, unknown>;
  actions?: Array<string | Partial<TuiAction>>;
  confidence?: number;
  evidence?: TuiEvidence[];
}

export interface WorldQuery {
  op: string;
  detail?: "compact" | "full";
  ref?: string;
  role?: string;
  name?: string | RegExp;
  text?: string | RegExp;
  exact?: boolean;
  domain?: string;
  source?: string;
  kind?: string;
  direction?: "in" | "out" | "both" | "above" | "below" | "leftOf" | "rightOf";
  strict?: boolean;
  selected?: boolean;
  focused?: boolean;
  visible?: boolean;
  minConfidence?: number;
  includeSource?: boolean;
  includeTarget?: boolean;
  intent?: string;
}

/** Compact or full rendering of a {@link TuiNode} for query results. */
export type NodeSummary = TuiNode | Record<string, unknown> | null;

/** Compact or full rendering of a {@link TuiEdge} for query results. */
export type EdgeSummary = TuiEdge | {
  id: string;
  kind: string;
  from: string;
  to: string;
  confidence: number;
};

/** Compact or full rendering of a {@link TuiAction} for query results. */
export type ActionSummary = TuiAction | {
  id: string;
  kind: string;
  key?: string;
  label?: string;
  source?: string;
  sourceRef?: string;
  targetRef?: string;
  confidence: number;
} | null;

const NON_INTERACTIVE_ROLES = new Set([
  "screen",
  "cursor",
  "empty_space",
  "fact",
]);
const DETAIL_FIELDS = [
  "id",
  "ref",
  "source",
  "domain",
  "role",
  "label",
  "bounds",
  "boundsAccuracy",
  "state",
  "confidence",
] as const;

function slug(value: unknown): string {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 48) || "node";
}

function uniqueValue(base: string, used: Set<string>): string {
  let value = base;
  let i = 2;
  while (used.has(value)) {
    value = `${base}_${i}`;
    i += 1;
  }
  used.add(value);
  return value;
}

function clamp(value: number, min: number, max: number): number {
  if (max < min) return min;
  return Math.min(max, Math.max(min, value));
}

export function toWorldRect(
  bounds: WorldElementInput["bounds"],
  viewport: TuiWorld["viewport"],
): TuiRect {
  const rawX = Number.isFinite(bounds.x) ? bounds.x : 0;
  const rawY = Number.isFinite(bounds.y) ? bounds.y : 0;
  const x = clamp(rawX, 0, viewport.width - 1);
  const y = clamp(rawY, 0, viewport.height - 1);
  const rawW = Number.isFinite(bounds.w) ? bounds.w! : bounds.width ?? 1;
  const rawH = Number.isFinite(bounds.h) ? bounds.h! : bounds.height ?? 1;
  return {
    x,
    y,
    w: Math.max(1, Math.min(rawW, viewport.width - x)),
    h: Math.max(1, Math.min(rawH, viewport.height - y)),
  };
}

export function rectContains(
  parent: TuiRect,
  child: TuiRect,
  padding = 0,
): boolean {
  return child.x >= parent.x - padding &&
    child.y >= parent.y - padding &&
    child.x + child.w <= parent.x + parent.w + padding &&
    child.y + child.h <= parent.y + parent.h + padding;
}

export function rectOverlaps(a: TuiRect, b: TuiRect): boolean {
  return a.x < b.x + b.w &&
    a.x + a.w > b.x &&
    a.y < b.y + b.h &&
    a.y + a.h > b.y;
}

function rectArea(rect: TuiRect): number {
  return rect.w * rect.h;
}

function rectCenter(rect: TuiRect): { x: number; y: number } {
  return {
    x: rect.x + (rect.w - 1) / 2,
    y: rect.y + (rect.h - 1) / 2,
  };
}

function rectRight(rect: TuiRect): number {
  return rect.x + rect.w;
}

function rectBottom(rect: TuiRect): number {
  return rect.y + rect.h;
}

function intervalsOverlap(
  aStart: number,
  aEnd: number,
  bStart: number,
  bEnd: number,
): boolean {
  return aStart < bEnd && aEnd > bStart;
}

function horizontalBandsOverlap(a: TuiRect, b: TuiRect): boolean {
  return intervalsOverlap(a.x, rectRight(a), b.x, rectRight(b));
}

function verticalBandsOverlap(a: TuiRect, b: TuiRect): boolean {
  return intervalsOverlap(a.y, rectBottom(a), b.y, rectBottom(b));
}

function inferDomain(role: string): string {
  if (role === "table") return "table";
  if (
    role === "button" || role === "checkbox" || role === "radio" ||
    role === "input"
  ) return "form";
  if (role === "progressBar" || role === "progress") return "chart";
  return "generic";
}

function actionFromElement(
  world: TuiWorld,
  input: WorldElementInput,
  node: TuiNode,
  action: string | Partial<TuiAction>,
): void {
  const rawKind = typeof action === "string" ? action : action.kind;
  const kind = rawKind === "click" || rawKind === "enter" || rawKind === "space"
    ? "activate"
    : rawKind || "activate";
  const key = typeof action === "string"
    ? action === "click" || action === "enter" ? "enter" : action
    : action.key ?? (kind === "activate" ? "enter" : undefined);
  world.actions.push({
    id: `a_${world.actions.length + 1}`,
    kind,
    key,
    label: typeof action === "string"
      ? input.label ?? input.content ?? kind
      : action.label ?? input.label,
    source: typeof action === "string" ? "element" : action.source ?? "element",
    targetRef: node.ref,
    sourceRef: typeof action === "string" ? undefined : action.sourceRef,
    confidence: typeof action === "string"
      ? node.confidence
      : action.confidence ?? node.confidence,
  });
}

export function buildTuiWorldFromElements(options: {
  frameId: string;
  viewport: TuiWorld["viewport"];
  sourceId?: string;
  elements: WorldElementInput[];
}): TuiWorld {
  const sourceId = options.sourceId ?? "metadata:tui";
  const world: TuiWorld = {
    frameId: options.frameId,
    viewport: options.viewport,
    sources: [
      { id: "terminal:viewport", kind: "terminal", count: 1 },
      { id: sourceId, kind: "metadata", count: options.elements.length },
    ],
    nodes: [],
    edges: [],
    actions: [],
    diagnostics: [],
  };
  const usedIds = new Set<string>();
  const usedRefs = new Set<string>();

  const addNode = (
    node: Omit<TuiNode, "id" | "ref"> & { id?: string; ref?: string },
  ): TuiNode => {
    const idBase = node.id ||
      `n_${slug(node.source)}_${slug(node.sourceIndex)}_${slug(node.role)}`;
    const refBase = node.ref ||
      `${slug(node.domain)}:${slug(node.role)}:${
        slug(node.label || node.sourceIndex)
      }:${node.bounds.x},${node.bounds.y}`;
    const complete: TuiNode = {
      ...node,
      id: uniqueValue(idBase, usedIds),
      ref: uniqueValue(refBase, usedRefs),
    };
    world.nodes.push(complete);
    return complete;
  };

  addNode({
    source: "terminal:viewport",
    sourceIndex: 0,
    domain: "generic",
    role: "screen",
    label: "screen",
    bounds: {
      x: 0,
      y: 0,
      w: options.viewport.width,
      h: options.viewport.height,
    },
    boundsAccuracy: "exact",
    state: {},
    confidence: 1,
    evidence: [{
      source: "terminal:viewport",
      index: 0,
      kind: "terminal",
      text: "",
    }],
  });

  options.elements.forEach((input, index) => {
    const source = input.source ?? sourceId;
    const sourceIndex = input.sourceIndex ?? index;
    const label = input.label ?? input.content ?? input.role;
    const node = addNode({
      id: input.ref ? `n_${slug(input.ref)}` : undefined,
      ref: input.ref,
      source,
      sourceIndex,
      domain: input.domain ?? inferDomain(input.role),
      role: input.role,
      label,
      bounds: toWorldRect(input.bounds, options.viewport),
      boundsAccuracy: "exact",
      state: input.state ?? {},
      confidence: Math.max(0, Math.min(1, input.confidence ?? 0.9)),
      evidence: input.evidence ?? [{
        source,
        index: sourceIndex,
        kind: "metadata",
        text: label,
        bounds: input.bounds,
      }],
    });
    for (const action of input.actions ?? []) {
      actionFromElement(world, input, node, action);
    }
  });

  buildSpatialRelations(world);
  world.diagnostics.push(...validate(world));
  return world;
}

export function buildSpatialRelations(world: TuiWorld): TuiEdge[] {
  const nodes = world.nodes.filter((node) => node.role !== "screen");
  const screen = world.nodes.find((node) => node.role === "screen");

  const addEdge = (
    kind: string,
    from: TuiNode,
    to: TuiNode,
    confidence: number,
  ) => {
    if (from.id === to.id) return;
    if (
      world.edges.some((edge) =>
        edge.kind === kind && edge.from === from.id && edge.to === to.id
      )
    ) return;
    world.edges.push({
      id: `e_${world.edges.length + 1}`,
      kind,
      from: from.id,
      to: to.id,
      confidence,
      evidence: to.evidence,
    });
  };

  for (const node of nodes) {
    let parent = screen;
    let parentArea = screen ? rectArea(screen.bounds) : Infinity;
    for (const candidate of nodes) {
      if (candidate.id === node.id) continue;
      const candidateArea = rectArea(candidate.bounds);
      if (candidateArea <= rectArea(node.bounds)) continue;
      if (!rectContains(candidate.bounds, node.bounds)) continue;
      if (candidateArea < parentArea) {
        parent = candidate;
        parentArea = candidateArea;
      }
    }
    if (parent) addEdge("contains", parent, node, 0.9);
  }

  for (let i = 0; i < nodes.length; i += 1) {
    const a = nodes[i]!;
    for (let j = i + 1; j < nodes.length; j += 1) {
      const b = nodes[j]!;
      if (!rectOverlaps(a.bounds, b.bounds)) continue;
      if (
        rectContains(a.bounds, b.bounds) || rectContains(b.bounds, a.bounds)
      ) continue;
      addEdge("overlaps", a, b, 0.65);
    }
  }

  for (let i = 0; i < nodes.length; i += 1) {
    const a = nodes[i]!;
    for (let j = i + 1; j < nodes.length; j += 1) {
      const b = nodes[j]!;
      const sameRow = verticalBandsOverlap(a.bounds, b.bounds);
      const sameColumn = horizontalBandsOverlap(a.bounds, b.bounds);

      if (sameRow) {
        addEdge("sameRow", a, b, 0.72);
        addEdge("sameRow", b, a, 0.72);
      }
      if (sameColumn) {
        addEdge("sameColumn", a, b, 0.72);
        addEdge("sameColumn", b, a, 0.72);
      }
      if (sameRow && rectRight(a.bounds) <= b.bounds.x) {
        addEdge("leftOf", a, b, 0.75);
        addEdge("rightOf", b, a, 0.75);
      } else if (sameRow && rectRight(b.bounds) <= a.bounds.x) {
        addEdge("leftOf", b, a, 0.75);
        addEdge("rightOf", a, b, 0.75);
      }
      if (sameColumn && rectBottom(a.bounds) <= b.bounds.y) {
        addEdge("above", a, b, 0.75);
        addEdge("below", b, a, 0.75);
      } else if (sameColumn && rectBottom(b.bounds) <= a.bounds.y) {
        addEdge("above", b, a, 0.75);
        addEdge("below", a, b, 0.75);
      }
    }
  }

  return world.edges;
}

function matchName(label: unknown, name: unknown, exact = false): boolean {
  if (name === undefined || name === null) return true;
  const value = String(label ?? "");
  if (name instanceof RegExp) return name.test(value);
  if (exact) return value.toLowerCase() === String(name).toLowerCase();
  return value.toLowerCase().includes(String(name).toLowerCase());
}

function isHidden(node: TuiNode): boolean {
  return node.state.hidden === true || node.state.visible === false;
}

function getNodeByRef(world: TuiWorld, ref: string): TuiNode | undefined {
  return world.nodes.find((node) => node.ref === ref || node.id === ref);
}

function queryError(
  code: string,
  message: string,
  extra: Record<string, unknown> = {},
): Error {
  const error = new Error(message);
  Object.assign(error, { code }, extra);
  return error;
}

function nodeSummary(
  node: TuiNode | null | undefined,
  detail: "compact" | "full" = "compact",
): NodeSummary {
  if (!node) return null;
  if (detail === "full") return node;
  const summary: Record<string, unknown> = {};
  for (const key of DETAIL_FIELDS) {
    if (key === "state" && Object.keys(node.state).length === 0) continue;
    summary[key] = node[key];
  }
  return summary;
}

function edgeSummary(
  edge: TuiEdge,
  world: TuiWorld,
  detail: "compact" | "full" = "compact",
): EdgeSummary {
  if (detail === "full") return edge;
  const from = world.nodes.find((node) => node.id === edge.from);
  const to = world.nodes.find((node) => node.id === edge.to);
  return {
    id: edge.id,
    kind: edge.kind,
    from: from?.ref ?? edge.from,
    to: to?.ref ?? edge.to,
    confidence: edge.confidence,
  };
}

function actionSummary(
  action: TuiAction | undefined | null,
  detail: "compact" | "full" = "compact",
): ActionSummary {
  if (!action) return null;
  if (detail === "full") return action;
  return {
    id: action.id,
    kind: action.kind,
    key: action.key,
    label: action.label,
    source: action.source,
    sourceRef: action.sourceRef,
    targetRef: action.targetRef,
    confidence: action.confidence,
  };
}

export function findNodes(
  world: TuiWorld,
  options: Partial<WorldQuery> = {},
): TuiNode[] {
  return world.nodes.filter((node) => {
    if (options.role && node.role !== options.role) return false;
    if (options.domain && node.domain !== options.domain) return false;
    if (options.source && node.source !== options.source) return false;
    if (
      options.minConfidence !== undefined &&
      node.confidence < options.minConfidence
    ) {
      return false;
    }
    if (
      options.name !== undefined &&
      !matchName(node.label, options.name, options.exact === true)
    ) {
      return false;
    }
    if (
      options.text !== undefined &&
      !matchName(node.label, options.text, options.exact === true)
    ) {
      return false;
    }
    if (
      options.selected !== undefined && node.state.selected !== options.selected
    ) return false;
    if (
      options.focused !== undefined && node.state.focused !== options.focused
    ) return false;
    if (options.visible && (node.role === "screen" || isHidden(node))) {
      return false;
    }
    return true;
  });
}

export function getByRef(world: TuiWorld, ref: string): TuiNode {
  const node = getNodeByRef(world, ref);
  if (!node) {
    throw queryError("not_found", `No TuiWorld node found for ref: ${ref}`, {
      ref,
    });
  }
  return node;
}

export function getByRole(
  world: TuiWorld,
  role: string,
  options: Partial<WorldQuery> = {},
): TuiNode | TuiNode[] {
  const strict = options.strict !== false;
  const matches = findNodes(world, { ...options, role });
  if (matches.length === 0) {
    throw queryError("not_found", `No TuiWorld node found for role "${role}"`, {
      role,
      name: options.name,
    });
  }
  if (strict && matches.length > 1) {
    throw queryError("ambiguous", `Ambiguous TuiWorld role "${role}"`, {
      role,
      name: options.name,
      candidates: matches.map((node) => nodeSummary(node)),
    });
  }
  return strict ? matches[0]! : matches;
}

export function related(
  world: TuiWorld,
  ref: string,
  options: Partial<WorldQuery> = {},
): Array<{ edge: TuiEdge; node: TuiNode }> {
  const node = getByRef(world, ref);
  const direction = options.direction ?? "both";
  return world.edges
    .filter((edge) => !options.kind || edge.kind === options.kind)
    .filter((edge) => {
      if (direction === "out") return edge.from === node.id;
      if (direction === "in") return edge.to === node.id;
      return edge.from === node.id || edge.to === node.id;
    })
    .map((edge) => {
      const otherId = edge.from === node.id ? edge.to : edge.from;
      return {
        edge,
        node: world.nodes.find((candidate) => candidate.id === otherId),
      };
    })
    .filter((entry): entry is { edge: TuiEdge; node: TuiNode } => !!entry.node)
    .filter((entry) => !options.role || entry.node.role === options.role);
}

export function nearest(
  world: TuiWorld,
  ref: string,
  options: Partial<WorldQuery> = {},
): TuiNode | null {
  const node = getByRef(world, ref);
  const center = rectCenter(node.bounds);
  const candidates = world.nodes.filter((candidate) => {
    if (
      candidate.id === node.id || candidate.role === "screen" ||
      candidate.role === "cursor"
    ) return false;
    if (options.role && candidate.role !== options.role) return false;
    if (options.domain && candidate.domain !== options.domain) return false;
    const candidateCenter = rectCenter(candidate.bounds);
    if (options.direction === "below") return candidateCenter.y > center.y;
    if (options.direction === "above") return candidateCenter.y < center.y;
    if (options.direction === "rightOf") return candidateCenter.x > center.x;
    if (options.direction === "leftOf") return candidateCenter.x < center.x;
    return true;
  });
  return candidates
    .map((candidate) => {
      const candidateCenter = rectCenter(candidate.bounds);
      const dx = Math.abs(candidateCenter.x - center.x);
      const dy = Math.abs(candidateCenter.y - center.y);
      const primary =
        options.direction === "above" || options.direction === "below"
          ? dy
          : dx;
      const secondary =
        options.direction === "above" || options.direction === "below"
          ? dx
          : dy;
      return { candidate, score: primary * 10 + secondary };
    })
    .sort((a, b) => {
      const scoreDelta = a.score - b.score;
      if (scoreDelta !== 0) return scoreDelta;
      const confidenceDelta = b.candidate.confidence - a.candidate.confidence;
      if (confidenceDelta !== 0) return confidenceDelta;
      const yDelta = a.candidate.bounds.y - b.candidate.bounds.y;
      if (yDelta !== 0) return yDelta;
      const xDelta = a.candidate.bounds.x - b.candidate.bounds.x;
      if (xDelta !== 0) return xDelta;
      return a.candidate.ref.localeCompare(b.candidate.ref);
    })[0]?.candidate ?? null;
}

export function actionsFor(
  world: TuiWorld,
  ref: string,
  options: Partial<WorldQuery> = {},
): TuiAction[] {
  const node = getByRef(world, ref);
  const includeSource = options.includeSource !== false;
  const includeTarget = options.includeTarget !== false;
  return world.actions.filter((action) => {
    if (options.kind && action.kind !== options.kind) return false;
    if (
      options.intent &&
      !String(action.label ?? action.kind).toLowerCase().includes(
        String(options.intent).toLowerCase(),
      )
    ) {
      return false;
    }
    return (includeTarget && action.targetRef === node.ref) ||
      (includeSource && action.sourceRef === node.ref);
  });
}

export function primaryAction(
  world: TuiWorld,
  ref: string,
  options: Partial<WorldQuery> = {},
): TuiAction | null {
  const preferred = ["activate", "select", "focus", "dismiss", "key"];
  const rank = (kind: string) => {
    const index = preferred.indexOf(kind);
    return index === -1 ? preferred.length : index;
  };
  return [...actionsFor(world, ref, options)].sort((a, b) => {
    const kindDelta = rank(a.kind) - rank(b.kind);
    if (kindDelta !== 0) return kindDelta;
    return b.confidence - a.confidence;
  })[0] ?? null;
}

export function validate(world: TuiWorld): TuiDiagnostic[] {
  const diagnostics: TuiDiagnostic[] = [];
  const refs = new Set<string>();
  const nodeByRef = new Map<string, TuiNode>();
  const push = (
    severity: TuiDiagnostic["severity"],
    code: string,
    message: string,
    refsForDiagnostic: string[] = [],
  ) => {
    diagnostics.push({
      id: `d_${diagnostics.length + 1}`,
      severity,
      code,
      message,
      refs: refsForDiagnostic,
    });
  };

  for (const node of world.nodes) {
    if (refs.has(node.ref)) {
      push("error", "duplicate_ref", `Duplicate node ref: ${node.ref}`, [
        node.ref,
      ]);
    }
    refs.add(node.ref);
    nodeByRef.set(node.ref, node);
    if (node.bounds.w <= 0 || node.bounds.h <= 0) {
      push("error", "invalid_bounds", `Invalid bounds for ${node.ref}`, [
        node.ref,
      ]);
    }
    if (
      node.bounds.x < 0 || node.bounds.y < 0 ||
      node.bounds.x + node.bounds.w > world.viewport.width ||
      node.bounds.y + node.bounds.h > world.viewport.height
    ) {
      push(
        "warning",
        "bounds_outside_viewport",
        `Bounds exceed viewport for ${node.ref}`,
        [node.ref],
      );
    }
    if (node.confidence < 0 || node.confidence > 1) {
      push(
        "error",
        "invalid_confidence",
        `Confidence outside 0..1 for ${node.ref}`,
        [node.ref],
      );
    }
  }

  const focused = world.nodes.filter((node) =>
    node.state.focused === true && !NON_INTERACTIVE_ROLES.has(node.role)
  );
  if (focused.length > 1) {
    push(
      "warning",
      "multiple_focused_nodes",
      "More than one primary node is marked focused",
      focused.map((node) => node.ref),
    );
  }

  for (const action of world.actions) {
    if (action.targetRef && !nodeByRef.has(action.targetRef)) {
      push(
        "warning",
        "action_target_missing",
        `Action target does not exist: ${action.targetRef}`,
        [action.targetRef],
      );
    }
  }

  const visibleCount = world.nodes.filter(
    (n) => n.role !== "screen" && n.role !== "cursor",
  ).length;
  if (visibleCount > 3 && world.edges.length === 0) {
    push(
      "warning",
      "low_relation_count",
      `${visibleCount} visible nodes but 0 edges — spatial relation extraction may have failed`,
    );
  }

  return diagnostics;
}

export function explain(world: TuiWorld, ref: string): {
  node: TuiNode;
  evidence: TuiEvidence[];
  incoming: TuiEdge[];
  outgoing: TuiEdge[];
  actions: TuiAction[];
  diagnostics: TuiDiagnostic[];
} {
  const node = getByRef(world, ref);
  return {
    node,
    evidence: node.evidence,
    incoming: world.edges.filter((edge) => edge.to === node.id),
    outgoing: world.edges.filter((edge) => edge.from === node.id),
    actions: actionsFor(world, ref),
    diagnostics: world.diagnostics.filter((diagnostic) =>
      diagnostic.refs?.includes(node.ref)
    ),
  };
}

export function worldQuery(world: TuiWorld, query: WorldQuery): {
  op: string;
  nodes?: NodeSummary[];
  node?: NodeSummary;
  entries?: Array<{ edge: EdgeSummary; node: NodeSummary }>;
  evidence?: TuiEvidence[];
  incoming?: EdgeSummary[];
  outgoing?: EdgeSummary[];
  actions?: ActionSummary[];
  action?: ActionSummary;
  diagnostics?: TuiDiagnostic[];
} {
  const detail = query.detail ?? "compact";
  const op = query.op;
  if (!op) throw new Error("world query op is required");

  if (op === "getByRole") {
    const result = getByRole(world, query.role!, query);
    return {
      op,
      nodes: Array.isArray(result)
        ? result.map((node) => nodeSummary(node, detail))
        : [nodeSummary(result, detail)],
    };
  }
  if (op === "getByRef") {
    return { op, node: nodeSummary(getByRef(world, query.ref!), detail) };
  }
  if (op === "find") {
    return {
      op,
      nodes: findNodes(world, query).map((node) => nodeSummary(node, detail)),
    };
  }
  if (op === "related") {
    return {
      op,
      entries: related(world, query.ref!, query).map((entry) => ({
        edge: edgeSummary(entry.edge, world, detail),
        node: nodeSummary(entry.node, detail),
      })),
    };
  }
  if (op === "nearest") {
    return { op, node: nodeSummary(nearest(world, query.ref!, query), detail) };
  }
  if (op === "explain") {
    const details = explain(world, query.ref!);
    return {
      op,
      node: nodeSummary(details.node, detail),
      evidence: details.evidence,
      incoming: details.incoming.map((edge) =>
        edgeSummary(edge, world, detail)
      ),
      outgoing: details.outgoing.map((edge) =>
        edgeSummary(edge, world, detail)
      ),
      actions: details.actions.map((action) => actionSummary(action, detail)),
      diagnostics: details.diagnostics,
    };
  }
  if (op === "actionsFor") {
    return {
      op,
      actions: actionsFor(world, query.ref!, query).map((action) =>
        actionSummary(action, detail)
      ),
    };
  }
  if (op === "primaryAction") {
    return {
      op,
      action: actionSummary(primaryAction(world, query.ref!, query), detail),
    };
  }
  if (op === "validate") return { op, diagnostics: validate(world) };
  throw new Error(`Unknown TuiWorld query op: ${op}`);
}
