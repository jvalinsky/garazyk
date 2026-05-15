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

import type { ServiceStatus, Run, ScenarioResult } from "./services/types.ts";

// ---------------------------------------------------------------------------
// State slices
// ---------------------------------------------------------------------------

export interface NetworkSlice {
  services: ServiceStatus[];
  /** Milliseconds since last successful health check response */
  lastHealthCheckMs: number;
  /** Current backoff delay for next health check (ms) */
  healthCheckDelayMs: number;
  /** Whether a health check fetch is in-flight */
  healthCheckInFlight: boolean;
}

export interface RunsSlice {
  /** Currently active run, if any */
  active: Run | null;
  /** Progress data for the active run */
  progress: RunProgress | null;
  /** Milliseconds since last progress update */
  lastProgressMs: number;
  /** Current backoff delay for next progress poll (ms) */
  progressDelayMs: number;
  /** Whether a progress fetch is in-flight */
  progressInFlight: boolean;
}

export interface RunProgress {
  exists: boolean;
  runId: string;
  total: number;
  completed: number;
  currentScenario: string | null;
  currentScenarioId: string | null;
  elapsedMs: number;
  updatedAt: number;
  now: number;
  running: boolean;
}

export interface ScenariosSlice {
  /** All known scenarios */
  all: ScenarioMeta[];
  /** Whether scenario list fetch is in-flight */
  fetchInFlight: boolean;
}

export interface ScenarioMeta {
  id: string;
  name: string;
  category: string;
  needsPds2: boolean;
  lastStatus?: "passed" | "failed" | "skipped" | null;
  parameters?: Record<string, {
    type: "number" | "string" | "boolean";
    default: string | number | boolean;
    description: string;
  }>;
}

export interface TopologySlice {
  /** Currently selected topology name */
  selected: string;
  /** Available topology names */
  available: Array<{ name: string }>;
  /** Preview data for the selected topology */
  preview: TopologyPreview | null;
  /** Whether topology preview fetch is in-flight */
  previewInFlight: boolean;
}

export interface TopologyPreview {
  name: string;
  description?: string;
  roles: string[];
  capabilities: string[];
}

export interface LogsSlice {
  /** Raw log text for the active run */
  text: string;
  /** Whether a log fetch is in-flight */
  fetchInFlight: boolean;
  /** Current backoff delay for next log poll (ms) */
  delayMs: number;
  /** Milliseconds since last log update */
  lastUpdateMs: number;
}

export interface MetricsSlice {
  /** Per-role container stats */
  stats: Record<string, { cpu: string; mem: string }>;
  /** Whether a metrics fetch is in-flight */
  fetchInFlight: boolean;
  /** Current backoff delay for next metrics poll (ms) */
  delayMs: number;
  /** Milliseconds since last metrics update */
  lastUpdateMs: number;
}

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

export interface DashboardState {
  network: NetworkSlice;
  runs: RunsSlice;
  scenarios: ScenariosSlice;
  topology: TopologySlice;
  logs: LogsSlice;
  metrics: MetricsSlice;
  ux: UxSlice;
  /** Monotonic tick counter for elapsed time calculations */
  lastTickMs: number;
}

// ---------------------------------------------------------------------------
// Msg (discriminated union of all state transitions)
// ---------------------------------------------------------------------------

