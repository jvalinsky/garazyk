/**
 * TUI Runtime — TEA runtime that interprets Cmds as direct service calls
 *
 * Reuses the existing DashboardState + Msg + update() state machine unchanged.
 * The only difference from the web runtime is how Cmd.fetch is interpreted:
 * instead of HTTP fetch to the web server, we call service methods directly.
 *
 * @module tui/runtime
 */

import { join } from "@std/path";
import type { Cmd, DashboardState, Msg, RunProgress, TopologyPreview } from "../dashboard_state.ts";
import { bootCmds, createInitialState, update } from "../dashboard_state.ts";
import type { Run, ServiceStatus } from "../services/types.ts";

// ---------------------------------------------------------------------------
// Runtime handle
// ---------------------------------------------------------------------------

/** Handle returned by createTuiRuntime — accessor for state, dispatch, and cleanup. */
export interface TuiRuntimeHandle {
  /** Current dashboard state */
  state: DashboardState;
  /** Dispatch a message to update state */
  dispatch: (msg: Msg) => void;
  /** Clean up all timers and resources */
  destroy: () => void;
  /** Subscribe to state changes */
  onChange: (fn: (state: DashboardState) => void) => () => void;
}

// ---------------------------------------------------------------------------
// Service module cache (lazy-loaded)
// ---------------------------------------------------------------------------

interface ServiceModules {
  network: typeof import("../services/network_manager.ts");
  run: typeof import("../services/run_manager.ts");
  db: typeof import("../db/index.ts");
  queries: typeof import("../db/queries.ts");
  scenarios: typeof import("../services/scenario_discovery.ts");
  topology: typeof import("../services/topology_service.ts");
}

let serviceModules: ServiceModules | null = null;

async function loadServices(): Promise<ServiceModules> {
  if (serviceModules) return serviceModules;
  const [network, run, db, queries, scenarios, topology] = await Promise.all([
    import("../services/network_manager.ts"),
    import("../services/run_manager.ts"),
    import("../db/index.ts"),
    import("../db/queries.ts"),
    import("../services/scenario_discovery.ts"),
    import("../services/topology_service.ts"),
  ]);
  serviceModules = { network, run, db, queries, scenarios, topology };
  return serviceModules;
}

// ---------------------------------------------------------------------------
// URL → service method mapping
// ---------------------------------------------------------------------------

type ServiceHandler = (url: string, method: string | undefined, body: unknown) => Promise<unknown>;

