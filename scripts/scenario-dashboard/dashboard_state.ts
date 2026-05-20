/**
 * Sans-IO Dashboard State Machine
 *
 * Pure state type + Msg discriminated union + update() function.
 * No I/O happens here — all effects are expressed as Cmd values
 * that the Runtime interprets.
 *
 * Architecture: The Elm Architecture (TEA)
 *   Model  = DashboardState
 *   Msg    = discriminated union of state transitions
 *   update = (state, msg) → [state, Cmd[]]
 *   view   = (state, dispatch) → VNode  (in islands)
 *
 * This module is the single source of truth for dashboard state.
 * Islands read from DashboardState and dispatch Msgs.
 * The Runtime interprets Cmds into real I/O.
 */

import type { Run, RunEvent, ScenarioResultView, ServiceStatus } from "./services/types.ts";

// ---------------------------------------------------------------------------
// State slices
// ---------------------------------------------------------------------------

/** Slice tracking network service health polling state. */
export interface NetworkSlice {
  /** Current network service statuses. */
  services: ServiceStatus[];
  /** Milliseconds since last successful health check response */
  lastHealthCheckMs: number;
  /** Current backoff delay for next health check (ms) */
  healthCheckDelayMs: number;
  /** Whether a health check fetch is in-flight */
  healthCheckInFlight: boolean;
  /** Latest health request token */
  healthToken: number;
}

/** Slice tracking active run, progress polling, and backoff state. */
export interface RunsSlice {
  /** Currently active run, if any */
  active: Run | null;
  /** Run currently being viewed by route islands */
  viewedRunId: string | null;
  /** Progress data keyed by run id */
  progressByRunId: Record<string, RunProgress>;
  /** Milliseconds since last progress update */
  lastProgressMs: number;
  /** Current backoff delay for next active run poll (ms) */
  activeDelayMs: number;
  /** Whether an active-run fetch is in-flight */
  activeInFlight: boolean;
  /** Latest active-run request token */
  activeToken: number;
  /** Current backoff delay for next progress poll (ms) */
  progressDelayMs: number;
  /** Whether a progress fetch is in-flight */
  progressInFlight: boolean;
  /** Run id for the current progress fetch */
  progressInFlightRunId: string | null;
  /** Latest progress request token */
  progressToken: number;
  /** Recent completed runs for the history panel */
  recentRuns: Run[];
  /** Whether a recent-runs fetch is in-flight */
  recentInFlight: boolean;
  /** Current backoff delay for next recent-runs poll (ms) */
  recentDelayMs: number;
  /** Latest recent-runs request token */
  recentToken: number;
  /** Run detail overlay: which run is being viewed, or null */
  detailRunId: string | null;
  /** Run detail overlay: the Run object for the viewed run */
  detailRun: Run | null;
  /** Run detail overlay: fetched scenario results */
  detailResults: ScenarioResultView[];
  /** Run detail overlay: cursor position in scenario list */
  detailCursor: number;
  /** Run detail overlay: scroll offset for scenario list */
  detailScrollOffset: number;
}

/** Per-run progress snapshot used for polling display. */
export interface RunProgress {
  /** Whether the run progress snapshot exists. */
  exists: boolean;
  /** Run ID for this snapshot. */
  runId: string;
  /** Total number of scenarios in the run. */
  total: number;
  /** Number of scenarios completed so far. */
  completed: number;
  /** Name of the current scenario, if any. */
  currentScenario: string | null;
  /** ID of the current scenario, if any. */
  currentScenarioId: string | null;
  /** Elapsed time since run start, in milliseconds. */
  elapsedMs: number;
  /** Timestamp of the latest progress update. */
  updatedAt: number;
  /** Timestamp of the current poll tick. */
  now: number;
  /** Whether the run is currently running. */
  running: boolean;
}

/** Slice tracking discovered scenarios and fetch state. */
export interface ScenariosSlice {
  /** All known scenarios */
  all: ScenarioMeta[];
  /** Whether scenario list fetch is in-flight */
  fetchInFlight: boolean;
  /** Latest scenarios request token */
  token: number;
}

/** Metadata for a single discoverable scenario. */
export interface ScenarioMeta {
  /** Scenario identifier. */
  id: string;
  /** Scenario display name. */
  name: string;
  /** One-line scenario description. */
  description: string;
  /** Scenario category. */
  category: string;
  /** Whether the scenario requires PDS2. */
  needsPds2: boolean;
  /** Most recent recorded status for the scenario. */
  lastStatus?: "passed" | "failed" | "skipped" | null;
  /** Scenario parameter definitions. */
  parameters?: Record<string, {
    type: "number" | "string" | "boolean";
    default: string | number | boolean;
    description: string;
  }>;
}

/** Slice tracking topology selection, preview, and fetch state. */
export interface TopologySlice {
  /** Currently selected topology name */
  selected: string;
  /** Available topology names */
  available: Array<{ name: string }>;
  /** Preview data for the selected topology */
  preview: TopologyPreview | null;
  /** Whether topology preview fetch is in-flight */
  previewInFlight: boolean;
  /** Name for current preview request */
  previewInFlightName: string | null;
  /** Latest preview request token */
  previewToken: number;
}

/** Preview data for a topology preset. */
export interface TopologyPreview {
  /** Topology name. */
  name: string;
  /** Topology description, if provided. */
  description?: string;
  /** Roles included in the topology. */
  roles: string[];
  /** Capabilities exposed by the topology. */
  capabilities: string[];
}

/** Slice tracking log text by run ID and polling state. */
export interface LogsSlice {
  /** Raw log text keyed by run id */
  textByRunId: Record<string, string>;
  /** Whether a log fetch is in-flight */
  fetchInFlight: boolean;
  /** Run id for the current log fetch */
  inFlightRunId: string | null;
  /** Latest log request token */
  token: number;
  /** Current backoff delay for next log poll (ms) */
  delayMs: number;
  /** Milliseconds since last log update */
  lastUpdateMs: number;
}

/** Slice tracking container CPU/memory stats and polling state. */
export interface MetricsSlice {
  /** Per-role container stats */
  stats: Record<string, { cpu: string; mem: string }>;
  /** Whether a metrics fetch is in-flight */
  fetchInFlight: boolean;
  /** Latest metrics request token */
  token: number;
  /** Current backoff delay for next metrics poll (ms) */
  delayMs: number;
  /** Milliseconds since last metrics update */
  lastUpdateMs: number;
}

