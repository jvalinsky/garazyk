/**
 * Shared command interpreter — Msg construction from Cmd results.
 *
 * Deduplicates the `constructMsg` and `constructErrorMsg` functions that were
 * previously copied between `runtime.ts` (web) and `tui/runtime.ts` (TUI).
 * Both runtimes translate `Cmd.fetch` responses into `Msg` values using the
 * same logic; this module is the single source of truth.
 *
 * The TUI runtime has two extra branches (`runs/recentReceived`,
 * `runs/recentFailed`) that the web runtime does not produce. These are
 * handled via an optional `extraBranches` callback so the shared function
 * stays clean.
 *
 * @module cmd_interpreter
 */

import type { Msg, RunProgress, TopologyPreview } from "./dashboard_state.ts";

import type {
  Run,
  ScenarioResultView,
  ServiceStatus,
} from "./services/types.ts";

// ---------------------------------------------------------------------------
// Type guards
// ---------------------------------------------------------------------------

/** Check whether a value is a plain object (not null, not array). */
export function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** Check whether a value conforms to the {@link RunProgress} shape. */
export function isRunProgress(value: unknown): value is RunProgress {
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

/** Check whether a value conforms to the {@link TopologyPreview} shape. */
export function isTopologyPreview(value: unknown): value is TopologyPreview {
  if (!isRecord(value)) return false;
  return typeof value.name === "string" &&
    Array.isArray(value.roles) &&
    Array.isArray(value.capabilities);
}

// ---------------------------------------------------------------------------
// Meta extraction
// ---------------------------------------------------------------------------

/** Extract common meta fields (token, runId, name) from a Cmd meta object. */
function extractMetaFields(meta: Record<string, unknown> = {}): {
  tokenField: { token: number } | {};
  runField: { runId: string } | {};
  nameField: { name: string } | {};
} {
  const token = typeof meta.token === "number" ? meta.token : undefined;
  const runId = typeof meta.runId === "string" ? meta.runId : undefined;
  const name = typeof meta.name === "string" ? meta.name : undefined;
  return {
    tokenField: token === undefined ? {} : { token },
    runField: runId === undefined ? {} : { runId },
    nameField: name === undefined ? {} : { name },
  };
}

// ---------------------------------------------------------------------------
// constructMsg
// ---------------------------------------------------------------------------

/**
 * Extra branch handler for runtime-specific `constructMsg` cases.
 *
 * The TUI runtime produces `runs/recentReceived` and `runs/recentFailed`
 * messages that the web runtime does not. Rather than branching in the
 * shared function, runtimes can supply this callback to handle their
 * own cases before falling through to the shared switch.
 *
 * @returns A `Msg` if the branch was handled, or `undefined` to fall
 *          through to the shared switch.
 */
export type ExtraMsgBranch = (
  onSuccess: string,
  data: unknown,
  meta: Record<string, unknown>,
  fields: ReturnType<typeof extractMetaFields>,
) => Msg | undefined;

/**
 * Translate a successful Cmd result into a Msg.
 *
 * @param onSuccess - The `onSuccess` label from the Cmd.
 * @param data - The response data from the fetch.
 * @param meta - The Cmd's meta object (carries token, runId, name).
 * @param extraBranches - Optional handler for runtime-specific cases.
 * @returns The constructed Msg.
 */
export function constructMsg(
  onSuccess: string,
  data: unknown,
  meta: Record<string, unknown> = {},
  extraBranches?: ExtraMsgBranch,
): Msg {
  const d = data as Record<string, unknown>;
  const fields = extractMetaFields(meta);
  const { tokenField, runField, nameField } = fields;

  // Try runtime-specific branches first.
  if (extraBranches) {
    const extra = extraBranches(onSuccess, data, meta, fields);
    if (extra !== undefined) return extra;
  }

  switch (onSuccess) {
    case "network/healthReceived":
      if (
        !isRecord(data) || (!Array.isArray(d.services) && !isRecord(d.services))
      ) {
        return {
          type: "network/healthFailed",
          error: "Malformed health response",
          ...tokenField,
        };
      }
      return {
        type: "network/healthReceived",
        services:
          (Array.isArray(d.services)
            ? d.services
            : Object.values(d.services)) as ServiceStatus[],
        ...tokenField,
      };

    case "runs/activeReceived":
      if (!isRecord(data)) {
        return {
          type: "runs/activeFailed",
          error: "Malformed active run response",
          ...tokenField,
        };
      }
      return {
        type: "runs/activeReceived",
        run: (d.activeRun ?? null) as Run | null,
        ...tokenField,
      };

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
      return {
        type: "runs/progressReceived",
        progress: data,
        ...runField,
        ...tokenField,
      };

    case "runs/recentReceived":
      if (!Array.isArray(data)) {
        return {
          type: "runs/recentFailed",
          error: "Malformed recent runs response",
          ...tokenField,
        };
      }
      return {
        type: "runs/recentReceived",
        runs: data as Run[],
        ...tokenField,
      };

    case "scenarios/received":
      if (!isRecord(data) || !Array.isArray(d.scenarios)) {
        return {
          type: "scenarios/failed",
          error: "Malformed scenarios response",
        };
      }
      return { type: "scenarios/received", scenarios: d.scenarios as never };

    case "topology/listReceived":
      if (!isRecord(data) || !Array.isArray(d.topologies)) {
        return {
          type: "topology/listFailed",
          error: "Malformed topologies response",
        };
      }
      return {
        type: "topology/listReceived",
        topologies: d.topologies as never,
      };

    case "topology/previewReceived":
      if (!isTopologyPreview(data)) {
        return {
          type: "topology/previewFailed",
          error: "Malformed topology response",
          ...nameField,
          ...tokenField,
        };
      }
      return {
        type: "topology/previewReceived",
        preview: data,
        ...nameField,
        ...tokenField,
      };

    case "network/startSucceeded":
      return { type: "network/startSucceeded" };

    case "network/stopSucceeded":
      return { type: "network/stopSucceeded" };

    case "runs/stopSucceeded":
      return { type: "runs/stopSucceeded" };

    case "runs/restartSucceeded":
      if (!isRecord(data) || !("newRunId" in d)) {
        return {
          type: "runs/restartFailed",
          error: "Malformed restart response",
        };
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
        return {
          type: "metrics/failed",
          error: "Malformed metrics response",
          ...tokenField,
        };
      }
      return {
        type: "metrics/received",
        stats: (d.stats ?? {}) as never,
        ...tokenField,
      };

    case "runs/detailResults":
      if (!isRecord(data) || !Array.isArray(d.results)) {
        return { type: "runs/closeDetail" };
      }
      return {
        type: "runs/detailResults",
        results: d.results as ScenarioResultView[],
      };

    default:
      throw new Error(`Unknown success msg type: ${onSuccess}`);
  }
}

// ---------------------------------------------------------------------------
// constructErrorMsg
// ---------------------------------------------------------------------------

/**
 * Extra branch handler for runtime-specific `constructErrorMsg` cases.
 *
 * @returns A `Msg` if the branch was handled, or `undefined` to fall
 *          through to the shared switch.
 */
export type ExtraErrorMsgBranch = (
  onError: string,
  error: string,
  meta: Record<string, unknown>,
  fields: ReturnType<typeof extractMetaFields>,
) => Msg | undefined;

/**
 * Translate a failed Cmd result into a Msg.
 *
 * @param onError - The `onError` label from the Cmd.
 * @param error - The error string from the fetch.
 * @param meta - The Cmd's meta object (carries token, runId, name).
 * @param extraBranches - Optional handler for runtime-specific cases.
 * @returns The constructed Msg.
 */
export function constructErrorMsg(
  onError: string,
  error: string,
  meta: Record<string, unknown> = {},
  extraBranches?: ExtraErrorMsgBranch,
): Msg {
  const fields = extractMetaFields(meta);
  const { tokenField, runField, nameField } = fields;

  // Try runtime-specific branches first.
  if (extraBranches) {
    const extra = extraBranches(onError, error, meta, fields);
    if (extra !== undefined) return extra;
  }

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
    case "runs/recentFailed":
      return { type: "runs/recentFailed", error, ...tokenField };
    case "scenarios/failed":
      return { type: "scenarios/failed", error };
    case "topology/listFailed":
      return { type: "topology/listFailed", error };
    case "topology/previewFailed":
      return {
        type: "topology/previewFailed",
        error,
        ...nameField,
        ...tokenField,
      };
    case "network/startFailed":
      return { type: "network/startFailed", error };
    case "network/stopFailed":
      return { type: "network/stopFailed", error };
    case "logs/failed":
      return { type: "logs/failed", error, ...runField, ...tokenField };
    case "metrics/failed":
      return { type: "metrics/failed", error, ...tokenField };
    case "runs/closeDetail":
      return { type: "runs/closeDetail" };
    default:
      throw new Error(`Unknown error msg type: ${onError}`);
  }
}