async function resolveServiceHandler(url: string): Promise<ServiceHandler | null> {
  const svc = await loadServices();

  // /api/network/health
  if (url === "/api/network/health") {
    return async () => {
      const serviceMap = await svc.network.networkManager.healthCheck();
      return { services: Object.values(serviceMap) };
    };
  }

  // /api/network/start
  if (url === "/api/network/start") {
    return async (_url: string, _method: string | undefined, body: unknown) => {
      const opts = body as { pds2?: boolean } | undefined;
      await svc.network.networkManager.startAll({ pds2: opts?.pds2 });
      return {};
    };
  }

  // /api/network/stop
  if (url === "/api/network/stop") {
    return async () => {
      await svc.network.networkManager.stopAll();
      return {};
    };
  }

  // /api/runs/active
  if (url === "/api/runs/active") {
    return () => Promise.resolve({ activeRun: svc.run.runManager.getActiveRun() ?? null });
  }

  // /api/runs/active/metrics
  if (url === "/api/runs/active/metrics") {
    return async () => {
      const stats = await svc.network.networkManager.getContainerStats();
      return { stats };
    };
  }

  // /api/runs/start
  if (url === "/api/runs/start") {
    return async (_url: string, _method: string | undefined, body: unknown) => {
      const config = body as {
        topology: string;
        runner: "host" | "docker";
        scenarioIds: string[];
        pds2: boolean;
        binaryMode: boolean;
        scenarioParams?: Record<string, string | number | boolean>;
      };
      const result = await svc.run.runManager.startRun(config);
      if ("conflict" in result) {
        throw new Error(result.conflict);
      }
      return { runId: result.runId };
    };
  }

  // /api/runs/:id/stop
  const stopMatch = url.match(/^\/api\/runs\/([^/]+)\/stop$/);
  if (stopMatch) {
    const runId = stopMatch[1]!;
    return async () => {
      await svc.run.runManager.stopRun(runId, true);
      return {};
    };
  }

  // /api/runs/:id/restart
  const restartMatch = url.match(/^\/api\/runs\/([^/]+)\/restart$/);
  if (restartMatch) {
    const runId = restartMatch[1]!;
    return async () => {
      const result = await svc.run.runManager.restartRun(runId);
      if ("error" in result) {
        throw new Error(result.error);
      }
      return { newRunId: result.newRunId };
    };
  }

  // /api/runs/:id/progress
  const progressMatch = url.match(/^\/api\/runs\/([^/]+)\/progress$/);
  if (progressMatch) {
    const runId = progressMatch[1]!;
    return async () => {
      // Build progress from active run state + live report scanning
      const run = svc.run.runManager.getActiveRun();
      if (!run || run.id !== runId) {
        return {
          exists: false,
          runId,
          total: 0,
          completed: 0,
          currentScenario: null,
          currentScenarioId: null,
          elapsedMs: 0,
          updatedAt: Date.now(),
          now: Date.now(),
          running: false,
        } satisfies RunProgress;
      }

      // Scan the reports directory for completed scenario reports
      // to get real-time progress instead of waiting for run completion
      let completed = 0;
      let currentScenario: string | null = null;
      let currentScenarioId: string | null = null;
      if (run.reportsDir) {
        try {
          const reportFiles: string[] = [];
          for await (const entry of Deno.readDir(run.reportsDir)) {
            if (entry.isFile && entry.name.endsWith(".json") &&
              !entry.name.endsWith("-progress.json") &&
              entry.name !== "overall-summary.json") {
              reportFiles.push(entry.name);
            }
          }
          completed = reportFiles.length;

          // The most recently modified report is likely the current scenario
          if (reportFiles.length > 0 && reportFiles.length < run.totalScenarios) {
            // Find the most recent report file
            let latestName = reportFiles[0]!;
            let latestMtime = 0;
            for (const name of reportFiles) {
              try {
                const stat = await Deno.stat(join(run.reportsDir, name));
                if (stat.mtime && stat.mtime.getTime() > latestMtime) {
                  latestMtime = stat.mtime.getTime();
                  latestName = name;
                }
              } catch {
                // skip
              }
            }
            // Extract scenario name from filename: 20260507-183659-01_account_lifecycle.json
            const nameMatch = latestName.match(/^\d{8}-\d{6}-(.+)\.json$/);
            if (nameMatch) {
              currentScenario = nameMatch[1]!.replace(/_/g, " ");
              const idMatch = nameMatch[1]!.match(/^(\d+)/);
              currentScenarioId = idMatch ? idMatch[1] : null;
            }
          }
        } catch {
          // Reports dir may not exist yet — that's fine
        }
      }

      const progress: RunProgress = {
        exists: true,
        runId,
        total: run.totalScenarios,
        completed,
        currentScenario,
        currentScenarioId,
        elapsedMs: Date.now() - run.startedAt,
        updatedAt: Date.now(),
        now: Date.now(),
        running: run.status === "running",
      };
      return progress;
    };
  }

  // /api/runs/:id/logs
  const logsMatch = url.match(/^\/api\/runs\/([^/]+)\/logs$/);
  if (logsMatch) {
    const runId = logsMatch[1]!;
    return async () => {
      // Read log file from run directory
      const run = svc.run.runManager.getActiveRun();
      if (run?.id === runId && run.logPath) {
        try {
          return await Deno.readTextFile(run.logPath);
        } catch {
          return "";
        }
      }
      // Try fetching from DB
      const dbRun = svc.queries.fetchRun(svc.db.db, runId);
      if (dbRun?.logPath) {
        try {
          return await Deno.readTextFile(dbRun.logPath);
        } catch {
          return "";
        }
      }
      return "";
    };
  }

  // /api/runs/recent
  const recentMatch = url.match(/^\/api\/runs\/recent(\?.*)?$/);
  if (recentMatch) {
    const params = new URL(url, "http://localhost").searchParams;
    const limit = parseInt(params.get("limit") ?? "10");
    return () => {
      return Promise.resolve(svc.queries.fetchRuns(svc.db.db, limit));
    };
  }

  // /api/scenarios
  if (url === "/api/scenarios") {
    return async () => {
      const scenarios = await svc.scenarios.getScenarios();
      // Map to ScenarioMeta shape
      const mapped = scenarios.map((s) => ({
        id: s.id,
        name: s.name,
        category: s.category,
        needsPds2: s.needsPds2,
        lastStatus: null as string | null,
        parameters: s.parameters,
      }));
      // Enrich with latest results
      try {
        const latestResults = svc.queries.fetchLatestResultPerScenario(svc.db.db);
        const resultMap = new Map(latestResults.map((r) => [r.scenario_id, r.status]));
        for (const s of mapped) {
          const status = resultMap.get(s.id);
          if (status) s.lastStatus = status;
        }
      } catch {
        // Ignore — results not available yet
      }
      return { scenarios: mapped };
    };
  }

  // /api/topologies
  if (url === "/api/topologies") {
    return async () => {
      const topologies = await svc.topology.listTopologies();
      return { topologies: topologies.map((t) => ({ name: t.name })) };
    };
  }

  // /api/topologies/:name
  const topoMatch = url.match(/^\/api\/topologies\/([^/]+)$/);
  if (topoMatch) {
    const name = topoMatch[1]!;
    return async () => {
      const topology = await svc.topology.getTopologyPreview(name);
      return {
        name: topology.name,
        description: topology.description,
        roles: topology.roles,
        capabilities: topology.capabilities,
      };
    };
  }

  return null;
}