export type Msg =
  // Network health
  | { type: "network/healthReceived"; services: ServiceStatus[] }
  | { type: "network/healthFailed"; error: string }
  | { type: "network/healthTimeout" }
  // Network control
  | { type: "network/startRequested"; pds2: boolean }
  | { type: "network/startSucceeded" }
  | { type: "network/startFailed"; error: string }
  | { type: "network/stopRequested" }
  | { type: "network/stopSucceeded" }
  | { type: "network/stopFailed"; error: string }
  // Active run
  | { type: "runs/activeReceived"; run: Run | null }
  | { type: "runs/activeFailed"; error: string }
  | { type: "runs/activeTimeout" }
  // Run progress
  | { type: "runs/progressReceived"; progress: RunProgress }
  | { type: "runs/progressFailed"; error: string }
  | { type: "runs/progressTimeout" }
  // Run control
  | { type: "runs/startRequested"; scenarioIds: string[]; pds2: boolean }
  | { type: "runs/startSucceeded"; runId: string }
  | { type: "runs/startFailed"; error: string }
  | { type: "runs/stopRequested" }
  | { type: "runs/stopSucceeded" }
  | { type: "runs/stopFailed"; error: string }
  | { type: "runs/restartRequested" }
  | { type: "runs/restartSucceeded"; newRunId: string }
  | { type: "runs/restartFailed"; error: string }
  // Scenarios
  | { type: "scenarios/received"; scenarios: ScenarioMeta[] }
  | { type: "scenarios/failed"; error: string }
  // Topology
  | { type: "topology/selected"; name: string }
  | { type: "topology/previewReceived"; preview: TopologyPreview }
  | { type: "topology/previewFailed"; error: string }
  | { type: "topology/listReceived"; topologies: Array<{ name: string }> }
  | { type: "topology/listFailed"; error: string }
  // Logs
  | { type: "logs/received"; text: string }
  | { type: "logs/failed"; error: string }
  | { type: "logs/timeout" }
  // Metrics
  | { type: "metrics/received"; stats: Record<string, { cpu: string; mem: string }> }
  | { type: "metrics/failed"; error: string }
  | { type: "metrics/timeout" }
  // UX
  | { type: "ux/toggleSettings" }
  | { type: "ux/setScenarioParam"; key: string; value: unknown }
  | { type: "ux/toggleCategory"; category: string }
  | { type: "ux/setSearchTerm"; term: string }
  // Tick (for elapsed time display)
  | { type: "tick"; nowMs: number };

// ---------------------------------------------------------------------------
// Cmd (declarative effects — data, not functions)
// ---------------------------------------------------------------------------

export type Cmd =
  | { type: "fetch"; url: string; method?: string; body?: unknown; onSuccess: string; onError: string }
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
const MAX_BACKOFF_MS = 30000;
const BACKOFF_MULTIPLIER = 2;

// ---------------------------------------------------------------------------
// update() — pure state transition function
// ---------------------------------------------------------------------------

