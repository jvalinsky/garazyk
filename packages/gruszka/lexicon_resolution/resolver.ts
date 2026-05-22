/**
 * Sans-IO lexicon resolution — layer 2: state machine.
 *
 * Implements the Elm Architecture pattern: `init()` produces an initial
 * `[ResolverState, ResolverCmd]` pair, and `update()` is a pure reducer that
 * maps `(state, msg)` to the next `[ResolverState, ResolverCmd]`.
 *
 * No I/O.  No side effects.  Every transition is deterministic and testable
 * without mocks, DNS servers, or HTTP fixtures.
 *
 * @module lexicon_resolution
 */

import {
  buildXrpcUrl,
  deriveDnsDomain,
  extractPdsEndpoint,
  parseDnsTxtRecords,
  parseNsid,
  verifyRecord,
} from "./core.ts";
import {
  asNsid,
  assertNever,
  type DidPendingState,
  type DnsPendingState,
  type RecordPendingState,
  type ResolvedState,
  type ResolverCmd,
  type ResolverMsg,
  type ResolverState,
} from "./types.ts";

// =============================================================================
// Init
// =============================================================================

/**
 * Bootstrap the resolver from a raw NSID string.
 *
 * Validates the NSID, parses it into authority + name, derives the DNS
 * domain, and emits a {@link ResolveDnsCmd} to kick off the first step
 * of resolution.
 *
 * If the NSID is syntactically invalid the state machine starts in the
 * `failed` terminal state.
 *
 * @param nsid - A raw (unbranded) NSID string to resolve.
 * @returns `[ResolverState, ResolverCmd]` — the initial state and command.
 *
 * @example
 * ```ts
 * const [state, cmd] = init("app.bsky.feed.post");
 * // state.status === "dnsPending"
 * // state.domain === "feed.bsky.app"
 * // cmd.type === "resolveDns"
 * ```
 */
export function init(nsid: string): [ResolverState, ResolverCmd] {
  // Validate and brand the NSID.
  let brandedNsid;
  try {
    brandedNsid = asNsid(nsid);
  } catch {
    return [
      { status: "failed", error: { type: "InvalidNsid", nsid } },
      { type: "done" },
    ];
  }

  // Split into authority and name.
  const parsed = parseNsid(brandedNsid);
  if (!parsed.ok) {
    return [
      { status: "failed", error: parsed.error },
      { type: "done" },
    ];
  }

  // Derive the DNS domain.
  const domain = deriveDnsDomain(parsed.value.authority);

  const state: DnsPendingState = {
    status: "dnsPending",
    nsid: brandedNsid,
    domain,
  };

  return [state, { type: "resolveDns", domain }];
}

// =============================================================================
// Update
// =============================================================================

/**
 * Pure state reducer — advance the resolver by one `(state, msg)` step.
 *
 * Terminal states (`resolved` and `failed`) are sinks: they ignore all
 * messages and emit `{ type: "done" }`.
 *
 * When a stale message arrives (one that does not match the expected
 * response for the current state), the reducer re-emits the state's expected
 * command as a retry.  This makes the state machine self-correcting under
 * message reordering.
 *
 * @param state - The current resolver state.
 * @param msg - The message received from the I/O layer.
 * @returns `[ResolverState, ResolverCmd]` — the next state and command.
 */
export function update(
  state: ResolverState,
  msg: ResolverMsg,
): [ResolverState, ResolverCmd] {
  switch (state.status) {
    // ── Terminal sinks ───────────────────────────────────────────────
    case "resolved":
      return [state, { type: "done" }];
    case "failed":
      return [state, { type: "done" }];

    // ── Initial state (should never receive a message) ───────────────
    case "init":
      return [
        { status: "failed", error: { type: "InvalidNsid", nsid: "(init)" } },
        { type: "done" },
      ];

    // ── DNS pending ──────────────────────────────────────────────────
    case "dnsPending":
      return reduceDnsPending(state, msg);

    // ── DID pending ──────────────────────────────────────────────────
    case "didPending":
      return reduceDidPending(state, msg);

    // ── Record pending ───────────────────────────────────────────────
    case "recordPending":
      return reduceRecordPending(state, msg);

    default:
      return assertNever(state);
  }
}

// =============================================================================
// Per-state reducers
// =============================================================================

/**
 * Reduce the `dnsPending` state with the given message.
 *
 * T2 — `dnsSuccess` with a valid DID → `didPending` + `resolveDid`.
 * T3 — `dnsSuccess` with no DID found → `failed`.
 * T4 — `dnsFailed` → `failed`.
 * T5–T8 — Any other (stale) message → re-emit `resolveDns` for retry.
 */
