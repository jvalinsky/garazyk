import { signal } from "@preact/signals";
import type { DashboardState, Msg, Cmd } from "./dashboard_state.ts";
import { update, createInitialState, bootCmds } from "./dashboard_state.ts";

const IS_BROWSER = typeof globalThis !== "undefined" && "document" in globalThis;

// Wraps a Preact Signal to present a non-nullable DashboardState type.
// Preact Signal<T> resolves as value: T|undefined in the version served
// by esm.sh; this wrapper contains the cast in one place.
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

interface RuntimeHandle {
  state: TypedSignal;
  dispatch: (msg: Msg) => void;
  destroy: () => void;
}

let _runtime: RuntimeHandle | null = null;

export function getRuntime(): RuntimeHandle | null {
  if (!IS_BROWSER) return null;
  if (!_runtime) _runtime = createRuntime();
  return _runtime;
}

export function useRuntime(): { state: TypedSignal; dispatch: (msg: Msg) => void } {
  const runtime = getRuntime();
  if (!runtime) {
    // SSR guard — return inert handles so islands don't crash during hydration
    return { state: new TypedSignal(createInitialState()), dispatch: () => {} };
  }
  return { state: runtime.state, dispatch: runtime.dispatch };
}

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

  async function handleFetch(cmd: Extract<Cmd, { type: "fetch" }>, d: (msg: Msg) => void): Promise<void> {
    try {
      const opts: RequestInit = {};
      if (cmd.method) opts.method = cmd.method;
      if (cmd.body !== undefined) opts.body = JSON.stringify(cmd.body);
      opts.headers = { "Content-Type": "application/json" };

      const res = await fetch(cmd.url, opts);
      const text = await res.text();
      let data: unknown;
      try { data = JSON.parse(text); } catch { data = text; }

      if (!res.ok) {
        const errMsg = (data && typeof data === "object" && "error" in (data as Record<string, unknown>))
          ? String((data as Record<string, string>).error)
          : `HTTP ${res.status}: ${res.statusText}`;
        d(constructErrorMsg(cmd.onError, errMsg));
        return;
      }

      d(constructMsg(cmd.onSuccess, data));
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      d(constructErrorMsg(cmd.onError, msg));
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
export function constructMsg(onSuccess: string, data: unknown): Msg {
  const d = data as Record<string, unknown>;
  switch (onSuccess) {
    case "network/healthReceived":
      return { type: "network/healthReceived", services: d.services as never };
    case "runs/activeReceived":
      return { type: "runs/activeReceived", run: (d.activeRun ?? null) as never };
    case "runs/startSucceeded":
      return { type: "runs/startSucceeded", runId: String(d.runId) };
    case "runs/progressReceived":
      return { type: "runs/progressReceived", progress: data as never };
    case "scenarios/received":
      return { type: "scenarios/received", scenarios: d.scenarios as never };
    case "topology/listReceived":
      return { type: "topology/listReceived", topologies: d.topologies as never };
    case "topology/previewReceived":
      return { type: "topology/previewReceived", preview: data as never };
    case "network/startSucceeded":
      return { type: "network/startSucceeded" };
    case "network/stopSucceeded":
      return { type: "network/stopSucceeded" };
    case "runs/stopSucceeded":
      return { type: "runs/stopSucceeded" };
    case "runs/restartSucceeded":
      return { type: "runs/restartSucceeded", newRunId: String(d.newRunId) };
    default:
      throw new Error(`Unknown success msg type: ${onSuccess}`);
  }
}

export function constructErrorMsg(onError: string, error: string): Msg {
  switch (onError) {
    case "network/healthFailed":
      return { type: "network/healthFailed", error };
    case "runs/activeFailed":
      return { type: "runs/activeFailed", error };
    case "runs/progressFailed":
      return { type: "runs/progressFailed", error };
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
      return { type: "topology/previewFailed", error };
    case "network/startFailed":
      return { type: "network/startFailed", error };
    case "network/stopFailed":
      return { type: "network/stopFailed", error };
    default:
      throw new Error(`Unknown error msg type: ${onError}`);
  }
}