// ---------------------------------------------------------------------------
// Msg construction (reuses web runtime patterns)
// ---------------------------------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isRunProgress(value: unknown): value is RunProgress {
  if (!isRecord(value)) return false;
  return typeof value.exists === "boolean" &&
    typeof value.runId === "string" &&
    typeof value.total === "number" &&
    typeof value.completed === "number" &&
    typeof value.elapsedMs === "number" &&
    typeof value.updatedAt === "number" &&
    typeof value.now === "number" &&
    typeof value.running === "boolean";
}

function isTopologyPreview(value: unknown): value is TopologyPreview {
  if (!isRecord(value)) return false;
  return typeof value.name === "string" &&
    Array.isArray(value.roles) &&
    Array.isArray(value.capabilities);
}

/** Construct a success Msg from a Cmd.fetch response. */
function constructMsg(
  onSuccess: string,
  data: unknown,
  meta: Record<string, unknown> = {},
): Msg {
  const d = data as Record<string, unknown>;
  const token = typeof meta.token === "number" ? meta.token : undefined;
  const runId = typeof meta.runId === "string" ? meta.runId : undefined;
  const name = typeof meta.name === "string" ? meta.name : undefined;
  const tokenField = token === undefined ? {} : { token };
  const runField = runId === undefined ? {} : { runId };
  const nameField = name === undefined ? {} : { name };

  switch (onSuccess) {
    case "network/healthReceived":
      if (!isRecord(data) || !Array.isArray(d.services)) {
        return { type: "network/healthFailed", error: "Malformed health response", ...tokenField };
      }
      return { type: "network/healthReceived", services: d.services as ServiceStatus[], ...tokenField };

    case "runs/activeReceived":
      if (!isRecord(data)) {
        return { type: "runs/activeFailed", error: "Malformed active run response", ...tokenField };
      }
      return { type: "runs/activeReceived", run: (d.activeRun ?? null) as Run | null, ...tokenField };

    case "runs/startSucceeded":
      if (!isRecord(data) || !("runId" in d)) {
        return { type: "runs/startFailed", error: "Malformed start response" };
      }
      return { type: "runs/startSucceeded", runId: String(d.runId) };

    case "runs/progressReceived":
      if (!isRunProgress(data)) {
        return { type: "runs/progressFailed", error: "Malformed progress response", ...runField, ...tokenField };
      }
      return { type: "runs/progressReceived", progress: data, ...runField, ...tokenField };

    case "scenarios/received":
      if (!isRecord(data) || !Array.isArray(d.scenarios)) {
        return { type: "scenarios/failed", error: "Malformed scenarios response" };
      }
      return { type: "scenarios/received", scenarios: d.scenarios as never };

    case "topology/listReceived":
      if (!isRecord(data) || !Array.isArray(d.topologies)) {
        return { type: "topology/listFailed", error: "Malformed topologies response" };
      }
      return { type: "topology/listReceived", topologies: d.topologies as never };

    case "topology/previewReceived":
      if (!isTopologyPreview(data)) {
        return { type: "topology/previewFailed", error: "Malformed topology response", ...nameField, ...tokenField };
      }
      return { type: "topology/previewReceived", preview: data, ...nameField, ...tokenField };

    case "network/startSucceeded":
      return { type: "network/startSucceeded" };

    case "network/stopSucceeded":
      return { type: "network/stopSucceeded" };

    case "runs/stopSucceeded":
      return { type: "runs/stopSucceeded" };

    case "runs/restartSucceeded":
      if (!isRecord(data) || !("newRunId" in d)) {
        return { type: "runs/restartFailed", error: "Malformed restart response" };
      }
      return { type: "runs/restartSucceeded", newRunId: String(d.newRunId) };

    case "logs/received":
      return { type: "logs/received", text: typeof data === "string" ? data : String(data), ...runField, ...tokenField };

    case "metrics/received":
      if (!isRecord(data) || !isRecord(d.stats ?? {})) {
        return { type: "metrics/failed", error: "Malformed metrics response", ...tokenField };
      }
      return { type: "metrics/received", stats: (d.stats ?? {}) as never, ...tokenField };

    case "runs/recentReceived":
      if (!Array.isArray(data)) {
        return { type: "runs/recentFailed", error: "Malformed recent runs response", ...tokenField };
      }
      return { type: "runs/recentReceived", runs: data as Run[], ...tokenField };

    default:
      throw new Error(`Unknown success msg type: ${onSuccess}`);
  }
}

