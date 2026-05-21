/** TEA Runtime — interprets Cmds into I/O, drives the state signal, and exposes dispatch. @module runtime */
import { signal } from "@preact/signals";
import type { Cmd, DashboardState, Msg } from "./dashboard_state.ts";
import { bootCmds, createInitialState, update } from "./dashboard_state.ts";
import { constructMsg, constructErrorMsg } from "./cmd_interpreter.ts";

const IS_BROWSER = typeof globalThis !== "undefined" && "document" in globalThis;

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

// Re-export shared Msg constructors from cmd_interpreter for backward compatibility.
// The web runtime has no extra branches — the shared module handles all cases.
export { constructMsg, constructErrorMsg } from "./cmd_interpreter.ts";