function reduceDnsPending(
  state: DnsPendingState,
  msg: ResolverMsg,
): [ResolverState, ResolverCmd] {
  switch (msg.type) {
    case "dnsSuccess": {
      const result = parseDnsTxtRecords(msg.records, state.domain);
      if (result.ok) {
        const next: DidPendingState = {
          status: "didPending",
          nsid: state.nsid,
          domain: state.domain,
          did: result.value,
        };
        return [next, { type: "resolveDid", did: result.value }];
      }
      return [
        { status: "failed", error: result.error },
        { type: "done" },
      ];
    }

    case "dnsFailed":
      return [
        {
          status: "failed",
          error: {
            type: "DnsQueryFailed",
            domain: state.domain,
            reason: msg.reason,
          },
        },
        { type: "done" },
      ];

    // Stale messages — re-emit the expected command so the caller retries.
    case "didSuccess":
    case "didFailed":
    case "recordSuccess":
    case "recordFailed":
      return [state, { type: "resolveDns", domain: state.domain }];

    default:
      return assertNever(msg);
  }
}

/**
 * Reduce the `didPending` state with the given message.
 *
 * T9  — `didSuccess` with a PDS endpoint found → `recordPending` + `fetchRecord`.
 * T10 — `didSuccess` with no PDS endpoint → `failed`.
 * T11 — `didFailed` → `failed`.
 * T12–T15 — Any other (stale) message → re-emit `resolveDid` for retry.
 */
function reduceDidPending(
  state: DidPendingState,
  msg: ResolverMsg,
): [ResolverState, ResolverCmd] {
  switch (msg.type) {
    case "didSuccess": {
      const result = extractPdsEndpoint(msg.document);
      if (result.ok) {
        const pdsEndpoint = result.value;
        const next: RecordPendingState = {
          status: "recordPending",
          nsid: state.nsid,
          domain: state.domain,
          did: state.did,
          pdsEndpoint,
        };
        const url = buildXrpcUrl(pdsEndpoint, state.did, state.nsid);
        return [next, {
          type: "fetchRecord",
          endpoint: url,
          did: state.did,
          nsid: state.nsid,
        }];
      }
      return [
        { status: "failed", error: result.error },
        { type: "done" },
      ];
    }

    case "didFailed":
      return [
        {
          status: "failed",
          error: {
            type: "DidResolutionFailed",
            did: state.did,
            reason: msg.reason,
          },
        },
        { type: "done" },
      ];

    // Stale messages — re-emit the expected command.
    case "dnsSuccess":
    case "dnsFailed":
    case "recordSuccess":
    case "recordFailed":
      return [state, { type: "resolveDid", did: state.did }];

    default:
      return assertNever(msg);
  }
}

/**
 * Reduce the `recordPending` state with the given message.
 *
 * T16 — `recordSuccess` with matching NSID → `resolved`.
 * T17 — `recordSuccess` with mismatched NSID → `failed` (verification failure).
 * T18 — `recordFailed` → `failed`.
 * T19–T22 — Any other (stale) message → re-emit `fetchRecord` for retry.
 */
function reduceRecordPending(
  state: RecordPendingState,
  msg: ResolverMsg,
): [ResolverState, ResolverCmd] {
  // Pre-compute — used in error path and stale-message retries.
  const xrpcUrl = buildXrpcUrl(state.pdsEndpoint, state.did, state.nsid);

  switch (msg.type) {
    case "recordSuccess": {
      const result = verifyRecord(msg.lexicon, state.nsid);
      if (result.ok) {
        const next: ResolvedState = {
          status: "resolved",
          lexicon: result.value,
          nsid: state.nsid,
        };
        return [next, { type: "done" }];
      }
      return [
        { status: "failed", error: result.error },
        { type: "done" },
      ];
    }

    case "recordFailed":
      return [
        {
          status: "failed",
          error: {
            type: "RecordFetchFailed",
            endpoint: xrpcUrl,
            reason: msg.reason,
          },
        },
        { type: "done" },
      ];

    // Stale messages — re-emit the expected command.
    case "dnsSuccess":
    case "dnsFailed":
    case "didSuccess":
    case "didFailed":
      return [
        state,
        {
          type: "fetchRecord",
          endpoint: xrpcUrl,
          did: state.did,
          nsid: state.nsid,
        },
      ];

    default:
      return assertNever(msg);
  }
}