/** Construct an error Msg from a Cmd.fetch failure. */
function constructErrorMsg(
  onError: string,
  error: string,
  meta: Record<string, unknown> = {},
): Msg {
  const token = typeof meta.token === "number" ? meta.token : undefined;
  const runId = typeof meta.runId === "string" ? meta.runId : undefined;
  const name = typeof meta.name === "string" ? meta.name : undefined;
  const tokenField = token === undefined ? {} : { token };
  const runField = runId === undefined ? {} : { runId };
  const nameField = name === undefined ? {} : { name };

  switch (onError) {
    case "network/healthFailed":
      return { type: "network/healthFailed", error, ...tokenField };
    case "runs/activeFailed":
      return { type: "runs/activeFailed", error, ...tokenField };
    case "runs/progressFailed":
      return { type: "runs/progressFailed", error, ...runField, ...tokenField };
    case "runs/startFailed":
      return { type: "runs/startFailed", error };
    case "runs/stopFailed":
      return { type: "runs/stopFailed", error };
    case "runs/restartFailed":
      return { type: "runs/restartFailed", error };
    case "scenarios/failed":
      return { type: "scenarios/failed", error };
    case "topology/listFailed":
      return { type: "topology/listFailed", error };
    case "topology/previewFailed":
      return { type: "topology/previewFailed", error, ...nameField, ...tokenField };
    case "network/startFailed":
      return { type: "network/startFailed", error };
    case "network/stopFailed":
      return { type: "network/stopFailed", error };
    case "logs/failed":
      return { type: "logs/failed", error, ...runField, ...tokenField };
    case "metrics/failed":
      return { type: "metrics/failed", error, ...tokenField };
    case "runs/recentFailed":
      return { type: "runs/recentFailed", error, ...tokenField };
    default:
      throw new Error(`Unknown error msg type: ${onError}`);
  }
}

