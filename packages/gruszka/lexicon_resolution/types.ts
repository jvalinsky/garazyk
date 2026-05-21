/**
 * Sans-IO lexicon resolution — layer 0: data types.
 *
 * Defines branded primitives, the discriminated error union, a general-purpose
 * {@link Result} type, and the state-machine types ({@link ResolverState},
 * {@link ResolverMsg}, {@link ResolverCmd}) used by the sans-IO resolver.
 *
 * No I/O, no platform dependencies — importable by tests, adapters, and the
 * resolver core without pulling in Deno or browser APIs.
 *
 * @module lexicon_resolution
 */

// ---------------------------------------------------------------------------
// Branded primitives
// ---------------------------------------------------------------------------

/** Brand tag for NSID strings (e.g. `com.atproto.repo.createRecord`). */
declare const nsidBrand: unique symbol;
/** Brand tag for DID strings (e.g. `did:plc:ewvi7nxzyoun6zhxrhs64oiz`). */
declare const didBrand: unique symbol;
/** Brand tag for DNS domain strings (e.g. `bsky.app`). */
declare const domainBrand: unique symbol;

/**
 * AT Protocol NSID — a reverse-DNS identifier for a lexicon method or record.
 *
 * Examples: `com.atproto.repo.createRecord`, `app.bsky.feed.post`.
 */
export type Nsid = string & { readonly [nsidBrand]: true };

/**
 * AT Protocol decentralized identifier.
 *
 * Examples: `did:plc:ewvi7nxzyoun6zhxrhs64oiz`, `did:web:bsky.app`.
 */
export type Did = string & { readonly [didBrand]: true };

/**
 * DNS domain name derived from an NSID authority segment.
 *
 * The domain is the reversed dot-separated authority of an NSID. For example,
 * the NSID `app.bsky.feed.post` has authority `app.bsky.feed`, which reverses
 * to the domain `feed.bsky.app`.
 */
export type Domain = string & { readonly [domainBrand]: true };

/**
 * Validate that a string conforms to NSID syntax.
 *
 * An NSID must:
 * - Contain only lowercase letters, digits, and dots
 * - Have at least three dot-separated segments (authority + name)
 * - Start and end with a letter or digit
 * - Not contain consecutive dots
 *
 * @param s - The candidate string.
 * @returns `true` if the string is a valid NSID.
 */
export function isValidNsid(s: string): boolean {
  if (s.length === 0) return false;
  // Must contain only letters, digits, dots (AT Protocol NSIDs use camelCase).
  if (!/^[a-zA-Z0-9.]+$/.test(s)) return false;
  // Must not start or end with a dot, and must not contain consecutive dots.
  if (s.startsWith(".") || s.endsWith(".") || s.includes("..")) return false;
  // Must have at least three dot-separated segments.
  const segments = s.split(".");
  return segments.length >= 3;
}

/**
 * Brand a string as a validated {@link Nsid}.
 *
 * @param s - A string that passes {@link isValidNsid}.
 * @returns The branded NSID.
 * @throws {TypeError} If the string is not a valid NSID.
 */
export function asNsid(s: string): Nsid {
  if (!isValidNsid(s)) {
    throw new TypeError(`Invalid NSID: ${JSON.stringify(s)}`);
  }
  return s as Nsid;
}

/**
 * Brand a string as a {@link Did}.
 *
 * Performs basic structural validation (must start with `did:` and have a
 * non-empty method segment). For full DID resolution, use the DID resolver
 * port.
 *
 * @param s - A string of the form `did:<method>:<id>`.
 * @returns The branded DID.
 * @throws {TypeError} If the string is not a valid DID.
 */
export function asDid(s: string): Did {
  // DID format: did:<method>:<id> where id is non-empty.
  if (!s.startsWith("did:") || s.length < 6) {
    throw new TypeError(`Invalid DID: ${JSON.stringify(s)}`);
  }
  const secondColon = s.indexOf(":", 4);
  // No second colon, or it is the last character (empty id).
  if (secondColon === -1 || secondColon === s.length - 1) {
    throw new TypeError(`Invalid DID: ${JSON.stringify(s)}`);
  }
  return s as Did;
}