/** Slice tracking UI state: modals, search, categories, busy flag. */
export interface UxSlice {
  /** Whether a network operation (start/stop) is in progress */
  busy: boolean;
  /** Whether the settings modal is open */
  settingsOpen: boolean;
  /** Scenario parameter overrides */
  scenarioParams: Record<string, unknown>;
  /** Collapsed sidebar categories */
  collapsedCategories: Set<string>;
  /** Search term for scenario filtering */
  searchTerm: string;
}

// ---------------------------------------------------------------------------
// DashboardState (the Model)
// ---------------------------------------------------------------------------

/** Root dashboard model — union of all state slices. */
export interface DashboardState {
  /** Network state slice. */
  network: NetworkSlice;
  /** Run state slice. */
  runs: RunsSlice;
  /** Scenario discovery state slice. */
  scenarios: ScenariosSlice;
  /** Topology state slice. */
  topology: TopologySlice;
  /** Log polling state slice. */
  logs: LogsSlice;
  /** Metrics polling state slice. */
  metrics: MetricsSlice;
  /** UI state slice. */
  ux: UxSlice;
  /** Monotonic tick counter for elapsed time calculations */
  lastTickMs: number;
}

// ---------------------------------------------------------------------------
// Msg (discriminated union of all state transitions)
// ---------------------------------------------------------------------------

/** Discriminated union of all state transitions in the TEA model. */
export type Msg =
  | NetworkMsg
  | RunsMsg
  | ScenariosMsg
  | TopologyMsg
  | LogsMsg
  | MetricsMsg
  | UxMsg
  | { type: "tick"; nowMs: number };

// ---------------------------------------------------------------------------
// Sub-unions (per-slice Msg variants)
// ---------------------------------------------------------------------------

/** Network health and control messages. */
export type NetworkMsg =
  | { type: "network/healthReceived"; services: ServiceStatus[]; token?: number }
  | { type: "network/healthFailed"; error: string; token?: number }
  | { type: "network/healthTimeout"; token?: number }
  | { type: "network/startRequested"; pds2: boolean }
  | { type: "network/startSucceeded" }
  | { type: "network/startFailed"; error: string }
  | { type: "network/stopRequested" }
  | { type: "network/stopSucceeded" }
  | { type: "network/stopFailed"; error: string };

/** Run lifecycle, progress, control, events, and detail overlay messages. */
export type RunsMsg =
  | { type: "runs/activeReceived"; run: Run | null; token?: number }
  | { type: "runs/activeFailed"; error: string; token?: number }
  | { type: "runs/activeTimeout"; token?: number }
  | { type: "runs/hydrateRun"; run: Run }
  | { type: "runs/viewRun"; runId: string }
  | { type: "runs/progressReceived"; progress: RunProgress; runId?: string; token?: number }
  | { type: "runs/progressFailed"; error: string; runId?: string; token?: number }
  | { type: "runs/progressTimeout"; runId?: string; token?: number }
  | { type: "runs/startRequested"; scenarioIds: string[]; pds2: boolean }
  | { type: "runs/startSucceeded"; runId: string }
  | { type: "runs/startFailed"; error: string }
  | { type: "runs/stopRequested" }
  | { type: "runs/stopSucceeded" }
  | { type: "runs/stopFailed"; error: string }
  | { type: "runs/restartRequested" }
  | { type: "runs/restartSucceeded"; newRunId: string }
  | { type: "runs/restartFailed"; error: string }
  | { type: "runs/recentReceived"; runs: Run[]; token?: number }
  | { type: "runs/recentFailed"; error: string; token?: number }
  | { type: "runs/recentTimeout"; token?: number }
  | { type: "runs/event"; event: RunEvent }
  | { type: "runs/viewDetail"; runId: string; run: Run }
  | { type: "runs/closeDetail" }
  | { type: "runs/detailResults"; results: ScenarioResultView[] }
  | { type: "runs/detailCursorUp" }
  | { type: "runs/detailCursorDown" };

/** Scenario discovery messages. */
export type ScenariosMsg =
  | { type: "scenarios/received"; scenarios: ScenarioMeta[] }
  | { type: "scenarios/failed"; error: string };

/** Topology selection and preview messages. */
export type TopologyMsg =
  | { type: "topology/selected"; name: string }
  | { type: "topology/previewReceived"; preview: TopologyPreview; name?: string; token?: number }
  | { type: "topology/previewFailed"; error: string; name?: string; token?: number }
  | { type: "topology/listReceived"; topologies: Array<{ name: string }> }
  | { type: "topology/listFailed"; error: string };

/** Log polling messages. */
export type LogsMsg =
  | { type: "logs/received"; text: string; runId?: string; token?: number }
  | { type: "logs/failed"; error: string; runId?: string; token?: number }
  | { type: "logs/timeout"; runId?: string; token?: number };

/** Metrics polling messages. */
export type MetricsMsg =
  | {
    type: "metrics/received";
    stats: Record<string, { cpu: string; mem: string }>;
    token?: number;
  }
  | { type: "metrics/failed"; error: string; token?: number }
  | { type: "metrics/timeout"; token?: number };

/** UI interaction messages. */
export type UxMsg =
  | { type: "ux/toggleSettings" }
  | { type: "ux/setScenarioParam"; key: string; value: unknown }
  | { type: "ux/toggleCategory"; category: string }
  | { type: "ux/setSearchTerm"; term: string };

/** Type guard: does this Msg belong to a given slice prefix? */
function isNetworkMsg(msg: Msg): msg is NetworkMsg {
  return msg.type.startsWith("network/");
}
function isRunsMsg(msg: Msg): msg is RunsMsg {
  return msg.type.startsWith("runs/");
}
function isScenariosMsg(msg: Msg): msg is ScenariosMsg {
  return msg.type.startsWith("scenarios/");
}
function isTopologyMsg(msg: Msg): msg is TopologyMsg {
  return msg.type.startsWith("topology/");
}
function isLogsMsg(msg: Msg): msg is LogsMsg {
  return msg.type.startsWith("logs/");
}
function isMetricsMsg(msg: Msg): msg is MetricsMsg {
  return msg.type.startsWith("metrics/");
}
function isUxMsg(msg: Msg): msg is UxMsg {
  return msg.type.startsWith("ux/");
}

