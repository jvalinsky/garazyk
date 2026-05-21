/**
 * Sans-IO lexicon resolution — layer 4: orchestration.
 *
 * Wires the pure {@link init}/{@link update} state machine together with
 * the IO port adapters into an async pipeline.  The public API is a single
 * function, {@link resolveLexicon}, that takes an NSID string and a set
 * of port implementations and returns a fully resolved {@link LexiconDoc}
 * (or a {@link ResolutionError}).
 *
 * No I/O in this file — all side effects are delegated to the ports.
 *
 * @module lexicon_resolution
 */

import type {
  DidDocument,
  LexiconDoc,
  ResolutionError,
  ResolverCmd,
  ResolverMsg,
  Result,
} from "./types.ts";

import { assertNever } from "./types.ts";

import type { DnsResolver, DidResolver, RecordFetcher } from "./ports.ts";

import type { KeyValueCache } from "./cache.ts";
import {
  CachingDnsResolver,
  CachingDidResolver,
  CachingRecordFetcher,
} from "./cache.ts";

import { init, update } from "./resolver.ts";

// ---------------------------------------------------------------------------
// Resolution ports (dependency injection)
// ---------------------------------------------------------------------------

/**
 * The three I/O capability interfaces needed by the resolver runtime.
 *
 * Pass concrete implementations (like {@link DenoDnsResolver},
 * {@link HttpDidResolver}, and {@link HttpRecordFetcher}) in production,
 * or stubs in tests.
 */
export interface ResolutionPorts {
  /** DNS TXT record resolver. */
  dns: DnsResolver;
  /** DID document resolver. */
  did: DidResolver;
  /** Lexicon record fetcher. */
  record: RecordFetcher;
  /**
   * Optional per-port cache configuration.
   *
   * When a cache is provided for a port, {@link resolveLexicon} automatically
   * wraps the port implementation with the corresponding caching wrapper
   * ({@link CachingDnsResolver}, {@link CachingDidResolver},
   * {@link CachingRecordFetcher}).  Cache misses delegate to the inner port
   * and populate the cache on success; errors are never cached.
   *
   * Each cache is independent — you can enable caching for DNS only, for all
   * three, or for any combination.
   *
   * @example
   * ```ts
   * import { InMemoryCache, DiskCache } from "./cache.ts";
   *
   * const ports = {
   *   dns: new DenoDnsResolver(),
   *   did: new HttpDidResolver(),
   *   record: new HttpRecordFetcher(),
   *   cache: {
   *     dns: new InMemoryCache<string[][]>({ ttlMs: 3600_000 }),
   *     did: new DiskCache<DidDocument>({ directory: "/tmp/did-cache" }),
   *     record: new InMemoryCache<LexiconDoc>({ ttlMs: 86_400_000 }),
   *   },
   * };
   * ```
   */
  cache?: {
    /** Cache for DNS TXT record lookups (domain → records). */
    dns?: KeyValueCache<string[][]>;
    /** Cache for DID document resolution (did → document). */
    did?: KeyValueCache<DidDocument>;
    /** Cache for lexicon record fetches (endpoint → lexicon doc). */
    record?: KeyValueCache<LexiconDoc>;
  };
}

// ---------------------------------------------------------------------------
// Runtime
// ---------------------------------------------------------------------------

/**
 * Wrap port implementations with caching layers when caches are configured.
 *
 * Returns a new {@link ResolutionPorts} value where any port with a
 * corresponding cache in `ports.cache` is wrapped with the appropriate
 * `Caching*` decorator.  Ports without caches are passed through unchanged.
 *
 * @param ports - The original (possibly uncached) port set.
 * @returns The effective port set with caching applied where configured.
 */
function applyCaches(ports: ResolutionPorts): ResolutionPorts {
  const { cache } = ports;
  if (!cache) return ports;

  return {
    dns: cache.dns
      ? new CachingDnsResolver(ports.dns, cache.dns)
      : ports.dns,
    did: cache.did
      ? new CachingDidResolver(ports.did, cache.did)
      : ports.did,
    record: cache.record
      ? new CachingRecordFetcher(ports.record, cache.record)
      : ports.record,
  };
}