/**
 * Brand a string as a {@link Domain}.
 *
 * Trims leading/trailing whitespace but performs no DNS-level validation.
 * The DNS resolver port is responsible for actual lookup.
 *
 * @param s - A domain string (e.g. `bsky.app`).
 * @returns The branded domain.
 * @throws {TypeError} If the string is empty after trimming.
 */
export function asDomain(s: string): Domain {
  const trimmed = s.trim();
  if (trimmed.length === 0) {
    throw new TypeError("Domain must not be empty");
  }
  return trimmed as Domain;
}

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

/**
 * Discriminated result type for fallible operations.
 *
 * Prefer this over throwing in sans-IO code — it makes error paths explicit
 * and forces callers to handle both branches.
 *
 * @typeParam T - The success value type.
 * @typeParam E - The error type (defaults to {@link ResolutionError}).
 *
 * @example
 * ```ts
 * function divide(a: number, b: number): Result<number, string> {
 *   if (b === 0) return { ok: false, error: "division by zero" };
 *   return { ok: true, value: a / b };
 * }
 * ```
 */
export type Result<T, E = ResolutionError> =
  | { ok: true; value: T }
  | { ok: false; error: E };

// ---------------------------------------------------------------------------
// Resolution error union
// ---------------------------------------------------------------------------

/**
 * Discriminated union of all errors that can occur during lexicon resolution.
 *
 * Each variant carries enough context for the caller to produce a useful
 * diagnostic message without inspecting nested error chains.
 */
export type ResolutionError =
  | { type: "InvalidNsid"; nsid: string }
  | { type: "DnsQueryFailed"; domain: Domain; reason: string }
  | { type: "NoLexiconDnsRecord"; domain: Domain }
  | { type: "DidResolutionFailed"; did: Did; reason: string }
  | { type: "PdsEndpointMissing"; did: Did }
  | { type: "RecordFetchFailed"; endpoint: string; reason: string }
  | { type: "RecordVerificationFailed"; nsid: Nsid; reason: string };

// ---------------------------------------------------------------------------
// Lexicon document
// ---------------------------------------------------------------------------

/**
 * A single AT Protocol lexicon JSON document.
 *
 * This is the shape of each `.json` file in the canonical lexicon repository
 * (e.g. `com/atproto/repo/createRecord.json`). It contains one or more named
 * definitions, with `main` being the primary operation definition.
 *
 * Only the fields consumed during resolution and code generation are typed
 * here; additional fields may be present in the actual JSON.
 */
export interface LexiconDoc {
  /** Lexicon schema version (always `1` in practice). */
  lexicon: number;
  /** Fully qualified NSID of this lexicon. */
  id: string;
  /** Revision number, incremented on each schema change. */
  revision?: number;
  /** Human-readable description of the lexicon's purpose. */
  description?: string;
  /** Named schema definitions, keyed by definition name. */
  defs: Record<string, LexiconDef>;
}

/**
 * A single named definition within a {@link LexiconDoc}.
 *
 * The `main` definition is the primary operation (query, procedure, or
 * record); other definitions are referenced via `#defName` refs.
 */
export interface LexiconDef {
  /** Definition type — `query`, `procedure`, `record`, `token`, or `subscription`. */
  type: "query" | "procedure" | "record" | "token" | "subscription";
  /** Human-readable description. */
  description?: string;
  /** Query parameters (only for `query` type). */
  parameters?: LexiconParams;
  /** Input body schema and encoding. */
  input?: LexiconBody;
  /** Output body schema and encoding. */
  output?: LexiconBody;
  /** Record schema (only for `record` type). */
  record?: LexiconSchema;
}

/** Parameter definition block within a query lexicon. */
export interface LexiconParams {
  type?: "params";
  required?: string[];
  properties?: Record<string, LexiconSchema>;
}

/** Input or output body descriptor. */
export interface LexiconBody {
  /** Content encoding. `application/json` is the default; binary encodings
   *  include `*`/`*`, `video/mp4`, `application/vnd.ipld.car`, etc. */
  encoding?: string;
  /** JSON schema for the body shape. */
  schema?: LexiconSchema;
}