// ---------------------------------------------------------------------------
// Cmd (declarative effects — data, not functions)
// ---------------------------------------------------------------------------

/** Declarative effect type — data, not functions. Runtime interprets these into I/O. */
export type Cmd =
  | {
    type: "fetch";
    url: string;
    method?: string;
    body?: unknown;
    onSuccess: string;
    onError: string;
    meta?: Record<string, unknown>;
  }
  | { type: "schedule"; delayMs: number; msg: Msg }
  | { type: "navigate"; url: string }
  | { type: "none" };

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const BASE_HEALTH_CHECK_MS = 5000;
const BASE_PROGRESS_POLL_MS = 2000;
const BASE_ACTIVE_POLL_MS = 2000;
const BASE_LOG_POLL_MS = 2000;
const BASE_METRICS_POLL_MS = 3000;
const BASE_RECENT_POLL_MS = 5000;
const MAX_BACKOFF_MS = 30000;
/** Maximum entries kept in per-run-id maps (progress, logs) to prevent unbounded growth. */
const MAX_RUN_CACHE_SIZE = 20;
const BACKOFF_MULTIPLIER = 2;

/** Trim a Record to keep at most `max` entries, evicting the oldest keys first. */
function trimRecord<T>(record: Record<string, T>, max: number): Record<string, T> {
  const keys = Object.keys(record);
  if (keys.length <= max) return record;
  // Keep the last `max` entries (most recently added)
  const kept = keys.slice(-max);
  const result: Record<string, T> = {};
  for (const k of kept) result[k] = record[k]!;
  return result;
}

// ---------------------------------------------------------------------------
// Per-slice reducers
// ---------------------------------------------------------------------------

/** Update the network slice. Returns the updated slice and any commands. */
function updateNetwork(state: DashboardState, msg: NetworkMsg): [Partial<DashboardState>, Cmd[]] {
  switch (msg.type) {
    case "network/healthReceived": {
      if (!shouldAccept(state.network.healthToken, msg.token)) return [{}, []];
      const network: NetworkSlice = {
        ...state.network,
        services: msg.services,
        lastHealthCheckMs: 0,
        healthCheckDelayMs: BASE_HEALTH_CHECK_MS,
        healthCheckInFlight: false,
      };
      return [{ network }, [{
        type: "schedule",
        delayMs: BASE_HEALTH_CHECK_MS,
        msg: { type: "network/healthTimeout" },
      }]];
    }

    case "network/healthFailed": {
      if (!shouldAccept(state.network.healthToken, msg.token)) return [{}, []];
      const backoff = Math.min(
        state.network.healthCheckDelayMs * BACKOFF_MULTIPLIER,
        MAX_BACKOFF_MS,
      );
      const network: NetworkSlice = {
        ...state.network,
        healthCheckInFlight: false,
        healthCheckDelayMs: backoff,
      };
      return [{ network }, [{ type: "schedule", delayMs: backoff, msg: { type: "network/healthTimeout" } }]];
    }

    case "network/healthTimeout": {
      if (state.network.healthCheckInFlight) return [{}, []];
      const token = nextToken(state.network.healthToken);
      const network: NetworkSlice = {
        ...state.network,
        healthCheckInFlight: true,
        healthToken: token,
      };
      return [{ network }, [{
        type: "fetch",
        url: "/api/network/health",
        onSuccess: "network/healthReceived",
        onError: "network/healthFailed",
        meta: { token },
      }]];
    }

    // Network control messages touch both network and ux — handled by root update()
    default:
      return [{}, []];
  }
}

/** Update the scenarios slice. Returns the updated slice and any commands. */
function updateScenarios(state: DashboardState, msg: ScenariosMsg): [Partial<DashboardState>, Cmd[]] {
  switch (msg.type) {
    case "scenarios/received": {
      return [{ scenarios: { ...state.scenarios, all: msg.scenarios, fetchInFlight: false } }, []];
    }
    case "scenarios/failed": {
      return [{ scenarios: { ...state.scenarios, fetchInFlight: false } }, []];
    }
  }
}

/** Update the topology slice. Returns the updated slice and any commands. */
function updateTopology(state: DashboardState, msg: TopologyMsg): [Partial<DashboardState>, Cmd[]] {
  switch (msg.type) {
    case "topology/selected": {
      // Cross-slice: reads runs.active — handled by root update()
      return [{}, []];
    }

    case "topology/previewReceived": {
      if (msg.name && msg.name !== state.topology.previewInFlightName) return [{}, []];
      if (!shouldAccept(state.topology.previewToken, msg.token)) return [{}, []];
      return [{
        topology: {
          ...state.topology,
          preview: msg.preview,
          previewInFlight: false,
          previewInFlightName: null,
        },
      }, []];
    }

    case "topology/previewFailed": {
      if (msg.name && msg.name !== state.topology.previewInFlightName) return [{}, []];
      if (!shouldAccept(state.topology.previewToken, msg.token)) return [{}, []];
      return [{
        topology: { ...state.topology, previewInFlight: false, previewInFlightName: null },
      }, []];
    }

    case "topology/listReceived": {
      const names = msg.topologies.map((t) => t.name);
      const fallback = names.includes("garazyk-default")
        ? "garazyk-default"
        : names[0] ?? state.topology.selected;
      const selected = names.includes(state.topology.selected) ? state.topology.selected : fallback;
      const cmds: Cmd[] = [];
      if (selected !== state.topology.selected || !state.topology.preview) {
        const token = nextToken(state.topology.previewToken);
        cmds.push({
          type: "fetch",
          url: `/api/topologies/${selected}`,
          onSuccess: "topology/previewReceived",
          onError: "topology/previewFailed",
          meta: { name: selected, token },
        });
        return [{
          topology: {
            ...state.topology,
            available: msg.topologies,
            selected,
            previewInFlight: true,
            previewInFlightName: selected,
            previewToken: token,
          },
        }, cmds];
      }
      return [{ topology: { ...state.topology, available: msg.topologies, selected } }, cmds];
    }

    case "topology/listFailed": {
      return [{}, []];
    }
  }
}