/**
 * Resolve an AT Protocol lexicon from the network.
 *
 * This is the top-level entry point — it bootstraps the sans-IO state
 * machine and drives it through the DNS → DID → record fetch pipeline
 * using the provided port implementations.
 *
 * The function returns a {@link LexiconDoc} on success (which can be
 * passed directly to a code generator) or a {@link ResolutionError} on
 * failure (which carries enough context for a useful diagnostic).
 *
 * @param nsid - The NSID of the lexicon to resolve (e.g. `app.bsky.feed.post`).
 * @param ports - The I/O port implementations to use for network access.
 * @returns On success: the resolved lexicon document. On failure: a
 *          {@link ResolutionError} describing what went wrong.
 *
 * @example
 * ```ts
 * import { DenoDnsResolver, HttpDidResolver, HttpRecordFetcher } from "./adapters.ts";
 * import { resolveLexicon } from "./mod.ts";
 *
 * const ports = {
 *   dns: new DenoDnsResolver(),
 *   did: new HttpDidResolver(),
 *   record: new HttpRecordFetcher(),
 * };
 *
 * const result = await resolveLexicon("app.bsky.feed.post", ports);
 * if (result.ok) {
 *   console.log("Resolved:", result.value.id);
 * } else {
 *   console.error("Failed:", result.error);
 * }
 * ```
 */
export async function resolveLexicon(
  nsid: string,
  ports: ResolutionPorts,
): Promise<Result<LexiconDoc, ResolutionError>> {
  // Wrap ports with caching wrappers if caches are provided.
  const effectivePorts = applyCaches(ports);

  // Bootstrap the state machine.
  let [state, cmd] = init(nsid);

  // Drive the loop.
  while (true) {
    const msg = await executeCommand(cmd, effectivePorts);
    if (!msg) break; // Terminal command — no message to feed.
    [state, cmd] = update(state, msg);
  }

  // Interpret the terminal state.
  switch (state.status) {
    case "resolved":
      return { ok: true, value: state.lexicon };
    case "failed":
      return { ok: false, error: state.error };
    default:
      // The loop can only exit on a `done` command, which only `update`
      // emits from terminal states (`resolved` or `failed`).  Any other
      // state here is a logic error in the state machine.
      throw new TypeError(
        `Unexpected terminal state: ${JSON.stringify(state.status)}`,
      );
  }
}

// ---------------------------------------------------------------------------
// Command → Msg interpreter
// ---------------------------------------------------------------------------

/**
 * Execute a single command against the port implementations.
 *
 * Maps each {@link ResolverCmd} variant to the corresponding port call,
 * converts the port's {@link Result} into the appropriate
 * {@link ResolverMsg} variant, and returns it for the state machine to
 * consume.
 *
 * If the command is `done` (terminal), returns `null` to signal the
 * run loop to exit.
 *
 * @param cmd - The command to execute.
 * @param ports - The port implementations.
 * @returns The message to feed to {@link update}, or `null` if the
 *          command is terminal.
 */
async function executeCommand(
  cmd: ResolverCmd,
  ports: ResolutionPorts,
): Promise<ResolverMsg | null> {
  switch (cmd.type) {
    case "resolveDns": {
      const result = await ports.dns.resolveTxt(cmd.domain);
      return result.ok
        ? { type: "dnsSuccess", records: result.value }
        : { type: "dnsFailed", reason: result.error };
    }

    case "resolveDid": {
      const result = await ports.did.resolve(cmd.did);
      return result.ok
        ? { type: "didSuccess", document: result.value }
        : { type: "didFailed", reason: result.error };
    }

    case "fetchRecord": {
      const result = await ports.record.fetch(cmd.endpoint);
      return result.ok
        ? { type: "recordSuccess", lexicon: result.value }
        : { type: "recordFailed", reason: result.error };
    }

    case "done":
      return null;

    default:
      return assertNever(cmd);
  }
}