/** A single schema node within a lexicon definition. */
export interface LexiconSchema {
  type?: string;
  ref?: string;
  refs?: string[];
  closed?: boolean;
  properties?: Record<string, LexiconSchema>;
  required?: string[];
  items?: LexiconSchema;
  description?: string;
  minimum?: number;
  maximum?: number;
  enum?: string[];
  const?: unknown;
  default?: unknown;
  minLength?: number;
  maxLength?: number;
  format?: string;
  /** Allow additional properties not explicitly listed in this schema. */
  [key: string]: unknown;
}

// ---------------------------------------------------------------------------
// DID document (subset consumed during resolution)
// ---------------------------------------------------------------------------

/**
 * Subset of a W3C DID document consumed during lexicon resolution.
 *
 * We only need the `service` entries to locate the AT Protocol PDS endpoint
 * hosting the lexicon repository. The full DID document contains additional
 * fields (verification methods, authentication, etc.) that are ignored here.
 */
export interface DidDocument {
  /** DID that this document describes. */
  id: string;
  /** DID context (always `["https://www.w3.org/ns/did/v1"]`). */
  "@context"?: unknown;
  /** Service endpoints advertised by the DID subject. */
  service?: Array<{
    /** Service identifier fragment (e.g. `#atproto_pds`). */
    id: string;
    /** Service type (e.g. `AtprotoPersonalDataServer`). */
    type: string;
    /** Service endpoint URL. */
    serviceEndpoint: string | Record<string, string>;
  }>;
}

// ---------------------------------------------------------------------------
// Resolver state machine
// ---------------------------------------------------------------------------

/**
 * Root state type for the sans-IO lexicon resolver.
 *
 * The resolver begins by calling {@link init} with an NSID string, which
 * returns an initial `[ResolverState, ResolverCmd]` pair. The caller feeds
 * messages back via {@link update} until the state reaches `resolved` or
 * `failed`.
 */
export type ResolverState =
  | InitState
  | DnsPendingState
  | DidPendingState
  | RecordPendingState
  | ResolvedState
  | FailedState;

/** Initial state — the resolver has not yet been started. */
export interface InitState {
  /** State discriminator. */
  status: "init";
}

/** Awaiting DNS TXT record lookup for the `_lexicon.<domain>` query. */
export interface DnsPendingState {
  /** State discriminator. */
  status: "dnsPending";
  /** The NSID being resolved. */
  nsid: Nsid;
  /** The DNS domain derived from the NSID authority. */
  domain: Domain;
}

/** DNS resolved successfully; awaiting DID document resolution to locate the PDS. */
export interface DidPendingState {
  /** State discriminator. */
  status: "didPending";
  /** The NSID being resolved. */
  nsid: Nsid;
  /** The DNS domain used for the lookup. */
  domain: Domain;
  /** The DID extracted from the DNS TXT record. */
  did: Did;
}

/** DID resolved; awaiting lexicon record fetch from the PDS. */
export interface RecordPendingState {
  /** State discriminator. */
  status: "recordPending";
  /** The NSID being resolved. */
  nsid: Nsid;
  /** The DNS domain used for the lookup. */
  domain: Domain;
  /** The DID that owns the lexicon namespace. */
  did: Did;
  /** The PDS endpoint URL used to fetch the lexicon record. */
  pdsEndpoint: string;
}

/** Lexicon successfully resolved and (if verification is enabled) verified. */
export interface ResolvedState {
  /** State discriminator. */
  status: "resolved";
  /** The resolved lexicon document. */
  lexicon: LexiconDoc;
  /** The NSID that was resolved. */
  nsid: Nsid;
}

/** Resolution failed with a terminal error. */
export interface FailedState {
  /** State discriminator. */
  status: "failed";
  /** The error that caused resolution to fail. */
  error: ResolutionError;
}

// ---------------------------------------------------------------------------
// Resolver messages
// ---------------------------------------------------------------------------