/** Update the logs slice. Returns the updated slice and any commands. */
function updateLogs(state: DashboardState, msg: LogsMsg): [Partial<DashboardState>, Cmd[]] {
  switch (msg.type) {
    case "logs/received": {
      const runId = msg.runId ?? state.logs.inFlightRunId;
      if (!runId || runId !== state.logs.inFlightRunId || !shouldAccept(state.logs.token, msg.token)) {
        return [{}, []];
      }
      const isActive = state.runs.active?.id === runId && isLiveRun(state.runs.active);
      const delay = isActive ? BASE_LOG_POLL_MS : BASE_LOG_POLL_MS * 5;
      const logs: LogsSlice = {
        ...state.logs,
        textByRunId: trimRecord(
          { ...state.logs.textByRunId, [runId]: msg.text },
          MAX_RUN_CACHE_SIZE,
        ),
        fetchInFlight: false,
        inFlightRunId: null,
        delayMs: delay,
        lastUpdateMs: 0,
      };
      const cmds: Cmd[] = [];
      if (isActive) {
        cmds.push({ type: "schedule", delayMs: delay, msg: { type: "logs/timeout", runId } });
      }
      return [{ logs }, cmds];
    }

    case "logs/failed": {
      const runId = msg.runId ?? state.logs.inFlightRunId;
      if (!runId || runId !== state.logs.inFlightRunId || !shouldAccept(state.logs.token, msg.token)) {
        return [{}, []];
      }
      const backoff = Math.min(state.logs.delayMs * BACKOFF_MULTIPLIER, MAX_BACKOFF_MS);
      const isActive = state.runs.active?.id === runId && isLiveRun(state.runs.active);
      const logs: LogsSlice = {
        ...state.logs,
        fetchInFlight: false,
        inFlightRunId: null,
        delayMs: backoff,
      };
      const cmds: Cmd[] = [];
      if (isActive) {
        cmds.push({ type: "schedule", delayMs: backoff, msg: { type: "logs/timeout", runId } });
      }
      return [{ logs }, cmds];
    }

    case "logs/timeout": {
      if (state.logs.fetchInFlight) return [{}, []];
      const runId = msg.runId ?? state.runs.viewedRunId ?? state.runs.active?.id;
      if (!runId) return [{}, []];
      const token = nextToken(state.logs.token);
      const logs: LogsSlice = { ...state.logs, fetchInFlight: true, inFlightRunId: runId, token };
      return [{ logs }, [{
        type: "fetch",
        url: `/api/runs/${runId}/logs`,
        onSuccess: "logs/received",
        onError: "logs/failed",
        meta: { runId, token },
      }]];
    }
  }
}

/** Update the metrics slice. Returns the updated slice and any commands. */
function updateMetrics(state: DashboardState, msg: MetricsMsg): [Partial<DashboardState>, Cmd[]] {
  switch (msg.type) {
    case "metrics/received": {
      if (!shouldAccept(state.metrics.token, msg.token)) return [{}, []];
      const isActive = isLiveRun(state.runs.active);
      const delay = isActive ? BASE_METRICS_POLL_MS : BASE_METRICS_POLL_MS * 5;
      const metrics: MetricsSlice = {
        ...state.metrics,
        stats: msg.stats,
        fetchInFlight: false,
        delayMs: delay,
        lastUpdateMs: 0,
      };
      const cmds: Cmd[] = [];
      if (isActive) {
        cmds.push({ type: "schedule", delayMs: delay, msg: { type: "metrics/timeout" } });
      }
      return [{ metrics }, cmds];
    }

    case "metrics/failed": {
      if (!shouldAccept(state.metrics.token, msg.token)) return [{}, []];
      const backoff = Math.min(state.metrics.delayMs * BACKOFF_MULTIPLIER, MAX_BACKOFF_MS);
      const isActive = isLiveRun(state.runs.active);
      const metrics: MetricsSlice = {
        ...state.metrics,
        fetchInFlight: false,
        delayMs: backoff,
      };
      const cmds: Cmd[] = [];
      if (isActive) {
        cmds.push({ type: "schedule", delayMs: backoff, msg: { type: "metrics/timeout" } });
      }
      return [{ metrics }, cmds];
    }

    case "metrics/timeout": {
      if (state.metrics.fetchInFlight) return [{}, []];
      const isActive = isLiveRun(state.runs.active);
      if (!isActive) return [{}, []];
      const token = nextToken(state.metrics.token);
      const metrics: MetricsSlice = { ...state.metrics, fetchInFlight: true, token };
      return [{ metrics }, [{
        type: "fetch",
        url: "/api/runs/active/metrics",
        onSuccess: "metrics/received",
        onError: "metrics/failed",
        meta: { token },
      }]];
    }
  }
}

/** Update the UX slice. Returns the updated slice and any commands. */
function updateUx(state: DashboardState, msg: UxMsg): [Partial<DashboardState>, Cmd[]] {
  switch (msg.type) {
    case "ux/toggleSettings": {
      return [{ ux: { ...state.ux, settingsOpen: !state.ux.settingsOpen } }, []];
    }
    case "ux/setScenarioParam": {
      return [{ ux: { ...state.ux, scenarioParams: { ...state.ux.scenarioParams, [msg.key]: msg.value } } }, []];
    }
    case "ux/toggleCategory": {
      const next = new Set(state.ux.collapsedCategories);
      if (next.has(msg.category)) next.delete(msg.category);
      else next.add(msg.category);
      return [{ ux: { ...state.ux, collapsedCategories: next } }, []];
    }
    case "ux/setSearchTerm": {
      return [{ ux: { ...state.ux, searchTerm: msg.term } }, []];
    }
  }
}

// ---------------------------------------------------------------------------
// update() — pure state transition function (root dispatcher)
// ---------------------------------------------------------------------------

function isLiveRun(run: Run | null | undefined): boolean {
  return run?.status === "running" || run?.status === "starting" || run?.status === "stopping";
}

function nextToken(token: number | undefined): number {
  return (token ?? 0) + 1;
}

function shouldAccept(current: number, token: number | undefined): boolean {
  return token === undefined || token === current;
}

function selectedProgressRunId(state: DashboardState, msgRunId?: string): string | null {
  return msgRunId ?? state.runs.viewedRunId ?? state.runs.active?.id ?? null;
}