export function update(state: DashboardState, msg: Msg): [DashboardState, Cmd[]] {
  switch (msg.type) {
    // ── Network health ──────────────────────────────────────────────────

    case "network/healthReceived": {
      const cmds: Cmd[] = [];

      const network: NetworkSlice = {
        ...state.network,
        services: msg.services,
        lastHealthCheckMs: 0,
        healthCheckDelayMs: BASE_HEALTH_CHECK_MS, // reset on success
        healthCheckInFlight: false,
      };

      // Schedule next health check
      cmds.push({ type: "schedule", delayMs: BASE_HEALTH_CHECK_MS, msg: { type: "network/healthTimeout" } });

      return [{ ...state, network }, cmds];
    }

    case "network/healthFailed": {
      const backoff = Math.min(
        state.network.healthCheckDelayMs * BACKOFF_MULTIPLIER,
        MAX_BACKOFF_MS,
      );
      const cmds: Cmd[] = [];
      const network: NetworkSlice = {
        ...state.network,
        healthCheckInFlight: false,
        healthCheckDelayMs: backoff,
      };

      cmds.push({ type: "schedule", delayMs: backoff, msg: { type: "network/healthTimeout" } });

      return [{ ...state, network }, cmds];
    }

    case "network/healthTimeout": {
      if (state.network.healthCheckInFlight) {
        // Already in flight — skip (deduplication)
        return [state, []];
      }
      const network: NetworkSlice = {
        ...state.network,
        healthCheckInFlight: true,
      };
      const cmd: Cmd = {
        type: "fetch",
        url: "/api/network/health",
        onSuccess: "network/healthReceived",
        onError: "network/healthFailed",
      };
      return [{ ...state, network }, [cmd]];
    }

    // ── Network control ─────────────────────────────────────────────────

    case "network/startRequested": {
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
      // Re-fetch health after starting
      return [
        { ...state, ux: { ...state.ux, busy: false } },
        [
          { type: "fetch", url: "/api/network/health", onSuccess: "network/healthReceived", onError: "network/healthFailed" },
        ],
      ];
    }

    case "network/startFailed": {
      return [{ ...state, ux: { ...state.ux, busy: false } }, []];
    }

    case "network/stopRequested": {
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
        [
          { type: "fetch", url: "/api/network/health", onSuccess: "network/healthReceived", onError: "network/healthFailed" },
        ],
      ];
    }

    case "network/stopFailed": {
      return [{ ...state, ux: { ...state.ux, busy: false } }, []];
    }

    // ── Active run ──────────────────────────────────────────────────────

    case "runs/activeReceived": {
      const cmds: Cmd[] = [];
      const isActive = msg.run?.status === "running" || msg.run?.status === "starting" || msg.run?.status === "stopping";
      const delay = isActive ? BASE_ACTIVE_POLL_MS : BASE_ACTIVE_POLL_MS * 5; // 10s when idle

      const runs: RunsSlice = {
        ...state.runs,
        active: msg.run,
        progressInFlight: false,
      };

      cmds.push({ type: "schedule", delayMs: delay, msg: { type: "runs/activeTimeout" } });

      // Kick off log and metrics polling when a run becomes active
      if (isActive && !state.logs.fetchInFlight) {
        cmds.push({ type: "schedule", delayMs: 0, msg: { type: "logs/timeout" } });
      }
      if (isActive && !state.metrics.fetchInFlight) {
        cmds.push({ type: "schedule", delayMs: 0, msg: { type: "metrics/timeout" } });
      }

      // Clear metrics when no active run
      if (!isActive && Object.keys(state.metrics.stats).length > 0) {
        return [{ ...state, runs, metrics: { ...state.metrics, stats: {} } }, cmds];
      }

      // If run just completed, clear progress
      if (msg.run && !isActive && state.runs.progress) {
        return [{ ...state, runs: { ...runs, progress: null } }, cmds];
      }

      return [{ ...state, runs }, cmds];
    }

    case "runs/activeFailed": {
      const backoff = Math.min(state.runs.progressDelayMs * BACKOFF_MULTIPLIER, MAX_BACKOFF_MS);
      const cmds: Cmd[] = [];
      cmds.push({ type: "schedule", delayMs: backoff, msg: { type: "runs/activeTimeout" } });
      return [{ ...state, runs: { ...state.runs, progressInFlight: false, progressDelayMs: backoff } }, cmds];
    }

    case "runs/activeTimeout": {
      if (state.runs.progressInFlight) return [state, []]; // dedup
      const runs: RunsSlice = { ...state.runs, progressInFlight: true };
      return [
        { ...state, runs },
        [{ type: "fetch", url: "/api/runs/active", onSuccess: "runs/activeReceived", onError: "runs/activeFailed" }],
      ];
    }

    // ── Run progress ────────────────────────────────────────────────────

    case "runs/progressReceived": {
      const cmds: Cmd[] = [];
      const isActive = state.runs.active?.status === "running";
      const delay = isActive ? BASE_PROGRESS_POLL_MS : BASE_PROGRESS_POLL_MS * 5;

      const runs: RunsSlice = {
        ...state.runs,
        progress: msg.progress,
        lastProgressMs: 0,
        progressDelayMs: delay,
        progressInFlight: false,
      };

      if (isActive) {
        cmds.push({ type: "schedule", delayMs: delay, msg: { type: "runs/progressTimeout" } });
      }

      return [{ ...state, runs }, cmds];
    }

    case "runs/progressFailed": {
      const backoff = Math.min(state.runs.progressDelayMs * BACKOFF_MULTIPLIER, MAX_BACKOFF_MS);
      const cmds: Cmd[] = [];
      const isActive = state.runs.active?.status === "running";
      if (isActive) {
        cmds.push({ type: "schedule", delayMs: backoff, msg: { type: "runs/progressTimeout" } });
      }
      return [{ ...state, runs: { ...state.runs, progressInFlight: false, progressDelayMs: backoff } }, cmds];
    }

    case "runs/progressTimeout": {
      if (state.runs.progressInFlight) return [state, []]; // dedup
      const runId = state.runs.active?.id;
      if (!runId) return [state, []];
      const runs: RunsSlice = { ...state.runs, progressInFlight: true };
      return [
        { ...state, runs },
        [{
          type: "fetch",
          url: `/api/runs/${runId}/progress`,
          onSuccess: "runs/progressReceived",
          onError: "runs/progressFailed",
        }],
      ];
    }

    // ── Run control ─────────────────────────────────────────────────────

    case "runs/startRequested": {
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
      return [
        { ...state, ux: { ...state.ux, busy: false, settingsOpen: false } },
        [{ type: "navigate", url: `/run/${msg.runId}` }],
      ];
    }

    case "runs/startFailed": {
      return [{ ...state, ux: { ...state.ux, busy: false } }, []];
    }

    case "runs/stopRequested": {
      const runId = state.runs.active?.id;
      if (!runId) return [state, []];
      return [
        { ...state, ux: { ...state.ux, busy: true } },
        [{
          type: "fetch",
          url: `/api/runs/${runId}/stop`,
          method: "POST",
          body: { graceful: true },
          onSuccess: "runs/stopSucceeded",
          onError: "runs/stopFailed",
        }],
      ];
    }

    case "runs/stopSucceeded": {
      return [{ ...state, ux: { ...state.ux, busy: false } }, []];
    }

    case "runs/stopFailed": {
      return [{ ...state, ux: { ...state.ux, busy: false } }, []];
    }

    case "runs/restartRequested": {
      const runId = state.runs.active?.id;
      if (!runId) return [state, []];
      return [
        { ...state, ux: { ...state.ux, busy: true } },
        [{
          type: "fetch",
          url: `/api/runs/${runId}/restart`,
          method: "POST",
          onSuccess: "runs/restartSucceeded",
          onError: "runs/restartFailed",
        }],
      ];
    }

    case "runs/restartSucceeded": {
      return [
        { ...state, ux: { ...state.ux, busy: false } },
        [{ type: "navigate", url: `/run/${msg.newRunId}` }],
      ];
    }

    case "runs/restartFailed": {
      return [{ ...state, ux: { ...state.ux, busy: false } }, []];
    }

    // ── Scenarios ────────────────────────────────────────────────────────

    case "scenarios/received": {
      return [{ ...state, scenarios: { ...state.scenarios, all: msg.scenarios, fetchInFlight: false } }, []];
    }

    case "scenarios/failed": {
      return [{ ...state, scenarios: { ...state.scenarios, fetchInFlight: false } }, []];
    }

    // ── Topology ─────────────────────────────────────────────────────────

    case "topology/selected": {
      if (msg.name === state.topology.selected) {
        return [state, []]; // no-op when same topology
      }
      return [
        { ...state, topology: { ...state.topology, selected: msg.name, previewInFlight: true } },
        [{
          type: "fetch",
          url: `/api/topologies/${msg.name}`,
          onSuccess: "topology/previewReceived",
          onError: "topology/previewFailed",
        }],
      ];
    }

    case "topology/previewReceived": {
      return [
        { ...state, topology: { ...state.topology, preview: msg.preview, previewInFlight: false } },
        [],
      ];
    }

    case "topology/previewFailed": {
      return [{ ...state, topology: { ...state.topology, previewInFlight: false } }, []];
    }

    case "topology/listReceived": {
      return [{ ...state, topology: { ...state.topology, available: msg.topologies } }, []];
    }

    case "topology/listFailed": {
      return [state, []];
    }

    // ── Logs ────────────────────────────────────────────────────────────

    case "logs/received": {
      const isActive = state.runs.active?.status === "running";
      const delay = isActive ? BASE_LOG_POLL_MS : BASE_LOG_POLL_MS * 5;
      const logs: LogsSlice = {
        ...state.logs,
        text: msg.text,
        fetchInFlight: false,
        delayMs: delay,
        lastUpdateMs: 0,
      };
      const cmds: Cmd[] = [];
      if (isActive) {
        cmds.push({ type: "schedule", delayMs: delay, msg: { type: "logs/timeout" } });
      }
      return [{ ...state, logs }, cmds];
    }

    case "logs/failed": {
      const backoff = Math.min(state.logs.delayMs * BACKOFF_MULTIPLIER, MAX_BACKOFF_MS);
      const isActive = state.runs.active?.status === "running";
      const logs: LogsSlice = {
        ...state.logs,
        fetchInFlight: false,
        delayMs: backoff,
      };
      const cmds: Cmd[] = [];
      if (isActive) {
        cmds.push({ type: "schedule", delayMs: backoff, msg: { type: "logs/timeout" } });
      }
      return [{ ...state, logs }, cmds];
    }

    case "logs/timeout": {
      if (state.logs.fetchInFlight) return [state, []]; // dedup
      const runId = state.runs.active?.id;
      if (!runId) return [state, []];
      const logs: LogsSlice = { ...state.logs, fetchInFlight: true };
      return [
        { ...state, logs },
        [{ type: "fetch", url: `/api/runs/${runId}/logs`, onSuccess: "logs/received", onError: "logs/failed" }],
      ];
    }

    // ── Metrics ─────────────────────────────────────────────────────────

    case "metrics/received": {
      const isActive = state.runs.active?.status === "running";
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
      return [{ ...state, metrics }, cmds];
    }

    case "metrics/failed": {
      const backoff = Math.min(state.metrics.delayMs * BACKOFF_MULTIPLIER, MAX_BACKOFF_MS);
      const isActive = state.runs.active?.status === "running";
      const metrics: MetricsSlice = {
        ...state.metrics,
        fetchInFlight: false,
        delayMs: backoff,
      };
      const cmds: Cmd[] = [];
      if (isActive) {
        cmds.push({ type: "schedule", delayMs: backoff, msg: { type: "metrics/timeout" } });
      }
      return [{ ...state, metrics }, cmds];
    }

    case "metrics/timeout": {
      if (state.metrics.fetchInFlight) return [state, []]; // dedup
      const isActive = state.runs.active?.status === "running";
      if (!isActive) return [state, []];
      const metrics: MetricsSlice = { ...state.metrics, fetchInFlight: true };
      return [
        { ...state, metrics },
        [{ type: "fetch", url: "/api/runs/active/metrics", onSuccess: "metrics/received", onError: "metrics/failed" }],
      ];
    }

    // ── UX ───────────────────────────────────────────────────────────────

    case "ux/toggleSettings": {
      return [{ ...state, ux: { ...state.ux, settingsOpen: !state.ux.settingsOpen } }, []];
    }

    case "ux/setScenarioParam": {
      return [{
        ...state,
        ux: { ...state.ux, scenarioParams: { ...state.ux.scenarioParams, [msg.key]: msg.value } },
      }, []];
    }

    case "ux/toggleCategory": {
      const next = new Set(state.ux.collapsedCategories);
      if (next.has(msg.category)) next.delete(msg.category);
      else next.add(msg.category);
      return [{ ...state, ux: { ...state.ux, collapsedCategories: next } }, []];
    }

    case "ux/setSearchTerm": {
      return [{ ...state, ux: { ...state.ux, searchTerm: msg.term } }, []];
    }

    // ── Tick ─────────────────────────────────────────────────────────────

    case "tick": {
      const delta = msg.nowMs - state.lastTickMs;
      const network: NetworkSlice = {
        ...state.network,
        lastHealthCheckMs: state.network.lastHealthCheckMs + delta,
      };
      const runs: RunsSlice = {
        ...state.runs,
        lastProgressMs: state.runs.lastProgressMs + delta,
      };
      const logs: LogsSlice = {
        ...state.logs,
        lastUpdateMs: state.logs.lastUpdateMs + delta,
      };
      const metrics: MetricsSlice = {
        ...state.metrics,
        lastUpdateMs: state.metrics.lastUpdateMs + delta,
      };
      return [{ ...state, network, runs, logs, metrics, lastTickMs: msg.nowMs }, []];
    }

    default: {
      // Exhaustiveness check — if TypeScript doesn't complain, all Msg variants are handled
      const _exhaustive: never = msg;
      return [state, []];
    }
  }
}