// ---------------------------------------------------------------------------
// TUI Runtime creation
// ---------------------------------------------------------------------------

/** Create the TUI runtime: initializes state, boot cmds, and timer management. */
export function createTuiRuntime(initialState?: DashboardState): TuiRuntimeHandle {
  let state = initialState ?? createInitialState();
  const timerIds: ReturnType<typeof setTimeout>[] = [];
  const listeners: ((state: DashboardState) => void)[] = [];

  function dispatch(msg: Msg): void {
    try {
      const [next, cmds] = update(state, msg);
      state = next;
      interpretCmds(cmds, dispatch);
      for (const fn of listeners) fn(state);
    } catch (err) {
      console.error("[TUI Runtime] dispatch failed:", err, msg);
    }
  }

  function interpretCmds(cmds: Cmd[], d: (msg: Msg) => void): void {
    for (const cmd of cmds) {
      switch (cmd.type) {
        case "fetch":
          handleFetch(cmd, d);
          break;
        case "schedule":
          handleSchedule(cmd, d);
          break;
        case "navigate":
          // In the web dashboard, navigate changes the URL.
          // In the TUI, a navigate after start/restart means we should
          // immediately re-fetch the active run so the UI updates.
          d({ type: "runs/activeTimeout" });
          break;
        case "none":
          break;
      }
    }
  }

  async function handleFetch(
    cmd: Extract<Cmd, { type: "fetch" }>,
    d: (msg: Msg) => void,
  ): Promise<void> {
    try {
      const handler = await resolveServiceHandler(cmd.url);
      if (!handler) {
        d(constructErrorMsg(cmd.onError, `No handler for ${cmd.url}`, cmd.meta ?? {}));
        return;
      }
      const data = await handler(cmd.url, cmd.method, cmd.body);
      d(constructMsg(cmd.onSuccess, data, cmd.meta ?? {}));
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      d(constructErrorMsg(cmd.onError, msg, cmd.meta ?? {}));
    }
  }

  function handleSchedule(
    cmd: Extract<Cmd, { type: "schedule" }>,
    d: (msg: Msg) => void,
  ): void {
    const id = setTimeout(() => {
      const idx = timerIds.indexOf(id);
      if (idx !== -1) timerIds.splice(idx, 1);
      d(cmd.msg);
    }, cmd.delayMs);
    timerIds.push(id);
  }

  function destroy(): void {
    for (const id of timerIds) clearTimeout(id);
    timerIds.length = 0;
    listeners.length = 0;
  }

  // Boot: run initial fetches
  interpretCmds(bootCmds(), dispatch);

  // Tick: drive elapsed-time counters (every 1s)
  const tickId = setInterval(() => {
    dispatch({ type: "tick", nowMs: Date.now() });
  }, 1000);
  timerIds.push(tickId);

  return {
    get state() { return state; },
    dispatch,
    destroy,
    onChange: (fn) => {
      listeners.push(fn);
      return () => {
        const idx = listeners.indexOf(fn);
        if (idx !== -1) listeners.splice(idx, 1);
      };
    },
  };
}