/** Pure state transition function. Takes current state and a Msg, returns next state and effects. */
export function update(state: DashboardState, msg: Msg): [DashboardState, Cmd[]] {
  // ── Delegate to slice reducers for single-slice messages ──────────────

  if (isScenariosMsg(msg)) {
    const [partial, cmds] = updateScenarios(state, msg);
    return [{ ...state, ...partial }, cmds];
  }

  if (isTopologyMsg(msg)) {
    // topology/selected has cross-slice reads — handle specially
    if (msg.type === "topology/selected") {
      if (isLiveRun(state.runs.active)) return [state, []];
      if (msg.name === state.topology.selected) return [state, []];
      const token = nextToken(state.topology.previewToken);
      return [{
        ...state,
        topology: {
          ...state.topology,
          selected: msg.name,
          previewInFlight: true,
          previewInFlightName: msg.name,
          previewToken: token,
        },
      }, [{
        type: "fetch",
        url: `/api/topologies/${msg.name}`,
        onSuccess: "topology/previewReceived",
        onError: "topology/previewFailed",
        meta: { name: msg.name, token },
      }]];
    }
    const [partial, cmds] = updateTopology(state, msg);
    return [{ ...state, ...partial }, cmds];
  }

  if (isLogsMsg(msg)) {
    const [partial, cmds] = updateLogs(state, msg);
    return [{ ...state, ...partial }, cmds];
  }

  if (isMetricsMsg(msg)) {
    const [partial, cmds] = updateMetrics(state, msg);
    return [{ ...state, ...partial }, cmds];
  }

  if (isUxMsg(msg)) {
    const [partial, cmds] = updateUx(state, msg);
    return [{ ...state, ...partial }, cmds];
  }

  // ── Network messages (some cross-slice) ──────────────────────────────

  if (isNetworkMsg(msg)) {
    // Health polling is pure network — delegate
    if (msg.type === "network/healthReceived" || msg.type === "network/healthFailed" || msg.type === "network/healthTimeout") {
      const [partial, cmds] = updateNetwork(state, msg);
      return [{ ...state, ...partial }, cmds];
    }

    // Network control messages touch ux — handle here
    switch (msg.type) {
      case "network/startRequested": {
        if (state.ux.busy || isLiveRun(state.runs.active)) return [state, []];
        const body = msg.pds2 ? { pds2: true } : {};
        return [
          { ...state, ux: { ...state.ux, busy: true } },
          [{
            type: "fetch",
            url: "/api/network/start",
            method: "POST",
            body,
            onSuccess: "network/startSucceeded",
            onError: "network/startFailed",
          }],
        ];
      }
      case "network/startSucceeded": {
        return [
          { ...state, ux: { ...state.ux, busy: false } },
          [{ type: "fetch", url: "/api/network/health", onSuccess: "network/healthReceived", onError: "network/healthFailed" }],
        ];
      }
      case "network/startFailed": {
        return [{ ...state, ux: { ...state.ux, busy: false } }, []];
      }
      case "network/stopRequested": {
        if (state.ux.busy || isLiveRun(state.runs.active)) return [state, []];
        return [
          { ...state, ux: { ...state.ux, busy: true } },
          [{
            type: "fetch",
            url: "/api/network/stop",
            method: "POST",
            onSuccess: "network/stopSucceeded",
            onError: "network/stopFailed",
          }],
        ];
      }
      case "network/stopSucceeded": {
        return [
          { ...state, ux: { ...state.ux, busy: false } },
          [{ type: "fetch", url: "/api/network/health", onSuccess: "network/healthReceived", onError: "network/healthFailed" }],
        ];
      }
      case "network/stopFailed": {
        return [{ ...state, ux: { ...state.ux, busy: false } }, []];
      }
    }
  }

  // ── Runs messages (many cross-slice) ─────────────────────────────────

  if (isRunsMsg(msg)) {
    switch (msg.type) {
      // ── Active run (cross-slice: updates runs, logs, metrics) ──────
      case "runs/activeReceived": {
        if (!shouldAccept(state.runs.activeToken, msg.token)) return [state, []];
        const cmds: Cmd[] = [];
        const isActive = isLiveRun(msg.run);
        const delay = isActive ? BASE_ACTIVE_POLL_MS : BASE_ACTIVE_POLL_MS * 5;

        let runs: RunsSlice = {
          ...state.runs,
          active: msg.run,
          activeInFlight: false,
          activeDelayMs: delay,
        };
        let logs = state.logs;
        let metrics = state.metrics;

        cmds.push({ type: "schedule", delayMs: delay, msg: { type: "runs/activeTimeout" } });

        const prevActiveId = state.runs.active?.id ?? null;
        const newActiveId = msg.run?.id ?? null;
        const runChanged = prevActiveId !== newActiveId;

        if (isActive && msg.run) {
          if (runChanged) {
            if (state.runs.progressInFlight && state.runs.progressInFlightRunId !== newActiveId) {
              runs = { ...runs, progressInFlight: false, progressInFlightRunId: null };
            }
            if (state.logs.fetchInFlight && state.logs.inFlightRunId !== newActiveId) {
              logs = { ...logs, fetchInFlight: false, inFlightRunId: null };
            }
            if (state.metrics.fetchInFlight) {
              metrics = { ...metrics, fetchInFlight: false };
            }
          }

          cmds.push({ type: "schedule", delayMs: 0, msg: { type: "runs/progressTimeout", runId: msg.run.id } });
          cmds.push({ type: "schedule", delayMs: 0, msg: { type: "logs/timeout", runId: msg.run.id } });
          cmds.push({ type: "schedule", delayMs: 0, msg: { type: "metrics/timeout" } });
        }

        if (!isActive) {
          // Run just stopped — keep last-known metrics visible (don't clear),
          // but trigger a recent-runs refresh so the completed run appears
          const refreshCmd: Cmd = { type: "fetch", url: "/api/runs/recent?limit=6", onSuccess: "runs/recentReceived", onError: "runs/recentFailed", meta: { token: nextToken(state.runs.recentToken) } };
          return [{ ...state, runs, logs, metrics }, [...cmds, refreshCmd]];
        }

        if (msg.run && !isActive && runs.progressByRunId[msg.run.id]) {
          const progressByRunId = { ...runs.progressByRunId };
          delete progressByRunId[msg.run.id];
          return [{ ...state, runs: { ...runs, progressByRunId }, logs, metrics }, cmds];
        }

        return [{ ...state, runs, logs, metrics }, cmds];
      }

      case "runs/activeFailed": {
        if (!shouldAccept(state.runs.activeToken, msg.token)) return [state, []];
        const backoff = Math.min(state.runs.activeDelayMs * BACKOFF_MULTIPLIER, MAX_BACKOFF_MS);
        return [
          { ...state, runs: { ...state.runs, activeInFlight: false, activeDelayMs: backoff } },
          [{ type: "schedule", delayMs: backoff, msg: { type: "runs/activeTimeout" } }],
        ];
      }

      case "runs/activeTimeout": {
        if (state.runs.activeInFlight) return [state, []];
        const token = nextToken(state.runs.activeToken);
        return [
          { ...state, runs: { ...state.runs, activeInFlight: true, activeToken: token } },
          [{ type: "fetch", url: "/api/runs/active", onSuccess: "runs/activeReceived", onError: "runs/activeFailed", meta: { token } }],
        ];
      }

      // ── Run progress (pure runs) ─────────────────────────────────
      case "runs/hydrateRun": {
        return [{ ...state, runs: { ...state.runs, viewedRunId: msg.run.id } }, [
          { type: "schedule", delayMs: 0, msg: { type: "runs/progressTimeout", runId: msg.run.id } },
          { type: "schedule", delayMs: 0, msg: { type: "logs/timeout", runId: msg.run.id } },
        ]];
      }

      case "runs/viewRun": {
        return [{ ...state, runs: { ...state.runs, viewedRunId: msg.runId } }, [
          { type: "schedule", delayMs: 0, msg: { type: "runs/progressTimeout", runId: msg.runId } },
          { type: "schedule", delayMs: 0, msg: { type: "logs/timeout", runId: msg.runId } },
        ]];
      }

      case "runs/progressReceived": {
        const runId = msg.runId ?? msg.progress.runId;
        if (runId !== state.runs.progressInFlightRunId || !shouldAccept(state.runs.progressToken, msg.token)) {
          return [state, []];
        }
        const isActive = state.runs.active?.id === runId && isLiveRun(state.runs.active);
        const delay = isActive ? BASE_PROGRESS_POLL_MS : BASE_PROGRESS_POLL_MS * 5;
        const runs: RunsSlice = {
          ...state.runs,
          progressByRunId: trimRecord({ ...state.runs.progressByRunId, [runId]: msg.progress }, MAX_RUN_CACHE_SIZE),
          lastProgressMs: 0,
          progressDelayMs: delay,
          progressInFlight: false,
          progressInFlightRunId: null,
        };
        const cmds: Cmd[] = [];
        if (isActive) cmds.push({ type: "schedule", delayMs: delay, msg: { type: "runs/progressTimeout", runId } });
        return [{ ...state, runs }, cmds];
      }

      case "runs/progressFailed": {
        const runId = msg.runId ?? state.runs.progressInFlightRunId;
        if (runId !== state.runs.progressInFlightRunId || !shouldAccept(state.runs.progressToken, msg.token)) {
          return [state, []];
        }
        const backoff = Math.min(state.runs.progressDelayMs * BACKOFF_MULTIPLIER, MAX_BACKOFF_MS);
        const isActive = state.runs.active?.id === runId && isLiveRun(state.runs.active);
        const cmds: Cmd[] = [];
        if (isActive) cmds.push({ type: "schedule", delayMs: backoff, msg: { type: "runs/progressTimeout", runId } });
        return [{ ...state, runs: { ...state.runs, progressInFlight: false, progressInFlightRunId: null, progressDelayMs: backoff } }, cmds];
      }

      case "runs/progressTimeout": {
        if (state.runs.progressInFlight) return [state, []];
        const runId = selectedProgressRunId(state, msg.runId);
        if (!runId) return [state, []];
        const token = nextToken(state.runs.progressToken);
        return [{ ...state, runs: { ...state.runs, progressInFlight: true, progressInFlightRunId: runId, progressToken: token } }, [{
          type: "fetch", url: `/api/runs/${runId}/progress`, onSuccess: "runs/progressReceived", onError: "runs/progressFailed", meta: { runId, token },
        }]];
      }

      // ── Run control (cross-slice: reads ux, runs, topology) ────────
      case "runs/startRequested": {
        if (state.ux.busy || isLiveRun(state.runs.active)) return [state, []];
        return [
          { ...state, ux: { ...state.ux, busy: true } },
          [{
            type: "fetch",
            url: "/api/runs/start",
            method: "POST",
            body: {
              topology: state.topology.selected,
              runner: "host",
              scenarioIds: msg.scenarioIds,
              pds2: msg.pds2,
              binaryMode: false,
              scenarioParams: state.ux.scenarioParams,
            },
            onSuccess: "runs/startSucceeded",
            onError: "runs/startFailed",
          }],
        ];
      }

      case "runs/startSucceeded": {
        return [{ ...state, ux: { ...state.ux, busy: false, settingsOpen: false } }, [{ type: "navigate", url: `/run/${msg.runId}` }]];
      }

      case "runs/startFailed": {
        return [{ ...state, ux: { ...state.ux, busy: false } }, []];
      }

      case "runs/stopRequested": {
        if (state.ux.busy) return [state, []];
        const runId = state.runs.active?.id;
        if (!runId) return [state, []];
        return [
          { ...state, ux: { ...state.ux, busy: true } },
          [{ type: "fetch", url: `/api/runs/${runId}/stop`, method: "POST", body: { graceful: true }, onSuccess: "runs/stopSucceeded", onError: "runs/stopFailed" }],
        ];
      }

      case "runs/stopSucceeded": {
        return [{ ...state, ux: { ...state.ux, busy: false } }, []];
      }

      case "runs/stopFailed": {
        return [{ ...state, ux: { ...state.ux, busy: false } }, []];
      }

      case "runs/restartRequested": {
        if (state.ux.busy) return [state, []];
        const runId = state.runs.active?.id;
        if (!runId) return [state, []];
        return [
          { ...state, ux: { ...state.ux, busy: true } },
          [{ type: "fetch", url: `/api/runs/${runId}/restart`, method: "POST", onSuccess: "runs/restartSucceeded", onError: "runs/restartFailed" }],
        ];
      }

      case "runs/restartSucceeded": {
        return [{ ...state, ux: { ...state.ux, busy: false } }, [{ type: "navigate", url: `/run/${msg.newRunId}` }]];
      }

      case "runs/restartFailed": {
        return [{ ...state, ux: { ...state.ux, busy: false } }, []];
      }

      // ── Recent runs (pure runs) ───────────────────────────────────
      case "runs/recentReceived": {
        if (!shouldAccept(state.runs.recentToken, msg.token)) return [state, []];
        return [{ ...state, runs: { ...state.runs, recentRuns: msg.runs, recentInFlight: false, recentDelayMs: BASE_RECENT_POLL_MS } }, [{ type: "schedule", delayMs: BASE_RECENT_POLL_MS, msg: { type: "runs/recentTimeout" } }]];
      }

      case "runs/recentFailed": {
        if (!shouldAccept(state.runs.recentToken, msg.token)) return [state, []];
        const backoff = Math.min(state.runs.recentDelayMs * BACKOFF_MULTIPLIER, MAX_BACKOFF_MS);
        return [{ ...state, runs: { ...state.runs, recentInFlight: false, recentDelayMs: backoff } }, [{ type: "schedule", delayMs: backoff, msg: { type: "runs/recentTimeout" } }]];
      }

      case "runs/recentTimeout": {
        if (state.runs.recentInFlight) return [state, []];
        const token = nextToken(state.runs.recentToken);
        return [{ ...state, runs: { ...state.runs, recentInFlight: true, recentToken: token } }, [{
          type: "fetch", url: "/api/runs/recent?limit=6", onSuccess: "runs/recentReceived", onError: "runs/recentFailed", meta: { token },
        }]];
      }

      // ── Run events (push-based, cross-slice: runs + ux + logs) ────
      case "runs/event": {
        const event = msg.event;
        switch (event.type) {
          case "run_started": {
            const run: Run = {
              id: event.runId,
              startedAt: event.startedAt,
              status: "starting",
              totalScenarios: event.totalScenarios,
              passed: 0,
              failed: 0,
              skipped: 0,
            };
            const runs: RunsSlice = {
              ...state.runs,
              active: run,
              activeInFlight: false,
              progressByRunId: trimRecord({
                ...state.runs.progressByRunId,
                [event.runId]: {
                  exists: true, runId: event.runId, total: event.totalScenarios, completed: 0,
                  currentScenario: null, currentScenarioId: null, elapsedMs: 0,
                  updatedAt: Date.now(), now: Date.now(), running: true,
                },
              }, MAX_RUN_CACHE_SIZE),
            };
            // Clear stale metrics from previous run when a new run starts
            const metrics: MetricsSlice = { ...state.metrics, stats: {} };
            return [{ ...state, runs, metrics, ux: { ...state.ux, busy: false } }, []];
          }

          case "run_status": {
            if (state.runs.active?.id !== event.runId) return [state, []];
            return [{ ...state, runs: { ...state.runs, active: { ...state.runs.active!, status: event.status } } }, []];
          }

          case "scenario_started": {
            if (state.runs.active?.id !== event.runId) return [state, []];
            const progress = state.runs.progressByRunId[event.runId];
            const updatedProgress: RunProgress = progress
              ? { ...progress, currentScenario: event.scenarioName, currentScenarioId: event.scenarioId }
              : {
                exists: true, runId: event.runId, total: state.runs.active.totalScenarios, completed: 0,
                currentScenario: event.scenarioName, currentScenarioId: event.scenarioId,
                elapsedMs: Date.now() - state.runs.active.startedAt, updatedAt: Date.now(), now: Date.now(), running: true,
              };
            return [{ ...state, runs: { ...state.runs, progressByRunId: trimRecord({ ...state.runs.progressByRunId, [event.runId]: updatedProgress }, MAX_RUN_CACHE_SIZE) } }, []];
          }

          case "scenario_finished": {
            const progress = state.runs.progressByRunId[event.runId];
            const prevCompleted = progress?.completed ?? 0;
            const updatedProgress: RunProgress = progress
              ? { ...progress, completed: prevCompleted + 1, currentScenario: null, currentScenarioId: null, updatedAt: Date.now(), now: Date.now() }
              : {
                exists: true, runId: event.runId, total: state.runs.active?.totalScenarios ?? 0, completed: 1,
                currentScenario: null, currentScenarioId: null, elapsedMs: 0, updatedAt: Date.now(), now: Date.now(), running: true,
              };
            let active = state.runs.active;
            if (active?.id === event.runId) {
              active = {
                ...active,
                passed: active.passed + (event.status === "passed" ? 1 : 0),
                failed: active.failed + (event.status === "failed" ? 1 : 0),
                skipped: active.skipped + (event.status === "skipped" ? 1 : 0),
              };
            }
            return [{ ...state, runs: { ...state.runs, active, progressByRunId: trimRecord({ ...state.runs.progressByRunId, [event.runId]: updatedProgress }, MAX_RUN_CACHE_SIZE) } }, []];
          }

          case "run_completed": {
            let active = state.runs.active;
            if (active?.id === event.runId) {
              active = { ...active, status: "completed", finishedAt: event.finishedAt, passed: event.passed, failed: event.failed, skipped: event.skipped };
            }
            const progress = state.runs.progressByRunId[event.runId];
            const finalProgress: RunProgress = progress
              ? { ...progress, running: false, updatedAt: Date.now(), now: Date.now() }
              : {
                exists: true, runId: event.runId, total: event.passed + event.failed + event.skipped,
                completed: event.passed + event.failed + event.skipped, currentScenario: null, currentScenarioId: null,
                elapsedMs: 0, updatedAt: Date.now(), now: Date.now(), running: false,
              };
            // Trigger immediate recent-runs refresh so completed run appears in history
            const refreshCmd: Cmd = { type: "fetch", url: "/api/runs/recent?limit=6", onSuccess: "runs/recentReceived", onError: "runs/recentFailed", meta: { token: nextToken(state.runs.recentToken) } };
            return [{ ...state, runs: { ...state.runs, active, progressByRunId: trimRecord({ ...state.runs.progressByRunId, [event.runId]: finalProgress }, MAX_RUN_CACHE_SIZE) }, ux: { ...state.ux, busy: false } }, [refreshCmd]];
          }

          case "run_failed": {
            let active = state.runs.active;
            if (active?.id === event.runId) {
              active = { ...active, status: "error", finishedAt: event.finishedAt, stopReason: event.reason, exitCode: event.exitCode };
            }
            // Trigger immediate recent-runs refresh so failed run appears in history
            const refreshCmd: Cmd = { type: "fetch", url: "/api/runs/recent?limit=6", onSuccess: "runs/recentReceived", onError: "runs/recentFailed", meta: { token: nextToken(state.runs.recentToken) } };
            return [{ ...state, runs: { ...state.runs, active }, ux: { ...state.ux, busy: false } }, [refreshCmd]];
          }

          case "log_line": {
            const prev = state.logs.textByRunId[event.runId] ?? "";
            const appended = prev + (prev ? "\n" : "") + event.line;
            return [{ ...state, logs: { ...state.logs, textByRunId: trimRecord({ ...state.logs.textByRunId, [event.runId]: appended }, MAX_RUN_CACHE_SIZE), lastUpdateMs: 0 } }, []];
          }

          default: {
            const _eventExhaustive: never = event;
            return [state, []];
          }
        }
      }

      // ── Run detail overlay (pure runs) ─────────────────────────────
      case "runs/viewDetail": {
        return [{ ...state, runs: { ...state.runs, detailRunId: msg.runId, detailRun: msg.run, detailResults: [], detailCursor: 0, detailScrollOffset: 0 } }, [{
          type: "fetch", url: `/api/runs/${msg.runId}/results`, onSuccess: "runs/detailResults", onError: "runs/closeDetail",
        }]];
      }

      case "runs/closeDetail": {
        return [{ ...state, runs: { ...state.runs, detailRunId: null, detailRun: null, detailResults: [], detailCursor: 0, detailScrollOffset: 0 } }, []];
      }

      case "runs/detailResults": {
        const cursor = Math.min(state.runs.detailCursor, Math.max(0, msg.results.length - 1));
        return [{ ...state, runs: { ...state.runs, detailResults: msg.results, detailCursor: cursor } }, []];
      }

      case "runs/detailCursorUp": {
        const cursor = Math.max(0, state.runs.detailCursor - 1);
        const scrollOffset = Math.min(state.runs.detailScrollOffset, cursor);
        return [{ ...state, runs: { ...state.runs, detailCursor: cursor, detailScrollOffset: scrollOffset } }, []];
      }

      case "runs/detailCursorDown": {
        const maxCursor = Math.max(0, state.runs.detailResults.length - 1);
        const cursor = Math.min(maxCursor, state.runs.detailCursor + 1);
        return [{ ...state, runs: { ...state.runs, detailCursor: cursor } }, []];
      }
    }
  }

  // ── Tick (cross-slice: updates network, runs, logs, metrics) ──────────

  if (msg.type === "tick") {
    const delta = msg.nowMs - state.lastTickMs;
    return [{
      ...state,
      network: { ...state.network, lastHealthCheckMs: state.network.lastHealthCheckMs + delta },
      runs: { ...state.runs, lastProgressMs: state.runs.lastProgressMs + delta },
      logs: { ...state.logs, lastUpdateMs: state.logs.lastUpdateMs + delta },
      metrics: { ...state.metrics, lastUpdateMs: state.metrics.lastUpdateMs + delta },
      lastTickMs: msg.nowMs,
    }, []];
  }

  // Exhaustiveness check — if TypeScript doesn't complain, all Msg variants are handled
  const _exhaustive: never = msg;
  return [state, []];
}

