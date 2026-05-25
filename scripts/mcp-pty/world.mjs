// Deterministic object graph for terminal UI reasoning.

const DEFAULT_VIEWPORT = { width: 80, height: 24 };
const ROW_ONLY_ROLES = new Set(["fact", "status_bar", "scoreBar", "titleBar", "pipeMeter", "blockBar"]);
const NON_INTERACTIVE_ROLES = new Set(["screen", "cursor", "empty_space", "fact"]);
const NODE_DETAIL_FIELDS = new Set([
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
  "evidence",
]);

function finiteNumber(value) {
  return Number.isFinite(value) ? value : null;
}

function clamp(value, min, max) {
  if (max < min) return min;
  return Math.min(max, Math.max(min, value));
}

function slug(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 48) || "node";
}

function uniqueValue(base, used) {
  let value = base;
  let i = 2;
  while (used.has(value)) {
    value = `${base}_${i}`;
    i += 1;
  }
  used.add(value);
  return value;
}

function inclusiveWidth(start, end) {
  return Math.max(1, end - start + 1);
}

function normalizeViewport(viewport) {
  return {
    width: Math.max(1, finiteNumber(viewport?.width) ?? DEFAULT_VIEWPORT.width),
    height: Math.max(1, finiteNumber(viewport?.height) ?? DEFAULT_VIEWPORT.height),
  };
}

function mergeBounds(element) {
  if (!element) return null;

  if (Array.isArray(element.positions) && element.positions.length > 0) {
    const xs = element.positions.map((p) => p.x).filter(Number.isFinite);
    const ys = element.positions.map((p) => p.y).filter(Number.isFinite);
    if (xs.length > 0 && ys.length > 0) {
      return {
        startX: Math.min(...xs),
        endX: Math.max(...xs),
        startY: Math.min(...ys),
        endY: Math.max(...ys),
      };
    }
  }

  if (element.position && Number.isFinite(element.position.x) && Number.isFinite(element.position.y)) {
    return {
      startX: element.position.x,
      endX: element.position.x,
      startY: element.position.y,
      endY: element.position.y,
    };
  }

  return {
    ...(element.bounds || element.sourceBounds || {}),
    startX: finiteNumber(element.startX) ?? element.bounds?.startX ?? element.sourceBounds?.startX,
    endX: finiteNumber(element.endX) ?? element.bounds?.endX ?? element.sourceBounds?.endX,
    startY: finiteNumber(element.startY) ?? element.bounds?.startY ?? element.sourceBounds?.startY,
    endY: finiteNumber(element.endY) ?? element.bounds?.endY ?? element.sourceBounds?.endY,
    x: finiteNumber(element.x) ?? element.bounds?.x,
    y: finiteNumber(element.y) ?? element.bounds?.y,
    w: finiteNumber(element.w) ?? element.bounds?.w,
    h: finiteNumber(element.h) ?? element.bounds?.h,
  };
}

function boundsAccuracy(bounds) {
  if (!bounds) return "estimated";
  if (
    Number.isFinite(bounds.x) && Number.isFinite(bounds.y) &&
    Number.isFinite(bounds.w) && Number.isFinite(bounds.h)
  ) {
    return "exact";
  }
  if (
    Number.isFinite(bounds.startX) && Number.isFinite(bounds.endX) &&
    Number.isFinite(bounds.startY) && Number.isFinite(bounds.endY)
  ) {
    return "exact";
  }
  if (Number.isFinite(bounds.startY) || Number.isFinite(bounds.y)) {
    return "row";
  }
  return "estimated";
}

export function toRect(bounds, viewport = DEFAULT_VIEWPORT) {
  const vp = normalizeViewport(viewport);
  if (!bounds) return null;

  if (
    Number.isFinite(bounds.x) && Number.isFinite(bounds.y) &&
    Number.isFinite(bounds.w) && Number.isFinite(bounds.h)
  ) {
    return {
      x: clamp(bounds.x, 0, vp.width - 1),
      y: clamp(bounds.y, 0, vp.height - 1),
      w: Math.max(1, Math.min(bounds.w, vp.width - clamp(bounds.x, 0, vp.width - 1))),
      h: Math.max(1, Math.min(bounds.h, vp.height - clamp(bounds.y, 0, vp.height - 1))),
    };
  }

  const startY = finiteNumber(bounds.startY) ?? finiteNumber(bounds.y);
  if (startY === null) return null;

  const endY = finiteNumber(bounds.endY) ?? startY;
  const hasX = Number.isFinite(bounds.startX) || Number.isFinite(bounds.x);
  const startX = hasX ? (finiteNumber(bounds.startX) ?? finiteNumber(bounds.x) ?? 0) : 0;
  const endX = Number.isFinite(bounds.endX)
    ? bounds.endX
    : Number.isFinite(bounds.w)
      ? startX + bounds.w - 1
      : vp.width - 1;

  const x = clamp(startX, 0, vp.width - 1);
  const y = clamp(startY, 0, vp.height - 1);
  const clampedEndX = clamp(endX, x, vp.width - 1);
  const clampedEndY = clamp(endY, y, vp.height - 1);

  return {
    x,
    y,
    w: inclusiveWidth(x, clampedEndX),
    h: inclusiveWidth(y, clampedEndY),
  };
}