// ---------------------------------------------------------------------------
// Initial state factory
// ---------------------------------------------------------------------------

export function createInitialState(overrides?: Partial<DashboardState>): DashboardState {
  return {
    network: {
      services: [],
      lastHealthCheckMs: 0,
      healthCheckDelayMs: BASE_HEALTH_CHECK_MS,
      healthCheckInFlight: false,
    },
    runs: {
      active: null,
      progress: null,
      lastProgressMs: 0,
      progressDelayMs: BASE_PROGRESS_POLL_MS,
      progressInFlight: false,
    },
    scenarios: {
      all: [],
      fetchInFlight: false,
    },
    topology: {
      selected: "garazyk-default",
      available: [],
      preview: null,
      previewInFlight: false,
    },
    logs: {
      text: "",
      fetchInFlight: false,
      delayMs: BASE_LOG_POLL_MS,
      lastUpdateMs: 0,
    },
    metrics: {
      stats: {},
      fetchInFlight: false,
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

export function bootCmds(): Cmd[] {
  return [
    { type: "fetch", url: "/api/network/health", onSuccess: "network/healthReceived", onError: "network/healthFailed" },
    { type: "fetch", url: "/api/runs/active", onSuccess: "runs/activeReceived", onError: "runs/activeFailed" },
    { type: "fetch", url: "/api/scenarios", onSuccess: "scenarios/received", onError: "scenarios/failed" },
    { type: "fetch", url: "/api/topologies", onSuccess: "topology/listReceived", onError: "topology/listFailed" },
  ];
}