// ---------------------------------------------------------------------------
// Initial state factory
// ---------------------------------------------------------------------------

/** Create initial dashboard state with defaults, optionally overriding slices. */
export function createInitialState(overrides?: Partial<DashboardState>): DashboardState {
  return {
    network: {
      services: [],
      lastHealthCheckMs: 0,
      healthCheckDelayMs: BASE_HEALTH_CHECK_MS,
      healthCheckInFlight: false,
      healthToken: 0,
    },
    runs: {
      active: null,
      viewedRunId: null,
      progressByRunId: {},
      lastProgressMs: 0,
      activeDelayMs: BASE_ACTIVE_POLL_MS,
      activeInFlight: false,
      activeToken: 0,
      progressDelayMs: BASE_PROGRESS_POLL_MS,
      progressInFlight: false,
      progressInFlightRunId: null,
      progressToken: 0,
      recentRuns: [],
      recentInFlight: false,
      recentDelayMs: BASE_RECENT_POLL_MS,
      recentToken: 0,
      detailRunId: null,
      detailRun: null,
      detailResults: [],
      detailCursor: 0,
      detailScrollOffset: 0,
    },
    scenarios: {
      all: [],
      fetchInFlight: false,
      token: 0,
    },
    topology: {
      selected: "garazyk-default",
      available: [],
      preview: null,
      previewInFlight: false,
      previewInFlightName: null,
      previewToken: 0,
    },
    logs: {
      textByRunId: {},
      fetchInFlight: false,
      inFlightRunId: null,
      token: 0,
      delayMs: BASE_LOG_POLL_MS,
      lastUpdateMs: 0,
    },
    metrics: {
      stats: {},
      fetchInFlight: false,
      token: 0,
      delayMs: BASE_METRICS_POLL_MS,
      lastUpdateMs: 0,
    },
    ux: {
      busy: false,
      settingsOpen: false,
      scenarioParams: {},
      collapsedCategories: new Set(["edge"]),
      searchTerm: "",
    },
    lastTickMs: 0,
    ...overrides,
  } as DashboardState;
}

// ---------------------------------------------------------------------------
// Boot Cmds — the initial effects to run when the dashboard loads
// ---------------------------------------------------------------------------

/** Initial effects to run when the dashboard loads: health check, active run, scenarios, topologies. */
export function bootCmds(): Cmd[] {
  return [
    {
      type: "fetch",
      url: "/api/network/health",
      onSuccess: "network/healthReceived",
      onError: "network/healthFailed",
    },
    {
      type: "fetch",
      url: "/api/runs/active",
      onSuccess: "runs/activeReceived",
      onError: "runs/activeFailed",
    },
    {
      type: "fetch",
      url: "/api/scenarios",
      onSuccess: "scenarios/received",
      onError: "scenarios/failed",
    },
    {
      type: "fetch",
      url: "/api/topologies",
      onSuccess: "topology/listReceived",
      onError: "topology/listFailed",
    },
    {
      type: "fetch",
      url: "/api/runs/recent?limit=6",
      onSuccess: "runs/recentReceived",
      onError: "runs/recentFailed",
    },
  ];
}
