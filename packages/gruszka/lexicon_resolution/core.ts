/**
 * Sans-IO lexicon resolution — layer 1: pure transformation functions.
 *
 * Every function in this module is a deterministic, synchronous, zero-I/O
 * transformation from a plain input to a {@link Result} (or a plain value).
 * Importable by tests, the resolver state machine, and adapters without
 * pulling in Deno, Node, or browser APIs.
 *
 * @module lexicon_resolution
 */

import {
  asDid,
  asDomain,
  type Did,
  type DidDocument,
  type Domain,
  type LexiconDoc,
  type Nsid,
  type ResolutionError,
  type Result,
} from "./types.ts";

// ---------------------------------------------------------------------------
// parseNsid
// ---------------------------------------------------------------------------

/** Success payload returned by {@link parseNsid}. */
export interface ParsedNsid {
  /**
   * The authority segment — all dot-separated components except the final
   * name. This is the namespace owner.
   *
   * @example `app.bsky.feed` (from `app.bsky.feed.post`)
   */
  authority: string;
  /**
   * The name segment — the final dot-separated component. This is the
   * specific operation or record within the authority's namespace.
   *
   * @example `post` (from `app.bsky.feed.post`)
   */
  name: string;
}

/**
 * Split an NSID into its authority and name components.
 *
 * Every NSID has the form `<authority>.<name>` where the authority is all
 * dot-separated segments except the last, and the name is the final segment.
 * For example, `com.atproto.repo.createRecord` splits into authority
 * `com.atproto.repo` and name `createRecord`.
 *
 * The NSID must already be validated (via {@link isValidNsid}) — this
 * function assumes valid input and does not re-validate.
 *
 * @param nsid - A validated AT Protocol NSID.
 * @returns `{ ok: true, value: ParsedNsid }` with the split components.
 *
 * @example
 * ```ts
 * const nsid = asNsid("app.bsky.feed.post");
 * const result = parseNsid(nsid);
 * // result.value.authority === "app.bsky.feed"
 * // result.value.name === "post"
 * ```
 */
export function parseNsid(nsid: Nsid): Result<ParsedNsid> {
  const lastDot = nsid.lastIndexOf(".");
  // An NSID always has at least two dots (three segments), so lastDot >= 0.
  if (lastDot < 0) {
    return {
      ok: false,
      error: { type: "InvalidNsid", nsid },
    };
  }
  return {
    ok: true,
    value: {
      authority: nsid.slice(0, lastDot),
      name: nsid.slice(lastDot + 1),
    },
  };
}

// ---------------------------------------------------------------------------
// deriveDnsDomain
// ---------------------------------------------------------------------------

/**
 * Derive the DNS domain from an NSID authority by reversing its segments.
 *
 * The authority (everything except the final name segment) is reversed
 * dot-by-dot to form a DNS domain. This domain is then queried for the
 * `_lexicon` TXT record to discover the DID that owns the namespace.
 *
 * @param authority - The authority portion of an NSID (e.g. `app.bsky.feed`).
 * @returns The reversed DNS domain (e.g. `feed.bsky.app`).
 *
 * @example
 * ```ts
 * deriveDnsDomain("app.bsky.feed")      // → "feed.bsky.app" (as Domain)
 * deriveDnsDomain("com.atproto.repo")   // → "repo.atproto.com" (as Domain)
 * ```
 */
export function deriveDnsDomain(authority: string): Domain {
  const reversed = authority.split(".").reverse().join(".");
  return asDomain(reversed);
}

// ---------------------------------------------------------------------------
// parseDnsTxtRecords
// ---------------------------------------------------------------------------

/**
 * Extract a DID from DNS TXT records returned by a `_lexicon.<domain>` query.
 *
 * Each outer-array entry is one DNS TXT record; the inner array contains
 * the character-string values for that record. The resolver concatenates
 * all strings in each record (DNS TXT records can be split across multiple
 * character strings) and looks for a `did=<value>` key-value pair.
 *
 * Only the first `did=` value found is returned. Optional whitespace between
 * `did=` and the value is consumed. The value itself must be a contiguous
 * non-whitespace token.
 *
 * @param records - DNS TXT response records (e.g. `[["did=did:plc:test"]]`).
 * @param domain - The domain being queried (for error diagnostics).
 * @returns `{ ok: true, value: Did }` if a `did=` value was found, or
 *          `{ ok: false, error: NoLexiconDnsRecord }` if not.
 *
 * @example
 * ```ts
 * parseDnsTxtRecords([["did=did:plc:ewvi7nxzyoun6zhxrhs64oiz"]],
 *                    asDomain("feed.bsky.app"))
 * // → { ok: true, value: "did:plc:ewvi7nxzyoun6zhxrhs64oiz" as Did }
 * ```
 */
export function parseDnsTxtRecords(
  records: string[][],
  domain: Domain,
): Result<Did, ResolutionError> {
  for (const record of records) {
    // Concatenate all character-strings in this record.
    const joined = record.join("");
    // Allow optional whitespace between did= and the value.
    const match = joined.match(/did=\s*([^\s]+)/);
    if (match?.[1]) {
      // asDid validates and trims internally — no need to pre-trim.
      try {
        return { ok: true, value: asDid(match[1]) };
      } catch {
        // Malformed DID value — skip this record and try the next.
        continue;
      }
    }
  }
  return {
    ok: false,
    error: { type: "NoLexiconDnsRecord", domain },
  };
}

