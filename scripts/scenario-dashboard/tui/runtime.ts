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
import type { Cmd, DashboardState, Msg, RunProgress } from "../dashboard_state.ts";
import { bootCmds, createInitialState, update } from "../dashboard_state.ts";
import type { Run, RunEvent } from "../services/types.ts";
import {
  constructMsg as sharedConstructMsg,
  constructErrorMsg as sharedConstructErrorMsg,
} from "../cmd_interpreter.ts";
import type { ExtraMsgBranch, ExtraErrorMsgBranch } from "../cmd_interpreter.ts";

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

  // /api/runs/:id/results
  const resultsMatch = url.match(/^\/api\/runs\/([^/]+)\/results$/);
  if (resultsMatch) {
    const runId = resultsMatch[1]!;
    return () => {
      return Promise.resolve({ results: svc.queries.fetchScenarioResults(svc.db.db, runId) });
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
        description: s.description,
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
// Msg construction (delegates to shared cmd_interpreter + TUI-specific branches)
// ---------------------------------------------------------------------------

/** TUI-specific extra branches for constructMsg (runs/recentReceived). */
const tuiExtraMsgBranch: ExtraMsgBranch = (onSuccess, data, meta, fields) => {
  const { tokenField } = fields;
  switch (onSuccess) {
    case "runs/recentReceived":
      if (!Array.isArray(data)) {
        return { type: "runs/recentFailed", error: "Malformed recent runs response", ...tokenField };
      }
      return { type: "runs/recentReceived", runs: data as Run[], ...tokenField };
    default:
      return undefined;
  }
};

/** TUI-specific extra branches for constructErrorMsg (runs/recentFailed). */
const tuiExtraErrorMsgBranch: ExtraErrorMsgBranch = (onError, error, _meta, fields) => {
  const { tokenField } = fields;
  switch (onError) {
    case "runs/recentFailed":
      return { type: "runs/recentFailed", error, ...tokenField };
    default:
      return undefined;
  }
};

/** Construct a success Msg from a Cmd.fetch response (TUI variant). */
function constructMsg(
  onSuccess: string,
  data: unknown,
  meta: Record<string, unknown> = {},
): Msg {
  return sharedConstructMsg(onSuccess, data, meta, tuiExtraMsgBranch);
}

/** Construct an error Msg from a Cmd.fetch failure (TUI variant). */
function constructErrorMsg(
  onError: string,
  error: string,
  meta: Record<string, unknown> = {},
): Msg {
  return sharedConstructErrorMsg(onError, error, meta, tuiExtraErrorMsgBranch);
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
        case "fetch": {
          // Skip progress and log polling when events are driving updates
          // for the active run. The runs/event handler keeps the state fresh.
          if (state.runs.active && (
            cmd.url.match(/^\/api\/runs\/[^/]+\/progress$/) ||
            cmd.url.match(/^\/api\/runs\/[^/]+\/logs$/)
          )) {
            break;
          }
          handleFetch(cmd, d);
          break;
        }
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
    if (eventUnsubscribe) {
      eventUnsubscribe();
      eventUnsubscribe = undefined;
    }
  }

  // Boot: run initial fetches
  interpretCmds(bootCmds(), dispatch);

  // Tick: drive elapsed-time counters (every 1s)
  const tickId = setInterval(() => {
    dispatch({ type: "tick", nowMs: Date.now() });
  }, 1000);
  timerIds.push(tickId);

  // Subscribe to RunManager events — push-based updates replace polling
  let eventUnsubscribe: (() => void) | undefined;
  loadServices().then((svc) => {
    eventUnsubscribe = svc.run.runManager.onEvent((event: RunEvent) => {
      dispatch({ type: "runs/event", event });
    });
  });

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