export function rectContains(parent, child, padding = 0) {
  if (!parent || !child) return false;
  return child.x >= parent.x - padding &&
    child.y >= parent.y - padding &&
    child.x + child.w <= parent.x + parent.w + padding &&
    child.y + child.h <= parent.y + parent.h + padding;
}

export function rectOverlaps(a, b) {
  if (!a || !b) return false;
  return a.x < b.x + b.w &&
    a.x + a.w > b.x &&
    a.y < b.y + b.h &&
    a.y + a.h > b.y;
}

function rectArea(rect) {
  return rect ? rect.w * rect.h : 0;
}

function rectCenter(rect) {
  return {
    x: rect.x + (rect.w - 1) / 2,
    y: rect.y + (rect.h - 1) / 2,
  };
}

function rectRight(rect) {
  return rect.x + rect.w;
}

function rectBottom(rect) {
  return rect.y + rect.h;
}

function intervalsOverlap(aStart, aEnd, bStart, bEnd) {
  return aStart < bEnd && aEnd > bStart;
}

function horizontalBandsOverlap(a, b) {
  return intervalsOverlap(a.x, rectRight(a), b.x, rectRight(b));
}

function verticalBandsOverlap(a, b) {
  return intervalsOverlap(a.y, rectBottom(a), b.y, rectBottom(b));
}

function intersectionArea(a, b) {
  if (!rectOverlaps(a, b)) return 0;
  const x1 = Math.max(a.x, b.x);
  const y1 = Math.max(a.y, b.y);
  const x2 = Math.min(a.x + a.w, b.x + b.w);
  const y2 = Math.min(a.y + a.h, b.y + b.h);
  return Math.max(0, x2 - x1) * Math.max(0, y2 - y1);
}

function inferDomain(role, element = {}) {
  if (role === "table") return "table";
  if (role === "checkbox" || role === "button" || role === "input") return "form";
  if (role === "brailleChart" || role === "blockBar" || role === "pipeMeter") return "chart";
  if (role === "cardGame" || role === "cardFace" || element.rank || element.suit) return "card_game";
  if (role === "Mode" || element.label === "Mode") return "editor";
  return "generic";
}

function copyState(element, extra = {}) {
  const omit = new Set([
    "id", "role", "bounds", "sourceBounds", "label", "title", "confidence", "evidence",
    "startX", "endX", "startY", "endY", "x", "y", "w", "h",
  ]);
  const state = { ...extra };
  for (const [key, value] of Object.entries(element || {})) {
    if (omit.has(key)) continue;
    if (typeof value === "function") continue;
    state[key] = value;
  }
  return state;
}

function evidenceText(element) {
  if (Array.isArray(element?.evidence) && element.evidence.length > 0) {
    return String(element.evidence[0]).slice(0, 120);
  }
  if (element?.label) return String(element.label).slice(0, 120);
  if (element?.title) return String(element.title).slice(0, 120);
  if (element?.id) return String(element.id).slice(0, 120);
  return "";
}

export function normalizeElement(element, context = {}) {
  const viewport = normalizeViewport(context.viewport);
  const role = context.role || element?.role || "element";
  const bounds = mergeBounds(element);
  const rect = toRect(bounds, viewport);
  if (!rect) return null;

  const source = context.source || "detector:unknown";
  const sourceIndex = context.sourceIndex ?? 0;
  const label = context.label ?? element?.label ?? element?.title ?? element?.id ?? role;
  const confidence = Math.max(0, Math.min(1, element?.confidence ?? context.confidence ?? 0.7));
  const domain = context.domain || inferDomain(role, element);

  return {
    id: "",
    ref: "",
    source,
    sourceIndex,
    domain,
    role,
    label: label === undefined || label === null ? undefined : String(label),
    bounds: rect,
    boundsAccuracy: context.boundsAccuracy || boundsAccuracy(bounds),
    state: copyState(element, context.state),
    confidence,
    evidence: [{
      source,
      index: sourceIndex,
      kind: context.kind || "detector",
      text: evidenceText(element),
      bounds: bounds || null,
    }],
  };
}

function makeSource(id, count, kind = "detector") {
  return { id, kind, count };
}

function getNodeByRef(world, ref) {
  return world.nodes.find((node) => node.ref === ref || node.id === ref);
}

function actionMatchesRef(action, ref) {
  return action.targetRef === ref || action.sourceRef === ref;
}

