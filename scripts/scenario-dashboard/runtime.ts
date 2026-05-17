/** TEA Runtime — interprets Cmds into I/O, drives the state signal, and exposes dispatch. @module runtime */
import { signal } from "@preact/signals";
import type { Cmd, DashboardState, Msg, RunProgress, TopologyPreview } from "./dashboard_state.ts";
import { bootCmds, createInitialState, update } from "./dashboard_state.ts";

export const IS_BROWSER = typeof globalThis !== "undefined" && "document" in globalThis;

// Wraps a Preact Signal to present a non-nullable DashboardState type.
// Preact Signal<T> resolves as value: T|undefined in the version served
// by esm.sh; this wrapper contains the cast in one place.
/** Wraps a Preact Signal to present a non-nullable DashboardState type. */
class TypedSignal {
  private sig: ReturnType<typeof signal<DashboardState>>;

  constructor(initial: DashboardState) {
    this.sig = signal(initial);
  }

  get value(): DashboardState {
    return this.sig.value as DashboardState;
  }

  set value(v: DashboardState) {
    this.sig.value = v as DashboardState;
  }

  peek(): DashboardState {
    return this.sig.peek() as DashboardState;
  }

  subscribe(fn: (value: DashboardState) => void): () => void {
    return this.sig.subscribe(fn as (v: DashboardState | undefined) => void);
  }
}

/** Handle returned by createRuntime — accessor for state, dispatch, and cleanup. */
interface RuntimeHandle {
  state: TypedSignal;
  dispatch: (msg: Msg) => void;
  destroy: () => void;
}

let _runtime: RuntimeHandle | null = null;

/** Get or create the singleton runtime. Returns null outside the browser. */
export function getRuntime(): RuntimeHandle | null {
  if (!IS_BROWSER) return null;
  if (!_runtime) _runtime = createRuntime();
  return _runtime;
}

/** Hook for islands to access the runtime state signal and dispatch. SSR-safe. */
export function useRuntime(): { state: TypedSignal; dispatch: (msg: Msg) => void } {
  const runtime = getRuntime();
  if (!runtime) {
    // SSR guard — return inert handles so islands don't crash during hydration
    return { state: new TypedSignal(createInitialState()), dispatch: () => {} };
  }
  return { state: runtime.state, dispatch: runtime.dispatch };
}

/** Create the runtime: initializes state, boot cmds, and the tick interval. */
function createRuntime(initialState?: DashboardState): RuntimeHandle {
  const state = new TypedSignal(initialState ?? createInitialState());
  const timerIds: number[] = [];
  const intervalIds: number[] = [];

  function dispatch(msg: Msg): void {
    try {
      const current = state.peek();
      const [next, cmds] = update(current, msg);
      state.value = next;
      interpretCmds(cmds, dispatch);
    } catch (err) {
      console.error("[Runtime] dispatch failed:", err, msg);
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
          handleNavigate(cmd);
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
      const opts: RequestInit = {};
      if (cmd.method) opts.method = cmd.method;
      if (cmd.body !== undefined) opts.body = JSON.stringify(cmd.body);
      opts.headers = { "Content-Type": "application/json" };

      const res = await fetch(cmd.url, opts);
      const text = await res.text();
      let data: unknown;
      try {
        data = JSON.parse(text);
      } catch {
        data = text;
      }

      if (!res.ok) {
        const errMsg =
          (data && typeof data === "object" && "error" in (data as Record<string, unknown>))
            ? String((data as Record<string, string>).error)
            : `HTTP ${res.status}: ${res.statusText}`;
        d(constructErrorMsg(cmd.onError, errMsg, cmd.meta));
        return;
      }

      d(constructMsg(cmd.onSuccess, data, cmd.meta));
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      d(constructErrorMsg(cmd.onError, msg, cmd.meta));
    }
  }

  function handleSchedule(cmd: Extract<Cmd, { type: "schedule" }>, d: (msg: Msg) => void): void {
    const id = setTimeout(() => {
      const idx = timerIds.indexOf(id);
      if (idx !== -1) timerIds.splice(idx, 1);
      d(cmd.msg);
    }, cmd.delayMs);
    timerIds.push(id);
  }

  function handleNavigate(cmd: Extract<Cmd, { type: "navigate" }>): void {
    if (IS_BROWSER) {
      window.location.href = cmd.url;
    }
  }

  function destroy(): void {
    for (const id of timerIds) clearTimeout(id);
    for (const id of intervalIds) clearInterval(id);
    timerIds.length = 0;
    intervalIds.length = 0;
  }

  // Boot: run initial fetches
  interpretCmds(bootCmds(), dispatch);

  // Tick: drive elapsed-time counters in state machine (every 1s).
  // Updates network.lastHealthCheckMs and runs.lastProgressMs.
  // Islands read these for "time since last update" display.
  if (IS_BROWSER) {
    const tickId = setInterval(() => {
      dispatch({ type: "tick", nowMs: Date.now() });
    }, 1000);
    intervalIds.push(tickId);
  }

  return { state, dispatch, destroy };
}

// Maps API response shapes to Msg constructors.
// Each endpoint's response shape was verified against route handler code.
/** Maps API response shapes to Msg constructors. */
export function constructMsg(
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
      return { type: "network/healthReceived", services: d.services as never, ...tokenField };
    case "runs/activeReceived":
      if (!isRecord(data)) {
        return { type: "runs/activeFailed", error: "Malformed active run response", ...tokenField };
      }
      return { type: "runs/activeReceived", run: (d.activeRun ?? null) as never, ...tokenField };
    case "runs/startSucceeded":
      if (!isRecord(data) || !("runId" in d)) {
        return { type: "runs/startFailed", error: "Malformed start response" };
      }
      return { type: "runs/startSucceeded", runId: String(d.runId) };
    case "runs/progressReceived":
      if (!isRunProgress(data)) {
        return {
          type: "runs/progressFailed",
          error: "Malformed progress response",
          ...runField,
          ...tokenField,
        };
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
        return {
          type: "topology/previewFailed",
          error: "Malformed topology response",
          ...nameField,
          ...tokenField,
        };
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
      return {
        type: "logs/received",
        text: typeof data === "string" ? data : String(data),
        ...runField,
        ...tokenField,
      };
    case "metrics/received":
      if (!isRecord(data) || !isRecord(d.stats ?? {})) {
        return { type: "metrics/failed", error: "Malformed metrics response", ...tokenField };
      }
      return { type: "metrics/received", stats: (d.stats ?? {}) as never, ...tokenField };
    default:
      throw new Error(`Unknown success msg type: ${onSuccess}`);
  }
}

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

/** Maps error response strings to error Msg constructors. */
export function constructErrorMsg(
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
    default:
      throw new Error(`Unknown error msg type: ${onError}`);
  }
}