/**
 * Discriminated union of all messages the resolver can receive.
 *
 * Messages are produced by the IO adapters in response to commands. The
 * caller feeds them into {@link update} to advance the state machine.
 */
export type ResolverMsg =
  | DnsSuccessMsg
  | DnsFailedMsg
  | DidSuccessMsg
  | DidFailedMsg
  | RecordSuccessMsg
  | RecordFailedMsg;

/** DNS TXT lookup succeeded. */
export interface DnsSuccessMsg {
  /** Message discriminator. */
  type: "dnsSuccess";
  /**
   * Raw DNS TXT record strings for the `_lexicon.<domain>` query.
   *
   * Each entry in the outer array is one DNS response; the inner array
   * contains the character-string values for that record.
   */
  records: string[][];
}

/** DNS TXT lookup failed. */
export interface DnsFailedMsg {
  /** Message discriminator. */
  type: "dnsFailed";
  /** Error reason from the DNS resolver. */
  reason: string;
}

/** DID document resolution succeeded. */
export interface DidSuccessMsg {
  /** Message discriminator. */
  type: "didSuccess";
  /** The resolved DID document. */
  document: DidDocument;
}

/** DID document resolution failed. */
export interface DidFailedMsg {
  /** Message discriminator. */
  type: "didFailed";
  /** Error reason from the DID resolver. */
  reason: string;
}

/** Lexicon record fetch succeeded. */
export interface RecordSuccessMsg {
  /** Message discriminator. */
  type: "recordSuccess";
  /** The fetched lexicon document. */
  lexicon: LexiconDoc;
}

/** Lexicon record fetch failed. */
export interface RecordFailedMsg {
  /** Message discriminator. */
  type: "recordFailed";
  /** Error reason from the record fetcher. */
  reason: string;
}

// ---------------------------------------------------------------------------
// Resolver commands
// ---------------------------------------------------------------------------

/**
 * Discriminated union of all effects the resolver can emit.
 *
 * Commands are data (not functions) — the caller's runtime interprets them
 * into actual I/O. This is the Elm Architecture pattern: the state machine
 * is pure, and all side effects are deferred.
 */
export type ResolverCmd =
  | ResolveDnsCmd
  | ResolveDidCmd
  | FetchRecordCmd
  | DoneCmd;

/** Resolve DNS TXT records for `_lexicon.<domain>`. */
export interface ResolveDnsCmd {
  /** Command discriminator. */
  type: "resolveDns";
  /** The domain to query. */
  domain: Domain;
}

/** Resolve a DID to its DID document. */
export interface ResolveDidCmd {
  /** Command discriminator. */
  type: "resolveDid";
  /** The DID to resolve. */
  did: Did;
}

/** Fetch a lexicon record from a PDS endpoint. */
export interface FetchRecordCmd {
  /** Command discriminator. */
  type: "fetchRecord";
  /** The AT Protocol repository endpoint hosting the lexicon record. */
  endpoint: string;
  /** The DID that owns the lexicon namespace. */
  did: Did;
  /** The NSID being resolved. */
  nsid: Nsid;
}

/** Terminal command — no further I/O is needed. */
export interface DoneCmd {
  /** Command discriminator. */
  type: "done";
}

// ---------------------------------------------------------------------------
// Utility types
// ---------------------------------------------------------------------------

/**
 * Exhaustiveness check for `switch` statements over discriminated unions.
 *
 * Call this in the `default` branch of a `switch` to get a compile-time error
 * when a new variant is added to the union but not handled. At runtime, it
 * throws if somehow an unexpected value reaches it.
 *
 * @param x - The value that should be of type `never`.
 * @throws {TypeError} If reached at runtime with a non-`never` value.
 *
 * @example
 * ```ts
 * switch (state.status) {
 *   case "dnsPending":  return handleDns(state);
 *   case "didPending":  return handleDid(state);
 *   // ...
 *   default: return assertNever(state);
 * }
 * ```
 */
export function assertNever(x: never): never {
  throw new TypeError(`Unexpected value: ${JSON.stringify(x)}`);
}