function nodeSummary(node, detail = "compact") {
  if (!node) return null;
  if (detail === "full") return node;
  const summary = {};
  for (const key of NODE_DETAIL_FIELDS) {
    if (key === "state" && (!node.state || Object.keys(node.state).length === 0)) continue;
    if (key === "evidence") continue;
    summary[key] = node[key];
  }
  return summary;
}

function edgeSummary(edge, world, detail = "compact") {
  if (!edge) return null;
  if (detail === "full") return edge;
  const from = world.nodes.find((node) => node.id === edge.from);
  const to = world.nodes.find((node) => node.id === edge.to);
  return {
    id: edge.id,
    kind: edge.kind,
    from: from?.ref || edge.from,
    to: to?.ref || edge.to,
    confidence: edge.confidence,
  };
}

function actionSummary(action, detail = "compact") {
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

function worldQueryError(code, message, extra = {}) {
  const error = new Error(message);
  error.code = code;
  Object.assign(error, extra);
  return error;
}

function addNode(world, node, usedIds, usedRefs) {
  const idBase = `n_${slug(node.source)}_${node.sourceIndex}_${slug(node.role)}`;
  const refBase = `${slug(node.domain)}:${slug(node.role)}:${slug(node.label || node.sourceIndex)}:${node.bounds.x},${node.bounds.y}`;
  node.id = uniqueValue(idBase, usedIds);
  node.ref = uniqueValue(refBase, usedRefs);
  world.nodes.push(node);
  return node;
}

function addEdge(world, kind, from, to, confidence = 0.8, evidence = []) {
  if (!from || !to || from.id === to.id) return null;
  const duplicate = world.edges.some((edge) =>
    edge.kind === kind && edge.from === from.id && edge.to === to.id
  );
  if (duplicate) return null;

  const edge = {
    id: `e_${world.edges.length + 1}`,
    kind,
    from: from.id,
    to: to.id,
    confidence,
    evidence,
  };
  world.edges.push(edge);
  return edge;
}

function actionId(world) {
  return `a_${world.actions.length + 1}`;
}

function addAction(world, action) {
  world.actions.push({
    id: actionId(world),
    confidence: action.confidence ?? 0.75,
    ...action,
  });
}

function visibleNodes(world) {
  return world.nodes.filter((node) => node.role !== "screen");
}

function sourceNodeMap(world) {
  const map = new Map();
  for (const node of world.nodes) {
    map.set(`${node.source}:${node.sourceIndex}`, node);
  }
  return map;
}

export function buildSpatialRelations(world) {
  const nodes = visibleNodes(world);
  const screen = world.nodes.find((node) => node.role === "screen");

  for (const node of nodes) {
    let parent = screen;
    let parentArea = rectArea(screen?.bounds);
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
    if (parent) addEdge(world, "contains", parent, node, 0.9, node.evidence);
  }

  for (let i = 0; i < nodes.length; i += 1) {
    const a = nodes[i];
    if (a.role === "cursor") continue;
    for (let j = i + 1; j < nodes.length; j += 1) {
      const b = nodes[j];
      if (b.role === "cursor") continue;
      if (!rectOverlaps(a.bounds, b.bounds)) continue;
      if (rectContains(a.bounds, b.bounds) || rectContains(b.bounds, a.bounds)) continue;
      const area = intersectionArea(a.bounds, b.bounds);
      if (area > 0) addEdge(world, "overlaps", a, b, 0.65);
    }
  }

  for (let i = 0; i < nodes.length; i += 1) {
    const a = nodes[i];
    if (a.role === "cursor") continue;
    for (let j = i + 1; j < nodes.length; j += 1) {
      const b = nodes[j];
      if (b.role === "cursor") continue;
      const sameRow = verticalBandsOverlap(a.bounds, b.bounds);
      const sameColumn = horizontalBandsOverlap(a.bounds, b.bounds);

      if (sameRow) {
        addEdge(world, "sameRow", a, b, 0.72, b.evidence);
        addEdge(world, "sameRow", b, a, 0.72, a.evidence);
      }
      if (sameColumn) {
        addEdge(world, "sameColumn", a, b, 0.72, b.evidence);
        addEdge(world, "sameColumn", b, a, 0.72, a.evidence);
      }
      if (sameRow && rectRight(a.bounds) <= b.bounds.x) {
        addEdge(world, "leftOf", a, b, 0.75, b.evidence);
        addEdge(world, "rightOf", b, a, 0.75, a.evidence);
      } else if (sameRow && rectRight(b.bounds) <= a.bounds.x) {
        addEdge(world, "leftOf", b, a, 0.75, a.evidence);
        addEdge(world, "rightOf", a, b, 0.75, b.evidence);
      }
      if (sameColumn && rectBottom(a.bounds) <= b.bounds.y) {
        addEdge(world, "above", a, b, 0.75, b.evidence);
        addEdge(world, "below", b, a, 0.75, a.evidence);
      } else if (sameColumn && rectBottom(b.bounds) <= a.bounds.y) {
        addEdge(world, "above", b, a, 0.75, a.evidence);
        addEdge(world, "below", a, b, 0.75, b.evidence);
      }
    }
  }

  const cursor = world.nodes.find((node) => node.role === "cursor");
  if (cursor) {
    let focused = null;
    for (const node of nodes) {
      if (node.role === "cursor" || NON_INTERACTIVE_ROLES.has(node.role)) continue;
      if (!rectContains(node.bounds, cursor.bounds)) continue;
      if (!focused || rectArea(node.bounds) < rectArea(focused.bounds)) focused = node;
    }
    if (focused) {
      focused.state = { ...focused.state, focused: true };
      addEdge(world, "focusedBy", focused, cursor, 0.85, cursor.evidence);
    }
  }

  for (const node of nodes) {
    if (node.state?.selected !== true) continue;
    const parent = nodes
      .filter((candidate) => candidate.role === "list" && rectContains(candidate.bounds, node.bounds))
      .sort((a, b) => rectArea(a.bounds) - rectArea(b.bounds))[0];
    if (parent) addEdge(world, "selectedBy", node, parent, 0.85, node.evidence);
  }

  return world.edges;
}

function buildActions(world, snapshot) {
  const bySource = sourceNodeMap(world);

  for (let i = 0; i < (snapshot.statusBars || []).length; i += 1) {
    const node = bySource.get(`detector:statusBars:${i}`);
    const statusBar = snapshot.statusBars[i];
    for (const keyAction of statusBar.keyActions || []) {
      addAction(world, {
        kind: "key",
        key: keyAction.key,
        label: keyAction.action,
        source: "status_bar",
        sourceRef: node?.ref,
        confidence: statusBar.confidence ?? 0.8,
      });
    }
  }

  for (const node of world.nodes) {
    if (node.role === "tab" && node.state?.index !== undefined) {
      const sourceRef = getNodeByRef(world, node.state.tabBarRef)?.ref;
      addAction(world, {
        kind: "key",
        key: String(node.state.index),
        label: `switch to ${node.label}`,
        source: "tab_bar",
        sourceRef,
        targetRef: node.ref,
        confidence: node.confidence,
      });
      const sourceNode = getNodeByRef(world, sourceRef);
      if (sourceNode) addEdge(world, "activates", sourceNode, node, 0.75, node.evidence);
    }

    if (node.role === "button") {
      addAction(world, {
        kind: "activate",
        key: "enter",
        label: node.label || "activate button",
        source: "control",
        targetRef: node.ref,
        confidence: node.confidence,
      });
    }

    if (node.role === "input") {
      addAction(world, {
        kind: "focus",
        key: "tab",
        label: node.label || "focus input",
        source: "control",
        targetRef: node.ref,
        confidence: node.confidence,
      });
    }

    if (node.role === "popup") {
      addAction(world, {
        kind: "dismiss",
        key: "escape",
        label: `dismiss ${node.label || "popup"}`,
        source: "popup",
        targetRef: node.ref,
        confidence: node.confidence,
      });
    }

    if (node.role === "list_item" && node.state?.selected === true) {
      addAction(world, {
        kind: "select",
        key: "enter",
        label: `select ${node.label || "item"}`,
        source: "selected_item",
        targetRef: node.ref,
        confidence: node.confidence,
      });
    }
  }
}

function addDiagnostic(world, severity, code, message, refs = []) {
  world.diagnostics.push({
    id: `d_${world.diagnostics.length + 1}`,
    severity,
    code,
    message,
    refs,
  });
}

export function validate(world) {
  const diagnostics = [];
  const refs = new Set();
  const nodeByRef = new Map();

  const push = (severity, code, message, refsForDiagnostic = []) => {
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
      push("error", "duplicate_ref", `Duplicate node ref: ${node.ref}`, [node.ref]);
    }
    refs.add(node.ref);
    nodeByRef.set(node.ref, node);

    if (!node.bounds || node.bounds.w <= 0 || node.bounds.h <= 0) {
      push("error", "invalid_bounds", `Invalid bounds for ${node.ref}`, [node.ref]);
    }
    if (node.bounds.x < 0 || node.bounds.y < 0 ||
        node.bounds.x + node.bounds.w > world.viewport.width ||
        node.bounds.y + node.bounds.h > world.viewport.height) {
      push("warning", "bounds_outside_viewport", `Bounds exceed viewport for ${node.ref}`, [node.ref]);
    }
    if (node.confidence < 0 || node.confidence > 1) {
      push("error", "invalid_confidence", `Confidence outside 0..1 for ${node.ref}`, [node.ref]);
    }
  }

  const focused = world.nodes.filter((node) => node.state?.focused === true);
  if (focused.length > 1) {
    push("warning", "multiple_focused_nodes", "More than one primary node is marked focused", focused.map((node) => node.ref));
  }

  for (const node of world.nodes) {
    if (node.role !== "list_item" || node.state?.selected !== true) continue;
    const hasList = world.edges.some((edge) =>
      edge.kind === "selectedBy" && edge.from === node.id
    );
    if (!hasList) {
      push("warning", "selected_item_without_collection", `Selected item has no containing list: ${node.ref}`, [node.ref]);
    }
  }

  for (const action of world.actions) {
    if (action.targetRef && !nodeByRef.has(action.targetRef)) {
      push("warning", "action_target_missing", `Action target does not exist: ${action.targetRef}`, [action.targetRef]);
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

function attachValidation(world) {
  for (const diagnostic of validate(world)) {
    addDiagnostic(world, diagnostic.severity, diagnostic.code, diagnostic.message, diagnostic.refs);
  }
}

function addDetectorNodes(world, usedIds, usedRefs, sourceId, values, mapper) {
  if (!Array.isArray(values) || values.length === 0) return;
  world.sources.push(makeSource(sourceId, values.length));
  values.forEach((value, index) => {
    const mapped = mapper(value, index);
    const entries = Array.isArray(mapped) ? mapped : [mapped];
    for (const entry of entries) {
      if (!entry) continue;
      const node = normalizeElement(entry.element, {
        source: sourceId,
        sourceIndex: entry.sourceIndex ?? index,
        role: entry.role,
        label: entry.label,
        domain: entry.domain,
        confidence: entry.confidence,
        state: entry.state,
        boundsAccuracy: entry.boundsAccuracy,
      });
      if (node) addNode(world, node, usedIds, usedRefs);
    }
  });
}

export function buildTuiWorld(snapshot, context = {}) {
  const viewport = normalizeViewport(context.viewport || {
    width: snapshot.viewport?.width ?? snapshot.cols ?? context.cols,
    height: snapshot.viewport?.height ?? snapshot.rows ?? context.rows,
  });
  const world = {
    frameId: snapshot.frameId || `${snapshot.sessionId || "session"}:${snapshot.frameSeq ?? "semantic"}`,
    viewport,
    sources: [],
    nodes: [],
    edges: [],
    actions: [],
    diagnostics: [],
  };
  const usedIds = new Set();
  const usedRefs = new Set();

  addNode(world, {
    id: "",
    ref: "",
    source: "terminal:viewport",
    sourceIndex: 0,
    domain: "generic",
    role: "screen",
    label: "screen",
    bounds: { x: 0, y: 0, w: viewport.width, h: viewport.height },
    boundsAccuracy: "exact",
    state: {},
    confidence: 1,
    evidence: [{ source: "terminal:viewport", index: 0, kind: "terminal", text: "" }],
  }, usedIds, usedRefs);

  if (snapshot.cursor) {
    addNode(world, normalizeElement({
      role: "cursor",
      label: "cursor",
      confidence: 1,
      bounds: {
        startX: snapshot.cursor.x,
        endX: snapshot.cursor.x,
        startY: snapshot.cursor.y,
        endY: snapshot.cursor.y,
      },
      evidence: [`cursor ${snapshot.cursor.x},${snapshot.cursor.y}`],
    }, {
      source: "terminal:cursor",
      sourceIndex: 0,
      role: "cursor",
      domain: "generic",
      kind: "terminal",
      viewport,
    }), usedIds, usedRefs);
    world.sources.push(makeSource("terminal:cursor", 1, "terminal"));
  }

  addDetectorNodes(world, usedIds, usedRefs, "detector:facts", snapshot.facts, (fact) => ({
    role: "fact",
    label: `${fact.label}: ${fact.value}`,
    domain: fact.label === "Mode" ? "editor" : "generic",
    element: { ...fact, bounds: fact.sourceBounds, role: "fact" },
    state: { name: fact.label, value: fact.value },
  }));

  addDetectorNodes(world, usedIds, usedRefs, "detector:tables", snapshot.tables, (table) => ({
    role: "table",
    domain: "table",
    label: table.label || table.id || "table",
    element: table,
    state: { columns: table.columns || [] },
  }));

  addDetectorNodes(world, usedIds, usedRefs, "detector:regions", snapshot.regions, (region) => ({
    role: region.role || "region",
    label: region.label || region.id || region.role,
    element: region,
  }));

  addDetectorNodes(world, usedIds, usedRefs, "detector:controls", snapshot.controls, (control) => ({
    role: control.role || "control",
    domain: "form",
    label: control.label,
    element: control,
  }));

  addDetectorNodes(world, usedIds, usedRefs, "detector:tabs", snapshot.tabs, (tabBar, index) => {
    const entries = [{
      role: tabBar.role || "tab_bar",
      label: tabBar.label || "tab_bar",
      element: tabBar,
      state: { tabs: tabBar.tabs || [] },
    }];
    const tabBarRect = toRect(mergeBounds(tabBar), viewport);
    for (let tabIndex = 0; tabIndex < (tabBar.tabs || []).length; tabIndex += 1) {
      const tab = tabBar.tabs[tabIndex];
      const x = Number.isFinite(tab.col) ? tab.col : tabIndex;
      const y = tabBarRect?.y ?? 0;
      const label = tab.label || `tab ${tab.index ?? tabIndex + 1}`;
      entries.push({
        role: "tab",
        label,
        sourceIndex: `${index}_${tabIndex}`,
        element: {
          role: "tab",
          label,
          confidence: tabBar.confidence ?? 0.8,
          bounds: { startX: x, endX: x + String(label).length - 1, startY: y, endY: y },
          evidence: tabBar.evidence || [label],
        },
        state: {
          index: tab.index,
          active: tab.active === true,
          tabBarRef: null,
        },
      });
    }
    return entries;
  });

  const tabBars = world.nodes.filter((node) => node.source === "detector:tabs" && node.role === "tab_bar");
  for (const tab of world.nodes.filter((node) => node.source === "detector:tabs" && node.role === "tab")) {
    const prefix = String(tab.sourceIndex).split("_")[0];
    const parent = tabBars[Number(prefix)];
    if (parent) tab.state.tabBarRef = parent.ref;
  }

  addDetectorNodes(world, usedIds, usedRefs, "detector:panes", snapshot.panes, (pane) => ({
    role: pane.role || "pane",
    label: pane.title || pane.label || pane.id,
    element: pane,
  }));

  addDetectorNodes(world, usedIds, usedRefs, "detector:lists", snapshot.lists, (item) => ({
    role: item.role || "list_item",
    label: item.label || item.id || item.role,
    element: item,
    state: { selected: item.selected === true, marker: item.marker, itemCount: item.items?.length },
  }));

  addDetectorNodes(world, usedIds, usedRefs, "detector:statusBars", snapshot.statusBars, (statusBar) => ({
    role: "status_bar",
    label: statusBar.label || "status",
    element: statusBar,
    state: { keyActions: statusBar.keyActions || [], keybindings: statusBar.keybindings || [] },
  }));

  addDetectorNodes(world, usedIds, usedRefs, "detector:popups", snapshot.popups, (popup) => ({
    role: popup.role || "popup",
    label: popup.title || popup.label || "popup",
    element: popup,
    state: { centered: popup.centered === true },
  }));

  addDetectorNodes(world, usedIds, usedRefs, "detector:gameElements", snapshot.gameElements, (element) => ({
    role: element.role || "game_element",
    label: element.label || element.id || element.role,
    domain: inferDomain(element.role, element),
    element,
    state: {
      rank: element.rank,
      suit: element.suit,
      suitColor: element.suitColor,
      entityRole: element.entityRole,
      count: element.count,
      selected: element.selected === true,
    },
  }));

  addDetectorNodes(world, usedIds, usedRefs, "detector:charts", snapshot.charts, (chart) => ({
    role: chart.role || "chart",
    label: chart.label || chart.chartType || "chart",
    domain: "chart",
    element: chart,
    state: { chartType: chart.chartType, values: chart.values, meters: chart.meters },
  }));

  buildSpatialRelations(world);
  buildActions(world, snapshot);
  attachValidation(world);

  return world;
}

function matchName(label, name, exact = false) {
  if (name === undefined || name === null) return true;
  const value = String(label || "");
  if (name instanceof RegExp) return name.test(value);
  if (exact) return value.toLowerCase() === String(name).toLowerCase();
  return value.toLowerCase().includes(String(name).toLowerCase());
}

function isHidden(node) {
  return node.state?.hidden === true || node.state?.visible === false;
}

export function find(world, predicate) {
  return world.nodes.filter(predicate);
}

export function findNodes(world, options = {}) {
  return world.nodes.filter((node) => {
    if (options.role && node.role !== options.role) return false;
    if (options.domain && node.domain !== options.domain) return false;
    if (options.source && node.source !== options.source) return false;
    if (options.minConfidence !== undefined && node.confidence < options.minConfidence) return false;
    if (options.name !== undefined && !matchName(node.label, options.name, options.exact === true)) return false;
    if (options.text !== undefined && !matchName(node.label, options.text, options.exact === true)) return false;
    if (options.selected !== undefined && node.state?.selected !== options.selected) return false;
    if (options.focused !== undefined && node.state?.focused !== options.focused) return false;
    if (options.visible !== undefined && options.visible && (node.role === "screen" || isHidden(node))) return false;
    return true;
  });
}

export function getByRef(world, ref) {
  const node = getNodeByRef(world, ref);
  if (!node) throw new Error(`No TuiWorld node found for ref: ${ref}`);
  return node;
}

export function getByRole(world, role, options = {}) {
  const strict = options.strict !== false;
  const matches = findNodes(world, { ...options, role });
  if (matches.length === 0) {
    throw worldQueryError("not_found", `No TuiWorld node found for role "${role}"`, {
      role,
      name: options.name,
    });
  }
  if (strict && matches.length > 1) {
    const refs = matches.map((node) => `${node.ref}${node.label ? ` (${node.label})` : ""}`).join(", ");
    throw worldQueryError("ambiguous", `Ambiguous TuiWorld role "${role}": ${refs}`, {
      role,
      name: options.name,
      candidates: matches.map((node) => nodeSummary(node)),
    });
  }
  return strict ? matches[0] : matches;
}

export class TuiLocator {
  constructor(world, resolver, description) {
    this.world = world;
    this.resolver = resolver;
    this.description = description;
  }

  resolve(options = {}) {
    const strict = options.strict !== false;
    const nodes = this.resolver();
    if (nodes.length === 0) {
      throw worldQueryError("not_found", `No TuiWorld node found for locator ${this.description}`, {
        locator: this.description,
      });
    }
    if (strict && nodes.length > 1) {
      const refs = nodes.map((node) => `${node.ref}${node.label ? ` (${node.label})` : ""}`).join(", ");
      throw worldQueryError("ambiguous", `Ambiguous TuiWorld locator ${this.description}: ${refs}`, {
        locator: this.description,
        candidates: nodes.map((node) => nodeSummary(node)),
      });
    }
    return strict ? nodes[0] : nodes;
  }

  all() {
    return this.resolve({ strict: false });
  }

  first() {
    const nodes = this.resolve({ strict: false });
    return nodes[0];
  }

  nth(index) {
    return new TuiLocator(
      this.world,
      () => {
        const nodes = this.resolve({ strict: false });
        return nodes[index] ? [nodes[index]] : [];
      },
      `${this.description}.nth(${index})`,
    );
  }

  filter(options = {}) {
    return new TuiLocator(
      this.world,
      () => this.resolve({ strict: false }).filter((node) =>
        findNodes({ nodes: [node] }, options).length === 1
      ),
      `${this.description}.filter(${JSON.stringify(options)})`,
    );
  }

  nearest(direction, options = {}) {
    return new TuiLocator(
      this.world,
      () => {
        const node = this.resolve();
        const found = nearest(this.world, node.ref, { ...options, direction });
        return found ? [found] : [];
      },
      `${this.description}.nearest(${direction})`,
    );
  }

  explain() {
    return explain(this.world, this.resolve().ref);
  }

  actions() {
    return actionsFor(this.world, this.resolve().ref);
  }

  primaryAction(intent) {
    return primaryAction(this.world, this.resolve().ref, { intent });
  }
}

export function locator(world) {
  return {
    getByRole(role, options = {}) {
      return new TuiLocator(
        world,
        () => findNodes(world, { ...options, role }),
        `getByRole(${role}${options.name !== undefined ? `, name=${String(options.name)}` : ""})`,
      );
    },
    getByRef(ref) {
      return new TuiLocator(
        world,
        () => {
          const node = getNodeByRef(world, ref);
          return node ? [node] : [];
        },
        `getByRef(${ref})`,
      );
    },
    getByText(textOrRegex, options = {}) {
      return new TuiLocator(
        world,
        () => findNodes(world, { ...options, text: textOrRegex }),
        `getByText(${String(textOrRegex)})`,
      );
    },
  };
}

export function related(world, ref, options = {}) {
  const node = getByRef(world, ref);
  const direction = options.direction || "both";
  return world.edges
    .filter((edge) => !options.kind || edge.kind === options.kind)
    .filter((edge) => {
      if (direction === "out") return edge.from === node.id;
      if (direction === "in") return edge.to === node.id;
      return edge.from === node.id || edge.to === node.id;
    })
    .map((edge) => {
      const otherId = edge.from === node.id ? edge.to : edge.from;
      return { edge, node: world.nodes.find((candidate) => candidate.id === otherId) };
    })
    .filter((entry) => entry.node)
    .filter((entry) => !options.role || entry.node.role === options.role);
}

export function nearest(world, ref, options = {}) {
  const node = getByRef(world, ref);
  const sourceCenter = rectCenter(node.bounds);
  const candidates = world.nodes.filter((candidate) => {
    if (candidate.id === node.id || candidate.role === "screen" || candidate.role === "cursor") return false;
    if (options.role && candidate.role !== options.role) return false;
    if (options.domain && candidate.domain !== options.domain) return false;
    const center = rectCenter(candidate.bounds);
    if (options.direction === "below") return center.y > sourceCenter.y;
    if (options.direction === "above") return center.y < sourceCenter.y;
    if (options.direction === "rightOf") return center.x > sourceCenter.x;
    if (options.direction === "leftOf") return center.x < sourceCenter.x;
    return true;
  });

  const scored = candidates.map((candidate) => {
    const center = rectCenter(candidate.bounds);
    const dx = Math.abs(center.x - sourceCenter.x);
    const dy = Math.abs(center.y - sourceCenter.y);
    const primary = options.direction === "below" || options.direction === "above" ? dy : dx;
    const secondary = options.direction === "below" || options.direction === "above" ? dx : dy;
    return { candidate, score: primary * 10 + secondary };
  }).sort((a, b) => {
    const scoreDelta = a.score - b.score;
    if (scoreDelta !== 0) return scoreDelta;
    const confidenceDelta = (b.candidate.confidence ?? 0) - (a.candidate.confidence ?? 0);
    if (confidenceDelta !== 0) return confidenceDelta;
    const yDelta = a.candidate.bounds.y - b.candidate.bounds.y;
    if (yDelta !== 0) return yDelta;
    const xDelta = a.candidate.bounds.x - b.candidate.bounds.x;
    if (xDelta !== 0) return xDelta;
    return a.candidate.ref.localeCompare(b.candidate.ref);
  });

  return scored[0]?.candidate || null;
}

export function actionsFor(world, ref, options = {}) {
  const node = getByRef(world, ref);
  const includeSource = options.includeSource !== false;
  const includeTarget = options.includeTarget !== false;
  return world.actions.filter((action) => {
    if (options.kind && action.kind !== options.kind) return false;
    if (options.intent && !String(action.label || action.kind).toLowerCase().includes(String(options.intent).toLowerCase())) return false;
    return (includeTarget && action.targetRef === node.ref) ||
      (includeSource && action.sourceRef === node.ref);
  });
}

export function primaryAction(world, ref, options = {}) {
  const actions = actionsFor(world, ref, options);
  const preferredKinds = options.preferredKinds || ["activate", "select", "focus", "dismiss", "key"];
  const rank = (kind) => {
    const index = preferredKinds.indexOf(kind);
    return index === -1 ? preferredKinds.length : index;
  };
  return [...actions].sort((a, b) => {
    const kindDelta = rank(a.kind) - rank(b.kind);
    if (kindDelta !== 0) return kindDelta;
    return (b.confidence ?? 0) - (a.confidence ?? 0);
  })[0] || null;
}

export function worldQuery(world, query = {}) {
  const detail = query.detail || "compact";
  const op = query.op;
  if (!op) throw new Error("world query op is required");

  if (op === "getByRole") {
    const result = getByRole(world, query.role, query);
    return {
      op,
      nodes: Array.isArray(result)
        ? result.map((node) => nodeSummary(node, detail))
        : [nodeSummary(result, detail)],
    };
  }

  if (op === "getByRef") {
    return { op, node: nodeSummary(getByRef(world, query.ref), detail) };
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
      entries: related(world, query.ref, query).map((entry) => ({
        edge: edgeSummary(entry.edge, world, detail),
        node: nodeSummary(entry.node, detail),
      })),
    };
  }

  if (op === "nearest") {
    return {
      op,
      node: nodeSummary(nearest(world, query.ref, query), detail),
    };
  }

  if (op === "explain") {
    const details = explain(world, query.ref);
    return {
      op,
      node: nodeSummary(details.node, detail),
      evidence: details.evidence,
      incoming: details.incoming.map((edge) => edgeSummary(edge, world, detail)),
      outgoing: details.outgoing.map((edge) => edgeSummary(edge, world, detail)),
      actions: details.actions.map((action) => actionSummary(action, detail)),
      diagnostics: details.diagnostics,
    };
  }

  if (op === "actionsFor") {
    return {
      op,
      actions: actionsFor(world, query.ref, query).map((action) => actionSummary(action, detail)),
    };
  }

  if (op === "primaryAction") {
    return {
      op,
      action: actionSummary(primaryAction(world, query.ref, query), detail),
    };
  }

  if (op === "validate") {
    return { op, diagnostics: validate(world) };
  }

  throw new Error(`Unknown TuiWorld query op: ${op}`);
}

export function explain(world, ref) {
  const node = getByRef(world, ref);
  return {
    node,
    evidence: node.evidence,
    incoming: world.edges.filter((edge) => edge.to === node.id),
    outgoing: world.edges.filter((edge) => edge.from === node.id),
    actions: actionsFor(world, ref),
    diagnostics: world.diagnostics.filter((diagnostic) => diagnostic.refs?.includes(node.ref)),
  };
}