// ---------------------------------------------------------------------------
// extractPdsEndpoint
// ---------------------------------------------------------------------------

/**
 * Extract the AT Protocol PDS service endpoint from a DID document.
 *
 * Looks through the `service` array for an entry whose `type` is
 * `AtprotoPersonalDataServer`. Returns the `serviceEndpoint` URL,
 * normalizing object-form endpoints (e.g. `{ "url": "https://..." }`)
 * to a plain string.
 *
 * If multiple PDS services are present the **first** match is returned
 * (this is consistent with how DID resolution picks a PDS).
 *
 * @param document - A resolved DID document.
 * @returns `{ ok: true, value: string }` with the PDS endpoint URL, or
 *          `{ ok: false, error: PdsEndpointMissing }` if no PDS service
 *          was found.
 *
 * @example
 * ```ts
 * const doc: DidDocument = {
 *   id: "did:plc:test",
 *   service: [{
 *     id: "#atproto_pds",
 *     type: "AtprotoPersonalDataServer",
 *     serviceEndpoint: "https://pds.example",
 *   }],
 * };
 * extractPdsEndpoint(doc)
 * // → { ok: true, value: "https://pds.example" }
 * ```
 */
export function extractPdsEndpoint(
  document: DidDocument,
): Result<string, ResolutionError> {
  const services = document.service ?? [];
  for (const svc of services) {
    if (svc.type !== "AtprotoPersonalDataServer") continue;

    // Normalise object-form endpoints (`{ url: "..." }`) to a plain string.
    let endpoint: unknown = svc.serviceEndpoint;
    if (typeof endpoint !== "string") {
      endpoint = (endpoint as Record<string, unknown>).url ?? endpoint;
    }

    if (typeof endpoint === "string" && endpoint.length > 0) {
      return { ok: true, value: endpoint };
    }
  }
  return {
    ok: false,
    error: { type: "PdsEndpointMissing", did: asDid(document.id) },
  };
}

// ---------------------------------------------------------------------------
// buildXrpcUrl
// ---------------------------------------------------------------------------

/**
 * Build the XRPC URL for fetching a lexicon record from a PDS.
 *
 * The URL calls `com.atproto.repo.getRecord` with:
 * - `repo` — the DID that owns the lexicon namespace
 * - `collection` — `com.atproto.lexicon.schema` (the record type for lexicons)
 * - `rkey` — the NSID of the lexicon being resolved
 *
 * Trailing slashes are stripped from the PDS endpoint before the path is
 * appended. Query parameter values are URL-encoded.
 *
 * @param pdsEndpoint - The PDS base URL (e.g. `https://pds.example`).
 * @param did - The DID that hosts the lexicon (e.g. `did:plc:test`).
 * @param nsid - The NSID being resolved (e.g. `app.bsky.feed.post`).
 * @returns The fully constructed XRPC URL.
 *
 * @example
 * ```ts
 * buildXrpcUrl("https://pds.example", asDid("did:plc:test"), asNsid("app.bsky.feed.post"))
 * // → "https://pds.example/xrpc/com.atproto.repo.getRecord?repo=did%3Aplc%3Atest&collection=com.atproto.lexicon.schema&rkey=app.bsky.feed.post"
 * ```
 */
export function buildXrpcUrl(
  pdsEndpoint: string,
  did: Did,
  nsid: Nsid,
): string {
  const base = pdsEndpoint.replace(/\/+$/, "");
  const repo = encodeURIComponent(did);
  const rkey = encodeURIComponent(nsid);
  return `${base}/xrpc/com.atproto.repo.getRecord?repo=${repo}&collection=com.atproto.lexicon.schema&rkey=${rkey}`;
}

// ---------------------------------------------------------------------------
// verifyRecord
// ---------------------------------------------------------------------------

/**
 * Verify that a fetched lexicon document's `id` matches the requested NSID.
 *
 * After fetching a lexicon record from a PDS, the caller must verify that
 * the returned document's `id` field equals the NSID that was requested.
 * This prevents the PDS from serving a different lexicon under a spoofed
 * record key.
 *
 * @param lexicon - The fetched lexicon document.
 * @param nsid - The NSID that was requested.
 * @returns `{ ok: true, value: LexiconDoc }` if the IDs match, or
 *          `{ ok: false, error: RecordVerificationFailed }` if they don't.
 *
 * @example
 * ```ts
 * const lexicon = { lexicon: 1, id: "app.bsky.feed.post", defs: {} };
 * verifyRecord(lexicon, asNsid("app.bsky.feed.post"))
 * // → { ok: true, value: lexicon }
 * ```
 */
export function verifyRecord(
  lexicon: LexiconDoc,
  nsid: Nsid,
): Result<LexiconDoc, ResolutionError> {
  if (lexicon.id === nsid) {
    return { ok: true, value: lexicon };
  }
  return {
    ok: false,
    error: {
      type: "RecordVerificationFailed",
      nsid,
      reason: `Lexicon id "${lexicon.id}" does not match requested NSID "${nsid}"`,
    },
  };
}
